--[[
    Curated Midnight weekly / content-event quests (shared by DailyQuestManager and reminder quest picker).
    weeklyQuests = emissary-style weeklies (Midnight: World Quests, Spark of Radiance, etc.) -- not Set Alert WQ list.
    events = Content Events (Soiree, Abundance, Haranir, Stormarion) -- Set Alert Content Events tab only.
    World quests: Modules/Data/ReminderMidnightWorldQuestData.lua (warcraft.wiki.gg Category:Midnight_world_quests).
    catalogKey = stable id for Weekly Progress per-item tracking (trackedCatalogKeys on daily_quests plans).
    Title-pattern rows (discoverByTitle) match quest log titles when quest IDs rotate weekly.
    12.0.7 quest IDs verified via warcraft.wiki.gg + wowhead (Seeking Knowledge 96410-96444, Sporefall 96746, Ritual Site Studies 96728+).
]]

local ADDON_NAME, ns = ...

local ENTRIES = {
    -- Weekly objectives (meta / important) -- 12.0.1 baseline
    { catalogKey = "spark_radiance", questID = 93942, title = "Spark of Radiance", category = "weeklyQuests", zone = "Silvermoon", icon = "Interface\\Icons\\INV_10_Jewelcrafting_Gem3Primal_Fire_Cut_Green",
      description = "Weekly Spark of Radiance from Lady Liadrin (professions)." },
    { catalogKey = "midnight_world_quests", questID = 93766, title = "Midnight: World Quests", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\worldquest-icon",
      description = "Complete 6 world quests in Midnight zones." },
    { catalogKey = "midnight_world_tour", questID = 95245, title = "Midnight: World Tour", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\INV_Misc_Map_01",
      description = "Complete all four zone events: Soiree, Abundance, Haranir, Stormarion." },
    { catalogKey = "midnight_world_boss", questID = 93913, title = "Midnight: World Boss", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      description = "Defeat the weekly world boss in Quel'Thalas." },
    { catalogKey = "bountiful_delves", questID = 81514, title = "Bountiful Delves", category = "weeklyQuests", zone = "Silvermoon", icon = "Interface\\Icons\\INV_Misc_Bag_33",
      description = "Complete Tier 8+ Delves for bonus rewards." },
    { catalogKey = "cracked_keystone", questID = 92600, title = "Cracked Keystone", category = "weeklyQuests", zone = "Silvermoon", icon = "Interface\\Icons\\INV_Keystone",
      description = "Complete a Tier 11 Bountiful Delve for a Crested Keystone." },

    -- Patch 12.0.7 (Revelations) -- warcraft.wiki.gg Patch 12.0.7, Sunstrider Omnium, Sporefall
    { catalogKey = "omnium_folio_w1", questID = 96410, title = "Seeking Knowledge (Week 1)", category = "weeklyQuests", zone = "Silvermoon", icon = "Interface\\Icons\\INV_Misc_Book_09",
      description = "Omnium Folio week 1: empower your first rune (Mote of Omnial Inquiry)." },
    { catalogKey = "omnium_folio_w2", questID = 96441, title = "Seeking Knowledge (Week 2)", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\INV_Misc_Book_09",
      description = "Omnium Folio week 2: collect Ritualized Arcana from Ritual Sites." },
    { catalogKey = "omnium_folio_w3", questID = 96442, title = "Seeking Knowledge (Week 3)", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\INV_Misc_Book_09",
      description = "Omnium Folio week 3: collect Dark-Ley Coalescence from Void Assaults." },
    { catalogKey = "omnium_folio_w4", questID = 96443, title = "Seeking Knowledge (Week 4)", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\INV_Misc_Book_09",
      description = "Omnium Folio week 4: recover a Primessence of Magic from dungeon, delve, or RF boss." },
    { catalogKey = "omnium_folio_w5", questID = 96444, title = "Seeking Knowledge (Week 5)", category = "weeklyQuests", zone = "Voidstorm", icon = "Interface\\Icons\\INV_Misc_Book_09",
      description = "Omnium Folio week 5: fragment of alien magic from Val or Naigtal Showdown WQs." },
    { catalogKey = "sporefall_rotmire", questID = 96746, title = "Sporefall: Rotmire", category = "weeklyQuests", zone = "Harandar", icon = "Interface\\Icons\\Ability_Druid_MasterShapeshifter",
      description = "Defeat Rotmire in the Sporefall raid (weekly Delicious Sporesnack)." },

    -- Rotating weekly quest lines (title match; quest ID changes per week)
    { catalogKey = "ritual_site_studies", discoverByTitle = true, titlePattern = "ritual site studies", category = "weeklyQuests", zone = "Quel'Thalas", icon = "Interface\\Icons\\Achievement_General",
      title = "Ritual Site Studies (Tier 6)", description = "Complete two Tier 6 Ritual Sites with the active weekly challenge (12.0.7)." },
    { catalogKey = "timewalking_path", discoverByTitle = true, titlePattern = "path through time", category = "weeklyQuests", zone = "Silvermoon", icon = "Interface\\Icons\\INV_Misc_Pocketwatch_01",
      title = "Timewalking: Path Through Time", description = "Turbulent Timeways weekly (5 timewalking dungeons or 4 raid bosses)." },

    -- Content events (weekly zone events -- meta quests + sub-quests)
    { catalogKey = "event_soiree", questID = 93889, title = "Midnight: Saltheril's Soiree", category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Food_164_Fish_Seadog", eventGroup = "soiree",
      description = "Earn favor with a Silvermoon Court faction at Saltheril's Soiree." },
    { catalogKey = "event_soiree_favor", questID = 89289, title = "Favor of the Court", category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Note_06", eventGroup = "soiree", isSubQuest = true,
      description = "Pick an ally faction to invite to the Soiree." },
    { catalogKey = "event_soiree_runestones", questID = 90573, title = "Fortify the Runestones", category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\Spell_Arcane_PortalSilvermoon", eventGroup = "soiree", isSubQuest = true, alternateIDs = {90574, 90575, 90576},
      description = "Charge and defend a Runestone (faction-specific)." },

    { catalogKey = "event_abundance", questID = 93890, title = "Midnight: Abundance", category = "events", zone = "Zul'Aman", icon = "Interface\\Icons\\INV_Misc_Herb_AncientLichen", eventGroup = "abundance",
      description = "Treasure cave sprint -- donate points to Dundun's altars." },
    { catalogKey = "event_abundance_offerings", questID = 89507, title = "Abundant Offerings", category = "events", zone = "Zul'Aman", icon = "Interface\\Icons\\INV_Misc_Coin_02", eventGroup = "abundance", isSubQuest = true,
      description = "Accumulate 20,000 treasure points across Abundance runs." },

    { catalogKey = "event_haranir", questID = 93891, title = "Midnight: Legends of the Haranir", category = "events", zone = "Harandar", icon = "Interface\\Icons\\INV_Misc_Book_09", eventGroup = "haranir",
      description = "Complete one Hara'ti relic scenario (warband weekly pick)." },
    { catalogKey = "event_haranir_legends", questID = 89268, title = "Lost Legends", category = "events", zone = "Harandar", icon = "Interface\\Icons\\INV_Misc_Rune_15", eventGroup = "haranir", isSubQuest = true,
      description = "Select a relic at the Reliquary of the Zur'ashar." },

    { catalogKey = "event_stormarion", questID = 93892, title = "Midnight: Stormarion Assault", category = "events", zone = "Voidstorm", icon = "Interface\\Icons\\Ability_Warrior_Charge", eventGroup = "stormarion",
      description = "Defend the Singularity Anchor during Stormarion Assault." },
}

