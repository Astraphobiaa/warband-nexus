#!/usr/bin/env lua
--[[
    Regression test (static): bag changes during the staged bank-open scan are queued, not dropped.

    While bankScanInProgress, ThrottledBagUpdate returned false without recording the bag. OnBagUpdate
    had already stored the new bag hash, so the change counted as handled and was never saved: items
    moved by the auto-deposit or the player during the ~18-frame scan stayed stale until that bag
    changed again. Now the bag is queued in pendingUpdates and finishBankScan flushes the queue.

    Static check of Modules/ItemsCacheService.lua: the full bank-open flow needs most of the client's
    container API, so this pins the two code paths instead of driving them.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local fh = assert(io.open(ROOT .. "/Modules/ItemsCacheService.lua", "rb"))
local src = fh:read("*a")
fh:close()

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local throttled = src:match("ThrottledBagUpdate = function%(bagID%)(.-)\nend\n")
check(throttled ~= nil, "ThrottledBagUpdate found")
local guard = throttled and throttled:match("if bankScanInProgress then(.-)%f[%w]end%f[%W]")
check(guard ~= nil, "bankScanInProgress guard found")
check(guard and guard:find("pendingUpdates%[bagID%]%s*=%s*true") ~= nil,
    "a bag changed during the bank scan is queued in pendingUpdates")

local finish = src:match("local function finishBankScan%(aborted%)(.-)\n    end\n")
check(finish ~= nil, "finishBankScan found")
check(finish and finish:find("ScheduleDeferredBagFlush%(") ~= nil,
    "finishBankScan flushes the queued bags")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Bank scan queue suite failed with " .. failed .. " failure(s).")
end
print("Bank scan queue suite: ALL TESTS PASSED.")
