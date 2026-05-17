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
local Constants = ns.Constants
local E = Constants.EVENTS

-- Unique AceEvent handler identity for EventManager
local EventManagerEvents = {}

-- ============================================================================
-- EVENT CONFIGURATION
-- ============================================================================

local EVENT_CONFIG = {
    -- Throttle delays (seconds) - minimum time between processing
    THROTTLE = {
        COLLECTION_CHANGED = 0.5,    -- Debounce rapid collection additions
        PET_LIST_CHANGED = 2.0,      -- Very slow for pet caging
    },
}

local activeTimers = {}    -- Active throttle/debounce timers

-- ============================================================================
-- THROTTLE & DEBOUNCE UTILITIES
-- ============================================================================

--[[
    Throttle a function call
    Ensures function is not called more than once per interval
    @param key string - Unique throttle key
    @param interval number - Throttle interval (seconds)
    @param func function - Function to call
]]
local function Throttle(key, interval, func)
    -- If already throttled, skip
    if activeTimers[key] then
        return false
    end
    
    -- Set throttle timer BEFORE executing to prevent re-entrancy
    activeTimers[key] = C_Timer.NewTimer(interval, function()
        activeTimers[key] = nil
    end)
    
    -- Execute immediately
    func()
    
    return true
end

--[[
    Debounce a function call
    Delays execution until calls stop for specified interval
    @param key string - Unique debounce key
    @param interval number - Debounce interval (seconds)
    @param func function - Function to call
]]
local function Debounce(key, interval, func)
    -- Cancel existing timer
    if activeTimers[key] then
        activeTimers[key]:Cancel()
    end

    -- Set new timer
    activeTimers[key] = C_Timer.NewTimer(interval, function()
        activeTimers[key] = nil
        func()
    end)
end

-- ============================================================================
-- PUBLIC API (WarbandNexus Event Handlers)
-- ============================================================================

--[[
    Debounced COLLECTION_CHANGED handler
    Waits for rapid collection changes to settle
]]
function WarbandNexus:OnCollectionChangedDebounced(event, ...)
    -- TRANSMOG_COLLECTION_UPDATED: Debounced transmog + illusion handling
    -- (Only event still routed through EventManager — mount/pet/toy owned by CollectionService)
    if event == "TRANSMOG_COLLECTION_UPDATED" then
        Debounce("TRANSMOG_COLLECTION", EVENT_CONFIG.THROTTLE.COLLECTION_CHANGED, function()
            self:OnTransmogCollectionUpdated(event)
        end)
        return
    end
    
    -- Invalidate collection cache for any other collection change
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
    Throttled SKILL_LINES_CHANGED handler
    Updates basic profession data, expansion data, and detects profession changes.
]]
function WarbandNexus:OnSkillLinesChanged()
    Throttle("SKILL_UPDATE", 2.0, function()
        -- Delegate to ProfessionService ONLY if module is enabled
        -- (data collection, stale data cleanup, expansion refresh)
        if ns.Utilities and ns.Utilities:IsModuleEnabled("professions") then
            if self.OnProfessionChanged then
                self:OnProfessionChanged()
            end
        end

        -- CHARACTER_UPDATED always fires (basic character data, not profession-specific)
        local msgKey = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and ns.CharacterService:ResolveSubsidiaryCharacterKey(self, nil))
            or (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey())
        if msgKey and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
        end
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = msgKey,
            dataType = "professions"
        })
    end)
end

