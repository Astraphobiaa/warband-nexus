--[[
    Unit test for ResetService: centralized daily and weekly reset system.
]]

-- Environment mocks
local _now = 1728480000 -- Wednesday 12:00:00 UTC (sample epoch)
function GetServerTime() return _now end
function time() return _now end
function GetCurrentRegion() return 3 end -- EU

C_DateAndTime = {
    GetSecondsUntilDailyReset = function() return 3600 end,   -- 1h remaining
    GetSecondsUntilWeeklyReset = function() return 7200 end,  -- 2h remaining
}

GameTime_GetFormattedTime = function(h, m)
    return string.format("%02d:%02d", h, m)
end

SecondsToTime = function(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    return string.format("%d hr %d min", h, m)
end

-- Mock Addon Namespace
local ns = {
    Constants = {
        EVENTS = {
            DAILY_RESET_OCCURRED = "WN_DAILY_RESET_OCCURRED",
            WEEKLY_RESET_OCCURRED = "WN_WEEKLY_RESET_OCCURRED",
            UI_MAIN_REFRESH_REQUESTED = "WN_UI_MAIN_REFRESH_REQUESTED",
        }
    }
}
local messagesFired = {}
local WarbandNexus = {
    db = {
        global = {
            resets = {
                lastDailyResetEpoch = 0,
                lastWeeklyResetEpoch = 0,
            }
        }
    },
    SendMessage = function(self, event, payload)
        table.insert(messagesFired, { event = event, payload = payload })
    end
}
ns.WarbandNexus = WarbandNexus

-- Load ResetService.lua
local f = io.open("Modules/ResetService.lua", "r")
assert(f, "Could not open Modules/ResetService.lua")
local code = f:read("*a")
f:close()

local chunk, err = loadstring(code, "ResetService.lua")
assert(chunk, "Failed to load ResetService.lua: " .. tostring(err))
chunk("WarbandNexus", ns)

local RS = ns.ResetService
assert(RS, "ns.ResetService was not exported")

print("Phase 1: Basic API Calculations")
local secDaily = RS.GetSecondsUntilDailyReset()
assert(secDaily == 3600, "GetSecondsUntilDailyReset failed: " .. tostring(secDaily))
print("  ok   GetSecondsUntilDailyReset = 3600")

local secWeekly = RS.GetSecondsUntilWeeklyReset()
assert(secWeekly == 7200, "GetSecondsUntilWeeklyReset failed: " .. tostring(secWeekly))
print("  ok   GetSecondsUntilWeeklyReset = 7200")

local currDailyStart = RS.GetCurrentDailyResetStartTime()
local expectedDaily = _now + 3600 - 86400
assert(currDailyStart == expectedDaily, "GetCurrentDailyResetStartTime mismatch")
print("  ok   GetCurrentDailyResetStartTime matches expected")

local currWeeklyStart = RS.GetCurrentWeeklyResetStartTime()
local expectedWeekly = _now + 7200 - (7 * 86400)
assert(currWeeklyStart == expectedWeekly, "GetCurrentWeeklyResetStartTime mismatch")
print("  ok   GetCurrentWeeklyResetStartTime matches expected")

print("Phase 2: Has*ResetOccurred Evaluation")
-- Stale timestamp before current cycle
local staleDailyTimestamp = currDailyStart - 100
local freshDailyTimestamp = currDailyStart + 100
assert(RS.HasDailyResetOccurred(staleDailyTimestamp) == true, "Stale daily timestamp should report reset occurred")
assert(RS.HasDailyResetOccurred(freshDailyTimestamp) == false, "Fresh daily timestamp should NOT report reset occurred")
assert(RS.HasDailyResetOccurred(nil) == true, "nil timestamp should report reset occurred")
print("  ok   HasDailyResetOccurred correctly discriminates timestamps")

local staleWeeklyTimestamp = currWeeklyStart - 100
local freshWeeklyTimestamp = currWeeklyStart + 100
assert(RS.HasWeeklyResetOccurred(staleWeeklyTimestamp) == true, "Stale weekly timestamp should report reset occurred")
assert(RS.HasWeeklyResetOccurred(freshWeeklyTimestamp) == false, "Fresh weekly timestamp should NOT report reset occurred")
print("  ok   HasWeeklyResetOccurred correctly discriminates timestamps")

print("Phase 3: Native Blizzard Time Formatting")
local rem = RS.FormatTimeRemaining(3660)
assert(rem:find("hr") or rem:find("min"), "FormatTimeRemaining failed: " .. tostring(rem))
print("  ok   FormatTimeRemaining = " .. rem)

local clockStr = RS.FormatResetClockTime(_now, false)
assert(clockStr == "13:20", "FormatResetClockTime mismatch: " .. tostring(clockStr))
print("  ok   FormatResetClockTime = " .. clockStr)

print("Phase 4: Centralized CheckAndTriggerResets Event Dispatch")
RS:CheckAndTriggerResets("test_check")
assert(WarbandNexus.db.global.resets.lastDailyResetEpoch == currDailyStart, "lastDailyResetEpoch not updated")
assert(WarbandNexus.db.global.resets.lastWeeklyResetEpoch == currWeeklyStart, "lastWeeklyResetEpoch not updated")

local foundDailyMsg = false
local foundWeeklyMsg = false
local foundUIRefresh = false
for _, msg in ipairs(messagesFired) do
    if msg.event == "WN_DAILY_RESET_OCCURRED" then foundDailyMsg = true end
    if msg.event == "WN_WEEKLY_RESET_OCCURRED" then foundWeeklyMsg = true end
    if msg.event == "WN_UI_MAIN_REFRESH_REQUESTED" then foundUIRefresh = true end
end
assert(foundDailyMsg, "WN_DAILY_RESET_OCCURRED not fired")
assert(foundWeeklyMsg, "WN_WEEKLY_RESET_OCCURRED not fired")
assert(foundUIRefresh, "WN_UI_MAIN_REFRESH_REQUESTED not fired")
print("  ok   CheckAndTriggerResets dispatched both reset events and UI refresh")

print("Phase 5: Subsequent Check Without Boundary Cross Does NOT Re-Fire")
messagesFired = {}
RS:CheckAndTriggerResets("test_check_duplicate")
assert(#messagesFired == 0, "Duplicate check fired events when boundaries did not cross: count=" .. tostring(#messagesFired))
print("  ok   No false positive events fired")

print("Phase 6: Backward Compatibility Shims on WarbandNexus")
assert(WarbandNexus:HasDailyResetOccurredSince(staleDailyTimestamp) == true, "Shim HasDailyResetOccurredSince failed")
assert(WarbandNexus:HasWeeklyResetOccurred(staleWeeklyTimestamp) == true, "Shim HasWeeklyResetOccurred failed")
assert(WarbandNexus:HasWeeklyResetOccurredSince(staleWeeklyTimestamp) == true, "Shim HasWeeklyResetOccurredSince failed")
assert(WarbandNexus:HasWeeklyResetOccurredForTimestamp(staleWeeklyTimestamp) == true, "Shim HasWeeklyResetOccurredForTimestamp failed")
assert(WarbandNexus:GetWeeklyResetTime() == _now + 7200, "Shim GetWeeklyResetTime failed")
print("  ok   All backward-compatibility shims on WarbandNexus pass")

print("\nALL RESET SERVICE TESTS PASSED!")
