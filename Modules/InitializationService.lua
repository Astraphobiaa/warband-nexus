--[[
    WarbandNexus - Initialization Service
    Manages addon module initialization with proper sequencing
    
    Responsibilities:
    - Coordinate module startup sequence
    - Manage initialization timings (prevent addon load lag)
    - Handle dependencies between modules
    - Centralize all C_Timer.After() calls
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

---@class InitializationService
local InitializationService = {}
ns.InitializationService = InitializationService

-- Combat-safe init: pending inits run after PLAYER_REGEN_ENABLED if timer fired during combat
local pendingInits = {}
local combatSafetyFrame = nil

--[[
    Combat-safety frame for deferred initializations.
    Frame:RegisterEvent() is protected during combat (/reload in combat).
    If OnEnable fires during lockdown, we use OnUpdate polling to wait, then register.
    OnUpdate + SetScript("OnUpdate") are NOT protected — they work during lockdown.
]]
local combatSafetyRegistered = false

local function EnsureCombatSafetyEvent()
    if combatSafetyRegistered then return end
    if InCombatLockdown() then return end
    combatSafetyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatSafetyRegistered = true
end

function InitializationService:SetupCombatSafety()
    if combatSafetyFrame then return end
    combatSafetyFrame = CreateFrame("Frame")

    combatSafetyFrame:SetScript("OnEvent", function()
        if #pendingInits == 0 then return end
        local queue = pendingInits
        pendingInits = {}
        -- Defer 0.1s: PLAYER_REGEN_ENABLED can fire before lockdown is fully lifted
        C_Timer.After(0.1, function()
            if InCombatLockdown() then
                for i = 1, #queue do
                    table.insert(pendingInits, queue[i])
                end
                return
            end
            for i = 1, #queue do
                DebugPrint("|cff00ff00[Init]|r Combat ended - executing: " .. (queue[i].label or "?"))
                queue[i].fn()
            end
        end)
    end)

    -- NEVER call RegisterEvent inline — always defer to first OnUpdate frame.
    -- InCombatLockdown() can return false during loading screen while RegisterEvent
    -- is still protected (/reload edge case).
    combatSafetyFrame:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then return end
        EnsureCombatSafetyEvent()
        self:SetScript("OnUpdate", nil)
        -- Flush any pending inits that queued while we waited
        if #pendingInits > 0 then
            local queue = pendingInits
            pendingInits = {}
            for i = 1, #queue do
                DebugPrint("|cff00ff00[Init]|r Lockdown lifted - executing: " .. (queue[i].label or "?"))
                queue[i].fn()
            end
        end
    end)
end

--[[
    Run fn now if out of combat; otherwise queue for combat end.
    Uses combatSafetyFrame (PLAYER_REGEN_ENABLED or OnUpdate fallback) to drain queue.
]]
local function SafeInit(fn, label)
    if not InCombatLockdown() then
        fn()
    else
        DebugPrint("|cffff9900[Init]|r Deferred (combat): " .. (label or "?"))
        table.insert(pendingInits, { fn = fn, label = label })
    end
end

-- Expose for Core.lua deferred inits (e.g. InitializePlanTracking, InitializeChatMessageService)
InitializationService.SafeInit = SafeInit

--[[
    Initialize all addon modules in proper sequence
    Called from OnEnable after basic event registration
]]
function InitializationService:InitializeAllModules(addon)
    if not addon then
        DebugPrint("|cffff0000[WN InitializationService]|r No addon instance provided!")
        return
    end

    self:SetupCombatSafety()

    -- STAGE 1: Core Infrastructure (0-0.5s)
    self:InitializeCoreInfrastructure(addon)
    
    -- STAGE 2: Data Services (1-2s)
    self:InitializeDataServices(addon)
    
    -- STAGE 3: UI & Utilities (1-2s)
    self:InitializeUIServices(addon)
    
    -- STAGE 4: Background Services (3-5s)
    self:InitializeBackgroundServices(addon)
    
    -- STAGE 5: Success Message (REMOVED - welcome message now in Core.lua OnEnable())
    -- C_Timer.After(1, function()
    --     if addon and addon.Print then
    --         local L = ns.L or {}
    --         addon:Print(L["ADDON_LOADED"] or "Warband Nexus loaded!")
    --     end
    -- end)
end

--[[
    STAGE 1: Core Infrastructure
    Essential systems that other modules depend on
]]
function InitializationService:InitializeCoreInfrastructure(addon)
    -- API Wrapper: Must load first (other modules may use it)
    if addon.InitializeAPIWrapper then
        addon:InitializeAPIWrapper()
    end
    
    -- Notification System: Initialize event listeners (0.5s)
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.InitializeLootNotifications then
                addon:InitializeLootNotifications()
            else
                DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeLootNotifications not found!")
            end
        end, "LootNotifications")
    end)

    -- Event Manager: Throttled/debounced event handling (0.5s)
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.InitializeEventManager then
                addon:InitializeEventManager()
            end
        end, "EventManager")
    end)
    
    -- Character Tracking Confirmation: Check for new characters (0.5s)
    C_Timer.After(0.5, function()
        if not addon or not addon.db or not addon.db.global then return end
        
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        local charData = addon.db.global.characters and addon.db.global.characters[charKey]
        
        -- Debug: Show character tracking status
        if charData then
            DebugPrint(string.format("[Init] Character exists: %s, isTracked=%s, trackingConfirmed=%s", 
                charKey, 
                tostring(charData.isTracked), 
                tostring(charData.trackingConfirmed)))
        else
            DebugPrint(string.format("[Init] Character NOT in DB: %s", charKey))
        end
        
        -- Only show popup if:
        -- 1. Character doesn't exist in DB, OR
        -- 2. Character exists but trackingConfirmed flag is not set (legacy characters)
        local shouldShowPopup = not charData or not charData.trackingConfirmed
        
        if shouldShowPopup then
            DebugPrint("[Init] Character needs tracking confirmation - showing popup")
            
            -- CRITICAL: DON'T set trackingConfirmed here!
            -- The flag will be set by ConfirmCharacterTracking() when user makes a choice
            -- This prevents the popup from appearing again
            
            -- Create stub entry with isTracked = false (prevents auto-save until user confirms)
            if not addon.db.global.characters then
                addon.db.global.characters = {}
            end
            if not addon.db.global.characters[charKey] then
                addon.db.global.characters[charKey] = {}
            end
            
            -- Only set isTracked if not already set (preserve existing choice)
            if addon.db.global.characters[charKey].isTracked == nil then
                addon.db.global.characters[charKey].isTracked = false
            end
            addon.db.global.characters[charKey].lastSeen = time()
            
            C_Timer.After(2, function()
                if ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                    ns.CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
                end
            end)
        else
            DebugPrint("[Init] Character tracking already confirmed, skipping popup")
            
            -- Returning user (already tracked): show What's New on first login after update
            -- Trigger with 1.5s delay to ensure DB and UI are ready
            C_Timer.After(1.5, function()
                if addon and addon.CheckNotificationsOnLogin then
                    addon:CheckNotificationsOnLogin()
                end
            end)
        end
    end)
