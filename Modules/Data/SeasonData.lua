--[[
    Warband Nexus - Season-scoped gearing data (crests, upgrade tracks, key currencies).

    Why this file exists: crest currency IDs, upgrade-track ilvls and "key currency"
    highlights all roll over every season. Before this, they were hardcoded in
    Constants.lua / GearService_UpgradeTracks.lua / GearService.lua and went stale
    the moment a season flipped. Now every season is one entry in SEASONS below and
    the rest of the addon reads whichever one is active.

    Contract for consumers: NEVER reassign the tables you get from a rebuild callback.
    GearService and friends capture them as chunk-level locals at load time, so a
    season switch must mutate them in place (table.wipe + refill).

    Loaded after Modules\Constants.lua, before Modules\GearService_UpgradeTracks.lua.
]]

local _, ns = ...

local SeasonData = {}
ns.SeasonData = SeasonData

-- SEASON TABLES
--
-- trackIlvls: full rank progression per upgrade track. Adjacent tracks overlap so the
--   last ranks of track N equal the first ranks of track N+1 (the reverse ilvl lookup
--   in GearService_UpgradeTracks resolves overlaps in favour of the higher track).
-- craftedTiers: crafted gear does NOT use the crest track — it recrafts to a tier cap.
--   Ordered high -> low; GearService walks it top-down.

