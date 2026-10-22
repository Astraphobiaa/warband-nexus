#!/usr/bin/env lua
--[[
    Regression test (static): only the chosen language stays in memory after OnInitialize.

    Every locale file loads into ns.LOCALES (any language is selectable on any client). After the
    chosen one is merged over the enUS base, nothing reads the registry again (a language switch
    reloads), but all 12 tables (~2.4k keys each) stayed referenced for the whole session.
    OnInitialize now drops ns.LOCALES after the merge; this pins that, and that no module reads the
    registry at run time.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return src
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local core = ReadFile("Core.lua")
local init = core:match("function WarbandNexus:OnInitialize%(%)(.-)\nend\n")
check(init ~= nil, "OnInitialize found")
local mergeAt = init and init:find("L[key] = value", 1, true)
local releaseAt = init and init:find("ns.LOCALES = nil", 1, true)
check(mergeAt ~= nil and releaseAt ~= nil and mergeAt < releaseAt, "ns.LOCALES is released after the merge")

local p = io.popen('find "' .. ROOT .. '/Modules" -name "*.lua" 2>/dev/null')
local readers = {}
for path in p:lines() do
    local rel = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    local src = ReadFile(rel):gsub("%-%-[^\n]*", "")
    if src:find("ns%.LOCALES") then readers[#readers + 1] = rel end
end
p:close()
check(#readers == 0, "no module reads ns.LOCALES at run time" .. (#readers > 0 and (" (" .. table.concat(readers, ", ") .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Locale release suite failed with " .. failed .. " failure(s).")
end
print("Locale release suite: ALL TESTS PASSED.")
