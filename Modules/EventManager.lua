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

-- Debug print helper (only prints if debug mode enabled)
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print(...)
    end
end

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

-- OnBagUpdateThrottled: REMOVED — BAG_UPDATE owned by ItemsCacheService (0.5s bucket)

--[[
    Debounced COLLECTION_CHANGED handler
    Waits for rapid collection changes to settle
]]
function WarbandNexus:OnCollectionChangedDebounced(event, ...)
    DebugPrint("|cff9370DB[WN EventManager]|r [Collection Event] " .. event .. " triggered")
    
    -- Handle TRANSMOG_COLLECTION_UPDATED separately (includes illusions)
    if event == "TRANSMOG_COLLECTION_UPDATED" then
        Debounce("TRANSMOG_COLLECTION", EVENT_CONFIG.THROTTLE.COLLECTION_CHANGED, function()
            self:OnTransmogCollectionUpdated(event)
        end)
        return
    end
    
    -- CRITICAL FIX: Route to correct CollectionService handlers
    -- Each event needs its own handler with event-specific data
    if event == "NEW_MOUNT_ADDED" then
        -- Get mountID from event args (first arg after event name)
        local mountID = ...
        if mountID and self.OnNewMount then
            self:OnNewMount(event, mountID)
        end
    elseif event == "NEW_PET_ADDED" then
        -- NEW_PET_ADDED returns petGUID (string: "BattlePet-0-..."), NOT speciesID!
        local petGUID = ...
        if petGUID and self.OnNewPet then
            self:OnNewPet(event, petGUID)
        end
    elseif event == "NEW_TOY_ADDED" then
        -- Get itemID from event args
        local itemID = ...
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
-- REMOVED: RefreshUIWithPriority() - never called, event-driven architecture handles refreshes

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
    DebugPrint("|cff9370DB[WN EventManager]|r [Profession Event] SKILL_LINES_CHANGED triggered")
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
        
        -- Fire event for UI update (DB-First pattern)
        local Constants = ns.Constants
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = key,
            dataType = "professions"
        })
    end)
end

--[[
    Throttled Item Level Change handler
    Updates character's average item level when equipment changes
]]
function WarbandNexus:OnItemLevelChanged()
    DebugPrint("|cff9370DB[WN EventManager]|r [ItemLevel Event] PLAYER_EQUIPMENT_CHANGED triggered")
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
            
            -- Fire event for UI update (DB-First pattern)
            local Constants = ns.Constants
            self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
                charKey = key,
                dataType = "itemLevel"
            })
        end
    end)
end

