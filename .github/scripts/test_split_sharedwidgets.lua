#!/usr/bin/env lua5.1
--[[
    SharedWidgets.lua split (2026-10-22): five feature groups moved verbatim into satellites.

      1. Modules/UI/SharedWidgets.lua stays below the 4000-line split rule and under 120
         top-level local lines (Lua 5.1 allows 200 per chunk).
      2. Every new satellite is listed in WarbandNexus.toc after every file that defines an ns
         field it reads at load time (SharedWidgets.lua included) and before every other file that
         reads one of its ns.UI_* exports (many files capture ns.UI_* at load time).
      3. Each satellite asserts the main file loaded first and asserts its own exports at the end.
      4. A function moved out of the main file is not also left behind in it.
      5. Loading each satellite under wow_stub.lua defines every ns.* name it declares.

    Run from the repo root:  lua5.1 .github/scripts/test_split_sharedwidgets.lua
]]

local ROOT = os.getenv("WN_ROOT") or "."
local MAIN = "Modules/UI/SharedWidgets.lua"
local SATELLITES = {
    "Modules/UI/SharedWidgets_PlansLayout.lua",
    "Modules/UI/SharedWidgets_TabLayout.lua",
    "Modules/UI/SharedWidgets_TitleCard.lua",
    "Modules/UI/SharedWidgets_TryCountPopup.lua",
    "Modules/UI/SharedWidgets_StateCards.lua",
}
local MAX_TOP_LEVEL_LOCALS = 120
local MAX_MAIN_LINES = 4000

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
    return (s:gsub("^\239\187\191", ""))
end

local function Lines(src)
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = (line:gsub("\r$", "")) end
    return out
end

--- ns names a file defines at column 0 (`function ns.X(` / `ns.X =`), first segment only.
local function DefinedNsNames(src)
    local names = {}
    for _, line in ipairs(Lines(src)) do
        local n = line:match("^function%s+ns%.([%w_]+)%s*%(") or line:match("^ns%.([%w_]+)%s*=[^=]")
        if n then names[n] = true end
    end
    return names
end

-- ---------------------------------------------------------------------------------------------
print("phase 1: main file headroom")
local main = assert(ReadFile(MAIN), "missing " .. MAIN)
local mainLines = Lines(main)
local topLocals = 0
for i = 1, #mainLines do
    if mainLines[i]:find("^local ") then topLocals = topLocals + 1 end
end
check(topLocals < MAX_TOP_LEVEL_LOCALS,
    MAIN .. " top-level local lines < " .. MAX_TOP_LEVEL_LOCALS .. " (got " .. topLocals .. ")")
