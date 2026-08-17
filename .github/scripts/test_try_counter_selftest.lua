#!/usr/bin/env lua5.1
--[[
    Runs the addon's OWN probe suite (WarbandNexus:RunTryCounterSelfTest, the /wn tc test command)
    headlessly under the WoW stub.

    That suite covers routes the dedicated test files here do not: object, rare, container, fishing,
    raid, encounter and CHAT_MSG_LOOT. Until now it only ran when a player typed /wn tc test in game,
    so a regression in any of those paths could ship unseen. This makes it a CI gate.

    It reports by printing, so the pass/fail state is parsed out of the captured chat: a "FAILED"
    summary line or any FAIL probe line fails this gate. WARN lines are allowed -- some probes need
    live game state (mount journal, a real instance) that a stub cannot provide, and they
    self-report as warnings rather than failures.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, ns = H.stub, H.WN, H.ns

-- SelfTest is not part of the harness's default load (it is a debug-only satellite).
local fh = assert(io.open("Modules/TryCounterService_SelfTest.lua", "rb"),
    "missing Modules/TryCounterService_SelfTest.lua")
local src = fh:read("*a")
fh:close()
src = src:gsub("^\239\187\191", "")
local chunk, lerr = loadstring(src, "@Modules/TryCounterService_SelfTest.lua")
if not chunk then error("load SelfTest: " .. tostring(lerr), 0) end
chunk("WarbandNexus", ns)

if type(WN.RunTryCounterSelfTest) ~= "function" then
    io.stderr:write("RunTryCounterSelfTest is not defined\n")
    os.exit(1)
end

stub.Reset()
local ok, err = pcall(WN.RunTryCounterSelfTest, WN)
stub.Advance(30)   -- let any probe-scheduled timers finish

if not ok then
    io.stderr:write("RunTryCounterSelfTest raised: " .. tostring(err) .. "\n")
    os.exit(1)
end

local failLines, warnLines, passCount, summary = {}, 0, 0, nil
for i = 1, #stub.chat do
    local line = tostring(stub.chat[i])
    if line:find("[WN-TC-Test] FAIL", 1, true) then failLines[#failLines + 1] = line end
    if line:find("[WN-TC-Test] PASS", 1, true) then passCount = passCount + 1 end
    if line:find("[WN-TC-Test] WARN", 1, true) then warnLines = warnLines + 1 end
    if line:find("passed", 1, true) and line:find("warnings", 1, true) then summary = line end
end

print(("probes passed: %d   warnings: %d   failures: %d   handler/timer errors: %d")
    :format(passCount, warnLines, #failLines, #stub.errors))
if summary then print("suite summary: " .. summary:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local bad = false
for i = 1, #failLines do print("  FAIL " .. failLines[i]); bad = true end
for i = 1, #stub.errors do print("  ERROR " .. tostring(stub.errors[i])); bad = true end
if summary and summary:find("FAILED", 1, true) then bad = true end
if passCount == 0 then
    print("  no probes ran - the suite is not actually executing")
    bad = true
end

if bad then
    io.stderr:write("\ntest_try_counter_selftest: suite did not pass cleanly\n")
    os.exit(1)
end
print("\ntest_try_counter_selftest: addon self-test suite passed")
