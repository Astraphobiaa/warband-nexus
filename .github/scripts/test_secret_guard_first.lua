#!/usr/bin/env lua
--[[
    Regression test: these helpers check issecretvalue before any compare / truth test on their input.

    2026-10-22 runtime audit: the guard sat on the line after the compare (the same-line lint in
    test_secret_check_order.lua cannot see that), so a secret value reached `value ~= ""`,
    `name == nil or name == ""` / `not nm` first, which errors in Midnight:
      - ProfessionService ResolveAPIString (secret profession / spell names),
      - CurrencyCacheService IsUsableCurrencyName / IsTrackerMetaCurrencyName,
      - PvECacheService gilded stash parse: tostring(left) .. tostring(right) on tooltip text.
    Static order check plus the plain-value results, which must not change.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end
local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return src
end
local function Body(src, header)
    local s = src:find(header, 1, true)
    if not s then return nil end
    local e = src:find("\nend\n", s, true)
    return e and src:sub(s, e + 4) or nil
end
-- First statement that touches `var` must be the issecretvalue guard.
local function GuardFirst(body, var)
    if not body then return false end
    local guardAt = body:find("issecretvalue(" .. var .. ")", 1, true)
    local patterns = { "not " .. var .. "%f[^%w_]", var .. " ==", var .. " ~=", "type%(" .. var .. "%)", "tostring%(" .. var .. "%)" }
    for i = 1, #patterns do
        local at = body:find(patterns[i])
        if at and (not guardAt or at < guardAt) then return false end
    end
    return guardAt ~= nil
end

local prof = ReadFile("Modules/ProfessionService.lua")
local resolveBody = Body(prof, "local function ResolveAPIString(value)")
check(GuardFirst(resolveBody, "value"), "ResolveAPIString: issecretvalue(value) before any test on value")

local cur = ReadFile("Modules/CurrencyCacheService.lua")
local usableBody = Body(cur, "local function IsUsableCurrencyName(name)")
local metaBody = Body(cur, "local function IsTrackerMetaCurrencyName(nm)")
check(GuardFirst(usableBody, "name"), "IsUsableCurrencyName: guard first")
check(GuardFirst(metaBody, "nm"), "IsTrackerMetaCurrencyName: guard first")

local pve = ReadFile("Modules/PvECacheService.lua")
local concatAt = pve:find("ParseGildedStashFraction(tostring(left) .. \" \" .. tostring(right))", 1, true)
local window = concatAt and pve:sub(math.max(1, concatAt - 260), concatAt) or ""
check(window:find("issecretvalue(left)", 1, true) ~= nil and window:find("issecretvalue(right)", 1, true) ~= nil,
    "gilded stash parse: left/right secret-checked before tostring / concatenation")

-- Plain values: same results as before.
local secrets = {}
local env = setmetatable({ issecretvalue = function(v) return secrets[v] == true end }, { __index = _G })
local function Load(body, name)
    local chunk = assert(loadstring(body .. "\nreturn " .. name))
    setfenv(chunk, env)
    return chunk()
end
local IsUsable = Load(usableBody, "IsUsableCurrencyName")
check(IsUsable(nil) == false and IsUsable("") == false and IsUsable("Valorstones") == true, "IsUsableCurrencyName plain results")
local secretName = {}
secrets[secretName] = true
check(IsUsable(secretName) == false, "IsUsableCurrencyName: secret -> false")
local IsMeta = Load(metaBody, "IsTrackerMetaCurrencyName")
check(IsMeta(nil) == false and IsMeta("") == false and IsMeta("Weekly Cap Tracker") == true and IsMeta("Valorstones") == false,
    "IsTrackerMetaCurrencyName plain results")
check(IsMeta(secretName) == false, "IsTrackerMetaCurrencyName: secret -> false")
local Resolve = Load("local _resolverFS = nil\n" .. resolveBody, "ResolveAPIString")
check(Resolve(nil) == nil and Resolve("Alchemy") == "Alchemy" and Resolve("") == nil and Resolve(12) == "12",
    "ResolveAPIString plain results")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Secret guard first suite failed with " .. failed .. " failure(s).")
end
print("Secret guard first suite: ALL TESTS PASSED.")
