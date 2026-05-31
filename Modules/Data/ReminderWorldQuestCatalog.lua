--[[
    Maintained Midnight world-quest catalog (shipped static rows + account SavedVariables).
    API map scans only return quests visible right now; this list always shows known WQs in the picker.

    Grow the static ENTRIES table from in-game exports (/wn reminder syncquestcatalog).
]]

local ADDON_NAME, ns = ...

local M = {}
ns.ReminderWorldQuestCatalog = M

--- Bump when static ENTRIES change; MigrationService seeds new rows into db.global.reminderQuestCatalog.
M.CATALOG_VERSION = 6

--- zoneKey must match ReminderWorldQuestIndex zone keys.
M.ZONE_KEYS = {
    "silvermoon",
    "eversong",
    "isle",
    "harandar",
    "zulaman",
    "voidstorm",
    "quelthalas_all",
}

M.ZONE_KEY_BY_INDEX = {
    [1] = "silvermoon",
    [2] = "eversong",
    [3] = "isle",
    [4] = "harandar",
    [5] = "zulaman",
    [6] = "voidstorm",
    [7] = "quelthalas_all",
}

M.ZONE_INDEX_BY_KEY = {
    silvermoon = 1,
    eversong = 2,
    isle = 3,
    harandar = 4,
    zulaman = 5,
    voidstorm = 6,
    quelthalas_all = 7,
}

--- Shipped static rows { zoneKey, questID, title?, mapID? } from ReminderMidnightWorldQuestData.
local function GetShippedEntries()
    local data = ns.ReminderMidnightWorldQuestData
    if data and type(data.ENTRIES) == "table" then
        return data.ENTRIES
    end
    return {}
end

M.ENTRIES = GetShippedEntries()

local function GetDbCatalog()
    local db = ns.WarbandNexus and ns.WarbandNexus.db
    if not db or not db.global then return nil end
    db.global.reminderQuestCatalog = db.global.reminderQuestCatalog or {
        version = 0,
        worldQuests = {},
    }
    return db.global.reminderQuestCatalog
end

function M.GetCatalogVersion()
    local cat = GetDbCatalog()
    return cat and tonumber(cat.version) or 0
end

