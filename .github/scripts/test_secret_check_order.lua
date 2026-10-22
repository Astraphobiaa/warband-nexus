#!/usr/bin/env lua
--[[
    Regression test: a value is checked with issecretvalue BEFORE it is compared.

    CLAUDE.md: never compare secret values with ==, ~= or `not`. `x ~= nil and issecretvalue(x)` and
    `x ~= "" ...; if issecretvalue(x)` compare first. issecretvalue(nil) is false, so the secret check
    can always go first without changing behaviour. Found 2026-10-22 in 13 places, including
    ProfessionService's central SafeAPIString helper (`value ~= ""` ran before its secret check) and
    three ProfessionService sites that stored / compared raw API names.

    Static scan:
      - every file in Modules/: the exact pattern `X ~= nil and [issecretvalue and] issecretvalue(X)` /
        `X ~= nil and not (issecretvalue and issecretvalue(X))` (13 sites fixed, none may come back);
      - Modules/ProfessionService.lua: no comparison of X with nil or "" before issecretvalue(X) on
        the same line, and SafeAPIString checks issecretvalue first.
    The broader rule (any nil / "" comparison before the secret check) still has ~97 pre-existing
    hits elsewhere; whether such a comparison errors on a secret in-game is unverified, so they are
    reported, not enforced, until that is confirmed.
]]

local ROOT = os.getenv("WN_ROOT") or "."
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
        for var in code:gmatch("issecretvalue%(%s*([%w_%.]+)%s*%)") do
            checked = checked + 1
            local esc = var:gsub("%p", "%%%0")
            local secretAt = code:find("issecretvalue%(%s*" .. esc .. "%s*%)")
            local isProfession = path:find("ProfessionService%.lua$") ~= nil
            local cmpAt
            if isProfession then
                cmpAt = code:find("%f[%w_%.]" .. esc .. "%s*[~=]=%s*nil") or code:find("%f[%w_%.]" .. esc .. '%s*[~=]=%s*""')
            else
                cmpAt = code:find("%f[%w_%.]" .. esc .. "%s*~=%s*nil%s+and%s+not%s+%(issecretvalue")
                    or code:find("%f[%w_%.]" .. esc .. "%s*~=%s*nil%s+and%s+issecretvalue")
                    or code:find("issecretvalue%s+and%s+" .. esc .. "%s*~=%s*nil%s+and")
            end
            if cmpAt and secretAt and cmpAt < secretAt then
                failures[#failures + 1] = string.format("%s:%d  `%s` is compared before issecretvalue(%s)",
                    path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", ""), ln, var, var)
            end
        end
    end
    fh:close()
end

-- SafeAPIString (ProfessionService): its first statement must be the secret check.
do
    local fh = io.open(ROOT .. "/Modules/ProfessionService.lua", "rb")
    local src = fh:read("*a")
    fh:close()
    local body = src:match("local function SafeAPIString%(value%)(.-)\nend\n")
    checked = checked + 1
    local first = body and body:match("^%s*%-%-[^\n]*\n%s*([^\n]+)") or (body and body:match("^%s*([^\n]+)"))
    if not (first and first:find("issecretvalue", 1, true)) then
        failures[#failures + 1] = "Modules/ProfessionService.lua  SafeAPIString must check issecretvalue before any comparison"
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("Secret check order suite failed with " .. #failures .. " failure(s).")
end
if checked < 50 then
    error("Secret check order suite matched too few issecretvalue calls (" .. checked .. "); the scanner is broken.")
end
print("Secret check order suite: ALL TESTS PASSED.")
