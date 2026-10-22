#!/usr/bin/env lua5.1
--[[
    Try Counter login cost and file split (2026-10-22), driven through the REAL shipped files.

      1. TryCounterService.lua stays well below Lua 5.1's 200-locals-per-function ceiling (the main
         chunk is one IIFE) and below the project's 4000-line split rule.
      2. Every TryCounterService_*.lua satellite is listed in WarbandNexus.toc, in an order where its
         load-time reads resolve, and the harness loads the same files in the same order.
      3. A function moved out of the main file is not also left behind in it (the later file would
         silently win and the two copies would drift).
      4. InitializeTryCounter no longer rebuilds the merged Statistics seed index inside the login
         frame. It is marked dirty there and built one frame later; every reader goes through the
         lazy EnsureMergedStatisticSeedIndex, and the per-character seed still rebuilds it at T+1s.

    Run from the repo root:  lua5.1 .github/scripts/test_trycounter_init_split.lua
]]

local ROOT = os.getenv("WN_ROOT") or "."
local MAIN = "Modules/TryCounterService.lua"
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
    return s
end

-- The harness is the behavioural suites' loader; phase 3 checks its file order, phase 4 reuses it.
local hsrc = assert(ReadFile(".github/scripts/wow_addon_harness.lua"), "missing .github/scripts/wow_addon_harness.lua")

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

-- ---------------------------------------------------------------------------------------------
print("phase 2: satellites listed in the TOC in a valid order")
local toc = assert(ReadFile("WarbandNexus.toc"), "missing WarbandNexus.toc")
local tocOrder, tocPos = {}, {}
for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
    local name = line:gsub("\r$", ""):match("^Modules\\(TryCounterService[%w_]*)%.lua%s*$")
    if name then
        tocOrder[#tocOrder + 1] = name
        tocPos[name] = #tocOrder
    end
end
local mainPos = tocPos.TryCounterService
check(mainPos ~= nil, "main file listed in the TOC")

local onDisk = {}
local p = io.popen("ls '" .. ROOT .. "/Modules/' 2>/dev/null")
if p then
    for f in p:lines() do
        local name = f:match("^(TryCounterService_[%w_]+)%.lua$")
        if name then onDisk[#onDisk + 1] = name end
    end
    p:close()
end
check(#onDisk > 0, "listed satellites on disk (" .. #onDisk .. ")")
for i = 1, #onDisk do
    local name = onDisk[i]
    local pos = tocPos[name]
    check(pos ~= nil, name .. ".lua is listed in the TOC")
    local src = ReadFile("Modules/" .. name .. ".lua") or ""
    if pos and mainPos then
        if src:find("local Fns = TC.Fns", 1, true) then
            -- TC.Fns is published at the end of the main file.
            check(pos > mainPos, name .. " (reads TC.Fns at load) loads after the main file")
        else
            -- Shared / Events / Process: the main file reads their tables at load.
            check(pos < mainPos, name .. " (read by the main file at load) loads before it")
        end
    end
end
if tocPos.TryCounterService_SelfTest then
    check(tocPos.TryCounterService_SelfTest == #tocOrder, "SelfTest is the last Try Counter file")
end

-- The behavioural suites load the slice through the harness; it must follow the TOC exactly.
local harnessOrder = {}
for name in hsrc:gmatch('LoadFile%("Modules/(TryCounterService[%w_]*)%.lua"%)') do
    harnessOrder[#harnessOrder + 1] = name
end
local expect = {}
for i = 1, #tocOrder do
    if tocOrder[i] ~= "TryCounterService_SelfTest" then expect[#expect + 1] = tocOrder[i] end
end
check(table.concat(harnessOrder, ",") == table.concat(expect, ","),
    "harness loads the TOC's Try Counter files in TOC order (harness: " .. table.concat(harnessOrder, ",") .. ")")

-- ---------------------------------------------------------------------------------------------
print("phase 3: no function is defined in two Try Counter files")
local function DefinedNames(src)
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local n = line:match("^function (Fns%.[%w_]+)%(") or line:match("^(Fns%.[%w_]+) = function")
            or line:match("^function (WarbandNexus[:.][%w_]+)%(")
        if n then out[#out + 1] = (n:gsub("WarbandNexus%.", "WarbandNexus:")) end
    end
    return out
end
local owner, dupes = {}, {}
for i = 1, #tocOrder do
    local rel = "Modules/" .. tocOrder[i] .. ".lua"
    local names = DefinedNames(ReadFile(rel) or "")
    for j = 1, #names do
        local n = names[j]
        if owner[n] and owner[n] ~= rel then dupes[#dupes + 1] = n .. " (" .. owner[n] .. " + " .. rel .. ")" end
        owner[n] = owner[n] or rel
    end
end
check(#dupes == 0, "each Fns.* / WarbandNexus:* has one definition"
    .. (#dupes > 0 and (": " .. table.concat(dupes, ", ", 1, math.min(#dupes, 6)) .. (#dupes > 6 and ", ..." or "")) or ""))

-- ---------------------------------------------------------------------------------------------
print("phase 4: InitializeTryCounter defers the statistic seed index by one frame")
-- The shared harness initializes on load; take its loader without that tail so this test owns init.
local cut = hsrc:find("\nWN:InitializeTryCounter()", 1, true)
assert(cut, "harness layout changed: WN:InitializeTryCounter() not found")
local tailStart = hsrc:find("\nreturn {", cut, true)
assert(tailStart, "harness layout changed: return table not found")
local loader = assert(loadstring(hsrc:sub(1, cut) .. hsrc:sub(tailStart + 1), "@harness-no-init"))
local loaded, H = pcall(loader)
check(loaded, "Try Counter slice loads in harness order" .. (loaded and "" or (" (" .. tostring(H) .. ")")))
if loaded then
    local stub, WN, Fns, RT = H.stub, H.WN, H.Fns, H.RT

    local rebuilds = 0
    local realRebuild = Fns.RebuildMergedStatisticSeedIndex
    Fns.RebuildMergedStatisticSeedIndex = function(...)
        rebuilds = rebuilds + 1
        return realRebuild(...)
    end

    WN:InitializeTryCounter()
    check(Fns.IsTryCounterReady() == true, "try counter is ready right after the init call")
    check(next(RT.npcIDToEncounterID) ~= nil, "reverse indices built synchronously (loot / encounter handlers need them)")
    check(next(RT.chatLootItemToNpc) ~= nil, "CHAT_MSG_LOOT item map built synchronously")
    check(rebuilds == 0, "seed index NOT rebuilt inside the init frame (got " .. rebuilds .. ")")
    check(RT.statState.indexDirty == true, "seed index left dirty for the lazy reader path")

    stub.Advance(0)
    check(rebuilds == 1, "deferred frame builds the seed index once (got " .. rebuilds .. ")")
    check(RT.statState.indexDirty == false and #RT.mergedStatSeedGroupList > 0,
        "seed index populated after the deferred frame (" .. #RT.mergedStatSeedGroupList .. " buckets)")

    stub.Advance(20)
    check(rebuilds >= 2, "per-character seed still rebuilds it after init (got " .. rebuilds .. ")")
    check(#stub.errors == 0, "no errors in timers (" .. tostring(stub.errors[1]) .. ")")
end

print(string.format("\nTotal Checks: %d | Failures: %d", total, failures))
if failures > 0 then os.exit(1) end
