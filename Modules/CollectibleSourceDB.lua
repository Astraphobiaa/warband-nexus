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
      Zone rare:    { sourceType = "zone_drop", mapID = 2395, raresOnly = true, hostileOnly = true, drops = _quelThalasRareMounts }
      Container:    { sourceType = "container", containerItemID = 39883, drops = {...} }
      Encounter:    { sourceType = "encounter", encounterID = 652, npcIDs = { 16152 } }

    DROP ENTRY FORMAT (inside drops):
      - type: "mount", "pet", "toy", or "item"
      - itemID, name: required
      - guaranteed: optional; 100% drop, no try count
      - repeatable: optional; resets try count on obtain
      - yields: optional; for "item" that leads to mount/pet (e.g. egg -> mount)
      - statisticIds: on the NPC array and/or per drop row — list every WoW Statistics column that counts
        kills/attempts for that source (LFR, Normal, Heroic, Mythic, legacy 10/25, etc.). Same mount from
        multiple bosses or difficulties must each contribute IDs; TryCounter merges rows that share the same
        mount/pet try key into one summed seed. dropDifficulty gates loot/encounter UI only, not which stats are merged.

    npcs, rares, objects, fishing, containers, zones, encounters, encounterNames, lockoutQuests
    are built at load from sources only. Do not add data to any legacy table.

    Mount NPC audits: cross-checked against community-maintained open-source mount
    datasets (Classic through Midnight) and DB2 CSV exports where needed.
]]

local ADDON_NAME, ns = ...

-- =====================================================================
-- BfA "Zone Drop" mounts - shared drop tables (referenced by multiple NPC entries)
-- These mounts drop from specific mob factions within a zone, NOT every mob.
--
-- Cross-check: community-maintained BfA mount datasets (baseline npcs={} per itemId) and
-- third-party "dropped by" listings (often larger: shared loot templates, phasing, creature templates).
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
-- =====================================================================

-- Quel'Thalas (Eversong Woods / Ghostlands) - 2 mounts from any zone rare
local _quelThalasRareMounts = {
    { type = "mount", itemID = 257156, name = "Cerulean Hawkstrider" },
    { type = "mount", itemID = 257147, name = "Cobalt Dragonhawk" },
}

-- Zul'Aman - 2 mounts from any zone rare
-- NOTE: Ancestral War Bear (257223) — Honored Warrior's Cache (obj 613727); guaranteed puzzle reward, not tracked.
-- NOTE: Hexed Vilefeather Eagle (257444) — Abandoned Ritual Skull (obj 539047); guaranteed, not tracked.
local _zulAmanRareMounts = {
    { type = "mount", itemID = 257152, name = "Amani Sharptalon" },
    { type = "mount", itemID = 257200, name = "Escaped Witherbark Pango" },
}

-- Harandar - 2 mounts from any zone rare
-- NOTE: Ruddy Sporeglider (252017) — Peculiar Cauldron (obj 614483); guaranteed puzzle reward, not tracked.
-- NOTE: Untainted Grove Crawler (256423) — Sporespawned Cache (obj 615963); guaranteed, not tracked.
local _harandarRareMounts = {
    { type = "mount", itemID = 246735, name = "Rootstalker Grimlynx" },
    { type = "mount", itemID = 252012, name = "Vibrant Petalwing" },
}

-- Voidstorm - 2 mounts from any zone rare
-- NOTE: Reins of the Insatiable Shredclaw (257446) — Final Clutch of Predaxas (obj 605169); guaranteed puzzle reward, not tracked.
local _voidstormRareMounts = {
    { type = "mount", itemID = 257085, name = "Augmented Stormray" },
    { type = "mount", itemID = 260635, name = "Sanguine Harrower" },
}

