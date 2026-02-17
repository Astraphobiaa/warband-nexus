--[[
    Warband Nexus - Collectible Source Database
    Comprehensive NPC/Object/Fishing/Container -> Mount/Pet/Toy drop mappings

    ENTRY FORMAT:
    { type = "mount"|"pet"|"toy", itemID = number, name = "Display Name" [, guaranteed = true] [, repeatable = true] }

    - type:         "mount", "pet", or "toy"
    - itemID:       The item that drops in the loot window (used for loot scanning)
    - name:         English display name for chat messages
    - guaranteed:   Optional. If true, this is a 100% drop rate item. Try counter does not increment
                    or display for guaranteed drops (Midnight 12.0+).
    - repeatable:   Optional. If true, this is a farmable item with no loot lockout (or BoE) that can be
                    obtained again after collection. Try counter resets on obtain instead of freezing,
                    starting a new cycle. Tooltip shows "X attempts" instead of "Collected".

    collectibleID (mountID/speciesID) is resolved at runtime via:
      mount: C_MountJournal.GetMountFromItem(itemID)
      pet:   C_PetJournal.GetPetInfoByItemID(itemID)
      toy:   same as itemID

    DATA SOURCE: Rarity addon (github.com/WowRarity/Rarity) - verified NPC/item IDs
    MAINTENANCE:
    - Update 'version' and 'lastUpdated' when adding new entries
    - Add entries under the correct expansion section
    - Use comment format: [npcID] = { -- NPC Name (Instance/Zone)
    - Run /wn validatedb in-game to check all entries
]]

local ADDON_NAME, ns = ...

-- =====================================================================
-- BfA "Zone Drop" mounts - shared drop tables (referenced by multiple NPC entries)
-- These mounts drop from specific mob factions within a zone, NOT every mob.
-- Source: Rarity addon (github.com/WowRarity/Rarity) - verified NPC IDs
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

-- TWW "Isle of Dorn" Crackling Shard - shared drop table (17 rares, ≥1% drop rate)
-- 10x Crackling Shard -> Storm Vessel -> defeat Alunira -> Alunira mount
local _cracklingShard = {
    { type = "item", itemID = 224025, name = "Crackling Shard", repeatable = true,
      yields = {
          { type = "mount", itemID = 223270, name = "Alunira" },
      },
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

ns.CollectibleSourceDB = {
    version = "12.0.12",
    lastUpdated = "2026-02-17",

    -- =================================================================
    -- NPC / BOSS KILLS
    -- Key: [npcID] = { { type, itemID, name [, guaranteed] }, ... }
    -- Detection: CLEU UNIT_DIED + LOOT_OPENED
    -- =================================================================
    npcs = {

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
        [174062] = { -- Skadi the Ruthless (Utgarde Pinnacle - Timewalking) [Rarity: npcs]
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
        [33288] = { -- Yogg-Saron (Ulduar 0-Light)
            { type = "mount", itemID = 45693, name = "Mimiron's Head" },
            statisticIds = { 2869, 2883 },  -- Yogg-Saron kills (10 & 25)
        },
        [10184] = { -- Onyxia (Onyxia's Lair)
            { type = "mount", itemID = 49636, name = "Reins of the Onyxian Drake" },
            statisticIds = { 1098 },  -- Onyxia kills
        },
        [36597] = { -- The Lich King (ICC 25H)
            { type = "mount", itemID = 50818, name = "Invincible's Reins" },
            statisticIds = { 4688 },  -- Lich King 25H kills
            dropDifficulty = "25H",
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
        [43214] = { -- Slabhide (The Stonecore)
            { type = "mount", itemID = 63043, name = "Reins of the Vitreous Stone Drake" },
        },
        [46753] = { -- Al'Akir (Throne of the Four Winds)
            { type = "mount", itemID = 63041, name = "Reins of the Drake of the South Wind" },
            statisticIds = { 5576, 5577 },  -- Al'Akir kills (10 & 25)
        },
        [52151] = { -- Bloodlord Mandokir (Zul'Gurub)
            { type = "mount", itemID = 68823, name = "Armored Razzashi Raptor" },
        },
        [52059] = { -- High Priestess Kilnara (Zul'Gurub) [Rarity verified NPC ID]
            { type = "mount", itemID = 68824, name = "Swift Zulian Panther" },
        },
        [55294] = { -- Ultraxion (Dragon Soul)
            { type = "mount", itemID = 78919, name = "Experiment 12-B" },
            statisticIds = { 6161, 6162 },  -- Ultraxion kills (10 & 25)
        },
        [52530] = { -- Alysrazor (Firelands)
            { type = "mount", itemID = 71665, name = "Flametalon of Alysrazor" },
            statisticIds = { 5970, 5971 },  -- Alysrazor kills (10 & 25)
        },
        [52409] = { -- Ragnaros (Firelands Heroic)
            { type = "mount", itemID = 69224, name = "Smoldering Egg of Millagazor" },
            statisticIds = { 5976, 5977 },  -- Ragnaros kills (10 & 25)
            dropDifficulty = "Heroic",
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
        },

        -- ========================================
        -- WARLORDS OF DRAENOR
        -- ========================================

        -- Rare Spawns (guaranteed drops from Rarity / verified sources)
        [81001] = { -- Nok-Karosh (Frostfire Ridge) [Rarity: chance=1]
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
        [87493] = { -- Rukhmar (Spires of Arak) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 116771, name = "Solar Spirehawk" },
            statisticIds = { 9279 },  -- Rukhmar kills
        },
        [83746] = { -- Rukhmar (Spires of Arak - alternate NPC ID) [Rarity: tooltipNpcs]
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

        -- Raid Bosses [Rarity verified NPC IDs via tooltipNpcs]
        [77325] = { -- Blackhand (Blackrock Foundry Mythic)
            { type = "mount", itemID = 116660, name = "Ironhoof Destroyer" },
            statisticIds = { 9365 },  -- Blackhand kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [91331] = { -- Archimonde (Hellfire Citadel Mythic)
            { type = "mount", itemID = 123890, name = "Felsteel Annihilator" },
            statisticIds = { 10252 },  -- Archimonde kills (Mythic)
            dropDifficulty = "Mythic",
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

        -- Argus Rares [Rarity verified]
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

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [105503] = { -- Gul'dan (The Nighthold)
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core", dropDifficulty = "Mythic" },
            statisticIds = { 10979, 10980, 10978 },  -- Gul'dan kills (H, M, N)
        },
        [104154] = { -- Gul'dan (The Nighthold - normal form) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core", dropDifficulty = "Mythic" },
            statisticIds = { 10979, 10980, 10978 },  -- Gul'dan kills (H, M, N)
        },
        [111022] = { -- The Demon Within (The Nighthold - Mythic phase) [Rarity: tooltipNpcs]
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
        [130352] = { -- Argus the Unmaker (Antorus Mythic) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 152789, name = "Shackled Ur'zul" },
            statisticIds = { 11986 },  -- Argus kills (Mythic)
            dropDifficulty = "Mythic",
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
        -- Source: Rarity addon (20 verified NPC IDs)
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
        -- Source: Rarity addon (9 verified NPC IDs)
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
        -- Source: Rarity addon (16 verified NPC IDs)
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
        -- Source: Rarity addon (25 verified NPC IDs)
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
        [152182] = { -- Rustfeather (Mechagon) [Rarity: itemId 168370]
            { type = "mount", itemID = 168370, name = "Rusted Keys to the Junkheap Drifter" },
        },
        [154342] = { -- Arachnoid Harvester (Mechagon - alt timeline) [Rarity: npcs={154342,151934}]
            { type = "mount", itemID = 168823, name = "Rusty Mechanocrawler" },
        },
        [151934] = { -- Arachnoid Harvester (Mechagon - standard) [Rarity: npcs={154342,151934}]
            { type = "mount", itemID = 168823, name = "Rusty Mechanocrawler" },
        },
        [152290] = { -- Soundless (Nazjatar) [Rarity verified]
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

        -- Dungeon Bosses [Rarity verified]
        [126983] = { -- Harlan Sweete (Freehold Mythic)
            { type = "mount", itemID = 159842, name = "Sharkbait's Favorite Crackers" },
            statisticIds = { 12752 },  -- Harlan Sweete kills (Mythic)
            dropDifficulty = "Mythic",
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
        },
        [150190] = { -- HK-8 Aerial Oppression Unit (Operation: Mechagon - alt ID)
            { type = "mount", itemID = 168826, name = "Mechagon Peacekeeper" },
        },

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [165396] = { -- Lady Jaina Proudmoore (Battle of Dazar'alor Mythic)
            { type = "mount", itemID = 166705, name = "Glacial Tidestorm" },
            statisticIds = { 13382 },  -- Jaina kills (Mythic)
            dropDifficulty = "Mythic",
        },
        [144796] = { -- Mekkatorque (Battle of Dazar'alor)
            { type = "mount", itemID = 166518, name = "G.M.O.D." },
            statisticIds = { 13372, 13373, 13374, 13379 },  -- Mekkatorque kills (N, H, M, LFR)
        },
        [158041] = { -- N'Zoth the Corruptor (Ny'alotha Mythic)
            { type = "mount", itemID = 174872, name = "Ny'alotha Allseer" },
            statisticIds = { 14138 },  -- N'Zoth kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- ========================================
        -- SHADOWLANDS
        -- ========================================

        -- Revendreth Rares
        [166521] = { -- Famu the Infinite (Revendreth) [Rarity: itemId 180582]
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
        [162818] = { -- Warbringer Mal'Korak (Maldraxxus - alternate) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 182085, name = "Blisterback Bloodtusk" },
        },
        [168147] = { -- Sabriel the Bonecleaver (Maldraxxus)
            { type = "mount", itemID = 181815, name = "Armored Bonehoof Tauralus" },
        },
        [168148] = { -- Sabriel the Bonecleaver (Maldraxxus - alternate) [Rarity: tooltipNpcs]
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

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [178738] = { -- The Nine (Sanctum of Domination)
            { type = "mount", itemID = 186656, name = "Sanctum Gloomcharger's Reins" },
            statisticIds = { 15145, 15144, 15147, 15146 },  -- The Nine kills (N, LFR, M, H)
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
        [195353] = { -- Breezebiter (The Azure Span) [Rarity verified]
            { type = "mount", itemID = 201440, name = "Reins of the Liberated Slyvern" },
        },

        -- Zaralek Cavern
        [203625] = { -- Karokta (Zaralek Cavern) [Rarity: itemId 205203]
            { type = "mount", itemID = 205203, name = "Cobalt Shalewing" },
        },

        -- Forbidden Reach rares - Ancient Salamanther (16 rares share same mount) [Rarity verified]
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
        [208029] = { -- Clayscale Hornstrider rare (Azure Span) [Rarity verified]
            { type = "mount", itemID = 212645, name = "Clayscale Hornstrider" },
        },

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [204931] = { -- Fyrakk (Amirdrassil Mythic) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 210061, name = "Reins of Anu'relos, Flame's Guidance" },
            statisticIds = { 19386 },  -- Fyrakk kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- ========================================
        -- THE WAR WITHIN
        -- ========================================

        -- Hallowfall
        [207802] = { -- Beledar's Spawn (Hallowfall) [Rarity verified]
            { type = "mount", itemID = 223315, name = "Beledar's Spawn" },
        },

        -- The Ringing Deeps
        [220285] = { -- Regurgitated Mole Reins rare (The Ringing Deeps) [Rarity verified]
            { type = "mount", itemID = 223501, name = "Regurgitated Mole Reins" },
        },

        -- Isle of Dorn — Crackling Shard sources (10x -> Storm Vessel -> Alunira mount)
        -- Rares with ≥1% drop rate. All repeatable, no weekly lockout.
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

        -- Dungeon
        [210797] = { -- Wick (Darkflame Cleft Mythic) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 225548, name = "Wick's Lead" },
            statisticIds = { 20484 },  -- Darkflame Cleft kills (Mythic)
            dropDifficulty = "Mythic",
        },

        -- 11.1 - Undermine
        [234621] = { -- Gallagio Garbage (Undermine) [Rarity verified] — no loot lockout, repeatable
            { type = "mount", itemID = 229953, name = "Salvaged Goblin Gazillionaire's Flying Machine", repeatable = true },
            _miscMechanica[1],
        },
        [231310] = { -- Darkfuse Precipitant (Undermine) [Rarity verified]
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
        [234845] = { -- Sthaarbs (Karesh) [Rarity verified]
            { type = "mount", itemID = 246160, name = "Sthaarbs's Last Lunch" },
        },
        [232195] = { -- Pearlescent Krolusk rare (Karesh) [Rarity verified]
            { type = "mount", itemID = 246067, name = "Pearlescent Krolusk" },
        },

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [218370] = { -- Queen Ansurek (Nerub-ar Palace) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 224147, name = "Reins of the Sureki Skyrazor" },
            statisticIds = { 40295, 40296, 40297, 40298 },  -- Ansurek kills (LFR, N, H, M)
        },
        [241526] = { -- Chrome King Gallywix (Liberation of Undermine) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 236960, name = "Prototype A.S.M.R." },
            statisticIds = { 41330, 41329, 41328, 41327 },  -- Gallywix kills (M, H, N, LFR)
        },

        -- ========================================
        -- HOLIDAY EVENTS
        -- ========================================

        -- Holiday bosses: mounts drop from CONTAINER ITEMS, not boss corpse loot.
        -- Headless Horseman → Loot-Filled Pumpkin (container 209024)
        -- Coren Direbrew → Keg-Shaped Treasure Chest (container 117393)
        -- Apothecary Hummel → Heart-Shaped Box (container 54537)
        -- All holiday boss mounts are tracked in the containers table below.
    },

    -- =================================================================
    -- GAME OBJECTS (Chests, Caches, Clickable Objects)
    -- Key: [objectID] = { { type, itemID, name }, ... }
    -- Detection: LOOT_OPENED + GameObject GUID
    -- =================================================================
    objects = {
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
        [469857] = { -- Overflowing Dumpster (Undermine) — dumpster diving
            _miscMechanica[1],
        },
    },

    -- =================================================================
    -- FISHING
    -- Key: [zoneMapID] = { { type, itemID, name }, ... }
    -- Use 0 for drops available in any zone
    -- Detection: Fishing spell tracking + LOOT_OPENED
    -- =================================================================
    fishing = {
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

        -- BfA zones - Great Sea Ray [Rarity verified] (BoE, repeatable)
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

        -- Zereth Mortis (Shadowlands 9.2) - Strange Goop (BoE, repeatable)
        -- Fishing material for Deepstar Aurelid mount via Hirukon summon chain.
        -- Extremely low drop rate (~0.04%), BoE - can be sold on AH repeatedly.
        [1970] = { -- Zereth Mortis
            { type = "mount", itemID = 187662, name = "Strange Goop", repeatable = true },
        },
    },

    -- =================================================================
    -- CONTAINER ITEMS (Open/Use from bags)
    -- Key: [containerItemID] = { drops = { { type, itemID, name }, ... } }
    -- Detection: UNIT_SPELLCAST_SUCCEEDED + LOOT_OPENED(isFromItem=true)
    -- =================================================================
    containers = {
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
        [228741] = { -- Dauntless Imperial Lynx bag (Hallowfall) [Rarity verified]
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

        -- Holiday Containers
        -- IMPORTANT: Holiday boss mounts drop from these container items, NOT from
        -- boss corpse loot. Players receive the container once per day via LFG,
        -- open it from bags → LOOT_OPENED fires with isFromItem=true → ProcessContainerLoot.
        -- Multiple item IDs cover different WoW versions (Blizzard changes these per expansion).

        [54537] = { -- Heart-Shaped Box (Love is in the Air)
            drops = {
                { type = "mount", itemID = 50250, name = "Big Love Rocket" },
                { type = "mount", itemID = 235658, name = "Spring Butterfly" },
            },
        },

        [209024] = { -- Loot-Filled Pumpkin (Hallow's End - modern retail)
            drops = {
                { type = "mount", itemID = 37012, name = "The Horseman's Reins" },
            },
        },
        [54516] = { -- Loot-Filled Pumpkin (Hallow's End - legacy item ID)
            drops = {
                { type = "mount", itemID = 37012, name = "The Horseman's Reins" },
            },
        },

        [117393] = { -- Keg-Shaped Treasure Chest (Brewfest - modern retail)
            drops = {
                { type = "mount", itemID = 37828, name = "Great Brewfest Kodo" },
            },
        },
        [54535] = { -- Keg-Shaped Treasure Chest (Brewfest - legacy item ID)
            drops = {
                { type = "mount", itemID = 37828, name = "Great Brewfest Kodo" },
            },
        },
    },

    -- =================================================================
    -- ZONE-WIDE DROPS (Kill any mob in zone)
    -- Key: [zoneMapID] = { { type, itemID, name }, ... }
    -- Detection: Kill ANY mob in zone + LOOT_OPENED
    -- =================================================================
    -- NOTE: BfA "zone drops" (Pack Mule, Dune Scavenger, Bloodfeaster, Goldenmane)
    -- have been moved to the npcs section with specific NPC IDs from Rarity addon.
    -- They were NOT truly zone-wide; each drops only from specific mob factions.
    zones = {
        -- TWW: Isle of Dorn — Crackling Shard (any mob in zone, <1% for normals)
        -- 165 mobs total. Rares with ≥1% are also in npcs section for specific tracking.
        -- This zone entry catches ALL normal mob kills as a fallback.
        [2248] = _cracklingShard, -- Isle of Dorn (uiMapID)
    },

    -- =================================================================
    -- ENCOUNTER FALLBACK (Midnight-safe)
    -- Key: [encounterID] = { npcID1, npcID2, ... }
    -- Maps Encounter Journal encounterID -> NPC IDs in npcs table
    -- Used when CLEU is blocked during active combat in instances
    -- =================================================================
    encounters = {
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
        [2281] = { 165396 }, -- Lady Jaina Proudmoore (BoD)
        [2271] = { 144796 }, -- Mekkatorque (BoD)
        [2375] = { 158041 }, -- N'Zoth (Ny'alotha)

        -- Shadowlands
        [2439] = { 178738 }, -- The Nine (Sanctum of Domination)
        [2435] = { 175732 }, -- Sylvanas Windrunner (SoD)
        [2464] = { 180990 }, -- The Jailer (Sepulcher)

        -- Dragonflight
        [2708] = { 204931 }, -- Fyrakk (Amirdrassil)

        -- TWW
        [2922] = { 218370 }, -- Queen Ansurek (Nerub-ar Palace)
        [2611] = { 241526 }, -- Chrome King Gallywix (Liberation of Undermine)
    },

    -- =================================================================
    -- NPC KILL LOCKOUT QUESTS (daily/weekly rare kill tracking)
    -- Key: [npcID] = questID  (or { questID1, questID2 } for multi-phase rares)
    -- When IsQuestFlaggedCompleted(questID) returns true, the player has already
    -- used their daily/weekly attempt on this NPC. Subsequent kills should NOT
    -- increment the try counter because the rare item cannot drop again until reset.
    -- Source: Rarity addon DB + Wowhead quest data
    -- =================================================================
    lockoutQuests = {
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

        -- Shadowlands: Revendreth rares (daily lockout) [Rarity verified]
        [166521] = 59869,  -- Famu the Infinite
        [165290] = 59612,  -- Harika the Horrid
        [166679] = 59900,  -- Hopecrusher
        [160821] = 58259,  -- Worldedge Gorger

        -- Shadowlands: Maldraxxus rares (daily lockout) [Rarity verified]
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

        -- Shadowlands: Ardenweald rares (daily lockout) [Rarity verified]
        [168647] = 61632,  -- Valfir the Unrelenting

        -- Shadowlands: Maw rares [Rarity verified]
        [174861] = 63433,  -- Gorged Shadehound

        -- Shadowlands: Korthia rares (daily lockout) [Rarity verified]
        [179472] = 64246,  -- Konthrogz the Obliterator
        [180160] = 64455,  -- Reliwik the Defiant
        [179684] = 64233,  -- Malbog

        -- Dragonflight: Zaralek Cavern (daily lockout) [Rarity verified]
        [203625] = 75333,  -- Karokta

        -- TWW: Hallowfall / Ringing Deeps (daily lockout) [Rarity verified]
        [207802] = 81763,  -- Beledar's Spawn
        [220285] = 81633,  -- Regurgitated Mole Reins rare

        -- TWW 11.1: Undermine (daily lockout) [Rarity verified]
        [231310] = 85010,  -- Darkfuse Precipitant
    },

    -- =================================================================
    -- NPC NAME → NPC IDs REVERSE INDEX (Midnight 12.0 tooltip fallback)
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
        ["Fyrakk the Blazing"] = { 204931 },
        -- TWW
        ["Wick"] = { 210797 },
        ["Queen Ansurek"] = { 218370 },
        ["Chrome King Gallywix"] = { 241526 },
    },
}
