--[[
    Curated Midnight weekly / content-event quests (DailyQuestManager + Weekly Progress picker).
    weeklyQuests = emissary-style weeklies (Spark, World Boss, delves, Omnium Folio, etc.)
    events = Content Events (Soiree, Abundance, Haranir, Stormarion)
    World quests: live map scan (ReminderMidnightWorldQuestData for Set Alert).
    catalogKey = stable id for trackedCatalogKeys on daily_quests plans.
    minInterface = first client interface where the objective is live (omit = always available).
    coreWeekly = recommended "do this week" objective for default tracking preset.
    Title-pattern rows match quest log when quest IDs rotate weekly.
]]

local ADDON_NAME, ns = ...

local CORE_INTERFACE = (ns.Constants and ns.Constants.CURRENT_EXPANSION_INTERFACE) or 120007

local function GetClientInterface()
    local ok, _, _, interfaceVersion = pcall(GetBuildInfo)
    if not ok then return 0 end
    return tonumber(interfaceVersion) or 0
end

local function IsEntryAvailable(entry)
    if not entry or entry.selectable == false then return false end
    local iface = GetClientInterface()
    if entry.minInterface and iface > 0 and iface < entry.minInterface then
        return false
    end
    if entry.maxInterface and iface > entry.maxInterface then
        return false
    end
    return true
end