--- Merge one quest into account catalog.
function M.UpsertWorldQuest(questID, zoneKey, title, mapID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return end
    local cat = GetDbCatalog()
    if not cat or type(cat.worldQuests) ~= "table" then return end
    local row = cat.worldQuests[questID]
    if not row then
        cat.worldQuests[questID] = {
            zoneKey = zoneKey,
            title = title,
            mapID = mapID,
            updatedAt = time(),
        }
    else
        if zoneKey and zoneKey ~= "" then row.zoneKey = zoneKey end
        if title and title ~= "" then row.title = title end
        if mapID then row.mapID = mapID end
        row.updatedAt = time()
    end
end

local function IsQuestCalling(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return false end
    if not C_QuestLog or not C_QuestLog.IsQuestCalling then return false end
    local ok, result = pcall(C_QuestLog.IsQuestCalling, questID)
    return ok and result == true
end

--- Import from ScanMidnightQuests worldQuest rows.
---@param questRows table[]
function M.ImportFromScanRows(questRows)
    if type(questRows) ~= "table" then return end
    local WQ_INDEX = ns.ReminderWorldQuestIndex
    for i = 1, #questRows do
        local q = questRows[i]
        local qid = q and tonumber(q.questID)
        if qid and not IsQuestCalling(qid) then
            local zoneKey
            local EMD = ns.ReminderMidnightFactionEmissaryData
            if EMD and EMD.GetZoneKeyForQuest then
                zoneKey = EMD.GetZoneKeyForQuest(qid)
            end
            if not zoneKey and WQ_INDEX and WQ_INDEX.ResolveZoneIndexForMap and q.mapID then
                local zi = WQ_INDEX.ResolveZoneIndexForMap(q.mapID)
                zoneKey = zi and M.ZONE_KEY_BY_INDEX[zi]
            end
            if zoneKey and zoneKey ~= "" then
                M.UpsertWorldQuest(qid, zoneKey, q.title, q.mapID)
            else
                M.UpsertWorldQuest(qid, nil, q.title, q.mapID)
            end
        end
    end
end

--- Drop emissary/calling rows and fix zoneKey from map pins after zone-matching fixes.
function M.ReconcileSavedWorldQuestZones()
    local cat = GetDbCatalog()
    if not cat or type(cat.worldQuests) ~= "table" then return end
    local WQ_INDEX = ns.ReminderWorldQuestIndex
    local staticZone = {}
    for i = 1, #M.ENTRIES do
        local e = M.ENTRIES[i]
        if e and e.questID and e.zoneKey then
            staticZone[e.questID] = e.zoneKey
        end
    end
    local EMD = ns.ReminderMidnightFactionEmissaryData
    if EMD and EMD.ENTRIES then
        for i = 1, #EMD.ENTRIES do
            local e = EMD.ENTRIES[i]
            if e and e.questID and e.zoneKey then
                staticZone[e.questID] = e.zoneKey
            end
        end
    end
    for qid, meta in pairs(cat.worldQuests) do
        local id = tonumber(qid)
        if id and meta then
            if IsQuestCalling(id) then
                cat.worldQuests[qid] = nil
            else
                local zk = staticZone[id]
                if zk then
                    meta.zoneKey = zk
                elseif WQ_INDEX and WQ_INDEX.ResolveZoneIndexForMap and meta.mapID then
                    local zi = WQ_INDEX.ResolveZoneIndexForMap(meta.mapID)
                    local resolved = zi and M.ZONE_KEY_BY_INDEX[zi]
                    if resolved and resolved ~= "" then
                        meta.zoneKey = resolved
                    end
                end
            end
        end
    end
end

function M.SeedStaticIntoDatabase()
    local cat = GetDbCatalog()
    if not cat then return end
    for i = 1, #M.ENTRIES do
        local e = M.ENTRIES[i]
        if e and e.questID then
            M.UpsertWorldQuest(e.questID, e.zoneKey, e.title, e.mapID)
        end
    end
    local EMD = ns.ReminderMidnightFactionEmissaryData
    if EMD and EMD.ENTRIES then
        for i = 1, #EMD.ENTRIES do
            local e = EMD.ENTRIES[i]
            if e and e.questID then
                M.UpsertWorldQuest(e.questID, e.zoneKey, e.title, e.mapID)
            end
        end
    end
    M.ReconcileSavedWorldQuestZones()
    cat.version = M.CATALOG_VERSION
end

---@param zoneKey string
---@return table[] { questID, title?, mapID?, zoneKey, source }
function M.GetMaintainedRowsForZoneKey(zoneKey)
    local out = {}
    local seen = {}
    if not zoneKey then return out end

    for i = 1, #M.ENTRIES do
        local e = M.ENTRIES[i]
        if e and e.zoneKey == zoneKey and e.questID and not seen[e.questID] then
            seen[e.questID] = true
            out[#out + 1] = {
                questID = e.questID,
                title = e.title,
                mapID = e.mapID,
                zoneKey = zoneKey,
                source = "static",
            }
        end
    end

    local cat = GetDbCatalog()
    if cat and type(cat.worldQuests) == "table" then
        for qid, meta in pairs(cat.worldQuests) do
            local id = tonumber(qid)
            if id and not seen[id] and meta then
                local zk = meta.zoneKey
                local include = (zk == zoneKey)
                if not include and zoneKey == "quelthalas_all" and zk and zk ~= "" then
                    include = true
                end
                if not include and zoneKey == "quelthalas_all" and not zk then
                    include = true
                end
                if include and zoneKey ~= "quelthalas_all" then
                    if IsQuestCalling(id) then
                        include = false
                    else
                        local WQ_INDEX = ns.ReminderWorldQuestIndex
                        local expectZi = M.ZONE_INDEX_BY_KEY[zoneKey]
                        local zi
                        if expectZi and WQ_INDEX then
                            if meta.mapID and WQ_INDEX.ResolveZoneIndexForMap then
                                zi = WQ_INDEX.ResolveZoneIndexForMap(meta.mapID)
                            end
                            if (not zi or zi == 7) and meta.title and WQ_INDEX.ResolveZoneIndexFromEmissaryTitle then
                                zi = WQ_INDEX.ResolveZoneIndexFromEmissaryTitle(meta.title)
                            end
                            if zi and zi ~= expectZi then
                                include = false
                            elseif zk and zk ~= zoneKey then
                                include = false
                            end
                        elseif zk and zk ~= zoneKey then
                            include = false
                        end
                    end
                end
                if include then
                    seen[id] = true
                    out[#out + 1] = {
                        questID = id,
                        title = meta.title,
                        mapID = meta.mapID,
                        zoneKey = zk or zoneKey,
                        source = "saved",
                    }
                end
            end
        end
    end

    return out
end

function M.GetZoneKeyForIndex(zoneIndex)
    return M.ZONE_KEY_BY_INDEX[zoneIndex]
end

--- All maintained world quests (static + SavedVariables), deduped.
---@return table[] { questID, title?, mapID?, zoneKey, source }
function M.GetAllMaintainedRows()
    local out = {}
    local seen = {}
    for zi = 1, #M.ZONE_KEYS do
        local rows = M.GetMaintainedRowsForZoneKey(M.ZONE_KEYS[zi])
        for i = 1, #rows do
            local e = rows[i]
            local qid = e and tonumber(e.questID)
            if qid and not seen[qid] then
                seen[qid] = true
                out[#out + 1] = e
            end
        end
    end
    return out
end
