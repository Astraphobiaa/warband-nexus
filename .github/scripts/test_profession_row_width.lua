#!/usr/bin/env lua
--[[
    Regression test (behaviour): a new Professions body width re-scales the column layout.

    DrawTab passes the body width through ProfUI.SetCachedRowWidth. ResolveProfessionColumnLayout
    caches the scaled widths until the layout is marked dirty, so a width change that did not
    invalidate it kept the old column scale after the window (or another tab's paint) changed the
    body width. The setter now invalidates the layout when the width changes, and only then.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local fh = assert(io.open(ROOT .. "/Modules/UI/ProfessionsUI.lua", "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local fnSrc = src:match("(function ProfUI%.SetCachedRowWidth%(w%).-\nend)\n")
check(fnSrc ~= nil, "ProfUI.SetCachedRowWidth defined")
if fnSrc then
    local chunk = assert(loadstring("local cachedRowWidth\nlocal ProfUI, PUI = ...\n" .. fnSrc
        .. "\nreturn function() return cachedRowWidth end"))
    local invalidations = 0
    local ProfUI = {}
    local PUI = { InvalidateProfessionColumnLayout = function() invalidations = invalidations + 1 end }
    local getWidth = chunk(ProfUI, PUI)

    ProfUI.SetCachedRowWidth(900)
    check(getWidth() == 900, "width stored")
    check(invalidations == 1, "first width invalidates the column layout")
    ProfUI.SetCachedRowWidth(900)
    check(invalidations == 1, "same width keeps the cached layout")
    ProfUI.SetCachedRowWidth(1200)
    check(getWidth() == 1200 and invalidations == 2, "changed width invalidates the column layout")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profession row width suite failed with " .. failed .. " failure(s).")
end
print("Profession row width suite: ALL TESTS PASSED.")
