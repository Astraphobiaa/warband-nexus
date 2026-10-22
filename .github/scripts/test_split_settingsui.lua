#!/usr/bin/env lua5.1
--[[
    Settings UI file split (2026-10-22), checked against the REAL shipped files.

      1. SettingsUI.lua stays below the project's 4000-line split rule and well below Lua 5.1's
         200-locals-per-chunk ceiling (< 120 top-level local lines).
      2. Every panel satellite (SettingsUI_<Panel>.lua) is listed in WarbandNexus.toc right after
         SettingsUI.lua: the panel bodies read ns.SettingsUI._H, which SettingsUI.lua builds at load.
      3. Each panel satellite asserts the module table, so a wrong TOC order fails loudly at load
         instead of as a nil index inside a settings click.
      4. Loading the files in TOC order under wow_stub.lua leaves every moved panel builder
         reachable as ns.SettingsUI.Append<Panel>Panel, and BuildSettings calls each one.

    Run from the repo root:  lua5.1 .github/scripts/test_split_settingsui.lua
]]

local ROOT = os.getenv("WN_ROOT") or "."
local SCRIPT_DIR = ".github/scripts"
local MAIN = "Modules/UI/SettingsUI.lua"
local MAX_TOP_LEVEL_LOCALS = 120
local MAX_MAIN_LINES = 4000
local PANELS = { "General", "Access", "Filters", "Notifications", "Appearance", "Advanced" }

local failures, total = 0, 0
local function check(cond, msg)
    total = total + 1
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

-- ---------------------------------------------------------------------------------------------
print("phase 1: main file headroom")
local main = assert(ReadFile(MAIN), "missing " .. MAIN)
local topLocals, lines = 0, 0
for line in (main .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + 1
    if line:find("^local ") then topLocals = topLocals + 1 end
end
check(topLocals < MAX_TOP_LEVEL_LOCALS,
    MAIN .. " top-level local lines < " .. MAX_TOP_LEVEL_LOCALS .. " (got " .. topLocals .. ")")
check(lines < MAX_MAIN_LINES, MAIN .. " lines < " .. MAX_MAIN_LINES .. " (got " .. lines .. ")")
for i = 1, #PANELS do
    local fn = "Append" .. PANELS[i] .. "Panel"
    check(main:find("ns%.SettingsUI%." .. fn .. "%(panelCtx%)") ~= nil, "BuildSettings calls ns.SettingsUI." .. fn)
end

-- ---------------------------------------------------------------------------------------------
print("phase 2: panel satellites listed in the TOC right after SettingsUI.lua")
local toc = assert(ReadFile("WarbandNexus.toc"), "missing WarbandNexus.toc")
local tocFiles, tocPos = {}, {}
for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:find("^#") then
        tocFiles[#tocFiles + 1] = line
        tocPos[line] = #tocFiles
    end
end
local mainPos = tocPos["Modules\\UI\\SettingsUI.lua"]
check(mainPos ~= nil, "SettingsUI.lua listed in the TOC")
mainPos = mainPos or 0
for i = 1, #PANELS do
    local rel = "Modules\\UI\\SettingsUI_" .. PANELS[i] .. ".lua"
    local pos = tocPos[rel]
    check(pos ~= nil and pos > mainPos, rel .. " listed after SettingsUI.lua")
    -- No unrelated file between SettingsUI.lua and its panels: nothing can consume the panels at
    -- load before they exist, and the block stays readable as one unit.
    local contiguous = pos ~= nil
    if pos then
        for k = mainPos + 1, pos - 1 do
            if not tocFiles[k]:find("^Modules\\UI\\SettingsUI_%w+%.lua$") then contiguous = false end
        end
    end
    check(contiguous, rel .. " sits in the SettingsUI block (no other file in between)")
end

-- ---------------------------------------------------------------------------------------------
print("phase 3: each panel satellite guards its module table")
for i = 1, #PANELS do
    local rel = "Modules/UI/SettingsUI_" .. PANELS[i] .. ".lua"
    local src = ReadFile(rel)
    check(src ~= nil, rel .. " exists")
    src = src or ""
    check(src:find("assert%(M and M%._H,") ~= nil, rel .. " asserts ns.SettingsUI._H")
    local _, defs = src:gsub("function M%.Append" .. PANELS[i] .. "Panel%(", "")
    check(defs == 1, rel .. " defines Append" .. PANELS[i] .. "Panel exactly once (got " .. defs .. ")")
    check(not main:find("function [%w_.]*Append" .. PANELS[i] .. "Panel%("),
        "Append" .. PANELS[i] .. "Panel is not also left in " .. MAIN)
end

-- ---------------------------------------------------------------------------------------------
print("phase 4: loading the real files in TOC order")
dofile(SCRIPT_DIR .. "/wow_stub.lua")
_G.LibStub = _G.LibStub or function() return nil end

local function NewNs()
    return { WarbandNexus = { db = { profile = {} } }, FontManager = {}, L = {} }
end

local function LoadFile(ns, rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return false, "missing file: " .. rel end
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then return false, "load " .. rel .. ": " .. tostring(err) end
    return pcall(chunk, "WarbandNexus", ns)
end

local ns = NewNs()
local order = {}
for i = 1, #tocFiles do
    local f = tocFiles[i]
    if f == "Modules\\Constants.lua" or f:find("^Modules\\UI\\SettingsUI[%w_]*%.lua$") then
        order[#order + 1] = (f:gsub("\\", "/"))
    end
end
check(#order >= 2, "TOC yields Constants + SettingsUI files to load (" .. #order .. ")")
local loadedAll = true
for i = 1, #order do
    local ok, err = LoadFile(ns, order[i])
    if not ok then
        loadedAll = false
        print("       " .. tostring(err))
    end
end
check(loadedAll, "every SettingsUI file loads in TOC order without error")
local SUI = ns.SettingsUI or {}
check(type(SUI._H) == "table", "SettingsUI.lua exports the shared helper table _H")
check(type(SUI._H) == "table" and type(SUI._H.themeTextRefs) == "table",
    "theme warning / AA hint refs live in one shared table (_H.themeTextRefs)")
for i = 1, #PANELS do
    local fn = "Append" .. PANELS[i] .. "Panel"
    check(type(SUI[fn]) == "function", "ns.SettingsUI." .. fn .. " reachable after load")
end
check(type(ns.WarbandNexus.DrawSettingsTab) == "function", "WarbandNexus:DrawSettingsTab still defined")
check(type(ns.WarbandNexus.ShowSettings) == "function", "WarbandNexus:ShowSettings still defined")

-- A satellite loaded before SettingsUI.lua must fail at load with a TOC hint.
local okEarly, errEarly = LoadFile(NewNs(), "Modules/UI/SettingsUI_General.lua")
check(not okEarly and tostring(errEarly):find("check the TOC") ~= nil,
    "SettingsUI_General.lua loaded before SettingsUI.lua fails with a TOC hint")

print(string.format("\n%d/%d checks passed", total - failures, total))
if failures > 0 then
    print("Total failures: " .. failures)
    os.exit(1)
end
print("Total failures: 0")
