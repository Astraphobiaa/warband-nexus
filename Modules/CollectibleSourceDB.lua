--[[
    Warband Nexus - Collectible Source Database
    Comprehensive NPC/Object/Fishing/Container -> Mount/Pet/Toy drop mappings

    ENTRY FORMAT:
    { type = "mount"|"pet"|"toy", itemID = number, name = "Display Name" [, guaranteed = true] }

    - type:         "mount", "pet", or "toy"
    - itemID:       The item that drops in the loot window (used for loot scanning)
    - name:         English display name for chat messages
    - guaranteed:   Optional. If true, this is a 100% drop rate item. Try counter does not increment
                    or display for guaranteed drops (Midnight 12.0+).

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

ns.CollectibleSourceDB = {
    version = "12.0.9",
    lastUpdated = "2026-02-09",

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
        },

        -- ========================================
        -- THE BURNING CRUSADE
        -- ========================================

        [16152] = { -- Attumen the Huntsman (Karazhan)
            { type = "mount", itemID = 30480, name = "Fiery Warhorse's Reins" },
        },
        [19622] = { -- Kael'thas Sunstrider (Tempest Keep: The Eye)
            { type = "mount", itemID = 32458, name = "Ashes of Al'ar" },
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

        [26693] = { -- Skadi the Ruthless (Utgarde Pinnacle Heroic)
            { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" },
        },
        [174062] = { -- Skadi the Ruthless (Utgarde Pinnacle - Timewalking) [Rarity: npcs]
            { type = "mount", itemID = 44151, name = "Reins of the Blue Proto-Drake" },
        },
        [28859] = { -- Malygos (Eye of Eternity)
            { type = "mount", itemID = 43953, name = "Reins of the Blue Drake" },
            { type = "mount", itemID = 43952, name = "Reins of the Azure Drake" },
        },
        [28860] = { -- Sartharion (Obsidian Sanctum 3D)
            { type = "mount", itemID = 43986, name = "Reins of the Black Drake" },
            { type = "mount", itemID = 43954, name = "Reins of the Twilight Drake" },
        },
        [33288] = { -- Yogg-Saron (Ulduar 0-Light)
            { type = "mount", itemID = 45693, name = "Mimiron's Head" },
        },
        [10184] = { -- Onyxia (Onyxia's Lair)
            { type = "mount", itemID = 49636, name = "Reins of the Onyxian Drake" },
        },
        [36597] = { -- The Lich King (ICC 25H)
            { type = "mount", itemID = 50818, name = "Invincible's Reins" },
        },
        [32273] = { -- Infinite Corruptor (Culling of Stratholme Heroic)
            { type = "mount", itemID = 43951, name = "Reins of the Bronze Drake", guaranteed = true },
        },
        -- Vault of Archavon bosses (faction-specific item IDs)
        [31125] = { -- Archavon the Stone Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
        },
        [33993] = { -- Emalon the Storm Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
        },
        [35013] = { -- Koralon the Flame Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
        },
        [38433] = { -- Toravon the Ice Watcher
            { type = "mount", itemID = 43959, name = "Reins of the Grand Black War Mammoth" }, -- Alliance
            { type = "mount", itemID = 44083, name = "Reins of the Grand Black War Mammoth" }, -- Horde
        },

        -- ========================================
        -- CATACLYSM
        -- ========================================

        [43873] = { -- Altairus (Vortex Pinnacle)
            { type = "mount", itemID = 63040, name = "Reins of the Drake of the North Wind" },
        },
        [43214] = { -- Slabhide (The Stonecore)
            { type = "mount", itemID = 63043, name = "Reins of the Vitreous Stone Drake" },
        },
        [46753] = { -- Al'Akir (Throne of the Four Winds)
            { type = "mount", itemID = 63041, name = "Reins of the Drake of the South Wind" },
        },
        [52151] = { -- Bloodlord Mandokir (Zul'Gurub)
            { type = "mount", itemID = 68823, name = "Armored Razzashi Raptor" },
        },
        [52059] = { -- High Priestess Kilnara (Zul'Gurub) [Rarity verified NPC ID]
            { type = "mount", itemID = 68824, name = "Swift Zulian Panther" },
        },
        [55294] = { -- Ultraxion (Dragon Soul)
            { type = "mount", itemID = 78919, name = "Experiment 12-B" },
        },
        [52530] = { -- Alysrazor (Firelands)
            { type = "mount", itemID = 71665, name = "Flametalon of Alysrazor" },
        },
        [52409] = { -- Ragnaros (Firelands Heroic)
            { type = "mount", itemID = 69224, name = "Smoldering Egg of Millagazor" },
        },
        -- Madness of Deathwing (Dragon Soul) - 2 mount drops
        [56173] = { -- Madness of Deathwing (Dragon Soul)
            { type = "mount", itemID = 77067, name = "Reins of the Blazing Drake" },
            { type = "mount", itemID = 77069, name = "Life-Binder's Handmaiden" },
        },

        -- ========================================
        -- MISTS OF PANDARIA
        -- ========================================

        -- World Bosses
        [60491] = { -- Sha of Anger (Kun-Lai Summit)
            { type = "mount", itemID = 87771, name = "Reins of the Heavenly Onyx Cloud Serpent" },
        },
        [62346] = { -- Galleon (Valley of the Four Winds)
            { type = "mount", itemID = 89783, name = "Son of Galleon's Saddle" },
        },
        [69099] = { -- Nalak (Isle of Thunder)
            { type = "mount", itemID = 95057, name = "Reins of the Thundering Cobalt Cloud Serpent" },
        },
        [69161] = { -- Oondasta (Isle of Giants)
            { type = "mount", itemID = 94228, name = "Reins of the Cobalt Primordial Direhorn" },
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
        },
        [68476] = { -- Horridon (Throne of Thunder)
            { type = "mount", itemID = 93666, name = "Spawn of Horridon" },
        },
        [69712] = { -- Ji-Kun (Throne of Thunder)
            { type = "mount", itemID = 95059, name = "Clutch of Ji-Kun" },
        },
        [71865] = { -- Garrosh Hellscream (Siege of Orgrimmar Mythic)
            { type = "mount", itemID = 104253, name = "Kor'kron Juggernaut" },
        },

        -- ========================================
        -- WARLORDS OF DRAENOR
        -- ========================================

        -- Rare Spawns (guaranteed drops from Rarity / verified sources)
        [81001] = { -- Nok-Karosh (Frostfire Ridge) [Rarity: chance=1]
            { type = "mount", itemID = 116794, name = "Garn Nighthowl", guaranteed = true },
        },

        -- World Boss
        [87493] = { -- Rukhmar (Spires of Arak) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 116771, name = "Solar Spirehawk" },
        },
        [83746] = { -- Rukhmar (Spires of Arak - alternate NPC ID) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 116771, name = "Solar Spirehawk" },
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
        },
        [91331] = { -- Archimonde (Hellfire Citadel Mythic)
            { type = "mount", itemID = 123890, name = "Felsteel Annihilator" },
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
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core" }, -- Mythic only
        },
        [104154] = { -- Gul'dan (The Nighthold - normal form) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core" },
        },
        [111022] = { -- The Demon Within (The Nighthold - Mythic phase) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 137574, name = "Living Infernal Core" },
            { type = "mount", itemID = 137575, name = "Fiendish Hellfire Core" },
        },
        [115767] = { -- Mistress Sassz'ine (Tomb of Sargeras)
            { type = "mount", itemID = 143643, name = "Abyss Worm" },
        },
        [126915] = { -- Felhounds of Sargeras (Antorus)
            { type = "mount", itemID = 152816, name = "Antoran Charhound" },
        },
        [126916] = { -- Felhounds of Sargeras alt (Antorus)
            { type = "mount", itemID = 152816, name = "Antoran Charhound" },
        },
        [130352] = { -- Argus the Unmaker (Antorus Mythic) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 152789, name = "Shackled Ur'zul" },
        },

        -- Toys
        [100230] = { -- Nazak the Fiend (Suramar)
            { type = "toy", itemID = 129149, name = "Skin of the Soulflayer" },
        },

        -- ========================================
        -- BATTLE FOR AZEROTH
        -- ========================================

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
        },
        [133007] = { -- Unbound Abomination (The Underrot Mythic)
            { type = "mount", itemID = 160829, name = "Underrot Crawg Harness" },
        },
        [136160] = { -- King Dazar (Kings' Rest Mythic)
            { type = "mount", itemID = 159921, name = "Mummified Raptor Skull" },
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
        },
        [144796] = { -- Mekkatorque (Battle of Dazar'alor)
            { type = "mount", itemID = 166518, name = "G.M.O.D." },
        },
        [158041] = { -- N'Zoth the Corruptor (Ny'alotha Mythic)
            { type = "mount", itemID = 174872, name = "Ny'alotha Allseer" },
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
        },
        [180863] = { -- So'leah (Tazavesh Mythic)
            { type = "mount", itemID = 186638, name = "Cartel Master's Gearglider" },
        },

        -- Raid Bosses [Rarity verified via tooltipNpcs]
        [178738] = { -- The Nine (Sanctum of Domination)
            { type = "mount", itemID = 186656, name = "Sanctum Gloomcharger's Reins" },
        },
        [175732] = { -- Sylvanas Windrunner (Sanctum of Domination Mythic)
            { type = "mount", itemID = 186642, name = "Vengeance's Reins" },
        },
        [180990] = { -- The Jailer (Sepulcher of the First Ones Mythic)
            { type = "mount", itemID = 190768, name = "Fractal Cypher of the Zereth Overseer" },
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

        -- Dungeon
        [210797] = { -- Wick (Darkflame Cleft Mythic) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 225548, name = "Wick's Lead" },
        },

        -- 11.1 - Undermine
        [234621] = { -- Gallagio Garbage (Undermine) [Rarity verified]
            { type = "mount", itemID = 229953, name = "Salvaged Goblin Gazillionaire's Flying Machine" },
        },
        [231310] = { -- Darkfuse Precipitant (Undermine) [Rarity verified]
            { type = "mount", itemID = 229955, name = "Darkfuse Spy-Eye" },
        },

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
        },
        [241526] = { -- Chrome King Gallywix (Liberation of Undermine) [Rarity: tooltipNpcs]
            { type = "mount", itemID = 236960, name = "Prototype A.S.M.R." },
        },

        -- ========================================
        -- HOLIDAY EVENTS
        -- ========================================

        -- Hallow's End
        [23682] = { -- Headless Horseman (Scarlet Monastery)
            { type = "mount", itemID = 37012, name = "The Horseman's Reins" },
        },

        -- Brewfest
        [23872] = { -- Coren Direbrew (Blackrock Depths)
            { type = "mount", itemID = 37828, name = "Great Brewfest Kodo" },
        },

        -- Love is in the Air
        [36296] = { -- Apothecary Hummel
            { type = "mount", itemID = 50250, name = "Big Love Rocket" },
        },
    },

    -- =================================================================
    -- GAME OBJECTS (Chests, Caches, Clickable Objects)
    -- Key: [objectID] = { { type, itemID, name }, ... }
    -- Detection: LOOT_OPENED + GameObject GUID
    -- =================================================================
    objects = {
        -- Object entries will be added as they are verified
        -- Format: [objectID] = { { type = "mount", itemID = 12345, name = "Mount Name" } },
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

        -- Argus zones (Legion 7.3) - Pond Nettle
        [885] = { -- Antoran Wastes
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },
        [830] = { -- Krokuun
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },
        [882] = { -- Mac'Aree
            { type = "mount", itemID = 152912, name = "Pond Nettle" },
        },

        -- BfA zones - Great Sea Ray [Rarity verified]
        [896] = { -- Drustvar
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
        },
        [895] = { -- Tiragarde Sound
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
        },
        [942] = { -- Stormsong Valley
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
        },
        [862] = { -- Zuldazar
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
        },
        [863] = { -- Nazmir
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
        },
        [864] = { -- Vol'dun
            { type = "mount", itemID = 163131, name = "Great Sea Ray" },
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
        [54537] = { -- Heart-Shaped Box (Love is in the Air)
            drops = {
                { type = "mount", itemID = 235658, name = "Spring Butterfly" },
            },
        },
    },

    -- =================================================================
    -- ZONE-WIDE DROPS (Kill any mob in zone)
    -- Key: [zoneMapID] = { { type, itemID, name }, ... }
    -- Detection: Kill ANY mob in zone + LOOT_OPENED
    -- =================================================================
    zones = {
        -- BfA Zone Drops [Rarity verified: large NPC lists -> zone-wide]
        [864] = { -- Vol'dun
            { type = "mount", itemID = 163576, name = "Captured Dune Scavenger" },
        },
        [896] = { -- Drustvar
            { type = "mount", itemID = 163574, name = "Chewed-On Reins of the Terrified Pack Mule" },
        },
        [863] = { -- Nazmir
            { type = "mount", itemID = 163575, name = "Reins of a Tamed Bloodfeaster" },
        },
        [942] = { -- Stormsong Valley
            { type = "mount", itemID = 163573, name = "Goldenmane's Reins" },
        },
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
