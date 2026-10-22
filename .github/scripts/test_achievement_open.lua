#!/usr/bin/env lua
--[[
    Regression test (static): achievement rows open the journal through a path that exists.

    CollectionsUI_Model's achievement row click called OpenAchievementFrameToAchievement, which does
    not exist in 12.1.5 FrameXML, so the click silently did nothing. The toast click already had a
    working path (load Blizzard_AchievementUI, show the frame, AchievementFrame_SelectAchievement —
    Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua:2659 on wow-ui-source live); it is now
    ns.UI_OpenAchievementInJournal and both callers use it.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n"):gsub("%-%-[^\n]*", "")
    fh:close()
    return src
end
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local nm = ReadFile("Modules/NotificationManager.lua")
local helper = nm:match("function ns%.UI_OpenAchievementInJournal%(achievementID%)(.-)\nend\n")
check(helper ~= nil, "shared opener defined")
check(helper and helper:find("AchievementFrame_SelectAchievement", 1, true) ~= nil
    and helper:find('SafeLoadAddOn("Blizzard_AchievementUI")', 1, true) ~= nil, "opener loads the journal and selects")
local toast = nm:match("local function NM_OpenToastTarget%(toast%)(.-)\nend\n")
check(toast and toast:find("ns.UI_OpenAchievementInJournal(achievementID)", 1, true) ~= nil, "toast click uses the opener")

local model = ReadFile("Modules/UI/CollectionsUI_Model.lua")
check(model:find("ns.UI_OpenAchievementInJournal(ach.id)", 1, true) ~= nil, "Collections achievement row uses the opener")
check(model:find("OpenAchievementFrameToAchievement", 1, true) == nil, "no call to the removed FrameXML function")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Achievement open suite failed with " .. failed .. " failure(s).")
end
print("Achievement open suite: ALL TESTS PASSED.")
