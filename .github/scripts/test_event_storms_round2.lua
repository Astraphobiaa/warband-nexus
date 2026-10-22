#!/usr/bin/env lua
--[[
    Regression test: event storms, round 2 (2026-10-22). Drives the shipped files under wow_stub.lua.

      B5  chat-triggered reputation scans (rep line / renown) bypassed the throttle and ran a
          ~200-faction full scan in combat; now deferred to one scan after PLAYER_REGEN_ENABLED.
      B10 CHAT_MSG_LOOT parsed every group member's loot line before checking the author
          (ReputationCacheService, PvECacheService); the reputation handler also rebuilt a
          closure and a pcall wrapper per event.
      B7  Saved Instances window: UPDATE_INSTANCE_INFO -> RequestRaidInfo -> UPDATE_INSTANCE_INFO
          looped for as long as the window stayed open.
      B9  profession knowledge refresh: a 0.35s trailing timer recreated on every
          QUEST_LOG_UPDATE / bag / trait-currency fire; now at most one run per 3s.
      E4  login timers that landed in the same frame on /reload are staggered.
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
table.wipe = _G.wipe

local inCombat = false
InCombatLockdown = function() return inCombat end

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

local function LoadFile(rel, ns)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function NewAddon(handlers)
    return {
        db = { global = { characters = {} }, profile = {}, char = {} },
        SendMessage = function() end,
        RegisterMessage = function() end,
        RegisterEvent = function(_, ev, fn) if handlers then handlers[ev] = fn end end,
        RegisterBucketEvent = function() end,
        Print = function() end,
    }
end

local function BaseNs(addon)
    local ns = { WarbandNexus = addon }
    ns.DebugPrint = function() end
    ns.DebugVerbosePrint = function() end
    ns.IsDebugModeEnabled = function() return false end
    ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
    return ns
end

-- ------------------------------------------------------------------------------------------------
-- B5 / B10: ReputationCacheService
-- ------------------------------------------------------------------------------------------------
local repNs = BaseNs(NewAddon())
repNs.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return "Player-1-00000001" end,
    ResolveCharactersTableKey = function() return "Player-1-00000001" end,
}
LoadFile("Modules/Constants.lua", repNs)
LoadFile("Modules/Utilities.lua", repNs)
LoadFile("Modules/DataFreshness.lua", repNs)
LoadFile("Modules/ReputationCacheService.lua", repNs)
local RC = repNs.ReputationCache

local scans, bypassScans, baselines = 0, 0, 0
RC.PerformFullScan = function(_, bypass)
    scans = scans + 1
    if bypass then bypassScans = bypassScans + 1 end
end
RC.CaptureCompanionBaseline = function() baselines = baselines + 1 end
RC.CheckCompanionRepDelta = function() end
RC:RegisterEventListeners()

local function ResetRep()
    stub.Advance(10)
    scans, bypassScans, baselines = 0, 0, 0
    RC._lastChatFullScanAt = nil
end

print("B5: a rep chat line out of combat still scans once (bypass)")
do
    ResetRep()
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "unparsable rep line")
    stub.Advance(1)
    assert_eq(scans, 1, "one scan")
    assert_eq(bypassScans, 1, "scan bypasses the throttle")
end

print("B5: rep chat lines in combat wait for PLAYER_REGEN_ENABLED, then scan once")
do
    ResetRep()
    inCombat = true
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "unparsable rep line")
    stub.Advance(2)
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "unparsable rep line")
    stub.Advance(2)
    assert_eq(scans, 0, "no full scan while in combat")
    inCombat = false
    stub.Fire("PLAYER_REGEN_ENABLED")
    stub.Advance(2)
    assert_eq(scans, 1, "exactly one scan after combat")
    assert_eq(bypassScans, 1, "the post-combat scan keeps the chat bypass")
    stub.Fire("PLAYER_REGEN_ENABLED")
    stub.Advance(2)
    assert_eq(scans, 1, "a second PLAYER_REGEN_ENABLED does not rescan")
end