--[[
    Throttled Item Level Change handler
    Updates character's average item level when equipment changes
]]
function WarbandNexus:OnItemLevelChanged()
    Throttle("ITEM_LEVEL_UPDATE", 0.3, function()
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        local key = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
        if not key then return end
        local tableKey = key
        if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
            local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
            if resolved then tableKey = resolved end
        end
        -- Mirror SaveCurrentCharacterData: row may still be under legacy Name-Realm briefly vs Resolve guid slot.
        local chars = self.db.global.characters
        local entry = chars and (chars[tableKey] or chars[key])
        if entry then
            local _, avgItemLevelEquipped = GetAverageItemLevel()
            if issecretvalue and avgItemLevelEquipped and issecretvalue(avgItemLevelEquipped) then return end
            
            entry.itemLevel = avgItemLevelEquipped
            entry.lastSeen = time()
            
            -- Fire event for UI update (DB-First pattern)
            local msgKey = key
            if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                msgKey = ns.Utilities:GetCanonicalCharacterKey(key) or key
            end
            self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
                charKey = msgKey,
                dataType = "itemLevel"
            })
        end
    end)
end


-- ============================================================================
-- REPUTATION & CURRENCY EVENT OWNERSHIP
-- ============================================================================
-- UPDATE_FACTION / MAJOR_FACTION_RENOWN_LEVEL_CHANGED: owned by ReputationCacheService
-- CURRENCY_DISPLAY_UPDATE / CHAT_MSG_CURRENCY: owned by CurrencyCacheService
-- Do NOT register or handle these here — single owner prevents duplicate processing.

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

--[[
    Called when player money changes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:OnMoneyChanged()
    local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)

    -- Gold column on Characters tab: UpdateCharacterGold works for untracked too (DataService).
    if self.UpdateCharacterGold then
        self:UpdateCharacterGold()
    end

    if not tracked then
        return
    end

    -- Tracked-only: session char gold + currency-tab style refresh coalescing
    -- GetMoney() may be a secret value (Midnight+); never persist opaque/compare without guard.
    if self.db and self.db.char then
        local m = GetMoney()
        if m ~= nil and not (issecretvalue and issecretvalue(m)) then
            local n = tonumber(m)
            if n then
                self.db.char.lastKnownGold = n
            end
        end
    end

    if not self.moneyRefreshPending then
        self.moneyRefreshPending = true
        C_Timer.After(0.05, function()
            if WarbandNexus then
                WarbandNexus.moneyRefreshPending = false
                WarbandNexus:SendMessage(E.MONEY_UPDATED)
            end
        end)
    end
end




-- REMOVED: WarbandNexus:CHALLENGE_MODE_COMPLETED / MYTHIC_PLUS_NEW_WEEKLY_RECORD
-- These were orphaned methods never registered as AceEvent handlers.
-- PvECacheService owns the actual event registration and processing.

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

        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end

        local charKey = ns.Utilities:GetCharacterKey()
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        end
        -- SavedVariables may use a different string than canonical (ResolveCharactersTableKey)
        local charTableKey = charKey
        if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
            local resolved = ns.CharacterService:ResolveCharactersTableKey(WarbandNexus)
            if resolved then charTableKey = resolved end
        end
        
        -- Scan and update keystone data (lightweight check)
        if WarbandNexus.ScanMythicKeystone then
            local keystoneData = WarbandNexus:ScanMythicKeystone()
            
            if WarbandNexus.db and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charTableKey] then
                local oldKeystone = WarbandNexus.db.global.characters[charTableKey].mythicKey
                
                -- Only update if keystone actually changed
                local keystoneChanged = false
                if not oldKeystone and keystoneData then
                    keystoneChanged = true
                elseif oldKeystone and keystoneData then
                    local ol, nl = tonumber(oldKeystone.level), tonumber(keystoneData.level)
                    local om, nm = tonumber(oldKeystone.mapID), tonumber(keystoneData.mapID)
                    keystoneChanged = (ol ~= nl or om ~= nm)
                    -- keystoneChanged already set above
                elseif oldKeystone and not keystoneData then
                    keystoneChanged = true
                end
                
                if keystoneChanged then
                    WarbandNexus.db.global.characters[charTableKey].mythicKey = keystoneData
                    WarbandNexus.db.global.characters[charTableKey].lastSeen = time()
                    
                    -- Mirror into PvE cache so PvE tab matches Characters tab (same API snapshot)
                    if WarbandNexus.db.global.pveCache and WarbandNexus.db.global.pveCache.mythicPlus then
                        WarbandNexus.db.global.pveCache.mythicPlus.keystones = WarbandNexus.db.global.pveCache.mythicPlus.keystones or {}
                        if keystoneData and keystoneData.level and keystoneData.level > 0 and keystoneData.mapID then
                            WarbandNexus.db.global.pveCache.mythicPlus.keystones[charKey] = {
                                mapID = keystoneData.mapID,
                                level = keystoneData.level,
                                lastUpdate = keystoneData.scanTime or time(),
                            }
                        elseif keystoneData == nil and WarbandNexus.db.global.pveCache.mythicPlus.keystones then
                            WarbandNexus.db.global.pveCache.mythicPlus.keystones[charKey] = nil
                        end
                        if WarbandNexus.SavePvECache then
                            WarbandNexus:SavePvECache()
                        end
                    end
                    
                    -- Same channel as CHALLENGE_MODE_COMPLETED / PvECache (UI.lua + PlansManager listen)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED, charKey)
                    end
                else
                    -- Keystone unchanged (verbose logging removed)
                end
            end
        end
    end)