check(#mainLines < MAX_MAIN_LINES, MAIN .. " lines < " .. MAX_MAIN_LINES .. " (got " .. #mainLines .. ")")

-- ---------------------------------------------------------------------------------------------
print("phase 2: satellites listed in the TOC in a valid order")
local toc = assert(ReadFile("WarbandNexus.toc"), "missing WarbandNexus.toc")
local tocOrder, tocPos = {}, {}
for _, line in ipairs(Lines(toc)) do
    if line:match("%.lua%s*$") and not line:match("^%s*#") then
        local rel = line:gsub("\\", "/"):gsub("%s+$", "")
        tocOrder[#tocOrder + 1] = rel
        tocPos[rel] = #tocOrder
    end
end
local isSatellite = {}
for i = 1, #SATELLITES do isSatellite[SATELLITES[i]] = true end

local tocSrc = {}
local function TocSource(rel)
    if tocSrc[rel] == nil then tocSrc[rel] = ReadFile(rel) or false end
    return tocSrc[rel] or nil
end

check(tocPos[MAIN] ~= nil, MAIN .. " is listed in the TOC")
for i = 1, #SATELLITES do
    local sat = SATELLITES[i]
    local src = ReadFile(sat)
    local pos = tocPos[sat]
    check(src ~= nil, sat .. " exists")
    check(pos ~= nil, sat .. " is listed in the TOC")
    if src and pos and tocPos[MAIN] then
        check(pos > tocPos[MAIN], sat .. " loads after " .. MAIN)

        -- Every ns field read at load time (outside column-0 function bodies) is defined by an
        -- earlier TOC file, or earlier in the satellite itself.
        local own, inFn, inBlock, reads = {}, false, false, {}
        for _, raw in ipairs(Lines(src)) do
            local line = raw:gsub('"[^"]*"', '""'):gsub("%-%-[^%[].*$", "")
            if inBlock then
                if raw:find("%]%]") then inBlock = false end
            elseif raw:match("^%-%-%[%[") then
                inBlock = not raw:find("%]%]")
            elseif not inFn and (line:match("^local%s+function%s") or line:match("^function%s")
                or line:match("^[%w_.]+%s*=%s*function%s*%(")) then
                inFn = not line:match("%send%s*$")
                local n = line:match("^function%s+ns%.([%w_]+)") or line:match("^ns%.([%w_]+)%s*=")
                if n then own[n] = true end
            elseif inFn then
                if line:match("^end") then inFn = false end
            elseif not line:match("^%s*%-%-") then
                local lhs = line:match("^ns%.([%w_]+)%s*=[^=]")
                for field in line:gsub("^ns%.[%w_]+%s*=", ""):gmatch("ns%.([%w_]+)") do
                    if not own[field] and not reads[field] then
                        reads[field] = true
                        reads[#reads + 1] = field
                    end
                end
                if lhs then own[lhs] = true end
            end
        end
        for k = 1, #reads do
            local field = reads[k]
            do
                local definer
                for j = 1, #tocOrder do
                    local s = TocSource(tocOrder[j])
                    if s and DefinedNsNames(s)[field] then definer = j; break end
                end
                check(definer ~= nil and definer < pos,
                    sat .. " reads ns." .. field .. " at load, defined earlier (" .. tostring(definer and tocOrder[definer]) .. ")")
            end
        end

        -- Every later reader of an export loads after the satellite.
        local exports = DefinedNsNames(src)
        local late = {}
        for j = tocPos[MAIN] + 1, #tocOrder do
            local rel = tocOrder[j]
            if rel ~= sat and not isSatellite[rel] then
                local s = TocSource(rel)
                if s then
                    for name in pairs(exports) do
                        if s:find("ns%." .. name .. "[^%w_]") and j < pos then
                            late[#late + 1] = rel .. " reads ns." .. name
                        end
                    end
                end
            end
        end
        check(#late == 0, sat .. " loads before every reader of its exports" .. (late[1] and (" (" .. late[1] .. ")") or ""))
    end
end

-- ---------------------------------------------------------------------------------------------
print("phase 3: satellites assert load order and exports")
for i = 1, #SATELLITES do
    local sat = SATELLITES[i]
    local src = ReadFile(sat) or ""
    check(src:find('assert%(ns%.UI and ns%.UI_ApplyVisuals and ns%.UI_CreateCard, "[%w_]+: load after SharedWidgets%.lua"%)') ~= nil,
        sat .. " asserts SharedWidgets.lua loaded first")
    check(src:find('assert%([^\n]*"[%w_]+: exports missing"%)%s*$') ~= nil, sat .. " asserts its exports at the end")
end

-- ---------------------------------------------------------------------------------------------
print("phase 4: moved functions are not left behind in the main file")
local mainDefs = DefinedNsNames(main)
for i = 1, #SATELLITES do
    local src = ReadFile(SATELLITES[i]) or ""
    local dupes = {}
    for name in pairs(DefinedNsNames(src)) do
        if mainDefs[name] then dupes[#dupes + 1] = name end
    end
    table.sort(dupes)
    check(#dupes == 0, SATELLITES[i] .. " exports are defined only there" .. (dupes[1] and (" (main still has ns." .. dupes[1] .. ")") or ""))
end

-- ---------------------------------------------------------------------------------------------
print("phase 5: satellites load under wow_stub.lua and define their exports")
dofile(".github/scripts/wow_stub.lua")
local NOOP = function() end
local ns = {
    UI = { Factory = {} },
    UI_ApplyVisuals = NOOP,
    UI_CreateCard = NOOP,
    UI_ApplyStandardTitleCardChrome = NOOP,
    UI_ApplyStandardCardElevatedChrome = NOOP,
    UI_IsLightMode = function() return false end,
    UI_IsClassicMode = function() return false end,
    UI_SnapRuleTexture = NOOP,
    UI_GetIconAtlas = function() return nil end,
    UI_SPACING = {},
    UI_LAYOUT = {},
    UITheme = { ThemeAPI = {}, COLORS = {}, GetColors = function() return {} end },
    FontManager = { GetFontRole = function() return "body" end },
    WarbandNexus = {},
    GetPixelScale = function() return 1 end,
}
for i = 1, #SATELLITES do
    local sat = SATELLITES[i]
    local src = ReadFile(sat)
    local chunk, err = src and loadstring(src, "@" .. sat)
    local ok, rerr = false, err or "missing"
    if chunk then ok, rerr = pcall(chunk, "WarbandNexus", ns) end
    check(ok, sat .. " loads" .. (ok and "" or (": " .. tostring(rerr))))
    if ok then
        local missing = {}
        for name in pairs(DefinedNsNames(src)) do
            if ns[name] == nil then missing[#missing + 1] = name end
        end
        check(#missing == 0, sat .. " defines every declared ns export" .. (missing[1] and (" (nil: " .. missing[1] .. ")") or ""))
    end
end
for _, name in ipairs({
    "UI_PlansCardGridLayout", "UI_CreateSubTabBar", "UI_GetMainTabLayoutMetrics", "UI_GetCharKey",
    "UI_CreateStandardTabTitleCard", "UI_GetTabIcon", "UI_ShowTryCountPopup", "UI_CreateSection",
    "UI_CreateLoadingStateCard", "UI_CreateResetTimer", "UI_CreateDisabledModuleCard",
}) do
    check(type(ns[name]) == "function", "ns." .. name .. " is reachable")
end

print(string.format("\nTotal: %d checks, %d failed", total, failures))
if failures > 0 then os.exit(1) end