print("B5: a chat scan armed before combat does not fire inside it")
do
    ResetRep()
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "unparsable rep line")
    inCombat = true
    stub.Advance(2)
    assert_eq(scans, 0, "armed timer fired in combat: no scan")
    inCombat = false
    stub.Fire("PLAYER_REGEN_ENABLED")
    stub.Advance(2)
    assert_eq(scans, 1, "one scan after combat")
end

print("B5: lockdown still reading true at PLAYER_REGEN_ENABLED does not lose the scan")
do
    ResetRep()
    inCombat = true
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "unparsable rep line")
    stub.Fire("PLAYER_REGEN_ENABLED")   -- dispatched while lockdown has not lifted yet
    inCombat = false
    stub.Advance(2)
    assert_eq(scans, 1, "scan runs once lockdown lifts")
end

local CHUNK = "You receive loot: |cff0070dd|Hitem:999001::::::::|h[Chunk of Companion Experience]|h|r."

print("B10: reputation CHAT_MSG_LOOT only reacts to the player's own loot")
do
    ResetRep()
    stub.Fire("CHAT_MSG_LOOT", CHUNK, "Partymate-OtherRealm")
    assert_eq(baselines, 0, "party member's companion chunk ignored")
    stub.Fire("CHAT_MSG_LOOT", CHUNK, stub.MarkSecret("Secretname"))
    assert_eq(baselines, 0, "secret author ignored")
    stub.Fire("CHAT_MSG_LOOT", CHUNK, "Tester-TestRealm")
    assert_eq(baselines, 1, "own chunk (Name-Realm author) handled")
    stub.Fire("CHAT_MSG_LOOT", CHUNK, "Tester")
    assert_eq(baselines, 2, "own chunk (bare name author) handled")
    stub.Fire("CHAT_MSG_LOOT", CHUNK, "")
    assert_eq(baselines, 3, "empty author still reads as self")
    stub.Advance(3)
end

print("B10: reputation OnEvent no longer builds a closure + pcall per event (static)")
do
    local src = ReadFile("Modules/ReputationCacheService.lua")
    assert_eq(src:find("pcall(inner", 1, true), nil, "no pcall(inner, ...) wrapper")
    assert_eq(src:find("local function inner(", 1, true), nil, "no per-event inner closure")
end

-- ------------------------------------------------------------------------------------------------
-- B10: PvECacheService keystone loot checks the author before parsing
-- ------------------------------------------------------------------------------------------------
print("B10: PvE keystone CHAT_MSG_LOOT skips party loot before the keystone probe")
do
    local pveHandlers = {}
    local addon = NewAddon(pveHandlers)
    addon.db.global.pveCache = {
        delves = { characters = {}, companion = {} },
        lockouts = { worldBosses = {}, raids = {}, dungeons = {} },
        mythicPlus = {}, greatVault = { activities = {}, rewards = {} },
    }
    local pveNs = BaseNs(addon)
    pveNs.CharacterService = { IsCharacterTracked = function() return true end }
    pveNs.Utilities = {
        IsModuleEnabled = function() return true end,
        IsAnyModuleEnabled = function() return true end,
        IsPvEVaultConsumerEnabled = function() return false end,
        GetCharacterKey = function() return "Player-01" end,
        GetCharacterStorageKey = function() return "Player-01" end,
        GetCanonicalCharacterKey = function(_, k) return k end,
    }
    RequestRaidInfo = function() end
    GetServerTime = GetServerTime or function() return 1791950400 end
    LoadFile("Modules/Constants.lua", pveNs)
    LoadFile("Modules/ResetService.lua", pveNs)
    LoadFile("Modules/PvECacheService.lua", pveNs)
    LoadFile("Modules/PvECacheService_MythicPlus.lua", pveNs)
    LoadFile("Modules/PvECacheService_Vault.lua", pveNs)
    addon:RegisterPvECacheEvents()

    local probes, refreshes = 0, 0
    C_Item.IsItemKeystoneByID = function() probes = probes + 1; return true end
    addon.RequestKeystoneRefresh = function() refreshes = refreshes + 1 end
    local KS = "You receive loot: |cffa335ee|Hitem:180653::::::::|h[Mythic Keystone]|h|r."
    local h = pveHandlers.CHAT_MSG_LOOT
    assert_eq(type(h), "function", "CHAT_MSG_LOOT registered")
    if h then
        h("CHAT_MSG_LOOT", KS, "Partymate-OtherRealm")
        assert_eq(probes, 0, "party keystone line: no C_Item probe")
        assert_eq(refreshes, 0, "party keystone line: no refresh")
        h("CHAT_MSG_LOOT", KS, "Tester-TestRealm")
        assert_eq(refreshes, 1, "own keystone line still refreshes")
    end
