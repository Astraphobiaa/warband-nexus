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
                local ok, err = pcall(queue[i].fn)
                if not ok then
                    local msg = string.format("|cffff4444[Init ERROR]|r %s failed: %s", queue[i].label or "?", tostring(err))
                    DebugPrint(msg)
                end
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
                local ok, err = pcall(queue[i].fn)
                if not ok then
                    local msg = string.format("|cffff4444[Init ERROR]|r %s failed: %s", queue[i].label or "?", tostring(err))
                    DebugPrint(msg)
                end
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
        local P = ns.Profiler
        if P and P.enabled and label then
            P:Start("Init:" .. label)
        end
        local ok, err = pcall(fn)
        if P and P.enabled and label then
            P:Stop("Init:" .. label)
        end
        if not ok then
            local msg = string.format("|cffff4444[Init ERROR]|r %s failed: %s", label or "?", tostring(err))
            DebugPrint(msg)
            if _G.print then _G.print("|cff9370DB[WN]|r " .. msg) end
        end
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
    
    -- T+0.5s: Batch lightweight event registrations (<2ms total)
    -- LootNotifications + EventManager — both are just event hookups
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.InitializeLootNotifications then
                addon:InitializeLootNotifications()
            end
            if addon and addon.InitializeEventManager then
                addon:InitializeEventManager()
            end
        end, "CoreEventSetup")
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
                SafeInit(function()
                    if ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                        ns.CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
                    end
                end, "CharacterTrackingPopup")
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
    -- DataServices: Priority-based batched initialization.
    -- Operations grouped by priority tier. Lightweight ops share frames.
    -- Heavy/async ops get dedicated slots to prevent frame spikes.
    --
    -- PRIORITY TIERS:
    --   P0 (T+0.5s): Lightweight DB/event registration (batched, <2ms total)
    --   P1 (T+1s):   Heavy async collection build (4ms/frame budget)
    --   P2 (T+1.5s): Moderate index build (TryCounter)
    --   P3 (T+2s):   Character + tracked-only caches (batched)
    --   P4 (T+3s):   Items cache + vault (tracked only)

    -- P0: Lightweight inits — DB loads + event registration
    -- Combined: DailyQuestManager + CollectionCacheDB (<2ms total)
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.InitializeDailyQuestManager then
                addon:InitializeDailyQuestManager()
            end
            if addon and addon.InitializeCollectionCache then
                addon:InitializeCollectionCache()
            end
        end, "P0:LightweightInits")
    end)

    -- P1: Heavy async — BuildCollectionCache (mounts/pets/toys, 4ms/frame batched)
    -- No dependency on P0 CollectionCacheDB (uses different data: .owned vs .uncollected)
    C_Timer.After(1, function()
        SafeInit(function()
            if addon and addon.BuildCollectionCache then
                addon:BuildCollectionCache()
            end
        end, "P1:BuildCollectionCache")
    end)

    -- P2: Moderate — TryCounter index build from CollectibleSourceDB
    -- No dependency on collection cache
    C_Timer.After(1.5, function()
        SafeInit(function()
            if addon and addon.InitializeTryCounter then
                addon:InitializeTryCounter()
            end
        end, "P2:TryCounter")
    end)

    -- P3: Character data + tracked-only caches (batched)
    -- CharacterCache is lightweight; Currency/PvE caches are event registration + DB init.
    -- Batching these saves 1s gap. Total frame cost: <3ms.
    -- Only register loading tracker for tracked characters (untracked skip cache init).
    local isTrackedEarly = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
    local LT = ns.LoadingTracker
    if LT and isTrackedEarly then LT:Register("caches", "Currency & Caches") end
    C_Timer.After(2, function()
        SafeInit(function()
            -- Character cache: only for already-tracked characters.
            -- New characters get this via ConfirmCharacterTracking post-confirmation flow.
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
            if isTracked then
                if addon and addon.RegisterCharacterCacheEvents then
                    addon:RegisterCharacterCacheEvents()
                end
                if addon and addon.GetCharacterData then
                    addon:GetCharacterData(true)
                end
            end
        end, "P3:CharacterCache")

        SafeInit(function()
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
            if isTracked then
                if addon and addon.InitializeCurrencyCache then
                    addon:InitializeCurrencyCache()
                end
                if addon and addon.RegisterPvECacheEvents then
                    addon:RegisterPvECacheEvents()
                end
                if addon and addon.InitializePvECache then
                    addon:InitializePvECache()
                end
            end
        end, "P3:CurrencyPvE")
    end)

    -- P4: Items cache + Vault request (tracked characters only)
    -- C_MythicPlus priming handled by RegisterPvECacheEvents (T+2s → +3s = T+5s).
    if isTrackedEarly then
        C_Timer.After(3, function()
            SafeInit(function()
                local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
                if isTracked then
                    if addon and addon.InitializeItemsCache then
                        addon:InitializeItemsCache()
                    end
                    if C_WeeklyRewards then
                        C_WeeklyRewards.OnUIInteract()
                    end
                end
                local LT = ns.LoadingTracker
                if LT then LT:Complete("caches") end
            end, "P4:ItemsMythicVault")
        end)
    end
end

--[[
    STAGE 3: UI & Utilities
    Tooltip, minimap, and visual systems
]]
function InitializationService:InitializeUIServices(addon)
    -- T+0.3s: Batch all lightweight UI inits (<2ms total)
    -- Tooltip:Initialize + StatisticsUI — both are event registration only
    C_Timer.After(0.3, function()
        SafeInit(function()
            if addon and addon.Tooltip and addon.Tooltip.Initialize then
                addon.Tooltip:Initialize()
            end
            if addon and addon.InitializeStatisticsUI then
                addon:InitializeStatisticsUI()
            end
        end, "UIEventSetup")
    end)
    
    -- T+0.5s: Tooltip hook — needs Tooltip:Initialize from T+0.3s
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.Tooltip and addon.Tooltip.InitializeGameTooltipHook then
                addon.Tooltip:InitializeGameTooltipHook()
            end
        end, "TooltipHook")
    end)
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
