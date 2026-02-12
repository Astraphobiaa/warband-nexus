--[[
    Warband Nexus - Event Registry
    Centralized event names for consistent communication
    Standardized: All events use WN_ prefix for consistency
]]

local ADDON_NAME, ns = ...

---@class EventRegistry
local Events = {
    --==========================================================================
    -- DATA UPDATE EVENTS
    --==========================================================================
    
    -- Character data updated (gold, level, class, etc.)
    CHARACTER_UPDATED = "WN_CHARACTER_UPDATED",
    
    -- Bag/inventory items updated
    ITEMS_UPDATED = "WN_ITEMS_UPDATED",
    
    -- Money/gold updated
    MONEY_UPDATED = "WN_MONEY_UPDATED",
    
    -- PvE data updated (Great Vault, M+, raids)
    PVE_UPDATED = "WN_PVE_UPDATED",
    
    -- Currency data updated
    CURRENCIES_UPDATED = "WN_CURRENCIES_UPDATED",
    
    -- Currency scan/loading events
    CURRENCY_LOADING_STARTED = "WN_CURRENCY_LOADING_STARTED",
    CURRENCY_CACHE_READY = "WN_CURRENCY_CACHE_READY",
    CURRENCY_UPDATED = "WN_CURRENCY_UPDATED",
    CURRENCY_CACHE_CLEARED = "WN_CURRENCY_CACHE_CLEARED",
    
    -- Reputation data updated
    REPUTATIONS_UPDATED = "WN_REPUTATIONS_UPDATED",
    
    -- Reputation scan/loading events
    REPUTATION_LOADING_STARTED = "WN_REPUTATION_LOADING_STARTED",
    REPUTATION_CACHE_READY = "WN_REPUTATION_CACHE_READY",
    REPUTATION_UPDATED = "WN_REPUTATION_UPDATED",
    
    --==========================================================================
    -- COLLECTION EVENTS
    --==========================================================================
    
    -- New collectible obtained (mount, pet, toy, etc.)
    COLLECTIBLE_OBTAINED = "WN_COLLECTIBLE_OBTAINED",
    
    -- Collection data updated (mount/pet count changed)
    COLLECTION_UPDATED = "WN_COLLECTION_UPDATED",
    
    -- Collection scan completed
    COLLECTION_SCAN_COMPLETE = "WN_COLLECTION_SCAN_COMPLETE",
    
    -- Collection scan progress update
    COLLECTION_SCAN_PROGRESS = "WN_COLLECTION_SCAN_PROGRESS",
    
    --==========================================================================
    -- PLAN EVENTS
    --==========================================================================
    
    -- Plans list updated (add, remove, modify)
    PLANS_UPDATED = "WN_PLANS_UPDATED",
    
    -- A plan was completed
    PLAN_COMPLETED = "WN_PLAN_COMPLETED",
    
    -- Quest completed
    QUEST_COMPLETED = "WN_QUEST_COMPLETED",
    
    -- Weekly vault checkpoint completed
    VAULT_CHECKPOINT_COMPLETED = "WN_VAULT_CHECKPOINT_COMPLETED",
    
    -- Weekly vault slot completed
    VAULT_SLOT_COMPLETED = "WN_VAULT_SLOT_COMPLETED",
    
    -- Full weekly vault plan completed
    VAULT_PLAN_COMPLETED = "WN_VAULT_PLAN_COMPLETED",
    
    --==========================================================================
    -- UI EVENTS
    --==========================================================================
    
    -- Search state changed
    SEARCH_STATE_CHANGED = "WN_SEARCH_STATE_CHANGED",
    
    -- Search query updated (immediate, no throttle)
    SEARCH_QUERY_UPDATED = "WN_SEARCH_QUERY_UPDATED",
    
    -- Tooltip show/hide
    TOOLTIP_SHOW = "WN_TOOLTIP_SHOW",
    TOOLTIP_HIDE = "WN_TOOLTIP_HIDE",
    
    --==========================================================================
    -- NOTIFICATION EVENTS
    --==========================================================================
    
    -- Show a notification
    SHOW_NOTIFICATION = "WN_SHOW_NOTIFICATION",
    
    -- Reputation level gained
    REPUTATION_GAINED = "WN_REPUTATION_GAINED",
    
    --==========================================================================
    -- PROFESSION EVENTS
    --==========================================================================
    
    -- Profession window opened/closed
    PROFESSION_WINDOW_OPENED = "WN_PROFESSION_WINDOW_OPENED",
    PROFESSION_WINDOW_CLOSED = "WN_PROFESSION_WINDOW_CLOSED",
    
    -- Recipe selected in profession UI
    RECIPE_SELECTED = "WN_RECIPE_SELECTED",
    
    -- Concentration data updated (collection, real-time currency change, or periodic tick)
    CONCENTRATION_UPDATED = "WN_CONCENTRATION_UPDATED",
    
    -- Knowledge data updated (collection, spec point spent, or periodic refresh)
    KNOWLEDGE_UPDATED = "WN_KNOWLEDGE_UPDATED",
    
    -- Recipe knowledge data updated (per-character scan)
    RECIPE_DATA_UPDATED = "WN_RECIPE_DATA_UPDATED",
    
    --==========================================================================
    -- MODULE EVENTS
    --==========================================================================
    
    -- Module toggled on/off
    MODULE_TOGGLED = "WN_MODULE_TOGGLED",
}

-- Export to namespace
ns.Events = Events

-- Backwards compatibility: expose common events individually
ns.EVENT_CHARACTER_UPDATED = Events.CHARACTER_UPDATED
ns.EVENT_ITEMS_UPDATED = Events.ITEMS_UPDATED
ns.EVENT_PVE_UPDATED = Events.PVE_UPDATED
ns.EVENT_CURRENCIES_UPDATED = Events.CURRENCIES_UPDATED
ns.EVENT_REPUTATIONS_UPDATED = Events.REPUTATIONS_UPDATED
ns.EVENT_PLANS_UPDATED = Events.PLANS_UPDATED

return Events
