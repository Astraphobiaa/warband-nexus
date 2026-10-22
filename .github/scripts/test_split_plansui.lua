#!/usr/bin/env lua
--[[
    Regression test: PlansUI.lua split (Weekly Progress view -> PlansUI_WeeklyProgress.lua,
    custom / weekly vault plan dialogs + custom plan storage -> PlansUI_Dialogs.lua).

    Static: the main file stays under the 4000-line / 120 top-level-local budget, both satellites are
    listed in the TOC after the shared widgets they alias at load and before PlansUI.lua (their only
    consumer: it binds its file-local helpers into them through Install), and PlansUI.lua asserts each
    satellite's module table so a mis-ordered TOC fails loudly.
    Runtime: under wow_stub.lua the satellites + main load, every moved public method is on
    WarbandNexus, and the moved code reaches the helpers PlansUI.lua bound through Install.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
end

local MAIN = "Modules/UI/PlansUI.lua"
local SATELLITES = {
    { file = "Modules/UI/PlansUI_WeeklyProgress.lua", var = "WeeklyProgress", ns = "PlansUI_WeeklyProgress" },
    { file = "Modules/UI/PlansUI_Dialogs.lua", var = "Dialogs", ns = "PlansUI_Dialogs" },
}

-- ---------- static: size budget ----------
print("Static: size budget and TOC order")
local main = ReadFile(MAIN) or ""
local lineCount, topLocals = 0, 0
for line in (main .. "\n"):gmatch("([^\n]*)\n") do
    lineCount = lineCount + 1
    if line:match("^local%s") then topLocals = topLocals + 1 end
end
check(lineCount < 4000, "PlansUI.lua under 4000 lines (" .. lineCount .. ")")
check(topLocals < 120, "PlansUI.lua under 120 top-level locals (" .. topLocals .. ")")

-- ---------- static: TOC order ----------
local toc = ReadFile("WarbandNexus.toc") or ""
local tocIndex, n = {}, 0
for line in toc:gmatch("[^\n]+") do
    n = n + 1
    local rel = line:gsub("\\", "/"):gsub("%s+$", "")
    if not tocIndex[rel] then tocIndex[rel] = n end
end
local mainIdx = tocIndex[MAIN]
local needs = { "Modules/Constants.lua", "Modules/UI/SharedWidgets.lua", "Modules/UI/WindowFactory.lua" }
for s = 1, #SATELLITES do
    local sat = SATELLITES[s]
    local satIdx = tocIndex[sat.file]
    check(satIdx ~= nil, sat.file .. " listed in the TOC")
    check(satIdx and mainIdx and satIdx < mainIdx, sat.file .. " loads before PlansUI.lua (its Install consumer)")
    for i = 1, #needs do
        local idx = tocIndex[needs[i]]
        check(satIdx and idx and idx < satIdx, sat.file .. " loads after " .. needs[i])
    end
end

-- ---------- static: module tables asserted ----------
for s = 1, #SATELLITES do
    local sat = SATELLITES[s]
    local satSrc = ReadFile(sat.file) or ""
    check(satSrc:find("ns." .. sat.ns .. " = ", 1, true) ~= nil, sat.file .. " publishes ns." .. sat.ns)
    local name = sat.file:match("([^/]+)$")
    check(main:find("local " .. sat.var .. " = ns." .. sat.ns .. "\nassert(" .. sat.var .. " and " .. sat.var
        .. ".Install, \"load " .. name .. " before PlansUI.lua\")", 1, true) ~= nil,
        "PlansUI.lua asserts ns." .. sat.ns .. " before binding it")
end

-- ---------- runtime: load satellites + main under the stub ----------
print("Runtime: moved methods reachable and wired")
local ns = {}
local printed, sent = {}, {}
local WarbandNexus = {
    db = { global = { characters = {}, plans = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) sent[#sent + 1] = { msg, payload } end,
    RegisterMessage = function() end,
    Print = function(_, msg) printed[#printed + 1] = msg end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.L = setmetatable({}, { __index = function() return nil end })
ns.UI = { Factory = {} }
ns.UI_FormatTextNumbers = function(s) return s end
-- PlansUI.lua's PlanGreenHex reads this; the Dialogs satellite only sees it through Install.
ns.PLAN_UI_COLORS = { completed = "|cTESTGRN" }

local function LoadFile(rel)
    local src = ReadFile(rel)
    if not src then return false, "missing file: " .. rel end
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then return false, err end
    return pcall(chunk, "WarbandNexus", ns)
end

local files = { "Modules/Constants.lua", "Modules/UI/PlansUI_Browse.lua" }
for s = 1, #SATELLITES do files[#files + 1] = SATELLITES[s].file end
files[#files + 1] = MAIN
for i = 1, #files do
    local ok, err = LoadFile(files[i])
    check(ok, "loads " .. files[i] .. (ok and "" or (" -- " .. tostring(err))))
end

local moved = {
    "DrawDailyTasksView", "ShowCustomPlanDialog", "SaveCustomPlan", "GetCustomPlans", "CompleteCustomPlan",
    "RemoveCustomPlan", "ShowWeeklyPlanDialog", "CloseAllPlanDialogs",
}
for i = 1, #moved do
    check(type(WarbandNexus[moved[i]]) == "function", "WarbandNexus:" .. moved[i] .. " reachable")
end
check(type(WarbandNexus.DrawPlansTab) == "function" and type(WarbandNexus.DrawActivePlans) == "function",
    "PlansUI.lua keeps DrawPlansTab / DrawActivePlans")

-- Custom plan storage round trip through the moved code (uses E + the Install-bound PlanGreenHex).
if type(WarbandNexus.SaveCustomPlan) == "function" and type(WarbandNexus.CompleteCustomPlan) == "function" then
    local ok, err = pcall(function()
        WarbandNexus:SaveCustomPlan("Goal", "desc", "none", 1, false)
        local list = WarbandNexus.db.global.customPlans
        local id = list and list[1] and list[1].id
        check(id ~= nil and sent[#sent] and sent[#sent][1] == "WN_PLANS_UPDATED", "SaveCustomPlan stores the plan and emits WN_PLANS_UPDATED")
        check(WarbandNexus:CompleteCustomPlan(id) == true, "CompleteCustomPlan finds the stored plan")
        check(printed[#printed] and printed[#printed]:find("|cTESTGRN", 1, true) ~= nil,
            "CompleteCustomPlan reaches PlansUI.lua's PlanGreenHex through Install")
        WarbandNexus:RemoveCustomPlan(id)
        check(#WarbandNexus:GetCustomPlans() == 0, "RemoveCustomPlan / GetCustomPlans round trip")
    end)
    check(ok, "custom plan storage runs" .. (ok and "" or (" -- " .. tostring(err))))
else
    check(false, "custom plan storage methods present")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
