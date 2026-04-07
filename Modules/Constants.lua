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
    -- GetAddOnMetadata() cannot be called during file initialization
    ADDON_VERSION = "2.5.11",
    -- Shown next to version in the What's New / changelog popup title
    ADDON_RELEASE_DATE = "2026-04-07",
    
    --==========================================================================
    -- EXPANSION TARGETING
    --==========================================================================
    
    CURRENT_EXPANSION_INTERFACE = 120000,   -- Midnight 12.0.x (## Interface in TOC)
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
    
    --==========================================================================
    -- EVENT NAMES (STANDARDIZED)
    --==========================================================================
    -- All events use WN_ prefix for consistency
    
    EVENTS = {
        -- Data updates
        CHARACTER_UPDATED = "WN_CHARACTER_UPDATED",
        ITEMS_UPDATED = "WN_ITEMS_UPDATED",
        GEAR_UPDATED = "WN_GEAR_UPDATED",
        MONEY_UPDATED = "WN_MONEY_UPDATED",
        PVE_UPDATED = "WN_PVE_UPDATED",
        CURRENCIES_UPDATED = "WN_CURRENCIES_UPDATED",
        REPUTATION_UPDATED = "WN_REPUTATION_UPDATED",

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
        
        -- Vault
        VAULT_CHECKPOINT_COMPLETED = "WN_VAULT_CHECKPOINT_COMPLETED",
        VAULT_SLOT_COMPLETED = "WN_VAULT_SLOT_COMPLETED",
        VAULT_PLAN_COMPLETED = "WN_VAULT_PLAN_COMPLETED",
        
        -- Reminders (progress-based, shown on plan cards)
        REMINDER_ACTIVATED = "WN_REMINDER_ACTIVATED",
        
        -- Item metadata
        ITEM_METADATA_READY = "WN_ITEM_METADATA_READY",
        
        -- UI
        SEARCH_STATE_CHANGED = "WN_SEARCH_STATE_CHANGED",
        SEARCH_QUERY_UPDATED = "WN_SEARCH_QUERY_UPDATED",
        TOOLTIP_SHOW = "WN_TOOLTIP_SHOW",
        TOOLTIP_HIDE = "WN_TOOLTIP_HIDE",
        
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
