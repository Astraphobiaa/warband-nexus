--[[
    Warband Nexus - Try Counter process pipeline constants (ops-030 slice)
    Classify-Lock-Process loot routing tables. Encounter/loot/CHAT_MSG_LOOT handlers
    in TryCounterService_Handlers.lua (ns.TryCounter.Runtime). Loaded after Events, before main.
]]

local _, ns = ...

local TC = ns.TryCounter or {}
ns.TryCounter = TC

-- Classify-Lock-Process priority (first match wins per loot session):
--   1. SKIP       — pickpocket / blocking vendor UI / profession loot
--   2. CONTAINER  — isFromItem flag OR recent tracked container use
--   3. FISHING    — IsFishingLoot() API OR structural bobber/pool sources in fishable zone
--   4. NPC/OBJECT — ProcessNPCLoot (exact GUID->ID match only; P1->P5 resolver)
TC.CLASSIFY_ROUTE_ORDER = { "skip", "container", "fishing", "npc_object" }

-- Fishing cast spell IDs (UNIT_SPELLCAST_SENT / UNIT_SPELLCAST_CHANNEL_START).
-- Passive profession-rank unlocks (471021 / 471008) never fire cast events — excluded.
TC.FISHING_SPELLS = {
    [7620]    = true,
    [131474]  = true,
    [110412]  = true,
    [271616]  = true,
    [271990]  = true,
    [271991]  = true,
    [384481]  = true,
    [389234]  = true,
    [463743]  = true,
    [1239033] = true,
    [1239227] = true,
    [1257770] = true,
    [1281823] = true,
    [1281824] = true,
}

-- Fishing bobber ids.
--
-- The bobber is a GAMEOBJECT, not a creature: GAMEOBJECT_TYPE_FISHINGNODE = 17, with
-- GAMEOBJECT_TYPE_FISHINGHOLE for the pool/school (consistent across TrinityCore, AzerothCore
-- and CMaNGOS, and TrinityCore's GameObjectData.h is generated from Blizzard's own type schema).
-- So GetLootSourceInfo reports fishing loot as `GameObject-...` GUIDs.
--
-- That makes this table's original name a category error: it was only ever consulted through
-- GetNPCIDFromGUID on GUIDs matching "^Creature", which a real bobber never produces. It is kept
-- (creature side) for toy/oversized-bobber creatures and legacy ids, while the GameObject side
-- below is what actually matches live fishing loot. Both are learned at runtime and persisted.
TC.FISHING_BOBBER_NPC_IDS = {
    [124736] = true,
    [35591]  = true,
    [216204] = true,
}

-- GameObject ids confirmed as a fishing node / fishing hole. Seeded empty on purpose: the live id
-- is learned the first time IsFishingLoot() confirms a session (then persisted to SavedVariables),
-- because hardcoding a guess here is exactly what left the structural route dead.
TC.FISHING_BOBBER_OBJECT_IDS = {}

-- SpellMisc.SpellIconFileDataID for the Fishing spell family, build 12.1.0.69299 (wago.tools):
-- 7620, 131474 and 1281823 all report 4620674. The old 136245 is the pre-icon-refresh FileDataID
-- and is kept only so an older client still resolves. C_Spell.GetSpellInfo().iconID is a fileID.
-- With the stale value alone, every fishing spell outside FISHING_SPELLS below was probed once and
-- then cached as NOT fishing forever, so the cast-context route never armed for it.
TC.FISHING_SPELL_ICON_IDS = {
    [4620674] = true,
    [136245]  = true,
}

-- Session cache: spell IDs probed via GetSpellInfo and confirmed not fishing (avoids per-cast API on dragonriding etc.).
TC.probedNonFishingSpells = {}

TC.SKIP_CHAT_DEDUP_SEC = 15
TC.FISHING_CAST_CONTEXT_TTL = 35

assert(TC.FISHING_SPELLS and TC.FISHING_BOBBER_NPC_IDS and TC.FISHING_BOBBER_OBJECT_IDS
    and TC.FISHING_SPELL_ICON_IDS, "TryCounterService_Process: tables missing")
