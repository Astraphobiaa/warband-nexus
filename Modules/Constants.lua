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
    ADDON_VERSION = "2.0.0",
    
    --==========================================================================
    -- CACHE VERSIONS
    --==========================================================================
    -- Start all caches at 1.0.0 for consistency
    -- Increment PATCH version (third number) when cache schema changes
    
    COLLECTION_CACHE_VERSION = "1.6.1",  -- Mounts, Pets, Toys, Achievements, Titles, Illusions (v1.6.1: refactoring phase complete)
    REPUTATION_CACHE_VERSION = "2.1.0",  -- Reputation factions and standings (v2.1.0: Per-character storage, direct DB architecture)
    CURRENCY_CACHE_VERSION = "1.0.1",    -- Currencies (character + warband) (v1.0.1: refactoring phase complete)
    PVE_CACHE_VERSION = "1.0.1",         -- Mythic+, Great Vault, Lockouts (v1.0.1: refactoring phase complete)
    ITEMS_CACHE_VERSION = "1.0.1",       -- Bags, Bank, Warband Bank (v1.0.1: refactoring phase complete)
    
    --==========================================================================
    -- DATABASE VERSIONS
    --==========================================================================
    
    DB_VERSION = 2,  -- Main database schema version (for migrations)
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
        MONEY_UPDATED = "WN_MONEY_UPDATED",
        PVE_UPDATED = "WN_PVE_UPDATED",
        CURRENCIES_UPDATED = "WN_CURRENCIES_UPDATED",
        REPUTATIONS_UPDATED = "WN_REPUTATIONS_UPDATED",
        PROFESSIONS_UPDATED = "WN_PROFESSIONS_UPDATED",
        
        -- Collections
        COLLECTIBLE_OBTAINED = "WN_COLLECTIBLE_OBTAINED",
        COLLECTION_UPDATED = "WN_COLLECTION_UPDATED",
        COLLECTION_SCAN_COMPLETE = "WN_COLLECTION_SCAN_COMPLETE",
        COLLECTION_SCAN_PROGRESS = "WN_COLLECTION_SCAN_PROGRESS",
        
        -- Plans
        PLANS_UPDATED = "WN_PLANS_UPDATED",
        PLAN_COMPLETED = "WN_PLAN_COMPLETED",
        QUEST_COMPLETED = "WN_QUEST_COMPLETED",
        
        -- Vault
        VAULT_CHECKPOINT_COMPLETED = "WN_VAULT_CHECKPOINT_COMPLETED",
        VAULT_SLOT_COMPLETED = "WN_VAULT_SLOT_COMPLETED",
        VAULT_PLAN_COMPLETED = "WN_VAULT_PLAN_COMPLETED",
        
        -- UI
        SEARCH_STATE_CHANGED = "WN_SEARCH_STATE_CHANGED",
        SEARCH_QUERY_UPDATED = "WN_SEARCH_QUERY_UPDATED",
        TOOLTIP_SHOW = "WN_TOOLTIP_SHOW",
        TOOLTIP_HIDE = "WN_TOOLTIP_HIDE",
        
        -- Notifications
        SHOW_NOTIFICATION = "WN_SHOW_NOTIFICATION",
        REPUTATION_GAINED = "WN_REPUTATION_GAINED",
        
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
