--[[
    Warband Nexus - Event Manager Module
    Centralized event handling with throttling, debouncing, and priority queues
    
    Features:
    - Event throttling (limit frequency of event processing)
    - Event debouncing (delay processing until events stop)
    - Priority queue (process high-priority events first)
    - Batch event processing (combine multiple events)
    - Event statistics and monitoring
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- EVENT CONFIGURATION
-- ============================================================================

local EVENT_CONFIG = {
    -- Throttle delays (seconds) - minimum time between processing
    THROTTLE = {
        BAG_UPDATE = 0.15,           -- Fast response for bag changes
        COLLECTION_CHANGED = 0.5,    -- Debounce rapid collection additions
        PVE_DATA_CHANGED = 1.0,      -- Slow response for PvE updates
        PET_LIST_CHANGED = 2.0,      -- Very slow for pet caging
    },
    
    -- Priority levels (higher = processed first)
    PRIORITY = {
        CRITICAL = 100,  -- UI-blocking events (bank open/close)
        HIGH = 75,       -- User-initiated actions (manual refresh)
        NORMAL = 50,     -- Standard game events (bag updates)
        LOW = 25,        -- Background updates (collections)
        IDLE = 10,       -- Deferred processing (statistics)
    },
}

-- ============================================================================
-- EVENT QUEUE & STATE
-- ============================================================================

local eventQueue = {}      -- Priority queue for pending events
local activeTimers = {}    -- Active throttle/debounce timers
local eventStats = {       -- Event processing statistics
    processed = {},
    throttled = {},
    queued = {},
}

-- ============================================================================
-- THROTTLE & DEBOUNCE UTILITIES
-- ============================================================================

--[[
    Throttle a function call
    Ensures function is not called more than once per interval
    @param key string - Unique throttle key
    @param interval number - Throttle interval (seconds)
    @param func function - Function to call
    @param ... any - Arguments to pass to function
]]
local function Throttle(key, interval, func, ...)
    -- If already throttled, skip
    if activeTimers[key] then
        eventStats.throttled[key] = (eventStats.throttled[key] or 0) + 1
        return false
    end
    
    -- Execute immediately
    func(...)
    eventStats.processed[key] = (eventStats.processed[key] or 0) + 1
    
    -- Set throttle timer
    activeTimers[key] = C_Timer.NewTimer(interval, function()
        activeTimers[key] = nil
    end)
    
    return true
end

--[[
    Debounce a function call
    Delays execution until calls stop for specified interval
    @param key string - Unique debounce key
    @param interval number - Debounce interval (seconds)
    @param func function - Function to call
    @param ... any - Arguments to pass to function
]]
local function Debounce(key, interval, func, ...)
    local args = {...}
    
    -- Cancel existing timer
    if activeTimers[key] then
        activeTimers[key]:Cancel()
    end
    
    eventStats.queued[key] = (eventStats.queued[key] or 0) + 1
    
    -- Set new timer
    activeTimers[key] = C_Timer.NewTimer(interval, function()
        activeTimers[key] = nil
        func(unpack(args))
        eventStats.processed[key] = (eventStats.processed[key] or 0) + 1
    end)
end

-- ============================================================================
-- PRIORITY QUEUE MANAGEMENT
-- ============================================================================

--[[
    Add event to priority queue
    @param eventName string - Event identifier
    @param priority number - Priority level
    @param handler function - Event handler function
    @param ... any - Handler arguments
]]
local function QueueEvent(eventName, priority, handler, ...)
    table.insert(eventQueue, {
        name = eventName,
        priority = priority,
        handler = handler,
        args = {...},
        timestamp = time(),
    })
    
    -- Sort queue by priority (descending)
    table.sort(eventQueue, function(a, b)
        return a.priority > b.priority
    end)
end

--[[
    Process next event in priority queue
    @return boolean - True if event was processed, false if queue empty
]]
local function ProcessNextEvent()
    if #eventQueue == 0 then
        return false
    end
    
    local event = table.remove(eventQueue, 1) -- Remove highest priority
    event.handler(unpack(event.args))
    eventStats.processed[event.name] = (eventStats.processed[event.name] or 0) + 1
    
    return true
end

--[[
    Process all queued events (up to max limit per frame)
    @param maxEvents number - Max events to process (default 10)
]]
local function ProcessEventQueue(maxEvents)
    maxEvents = maxEvents or 10
    local processed = 0
    
    while processed < maxEvents and ProcessNextEvent() do
        processed = processed + 1
    end
    
    return processed
end

-- ============================================================================
-- BATCH EVENT PROCESSING
-- ============================================================================

local batchedEvents = {
    BAG_UPDATE = {},      -- Collect bag IDs
    ITEM_LOCKED = {},     -- Collect locked items
}

--[[
    Add event to batch
    @param eventType string - Batch type (BAG_UPDATE, etc.)
    @param data any - Data to batch
]]
local function BatchEvent(eventType, data)
    if not batchedEvents[eventType] then
        batchedEvents[eventType] = {}
    end
    
    table.insert(batchedEvents[eventType], data)
end

--[[
    Process batched events
    @param eventType string - Batch type to process
    @param handler function - Handler receiving batched data
]]
local function ProcessBatch(eventType, handler)
    if not batchedEvents[eventType] or #batchedEvents[eventType] == 0 then
        return 0
    end
    
    local batch = batchedEvents[eventType]
    batchedEvents[eventType] = {} -- Clear batch
    
    handler(batch)
    eventStats.processed[eventType] = (eventStats.processed[eventType] or 0) + 1
    
    return #batch
end

-- ============================================================================
-- PUBLIC API (WarbandNexus Event Handlers)
-- ============================================================================

--[[
    Throttled BAG_UPDATE handler
    Batches bag IDs and processes them together
]]
function WarbandNexus:OnBagUpdateThrottled(bagIDs)
    -- Skip processing during combat (queue for after combat)
    if InCombatLockdown() then
        -- Queue update for after combat
        self.pendingBagUpdateAfterCombat = self.pendingBagUpdateAfterCombat or {}
        for bagID in pairs(bagIDs) do
            self.pendingBagUpdateAfterCombat[bagID] = true
        end
        return
    end
    
    -- Batch all bag IDs
    for bagID in pairs(bagIDs) do
        BatchEvent("BAG_UPDATE", bagID)
    end
    
    -- Adaptive throttle: longer during rapid updates, shorter when idle
    local throttleDuration = InCombatLockdown() and 0.5 or 0.2
    
    -- Throttled processing
    Throttle("BAG_UPDATE", throttleDuration, function()
        -- Process all batched bag updates at once
        ProcessBatch("BAG_UPDATE", function(bagIDList)
            -- Convert array to set for fast lookup
            local bagSet = {}
            for _, bagID in ipairs(bagIDList) do
                bagSet[bagID] = true
            end
            
            -- Call original handler with batched bag IDs
            self:OnBagUpdate(bagSet)
        end)
    end)
end

--[[
    Debounced COLLECTION_CHANGED handler
    Waits for rapid collection changes to settle
]]
function WarbandNexus:OnCollectionChangedDebounced(event, ...)
    -- Handle TRANSMOG_COLLECTION_UPDATED separately (includes illusions)
    if event == "TRANSMOG_COLLECTION_UPDATED" then
        Debounce("TRANSMOG_COLLECTION", EVENT_CONFIG.THROTTLE.COLLECTION_CHANGED, function()
            self:OnTransmogCollectionUpdated(event)
        end)
        return
    end
    
    print("|cffffcc00[WN EventManager]|r OnCollectionChangedDebounced: " .. event)
    
    -- CRITICAL FIX: Route to correct CollectionService handlers
    -- Each event needs its own handler with event-specific data
    if event == "NEW_MOUNT_ADDED" then
        -- Get mountID from event args (first arg after event name)
        local mountID = ...
        print("|cffffcc00[WN EventManager]|r NEW_MOUNT_ADDED mountID: " .. tostring(mountID))
        if mountID and self.OnNewMount then
            self:OnNewMount(event, mountID)
        end
    elseif event == "NEW_PET_ADDED" then
        -- NEW_PET_ADDED returns petGUID (string: "BattlePet-0-..."), NOT speciesID!
        local petGUID = ...
        print("|cffffcc00[WN EventManager]|r NEW_PET_ADDED petGUID: " .. tostring(petGUID))
        if petGUID and self.OnNewPet then
            self:OnNewPet(event, petGUID)
        end
    elseif event == "NEW_TOY_ADDED" then
        -- Get itemID from event args
        local itemID = ...
        print("|cffffcc00[WN EventManager]|r NEW_TOY_ADDED itemID: " .. tostring(itemID))
        if itemID and self.OnNewToy then
            self:OnNewToy(event, itemID)
        end
    end
    
    -- Invalidate collection cache after any collection change
    self:InvalidateCollectionCache()
end


--[[
    Debounced PET_LIST_CHANGED handler
    Heavy operation, wait for changes to settle
]]
function WarbandNexus:OnPetListChangedDebounced()
    Debounce("PET_LIST_CHANGED", EVENT_CONFIG.THROTTLE.PET_LIST_CHANGED, function()
        self:OnPetListChanged()
    end)
end

--[[
    Throttled PVE_DATA_CHANGED handler
    Reduces redundant PvE data refreshes
]]
-- ============================================================================
-- PRIORITY EVENT HANDLERS
-- ============================================================================

--[[
    Process bank open with high priority
    UI-critical event, process immediately
]]
function WarbandNexus:OnBankOpenedPriority()
    QueueEvent("BANKFRAME_OPENED", EVENT_CONFIG.PRIORITY.CRITICAL, function()
        self:OnBankOpened()
    end)
    
    -- Process immediately (don't wait for queue processor)
    ProcessNextEvent()
end

--[[
    Process bank close with high priority
    UI-critical event, process immediately
]]
function WarbandNexus:OnBankClosedPriority()
    QueueEvent("BANKFRAME_CLOSED", EVENT_CONFIG.PRIORITY.CRITICAL, function()
        self:OnBankClosed()
    end)
    
    -- Process immediately
    ProcessNextEvent()
end

--[[
    Process manual UI refresh with high priority
    User-initiated, process quickly
    NOTE: Event-driven architecture - UI modules listen to data update events
]]
function WarbandNexus:RefreshUIWithPriority()
    -- Fire event for UI to refresh
    if self.SendMessage then
        self:SendMessage("WARBAND_CHARACTER_UPDATED")
        self:SendMessage("WARBAND_ITEMS_UPDATED")
    end
end

-- ============================================================================
-- EVENT STATISTICS & MONITORING
-- ============================================================================

--[[
    Get event processing statistics
    @return table - Event stats by type
]]
function WarbandNexus:GetEventStats()
    local stats = {
        processed = {},
        throttled = {},
        queued = {},
        pending = #eventQueue,
        activeTimers = 0,
    }
    
    -- Copy stats
    for event, count in pairs(eventStats.processed) do
        stats.processed[event] = count
    end
    for event, count in pairs(eventStats.throttled) do
        stats.throttled[event] = count
    end
    for event, count in pairs(eventStats.queued) do
        stats.queued[event] = count
    end
    
    -- Count active timers
    for _ in pairs(activeTimers) do
        stats.activeTimers = stats.activeTimers + 1
    end
    
    return stats
end

--[[
    Print event statistics to chat
]]
function WarbandNexus:PrintEventStats()
    local stats = self:GetEventStats()
    
    self:Print("===== Event Manager Statistics =====")
    self:Print(string.format("Pending Events: %d | Active Timers: %d", 
        stats.pending, stats.activeTimers))
    
    self:Print("Processed Events:")
    for event, count in pairs(stats.processed) do
        local throttled = stats.throttled[event] or 0
        local queued = stats.queued[event] or 0
        self:Print(string.format("  %s: %d (throttled: %d, queued: %d)", 
            event, count, throttled, queued))
    end
end

--[[
    Reset event statistics
]]
function WarbandNexus:ResetEventStats()
    eventStats = {
        processed = {},
        throttled = {},
        queued = {},
    }
    eventQueue = {}
end

-- ============================================================================
-- AUTOMATIC QUEUE PROCESSOR
-- ============================================================================

--[[
    Periodic queue processor
    Processes pending events every frame (if any exist)
]]
local function QueueProcessorTick()
    if #eventQueue > 0 then
        ProcessEventQueue(5) -- Process up to 5 events per frame
    end
end

-- Register frame update for queue processing
if WarbandNexus then
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, elapsed)
        QueueProcessorTick()
    end)
end

--[[
    Throttled SKILL_LINES_CHANGED handler
    Updates basic profession data
]]
function WarbandNexus:OnSkillLinesChanged()
    Throttle("SKILL_UPDATE", 2.0, function()
        -- Detect profession changes (unlearn/relearn detection)
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        local oldProfs = nil
        if self.db.global.characters and self.db.global.characters[key] then
            oldProfs = self.db.global.characters[key].professions
        end
        
        if self.UpdateProfessionData then
            self:UpdateProfessionData()
        end
        
        -- Check if professions changed (unlearned or new profession learned)
        if oldProfs and self.db.global.characters and self.db.global.characters[key] then
            local newProfs = self.db.global.characters[key].professions
            local professionChanged = false
            
            -- Check if primary professions changed
            for i = 1, 2 do
                local oldProf = oldProfs[i]
                local newProf = newProfs[i]
                
                -- If skillLine changed or profession was removed/added
                if (oldProf and newProf and oldProf.skillLine ~= newProf.skillLine) or
                   (oldProf and not newProf) or
                   (not oldProf and newProf) then
                    professionChanged = true
                    break
                end
            end
            
            -- Check if secondary professions changed (cooking, fishing, archaeology)
            if not professionChanged then
                local secondaryKeys = {"cooking", "fishing", "archaeology"}
                for _, profKey in ipairs(secondaryKeys) do
                    local oldProf = oldProfs[profKey]
                    local newProf = newProfs[profKey]
                    
                    -- If skillLine changed or profession was removed/added
                    if (oldProf and newProf and oldProf.skillLine ~= newProf.skillLine) or
                       (oldProf and not newProf) or
                       (not oldProf and newProf) then
                        professionChanged = true
                        break
                    end
                end
            end
            
            -- If a profession was changed, clear its expansion data to trigger refresh on next profession UI open
            if professionChanged then
                -- Clear primary professions
                for i = 1, 2 do
                    if newProfs[i] then
                        newProfs[i].expansions = nil
                    end
                end
                -- Clear secondary professions
                local secondaryKeys = {"cooking", "fishing", "archaeology"}
                for _, profKey in ipairs(secondaryKeys) do
                    if newProfs[profKey] then
                        newProfs[profKey].expansions = nil
                    end
                end
            end
        end
        
        -- Fire event for UI update
        if self.SendMessage then
            self:SendMessage("WARBAND_CHARACTER_UPDATED")
        end
    end)
end

--[[
    Throttled Item Level Change handler
    Updates character's average item level when equipment changes
]]
function WarbandNexus:OnItemLevelChanged()
    Throttle("ITEM_LEVEL_UPDATE", 0.3, function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if self.db.global.characters and self.db.global.characters[key] then
            -- Get current equipped item level
            local _, avgItemLevelEquipped = GetAverageItemLevel()
            
            -- Update in database
            self.db.global.characters[key].itemLevel = avgItemLevelEquipped
            self.db.global.characters[key].lastSeen = time()
            
            -- Invalidate cache to refresh UI
            if self.InvalidateCharacterCache then
                self:InvalidateCharacterCache()
            end
            
            -- Fire event for UI update
            if self.SendMessage then
                self:SendMessage("WARBAND_CHARACTER_UPDATED")
            end
        end
    end)
end

--[[
    Throttled Trade Skill events handler
    Updates detailed expansion profession data
]]
function WarbandNexus:OnTradeSkillUpdate()
    Throttle("TRADESKILL_UPDATE", 1.0, function()
        local updated = false
        if self.UpdateDetailedProfessionData then
            updated = self:UpdateDetailedProfessionData()
        end
        -- Only refresh UI if data was actually updated        
        if updated and self.SendMessage then
            self:SendMessage("WARBAND_PROFESSIONS_UPDATED")
        end
    end)
end

-- ============================================================================
-- REPUTATION & CURRENCY THROTTLED HANDLERS
-- ============================================================================

--[[
    Throttled reputation change handler
    Uses incremental updates when factionID is available
    @param event string - Event name
    @param ... - Event arguments (factionID for some events)
]]
function WarbandNexus:OnReputationChangedThrottled(event, ...)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("reputations") then
        return
    end
    
    local factionID = nil
    local newRenownLevel = nil
    
    -- Extract factionID from event payload
    if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        factionID, newRenownLevel = ... -- First arg is majorFactionID, second is new level
    elseif event == "MAJOR_FACTION_UNLOCKED" then
        factionID = ... -- First arg is majorFactionID
    end
    -- Note: UPDATE_FACTION doesn't provide factionID
    
    -- For immediate renown level changes, update without debounce
    if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" and factionID then
        -- CRITICAL: Incremental update for single faction (NO full scan)
        if self.UpdateReputationFaction then
            -- Use new incremental update function
            self:UpdateReputationFaction(factionID)
        elseif self.RefreshReputationCache then
            -- Fallback: full refresh with throttle protection
            self:RefreshReputationCache(false)  -- Don't force, respect cache age
        end
        
        -- Send message for UI update (single event)
        if self.SendMessage then
            self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
        
        -- Show notification for renown level up
        if newRenownLevel and C_MajorFactions then
            local majorData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorData and self.ShowToastNotification then
                local COLORS = ns.UI_COLORS or {accent = {0.2, 0.8, 1}}
                
                -- Try to get faction icon, fallback to scroll/parşömen icon
                local factionIcon = "Interface\\Icons\\INV_Scroll_11" -- Parchment/scroll fallback
                if majorData.textureKit then
                    -- Try major faction icon
                    factionIcon = string.format("Interface\\Icons\\UI_MajorFaction_%s", majorData.textureKit)
                elseif majorData.uiTextureKit then
                    factionIcon = string.format("Interface\\Icons\\UI_MajorFaction_%s", majorData.uiTextureKit)
                end
                
                self:ShowToastNotification({
                    icon = factionIcon,
                    title = "Renown Increased!",
                    message = string.format("%s is now Renown %d", majorData.name or "Faction", newRenownLevel),
                    color = COLORS.accent,
                    autoDismiss = 3,
                })
            end
        end
        return
    end
    
    -- For other reputation events, use debounce to prevent spam (increased to 0.5s)
    Debounce("REPUTATION_UPDATE", 0.5, function()
        -- CRITICAL: Call ReputationCacheService to update DB-backed cache
        if self.RefreshReputationCache then
            self:RefreshReputationCache(false)  -- Don't force, respect cache age (5s minimum)
        elseif self.ScanReputations then
            -- LEGACY FALLBACK: Old Scanner system
            self.currentTrigger = event or "REPUTATION_EVENT"
            self:ScanReputations()
        end
        
        -- Send message for UI update (single event)
        if self.SendMessage then
            self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
    end)
end

--[[
    Throttled currency change handler
    Uses incremental updates when currencyID is available
    @param event string - Event name
    @param currencyType number - Currency ID that changed
    @param quantity number - New quantity
    @param quantityChange number - Amount changed
    @param quantityGainSource number - Source of gain
    @param quantityLostSource number - Source of loss
]]
function WarbandNexus:OnCurrencyChangedThrottled(event, currencyType, quantity, quantityChange, ...)
    -- DEPRECATED: CurrencyCacheService handles currency updates now
    -- This function intentionally does nothing to avoid duplicate updates
    -- See: CurrencyCacheService.lua → RegisterCurrencyCacheEvents()
    -- The event registration is kept for compatibility but handler is disabled
    return
end

--[[
    Throttled PvE data change handler
    Handles Great Vault, M+, and raid lockout updates
    @param event string - Event name
]]
function WarbandNexus:OnPvEDataChangedThrottled(event)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("pve") then
        return
    end
    
    -- Request fresh data from Blizzard APIs
    if C_MythicPlus then
        C_MythicPlus.RequestMapInfo()
        C_MythicPlus.RequestRewards()
    end
    if C_WeeklyRewards then
        C_WeeklyRewards.OnUIInteract()
    end
    
    -- Wait for API responses (300ms delay for data to populate)
    C_Timer.After(0.3, function()
        Throttle("PVE_DATA_UPDATE", EVENT_CONFIG.THROTTLE.PVE_DATA_CHANGED, function()
            -- Route to PvECacheService (Phase 1)
            if self.UpdatePvEData then
                self:UpdatePvEData()
            elseif self.CollectPvEData then
                -- Fallback: Legacy DataService (will be removed in Phase 2)
                local pveData = self:CollectPvEData()
                if pveData then
                    local charKey = ns.Utilities:GetCharacterKey()
                    if self.UpdatePvEDataV2 then
                        self:UpdatePvEDataV2(charKey, pveData)
                    end
                    if self.SendMessage then
                        self:SendMessage(ns.Constants.EVENTS.PVE_UPDATED)
                    end
                end
            end
        end)
    end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    UI Scale/Resolution change handler
    Resets PixelScale cache and refreshes fonts when UI scale or resolution changes
]]
function WarbandNexus:OnUIScaleChanged()
    -- Reset pixel scale cache (force recalculation)
    if ns.ResetPixelScale then
        ns.ResetPixelScale()
    end
    
    -- Refresh all fonts with new scale
    if ns.FontManager and ns.FontManager.RefreshAllFonts then
        ns.FontManager:RefreshAllFonts()
    end
