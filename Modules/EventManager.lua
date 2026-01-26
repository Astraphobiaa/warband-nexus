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
    -- Batch all bag IDs
    for bagID in pairs(bagIDs) do
        BatchEvent("BAG_UPDATE", bagID)
    end
    
    -- Throttled processing
    Throttle("BAG_UPDATE", EVENT_CONFIG.THROTTLE.BAG_UPDATE, function()
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
function WarbandNexus:OnCollectionChangedDebounced(event)
    Debounce("COLLECTION_CHANGED", EVENT_CONFIG.THROTTLE.COLLECTION_CHANGED, function()
        self:OnCollectionChanged(event)
        self:InvalidateCollectionCache() -- Invalidate cache after collection changes
    end, event)
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
function WarbandNexus:OnPvEDataChangedThrottled()
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.pve then
        return
    end
    
    Throttle("PVE_DATA_CHANGED", EVENT_CONFIG.THROTTLE.PVE_DATA_CHANGED, function()
        self:OnPvEDataChanged()
        
        -- Invalidate PvE cache for current character
        local playerKey = UnitName("player") .. "-" .. GetRealmName()
        self:InvalidatePvECache(playerKey)
    end)
end

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
]]
function WarbandNexus:RefreshUIWithPriority()
    QueueEvent("MANUAL_REFRESH", EVENT_CONFIG.PRIORITY.HIGH, function()
        self:RefreshUI()
    end)
    
    -- Process on next frame (allow other critical events first)
    C_Timer.After(0, ProcessNextEvent)
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
        
        -- Trigger UI update if necessary
        if self.RefreshUI then
            self:RefreshUI()
        end
    end)
end

--[[
    Throttled Item Level Change handler
    Updates character's average item level when equipment changes
]]
function WarbandNexus:OnItemLevelChanged()
    Throttle("ITEM_LEVEL_UPDATE", 1.0, function()
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
        if updated and self.RefreshUI then
            self:RefreshUI()
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
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.reputations then
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
        if self.UpdateSingleReputation then
            self:UpdateSingleReputation(factionID)
        end
        
        -- Send message immediately for renown changes
        if self.SendMessage then
            self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
        
        -- Refresh UI immediately for renown changes
        local mainFrame = self.UI and self.UI.mainFrame
        if mainFrame and mainFrame:IsShown() and self.RefreshUI then
            self:RefreshUI()
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
    
    -- For other reputation events, use debounce to prevent spam
    Debounce("REPUTATION_UPDATE", 0.1, function()
        if factionID and self.UpdateSingleReputation then
            -- Incremental update for specific faction
            self:UpdateSingleReputation(factionID)
        else
            -- Fallback: full scan (for UPDATE_FACTION which doesn't provide ID)
            if self.ScanReputations then
                self.currentTrigger = event or "REPUTATION_EVENT"
                self:ScanReputations()
            end
        end
        
        -- Send message for cache invalidation
        if self.SendMessage then
            self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
        
        -- Refresh UI if addon window is open and visible
        local mainFrame = self.UI and self.UI.mainFrame
        if mainFrame and mainFrame:IsShown() and self.RefreshUI then
            self:RefreshUI()
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
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.currencies then
        return
    end
    
    Debounce("CURRENCY_UPDATE", 0.3, function()
        if currencyType and self.UpdateSingleCurrency then
            -- Incremental update for specific currency
            self:UpdateSingleCurrency(currencyType)
        else
            -- Fallback: full update
            if self.UpdateCurrencyData then
                self:UpdateCurrencyData()
            end
        end
        
        -- INSTANT UI refresh if currency tab is open
        local mainFrame = self.UI and self.UI.mainFrame
        if mainFrame and mainFrame.currentTab == "currency" and self.RefreshUI then
            self:RefreshUI()
        end
    end)
end

--[[
    Throttled PvE data change handler
    Handles Great Vault, M+, and raid lockout updates
    @param event string - Event name
]]
function WarbandNexus:OnPvEDataChangedThrottled(event)
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.pve then
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
            -- Collect fresh PvE data
            if self.CollectPvEData then
                local pveData = self:CollectPvEData()
                if pveData then
                    -- Get current character key
                    local charKey = UnitName("player") .. "-" .. GetRealmName()
                    
                    -- Update database
                    if self.UpdatePvEDataV2 then
                        self:UpdatePvEDataV2(charKey, pveData)
                    end
                    
                    -- Send message for cache invalidation
                    if self.SendMessage then
                        self:SendMessage("WARBAND_PVE_UPDATED")
                    end
                    
                    -- INSTANT UI refresh if PvE tab is open
                    local mainFrame = self.UI and self.UI.mainFrame
                    if mainFrame and mainFrame.currentTab == "pve" and self.RefreshUI then
                        self:RefreshUI()
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
    
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("TOYS_UPDATED", "OnCollectionChangedDebounced")
    
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
    
    -- Keystone tracking (delayed bag events for M+ stones)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
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
    
    -- Replace currency event with throttled version
    self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChangedThrottled")
end

-- Export for debugging
ns.EventStats = eventStats
ns.EventQueue = eventQueue
