--[[
    Map-scoped quest activity for Set Alert reminders.
    Uses C_TaskQuest / C_QuestLog on the map tree (same quest IDs as the picker), not
    DailyQuestManager category buckets (weekly / assignments / scan.events differ).
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

local M = {}
ns.ReminderMapContent = M

local QUELTHALAS_HUB = 2537

local function IsSecret(val)
    return issecretvalue and val and issecretvalue(val)
end

local function SafeParentUIMapID(mid)
    if not mid or mid <= 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mid)
    if not ok or not info then return nil end
    local p = info.parentMapID
    if p == nil or p == 0 then return nil end
    if IsSecret(p) then return nil end
    p = tonumber(p)
    if not p or p <= 0 then return nil end
    return p
end

--- True if descendant equals ancestor or ancestor is on the parent walk from descendant.
function M.MapIsUnderAncestor(descendantId, ancestorId)
    local target = tonumber(ancestorId)
    local cur = tonumber(descendantId)
    if not target or not cur then return false end
    local guard = 0
    while cur and cur > 0 and guard < 64 do
        guard = guard + 1
        if cur == target then return true end
        cur = SafeParentUIMapID(cur)
    end
    return false
end

--- Collapse player map id (delve alternates only).
local function CollapsePlayerMap(mapID)
    local RCI = ns.ReminderContentIndex
    if RCI and RCI.CollapseAlternateUIMapOnly then
        local cr = RCI.CollapseAlternateUIMapOnly(mapID)
        if cr then return cr end
    end
    return tonumber(mapID)
end

local function MapRelatesToPlayer(questMapID, playerMap)
    questMapID = CollapsePlayerMap(questMapID) or questMapID
    playerMap = CollapsePlayerMap(playerMap) or playerMap
    if not questMapID or not playerMap then return false end
    if questMapID == playerMap then return true end
    return M.MapIsUnderAncestor(playerMap, questMapID) or M.MapIsUnderAncestor(questMapID, playerMap)
end

local function IsWorldQuest(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.IsQuestCalling then
        local okC, isCalling = pcall(C_QuestLog.IsQuestCalling, questID)
        if okC and isCalling then return false end
    end
    if not C_QuestLog or not C_QuestLog.IsWorldQuest then return false end
    local ok, result = pcall(C_QuestLog.IsWorldQuest, questID)
    return ok and result == true
end

local function IsQuestComplete(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, done = pcall(C_QuestLog.IsComplete, questID)
        if ok and done then return true end
    end
    return false
end

---@param mapID number
---@param playerMap number
---@param seen table<number, boolean>
---@param out table<number, boolean>
---@param filterFn function|nil fun(questID: number): boolean
local function CollectQuestIDsOnMap(mapID, playerMap, seen, out, filterFn)
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 then return end

    local function tryAdd(questID, questMapID)
        questID = tonumber(questID)
        if not questID or questID <= 0 or seen[questID] then return end
        if filterFn and not filterFn(questID) then return end
        if IsQuestComplete(questID) then return end
        local qMap = tonumber(questMapID) or mapID
        if not MapRelatesToPlayer(qMap, playerMap) then return end
        seen[questID] = true
        out[questID] = true
    end

    if C_TaskQuest then
        local taskPOIs
        if C_TaskQuest.GetQuestsForPlayerByMapID then
            local ok, result = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
            if ok and type(result) == "table" then taskPOIs = result end
        end
        if not taskPOIs and C_TaskQuest.GetQuestsOnMap then
            local ok, result = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
            if ok and type(result) == "table" then taskPOIs = result end
        end
        if taskPOIs then
            for j = 1, #taskPOIs do
                local qi = taskPOIs[j]
                local qid = qi and (qi.questID or qi.questId)
                if qid == nil or IsSecret(qid) then
                    qid = nil
                end
                if qid then
                    tryAdd(qid, qi.mapID or qi.mapId or mapID)
                end
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, mapQuests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if ok and type(mapQuests) == "table" then
            for _, qi in pairs(mapQuests) do
                local qid = qi and qi.questID
                if qid == nil or IsSecret(qid) then
                    qid = nil
                end
                if qid then
                    tryAdd(qid, qi.mapID or mapID)
                end
            end
        end
    end
end

--- Maps to scan around the player (zone list + Quel'Thalas hub when in a Midnight zone).
---@param playerMap number
---@return number[]
local function GetMapsToScan(playerMap)
    local seen = {}
    local list = {}
    local function add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end

    add(playerMap)

    local INDEX = ns.ReminderWorldQuestIndex
    if INDEX and INDEX.ResolveZoneIndexForMap and INDEX.ZONES then
        local zi = INDEX.ResolveZoneIndexForMap(playerMap)
        if zi and INDEX.ZONES[zi] then
            local z = INDEX.ZONES[zi]
            for mi = 1, #(z.mapIDs or {}) do
                add(z.mapIDs[mi])
            end
            if zi ~= #(INDEX.ZONES) then
                add(QUELTHALAS_HUB)
            end
        end
    end

    return list
end

--- World quests currently up on the map tree (C_QuestLog.IsWorldQuest — matches Set Alert WQ picker).
---@param rawMapID number
---@return table<number, boolean>
function M.GetActiveWorldQuestIDsOnMap(rawMapID)
    local out = {}
    local playerMap = CollapsePlayerMap(rawMapID)
    if not playerMap or playerMap <= 0 then return out end

    local seen = {}
    local maps = GetMapsToScan(playerMap)
    for i = 1, #maps do
        CollectQuestIDsOnMap(maps[i], playerMap, seen, out, IsWorldQuest)
    end
    return out
end

--- Content Events from MidnightQuestCatalog (category events) — not ScanMidnightQuests.events.
---@param rawMapID number
---@param selectedQuestIDs number[]|nil
---@return table<number, boolean>
function M.GetActiveContentEventQuestIDsOnMap(rawMapID, selectedQuestIDs)
    local out = {}
    local playerMap = CollapsePlayerMap(rawMapID)
    if not playerMap or playerMap <= 0 then return out end

    local want = {}
    if selectedQuestIDs and #selectedQuestIDs > 0 then
        for i = 1, #selectedQuestIDs do
            local id = tonumber(selectedQuestIDs[i])
            if id and id > 0 then want[id] = true end
        end
    else
        local RQC = ns.ReminderQuestCatalog
        if RQC and RQC.GetFlatContentEventRows then
            local rows = RQC.GetFlatContentEventRows()
            for i = 1, #rows do
                local id = rows[i] and tonumber(rows[i].questID)
                if id then want[id] = true end
            end
        end
    end
    if not next(want) then return out end

    local function wantsQuest(questID)
        return want[questID] == true
    end

    local seen = {}
    local maps = GetMapsToScan(playerMap)
    for i = 1, #maps do
        CollectQuestIDsOnMap(maps[i], playerMap, seen, out, wantsQuest)
    end
    return out
end

--- Legacy: DailyQuestManager buckets (worldQuests | events). Prefer GetActiveWorldQuestIDsOnMap /
--- GetActiveContentEventQuestIDsOnMap for Set Alert — scan categories diverge from the picker.
---@param rawMapID number
---@param category string "worldQuests" | "events"
---@return table<number, boolean>
function M.GetActiveQuestIDsForCategoryOnMap(rawMapID, category)
    if category == "worldQuests" then
        return M.GetActiveWorldQuestIDsOnMap(rawMapID)
    end
    if category == "events" then
        return M.GetActiveContentEventQuestIDsOnMap(rawMapID, nil)
    end
    return {}
end

--- Match selected quest IDs against active set; empty selection = any active in category on map.
---@param activeSet table<number, boolean>
---@param selectedIDs number[]|nil
---@return boolean
function M.MatchesQuestSelection(activeSet, selectedIDs)
    if not activeSet or not next(activeSet) then return false end
    if not selectedIDs or #selectedIDs == 0 then
        return true
    end
    for i = 1, #selectedIDs do
        local id = tonumber(selectedIDs[i])
        if id and activeSet[id] then return true end
    end
    return false
end
