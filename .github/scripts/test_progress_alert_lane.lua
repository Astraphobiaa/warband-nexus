#!/usr/bin/env lua
--[[
    Regression test (static): the Traveler's Log alert lane hooks the alert system 12.1.5 has.

    The WN criteria-progress lane wraps a Blizzard alert system's AddAlert to show Traveler's Log
    progress as a WN toast. It looked for ProgressAlertSystem / MonthlyActivitiesAlertSystem /
    PerksActivitiesAlertSystem, none of which exist in 12.1.5 (wow-ui-source live,
    Blizzard_FrameXML/Mainline/AlertFrameSystems.lua defines MonthlyActivityAlertSystem, whose
    AddAlert takes a perksActivityID), so the lane never engaged. The list now names the real system,
    and the payload resolver turns the activity ID into a payload via
    C_PerksActivities.GetPerksActivityInfo (activityName).
]]

local ROOT = os.getenv("WN_ROOT") or "."
local fh = assert(io.open(ROOT .. "/Modules/NotificationManager.lua", "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local listBody = src:match("local PROGRESS_ALERT_SYSTEM_GLOBALS = {(.-)}")
check(listBody ~= nil, "alert system list defined")
check(listBody and listBody:find('"MonthlyActivityAlertSystem"', 1, true) ~= nil, "list names MonthlyActivityAlertSystem")
check(listBody and listBody:find("MonthlyActivitiesAlertSystem", 1, true) == nil and listBody:find("PerksActivitiesAlertSystem", 1, true) == nil,
    "names that do not exist in 12.1.5 are gone")
local defAt = src:find("local PROGRESS_ALERT_SYSTEM_GLOBALS = {", 1, true)
local useAt = src:find("#PROGRESS_ALERT_SYSTEM_GLOBALS", 1, true)
check(defAt and useAt and defAt < useAt, "list defined before its first use")
local resolver = src:match("local function ResolveProgressAlertPayload%(a1, a2, %.%.%.%)(.-)\nend\n")
check(resolver and resolver:find("C_PerksActivities.GetPerksActivityInfo", 1, true) ~= nil, "numeric activity id resolved through the perks API")
check(resolver and resolver:find('if type(a1) == "number" and not (issecretvalue and issecretvalue(a1))', 1, true) ~= nil,
    "activity id secret-checked before use")

-- Behaviour: a perks activity id shows the activity name, not its description.
if resolver then
    local chunk = assert(loadstring("local function ResolveProgressAlertPayload(a1, a2, ...)" .. resolver
        .. "\nend\nreturn ResolveProgressAlertPayload"))
    setfenv(chunk, {
        type = type, pcall = pcall, select = select, issecretvalue = function() return false end,
        C_PerksActivities = { GetPerksActivityInfo = function(id)
            return { ID = id, activityName = "Complete a delve", description = "Finish any delve on any tier." }
        end },
    })
    local payload = chunk()(4242)
    check(payload and payload.text == "Complete a delve", "perks payload text is activityName (got " .. tostring(payload and payload.text) .. ")")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Progress alert lane suite failed with " .. failed .. " failure(s).")
end
print("Progress alert lane suite: ALL TESTS PASSED.")
