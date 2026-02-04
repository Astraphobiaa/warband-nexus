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

--[[
    Initialize all addon modules in proper sequence
    Called from OnEnable after basic event registration
]]
function InitializationService:InitializeAllModules(addon)
    if not addon then
        DebugPrint("|cffff0000[WN InitializationService]|r No addon instance provided!")
        return
    end
    
    -- Starting module initialization (verbose logging removed)
    
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
    
    -- Module Manager: Event-driven module toggles
    if addon.InitializeModuleManager then
        addon:InitializeModuleManager()
    end
    
    -- Notification System: Initialize event listeners (0.5s)
    C_Timer.After(0.5, function()
        if addon and addon.InitializeLootNotifications then
            addon:InitializeLootNotifications()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeLootNotifications not found!")
        end
    end)
    
    -- Event Manager: Throttled/debounced event handling (0.5s)
    C_Timer.After(0.5, function()
        if addon and addon.InitializeEventManager then
            addon:InitializeEventManager()
        end
    end)
    
    -- Character Tracking Confirmation: Check for new characters (0.5s)
    C_Timer.After(0.5, function()
        if not addon or not addon.db or not addon.db.global then return end
        
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        local isNew = not addon.db.global.characters or not addon.db.global.characters[charKey]
        
        if isNew then
            DebugPrint("[Init] New character detected - showing tracking confirmation")
            C_Timer.After(2, function()
                if ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                    ns.CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
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
        if addon and addon.InitializeDailyQuestManager then
            addon:InitializeDailyQuestManager()
        end
    end)
    
    -- Collection Tracking: Load cache and build owned cache (1s)
    C_Timer.After(1, function()
        -- Load persisted cache from DB (uncollected items for Browse UI)
        if addon and addon.InitializeCollectionCache then
            addon:InitializeCollectionCache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeCollectionCache not found!")
        end
        
        -- Build owned cache in RAM (for real-time detection)
        if addon and addon.BuildCollectionCache then
            addon:BuildCollectionCache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: BuildCollectionCache not found!")
        end
        
        -- Initialize Reputation Cache (DB-backed)
        if addon and addon.InitializeReputationCache then
            addon:InitializeReputationCache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeReputationCache not found!")
        end
        
        -- Register Reputation Cache Events
        if addon and addon.RegisterReputationCacheEvents then
            addon:RegisterReputationCacheEvents()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: RegisterReputationCacheEvents not found!")
        end
        
        -- Initialize Currency Cache (DB-backed)
        if addon and addon.InitializeCurrencyCache then
            addon:InitializeCurrencyCache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeCurrencyCache not found!")
        end
        
        -- Register Currency Cache Events
        if addon and addon.RegisterCurrencyCacheEvents then
            addon:RegisterCurrencyCacheEvents()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: RegisterCurrencyCacheEvents not found!")
        end
        
        -- Register Character Cache Events (DataService layer)
        if addon and addon.RegisterCharacterCacheEvents then
            addon:RegisterCharacterCacheEvents()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: RegisterCharacterCacheEvents not found!")
        end
        
        -- Initialize character cache (first population)
        if addon and addon.GetCharacterData then
            addon:GetCharacterData(true)  -- Force initial population
        end
        
        -- Initialize PvE Cache Service (DB-backed)
        if addon and addon.InitializePvECache then
            addon:InitializePvECache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializePvECache not found!")
        end
        
        -- Initialize Items Cache Service (DB-backed)
        if addon and addon.InitializeItemsCache then
            addon:InitializeItemsCache()
        else
            DebugPrint("|cffff0000[WN InitializationService]|r ERROR: InitializeItemsCache not found!")
        end
    end)
    
    -- Request M+ and Weekly Rewards data (1s)
    C_Timer.After(1, function()
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestRewards()
            C_MythicPlus.RequestCurrentAffixes()
        end
        if C_WeeklyRewards then
            C_WeeklyRewards.OnUIInteract()
        end
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
    
    -- Tooltip Injection: GameTooltip hook for item counts (1s)
    C_Timer.After(1, function()
        if addon and addon.Tooltip and addon.Tooltip.InitializeGameTooltipHook then
            addon.Tooltip:InitializeGameTooltipHook()
        end
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
