#!/usr/bin/env lua
--[[
    Regression test: no shipped module writes a global (or its setfenv environment) by accident.

    2026-10-22: a bytecode scan found writes that were missing a `local`:
      - real _G writes: `_` in ItemsUI_StorageDraw / SettingsUI_Notifications, and three
        UI_Create*StateCard functions defined without `local`;
      - setfenv-environment writes in the VaultButton_* files and ProfessionsUI_DrawTab: FontString
        temporaries, `right`, and two that were bugs — GetVaultColumnNextProgress kept nextThresh /
        nextProg across calls (another character's threshold leaked in), the table rebuild re-saved a
        stale position, and DrawTab's cachedRowWidth never reached ProfessionsUI's local.
    This test lists every global / environment write (GSET under LuaJIT, SETGLOBAL under Lua 5.1)
    in Modules/**/*.lua and Core.lua and fails on any that is not allow-listed.

    It also lists free reads of lowercase names (GGET / GETGLOBAL). WoW's own globals in that shape
    are the Lua base library plus a few FrameXML helpers (LOWER_READS); anything else is a local
    that was never declared, e.g. VaultButton_SavedInstancesUI read an unset `rowH` (nil).
]]

local ROOT = os.getenv("WN_ROOT") or "."
local ALLOWED = {
    -- name = true for intentional globals (none today; Core publishes WarbandNexus via _G.WarbandNexus).
}

local hits, scanned = {}, 0

-- Lowercase globals the WoW client (or Lua 5.1) provides. `os` / `debug` are read only behind a
-- nil guard (ResetService, ChatIntegrationService).
local LOWER_READS = {}
for name in ([[_G assert coroutine date debug debugprofilestart debugprofilestop debugstack error format
    geterrorhandler getmetatable hooksecurefunc ipairs issecretvalue math next os pairs pcall print rawget
    rawset select setfenv setmetatable string strlower strsplit strupper table time tinsert tonumber
    tostring type unpack wipe xpcall]]):gmatch("%S+") do LOWER_READS[name] = true end

local function CheckRead(path, line, name)
    if type(name) == "string" and name:match("^[a-z_]") and not LOWER_READS[name] then
        hits[#hits + 1] = string.format("%s:%s reads undeclared `%s`", path, tostring(line), name)
    end
end

local files = {}
local p = io.popen('find "' .. ROOT .. '/Modules" -name "*.lua" 2>/dev/null; echo "' .. ROOT .. '/Core.lua"')
for line in p:lines() do files[#files + 1] = line end
p:close()

local ok, jutil = pcall(require, "jit.util")
if ok then
    local bcnames = require("jit.vmdef").bcnames
    local function opname(op) return (bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", "")) end
    for _, path in ipairs(files) do
        local fh = io.open(path, "rb")
        local src = fh:read("*a"):gsub("^\239\187\191", "")
        fh:close()
        local fn = assert(loadstring(src, "@" .. path))
        scanned = scanned + 1
        local seen = {}
        local function walk(f)
            if seen[f] then return end
            seen[f] = true
            local pc = 1
            while true do
                local ins = jutil.funcbc(f, pc)
                if not ins then break end
                local op = opname(bit.band(ins, 0xff))
                if op == "GGET" then
                    CheckRead(path, jutil.funcinfo(f, pc).currentline, jutil.funck(f, -bit.rshift(ins, 16) - 1))
                end
                if op == "GSET" then
                    local name = jutil.funck(f, -bit.rshift(ins, 16) - 1)
                    if not ALLOWED[name] then
                        hits[#hits + 1] = string.format("%s:%s writes `%s`", path, tostring(jutil.funcinfo(f, pc).currentline), tostring(name))
                    end
                end
                pc = pc + 1
            end
            local i = -1
            while true do
                local k = jutil.funck(f, i)
                if k == nil then break end
                if type(k) == "proto" then walk(k) end
                i = i - 1
            end
        end
        walk(fn)
    end
else
    local luac = nil
    for _, cand in ipairs({ "luac5.1", "luac" }) do
        local h = io.popen("command -v " .. cand .. " 2>/dev/null")
        local out = h:read("*a")
        h:close()
        if out and out ~= "" then luac = cand break end
    end
    if not luac then
        print("SKIP: neither LuaJIT (jit.util) nor luac5.1 available to list global writes")
        return
    end
    for _, path in ipairs(files) do
        scanned = scanned + 1
        local h = io.popen(luac .. ' -p -l "' .. path .. '" 2>&1')
        for line in h:lines() do
            local ln, name = line:match("%[(%d+)%]%s+SETGLOBAL%s+.-;%s*([%w_]+)")
            if name and not ALLOWED[name] then
                hits[#hits + 1] = string.format("%s:%s writes `%s`", path, ln, name)
            end
            local rln, rname = line:match("%[(%d+)%]%s+GETGLOBAL%s+.-;%s*([%w_]+)")
            if rname then CheckRead(path, rln, rname) end
        end
        h:close()
    end
end

for i = 1, #hits do print("  FAIL " .. hits[i]) end
print(string.format("\nTotal Checks: %d files | Failures: %d", scanned, #hits))
if #hits > 0 then
    error("No global writes suite failed with " .. #hits .. " failure(s).")
end
if scanned < 100 then
    error("No global writes suite scanned too few files (" .. scanned .. "); the file walk is broken.")
end
print("No global writes suite: ALL TESTS PASSED.")
