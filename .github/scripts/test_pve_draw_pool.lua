#!/usr/bin/env lua
--[[
    Regression test (static): the PvE tab's row pool is one shared table and re-used rows are reset.

    PvEUI.lua kept its draw pool in a file-local `_pveDrawPool` while PvEUI_CharList.lua created its
    own `ns.PvEUI._pveDrawPool`, so rows acquired by CharList were never the ones BodyPaint painted
    and re-used. A re-used row also kept its last expand state, the detail populate key / width
    cache (old expanded cards survived a data change), the text and tooltip of a column that has no
    value this paint, and column dividers after the columns went to zero.
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

local pve = ReadFile("Modules/UI/PvEUI.lua")
local charList = ReadFile("Modules/UI/PvEUI_CharList.lua")
local body = ReadFile("Modules/UI/PvEUI_BodyPaint.lua")

check(pve:find("ns.PvEUI._pveDrawPool = _pveDrawPool", 1, true) ~= nil, "PvEUI exports its draw pool")
local getPool = charList:match("local function getPool%(%)(.-)\nend\n")
check(getPool and getPool:find("PvEUI._pveDrawPool", 1, true) ~= nil and getPool:find("{ charRows = {}, inline = {} }", 1, true) == nil,
    "CharList re-uses the shared pool instead of creating its own")
local acquire = charList:match("local function PvEAcquireCharRowFrames%(rowHost, charKey%)(.-)\nend\n")
check(acquire and acquire:find("header:ClearAllPoints()", 1, true) ~= nil, "a re-used row comes back unanchored")
check(body:find("charHeader._wnCollExpanded = charExpanded and true or false", 1, true) ~= nil, "expand state re-synced on re-use")
check(body:find("charDetailContent._wnPopulateKey = nil", 1, true) ~= nil, "detail populate key reset on a full paint")
check(body:find("local staleCell = (not val) and rowCells and rowCells[col.key]", 1, true) ~= nil, "valueless column cell cleared")
check(body:find("#pveColumnDividerXs > 0 or charHeader._wnGridColDividers", 1, true) ~= nil, "dividers cleared when columns go to zero")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE draw pool suite failed with " .. failed .. " failure(s).")
end
print("PvE draw pool suite: ALL TESTS PASSED.")
