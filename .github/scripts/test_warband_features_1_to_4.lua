#!/usr/bin/env lua
--[[
    Warband Nexus - Unit Test: Features 1 - 4 Validation Suite
    Target: Midnight 12.1.0 (## Interface: 120100)

    Tests:
    1. Warband Concentration Burn & Transmute Yield Optimizer
       - Projection math: 10 pts/hr = 1 pt / 360s
       - Cap countdown & alerts
       - Priority queue sorting
    2. Warband Crest & High Watermark Cascade Simulator
       - Multi-alt crest discount calculations (15 crests / step)
       - Source alt exclusion & watermark thresholding
    3. Warband Strategic Staging & Rare Proximity Dispatcher
       - Coordinate persistence & Euclidean distance scoring
       - Resting status & eligibility filtering
    4. Warband Great Vault & Keystone Synergy Choreographer
       - Alt keystone rating potential matrix
       - Keystone reroll recommendations & needy alt counts
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

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."

-- Load stub environment
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")
table.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local ns = {}
local WarbandNexus = {}
ns.WarbandNexus = WarbandNexus

-- Mock AceDB
WarbandNexus.db = {
    profile = {
        themeMode = "dark",
    },
    global = {
        characters = {},
        accountWatermarks = {},
        pveCache = {
            mythicPlus = { runHistory = {} },
            greatVault = { activities = {} },
        },
    },
    char = {},
}
WarbandNexus.RegisterMessage = function(...) end
WarbandNexus.SendMessage = function(...) end
WarbandNexus.RegisterEvent = function(...) end
WarbandNexus.Print = function(...) end
WarbandNexus.Debug = function(...) end
WarbandNexus.ScheduleTimer = function(self, fn, delay) return _G.C_Timer.NewTimer(delay, fn) end
WarbandNexus.CancelTimer = function(self, t) if t and t.Cancel then t:Cancel() end end

ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = { SVC = "svc" }, Start = function() end, Stop = function() end }
ns.Utilities = {
    GetCanonicalCharacterKey = function(_, k) return k end,
    ResolveKeystoneDungeonName = function(_, mk) return mk and mk.dungeonName or "Keystone" end,
    GetCharacterStorageKey = function() return "Player-01" end,
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
assert_true(type(ns.L) == "table", "ns.L populated")

-- Load service modules
LoadFile("Modules/Constants.lua")
LoadFile("Modules/Data/SeasonData.lua")
LoadFile("Modules/GearService_Slots.lua")
LoadFile("Modules/GearService_UpgradeTracks.lua")
LoadFile("Modules/GearService.lua")
LoadFile("Modules/ProfessionService.lua")
LoadFile("Modules/CharacterService.lua")
LoadFile("Modules/TryCounterService_Shared.lua")
LoadFile("Modules/PvECacheService.lua")

print("=== Phase 1: Warband Concentration Burn & Transmute Yield Optimizer ===")
do
    local now = time()
    WarbandNexus.db.global.characters["Player-01"] = {
        name = "AlchemistMain",
        classFile = "MAGE",
        concentration = {
            [171] = { current = 400, max = 1000, lastUpdate = now - 3600 } -- 1 hour ago: gained 10 pts -> 410
        }
    }
    WarbandNexus.db.global.characters["Player-02"] = {
        name = "BlacksmithAlt",
        classFile = "WARRIOR",
        concentration = {
            [164] = { current = 980, max = 1000, lastUpdate = now - 7200 } -- 2 hours ago: gained 20 pts -> 1000 (CAPPED)
        }
    }
    WarbandNexus.db.global.characters["Player-03"] = {
        name = "TailorAlt",
        classFile = "PRIEST",
        concentration = {
            [197] = { current = 950, max = 1000, lastUpdate = now - 360 } -- 6 mins ago: gained 1 pt -> 951, remaining 49 pts = 17640s = 4.9 hrs
        }
    }

    local p1 = WarbandNexus:GetProjectedConcentration("Player-01", 171)
    assert_eq(p1.projected, 410, "Player-01 projected concentration after 1 hour (400 + 10)")
    assert_eq(p1.isCapped, false, "Player-01 is not capped")
    assert_eq(p1.secondsToCap, (1000 - 410) * 360, "Player-01 seconds to cap matches remaining * 360")

    local p2 = WarbandNexus:GetProjectedConcentration("Player-02", 164)
    assert_eq(p2.projected, 1000, "Player-02 capped at 1000 after 2 hours")
    assert_eq(p2.isCapped, true, "Player-02 isCapped is true")
    assert_eq(p2.secondsToCap, 0, "Player-02 secondsToCap is 0")

    local alerts = WarbandNexus:GetConcentrationExpiringAlerts(6) -- alert if capping within 6 hours
    assert_eq(#alerts, 2, "Found 2 characters capping within 6 hours (Player-02 already capped, Player-03 in 4.9h)")

    local queue = WarbandNexus:GetConcentrationQueue()
    assert_eq(#queue, 3, "Queue returned 3 concentration records")
    assert_eq(queue[1].charName, "BlacksmithAlt", "Highest priority is BlacksmithAlt (0s to cap)")
    assert_eq(queue[2].charName, "TailorAlt", "Second priority is TailorAlt")
    assert_eq(queue[3].charName, "AlchemistMain", "Lowest priority is AlchemistMain")
end

print("=== Phase 2: Warband Crest & High Watermark Cascade Simulator ===")
do
    -- Set account watermark for Chest (slot 5) to 630
    WarbandNexus.db.global.accountWatermarks[5] = 630

    -- Add alts with chest gear below 639
    WarbandNexus.db.global.gearData = {
        ["Player-01"] = {
            slots = {
                [5] = { itemLevel = 630, currUpgrade = 4, maxUpgrade = 8, upgradeTrack = "Hero" }
            }
        },
        ["Player-02"] = {
            slots = {
                [5] = { itemLevel = 619, currUpgrade = 1, maxUpgrade = 8, upgradeTrack = "Champion" }
            }
        },
        ["Player-03"] = {
            slots = {
                [5] = { itemLevel = 606, currUpgrade = 0, maxUpgrade = 8, upgradeTrack = "Veteran" }
            }
        },
    }

    -- Player-01 upgrades chest to 639
    local cascade = WarbandNexus:SimulateWatermarkCascade(5, 639, "Player-01")
    assert_true(cascade ~= nil, "Cascade simulation returned result")
    assert_eq(#cascade.affectedAlts, 2, "Excluded source player Player-01; 2 alts affected")
    assert_true(cascade.totalCrestsSaved > 0, "Total crests saved is greater than 0")
    -- Player-02: baseline was 630 (account watermark > 619). ilvlDiff = 639 - 630 = 9. steps = 2. savings = 30 crests.
    -- Player-03: baseline was 630. ilvlDiff = 9. steps = 2. savings = 30 crests.
    assert_eq(cascade.totalCrestsSaved, 60, "Calculated exactly 60 crests saved across Warband")
    assert_eq(cascade.crestType, "Mistcrest", "Correct Midnight crest type")
end

print("=== Phase 3: Warband Strategic Staging & Rare Proximity Dispatcher ===")
do
    -- Locations
    -- Target is in Isle of Dorn (map 2248) at (0.45, 0.55)
    WarbandNexus.db.global.characters["Player-01"].uiMapID = 2248
    WarbandNexus.db.global.characters["Player-01"].mapX = 0.46
    WarbandNexus.db.global.characters["Player-01"].mapY = 0.56
    WarbandNexus.db.global.characters["Player-01"].zoneName = "Isle of Dorn"
    WarbandNexus.db.global.characters["Player-01"].isResting = false

    -- Player-02 is in Dornogal (map 2339) resting
    WarbandNexus.db.global.characters["Player-02"].uiMapID = 2339
    WarbandNexus.db.global.characters["Player-02"].mapX = 0.50
    WarbandNexus.db.global.characters["Player-02"].mapY = 0.50
    WarbandNexus.db.global.characters["Player-02"].zoneName = "Dornogal"
    WarbandNexus.db.global.characters["Player-02"].isResting = true

    -- Player-03 is in Ringing Deeps (map 2214) not resting
    WarbandNexus.db.global.characters["Player-03"].uiMapID = 2214
    WarbandNexus.db.global.characters["Player-03"].mapX = 0.30
    WarbandNexus.db.global.characters["Player-03"].mapY = 0.30
    WarbandNexus.db.global.characters["Player-03"].zoneName = "The Ringing Deeps"
    WarbandNexus.db.global.characters["Player-03"].isResting = false

    local dispatch = WarbandNexus:FindNearestEligibleAlt("RareNPC-12345", 2248, 0.45, 0.55)
    assert_true(dispatch ~= nil, "Dispatch found candidate alts")
    assert_eq(dispatch.bestAlt.charName, "AlchemistMain", "Player-01 is nearest (in same zone, adjacent coordinates)")
    assert_true(dispatch.bestAlt.score < dispatch.allAlts[2].score, "Best alt has lower distance score")
    assert_eq(dispatch.allAlts[2].charName, "BlacksmithAlt", "Second nearest is resting in capital city (score 30)")
    assert_eq(dispatch.allAlts[3].charName, "TailorAlt", "Third is in another zone non-resting (score 70)")
end

print("=== Phase 4: Warband Great Vault & Keystone Synergy Choreographer ===")
do
    -- Player-01 has a +10 Ara-Kara keystone
    WarbandNexus.db.global.characters["Player-01"].mythicKey = {
        level = 10,
        dungeonName = "Ara-Kara, City of Echoes",
        mapChallengeModeID = 501,
    }

    -- Player-01 completed +10 Ara-Kara run
    WarbandNexus.db.global.pveCache.mythicPlus.runHistory["Player-01"] = {
        { dungeon = "Ara-Kara, City of Echoes", level = 10 },
    }

    -- Player-02 best Ara-Kara run is +6
    WarbandNexus.db.global.pveCache.mythicPlus.runHistory["Player-02"] = {
        { dungeon = "Ara-Kara, City of Echoes", level = 6 },
        { dungeon = "The Stonevault", level = 8 },
    }

    -- Player-03 has no runs in Ara-Kara (best is 0)
    WarbandNexus.db.global.pveCache.mythicPlus.runHistory["Player-03"] = {
        { dungeon = "The Dawnbreaker", level = 7 },
    }

    local synergies = WarbandNexus:GetKeystoneSynergyMatrix()
    assert_true(#synergies > 0, "Synergies matrix produced results")
    local topSyn = synergies[1]
    assert_eq(topSyn.holderName, "AlchemistMain", "Top synergy holder is AlchemistMain (+10 Ara-Kara)")
    assert_eq(#topSyn.beneficiaries, 2, "Both Player-02 and Player-03 are beneficiaries")

    -- Player-03: delta = 10 - 0 = 10 -> rating gain = floor(10 * 7.5) = 75
    -- Player-02: delta = 10 - 6 = 4 -> rating gain = floor(4 * 7.5) = 30
    assert_eq(topSyn.beneficiaries[1].charName, "TailorAlt", "TailorAlt gets highest rating gain (75)")
    assert_eq(topSyn.beneficiaries[2].charName, "BlacksmithAlt", "BlacksmithAlt gets 30 rating gain")

    -- Keystone reroll recommendations targeting dungeons under level 8
    local recs = WarbandNexus:GetKeystoneRerollRecommendations(8)
    assert_true(#recs > 0, "Reroll recommendations produced results")
    -- Ara-Kara has 2 alts under +8 (Player-02 at 6, Player-03 at 0)
    local araKara = nil
    for _, r in ipairs(recs) do
        if r.dungeonName == "Ara-Kara, City of Echoes" then
            araKara = r
            break
        end
    end
    assert_true(araKara ~= nil, "Ara-Kara recommended for rerolls")
    assert_eq(araKara.needyCount, 2, "2 alts need Ara-Kara to reach +8")
end

print(string.format("\ntest_warband_features_1_to_4: %d checks passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
