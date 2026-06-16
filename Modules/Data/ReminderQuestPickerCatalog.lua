--[[
    Set Alert quest picker: left-nav sections (WQ regions, Content Events, calendar World Events)
    with group headers. Save track modes remain worldQuests | contentEvents | worldEvents.

    Data dependencies (read-only catalogs; no parallel quest id lists here):
      ReminderWorldQuestIndex + ReminderWorldQuestCatalog / ReminderMidnightWorldQuestData — WQ rows
      ReminderQuestCatalog + MidnightQuestCatalog — quest titles / content-event ids
      ReminderHolidayEventCatalog — calendar world-event keys
    UI: Modules/UI/ReminderSetAlertDialog_QuestCatalog.lua
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

local M = {}
ns.ReminderQuestPickerCatalog = M

local WQ_INDEX = ns.ReminderWorldQuestIndex
local RQC = ns.ReminderQuestCatalog
local HEC = ns.ReminderHolidayEventCatalog

local EVENT_GROUP_HEADER = {
    soiree = "REMINDER_EVENT_GRP_SOIREE",
    abundance = "REMINDER_EVENT_GRP_ABUNDANCE",
    haranir = "REMINDER_EVENT_GRP_HARANIR",
    stormarion = "REMINDER_EVENT_GRP_STORMARION",
}

local sectionCache = nil
local rowCache = {}

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

local function ResolveTitle(entry)
    if not entry then return "?" end
    local title = entry.title
    if title and title ~= "" and not (issecretvalue and issecretvalue(title)) then
        return title
    end
    if entry.questID and RQC and RQC.ResolveQuestTitle then
        return RQC.ResolveQuestTitle(entry.questID) or ("Quest " .. tostring(entry.questID))
    end
    return entry.label or entry.key or "?"
end

function M.GetTypeSections()
    if sectionCache then return sectionCache end
    local out = {}
    if WQ_INDEX and WQ_INDEX.ZONES then
        for zi = 1, #WQ_INDEX.ZONES do
            local z = WQ_INDEX.ZONES[zi]
            if z and z.localeKey ~= "REMINDER_WQ_CAT_QUELTHALAS" then
                out[#out + 1] = {
                    trackMode = "worldQuests",
                    sectionKey = "wq_" .. tostring(zi),
                    zoneIndex = zi,
                    labelKey = z.localeKey,
                    fallback = z.defaultLabel or z.zoneName or "?",
                }
            end
        end
    end
    out[#out + 1] = {
        trackMode = "contentEvents",
        sectionKey = "zone_events",
        labelKey = "REMINDER_QUEST_CAT_CONTENT_EVENTS",
        fallback = "Content Events",
    }
    out[#out + 1] = {
        trackMode = "worldEvents",
        sectionKey = "calendar",
        labelKey = "REMINDER_QUEST_CAT_CALENDAR",
        fallback = "World Events",
    }
    sectionCache = out
    return out
end

function M.GetSectionIndex(sectionKey)
    local sections = M.GetTypeSections()
    for i = 1, #sections do
        if sections[i].sectionKey == sectionKey then
            return i
        end
    end
    return 1
end

function M.GetDefaultSectionIndexForTrackMode(trackMode)
    local sections = M.GetTypeSections()
    for i = 1, #sections do
        if sections[i].trackMode == trackMode then
            return i
        end
    end
    return 1
end

local function BuildWorldQuestRows(zoneIndex)
    local out = {}
    if WQ_INDEX and WQ_INDEX.CollectForZone and zoneIndex then
        local collected = WQ_INDEX.CollectForZone(zoneIndex)
        for i = 1, #collected do
            local e = collected[i]
            if e and e.questID then
                out[#out + 1] = {
                    questID = e.questID,
                    trackMode = "worldQuests",
                    title = ResolveTitle(e),
                    zone = e.zone,
                    typeTagKey = "REMINDER_QUEST_TAG_WQ",
                }
            end
        end
        table.sort(out, CmpTitle)
    end
    return out
end

local function BuildZoneEventRows()
    local out = {}
    local lastGroup = nil
    local flat = (RQC and RQC.GetFlatContentEventRows and RQC.GetFlatContentEventRows()) or {}
    local cat = ns.MidnightQuestCatalog
    local lookup = cat and cat.GetLookup and cat.GetLookup()
    for i = 1, #flat do
        local e = flat[i]
        if e and e.questID then
            local grp = nil
            if lookup and lookup[e.questID] then
                grp = lookup[e.questID].eventGroup
            end
            local hk = grp and EVENT_GROUP_HEADER[grp]
            if hk and hk ~= lastGroup then
                out[#out + 1] = { headerKey = hk }
                lastGroup = hk
            end
            out[#out + 1] = {
                questID = e.questID,
                trackMode = "contentEvents",
                title = ResolveTitle(e),
                zone = e.zone,
                    typeTagKey = "REMINDER_QUEST_TAG_CONTENT_EVENT",
            }
        end
    end
    return out
end

local function BuildCalendarRows()
    if HEC and HEC.GetPickerRows then
        local rows = HEC.GetPickerRows()
        local out = {}
        for i = 1, #rows do
            local e = rows[i]
            if e and e.key then
                out[#out + 1] = {
                    eventKey = e.key,
                    trackMode = "worldEvents",
                    label = e.label,
                    title = e.label,
                    isActive = e.isActive,
                    typeTagKey = "REMINDER_QUEST_TAG_CALENDAR",
                }
            end
        end
        return out
    end
    return {}
end

function M.GetDisplayRows(section)
    if not section then return {} end
    local cacheKey = (section.sectionKey or "") .. ":" .. tostring(section.zoneIndex or "")
    if rowCache[cacheKey] then
        return rowCache[cacheKey]
    end
    local rows
    if section.trackMode == "worldQuests" and section.zoneIndex then
        rows = BuildWorldQuestRows(section.zoneIndex)
    elseif section.trackMode == "contentEvents" or section.sectionKey == "zone_events" then
        rows = BuildZoneEventRows()
    else
        rows = BuildCalendarRows()
    end
    rowCache[cacheKey] = rows
    return rows
end

function M.ClearRowCache()
    rowCache = {}
    if RQC and RQC.ClearRowCache then
        RQC.ClearRowCache()
    end
end

function M.GetMaxDisplayRowCount()
    local maxRows = 64
    local sections = M.GetTypeSections()
    for i = 1, #sections do
        local rows = M.GetDisplayRows(sections[i])
        if #rows > maxRows then
            maxRows = #rows
        end
    end
    if RQC and RQC.GetMaxListRowCount then
        local base = RQC.GetMaxListRowCount()
        if base > maxRows then maxRows = base end
    end
    return maxRows + 8
end