local ENTRIES = {
    -- Core weeklies (Midnight 12.0.1+ live)
    { catalogKey = "spark_radiance", questID = 93942, title = "Spark of Radiance", category = "weeklyQuests", zone = "Silvermoon",
      icon = "Interface\\Icons\\INV_10_Jewelcrafting_Gem3Primal_Fire_Cut_Green", sortOrder = 10, coreWeekly = true,
      description = "Weekly Spark of Radiance from Lady Liadrin (professions)." },
    { catalogKey = "midnight_world_quests", questID = 93766, title = "Midnight: World Quests", category = "weeklyQuests", zone = "Quel'Thalas",
      icon = "Interface\\Icons\\worldquest-icon", sortOrder = 20, coreWeekly = true,
      description = "Complete 6 world quests in Midnight zones." },
    { catalogKey = "midnight_world_tour", questID = 95245, title = "Midnight: World Tour", category = "weeklyQuests", zone = "Quel'Thalas",
      icon = "Interface\\Icons\\INV_Misc_Map_01", sortOrder = 30, coreWeekly = true,
      description = "Complete all four zone events: Soiree, Abundance, Haranir, Stormarion." },
    { catalogKey = "midnight_world_boss", questID = 93913, title = "Midnight: World Boss", category = "weeklyQuests", zone = "Quel'Thalas",
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", sortOrder = 40, coreWeekly = true,
      description = "Defeat the weekly world boss in Quel'Thalas." },
    { catalogKey = "bountiful_delves", questID = 93909, title = "Midnight: Delves", category = "weeklyQuests", zone = "Silvermoon",
      icon = "Interface\\Icons\\INV_Misc_Bag_33", sortOrder = 50, coreWeekly = true,
      description = "Complete 3 Delves in Midnight (weekly)." },
    { catalogKey = "cracked_keystone", questID = 92600, title = "Cracked Keystone", category = "weeklyQuests", zone = "Silvermoon",
      icon = "Interface\\Icons\\INV_Keystone", sortOrder = 60, coreWeekly = true,
      description = "Complete a Tier 11 Bountiful Delve for a Crested Keystone." },

    -- Rotating / title-match weeklies
    { catalogKey = "timewalking_path", discoverByTitle = true, titlePattern = "path through time", category = "weeklyQuests", zone = "Silvermoon",
      icon = "Interface\\Icons\\INV_Misc_Pocketwatch_01", sortOrder = 70,
      title = "Timewalking: Path Through Time", description = "Turbulent Timeways weekly (5 timewalking dungeons or 4 raid bosses)." },

    -- Patch 12.0.7 (Revelations) -- gated until client interface >= 120007
    { catalogKey = "omnium_folio", discoverByTitle = true, titlePattern = "seeking knowledge", category = "weeklyQuests", zone = "Silvermoon",
      icon = "Interface\\Icons\\INV_Misc_Book_09", sortOrder = 80, coreWeekly = true, minInterface = 120007,
      title = "Seeking Knowledge (Omnium Folio)", description = "Sunstrider Omnium weekly rune progress (rotating chapter)." },
    { catalogKey = "ritual_site_studies", discoverByTitle = true, titlePattern = "ritual site studies", category = "weeklyQuests", zone = "Quel'Thalas",
      icon = "Interface\\Icons\\Achievement_General", sortOrder = 90, minInterface = 120007,
      title = "Ritual Site Studies", description = "Complete Tier 6 Ritual Sites with the active weekly challenge." },
    { catalogKey = "sporefall_rotmire", questID = 96746, title = "Sporefall: Rotmire", category = "weeklyQuests", zone = "Harandar",
      icon = "Interface\\Icons\\Ability_Druid_MasterShapeshifter", sortOrder = 100, coreWeekly = true, minInterface = 120007,
      description = "Defeat Rotmire in the Sporefall raid (weekly reward)." },

    -- Omnium Folio week quest IDs (lookup only -- one active chapter at a time)
    { catalogKey = "omnium_folio", questID = 96410, category = "weeklyQuests", selectable = false },
    { catalogKey = "omnium_folio", questID = 96441, category = "weeklyQuests", selectable = false },
    { catalogKey = "omnium_folio", questID = 96442, category = "weeklyQuests", selectable = false },
    { catalogKey = "omnium_folio", questID = 96443, category = "weeklyQuests", selectable = false },
    { catalogKey = "omnium_folio", questID = 96444, category = "weeklyQuests", selectable = false },

    -- Content events (weekly zone events)
    { catalogKey = "event_soiree", questID = 93889, title = "Midnight: Saltheril's Soiree", category = "events", zone = "Eversong Woods",
      icon = "Interface\\Icons\\INV_Misc_Food_164_Fish_Seadog", eventGroup = "soiree", sortOrder = 10, coreWeekly = true,
      description = "Earn favor with a Silvermoon Court faction at Saltheril's Soiree." },
    { catalogKey = "event_soiree_favor", questID = 89289, title = "Favor of the Court", category = "events", zone = "Eversong Woods",
      icon = "Interface\\Icons\\INV_Misc_Note_06", eventGroup = "soiree", isSubQuest = true,
      description = "Pick an ally faction to invite to the Soiree." },
    { catalogKey = "event_soiree_runestones", questID = 90573, title = "Fortify the Runestones", category = "events", zone = "Eversong Woods",
      icon = "Interface\\Icons\\Spell_Arcane_PortalSilvermoon", eventGroup = "soiree", isSubQuest = true, alternateIDs = {90574, 90575, 90576},
      description = "Charge and defend a Runestone (faction-specific)." },

    { catalogKey = "event_abundance", questID = 93890, title = "Midnight: Abundance", category = "events", zone = "Zul'Aman",
      icon = "Interface\\Icons\\INV_Misc_Herb_AncientLichen", eventGroup = "abundance", sortOrder = 20, coreWeekly = true,
      description = "Treasure cave sprint -- donate points to Dundun's altars." },
    { catalogKey = "event_abundance_offerings", questID = 89507, title = "Abundant Offerings", category = "events", zone = "Zul'Aman",
      icon = "Interface\\Icons\\INV_Misc_Coin_02", eventGroup = "abundance", isSubQuest = true,
      description = "Accumulate 20,000 treasure points across Abundance runs." },

    { catalogKey = "event_haranir", questID = 93891, title = "Midnight: Legends of the Haranir", category = "events", zone = "Harandar",
      icon = "Interface\\Icons\\INV_Misc_Book_09", eventGroup = "haranir", sortOrder = 30, coreWeekly = true,
      description = "Complete one Hara'ti relic scenario (warband weekly pick)." },
    { catalogKey = "event_haranir_legends", questID = 89268, title = "Lost Legends", category = "events", zone = "Harandar",
      icon = "Interface\\Icons\\INV_Misc_Rune_15", eventGroup = "haranir", isSubQuest = true,
      description = "Select a relic at the Reliquary of the Zur'ashar." },

    { catalogKey = "event_stormarion", questID = 93892, title = "Midnight: Stormarion Assault", category = "events", zone = "Voidstorm",
      icon = "Interface\\Icons\\Ability_Warrior_Charge", eventGroup = "stormarion", sortOrder = 40, coreWeekly = true,
      description = "Defend the Singularity Anchor during Stormarion Assault." },
}