SeasonData.SEASONS = {
    -- MIDNIGHT SEASON 1 (12.0.x) - Dawncrests
    [1] = {
        label = "Midnight Season 1",
        crestPerLevel = 20,
        goldPerLevelCopper = 10 * 10000,
        weeklyCapPerTier = 100,
        crestIDs = {
            Adventurer = 3383,
            Veteran    = 3341,
            Champion   = 3343,
            Hero       = 3345,
            Myth       = 3347,
        },
        crestNames = {
            [3383] = "Adventurer Dawncrest",
            [3341] = "Veteran Dawncrest",
            [3343] = "Champion Dawncrest",
            [3345] = "Hero Dawncrest",
            [3347] = "Myth Dawncrest",
        },
        -- Increment pattern per track: +4, +3, +3, +3, +4
        trackIlvls = {
            Adventurer = { 220, 224, 227, 230, 233, 237 },
            Veteran    = { 233, 237, 240, 243, 246, 250 },
            Champion   = { 246, 250, 253, 256, 259, 263 },
            Hero       = { 259, 263, 266, 269, 272, 276 },
            Myth       = { 272, 276, 279, 282, 285, 289 },
        },
        craftedTiers = {
            { crestID = 3347, name = "Myth",       maxIlvl = 285, cost = 80 },
            { crestID = 3345, name = "Hero",       maxIlvl = 272, cost = 60 },
            { crestID = 3343, name = "Champion",   maxIlvl = 263, cost = 60 },
            { crestID = 3341, name = "Veteran",    maxIlvl = 250, cost = 45 },
            { crestID = 3383, name = "Adventurer", maxIlvl = 237, cost = 30 },
        },
        keyCurrencies = {
            [3378] = { name = "Dawnlight Manaflux", category = "catalyst" },
            [3314] = { name = "Radiant Ember", category = "crest" },
            [3313] = { name = "Radiant Dust", category = "crest" },
            [3312] = { name = "Radiant Shard", category = "crest" },
        },
        -- "Where to farm" tooltip copy. Amount strings mix exact ("10\226\128\14318 / key") and
        -- qualitative ("varies") because Blizzard does not document per-boss / per-tier amounts.
        crestSources = {
            [3383] = {
                "Repeatable Outdoor Events",
                "Tier 4 Delves",
            },
            [3341] = {
                "Hard-Mode Prey events  (~15 / ~7\226\128\13110 min)",
                "Heroic Seasonal Dungeons",
                "Raid Finder bosses",
                "Delves Tier 5\226\128\1316",
                "Trovehunter\226\128\153s Bounty (T4\226\128\1315)",
            },
            [3343] = {
                "Mythic 0 Seasonal Dungeons",
                "Mythic Keystone +2 to +3 (timed)",
                "Normal Raid bosses",
                "Delves Tier 7\226\128\13110",
                "Trovehunter\226\128\153s Bounty (T6\226\128\1317)",
                "Weekly Outdoor Events",
            },
            [3345] = {
                "Mythic Keystone +2 to +6 timed  (10\226\128\13118 / key)",
                "Heroic Raid bosses",
                "Delves Tier 11",
                "Trovehunter\226\128\153s Bounty (T8+)",
            },
            [3347] = {
                "Mythic Keystone +7 and higher  (10\226\128\13120 / key)",
                "Mythic Raid bosses",
                "T11 Bountiful Gilded Stash  (7 / run, up to 3 / week)",
            },
        },
    },

    -- MIDNIGHT SEASON 2 (12.1 "Curse of Ula'tek") - Mistcrests
    -- Season opens 2026-08-18; patch 12.1 shipped 2026-08-11, so both seasons coexist
    -- in the client for a week. ResolveFromAPI below picks the live one at runtime.
    [2] = {
        label = "Midnight Season 2",
        crestPerLevel = 20,
        goldPerLevelCopper = 10 * 10000,
        weeklyCapPerTier = 100,
        -- Currency IDs verified on Wowhead 12.1.0 (currency=3442..3446).
        crestIDs = {
            Adventurer = 3442,
            Veteran    = 3443,
            Champion   = 3444,
            Hero       = 3445,
            Myth       = 3446,
        },
        crestNames = {
            [3442] = "Adventurer Mistcrest",
            [3443] = "Veteran Mistcrest",
            [3444] = "Champion Mistcrest",
            [3445] = "Hero Mistcrest",
            [3446] = "Myth Mistcrest",
        },
        -- REVISED 2026-08-19, and still UNCONFIRMED for Season 2 - read this before trusting it.
        --
        -- What is settled: the table shipped before this was anchored on a reading of
        -- "Champion 6/6 = 292" taken through C_ItemUpgrade.GetItemUpgradeItemInfo(location), and
        -- that function takes NO arguments (Blizzard_APIDocumentationGenerated/
        -- ItemUpgradeDocumentation.lua). It reports whatever sits in the upgrade session, so the
        -- anchor never described the item it was attributed to. That table matched no source.
        --
        -- What is NOT settled: two credible sources disagree about where S2 starts.
        --   Set A (used below): Adventurer 259-276, Veteran 272-289, Champion 285-302,
        --     Hero 298-315, Myth 311-328; season cap 334/337 on special raid loot.
        --     Sources: icy-veins.com/wow/news/item-level-of-loot-in-midnight-season-2 ("a
        --     39-item-level increase from the prior season") and expcarry.com/mistcrest-upgrade-guide.
        --     +39 on every S1 rank reproduces this set exactly, and S1 is verified.
        --   Set B: Champion 292-308, Hero 305-321, Myth 318-334, with ranks past 6 ("Myth 9" =
        --     344 from the last two Mythic bosses). Sources: method.gg/guides/all-midnight-
        --     season-2-upgrade-tracks-and-item-levels and warcraft.wiki.gg/wiki/Midnight_Season_2.
        --     That is +45 on S1, and uses +3/+3/+4/+3/+3 (span 16) instead of S1's span 17.
        -- Set A wins on internal consistency (it is S1's shape and spacing, unchanged), which is
        -- why it is here - but no Season 2 item has actually been observed to settle it.
        --
        -- To settle it, one line in-game (verified signature, warcraft.wiki.gg):
        --   /run C_MythicPlus.RequestMapInfo() for k=2,12 do print(k,C_MythicPlus.GetRewardLevelForDifficultyLevel(k)) end
        -- returns weeklyRewardLevel, endOfRunRewardLevel per keystone level - real S2 numbers that
        -- must land on ranks in whichever set is right.
        --
        -- Do NOT re-verify from a player's SavedVariables unless their gear is Season 2: a
        -- character still in S1 gear (itemIDs below ~270000) produces item levels that fit both
        -- sets, because S2 Adventurer/Veteran overlap S1 Hero/Myth exactly.
        trackIlvls = {
            Adventurer = { 259, 263, 266, 269, 272, 276 },
            Veteran    = { 272, 276, 279, 282, 285, 289 },
            Champion   = { 285, 289, 292, 295, 298, 302 },
            Hero       = { 298, 302, 305, 308, 311, 315 },
            Myth       = { 311, 315, 318, 321, 324, 328 },
        },
        -- Crafted caps follow the S1 shape: Hero/Myth one rank below the track max, lower tracks
        -- at the track max. VERIFY: recraft costs are still carried over from S1, no S2 numbers.
        craftedTiers = {
            { crestID = 3446, name = "Myth",       maxIlvl = 324, cost = 80 },
            { crestID = 3445, name = "Hero",       maxIlvl = 311, cost = 60 },
            { crestID = 3444, name = "Champion",   maxIlvl = 302, cost = 60 },
            { crestID = 3443, name = "Veteran",    maxIlvl = 289, cost = 45 },
            { crestID = 3442, name = "Adventurer", maxIlvl = 276, cost = 30 },
        },
        -- Venomblight Manaflux = S2 catalyst charge (Wowhead 12.1.0 currency=3465).
        -- Spark of Tides and Ascendant Venomstone are NOT listed here: their currency IDs are
        -- not published yet and guessing an ID would silently highlight the wrong row.
        keyCurrencies = {
            [3465] = { name = "Venomblight Manaflux", category = "catalyst" },
        },
        -- VERIFY: farm sources are from 12.1 previews, not final patch notes.
        crestSources = {
            [3442] = {
                "Repeatable Outdoor Events",
                "Tier 4 Delves",
            },
            [3443] = {
                "Heroic Seasonal Dungeons",
                "Raid Finder bosses",
                "Delves Tier 5\226\128\1316",
            },
            [3444] = {
                "Mythic 0 Seasonal Dungeons",
                "Mythic Keystone +2 to +3 (timed)",
                "Normal Raid bosses",
                "Delves Tier 7\226\128\13110",
            },
            [3445] = {
                "Mythic Keystone +2 to +6 timed",
                "Heroic Raid bosses",
                "Delves Tier 11",
            },
            [3446] = {
                "Mythic Keystone +7 and higher",
                "Mythic Raid bosses",
                "T11 Bountiful Stash",
            },
        },
    },
}

-- Season-independent currencies that stay highlighted across rollovers.
SeasonData.SHARED_KEY_CURRENCIES = {
    [3089] = { name = "Coffer Key", category = "delves" },
}

SeasonData.LATEST_SEASON = 2

-- Locale keys for track labels. Keyed by ENGLISH TRACK NAME (not currency ID) so
-- NormalizeUpgradeTrackName can map a localized track string back to its English name.
SeasonData.TRACK_LABEL_KEYS = {
    Adventurer = "PVE_CREST_ADV",
    Veteran    = "PVE_CREST_VET",
    Champion   = "PVE_CREST_CHAMP",
    Hero       = "PVE_CREST_HERO",
    Myth       = "PVE_CREST_MYTH",
}

-- Canonical track order, low -> high. Stable across seasons so far.
SeasonData.TRACK_ORDER = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- ACTIVE SEASON

SeasonData.current = nil

local rebuildCallbacks = {}

---Get the data table for the currently applied season (falls back to the latest).
function SeasonData:GetActive()
    return self.SEASONS[self.current or self.LATEST_SEASON] or self.SEASONS[self.LATEST_SEASON]
end

---Register a callback that refills derived tables when the season changes.
---The callback fires IMMEDIATELY once so load-time consumers get populated tables,
---then again on every Apply(). It receives the active season table and its number.
function SeasonData:RegisterRebuild(fn)
    if type(fn) ~= "function" then return end
    rebuildCallbacks[#rebuildCallbacks + 1] = fn
    fn(self:GetActive(), self.current or self.LATEST_SEASON)
end

---Switch the active season and refill every registered consumer. No-op if unchanged.
function SeasonData:Apply(seasonNumber)
    if not self.SEASONS[seasonNumber] then return false end
    if self.current == seasonNumber then return false end
    self.current = seasonNumber
    local active = self.SEASONS[seasonNumber]
    for i = 1, #rebuildCallbacks do
        local ok, err = pcall(rebuildCallbacks[i], active, seasonNumber)
        if not ok and ns.DebugPrint then
            ns.DebugPrint("|cffFF6B6B[SeasonData]|r rebuild callback failed: " .. tostring(err))
        end
    end
    if ns.DebugPrint then
        ns.DebugPrint("|cff9370DB[SeasonData]|r Active season -> " .. tostring(seasonNumber) .. " (" .. tostring(active.label) .. ")")
    end
    return true
end

---Does this season's crest currency look live to the client right now?
---A crest only gets a season cap / weekly cap while its season is running, and a player
---who has played the season will also have quantity or totalEarned on it.
---Confirmed against live 12.1 SavedVariables: the active character holds Adventurer/Veteran/
---Champion Mistcrest (30/55/80) while every Dawncrest sits at 0, so the quantity signal already
---separates the seasons before the 2026-08-18 flip. maxQuantity is kept as the leading check for
---fresh characters who hold no crests yet.
local function SeasonLooksActive(season)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return false end
    for _, currencyID in pairs(season.crestIDs) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and info then
            if (info.maxQuantity or 0) > 0 then return true end
            if (info.quantity or 0) > 0 then return true end
            if (info.totalEarned or 0) > 0 then return true end
        end
    end
    return false
end

---Detect the live season from the currency API and apply it.
---Walks newest -> oldest so a fresh season wins over leftover crests from the old one.
---Safe to call repeatedly; Apply() no-ops when nothing changed.
function SeasonData:ResolveFromAPI()
    -- Preferred: Blizzard tells us outright. Confirmed live in 12.1 (returns 2, and PvECacheService
    -- already persists it as pveCache.delves.season). Only fall through to the crest heuristic when
    -- this API is missing or returns something we have no data for.
    if C_DelvesUI and C_DelvesUI.GetCurrentDelvesSeasonNumber then
        local ok, seasonNum = pcall(C_DelvesUI.GetCurrentDelvesSeasonNumber)
        if ok and type(seasonNum) == "number" and self.SEASONS[seasonNum] then
            self:Apply(seasonNum)
            return seasonNum
        end
    end

    for seasonNumber = self.LATEST_SEASON, 1, -1 do
        local season = self.SEASONS[seasonNumber]
        if season and SeasonLooksActive(season) then
            self:Apply(seasonNumber)
            return seasonNumber
        end
    end
    -- Nothing readable yet (API not warm, or brand-new character): keep whatever is applied.
    return self.current or self.LATEST_SEASON
end

---Debug/manual override, e.g. to preview next season's tables before it opens.
function SeasonData:ForceSeason(seasonNumber)
    return self:Apply(seasonNumber)
end

-- CONSTANTS BRIDGE
--
-- Constants.lua no longer owns the season block. Populate it here so every existing
-- Constants.CREST_UI / Constants.MIDNIGHT_KEY_CURRENCIES reader keeps working, and
-- mutate in place because Constants is captured as an upvalue all over the addon.

local Constants = ns.Constants
if Constants then
    Constants.CREST_UI = Constants.CREST_UI or {
        COLUMN_IDS = {},
        DISPLAY_NAMES = {},
        PVE_LABEL_KEYS = {},
        SOURCES = {},
        WEEKLY_CAP_PER_TIER = 100,
    }
    -- Back-compat alias: older call sites still say DAWNCREST_UI.
    Constants.DAWNCREST_UI = Constants.CREST_UI
    Constants.MIDNIGHT_KEY_CURRENCIES = Constants.MIDNIGHT_KEY_CURRENCIES or {}

    SeasonData:RegisterRebuild(function(season)
        local ui = Constants.CREST_UI
        local order = SeasonData.TRACK_ORDER
        local labelKeys = SeasonData.TRACK_LABEL_KEYS

        table.wipe(ui.COLUMN_IDS)
        table.wipe(ui.DISPLAY_NAMES)
        table.wipe(ui.PVE_LABEL_KEYS)
        table.wipe(ui.SOURCES)
        for i = 1, #order do
            local trackName = order[i]
            local currencyID = season.crestIDs[trackName]
            if currencyID then
                ui.COLUMN_IDS[#ui.COLUMN_IDS + 1] = currencyID
                ui.DISPLAY_NAMES[currencyID] = season.crestNames[currencyID]
                ui.PVE_LABEL_KEYS[currencyID] = labelKeys[trackName]
                ui.SOURCES[currencyID] = season.crestSources and season.crestSources[currencyID]
            end
        end
        ui.WEEKLY_CAP_PER_TIER = season.weeklyCapPerTier or 100

        local keys = Constants.MIDNIGHT_KEY_CURRENCIES
        table.wipe(keys)
        for currencyID, entry in pairs(SeasonData.SHARED_KEY_CURRENCIES) do
            keys[currencyID] = entry
        end
        for currencyID, entry in pairs(season.keyCurrencies or {}) do
            keys[currencyID] = entry
        end
    end)
end