end

-- REMOVED: WarbandNexus:OnPvEDataChangedThrottled
-- Orphaned method — no call sites. PvECacheService handles PvE event throttling directly.

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    UI Scale/Resolution change handler
    Resets PixelScale cache and refreshes fonts when UI scale or resolution changes
]]
function WarbandNexus:OnUIScaleChanged()
    -- Immediately clear the pixel-scale cache so stale value is not used during this frame.
    if ns.ResetPixelScale then
        ns.ResetPixelScale()
    end

    -- Defer the actual font refresh to the next frame.
    -- UIParent:GetEffectiveScale() is only guaranteed to reflect the new scale on the
    -- frame AFTER UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED fires.  Calling
    -- RefreshAllFonts() synchronously here would sample the old effectiveScale, cache
    -- it into `mult`, and render every FontString at the wrong size until the next
    -- manual font change.  The border-registry handler in SharedWidgets already uses
    -- C_Timer.After(0) for the same reason.
    C_Timer.After(0, function()
        -- Reset again: the deferred call may arrive after another stale cache was built.
        if ns.ResetPixelScale then
            ns.ResetPixelScale()
        end
        if ns.FontManager and ns.FontManager.RefreshAllFonts then
            ns.FontManager:RefreshAllFonts()
        end
        local LC = ns.UI_LayoutCoordinator
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if LC and LC.OnDisplayMetricsChanged and mf and mf:IsShown() then
            LC:OnDisplayMetricsChanged(mf)
        end
    end)
end

-- Appearance + pet journal: high churn during cold login; not needed for T+0 UI/fonts/items.
-- Gated on profile `modulesEnabled.collections` and registered after COLLECTION_EM_DEFER_SEC
-- (InitializeEventManager already runs at T+0.5 from InitializationService).
local COLLECTION_EM_DEFER_SEC = 2.5

function WarbandNexus:EnsureEventManagerCollectionListeners()
    if self._wnEventMgrCollectionRegistered then return end
    if not (ns.Utilities and ns.Utilities:IsModuleEnabled("collections")) then return end
    if not self.RegisterEvent then return end
    self._wnEventMgrCollectionRegistered = true
    self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED", "OnCollectionChangedDebounced")
    self:RegisterEvent("PET_JOURNAL_LIST_UPDATE", "OnPetListChangedDebounced")
end

function WarbandNexus:ClearEventManagerCollectionListeners()
    if not self._wnEventMgrCollectionRegistered then return end
    if self.UnregisterEvent then
        self:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
        self:UnregisterEvent("PET_JOURNAL_LIST_UPDATE")
    end
    self._wnEventMgrCollectionRegistered = false
end

