--[[
    UiMapID → content kind for reminder zone picker (Midnight / Interface 120005).

    Curated picker ids (Midnight): Modules/Data/ReminderContentIndex.lua — optional journalInstanceID;
    live projection uses EJ_GetInstanceForMap (warcraft.wiki.gg/wiki/API_EJ_GetInstanceForMap) + EJ_GetInstanceInfo.

    Authoritative rules (live client):
    - C_Map.GetMapInfo(uiMapID).mapType (Enum.UIMapType)
    - Encounter Journal: EJ_GetInstanceForMap(uiMapID) → EJ_GetInstanceInfo(jid)
      → select 12 = isRaid (warcraft.wiki.gg/API_EJ_GetInstanceInfo)

    Raid vs dungeon uses journal when available; UIMapType.Dungeon alone is not sufficient.

    Delves: Blizzard often reports delve instances as UIMapType.Dungeon. UiMapIDs listed as delves in
    Modules/Data/ReminderContentIndex.lua resolve as Kind.DELVE (see ReminderContentIndex.IsDelveUIMap).
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

ns.UIMapContentKind = ns.UIMapContentKind or {}

local UIMapType = Enum and Enum.UIMapType

---@class UIMapContentKindEnum
local Kind = {
    COSMIC = "cosmic",
    WORLD = "world",
    CONTINENT = "continent",
    ZONE = "zone",
    MICRO = "micro",
    ORPHAN = "orphan",
    SCENARIO = "scenario",
    DUNGEON = "dungeon",
    RAID = "raid",
    DELVE = "delve",
    UNKNOWN = "unknown",
}

local cache = {}

local TAG_HEX = {
    raid = "c8b68e",
    dungeon = "d4b56c",
    delve = "6ecfb9",
    zone = "9ecfae",
    micro = "b0a8e8",
    orphan = "8eb0ca",
    scenario = "8eb0ca",
    continent = "c0c0c0",
    unknown = "888888",
}

local TAG_LOCALE = {
    raid = "REMINDER_ZONE_KIND_TAG_RAID",
    dungeon = "REMINDER_ZONE_KIND_TAG_DUNGEON",
    delve = "REMINDER_ZONE_KIND_TAG_DELVE",
    zone = "REMINDER_ZONE_KIND_TAG_ZONE",
    micro = "REMINDER_ZONE_KIND_TAG_AREA",
    orphan = "REMINDER_ZONE_KIND_TAG_MISC",
    scenario = "REMINDER_ZONE_KIND_TAG_SCENARIO",
    continent = "REMINDER_ZONE_KIND_TAG_REGION",
    unknown = "REMINDER_ZONE_KIND_TAG_UNKNOWN",
}

local TAG_FALLBACK = {
    raid = "[Raid]",
    dungeon = "[Dgn]",
    delve = "[Dlv]",
    zone = "[Zone]",
    micro = "[Area]",
    orphan = "[Misc]",
    scenario = "[Scen]",
    continent = "[Reg]",
    unknown = "[?]",
}

local ejPrimed = false

local function ensureEncounterJournal()
    if ejPrimed then return end
    if InCombatLockdown() then return end
    local U = ns.Utilities
    if U and U.SafeLoadAddOn then
        U:SafeLoadAddOn("Blizzard_EncounterJournal")
    end
    ejPrimed = true
end

---@param journalInstanceID number
---@return boolean|nil isRaid true/false when EJ answers; nil if unknown
local function ejInstanceIsRaid(journalInstanceID)
    if not journalInstanceID or type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return nil
    end
    if not EJ_GetInstanceInfo then return nil end
    ensureEncounterJournal()
    local ok, _, _, _, _, _, _, _, _, _, _, isRaid = pcall(EJ_GetInstanceInfo, journalInstanceID)
    if not ok then return nil end
    if type(isRaid) ~= "boolean" then return nil end
    return isRaid
end

---@param mapID number
---@return number|nil journalInstanceID
local function journalInstanceForUIMap(mapID)
    if not EJ_GetInstanceForMap then return nil end
    ensureEncounterJournal()
    local ok, jid = pcall(EJ_GetInstanceForMap, mapID)
    if not ok or jid == nil then return nil end
    if type(jid) ~= "number" or jid <= 0 then return nil end
    if issecretvalue and issecretvalue(jid) then return nil end
    return jid
end

local function cacheResult(mapID, kind)
    cache[mapID] = kind
    return kind
end

--- Load Blizzard_EncounterJournal before bulk Resolve (picker open). Safe no-op in combat.
function ns.UIMapContentKind.EnsureJournalLoaded()
    ensureEncounterJournal()
end

function ns.UIMapContentKind.InvalidateCache()
    wipe(cache)
end

--- Exposed for ordering / switches (stable string keys).
function ns.UIMapContentKind.GetKindEnum()
    return Kind
end

--- Colored short tag for FontString:SetText (matches reminder picker column).
---@param kind string
---@return string
function ns.UIMapContentKind.FormatPickerTag(kind)
    if not kind or kind == "" then kind = Kind.UNKNOWN end
    local hex = TAG_HEX[kind] or TAG_HEX.unknown
    local L = ns.L
    local locKey = TAG_LOCALE[kind]
    local text = (locKey and L and L[locKey]) or TAG_FALLBACK[kind] or TAG_FALLBACK.unknown
    return "|cff" .. hex .. text .. "|r"
end

---@param mapID number
---@param info table|nil Optional result of C_Map.GetMapInfo(mapID) to avoid duplicate API calls.
---@return string kind One of Kind.* string values.
function ns.UIMapContentKind.Resolve(mapID, info)
    local mid = tonumber(mapID)
    if not mid or mid <= 0 then return Kind.UNKNOWN end

    local cached = cache[mid]
    if cached then return cached end

    if not UIMapType then return cacheResult(mid, Kind.UNKNOWN) end

    local mapInfo = info
    if not mapInfo then
        if not C_Map or not C_Map.GetMapInfo then return cacheResult(mid, Kind.UNKNOWN) end
        local ok, inf = pcall(C_Map.GetMapInfo, mid)
        if not ok or not inf then return cacheResult(mid, Kind.UNKNOWN) end
        mapInfo = inf
    end

    local mt = mapInfo.mapType

    if mt == UIMapType.Cosmic then return cacheResult(mid, Kind.COSMIC) end
    if mt == UIMapType.World then return cacheResult(mid, Kind.WORLD) end
    if mt == UIMapType.Continent then return cacheResult(mid, Kind.CONTINENT) end

    if UIMapType.Delve and mt == UIMapType.Delve then return cacheResult(mid, Kind.DELVE) end

    local jid = journalInstanceForUIMap(mid)
    local isRaid = jid and ejInstanceIsRaid(jid) or nil

    if mt == UIMapType.Dungeon then
        if isRaid == true then return cacheResult(mid, Kind.RAID) end
        local RCI = ns.ReminderContentIndex
        if RCI and RCI.IsDelveUIMap and RCI.IsDelveUIMap(mid) then
            return cacheResult(mid, Kind.DELVE)
        end
        return cacheResult(mid, Kind.DUNGEON)
    end

    if mt == UIMapType.Zone then
        if isRaid == true then return cacheResult(mid, Kind.RAID) end
        if isRaid == false then return cacheResult(mid, Kind.DUNGEON) end
        return cacheResult(mid, Kind.ZONE)
    end

    if mt == UIMapType.Micro then return cacheResult(mid, Kind.MICRO) end
    if mt == UIMapType.Orphan then return cacheResult(mid, Kind.ORPHAN) end

    if UIMapType.Scenario and mt == UIMapType.Scenario then return cacheResult(mid, Kind.SCENARIO) end

    return cacheResult(mid, Kind.UNKNOWN)
end

---Coarse geography bucket for cross-layer labels (plans, reminders, picker).
---@param kind string|nil Resolved kind string (same family as Resolve / Kind.* values).
---@return string raid|dungeon|delve|open_world|scenario|continent|world|unknown
function ns.UIMapContentKind.GetGeographyBucket(kind)
    if not kind or kind == "" then return "unknown" end
    if kind == Kind.RAID then return "raid" end
    if kind == Kind.DUNGEON then return "dungeon" end
    if kind == Kind.DELVE then return "delve" end
    if kind == Kind.ZONE or kind == Kind.MICRO then return "open_world" end
    if kind == Kind.CONTINENT then return "continent" end
    if kind == Kind.SCENARIO or kind == Kind.ORPHAN then return "scenario" end
    if kind == Kind.COSMIC or kind == Kind.WORLD then return "world" end
    return "unknown"
end

---Colored picker tag plus safe map title for tooltips/catalog hints. Omits sensitive API strings.
---@param mapID number|nil UiMapID
---@return string|nil line Rich text fragment or nil when unavailable.
function ns.UIMapContentKind.FormatGeographySummary(mapID)
    local mid = tonumber(mapID)
    if not mid or mid <= 0 then return nil end
    local UICK = ns.UIMapContentKind
    if UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
    local kind = UICK.Resolve(mid)
    local tag = UICK.FormatPickerTag(kind)

    local display = nil
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mid)
        if ok and info and info.name and info.name ~= "" then
            local nm = info.name
            if not (issecretvalue and nm and issecretvalue(nm)) then
                display = nm
            end
        end
    end
    if not display then
        display = "#" .. tostring(mid)
    end
    return tag .. " " .. display
end
