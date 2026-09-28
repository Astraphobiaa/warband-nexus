#!/usr/bin/env lua5.1
--[[
    Offline Simulation Test Module for Try Counter (Encounter, Raid, Dungeon, Chest, Trash, Secret Values)
    
    Target: Midnight 12.1.0 (Lua 5.1).
    This file is located in .github/scripts/ and excluded from releases via .pkgmeta.
    It drives the real shipped addon files end-to-end through simulated combat, instances,
    loot windows, auto-loot, chests, trash pulls, and secret values without needing live in-game testing.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, Fns, RT = H.stub, H.WN, H.Fns, H.RT

local failures = 0
local totalChecks = 0

local function check(cond, msg)
    totalChecks = totalChecks + 1
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local function GetCount(tcType, tryKey)
    return WN:GetTryCount(tcType, tryKey) or 0
end

local corpseSeq = 1000
local function MakeCreatureGUID(npcID)
    corpseSeq = corpseSeq + 1
    return ("Creature-0-0-0-0-%d-%012d"):format(npcID, corpseSeq)
end

local function MakeGameObjectGUID(objID)
    corpseSeq = corpseSeq + 1
    return ("GameObject-0-0-0-0-%d-%012d"):format(objID, corpseSeq)
end

local function ResetState()
    stub.Reset()
    stub.ClearSecrets()
    stub.world.lootSlots = {}
    stub.world.lootSources = {}
    stub.world.isFishingLoot = false
end

-- =========================================================================
-- Phase 1: Dungeon Boss without statisticIds (Bloodlord Mandokir - Raptor)
-- =========================================================================
print("Phase 1: Dungeon Boss (Bloodlord Mandokir - Armored Razzashi Raptor)")
local MANDOKIR_NPC = 52151
local MANDOKIR_ENC = 1179
local RAPTOR_ITEM = 68823
local GURUBASHI_TRASH_NPC = 52156 -- Gurubashi Blood Drinker (trash)

check(RT.encounterDB[MANDOKIR_ENC] ~= nil, "Mandokir is in encounterDB")
check(RT.npcDropDB[MANDOKIR_NPC] ~= nil, "Mandokir is in npcDropDB")
local baseMandokirCount = GetCount("mount", RAPTOR_ITEM)

-- 1.1: Standard Boss Kill + Corpse Loot (Mount miss)
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(5)

-- Pull
stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(30) -- 30s fight

-- Kill
stub.Fire("ENCOUNTER_END", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5, 1)
stub.Advance(2) -- walk to corpse

-- Loot boss corpse
local mandokirCorpse = MakeCreatureGUID(MANDOKIR_NPC)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:69605::::::::::::::::|h[Decapitating Sword]|h" } }
stub.world.lootSources = { { mandokirCorpse, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local countAfterKill = GetCount("mount", RAPTOR_ITEM)
check(countAfterKill == baseMandokirCount + 1, ("Mandokir kill + corpse loot counted exactly +1 (got %d, expected %d)"):format(countAfterKill, baseMandokirCount + 1))

-- 1.2: MANDOKIR REGRESSION: Subsequent Trash Packs must NEVER increment the boss counter!
local trashAttemptsBefore = GetCount("mount", RAPTOR_ITEM)
for p = 1, 5 do
    ResetState()
    stub.world.inInstance = true
    stub.world.instanceType = "party"
    stub.Advance(10)
    
    local trashCorpse = MakeCreatureGUID(GURUBASHI_TRASH_NPC)
    stub.world.lootSlots = {
        { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen Cloth]|h" },
        { hasItem = true, link = "|Hitem:4306::::::::::::::::|h[Silk Cloth]|h" },
    }
    stub.world.lootSources = { { trashCorpse, 1 }, { trashCorpse, 1 } }
    
    -- Loot window on trash corpse
    stub.Fire("LOOT_READY", true)
    stub.Fire("LOOT_OPENED", true, false)
    stub.Advance(0.5)
    stub.Fire("LOOT_CLOSED")
    
    -- Chat loot messages from trash
    stub.Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589::::::::::::::::|h[Linen Cloth]|h.")
    stub.Fire("CHAT_MSG_LOOT", "Player2 receives loot: |cffffffff|Hitem:4306::::::::::::::::|h[Silk Cloth]|h.")
    stub.Advance(2)
end

local trashAttemptsAfter = GetCount("mount", RAPTOR_ITEM)
check(trashAttemptsAfter == trashAttemptsBefore, ("5 trash packs produced ZERO boss attempts (before: %d, after: %d)"):format(trashAttemptsBefore, trashAttemptsAfter))

-- 1.3: Fast Auto-Loot on Dungeon Boss (no LOOT_OPENED event)
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(20)

stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(25)
stub.Fire("ENCOUNTER_END", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5, 1)
stub.Advance(1)

local autoLootCorpse = MakeCreatureGUID(MANDOKIR_NPC)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:69605::::::::::::::::|h[Decapitating Sword]|h" } }
stub.world.lootSources = { { autoLootCorpse, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_CLOSED") -- fast auto-loot fires closed without opened
stub.Advance(3)

check(GetCount("mount", RAPTOR_ITEM) == trashAttemptsAfter + 1, "Fast auto-loot counted boss attempt successfully (+1)")

-- 1.4: Walkaway / Lootless Kill (Personal Loot / player never loots corpse)
local countBeforeWalkaway = GetCount("mount", RAPTOR_ITEM)
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(20)

stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(30)
stub.Fire("ENCOUNTER_END", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5, 1)

-- Player does NOT loot anything and walks away
-- Fallback timer is scheduled at 4s and 10s
stub.Advance(15)

local countAfterWalkaway = GetCount("mount", RAPTOR_ITEM)
check(countAfterWalkaway == countBeforeWalkaway + 1, ("Lootless / walkaway kill counted via delayed fallback (+1, got %d)"):format(countAfterWalkaway))

-- =========================================================================
-- Phase 2: Consecutive Bosses in Same Dungeon Run (Mandokir -> Kilnara)
-- =========================================================================
print("Phase 2: Consecutive Bosses in Same Instance (Kilnara - Swift Zulian Panther)")
local KILNARA_NPC = 52059
local KILNARA_ENC = 1180
local PANTHER_ITEM = 68824

local kilnaraBase = GetCount("mount", PANTHER_ITEM)
local mandokirPreKilnara = GetCount("mount", RAPTOR_ITEM)

ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(30)

stub.Fire("ENCOUNTER_START", KILNARA_ENC, "High Priestess Kilnara", 2, 5)
stub.Advance(40)
stub.Fire("ENCOUNTER_END", KILNARA_ENC, "High Priestess Kilnara", 2, 5, 1)
stub.Advance(2)

local kilnaraCorpse = MakeCreatureGUID(KILNARA_NPC)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:69612::::::::::::::::|h[Zulian Claw]|h" } }
stub.world.lootSources = { { kilnaraCorpse, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

check(GetCount("mount", PANTHER_ITEM) == kilnaraBase + 1, "Kilnara kill counted for Swift Zulian Panther (+1)")
check(GetCount("mount", RAPTOR_ITEM) == mandokirPreKilnara, "Kilnara kill did NOT affect Mandokir counter (zero cross-talk)")

-- =========================================================================
-- Phase 3: Multi-Boss Encounter (Council / Multi-NPC Boss - HK-8 Aerial Oppression Unit)
-- =========================================================================
print("Phase 3: Multi-NPC Encounter (Council / Shared Encounter - HK-8)")
local HK8_ENC = 2291
local HK8_NPC1 = 155157
local HK8_NPC2 = 150190
local HK8_MOUNT = 168826 -- Mechagon Peacekeeper

local hk8Base = GetCount("mount", HK8_MOUNT)

ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(20)

stub.Fire("ENCOUNTER_START", HK8_ENC, "HK-8 Aerial Oppression Unit", 23, 5)
stub.Advance(60)
stub.Fire("ENCOUNTER_END", HK8_ENC, "HK-8 Aerial Oppression Unit", 23, 5, 1)
stub.Advance(2)

-- Loot Tank 1
local hk8Corpse1 = MakeCreatureGUID(HK8_NPC1)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:168000::::::::::::::::|h[Dungeon Gear]|h" } }
stub.world.lootSources = { { hk8Corpse1, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(2)

local hk8Count1 = GetCount("mount", HK8_MOUNT)
check(hk8Count1 == hk8Base + 1, "Looting first council boss counted +1 attempt")

-- Immediately Loot Tank 2 from the same encounter
local hk8Corpse2 = MakeCreatureGUID(HK8_NPC2)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:168001::::::::::::::::|h[Dungeon Gear 2]|h" } }
stub.world.lootSources = { { hk8Corpse2, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local hk8Count2 = GetCount("mount", HK8_MOUNT)
check(hk8Count2 == hk8Count1, "Looting second council boss from same encounter did NOT double count (stayed +1)")

-- =========================================================================
-- Phase 4: Raid Boss with Statistic IDs (Onyxia / Onyxian Drake)
-- =========================================================================
print("Phase 4: Raid Boss with Statistic IDs (Onyxia)")
local ONYXIA_ENC = 1084
local ONYXIA_STAT = 1098
local ONYXIA_MOUNT = 49636

stub.SetStatistic(ONYXIA_STAT, 15)
stub.Advance(10)
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "raid"

stub.Fire("ENCOUNTER_START", ONYXIA_ENC, "Onyxia", 4, 25)
stub.Advance(45)

-- Blizzard increments statistic upon boss death
stub.SetStatistic(ONYXIA_STAT, 16)
stub.Fire("ENCOUNTER_END", ONYXIA_ENC, "Onyxia", 4, 25, 1)
stub.Advance(5) -- allow scheduled stat reseed to run

local onyxiaCount = GetCount("mount", ONYXIA_MOUNT)
check(onyxiaCount == 16, ("Onyxia attempt updated from Blizzard kill statistic (got %d, expected 16)"):format(onyxiaCount))

-- Looting Onyxia corpse afterwards does not double count
local onyxiaCorpse = MakeCreatureGUID(10184)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:49295::::::::::::::::|h[Bag]|h" } }
stub.world.lootSources = { { onyxiaCorpse, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

check(GetCount("mount", ONYXIA_MOUNT) == 16, "Looting Onyxia corpse after statistic sync does NOT double count")

-- =========================================================================
-- Phase 5: Boss Chest / GameObject Encounter (Sylvanas Mythic Chest)
-- =========================================================================
print("Phase 5: Boss Chest / GameObject Encounter (Sylvanas Mythic - Vengeance's Reins)")
local SYLVANAS_ENC = 2435
local SYLVANAS_CHEST_OBJ = 369898
local SYLVANAS_MOUNT = 186642

local sylvBase = GetCount("mount", SYLVANAS_MOUNT)

-- 5.1: Mythic Difficulty (diff 16) matches
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "raid"
stub.Advance(10)

stub.Fire("ENCOUNTER_START", SYLVANAS_ENC, "Sylvanas Windrunner", 16, 20)
stub.Advance(120)
stub.Fire("ENCOUNTER_END", SYLVANAS_ENC, "Sylvanas Windrunner", 16, 20, 1)
stub.Advance(15) -- post-cinematic

local chestGUID = MakeGameObjectGUID(SYLVANAS_CHEST_OBJ)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:186420::::::::::::::::|h[Mythic Bow]|h" } }
stub.world.lootSources = { { chestGUID, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local sylvAfterMythic = GetCount("mount", SYLVANAS_MOUNT)
check(sylvAfterMythic == sylvBase + 1, ("Sylvanas Mythic chest counted +1 attempt (got %d, expected %d)"):format(sylvAfterMythic, sylvBase + 1))

-- 5.2: Heroic Difficulty (diff 15) -> Mount is Mythic only -> Must skip!
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "raid"
stub.Advance(20)

stub.Fire("ENCOUNTER_START", SYLVANAS_ENC, "Sylvanas Windrunner", 15, 20)
stub.Advance(120)
stub.Fire("ENCOUNTER_END", SYLVANAS_ENC, "Sylvanas Windrunner", 15, 20, 1)
stub.Advance(15)

local chestHeroic = MakeGameObjectGUID(SYLVANAS_CHEST_OBJ)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:186421::::::::::::::::|h[Heroic Bow]|h" } }
stub.world.lootSources = { { chestHeroic, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local sylvAfterHeroic = GetCount("mount", SYLVANAS_MOUNT)
check(sylvAfterHeroic == sylvAfterMythic, ("Heroic kill did NOT count for Mythic-only mount (stayed %d)"):format(sylvAfterHeroic))

-- =========================================================================
-- Phase 6: World Rare with Daily Lockout Quest (Soundless)
-- =========================================================================
print("Phase 6: World Rare with Daily Lockout Quest (Soundless)")
local SOUNDLESS_NPC = 152290
local SOUNDLESS_MOUNT = 169163 -- Silent Glider
local SOUNDLESS_QUEST = 56298

check(RT.lockoutQuestsDB[SOUNDLESS_NPC] == SOUNDLESS_QUEST, "Soundless has lockout quest in lockoutQuestsDB")
local soundlessBase = GetCount("mount", SOUNDLESS_MOUNT)

ResetState()
stub.world.inInstance = false
stub.world.instanceType = "none"
stub.world.mapID = 1355 -- Nazjatar
stub.Advance(10)

-- Kill 1: Rare dies and Blizzard flags the lockout quest
stub.SetQuestCompleted(SOUNDLESS_QUEST, true)
local soundlessCorpse1 = MakeCreatureGUID(SOUNDLESS_NPC)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:168000::::::::::::::::|h[Prismatic Manapearl]|h" } }
stub.world.lootSources = { { soundlessCorpse1, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local soundlessAfter1 = GetCount("mount", SOUNDLESS_MOUNT)
check(soundlessAfter1 == soundlessBase + 1, "First Soundless kill counted +1 attempt")

-- Same rare killed again 5 minutes later on the same character / lockout
stub.Advance(300)
local soundlessCorpse2 = MakeCreatureGUID(SOUNDLESS_NPC)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:168000::::::::::::::::|h[Prismatic Manapearl]|h" } }
stub.world.lootSources = { { soundlessCorpse2, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)

local soundlessAfter2 = GetCount("mount", SOUNDLESS_MOUNT)
check(soundlessAfter2 == soundlessAfter1, "Second Soundless kill on same day suppressed by lockout quest (stayed +1)")

-- =========================================================================
-- Phase 7: Midnight 12.0/12.1 Secret Values Stress Test
-- =========================================================================
print("Phase 7: Midnight 12.0/12.1 Secret Values Injection")
local secretPreCount = GetCount("mount", RAPTOR_ITEM)

ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(20)

-- Clean ENCOUNTER_START captures authoritative IDs
stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(20)

-- In Midnight retail, secret values are distinct userdata handles
local secretEncID = stub.MarkSecret(newproxy(true))
local secretDiffID = stub.MarkSecret(newproxy(true))
local secretName = stub.MarkSecret(newproxy(true))
local secretSuccess = stub.MarkSecret(newproxy(true))

-- Fire ENCOUNTER_END with secret values (rescued from start cache)
stub.Fire("ENCOUNTER_END", secretEncID, secretName, secretDiffID, 5, 1)
stub.Advance(1)

-- Loot window with secret GUIDs
local normalCorpse = MakeCreatureGUID(MANDOKIR_NPC)
local secretCorpse = stub.MarkSecret(newproxy(true))
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:69605::::::::::::::::|h[Decapitating Sword]|h" } }
stub.world.lootSources = { { secretCorpse, 1 } }

stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(5)

check(#stub.errors == 0, ("Zero Lua runtime errors during secret value injection (errors: %d)"):format(#stub.errors))
local secretPostCount = GetCount("mount", RAPTOR_ITEM)
check(secretPostCount == secretPreCount + 1, ("Secret ENCOUNTER_END successfully rescued via start cache (got %d, expected %d)"):format(secretPostCount, secretPreCount + 1))

-- Also verify wipe with secret success doesn't crash
stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(10)
stub.Fire("ENCOUNTER_END", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5, secretSuccess)
stub.Advance(2)
check(#stub.errors == 0, "Secret success argument in ENCOUNTER_END handled safely without crash")

-- =========================================================================
-- Phase 8: Chat Loot Drop Attribution & Obtained Behavior
-- =========================================================================
print("Phase 8: Chat Loot Drop Attribution & Obtained Behavior")
ResetState()
stub.world.inInstance = true
stub.world.instanceType = "party"
stub.Advance(20)

stub.Fire("ENCOUNTER_START", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5)
stub.Advance(25)
stub.Fire("ENCOUNTER_END", MANDOKIR_ENC, "Bloodlord Mandokir", 2, 5, 1)
stub.Advance(3) -- advance past 2.0s CHAT_LOOT_DEBOUNCE

-- Mount drops in chat loot
local raptorLink = "|cffa335ee|Hitem:68823::::::::::::::::|h[Armored Razzashi Raptor]|h"
stub.Fire("CHAT_MSG_LOOT", "You receive loot: " .. raptorLink .. ".")
stub.Advance(3)

local chatObtainedApplied = Fns.IsObtainOutcomeApplied("mount", RAPTOR_ITEM, { itemID = RAPTOR_ITEM, type = "mount" })
check(chatObtainedApplied == true, "Chat loot drop marked obtain outcome applied")

local hadObtainedChat = false
for i = 1, #stub.chat do
    if stub.chat[i]:find("You got") or stub.chat[i]:find("Obtained") then
        hadObtainedChat = true
        break
    end
end
check(hadObtainedChat == true, "Obtained announcement successfully emitted in chat")

-- =========================================================================
-- Phase 9: Non-Combat Loot Isolation (Fishing / Containers)
-- =========================================================================
print("Phase 9: Non-Combat Loot Isolation (Fishing & Bag Containers)")
local raptorCountFinal = GetCount("mount", RAPTOR_ITEM)

ResetState()
stub.world.inInstance = false
stub.world.instanceType = "none"
stub.world.isFishingLoot = true
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:13755::::::::::::::::|h[Winter Squid]|h" } }
stub.world.lootSources = {}

stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(1)
stub.Fire("LOOT_CLOSED")
stub.Advance(2)

check(GetCount("mount", RAPTOR_ITEM) == raptorCountFinal, "Fishing loot does not pollute encounter state or touch boss counters")

-- =========================================================================
-- Summary & Error Gate
-- =========================================================================
print("----------------------------------------------------------------------")
print(("Total Checks: %d | Failures: %d | Runtime Errors: %d"):format(totalChecks, failures, #stub.errors))
if #stub.errors > 0 then
    for i = 1, #stub.errors do
        print("  [ERROR] " .. stub.errors[i])
    end
end

if failures == 0 and #stub.errors == 0 then
    print("\nEncounter simulation matrix: ALL TESTS PASSED.")
    os.exit(0)
else
    print("\nEncounter simulation matrix: TEST FAILURES DETECTED.")
    os.exit(1)
end