end

-- ------------------------------------------------------------------------------------------------
-- B7: Saved Instances live refresh
-- ------------------------------------------------------------------------------------------------
print("B7: UPDATE_INSTANCE_INFO repaint does not request raid info again")
do
    local requests = 0
    RequestRaidInfo = function() requests = requests + 1 end
    local viNs = BaseNs(NewAddon())
    viNs.VaultButton = { state = {} }
    LoadFile("Modules/VaultButton_SavedInstances.lua", viNs)
    local VB = viNs.VaultButton
    VB.ScheduleSavedInstancesLiveRefresh(false)
    assert_eq(requests, 0, "repaint-only refresh sends no RequestRaidInfo")
    VB.ScheduleSavedInstancesLiveRefresh(true)
    assert_eq(requests, 1, "explicit refresh still requests raid info")
    stub.Advance(1)
    -- The live event frame is built only by the window's OnShow (needs the full UI stack): pin the
    -- routing statically.
    local src = ReadFile("Modules/VaultButton_SavedInstances.lua")
    assert_eq(src:find('ScheduleSavedInstancesLiveRefresh(event ~= "UPDATE_INSTANCE_INFO")', 1, true) ~= nil, true,
        "UPDATE_INSTANCE_INFO routes to the repaint-only refresh")
end

-- ------------------------------------------------------------------------------------------------
-- B9: profession knowledge refresh throttle
-- ------------------------------------------------------------------------------------------------
print("B9: QUEST_LOG_UPDATE stream runs the knowledge refresh at most once per 3s")
do
    local profAddon = NewAddon()
    profAddon.db.profile.modulesEnabled = { professions = true }
    profAddon.db.global.characters["Player-01"] = {
        name = "AltHero",
        professions = {
            [1] = { name = "Alchemy", skillLine = 171, rank = 100, maxRank = 100 },
            [2] = { name = "Inscription", skillLine = 773, rank = 100, maxRank = 100 },
        },
        professionData = { bySkillLine = {} },
        discoveredSkillLines = {},
    }
    local profNs = BaseNs(profAddon)
    profNs.Profiler.CAT = { SVC = "svc" }
    profNs.Utilities = {
        GetCharacterStorageKey = function() return "Player-01" end,
        GetCharacterKey = function() return "Player-01" end,
        IsModuleEnabled = function(_, mod) return mod == "professions" end,
    }
    profNs.CharacterService = {
        IsCharacterTracked = function() return true end,
        ResolveCharactersTableKey = function() return "Player-01" end,
    }
    LoadFile("Locales/enUS.lua", profNs)
    profNs.L = profNs.LOCALES and profNs.LOCALES.enUS
    LoadFile("Modules/Constants.lua", profNs)
    LoadFile("Modules/ProfessionService.lua", profNs)
    LoadFile("Modules/ProfessionService_WeeklyKnowledge.lua", profNs)
    LoadFile("Modules/ProfessionService_Login.lua", profNs)
    LoadFile("Modules/ProfessionService_Queries.lua", profNs)

    local flagReads = 0
    local realFlag = C_QuestLog.IsQuestFlaggedCompleted
    C_QuestLog.IsQuestFlaggedCompleted = function(q) flagReads = flagReads + 1; return realFlag(q) end

    profAddon:OnProfessionQuestProgressChanged(true)
    local perRun = flagReads
    assert_eq(perRun > 0, true, "one refresh reads quest flags")
    stub.Advance(5)

    flagReads = 0
    for _ = 1, 12 do                      -- QUEST_LOG_UPDATE every 0.5s for 6s
        profAddon:OnProfessionQuestProgressChanged()
        stub.Advance(0.5)
    end
    stub.SetQuestCompleted(95131, true)    -- Inscription treatise consumed: last event of the stream
    profAddon:OnProfessionQuestProgressChanged()
    stub.Advance(5)
    local runs = perRun > 0 and (flagReads / perRun) or -1
    assert_eq(runs <= 4, true, "6.5s of events cost at most 4 refresh runs (got " .. tostring(runs) .. ")")
    assert_eq(runs >= 2, true, "events inside the window still get a trailing run")
    local insc = profAddon:GetCharacterWeeklyKnowledge(profAddon.db.global.characters["Player-01"], 2913)
    assert_eq(insc and insc.treatise and insc.treatise.current, 1, "final state (treatise 1/1) persisted")

    flagReads = 0
    profAddon:OnProfessionQuestProgressChanged()
    stub.Advance(0.2)
    assert_eq(flagReads, 0, "single trigger waits for the settle delay")
    stub.Advance(1)
    -- One run: at most the first run's reads (a counter already at its cap is not re-read, 2026-10-22).
    assert_eq(flagReads > 0 and flagReads <= perRun, true, "single trigger after a quiet period runs once")
    C_QuestLog.IsQuestFlaggedCompleted = realFlag
