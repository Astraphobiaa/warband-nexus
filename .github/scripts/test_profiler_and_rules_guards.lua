#!/usr/bin/env lua
--[[
    Regression test: two small runtime guards (2026-10-22).

      1. Profiler:Wrap / Profiler:RunAsyncSlice packed `{ pcall(func, ...) }`, removed the status with
         table.remove and returned unpack(results). A table with a nil hole has an undefined length, so
         a wrapped function returning `nil, x` came back with no values at all once profiling was on.
         Now the count comes from select("#", ...) and unpack(results, 2, n).
      2. WarbandNexus:GetItemCollectionType walked pairs(CollectionRules), which also holds
         UnobtainableFilters (no CheckIfItemID): any item no rule claimed raised "attempt to call nil".

    Loads the shipped Modules/Profiler.lua and Modules/CollectionRules.lua under wow_stub.lua.
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local ns = {}
local WarbandNexus = {
    db = { global = {}, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function pack(...) return { n = select("#", ...), ... } end

print("Phase 1: Profiler keeps every return value, nils included")
do
    LoadFile("Modules/Profiler.lua")
    local P = assert(ns.Profiler, "Profiler not exported")
    P.enabled = true
    local function nilThenValue() return nil, 2 end
    local function valueNilValue() return 1, nil, 3 end
    local r = pack(P:Wrap("test.wrap", nilThenValue))
    assert_eq(r.n, 2, "Wrap: two values for `return nil, 2`")
    assert_eq(r[2], 2, "Wrap: second value kept after a nil")
    r = pack(P:Wrap("test.wrap3", valueNilValue))
    assert_eq(r.n, 3, "Wrap: three values for `return 1, nil, 3`")
    assert_eq(r[3], 3, "Wrap: third value kept after a nil")
    r = pack(P:RunAsyncSlice("test", "async", nilThenValue))
    assert_eq(r.n, 2, "RunAsyncSlice: two values for `return nil, 2`")
    assert_eq(r[2], 2, "RunAsyncSlice: second value kept after a nil")
    local ok, err = pcall(P.Wrap, P, "test.err", function() error("boom", 0) end)
    assert_eq(ok, false, "Wrap: an error still propagates")
    assert_eq(err, "boom", "Wrap: the original error value propagates")
    P.enabled = false
end

print("Phase 2: GetItemCollectionType skips non-rule entries")
do
    C_Item.GetItemSpell = function() return nil end
    C_ToyBox.GetToyInfo = function() return nil end
    C_PetJournal.GetPetInfoByItemID = function() return nil end
    C_TransmogCollection.GetItemInfo = function() return nil end
    C_TransmogCollection.GetIllusions = function() return {} end
    LoadFile("Modules/CollectionRules.lua")
    local ok, res = pcall(WarbandNexus.GetItemCollectionType, WarbandNexus, 123456)
    assert_eq(ok, true, "no error for an item no rule claims (" .. tostring(res) .. ")")
    assert_eq(ok and res, nil, "returns nil for an unclaimed item")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profiler / rules guard suite failed with " .. failed .. " failure(s).")
end
print("Profiler / rules guard suite: ALL TESTS PASSED.")
