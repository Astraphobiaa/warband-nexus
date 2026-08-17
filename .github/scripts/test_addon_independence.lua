#!/usr/bin/env lua5.1
--[[
    Warband Nexus must work on a bare client: no ElvUI, no Chattynator, no Rarity, no anything.

    The harness stub reports every external addon as absent (IsAddOnLoaded / C_AddOns return false,
    no third-party globals exist), so this file is the explicit assertion of that contract rather
    than an accident of the test environment. Third-party integrations are one-way enhancements:
    present -> extra data, absent -> the shipped path runs unchanged.

    ## OptionalDeps in the .toc is a load-ORDER hint ("load after these if installed"), not a
    requirement -- it never blocks loading. The runtime guards below are what actually matter.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, ns, WN, Fns = H.stub, H.ns, H.WN, H.Fns

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

print("phase 1: the environment really is a bare client")
check(_G.IsAddOnLoaded("ElvUI") == false, "ElvUI reported absent")
check(_G.C_AddOns.IsAddOnLoaded("Chattynator") == false, "Chattynator reported absent")
check(rawget(_G, "Rarity") == nil, "no Rarity global")
check(rawget(_G, "ElvUI") == nil, "no ElvUI global")

print("phase 2: chat routing delivers with no chat addon installed")
check(ns.ChatOutput ~= nil, "ns.ChatOutput exists")
check(ns.ChatOutput.IsElvUIPresent() == false, "IsElvUIPresent() false")
check(ns.ChatOutput.IsChattynatorPresent() == false, "IsChattynatorPresent() false")

-- Every route must land a line. "loot" is the default; the other two are user settings.
for _, route in ipairs({ "loot", "all_tabs", "dedicated" }) do
    WN.db.profile.notifications.tryCounterChatRoute = route
    stub.Reset()
    ns.ChatOutput.SendTryCounterMessage("|cff9370DB[WN-Counter]|r route test")
    check(#stub.chat == 1, ("route %q delivers exactly one line (got %d)"):format(route, #stub.chat))
end
WN.db.profile.notifications.tryCounterChatRoute = "loot"

print("phase 3: delivery survives a chat layout with no LOOT tab")
-- Common real setup: the user moved loot to a tab that does not report the LOOT message group, or
-- a chat addon replaced the frames. The fallback frame must still receive the line.
local origGetMessages = _G.GetChatWindowMessages
_G.GetChatWindowMessages = function() return nil end
stub.Reset()
ns.ChatOutput.SendTryCounterMessage("|cff9370DB[WN-Counter]|r no loot tab")
check(#stub.chat == 1, ("no frame subscribes to LOOT -> fallback still delivers (got %d)"):format(#stub.chat))
_G.GetChatWindowMessages = origGetMessages

print("phase 4: the Rarity overlay is inert when Rarity is not installed")
check(type(WN.SyncRarityMountAttemptsMax) == "function", "sync entry point exists regardless")
local ok, scanned, updated = pcall(WN.SyncRarityMountAttemptsMax, WN)
check(ok, "SyncRarityMountAttemptsMax does not error without Rarity")
check(scanned == 0 and updated == 0, "it reports nothing scanned and nothing updated")

if type(WN.RestoreRarityImportBackup) == "function" then
    check(pcall(WN.RestoreRarityImportBackup, WN), "RestoreRarityImportBackup runs without Rarity")
end

print("phase 5: counting works end to end on the bare client")
-- The whole point: a real cast still counts and still announces with nothing else installed.
local DRAKE = 260916
local before = WN:GetTryCount("mount", DRAKE) or 0
stub.Reset()
stub.world.mapID = 2405
stub.world.isFishingLoot = true
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:6303::::::::::::::::|h[Junk]|h" } }
stub.world.lootSources = { { "Creature-0-0-0-0-124736-000000000000", 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(0.05)
stub.Fire("LOOT_CLOSED")
stub.Advance(5)
check((WN:GetTryCount("mount", DRAKE) or 0) == before + 1, "cast counted on a bare client")
check(#stub.chat == 1, ("cast announced on a bare client (got %d lines)"):format(#stub.chat))

print("phase 6: no errors escaped any handler or timer")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
check(#stub.errors == 0, "no runtime errors")

if failures > 0 then
    io.stderr:write(("\ntest_addon_independence: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_addon_independence: all checks passed")
