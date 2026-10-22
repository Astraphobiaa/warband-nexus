#!/usr/bin/env lua
--[[
    Regression test (static): tabs build their section chrome through SectionPool.

    Each tab below used to create its section wraps / bodies / collapsible headers with
    Factory:CreateContainer / CreateCollapsibleHeader on every redraw and park the previous ones in
    the recycle bin forever. For every adopted draw function this checks that:
      - every CreateCollapsibleHeader call gets SectionPool.HeaderOpts and is remembered;
      - no section wrap / body is created with Factory:CreateContainer directly;
      - teardown discards through SectionPool (no raw SetParent(recycleBin)).
    The pool itself is driven by test_section_pool.lua.
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
local function count(s, pat)
    local n = 0
    for _ in s:gmatch(pat) do n = n + 1 end
    return n
end

-- { label, file, function header pattern }
local ADOPTED = {
    { "Currency", "Modules/UI/CurrencyUI.lua", "function WarbandNexus:DrawCurrencyList%(container, width%)" },
}

for i = 1, #ADOPTED do
    local label, rel, head = ADOPTED[i][1], ADOPTED[i][2], ADOPTED[i][3]
    local src = ReadFile(rel)
    local s = src:find(head)
    check(s ~= nil, label .. ": draw function found")
    if s then
        local body = src:sub(s, (src:find("\nfunction ", s + 1) or #src))
        local headers = count(body, "CreateCollapsibleHeader%(")
        check(headers > 0 and headers == count(body, "SP%.HeaderOpts%("),
            label .. ": every collapsible header goes through SectionPool.HeaderOpts (" .. headers .. ")")
        check(count(body, "SP%.Remember%(") == headers, label .. ": every pooled header is remembered")
        check(count(body, "CreateContainer%(") == 0, label .. ": no direct Factory:CreateContainer for section chrome")
        check(body:find("SetParent%(recycleBin") == nil, label .. ": no raw recycle-bin parking in teardown")
        check(body:find("SP.BeginPass(", 1, true) ~= nil, label .. ": teardown starts a SectionPool pass")
    end
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Section pool adoption suite failed with " .. failed .. " failure(s).")
end
print("Section pool adoption suite: ALL TESTS PASSED.")