local LOOKUP = {}
local CATALOG_KEY_LOOKUP = {}
local TITLE_PATTERNS = {}

for i = 1, #ENTRIES do
    local entry = ENTRIES[i]
    if entry.catalogKey and entry.selectable ~= false and (entry.title or entry.discoverByTitle) and not entry.isSubQuest then
        if not CATALOG_KEY_LOOKUP[entry.catalogKey] or (entry.sortOrder and not CATALOG_KEY_LOOKUP[entry.catalogKey].sortOrder) then
            CATALOG_KEY_LOOKUP[entry.catalogKey] = entry
        end
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

local function EntryMatchesCategory(entry, categoryKey)
    return entry and entry.category == categoryKey and entry.catalogKey and not entry.isSubQuest and entry.selectable ~= false
end

local function SortSelectableEntries(a, b)
    local oa = a.sortOrder or 999
    local ob = b.sortOrder or 999
    if oa ~= ob then return oa < ob end
    return (a.title or a.catalogKey or "") < (b.title or b.catalogKey or "")
end

ns.MidnightQuestCatalog = {
    CORE_INTERFACE = CORE_INTERFACE,
    GetClientInterface = GetClientInterface,
    IsEntryAvailable = IsEntryAvailable,

    GetEntries = function() return ENTRIES end,
    GetLookup = function() return LOOKUP end,
    GetCatalogKeyLookup = function() return CATALOG_KEY_LOOKUP end,
    GetTitlePatterns = function() return TITLE_PATTERNS end,
    GetEventGroupOrder = function()
        return { soiree = 1, abundance = 2, haranir = 3, stormarion = 4 }
    end,

    --- Selectable rows for Weekly Progress picker (respects minInterface; excludes sub-quests).
    GetSelectableForCategory = function(categoryKey, opts)
        opts = opts or {}
        local includeUpcoming = opts.includeUpcoming == true
        local out = {}
        for i = 1, #ENTRIES do
            local e = ENTRIES[i]
            if EntryMatchesCategory(e, categoryKey) then
                if includeUpcoming or IsEntryAvailable(e) then
                    out[#out + 1] = e
                end
            end
        end
        table.sort(out, SortSelectableEntries)
        return out
    end,

    GetCoreWeeklyCatalogKeys = function()
        local keys = {}
        for i = 1, #ENTRIES do
            local e = ENTRIES[i]
            if e.coreWeekly and e.catalogKey and EntryMatchesCategory(e, e.category) and IsEntryAvailable(e) then
                keys[e.catalogKey] = true
            end
        end
        return keys
    end,

    ResolveByTitlePattern = function(questTitle)
        if not questTitle or questTitle == "" or (issecretvalue and issecretvalue(questTitle)) then
            return nil
        end
        local lower = questTitle:lower()
        for i = 1, #TITLE_PATTERNS do
            local p = TITLE_PATTERNS[i]
            if p.titlePattern and lower:find(p.titlePattern, 1, true) and IsEntryAvailable(p) then
                return p
            end
        end
        return nil
    end,
}
