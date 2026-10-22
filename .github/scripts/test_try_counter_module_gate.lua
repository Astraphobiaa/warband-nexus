#!/usr/bin/env lua
--[[
    Regression test: with the Try Counter module off, its event dispatcher does no try-counter work
    for QUEST_LOG_UPDATE, PLAYER_TARGET_CHANGED and PLAYER_REGEN_ENABLED.

    Try counter events stay registered when the module is disabled (protected API, cannot be
    re-registered safely), and the handlers gate their own bodies. These three were dispatched inline
    with no gate: every QUEST_LOG_UPDATE armed a debounce timer and swept the known lockout quests,
    every target change parsed the target GUID against the drop tables, and every combat end rebuilt
    the merged statistic seed index. They now return early when the module is off.

    Loads the real Try Counter slice through wow_addon_harness.lua and fires the events at the
    registered frame.
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

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, Fns = H.stub, H.WN, H.Fns

local counts = {}
local function Spy(name)
    local real = Fns[name]
    Fns[name] = function(...)
        counts[name] = (counts[name] or 0) + 1
        return real(...)
    end
end
Spy("ProcessKnownLockoutQuestCompletions")
Spy("SafeGetTargetGUID")
Spy("EnsureMergedStatisticSeedIndex")

local function FireAll()
    for k in pairs(counts) do counts[k] = nil end
    stub.Fire("QUEST_LOG_UPDATE")
    stub.Fire("PLAYER_TARGET_CHANGED")
    stub.Fire("PLAYER_REGEN_ENABLED")
    stub.Advance(5)   -- past the QUEST_LOG_UPDATE debounce
end

print("Phase 1: Module on: the three events do their work")
do
    WN.db.profile.modulesEnabled.tryCounter = true
    FireAll()
    assert_eq(counts.ProcessKnownLockoutQuestCompletions, 1, "QUEST_LOG_UPDATE sweeps the lockout quests")
    assert_eq(counts.SafeGetTargetGUID, 1, "PLAYER_TARGET_CHANGED reads the target")
    assert_eq(counts.EnsureMergedStatisticSeedIndex, 1, "PLAYER_REGEN_ENABLED checks the seed index")
end

print("Phase 2: Module off: the dispatcher returns before any of it")
do
    WN.db.profile.modulesEnabled.tryCounter = false
    FireAll()
    assert_eq(counts.ProcessKnownLockoutQuestCompletions, nil, "QUEST_LOG_UPDATE: no lockout sweep")
    assert_eq(counts.SafeGetTargetGUID, nil, "PLAYER_TARGET_CHANGED: no target read")
    assert_eq(counts.EnsureMergedStatisticSeedIndex, nil, "PLAYER_REGEN_ENABLED: no seed index work")
end

print("Phase 3: Re-enabled: work resumes")
do
    WN.db.profile.modulesEnabled.tryCounter = true
    FireAll()
    assert_eq(counts.ProcessKnownLockoutQuestCompletions, 1, "lockout sweep resumes")
    assert_eq(counts.SafeGetTargetGUID, 1, "target read resumes")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers"
    .. (stub.errors[1] and (" (" .. stub.errors[1] .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Try counter module gate suite failed with " .. failed .. " failure(s).")
end
print("Try counter module gate suite: ALL TESTS PASSED.")
