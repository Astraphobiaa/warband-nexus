#!/usr/bin/env lua
--[[
    Regression test: every path that removes a roster row removes everything that belongs to it.

    Three paths remove rows: DeleteCharacter, EnforceCharacterLimit and CleanupStaleCharacters (90-day
    untracked prune). Each kept its own idea of "what belongs to a character":
      - the stale prune dropped only the row: PvP, weekly currency / M+ stamps, statistic seed stamps,
        favorites, group assignments and every subsidiary table stayed behind for good;
      - the next login's orphan sweep had its own (shorter) table list, so it did not catch them either;
      - the limit prune skipped the alias cleanup (group assignments / locks survived);
      - no path removed the character's weekly vault / daily quest plans or its guild bank cache.
    All three now go through CharacterService:PurgeCharacterRow, and the orphan sweep walks the same
    GetCharacterKeyedTables list as the delete path.

    Loads the shipped CharacterService, MigrationService and DatabaseOptimizer under wow_stub.lua;
    CleanupStaleCharacters and RemovePlansForCharacter are extracted from their files.
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
dofile(SCRIPT_DIR .. "/wow_stub.lua")

local LIVE, OLD, KEEP = "Player-3674-0000000A", "Player-3674-0000000B", "Player-3674-0000000C"
UnitGUID = function(unit) if unit == "player" then return LIVE end end

local ns = {}
local messages = {}
local guildRemovals = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
    InvalidateGetAllCharactersCache = function() end,
    RefreshPlanCache = function() end,
}
function WarbandNexus:MaybeRemoveGuildBankCache(guildName, excludeCharKey)
    guildRemovals[#guildRemovals + 1] = guildName .. "|" .. tostring(excludeCharKey)
    return true
end
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
local chars
ns.Utilities = {
    -- Mirrors Utilities:GetCharacterKey: spaces stripped ("Twisting Nether" -> "TwistingNether").
    GetCharacterKey = function(_, name, realm)
        return ((name or "Alpha"):gsub("%s+", "")) .. "-" .. ((realm or "Kazzak"):gsub("%s+", ""))
    end,
    GetCharacterStorageKey = function() return LIVE end,
    GetCanonicalCharacterKey = function(_, k)
        for key, row in pairs(chars or {}) do
            if type(row) == "table" and row.name and (row.name .. "-" .. row.realm) == k and key ~= k then return key end
        end
        return k
    end,
    SafeGuid = function(_, unit) if unit == "player" then return LIVE end end,
    SplitCharacterKey = function(_, k)
        local n, r = tostring(k or ""):match("^([^-]+)%-(.+)$")
        return n, r
    end,
    InvalidateCharacterKeyIndex = function() end,
    IsModuleEnabled = function() return true end,
}

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
-- Pull one `function WarbandNexus:Name(...)` out of a file and install it on the test addon.
local function Extract(rel, name, prelude)
    local src = ReadFile(rel)
    local body = src:match("(function WarbandNexus:" .. name .. "%(.-\nend)\n")
    assert(body, "function not found: " .. name)
    local chunk = assert(loadstring((prelude or "") .. "\nlocal WarbandNexus = ...\n" .. body, "@" .. rel .. ":" .. name))
    chunk(WarbandNexus, ns)
end

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/CharacterService.lua")
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/DatabaseOptimizer.lua")
Extract("Modules/DataService.lua", "CleanupStaleCharacters", "local _, ns = nil, select(2, ...)\nlocal Constants = ns.Constants")
Extract("Modules/PlansManager.lua", "RemovePlansForCharacter",
    "local _, ns = nil, select(2, ...)\nlocal E = ns.Constants.EVENTS\nlocal CHARACTER_BOUND_PLAN_TYPES = { weekly_vault = true, daily_quests = true }")
function WarbandNexus:IsCharacterEligibleForStaleRemoval(char) return type(char) == "table" and char.stale == true end

local G, P = WarbandNexus.db.global, WarbandNexus.db.profile

-- A world where OLD owns one entry in every per-character table; LIVE and KEEP own their own.
local function Seed(oldRow)
    G.characters = {
        [LIVE] = { name = "Alpha", realm = "Kazzak", guid = LIVE, isTracked = true },
        [OLD] = oldRow,
        [KEEP] = { name = "Charlie", realm = "Kazzak", guid = KEEP, isTracked = true },
    }
    chars = G.characters
    local function per() return { [LIVE] = { v = 1 }, [OLD] = { v = 2 }, [KEEP] = { v = 3 } } end
    G.currencyData = { currencies = per(), totalEarned = per(), currencyProgressWeek = per(), weeklyEarnedThisWeek = per() }
    G.gearData, G.pveProgress, G.statisticSnapshots, G.personalBanks = per(), per(), per(), per()
    G.itemStorage = per()
    G.itemStorage.warbandBank = { compressed = true, data = "x" }
    G.pvpProgress, G.pvpMatches = per(), per()
    G.tryCounterStatSeedAt = { [LIVE] = 1, [OLD] = 2, [KEEP] = 3 }
    G.pveCache = {
        mythicPlus = { keystones = per(), bestRuns = per(), dungeonScores = per(), runHistory = per(), runHistoryWeek = per() },
        greatVault = { activities = per(), rewards = per() },
        lockouts = { raids = per(), dungeons = per(), worldBosses = per() },
        delves = { characters = per() },
    }
    G.reputationData = { characters = per() }
    G.favoriteCharacters = { "Bravo-Kazzak", LIVE }
    P.characterGroupAssignments = { [OLD] = "group_1", ["Bravo-Kazzak"] = "group_1", [LIVE] = "group_2" }
    P.characterLockedAssignments = { [OLD] = true, [LIVE] = true }
    P.characterOrder = { regular = { LIVE, OLD, KEEP } }
    G.plans = {
        { id = 1, type = "weekly_vault", characterName = "Bravo", characterRealm = "Kazzak" },
        { id = 2, type = "daily_quests", characterName = "Bravo", characterRealm = "Kazzak" },
        { id = 3, type = "weekly_vault", characterName = "Alpha", characterRealm = "Kazzak" },
        { id = 4, type = "mount", mountID = 99 },
    }
    messages, guildRemovals = {}, {}
end

local function CountOld()
    local n = 0
    local tables = ns.CharacterService:GetCharacterKeyedTables(WarbandNexus)
    for i = 1, #tables do
        if tables[i][OLD] ~= nil then n = n + 1 end
    end
    return n, #tables
end

local function CheckPurged(label)
    local left, total = CountOld()
    assert_eq(total >= 24, true, label .. ": shared table list covers every per-character store (" .. total .. ")")
    assert_eq(left, 0, label .. ": no per-character table keeps the removed row")
    assert_eq(G.characters[OLD], nil, label .. ": row removed")
    assert_eq(G.pvpProgress[LIVE] and G.pvpProgress[LIVE].v, 1, label .. ": other characters' PvP kept")
    assert_eq(G.tryCounterStatSeedAt[KEEP], 3, label .. ": other characters' seed stamps kept")
    assert_eq(G.itemStorage.warbandBank ~= nil, true, label .. ": warband bank bucket kept")
    assert_eq(P.characterGroupAssignments[OLD], nil, label .. ": group assignment removed")
    assert_eq(P.characterGroupAssignments["Bravo-Kazzak"], nil, label .. ": Name-Realm group assignment removed")
    assert_eq(P.characterLockedAssignments[OLD], nil, label .. ": section lock removed")
    assert_eq(P.characterGroupAssignments[LIVE], "group_2", label .. ": other assignment kept")
    assert_eq(#P.characterOrder.regular, 2, label .. ": order entry removed")
    assert_eq(#G.plans, 2, label .. ": the removed character's vault and daily plans removed")
    assert_eq(G.plans[1].id, 3, label .. ": another character's vault plan kept")
    assert_eq(G.plans[2].id, 4, label .. ": collectible plan kept")
    assert_eq(guildRemovals[1], "Raiders|" .. OLD, label .. ": guild bank cache checked for the removed row's guild")
end

local function OldRow(extra)
    local row = { name = "Bravo", realm = "Kazzak", guid = OLD, isTracked = false, guildName = "Raiders", lastSeen = 100 }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

print("Phase 1: DeleteCharacter")
Seed(OldRow())
assert_eq(WarbandNexus:DeleteCharacter(OLD), true, "delete succeeds")
CheckPurged("delete")

print("Phase 2: CleanupStaleCharacters (90-day untracked prune)")
Seed(OldRow({ stale = true }))
assert_eq(WarbandNexus:CleanupStaleCharacters(90), 1, "one stale row pruned")
CheckPurged("stale prune")

print("Phase 3: EnforceCharacterLimit")
Seed(OldRow())
G.favoriteCharacters = { LIVE }   -- favorites are protected from the limit prune
assert_eq(WarbandNexus:EnforceCharacterLimit(2), 1, "oldest untracked row pruned over the limit")
CheckPurged("limit prune")

print("Phase 4: orphan sweep walks the same table list")
Seed(OldRow())
G.characters[OLD] = nil    -- a row removed by an older build that left its tables behind
WarbandNexus:CleanupOrphanedData()
local left = CountOld()
assert_eq(left, 0, "orphan sweep removes the leftovers from every per-character table")
assert_eq(G.pvpMatches[KEEP] and G.pvpMatches[KEEP].v, 3, "owned entries kept")
assert_eq(G.itemStorage.warbandBank ~= nil, true, "warband bank bucket kept by the sweep")

print("Phase 5: a same-name copy keeps the Name-Realm plans")
Seed(OldRow())
G.characters["Bravo-Kazzak"] = { name = "Bravo", realm = "Kazzak", isTracked = true }
WarbandNexus:DeleteCharacter(OLD)
assert_eq(#G.plans, 4, "plans of a Name-Realm another row still owns are kept")

print("Phase 6: plan realm from GetRealmName (with spaces) matches the normalized roster realm")
Seed(OldRow({ realm = "TwistingNether" }))
G.plans = {
    { id = 7, type = "weekly_vault", characterName = "Bravo", characterRealm = "Twisting Nether" },
    { id = 8, type = "weekly_vault", characterName = "Alpha", characterRealm = "Kazzak" },
}
WarbandNexus:DeleteCharacter(OLD)
assert_eq(#G.plans, 1, "multi-word realm plan of the deleted character removed")
assert_eq(G.plans[1] and G.plans[1].id, 8, "other character's plan kept")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character purge paths suite failed with " .. failed .. " failure(s).")
end
print("Character purge paths suite: ALL TESTS PASSED.")