-- MIDNIGHT 12.0 Fishing mount chain:
-- Nether-Warped Egg -> Nether-Warped Drake (mount; item 260916 = "Lost Nether Drake" in-game).
-- Drop source: direct fishing loot (bobber/pool) in ALL main Midnight zones.
-- Verified against community fishing-zone datasets:
--   Eversong Woods (2395), Harandar (2413), Zul'Aman (2437), Voidstorm (2405), Slayer's Rise (2444).
-- Sub-zones (Silvermoon 2393, Isle of Quel'Danas 2424, The Den 2576, Atal'Aman 2536, Arcantina 2541)
-- are reached automatically by CollectFishingDropsForZone()'s parent-map-chain walker.
-- NOTE: Patient Treasure chests that spawn while fishing are world objects (GameObject), NOT fishing loot.
-- The addon's ClassifyLootSession skips GameObject-only sources that lack a bobber/pool, so Patient
-- Treasure opens never route to ProcessFishingLoot. This is expected — only bobber/pool catches count.
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
    version = "12.0.34",
    lastUpdated = "2026-04-18",
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
            mapIDs = { 2395, 2413, 2437, 2405, 2444 },  -- Eversong, Harandar, Zul'Aman, Voidstorm, Slayer's Rise
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

        -- =====================================================================
        -- World Rares
        -- =====================================================================
        { sourceType = "world_rare", npcID = 180978,
          -- Hirukon (Zereth Mortis, summoned via Aurelid Lure from Strange Goop)
          drops = { { type = "mount", itemID = 187676, name = "Deepstar Polyp" } },
        },

        -- =====================================================================
        -- Game Objects (chests / post-boss caches)
        -- INTENTIONAL DUPLICATE mount itemIDs vs npcs: many raids put loot on a
        -- GameObject chest while the boss NPC row drives statistics/encounter context.
        -- =====================================================================
        -- WotLK
        { sourceType = "object", objectID = 193081,  -- Alexstrasza's Gift (Eye of Eternity - post-Malygos chest)
          drops = {
              { type = "mount", itemID = 43952, name = "Reins of the Azure Drake" },
              { type = "mount", itemID = 43953, name = "Reins of the Blue Drake" },
          },
        },
        -- Cataclysm
        { sourceType = "object", objectID = 210220,  -- Elementium Fragment (Dragon Soul - post-Deathwing chest)
          drops = {
              { type = "mount", itemID = 77067, name = "Reins of the Blazing Drake" },
              { type = "mount", itemID = 77069, name = "Life-Binder's Handmaiden" },
          },
        },
        -- MoP
        { sourceType = "object", objectID = 214424,  -- Cache of Pure Energy (Mogu'shan Vaults - post-Elegon chest)
          drops = { { type = "mount", itemID = 87777, name = "Reins of the Astral Cloud Serpent" } },
        },
        -- Shadowlands
        { sourceType = "object", objectID = 368304,  -- Sylvanas's Chest (Sanctum of Domination Mythic)
          drops = { { type = "mount", itemID = 186642, name = "Vengeance's Reins" } },
        },
        -- Dragonflight
        { sourceType = "object", objectID = 376587,  -- Expedition Scout's Pack (Dragon Isles - rare event)
          drops = { { type = "mount", itemID = 192764, name = "Verdant Skitterfly" } },
        },
        -- TWW 11.1 - Undermine
        { sourceType = "object", objectID = 469857,  -- Overflowing Dumpster (Undermine) — dumpster diving
          drops = { _miscMechanica[1] },
        },

        -- =====================================================================
        -- Fishing
        -- =====================================================================
        -- Global (any expansion zone fishing pool)
        { sourceType = "fishing", mapID = 0,
          drops = { { type = "mount", itemID = 46109, name = "Sea Turtle" } },
        },
        -- Dalaran Underbelly (WotLK/Legion)
        { sourceType = "fishing", mapID = 125,
          drops = { { type = "pet", itemID = 43698, name = "Giant Sewer Rat" } },
        },
        -- Argus zones (Legion 7.3) - Pond Nettle (BoE but one-time learn)
        { sourceType = "fishing", mapIDs = { 885, 830, 882 },  -- Antoran Wastes, Krokuun, Mac'Aree
          drops = { { type = "mount", itemID = 152912, name = "Pond Nettle" } },
        },
        -- BfA zones - Great Sea Ray (BoE, repeatable)
        { sourceType = "fishing",
          mapIDs = { 896, 895, 942, 862, 863, 864, 1462 },  -- Drustvar, Tiragarde Sound, Stormsong Valley, Zuldazar, Nazmir, Vol'dun, Mechagon Island
          drops = { { type = "mount", itemID = 163131, name = "Great Sea Ray", repeatable = true } },
        },
        -- Zereth Mortis (Shadowlands 9.2) - Strange Goop (BoE, extremely rare ~0.04%)
        -- Fishing material for Deepstar Aurelid mount via Hirukon summon chain.
        { sourceType = "fishing", mapID = 1970,
          drops = { { type = "item", itemID = 187662, name = "Strange Goop", repeatable = true } },
        },

        -- =====================================================================
        -- Containers
        -- =====================================================================
        -- WotLK
        { sourceType = "container", containerItemID = 39883,  -- Mysterious Egg (The Oracles, Sholazar Basin)
          drops = { { type = "mount", itemID = 44707, name = "Reins of the Green Proto-Drake" } },
        },
        { sourceType = "container", containerItemID = 44751,  -- Hyldnir Spoils (Storm Peaks daily)
          drops = { { type = "mount", itemID = 43962, name = "Reins of the White Polar Bear" } },
        },
        { sourceType = "container", containerItemID = 69903,  -- Hyldnir Spoils (alternate ID)
          drops = { { type = "mount", itemID = 43962, name = "Reins of the White Polar Bear" } },
        },
        -- WoD Garrison Invasion Bags
        { sourceType = "container", containerItemID = 116980,  -- Gold Strongbox (Garrison Invasion Gold)
          drops = {
              { type = "mount", itemID = 116779, name = "Garn Steelmaw" },
              { type = "mount", itemID = 116673, name = "Giant Coldsnout" },
              { type = "mount", itemID = 116663, name = "Shadowhide Pearltusk" },
              { type = "mount", itemID = 116786, name = "Smoky Direwolf" },
          },
        },
        { sourceType = "container", containerItemID = 122163,  -- Platinum Strongbox (Garrison Invasion Platinum)
          drops = {
              { type = "mount", itemID = 116779, name = "Garn Steelmaw" },
              { type = "mount", itemID = 116673, name = "Giant Coldsnout" },
              { type = "mount", itemID = 116663, name = "Shadowhide Pearltusk" },
              { type = "mount", itemID = 116786, name = "Smoky Direwolf" },
          },
        },
        -- Legion Paragon Caches (Broken Isles)
        { sourceType = "container", containerItemID = 152102,  -- Court of Farondis Paragon Cache (Azsuna)
          drops = { { type = "mount", itemID = 147806, name = "Cloudwing Hippogryph" } },
        },
        { sourceType = "container", containerItemID = 152104,  -- Highmountain Tribe Paragon Cache
          drops = { { type = "mount", itemID = 147807, name = "Highmountain Elderhorn" } },
        },
        { sourceType = "container", containerItemID = 152103,  -- Dreamweavers Paragon Cache (Val'sharah)
          drops = { { type = "mount", itemID = 147804, name = "Wild Dreamrunner" } },
        },
        { sourceType = "container", containerItemID = 152105,  -- Nightfallen Paragon Cache (Suramar)
          drops = { { type = "mount", itemID = 143764, name = "Leywoven Flying Carpet" } },
        },
        { sourceType = "container", containerItemID = 152106,  -- Valarjar Paragon Cache (Stormheim)
          drops = { { type = "mount", itemID = 147805, name = "Valarjar Stormwing" } },
        },
        -- Legion Paragon Caches (Argus)
        { sourceType = "container", containerItemID = 152923,  -- Army of the Light Supply Cache
          drops = {
              { type = "mount", itemID = 153044, name = "Avenging Felcrusher" },
              { type = "mount", itemID = 153043, name = "Blessed Felcrusher" },
              { type = "mount", itemID = 153042, name = "Glorious Felcrusher" },
          },
        },
        -- Legion Cracked Fel-Spotted Egg (Argus panthara rares)
        { sourceType = "container", containerItemID = 153191,  -- Cracked Fel-Spotted Egg
          drops = {
              { type = "mount", itemID = 152840, name = "Scintillating Mana Ray" },
              { type = "mount", itemID = 152841, name = "Felglow Mana Ray" },
              { type = "mount", itemID = 152843, name = "Darkspore Mana Ray" },
              { type = "mount", itemID = 152842, name = "Vibrant Mana Ray" },
          },
        },
        -- BfA Containers
        { sourceType = "container", containerItemID = 169940,  -- Nazjatar Royal Snapdragon container
          drops = { { type = "mount", itemID = 169198, name = "Royal Snapdragon" } },
        },
        { sourceType = "container", containerItemID = 169939,  -- Nazjatar Royal Snapdragon container (alt)
          drops = { { type = "mount", itemID = 169198, name = "Royal Snapdragon" } },
        },
        -- Shadowlands Containers
        { sourceType = "container", containerItemID = 186650,  -- Maw supply container (9.1)
          drops = {
              { type = "mount", itemID = 186649, name = "Fierce Razorwing" },
              { type = "mount", itemID = 186644, name = "Beryl Shardhide" },
          },
        },
        { sourceType = "container", containerItemID = 187029,  -- Death's Advance supply container
          drops = { { type = "mount", itemID = 186657, name = "Soulbound Gloomcharger's Reins" } },
        },
        { sourceType = "container", containerItemID = 187028,  -- Korthia supply container
          drops = { { type = "mount", itemID = 186641, name = "Tamed Mauler Harness" } },
        },
        { sourceType = "container", containerItemID = 185992,  -- Assault supply container
          drops = { { type = "mount", itemID = 186103, name = "Undying Darkhound's Harness" } },
        },
        { sourceType = "container", containerItemID = 185991,  -- Assault supply container (alt)
          drops = { { type = "mount", itemID = 186000, name = "Legsplitter War Harness" } },
        },
        { sourceType = "container", containerItemID = 185990,  -- Assault supply container (Revendreth)
          drops = { { type = "mount", itemID = 185996, name = "Harvester's Dredwing Saddle" } },
        },
        { sourceType = "container", containerItemID = 180646,  -- Maldraxxus Slime container
          drops = { { type = "mount", itemID = 182081, name = "Reins of the Colossal Slaughterclaw" } },
        },
        { sourceType = "container", containerItemID = 180649,  -- Ardenweald Ardenmoth container
          drops = { { type = "mount", itemID = 183800, name = "Amber Ardenmoth" } },
        },
        { sourceType = "container", containerItemID = 184158,  -- Necroray container (Maldraxxus)
          drops = {
              { type = "mount", itemID = 184160, name = "Bulbous Necroray" },
              { type = "mount", itemID = 184162, name = "Pestilent Necroray" },
              { type = "mount", itemID = 184161, name = "Infested Necroray" },
          },
        },
        -- Dragonflight Containers
        { sourceType = "container", containerItemID = 200468,  -- Plainswalker Bearer container
          drops = { { type = "mount", itemID = 192791, name = "Plainswalker Bearer" } },
        },
        -- TWW Containers
        { sourceType = "container", containerItemID = 228741,  -- Dauntless Imperial Lynx bag (Hallowfall)
          drops = { { type = "mount", itemID = 223318, name = "Dauntless Imperial Lynx" } },
        },
        { sourceType = "container", containerItemID = 232465,  -- Bronze Goblin Waveshredder container (Undermine)
          drops = { { type = "mount", itemID = 233064, name = "Bronze Goblin Waveshredder" } },
        },
        { sourceType = "container", containerItemID = 233557,  -- Personalized Goblin S.C.R.A.Per container (Undermine)
          drops = { { type = "mount", itemID = 229949, name = "Personalized Goblin S.C.R.A.Per" } },
        },
        { sourceType = "container", containerItemID = 237132,  -- Bilgewater Bombardier container (Undermine)
          drops = { { type = "mount", itemID = 229957, name = "Bilgewater Bombardier" } },
        },
        { sourceType = "container", containerItemID = 237135,  -- Blackwater Bonecrusher container (Undermine)
          drops = { { type = "mount", itemID = 229937, name = "Blackwater Bonecrusher" } },
        },
        { sourceType = "container", containerItemID = 237133,  -- Venture Co-ordinator container (Undermine)
          drops = { { type = "mount", itemID = 229951, name = "Venture Co-ordinator" } },
        },
        { sourceType = "container", containerItemID = 237134,  -- Steamwheedle Supplier container (Undermine)
          drops = { { type = "mount", itemID = 229943, name = "Steamwheedle Supplier" } },
        },
        { sourceType = "container", containerItemID = 245611,  -- Curious Slateback container (Karesh)
          drops = { { type = "mount", itemID = 242734, name = "Curious Slateback" } },
        },
        { sourceType = "container", containerItemID = 239546,  -- Void-Scarred Lynx container (Hallowfall 11.1.5)
          drops = { { type = "mount", itemID = 239563, name = "Void-Scarred Lynx" } },
        },
        -- Midnight 12.0 Paragon / Event Caches
        { sourceType = "container", containerItemID = 267299,  -- Slayer's Duellum Trove (Voidstorm paragon cache)
          drops = { { type = "mount", itemID = 257176, name = "Duskbrute Harrower" } },
        },
        { sourceType = "container", containerItemID = 267300,  -- Victorious Stormarion Pinnacle Cache
          drops = {
              { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
              { type = "pet",   itemID = 257178, name = "Kai" },
          },
        },
        { sourceType = "container", containerItemID = 268485,  -- Victorious Stormarion Pinnacle Cache (Midnight Preseason)
          drops = {
              { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
              { type = "pet",   itemID = 257178, name = "Kai" },
          },
        },
        { sourceType = "container", containerItemID = 260979,  -- Victorious Stormarion Cache (blue/uncommon weekly)
          drops = {
              { type = "mount", itemID = 257180, name = "Reins of the Contained Stormarion Defender" },
              { type = "pet",   itemID = 257178, name = "Kai" },
          },
        },
        -- Holiday Containers
        -- IMPORTANT: Holiday boss mounts drop from these container items, NOT from boss corpse loot.
        -- Players receive the container once per day via LFG, open from bags → ProcessContainerLoot.
        { sourceType = "container", containerItemID = 54537,  -- Heart-Shaped Box (Love is in the Air)
          drops = {
              { type = "mount", itemID = 50250,  name = "Big Love Rocket" },
              { type = "mount", itemID = 235658, name = "Spring Butterfly" },
              { type = "mount", itemID = 210976, name = "X-45 Heartbreaker" },
              { type = "mount", itemID = 235823, name = "Love Witch's Sweeper" },
          },
        },
        { sourceType = "container", containerItemID = 209024,  -- Loot-Filled Pumpkin (Hallow's End - modern retail)
          drops = {
              { type = "mount", itemID = 37012,  name = "The Horseman's Reins" },
              { type = "mount", itemID = 247721, name = "The Headless Horseman's Ghoulish Charger" },
          },
        },
        { sourceType = "container", containerItemID = 54516,  -- Loot-Filled Pumpkin (Hallow's End - legacy item ID)
          drops = {
              { type = "mount", itemID = 37012,  name = "The Horseman's Reins" },
              { type = "mount", itemID = 247721, name = "The Headless Horseman's Ghoulish Charger" },
          },
        },
        { sourceType = "container", containerItemID = 117393,  -- Keg-Shaped Treasure Chest (Brewfest - modern retail)
          drops = {
              { type = "mount", itemID = 37828,  name = "Great Brewfest Kodo" },
              { type = "mount", itemID = 33977,  name = "Swift Brewfest Ram" },
              { type = "mount", itemID = 248761, name = "Brewfest Barrel Bomber" },
          },
        },
        { sourceType = "container", containerItemID = 54535,  -- Keg-Shaped Treasure Chest (Brewfest - legacy item ID)
          drops = {
              { type = "mount", itemID = 37828,  name = "Great Brewfest Kodo" },
              { type = "mount", itemID = 33977,  name = "Swift Brewfest Ram" },
              { type = "mount", itemID = 248761, name = "Brewfest Barrel Bomber" },
          },
        },

        -- =====================================================================
        -- Zone Drops
        -- =====================================================================
        -- TWW: Isle of Dorn — Crackling Shard (any killable mob in zone, <1% for normals)
        -- 17 rares with ≥1% are also in npcs section for specific tracking.
        -- hostileOnly=true: tooltip only shows on attackable units (excludes friendly NPCs/vendors)
        { sourceType = "zone_drop", mapID = 2248, hostileOnly = true,
          drops = _cracklingShard,  -- Isle of Dorn (uiMapID)
        },
        -- MIDNIGHT 12.0 - Zone Rare Mounts (any RARE in zone, daily lockout per rare)
        -- raresOnly=true: tooltip only on rare/elite/worldboss classification
        -- hostileOnly=true: also require UnitCanAttack (excludes Restoration Stones etc. that use Creature tooltip + rare vignette)
        -- Quel'Thalas region (Cerulean Hawkstrider, Cobalt Dragonhawk)
        { sourceType = "zone_drop", mapIDs = { 2393, 2395, 2424 }, raresOnly = true, hostileOnly = true,
          drops = _quelThalasRareMounts,  -- Silvermoon, Eversong Woods, Isle of Quel'Danas
        },
        -- Harandar (Rootstalker Grimlynx, Vibrant Petalwing)
        { sourceType = "zone_drop", mapIDs = { 2413, 2576 }, raresOnly = true, hostileOnly = true,
          drops = _harandarRareMounts,  -- Harandar, The Den
        },
        -- Zul'Aman (Amani Sharptalon, Escaped Witherbark Pango)
        { sourceType = "zone_drop", mapIDs = { 2437, 2536 }, raresOnly = true, hostileOnly = true,
          drops = _zulAmanRareMounts,  -- Zul'Aman, Atal'Aman
        },
        -- Voidstorm (Augmented Stormray, Sanguine Harrower)
        { sourceType = "zone_drop", mapIDs = { 2405, 2541 }, raresOnly = true, hostileOnly = true,
          drops = _voidstormRareMounts,  -- Voidstorm, Arcantina
        },

        -- =====================================================================
        -- NPCs / Instance Bosses / World Rares
        -- =====================================================================

        -- ========================================
        -- CLASSIC
        -- ========================================
        { sourceType = "instance_boss", npcID = 10440,  -- Baron Rivendare (Stratholme)
          drops = { { type = "mount", itemID = 13335, name = "Deathcharger's Reins" } },
          statisticIds = { 1097 },
        },
        -- AQ40 Trash Mobs
        { sourceType = "npc", npcID = 15246,  -- Qiraji Mindslayer (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },
        { sourceType = "npc", npcID = 15317,  -- Qiraji Champion (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },
        { sourceType = "npc", npcID = 15247,  -- Vekniss Stinger (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },
        { sourceType = "npc", npcID = 15311,  -- Anubisath Sentinel (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },
        { sourceType = "npc", npcID = 15249,  -- Vekniss Wasp (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },
        { sourceType = "npc", npcID = 15310,  -- Vekniss Hive Crawler (AQ40)
          drops = {
              { type = "mount", itemID = 21218, name = "Yellow Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21219, name = "Blue Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21220, name = "Green Qiraji Resonating Crystal" },
              { type = "mount", itemID = 21321, name = "Red Qiraji Resonating Crystal" },
          },
        },

        -- ========================================
        -- THE BURNING CRUSADE
        -- ========================================
        { sourceType = "instance_boss", npcID = 16152,  -- Attumen the Huntsman (Karazhan)
          drops = { { type = "mount", itemID = 30480, name = "Fiery Warhorse's Reins" } },
        },
        { sourceType = "instance_boss", npcID = 19622,  -- Kael'thas Sunstrider (Tempest Keep: The Eye)
          drops = { { type = "mount", itemID = 32458, name = "Ashes of Al'ar" } },
          statisticIds = { 1088 },
        },
        { sourceType = "instance_boss", npcID = 24664,  -- Kael'thas Sunstrider (Magister's Terrace)
          drops = { { type = "mount", itemID = 35513, name = "Swift White Hawkstrider" } },
        },
        { sourceType = "instance_boss", npcID = 23035,  -- Anzu (Sethekk Halls Heroic)
          drops = { { type = "mount", itemID = 32768, name = "Reins of the Raven Lord" } },
        },

        -- ========================================
        -- WRATH OF THE LICH KING
        -- ========================================
        { sourceType = "instance_boss", npcID = 26693,  -- Skadi the Ruthless (Utgarde Pinnacle Heroic)
          drops = { { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" } },
        },
        { sourceType = "instance_boss", npcID = 174062,  -- Skadi the Ruthless (Utgarde Pinnacle - Timewalking)
          drops = { { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" } },
        },
        { sourceType = "instance_boss", npcID = 28859,  -- Malygos (Eye of Eternity)
          drops = {
              { type = "mount", itemID = 43953, name = "Reins of the Blue Drake" },
              { type = "mount", itemID = 43952, name = "Reins of the Azure Drake" },
          },
          statisticIds = { 1391, 1394 },
        },
        { sourceType = "instance_boss", npcID = 28860,  -- Sartharion (Obsidian Sanctum 3D)
          drops = {
              { type = "mount", itemID = 43986, name = "Reins of the Black Drake" },
              { type = "mount", itemID = 43954, name = "Reins of the Twilight Drake" },
          },
          statisticIds = { 1392, 1393 },
        },
        { sourceType = "instance_boss", npcID = 33288,  -- Yogg-Saron (Ulduar 0-Light 25-man)
          drops = { { type = "mount", itemID = 45693, name = "Mimiron's Head" } },
          statisticIds = { 2869, 2883 },
          dropDifficulty = "25-man",
        },
        { sourceType = "instance_boss", npcID = 10184,  -- Onyxia (Onyxia's Lair)
          drops = { { type = "mount", itemID = 49636, name = "Reins of the Onyxian Drake" } },
          statisticIds = { 1098 },
        },
        { sourceType = "instance_boss", npcID = 36597,  -- The Lich King (ICC 25H)
          drops = { { type = "mount", itemID = 50818, name = "Invincible's Reins" } },
          statisticIds = { 4688 },
          dropDifficulty = "25H",
        },
        -- Vault of Archavon bosses (faction-specific item IDs)
        { sourceType = "instance_boss", npcID = 31125,  -- Archavon the Stone Watcher
          drops = {
              { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" },  -- Alliance
              { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" },  -- Horde
          },
          statisticIds = { 1753, 1754 },
        },
        { sourceType = "instance_boss", npcID = 33993,  -- Emalon the Storm Watcher
          drops = {
              { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" },
              { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" },
          },
          statisticIds = { 3236, 2870 },
        },
        { sourceType = "instance_boss", npcID = 35013,  -- Koralon the Flame Watcher
          drops = {
              { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" },
              { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" },
          },
          statisticIds = { 4074, 4075 },
        },
        { sourceType = "instance_boss", npcID = 38433,  -- Toravon the Ice Watcher
          drops = {
              { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" },
              { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" },
          },
          statisticIds = { 4657, 4658 },
        },

        -- ========================================
        -- CATACLYSM
        -- ========================================
        { sourceType = "instance_boss", npcID = 43873,  -- Altairus (Vortex Pinnacle)
          drops = { { type = "mount", itemID = 63040, name = "Reins of the Drake of the North Wind" } },
        },
        { sourceType = "instance_boss", npcID = 43214,  -- Slabhide (The Stonecore) - ALL DIFFICULTIES
          drops = { { type = "mount", itemID = 63043, name = "Reins of the Vitreous Stone Drake" } },
        },
        { sourceType = "instance_boss", npcID = 46753,  -- Al'Akir (Throne of the Four Winds)
          drops = { { type = "mount", itemID = 63041, name = "Reins of the Drake of the South Wind" } },
          statisticIds = { 5576, 5577 },
        },
        { sourceType = "instance_boss", npcID = 52151,  -- Bloodlord Mandokir (Zul'Gurub)
          drops = { { type = "mount", itemID = 68823, name = "Armored Razzashi Raptor" } },
        },
        { sourceType = "instance_boss", npcID = 52059,  -- High Priestess Kilnara (Zul'Gurub)
          drops = { { type = "mount", itemID = 68824, name = "Swift Zulian Panther" } },
        },
        { sourceType = "instance_boss", npcID = 55294,  -- Ultraxion (Dragon Soul) - ALL DIFFICULTIES
          drops = { { type = "mount", itemID = 78919, name = "Experiment 12-B" } },
          statisticIds = { 6161, 6162 },
        },
        { sourceType = "instance_boss", npcID = 52530,  -- Alysrazor (Firelands)
          drops = { { type = "mount", itemID = 71665, name = "Flametalon of Alysrazor" } },
          statisticIds = { 5970, 5971 },
        },
        { sourceType = "instance_boss", npcID = 52409,  -- Ragnaros (Firelands) - ALL DIFFICULTIES
          drops = { { type = "mount", itemID = 69224, name = "Smoldering Egg of Millagazor" } },
          statisticIds = { 5976, 5977 },
        },
        { sourceType = "instance_boss", npcID = 56173,  -- Madness of Deathwing (Dragon Soul)
          drops = {
              { type = "mount", itemID = 77067, name = "Reins of the Blazing Drake" },
              { type = "mount", itemID = 77069, name = "Life-Binder's Handmaiden", dropDifficulty = "Heroic" },
          },
          statisticIds = { 6167, 6168 },
        },

        -- ========================================
        -- MISTS OF PANDARIA
        -- ========================================
        -- World Bosses
        { sourceType = "world_rare", npcID = 60491,  -- Sha of Anger (Kun-Lai Summit)
          drops = { { type = "mount", itemID = 87771, name = "Reins of the Heavenly Onyx Cloud Serpent" } },
          statisticIds = { 6989 },
        },
        { sourceType = "world_rare", npcID = 62346,  -- Galleon (Valley of the Four Winds)
          drops = { { type = "mount", itemID = 89783, name = "Son of Galleon's Saddle" } },
          statisticIds = { 6990 },
        },
        { sourceType = "world_rare", npcID = 69099,  -- Nalak (Isle of Thunder)
          drops = { { type = "mount", itemID = 95057, name = "Reins of the Thundering Cobalt Cloud Serpent" } },
          statisticIds = { 8146 },
        },
        { sourceType = "world_rare", npcID = 69161,  -- Oondasta (Isle of Giants)
          drops = { { type = "mount", itemID = 94228, name = "Reins of the Cobalt Primordial Direhorn" } },
          statisticIds = { 8147 },
        },
        { sourceType = "world_rare", npcID = 73167,  -- Huolon (Timeless Isle)
          drops = { { type = "mount", itemID = 104269, name = "Reins of the Thundering Onyx Cloud Serpent" } },
        },
        -- Zandalari Warbringers (3 colors from 3 NPC variants)
        { sourceType = "world_rare", npcID = 69841,  -- Zandalari Warbringer (Amber)
          drops = { { type = "mount", itemID = 94230, name = "Reins of the Amber Primordial Direhorn" } },
        },
        { sourceType = "world_rare", npcID = 69842,  -- Zandalari Warbringer (Jade)
          drops = { { type = "mount", itemID = 94231, name = "Reins of the Jade Primordial Direhorn" } },
        },
        { sourceType = "world_rare", npcID = 69769,  -- Zandalari Warbringer (Slate)
          drops = { { type = "mount", itemID = 94229, name = "Reins of the Slate Primordial Direhorn" } },
        },
        -- Raid Bosses
        { sourceType = "instance_boss", npcID = 60410,  -- Elegon (Mogu'shan Vaults)
          drops = { { type = "mount", itemID = 87777, name = "Reins of the Astral Cloud Serpent" } },
          statisticIds = { 6797, 6798, 7924, 7923 },
        },
        { sourceType = "instance_boss", npcID = 68476,  -- Horridon (Throne of Thunder)
          drops = { { type = "mount", itemID = 93666, name = "Spawn of Horridon" } },
          statisticIds = { 8151, 8149, 8152, 8150 },
        },
        { sourceType = "instance_boss", npcID = 69712,  -- Ji-Kun (Throne of Thunder)
          drops = { { type = "mount", itemID = 95059, name = "Clutch of Ji-Kun" } },
          statisticIds = { 8171, 8169, 8172, 8170 },
        },
        { sourceType = "instance_boss", npcID = 71865,  -- Garrosh Hellscream (Siege of Orgrimmar Mythic)
          drops = { { type = "mount", itemID = 104253, name = "Kor'kron Juggernaut" } },
          statisticIds = { 8638, 8637 },
          dropDifficulty = "Mythic",
        },

        -- =====================================================================
        -- Encounter ID → NPC(s) mappings (DungeonEncounter.ID)
        -- Every instance_boss/legacyNpc that fires ENCOUNTER_END needs an entry here.
        -- =====================================================================
        -- The Burning Crusade
        { sourceType = "encounter", encounterID = 652,  npcIDs = { 16152 } },              -- Attumen the Huntsman (Karazhan)
        { sourceType = "encounter", encounterID = 733,  npcIDs = { 19622 } },              -- Kael'thas (The Eye)
        { sourceType = "encounter", encounterID = 1894, npcIDs = { 24664 } },              -- Kael'thas (Magisters' Terrace)
        { sourceType = "encounter", encounterID = 1904, npcIDs = { 23035 } },              -- Anzu (Sethekk Halls)
        -- Wrath of the Lich King
        { sourceType = "encounter", encounterID = 2029, npcIDs = { 26693, 174062 } },      -- Skadi the Ruthless (Utgarde Pinnacle + TW)
        { sourceType = "encounter", encounterID = 1126, npcIDs = { 31125 } },              -- Archavon
        { sourceType = "encounter", encounterID = 1127, npcIDs = { 33993 } },              -- Emalon
        { sourceType = "encounter", encounterID = 1128, npcIDs = { 35013 } },              -- Koralon
        { sourceType = "encounter", encounterID = 1129, npcIDs = { 38433 } },              -- Toravon
        { sourceType = "encounter", encounterID = 1094, npcIDs = { 28859 } },              -- Malygos
        { sourceType = "encounter", encounterID = 1090, npcIDs = { 28860 } },              -- Sartharion
        { sourceType = "encounter", encounterID = 1084, npcIDs = { 10184 } },              -- Onyxia
        { sourceType = "encounter", encounterID = 1143, npcIDs = { 33288 } },              -- Yogg-Saron
        { sourceType = "encounter", encounterID = 1106, npcIDs = { 36597 } },              -- The Lich King
        -- Cataclysm
        { sourceType = "encounter", encounterID = 1041, npcIDs = { 43873 } },              -- Altairus (Vortex Pinnacle)
        { sourceType = "encounter", encounterID = 1059, npcIDs = { 43214 } },              -- Slabhide (The Stonecore)
        { sourceType = "encounter", encounterID = 1034, npcIDs = { 46753 } },              -- Al'Akir (Throne of the Four Winds)
        { sourceType = "encounter", encounterID = 1179, npcIDs = { 52151 } },              -- Bloodlord Mandokir (Zul'Gurub)
        { sourceType = "encounter", encounterID = 1180, npcIDs = { 52059 } },              -- High Priestess Kilnara (Zul'Gurub)
        { sourceType = "encounter", encounterID = 1206, npcIDs = { 52530 } },              -- Alysrazor (Firelands)
        { sourceType = "encounter", encounterID = 1203, npcIDs = { 52409 } },              -- Ragnaros (Firelands)
        { sourceType = "encounter", encounterID = 1297, npcIDs = { 55294 } },              -- Ultraxion (Dragon Soul)
        { sourceType = "encounter", encounterID = 1299, npcIDs = { 56173 } },              -- Madness of Deathwing (Dragon Soul)
        -- Mists of Pandaria
        { sourceType = "encounter", encounterID = 1500, npcIDs = { 60410 } },              -- Elegon
        { sourceType = "encounter", encounterID = 1575, npcIDs = { 68476 } },              -- Horridon
        { sourceType = "encounter", encounterID = 1573, npcIDs = { 69712 } },              -- Ji-Kun
        { sourceType = "encounter", encounterID = 1623, npcIDs = { 71865 } },              -- Garrosh Hellscream
        { sourceType = "encounter", encounterID = 1704, npcIDs = { 77325 } },              -- Blackhand
        { sourceType = "encounter", encounterID = 1799, npcIDs = { 91331 } },              -- Archimonde
        -- Legion
        { sourceType = "encounter", encounterID = 1960, npcIDs = { 114262 } },             -- Attumen (Return to Karazhan)
        { sourceType = "encounter", encounterID = 2031, npcIDs = { 114895 } },             -- Nightbane (Return to Karazhan)
        { sourceType = "encounter", encounterID = 1866, npcIDs = { 105503, 104154, 111022 } }, -- Gul'dan
        { sourceType = "encounter", encounterID = 2037, npcIDs = { 115767 } },             -- Mistress Sassz'ine
        { sourceType = "encounter", encounterID = 2074, npcIDs = { 126915, 126916 } },     -- Felhounds of Sargeras
        { sourceType = "encounter", encounterID = 2092, npcIDs = { 130352 } },             -- Argus the Unmaker
        -- Battle for Azeroth
        { sourceType = "encounter", encounterID = 2291, npcIDs = { 155157, 150190 } },     -- HK-8 Aerial Oppression Unit
        { sourceType = "encounter", encounterID = 2673, npcIDs = { 198933 } },             -- Chrono-Lord Deios (Dawn of the Infinite)
        { sourceType = "encounter", encounterID = 2096, npcIDs = { 126983 } },             -- Harlan Sweete
        { sourceType = "encounter", encounterID = 2123, npcIDs = { 133007 } },             -- Unbound Abomination
        { sourceType = "encounter", encounterID = 2143, npcIDs = { 136160 } },             -- King Dazar
        { sourceType = "encounter", encounterID = 2276, npcIDs = { 144796 } },             -- Mekkatorque
        { sourceType = "encounter", encounterID = 2281, npcIDs = { 165396 } },             -- Lady Jaina Proudmoore
        { sourceType = "encounter", encounterID = 2344, npcIDs = { 158041 } },             -- N'Zoth the Corruptor
        { sourceType = "encounter", encounterID = 2390, npcIDs = { 162693 } },             -- Nalthor the Rimebinder
        { sourceType = "encounter", encounterID = 2442, npcIDs = { 180863 } },             -- So'leah
        { sourceType = "encounter", encounterID = 2429, npcIDs = { 178738 } },             -- The Nine
        { sourceType = "encounter", encounterID = 2435, npcIDs = { 175732 } },             -- Sylvanas Windrunner
        { sourceType = "encounter", encounterID = 2537, npcIDs = { 180990 } },             -- The Jailer
        { sourceType = "encounter", encounterID = 2607, npcIDs = { 189492 } },             -- Raszageth
        { sourceType = "encounter", encounterID = 2685, npcIDs = { 201791 } },             -- Scalecommander Sarkareth
        { sourceType = "encounter", encounterID = 2677, npcIDs = { 204931 } },             -- Fyrakk
        { sourceType = "encounter", encounterID = 2788, npcIDs = { 210798 } },             -- The Darkness (Darkflame Cleft)
        { sourceType = "encounter", encounterID = 2883, npcIDs = { 213119 } },             -- Void Speaker Eirich
        { sourceType = "encounter", encounterID = 2922, npcIDs = { 218370 } },             -- Queen Ansurek
        { sourceType = "encounter", encounterID = 3016, npcIDs = { 241526 } },             -- Chrome King Gallywix
        { sourceType = "encounter", encounterID = 3059, npcIDs = { 231636 } },             -- Restless Heart (Windrunner Spire)
        { sourceType = "encounter", encounterID = 3074, npcIDs = { 231865 } },             -- Degentrius (Magisters' Terrace)
        { sourceType = "encounter", encounterID = 3183, npcIDs = { 214650 } },             -- Midnight Falls (March on Quel'Danas)

        -- =====================================================================
        -- Encounter Name → NPC(s) mappings (GUID fallback for Midnight)
        -- =====================================================================
        { sourceType = "encounter_name", encounterName = "Restless Heart", npcIDs = { 231636 } },  -- Windrunner Spire
        { sourceType = "encounter_name", encounterName = "Degentrius",     npcIDs = { 231865 } },  -- Magisters' Terrace
        { sourceType = "encounter_name", encounterName = "Midnight Falls", npcIDs = { 214650 } },  -- March on Quel'Danas

        -- =====================================================================
        -- Lockout Quests (older content: MoP through TWW 11.2)
        -- Midnight 12.0 lockout quests are listed earlier in this sources[] block.
        -- =====================================================================
        -- MoP: World Bosses (weekly lockout via bonus roll quest)
        { sourceType = "lockout_quest", npcID = 60491, questID = 32099 },  -- Sha of Anger (Kun-Lai Summit)
        { sourceType = "lockout_quest", npcID = 62346, questID = 32098 },  -- Galleon (Valley of the Four Winds)
        { sourceType = "lockout_quest", npcID = 69099, questID = 32518 },  -- Nalak (Isle of Thunder)
        { sourceType = "lockout_quest", npcID = 69161, questID = 32519 },  -- Oondasta (Isle of Giants)
        -- MoP: Timeless Isle (daily lockout)
        { sourceType = "lockout_quest", npcID = 73167, questID = 33311 },  -- Huolon

        -- WoD: World Boss (weekly lockout)
        { sourceType = "lockout_quest", npcID = 83746, questID = 37464 },  -- Rukhmar (Spires of Arak)
        { sourceType = "lockout_quest", npcID = 87493, questID = 37464 },  -- Rukhmar (alt NPC ID)
        -- WoD: Tanaan Jungle Champions (daily lockout)
        { sourceType = "lockout_quest", npcID = 95044, questID = 39288 },  -- Terrorfist
        { sourceType = "lockout_quest", npcID = 95053, questID = 39287 },  -- Deathtalon
        { sourceType = "lockout_quest", npcID = 95054, questID = 39290 },  -- Vengeance
        { sourceType = "lockout_quest", npcID = 95056, questID = 39289 },  -- Doomroller

        -- Legion: World Bosses (biweekly lockout)
        { sourceType = "lockout_quest", npcID = 111573, questID = 43798 },  -- Kosumoth the Hungering — TODO: verify questID in-game
        -- Legion: Argus rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 122958, questID = 49183 },  -- Blistermaw (Antoran Wastes)
        { sourceType = "lockout_quest", npcID = 126040, questID = 48809 },  -- Puscilla (Antoran Wastes)
        { sourceType = "lockout_quest", npcID = 126199, questID = 48810 },  -- Vrax'thul (Antoran Wastes)
        { sourceType = "lockout_quest", npcID = 126852, questID = 48695 },  -- Wrangler Kravos (Mac'Aree)
        { sourceType = "lockout_quest", npcID = 126867, questID = 48705 },  -- Venomtail Skyfin (Mac'Aree)
        { sourceType = "lockout_quest", npcID = 126912, questID = 48721 },  -- Skreeg the Devourer (Mac'Aree)
        { sourceType = "lockout_quest", npcID = 127288, questID = 48821 },  -- Houndmaster Kerrax (Antoran Wastes)

        -- BfA: Warfront Arathi Highlands (cycle-based lockout)
        { sourceType = "lockout_quest", npcID = 142692, questIDs = { 53091, 53517 } },  -- Nimar the Slayer
        { sourceType = "lockout_quest", npcID = 142423, questIDs = { 53014, 53518 } },  -- Overseer Krix
        { sourceType = "lockout_quest", npcID = 142437, questIDs = { 53022, 53526 } },  -- Skullripper
        { sourceType = "lockout_quest", npcID = 142709, questIDs = { 53083, 53504 } },  -- Beastrider Kama
        { sourceType = "lockout_quest", npcID = 142741, questID = 53085 },              -- Doomrider Helgrim (Alliance)
        { sourceType = "lockout_quest", npcID = 142739, questID = 53088 },              -- Knight-Captain Aldrin (Horde)
        -- BfA: Warfront Darkshore (cycle-based lockout)
        { sourceType = "lockout_quest", npcID = 148787, questIDs = { 54695, 54696 } },  -- Alash'anir
        { sourceType = "lockout_quest", npcID = 149652, questID = 54883 },              -- Agathe Wyrmwood (Alliance)
        { sourceType = "lockout_quest", npcID = 149660, questID = 54890 },              -- Blackpaw (Horde)
        { sourceType = "lockout_quest", npcID = 149655, questID = 54886 },              -- Croz Bloodrage (Alliance)
        { sourceType = "lockout_quest", npcID = 149663, questID = 54892 },              -- Shadowclaw (Horde)
        { sourceType = "lockout_quest", npcID = 148037, questID = 54431 },              -- Athil Dewfire (Horde)
        { sourceType = "lockout_quest", npcID = 147701, questID = 54277 },              -- Moxo the Beheader (Alliance)
        -- BfA 8.2: Mechagon / Nazjatar (daily lockout)
        { sourceType = "lockout_quest", npcID = 152182, questID = 55811 },  -- Rustfeather
        { sourceType = "lockout_quest", npcID = 154342, questID = 55512 },  -- Arachnoid Harvester (alt timeline)
        { sourceType = "lockout_quest", npcID = 151934, questID = 55512 },  -- Arachnoid Harvester (standard)
        { sourceType = "lockout_quest", npcID = 152290, questID = 56298 },  -- Soundless
        -- BfA 8.3: Vale of Eternal Blossoms assault rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 157466, questID = 57363 },  -- Anh-De the Loyal
        { sourceType = "lockout_quest", npcID = 157153, questID = 57344 },  -- Ha-Li
        { sourceType = "lockout_quest", npcID = 157160, questID = 57345 },  -- Houndlord Ren
        -- BfA 8.3: Uldum assault rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 157134, questID = 57259 },  -- Ishak of the Four Winds
        { sourceType = "lockout_quest", npcID = 162147, questID = 58696 },  -- Corpse Eater
        { sourceType = "lockout_quest", npcID = 157146, questID = 57273 },  -- Rotfeaster
        -- BfA: World Boss (weekly lockout via world quest)
        { sourceType = "lockout_quest", npcID = 138794, questID = 53000 },  -- Dunegorger Kraulok

        -- Shadowlands: Ardenweald rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 164107, questID = 59145 },  -- Gormtamer Tizo
        { sourceType = "lockout_quest", npcID = 164112, questID = 59157 },  -- Humon'gozz
        { sourceType = "lockout_quest", npcID = 168647, questID = 61632 },  -- Valfir the Unrelenting
        -- Shadowlands: Bastion (daily lockout)
        { sourceType = "lockout_quest", npcID = 170548, questID = 60862 },  -- Sundancer
        -- Shadowlands: Revendreth rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 166521, questID = 59869 },  -- Famu the Infinite
        { sourceType = "lockout_quest", npcID = 165290, questID = 59612 },  -- Harika the Horrid
        { sourceType = "lockout_quest", npcID = 166679, questID = 59900 },  -- Hopecrusher
        { sourceType = "lockout_quest", npcID = 160821, questID = 58259 },  -- Worldedge Gorger
        -- Shadowlands: Maldraxxus rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 162741, questID = 58872 },  -- Gieger
        { sourceType = "lockout_quest", npcID = 162586, questID = 58783 },  -- Tahonta
        { sourceType = "lockout_quest", npcID = 157309, questID = 61720 },  -- Violet Mistake
        { sourceType = "lockout_quest", npcID = 162690, questID = 58851 },  -- Nerissa Heartless
        { sourceType = "lockout_quest", npcID = 162819, questID = 58889 },  -- Warbringer Mal'Korak
        { sourceType = "lockout_quest", npcID = 162818, questID = 58889 },  -- Warbringer Mal'Korak (alt)
        { sourceType = "lockout_quest", npcID = 168147, questID = 58784 },  -- Sabriel the Bonecleaver
        { sourceType = "lockout_quest", npcID = 168148, questID = 58784 },  -- Sabriel the Bonecleaver (alt)
        -- Theater of Pain combatants (shared daily lockout)
        { sourceType = "lockout_quest", npcID = 162873, questID = 62786 },
        { sourceType = "lockout_quest", npcID = 162880, questID = 62786 },
        { sourceType = "lockout_quest", npcID = 162875, questID = 62786 },
        { sourceType = "lockout_quest", npcID = 162853, questID = 62786 },
        { sourceType = "lockout_quest", npcID = 162874, questID = 62786 },
        { sourceType = "lockout_quest", npcID = 162872, questID = 62786 },
        -- Shadowlands: Maw rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 174861, questID = 63433 },  -- Gorged Shadehound
        { sourceType = "lockout_quest", npcID = 179460, questID = 64164 },  -- Fallen Charger
        -- Shadowlands: Korthia rares (daily lockout)
        { sourceType = "lockout_quest", npcID = 179472, questID = 64246 },  -- Konthrogz the Obliterator
        { sourceType = "lockout_quest", npcID = 180160, questID = 64455 },  -- Reliwik the Defiant
        { sourceType = "lockout_quest", npcID = 179684, questID = 64233 },  -- Malbog
        { sourceType = "lockout_quest", npcID = 179985, questID = 64313 },  -- Stygian Stonecrusher
        { sourceType = "lockout_quest", npcID = 180032, questID = 64338 },  -- Wild Worldcracker
        { sourceType = "lockout_quest", npcID = 180042, questID = 64349 },  -- Fleshwing
        -- Shadowlands: Zereth Mortis (daily lockout)
        { sourceType = "lockout_quest", npcID = 180978, questID = 65548 },  -- Hirukon

        -- Dragonflight: Zaralek Cavern (daily lockout)
        { sourceType = "lockout_quest", npcID = 203625, questID = 75333 },  -- Karokta
        -- Dragonflight: Forbidden Reach rares (daily lockout, shared Ancient Salamanther mount)
        { sourceType = "lockout_quest", npcID = 200537, questID = 73095 },  -- Gahz'raxes
        { sourceType = "lockout_quest", npcID = 200579, questID = 73100 },  -- Ishyra
        { sourceType = "lockout_quest", npcID = 200584, questID = 73111 },  -- Vraken the Hunter
        { sourceType = "lockout_quest", npcID = 200600, questID = 73117 },  -- Reisa the Drowned
        { sourceType = "lockout_quest", npcID = 200610, questID = 73118 },  -- Duzalgor
        { sourceType = "lockout_quest", npcID = 200681, questID = 74341 },  -- Bonesifter Marwak
        { sourceType = "lockout_quest", npcID = 200717, questID = 74342 },  -- Galakhad
        { sourceType = "lockout_quest", npcID = 200721, questID = 73154 },  -- Grugoth the Hullcrusher
        { sourceType = "lockout_quest", npcID = 200885, questID = 73222 },  -- Lady Shaz'ra
        { sourceType = "lockout_quest", npcID = 200904, questID = 73229 },  -- Veltrax
        { sourceType = "lockout_quest", npcID = 200911, questID = 73225 },  -- Volcanakk
        { sourceType = "lockout_quest", npcID = 200956, questID = 74349 },  -- Ookbeard
        { sourceType = "lockout_quest", npcID = 200960, questID = 73367 },  -- Warden Entrix
        { sourceType = "lockout_quest", npcID = 200978, questID = 73385 },  -- Pyrachniss
        { sourceType = "lockout_quest", npcID = 201013, questID = 73409 },  -- Wyrmslayer Angvardi
        { sourceType = "lockout_quest", npcID = 201181, questID = 74283 },  -- Mad-Eye Carrey

        -- TWW: Hallowfall / Ringing Deeps (daily lockout)
        { sourceType = "lockout_quest", npcID = 207802, questID = 81763 },  -- Beledar's Spawn
        { sourceType = "lockout_quest", npcID = 220285, questID = 81633 },  -- Regurgitated Mole Reins rare
        -- TWW: Azj-Kahet (daily lockout)
        { sourceType = "lockout_quest", npcID = 216046, questID = 82289 },  -- Tka'ktath
        -- TWW 11.1: Undermine — Darkfuse Precipitant (weekly loot lockout)
        { sourceType = "lockout_quest", npcID = 231310, questID = 85010 },  -- Darkfuse Precipitant
        -- TWW 11.1: Undermine — weekly elite rares
        { sourceType = "lockout_quest", npcID = 230746, questID = 84877 },  -- Ephemeral Agent Lathyd
        { sourceType = "lockout_quest", npcID = 230793, questID = 84884 },  -- The Junk-Wall
        { sourceType = "lockout_quest", npcID = 230800, questID = 84895 },  -- Slugger the Smart
        { sourceType = "lockout_quest", npcID = 230828, questID = 84907 },  -- Chief Foreman Gutso
        { sourceType = "lockout_quest", npcID = 230840, questID = 84911 },  -- Flyboy Snooty
        -- TWW 11.1: Undermine — daily rares
        { sourceType = "lockout_quest", npcID = 230931, questID = 84917 },  -- Scrapbeak
        { sourceType = "lockout_quest", npcID = 230934, questID = 84918 },  -- Ratspit
        { sourceType = "lockout_quest", npcID = 230940, questID = 84919 },  -- Tally Doublespeak
        { sourceType = "lockout_quest", npcID = 230946, questID = 84920 },  -- V.V. Goosworth
        { sourceType = "lockout_quest", npcID = 230951, questID = 84921 },  -- Thwack
        { sourceType = "lockout_quest", npcID = 230979, questID = 84922 },  -- S.A.L.
        { sourceType = "lockout_quest", npcID = 230995, questID = 84926 },  -- Nitro
        { sourceType = "lockout_quest", npcID = 231012, questID = 84927 },  -- Candy Stickemup
        { sourceType = "lockout_quest", npcID = 231017, questID = 84928 },  -- Grimewick
        { sourceType = "lockout_quest", npcID = 231288, questID = 85004 },  -- Swigs Farsight
        -- TWW 11.2: Karesh (daily lockout)
        { sourceType = "lockout_quest", npcID = 232195, questID = 90593 },  -- Pearlescent Krolusk
        { sourceType = "lockout_quest", npcID = 234845, questID = 91293 },  -- Sthaarbs
    },

    -- DEPRECATED: do not add here. Add only to sources[]. This table will be removed once fully migrated.
    legacyNpcs = {
        -- Classic/TBC/WotLK migrated to sources[].

        -- ========================================
        -- CATACLYSM
        -- ========================================

        -- Cataclysm + MoP migrated to sources[].

        -- ========================================
        -- WARLORDS OF DRAENOR
        -- ========================================

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

        -- World Bosses
        [111573] = { -- Kosumoth the Hungering (Eye of Azshara / Broken Isles)
            { type = "mount", itemID = 138201, name = "Fathom Dweller" },
            { type = "pet",   itemID = 140261, name = "Hungering Claw" },
            -- NOTE: Biweekly world boss; region alternates between mount and pet reward weekly.
            -- Requires attunement (activate 10 Hungering Orbs hidden across Broken Isles).
            -- Lockout quest: 43798 (DANGER: Kosumoth the Hungering).
            -- TODO: Verify NPC ID, item IDs, and questID in-game.
        },

        -- Toys
        [100230] = { -- Nazak the Fiend (Suramar)
            { type = "toy", itemID = 129149, name = "Skin of the Soulflayer" },
        },

        -- ========================================
        -- BATTLE FOR AZEROTH
        -- ========================================

        -- Darkshore / BfA World Rares
        [160708] = { -- Mail Muncher (Horrific Visions)
            { type = "mount", itemID = 174653, name = "Mail Muncher" },
        },

        -- BfA Zone Drops: Captured Dune Scavenger (Vol'dun - Sethrak/Faithless mobs)
        -- Matches community BfA mount DB (21 NPC IDs)
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

        -- BfA Zone Drops: Terrified Pack Mule (Drustvar - Hexthralled / Corlain line)
        -- Community baseline + cross-checked "dropped by" lists (duplicate display names = extra creature ids).
        [129995] = _terrifiedPackMule,  -- Emily Mayville (rare)
        [130016] = _terrifiedPackMule,  -- Emily Mayville (alt spawn / phase)
        [131519] = _terrifiedPackMule,  -- Hexthralled Falconer
        [131529] = _terrifiedPackMule,  -- Hexthralled Villager (verify in-game if renamed)
        [131530] = _terrifiedPackMule,  -- Hexthralled Ravager
        [131534] = _terrifiedPackMule,  -- Hexthralled Guardsman (cursed horse, Corlain)
        [131859] = _terrifiedPackMule,  -- Hexthralled Crossbowman (alt template)
        [133736] = _terrifiedPackMule,  -- Hexthralled Falconer (alt template)
        [133889] = _terrifiedPackMule,  -- Hexthralled Halberdier
        [133892] = _terrifiedPackMule,  -- Hexthralled Crossbowman
        [137134] = _terrifiedPackMule,  -- Hexthralled Soldier
        [138245] = _terrifiedPackMule,  -- Hexthralled Crossbowman (Midnight-scale template)
        [141642] = _terrifiedPackMule,  -- Hexthralled Halberdier (Goodspeed's Guard, etc.)

        -- BfA Zone Drops: Reins of a Tamed Bloodfeaster (Nazmir - Blood Troll mobs)
        -- Baseline: community BfA mount dataset npcs (16). Extended: cross-checked "dropped by" lists, Amaki/Zalamar
        -- lines, Loa-Gutter summoners (Midnight), ritualists, extra warrior template — verify on the mount item.
        [120606] = _bloodfeaster,  -- Blood Troll Hexxer / Mystic
        [120607] = _bloodfeaster,  -- Blood Troll Warrior (template)
        [120613] = _bloodfeaster,  -- Blood Troll Warmother
        [122204] = _bloodfeaster,  -- Blood Witch Najima
        [122239] = _bloodfeaster,  -- Blood Priest
        [123071] = _bloodfeaster,  -- Blood Hunter
        [123328] = _bloodfeaster,  -- Warmother Boatema
        [123437] = _bloodfeaster,  -- Bloodhunter Cursecarver
        [123439] = _bloodfeaster,  -- Bloodhunter War-Witch
        [123441] = _bloodfeaster,  -- Bloodhunter Warmother
        [124547] = _bloodfeaster,  -- Blood Troll Marauder
        [124688] = _bloodfeaster,  -- Natha'vor Cannibal
        [126089] = _bloodfeaster,  -- Bloodhunter Warrior
        [126187] = _bloodfeaster,  -- Corpse Bringer Yal'kar (rare)
        [126888] = _bloodfeaster,  -- Blood Witch Vashera
        [126890] = _bloodfeaster,  -- Blood Priestess Zu'Anji
        [126891] = _bloodfeaster,  -- Blood Witch Yialu
        [127040] = _bloodfeaster,  -- Zalamar Zealot (Zalamar line)
        [127145] = _bloodfeaster,  -- Zalamar Bloodsinger
        [127224] = _bloodfeaster,  -- Blood Troll Shaman / Empowered Worshipper (display)
        [127770] = _bloodfeaster,  -- Blood Troll Warrior (alt template, Nazmir)
        [127919] = _bloodfeaster,  -- Loa-Gutter Skullcrusher / Blood Troll Reaver
        [127928] = _bloodfeaster,  -- Loa-Gutter Drudge
        [128371] = _bloodfeaster,  -- Loa-Gutter Impaler
        [128734] = _bloodfeaster,  -- Amaki Guard (also listed as Blood Troll Rampager in some builds)
        [128770] = _bloodfeaster,  -- Warmother Nagla
        [128773] = _bloodfeaster,  -- Amaki Bloodsinger
        [129723] = _bloodfeaster,  -- Blood Troll (generic Nazmir)
        [131155] = _bloodfeaster,  -- Nazwathan Guardian
        [131156] = _bloodfeaster,  -- Nazwathan Hulk
        [131157] = _bloodfeaster,  -- Nazwathan Blood Bender
        [131658] = _bloodfeaster,  -- Amaki Warrider
        [133063] = _bloodfeaster,  -- Nazmani Blood Witch
        [133077] = _bloodfeaster,  -- Nazmani War Slave
        [133181] = _bloodfeaster,  -- Nazmani Ritualist
        [133279] = _bloodfeaster,  -- Nazmani Drudge
        [133445] = _bloodfeaster,  -- Nazmani Raider (item 163575 dropped-by cross-check)
        [136293] = _bloodfeaster,  -- Blood Troll Savage
        [136639] = _bloodfeaster,  -- Blood Troll Berserker
        [138816] = _bloodfeaster,  -- Loa-Gutter Summoner (Midnight+ Nazmir)

        -- BfA Zone Drops: Goldenmane's Reins (Stormsong Valley - Tidesage/Irontide mobs)
        -- Source: community datasets cross-checked (25 NPC IDs)
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
        -- Jaina: Glacial Tidestorm is Mythic-only (never LFR). G.M.O.D. was moved to Jaina for LFR only (Feb 2019 hotfix).
        [165396] = { -- Lady Jaina Proudmoore (Battle of Dazar'alor)
            { type = "mount", itemID = 166705, name = "Glacial Tidestorm",
              dropDifficulty = "Mythic",
              statisticIds = { 13382 },  -- Jaina kills (Mythic BoD)
            },
            -- LFR G.M.O.D.: personal loot on Jaina (boss loot window / post-kill roll), not a separate bonus chest.
            { type = "mount", itemID = 166518, name = "G.M.O.D.",
              dropDifficulty = "LFR",
              statisticIds = { 13379 },  -- Lady Jaina kills (LFR BoD); 13379 is NOT Mekkatorque LFR (that's 13371)
            },
        },
        -- G.M.O.D. on Normal/Heroic/Mythic drops from Mekkatorque; LFR source is Jaina row above.
        [144796] = { -- Mekkatorque (Battle of Dazar'alor)
            { type = "mount", itemID = 166518, name = "G.M.O.D.",
              dropDifficulty = "Normal", -- N/H/M raid (excludes LFR — see DoesDifficultyMatch "Normal")
            },
            statisticIds = { 13372, 13373, 13374 },  -- Mekkatorque N/H/M; omit 13371/13379 (LFR is Jaina for G.M.O.D.)
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
        [201791] = { -- Scalecommander Sarkareth (Aberrus, the Shadowed Crucible Mythic)
            { type = "mount", itemID = 205876, name = "Highland Drake: Embodiment of the Hellforged" },
            dropDifficulty = "Mythic",
            -- NOTE: Mythic-only drakewatcher manuscript; encounterID 2685
            -- TODO: Add statisticIds after in-game verification
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
        -- No statisticIds: WoW stat 20500 / merged seed often reads 0 or mismatches journal keys, which
        -- made ProcessMissedDrops skip manual increments entirely — UI showed 0 tries. Counts come from
        -- per-kill loot-miss increments (tryCountReflectsTo → mount 2119), same as farming the item.
        [213119] = { -- Void Speaker Eirich (The Stonevault Mythic/M+) [Verified]
            { type = "item", itemID = 226683, name = "Malfunctioning Mechsuit", repeatable = false,
              questStarters = {
                  { type = "mount", itemID = 221765, name = "Stonevault Mechsuit", mountID = 2119 },
              },
              tryCountReflectsTo = { type = "mount", itemID = 221765, name = "Stonevault Mechsuit", mountID = 2119 },
            },
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
        -- Midnight zone rare NPC IDs verified against in-game / wago DB2 at data entry
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

        -- Midnight 12.0 Season 1 — complete list of boss encounters that drop a mount.
        --
        -- Verified against Wowhead/Icy-Veins/community guides as of 2026-04 (Midnight S1 active):
        --   • 2 Mythic dungeons (M/M+): Windrunner Spire, Magisters' Terrace
        --   • 1 Mythic raid: March on Quel'Danas → Midnight Falls (final boss only)
        --
        -- Other Midnight S1 content WITHOUT direct mount drops (no try-counter entry needed):
        --   • Raids: The Dreamrift (Chimaerus), The Voidspire (6 bosses)
        --   • Dungeons in M+ rotation: Maisara Caverns, Nexus-Point Xenas (new) +
        --     Algeth'ar Academy, Seat of the Triumvirate, Skyreach, Pit of Saron (legacy in rotation)
        --   • Achievement-reward mounts (Tenebrous Harrower / Calamitous Carrion /
        --     Convalescent Carrion) are earned once via meta-achievements, not boss drops —
        --     they belong to the achievement tracking path, NOT this NPC drop table.
        --
        -- difficultyIDs: 23 = Mythic dungeon, 8 = Mythic Keystone (M+), 16 = Mythic raid (all map to "Mythic")
        -- Spectral / Lucent Hawkstrider: BoP, account-wide mount (learn once). Same cadence as other M dungeon mounts.
        -- Not BoE farm copies — try count must not "reset on obtain" (repeatable = false).
        [231636] = { -- Restless Heart (Windrunner Spire) â€” Spectral Hawkstrider â€” encounterID 3059
            { type = "mount", itemID = 262914, name = "Spectral Hawkstrider", repeatable = false },
            dropDifficulty = "Mythic",
            difficultyIDs = { 23, 8 },  -- Mythic dungeon + Mythic Keystone (M+); same encounter, no separate M+ entry
        },
        [231865] = { -- Degentrius (Magisters' Terrace) â€” Lucent Hawkstrider â€” encounterID 3074 (npcID 231865)
            -- mountID: journal id (avoids GetMountFromItem when secret in instances); spell fallback still applies
            { type = "mount", itemID = 260231, name = "Lucent Hawkstrider", mountID = 2817, repeatable = false },
            dropDifficulty = "Mythic",
            difficultyIDs = { 23, 8 },  -- Mythic dungeon + Mythic Keystone (M+)
        },
        [214650] = { -- Midnight Falls encounter (March on Quel'Danas raid, final boss) — encounterID 3183
            -- Seat of the Triumvirate (Legion / M+ rotation) reuses npcID 214650 and boss name L'ura.
            -- Belo'ren drops only from March on Quel'Danas Mythic; exclude Legion dungeon instance MapID.
            { type = "mount", itemID = 246590, name = "Ashes of Belo'ren", excludeInstanceIDs = { 1753 } },
            dropDifficulty = "Mythic",
            difficultyIDs = { 16 },  -- Mythic raid only (excludes M+ kills sharing this npcID)
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

    legacyObjects = {},  -- migrated to sources[]

    legacyFishing = {},  -- migrated to sources[]

    legacyRares = {},  -- migrated to sources[]

    legacyContainers = {},  -- migrated to sources[]

    legacyZones = {},  -- migrated to sources[]

    legacyEncounters = {},       -- migrated to sources[]
    legacyEncounterNames = {},   -- migrated to sources[]
    legacyLockoutQuests = {},    -- migrated to sources[]

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
        ["Kosumoth the Hungering"] = { 111573 },
        ["Gul'dan"] = { 105503, 104154, 111022 },
        ["The Demon Within"] = { 111022 },
        ["Mistress Sassz'ine"] = { 115767 },
        ["Felhounds of Sargeras"] = { 126915, 126916 },
        ["Argus the Unmaker"] = { 130352 },
        -- BfA
        ["Nazmani Raider"] = { 133445 }, -- Tamed Bloodfeaster; GUID→npcs also (secret GUID fallback)
        ["Mail Muncher"] = { 160708 },
        ["Harlan Sweete"] = { 126983 },
        ["Unbound Abomination"] = { 133007 },
        ["King Dazar"] = { 136160 },
        ["HK-8 Aerial Oppression Unit"] = { 155157, 150190 },
        ["Arachnoid Harvester"] = { 154342, 151934 },
        ["Lady Jaina Proudmoore"] = { 165396 },
        -- ENCOUNTER_END name fallback when encounterID is secret (non–enUS clients)
        ["Leydi Jaina Proudmoore"] = { 165396 },
        ["Lady Jaina Prachtmeer"] = { 165396 },
        ["Dame Jaina Portvaillant"] = { 165396 },
        ["Lady Jaina Valororgullo"] = { 165396 },
        ["Lady Jaina Orgulhomar"] = { 165396 },
        ["Lady Jaina Mareorgoglio"] = { 165396 },
        ["Леди Джайна Праудмур"] = { 165396 },
        ["吉安娜·普罗德摩尔女士"] = { 165396 },
        ["珍娜·普羅德摩爾女士"] = { 165396 },
        ["여군주 제이나 프라우드무어"] = { 165396 },
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
        ["Scalecommander Sarkareth"] = { 201791 },
        -- TWW
        -- Wick's Lead drops from journal boss "The Darkness" (npc 210798); 210797 is a separate unit template.
        ["Wick"] = { 210798 },
        ["The Darkness"] = { 210798 },
        ["Void Speaker Eirich"] = { 213119 },
        ["Queen Ansurek"] = { 218370 },
        ["Chrome King Gallywix"] = { 241526 },
        -- March on Quel'Danas raid — Midnight Falls (final encounter, Mythic drops mount).
        -- Difficulty gating in CollectibleSourceDB[214650].difficultyIDs = { 16 } restricts the
        -- Belo'ren mount to Mythic raid only; M+ kills sharing this npcID are filtered out.
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
                            if source.hostileOnly then zoneEntry.hostileOnly = true end
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
-- Merge remaining legacyNpcs into runtime db.npcs.
-- Will be removed once legacyNpcs is fully migrated to sources[].
local function MergeLegacyNpcs(db)
    if not db or type(db.legacyNpcs) ~= "table" then return end
    for npcID, data in pairs(db.legacyNpcs) do
        if type(data) == "table" then
            local target = db.npcs[npcID] or {}
            MergeDropArray(target, data, data.statisticIds, data.dropDifficulty)
            db.npcs[npcID] = target
        end
    end
end
MergeLegacyNpcs(ns.CollectibleSourceDB)

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
            if mID and not (issecretvalue and issecretvalue(mID)) and not idx[mID] then
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

-- =================================================================
-- Drop rates LUT (per-kill/per-attempt community-documented rates).
-- Keyed by mount teach-item itemID. Values are probabilities in [0,1].
-- Used for "What a grind" messaging: cumulative P = 1 - (1-rate)^tries.
-- Rates are approximate community baselines as of 2026-04; refine with in-game
-- experience. Wrong rates only cause missed/false grind messages — gameplay safe.
-- Omit an entry to disable the grind-check for that mount.
-- =================================================================
ns.CollectibleSourceDB.dropRates = {
    -- Classic / Vanilla
    [13335]  = 0.01,    -- Deathcharger's Reins (Baron Rivendare, Strat)
    [18767]  = 0.02,    -- Swift Razzashi Raptor (Bloodlord Mandokir, ZG)
    [19872]  = 0.01,    -- Swift Zulian Tiger (High Priest Thekal, ZG)
    [21176]  = 0.01,    -- Black Qiraji Resonating Crystal (AQ40) — legacy gated
    [30480]  = 0.007,   -- Fiery Warhorse's Reins (Attumen, Karazhan)
    -- TBC
    [32458]  = 0.013,   -- Ashes of Al'ar (Kael'thas, Tempest Keep)
    [32768]  = 0.013,   -- Reins of the Raven Lord (Anzu, Sethekk Halls H)
    [29228]  = 0.013,   -- Swift White Hawkstrider (Kael'thas, Magisters' Terrace H)
    [35513]  = 0.013,   -- Blue Drake (Malygos 10)
    -- Holiday / Event
    [37012]  = 0.005,   -- Headless Horseman's Reins (Hallow's End)
    [71665]  = 0.0003,  -- Big Love Rocket (Apothecary Hummel, Love is in the Air)
    -- WotLK
    [43951]  = 0.04,    -- Reins of the Bronze Drake (CoS timed)
    [43952]  = 0.04,    -- Reins of the Azure Drake (Malygos 10)
    [43953]  = 0.04,    -- Reins of the Twilight Drake (Sartharion+3)
    [43986]  = 0.005,   -- Reins of the Blue Drake (Malygos 10, legacy)
    [44168]  = 0.0003,  -- Reins of the Time-Lost Proto-Drake (Storm Peaks rare)
    [44177]  = 0.01,    -- Reins of the Ice Mammoth (legacy rare)
    [44689]  = 0.02,    -- Reins of the Blue Drake (alt)
    [45693]  = 0.01,    -- Mimiron's Head (Yogg-Saron 0-keeper 25)
    [46109]  = 0.00014, -- Reins of the Sea Turtle (fishing)
    [50818]  = 0.009,   -- Reins of the Crimson Deathcharger — Invincible (LK25H)
    [49636]  = 0.04,    -- Reins of the Onyxian Drake (Onyxia 25)
    -- Cataclysm
    [63231]  = 0.01,    -- Flametalon of Alysrazor (Firelands)
    [63040]  = 0.01,    -- Smoldering Egg of Millagazor (Ragnaros)
    [63043]  = 0.01,    -- Life-Binder's Handmaiden (Deathwing H)
    [63042]  = 0.0001,  -- Reins of the Phosphorescent Stone Drake (Aeonaxx rare)
    [67151]  = 0.0002,  -- Reins of Poseidus (rare world serpent)
    [69230]  = 0.03,    -- Amani Battle Bear (ZA timed, legacy)
    [78919]  = 0.005,   -- Experiment 12-B (Ultraxion LFR/N)
    -- MoP
    [87771]  = 0.01,    -- Reins of the Heavenly Crimson Cloud Serpent (Sha of Anger)
    [87777]  = 0.009,   -- Reins of the Astral Cloud Serpent (Elegon)
    [89783]  = 0.01,    -- Son of Galleon's Saddle (Galleon rare)
    [93666]  = 0.015,   -- Clutch of Ji-Kun (Ji-Kun, Throne of Thunder)
    [94228]  = 0.01,    -- Spawn of Horridon (Horridon, ToT)
    [95059]  = 0.01,    -- Kor'kron Juggernaut (Garrosh H, SoO)
    [104253] = 0.01,    -- Reins of the Thundering Ruby Cloud Serpent (Alani)
    -- WoD
    [116775] = 0.015,   -- Giant Coldsnout (Draenor zone rare cluster)
    [116669] = 0.01,    -- Garn Nighthowl (Nok-Karosh type, Frostfire rare)
    [127156] = 0.01,    -- Trained Rocktusk
    [128671] = 0.005,   -- Ironhoof Destroyer (Blackhand M)
    [130965] = 0.01,    -- Felsteel Annihilator (Archimonde M)
    -- Legion
    [137574] = 0.01,    -- Midnight's Eternal Reins (Kara Nightbane)
    [137615] = 0.005,   -- Abyss Worm (Mistress Sassz'ine M)
    [142236] = 0.005,   -- Antoran Charhound (Felhounds of Sargeras M)
    [147899] = 0.005,   -- Shackled Ur'zul (Argus M)
    [152844] = 0.005,   -- Fiendish Hellfire Core (Jaina M, BoD)
    [152912] = 0.00025, -- Pond Nettle (fishing, Legion)
    [152815] = 0.02,    -- Highmountain Elderhorn (legacy)
    -- BfA
    [163131] = 0.0002,  -- Great Sea Ray (fishing, BfA)
    [163575] = 0.005,   -- Glacial Tidestorm (Jaina M)
    [166518] = 0.005,   -- G.M.O.D. (Mekkatorque M)
    [166705] = 0.005,   -- Bloodflank Charger (Stormwall Blockade M)
    [168832] = 0.005,   -- Awakened Mindborer (Queen Azshara M)
    [174859] = 0.005,   -- Ankoan Waverider (Uu'nat M, Crucible)
    [175836] = 0.005,   -- Ny'alothan Ta'etheral (N'Zoth M)
    -- Shadowlands
    [180725] = 0.01,    -- Arboreal Gulper (Gormtamer Tizo rare, Ardenweald)
    [186656] = 0.005,   -- Soultwisted Deathwalker (Sylvanas M)
    [190177] = 0.005,   -- Vengeance (Jailer M)
    -- Dragonflight
    [201098] = 0.01,    -- Renewed Proto-Drake: Reins of Wrathion's Steed
    [204729] = 0.005,   -- Shadowflame Reaver (Raszageth M)
    [210600] = 0.005,   -- Cobalt Pyreclaw (Fyrakk M)
    [220267] = 0.005,   -- Ashen Predator (Nymue M)
    -- War Within S1-S2
    [224147] = 0.008,   -- Sureki Skyrazor (Queen Ansurek M)
    [236960] = 0.03,    -- Prototype A.S.M.R. (Gallywix M, Nerub-ar / Liberation)
    -- Midnight 12.0
    [246590] = 0.5,     -- Ashes of Belo'ren (March on Quel'Danas — Midnight Falls Mythic; per-player ~50%)
    [260916] = 0.0001,  -- Nether-Warped Drake (fishing, Midnight)
}

-- =================================================================
-- Returns the known per-attempt drop rate for a mount item, or nil.
-- @param itemID number mount teach-item itemID
-- @return number|nil rate in [0,1]
-- =================================================================
function ns.CollectibleSourceDB.GetDropRate(itemID)
    if not itemID then return nil end
    local id = tonumber(itemID)
    if not id then return nil end
    local rate = ns.CollectibleSourceDB.dropRates[id]
    if type(rate) ~= "number" or rate <= 0 or rate >= 1 then return nil end
    return rate
end

-- =================================================================
-- Cumulative probability of obtaining a drop in N independent attempts.
-- P(obtained by N tries) = 1 - (1 - rate)^tries
-- @param itemID number mount teach-item itemID
-- @param tries number number of attempts (>= 0)
-- @return number|nil P in [0,1], or nil when rate unknown
-- =================================================================
function ns.CollectibleSourceDB.GetCumulativeProbability(itemID, tries)
    local rate = ns.CollectibleSourceDB.GetDropRate(itemID)
    if not rate then return nil end
    local n = tonumber(tries) or 0
    if n <= 0 then return 0 end
    return 1 - (1 - rate) ^ n
end