end

--[[
    STAGE 2: Data Services
    Services that collect and process game data
]]
function InitializationService:InitializeDataServices(addon)
    -- Daily Quest Manager: Quest tracking and plan updates (1s)
    C_Timer.After(1, function()
        SafeInit(function()
            if addon and addon.InitializeDailyQuestManager then
                addon:InitializeDailyQuestManager()
            end
        end, "DailyQuestManager")
    end)

    -- Collection Tracking, Try Counter, Character/PvE/Items caches (1s) — combat-safe
    C_Timer.After(1, function()
        SafeInit(function()
            -- Load persisted cache from DB (uncollected items for Browse UI)
            if addon and addon.InitializeCollectionCache then
                addon:InitializeCollectionCache()
            end

            -- Build owned cache in RAM (for real-time detection)
            if addon and addon.BuildCollectionCache then
                addon:BuildCollectionCache()
            end

            -- Try counter (manual + LOOT_OPENED when mapping exists)
            if addon and addon.InitializeTryCounter then
                addon:InitializeTryCounter()
            end

            -- TRACKING GUARD: Only initialize data caches for tracked characters
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)

            if isTracked then
                if addon and addon.InitializeCurrencyCache then
                    addon:InitializeCurrencyCache()
                end
            else
                DebugPrint("|cff808080[Init]|r Character not tracked - skipping Reputation/Currency cache initialization")
            end

            -- Register Character Cache Events (DataService layer)
            if addon and addon.RegisterCharacterCacheEvents then
                addon:RegisterCharacterCacheEvents()
            end

            -- Initialize character cache (first population)
            if addon and addon.GetCharacterData then
                addon:GetCharacterData(true)  -- Force initial population
            end

            -- TRACKING GUARD: Only initialize PvE/Items caches for tracked characters
            if isTracked then
                if addon and addon.RegisterPvECacheEvents then
                    addon:RegisterPvECacheEvents()
                end
                if addon and addon.InitializePvECache then
                    addon:InitializePvECache()
                end
                if addon and addon.InitializeItemsCache then
                    addon:InitializeItemsCache()
                end

                -- Request M+ and Weekly Rewards data (inside isTracked guard)
                -- Moved here from a separate C_Timer.After(1) closure to fix scoping bug:
                -- isTracked was previously referenced in a different closure where it was nil.
                if C_MythicPlus then
                    C_MythicPlus.RequestMapInfo()
                    C_MythicPlus.RequestRewards()
                    C_MythicPlus.RequestCurrentAffixes()
                end
                if C_WeeklyRewards then
                    C_WeeklyRewards.OnUIInteract()
                end
            else
                DebugPrint("|cff808080[Init]|r Character not tracked - skipping PvE/Items cache initialization")
            end
        end, "DataServices")
    end)
    
    -- Cache Manager: Smart caching for performance (2s)
    C_Timer.After(2, function()
        if addon and addon.WarmupCaches then
            addon:WarmupCaches()
        end
    end)
