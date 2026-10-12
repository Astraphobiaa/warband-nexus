--[[
    Warband Nexus — ResetService
    Authoritative, centralized daily and weekly reset tracking and event dispatcher.

    - Canonical clock: GetServerTime() + C_DateAndTime (immune to OS clock drift and timezones).
    - Single source of truth in SavedVariables: db.global.resets.lastDailyResetEpoch, lastWeeklyResetEpoch.
    - Native Blizzard formatting: SecondsToTime() and GameTime_GetFormattedTime().
    - Precise event dispatching: WN_DAILY_RESET_OCCURRED, WN_WEEKLY_RESET_OCCURRED.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local ResetService = {}
ns.ResetService = ResetService

local DAY_SECONDS = 86400
local WEEK_SECONDS = 7 * DAY_SECONDS

local dailyTimer = nil
local weeklyTimer = nil

---Get exact seconds remaining until next daily reset directly from Blizzard server API.
---@return number
function ResetService.GetSecondsUntilDailyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok, secs = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and type(secs) == "number" and secs >= 0 then
            return secs
        end
    end
    -- Fallback: 24h cycle from server time
    local now = (GetServerTime and GetServerTime()) or time()
    return DAY_SECONDS - (now % DAY_SECONDS)
end

---Get exact seconds remaining until next weekly reset directly from Blizzard server API.
---@return number
function ResetService.GetSecondsUntilWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(secs) == "number" and secs >= 0 then
            return secs
        end
    end

    -- Region-based UTC fallback
    local now = (GetServerTime and GetServerTime()) or time()
    local region = (GetCurrentRegion and GetCurrentRegion()) or 1
    local resetDay = (region == 3) and 4 or 3       -- EU=Wed(4), US=Tue(3)
    local resetHour = (region == 3) and 4 or 15     -- EU=04:00 UTC, US=15:00 UTC
    
    local dateFn = date or (os and os.date)
    if not dateFn then return 0 end
    local d = dateFn("!*t", now)
    if not d then return 0 end
    local secIntoDay = (d.hour * 3600) + (d.min * 60) + d.sec
    local daysUntil = (resetDay - d.wday + 7) % 7
    if daysUntil == 0 and secIntoDay >= (resetHour * 3600) then
        daysUntil = 7
    end
    local targetSec = (daysUntil * DAY_SECONDS) + (resetHour * 3600) - secIntoDay
    return math.max(0, targetSec)
end

---Get epoch timestamp (server UTC seconds) when current daily reset cycle began.
---@return number
function ResetService.GetCurrentDailyResetStartTime()
    local now = (GetServerTime and GetServerTime()) or time()
    return now + ResetService.GetSecondsUntilDailyReset() - DAY_SECONDS
end

---Get epoch timestamp (server UTC seconds) when current weekly reset cycle began.
---@return number
function ResetService.GetCurrentWeeklyResetStartTime()
    local now = (GetServerTime and GetServerTime()) or time()
    return now + ResetService.GetSecondsUntilWeeklyReset() - WEEK_SECONDS
end

---Get epoch timestamp (server UTC seconds) of next daily reset.
---@return number
function ResetService.GetNextDailyResetTime()
    local now = (GetServerTime and GetServerTime()) or time()
    return now + ResetService.GetSecondsUntilDailyReset()
end

---Get epoch timestamp (server UTC seconds) of next weekly reset.
---@return number
function ResetService.GetNextWeeklyResetTime()
    local now = (GetServerTime and GetServerTime()) or time()
    return now + ResetService.GetSecondsUntilWeeklyReset()
end

---Check if a daily reset occurred since the given timestamp.
---@param timestamp number|nil
---@return boolean
function ResetService.HasDailyResetOccurred(timestamp)
    if not timestamp or timestamp <= 0 then return true end
    return timestamp < ResetService.GetCurrentDailyResetStartTime()
end

---Check if a weekly reset occurred since the given timestamp.
---@param timestamp number|nil
---@return boolean
function ResetService.HasWeeklyResetOccurred(timestamp)
    if not timestamp or timestamp <= 0 then return true end
    return timestamp < ResetService.GetCurrentWeeklyResetStartTime()
end

---Format seconds remaining using native Blizzard localized time if available.
---@param seconds number
---@return string
function ResetService.FormatTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return "Now"
    end
    if SecondsToTime then
        return SecondsToTime(seconds, false, false, 2, false)
    end
    local days = math.floor(seconds / DAY_SECONDS)
    local hours = math.floor((seconds % DAY_SECONDS) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", math.max(1, minutes))
    end
end

---Format a reset epoch into a localized clock string (e.g. "06:00" or "6:00 AM").
---@param epoch number
---@param useLocalTime boolean|nil If true (default), formats in player's local timezone. If false, formats in UTC/realm.
---@return string
function ResetService.FormatResetClockTime(epoch, useLocalTime)
    if not epoch or epoch <= 0 then return "" end
    if useLocalTime == nil then useLocalTime = true end
    local dateFn = date or (os and os.date)
    if not dateFn then return "" end
    local d = useLocalTime and dateFn("*t", epoch) or dateFn("!*t", epoch)
    if not d then return "" end

    local useMilitary = (GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime"))
    if useMilitary then
        return string.format(TIME_TWENTYFOURHOURS or "%02d:%02d", d.hour, d.min)
    else
        local hour = d.hour
        local isPM = hour >= 12
        local displayHour = hour % 12
        if displayHour == 0 then displayHour = 12 end
        local fmt = isPM and (TIME_TWELVEHOURPM or "%d:%02d PM") or (TIME_TWELVEHOURAM or "%d:%02d AM")
        return string.format(fmt, displayHour, d.min)
    end
end

---Central check and trigger function. Compares stored DB flags against current reset epochs.
---Dispatches WN_DAILY_RESET_OCCURRED and WN_WEEKLY_RESET_OCCURRED when boundaries cross.
---@param source string|nil Diagnostic source tag
function ResetService:CheckAndTriggerResets(source)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return end
    
    if not WarbandNexus.db.global.resets then
        WarbandNexus.db.global.resets = {
            lastDailyResetEpoch = 0,
            lastWeeklyResetEpoch = 0,
        }
    end
    local resets = WarbandNexus.db.global.resets
    local events = ns.Constants and ns.Constants.EVENTS

    local currDailyStart = ResetService.GetCurrentDailyResetStartTime()
    local currWeeklyStart = ResetService.GetCurrentWeeklyResetStartTime()

    local dailyFired = false
    local weeklyFired = false

    -- DAILY RESET CHECK
    if (resets.lastDailyResetEpoch or 0) < currDailyStart then
        resets.lastDailyResetEpoch = currDailyStart
        dailyFired = true
        if events and events.DAILY_RESET_OCCURRED and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(events.DAILY_RESET_OCCURRED, {
                resetEpoch = currDailyStart,
                source = source or "check",
            })
        end
    end

    -- WEEKLY RESET CHECK
    if (resets.lastWeeklyResetEpoch or 0) < currWeeklyStart then
        resets.lastWeeklyResetEpoch = currWeeklyStart
        weeklyFired = true
        if events and events.WEEKLY_RESET_OCCURRED and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(events.WEEKLY_RESET_OCCURRED, {
                resetEpoch = currWeeklyStart,
                source = source or "check",
            })
        end
    end

    -- If either fired, request debounced UI refresh
    if (dailyFired or weeklyFired) and events and events.UI_MAIN_REFRESH_REQUESTED and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(events.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
    end

    -- ARM EXACT-SECOND TIMERS FOR NEXT BOUNDARIES
    self:ArmTimers()
end

---Arm C_Timer timers to trigger exactly 1 second after the next daily and weekly resets.
function ResetService:ArmTimers()
    if not (C_Timer and C_Timer.After) then return end

    if dailyTimer then
        dailyTimer:Cancel()
        dailyTimer = nil
    end
    if weeklyTimer then
        weeklyTimer:Cancel()
        weeklyTimer = nil
    end

    local secDaily = ResetService.GetSecondsUntilDailyReset()
    local secWeekly = ResetService.GetSecondsUntilWeeklyReset()

    if secDaily and secDaily >= 0 and secDaily <= DAY_SECONDS then
        dailyTimer = C_Timer.NewTimer(secDaily + 1, function()
            dailyTimer = nil
            ResetService:CheckAndTriggerResets("timer_daily")
        end)
    end

    if secWeekly and secWeekly >= 0 and secWeekly <= WEEK_SECONDS then
        weeklyTimer = C_Timer.NewTimer(secWeekly + 1, function()
            weeklyTimer = nil
            ResetService:CheckAndTriggerResets("timer_weekly")
        end)
    end
end

-- ============================================================================
-- GLOBAL & NAMESPACE SHIMS (BACKWARD COMPATIBILITY)
-- ============================================================================

ns.GetCurrentWeeklyResetStartTime = ResetService.GetCurrentWeeklyResetStartTime
ns.GetCurrentDailyResetStartTime = ResetService.GetCurrentDailyResetStartTime

function WarbandNexus:HasWeeklyResetOccurred(timestamp)
    return ResetService.HasWeeklyResetOccurred(timestamp)
end

function WarbandNexus:HasWeeklyResetOccurredSince(timestamp)
    return ResetService.HasWeeklyResetOccurred(timestamp)
end

function WarbandNexus:HasWeeklyResetOccurredForTimestamp(timestamp)
    return ResetService.HasWeeklyResetOccurred(timestamp)
end

function WarbandNexus:HasDailyResetOccurredSince(timestamp)
    return ResetService.HasDailyResetOccurred(timestamp)
end

function WarbandNexus:GetWeeklyResetTime()
    return ResetService.GetNextWeeklyResetTime()
end
