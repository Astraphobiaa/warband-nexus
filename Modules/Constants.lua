--[[
    Warband Nexus - Constants
    Centralized version management and configuration constants
    
    VERSIONING STRATEGY (Semantic Versioning):
    ==========================================
    
    Format: MAJOR.MINOR.PATCH (e.g., 1.0.1)
    
    1. PATCH (third number): 1.0.0 → 1.0.1
       - Bug fixes
       - Small cache schema changes
       - Performance improvements
       - No breaking changes
       
    2. MINOR (second number): 1.0.0 → 1.1.0
       - New features
       - Deprecations (with backwards compatibility)
       - Cache restructuring
       
    3. MAJOR (first number): 1.0.0 → 2.0.0
       - Breaking changes
       - Complete rewrites
       - Incompatible API changes
    
    WHEN TO UPDATE VERSIONS:
    ========================
    - Cache schema changed? → Increment PATCH version (e.g., 1.0.0 → 1.0.1)
    - New field added to cache? → Increment PATCH version
    - Cache format completely changed? → Increment MINOR version (e.g., 1.0.0 → 1.1.0)
    - Breaking change? → Increment MAJOR version (e.g., 1.0.0 → 2.0.0)
]]

local ADDON_NAME, ns = ...

---@class Constants
local Constants = {
    --==========================================================================
    -- ADDON VERSION
    --==========================================================================
    
    -- Main addon version (must match ## Version in WarbandNexus.toc)
    -- IMPORTANT: Update this whenever you update the TOC version!
    -- Suffixes like -beta1 are OK; What's New resolves CHANGELOG_V<x><y><z> from the numeric triple only.
    -- GetAddOnMetadata() cannot be called during file initialization
    ADDON_VERSION = "2.7.0",
    -- Shown next to version in the What's New / changelog popup title
    ADDON_RELEASE_DATE = "2026-05-05",

    -- Single-roof version registry. Cache invalidation triggers ONLY when one of:
    --   1. Game build (select(4, GetBuildInfo())) changes — Blizzard API may have shifted shape.
    --   2. The matching CACHE.<name> integer is bumped manually here (breaking schema change).
    -- Addon version bumps DO NOT invalidate any cache by themselves.
    -- Bump CACHE.<name> only when the cache's stored shape becomes incompatible with the new code.
    VERSIONS = {
        CACHE = {
            reputation = 1,
            collection = 1,
            currency   = 1,
            pve        = 1,
        },
    },
    
    --==========================================================================
    -- EXPANSION TARGETING
    --==========================================================================
    
    CURRENT_EXPANSION_INTERFACE = 120005,   -- Midnight 12.0.5 (## Interface in TOC; must match WarbandNexus.toc)
    CURRENT_EXPANSION_NAME = "Midnight",    -- Used for filtering profession content to latest expansion
    
    --==========================================================================
    -- CACHE VERSIONS
    --==========================================================================
    -- Start all caches at 1.0.0 for consistency
    -- Increment PATCH version (third number) when cache schema changes
    
    -- All versions reset to 1.0.0 — Schema v4 full wipe gives every user a clean slate.
    COLLECTION_CACHE_VERSION = "2.0.2",  -- Cache refresh (Midnight encounter/achievement incremental invalidation)
    REPUTATION_CACHE_VERSION = "1.5.0",  -- Reputation (parse-first architecture + non-destructive rescan safety)
    CURRENCY_CACHE_VERSION = "2.0.0",    -- Currency (lean SV + on-demand metadata cache)
    PVE_CACHE_VERSION = "1.0.0",         -- PvE (lean IDs/scores; metadata on-demand)
    ITEMS_CACHE_VERSION = "1.0.0",       -- Items (lean itemID+stack+quality; metadata on-demand)
    
    --==========================================================================
    -- DATABASE VERSIONS
    --==========================================================================
    
    DB_VERSION = 1,  -- Main database schema version (for migrations)
                     -- Increment when database structure changes require migration
    
    --==========================================================================
    -- PERFORMANCE CONSTANTS
    --==========================================================================
    
    -- Throttle timings (in seconds)
    THROTTLE = {
        PERSONAL_FREQUENT = 2.0,  -- Bags (BAG_UPDATE spam prevention)
        SHARED_MODERATE = 1.0,    -- Currency, Reputation (moderate changes)
        SHARED_RARE = 2.0,        -- PvE, Collections (rare changes)
        CURRENCY_UPDATE = 0.3,    -- Legacy currency throttle
        REPUTATION_UPDATE = 2.0,  -- Legacy reputation throttle
    },
    
    -- Frame budget for async operations (in milliseconds)
    FRAME_BUDGET_MS = 8,  -- Max 8ms per frame for background tasks (increased from 5ms)
    
    -- Batch sizes for yielding
    BATCH_SIZE = 100,  -- Yield every 100 items in async operations (increased from 10 for performance)

    -- Collections tab → Recent strip: SavedVariables rows older than this are removed (seconds)
    COLLECTIONS_RECENT_RETENTION_SEC = 604800, -- 7 days
    
    --==========================================================================
    -- EVENT NAMES (STANDARDIZED)
    --==========================================================================
    -- All events use WN_ prefix for consistency
    
    EVENTS = {
        -- Data updates
        CHARACTER_UPDATED = "WN_CHARACTER_UPDATED",
        ITEMS_UPDATED = "WN_ITEMS_UPDATED",
        BAGS_UPDATED = "WN_BAGS_UPDATED",
        GEAR_UPDATED = "WN_GEAR_UPDATED",
        MONEY_UPDATED = "WN_MONEY_UPDATED",
        PVE_UPDATED = "WN_PVE_UPDATED",
        CURRENCY_UPDATED = "WN_CURRENCY_UPDATED",
        CURRENCIES_UPDATED = "WN_CURRENCIES_UPDATED",
        CURRENCY_LOADING_STARTED = "WN_CURRENCY_LOADING_STARTED",
        CURRENCY_CACHE_READY = "WN_CURRENCY_CACHE_READY",
        CURRENCY_CACHE_CLEARED = "WN_CURRENCY_CACHE_CLEARED",
        CURRENCY_GAINED = "WN_CURRENCY_GAINED",
        REPUTATION_UPDATED = "WN_REPUTATION_UPDATED",
        REPUTATION_LOADING_STARTED = "WN_REPUTATION_LOADING_STARTED",
        REPUTATION_CACHE_READY = "WN_REPUTATION_CACHE_READY",
        REPUTATION_CACHE_CLEARED = "WN_REPUTATION_CACHE_CLEARED",

        -- Collections
        COLLECTIBLE_OBTAINED = "WN_COLLECTIBLE_OBTAINED",
        COLLECTION_UPDATED = "WN_COLLECTION_UPDATED",
        COLLECTION_SCAN_COMPLETE = "WN_COLLECTION_SCAN_COMPLETE",
        COLLECTION_SCAN_PROGRESS = "WN_COLLECTION_SCAN_PROGRESS",
        ACHIEVEMENT_TRACKING_UPDATED = "WN_ACHIEVEMENT_TRACKING_UPDATED",
        
        -- Plans
        PLANS_UPDATED = "WN_PLANS_UPDATED",
        PLAN_COMPLETED = "WN_PLAN_COMPLETED",
        QUEST_COMPLETED = "WN_QUEST_COMPLETED",
        --- Daily / weekly quest plan progress (not WN_ prefix — legacy identifier)
        QUEST_PROGRESS_UPDATED = "WARBAND_QUEST_PROGRESS_UPDATED",
        
        -- Vault
        VAULT_CHECKPOINT_COMPLETED = "WN_VAULT_CHECKPOINT_COMPLETED",
        VAULT_SLOT_COMPLETED = "WN_VAULT_SLOT_COMPLETED",
        VAULT_PLAN_COMPLETED = "WN_VAULT_PLAN_COMPLETED",
        VAULT_REWARD_AVAILABLE = "WN_VAULT_REWARD_AVAILABLE",
        
        -- Reminders (progress-based, shown on plan cards)
        REMINDER_ACTIVATED = "WN_REMINDER_ACTIVATED",
        
        -- Item metadata
        ITEM_METADATA_READY = "WN_ITEM_METADATA_READY",
        
        -- UI
        SEARCH_STATE_CHANGED = "WN_SEARCH_STATE_CHANGED",
        SEARCH_QUERY_UPDATED = "WN_SEARCH_QUERY_UPDATED",
        TOOLTIP_SHOW = "WN_TOOLTIP_SHOW",
        TOOLTIP_HIDE = "WN_TOOLTIP_HIDE",
        FONT_CHANGED = "WN_FONT_CHANGED",
        FONT_LIST_UPDATED = "WN_FONT_LIST_UPDATED",
        --- UI-initiated full main-window content rebuild (debounced via SchedulePopulateContent).
        --- Payload: { tab = optional string (only refresh if main frame is on this tab), skipCooldown = optional bool (default true) }
        UI_MAIN_REFRESH_REQUESTED = "WN_UI_MAIN_REFRESH_REQUESTED",
        LOADING_UPDATED = "WN_LOADING_UPDATED",
        LOADING_COMPLETE = "WN_LOADING_COMPLETE",
        
        -- Notifications
        SHOW_NOTIFICATION = "WN_SHOW_NOTIFICATION",
        REPUTATION_GAINED = "WN_REPUTATION_GAINED",
        
        -- Professions
        PROFESSION_WINDOW_OPENED = "WN_PROFESSION_WINDOW_OPENED",
        PROFESSION_WINDOW_CLOSED = "WN_PROFESSION_WINDOW_CLOSED",
        RECIPE_SELECTED = "WN_RECIPE_SELECTED",
        CONCENTRATION_UPDATED = "WN_CONCENTRATION_UPDATED",
        KNOWLEDGE_UPDATED = "WN_KNOWLEDGE_UPDATED",
        RECIPE_DATA_UPDATED = "WN_RECIPE_DATA_UPDATED",
        PROFESSION_EQUIPMENT_UPDATED = "WN_PROFESSION_EQUIPMENT_UPDATED",
        CRAFTING_ORDERS_UPDATED = "WN_CRAFTING_ORDERS_UPDATED",
        PROFESSION_COOLDOWNS_UPDATED = "WN_PROFESSION_COOLDOWNS_UPDATED",
        PROFESSION_DATA_UPDATED = "WN_PROFESSION_DATA_UPDATED",

        -- Modules
        MODULE_TOGGLED = "WN_MODULE_TOGGLED",

        -- Character / tracking / gold UI
        CHARACTER_TRACKING_CHANGED = "WN_CHARACTER_TRACKING_CHANGED",
        CHARACTER_BANK_MONEY_LOG_UPDATED = "WN_CHARACTER_BANK_MONEY_LOG_UPDATED",
        GOLD_MANAGEMENT_CHANGED = "WN_GOLD_MANAGEMENT_CHANGED",
    },
    
    --==========================================================================
    -- FEATURE FLAGS
    --==========================================================================
    
    ENABLE_GUILD_BANK = false,  -- Set to true when Guild Bank features are ready
    ENABLE_DEBUG_MODE = false,  -- Global debug mode (can be overridden per-profile)
    
    --==========================================================================
    -- WOW CLASS COLORS (Hex codes for text coloring)
    --==========================================================================
    -- Standard WoW class colors in hex format for use in text strings
    CLASS_COLORS = {
        WARRIOR = "|cffC79C6E",      -- Tan/Brown
        PALADIN = "|cffF58CBA",      -- Pink
        HUNTER = "|cffABD473",       -- Green
        ROGUE = "|cffFFF569",        -- Yellow
        PRIEST = "|cffFFFFFF",       -- White
        DEATHKNIGHT = "|cffC41F3B",  -- Red
        SHAMAN = "|cff0070DE",       -- Blue
        MAGE = "|cff40C7EB",         -- Cyan
        WARLOCK = "|cff8787ED",      -- Purple
        MONK = "|cff00FF96",         -- Jade Green
        DRUID = "|cffFF7D0A",        -- Orange
        DEMONHUNTER = "|cffA330EE",  -- Purple-Magenta
        EVOKER = "|cff33937F",       -- Teal
    },

    -- English class file string (UnitClass) -> GetSpecializationInfoForClassID classID
    CLASS_FILE_TO_CLASS_ID = {
        WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
        DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
        DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
    },
    
    --==========================================================================
    -- MIDNIGHT KEY CURRENCIES (auto-highlighted in UI)
    --==========================================================================
    
    MIDNIGHT_KEY_CURRENCIES = {
        [3378] = { name = "Dawnlight Manaflux", category = "catalyst" },   -- Catalyst charges
        [3314] = { name = "Radiant Ember", category = "crest" },           -- Gilded Crest equivalent
        [3313] = { name = "Radiant Dust", category = "crest" },            -- Runed Crest equivalent
        [3312] = { name = "Radiant Shard", category = "crest" },           -- Carved Crest equivalent
        [3089] = { name = "Coffer Key", category = "delves" },             -- Delve Coffer Keys
    },

    --==========================================================================
    -- DAWNCREST UI COLUMN ORDER (Gear tab + PvE summary only)
    --==========================================================================
    -- Chat notifications and CurrencyCache use C_CurrencyInfo flags (useTotalEarnedForMaxQty, etc.),
    -- not this list — so new patch currencies do not require ID updates for WN-Currency messages.
    DAWNCREST_UI = {
        COLUMN_IDS = { 3383, 3341, 3343, 3345, 3347 },
        DISPLAY_NAMES = {
            [3383] = "Adventurer Dawncrest",
            [3341] = "Veteran Dawncrest",
            [3343] = "Champion Dawncrest",
            [3345] = "Hero Dawncrest",
            [3347] = "Myth Dawncrest",
        },
        PVE_LABEL_KEYS = {
            [3383] = "PVE_CREST_ADV",
            [3341] = "PVE_CREST_VET",
            [3343] = "PVE_CREST_CHAMP",
            [3345] = "PVE_CREST_HERO",
            [3347] = "PVE_CREST_MYTH",
        },
        -- Source tables for "where to farm" tooltip (Midnight S1).
        -- Sources: Warcraft Wiki Midnight S1 + Method/IcyVeins/Wowhead patch notes (verify per patch).
        -- Amount strings are deliberately a mix of exact ("10\226\128\14318 / key") and qualitative
        -- ("varies") because Blizzard does not document T1\226\128\14310 delve / per-boss raid amounts.
        SOURCES = {
            [3383] = {  -- Adventurer
                "Repeatable Outdoor Events",
                "Tier 4 Delves",
            },
            [3341] = {  -- Veteran
                "Hard-Mode Prey events  (~15 / ~7\226\128\13110 min)",
                "Heroic Seasonal Dungeons",
                "Raid Finder bosses",
                "Delves Tier 5\226\128\1316",
                "Trovehunter\226\128\153s Bounty (T4\226\128\1315)",
            },
            [3343] = {  -- Champion
                "Mythic 0 Seasonal Dungeons",
                "Mythic Keystone +2 to +3 (timed)",
                "Normal Raid bosses",
                "Delves Tier 7\226\128\13110",
                "Trovehunter\226\128\153s Bounty (T6\226\128\1317)",
                "Weekly Outdoor Events",
            },
            [3345] = {  -- Hero
                "Mythic Keystone +2 to +6 timed  (10\226\128\13118 / key)",
                "Heroic Raid bosses",
                "Delves Tier 11",
                "Trovehunter\226\128\153s Bounty (T8+)",
            },
            [3347] = {  -- Myth
                "Mythic Keystone +7 and higher  (10\226\128\13120 / key)",
                "Mythic Raid bosses",
                "T11 Bountiful Gilded Stash  (7 / run, up to 3 / week)",
            },
        },
        WEEKLY_CAP_PER_TIER = 100,  -- Some tiers have +source-specific caps (e.g. Veteran 200 cumulative).
    },

    -- Slots used for "missing primary enchant" (Gear tab + GearService). INVSLOT_* ids.
    -- Midnight 12.x primary enchants: head, shoulder, chest, boots, rings, weapon(s).
    -- Cloak/wrist/legs are intentionally omitted to avoid false flags.
    GEAR_ENCHANTABLE_SLOTS = {
        [1] = true,   -- Head
        [3] = true,   -- Shoulder
        [5] = true,   -- Chest
        [8] = true,   -- Feet
        [11] = true,  -- Finger 1
        [12] = true,  -- Finger 2
        [16] = true,  -- Main hand (weapon-capable)
        [17] = true,  -- Off hand (weapon-capable)
    },

    -- PvE tab — Trovehunter's Bounty column uses IsQuestFlaggedCompleted on a hidden tracking quest (per-char snapshot in cache).
    -- 86371 = weekly Trovehunter's Bounty loot/claim flag (TWW/Midnight). Confirmed in community tooling, e.g.
    --   github.com/BejayGE/BountifulDelvesHunter-Midnight (delverBountyQ = IsQuestFlaggedCompleted(86371)).
    -- Do NOT OR in 92600 (Cracked Keystone) or 81514 (Bountiful Delves weekly) here — those are different quests and would
    -- show "bounty done" when only the keystone / coffer weekly was completed.
    PVE_BOUNTIFUL_WEEKLY_QUEST_IDS = {
        86371,
    },
    PVE_CRACKED_KEYSTONE_WEEKLY_QUEST_ID = 92600,

    -- PvE "Bountiful" column: icon from Trovehunter's Bounty item (C_Item.GetItemIconByID); ALT for ID drift between patches.
    TROVEHUNTERS_BOUNTY_ITEM_ID = 252415,
    TROVEHUNTERS_BOUNTY_ITEM_ID_ALT = 265714,
    
    --==========================================================================
    -- REPUTATION STANDARDS (for validation)
    --==========================================================================
    -- Classic Reputation uses FIXED threshold ranges (never changes)
    -- These are Blizzard's standard values used across all Classic reputations
    
    CLASSIC_REP_THRESHOLDS = {
        [1] = {min = -42000, max = -6000, range = 36000},   -- Hated
        [2] = {min = -6000, max = -3000, range = 3000},     -- Hostile
        [3] = {min = -3000, max = 0, range = 3000},         -- Unfriendly
        [4] = {min = 0, max = 3000, range = 3000},          -- Neutral
        [5] = {min = 3000, max = 9000, range = 6000},       -- Friendly
        [6] = {min = 9000, max = 21000, range = 12000},     -- Honored
        [7] = {min = 21000, max = 42000, range = 21000},    -- Revered
        [8] = {min = 42000, max = 999999, range = 0},       -- Exalted (capped, no range)
    },

    --==========================================================================
    -- RACE ICON ATLAS (raceFile / clientFileString -> middle segment of atlas name)
    -- Used by SharedWidgets: string.format("raceicon128-%s-%s", prefix, gender)
    --==========================================================================
    RACE_FILE_TO_ATLAS_PREFIX = {
        ["BloodElf"] = "bloodelf",
        ["DarkIronDwarf"] = "darkirondwarf",
        ["Dracthyr"] = "dracthyrvisage",
        ["Draenei"] = "draenei",
        ["Dwarf"] = "dwarf",
        ["Earthen"] = "earthen",
        ["Haranir"] = "haranir",
        ["Harronir"] = "haranir",
        ["Gnome"] = "gnome",
        ["Goblin"] = "goblin",
        ["HighmountainTauren"] = "highmountain",
        ["Human"] = "human",
        ["KulTiran"] = "kultiran",
        ["LightforgedDraenei"] = "lightforged",
        ["MagharOrc"] = "magharorc",
        ["Mechagnome"] = "mechagnome",
        ["Nightborne"] = "nightborne",
        ["NightElf"] = "nightelf",
        ["Orc"] = "orc",
        ["Pandaren"] = "pandaren",
        ["Tauren"] = "tauren",
        ["Troll"] = "troll",
        ["Scourge"] = "undead",
        ["Worgen"] = "worgen",
        ["ZandalariTroll"] = "zandalari",
        ["VoidElf"] = "voidelf",
        ["Vulpera"] = "vulpera",
    },
    
    -- NOTE: Renown and Friendship thresholds are NOT standardized
    -- Renown: Each faction has different thresholds (2.5k, 5k, 7.5k, 10k, etc.)
    -- Friendship: Each faction has different rank systems (5, 6, 10 ranks with custom names)
    -- For these types: Trust API data, only validate for negatives/zero-division
}

-- Export to namespace
ns.Constants = Constants

-- Backwards compatibility exports
ns.ADDON_VERSION = Constants.ADDON_VERSION
ns.Events = Constants.EVENTS

-- REMOVED: Verbose load messages - only show in debug mode via DebugService
-- Print load message with all version info (debug mode only)
-- These messages are now hidden from normal users to reduce spam

return Constants
