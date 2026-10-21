#!/usr/bin/env lua
--[[
    Regression test: no `or <fallback>` after helpers that return 0 instead of nil.

    GearService's GetEffectiveIlvl / GetItemQuality return 0 (never nil) when item info is not cached,
    so `GetEffectiveIlvl(link) or slotEntry.itemLevel` never used the stored value: equipped slots
    were saved with item level 0 and quality 0 at login and in the logout flush. A fallback for these
    helpers must test the value (`if v <= 0 then ...`), not use `or`. `or 0` (no-op) and the ternary
    `cond and F(x) or nil` are allowed.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local ZERO_SENTINEL = { "GetEffectiveIlvl", "GetItemQuality", "Gear_GetEffectiveIlvl" }

local p = io.popen('find "' .. ROOT .. '/Modules" -name "*.lua" 2>/dev/null')
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()

local checked, failures = 0, {}
for _, path in ipairs(files) do
    local fh = io.open(path, "rb")
    local ln = 0
    for line in fh:lines() do
        ln = ln + 1
        local code = line:gsub("%-%-.*$", "")
        for _, fn in ipairs(ZERO_SENTINEL) do
            for after in code:gmatch("%f[%w_]" .. fn .. "%s*%b()%s*or%s+([^%s%)]+)") do
                checked = checked + 1
                -- `or 0` is a no-op and `cond and F(x) or nil` is a ternary, not a fallback.
                if after ~= "0" and after ~= "nil" then
                    failures[#failures + 1] = string.format("%s:%d  %s(...) or %s: %s returns 0, never nil",
                        path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", ""), ln, fn, after, fn)
                end
            end
        end
    end
    fh:close()
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("Zero-sentinel fallback suite failed with " .. #failures .. " failure(s).")
end
print("Zero-sentinel fallback suite: ALL TESTS PASSED.")
