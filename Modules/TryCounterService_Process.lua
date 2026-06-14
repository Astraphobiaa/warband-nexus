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

-- Creature NPC ids for fishing bobber (GUID type Creature — not a lootable corpse).
TC.FISHING_BOBBER_NPC_IDS = {
    [124736] = true,
    [35591]  = true,
    [216204] = true,
}

-- Session cache: spell IDs probed via GetSpellInfo and confirmed not fishing (avoids per-cast API on dragonriding etc.).
TC.probedNonFishingSpells = {}

TC.SKIP_CHAT_DEDUP_SEC = 15
TC.FISHING_CAST_CONTEXT_TTL = 35

assert(TC.FISHING_SPELLS and TC.FISHING_BOBBER_NPC_IDS, "TryCounterService_Process: tables missing")
