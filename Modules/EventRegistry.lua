--[[
    Warband Nexus - Event Registry
    Centralized event names for consistent communication
    Eliminates mixed naming conventions (WN_* vs WARBAND_*)
]]

local ADDON_NAME, ns = ...

---@class EventRegistry
local Events = {
    --==========================================================================
    -- DATA UPDATE EVENTS
    --==========================================================================
    
    -- Character data updated (gold, level, class, etc.)
    CHARACTER_UPDATED = "WARBAND_CHARACTER_UPDATED",
    
    -- Bag/inventory items updated
    ITEMS_UPDATED = "WARBAND_ITEMS_UPDATED",
    BAGS_UPDATED = "WN_BAGS_UPDATED",  -- Legacy compatibility
    
    -- PvE data updated (Great Vault, M+, raids)
    PVE_UPDATED = "WARBAND_PVE_UPDATED",
    
    -- Currency data updated
    CURRENCIES_UPDATED = "WARBAND_CURRENCIES_UPDATED",
    
    -- Reputation data updated
    REPUTATIONS_UPDATED = "WARBAND_REPUTATIONS_UPDATED",
    
    -- Profession data updated
    PROFESSIONS_UPDATED = "WARBAND_PROFESSIONS_UPDATED",
    
    --==========================================================================
    -- COLLECTION EVENTS
    --==========================================================================
    
    -- New collectible obtained (mount, pet, toy, etc.)
    COLLECTIBLE_OBTAINED = "WARBAND_COLLECTIBLE_OBTAINED",
    
    -- Collection scan completed
    COLLECTION_SCAN_COMPLETE = "WARBAND_COLLECTION_SCAN_COMPLETE",
    
    -- Collection scan progress update
    COLLECTION_SCAN_PROGRESS = "WARBAND_COLLECTION_SCAN_PROGRESS",
    
    --==========================================================================
    -- PLAN EVENTS
    --==========================================================================
    
    -- Plans list updated (add, remove, modify)
    PLANS_UPDATED = "WARBAND_PLANS_UPDATED",
    
    -- A plan was completed
    PLAN_COMPLETED = "WARBAND_PLAN_COMPLETED",
    
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
    SEARCH_STATE_CHANGED = "WARBAND_SEARCH_STATE_CHANGED",
    
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
