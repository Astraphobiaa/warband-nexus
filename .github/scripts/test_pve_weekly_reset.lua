#!/usr/bin/env lua
--[[
    Regression test: week-scoped PvE data shown for any character does not survive the weekly reset.

    The reset pass pruned pveCache.mythicPlus.keystones only. The roster row's mythicKey mirror --
    what the Characters tab, tooltips and /wn read -- was never cleared, and with no key in the
    bags C_MythicPlus.GetOwnedKeystoneLevel returns nothing (MayReturnNothing), which the keystone
    reader keeps as "API not ready". Every character kept last week's key on screen.

    Loads the shipped ResetService.lua + PvECacheService.lua under wow_stub.lua.
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

local WEEK = 7 * 86400
local RESET = 1791950400            -- 2026-10-14 04:00:00 UTC
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end }

local savedInstances = {}
local raidInfoRequests = 0
GetNumSavedInstances = function() return #savedInstances end
GetSavedInstanceInfo = function(i)
    local r = savedInstances[i]
    if not r then return end
    -- name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid, maxPlayers,
    -- difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
    return r.name, 1, r.reset, 16, true, false, 0, true, 20, "Mythic", 8, 3, false, r.instanceId
end
GetSavedInstanceEncounterInfo = function() return nil end
RequestRaidInfo = function() raidInfoRequests = raidInfoRequests + 1 end

local KEY = "Player-01"
local ns = {}
local handlers = {}
local WarbandNexus = {
    db = {
        global = {
            characters = {},
            pveCache = {
                delves = { characters = {}, companion = {} },
                lockouts = { worldBosses = {}, raids = {}, dungeons = {} },
                mythicPlus = {}, greatVault = { activities = {}, rewards = {} },
            },
        },
        profile = {}, char = {},
    },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function(_, ev, fn) handlers[ev] = fn end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = { IsCharacterTracked = function() return true end }
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    IsPvEVaultConsumerEnabled = function() return false end,   -- keep the event handler's refresh path out
    GetCharacterKey = function() return KEY end,
    GetCharacterStorageKey = function() return KEY end,
    GetCanonicalCharacterKey = function(_, k) return k end,
}

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
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/PvECacheService.lua")
LoadFile("Modules/PvECacheService_MythicPlus.lua")
LoadFile("Modules/PvECacheService_Vault.lua")

local chars = WarbandNexus.db.global.characters
chars["Player-A"] = { name = "Superluminal", mythicKey = { level = 18, mapID = 2521, scanTime = RESET - 5 * 86400 } }
chars["Player-B"] = { name = "Vhorzenn", mythicKey = { level = 9, mapID = 2649, scanTime = RESET - 70 * 86400 } }
chars["Player-C"] = { name = "Xentis", mythicKey = { level = 12, mapID = 2652, scanTime = RESET + 3600 } }
chars["Player-D"] = { name = "Legacy", mythicKey = { level = 4, mapID = 2652 } }   -- no stamp

print("Phase 1: the reset pass clears every roster key stamped before this week's reset")
WarbandNexus:PruneAllPvEWeeklyData()
assert_eq(chars["Player-A"].mythicKey, nil, "last week's key is cleared on the logged-in character")
assert_eq(chars["Player-B"].mythicKey, nil, "an offline alt's old key is cleared")
assert_eq(chars["Player-D"].mythicKey, nil, "a key with no scan time is treated as stale")
assert_eq(chars["Player-C"].mythicKey and chars["Player-C"].mythicKey.level, 12, "a key obtained this week stays")

print("Phase 2: the answer to RequestMapInfo does not ask for another answer")
do
    -- CHALLENGE_MODE_MAPS_UPDATE / MYTHIC_PLUS_CURRENT_AFFIX_UPDATE are what RequestMapInfo
    -- produces. Requesting again from their handlers looped for the whole session.
    local requests = 0
    C_MythicPlus = {
        RequestMapInfo = function() requests = requests + 1 end,
        -- A definitive read (key in bags), so the separately capped warmup retry stays out of it.
        GetOwnedKeystoneChallengeMapID = function() return 2521 end,
        GetOwnedKeystoneLevel = function() return 7 end,
    }
    WarbandNexus:RequestKeystoneRefresh("CHALLENGE_MODE_MAPS_UPDATE", true)
    WarbandNexus:RequestKeystoneRefresh("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", true)
    assert_eq(requests, 0, "answer events read the keystone without requesting map info again")
    WarbandNexus:RequestKeystoneRefresh("OnKeystoneChanged", true)   -- high priority: no throttle
    assert_eq(requests, 1, "other triggers still request fresh map info")
end

print("Phase 3: an alt's Great Vault progress from last week reads as post-reset")
do
    -- Only the logged-in character's scan ever set isPostReset, so an alt's last-week slots kept
    -- showing as this week's progress until that alt logged in.
    local acts = {
        ["Player-A"] = { weeklyResetTime = RESET, raids = { { progress = 6, threshold = 6 } },
            dungeonRunCounts = { heroic = 4 } },                          -- snapshot from last week
        ["Player-C"] = { weeklyResetTime = RESET + WEEK, raids = { { progress = 2, threshold = 6 } } },
    }
    WarbandNexus.db.global.pveCache.greatVault.activities = acts
    WarbandNexus:PruneAllPvEWeeklyData()
    assert_eq(acts["Player-A"].isPostReset, true, "last week's snapshot is marked post-reset")
    assert_eq(acts["Player-A"].dungeonRunCounts, nil, "last week's run counts are dropped")
    assert_eq(acts["Player-A"].raids[1].progress, 6, "rows are kept for the unclaimed-chest check")
    assert_eq(acts["Player-C"].isPostReset, nil, "this week's snapshot is untouched")
end

print("Phase 4: one Great Vault request per answer, not one per caller")
do
    -- Measured: 4 vault pokes per login (scanner, UPDATE_INSTANCE_INFO, the M+ affix replies), and
    -- every answer runs three full vault handlers.
    local pokes = 0
    C_WeeklyRewards = { OnUIInteract = function() pokes = pokes + 1 end }
    stub.Advance(60)
    WarbandNexus:PokeWeeklyVaultServer(true)                -- login owner
    assert_eq(pokes, 1, "the forced login poke is sent")
    stub.Advance(3)
    WarbandNexus:RequestWeeklyVaultRefresh()                -- UPDATE_INSTANCE_INFO, answer pending
    assert_eq(pokes, 1, "a routine poke waits while the answer is still on its way")
    WarbandNexus:NoteWeeklyVaultAnswered()
    stub.Advance(3)
    WarbandNexus:RequestWeeklyVaultRefresh()
    assert_eq(pokes, 2, "after the answer a routine poke goes out again")
    WarbandNexus:PokeWeeklyVaultServer(true)                -- a claim
    assert_eq(pokes, 3, "a forced poke (claim / run completed) is never held back")
end

print("Phase 5: the M+ affix answer is not handled as a weekly reset")
do
    -- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE answers RequestMapInfo / RequestCurrentAffixes. Each one ran
    -- the weekly-reset chain (prune + save + full PvE update + vault poke): twice per login.
    local pokes, saves, mapInfo = 0, 0, 0
    C_WeeklyRewards = { OnUIInteract = function() pokes = pokes + 1 end }
    C_MythicPlus = {
        RequestMapInfo = function() mapInfo = mapInfo + 1 end,
        RequestCurrentAffixes = function() end,
        GetCurrentAffixes = function() return { 9, 10 } end,
        GetOwnedKeystoneChallengeMapID = function() return 2521 end,
        GetOwnedKeystoneLevel = function() return 7 end,
    }
    C_ChallengeMode = C_ChallengeMode or {}
    local save = WarbandNexus.SavePvECache
    WarbandNexus.SavePvECache = function() saves = saves + 1 end
    WarbandNexus:RegisterPvECacheEvents()
    local onAffix = handlers["MYTHIC_PLUS_CURRENT_AFFIX_UPDATE"]
    assert_eq(type(onAffix), "function", "affix handler registered")
    stub.Advance(60)          -- runs the login prime timers registered above
    pokes, mapInfo = 0, 0
    onAffix()
    local mp = WarbandNexus.db.global.pveCache.mythicPlus
    assert_eq(table.concat(mp.currentAffixes or {}, ","), "9,10", "the affix list is refreshed")
    assert_eq(pokes, 0, "no Great Vault request from an affix answer")
    local savesAfterFirst = saves
    onAffix()
    assert_eq(saves, savesAfterFirst, "an unchanged affix list is not saved again")
    assert_eq(mapInfo, 0, "the answer does not request another answer")
    WarbandNexus.SavePvECache = save
end

print("Phase 6: routine map-info requests share one door")
do
    local mapInfo = 0
    C_MythicPlus.RequestMapInfo = function() mapInfo = mapInfo + 1 end
    stub.Advance(60)
    WarbandNexus:RequestMythicPlusMapInfo(false)
    WarbandNexus:RequestMythicPlusMapInfo(false)
    assert_eq(mapInfo, 1, "a second routine request within 5s is dropped")
    WarbandNexus:RequestMythicPlusMapInfo(true)
    assert_eq(mapInfo, 2, "a forced request (run completed / claim) still goes out")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE weekly reset suite failed with " .. failed .. " failure(s).")
end
print("PvE weekly reset suite: ALL TESTS PASSED.")
