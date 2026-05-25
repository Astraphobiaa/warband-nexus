--[[
    Curated Midnight weekly / content-event quests (shared by DailyQuestManager and reminder quest picker).
    weeklyQuests = emissary-style weeklies (Midnight: World Quests, Spark of Radiance, etc.) — not in Set Alert WQ list.
    events = Content Events (Soiree, Abundance, Haranir, Stormarion) — Set Alert Content Events tab only.
    World quests: Modules/Data/ReminderMidnightWorldQuestData.lua (warcraft.wiki.gg Category:Midnight_world_quests).
    Titles verified via warcraft.wiki.gg quest pages (12.0.1).
]]

local ADDON_NAME, ns = ...

local ENTRIES = {
    -- Weekly objectives (meta / important)
    { questID = 93942, title = "Spark of Radiance",            category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_10_Jewelcrafting_Gem3Primal_Fire_Cut_Green",
      description = "Weekly Spark of Radiance from Lady Liadrin (professions)." },
    { questID = 93766, title = "Midnight: World Quests",       category = "weeklyQuests", zone = "Quel'Thalas",   icon = "Interface\\Icons\\worldquest-icon",
      description = "Complete 6 world quests in Midnight zones." },
    { questID = 95245, title = "Midnight: World Tour",         category = "weeklyQuests", zone = "Quel'Thalas",   icon = "Interface\\Icons\\INV_Misc_Map_01",
      description = "Complete all four zone events: Soiree, Abundance, Haranir, Stormarion." },
    { questID = 93913, title = "Midnight: World Boss",         category = "weeklyQuests", zone = "Quel'Thalas",   icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      description = "Defeat the weekly world boss in Quel'Thalas." },
    { questID = 81514, title = "Bountiful Delves",             category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_Misc_Bag_33",
      description = "Complete Tier 8+ Delves for bonus rewards." },
    { questID = 92600, title = "Cracked Keystone",             category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_Keystone",
      description = "Complete a Tier 11 Bountiful Delve for a Crested Keystone." },

    -- Content events (weekly zone events — meta quests + sub-quests)
    { questID = 93889, title = "Midnight: Saltheril's Soiree", category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Food_164_Fish_Seadog", eventGroup = "soiree",
      description = "Earn favor with a Silvermoon Court faction at Saltheril's Soiree." },
    { questID = 89289, title = "Favor of the Court",           category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Note_06",              eventGroup = "soiree", isSubQuest = true,
      description = "Pick an ally faction to invite to the Soiree." },
    { questID = 90573, title = "Fortify the Runestones",       category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\Spell_Arcane_PortalSilvermoon", eventGroup = "soiree", isSubQuest = true, alternateIDs = {90574, 90575, 90576},
      description = "Charge and defend a Runestone (faction-specific)." },

    { questID = 93890, title = "Midnight: Abundance",          category = "events", zone = "Zul'Aman",       icon = "Interface\\Icons\\INV_Misc_Herb_AncientLichen",  eventGroup = "abundance",
      description = "Treasure cave sprint — donate points to Dundun's altars." },
    { questID = 89507, title = "Abundant Offerings",           category = "events", zone = "Zul'Aman",       icon = "Interface\\Icons\\INV_Misc_Coin_02",             eventGroup = "abundance", isSubQuest = true,
      description = "Accumulate 20,000 treasure points across Abundance runs." },

    { questID = 93891, title = "Midnight: Legends of the Haranir", category = "events", zone = "Harandar",     icon = "Interface\\Icons\\INV_Misc_Book_09",             eventGroup = "haranir",
      description = "Complete one Hara'ti relic scenario (warband weekly pick)." },
    { questID = 89268, title = "Lost Legends",                 category = "events", zone = "Harandar",       icon = "Interface\\Icons\\INV_Misc_Rune_15",             eventGroup = "haranir", isSubQuest = true,
      description = "Select a relic at the Reliquary of the Zur'ashar." },

    { questID = 93892, title = "Midnight: Stormarion Assault", category = "events", zone = "Voidstorm",      icon = "Interface\\Icons\\Ability_Warrior_Charge",       eventGroup = "stormarion",
      description = "Defend the Singularity Anchor during Stormarion Assault." },
}

local LOOKUP = {}
for i = 1, #ENTRIES do
    local entry = ENTRIES[i]
    LOOKUP[entry.questID] = entry
    if entry.alternateIDs then
        for ai = 1, #entry.alternateIDs do
            LOOKUP[entry.alternateIDs[ai]] = entry
        end
    end
end

local EVENT_GROUP_ORDER = { soiree = 1, abundance = 2, haranir = 3, stormarion = 4 }

ns.MidnightQuestCatalog = {
    GetEntries = function() return ENTRIES end,
    GetLookup = function() return LOOKUP end,
    GetEventGroupOrder = function() return EVENT_GROUP_ORDER end,
}