local LOOKUP = {}
local CATALOG_KEY_LOOKUP = {}
local TITLE_PATTERNS = {}

for i = 1, #ENTRIES do
    local entry = ENTRIES[i]
    if entry.catalogKey then
        CATALOG_KEY_LOOKUP[entry.catalogKey] = entry
    end
    if entry.questID then
        LOOKUP[entry.questID] = entry
        if entry.alternateIDs then
            for ai = 1, #entry.alternateIDs do
                LOOKUP[entry.alternateIDs[ai]] = entry
            end
        end
    end
    if entry.discoverByTitle and entry.titlePattern and entry.catalogKey then
        TITLE_PATTERNS[#TITLE_PATTERNS + 1] = entry
    end
end

local EVENT_GROUP_ORDER = { soiree = 1, abundance = 2, haranir = 3, stormarion = 4 }

local function EntryMatchesCategory(entry, categoryKey)
    return entry and entry.category == categoryKey and entry.catalogKey and not entry.isSubQuest
end

ns.MidnightQuestCatalog = {
    GetEntries = function() return ENTRIES end,
    GetLookup = function() return LOOKUP end,
    GetCatalogKeyLookup = function() return CATALOG_KEY_LOOKUP end,
    GetTitlePatterns = function() return TITLE_PATTERNS end,
    GetEventGroupOrder = function() return EVENT_GROUP_ORDER end,

    --- Selectable catalog rows for Weekly Progress picker (excludes sub-quests; includes title-pattern rows).
  ---@param categoryKey string weeklyQuests | events | ...
    GetSelectableForCategory = function(categoryKey)
        local out = {}
        for i = 1, #ENTRIES do
            local e = ENTRIES[i]
            if EntryMatchesCategory(e, categoryKey) then
                out[#out + 1] = e
            end
        end
        return out
    end,

    ResolveByTitlePattern = function(questTitle)
        if not questTitle or questTitle == "" or (issecretvalue and issecretvalue(questTitle)) then
            return nil
        end
        local lower = questTitle:lower()
        for i = 1, #TITLE_PATTERNS do
            local p = TITLE_PATTERNS[i]
            if p.titlePattern and lower:find(p.titlePattern, 1, true) then
                return p
            end
        end
        return nil
    end,
}