--[[
    Throttled Trade Skill events handler
    Updates detailed expansion profession data
]]
function WarbandNexus:OnTradeSkillUpdate()
    DebugPrint("|cff9370DB[WN EventManager]|r [Profession Event] TRADE_SKILL_* triggered")
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
    Throttled reputation change handler (v2.0.0)
    Routes events to new ReputationCacheService
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
        -- INCREMENTAL UPDATE: Single faction only (v2.0.0)
        if self.UpdateReputationFaction then
            self:UpdateReputationFaction(factionID)
        end
        
        -- Show notification for renown level up
        if newRenownLevel and C_MajorFactions then
            local majorData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorData and self.Notify then
                -- Try to get faction icon, fallback to reputation category icon
                local factionIcon = "Interface\\Icons\\INV_Scroll_11"
                if majorData.textureKit then
                    factionIcon = string.format("Interface\\Icons\\UI_MajorFaction_%s", majorData.textureKit)
                elseif majorData.uiTextureKit then
                    factionIcon = string.format("Interface\\Icons\\UI_MajorFaction_%s", majorData.uiTextureKit)
                end
                
                self:Notify("reputation", "Renown Increased!", factionIcon, {
                    action = string.format("%s is now Renown %d", majorData.name or "Faction", newRenownLevel),
                })
            end
        end
        return
    end
    
    -- For other reputation events, short debounce (matches ReputationCacheService)
    Debounce("REPUTATION_UPDATE", 0.15, function()
        if self.RefreshReputationCache then
            self:RefreshReputationCache(false)
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
-- REMOVED: OnCurrencyChangedThrottled() - deprecated, handled by CurrencyCacheService

--[[
    Called when player money changes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:OnMoneyChanged()
    DebugPrint("|cff9370DB[WN EventManager]|r [Money Event] PLAYER_MONEY/ACCOUNT_MONEY triggered")
    
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Store last known gold in char-specific DB
    self.db.char.lastKnownGold = GetMoney()
    
    -- Update character gold via DataService
    if self.UpdateCharacterGold then
        self:UpdateCharacterGold()
    end
    
    -- Fire event for UI refresh (instead of direct RefreshUI call)
    -- Use short delay to debounce rapid money changes (loot, vendor)
    if not self.moneyRefreshPending then
        self.moneyRefreshPending = true
        C_Timer.After(0.05, function()
            if WarbandNexus then
                WarbandNexus.moneyRefreshPending = false
                WarbandNexus:SendMessage("WN_MONEY_UPDATED")
            end
        end)
    end
end

--[[
    Called when currency changes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:OnCurrencyChanged()
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.currencies then
        return
    end
    
    -- Update currency data via DataService
    if self.UpdateCurrencyData then
        self:UpdateCurrencyData()
    end
    
    -- Fire event for UI refresh (instead of direct RefreshUI call)
    -- Use short delay to batch multiple currency events
    if not self.currencyRefreshPending then
        self.currencyRefreshPending = true
        C_Timer.After(0.1, function()
            if WarbandNexus then
                WarbandNexus.currencyRefreshPending = false
                WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
            end
        end)
    end
end

--[[
    Called when M+ dungeon run completes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:CHALLENGE_MODE_COMPLETED(mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels)
    local charKey = ns.Utilities:GetCharacterKey()
    
    -- Re-collect PvE data via DataService
    if self.CollectPvEData then
        local pveData = self:CollectPvEData()
        
        -- Update via DataService
        if self.UpdatePvEDataV2 and self.db.global.characters and self.db.global.characters[charKey] then
            self:UpdatePvEDataV2(charKey, pveData)
        end
        
        -- Fire event for UI refresh (instead of direct call)
        self:SendMessage("WN_PVE_UPDATED", charKey)
    end
end

--[[
    Called when new weekly M+ record is set
    Delegates to PvE data update
]]
function WarbandNexus:MYTHIC_PLUS_NEW_WEEKLY_RECORD()
    -- Same logic as CHALLENGE_MODE_COMPLETED
    self:CHALLENGE_MODE_COMPLETED()
end

--[[
    Called when keystone changes (picked up, upgraded, depleted)
    Delegates to DataService for business logic
]]
function WarbandNexus:OnKeystoneChanged()
    -- Throttle keystone checks to avoid spam
    if self.keystoneCheckPending then
        return
    end
    
    self.keystoneCheckPending = true
    C_Timer.After(0.5, function()
        if not WarbandNexus then return end
        WarbandNexus.keystoneCheckPending = false
        
        local charKey = ns.Utilities:GetCharacterKey()
        
        -- Scan and update keystone data (lightweight check)
        if WarbandNexus.ScanMythicKeystone then
            local keystoneData = WarbandNexus:ScanMythicKeystone()
            
            if WarbandNexus.db and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey] then
                local oldKeystone = WarbandNexus.db.global.characters[charKey].mythicKey
                
                -- Only update if keystone actually changed
                local keystoneChanged = false
                if not oldKeystone and keystoneData then
                    keystoneChanged = true
                elseif oldKeystone and keystoneData then
                    keystoneChanged = (oldKeystone.level ~= keystoneData.level or 
                                     oldKeystone.mapID ~= keystoneData.mapID)
                    -- keystoneChanged already set above
                elseif oldKeystone and not keystoneData then
                    keystoneChanged = true
                end
                
                if keystoneChanged then
                    WarbandNexus.db.global.characters[charKey].mythicKey = keystoneData
                    WarbandNexus.db.global.characters[charKey].lastSeen = time()
                    
                    -- Fire event for UI update (only PvE tab needs refresh)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WARBAND_PVE_UPDATED")
                    end
                    
                    -- Invalidate cache to refresh UI
                    if WarbandNexus.InvalidateCharacterCache then
                        WarbandNexus:InvalidateCharacterCache()
                    end
                else
                    -- Keystone unchanged (verbose logging removed)
                end
            end
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
    
    -- BAG_UPDATE: owned by ItemsCacheService (0.5s bucket, single owner)
    -- Do NOT register here — prevents duplicate scanning
    
    -- ── Collection events (single owner: EventManager → CollectionService) ──
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionChangedDebounced")
    self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED", "OnCollectionChangedDebounced")
    self:RegisterEvent("PET_JOURNAL_LIST_UPDATE", "OnPetListChangedDebounced")
    -- ACHIEVEMENT_EARNED: owned by CollectionService (file-level registration)
    -- TOYS_UPDATED: removed — spams on every toy use/cooldown
    
    -- PvE events are now handled by PvECacheService (RegisterPvECacheEvents)
    -- Removed duplicate registration to prevent conflicts
    
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
    DebugPrint("|cff9370DB[WN EventManager]|r [Keystone Event] CHALLENGE_MODE_KEYSTONE_SLOTTED triggered")
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE: owned by PvECacheService (weekly reset + keystone refresh)
    
    -- BAG_UPDATE_DELAYED: owned by ItemsCacheService (single owner)
    -- Keystone detection + collectible checks are integrated there
    
    -- UPDATE_FACTION / MAJOR_FACTION_RENOWN_*: owned by ReputationCacheService (SnapshotDiff)
    -- CURRENCY_DISPLAY_UPDATE: owned by CurrencyCacheService (FIFO queue)
    -- Do NOT register here — single owner prevents duplicate processing
    
    -- ElvUI detection (informational for debugging compatibility)
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") then
        DebugPrint("[WarbandNexus] ElvUI detected - using compatible rendering mode")
    end
end

-- Export EventManager and debugging info
ns.EventManager = WarbandNexus
ns.EventStats = eventStats
ns.EventQueue = eventQueue

-- EventManager exported (verbose logging removed)
