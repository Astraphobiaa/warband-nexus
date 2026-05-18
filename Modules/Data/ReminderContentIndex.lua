--[[
    Single source of truth for reminder zone-picker rows (all catalogued expansion / continent sections).

    Fields per row:
      key           — stable maintainer id (unique globally across all sections)
      uiMapID       — canonical picker id (zone_enter matching uses NormalizeToCanonicalPickerMap so subfloors resolve here)
      mapType       — Blizzard UiMap.Type / Enum.UIMapType (0–6) from DB2; drives picker band with raid/delve overrides
      group         — picker band: regions | micro | delves | dungeons | raids | orphan (see GROUP_ORDER)
      contentKind   — curated tag (zone/raid/dungeon/delve/micro/orphan/…); raids/delves kept when Type=Dungeon
      journalID     — optional JournalInstance.ID when known (EJ_GetInstanceForMap(uiMapID) at runtime;
                      see https://warcraft.wiki.gg/wiki/API_EJ_GetInstanceForMap). Nil = derive via Resolve only.

    uiMapIDs cross-checked where available against https://warcraft.wiki.gg/wiki/UiMapID (table + patch notes).
    When that table lags (e.g. Midnight / post-11.x ids not listed yet), https://wago.tools/maps/worldmap/{id} titles
    were used as a secondary datamine cross-check (May 2026 audit).
    Main-floor policy: one canonical uiMapID per location (lowest ID in the DB2 name cluster for that instance).
    Do not list interior wings/subfloors (e.g. Mechagon 1491+ — only 1490 dungeon + 1462 zone). Use alternateUIMapIDs
    when the client reports a different floor id for the same picker row (Ny'alotha 2379 + 1580-1582, Nerub'ar 2291 + 2298).
    Duplicate prevention: Validate() checks unique key + unique uiMapID globally (+ optional journalID globally when set).
    Offline parity: python _ignored/scripts/audit_reminder_content_index.py (structural Validate rules).
    External cross-check (all uiMapIDs vs wago.tools titles): python _ignored/scripts/audit_reminder_content_index_external.py
    → writes _ignored/audit_reminder_content_index_report.txt
    ReminderZoneCatalog sections use pickerGroups built here (no parallel id lists).

    Deduplication policy (Kalimdor / Eastern Kingdoms vs classic expansions):
    - Global rule: each uiMapID appears in at most one section (Validate()).
    - Continent tabs add Classic/Vanilla-style dungeons & raids whose **main-floor** id is **not** used
      anywhere else in this file (see BC / Wrath / Cataclysm / MoP rows for the same world spaces).
    - If an instance is already indexed under an expansion tab (e.g. Deadmines 291 under Cataclysm,
      Onyxia 248 under Wrath, Scarlet Monastery wings under Cataclysm), **do not duplicate** — use that tab.
    - Cataclysm surface zones (e.g. Hyjal 198, Deepholm 207, Uldum 249, Twilight Highlands 241) stay
      under REMINDER_ZONE_CAT_CATA only, not repeated on continent buckets.
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

ns.ReminderContentIndex = ns.ReminderContentIndex or {}

---@class ReminderContentRow
---@field key string
---@field uiMapID number
---@field mapType number|nil Enum.UIMapType value from DB2 (0=Cosmic … 6=Orphan)
---@field group string
---@field contentKind string
---@field journalID number|nil
---@field hintKey string|nil optional ns.L key — suffix in picker when C_Map names collide (e.g. Undermine zone vs raid)
---@field alternateUIMapIDs number[]|nil Interior/subfloor ids that Normalize maps to uiMapID (parent chain may not link)

local GROUP_META_MIDNIGHT = {
    regions = { headerKey = "REMINDER_ZONE_CATALOG_REGIONS", kindTag = "zone" },
    micro = { headerKey = "REMINDER_ZONE_MIDNIGHT_WORLD_EVENTS", kindTag = "micro" },
    delves = { headerKey = "REMINDER_ZONE_CATALOG_DELVES", kindTag = "delve" },
    dungeons = { headerKey = "REMINDER_ZONE_CATALOG_DUNGEONS", kindTag = "dungeon" },
    raids = { headerKey = "REMINDER_ZONE_CATALOG_RAIDS", kindTag = "raid" },
    orphan = { headerKey = "REMINDER_ZONE_CATALOG_SCENARIOS", kindTag = "orphan" },
}

--- Generic headers (non-Midnight expansions): micro uses catalog “Areas” string.
local GROUP_META_GENERIC = {
    regions = { headerKey = "REMINDER_ZONE_CATALOG_REGIONS", kindTag = "zone" },
    micro = { headerKey = "REMINDER_ZONE_CATALOG_AREAS", kindTag = "micro" },
    delves = { headerKey = "REMINDER_ZONE_CATALOG_DELVES", kindTag = "delve" },
    dungeons = { headerKey = "REMINDER_ZONE_CATALOG_DUNGEONS", kindTag = "dungeon" },
    raids = { headerKey = "REMINDER_ZONE_CATALOG_RAIDS", kindTag = "raid" },
    orphan = { headerKey = "REMINDER_ZONE_CATALOG_SCENARIOS", kindTag = "orphan" },
}

--- Midnight / Quel'Thalas (apiRoot 2537): curated picker ids only.
local MIDNIGHT = {
    -- Regions (surface uiMapIDs under apiRoot 2537 — names from live C_Map at runtime)
    { key = "midnight_region_2424", uiMapID = 2424, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "midnight_region_2395", uiMapID = 2395, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "midnight_region_2437", uiMapID = 2437, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "midnight_region_2405", uiMapID = 2405, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "midnight_region_2413", uiMapID = 2413, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    -- Raids (main-floor uiMapIDs)
    { key = "midnight_raid_2533", uiMapID = 2533, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "midnight_raid_2529", uiMapID = 2529, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "midnight_raid_2531", uiMapID = 2531, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    -- Mythic+ / dungeons
    { key = "midnight_dungeon_2492", uiMapID = 2492, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2433", uiMapID = 2433, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2514", uiMapID = 2514, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2501", uiMapID = 2501, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2511", uiMapID = 2511, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2556", uiMapID = 2556, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2500", uiMapID = 2500, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "midnight_dungeon_2572", uiMapID = 2572, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil, alternateUIMapIDs = { 2573 } }, -- Voidscar Arena (2573 = same client title on wago)
    { key = "midnight_dungeon_2541", uiMapID = 2541, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },

    -- Delves
    { key = "midnight_delve_2502", uiMapID = 2502, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2504", uiMapID = 2504, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2505", uiMapID = 2505, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2506", uiMapID = 2506, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2507", uiMapID = 2507, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2525", uiMapID = 2525, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2528", uiMapID = 2528, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2535", uiMapID = 2535, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "midnight_delve_2545", uiMapID = 2545, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    -- Subfloors use 2577 / 2578 while picker row stays 2547 (DefineZone12 / UiMap dump; parent chain may be 2393).
    { key = "midnight_delve_2547", uiMapID = 2547, mapType = 4, group = "delves", contentKind = "delve", journalID = nil, alternateUIMapIDs = { 2577, 2578 } },

    -- Micro / weekly hubs
    { key = "midnight_region_2510", uiMapID = 2510, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "midnight_micro_2522", uiMapID = 2522, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2526", uiMapID = 2526, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2576", uiMapID = 2576, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2579", uiMapID = 2579, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2580", uiMapID = 2580, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2581", uiMapID = 2581, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2583", uiMapID = 2583, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "midnight_micro_2584", uiMapID = 2584, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
}

--- The War Within — Khaz Algar + Undermine + K'aresh hubs (picker ids; see warcraft.wiki.gg/wiki/UiMapID 11.x rows).
local TWW = {
    { key = "tww_region_2248", uiMapID = 2248, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Khaz Algar
    { key = "tww_region_2214", uiMapID = 2214, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- The Ringing Deeps
    { key = "tww_region_2215", uiMapID = 2215, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Hallowfall
    { key = "tww_region_2255", uiMapID = 2255, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Azj-Kahet
    { key = "tww_region_2339", uiMapID = 2339, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Dornogal
    { key = "tww_region_2371", uiMapID = 2371, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- K'aresh hub
    { key = "tww_region_2346", uiMapID = 2346, mapType = 3, group = "regions", contentKind = "zone", journalID = nil, hintKey = "REMINDER_ZONE_CATALOG_OPEN_WORLD" }, -- Undermine (open world; distinct from 2406 raid floor)

    { key = "tww_raid_2291", uiMapID = 2291, mapType = 4, group = "raids", contentKind = "raid", journalID = nil, alternateUIMapIDs = { 2298 } }, -- Nerub'ar Palace (2298 = zone-type floor, same wago title)
    { key = "tww_raid_2406", uiMapID = 2406, mapType = 4, group = "raids", contentKind = "raid", journalID = nil, hintKey = "REMINDER_ZONE_PICKER_HINT_RAID" }, -- Liberation of Undermine (wiki: Dungeon map type)
    { key = "tww_raid_2460", uiMapID = 2460, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Manaforge Omega (TWW 11.2; main floor 2460)

    { key = "tww_dungeon_2308", uiMapID = 2308, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Priory of the Sacred Flame
    { key = "tww_dungeon_2315", uiMapID = 2315, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Rookery
    { key = "tww_dungeon_2341", uiMapID = 2341, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Stonevault
    { key = "tww_dungeon_2343", uiMapID = 2343, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- City of Threads
    { key = "tww_dungeon_2303", uiMapID = 2303, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Darkflame Cleft
    { key = "tww_dungeon_2359", uiMapID = 2359, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Dawnbreaker
    { key = "tww_dungeon_2335", uiMapID = 2335, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Cinderbrew Meadery
    { key = "tww_dungeon_2387", uiMapID = 2387, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Operation: Floodgate
    { key = "tww_dungeon_2367", uiMapID = 2367, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Vault of Memory
    { key = "tww_dungeon_2368", uiMapID = 2368, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Hall of Awakening
    { key = "tww_dungeon_2373", uiMapID = 2373, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The War Creche

    { key = "tww_delve_2299", uiMapID = 2299, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "tww_delve_2300", uiMapID = 2300, mapType = 4, group = "delves", contentKind = "delve", journalID = nil, hintKey = "REMINDER_ZONE_HINT_DELVE_UIMAP" },
    { key = "tww_delve_2301", uiMapID = 2301, mapType = 4, group = "delves", contentKind = "delve", journalID = nil, hintKey = "REMINDER_ZONE_HINT_DELVE_UIMAP" },
    { key = "tww_delve_2302", uiMapID = 2302, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "tww_delve_2347", uiMapID = 2347, mapType = 4, group = "delves", contentKind = "delve", journalID = nil, hintKey = "REMINDER_ZONE_HINT_DELVE_UIMAP" },
    { key = "tww_delve_2348", uiMapID = 2348, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "tww_delve_2312", uiMapID = 2312, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },
    { key = "tww_delve_2313", uiMapID = 2313, mapType = 4, group = "delves", contentKind = "delve", journalID = nil, hintKey = "REMINDER_ZONE_HINT_DELVE_UIMAP" },
    { key = "tww_delve_2314", uiMapID = 2314, mapType = 4, group = "delves", contentKind = "delve", journalID = nil },

    { key = "tww_region_2369", uiMapID = 2369, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Siren Isle (warcraft.wiki.gg UiMapID: Zone)
    { key = "tww_micro_2375", uiMapID = 2375, mapType = 5, group = "micro", contentKind = "micro", journalID = nil }, -- The Forgotten Tomb
    { key = "tww_dungeon_2396", uiMapID = 2396, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Excavation Site 9 (warcraft.wiki.gg UiMapID: Zone)
    -- 2328 Khaz Algar — Proscenium omitted: same display family as 2248 (wiki); use 2248 + Get ID for Proscenium if needed.
}

--- Dragonflight — Dragon Isles surface + instances (wiki UiMapID 10.x rows).
local DRAGONFLIGHT = {
    { key = "df_region_2022", uiMapID = 2022, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- The Waking Shores
    { key = "df_region_2023", uiMapID = 2023, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Ohn'ahran Plains
    { key = "df_region_2024", uiMapID = 2024, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- The Azure Span
    { key = "df_region_2025", uiMapID = 2025, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Thaldraszus
    { key = "df_region_2112", uiMapID = 2112, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Valdrakken
    { key = "df_region_2133", uiMapID = 2133, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Zaralek Cavern
    { key = "df_region_2118", uiMapID = 2118, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- The Forbidden Reach
    { key = "df_region_2241", uiMapID = 2241, mapType = 3, group = "regions", contentKind = "zone", journalID = nil }, -- Emerald Dream (wiki: "10.2 Dream Tree", UiMapID)
    { key = "df_region_2239", uiMapID = 2239, mapType = 3, group = "regions", contentKind = "zone", journalID = nil, hintKey = "REMINDER_ZONE_CATALOG_OPEN_WORLD", alternateUIMapIDs = { 2268 } }, -- Amirdrassil open-world (2268 = same wago title)

    { key = "df_raid_2125", uiMapID = 2125, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Vault of the Incarnates
    { key = "df_raid_2166", uiMapID = 2166, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Aberrus
    { key = "df_raid_2234", uiMapID = 2234, mapType = 4, group = "raids", contentKind = "raid", journalID = nil, hintKey = "REMINDER_ZONE_PICKER_HINT_RAID" }, -- Amirdrassil raid (same name as 2239 zone in many locales)

    { key = "df_dungeon_2073", uiMapID = 2073, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Azure Vault
    { key = "df_dungeon_2080", uiMapID = 2080, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Neltharus
    { key = "df_dungeon_2082", uiMapID = 2082, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Halls of Infusion (wiki main floor row)
    { key = "df_dungeon_2096", uiMapID = 2096, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Brackenhide Hollow
    { key = "df_dungeon_2093", uiMapID = 2093, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Nokhud Offensive
    { key = "df_dungeon_2094", uiMapID = 2094, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Ruby Life Pools
    { key = "df_dungeon_2097", uiMapID = 2097, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Algeth'ar Academy
    { key = "df_dungeon_2198", uiMapID = 2198, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Dawn of the Infinite
    { key = "df_dungeon_2071", uiMapID = 2071, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Uldaman: Legacy of Tyr

    { key = "df_micro_2085", uiMapID = 2085, mapType = 6, group = "micro", contentKind = "micro", journalID = nil }, -- The Primalist Future
    { key = "df_micro_2199", uiMapID = 2199, mapType = 6, group = "micro", contentKind = "micro", journalID = nil }, -- Tyrhold Reservoir
}

--- Shadowlands (wiki UiMapID 9.x rows; continent apiRoot 1550).
local SHADOWLANDS = {
    { key = "sl_region_1533", uiMapID = 1533, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_region_1536", uiMapID = 1536, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_region_1525", uiMapID = 1525, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_region_1565", uiMapID = 1565, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_dungeon_1670", uiMapID = 1670, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_region_1543", uiMapID = 1543, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_region_1961", uiMapID = 1961, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "sl_region_1970", uiMapID = 1970, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "sl_raid_1735", uiMapID = 1735, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "sl_raid_1998", uiMapID = 1998, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "sl_raid_2047", uiMapID = 2047, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "sl_dungeon_1663", uiMapID = 1663, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1989", uiMapID = 1989, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Tazavesh (main floor)
    { key = "sl_dungeon_1666", uiMapID = 1666, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1669", uiMapID = 1669, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1674", uiMapID = 1674, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1683", uiMapID = 1683, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1692", uiMapID = 1692, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Spires of Ascension (main floor)
    { key = "sl_dungeon_1675", uiMapID = 1675, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_dungeon_1677", uiMapID = 1677, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- De Other Side (main floor)

    { key = "sl_micro_1619", uiMapID = 1619, mapType = 6, group = "micro", contentKind = "micro", journalID = nil },
    { key = "sl_dungeon_1707", uiMapID = 1707, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "sl_micro_1714", uiMapID = 1714, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
}

--- Battle for Azeroth (wiki 8.x rows). Extra ids (e.g. Chamber of Heart) need Silithus / Kalimdor roots in ReminderZoneCatalog.apiRoots.
local BFA = {
    { key = "bfa_region_862", uiMapID = 862, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_863", uiMapID = 863, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_864", uiMapID = 864, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_895", uiMapID = 895, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_896", uiMapID = 896, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_942", uiMapID = 942, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_1161", uiMapID = 1161, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_1165", uiMapID = 1165, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_1355", uiMapID = 1355, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_region_1462", uiMapID = 1462, mapType = 3, group = "regions", contentKind = "zone", journalID = nil, hintKey = "REMINDER_ZONE_HINT_MECHAGON_ISLAND" }, -- Mechagon Island (open world; dungeon = 1490)

    { key = "bfa_raid_1148", uiMapID = 1148, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bfa_raid_1358", uiMapID = 1358, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bfa_raid_1512", uiMapID = 1512, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bfa_raid_1345", uiMapID = 1345, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Crucible of Storms (main floor)
    { key = "bfa_raid_2379", uiMapID = 2379, mapType = 4, group = "raids", contentKind = "raid", journalID = nil, alternateUIMapIDs = { 1580, 1581, 1582 } }, -- Ny'alotha, the Waking City (main); 1580-1582 = instance floors

    { key = "bfa_dungeon_934", uiMapID = 934, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_936", uiMapID = 936, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_975", uiMapID = 975, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1004", uiMapID = 1004, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1010", uiMapID = 1010, mapType = 3, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The MOTHERLODE!! (entrance uiMap)
    { key = "bfa_dungeon_1015", uiMapID = 1015, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1038", uiMapID = 1038, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1040", uiMapID = 1040, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1042", uiMapID = 1042, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Underrot (main floor)
    { key = "bfa_dungeon_1162", uiMapID = 1162, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_dungeon_1490", uiMapID = 1490, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil, hintKey = "REMINDER_ZONE_PICKER_HINT_DUNGEON" }, -- Operation: Mechagon (main floor; zone = 1462 Mechagon Island)

    { key = "bfa_dungeon_1021", uiMapID = 1021, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bfa_region_1036", uiMapID = 1036, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bfa_micro_1469", uiMapID = 1469, mapType = 6, group = "micro", contentKind = "micro", journalID = nil },
}

--- Legion (wiki 7.x rows).
local LEGION = {
    { key = "legion_region_630", uiMapID = 630, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_634", uiMapID = 634, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_641", uiMapID = 641, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_650", uiMapID = 650, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_680", uiMapID = 680, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_790", uiMapID = 790, mapType = 3, group = "regions", contentKind = "zone", journalID = nil, hintKey = "REMINDER_ZONE_PICKER_HINT_DUNGEON" }, -- Eye of Azshara (zone); dungeon map = 713
    { key = "legion_region_646", uiMapID = 646, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_830", uiMapID = 830, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_882", uiMapID = 882, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_region_885", uiMapID = 885, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "legion_dungeon_627", uiMapID = 627, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },

    { key = "legion_raid_777", uiMapID = 777, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "legion_raid_806", uiMapID = 806, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "legion_raid_767", uiMapID = 767, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "legion_raid_852", uiMapID = 852, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "legion_raid_909", uiMapID = 909, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "legion_dungeon_703", uiMapID = 703, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_751", uiMapID = 751, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_706", uiMapID = 706, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_713", uiMapID = 713, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil, hintKey = "REMINDER_ZONE_PICKER_HINT_DUNGEON" }, -- Eye of Azshara instance (790 = open-world zone)
    { key = "legion_dungeon_677", uiMapID = 677, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_733", uiMapID = 733, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Darkheart Thicket (main floor)
    { key = "legion_dungeon_761", uiMapID = 761, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_845", uiMapID = 845, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_749", uiMapID = 749, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_723", uiMapID = 723, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_795", uiMapID = 795, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_dungeon_903", uiMapID = 903, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Seat of the Triumvirate (main floor)
    { key = "legion_dungeon_731", uiMapID = 731, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Neltharion's Lair (main floor)

    { key = "legion_dungeon_734", uiMapID = 734, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "legion_micro_682", uiMapID = 682, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
    { key = "legion_micro_750", uiMapID = 750, mapType = 6, group = "micro", contentKind = "micro", journalID = nil },
}

--- Warlords of Draenor (wiki 6.x rows). Lists only maps under Draenor continent (572); UBRS/Scholomance-style EK instances omitted.
local WOD = {
    { key = "wod_region_525", uiMapID = 525, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_535", uiMapID = 535, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_539", uiMapID = 539, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_542", uiMapID = 542, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_543", uiMapID = 543, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_550", uiMapID = 550, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_534", uiMapID = 534, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wod_region_588", uiMapID = 588, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "wod_raid_610", uiMapID = 610, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wod_raid_596", uiMapID = 596, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wod_raid_661", uiMapID = 661, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Hellfire Citadel (main floor)

    { key = "wod_dungeon_573", uiMapID = 573, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_574", uiMapID = 574, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_593", uiMapID = 593, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_595", uiMapID = 595, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_601", uiMapID = 601, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_620", uiMapID = 620, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wod_dungeon_606", uiMapID = 606, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },

    { key = "wod_micro_578", uiMapID = 578, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
}

--- Mists of Pandaria (wiki 5.x rows). Scholomance (476) needs EK root on the catalog section.
local MOP = {
    { key = "mop_region_371", uiMapID = 371, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_376", uiMapID = 376, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_379", uiMapID = 379, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_388", uiMapID = 388, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_390", uiMapID = 390, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_418", uiMapID = 418, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_422", uiMapID = 422, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "mop_region_433", uiMapID = 433, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "mop_raid_471", uiMapID = 471, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "mop_raid_474", uiMapID = 474, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "mop_raid_456", uiMapID = 456, mapType = 6, group = "raids", contentKind = "raid", journalID = nil },
    { key = "mop_raid_508", uiMapID = 508, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Throne of Thunder (main floor)
    { key = "mop_raid_556", uiMapID = 556, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "mop_dungeon_437", uiMapID = 437, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "mop_dungeon_439", uiMapID = 439, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "mop_dungeon_443", uiMapID = 443, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "mop_dungeon_453", uiMapID = 453, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "mop_dungeon_476", uiMapID = 476, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "mop_dungeon_429", uiMapID = 429, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Temple of the Jade Serpent
{ key = "mop_dungeon_457", uiMapID = 457, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Siege of Niuzao Temple (main floor)

    { key = "mop_micro_392", uiMapID = 392, mapType = 5, group = "micro", contentKind = "micro", journalID = nil },
}

--- Cataclysm (wiki 4.x rows). apiRoots intentionally empty on catalog — parent chains span EK/Kalimdor/Maelstrom; filter allows all rows when apiRoots missing.
local CATACLYSM = {
    { key = "cata_region_198", uiMapID = 198, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_207", uiMapID = 207, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_241", uiMapID = 241, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_249", uiMapID = 249, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_201", uiMapID = 201, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_204", uiMapID = 204, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_205", uiMapID = 205, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "cata_region_203", uiMapID = 203, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "cata_dungeon_283", uiMapID = 283, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Blackrock Caverns
    { key = "cata_raid_285", uiMapID = 285, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "cata_raid_287", uiMapID = 287, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "cata_raid_294", uiMapID = 294, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "cata_raid_367", uiMapID = 367, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "cata_raid_328", uiMapID = 328, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "cata_raid_282", uiMapID = 282, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Baradin Hold
    { key = "cata_raid_409", uiMapID = 409, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "cata_dungeon_291", uiMapID = 291, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "cata_dungeon_293", uiMapID = 293, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "cata_dungeon_301", uiMapID = 301, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "cata_dungeon_302", uiMapID = 302, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "cata_dungeon_322", uiMapID = 322, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Throne of the Tides (main floor)
{ key = "cata_dungeon_324", uiMapID = 324, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Stonecore
{ key = "cata_dungeon_325", uiMapID = 325, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Vortex Pinnacle (main floor)
{ key = "cata_dungeon_297", uiMapID = 297, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Halls of Origination (main floor)
{ key = "cata_dungeon_277", uiMapID = 277, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Lost City of the Tol'vir
{ key = "cata_dungeon_401", uiMapID = 401, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- End Time (main floor)
{ key = "cata_dungeon_399", uiMapID = 399, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Hour of Twilight (main floor)
{ key = "cata_dungeon_398", uiMapID = 398, mapType = 6, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Well of Eternity

    { key = "cata_micro_338", uiMapID = 338, mapType = 6, group = "micro", contentKind = "micro", journalID = nil },
}

--- Wrath of the Lich King (wiki 3.x Northrend rows). Hyjal raid (329) lives in BC only.
local WRATH = {
    { key = "wrath_region_114", uiMapID = 114, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_115", uiMapID = 115, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_116", uiMapID = 116, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_117", uiMapID = 117, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_118", uiMapID = 118, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_119", uiMapID = 119, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_120", uiMapID = 120, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_121", uiMapID = 121, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_123", uiMapID = 123, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "wrath_region_127", uiMapID = 127, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "wrath_raid_162", uiMapID = 162, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_147", uiMapID = 147, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_186", uiMapID = 186, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_141", uiMapID = 141, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_200", uiMapID = 200, mapType = 6, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_155", uiMapID = 155, mapType = 6, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_156", uiMapID = 156, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "wrath_raid_248", uiMapID = 248, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "wrath_dungeon_129", uiMapID = 129, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_132", uiMapID = 132, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_133", uiMapID = 133, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_136", uiMapID = 136, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_138", uiMapID = 138, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_140", uiMapID = 140, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_orphan_142", uiMapID = 142, mapType = 6, group = "orphan", contentKind = "orphan", journalID = nil },
    { key = "wrath_dungeon_154", uiMapID = 154, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_157", uiMapID = 157, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_160", uiMapID = 160, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_168", uiMapID = 168, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_130", uiMapID = 130, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_183", uiMapID = 183, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_dungeon_185", uiMapID = 185, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },

    { key = "wrath_dungeon_125", uiMapID = 125, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "wrath_micro_124", uiMapID = 124, mapType = 6, group = "micro", contentKind = "micro", journalID = nil },
}

--- The Burning Crusade (Outland + Hyjal raid CoT id 329, Sunwell 335; wiki 2.x rows).
local BC = {
    { key = "bc_region_100", uiMapID = 100, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_102", uiMapID = 102, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_104", uiMapID = 104, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_105", uiMapID = 105, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_107", uiMapID = 107, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_108", uiMapID = 108, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_109", uiMapID = 109, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "bc_region_111", uiMapID = 111, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    { key = "bc_raid_330", uiMapID = 330, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_331", uiMapID = 331, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_332", uiMapID = 332, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_334", uiMapID = 334, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_339", uiMapID = 339, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_329", uiMapID = 329, mapType = 6, group = "raids", contentKind = "raid", journalID = nil },
    { key = "bc_raid_335", uiMapID = 335, mapType = 4, group = "raids", contentKind = "raid", journalID = nil },

    { key = "bc_dungeon_347", uiMapID = 347, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_261", uiMapID = 261, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_246", uiMapID = 246, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_262", uiMapID = 262, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_263", uiMapID = 263, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_265", uiMapID = 265, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_266", uiMapID = 266, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_267", uiMapID = 267, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_269", uiMapID = 269, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_272", uiMapID = 272, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_256", uiMapID = 256, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_258", uiMapID = 258, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_dungeon_260", uiMapID = 260, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
    { key = "bc_orphan_273", uiMapID = 273, mapType = 6, group = "orphan", contentKind = "orphan", journalID = nil },
    { key = "bc_orphan_274", uiMapID = 274, mapType = 6, group = "orphan", contentKind = "orphan", journalID = nil },
    { key = "bc_dungeon_348", uiMapID = 348, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil },
}

--- Kalimdor (continent uiMapID 12): overworld regions + Classic-era instances on this continent whose
--- uiMapIDs are exclusive in this index (warcraft.wiki.gg/wiki/UiMapID).
local KALIMDOR = {
    { key = "kal_region_1", uiMapID = 1, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_7", uiMapID = 7, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_10", uiMapID = 10, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_57", uiMapID = 57, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_62", uiMapID = 62, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_63", uiMapID = 63, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_64", uiMapID = 64, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_65", uiMapID = 65, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_66", uiMapID = 66, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_69", uiMapID = 69, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_70", uiMapID = 70, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_71", uiMapID = 71, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_76", uiMapID = 76, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_77", uiMapID = 77, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_78", uiMapID = 78, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_80", uiMapID = 80, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_83", uiMapID = 83, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_85", uiMapID = 85, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_88", uiMapID = 88, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_89", uiMapID = 89, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_97", uiMapID = 97, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_103", uiMapID = 103, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_106", uiMapID = 106, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_1329", uiMapID = 1329, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "kal_region_1321", uiMapID = 1321, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    -- Raids (main-floor / entry uiMapIDs; Onyxia 248 omitted — claimed by Wrath section)
    { key = "kal_raid_232", uiMapID = 232, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Molten Core
    { key = "kal_raid_247", uiMapID = 247, mapType = 6, group = "raids", contentKind = "raid", journalID = nil }, -- Ruins of Ahn'Qiraj
    { key = "kal_raid_319", uiMapID = 319, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Temple of Ahn'Qiraj

    { key = "kal_dungeon_213", uiMapID = 213, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Ragefire Chasm
    { key = "kal_dungeon_279", uiMapID = 279, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Wailing Caverns
    { key = "kal_dungeon_221", uiMapID = 221, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Blackfathom Deeps
    { key = "kal_dungeon_220", uiMapID = 220, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Temple of Atal'Hakkar
    { key = "kal_orphan_219", uiMapID = 219, mapType = 6, group = "orphan", contentKind = "orphan", journalID = nil }, -- Zul'Farrak
    { key = "kal_dungeon_300", uiMapID = 300, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Razorfen Downs (Kraul 301 — Cata section)
    { key = "kal_dungeon_280", uiMapID = 280, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Maraudon
    { key = "kal_dungeon_235", uiMapID = 235, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Dire Maul (Gordok Commons)

    { key = "kal_micro_86", uiMapID = 86, mapType = 6, group = "micro", contentKind = "micro", journalID = nil, hintKey = "REMINDER_ZONE_HINT_ORGRIMMAR_CLEFT" }, -- wiki: Orgrimmar — Cleft of Shadow (85 = city)
}

--- Eastern Kingdoms (continent uiMapID 13): overworld regions + Classic-era instances whose uiMapIDs are
--- exclusive here. Scholomance Legacy wings (306+) vs MoP Scholomance (476) — separate ids.
local EASTERN_KINGDOMS = {
    { key = "ek_region_14", uiMapID = 14, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_15", uiMapID = 15, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_17", uiMapID = 17, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_18", uiMapID = 18, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_21", uiMapID = 21, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_22", uiMapID = 22, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_23", uiMapID = 23, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_25", uiMapID = 25, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_26", uiMapID = 26, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_27", uiMapID = 27, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_32", uiMapID = 32, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_36", uiMapID = 36, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_37", uiMapID = 37, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_47", uiMapID = 47, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_48", uiMapID = 48, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_49", uiMapID = 49, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_50", uiMapID = 50, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_51", uiMapID = 51, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_52", uiMapID = 52, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_56", uiMapID = 56, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_84", uiMapID = 84, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_87", uiMapID = 87, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_90", uiMapID = 90, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_94", uiMapID = 94, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_95", uiMapID = 95, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_110", uiMapID = 110, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_region_122", uiMapID = 122, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },
    { key = "ek_orphan_179", uiMapID = 179, mapType = 6, group = "orphan", contentKind = "orphan", journalID = nil },
    { key = "ek_region_210", uiMapID = 210, mapType = 3, group = "regions", contentKind = "zone", journalID = nil },

    -- Raids (Karazhan / Zul'Aman — BC tab holds Sunwell 335 & Magisters' Terrace 348; BWL uses Cata id 287)
    { key = "ek_raid_350", uiMapID = 350, mapType = 4, group = "raids", contentKind = "raid", journalID = nil }, -- Karazhan
    { key = "ek_raid_333", uiMapID = 333, mapType = 6, group = "raids", contentKind = "raid", journalID = nil }, -- Zul'Aman

    { key = "ek_dungeon_225", uiMapID = 225, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- The Stockade
    { key = "ek_dungeon_226", uiMapID = 226, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Gnomeregan
    { key = "ek_dungeon_230", uiMapID = 230, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Uldaman
    { key = "ek_dungeon_306", uiMapID = 306, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Scholomance (Classic)
    { key = "ek_dungeon_310", uiMapID = 310, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Shadowfang Keep
    { key = "ek_dungeon_317", uiMapID = 317, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Stratholme
    { key = "ek_dungeon_242", uiMapID = 242, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Blackrock Depths
    { key = "ek_dungeon_250", uiMapID = 250, mapType = 4, group = "dungeons", contentKind = "dungeon", journalID = nil }, -- Blackrock Spire
}

--- Row arrays in Validate() order — single list for shared scans (delve set, etc.).
local SECTION_ROW_TABLES = {
    MIDNIGHT, TWW, DRAGONFLIGHT, SHADOWLANDS, BFA, LEGION, WOD, MOP,
    CATACLYSM, WRATH, BC, KALIMDOR, EASTERN_KINGDOMS,
}

--- UiMapIDs we curate under Delves; live client often uses UIMapType.Dungeon for these interiors.
local delveUiMapIDSet = {}
--- Every uiMapID listed in SECTION_ROW_TABLES (picker / zone reminder canonical rows).
local pickerCanonicalUIMapSet = {}
--- Extra client map ids → canonical picker uiMapID (see alternateUIMapIDs on rows).
local pickerAlternateToCanonical = {}
do
    for si = 1, #SECTION_ROW_TABLES do
        local rows = SECTION_ROW_TABLES[si]
        for ri = 1, #rows do
            local e = rows[ri]
            if e then
                local id = tonumber(e.uiMapID)
                if id then
                    pickerCanonicalUIMapSet[id] = true
                    if e.group == "delves" or e.contentKind == "delve" then
                        delveUiMapIDSet[id] = true
                    end
                end
                if type(e.alternateUIMapIDs) == "table" and id then
                    for ai = 1, #e.alternateUIMapIDs do
                        local aid = tonumber(e.alternateUIMapIDs[ai])
                        if aid then
                            pickerAlternateToCanonical[aid] = id
                            if e.group == "delves" or e.contentKind == "delve" then
                                delveUiMapIDSet[aid] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

local function safeParentUIMapID(mid)
    if not mid or mid <= 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mid)
    if not ok or not info then return nil end
    local p = info.parentMapID
    if p == nil or p == 0 then return nil end
    if issecretvalue and issecretvalue(p) then return nil end
    p = tonumber(p)
    if not p or p <= 0 then return nil end
    return p
end

--- First curated picker uiMapID on the parent chain from mapID (child subfloor → canonical row), else mapID.
---@param mapID number
---@return number|nil
function ns.ReminderContentIndex.NormalizeToCanonicalPickerMap(mapID)
    local mid = tonumber(mapID)
    if not mid or mid <= 0 then return nil end
    if issecretvalue and issecretvalue(mid) then return nil end
    local canonAlt = pickerAlternateToCanonical[mid]
    if canonAlt then return canonAlt end
    local guard = 0
    local cur = mid
    while cur and cur > 0 and guard < 64 do
        guard = guard + 1
        if pickerCanonicalUIMapSet[cur] then return cur end
        cur = safeParentUIMapID(cur)
    end
    return mid
end

--- Collapse only explicit alternateUIMapIDs (e.g. delve 2577→2547). Does not walk the picker parent chain;
--- zone reminders use this plus C_Map parents separately so capitals (84) still match district micro-maps.
---@param mapID number
---@return number|nil
function ns.ReminderContentIndex.CollapseAlternateUIMapOnly(mapID)
    local mid = tonumber(mapID)
    if not mid or mid <= 0 then return nil end
    if issecretvalue and issecretvalue(mid) then return nil end
    local canonAlt = pickerAlternateToCanonical[mid]
    if canonAlt then return canonAlt end
    return mid
end

---@param mapID number
---@return boolean
function ns.ReminderContentIndex.IsCanonicalPickerUIMap(mapID)
    local mid = tonumber(mapID)
    if not mid then return false end
    return pickerCanonicalUIMapSet[mid] == true
end

--- Used by UIMapContentKind.Resolve when mapType is Dungeon but row is a delve.
---@param mapID number
---@return boolean
function ns.ReminderContentIndex.IsDelveUIMap(mapID)
    local mid = tonumber(mapID)
    if not mid then return false end
    return delveUiMapIDSet[mid] == true
end

-- Picker order follows Enum.UIMapType geography: continent/zone → micro → delves → dungeons → raids → orphan.
local GROUP_ORDER = { "regions", "micro", "delves", "dungeons", "raids", "orphan" }

---@param rows table[]
---@param groupMeta table<string, { headerKey: string, kindTag: string }>
---@return table[]
local function sortPickerBucketIds(ids)
    table.sort(ids, function(a, b)
        local na = type(a) == "table" and tonumber(a.id) or tonumber(a)
        local nb = type(b) == "table" and tonumber(b.id) or tonumber(b)
        na = na or 0
        nb = nb or 0
        return na < nb
    end)
end

local function buildPickerGroupsFromRows(rows, groupMeta)
    local byGroup = {}
    for gi = 1, #GROUP_ORDER do
        byGroup[GROUP_ORDER[gi]] = {}
    end
    local L = ns.L
    for i = 1, #rows do
        local e = rows[i]
        local g = e.group
        local bucket = byGroup[g]
        if bucket and e.uiMapID then
            local mid = tonumber(e.uiMapID)
            local hk = e.hintKey
            local hint = nil
            if hk and hk ~= "" and L and L[hk] and L[hk] ~= "" then
                if hk == "REMINDER_ZONE_HINT_DELVE_UIMAP" then
                    hint = string.format(L[hk], mid)
                else
                    hint = L[hk]
                end
            end
            if hint then
                bucket[#bucket + 1] = { id = mid, hint = hint }
            else
                bucket[#bucket + 1] = mid
            end
        end
    end
    for gi = 1, #GROUP_ORDER do
        local gname = GROUP_ORDER[gi]
        local ids = byGroup[gname]
        if ids then
            sortPickerBucketIds(ids)
        end
    end

    local out = {}
    for gi = 1, #GROUP_ORDER do
        local gname = GROUP_ORDER[gi]
        local meta = groupMeta[gname]
        local ids = byGroup[gname]
        if meta and ids and #ids > 0 then
            out[#out + 1] = {
                headerKey = meta.headerKey,
                kindTag = meta.kindTag,
                ids = ids,
            }
        end
    end
    return out
end

--- Global uniqueness: keys + uiMapIDs across all curated expansion/continent tables; journalID unique when set (global).
---@return string|nil err
function ns.ReminderContentIndex.Validate()
    local seenKey = {}
    ---@type table<number, string> first key that claimed each uiMapID
    local seenMap = {}
    ---@type table<number, string> first key that claimed each alternateUIMapIDs entry
    local seenAlternate = {}
    local seenJournal = {}

    local function consumeRows(rows, label)
        for i = 1, #rows do
            local e = rows[i]
            if not e.key or e.key == "" then
                return "empty key in " .. label .. " at " .. tostring(i)
            end
            if seenKey[e.key] then
                return "duplicate key " .. e.key .. " (" .. label .. ")"
            end
            seenKey[e.key] = true

            local mid = tonumber(e.uiMapID)
            if not mid or mid <= 0 then
                return "bad uiMapID for " .. e.key .. " (" .. label .. ")"
            end
            if seenMap[mid] then
                return "duplicate uiMapID " .. tostring(mid) .. " (" .. label .. ", also " .. seenMap[mid] .. ")"
            end
            seenMap[mid] = e.key

            if type(e.alternateUIMapIDs) == "table" then
                for ai = 1, #e.alternateUIMapIDs do
                    local aid = tonumber(e.alternateUIMapIDs[ai])
                    if not aid or aid <= 0 then
                        return "bad alternateUIMapIDs entry for " .. e.key .. " (" .. label .. ")"
                    end
                    if aid == mid then
                        return "alternateUIMapIDs duplicates primary uiMapID for " .. e.key .. " (" .. label .. ")"
                    end
                    if seenMap[aid] then
                        return "alternate uiMapID " .. tostring(aid) .. " conflicts with primary row " .. seenMap[aid] .. " (" .. label .. ")"
                    end
                    if seenAlternate[aid] then
                        return "duplicate alternate uiMapID " .. tostring(aid) .. " (" .. label .. ", also " .. seenAlternate[aid] .. ")"
                    end
                    seenAlternate[aid] = e.key
                end
            end

            local jid = e.journalID ~= nil and tonumber(e.journalID) or nil
            if jid and jid > 0 then
                if seenJournal[jid] then
                    return "duplicate journalID " .. tostring(jid) .. " (" .. label .. ")"
                end
                seenJournal[jid] = true
            end
        end
        return nil
    end

    local err = consumeRows(MIDNIGHT, "Midnight")
    if err then return err end
    err = consumeRows(TWW, "TWW")
    if err then return err end
    err = consumeRows(DRAGONFLIGHT, "Dragonflight")
    if err then return err end
    err = consumeRows(SHADOWLANDS, "Shadowlands")
    if err then return err end
    err = consumeRows(BFA, "BFA")
    if err then return err end
    err = consumeRows(LEGION, "Legion")
    if err then return err end
    err = consumeRows(WOD, "WoD")
    if err then return err end
    err = consumeRows(MOP, "MoP")
    if err then return err end
    err = consumeRows(CATACLYSM, "Cataclysm")
    if err then return err end
    err = consumeRows(WRATH, "Wrath")
    if err then return err end
    err = consumeRows(BC, "BC")
    if err then return err end
    err = consumeRows(KALIMDOR, "Kalimdor")
    if err then return err end
    err = consumeRows(EASTERN_KINGDOMS, "EasternKingdoms")
    if err then return err end

    return nil
end

---@return table[] rows readonly MIDNIGHT list
function ns.ReminderContentIndex.GetMidnightRows()
    return MIDNIGHT
end

---@return table[] rows readonly TWW list
function ns.ReminderContentIndex.GetTWWRows()
    return TWW
end

---@return table[] rows readonly Dragonflight list
function ns.ReminderContentIndex.GetDragonflightRows()
    return DRAGONFLIGHT
end

--- Builds ReminderZoneCatalog `pickerGroups` shape for Midnight section.
---@return table[]
function ns.ReminderContentIndex.BuildMidnightPickerGroups()
    return buildPickerGroupsFromRows(MIDNIGHT, GROUP_META_MIDNIGHT)
end

--- Builds ReminderZoneCatalog `pickerGroups` shape for The War Within section.
---@return table[]
function ns.ReminderContentIndex.BuildTWWPickerGroups()
    return buildPickerGroupsFromRows(TWW, GROUP_META_GENERIC)
end

--- Builds ReminderZoneCatalog `pickerGroups` shape for Dragonflight section.
---@return table[]
function ns.ReminderContentIndex.BuildDragonflightPickerGroups()
    return buildPickerGroupsFromRows(DRAGONFLIGHT, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildShadowlandsPickerGroups()
    return buildPickerGroupsFromRows(SHADOWLANDS, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildBFAPickerGroups()
    return buildPickerGroupsFromRows(BFA, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildLegionPickerGroups()
    return buildPickerGroupsFromRows(LEGION, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildWoDPickerGroups()
    return buildPickerGroupsFromRows(WOD, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildMOPPickerGroups()
    return buildPickerGroupsFromRows(MOP, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildCataclysmPickerGroups()
    return buildPickerGroupsFromRows(CATACLYSM, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildWrathPickerGroups()
    return buildPickerGroupsFromRows(WRATH, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildBCPickerGroups()
    return buildPickerGroupsFromRows(BC, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildKalimdorPickerGroups()
    return buildPickerGroupsFromRows(KALIMDOR, GROUP_META_GENERIC)
end

function ns.ReminderContentIndex.BuildEasternKingdomsPickerGroups()
    return buildPickerGroupsFromRows(EASTERN_KINGDOMS, GROUP_META_GENERIC)
end

do
    local err = ns.ReminderContentIndex.Validate()
    if err and ns.DebugPrint then
        ns.DebugPrint("ReminderContentIndex.Validate failed:", err)
    end
end