end

-- ------------------------------------------------------------------------------------------------
-- E4: login timer stagger
-- ------------------------------------------------------------------------------------------------
print("E4: InitializationService timers no longer share a frame with each other or Core")
do
    local at = {}
    local t0 = GetTime()
    local function rec(name) return function() at[name] = GetTime() - t0 end end
    local initAddon = NewAddon()
    initAddon.Tooltip = { Initialize = rec("TooltipInit"), InitializeGameTooltipHook = rec("TooltipHook") }
    initAddon.InitializeCurrencyCache = rec("CurrencyCache")
    initAddon.RegisterPvECacheEvents = rec("PvECacheEvents")
    initAddon.InitializeItemsCache = rec("ItemsCache")
    initAddon.InitializeGoldManagementService = rec("BankMoney")
    initAddon.InitializeReminderService = rec("Reminder")
    initAddon.InitializeEventManager = rec("CoreEventSetup")
    local initNs = BaseNs(initAddon)
    initNs.CharacterService = { IsCharacterTracked = function() return true end }
    LoadFile("Modules/InitializationService.lua", initNs)
    local IS = initNs.InitializationService
    IS:InitializeDataServices(initAddon)
    IS:InitializeUIServices(initAddon)
    IS:InitializeBackgroundServices(initAddon)
    stub.Advance(10)
    local function near(a, b) return a and b and math.abs(a - b) < 0.05 end
    assert_eq(near(at.CurrencyCache, 2), false, "P3 caches off Core's T+2 light save")
    assert_eq(near(at.BankMoney, at.ItemsCache), false, "bank-money services off the items-cache frame")
    assert_eq(near(at.Reminder, 4), false, "ReminderService off Core P0 (T+4)")
    assert_eq(near(at.TooltipHook, 0.5), false, "tooltip hook off the T+0.5 core-init frame")
    -- Dependencies keep their order.
    assert_eq((at.TooltipInit or 99) < (at.TooltipHook or 0), true, "tooltip init before hook")
    assert_eq((at.PvECacheEvents or 99) < (at.ItemsCache or 0), true, "PvE cache events before items cache")
    assert_eq((at.ItemsCache or 99) < (at.BankMoney or 0), true, "items cache before bank-money services")
    local core = ReadFile("Core.lua")
    assert_eq(core:find("-- Core P0 (T+4s): Lightweight resets", 1, true) ~= nil
        and core:find("C_Timer.After(4, function()", 1, true) ~= nil, true, "Core P0 still at T+4 (anchor for the check above)")
    assert_eq(core:find("if isInitialLogin or isReloadingUi then\n        C_Timer.After(2, function()", 1, true) ~= nil, true,
        "Core light save still at T+2 (anchor for the check above)")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    " .. stub.errors[i]) end end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
