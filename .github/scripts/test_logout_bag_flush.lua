#!/usr/bin/env lua
--[[
    Regression test (static): the PLAYER_LOGOUT bag flush never live-reads a container.

    FlushItemsCacheOnLogout wrote every pending bag through ThrottledBagUpdate -> UpdateSingleBag ->
    ScanBag. A bag whose slot data was not cached from its BAG_UPDATE fell back to a live
    C_Container read during teardown, and that read replaced the stored bag. Now the logout flush
    passes cacheOnly: a bag is written only from the slot data captured at its BAG_UPDATE, otherwise
    the stored bag is kept and the login scan re-reads it.

    Static check of Modules/ItemsCacheService.lua: the flush needs the compression libraries and most
    of the container API, so this pins the code path instead of driving it.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local fh = assert(io.open(ROOT .. "/Modules/ItemsCacheService.lua", "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local flush = src:match("function WarbandNexus:FlushItemsCacheOnLogout%(%)(.-)\nend\n")
check(flush ~= nil, "FlushItemsCacheOnLogout found")
check(flush and flush:find("ThrottledBagUpdate%(%s*bagID%s*,%s*true%s*%)") ~= nil,
    "pending bags are flushed with cacheOnly = true")
check(flush and flush:find("ProcessPendingBagUpdates", 1, true) == nil,
    "the logout flush does not go through ProcessPendingBagUpdates (no cacheOnly there)")

local throttled = src:match("ThrottledBagUpdate = function%(bagID, cacheOnly%)(.-)\nend\n")
check(throttled ~= nil, "ThrottledBagUpdate takes cacheOnly")
local passes = 0
if throttled then
    for _ in throttled:gmatch("UpdateSingleBag%(charKey, bagID, cacheOnly%)") do passes = passes + 1 end
end
check(passes == 2, "ThrottledBagUpdate passes cacheOnly to both UpdateSingleBag calls")

local update = src:match("function WarbandNexus:UpdateSingleBag%(charKey, bagID, cacheOnly%)(.-)\nend\n")
check(update ~= nil, "UpdateSingleBag takes cacheOnly")
check(update and update:find("ScanBag%(bagID, cacheOnly%)") ~= nil, "UpdateSingleBag passes cacheOnly to ScanBag")
check(update and update:find("if hadSecretSlots or not newBagItems then", 1, true) ~= nil,
    "no scan result keeps the stored bag")

local scan = src:match("local function ScanBag%(bagID, cacheOnly%)(.-)\nend\n")
check(scan ~= nil, "ScanBag takes cacheOnly")
local cacheOnlyAt = scan and scan:find("if cacheOnly then return nil", 1, true)
local liveAt = scan and scan:find("C_Container.GetContainerNumSlots", 1, true)
check(cacheOnlyAt and liveAt and cacheOnlyAt < liveAt,
    "cacheOnly returns before the live C_Container fallback")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Logout bag flush suite failed with " .. failed .. " failure(s).")
end
print("Logout bag flush suite: ALL TESTS PASSED.")
