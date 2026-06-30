--[[
    Midnight world-quest picker index: per-zone map scan (C_TaskQuest + C_QuestLog) plus optional static seeds.
    Used by ReminderQuestCatalog for the Set Alert quest list (complete catalog, not only active tasks).
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

local INDEX = {}
ns.ReminderWorldQuestIndex = INDEX

local QUELTHALAS_MAP = 2537
local QUELTHALAS_ALL_INDEX = 7

---@type { localeKey: string, defaultLabel: string, zoneName: string, mapIDs: number[] }[]
INDEX.ZONES = {
    { localeKey = "REMINDER_WQ_CAT_SILVERMOON",  defaultLabel = "Silvermoon",           zoneName = "Silvermoon",       mapIDs = { 2393 } },
    { localeKey = "REMINDER_WQ_CAT_EVERSONG",    defaultLabel = "Eversong Woods",       zoneName = "Eversong Woods",   mapIDs = { 2395 } },
    { localeKey = "REMINDER_WQ_CAT_ISLE",        defaultLabel = "Isle of Quel'Danas", zoneName = "Isle of Quel'Danas", mapIDs = { 2424 } },
    { localeKey = "REMINDER_WQ_CAT_HARANDAR",   defaultLabel = "Harandar",             zoneName = "Harandar",         mapIDs = { 2413, 2576 } },
    { localeKey = "REMINDER_WQ_CAT_ZULAMAN",    defaultLabel = "Zul'Aman",             zoneName = "Zul'Aman",         mapIDs = { 2437, 2536 } },
    { localeKey = "REMINDER_WQ_CAT_VOIDSTORM",  defaultLabel = "Voidstorm",            zoneName = "Voidstorm",        mapIDs = { 2405, 2444, 2541 } },
    { localeKey = "REMINDER_WQ_CAT_QUELTHALAS", defaultLabel = "Quel'Thalas (all)",    zoneName = "Quel'Thalas",
      mapIDs = { 2393, 2395, 2424, 2413, 2576, 2437, 2536, 2405, 2444, 2541, QUELTHALAS_MAP } },
}

local MAP_TO_ZONE_INDEX = {}
for zi = 1, #INDEX.ZONES do
    local z = INDEX.ZONES[zi]
    for mi = 1, #(z.mapIDs or {}) do
        local mid = z.mapIDs[mi]
        if not MAP_TO_ZONE_INDEX[mid] then
            MAP_TO_ZONE_INDEX[mid] = zi
        end
    end
end

local function IsSecret(val)
    return issecretvalue and val and issecretvalue(val)
end

local expandedZoneMapTrees = {}

--- Merge C_Map child uiMapIDs under each zone root (Silvermoon subfloors, etc.).
local function EnsureZoneMapExpansion(zoneIndex)
    if expandedZoneMapTrees[zoneIndex] then return end
    expandedZoneMapTrees[zoneIndex] = true
    local z = INDEX.ZONES[zoneIndex]
    if not z or not C_Map or not C_Map.GetMapChildrenInfo then return end
    local base = z.mapIDs or {}
    local seen = {}
    for i = 1, #base do
        seen[base[i]] = true
    end
    local function walk(parentID, depth)
        depth = depth or 0
        if depth > 8 then return end
        parentID = tonumber(parentID)
        if not parentID or parentID <= 0 then return end
        local ok, children = pcall(C_Map.GetMapChildrenInfo, parentID, nil, true)
        if not ok or type(children) ~= "table" then return end
        for ci = 1, #children do
            local child = children[ci]
            local childID = child and (child.mapID or child.mapId)
            if childID == nil or IsSecret(childID) then
                childID = nil
            else
                childID = tonumber(childID)
            end
            if childID and childID > 0 and not seen[childID] then
                seen[childID] = true
                z.mapIDs[#z.mapIDs + 1] = childID
                if not MAP_TO_ZONE_INDEX[childID] then
                    MAP_TO_ZONE_INDEX[childID] = zoneIndex
                end
                walk(childID, depth + 1)
            end
        end
    end
    for i = 1, #base do
        walk(base[i], 0)
    end
end

--- Optional curated quest IDs per uiMapID (merged with API scan + discovery).
INDEX.QUEST_SEEDS = {}

local function IsWorldQuest(questID)
    if not questID or questID <= 0 then return false end
    if not C_QuestLog or not C_QuestLog.IsWorldQuest then return false end
    local ok, result = pcall(C_QuestLog.IsWorldQuest, questID)
    return ok and result == true
end

--- Emissary / calling weeklies are not regional WQs — exclude from zone tabs (see DailyQuestManager weeklyQuests).
local function IsQuestCalling(questID)
    if not questID or questID <= 0 then return false end
    if not C_QuestLog or not C_QuestLog.IsQuestCalling then return false end
    local ok, result = pcall(C_QuestLog.IsQuestCalling, questID)
    return ok and result == true
end

--- Title fallback when map pins sit on Quel'Thalas hub (2537) or a wrong subfloor.
function INDEX.ResolveZoneIndexFromEmissaryTitle(title)
    if not title or title == "" or IsSecret(title) then return nil end
    local lower = title:lower()
    if not lower:find("emissary", 1, true) then return nil end
    if lower:find("silvermoon court", 1, true) then return 2 end
    if lower:find("amani", 1, true) then return 5 end
    if lower:find("hara'ti", 1, true) or lower:find("harati", 1, true) or lower:find("haranir", 1, true) then return 4 end
    if lower:find("singularity", 1, true) or lower:find("stormarion", 1, true) then return 6 end
    return nil
end

local function SafeTitleSortKey(title)
    if not title or title == "" or IsSecret(title) then return "" end
    return title:lower()
end

local function ResolveQuestTitle(questID, questInfo)
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and t and t ~= "" and not IsSecret(t) then title = t end
    end
    if (not title or title == "") and type(questInfo) == "table" then
        local t2 = questInfo.title
        if t2 and t2 ~= "" and not IsSecret(t2) then title = t2 end
    end
    return title
end

--- True when the quest pin map lies on or under one of the zone root maps (not the reverse).
local function MapUnderZone(questMapID, zoneMapIDs)
    questMapID = tonumber(questMapID)
    if not questMapID or questMapID <= 0 then return false end
    if questMapID == QUELTHALAS_MAP then return false end
    local RMC = ns.ReminderMapContent
    if not RMC or not RMC.MapIsUnderAncestor then
        for i = 1, #zoneMapIDs do
            if zoneMapIDs[i] == questMapID then return true end
        end
        return false
    end
    for i = 1, #zoneMapIDs do
        local zid = zoneMapIDs[i]
        if questMapID == zid then return true end
        if RMC.MapIsUnderAncestor(questMapID, zid) then
            return true
        end
    end
    return false
end

local function GetCuratedZoneIndex(questID, title)
    local EMD = ns.ReminderMidnightFactionEmissaryData
    if EMD and EMD.GetZoneIndexForQuest then
        local zi = EMD.GetZoneIndexForQuest(questID)
        if zi then return zi end
    end
    if EMD and EMD.IsEmissaryTitle and EMD.IsEmissaryTitle(title) then
        return INDEX.ResolveZoneIndexFromEmissaryTitle(title)
    end
    local data = ns.ReminderMidnightWorldQuestData
    if data and data.ENTRIES then
        local qid = tonumber(questID)
        for i = 1, #data.ENTRIES do
            local e = data.ENTRIES[i]
            if e and e.questID == qid and e.zoneKey then
                local WQC = ns.ReminderWorldQuestCatalog
                if WQC and WQC.ZONE_INDEX_BY_KEY then
                    return WQC.ZONE_INDEX_BY_KEY[e.zoneKey]
                end
            end
        end
    end
    return nil
end

local function QuestBelongsToZoneIndex(questID, questMapID, title, zoneIndex)
    if zoneIndex == QUELTHALAS_ALL_INDEX then return true end
    local z = INDEX.ZONES[zoneIndex]
    if not z then return false end
    title = title or ResolveQuestTitle(questID, nil)

    local curatedZi = GetCuratedZoneIndex(questID, title)
    if curatedZi then
        return curatedZi == zoneIndex
    end

    local titleZi = INDEX.ResolveZoneIndexFromEmissaryTitle(title)
    if titleZi then
        return titleZi == zoneIndex
    end

    local mapIDs = z.mapIDs or {}
    local qMap = tonumber(questMapID)
    if qMap and qMap > 0 and MapUnderZone(qMap, mapIDs) then return true end
    if qMap and qMap > 0 then
        local resolved = INDEX.ResolveZoneIndexForMap(qMap)
        if resolved and resolved == zoneIndex then return true end
    end
    return false
end

--- Collect world quests registered on a map (catalog: include inactive map pins).
---@param mapID number
---@param seen table<number, boolean>
---@param out table[]
local function CollectWorldQuestsOnMap(mapID, zoneName, seen, out)
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 then return end

    local function tryAdd(questID, questMapID, questInfo, sourceTag)
        questID = tonumber(questID)
        if not questID or questID <= 0 or seen[questID] then return end
        if not IsWorldQuest(questID) then return end
        if IsQuestCalling(questID) then return end
        local title = ResolveQuestTitle(questID, questInfo)
        local EMD = ns.ReminderMidnightFactionEmissaryData
        if EMD and EMD.IsEmissaryTitle and EMD.IsEmissaryTitle(title) and not EMD.GetEntry(questID) then
            return
        end
        seen[questID] = true
        local qMap = tonumber(questMapID) or mapID
        local displayZone
        local curatedZi = GetCuratedZoneIndex(questID, title)
        if curatedZi and INDEX.ZONES[curatedZi] then
            displayZone = INDEX.ZONES[curatedZi].zoneName
            local entry = EMD and EMD.GetEntry and EMD.GetEntry(questID)
            if entry and entry.mapID then
                qMap = entry.mapID
            end
        else
            displayZone = INDEX.ResolveZoneNameForMap(qMap) or zoneName
        end
        out[#out + 1] = {
            questID = questID,
            title = title,
            zone = displayZone,
            mapID = qMap,
            source = sourceTag or "api",
        }
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
                    tryAdd(qid, qi.mapID or qi.mapId or mapID, qi, "task")
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
                    tryAdd(qid, qi.mapID or mapID, qi, "questlog")
                end
            end
        end
    end
end

---@param zoneIndex number
---@return table[] entries { questID, title, zone, mapID, source, isActive }
function INDEX.CollectForZone(zoneIndex)
    local z = INDEX.ZONES[zoneIndex]
    if not z then return {} end
    EnsureZoneMapExpansion(zoneIndex)

    local seen = {}
    local raw = {}
    local mapIDs = z.mapIDs or {}

    local EMD = ns.ReminderMidnightFactionEmissaryData
    if EMD and EMD.ENTRIES then
        for ei = 1, #EMD.ENTRIES do
            local e = EMD.ENTRIES[ei]
            local qid = e and tonumber(e.questID)
            if qid and not seen[qid] and EMD.GetZoneIndexForQuest(qid) == zoneIndex then
                seen[qid] = true
                raw[#raw + 1] = {
                    questID = qid,
                    title = e.title or ResolveQuestTitle(qid, nil),
                    zone = z.zoneName,
                    mapID = e.mapID,
                    source = "emissary_curated",
                }
            end
        end
    end

    local WQC = ns.ReminderWorldQuestCatalog
    local zoneKey = WQC and WQC.GetZoneKeyForIndex and WQC.GetZoneKeyForIndex(zoneIndex)
    if WQC and zoneKey and WQC.GetMaintainedRowsForZoneKey then
        local maintained = WQC.GetMaintainedRowsForZoneKey(zoneKey)
        for i = 1, #maintained do
            local e = maintained[i]
            local qid = e and tonumber(e.questID)
            if qid and not seen[qid] and not IsQuestCalling(qid) then
                local title = e.title or ResolveQuestTitle(qid, nil)
                if QuestBelongsToZoneIndex(qid, e.mapID, title, zoneIndex) then
                    seen[qid] = true
                    local qMap = tonumber(e.mapID)
                    raw[#raw + 1] = {
                        questID = qid,
                        title = title,
                        zone = (qMap and INDEX.ResolveZoneNameForMap(qMap)) or z.zoneName,
                        mapID = e.mapID,
                        source = e.source or "catalog",
                    }
                end
            end
        end
    end

    for mi = 1, #mapIDs do
        CollectWorldQuestsOnMap(mapIDs[mi], z.zoneName, seen, raw)
    end

    -- Parent hub: only quests whose pin map is under this zone (not every child of 2537).
    if zoneIndex ~= QUELTHALAS_ALL_INDEX then
        local hubSeen = {}
        local hubRaw = {}
        CollectWorldQuestsOnMap(QUELTHALAS_MAP, z.zoneName, hubSeen, hubRaw)
        for i = 1, #hubRaw do
            local e = hubRaw[i]
            local qid = e.questID
            if qid and not seen[qid] and QuestBelongsToZoneIndex(qid, e.mapID, e.title, zoneIndex) then
                seen[qid] = true
                raw[#raw + 1] = e
            end
        end
    end

    for mi = 1, #mapIDs do
        local seeds = INDEX.QUEST_SEEDS[mapIDs[mi]]
        if seeds then
            for si = 1, #seeds do
                local qid = tonumber(seeds[si])
                if qid and not seen[qid] then
                    seen[qid] = true
                    raw[#raw + 1] = {
                        questID = qid,
                        title = ResolveQuestTitle(qid, nil),
                        zone = z.zoneName,
                        mapID = mapIDs[mi],
                        source = "seed",
                    }
                end
            end
        end
    end

    local activeSet = {}
    local WarbandNexus = ns.WarbandNexus
    if WarbandNexus and WarbandNexus.ScanMidnightQuests then
        local ok, quests = pcall(function() return WarbandNexus:ScanMidnightQuests() end)
        if ok and quests and type(quests.worldQuests) == "table" then
            for i = 1, #quests.worldQuests do
                local q = quests.worldQuests[i]
                if q and q.questID then
                    activeSet[q.questID] = true
                end
            end
        end
    end

    if zoneIndex ~= QUELTHALAS_ALL_INDEX then
        local filtered = {}
        for i = 1, #raw do
            local e = raw[i]
            if e and QuestBelongsToZoneIndex(e.questID, e.mapID, e.title, zoneIndex) then
                filtered[#filtered + 1] = e
            end
        end
        raw = filtered
    end

    for i = 1, #raw do
        local e = raw[i]
        e.isActive = activeSet[e.questID] == true
    end

    table.sort(raw, function(a, b)
        local aa = a.isActive and 0 or 1
        local ab = b.isActive and 0 or 1
        if aa ~= ab then return aa < ab end
        local ta = SafeTitleSortKey(a.title)
        local tb = SafeTitleSortKey(b.title)
        return ta < tb
    end)

    return raw
end

local function ParentHopCount(fromMapID, rootMapID)
    local RMC = ns.ReminderMapContent
    if not RMC or not RMC.MapIsUnderAncestor then return 0 end
    if not RMC.MapIsUnderAncestor(fromMapID, rootMapID) then return -1 end
    local depth = 0
    local cur = tonumber(fromMapID)
    local root = tonumber(rootMapID)
    local guard = 0
    while cur and cur > 0 and cur ~= root and guard < 64 do
        guard = guard + 1
        depth = depth + 1
        if not C_Map or not C_Map.GetMapInfo then break end
        local ok, info = pcall(C_Map.GetMapInfo, cur)
        if not ok or not info then break end
        local p = info.parentMapID
        if p == nil or p == 0 or (issecretvalue and issecretvalue(p)) then break end
        cur = tonumber(p)
    end
    return depth
end

function INDEX.ResolveZoneIndexForMap(mapID)
    mapID = tonumber(mapID)
    if not mapID then return nil end
    if mapID == QUELTHALAS_MAP then return QUELTHALAS_ALL_INDEX end
    local direct = MAP_TO_ZONE_INDEX[mapID]
    if direct and direct ~= QUELTHALAS_ALL_INDEX then return direct end
    local RMC = ns.ReminderMapContent
    if not RMC or not RMC.MapIsUnderAncestor then return direct end
    local bestZi, bestDepth = nil, -1
    for zi = 1, QUELTHALAS_ALL_INDEX - 1 do
        local z = INDEX.ZONES[zi]
        local mapIDs = z.mapIDs or {}
        for mi = 1, #mapIDs do
            local root = mapIDs[mi]
            if mapID == root then
                return zi
            end
            local depth = ParentHopCount(mapID, root)
            if depth >= 0 and depth > bestDepth then
                bestDepth = depth
                bestZi = zi
            end
        end
    end
    return bestZi or direct
end

function INDEX.ResolveZoneNameForMap(mapID)
    local zi = INDEX.ResolveZoneIndexForMap(mapID)
    if zi and INDEX.ZONES[zi] then
        return INDEX.ZONES[zi].zoneName
    end
    return "Quel'Thalas"
end

--- All Midnight picker maps: curated zone list + Quel'Thalas subtree from C_Map.
---@return number[]
function INDEX.GetExpandedMapIDList()
    local seen = {}
    local out = {}

    local function add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end

    for zi = 1, #INDEX.ZONES do
        local z = INDEX.ZONES[zi]
        for mi = 1, #(z.mapIDs or {}) do
            add(z.mapIDs[mi])
        end
    end

    local function walk(parentID, depth)
        depth = depth or 0
        if depth > 8 or not parentID then return end
        add(parentID)
        if not C_Map or not C_Map.GetMapChildrenInfo then return end
        local ok, children = pcall(C_Map.GetMapChildrenInfo, parentID, nil, true)
        if not ok or type(children) ~= "table" then return end
        for ci = 1, #children do
            local child = children[ci]
            local childID = child and (child.mapID or child.mapId)
            if childID == nil or IsSecret(childID) then
                childID = nil
            else
                childID = tonumber(childID)
            end
            if childID and childID > 0 then
                walk(childID, depth + 1)
            end
        end
    end

    walk(QUELTHALAS_MAP, 0)
    for i = 1, #out do
        walk(out[i], 0)
    end

    return out
end

--- Deep scan every Midnight map (catalog rows, including inactive map pins).
---@return table[] entries { questID, title, zone, mapID, source }
function INDEX.DeepScanAllMaps()
    local mapIDs = INDEX.GetExpandedMapIDList()
    local seen = {}
    local raw = {}
    for mi = 1, #mapIDs do
        local mapID = mapIDs[mi]
        local zoneName = INDEX.ResolveZoneNameForMap(mapID)
        CollectWorldQuestsOnMap(mapID, zoneName, seen, raw)
    end
    return raw
end
