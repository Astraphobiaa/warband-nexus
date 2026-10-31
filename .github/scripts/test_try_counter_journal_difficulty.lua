#!/usr/bin/env lua5.1
--[[
    Encounter Journal scan: difficulty walk and the difficultyIDs whitelist it produces.

    Drives the real Modules/TryCounterService_JournalScan.lua under wow_stub.lua, then fires real
    ENCOUNTER_END events at the shipped handler, so this fails if either half regresses.

    What it pins down:
      * every (instance, difficulty, encounter) is read exactly once -- the walk used to yield a
        frame on each difficulty switch and re-enter with a stale guard, reading only the LAST
        difficulty of each instance, which silently produced no whitelists at all
      * a drop seen at only some difficulties gets difficultyIDs; one seen at all of them does not
      * an encounter whose loot list NEVER arrives gets NO whitelist, because "not in the list"
        and "list never arrived" are indistinguishable (fail open on scan, fail closed on count)
      * a loot list that was merely slow is picked up by the retry pass, and its encounter then
        does get a whitelist -- without that second pass a single slow read wasted every other
        difficulty already read cleanly for that boss
      * the payoff: a Mythic-only mount takes no attempt off a Normal kill

    Run from the repo root:  lua5.1 .github/scripts/test_try_counter_journal_difficulty.lua
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, Fns, RT = H.stub, H.WN, H.Fns, H.RT

local failures, totalChecks = 0, 0
local function check(cond, msg)
    totalChecks = totalChecks + 1
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end
function stub.chatHas(needle)
    for i = 1, #stub.chat do
        if tostring(stub.chat[i]):find(needle, 1, true) then return true end
    end
    return false
end

local function checkEq(got, want, msg)
    check(got == want, msg .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

-- ── world ───────────────────────────────────────────────────────────────────
local RAID, DUN, PARTIAL, SLOW = 1101, 1102, 1103, 1104
local RAID_ENC, DUN_ENC_A, DUN_ENC_B, PARTIAL_ENC, SLOW_ENC = 5001, 5002, 5003, 5004, 5005
local COMMON_MOUNT, MYTHIC_MOUNT, DUN_PET = 70001, 80001, 90001
local PARTIAL_MOUNT, SLOW_MOUNT = 95001, 96001
-- Not in world.itemClass, so ClassifyCollectibleItem ignores it. Present only so the list is
-- non-empty: the scan reads an empty loot list as "still loading", never as "drops nothing".
local FILLER = 99999

stub.world.itemClass = {
    [COMMON_MOUNT]  = { 15, 5 },
    [MYTHIC_MOUNT]  = { 15, 5 },
    [PARTIAL_MOUNT] = { 15, 5 },
    [SLOW_MOUNT]    = { 15, 5 },
    [DUN_PET]       = { 15, 2 },
}
stub.world.journal = {
    order = { { RAID, true }, { DUN, false }, { PARTIAL, false }, { SLOW, false } },
    instances = {
        [RAID] = {
            diffs = { 14, 15, 16 },
            encounters = { { jid = 9001, did = RAID_ENC } },
            loot = {
                [14] = { COMMON_MOUNT },
                [15] = { COMMON_MOUNT },
                [16] = { COMMON_MOUNT, MYTHIC_MOUNT },
            },
        },
        [DUN] = {
            diffs = { 1, 2, 23 },
            encounters = { { jid = 9002, did = DUN_ENC_A }, { jid = 9003, did = DUN_ENC_B } },
            loot = { [1] = { DUN_PET }, [2] = { DUN_PET }, [23] = { DUN_PET } },
        },
        [PARTIAL] = {
            diffs = { 1, 2 },
            encounters = { { jid = 9004, did = PARTIAL_ENC } },
            loot = { [1] = { PARTIAL_MOUNT }, [2] = "STALE" },
        },
        -- Heroic is slow rather than absent: out of date on the first read, delivered on the
        -- retry. The mount is Mythic-only, so the whitelist is only reachable if the retry works.
        [SLOW] = {
            diffs = { 1, 2, 23 },
            encounters = { { jid = 9005, did = SLOW_ENC } },
            loot = {
                [1] = { FILLER },
                [2] = { staleFor = 1, items = { FILLER } },
                [23] = { FILLER, SLOW_MOUNT },
            },
        },
    },
}

-- ── run the scan to completion ──────────────────────────────────────────────
print("\n[1] Encounter Journal walk")
WN:ScanEncounterJournalSources()
stub.Advance(30)

local seen, unique = {}, {}
for i = 1, #stub.ej.visits do
    local v = stub.ej.visits[i]
    if not seen[v] then unique[#unique + 1] = v end
    seen[v] = (seen[v] or 0) + 1
end
table.sort(unique)
checkEq(table.concat(unique, " "),
    -- lexicographic, so 1102@23 sorts before 1102@2
    "1101@14:9001 1101@15:9001 1101@16:9001 1102@1:9002 1102@1:9003 1102@23:9002 "
    .. "1102@23:9003 1102@2:9002 1102@2:9003 1103@1:9004 1104@1:9005 1104@23:9005 "
    .. "1104@2:9005",
    "every (instance, difficulty, encounter) was visited")
checkEq(seen["1101@14:9001"], 1, "a loot list that arrives first time is read once")
checkEq(seen["1104@2:9005"], 2, "a slow loot list is read again by the retry pass")
checkEq(seen["1103@1:9004"], 1, "a clean difficulty is not retried just because a sibling failed")

checkEq(stub.ej.difficulty, 14, "player's journal difficulty restored after the scan")
check(stub.chatHas("Second pass recovered"), "the retry pass reported a recovered loot list")
checkEq(stub.ej.tier, 1, "player's journal tier restored after the scan")

-- ── the stored whitelist ────────────────────────────────────────────────────
print("\n[2] difficultyIDs whitelist")
local journal = WN.db.global.trackDB and WN.db.global.trackDB.journal
check(journal ~= nil, "journal namespace written")

local function whitelist(encID, itemID)
    local list = journal and journal.encounters and journal.encounters[encID]
    if not list then return "NO ENCOUNTER" end
    for i = 1, #list do
        if list[i].itemID == itemID then
            local ids = list[i].difficultyIDs
            return ids and table.concat(ids, ",") or "none"
        end
    end
    return "NO ROW"
end

checkEq(whitelist(RAID_ENC, MYTHIC_MOUNT), "16", "mount seen only on Mythic is restricted to 16")
checkEq(whitelist(RAID_ENC, COMMON_MOUNT), "none", "mount seen on all three raid difficulties is unrestricted")
checkEq(whitelist(DUN_ENC_A, DUN_PET), "none", "pet on every dungeon difficulty is unrestricted")
checkEq(whitelist(DUN_ENC_B, DUN_PET), "none", "the dungeon's second encounter was recorded too")
checkEq(whitelist(PARTIAL_ENC, PARTIAL_MOUNT), "none",
    "encounter whose loot list never arrives is left unrestricted, not wrongly narrowed")
checkEq(whitelist(SLOW_ENC, SLOW_MOUNT), "23",
    "a merely slow loot list is recovered by the retry pass, so the whitelist still lands")

-- ── the payoff: real ENCOUNTER_END through the shipped handler ──────────────
print("\n[3] ENCOUNTER_END honours the whitelist")
local function countOf(itemID)
    return WN:GetTryCount("mount", itemID) or 0
end
local function killRaidBoss(difficultyID)
    -- The journal lane dedupes on its own source key for 15s; move the clock past it.
    stub.Advance(20)
    RT.lastTryCountSourceKey, RT.lastTryCountSourceTime = nil, nil
    stub.Fire("ENCOUNTER_END", RAID_ENC, "Journal Test Boss", difficultyID, 20, 1)
    stub.Advance(5)
end

local mythicBefore, commonBefore = countOf(MYTHIC_MOUNT), countOf(COMMON_MOUNT)
killRaidBoss(14)
checkEq(countOf(MYTHIC_MOUNT), mythicBefore, "Mythic-only mount takes NO attempt from a Normal kill")
check(countOf(COMMON_MOUNT) > commonBefore, "unrestricted mount still counts on a Normal kill")

local mythicBefore2 = countOf(MYTHIC_MOUNT)
killRaidBoss(16)
check(countOf(MYTHIC_MOUNT) > mythicBefore2, "Mythic-only mount counts on a Mythic kill")

-- ── errors ──────────────────────────────────────────────────────────────────
print("\n[4] no errors raised")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
checkEq(#stub.errors, 0, "no errors from timers or event handlers")

print(string.format("\n%d checks, %d failed", totalChecks, failures))
os.exit(failures == 0 and 0 or 1)
