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
    ADDON_VERSION = "1.2.4",
    
    --==========================================================================
    -- CACHE VERSIONS
    --==========================================================================
    -- Start all caches at 1.0.0 for consistency
    -- Increment PATCH version (third number) when cache schema changes
    
    COLLECTION_CACHE_VERSION = "1.6.0",  -- Mounts, Pets, Toys, Achievements, Titles, Illusions (v1.6.0: tab switch abort protocol)
    REPUTATION_CACHE_VERSION = "1.1.0",  -- Reputation factions and standings (v1.1.0: spam fix + consecutive invalid counter)
    CURRENCY_CACHE_VERSION = "1.0.0",    -- Currencies (character + warband)
    PVE_CACHE_VERSION = "1.0.0",         -- Mythic+, Great Vault, Lockouts (Phase 1)
    ITEMS_CACHE_VERSION = "1.0.0",       -- Bags, Bank, Warband Bank (Phase 1)
    
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
}

-- Export to namespace
ns.Constants = Constants

-- Backwards compatibility exports
ns.ADDON_VERSION = Constants.ADDON_VERSION
ns.Events = Constants.EVENTS

-- Print load message with all version info
print(string.format("|cff9370DB[WN Constants]|r Loaded - Addon v%s | DB v%d", Constants.ADDON_VERSION, Constants.DB_VERSION))
print(string.format("|cff9370DB[WN Constants]|r Cache versions - Collection: %s | Reputation: %s | Currency: %s", 
    Constants.COLLECTION_CACHE_VERSION, 
    Constants.REPUTATION_CACHE_VERSION, 
    Constants.CURRENCY_CACHE_VERSION))

return Constants
