--[[
    Game-calendar world events for Set Alert (event keys only — no quest rows).
    Shipped catalog from warcraft.wiki.gg Category:Holidays (+ Darkmoon, micro-holidays).
    Active state: event title matches a HOLIDAY entry on today's calendar (C_Calendar).
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

local M = {}
ns.ReminderHolidayEventCatalog = M

---@class ReminderCalendarEventDef
---@field key string
---@field calendarName string Official / wiki calendar holiday name
---@field localeKey string|nil
---@field defaultLabel string

--- Shipped calendar holidays (wiki Category:Holidays + common micro-holidays).
M.CALENDAR_EVENTS = {
    { key = "darkmoon",           calendarName = "Darkmoon Faire",              localeKey = "REMINDER_HOLIDAY_DARKMOON",       defaultLabel = "Darkmoon Faire" },
    { key = "brewfest",           calendarName = "Brewfest",                    localeKey = "REMINDER_HOLIDAY_BREWFEST",       defaultLabel = "Brewfest" },
    { key = "childrens_week",     calendarName = "Children's Week",             localeKey = "REMINDER_HOLIDAY_CHILDRENS_WEEK", defaultLabel = "Children's Week" },
    { key = "day_of_the_dead",    calendarName = "Day of the Dead",             localeKey = "REMINDER_HOLIDAY_DAY_OF_DEAD",    defaultLabel = "Day of the Dead" },
    { key = "winter_veil",        calendarName = "Feast of Winter Veil",        localeKey = "REMINDER_HOLIDAY_WINTER_VEIL",  defaultLabel = "Feast of Winter Veil" },
    { key = "fireworks",          calendarName = "Fireworks Spectacular",       localeKey = "REMINDER_HOLIDAY_FIREWORKS",      defaultLabel = "Fireworks Spectacular" },
    { key = "hallows_end",        calendarName = "Hallow's End",                localeKey = "REMINDER_HOLIDAY_HALLOWS_END",    defaultLabel = "Hallow's End" },
    { key = "harvest_festival",   calendarName = "Harvest Festival",            localeKey = "REMINDER_HOLIDAY_HARVEST",        defaultLabel = "Harvest Festival" },
    { key = "love",               calendarName = "Love is in the Air",          localeKey = "REMINDER_HOLIDAY_LOVE",           defaultLabel = "Love is in the Air" },
    { key = "lunar",              calendarName = "Lunar Festival",              localeKey = "REMINDER_HOLIDAY_LUNAR",          defaultLabel = "Lunar Festival" },
    { key = "midsummer",          calendarName = "Midsummer Fire Festival",     localeKey = "REMINDER_HOLIDAY_MIDSUMMER",      defaultLabel = "Midsummer Fire Festival" },
    { key = "new_year",           calendarName = "New Year",                    localeKey = "REMINDER_HOLIDAY_NEW_YEAR",       defaultLabel = "New Year" },
    { key = "noblegarden",        calendarName = "Noblegarden",                 localeKey = "REMINDER_HOLIDAY_NOBLEGARDEN",    defaultLabel = "Noblegarden" },
    { key = "peon_day",           calendarName = "Peon Day",                    localeKey = "REMINDER_HOLIDAY_PEON_DAY",       defaultLabel = "Peon Day" },
    { key = "pilgrim",            calendarName = "Pilgrim's Bounty",            localeKey = "REMINDER_HOLIDAY_PILGRIM",        defaultLabel = "Pilgrim's Bounty" },
    { key = "pirates_day",        calendarName = "Pirates' Day",                localeKey = "REMINDER_HOLIDAY_PIRATES_DAY",      defaultLabel = "Pirates' Day" },
    { key = "wanderers_festival", calendarName = "Wanderer's Festival",         localeKey = "REMINDER_HOLIDAY_WANDERERS",      defaultLabel = "Wanderer's Festival" },
    { key = "auction_dance",      calendarName = "Auction House Dance Party",   localeKey = "REMINDER_HOLIDAY_AUCTION_DANCE",  defaultLabel = "Auction House Dance Party" },
    { key = "call_of_scarab",     calendarName = "Call of the Scarab",          localeKey = "REMINDER_HOLIDAY_CALL_SCARAB",    defaultLabel = "Call of the Scarab" },
    { key = "free_tshirt",        calendarName = "Free T-Shirt Day",            localeKey = "REMINDER_HOLIDAY_FREE_TSHIRT",    defaultLabel = "Free T-Shirt Day" },
    { key = "glowcap",            calendarName = "Glowcap Festival",            localeKey = "REMINDER_HOLIDAY_GLOWCAP",        defaultLabel = "Glowcap Festival" },
    { key = "gnomeregan_run",     calendarName = "Great Gnomeregan Run",        localeKey = "REMINDER_HOLIDAY_GNOMEREGAN",     defaultLabel = "Great Gnomeregan Run" },
    { key = "hippogryph_hatch",   calendarName = "Hatching of the Hippogryphs", localeKey = "REMINDER_HOLIDAY_HIPPOGRYPH",     defaultLabel = "Hatching of the Hippogryphs" },
    { key = "kirin_tor_crawl",    calendarName = "Kirin Tor Tavern Crawl",      localeKey = "REMINDER_HOLIDAY_KIRIN_TOR",      defaultLabel = "Kirin Tor Tavern Crawl" },
    { key = "luminous",           calendarName = "Luminous Luminaries",         localeKey = "REMINDER_HOLIDAY_LUMINOUS",       defaultLabel = "Luminous Luminaries" },
    { key = "march_tadpoles",     calendarName = "March of the Tadpoles",       localeKey = "REMINDER_HOLIDAY_TADPOLES",       defaultLabel = "March of the Tadpoles" },
    { key = "moonkin_festival",   calendarName = "Moonkin Festival",            localeKey = "REMINDER_HOLIDAY_MOONKIN",        defaultLabel = "Moonkin Festival" },
    { key = "spring_balloon",     calendarName = "Spring Balloon Festival",     localeKey = "REMINDER_HOLIDAY_SPRING_BALLOON", defaultLabel = "Spring Balloon Festival" },
    { key = "thousand_boat",      calendarName = "Thousand Boat Bash",           localeKey = "REMINDER_HOLIDAY_THOUSAND_BOAT",  defaultLabel = "Thousand Boat Bash" },
    { key = "trial_of_style",     calendarName = "Trial of Style",              localeKey = "REMINDER_HOLIDAY_TRIAL_STYLE",    defaultLabel = "Trial of Style" },
    { key = "ungoro_madness",     calendarName = "Un'Goro Madness",             localeKey = "REMINDER_HOLIDAY_UNGORO",         defaultLabel = "Un'Goro Madness" },
    { key = "volunteer_guard",    calendarName = "Volunteer Guard Day",         localeKey = "REMINDER_HOLIDAY_VOLUNTEER",      defaultLabel = "Volunteer Guard Day" },
    { key = "timewalking",        calendarName = "Timewalking Dungeon Event",   localeKey = "REMINDER_HOLIDAY_TIMEWALKING",    defaultLabel = "Timewalking Dungeon Event" },
    { key = "pvp_call_to_arms",   calendarName = "Call to Arms: ",              localeKey = "REMINDER_HOLIDAY_CALL_TO_ARMS",  defaultLabel = "Call to Arms (Battleground)" },
}

--- Legacy alias for code that referenced M.EVENTS.
M.EVENTS = M.CALENDAR_EVENTS

local function IsSecret(val)
    return issecretvalue and val and issecretvalue(val)
end

local function NormalizeName(s)
    if s == nil or IsSecret(s) then return "" end
    if s == "" then return "" end
    return s:lower()
end

local function NamesMatch(a, b)
    local na, nb = NormalizeName(a), NormalizeName(b)
    if na == "" or nb == "" then return false end
    if na == nb then return true end
    return na:find(nb, 1, true) or nb:find(na, 1, true)
end

--- Midnight: calendarType/title from C_Calendar may be secret in instances — never compare or index secret strings.
local function SafeNonEmptyString(val)
    if val == nil or IsSecret(val) then return nil end
    if val == "" then return nil end
    return val
end

local function IsHolidayCalendarType(calendarType)
    if calendarType == nil or IsSecret(calendarType) then return false end
    return calendarType == "HOLIDAY"
end

local function DayEventHolidayTitle(ev)
    if ev == nil then return nil end
    return SafeNonEmptyString(ev.title) or SafeNonEmptyString(ev.name)
end

local holidayTitlesCacheDay = nil
local holidayTitlesCache = nil

--- Midnight: C_Calendar day-event fields are often secret in instances; skip live reads there.
local function IsPlayerInInstanceSafe()
    if not IsInInstance then return false end
    local ok, inInst = pcall(IsInInstance)
    if not ok then return false end
    if IsSecret(inInst) then return true end
    return inInst and true or false
end

local function ShouldSkipLiveCalendarRead()
    return IsPlayerInInstanceSafe()
end

local function EventMatchesTodayTitles(eventDef, todayTitles)
    if not eventDef or not eventDef.calendarName or not todayTitles then return false end
    local target = eventDef.calendarName
    for i = 1, #todayTitles do
        if NamesMatch(todayTitles[i], target) then
            return true
        end
    end
    return false
end

function M.InvalidateHolidayTitlesCache()
    holidayTitlesCacheDay = nil
    holidayTitlesCache = nil
end

function M.GetEventLabel(eventDef)
    if not eventDef then return "?" end
    local L = ns.L
    if L and eventDef.localeKey and L[eventDef.localeKey] then
        return L[eventDef.localeKey]
    end
    return eventDef.defaultLabel or eventDef.calendarName or eventDef.key or "?"
end

---@param key string
---@return ReminderCalendarEventDef|nil
function M.GetEventByKey(key)
    for i = 1, #M.CALENDAR_EVENTS do
        if M.CALENDAR_EVENTS[i].key == key then
            return M.CALENDAR_EVENTS[i]
        end
    end
    return nil
end

local function GetTodayCalendarDay()
    if not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then return nil end
    local ok, today = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if ok and type(today) == "table" then
        local day = today.monthDay
        if type(day) == "number" and day >= 1 and day <= 31 and not IsSecret(day) then
            return day
        end
    end
    return nil
end

--- Collect HOLIDAY titles on today's calendar day (month offset 0).
---@param todayDay number
---@return string[]
local function BuildTodayHolidayTitles(todayDay)
    local out = {}
    local seen = {}
    if not todayDay or not C_Calendar then return out end
    if C_Calendar.OpenCalendar then
        pcall(C_Calendar.OpenCalendar)
    end

    local numEvents = 0
    if C_Calendar.GetNumDayEvents then
        local ok, n = pcall(C_Calendar.GetNumDayEvents, 0, todayDay)
        if ok and type(n) == "number" then numEvents = n end
    end

    local function addTitle(title)
        if title == nil or IsSecret(title) then return end
        if title == "" or seen[title] then return end
        seen[title] = true
        out[#out + 1] = title
    end

    for index = 1, numEvents do
        pcall(function()
            if C_Calendar.GetHolidayInfo then
                local ok2, info = pcall(C_Calendar.GetHolidayInfo, 0, todayDay, index)
                if ok2 and info then
                    addTitle(SafeNonEmptyString(info.name))
                end
            end
            if C_Calendar.GetDayEvent then
                local ok3, ev = pcall(C_Calendar.GetDayEvent, 0, todayDay, index)
                if ok3 and ev and IsHolidayCalendarType(ev.calendarType) then
                    addTitle(DayEventHolidayTitle(ev))
                end
            end
        end)
    end

    return out
end

---@return string[]
local function GetTodayHolidayTitles()
    local todayDay = GetTodayCalendarDay()
    if not todayDay then return {} end
    if holidayTitlesCacheDay == todayDay and holidayTitlesCache then
        return holidayTitlesCache
    end
    if ShouldSkipLiveCalendarRead() then
        return holidayTitlesCache or {}
    end
    local ok, built = pcall(BuildTodayHolidayTitles, todayDay)
    if not ok or type(built) ~= "table" then
        built = {}
    end
    holidayTitlesCacheDay = todayDay
    holidayTitlesCache = built
    return built
end

---@param eventDef ReminderCalendarEventDef
function M.IsEventActive(eventDef)
    return EventMatchesTodayTitles(eventDef, GetTodayHolidayTitles())
end

--- Picker rows: { key, label, isActive }
function M.GetPickerRows()
    local todayTitles = GetTodayHolidayTitles()
    local out = {}
    for i = 1, #M.CALENDAR_EVENTS do
        local e = M.CALENDAR_EVENTS[i]
        out[#out + 1] = {
            key = e.key,
            label = M.GetEventLabel(e),
            isActive = EventMatchesTodayTitles(e, todayTitles),
        }
    end
    table.sort(out, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return (a.label or ""):lower() < (b.label or ""):lower()
    end)
    return out
end

---@return ReminderCalendarEventDef[] entries active on today's calendar
function M.GetActiveEventsToday()
    local todayTitles = GetTodayHolidayTitles()
    local out = {}
    for i = 1, #M.CALENDAR_EVENTS do
        local e = M.CALENDAR_EVENTS[i]
        if EventMatchesTodayTitles(e, todayTitles) then
            out[#out + 1] = e
        end
    end
    return out
end

---@param eventKeys string[]|nil
---@return boolean
function M.MatchesWorldEventSelection(eventKeys)
    if not eventKeys or #eventKeys == 0 then
        return #M.GetActiveEventsToday() > 0
    end
    local todayTitles = GetTodayHolidayTitles()
    for i = 1, #eventKeys do
        local def = M.GetEventByKey(eventKeys[i])
        if EventMatchesTodayTitles(def, todayTitles) then return true end
    end
    return false
end