--[[
    Initialize event manager
    Called during OnEnable
]]
function WarbandNexus:InitializeEventManager()
    -- Idempotent: InitializationService may theoretically reschedule startup; AceEvent last-register-wins
    -- would drop handlers — bail after first successful setup.
    if self._wnEventManagerInitialized then
        return
    end
    self._wnEventManagerInitialized = true

    -- UI Scale/Resolution Events (immediate refresh for consistent rendering)
    self:RegisterEvent("UI_SCALE_CHANGED", "OnUIScaleChanged")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnUIScaleChanged")
    
    -- BAG_UPDATE: owned by ItemsCacheService (0.5s bucket, single owner)
    -- Do NOT register here — prevents duplicate scanning
    
    -- ── Collection events (single owner: CollectionService) ──
    -- NEW_MOUNT_ADDED, NEW_PET_ADDED, NEW_TOY_ADDED, ACHIEVEMENT_EARNED: registered when
    -- `modulesEnabled.collections` is on — see CollectionService:EnsureCollectionServiceRealtimeListeners.
    -- Each handler uses incremental updates + SendMessage(COLLECTION_UPDATED) — no EventManager routing needed.
    -- Do NOT register here — AceEvent allows only one handler per event per object,
    -- and re-registering here would OVERWRITE the CollectionService handlers.
    -- TRANSMOG + PET_JOURNAL: deferred + collections toggle — see EnsureEventManagerCollectionListeners.
    if not self._wnEventMgrCollectionMsgHooked and self.RegisterMessage then
        self._wnEventMgrCollectionMsgHooked = true
        self:RegisterMessage(E.MODULE_TOGGLED, function(_, moduleName, enabled)
            if moduleName ~= "collections" then return end
            if enabled then
                WarbandNexus:EnsureEventManagerCollectionListeners()
            else
                WarbandNexus:ClearEventManagerCollectionListeners()
            end
        end)
    end
    C_Timer.After(COLLECTION_EM_DEFER_SEC, function()
        if WarbandNexus then
            WarbandNexus:EnsureEventManagerCollectionListeners()
        end
    end)
    -- ACHIEVEMENT_EARNED: owned by CollectionService (EnsureCollectionServiceRealtimeListeners)
    -- TOYS_UPDATED: removed — spams on every toy use/cooldown
    
    -- PvE events are now handled by PvECacheService (RegisterPvECacheEvents)
    -- Removed duplicate registration to prevent conflicts
    
    -- Profession basic data (which professions a character has)
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkillLinesChanged")
    
    -- Profession window events (ProfessionService + RecipeCompanionWindow)
    -- All profession events are guarded: zero processing when module is disabled
    local IsModuleEnabled = ns.Utilities and ns.Utilities.IsModuleEnabled
    
    self:RegisterEvent("TRADE_SKILL_SHOW", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnTradeSkillShow then
            WarbandNexus:OnTradeSkillShow()
        end
    end)
    self:RegisterEvent("TRADE_SKILL_CLOSE", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnTradeSkillClose then
            WarbandNexus:OnTradeSkillClose()
        end
    end)
    
    -- Recipe learned event (update recipe knowledge incrementally)
    self:RegisterEvent("NEW_RECIPE_LEARNED", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnNewRecipeLearned then
            WarbandNexus:OnNewRecipeLearned()
        end
    end)
    
    -- Recipe list updated (fires after crafting, skill changes — refreshes firstCraft/canSkillUp)
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnTradeSkillListUpdate then
            WarbandNexus:OnTradeSkillListUpdate()
        end
    end)
    self:RegisterEvent("QUEST_TURNED_IN", function(event, questID, ...)
        -- Consolidated handler: DailyQuestManager + ProfessionService share this event.
        -- AceEvent allows ONE handler per (event, self) — DailyQuestManager no longer registers
        -- separately to avoid silent overwrite.
        if WarbandNexus.OnDailyQuestCompleted then
            WarbandNexus:OnDailyQuestCompleted(event, questID, ...)
        end
        if IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions") then
            if WarbandNexus.OnProfessionQuestProgressChanged then
                WarbandNexus:OnProfessionQuestProgressChanged()
            end
        end
    end)
    
    -- ====== REAL-TIME PROFESSION UPDATES ======
    
    -- Concentration: piggyback on CurrencyCacheService's output
    -- WN_CURRENCY_UPDATED fires with currencyID when a single currency changes.
    -- We check if it's a concentration currency and refresh if so.
    -- NOTE: Uses EventManagerEvents as 'self' key to avoid overwriting CurrencyUI's handler.
    WarbandNexus.RegisterMessage(EventManagerEvents, E.CURRENCY_UPDATED, function(_, currencyID)
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if currencyID and WarbandNexus.OnConcentrationCurrencyChanged then
            WarbandNexus:OnConcentrationCurrencyChanged(currencyID)
        end
        if currencyID and WarbandNexus.OnProfessionProgressCurrencyChanged then
            WarbandNexus:OnProfessionProgressCurrencyChanged(currencyID)
        end
    end)
    
    -- Knowledge: TRAIT_NODE_CHANGED fires when profession spec points are spent
    -- TRAIT_CONFIG_UPDATED fires when spec tree is modified
    self:RegisterEvent("TRAIT_NODE_CHANGED", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnKnowledgeChanged then
            WarbandNexus:OnKnowledgeChanged()
        end
    end)
    
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", function()
        if not (IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions")) then return end
        if WarbandNexus.OnKnowledgeChanged then
            WarbandNexus:OnKnowledgeChanged()
        end
    end)
    
    -- Periodic recharge timer: 60s tick for UI recalculation
    -- Only start if professions module is enabled AND character is tracked
    C_Timer.After(5, function()
        if not (ns.Utilities and ns.Utilities:IsModuleEnabled("professions")) then return end
        if not (ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus)) then return end
        if WarbandNexus and WarbandNexus.StartRechargeTimer then
            WarbandNexus:StartRechargeTimer()
        end
    end)
    
    -- Initialize Recipe Companion Window (deferred: UI modules must be loaded)
    C_Timer.After(0.1, function()
        if WarbandNexus and WarbandNexus.InitializeRecipeCompanion then
            WarbandNexus:InitializeRecipeCompanion()
        end
    end)
    
    -- Item Level Events (throttled to avoid spam during rapid gear swaps)
    -- PLAYER_EQUIPMENT_CHANGED: also check profession equipment slots (20, 21, 22)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
        -- Item level update (existing)
        if WarbandNexus.OnItemLevelChanged then
            WarbandNexus:OnItemLevelChanged()
        end
        -- Gear cache update (equipped slots 1-17)
        if WarbandNexus.OnGearEquipmentChanged then
            WarbandNexus:OnGearEquipmentChanged(slot)
        end
        -- Profession equipment update (slot-filtered in handler)
        if IsModuleEnabled and ns.Utilities:IsModuleEnabled("professions") then
            if WarbandNexus.OnEquipmentChanged then
                WarbandNexus:OnEquipmentChanged(slot)
            end
        end
    end)
    self:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", "OnItemLevelChanged")
    
    -- Keystone tracking (optimized - check only keystone-related events)
    -- CHALLENGE_MODE_KEYSTONE_SLOTTED: Fired when a keystone is inserted into the pedestal
    self:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED", function()
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE: owned by PvECacheService (weekly reset + keystone refresh)
    
    -- BAG_UPDATE_DELAYED: owned by ItemsCacheService (single owner)
    -- Keystone detection + collectible checks are integrated there
    
    -- UPDATE_FACTION / MAJOR_FACTION_RENOWN_*: owned by ReputationCacheService (SnapshotDiff)
    -- CURRENCY_DISPLAY_UPDATE: owned by CurrencyCacheService (FIFO queue)
    -- Concentration piggyback: via WN_CURRENCY_CHANGED message (see above)
    
end

-- Export EventManager
ns.EventManager = WarbandNexus
