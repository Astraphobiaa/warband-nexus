--[[
    Set Alert quest lists: flat World Quest + flat Content Events (MidnightQuestCatalog category events).
    Display-only catalog (active/inactive not split); maintained WQ data + MidnightQuestCatalog events.
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

local M = {}
ns.ReminderQuestCatalog = M

local WQ_INDEX = ns.ReminderWorldQuestIndex
local rowCache = {}

local function GetDiscoveryTable()
    local db = ns.WarbandNexus and ns.WarbandNexus.db
    if not db or not db.global then return nil end
    db.global.reminderQuestDiscovery = db.global.reminderQuestDiscovery or {
        worldQuests = {},
    }
    return db.global.reminderQuestDiscovery
end

function M.RecordDiscoveredWorldQuests(questRows)
    if type(questRows) ~= "table" then return end
    local disc = GetDiscoveryTable()
    if not disc or type(disc.worldQuests) ~= "table" then return end
    local wq = disc.worldQuests
    local now = time()
    for i = 1, #questRows do
        local q = questRows[i]
        local id = q and tonumber(q.questID)
        if id and id > 0 then
            local title = q.title
            if title and issecretvalue and issecretvalue(title) then title = nil end
            local row = wq[id]
            if not row then
                wq[id] = {
                    title = title or ("Quest " .. tostring(id)),
                    zone = q.zone,
                    mapID = q.mapID,
                    lastSeen = now,
                }
            else
                if title and title ~= "" then row.title = title end
                if q.zone and q.zone ~= "" then row.zone = q.zone end
                if q.mapID then row.mapID = q.mapID end
                row.lastSeen = now
            end
        end
    end
end

local function ImportWorldQuestRows(questRows)
    if type(questRows) ~= "table" or #questRows == 0 then return end
    M.RecordDiscoveredWorldQuests(questRows)
    local WQC = ns.ReminderWorldQuestCatalog
    if WQC and WQC.ImportFromScanRows then
        WQC.ImportFromScanRows(questRows)
    end
end

function M.RefreshDiscoveryFromScan()
    local rows
    if WQ_INDEX and WQ_INDEX.DeepScanAllMaps then
        local ok, scanned = pcall(WQ_INDEX.DeepScanAllMaps)
        if ok and type(scanned) == "table" and #scanned > 0 then
            rows = scanned
        end
    end
    if not rows then
        local WarbandNexus = ns.WarbandNexus
        if WarbandNexus and WarbandNexus.ScanMidnightQuests then
            local ok, quests = pcall(function() return WarbandNexus:ScanMidnightQuests() end)
            if ok and quests and quests.worldQuests then
                rows = quests.worldQuests
            end
        end
    end
    if rows then
        ImportWorldQuestRows(rows)
    end
    rowCache = {}
end

function M.ClearRowCache()
    rowCache = {}
end

local function SafeSortKey(s)
    if not s or s == "" or (issecretvalue and issecretvalue(s)) then return "" end
    return s:lower()
end

local function CmpTitle(a, b)
    local za = SafeSortKey(a and a.zone)
    local zb = SafeSortKey(b and b.zone)
    if za ~= zb then return za < zb end
    return SafeSortKey(a and a.title) < SafeSortKey(b and b.title)
end

---@return table[] { questID, title, zone }
function M.GetFlatWorldQuestRows()
    if rowCache.worldQuests then return rowCache.worldQuests end

    local seen = {}
    local out = {}

    if WQ_INDEX and WQ_INDEX.ZONES then
        for zi = 1, #WQ_INDEX.ZONES do
            if WQ_INDEX.CollectForZone then
                local collected = WQ_INDEX.CollectForZone(zi)
                for i = 1, #collected do
                    local e = collected[i]
                    local qid = e and tonumber(e.questID)
                    if qid and not seen[qid] then
                        seen[qid] = true
                        out[#out + 1] = {
                            questID = qid,
                            title = e.title,
                            zone = e.zone,
                        }
                    end
                end
            end
        end
    end

    local WQC = ns.ReminderWorldQuestCatalog
    if WQC and WQC.GetAllMaintainedRows then
        local WQ_INDEX2 = ns.ReminderWorldQuestIndex
        local maintained = WQC.GetAllMaintainedRows()
        for i = 1, #maintained do
            local e = maintained[i]
            local qid = e and tonumber(e.questID)
            if qid and not seen[qid] then
                seen[qid] = true
                local zone
                if e.zoneKey and WQ_INDEX2 and WQ_INDEX2.ZONES then
                    for zi = 1, #WQ_INDEX2.ZONES do
                        local zk = WQC.GetZoneKeyForIndex and WQC.GetZoneKeyForIndex(zi)
                        if zk == e.zoneKey then
                            zone = WQ_INDEX2.ZONES[zi].zoneName
                            break
                        end
                    end
                end
                out[#out + 1] = {
                    questID = qid,
                    title = e.title,
                    zone = zone,
                }
            end
        end
    end

    local disc = GetDiscoveryTable()
    if disc and type(disc.worldQuests) == "table" then
        for qid, meta in pairs(disc.worldQuests) do
            local id = tonumber(qid)
            if id and not seen[id] then
                seen[id] = true
                out[#out + 1] = {
                    questID = id,
                    title = meta and meta.title,
                    zone = meta and meta.zone,
                }
            end
        end
    end

    table.sort(out, CmpTitle)
    rowCache.worldQuests = out
    return out
end

---@return table[] { questID, title, zone }
function M.GetFlatContentEventRows()
    if rowCache.contentEvents then return rowCache.contentEvents end

    local out = {}
    local cat = ns.MidnightQuestCatalog
    if cat and cat.GetEntries then
        local list = cat.GetEntries()
        local order = cat.GetEventGroupOrder and cat.GetEventGroupOrder() or {}
        for i = 1, #list do
            local e = list[i]
            if e and e.category == "events" and e.questID then
                out[#out + 1] = {
                    questID = e.questID,
                    title = e.title,
                    zone = e.zone,
                    sortGroup = order[e.eventGroup or ""] or 99,
                    isSubQuest = e.isSubQuest,
                }
            end
        end
        table.sort(out, function(a, b)
            if a.sortGroup ~= b.sortGroup then return a.sortGroup < b.sortGroup end
            local aSub = a.isSubQuest and 1 or 0
            local bSub = b.isSubQuest and 1 or 0
            if aSub ~= bSub then return aSub < bSub end
            return CmpTitle(a, b)
        end)
        for i = 1, #out do
            out[i].sortGroup = nil
            out[i].isSubQuest = nil
        end
    end

    rowCache.contentEvents = out
    return out
end

function M.GetMaxListRowCount()
    local wq = M.GetFlatWorldQuestRows()
    local ev = M.GetFlatContentEventRows()
    local we = 0
    local HEC = ns.ReminderHolidayEventCatalog
    if HEC and HEC.CALENDAR_EVENTS then
        we = #HEC.CALENDAR_EVENTS
    end
    local staticWQ = (ns.ReminderMidnightWorldQuestData and ns.ReminderMidnightWorldQuestData.BUILD_COUNT) or 0
    return math.max(#wq, #ev, we, staticWQ, 64)
end

function M.ResolveQuestTitle(questID)
    local id = tonumber(questID)
    if not id then return nil end
    local lookup = ns.MidnightQuestCatalog and ns.MidnightQuestCatalog.GetLookup and ns.MidnightQuestCatalog.GetLookup()
    if lookup and lookup[id] and lookup[id].title then
        return lookup[id].title
    end
    local disc = GetDiscoveryTable()
    if disc and disc.worldQuests and disc.worldQuests[id] and disc.worldQuests[id].title then
        return disc.worldQuests[id].title
    end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and title and not (issecretvalue and issecretvalue(title)) then
            return title
        end
    end
    return nil
end