end

--[[
    STAGE 3: UI & Utilities
    Tooltip, minimap, and visual systems
]]
function InitializationService:InitializeUIServices(addon)
    -- Tooltip Service: Initialize central tooltip system (0.3s)
    C_Timer.After(0.3, function()
        if addon and addon.Tooltip and addon.Tooltip.Initialize then
            addon.Tooltip:Initialize()
        end
    end)
    
    -- Tooltip Injection: GameTooltip hook for item counts (1s) — registers PLAYER_LEAVING_WORLD
    C_Timer.After(1, function()
        SafeInit(function()
            if addon and addon.Tooltip and addon.Tooltip.InitializeGameTooltipHook then
                addon.Tooltip:InitializeGameTooltipHook()
            end
        end, "TooltipHook")
    end)
    
    -- Statistics UI: Initialize event listeners (0.5s)
    C_Timer.After(0.5, function()
        if addon and addon.InitializeStatisticsUI then
            addon:InitializeStatisticsUI()
        end
    end)
    
    -- Minimap Button: LibDBIcon integration (handled in OnInitialize)
    -- Note: Already initialized in OnInitialize, no need to duplicate here
end

--[[
    STAGE 4: Background Services
    Non-critical systems that can load later
]]
function InitializationService:InitializeBackgroundServices(addon)
    -- Error Handler: Wrap critical functions (1.5s)
    -- NOTE: Must run AFTER all other modules are loaded
    C_Timer.After(1.5, function()
        if addon and addon.InitializeErrorHandler then
            addon:InitializeErrorHandler()
        end
    end)
    
    --[[
        [DEPRECATED] CollectionScanner removed - now using CollectionService
        CollectionService auto-initializes via Core.lua and loads cache from DB
        No manual initialization needed - cache is persistent and loaded on addon load
    ]]
    
    -- [REMOVED] Legacy CollectionScanner:Initialize() call (7 lines removed)
    -- CollectionService is now initialized automatically in Core.lua:OnInitialize
    
    -- Database Optimizer: Auto-cleanup and optimization (5s)
    C_Timer.After(5, function()
        if addon and addon.InitializeDatabaseOptimizer then
            addon:InitializeDatabaseOptimizer()
        end
    end)
end

--[[
    Initialize minimap button (called from OnInitialize)
    This is separate because it needs database to be ready first
]]
function InitializationService:InitializeMinimapButton(addon)
    C_Timer.After(1, function()
        if addon and addon.InitializeMinimapButton then
            addon:InitializeMinimapButton()
        end
    end)
end

return InitializationService