end

--[[
    Initialize event manager
    Called during OnEnable
]]
function WarbandNexus:InitializeEventManager()
    -- UI Scale/Resolution Events (immediate refresh for consistent rendering)
    self:RegisterEvent("UI_SCALE_CHANGED", "OnUIScaleChanged")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnUIScaleChanged")
    
    -- Replace bucket event with throttled version
    if self.UnregisterBucket then
        self:UnregisterBucket("BAG_UPDATE")
    end
    
    -- Register throttled bucket event
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdateThrottled")
    
    -- Replace collection events with debounced versions
    self:UnregisterEvent("NEW_MOUNT_ADDED")
    self:UnregisterEvent("NEW_PET_ADDED")
    self:UnregisterEvent("NEW_TOY_ADDED")
    self:UnregisterEvent("TOYS_UPDATED")
    self:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
    
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionChangedDebounced")
    -- TOYS_UPDATED removed - spams on every toy use/cooldown, bag scan handles loot detection
    self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED", "OnCollectionChangedDebounced")
    
    -- Replace pet list event with debounced version
    self:UnregisterEvent("PET_JOURNAL_LIST_UPDATE")
    self:RegisterEvent("PET_JOURNAL_LIST_UPDATE", "OnPetListChangedDebounced")
    
    -- Replace PvE events with throttled versions
    self:UnregisterEvent("WEEKLY_REWARDS_UPDATE")
    self:UnregisterEvent("UPDATE_INSTANCE_INFO")
    self:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
    
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnPvEDataChangedThrottled")
    self:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED", "OnPvEDataChangedThrottled")
    self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnPvEDataChangedThrottled")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnPvEDataChangedThrottled")
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", "OnPvEDataChangedThrottled")
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "OnPvEDataChangedThrottled")
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD", "OnPvEDataChangedThrottled")
    
    -- Profession Events
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkillLinesChanged")
    self:RegisterEvent("TRADE_SKILL_SHOW", "OnTradeSkillUpdate")
    self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", "OnTradeSkillUpdate")
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "OnTradeSkillUpdate")
    self:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", "OnTradeSkillUpdate")
    
    -- Item Level Events (throttled to avoid spam during rapid gear swaps)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnItemLevelChanged")
    self:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", "OnItemLevelChanged")
    
    -- Keystone tracking (optimized - check only keystone-related events)
    -- CHALLENGE_MODE_KEYSTONE_SLOTTED: Fired when a keystone is inserted into the pedestal
    self:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED", function()
        print("|cff00ffff[WN EventManager]|r Keystone slotted - checking inventory")
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE: Fired when keystones reset (weekly)
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
        print("|cff00ffff[WN EventManager]|r M+ affixes updated - checking keystones")
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- BAG_UPDATE_DELAYED: Check for keystones AND new collectibles (Rarity-style)
    -- This reduces checks from "every bag change" to "only keystone-related bag changes"
    local lastKeystoneCheck = 0
    local KEYSTONE_CHECK_THROTTLE = 2.0  -- Don't check more than once per 2 seconds
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        local now = GetTime()
        
        -- 1. Keystone check (throttled)
        if now - lastKeystoneCheck >= KEYSTONE_CHECK_THROTTLE then
            -- Quick scan: Check if any bag has a keystone item (158923 is base keystone item)
            local hasKeystoneInBags = false
            for bagID = 0, 4 do  -- Check only backpack bags
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                for slotID = 1, numSlots do
                    local itemID = C_Container.GetContainerItemID(bagID, slotID)
                    if itemID == 158923 or itemID == 180653 then  -- 158923 = Keystone, 180653 = Timeworn Keystone
                        hasKeystoneInBags = true
                        break
                    end
                end
                if hasKeystoneInBags then break end
            end
            
            -- Only check if we found a keystone OR if we had one before (to detect removal)
            if hasKeystoneInBags or (WarbandNexus.db and WarbandNexus.db.global.characters) then
                local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
                local hadKeystone = charKey and WarbandNexus.db.global.characters[charKey] and 
                                   WarbandNexus.db.global.characters[charKey].mythicKey
                
                if hasKeystoneInBags or hadKeystone then
                    lastKeystoneCheck = now
                    if WarbandNexus.OnKeystoneChanged then
                        WarbandNexus:OnKeystoneChanged()
                    end
                end
            end
        end
        
        -- 2. Collectible detection (Rarity-style bag scan - NO throttle)
        if WarbandNexus.OnBagUpdateForCollectibles then
            WarbandNexus:OnBagUpdateForCollectibles()
        end
    end)
    
    -- Replace reputation events with throttled versions
    self:UnregisterEvent("UPDATE_FACTION")
    self:UnregisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    self:UnregisterEvent("MAJOR_FACTION_UNLOCKED")
    self:UnregisterEvent("QUEST_LOG_UPDATE")
    
    self:RegisterEvent("UPDATE_FACTION", "OnReputationChangedThrottled")
    self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnReputationChangedThrottled")
    self:RegisterEvent("MAJOR_FACTION_UNLOCKED", "OnReputationChangedThrottled")
    -- Note: QUEST_LOG_UPDATE is too noisy for reputation, removed
    
    -- Currency events are handled by CurrencyCacheService (see CurrencyCacheService.lua)
    -- DEPRECATED: Old currency event handler disabled to avoid duplicate updates
    -- self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
    -- self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChangedThrottled")
    
    print("|cff00ff00[WN EventManager]|r Throttled event handlers registered (currency handled by CurrencyCacheService)")
end

-- Export EventManager and debugging info
ns.EventManager = WarbandNexus
ns.EventStats = eventStats
ns.EventQueue = eventQueue

print("|cff00ff00[WN EventManager]|r Exported to ns.EventManager")
