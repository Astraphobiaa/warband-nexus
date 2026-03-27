--[[
    Warband Nexus - Collectible Source Database
    Single source of truth: the `sources` array. All try-count and tooltip data is built from it at load.

    HOW TO ADD A NEW ENTRY
    ----------------------
    Add exactly one element to the `sources` table with:
      - sourceType: one of instance_boss, world_rare, npc, object, container, fishing, zone_drop,
                    encounter, encounter_name, lockout_quest
      - The IDs that type needs: npcID, objectID, containerItemID, mapID/mapIDs, encounterID, etc.
      - drops: array of { type = "mount"|"pet"|"toy"|"item", itemID, name [, guaranteed] [, repeatable] [, yields] }

    Examples:
      Boss drop:    { sourceType = "instance_boss", npcID = 10440, drops = {...}, statisticIds = {1097} }
      Fishing:      { sourceType = "fishing", mapIDs = { 2405, 2395 }, drops = _someDrops }
      Zone rare:    { sourceType = "zone_drop", mapID = 2395, raresOnly = true, drops = _quelThalasRareMounts }
      Container:    { sourceType = "container", containerItemID = 39883, drops = {...} }
      Encounter:    { sourceType = "encounter", encounterID = 652, npcIDs = { 16152 } }

    DROP ENTRY FORMAT (inside drops):
      - type: "mount", "pet", "toy", or "item"
      - itemID, name: required
      - guaranteed: optional; 100% drop, no try count
      - repeatable: optional; resets try count on obtain
      - yields: optional; for "item" that leads to mount/pet (e.g. egg -> mount)

    npcs, rares, objects, fishing, containers, zones, encounters, encounterNames, lockoutQuests
    are built at load from sources only. Do not add data to any legacy table.
]]

local ADDON_NAME, ns = ...

-- =====================================================================
-- BfA "Zone Drop" mounts - shared drop tables (referenced by multiple NPC entries)
-- These mounts drop from specific mob factions within a zone, NOT every mob.
-- Source: WoWHead / community-verified NPC IDs
-- =====================================================================
local _duneScavenger = {
    { type = "mount", itemID = 163576, name = "Captured Dune Scavenger", repeatable = true },
}
local _terrifiedPackMule = {
    { type = "mount", itemID = 163574, name = "Chewed-On Reins of the Terrified Pack Mule", repeatable = true },
}
local _bloodfeaster = {
    { type = "mount", itemID = 163575, name = "Reins of a Tamed Bloodfeaster", repeatable = true },
}
local _goldenmane = {
    { type = "mount", itemID = 163573, name = "Goldenmane's Reins", repeatable = true },
}

-- TWW "Isle of Dorn" Crackling Shard - shared drop table (17 rares, â‰¥1% drop rate)
-- 10x Crackling Shard -> Storm Vessel -> defeat Alunira -> Alunira mount
-- Try count stored on mount so mount UI shows attempts (tryCountReflectsTo).
local _cracklingShard = {
    { type = "item", itemID = 224025, name = "Crackling Shard", repeatable = true,
      yields = {
          { type = "mount", itemID = 223270, name = "Alunira" },
      },
      tryCountReflectsTo = { type = "mount", itemID = 223270, name = "Alunira" },
    },
}

-- TWW 11.1 "Undermine" Miscellaneous Mechanica - shared drop table
-- Currency item used to purchase mounts (25 each) and pets from vendors in Undermine
local _miscMechanica = {
    { type = "item", itemID = 234741, name = "Miscellaneous Mechanica", repeatable = true,
      yields = {
          -- Mounts (Skedgit Cinderbangs vendor, 25 Mechanica each)
          { type = "mount", itemID = 229941, name = "Innovation Investigator" },
          { type = "mount", itemID = 229952, name = "Asset Advocator" },
          { type = "mount", itemID = 229954, name = "Margin Manipulator" },
          -- Pets (Ditty Fuzeboy vendor, 5-10 Mechanica each)
          { type = "pet", itemID = 232840, name = "Mechagopher" },
          { type = "pet", itemID = 232841, name = "Professor Punch" },
          { type = "pet", itemID = 232842, name = "Crimson Mechasaur" },
          { type = "pet", itemID = 232846, name = "Steamwheedle Flunkie" },
          { type = "pet", itemID = 232849, name = "Venture Companyman" },
          { type = "pet", itemID = 232850, name = "Blackwater Kegmover" },
      },
    },
}

-- =====================================================================
-- MIDNIGHT 12.0 "Zone Rare" mounts - shared drop tables
-- Any rare in the zone can drop these mounts (daily lockout per rare)
-- Source: WoWHead - https://www.wowhead.com/news/45-new-mounts-to-collect-with-the-launch-of-midnight-380520
-- =====================================================================

-- Quel'Thalas (Eversong Woods / Ghostlands) - 2 mounts from any zone rare
local _quelThalasRareMounts = {
    { type = "mount", itemID = 257156, name = "Cerulean Hawkstrider" },
    { type = "mount", itemID = 257147, name = "Cobalt Dragonhawk" },
}

-- Zul'Aman - 2 mounts from any zone rare
-- NOTE: Ancestral War Bear (257223) is from Honored Warrior's Cache treasure
-- NOTE: Hexed Vilefeather Eagle (257444) is from Abandoned Ritual Skull treasure
local _zulAmanRareMounts = {
    { type = "mount", itemID = 257152, name = "Amani Sharptalon" },
    { type = "mount", itemID = 257200, name = "Escaped Witherbark Pango" },
}

-- Harandar - 2 mounts from any zone rare
-- NOTE: Ruddy Sporeglider (252017) is from Peculiar Cauldron treasure
-- NOTE: Untainted Grove Crawler (256423) is from Sporespawned Cache treasure
local _harandarRareMounts = {
    { type = "mount", itemID = 246735, name = "Rootstalker Grimlynx" },
    { type = "mount", itemID = 252012, name = "Vibrant Petalwing" },
}

-- Voidstorm - 2 mounts from any zone rare
-- NOTE: Reins of the Insatiable Shredclaw (257446) is from Final Clutch of Predaxas treasure
local _voidstormRareMounts = {
    { type = "mount", itemID = 257085, name = "Augmented Stormray" },
    { type = "mount", itemID = 260635, name = "Sanguine Harrower" },
}

-- MIDNIGHT 12.0 Fishing mount chain:
-- Nether-Warped Egg (fishing/treasure catch in Midnight zones) -> Nether-Warped Drake (mount; item 260916 = "Lost Nether Drake" in-game).
local _netherWarpedEgg = {
    { type = "item", itemID = 268730, name = "Nether-Warped Egg",
      yields = {
          { type = "mount", itemID = 260916, name = "Nether-Warped Drake" },
      },
      tryCountReflectsTo = { type = "mount", itemID = 260916, name = "Nether-Warped Drake" },
    },
}

