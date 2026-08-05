#!/usr/bin/env lua5.1
-- Regression: ImportLegacy / ProcessGreatVault / SyncVault must not replace
-- completed vault rows with non-empty zero-progress current-week snapshots.
-- Mirrors ShouldPreserveCompletedVaultRows + ImportLegacy skip decision.

local function GreatVaultActivityHasCompletedRows(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    local gvCategories = { "raids", "mythicPlus", "world", "pvp" }
    for ci = 1, #gvCategories do
        local rows = bucket[gvCategories[ci]]
        if type(rows) == "table" then
            for i = 1, #rows do
                local row = rows[i]
                local progress = row and tonumber(row.progress) or 0
                local threshold = row and tonumber(row.threshold) or 0
                if threshold > 0 and progress >= threshold then
                    return true
                end
            end
        end
    end
    return false
end

local function ShouldPreserveCompletedVaultRows(prevBucket, incomingHasCompleted, rewardClaimedThisReset, previousResetTime)
    if not GreatVaultActivityHasCompletedRows(prevBucket) then
        return false, false
    end
    if rewardClaimedThisReset or incomingHasCompleted then
        return false, false
    end
    local storedBeforeReset = previousResetTime and (tonumber(prevBucket.lastUpdate) or 0) < previousResetTime
    return true, storedBeforeReset and true or false
end

local function LegacyGreatVaultArrayHasCompleted(legacyArr)
    if type(legacyArr) ~= "table" then return false end
    for i = 1, #legacyArr do
        local activity = legacyArr[i]
        local progress = activity and tonumber(activity.progress) or 0
        local threshold = activity and tonumber(activity.threshold) or 0
        if threshold > 0 and progress >= threshold then
            return true
        end
    end
    return false
end

local function GreatVaultActivityHasRows(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    if bucket.raids and #bucket.raids > 0 then return true end
    if bucket.mythicPlus and #bucket.mythicPlus > 0 then return true end
    if bucket.world and #bucket.world > 0 then return true end
    if bucket.pvp and #bucket.pvp > 0 then return true end
    return false
end

-- Simulate ImportLegacy replace decision (old vs new).
local function WouldImportReplace(prevVault, legacyGreatVault, rewardClaimedThisReset, previousResetTime)
    local incomingCompleted = LegacyGreatVaultArrayHasCompleted(legacyGreatVault)
    local preserveRows = ShouldPreserveCompletedVaultRows(
        prevVault, incomingCompleted, rewardClaimedThisReset, previousResetTime)
    if #legacyGreatVault == 0 and GreatVaultActivityHasRows(prevVault) then
        return false, "empty"
    end
    if preserveRows then
        return false, "preserve"
    end
    return true, "replace"
end

local function OldWouldImportReplace(prevVault, legacyGreatVault)
    -- Old code only skipped empty arrays.
    if #legacyGreatVault == 0 and GreatVaultActivityHasRows(prevVault) then
        return false, "empty"
    end
    return true, "replace"
end

local failures = 0
local function assertTrue(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local weekStart = 1000000
local prevCompleted = {
    lastUpdate = weekStart - 100,
    weeklyResetTime = weekStart,
    mythicPlus = {
        { progress = 8, threshold = 8, rewardItemLevel = 639 },
        { progress = 4, threshold = 8 },
        { progress = 0, threshold = 8 },
    },
    raids = {},
    world = {},
    pvp = {},
}

local zeroProgressIncoming = {
    { type = 2, progress = 0, threshold = 1 },
    { type = 2, progress = 0, threshold = 4 },
    { type = 2, progress = 0, threshold = 8 },
    { type = 1, progress = 0, threshold = 2 },
    { type = 1, progress = 0, threshold = 4 },
    { type = 1, progress = 0, threshold = 6 },
    { type = 4, progress = 0, threshold = 2 },
    { type = 4, progress = 0, threshold = 4 },
    { type = 4, progress = 0, threshold = 8 },
}

-- 1) Post-reset: old path clobbers; new path preserves + markPostReset
do
    local oldReplace = OldWouldImportReplace(prevCompleted, zeroProgressIncoming)
    assertTrue(oldReplace == true, "old ImportLegacy must replace zero-progress over completed (bug repro)")
    local replace, why = WouldImportReplace(prevCompleted, zeroProgressIncoming, false, weekStart)
    assertTrue(replace == false and why == "preserve", "new ImportLegacy preserves post-reset completed over zero-progress")
    local preserve, markPost = ShouldPreserveCompletedVaultRows(prevCompleted, false, false, weekStart)
    assertTrue(preserve and markPost, "post-reset preserve must set isPostReset")
end

-- 2) Mid-week completed + zero incoming (API race): preserve without postReset
do
    local midWeek = {
        lastUpdate = weekStart + 50,
        mythicPlus = { { progress = 8, threshold = 8 } },
        raids = {}, world = {}, pvp = {},
    }
    local preserve, markPost = ShouldPreserveCompletedVaultRows(midWeek, false, false, weekStart)
    assertTrue(preserve and not markPost, "mid-week race preserves without isPostReset")
    local replace = WouldImportReplace(midWeek, zeroProgressIncoming, false, weekStart)
    assertTrue(replace == false, "ImportLegacy must not wipe mid-week completed with zeros")
end

-- 3) Claimed this reset: allow replace with zeros (fresh week after claim)
do
    local preserve = ShouldPreserveCompletedVaultRows(prevCompleted, false, true, weekStart)
    assertTrue(not preserve, "claimed-this-reset must not preserve old completed rows")
    local replace = WouldImportReplace(prevCompleted, zeroProgressIncoming, true, weekStart)
    assertTrue(replace == true, "ImportLegacy replaces after claim stamp")
end

-- 4) Incoming has a completed slot: allow replace (new progress this week)
do
    local incomingDone = {
        { type = 2, progress = 1, threshold = 1 },
        { type = 2, progress = 0, threshold = 4 },
    }
    local preserve = ShouldPreserveCompletedVaultRows(prevCompleted, true, false, weekStart)
    assertTrue(not preserve, "incoming completed must clear preserve")
    local replace = WouldImportReplace(prevCompleted, incomingDone, false, weekStart)
    assertTrue(replace == true, "ImportLegacy applies when incoming has completed slots")
end

-- 5) Empty incoming still skipped when cache has rows
do
    local replace, why = WouldImportReplace(prevCompleted, {}, false, weekStart)
    assertTrue(replace == false and why == "empty", "empty legacy array still skipped")
end

-- 6) Heuristic basis: CountEarnedVaultSlots would go 1→0 under old replace
do
    local function countEarned(acts)
        local n = 0
        for _, cat in ipairs({ acts.raids, acts.mythicPlus, acts.world }) do
            if cat then
                for _, a in ipairs(cat) do
                    local p = tonumber(a.progress) or 0
                    local t = tonumber(a.threshold) or 0
                    if t > 0 and p >= t then n = n + 1 end
                end
            end
        end
        return n
    end
    assertTrue(countEarned(prevCompleted) == 1, "fixture has one earned slot")
    -- Old replace would build zero-progress buckets → earned 0 (badge heuristic dies)
    local wiped = { raids = { { progress = 0, threshold = 2 } }, mythicPlus = { { progress = 0, threshold = 1 } }, world = {} }
    assertTrue(countEarned(wiped) == 0, "zero-progress replace destroys earned-slot heuristic")
end

if failures > 0 then
    io.stderr:write(string.format("%d assertion(s) failed\n", failures))
    os.exit(1)
end
print("test_vault_preserve_import: ok")
