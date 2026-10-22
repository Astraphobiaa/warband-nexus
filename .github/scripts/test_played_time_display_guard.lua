#!/usr/bin/env lua
--[[
    Regression test: an error inside Blizzard's played-time display does not silence /played.

    The DisplayTimePlayed wrappers raise a depth counter around the call to the original so a chat
    addon that re-enters our wrapper does not recurse. The call was unprotected: if the original
    errored, the decrement never ran, the counter stayed > 0 and every later /played line was
    swallowed for the session. The call is now pcall'd, the counter always drops, and the error
    goes to the error handler as an unprotected call would have.

    Loads the shipped Modules/ChatIntegrationService.lua under wow_stub.lua and drives both the
    ChatFrameUtil.DisplayTimePlayed and the legacy ChatFrame_DisplayTimePlayed wrappers.
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
    db = { global = {}, profile = { notifications = { hidePlayedTimeInChat = false } }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {}

-- Blizzard originals: count displays, error on demand.
local shown = { util = 0, legacy = 0 }
local failNext = { util = false, legacy = false }
_G.ChatFrameUtil = {
    DisplayTimePlayed = function(chatFrame, totalTime, levelTime)
        if failNext.util then failNext.util = false; error("util display failed") end
        shown.util = shown.util + 1
    end,
}
_G.ChatFrame_DisplayTimePlayed = function(cf, totalTime, levelTime)
    if failNext.legacy then failNext.legacy = false; error("legacy display failed") end
    shown.legacy = shown.legacy + 1
end

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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/ChatIntegrationService.lua")
WarbandNexus:InstallPlayedTimeDisplayHook()

local function Call(fn, ...)
    local ok = pcall(fn, ...)
    return ok
end

print("Phase 1: Wrappers are installed and pass through")
do
    assert_eq(ChatFrameUtil.DisplayTimePlayed == WarbandNexus._wnChatFrameUtilDisplayWrapper, true,
        "ChatFrameUtil.DisplayTimePlayed wrapped")
    assert_eq(ChatFrame_DisplayTimePlayed == WarbandNexus._wnPlayedTimeWrapper, true,
        "ChatFrame_DisplayTimePlayed wrapped")
    ChatFrameUtil.DisplayTimePlayed(ChatFrame1, 100, 10)
    assert_eq(shown.util, 1, "util wrapper shows the line")
end

print("Phase 2: An error in the original does not swallow later /played lines")
do
    stub.Reset()
    failNext.util = true
    Call(ChatFrameUtil.DisplayTimePlayed, ChatFrame1, 100, 10)
    assert_eq(#stub.errors, 1, "util error reported to the error handler once")
    assert_eq(stub.errors[1] and stub.errors[1]:find("util display failed", 1, true) ~= nil, true,
        "reported error is the original's")
    ChatFrameUtil.DisplayTimePlayed(ChatFrame1, 200, 20)
    assert_eq(shown.util, 2, "next util /played line still shows")
    ChatFrame_DisplayTimePlayed(ChatFrame1, 200, 20)
    assert_eq(shown.legacy, 1, "legacy wrapper is not silenced by the util failure")

    stub.Reset()
    failNext.legacy = true
    Call(ChatFrame_DisplayTimePlayed, ChatFrame1, 100, 10)
    assert_eq(#stub.errors, 1, "legacy error reported to the error handler once")
    ChatFrame_DisplayTimePlayed(ChatFrame1, 300, 30)
    assert_eq(shown.legacy, 2, "next legacy /played line still shows")
    ChatFrameUtil.DisplayTimePlayed(ChatFrame1, 300, 30)
    assert_eq(shown.util, 3, "util wrapper is not silenced by the legacy failure")
    stub.Reset()
end

print("Phase 3: Re-entry from a chat addon is still blocked")
do
    local before = shown.util
    local orig = WarbandNexus._wnBlizzardDisplayTimePlayed
    WarbandNexus._wnBlizzardDisplayTimePlayed = function(...)
        shown.util = shown.util + 1
        ChatFrameUtil.DisplayTimePlayed(...)   -- addon hook calling back into the wrapper
    end
    ChatFrameUtil.DisplayTimePlayed(ChatFrame1, 1, 1)
    WarbandNexus._wnBlizzardDisplayTimePlayed = orig
    assert_eq(shown.util - before, 1, "nested call returns at the depth guard (one line, no recursion)")
    ChatFrameUtil.DisplayTimePlayed(ChatFrame1, 1, 1)
    assert_eq(shown.util - before, 2, "guard released after the nested call")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Played time display guard suite failed with " .. failed .. " failure(s).")
end
print("Played time display guard suite: ALL TESTS PASSED.")