-- NOTE: Additional Midnight mounts NOT tracked (vendor/achievement rewards):
-- - Amani Blessed Bear (257219) - Renown 17 vendor (Amani Tribe)
-- - Blessed Amani Burrower (257197) - Abundance Event vendor (1600 Unalloyed Abundance)
-- - Amani Sunfeather (250782) - Abundance Event vendor (1600 Unalloyed Abundance)
-- - Crimson Silvermoon Hawkstrider (257154) - Renown 17 vendor (Silvermoon Court)
-- - Fiery Dragonhawk (257142) - Renown 19 vendor (Silvermoon Court)
-- - Fierce Grimlynx (246734) - Renown 16 vendor (Hara'ti)
-- - Cerulean Sporeglider (252014) - Renown 19 vendor (Hara'ti)
-- - Prowling Shredclaw (257447) - Exalted vendor (Slayer's Duellum)
-- - Frenzied Shredclaw (257448) - Exalted vendor (Slayer's Duellum)
-- - Tenebrous Harrower (260887) - Glory of the Midnight Raider meta-achievement

ns.CollectibleSourceDB = {
    version = "12.0.25",
    lastUpdated = "2026-03-25",
    sourceSchemaVersion = 1,
    sourceTypes = {
        "instance_boss", -- npcID + drops
        "world_rare",    -- npcID + drops
        "npc",           -- npcID + drops
        "object",        -- objectID + drops (chests/world objects)
        "container",     -- containerItemID + drops
        "fishing",       -- mapID/mapIDs + drops
        "zone_drop",     -- mapID/mapIDs + drops + raresOnly
        "encounter",     -- encounterID + npcIDs
        "encounter_name",-- encounterName + npcIDs
        "lockout_quest", -- npcID + questID/questIDs
    },
    -- Single source of truth for new entries. Add here only; see header "HOW TO ADD".
    sources = {
        {
            sourceType = "fishing",
            mapIDs = { 2393, 2395, 2424, 2413, 2576, 2437, 2536, 2405, 2541 },
            drops = _netherWarpedEgg,
        },

        -- =====================================================================
        -- MIDNIGHT 12.0 — Daily lockout quests for zone rares
        -- Each rare can be looted once per day; quest flag resets on daily reset.
        -- =====================================================================

        -- Eversong Woods / Quel'Thalas (A Bloody Song) — 15 rares
        { sourceType = "lockout_quest", npcID = 246332, questID = 91280 },  -- Warden of Weeds
        { sourceType = "lockout_quest", npcID = 246633, questID = 91315 },  -- Harried Hawkstrider
        { sourceType = "lockout_quest", npcID = 240129, questID = 92392 },  -- Overfester Hydra
        { sourceType = "lockout_quest", npcID = 250582, questID = 92366 },  -- Bloated Snapdragon
        { sourceType = "lockout_quest", npcID = 250719, questID = 92391 },  -- Cre'van
        { sourceType = "lockout_quest", npcID = 250683, questID = 92389 },  -- Coralfang
        { sourceType = "lockout_quest", npcID = 250754, questID = 92393 },  -- Lady Liminus
        { sourceType = "lockout_quest", npcID = 250876, questID = 92409 },  -- Terrinor
        { sourceType = "lockout_quest", npcID = 250841, questID = 92404 },  -- Bad Zed
        { sourceType = "lockout_quest", npcID = 250780, questID = 92395 },  -- Waverly
        { sourceType = "lockout_quest", npcID = 250826, questID = 92403 },  -- Banuran
        { sourceType = "lockout_quest", npcID = 250806, questID = 92399 },  -- Lost Guardian
        { sourceType = "lockout_quest", npcID = 255302, questID = 93550 },  -- Duskburn
        { sourceType = "lockout_quest", npcID = 255329, questID = 93555 },  -- Malfunctioning Construct
        { sourceType = "lockout_quest", npcID = 255348, questID = 93561 },  -- Dame Bloodshed

        -- Zul'Aman / Atal'Aman (Tallest Tree in the Forest) — 15 rares
        { sourceType = "lockout_quest", npcID = 242023, questID = 89569 },  -- Necrohexxer Raz'ka
        { sourceType = "lockout_quest", npcID = 242024, questID = 89570 },  -- The Snapping Scourge
        { sourceType = "lockout_quest", npcID = 242025, questID = 89571 },  -- Skullcrusher Harak
        { sourceType = "lockout_quest", npcID = 242026, questID = 89572 },  -- Elder Oaktalon
        { sourceType = "lockout_quest", npcID = 242027, questID = 89573 },  -- Depthborn Eelamental
        { sourceType = "lockout_quest", npcID = 242028, questID = 89575 },  -- Lightwood Borer
        { sourceType = "lockout_quest", npcID = 242031, questID = 89578 },  -- Spinefrill
        { sourceType = "lockout_quest", npcID = 242032, questID = 89579 },  -- Oophaga
        { sourceType = "lockout_quest", npcID = 242033, questID = 89580 },  -- Tiny Vermin
        { sourceType = "lockout_quest", npcID = 242034, questID = 89581 },  -- Voidtouched Crustacean
        { sourceType = "lockout_quest", npcID = 242035, questID = 89583 },  -- The Devouring Invader
        { sourceType = "lockout_quest", npcID = 245691, questID = 91072 },  -- The Decaying Diamondback
        { sourceType = "lockout_quest", npcID = 245692, questID = 91073 },  -- Ash'an the Empowered
        { sourceType = "lockout_quest", npcID = 245975, questID = 91174 },  -- Mrrlokk
        { sourceType = "lockout_quest", npcID = 247976, questID = 91634 },  -- Poacher Rav'ik (Atal'Aman)

        -- Harandar (Leaf None Behind) — 15 rares (Aln'sharan quest ID unknown)
        { sourceType = "lockout_quest", npcID = 248741, questID = 91832 },  -- Rhazul
        { sourceType = "lockout_quest", npcID = 249844, questID = 92137 },  -- Chironex
        { sourceType = "lockout_quest", npcID = 249849, questID = 92142 },  -- Ha'kalawe
        { sourceType = "lockout_quest", npcID = 249902, questID = 92148 },  -- Tallcap the Truthspreader
        { sourceType = "lockout_quest", npcID = 249962, questID = 92154 },  -- Queen Lashtongue
        { sourceType = "lockout_quest", npcID = 249997, questID = 92161 },  -- Chlorokyll
        { sourceType = "lockout_quest", npcID = 250086, questID = 92168 },  -- Stumpy
        { sourceType = "lockout_quest", npcID = 250180, questID = 92170 },  -- Serrasa
        { sourceType = "lockout_quest", npcID = 250226, questID = 92172 },  -- Mindrot
        { sourceType = "lockout_quest", npcID = 250231, questID = 92176 },  -- Dracaena
        { sourceType = "lockout_quest", npcID = 250246, questID = 92183 },  -- Treetop
        { sourceType = "lockout_quest", npcID = 250317, questID = 92190 },  -- Oro'ohna
        { sourceType = "lockout_quest", npcID = 250321, questID = 92191 },  -- Pterrock
        { sourceType = "lockout_quest", npcID = 250347, questID = 92193 },  -- Ahl'ua'huhi
        { sourceType = "lockout_quest", npcID = 250358, questID = 92194 },  -- Annulus the Worldshaker

        -- Voidstorm / Slayer's Rise (The Ultimate Predator) — 14 rares
        { sourceType = "lockout_quest", npcID = 238498, questID = 91050 },  -- Territorial Voidscythe
        { sourceType = "lockout_quest", npcID = 241443, questID = 91048 },  -- Tremora
        { sourceType = "lockout_quest", npcID = 244272, questID = 90805 },  -- Sundereth the Caller
        { sourceType = "lockout_quest", npcID = 245044, questID = 91051 },  -- Nightbrood
        { sourceType = "lockout_quest", npcID = 245182, questID = 91047 },  -- Eruundi (Slayer's Rise)
        { sourceType = "lockout_quest", npcID = 256770, questID = 93884 },  -- Bilemaw the Gluttonous
        { sourceType = "lockout_quest", npcID = 256808, questID = 93895 },  -- Ravengerus
        { sourceType = "lockout_quest", npcID = 256821, questID = 93896 },  -- Far'thana the Mad
        { sourceType = "lockout_quest", npcID = 256922, questID = 93966 },  -- Screammaxa the Matriarch
        { sourceType = "lockout_quest", npcID = 256923, questID = 93946 },  -- Bane of the Vilebloods
        { sourceType = "lockout_quest", npcID = 256924, questID = 93944 },  -- Aeonelle Blackstar
        { sourceType = "lockout_quest", npcID = 256925, questID = 93947 },  -- Lotus Darkblossom
        { sourceType = "lockout_quest", npcID = 256926, questID = 93934 },  -- Queen o' War
        { sourceType = "lockout_quest", npcID = 257027, questID = 93953 },  -- Rakshur the Bonegrinder (Slayer's Rise)

        -- Arcantina / Slayer's Rise — additional rares (gear-only drops)
        { sourceType = "lockout_quest", npcID = 248791, questID = 94459 },  -- Voidseer Orivane
        { sourceType = "lockout_quest", npcID = 248459, questID = 94458 },  -- The Many-Broken
        { sourceType = "lockout_quest", npcID = 248700, questID = 94462 },  -- Abysslick
        { sourceType = "lockout_quest", npcID = 248068, questID = 94460 },  -- Nullspiral
        { sourceType = "lockout_quest", npcID = 248823, questID = 94463 },  -- Blackcore
        { sourceType = "lockout_quest", npcID = 257199, questID = 94461 },  -- Hardin Steellock (Horde)
        { sourceType = "lockout_quest", npcID = 257231, questID = 94461 },  -- Gar'chak Skullcleave (Alliance, shared quest)

        -- Isle of Quel'Danas — 2 rares (gear-only drops)
        { sourceType = "lockout_quest", npcID = 252465, questID = 95011 },  -- Tarhu the Ransacker
        { sourceType = "lockout_quest", npcID = 239864, questID = 95010 },  -- Dripping Shadow

        -- World Bosses — weekly lockout (via world quest)
        { sourceType = "lockout_quest", npcID = 244762, questID = 92560 },  -- Lu'ashal (Eversong Woods)
        { sourceType = "lockout_quest", npcID = 244424, questID = 92123 },  -- Cragpine (Zul'Aman)
        { sourceType = "lockout_quest", npcID = 249776, questID = 92034 },  -- Thorm'belan (Harandar)
        { sourceType = "lockout_quest", npcID = 248864, questID = 92636 },  -- Predaxas (Voidstorm)
    },

    -- DEPRECATED: do not add here. Data is merged into npcs/rares/... at load for backward compatibility.
    -- New entries go in sources[] only. These tables will be removed once fully migrated to sources.
    legacyNpcs = {

        -- ========================================
        -- CLASSIC
        -- ========================================

        [10440] = { -- Baron Rivendare (Stratholme)
            { type = "mount", itemID = 13335, name = "Deathcharger's Reins" },
            statisticIds = { 1097 },  -- Rivendare kills (Stratholme)
        },

        -- AQ40 Trash Mobs (Temple of Ahn'Qiraj)
        [15246] = { -- Qiraji Mindslayer (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },
        [15317] = { -- Qiraji Champion (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },
        [15247] = { -- Vekniss Stinger (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },
        [15311] = { -- Anubisath Sentinel (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },
        [15249] = { -- Vekniss Wasp (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },
        [15310] = { -- Vekniss Hive Crawler (AQ40)
            { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
            { type = "mount", itemID = 21221, name = "Red Qiraji Resonating Crystal" },
        },

        -- ========================================
        -- THE BURNING CRUSADE
        -- ========================================

        [16152] = { -- Attumen the Huntsman (Karazhan)
            { type = "mount", itemID = 30480, name = "Fiery Warhorse's Reins" },
        },
        [19622] = { -- Kael'thas Sunstrider (Tempest Keep: The Eye)
            { type = "mount", itemID = 32458, name = "Ashes of Al'ar" },
            statisticIds = { 1088 },  -- Kael'thas Sunstrider kills (The Eye)
        },
        [24664] = { -- Kael'thas Sunstrider (Magister's Terrace)
            { type = "mount", itemID = 35513, name = "Swift White Hawkstrider" },
        },
        [23035] = { -- Anzu (Sethekk Halls Heroic)
            { type = "mount", itemID = 32768, name = "Reins of the Raven Lord" },
        },

        -- ========================================
        -- WRATH OF THE LICH KING
        -- ========================================

        [32491] = { -- Time-Lost Proto-Drake (Storm Peaks)
            { type = "mount", itemID = 44168, name = "Reins of the Time-Lost Proto-Drake", guaranteed = true },
        },
        [26693] = { -- Skadi the Ruthless (Utgarde Pinnacle Heroic)
            { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" },
        },
        [174062] = { -- Skadi the Ruthless (Utgarde Pinnacle - Timewalking) [Verified]
            { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" },
        },
        [28859] = { -- Malygos (Eye of Eternity)
            { type = "mount", itemID = 43953, name = "Reins of the Blue Drake" },
            { type = "mount", itemID = 43952, name = "Reins of the Azure Drake" },
            statisticIds = { 1391, 1394 },  -- Malygos kills (10 & 25)
        },
        [28860] = { -- Sartharion (Obsidian Sanctum 3D)
            { type = "mount", itemID = 43986, name = "Reins of the Black Drake" },
            { type = "mount", itemID = 43954, name = "Reins of the Twilight Drake" },
            statisticIds = { 1392, 1393 },  -- Sartharion kills (10 & 25)
        },
        [33288] = { -- Yogg-Saron (Ulduar 0-Light 25-man)
            { type = "mount", itemID = 45693, name = "Mimiron's Head" },
            statisticIds = { 2869, 2883 },  -- Yogg-Saron kills (10 & 25)
            dropDifficulty = "25-man",
            -- NOTE: Requires defeating Yogg-Saron with 0 keepers (Alone in the Darkness)
            -- Only drops from 25-player mode, not 10-player
        },
        [10184] = { -- Onyxia (Onyxia's Lair)
            { type = "mount", itemID = 49636, name = "Reins of the Onyxian Drake" },
            statisticIds = { 1098 },  -- Onyxia kills
        },
        [36597] = { -- The Lich King (ICC 25H)
            { type = "mount", itemID = 50818, name = "Invincible's Reins" },
            statisticIds = { 4688 },  -- Lich King 25H kills
            dropDifficulty = "25H",
            -- NOTE: 25-player Heroic only, <1% drop rate
        },
        [32273] = { -- Infinite Corruptor (Culling of Stratholme Heroic)
            { type = "mount", itemID = 43951, name = "Reins of the Bronze Drake", guaranteed = true },
        },
        -- Vault of Archavon bosses (faction-specific item IDs)
        [31125] = { -- Archavon the Stone Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
            statisticIds = { 1753, 1754 },  -- Archavon kills (10 & 25)
        },
        [33993] = { -- Emalon the Storm Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
            statisticIds = { 3236, 2870 },  -- Emalon kills (10 & 25)
        },
        [35013] = { -- Koralon the Flame Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
            statisticIds = { 4074, 4075 },  -- Koralon kills (10 & 25)
        },
        [38433] = { -- Toravon the Ice Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
            statisticIds = { 4657, 4658 },  -- Toravon kills (10 & 25)
        },

        -- ========================================
        -- CATACLYSM
        -- ========================================

        -- World Rares (guaranteed drops)
        [50062] = { -- Aeonaxx (Deepholm)
            { type = "mount", itemID = 63042, name = "Reins of the Phosphorescent Stone Drake", guaranteed = true },
        },
        [50005] = { -- Poseidus (Vashj'ir)
            { type = "mount", itemID = 67151, name = "Reins of Poseidus", guaranteed = true },
        },

        [43873] = { -- Altairus (Vortex Pinnacle)
            { type = "mount", itemID = 63040, name = "Reins of the Drake of the North Wind" },
        },
        [43214] = { -- Slabhide (The Stonecore) - ALL DIFFICULTIES
            { type = "mount", itemID = 63043, name = "Reins of the Vitreous Stone Drake" },
            -- NOTE: Drops on both Normal and Heroic (no Mythic in Cataclysm)
        },
        [46753] = { -- Al'Akir (Throne of the Four Winds)
            { type = "mount", itemID = 63041, name = "Reins of the Drake of the South Wind" },
            statisticIds = { 5576, 5577 },  -- Al'Akir kills (10 & 25)
        },
        [52151] = { -- Bloodlord Mandokir (Zul'Gurub)
            { type = "mount", itemID = 68823, name = "Armored Razzashi Raptor" },
        },
        [52059] = { -- High Priestess Kilnara (Zul'Gurub) [Verified]
            { type = "mount", itemID = 68824, name = "Swift Zulian Panther" },
        },
        [55294] = { -- Ultraxion (Dragon Soul) - ALL DIFFICULTIES
            { type = "mount", itemID = 78919, name = "Experiment 12-B" },
            statisticIds = { 6161, 6162 },  -- Ultraxion kills (10 & 25)
            -- NOTE: Drops on 10/25 Normal and Heroic, ~1% drop rate
        },
        [52530] = { -- Alysrazor (Firelands)
            { type = "mount", itemID = 71665, name = "Flametalon of Alysrazor" },
            statisticIds = { 5970, 5971 },  -- Alysrazor kills (10 & 25)
        },
        [52409] = { -- Ragnaros (Firelands) - ALL DIFFICULTIES
            { type = "mount", itemID = 69224, name = "Smoldering Egg of Millagazor" },
            statisticIds = { 5976, 5977 },  -- Ragnaros kills (10 & 25)
            -- NOTE: Drops on both Normal and Heroic (10/25), ~1-2% drop rate
        },
        -- Madness of Deathwing (Dragon Soul) - 2 mount drops
        [56173] = { -- Madness of Deathwing (Dragon Soul)
            { type = "mount", itemID = 77067, name = "Reins of the Blazing Drake" },
            { type = "mount", itemID = 77069, name = "Life-Binder's Handmaiden", dropDifficulty = "Heroic" },
            statisticIds = { 6167, 6168 },  -- Madness of Deathwing kills (10 & 25)
        },

        -- ========================================
        -- MISTS OF PANDARIA
        -- ========================================

        -- World Bosses
        [60491] = { -- Sha of Anger (Kun-Lai Summit)
            { type = "mount", itemID = 87771, name = "Reins of the Heavenly Onyx Cloud Serpent" },
            statisticIds = { 6989 },  -- Sha of Anger kills
        },
        [62346] = { -- Galleon (Valley of the Four Winds)
            { type = "mount", itemID = 89783, name = "Son of Galleon's Saddle" },
            statisticIds = { 6990 },  -- Galleon kills
        },
        [69099] = { -- Nalak (Isle of Thunder)
            { type = "mount", itemID = 95057, name = "Reins of the Thundering Cobalt Cloud Serpent" },
            statisticIds = { 8146 },  -- Nalak kills
        },
        [69161] = { -- Oondasta (Isle of Giants)
            { type = "mount", itemID = 94228, name = "Reins of the Cobalt Primordial Direhorn" },
            statisticIds = { 8147 },  -- Oondasta kills
        },
        [73167] = { -- Huolon (Timeless Isle)
            { type = "mount", itemID = 104269, name = "Reins of the Thundering Onyx Cloud Serpent" },
        },

        -- Zandalari Warbringers (3 colors from 3 NPC variants)
        [69841] = { -- Zandalari Warbringer (Amber)
            { type = "mount", itemID = 94230, name = "Reins of the Amber Primordial Direhorn" },
        },
        [69842] = { -- Zandalari Warbringer (Jade)
            { type = "mount", itemID = 94231, name = "Reins of the Jade Primordial Direhorn" },
        },
        [69769] = { -- Zandalari Warbringer (Slate)
            { type = "mount", itemID = 94229, name = "Reins of the Slate Primordial Direhorn" },
        },

        -- Raid Bosses
        [60410] = { -- Elegon (Mogu'shan Vaults)
            { type = "mount", itemID = 87777, name = "Reins of the Astral Cloud Serpent" },
            statisticIds = { 6797, 6798, 7924, 7923 },  -- Elegon kills (10N, 25N, 10H, 25H)
        },
        [68476] = { -- Horridon (Throne of Thunder)
            { type = "mount", itemID = 93666, name = "Spawn of Horridon" },
            statisticIds = { 8151, 8149, 8152, 8150 },  -- Horridon kills (10N, 25N, 10H, 25H)
        },
        [69712] = { -- Ji-Kun (Throne of Thunder)
            { type = "mount", itemID = 95059, name = "Clutch of Ji-Kun" },
            statisticIds = { 8171, 8169, 8172, 8170 },  -- Ji-Kun kills (10N, 25N, 10H, 25H)
        },
        [71865] = { -- Garrosh Hellscream (Siege of Orgrimmar Mythic)
            { type = "mount", itemID = 104253, name = "Kor'kron Juggernaut" },
            statisticIds = { 8638, 8637 },  -- Garrosh kills (N/H & Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only mechanical scorpion mount (item 104253, not 112751)
        },

        -- ========================================
        -- WARLORDS OF DRAENOR
        -- ========================================

        -- Rare Spawns (guaranteed drops from verified sources)
        [81001] = { -- Nok-Karosh (Frostfire Ridge) [Verified]
            { type = "mount", itemID = 116794, name = "Garn Nighthowl", guaranteed = true },
        },
        [50990] = { -- Nakk the Thunderer (Nagrand)
            { type = "mount", itemID = 116659, name = "Bloodhoof Bull", guaranteed = true },
        },
        [50981] = { -- Luk'hok (Nagrand)
            { type = "mount", itemID = 116661, name = "Mottled Meadowstomper", guaranteed = true },
        },
        [50992] = { -- Gorok (Frostfire Ridge)
            { type = "mount", itemID = 116674, name = "Great Greytusk", guaranteed = true },
        },
        [51015] = { -- Silthide (Talador)
            { type = "mount", itemID = 116767, name = "Sapphire Riverbeast", guaranteed = true },
        },
        [50985] = { -- Poundfist (Gorgrond)
            { type = "mount", itemID = 116792, name = "Sunhide Gronnling", guaranteed = true },
        },
        [50883] = { -- Pathrunner (Shadowmoon Valley)
            { type = "mount", itemID = 116773, name = "Swift Breezestrider", guaranteed = true },
        },

        -- World Boss
        [87493] = { -- Rukhmar (Spires of Arak) [Verified]
            { type = "mount", itemID = 116771, name = "Solar Spirehawk" },
            statisticIds = { 9279 },  -- Rukhmar kills
        },
        [83746] = { -- Rukhmar (Spires of Arak - alternate NPC ID) [Verified]
            { type = "mount", itemID = 116771, name = "Solar Spirehawk" },
            statisticIds = { 9279 },  -- Rukhmar kills
        },

        -- Tanaan Jungle Champions (drop Rattling Iron Cage -> 3 mounts)
        [95044] = { -- Deathtalon (Tanaan Jungle)
            { type = "mount", itemID = 116669, name = "Armored Razorback" },
            { type = "mount", itemID = 116658, name = "Tundra Icehoof" },
            { type = "mount", itemID = 116780, name = "Warsong Direfang" },
        },
        [95054] = { -- Terrorfist (Tanaan Jungle)
            { type = "mount", itemID = 116669, name = "Armored Razorback" },
            { type = "mount", itemID = 116658, name = "Tundra Icehoof" },
            { type = "mount", itemID = 116780, name = "Warsong Direfang" },
        },
        [95053] = { -- Vengeance (Tanaan Jungle)
            { type = "mount", itemID = 116669, name = "Armored Razorback" },
            { type = "mount", itemID = 116658, name = "Tundra Icehoof" },
            { type = "mount", itemID = 116780, name = "Warsong Direfang" },
        },
        [95056] = { -- Doomroller (Tanaan Jungle)
            { type = "mount", itemID = 116669, name = "Armored Razorback" },
            { type = "mount", itemID = 116658, name = "Tundra Icehoof" },
            { type = "mount", itemID = 116780, name = "Warsong Direfang" },
        },

        -- Raid Bosses [Verified]
        [77325] = { -- Blackhand (Blackrock Foundry Mythic)
            { type = "mount", itemID = 116660, name = "Ironhoof Destroyer" },
            statisticIds = { 9365 },  -- Blackhand kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only fiery clefthoof mount from WoD
        },
        [91331] = { -- Archimonde (Hellfire Citadel Mythic)
            { type = "mount", itemID = 123890, name = "Felsteel Annihilator" },
            statisticIds = { 10252 },  -- Archimonde kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only fel reaver mount from WoD
        },

        -- ========================================
        -- LEGION
        -- ========================================

        -- Dungeon Bosses
        [114895] = { -- Nightbane (Return to Karazhan Mythic)
            { type = "mount", itemID = 142552, name = "Smoldering Ember Wyrm" },
        },
        [114262] = { -- Attumen the Huntsman (Return to Karazhan)
            { type = "mount", itemID = 142236, name = "Midnight's Eternal Reins" },
        },

        -- Argus Rares [Verified]
        [126867] = { -- Venomtail Skyfin (Mac'Aree)
            { type = "mount", itemID = 152844, name = "Lambent Mana Ray" },
        },
        [126852] = { -- Wrangler Kravos (Mac'Aree)
            { type = "mount", itemID = 152814, name = "Maddened Chaosrunner" },
        },
        [126912] = { -- Skreeg the Devourer (Mac'Aree)
            { type = "mount", itemID = 152904, name = "Acid Belcher" },
        },
        [122958] = { -- Blistermaw (Antoran Wastes)
            { type = "mount", itemID = 152905, name = "Crimson Slavermaw" },
        },
        [127288] = { -- Houndmaster Kerrax (Antoran Wastes)
            { type = "mount", itemID = 152790, name = "Vile Fiend" },
        },
        [126040] = { -- Puscilla (Antoran Wastes)
            { type = "mount", itemID = 152903, name = "Biletooth Gnasher" },
        },
        [126199] = { -- Vrax'thul (Antoran Wastes)
            { type = "mount", itemID = 152903, name = "Biletooth Gnasher" },
        },

        -- Raid Bosses [Verified]
        [105503] = { -- Gul'dan (The Nighthold) - ALL DIFFICULTIES
            { type = "mount", itemID = 137574, name = "Living Infernal Core" }, -- N/H/M (<1% drop)
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core", dropDifficulty = "Mythic" },
            statisticIds = { 10979, 10980, 10978 },  -- Gul'dan kills (H, M, N)
            -- NOTE: Living Infernal Core drops on N/H/M, Fiendish Hellfire Core is Mythic-only
        },
        [104154] = { -- Gul'dan (The Nighthold - normal form) [Verified]
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core", dropDifficulty = "Mythic" },
            statisticIds = { 10979, 10980, 10978 },  -- Gul'dan kills (H, M, N)
        },
        [111022] = { -- The Demon Within (The Nighthold - Mythic phase) [Verified]
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core", dropDifficulty = "Mythic" },
            statisticIds = { 10979, 10980, 10978 },  -- Gul'dan kills (H, M, N)
        },
        [115767] = { -- Mistress Sassz'ine (Tomb of Sargeras)
            { type = "mount", itemID = 143643, name = "Abyss Worm" },
            statisticIds = { 11893, 11894, 11895, 11896 },  -- Sassz'ine kills (LFR, N, H, M)
        },
        [126915] = { -- Felhounds of Sargeras (Antorus)
            { type = "mount", itemID = 152816, name = "Antoran Charhound" },
            statisticIds = { 12118, 11957, 11958, 11959 },  -- Felhounds kills (LFR, N, H, M)
        },
        [126916] = { -- Felhounds of Sargeras alt (Antorus)
            { type = "mount", itemID = 152816, name = "Antoran Charhound" },
            statisticIds = { 12118, 11957, 11958, 11959 },  -- Felhounds kills (LFR, N, H, M)
        },
        [130352] = { -- Argus the Unmaker (Antorus Mythic) [Verified]
            { type = "mount", itemID = 152789, name = "Shackled Ur'zul" },
            statisticIds = { 11986 },  -- Argus kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only mount, 100% drop during Legion/BfA, rare after Shadowlands
        },

        -- Toys
        [100230] = { -- Nazak the Fiend (Suramar)
            { type = "toy", itemID = 129149, name = "Skin of the Soulflayer" },
        },

        -- ========================================
        -- BATTLE FOR AZEROTH
        -- ========================================

        -- Darkshore / BfA World Rares
        [148790] = { -- Frightened Kodo (Darkshore)
            { type = "mount", itemID = 166433, name = "Frightened Kodo", guaranteed = true },
        },
        [160708] = { -- Mail Muncher (Horrific Visions)
            { type = "mount", itemID = 174653, name = "Mail Muncher" },
        },

        -- BfA Zone Drops: Captured Dune Scavenger (Vol'dun - Sethrak/Faithless mobs)
        -- Source: WoWHead-verified (20 NPC IDs)
        [128682] = _duneScavenger,  -- Faithless Defender
        [123774] = _duneScavenger,  -- Sethrak Aggressor
        [136191] = _duneScavenger,  -- Sethrak Ravager
        [134429] = _duneScavenger,  -- Faithless Ravager
        [129778] = _duneScavenger,  -- Faithless Skycaller
        [134427] = _duneScavenger,  -- Faithless Scalecaller
        [129652] = _duneScavenger,  -- Faithless Felblade
        [134560] = _duneScavenger,  -- Sethrak Fanatic
        [134103] = _duneScavenger,  -- Faithless Pillager
        [128678] = _duneScavenger,  -- Faithless Conscript
        [123773] = _duneScavenger,  -- Sethrak Warden
        [134559] = _duneScavenger,  -- Sethrak Skulker
        [123775] = _duneScavenger,  -- Sethrak Bladesman
        [128749] = _duneScavenger,  -- Faithless Tender
        [127406] = _duneScavenger,  -- Faithless Stalker
        [122746] = _duneScavenger,  -- Sethrak Overseer
        [123864] = _duneScavenger,  -- Sethrak Sandscout
        [136545] = _duneScavenger,  -- Faithless Raider
        [122782] = _duneScavenger,  -- Sethrak Skirmisher
        [123863] = _duneScavenger,  -- Sethrak Outrider

        -- BfA Zone Drops: Terrified Pack Mule (Drustvar - Heartsbane Coven mobs)
        -- Source: WoWHead-verified (9 NPC IDs)
        [131534] = _terrifiedPackMule,  -- Hexthralled Crossbowman
        [133892] = _terrifiedPackMule,  -- Hexthralled Soldier
        [133889] = _terrifiedPackMule,  -- Hexthralled Guardsman
        [141642] = _terrifiedPackMule,  -- Hexthralled Halberdier
        [131519] = _terrifiedPackMule,  -- Hexthralled Falconer
        [137134] = _terrifiedPackMule,  -- Heartsbane Vinetwister
        [133736] = _terrifiedPackMule,  -- Coven Thornshaper
        [131530] = _terrifiedPackMule,  -- Hexthralled Ravager
        [131529] = _terrifiedPackMule,  -- Hexthralled Villager

        -- BfA Zone Drops: Reins of a Tamed Bloodfeaster (Nazmir - Blood Troll mobs)
        -- Source: WoWHead-verified (16 NPC IDs)
        [126888] = _bloodfeaster,  -- Blood Troll Warder
        [126187] = _bloodfeaster,  -- Blood Witch Tashka
        [133077] = _bloodfeaster,  -- Blood Priestess Kel'zo
        [122239] = _bloodfeaster,  -- Blood Priest
        [127919] = _bloodfeaster,  -- Blood Troll Reaver
        [120607] = _bloodfeaster,  -- Blood Troll Warrior
        [136639] = _bloodfeaster,  -- Blood Troll Berserker
        [127224] = _bloodfeaster,  -- Blood Troll Shaman
        [136293] = _bloodfeaster,  -- Blood Troll Savage
        [133279] = _bloodfeaster,  -- Blood Priestess Vatat
        [133063] = _bloodfeaster,  -- Blood Troll Tracker
        [128734] = _bloodfeaster,  -- Blood Troll Rampager
        [127928] = _bloodfeaster,  -- Blood Hexlord
        [120606] = _bloodfeaster,  -- Blood Troll Mystic
        [124547] = _bloodfeaster,  -- Blood Troll Marauder
        [124688] = _bloodfeaster,  -- Blood Ritualist

        -- BfA Zone Drops: Goldenmane's Reins (Stormsong Valley - Tidesage/Irontide mobs)
        -- Source: WoWHead-verified (25 NPC IDs)
        [129750] = _goldenmane,  -- Tidesage Initiate
        [131646] = _goldenmane,  -- Tidesage Seacaller
        [135585] = _goldenmane,  -- Tidesage Adept
        [138167] = _goldenmane,  -- Tidesage Spiritualist
        [138332] = _goldenmane,  -- Tidesage Channeler
        [141143] = _goldenmane,  -- Tidesage Assailant
        [137202] = _goldenmane,  -- Tidesage Recruit
        [138168] = _goldenmane,  -- Tidesage Binder
        [130641] = _goldenmane,  -- Irontide Buccaneer
        [131166] = _goldenmane,  -- Irontide Raider
        [138226] = _goldenmane,  -- Tidesage Defiler
        [130897] = _goldenmane,  -- Irontide Enforcer
        [135584] = _goldenmane,  -- Tidesage Sycophant
        [140209] = _goldenmane,  -- Tidesage Mentalist
        [137893] = _goldenmane,  -- Quilboar Ravager
        [138170] = _goldenmane,  -- Tidesage Conjurer
        [137156] = _goldenmane,  -- Quilboar Warrior
        [130006] = _goldenmane,  -- Irontide Plunderer
        [131404] = _goldenmane,  -- Irontide Powderman
        [136158] = _goldenmane,  -- Quilboar Boarherd
        [130039] = _goldenmane,  -- Irontide Marauder
        [132226] = _goldenmane,  -- Irontide Sharpshooter
        [138340] = _goldenmane,  -- Tidesage Savant
        [137155] = _goldenmane,  -- Quilboar Brute
        [130531] = _goldenmane,  -- Irontide Mugger

        -- Warfront: Arathi Highlands
        [142692] = { -- Nimar the Slayer (Arathi)
            { type = "mount", itemID = 163706, name = "Witherbark Direwing" },
        },
        [142423] = { -- Overseer Krix (Arathi)
            { type = "mount", itemID = 163646, name = "Lil' Donkey" },
        },
        [142437] = { -- Skullripper (Arathi)
            { type = "mount", itemID = 163645, name = "Skullripper" },
        },
        [142709] = { -- Beastrider Kama (Arathi)
            { type = "mount", itemID = 163644, name = "Swift Albino Raptor" },
        },
        [142741] = { -- Doomrider Helgrim (Arathi - Alliance)
            { type = "mount", itemID = 163579, name = "Highland Mustang" },
        },
        [142739] = { -- Knight-Captain Aldrin (Arathi - Horde)
            { type = "mount", itemID = 163578, name = "Broken Highland Mustang" },
        },

        -- Warfront: Darkshore
        [148787] = { -- Alash'anir (Darkshore)
            { type = "mount", itemID = 166432, name = "Ashenvale Chimaera" },
        },
        [149652] = { -- Agathe Wyrmwood (Darkshore - Alliance)
            { type = "mount", itemID = 166438, name = "Caged Bear" },
        },
        [149660] = { -- Blackpaw (Darkshore - Horde)
            { type = "mount", itemID = 166428, name = "Blackpaw" },
        },
        [149655] = { -- Croz Bloodrage (Darkshore - Alliance)
            { type = "mount", itemID = 166437, name = "Captured Kaldorei Nightsaber" },
        },
        [149663] = { -- Shadowclaw (Darkshore - Horde)
            { type = "mount", itemID = 166435, name = "Kaldorei Nightsaber" },
        },
        [148037] = { -- Athil Dewfire (Darkshore - Horde)
            { type = "mount", itemID = 166803, name = "Umber Nightsaber" },
        },
        [147701] = { -- Moxo the Beheader (Darkshore - Alliance)
            { type = "mount", itemID = 166434, name = "Captured Umber Nightsaber" },
        },

        -- 8.2 Rares
        [152182] = { -- Rustfeather (Mechagon) [Verified]
            { type = "mount", itemID = 168370, name = "Rusted Keys to the Junkheap Drifter" },
        },
        [154342] = { -- Arachnoid Harvester (Mechagon - alt timeline) [Verified]
            { type = "mount", itemID = 168823, name = "Rusty Mechanocrawler" },
        },
        [151934] = { -- Arachnoid Harvester (Mechagon - standard) [Verified]
            { type = "mount", itemID = 168823, name = "Rusty Mechanocrawler" },
        },
        [152290] = { -- Soundless (Nazjatar) [Verified]
            { type = "mount", itemID = 169163, name = "Silent Glider" },
        },

        -- 8.3 Assault Rares - Vale of Eternal Blossoms
        [157466] = { -- Anh-De the Loyal (Vale)
            { type = "mount", itemID = 174840, name = "Xinlao" },
        },
        [157153] = { -- Ha-Li (Vale)
            { type = "mount", itemID = 173887, name = "Clutch of Ha-Li" },
        },
        [157160] = { -- Houndlord Ren (Vale)
            { type = "mount", itemID = 174841, name = "Ren's Stalwart Hound" },
        },

        -- 8.3 Assault Rares - Uldum
        [157134] = { -- Ishak of the Four Winds (Uldum)
            { type = "mount", itemID = 174641, name = "Reins of the Drake of the Four Winds" },
        },
        [162147] = { -- Corpse Eater (Uldum)
            { type = "mount", itemID = 174769, name = "Malevolent Drone" },
        },
        [157146] = { -- Rotfeaster (Uldum)
            { type = "mount", itemID = 174753, name = "Waste Marauder" },
        },

        -- World Boss
        [138794] = { -- Dunegorger Kraulok (Vol'dun)
            { type = "mount", itemID = 174842, name = "Slightly Damp Pile of Fur" },
        },

        -- Dungeon Bosses [Verified]
        [126983] = { -- Harlan Sweete (Freehold Mythic)
            { type = "mount", itemID = 159842, name = "Sharkbait's Favorite Crackers" },
            statisticIds = { 12752 },  -- Harlan Sweete kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only parrot mount from BfA dungeon
        },
        [133007] = { -- Unbound Abomination (The Underrot Mythic)
            { type = "mount", itemID = 160829, name = "Underrot Crawg Harness" },
            statisticIds = { 12745 },  -- Unbound Abomination kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [136160] = { -- King Dazar (Kings' Rest Mythic)
            { type = "mount", itemID = 159921, name = "Mummified Raptor Skull" },
            statisticIds = { 12763 },  -- King Dazar kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [155157] = { -- HK-8 Aerial Oppression Unit (Operation: Mechagon - main encounter)
            { type = "mount", itemID = 168826, name = "Mechagon Peacekeeper" },
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only mount; encounter 2291 used for fallback. statisticIds optional (verify in-game).
        },
        [150190] = { -- HK-8 Aerial Oppression Unit (Operation: Mechagon - alt ID)
            { type = "mount", itemID = 168826, name = "Mechagon Peacekeeper" },
            dropDifficulty = "Mythic",
        },

        -- Raid Bosses [Verified]
        [165396] = { -- Lady Jaina Proudmoore (Battle of Dazar'alor Mythic)
            { type = "mount", itemID = 166705, name = "Glacial Tidestorm" },
            statisticIds = { 13382 },  -- Jaina kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only, 100% drop during BfA, rare after Shadowlands
        },
        [144796] = { -- Mekkatorque (Battle of Dazar'alor)
            { type = "mount", itemID = 166518, name = "G.M.O.D." },
            statisticIds = { 13372, 13373, 13374, 13379 },  -- Mekkatorque kills (N, H, M, LFR)
        },
        [158041] = { -- N'Zoth the Corruptor (Ny'alotha Mythic)
            { type = "mount", itemID = 174872, name = "Ny'alotha Allseer" },
            statisticIds = { 14138 },  -- N'Zoth kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only mount from final BfA raid boss
        },

        -- ========================================
        -- SHADOWLANDS
        -- ========================================

        -- Revendreth Rares
        [166521] = { -- Famu the Infinite (Revendreth) [Verified]
            { type = "mount", itemID = 180582, name = "Endmire Flyer Tether" },
        },
        [165290] = { -- Harika the Horrid (Revendreth)
            { type = "mount", itemID = 180461, name = "Horrid Dredwing" },
        },
        [166679] = { -- Hopecrusher (Revendreth)
            { type = "mount", itemID = 180581, name = "Hopecrusher Gargon" },
        },
        [160821] = { -- Worldedge Gorger (Revendreth)
            { type = "mount", itemID = 180583, name = "Impressionable Gorger Spawn" },
        },

        -- Maldraxxus Rares
        [162741] = { -- Gieger (Maldraxxus)
            { type = "mount", itemID = 182080, name = "Predatory Plagueroc" },
        },
        [162586] = { -- Tahonta (Maldraxxus)
            { type = "mount", itemID = 182075, name = "Bonehoof Tauralus" },
        },
        [157309] = { -- Violet Mistake (Maldraxxus)
            { type = "mount", itemID = 182079, name = "Slime-Covered Reins of the Hulking Deathroc" },
        },
        [162690] = { -- Nerissa Heartless (Maldraxxus)
            { type = "mount", itemID = 182084, name = "Gorespine" },
        },
        [162819] = { -- Warbringer Mal'Korak (Maldraxxus)
            { type = "mount", itemID = 182085, name = "Blisterback Bloodtusk" },
        },
        [162818] = { -- Warbringer Mal'Korak (Maldraxxus - alternate) [Verified]
            { type = "mount", itemID = 182085, name = "Blisterback Bloodtusk" },
        },
        [168147] = { -- Sabriel the Bonecleaver (Maldraxxus)
            { type = "mount", itemID = 181815, name = "Armored Bonehoof Tauralus" },
        },
        [168148] = { -- Sabriel the Bonecleaver (Maldraxxus - alternate) [Verified]
            { type = "mount", itemID = 181815, name = "Armored Bonehoof Tauralus" },
        },
        -- Theater of Pain (Maldraxxus) - multiple arena combatants
        [162873] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },
        [162880] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },
        [162875] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },
        [162853] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },
        [162874] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },
        [162872] = { -- Theater of Pain combatant
            { type = "mount", itemID = 184062, name = "Gnawed Reins of the Battle-Bound Warhound" },
        },

        -- Ardenweald Rares
        [168647] = { -- Valfir the Unrelenting (Ardenweald)
            { type = "mount", itemID = 180730, name = "Wild Glimmerfur Prowler" },
        },
        [164107] = { -- Gormtamer Tizo (Ardenweald)
            { type = "mount", itemID = 180725, name = "Arboreal Gulper", guaranteed = true },
        },
        [164112] = { -- Humon'gozz (Ardenweald)
            { type = "mount", itemID = 182650, name = "Unusual Ally" },
        },

        -- Bastion
        [170548] = { -- Sundancer (Bastion)
            { type = "mount", itemID = 180773, name = "Sundancer" },
        },

        -- The Maw
        [179460] = { -- Fallen Charger (The Maw)
            { type = "mount", itemID = 186659, name = "Fallen Charger's Reins" },
        },
        [174861] = { -- Gorged Shadehound (The Maw)
            { type = "mount", itemID = 184167, name = "Mawsworn Soulhunter" },
        },

        -- Korthia Rares
        [179472] = { -- Konthrogz the Obliterator (Korthia)
            { type = "mount", itemID = 187183, name = "Rampaging Mauler" },
        },
        [180160] = { -- Reliwik the Defiant (Korthia)
            { type = "mount", itemID = 186652, name = "Garnet Razorwing" },
        },
        [179684] = { -- Malbog (Korthia)
            { type = "mount", itemID = 186645, name = "Crimson Shardhide" },
        },

        -- 9.2 Korthia/Maw additions
        [180042] = { -- Fleshwing (The Maw - Perdition Hold)
            { type = "mount", itemID = 186489, name = "Bound Shadehound" },
        },
        [180032] = { -- Wild Worldcracker (Zereth Mortis)
            { type = "mount", itemID = 187282, name = "Rampaging Worldcracker" },
        },
        [179985] = { -- Stygian Stonecrusher (The Maw)
            { type = "mount", itemID = 187283, name = "Stygian Stonecrusher" },
        },

        -- Zereth Mortis
        [182120] = { -- Rhuv, Gorger of Ruin (Zereth Mortis)
            { type = "mount", itemID = 190765, name = "Iska's Mawrat Leash" },
        },
        [180978] = { -- Hirukon (Zereth Mortis)
            { type = "mount", itemID = 187676, name = "Deepstar Polyp" },
        },

        -- Dungeon Bosses
        [162693] = { -- Nalthor the Rimebinder (The Necrotic Wake Mythic)
            { type = "mount", itemID = 181819, name = "Marrowfang's Reins" },
            statisticIds = { 14404 },  -- Nalthor kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [180863] = { -- So'leah (Tazavesh Mythic)
            { type = "mount", itemID = 186638, name = "Cartel Master's Gearglider" },
            statisticIds = { 15168 },  -- So'leah kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- Raid Bosses [Verified]
        [178738] = { -- The Nine (Sanctum of Domination) - ALL DIFFICULTIES
            { type = "mount", itemID = 186656, name = "Sanctum Gloomcharger's Reins" },
            statisticIds = { 15145, 15144, 15147, 15146 },  -- The Nine kills (N, LFR, M, H)
            -- NOTE: Mount drops on ALL difficulties (LFR, Normal, Heroic, Mythic)
        },
        [175732] = { -- Sylvanas Windrunner (Sanctum of Domination Mythic)
            { type = "mount", itemID = 186642, name = "Vengeance's Reins" },
            statisticIds = { 15176 },  -- Sylvanas kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [180990] = { -- The Jailer (Sepulcher of the First Ones Mythic)
            { type = "mount", itemID = 190768, name = "Fractal Cypher of the Zereth Overseer" },
            statisticIds = { 15467 },  -- The Jailer kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- ========================================
        -- DRAGONFLIGHT
        -- ========================================

        -- Dragon Isles Rares
        [195353] = { -- Breezebiter (The Azure Span) [Verified]
            { type = "mount", itemID = 201440, name = "Reins of the Liberated Slyvern" },
        },

        -- Zaralek Cavern
        [203625] = { -- Karokta (Zaralek Cavern) [Verified]
            { type = "mount", itemID = 205203, name = "Cobalt Shalewing" },
        },

        -- Forbidden Reach rares - Ancient Salamanther (16 rares share same mount) [Verified]
        [201181] = { -- Mad-Eye Carrey (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200960] = { -- Warden Entrix (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200584] = { -- Vraken the Hunter (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200904] = { -- Veltrax (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200956] = { -- Ookbeard (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [201013] = { -- Wyrmslayer Angvardi (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200610] = { -- Duzalgor (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200721] = { -- Grugoth the Hullcrusher (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200911] = { -- Volcanakk (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200600] = { -- Reisa the Drowned (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200717] = { -- Galakhad (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200978] = { -- Pyrachniss (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200885] = { -- Lady Shaz'ra (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200681] = { -- Bonesifter Marwak (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200579] = { -- Ishyra (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },
        [200537] = { -- Gahz'raxes (Forbidden Reach)
            { type = "mount", itemID = 192772, name = "Ancient Salamanther" },
        },

        -- Clayscale Hornstrider (Azure Span 10.2.5)
        [208029] = { -- Clayscale Hornstrider rare (Azure Span) [Verified]
            { type = "mount", itemID = 212645, name = "Clayscale Hornstrider" },
        },

        -- Raid Bosses
        [189492] = { -- Raszageth the Storm-Eater (Vault of the Incarnates Mythic)
            { type = "mount", itemID = 201790, name = "Renewed Proto-Drake: Embodiment of the Storm-Eater" },
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only dragonriding customization manuscript
            -- TODO: Add statisticIds after in-game verification
        },
        [204931] = { -- Fyrakk (Amirdrassil Mythic)
            { type = "mount", itemID = 210061, name = "Reins of Anu'relos, Flame's Guidance" },
            statisticIds = { 19386 },  -- Fyrakk kills (Mythic)
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only phoenix mount from Dragonflight final raid
        },

        -- Dungeon Bosses [Verified]
        [198933] = { -- Chrono-Lord Deios (Dawn of the Infinite Mythic)
            { type = "mount", itemID = 208216, name = "Reins of the Quantum Courser" },
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only mount from Dragonflight megadungeon (10.1.5)
            -- When used, teaches a random mount from past dungeon content
            -- TODO: Add statisticIds after in-game verification
        },

        -- ========================================
        -- THE WAR WITHIN
        -- ========================================

        -- Hallowfall
        [207802] = { -- Beledar's Spawn (Hallowfall) [Verified]
            { type = "mount", itemID = 223315, name = "Beledar's Spawn" },
        },

        -- The Ringing Deeps
        [220285] = { -- Regurgitated Mole Reins rare (The Ringing Deeps) [Verified]
            { type = "mount", itemID = 223501, name = "Regurgitated Mole Reins" },
        },

        -- Azj-Kahet
        [216046] = { -- Tka'ktath (Azj-Kahet) [Verified]
            { type = "item", itemID = 225952, name = "Vial of Tka'ktath's Blood", repeatable = false,
              questStarters = {
                  { type = "mount", itemID = 224150, name = "Siesbarg", mountID = 2222 },
              },
              tryCountReflectsTo = { type = "mount", itemID = 224150, name = "Siesbarg", mountID = 2222 },
            },
        },

        -- Isle of Dorn â€” Crackling Shard sources (10x -> Storm Vessel -> Alunira mount)
        -- Rares with â‰¥1% drop rate. All repeatable, no weekly lockout.
        [219266] = _cracklingShard, -- Escaped Cutthroat (Isle of Dorn) ~5%
        [219268] = _cracklingShard, -- Gar'loc (Isle of Dorn) ~3%
        [221128] = _cracklingShard, -- Clawbreaker K'zithix (Isle of Dorn) ~3%
        [219271] = _cracklingShard, -- Twice-Stinger the Wretched (Isle of Dorn) ~2%
        [219284] = _cracklingShard, -- Zovex (Isle of Dorn) ~2%
        [219702] = _cracklingShard, -- Shipwright Isaebela (Isle of Dorn) ~1.9%
        [219279] = _cracklingShard, -- Flamekeeper Graz (Isle of Dorn) ~1.5%
        [219270] = _cracklingShard, -- Kronolith, Might of the Mountain (Isle of Dorn) ~1.4%
        [220890] = _cracklingShard, -- Matriarch Charfuria (Isle of Dorn) ~1.4%
        [220883] = _cracklingShard, -- Sweetspark the Oozeful (Isle of Dorn) ~1.4%
        [213115] = _cracklingShard, -- Rustul Titancap (Isle of Dorn) ~1.3%
        [221126] = _cracklingShard, -- Tephratennae (Isle of Dorn) ~1.3%
        [219265] = _cracklingShard, -- Emperor Pitfang (Isle of Dorn) ~1%
        [219264] = _cracklingShard, -- Bloodmaw (Isle of Dorn) ~1%
        [219263] = _cracklingShard, -- Warphorn (Isle of Dorn) ~1%
        [219262] = _cracklingShard, -- Springbubble (Isle of Dorn) ~1%
        [219278] = _cracklingShard, -- Shallowshell the Clacker (Isle of Dorn) ~1%

        -- Dungeon: TWW Season 1
        [210798] = { -- The Darkness (Darkflame Cleft Mythic) [Verified via logic]
            { type = "mount", itemID = 225548, name = "Wick's Lead" },
            statisticIds = { 20484 },  -- Darkflame Cleft kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [213119] = { -- Void Speaker Eirich (The Stonevault Mythic/M+) [Verified]
            { type = "item", itemID = 226683, name = "Malfunctioning Mechsuit", repeatable = false,
              questStarters = {
                  { type = "mount", itemID = 221765, name = "Stonevault Mechsuit", mountID = 2119 },
              },
              tryCountReflectsTo = { type = "mount", itemID = 221765, name = "Stonevault Mechsuit", mountID = 2119 },
            },
            statisticIds = { 20500 },  -- The Stonevault kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- 11.1 - Undermine
        [234621] = { -- Gallagio Garbage (Undermine) [Verified] â€” no loot lockout, repeatable
            { type = "mount", itemID = 229953, name = "Salvaged Goblin Gazillionaire's Flying Machine" },
        },
        [231310] = { -- Darkfuse Precipitant (Undermine) [Verified]
            { type = "mount", itemID = 229955, name = "Darkfuse Spy-Eye" },
            _miscMechanica[1],
        },

        -- 11.1 - Undermine: Miscellaneous Mechanica sources (~5% drop rate, repeatable)
        -- Cartel rares (repeatable kills, no weekly lockout)
        [234480] = _miscMechanica, -- M.A.G.N.O. (Undermine)
        [233472] = _miscMechanica, -- Voltstrike the Charged (Undermine)
        [234499] = _miscMechanica, -- Giovante (Undermine)
        [233471] = _miscMechanica, -- Scrapchewer (Undermine)
        -- Larger elite rares (weekly lockout)
        [230840] = _miscMechanica, -- Flyboy Snooty (Undermine)
        [230793] = _miscMechanica, -- The Junk-Wall (Undermine)
        [230828] = _miscMechanica, -- Chief Foreman Gutso (Undermine)
        [230800] = _miscMechanica, -- Slugger the Smart (Undermine)
        [230746] = _miscMechanica, -- Ephemeral Agent Lathyd (Undermine)
        -- Smaller daily rares
        [231288] = _miscMechanica, -- Swigs Farsight (Undermine)
        [230979] = _miscMechanica, -- S.A.L. (Undermine)
        [231017] = _miscMechanica, -- Grimewick (Undermine)
        [230940] = _miscMechanica, -- Tally Doublespeak (Undermine)
        [230946] = _miscMechanica, -- V.V. Goosworth (Undermine)
        [230951] = _miscMechanica, -- Thwack (Undermine)
        [230995] = _miscMechanica, -- Nitro (Undermine)
        [230934] = _miscMechanica, -- Ratspit (Undermine)
        [231012] = _miscMechanica, -- Candy Stickemup (Undermine)
        [230931] = _miscMechanica, -- Scrapbeak (Undermine)

        -- 11.2 - Karesh
        [234845] = { -- Sthaarbs (Karesh) [Verified]
            { type = "mount", itemID = 246160, name = "Sthaarbs's Last Lunch" },
        },
        [232195] = { -- Pearlescent Krolusk rare (Karesh) [Verified]
            { type = "mount", itemID = 246067, name = "Pearlescent Krolusk" },
        },

        -- Raid Bosses
        [218370] = { -- Queen Ansurek (Nerub-ar Palace) [Verified] - ALL DIFFICULTIES
            { type = "mount", itemID = 224147, name = "Reins of the Sureki Skyrazor" },
            statisticIds = { 40295, 40296, 40297, 40298 },  -- Ansurek kills (LFR, N, H, M)
            -- NOTE: Mount drops on ALL difficulties (~0.65-1% drop rate on all)
        },
        [241526] = { -- Chrome King Gallywix (Liberation of Undermine) [Verified]
            { type = "mount", itemID = 236960, name = "Prototype A.S.M.R." },
            statisticIds = { 41330, 41329, 41328, 41327 },  -- Gallywix kills (M, H, N, LFR)
        },

        -- ========================================
        -- MIDNIGHT 12.0
        -- NPC IDs cross-referenced with Docs/Midnight-Rare-NPC-IDs.md
        -- ========================================

        -- Harandar Zone Rares (Rootstalker Grimlynx / Vibrant Petalwing)
        [242086] = { -- Aln'sharan (unique: Echo of Aln'sharan)
            { type = "mount", itemID = 256424, name = "Echo of Aln'sharan" },
        },
        [248741] = _harandarRareMounts, -- Rhazul
        [249844] = _harandarRareMounts, -- Chironex
        [249849] = _harandarRareMounts, -- Ha'kalawe
        [249902] = _harandarRareMounts, -- Tallcap the Truthspreader
        [249962] = _harandarRareMounts, -- Queen Lashtongue
        [249997] = _harandarRareMounts, -- Chlorokyll
        [250086] = _harandarRareMounts, -- Stumpy
        [250180] = _harandarRareMounts, -- Serrasa
        [250226] = _harandarRareMounts, -- Mindrot
        [250231] = _harandarRareMounts, -- Dracaena
        [250246] = _harandarRareMounts, -- Treetop
        [250317] = _harandarRareMounts, -- Oro'ohna
        [250321] = _harandarRareMounts, -- Pterrock
        [250347] = _harandarRareMounts, -- Ahl'ua'huhi
        [250358] = _harandarRareMounts, -- Annulus the Worldshaker

        -- Eversong Woods / Quel'Thalas Rares (Cerulean Hawkstrider / Cobalt Dragonhawk)
        [240129] = _quelThalasRareMounts, -- Overfester Hydra
        [246332] = _quelThalasRareMounts, -- Warden of Weeds
        [246633] = _quelThalasRareMounts, -- Harried Hawkstrider
        [250582] = _quelThalasRareMounts, -- Bloated Snapdragon
        [250683] = _quelThalasRareMounts, -- Coralfang
        [250719] = _quelThalasRareMounts, -- Cre'van
        [250754] = _quelThalasRareMounts, -- Lady Liminus
        [250780] = _quelThalasRareMounts, -- Waverly
        [250806] = _quelThalasRareMounts, -- Lost Guardian
        [250826] = _quelThalasRareMounts, -- Banuran
        [250841] = _quelThalasRareMounts, -- Bad Zed
        [250876] = _quelThalasRareMounts, -- Terrinor
        [255302] = _quelThalasRareMounts, -- Duskburn
        [255329] = _quelThalasRareMounts, -- Malfunctioning Construct
        [255348] = _quelThalasRareMounts, -- Dame Bloodshed

        -- Zul'Aman / Atal'Aman Rares (Amani Sharptalon / Escaped Witherbark Pango)
        [242023] = _zulAmanRareMounts, -- Necrohexxer Raz'ka
        [242024] = _zulAmanRareMounts, -- The Snapping Scourge
        [242025] = _zulAmanRareMounts, -- Skullcrusher Harak
        [242026] = _zulAmanRareMounts, -- Elder Oaktalon
        [242027] = _zulAmanRareMounts, -- Depthborn Eelamental
        [242028] = _zulAmanRareMounts, -- Lightwood Borer
        [242031] = _zulAmanRareMounts, -- Spinefrill
        [242032] = _zulAmanRareMounts, -- Oophaga
        [242033] = _zulAmanRareMounts, -- Tiny Vermin
        [242034] = _zulAmanRareMounts, -- Voidtouched Crustacean
        [242035] = _zulAmanRareMounts, -- The Devouring Invader
        [245691] = _zulAmanRareMounts, -- The Decaying Diamondback
        [245692] = _zulAmanRareMounts, -- Ash'an the Empowered
        [245975] = _zulAmanRareMounts, -- Mrrlokk
        [247976] = _zulAmanRareMounts, -- Poacher Rav'ik (Atal'Aman)

        -- Voidstorm / Slayer's Rise Rares (Augmented Stormray / Sanguine Harrower)
        [238498] = _voidstormRareMounts, -- Territorial Voidscythe
        [241443] = _voidstormRareMounts, -- Tremora
        [244272] = _voidstormRareMounts, -- Sundereth the Caller
        [245044] = _voidstormRareMounts, -- Nightbrood
        [245182] = _voidstormRareMounts, -- Eruundi (Slayer's Rise)
        [256770] = _voidstormRareMounts, -- Bilemaw the Gluttonous
        [256808] = _voidstormRareMounts, -- Ravengerus
        [256821] = _voidstormRareMounts, -- Far'thana the Mad
        [256922] = _voidstormRareMounts, -- Screammaxa the Matriarch
        [256923] = _voidstormRareMounts, -- Bane of the Vilebloods
        [256924] = _voidstormRareMounts, -- Aeonelle Blackstar
        [256925] = _voidstormRareMounts, -- Lotus Darkblossom
        [256926] = _voidstormRareMounts, -- Queen o' War
        [257027] = _voidstormRareMounts, -- Rakshur the Bonegrinder (Slayer's Rise)

        -- Midnight 12.0 â€” only bosses that drop mounts (2 dungeons M/M+, 1 raid M)
        -- Source: warcraftmounts.com Patch 12.0.1; encounter IDs: wago.tools DungeonEncounter DB2
        -- difficultyIDs: 23 = Mythic dungeon, 8 = Mythic Keystone (M+), 16 = Mythic raid (all map to "Mythic")
        [231636] = { -- Restless Heart (Windrunner Spire) â€” Spectral Hawkstrider â€” encounterID 3059
            { type = "mount", itemID = 262914, name = "Spectral Hawkstrider" },
            dropDifficulty = "Mythic",
            difficultyIDs = { 23, 8 },  -- Mythic dungeon + Mythic Keystone (M+); same encounter, no separate M+ entry
        },
        [231865] = { -- Degentrius (Magisters' Terrace) â€” Lucent Hawkstrider â€” encounterID 3074 (npc=231865 wowhead)
            { type = "mount", itemID = 260231, name = "Lucent Hawkstrider" },
            dropDifficulty = "Mythic",
            difficultyIDs = { 23, 8 },  -- Mythic dungeon + Mythic Keystone (M+)
        },
        [214650] = { -- L'ura / Midnight Falls (March on Quel'Danas raid final boss) â€” encounterID 3183
            { type = "mount", itemID = 246590, name = "Ashes of Belo'ren", guaranteed = true },
            dropDifficulty = "Mythic",
            difficultyIDs = { 16 },  -- Mythic raid only
        },

        -- ========================================
        -- HOLIDAY EVENTS
        -- ========================================

        -- Holiday bosses: mounts drop from CONTAINER ITEMS, not boss corpse loot.
        -- Headless Horseman â†’ Loot-Filled Pumpkin (container 209024)
        -- Coren Direbrew â†’ Keg-Shaped Treasure Chest (container 117393)
        -- Apothecary Hummel â†’ Heart-Shaped Box (container 54537)
        -- All holiday boss mounts are tracked in the containers table below.
    },

    -- =================================================================
    -- GAME OBJECTS (Chests, Caches, Clickable Objects)
    -- Key: [objectID] = { { type, itemID, name }, ... }
    legacyObjects = {
        -- WotLK
        [193081] = { -- Alexstrasza's Gift (Eye of Eternity - post-Malygos chest)
            { type = "mount", itemID = 43952, name = "Reins of the Azure Drake" },
            { type = "mount", itemID = 43953, name = "Reins of the Blue Drake" },
        },

        -- Cataclysm
        [210220] = { -- Elementium Fragment (Dragon Soul - post-Deathwing chest)
            { type = "mount", itemID = 77067, name = "Reins of the Blazing Drake" },
            { type = "mount", itemID = 77069, name = "Life-Binder's Handmaiden" },
        },
        [207123] = { -- Kasha's Bag (Zul'Aman - timed event chest)
            { type = "mount", itemID = 69230, name = "Amani Battle Bear", guaranteed = true },
        },

        -- MoP
        [214424] = { -- Cache of Pure Energy (Mogu'shan Vaults - post-Elegon chest)
            { type = "mount", itemID = 87777, name = "Reins of the Astral Cloud Serpent" },
        },

        -- Dragonflight
        [376587] = { -- Expedition Scout's Pack (Dragon Isles - rare event)
            { type = "mount", itemID = 192055, name = "Verdant Skitterfly" },
        },

        -- Shadowlands
        [368304] = { -- Sylvanas's Chest (Sanctum of Domination Mythic)
            { type = "mount", itemID = 186642, name = "Vengeance's Reins" },
        },

        -- TWW 11.1 - Undermine
        [469857] = { -- Overflowing Dumpster (Undermine) â€” dumpster diving
            _miscMechanica[1],
        },
    },

    legacyFishing = {
        -- Global fishing drops (any expansion zone fishing pool)
        [0] = {
            { type = "mount", itemID = 46109, name = "Sea Turtle" },
        },

        -- Dalaran Underbelly (WotLK/Legion)
        [125] = {
            { type = "pet", itemID = 43698, name = "Giant Sewer Rat" },
        },

        -- Argus zones (Legion 7.3) - Pond Nettle (BoE but one-time learn)
        [885] = { -- Antoran Wastes
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },
        [830] = { -- Krokuun
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },
        [882] = { -- Mac'Aree
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },

        -- BfA zones - Great Sea Ray [Verified] (BoE, repeatable)
        [896] = { -- Drustvar
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [895] = { -- Tiragarde Sound
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [942] = { -- Stormsong Valley
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [862] = { -- Zuldazar
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [863] = { -- Nazmir
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [864] = { -- Vol'dun
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },
        [1462] = { -- Mechagon Island
            { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true },
        },

        -- Zereth Mortis (Shadowlands 9.2) - Strange Goop (BoE, repeatable)
        -- Fishing material for Deepstar Aurelid mount via Hirukon summon chain.
        -- Extremely low drop rate (~0.04%), BoE - can be sold on AH repeatedly.
        [1970] = { -- Zereth Mortis (Fishing)
            { type = "item", itemID = 187662, name = "Strange Goop", repeatable = true },
        },

        -- Midnight Nether-Warped Egg -> Nether-Warped Drake is in sources.
        -- They are materialized into this legacy `fishing` table at load time.
    },

    legacyRares = {
        -- Shadowlands: Zereth Mortis
        [180978] = { -- Hirukon (Zereth Mortis, summoned via Aurelid Lure from Strange Goop)
            { type = "mount", itemID = 187676, name = "Deepstar Polyp" },  -- Deepstar Aurelid mount
        },
    },

    legacyContainers = {
        -- WotLK Containers
        [39883] = { -- Mysterious Egg (The Oracles, Sholazar Basin)
            drops = {
                { type = "mount", itemID = 44707, name = "Reins of the Green Proto-Drake" },
            },
        },
        [44751] = { -- Hyldnir Spoils (Storm Peaks daily)
            drops = {
                { type = "mount", itemID = 43962, name = "Reins of the White Polar Bear" },
            },
        },
        [69903] = { -- Hyldnir Spoils (alternate ID)
            drops = {
                { type = "mount", itemID = 43962, name = "Reins of the White Polar Bear" },
            },
        },

        -- WoD Garrison Invasion Bags
        [116980] = { -- Gold Strongbox (Garrison Invasion Gold)
            drops = {
                { type = "mount", itemID = 116779, name = "Garn Steelmaw" },
                { type = "mount", itemID = 116673, name = "Giant Coldsnout" },
                { type = "mount", itemID = 116663, name = "Shadowhide Pearltusk" },
                { type = "mount", itemID = 116786, name = "Smoky Direwolf" },
            },
        },
        [122163] = { -- Platinum Strongbox (Garrison Invasion Platinum)
            drops = {
                { type = "mount", itemID = 116779, name = "Garn Steelmaw" },
                { type = "mount", itemID = 116673, name = "Giant Coldsnout" },
                { type = "mount", itemID = 116663, name = "Shadowhide Pearltusk" },
                { type = "mount", itemID = 116786, name = "Smoky Direwolf" },
            },
        },

        -- Legion Paragon Caches (Broken Isles)
        [152102] = { -- Court of Farondis Paragon Cache (Azsuna)
            drops = {
                { type = "mount", itemID = 147806, name = "Cloudwing Hippogryph" },
            },
        },
        [152104] = { -- Highmountain Tribe Paragon Cache
            drops = {
                { type = "mount", itemID = 147807, name = "Highmountain Elderhorn" },
            },
        },
        [152103] = { -- Dreamweavers Paragon Cache (Val'sharah)
            drops = {
                { type = "mount", itemID = 147804, name = "Wild Dreamrunner" },
            },
        },
        [152105] = { -- Nightfallen Paragon Cache (Suramar)
            drops = {
                { type = "mount", itemID = 143764, name = "Leywoven Flying Carpet" },
            },
        },
        [152106] = { -- Valarjar Paragon Cache (Stormheim)
            drops = {
                { type = "mount", itemID = 147805, name = "Valarjar Stormwing" },
            },
        },

        -- Legion Paragon Caches (Argus)
        [152923] = { -- Army of the Light Supply Cache
            drops = {
                { type = "mount", itemID = 153044, name = "Avenging Felcrusher" },
                { type = "mount", itemID = 153043, name = "Blessed Felcrusher" },
                { type = "mount", itemID = 153042, name = "Glorious Felcrusher" },
            },
        },

        -- Legion Cracked Fel-Spotted Egg (Argus panthara rares)
        [153191] = { -- Cracked Fel-Spotted Egg
            drops = {
                { type = "mount", itemID = 152840, name = "Scintillating Mana Ray" },
                { type = "mount", itemID = 152841, name = "Felglow Mana Ray" },
                { type = "mount", itemID = 152843, name = "Darkspore Mana Ray" },
                { type = "mount", itemID = 152842, name = "Vibrant Mana Ray" },
            },
        },

        -- BfA Containers
        [169940] = { -- Nazjatar Royal Snapdragon container
            drops = {
                { type = "mount", itemID = 169198, name = "Royal Snapdragon" },
            },
        },
        [169939] = { -- Nazjatar Royal Snapdragon container (alt)
            drops = {
                { type = "mount", itemID = 169198, name = "Royal Snapdragon" },
            },
        },

        -- Shadowlands Containers
        [186650] = { -- Maw supply container (9.1)
            drops = {
                { type = "mount", itemID = 186649, name = "Fierce Razorwing" },
                { type = "mount", itemID = 186644, name = "Beryl Shardhide" },
            },
        },
        [187029] = { -- Death's Advance supply container
            drops = {
                { type = "mount", itemID = 186657, name = "Soulbound Gloomcharger's Reins" },
            },
        },
        [187028] = { -- Korthia supply container
            drops = {
                { type = "mount", itemID = 186641, name = "Tamed Mauler Harness" },
            },
        },
        [185992] = { -- Assault supply container
            drops = {
                { type = "mount", itemID = 186103, name = "Undying Darkhound's Harness" },
            },
        },
        [185991] = { -- Assault supply container (alt)
            drops = {
                { type = "mount", itemID = 186000, name = "Legsplitter War Harness" },
            },
        },
        [185990] = { -- Assault supply container (Revendreth)
            drops = {
                { type = "mount", itemID = 185996, name = "Harvester's Dredwing Saddle" },
            },
        },
        [180646] = { -- Maldraxxus Slime container
            drops = {
                { type = "mount", itemID = 182081, name = "Reins of the Colossal Slaughterclaw" },
            },
        },
        [180649] = { -- Ardenweald Ardenmoth container
            drops = {
                { type = "mount", itemID = 183800, name = "Amber Ardenmoth" },
            },
        },
        [184158] = { -- Necroray container (Maldraxxus)
            drops = {
                { type = "mount", itemID = 184160, name = "Bulbous Necroray" },
                { type = "mount", itemID = 184162, name = "Pestilent Necroray" },
                { type = "mount", itemID = 184161, name = "Infested Necroray" },
            },
        },

        -- Dragonflight Containers
        [200468] = { -- Plainswalker Bearer container
            drops = {
                { type = "mount", itemID = 192791, name = "Plainswalker Bearer" },
            },
        },

        -- TWW Containers
        [228741] = { -- Dauntless Imperial Lynx bag (Hallowfall) [Verified]
            drops = {
                { type = "mount", itemID = 223318, name = "Dauntless Imperial Lynx" },
            },
        },
        [232465] = { -- Bronze Goblin Waveshredder container (Undermine)
            drops = {
                { type = "mount", itemID = 233064, name = "Bronze Goblin Waveshredder" },
            },
        },
        [233557] = { -- Personalized Goblin S.C.R.A.Per container (Undermine)
            drops = {
                { type = "mount", itemID = 229949, name = "Personalized Goblin S.C.R.A.Per" },
            },
        },
        [237132] = { -- Bilgewater Bombardier container (Undermine)
            drops = {
                { type = "mount", itemID = 229957, name = "Bilgewater Bombardier" },
            },
        },
        [237135] = { -- Blackwater Bonecrusher container (Undermine)
            drops = {
                { type = "mount", itemID = 229937, name = "Blackwater Bonecrusher" },
            },
        },
        [237133] = { -- Venture Co-ordinator container (Undermine)
            drops = {
                { type = "mount", itemID = 229951, name = "Venture Co-ordinator" },
            },
        },
        [237134] = { -- Steamwheedle Supplier container (Undermine)
            drops = {
                { type = "mount", itemID = 229943, name = "Steamwheedle Supplier" },
            },
        },
        [245611] = { -- Curious Slateback container (Karesh)
            drops = {
                { type = "mount", itemID = 242734, name = "Curious Slateback" },
            },
        },
        [239546] = { -- Void-Scarred Lynx container (Hallowfall 11.1.5)
            drops = {
                { type = "mount", itemID = 239563, name = "Void-Scarred Lynx" },
            },
        },

        -- Midnight 12.0 Paragon / Event Caches
        [267299] = { -- Slayer's Duellum Trove (Voidstorm paragon cache)
            drops = {
                { type = "mount", itemID = 257176, name = "Duskbrute Harrower" },
            },
        },
        -- Stormarion Assault (Voidstorm) weekly â€” Victorious Stormarion Pinnacle Cache
        -- If container/mount not detected, verify container item ID in-game (cache in bags) and update key/drops.
        [267300] = { -- Victorious Stormarion Pinnacle Cache
            drops = {
                { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
                { type = "pet", itemID = 257178, name = "Kai" },
            },
        },
        [268485] = { -- Victorious Stormarion Pinnacle Cache - Midnight Preseason (same loot table)
            drops = {
                { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
                { type = "pet", itemID = 257178, name = "Kai" },
            },
        },
        [260979] = { -- Victorious Stormarion Cache (blue/uncommon weekly cache; same collectible pool as pinnacle)
            drops = {
                { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
                { type = "pet", itemID = 257178, name = "Kai" },
            },
        },

        -- Holiday Containers
        -- IMPORTANT: Holiday boss mounts drop from these container items, NOT from
        -- boss corpse loot. Players receive the container once per day via LFG,
        -- open it from bags â†’ LOOT_OPENED fires with isFromItem=true â†’ ProcessContainerLoot.
        -- Multiple item IDs cover different WoW versions (Blizzard changes these per expansion).

        [54537] = { -- Heart-Shaped Box (Love is in the Air)
            drops = {
                { type = "mount", itemID = 50250, name = "Big Love Rocket" },
                { type = "mount", itemID = 235658, name = "Spring Butterfly" },
                { type = "mount", itemID = 210976, name = "X-45 Heartbreaker" },
                { type = "mount", itemID = 235823, name = "Love Witch's Sweeper" },
            },
        },

        [209024] = { -- Loot-Filled Pumpkin (Hallow's End - modern retail)
            drops = {
                { type = "mount", itemID = 37012, name = "The Horseman's Reins" },
                { type = "mount", itemID = 247721, name = "The Headless Horseman's Ghoulish Charger" },
            },
        },
        [54516] = { -- Loot-Filled Pumpkin (Hallow's End - legacy item ID)
            drops = {
                { type = "mount", itemID = 37012, name = "The Horseman's Reins" },
                { type = "mount", itemID = 247721, name = "The Headless Horseman's Ghoulish Charger" },
            },
        },

        [117393] = { -- Keg-Shaped Treasure Chest (Brewfest - modern retail)
            drops = {
                { type = "mount", itemID = 37828, name = "Great Brewfest Kodo" },
                { type = "mount", itemID = 33977, name = "Swift Brewfest Ram" },
                { type = "mount", itemID = 248761, name = "Brewfest Barrel Bomber" },
            },
        },
        [54535] = { -- Keg-Shaped Treasure Chest (Brewfest - legacy item ID)
            drops = {
                { type = "mount", itemID = 37828, name = "Great Brewfest Kodo" },
                { type = "mount", itemID = 33977, name = "Swift Brewfest Ram" },
                { type = "mount", itemID = 248761, name = "Brewfest Barrel Bomber" },
            },
        },
    },

    legacyZones = {
        -- TWW: Isle of Dorn — Crackling Shard (any killable mob in zone, <1% for normals)
        -- 17 rares with ≥1% are also in npcs section for specific tracking.
        -- hostileOnly=true: tooltip only shows on attackable units (excludes friendly NPCs/vendors)
        [2248] = { drops = _cracklingShard, hostileOnly = true }, -- Isle of Dorn (uiMapID)

        -- ========================================
        -- MIDNIGHT 12.0 - Zone Rare Mounts
        -- Any RARE in zone can drop these mounts (daily lockout per rare)
        -- raresOnly=true means tooltip only shows on rare/elite units
        -- Zone IDs: Silvermoon 2393, Isle of Quel'Danas 2424, Eversong 2395, Harandar 2413,
        --   The Den 2576, Zul'Aman 2437, Atal'Aman 2536, Arcantina 2541, Voidstorm 2405
        -- Zone IDs verified via in-game C_Map data
        -- ========================================
        -- Quel'Thalas region (Cerulean Hawkstrider, Cobalt Dragonhawk)
        [2393] = { drops = _quelThalasRareMounts, raresOnly = true },   -- Silvermoon
        [2395] = { drops = _quelThalasRareMounts, raresOnly = true },   -- Eversong Woods
        [2424] = { drops = _quelThalasRareMounts, raresOnly = true },   -- Isle of Quel'Danas
        -- Harandar (Rootstalker Grimlynx, Vibrant Petalwing)
        [2413] = { drops = _harandarRareMounts, raresOnly = true },     -- Harandar
        [2576] = { drops = _harandarRareMounts, raresOnly = true },     -- The Den
        -- Zul'Aman (Amani Sharptalon, Escaped Witherbark Pango)
        [2437] = { drops = _zulAmanRareMounts, raresOnly = true },      -- Zul'Aman
        [2536] = { drops = _zulAmanRareMounts, raresOnly = true },      -- Atal'Aman
        -- Voidstorm (Augmented Stormray, Sanguine Harrower)
        [2405] = { drops = _voidstormRareMounts, raresOnly = true },    -- Voidstorm
        [2541] = { drops = _voidstormRareMounts, raresOnly = true },     -- Arcantina
    },

    legacyEncounters = {
        -- TBC
        [652] = { 16152 },   -- Attumen the Huntsman (Karazhan)
        [733] = { 19622 },   -- Kael'thas Sunstrider (The Eye)

        -- WotLK
        [1126] = { 31125 },  -- Archavon the Stone Watcher (Vault of Archavon)
        [1127] = { 33993 },  -- Emalon the Storm Watcher (Vault of Archavon)
        [1128] = { 35013 },  -- Koralon the Flame Watcher (Vault of Archavon)
        [1129] = { 38433 },  -- Toravon the Ice Watcher (Vault of Archavon)
        [1143] = { 33288 },  -- Yogg-Saron (Ulduar)
        [1103] = { 36597 },  -- The Lich King (ICC)
        [1094] = { 28859 },  -- Malygos (Eye of Eternity)
        [742] = { 28860 },   -- Sartharion (Obsidian Sanctum)
        [1084] = { 10184 },  -- Onyxia (Onyxia's Lair)

        -- Cataclysm
        [1082] = { 52409 },  -- Ragnaros (Firelands)
        [1205] = { 55294 },  -- Ultraxion (Dragon Soul)
        [1206] = { 56173 },  -- Madness of Deathwing (Dragon Soul)

        -- MoP
        [1395] = { 60410 },  -- Elegon (Mogu'shan Vaults)
        [1578] = { 68476 },  -- Horridon (Throne of Thunder)
        [1573] = { 69712 },  -- Ji-Kun (Throne of Thunder)
        [1623] = { 71865 },  -- Garrosh Hellscream (Siege of Orgrimmar)

        -- WoD
        [1704] = { 77325 },  -- Blackhand (Blackrock Foundry)
        [1799] = { 91331 },  -- Archimonde (Hellfire Citadel)

        -- Legion
        [1866] = { 105503 }, -- Gul'dan (The Nighthold)
        [2032] = { 115767 }, -- Mistress Sassz'ine (Tomb of Sargeras)
        [2074] = { 126915, 126916 }, -- Felhounds of Sargeras (Antorus)
        [2092] = { 130352 }, -- Argus the Unmaker (Antorus)

        -- BfA
        [2291] = { 155157, 150190 }, -- HK-8 Aerial Oppression Unit (Operation: Mechagon)
        [2096] = { 126983 }, -- Harlan Sweete (Freehold)
        [2123] = { 133007 }, -- Unbound Abomination (The Underrot)
        [2143] = { 136160 }, -- King Dazar (Kings' Rest)
        [2281] = { 165396 }, -- Lady Jaina Proudmoore (BoD)
        [2271] = { 144796 }, -- Mekkatorque (BoD)
        [2375] = { 158041 }, -- N'Zoth (Ny'alotha)

        -- Shadowlands
        [2286] = { 162693 }, -- The Necrotic Wake (Nalthor the Rimebinder)
        [2441] = { 180863 }, -- Tazavesh (So'leah)
        [2439] = { 178738 }, -- The Nine (Sanctum of Domination)
        [2435] = { 175732 }, -- Sylvanas Windrunner (SoD)
        [2464] = { 180990 }, -- The Jailer (Sepulcher)

        -- Dragonflight
        [2708] = { 204931 }, -- Fyrakk (Amirdrassil)

        -- TWW
        [2652] = { 210798 }, -- Darkflame Cleft (The Darkness)
        [2653] = { 213119 }, -- The Stonevault (Void Speaker Eirich)
        [2922] = { 218370 }, -- Queen Ansurek (Nerub-ar Palace)
        [2611] = { 241526 }, -- Chrome King Gallywix (Liberation of Undermine)

        -- Midnight 12.0 â€” only encounters that drop mounts (wago.tools DungeonEncounter DB2)
        -- difficultyIDs per encounter: dungeons 23 (Mythic) + 8 (Mythic Keystone / M+); raid 16 (Mythic).
        -- Mythic+ uses the SAME encounterID as Mythic dungeon; no separate M+ encounter entry needed.
        [3059] = { 231636 },   -- Restless Heart (Windrunner Spire) â€” difficultyIDs 23, 8 â€” Spectral Hawkstrider
        [3074] = { 231865 },   -- Degentrius (Magisters' Terrace) â€” difficultyIDs 23, 8 â€” Lucent Hawkstrider
        [3183] = { 214650 },   -- Midnight Falls / L'ura (March on Quel'Danas) â€” difficultyID 16 â€” Ashes of Belo'ren
    },

    legacyEncounterNames = {
        ["Restless Heart"] = { 231636 },       -- Windrunner Spire
        ["Degentrius"] = { 231865 },           -- Magisters' Terrace
        ["Midnight Falls"] = { 214650 },       -- March on Quel'Danas
    },

    legacyLockoutQuests = {
        -- ========================================
        -- MISTS OF PANDARIA
        -- ========================================

        -- MoP: World Bosses (weekly lockout via bonus roll quest)
        [60491] = 32099,  -- Sha of Anger (Kun-Lai Summit)
        [62346] = 32098,  -- Galleon (Valley of the Four Winds)
        [69099] = 32518,  -- Nalak (Isle of Thunder)
        [69161] = 32519,  -- Oondasta (Isle of Giants)

        -- MoP: Timeless Isle (daily lockout)
        [73167] = 33311,  -- Huolon

        -- ========================================
        -- WARLORDS OF DRAENOR
        -- ========================================

        -- WoD: World Boss (weekly lockout)
        [83746] = 37464,  -- Rukhmar (Spires of Arak)
        [87493] = 37464,  -- Rukhmar (alt NPC ID)

        -- WoD: Tanaan Jungle Champions (daily lockout)
        [95044] = 39288,  -- Terrorfist
        [95053] = 39287,  -- Deathtalon
        [95054] = 39290,  -- Vengeance
        [95056] = 39289,  -- Doomroller

        -- ========================================
        -- LEGION
        -- ========================================

        -- Legion: Argus rares (daily lockout)
        [122958] = 49183,  -- Blistermaw (Antoran Wastes)
        [126040] = 48809,  -- Puscilla (Antoran Wastes)
        [126199] = 48810,  -- Vrax'thul (Antoran Wastes)
        [126852] = 48695,  -- Wrangler Kravos (Mac'Aree)
        [126867] = 48705,  -- Venomtail Skyfin (Mac'Aree)
        [126912] = 48721,  -- Skreeg the Devourer (Mac'Aree)
        [127288] = 48821,  -- Houndmaster Kerrax (Antoran Wastes)

        -- ========================================
        -- BATTLE FOR AZEROTH
        -- ========================================

        -- BfA: Warfront Arathi Highlands (cycle-based lockout)
        [142692] = { 53091, 53517 },  -- Nimar the Slayer
        [142423] = { 53014, 53518 },  -- Overseer Krix
        [142437] = { 53022, 53526 },  -- Skullripper
        [142709] = { 53083, 53504 },  -- Beastrider Kama
        [142741] = 53085,             -- Doomrider Helgrim (Alliance)
        [142739] = 53088,             -- Knight-Captain Aldrin (Horde)

        -- BfA: Warfront Darkshore (cycle-based lockout)
        [148787] = { 54695, 54696 },  -- Alash'anir
        [149652] = 54883,             -- Agathe Wyrmwood (Alliance)
        [149660] = 54890,             -- Blackpaw (Horde)
        [149655] = 54886,             -- Croz Bloodrage (Alliance)
        [149663] = 54892,             -- Shadowclaw (Horde)
        [148037] = 54431,             -- Athil Dewfire (Horde)
        [147701] = 54277,             -- Moxo the Beheader (Alliance)

        -- BfA 8.2: Mechagon / Nazjatar (daily lockout)
        [152182] = 55811,  -- Rustfeather
        [154342] = 55512,  -- Arachnoid Harvester (alt timeline)
        [151934] = 55512,  -- Arachnoid Harvester (standard)
        [152290] = 56298,  -- Soundless

        -- BfA 8.3: Vale of Eternal Blossoms assault rares (daily lockout)
        [157466] = 57363,  -- Anh-De the Loyal
        [157153] = 57344,  -- Ha-Li
        [157160] = 57345,  -- Houndlord Ren

        -- BfA 8.3: Uldum assault rares (daily lockout)
        [157134] = 57259,  -- Ishak of the Four Winds
        [162147] = 58696,  -- Corpse Eater
        [157146] = 57273,  -- Rotfeaster

        -- BfA: World Boss (weekly lockout via world quest)
        [138794] = 53000,  -- Dunegorger Kraulok

        -- ========================================
        -- SHADOWLANDS
        -- ========================================

        -- Shadowlands: Ardenweald rares (daily lockout)
        [164107] = 59145,  -- Gormtamer Tizo
        [164112] = 59157,  -- Humon'gozz
        [168647] = 61632,  -- Valfir the Unrelenting

        -- Shadowlands: Bastion (daily lockout)
        [170548] = 60862,  -- Sundancer

        -- Shadowlands: Revendreth rares (daily lockout)
        [166521] = 59869,  -- Famu the Infinite
        [165290] = 59612,  -- Harika the Horrid
        [166679] = 59900,  -- Hopecrusher
        [160821] = 58259,  -- Worldedge Gorger

        -- Shadowlands: Maldraxxus rares (daily lockout)
        [162741] = 58872,  -- Gieger
        [162586] = 58783,  -- Tahonta
        [157309] = 61720,  -- Violet Mistake
        [162690] = 58851,  -- Nerissa Heartless
        [162819] = 58889,  -- Warbringer Mal'Korak
        [162818] = 58889,  -- Warbringer Mal'Korak (alt)
        [168147] = 58784,  -- Sabriel the Bonecleaver
        [168148] = 58784,  -- Sabriel the Bonecleaver (alt)
        -- Theater of Pain combatants (shared daily lockout)
        [162873] = 62786,  -- Theater of Pain combatant
        [162880] = 62786,  -- Theater of Pain combatant
        [162875] = 62786,  -- Theater of Pain combatant
        [162853] = 62786,  -- Theater of Pain combatant
        [162874] = 62786,  -- Theater of Pain combatant
        [162872] = 62786,  -- Theater of Pain combatant

        -- Shadowlands: Maw rares (daily lockout)
        [174861] = 63433,  -- Gorged Shadehound
        [179460] = 64164,  -- Fallen Charger

        -- Shadowlands: Korthia rares (daily lockout)
        [179472] = 64246,  -- Konthrogz the Obliterator
        [180160] = 64455,  -- Reliwik the Defiant
        [179684] = 64233,  -- Malbog
        [179985] = 64313,  -- Stygian Stonecrusher
        [180032] = 64338,  -- Wild Worldcracker
        [180042] = 64349,  -- Fleshwing

        -- Shadowlands: Zereth Mortis (daily lockout)
        [180978] = 65548,  -- Hirukon

        -- ========================================
        -- DRAGONFLIGHT
        -- ========================================

        -- Dragonflight: Zaralek Cavern (daily lockout)
        [203625] = 75333,  -- Karokta

        -- Dragonflight: Forbidden Reach rares (daily lockout, shared Ancient Salamanther mount)
        [200537] = 73095,  -- Gahz'raxes
        [200579] = 73100,  -- Ishyra
        [200584] = 73111,  -- Vraken the Hunter
        [200600] = 73117,  -- Reisa the Drowned
        [200610] = 73118,  -- Duzalgor
        [200681] = 74341,  -- Bonesifter Marwak
        [200717] = 74342,  -- Galakhad
        [200721] = 73154,  -- Grugoth the Hullcrusher
        [200885] = 73222,  -- Lady Shaz'ra
        [200904] = 73229,  -- Veltrax
        [200911] = 73225,  -- Volcanakk
        [200956] = 74349,  -- Ookbeard
        [200960] = 73367,  -- Warden Entrix
        [200978] = 73385,  -- Pyrachniss
        [201013] = 73409,  -- Wyrmslayer Angvardi
        [201181] = 74283,  -- Mad-Eye Carrey

        -- ========================================
        -- THE WAR WITHIN
        -- ========================================

        -- TWW: Hallowfall / Ringing Deeps (daily lockout)
        [207802] = 81763,  -- Beledar's Spawn
        [220285] = 81633,  -- Regurgitated Mole Reins rare

        -- TWW: Azj-Kahet (daily lockout)
        [216046] = 82289,  -- Tka'ktath

        -- TWW 11.1: Undermine — Darkfuse Precipitant (weekly loot lockout)
        [231310] = 85010,  -- Darkfuse Precipitant

        -- TWW 11.1: Undermine — weekly elite rares
        [230746] = 84877,  -- Ephemeral Agent Lathyd
        [230793] = 84884,  -- The Junk-Wall
        [230800] = 84895,  -- Slugger the Smart
        [230828] = 84907,  -- Chief Foreman Gutso
        [230840] = 84911,  -- Flyboy Snooty

        -- TWW 11.1: Undermine — daily rares
        [230931] = 84917,  -- Scrapbeak
        [230934] = 84918,  -- Ratspit
        [230940] = 84919,  -- Tally Doublespeak
        [230946] = 84920,  -- V.V. Goosworth
        [230951] = 84921,  -- Thwack
        [230979] = 84922,  -- S.A.L.
        [230995] = 84926,  -- Nitro
        [231012] = 84927,  -- Candy Stickemup
        [231017] = 84928,  -- Grimewick
        [231288] = 85004,  -- Swigs Farsight

        -- TWW 11.2: Karesh (daily lockout)
        [232195] = 90593,  -- Pearlescent Krolusk
        [234845] = 91293,  -- Sthaarbs
    },

    -- Display name (EN) â†’ npcID for lockout NPCs; used to gray "Drop: Name" in Plans when no loot this period.
    lockoutNpcNames = {
        ["Darkfuse Precipitant"] = 231310,
    },

    -- =================================================================
    -- NPC NAME â†’ NPC IDs REVERSE INDEX (Midnight 12.0 tooltip fallback)
    -- When UnitGUID returns secret values inside instances, the tooltip
    -- hook reads the NPC name from the tooltip text and looks up drops
    -- by name instead of by GUID.
    -- Names MUST match the in-game English NPC display name exactly.
    -- Only instance NPCs (dungeons/raids) need entries here;
    -- open-world rares work with GUID-based lookup.
    -- =================================================================
    npcNameIndex = {
        -- Classic
        ["Baron Rivendare"] = { 10440 },
        -- AQ40 Trash (Temple of Ahn'Qiraj)
        ["Qiraji Mindslayer"] = { 15246 },
        ["Qiraji Champion"] = { 15317 },
        ["Vekniss Stinger"] = { 15247 },
        ["Anubisath Sentinel"] = { 15311 },
        ["Vekniss Wasp"] = { 15249 },
        ["Vekniss Hive Crawler"] = { 15310 },
        -- TBC
        ["Attumen the Huntsman"] = { 16152, 114262 },
        ["Kael'thas Sunstrider"] = { 19622, 24664 },
        ["Anzu"] = { 23035 },
        -- WotLK
        ["Skadi the Ruthless"] = { 26693, 174062 },
        ["Malygos"] = { 28859 },
        ["Sartharion"] = { 28860 },
        ["Yogg-Saron"] = { 33288 },
        ["Onyxia"] = { 10184 },
        ["The Lich King"] = { 36597 },
        ["Infinite Corruptor"] = { 32273 },
        ["Archavon the Stone Watcher"] = { 31125 },
        ["Emalon the Storm Watcher"] = { 33993 },
        ["Koralon the Flame Watcher"] = { 35013 },
        ["Toravon the Ice Watcher"] = { 38433 },
        -- Cataclysm
        ["Altairus"] = { 43873 },
        ["Slabhide"] = { 43214 },
        ["Al'Akir"] = { 46753 },
        ["Bloodlord Mandokir"] = { 52151 },
        ["High Priestess Kilnara"] = { 52059 },
        ["Ultraxion"] = { 55294 },
        ["Alysrazor"] = { 52530 },
        ["Ragnaros"] = { 52409 },
        ["Madness of Deathwing"] = { 56173 },
        -- MoP
        ["Elegon"] = { 60410 },
        ["Horridon"] = { 68476 },
        ["Ji-Kun"] = { 69712 },
        ["Garrosh Hellscream"] = { 71865 },
        -- WoD
        ["Blackhand"] = { 77325 },
        ["Archimonde"] = { 91331 },
        ["Rukhmar"] = { 87493, 83746 },
        -- Legion
        ["Nightbane"] = { 114895 },
        ["Gul'dan"] = { 105503, 104154, 111022 },
        ["The Demon Within"] = { 111022 },
        ["Mistress Sassz'ine"] = { 115767 },
        ["Felhounds of Sargeras"] = { 126915, 126916 },
        ["Argus the Unmaker"] = { 130352 },
        -- BfA
        ["Mail Muncher"] = { 160708 },
        ["Harlan Sweete"] = { 126983 },
        ["Unbound Abomination"] = { 133007 },
        ["King Dazar"] = { 136160 },
        ["HK-8 Aerial Oppression Unit"] = { 155157, 150190 },
        ["Arachnoid Harvester"] = { 154342, 151934 },
        ["Lady Jaina Proudmoore"] = { 165396 },
        ["High Tinker Mekkatorque"] = { 144796 },
        ["N'Zoth the Corruptor"] = { 158041 },
        -- Shadowlands
        ["Nalthor the Rimebinder"] = { 162693 },
        ["So'leah"] = { 180863 },
        ["Warbringer Mal'Korak"] = { 162819, 162818 },
        ["Sabriel the Bonecleaver"] = { 168147, 168148 },
        ["The Nine"] = { 178738 },
        ["Sylvanas Windrunner"] = { 175732 },
        ["The Jailer"] = { 180990 },
        -- Dragonflight
        ["Raszageth the Storm-Eater"] = { 189492 },
        ["Chrono-Lord Deios"] = { 198933 },
        ["Fyrakk the Blazing"] = { 204931 },
        -- TWW
        ["Wick"] = { 210797 },
        ["Void Speaker Eirich"] = { 213119 },
        ["Queen Ansurek"] = { 218370 },
        ["Chrome King Gallywix"] = { 241526 },
        -- Midnight raid boss (mount drops)
        ["Midnight Falls"] = { 214650 },
        ["L'ura"] = { 214650 },
        -- Midnight zone rares (mount drops)
        ["Aln'sharan"] = { 242086 },
        ["Rhazul"] = { 248741 },
        ["Chironex"] = { 249844 },
        ["Ha'kalawe"] = { 249849 },
        ["Tallcap the Truthspreader"] = { 249902 },
        ["Queen Lashtongue"] = { 249962 },
        ["Chlorokyll"] = { 249997 },
        ["Stumpy"] = { 250086 },
        ["Serrasa"] = { 250180 },
        ["Mindrot"] = { 250226 },
        ["Dracaena"] = { 250231 },
        ["Treetop"] = { 250246 },
        ["Oro'ohna"] = { 250317 },
        ["Pterrock"] = { 250321 },
        ["Ahl'ua'huhi"] = { 250347 },
        ["Annulus the Worldshaker"] = { 250358 },
        -- Eversong Woods / Quel'Thalas
        ["Warden of Weeds"] = { 246332 },
        ["Harried Hawkstrider"] = { 246633 },
        ["Overfester Hydra"] = { 240129 },
        ["Bloated Snapdragon"] = { 250582 },
        ["Cre'van"] = { 250719 },
        ["Coralfang"] = { 250683 },
        ["Lady Liminus"] = { 250754 },
        ["Terrinor"] = { 250876 },
        ["Bad Zed"] = { 250841 },
        ["Waverly"] = { 250780 },
        ["Banuran"] = { 250826 },
        ["Lost Guardian"] = { 250806 },
        ["Duskburn"] = { 255302 },
        ["Malfunctioning Construct"] = { 255329 },
        ["Dame Bloodshed"] = { 255348 },
        -- Zul'Aman / Atal'Aman
        ["Necrohexxer Raz'ka"] = { 242023 },
        ["The Snapping Scourge"] = { 242024 },
        ["Skullcrusher Harak"] = { 242025 },
        ["Lightwood Borer"] = { 242028 },
        ["Mrrlokk"] = { 245975 },
        ["Spinefrill"] = { 242031 },
        ["Oophaga"] = { 242032 },
        ["Tiny Vermin"] = { 242033 },
        ["Voidtouched Crustacean"] = { 242034 },
        ["The Devouring Invader"] = { 242035 },
        ["Elder Oaktalon"] = { 242026 },
        ["Depthborn Eelamental"] = { 242027 },
        ["The Decaying Diamondback"] = { 245691 },
        ["Ash'an the Empowered"] = { 245692 },
        ["Poacher Rav'ik"] = { 247976 },
        -- Voidstorm / Slayer's Rise
        ["Sundereth the Caller"] = { 244272 },
        ["Territorial Voidscythe"] = { 238498 },
        ["Tremora"] = { 241443 },
        ["Screammaxa the Matriarch"] = { 256922 },
        ["Bane of the Vilebloods"] = { 256923 },
        ["Aeonelle Blackstar"] = { 256924 },
        ["Lotus Darkblossom"] = { 256925 },
        ["Queen o' War"] = { 256926 },
        ["Ravengerus"] = { 256808 },
        ["Bilemaw the Gluttonous"] = { 256770 },
        ["Nightbrood"] = { 245044 },
        ["Far'thana the Mad"] = { 256821 },
        ["Eruundi"] = { 245182 },
        ["Rakshur the Bonegrinder"] = { 257027 },
    },
}

-- =================================================================
-- SOURCE NORMALIZATION (typed `sources` -> legacy tables)
-- Keeps backward compatibility while allowing a single standardized source schema.
-- =================================================================
local function CopyDropArray(drops)
    if type(drops) ~= "table" then return nil end
    local copy = {}
    for i = 1, #drops do
        copy[i] = drops[i]
    end
    if drops.statisticIds then copy.statisticIds = drops.statisticIds end
    if drops.dropDifficulty then copy.dropDifficulty = drops.dropDifficulty end
    return copy
end

local function MergeDropArray(target, incoming, statisticIds, dropDifficulty)
    if type(target) ~= "table" or type(incoming) ~= "table" then return end
    local seen = {}
    for i = 1, #target do
        local d = target[i]
        if d and d.itemID then
            seen[d.type .. "\0" .. tostring(d.itemID)] = true
        end
    end
    for i = 1, #incoming do
        local d = incoming[i]
        if d and d.itemID then
            local key = d.type .. "\0" .. tostring(d.itemID)
            if not seen[key] then
                target[#target + 1] = d
                seen[key] = true
            end
        end
    end
    if statisticIds and not target.statisticIds then target.statisticIds = statisticIds end
    if dropDifficulty and not target.dropDifficulty then target.dropDifficulty = dropDifficulty end
end

local function ForEachID(source, singleKey, listKey, fn)
    local id = source[singleKey]
    if id ~= nil then fn(id) end
    local ids = source[listKey]
    if type(ids) == "table" then
        for i = 1, #ids do
            if ids[i] ~= nil then fn(ids[i]) end
        end
    end
end

local function ApplyTypedSources(db)
    if not db or type(db.sources) ~= "table" then return end
    -- Single source of truth: build these tables only from sources (no legacy merge).
    db.npcs = {}
    db.rares = {}
    db.objects = {}
    db.fishing = {}
    db.containers = {}
    db.zones = {}
    db.encounters = {}
    db.encounterNames = {}
    db.lockoutQuests = {}
    if #db.sources == 0 then return end

    for i = 1, #db.sources do
        local source = db.sources[i]
        if type(source) == "table" then
            local sourceType = source.sourceType
            local drops = CopyDropArray(source.drops)

            if sourceType == "instance_boss" or sourceType == "npc" then
                local npcID = tonumber(source.npcID or source.id)
                if npcID and drops then
                    local target = db.npcs[npcID] or {}
                    MergeDropArray(target, drops, source.statisticIds, source.dropDifficulty)
                    db.npcs[npcID] = target
                end
            elseif sourceType == "world_rare" then
                local npcID = tonumber(source.npcID or source.id)
                if npcID and drops then
                    local rareTarget = db.rares[npcID] or {}
                    MergeDropArray(rareTarget, drops, source.statisticIds, source.dropDifficulty)
                    db.rares[npcID] = rareTarget
                end
            elseif sourceType == "object" then
                local objectID = tonumber(source.objectID or source.id)
                if objectID and drops then
                    local target = db.objects[objectID] or {}
                    MergeDropArray(target, drops)
                    db.objects[objectID] = target
                end
            elseif sourceType == "container" then
                local containerItemID = tonumber(source.containerItemID or source.itemID or source.id)
                if containerItemID and drops then
                    local entry = db.containers[containerItemID] or {}
                    local target = entry.drops or entry
                    if type(target) ~= "table" then target = {} end
                    MergeDropArray(target, drops)
                    db.containers[containerItemID] = { drops = target }
                end
            elseif sourceType == "fishing" then
                if drops then
                    ForEachID(source, "mapID", "mapIDs", function(rawMapID)
                        local mapID = tonumber(rawMapID)
                        if mapID then
                            local target = db.fishing[mapID] or {}
                            MergeDropArray(target, drops)
                            db.fishing[mapID] = target
                        end
                    end)
                end
            elseif sourceType == "zone_drop" then
                if drops then
                    ForEachID(source, "mapID", "mapIDs", function(rawMapID)
                        local mapID = tonumber(rawMapID)
                        if mapID then
                            local existing = db.zones[mapID]
                            local zoneEntry
                            if type(existing) == "table" and existing.drops then
                                zoneEntry = existing
                            else
                                zoneEntry = { drops = type(existing) == "table" and existing or {} }
                            end
                            MergeDropArray(zoneEntry.drops, drops)
                            if source.raresOnly then zoneEntry.raresOnly = true end
                            db.zones[mapID] = zoneEntry
                        end
                    end)
                end
            elseif sourceType == "encounter" then
                local encounterID = tonumber(source.encounterID or source.id)
                if encounterID and type(source.npcIDs) == "table" and #source.npcIDs > 0 then
                    db.encounters[encounterID] = source.npcIDs
                end
            elseif sourceType == "encounter_name" then
                local encounterName = source.encounterName or source.name
                if type(encounterName) == "string" and encounterName ~= "" and type(source.npcIDs) == "table" and #source.npcIDs > 0 then
                    db.encounterNames[encounterName] = source.npcIDs
                end
            elseif sourceType == "lockout_quest" then
                local npcID = tonumber(source.npcID or source.id)
                if npcID then
                    if source.questID then
                        db.lockoutQuests[npcID] = source.questID
                    elseif type(source.questIDs) == "table" and #source.questIDs > 0 then
                        db.lockoutQuests[npcID] = source.questIDs
                    end
                end
            end
        end
    end
end

ApplyTypedSources(ns.CollectibleSourceDB)

-- Merge deprecated legacy* tables into runtime npcs/rares/... so existing data still works.
-- Do not add to legacy*; add only to sources. Legacy tables will be removed once migrated.
local function MergeLegacyIntoRuntime(db)
    if not db then return end
    local function mergeNpc(destKey, src)
        if type(src) ~= "table" then return end
        for npcID, data in pairs(src) do
            if type(data) == "table" then
                local target = db[destKey][npcID] or {}
                MergeDropArray(target, data, data.statisticIds, data.dropDifficulty)
                db[destKey][npcID] = target
            end
        end
    end
    mergeNpc("npcs", db.legacyNpcs)
    mergeNpc("rares", db.legacyRares)
    if db.legacyObjects then
        for objectID, data in pairs(db.legacyObjects) do
            if type(data) == "table" and not db.objects[objectID] then
                db.objects[objectID] = CopyDropArray(data)
            end
        end
    end
    if db.legacyFishing then
        for mapID, data in pairs(db.legacyFishing) do
            if type(data) == "table" and not db.fishing[mapID] then
                db.fishing[mapID] = CopyDropArray(data)
            end
        end
    end
    if db.legacyContainers then
        for cid, data in pairs(db.legacyContainers) do
            if type(data) == "table" then
                local drops = data.drops or data
                if not db.containers[cid] then db.containers[cid] = { drops = CopyDropArray(drops) } end
            end
        end
    end
    if db.legacyZones then
        for mapID, data in pairs(db.legacyZones) do
            if type(data) == "table" then
                local zd = db.zones[mapID] or { drops = {} }
                MergeDropArray(zd.drops, data.drops or data)
                if data.raresOnly then zd.raresOnly = true end
                if data.hostileOnly then zd.hostileOnly = true end
                db.zones[mapID] = zd
            end
        end
    end
    if db.legacyEncounters then
        for eid, npcIDs in pairs(db.legacyEncounters) do
            if not db.encounters[eid] then db.encounters[eid] = npcIDs end
        end
    end
    if db.legacyEncounterNames then
        for name, npcIDs in pairs(db.legacyEncounterNames) do
            if not db.encounterNames[name] then db.encounterNames[name] = npcIDs end
        end
    end
    if db.legacyLockoutQuests then
        for npcID, q in pairs(db.legacyLockoutQuests) do
            if not db.lockoutQuests[npcID] then db.lockoutQuests[npcID] = q end
        end
    end
end
MergeLegacyIntoRuntime(ns.CollectibleSourceDB)

-- =================================================================
-- TOY SOURCE LOOKUP (for Plans + Collections)
-- Returns display string when this toy is in the DB (npc/container/zone/fishing/rare).
-- Used to enrich tooltip source when Blizzard returns "Toy Collection".
-- Uses lazy-built O(1) index so repeated lookups do not scan all tables.
-- =================================================================
function ns.CollectibleSourceDB.GetSourceStringForToy(itemID)
    if not itemID or type(itemID) ~= "number" then return nil end
    local db = ns.CollectibleSourceDB
    if not db then return nil end

    -- Lazy-build index once: itemID -> sourceString (O(1) lookup, one-time O(n) build)
    if not db._toySourceByItemID then
        local dropLabel = (ns.L and ns.L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop"
        local zoneDrop = (ns.L and ns.L["ZONE_DROP"]) or "Zone drop"
        local fishing = (ns.L and ns.L["FISHING"]) or "Fishing"
        local idx = {}
        local function npcIDToName(npcID)
            if not db.npcNameIndex then return nil end
            for name, ids in pairs(db.npcNameIndex) do
                if ids then
                    for i = 1, #ids do
                        if ids[i] == npcID then return name end
                    end
                end
            end
            return nil
        end
        -- Build index from all sources (first match wins; npcs/rares use name when available)
        if db.npcs then
            for npcID, list in pairs(db.npcs) do
                if type(list) == "table" then
                    for j = 1, #list do
                        local d = list[j]
                        if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                            local name = npcIDToName(npcID)
                            idx[d.itemID] = name and (dropLabel .. " : " .. name) or (dropLabel .. " (NPC " .. tostring(npcID) .. ")")
                        end
                    end
                end
            end
        end
        if db.rares then
            for npcID, list in pairs(db.rares) do
                if type(list) == "table" then
                    for j = 1, #list do
                        local d = list[j]
                        if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                            local name = npcIDToName(npcID)
                            idx[d.itemID] = name and (dropLabel .. " : " .. name) or (dropLabel .. " (NPC " .. tostring(npcID) .. ")")
                        end
                    end
                end
            end
        end
        if db.containers then
            for containerItemID, data in pairs(db.containers) do
                if data and data.drops then
                    for j = 1, #data.drops do
                        local d = data.drops[j]
                        if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                            local containerName = (GetItemInfo and GetItemInfo(containerItemID)) or nil
                            idx[d.itemID] = (containerName and containerName ~= "") and ("Contained in : " .. containerName) or "Contained in"
                        end
                    end
                end
            end
        end
        if db.zones then
            for mapID, data in pairs(db.zones) do
                if data then
                    local drops = data.drops or data
                    if type(drops) == "table" then
                        for j = 1, #drops do
                            local d = drops[j]
                            if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                                idx[d.itemID] = zoneDrop
                            end
                        end
                    end
                end
            end
        end
        if db.fishing then
            for mapID, list in pairs(db.fishing) do
                if type(list) == "table" then
                    for j = 1, #list do
                        local d = list[j]
                        if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                            idx[d.itemID] = fishing
                        end
                    end
                end
            end
        end
        if db.objects then
            for objectID, list in pairs(db.objects) do
                if type(list) == "table" then
                    for j = 1, #list do
                        local d = list[j]
                        if d and d.type == "toy" and d.itemID and not idx[d.itemID] then
                            idx[d.itemID] = dropLabel .. " (Object " .. tostring(objectID) .. ")"  -- objectID has no colon
                        end
                    end
                end
            end
        end
        db._toySourceByItemID = idx
    end

    return db._toySourceByItemID[itemID]
end

-- =================================================================
-- MOUNT SOURCE LOOKUP (for Plans when API returns empty)
-- Returns display string when mount is in DB (fishing, zone_drop, npc, etc.).
-- Used when C_MountJournal.GetMountInfoExtraByID returns empty (e.g. Nether-Warped Drake).
-- Lazy-builds mountID -> sourceString index via GetMountFromItem(itemID).
-- =================================================================
function ns.CollectibleSourceDB.GetSourceStringForMount(mountID)
    if not mountID or type(mountID) ~= "number" then return nil end
    local db = ns.CollectibleSourceDB
    if not db then return nil end
    if not C_MountJournal or not C_MountJournal.GetMountFromItem then return nil end

    if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end

    if not db._mountSourceByMountID then
        local dropLabel = (ns.L and ns.L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop"
        local zoneDrop = (ns.L and ns.L["ZONE_DROP"]) or "Zone drop"
        local fishing = (ns.L and ns.L["FISHING"]) or "Fishing"
        local idx = {}
        local function addMount(itemID, sourceStr)
            if not itemID then return end
            local mID = C_MountJournal.GetMountFromItem(itemID)
            if mID and (not issecretvalue or not issecretvalue(mID)) and not idx[mID] then
                idx[mID] = sourceStr
            end
        end
        local function collectMountsFromDrops(drops, sourceStr)
            if not drops or type(drops) ~= "table" then return end
            for j = 1, #drops do
                local d = drops[j]
                if d then
                    if d.type == "mount" and d.itemID then
                        addMount(d.itemID, sourceStr)
                    end
                    if d.yields and type(d.yields) == "table" then
                        for k = 1, #d.yields do
                            local y = d.yields[k]
                            if y and y.type == "mount" and y.itemID then
                                addMount(y.itemID, sourceStr)
                            end
                        end
                    end
                end
            end
        end
        local function npcIDToName(npcID)
            if not db.npcNameIndex then return nil end
            for name, ids in pairs(db.npcNameIndex or {}) do
                if ids then
                    for i = 1, #ids do
                        if ids[i] == npcID then return name end
                    end
                end
            end
            return nil
        end
        if db.npcs then
            for npcID, list in pairs(db.npcs) do
                if type(list) == "table" then
                    local name = npcIDToName(npcID)
                    local src = name and (dropLabel .. " : " .. name) or (dropLabel .. " (NPC " .. tostring(npcID) .. ")")
                    collectMountsFromDrops(list, src)
                end
            end
        end
        if db.rares then
            for npcID, list in pairs(db.rares) do
                if type(list) == "table" then
                    local name = npcIDToName(npcID)
                    local src = name and (dropLabel .. " : " .. name) or (dropLabel .. " (NPC " .. tostring(npcID) .. ")")
                    collectMountsFromDrops(list, src)
                end
            end
        end
        if db.fishing then
            for mapID, list in pairs(db.fishing) do
                if type(list) == "table" then
                    collectMountsFromDrops(list, fishing)
                end
            end
        end
        if db.zones then
            for zMapID, data in pairs(db.zones) do
                local drops = data and (data.drops or data)
                if type(drops) == "table" then
                    collectMountsFromDrops(drops, zoneDrop)
                end
            end
        end
        if db.containers then
            for containerItemID, cData in pairs(db.containers) do
                if cData and cData.drops then
                    local containerName = (GetItemInfo and GetItemInfo(containerItemID)) or nil
                    local src = (containerName and containerName ~= "") and ("Contained in : " .. containerName) or "Contained in"
                    collectMountsFromDrops(cData.drops, src)
                end
            end
        end
        if db.objects then
            for objectID, list in pairs(db.objects) do
                if type(list) == "table" then
                    collectMountsFromDrops(list, dropLabel .. " (Object " .. tostring(objectID) .. ")")
                end
            end
        end
        db._mountSourceByMountID = idx
    end

    return db._mountSourceByMountID[mountID]
end
