#!/usr/bin/env lua5.1
--[[
    Warband Nexus - Unit Test: Dead Run Tracker & Shopping List
    Tests:
    1. GetVaultDeadRunAnalysis (Mythic+ and Delves/World)
    2. GetRecipeMissingReagents & FormatShoppingList
]]

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    assert_eq(not not cond, true, msg)
end

print("phase 1: Mythic+ Great Vault Dead Run Analysis")

-- Mock addon environment
local ns = {}
local WarbandNexus = {
    db = {
        global = {
            pveCache = {
                greatVault = { activities = {} },
                mythicPlus = { runHistory = {} },
            }
        }
    }
}

-- Load PvECacheService functions under test
function WarbandNexus:GetPvEData(charKey)
    local dbCache = self.db.global.pveCache
    return {
        mythicPlus = {
            runHistory = dbCache.mythicPlus.runHistory[charKey] or {},
        },
        vaultActivities = dbCache.greatVault.activities[charKey] or {},
    }
end

-- Inline the GetVaultDeadRunAnalysis implementation
function WarbandNexus:GetVaultDeadRunAnalysis(charKey)
    local pve = self:GetPvEData(charKey) or {}
    local analysis = {
        mythicPlus = {
            totalRuns = 0,
            deadRunFloor = nil,
            deadRunsCount = 0,
            slotTargets = {},
            sortedRuns = {},
        },
        world = {
            totalActivities = 0,
            deadRunFloor = nil,
            deadRunsCount = 0,
            slotTargets = {},
            sortedActivities = {},
        },
    }

    -- 1. Mythic+ Analysis
    local rawRuns = pve.mythicPlus and pve.mythicPlus.runHistory
    local runs = {}
    if rawRuns and type(rawRuns) == "table" then
        for i = 1, #rawRuns do
            local r = rawRuns[i]
            if r and type(r) == "table" then
                runs[#runs + 1] = {
                    level = tonumber(r.level) or 0,
                    mapChallengeModeID = r.mapChallengeModeID,
                    dungeon = r.dungeon or r.name,
                }
            end
        end
    end
    table.sort(runs, function(a, b)
        local aLvl = a.level or 0
        local bLvl = b.level or 0
        if aLvl ~= bLvl then return aLvl > bLvl end
        return (a.mapChallengeModeID or 0) < (b.mapChallengeModeID or 0)
    end)
    analysis.mythicPlus.sortedRuns = runs
    analysis.mythicPlus.totalRuns = #runs

    local mplusThresholds = { 1, 4, 8 }
    local mplusBaseRuns = { 1, 4, 8 }
    if #runs >= 8 then
        analysis.mythicPlus.deadRunFloor = runs[8].level
        analysis.mythicPlus.deadRunsCount = #runs - 8
    end

    for s = 1, 3 do
        local thresh = mplusThresholds[s]
        local baseIdx = mplusBaseRuns[s]
        local runAtBase = runs[baseIdx]
        local isUnlocked = (#runs >= thresh)
        local curLevel = (isUnlocked and runAtBase) and runAtBase.level or 0
        local nextNeeded = isUnlocked and (curLevel + 1) or nil
        analysis.mythicPlus.slotTargets[s] = {
            slotIndex = s,
            threshold = thresh,
            baseRunIndex = baseIdx,
            isUnlocked = isUnlocked,
            currentLevel = curLevel,
            nextLevelNeeded = nextNeeded,
            runsRemaining = isUnlocked and 0 or (thresh - #runs),
        }
    end

    -- 2. World / Delves Analysis
    local worldTierProgress = pve.vaultActivities and pve.vaultActivities.worldTierProgress
    local worldActivities = {}
    if worldTierProgress and type(worldTierProgress) == "table" then
        for wi = 1, #worldTierProgress do
            local entry = worldTierProgress[wi]
            local count = tonumber(entry.numPoints) or 0
            local tier = tonumber(entry.difficulty) or 0
            for _ = 1, count do
                worldActivities[#worldActivities + 1] = { tier = tier }
            end
        end
    end
    table.sort(worldActivities, function(a, b)
        return (a.tier or 0) > (b.tier or 0)
    end)
    analysis.world.sortedActivities = worldActivities
    analysis.world.totalActivities = #worldActivities

    local worldThresholds = { 2, 4, 8 }
    local worldBaseActivities = { 2, 4, 8 }
    if #worldActivities >= 8 then
        analysis.world.deadRunFloor = worldActivities[8].tier
        analysis.world.deadRunsCount = #worldActivities - 8
    end

    for s = 1, 3 do
        local thresh = worldThresholds[s]
        local baseIdx = worldBaseActivities[s]
        local actAtBase = worldActivities[baseIdx]
        local isUnlocked = (#worldActivities >= thresh)
        local curTier = (isUnlocked and actAtBase) and actAtBase.tier or 0
        local nextNeeded = isUnlocked and (curTier + 1) or nil
        analysis.world.slotTargets[s] = {
            slotIndex = s,
            threshold = thresh,
            baseRunIndex = baseIdx,
            isUnlocked = isUnlocked,
            currentTier = curTier,
            nextTierNeeded = nextNeeded,
            activitiesRemaining = isUnlocked and 0 or (thresh - #worldActivities),
        }
    end

    return analysis
end

-- Case 1: 0 runs
local res0 = WarbandNexus:GetVaultDeadRunAnalysis("Char-Zero")
assert_eq(res0.mythicPlus.totalRuns, 0, "0 runs total")
assert_eq(res0.mythicPlus.deadRunFloor, nil, "0 runs: deadRunFloor is nil")
assert_eq(res0.mythicPlus.slotTargets[1].isUnlocked, false, "Slot 1 locked with 0 runs")
assert_eq(res0.mythicPlus.slotTargets[1].runsRemaining, 1, "Slot 1 needs 1 run")

-- Case 2: 4 runs (+10, +10, +8, +6)
WarbandNexus.db.global.pveCache.mythicPlus.runHistory["Char-4"] = {
    { level = 8, name = "Dungeon A" },
    { level = 10, name = "Dungeon B" },
    { level = 6, name = "Dungeon C" },
    { level = 10, name = "Dungeon D" },
}
local res4 = WarbandNexus:GetVaultDeadRunAnalysis("Char-4")
assert_eq(res4.mythicPlus.totalRuns, 4, "4 runs total")
assert_eq(res4.mythicPlus.deadRunFloor, nil, "4 runs: deadRunFloor is nil (all count towards unlocking)")
assert_eq(res4.mythicPlus.slotTargets[1].isUnlocked, true, "Slot 1 unlocked")
assert_eq(res4.mythicPlus.slotTargets[1].currentLevel, 10, "Slot 1 based on +10")
assert_eq(res4.mythicPlus.slotTargets[1].nextLevelNeeded, 11, "Slot 1 upgrade needs +11")
assert_eq(res4.mythicPlus.slotTargets[2].isUnlocked, true, "Slot 2 unlocked")
assert_eq(res4.mythicPlus.slotTargets[2].currentLevel, 6, "Slot 2 based on 4th run (+6)")
assert_eq(res4.mythicPlus.slotTargets[2].nextLevelNeeded, 7, "Slot 2 upgrade needs +7")
assert_eq(res4.mythicPlus.slotTargets[3].isUnlocked, false, "Slot 3 locked")
assert_eq(res4.mythicPlus.slotTargets[3].runsRemaining, 4, "Slot 3 needs 4 more runs")

-- Case 3: 10 runs (8 maxed, 2 dead runs)
WarbandNexus.db.global.pveCache.mythicPlus.runHistory["Char-10"] = {
    { level = 15 }, { level = 14 }, { level = 12 }, { level = 12 },
    { level = 11 }, { level = 10 }, { level = 10 }, { level = 9 },
    { level = 7 }, { level = 5 },
}
local res10 = WarbandNexus:GetVaultDeadRunAnalysis("Char-10")
assert_eq(res10.mythicPlus.totalRuns, 10, "10 runs total")
assert_eq(res10.mythicPlus.deadRunFloor, 9, "Dead run floor is +9 (8th run)")
assert_eq(res10.mythicPlus.deadRunsCount, 2, "2 runs beyond top 8 (dead runs)")
assert_eq(res10.mythicPlus.slotTargets[1].currentLevel, 15, "Slot 1 based on +15")
assert_eq(res10.mythicPlus.slotTargets[1].nextLevelNeeded, 16, "Slot 1 upgrade needs +16")
assert_eq(res10.mythicPlus.slotTargets[2].currentLevel, 12, "Slot 2 based on +12")
assert_eq(res10.mythicPlus.slotTargets[2].nextLevelNeeded, 13, "Slot 2 upgrade needs +13")
assert_eq(res10.mythicPlus.slotTargets[3].currentLevel, 9, "Slot 3 based on +9")
assert_eq(res10.mythicPlus.slotTargets[3].nextLevelNeeded, 10, "Slot 3 upgrade needs +10")

print("phase 2: Delves/World Great Vault Dead Run Analysis")
WarbandNexus.db.global.pveCache.greatVault.activities["Char-World"] = {
    worldTierProgress = {
        { difficulty = 8, numPoints = 4 },
        { difficulty = 7, numPoints = 3 },
        { difficulty = 4, numPoints = 2 },
    }
}
local resWorld = WarbandNexus:GetVaultDeadRunAnalysis("Char-World")
assert_eq(resWorld.world.totalActivities, 9, "9 total delve activities")
assert_eq(resWorld.world.deadRunFloor, 4, "Dead run floor is Tier 4")
assert_eq(resWorld.world.deadRunsCount, 1, "1 dead delve run")
assert_eq(resWorld.world.slotTargets[1].currentTier, 8, "Slot 1 (2nd run) is Tier 8")
assert_eq(resWorld.world.slotTargets[2].currentTier, 8, "Slot 2 (4th run) is Tier 8")
assert_eq(resWorld.world.slotTargets[3].currentTier, 4, "Slot 3 (8th run) is Tier 4")
assert_eq(resWorld.world.slotTargets[3].nextTierNeeded, 5, "Slot 3 upgrade needs Tier 5")

print("phase 3: Crafting Order Shopping List")

function WarbandNexus:FormatShoppingList(missingData)
    if not missingData or not missingData.missingReagents then return "" end
    local lines = {}
    local title = missingData.recipeName or "Shopping List"
    lines[#lines + 1] = "Warband Nexus: " .. title
    for i = 1, #missingData.missingReagents do
        local r = missingData.missingReagents[i]
        lines[#lines + 1] = string.format("- %dx %s", r.missing, r.name)
    end
    return table.concat(lines, "\n")
end

local mockMissing = {
    recipeName = "Test Midnight Chest",
    missingReagents = {
        { itemID = 101, name = "Bismuth", needed = 20, have = 8, missing = 12 },
        { itemID = 102, name = "Null Stone", needed = 4, have = 0, missing = 4 },
    }
}
local formatted = WarbandNexus:FormatShoppingList(mockMissing)
assert_true(formatted:find("Warband Nexus: Test Midnight Chest") ~= nil, "Header in formatted list")
assert_true(formatted:find("- 12x Bismuth") ~= nil, "Bismuth in formatted list")
assert_true(formatted:find("- 4x Null Stone") ~= nil, "Null Stone in formatted list")

print(string.format("test_dead_run_and_shopping_list: %d checks passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
