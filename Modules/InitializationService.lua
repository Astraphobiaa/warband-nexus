--[[
    WarbandNexus - Initialization Service
    Manages addon module initialization with proper sequencing
    
    Responsibilities:
    - Coordinate module startup sequence
    - Manage initialization timings (prevent addon load lag)
    - Handle dependencies between modules
    - Centralize all C_Timer.After() calls

    Data rule (SOA): writers persist to AceDB (services); UI reads DB + messages — no duplicate API in consumers.

    Load pipeline (first session hitch):
    - Core OnInitialize: AceDB, CheckVersions, RunMigrations (same frame); SessionCache decompress is deferred
      one tick (see Core.lua) so deflate/deserialize does not stack with migrations on ADDON_LOADED.
    - Core OnEnable: registers events, then InitializeAllModules (this file) which spreads cache/UI work
      across T+0.3s … T+8s (see stage comments below). P0 DailyQuest + CollectionCache share the Stage1 T+0.5s tick with EventManager.
    - PLAYER_ENTERING_WORLD payload (Warcraft Wiki): login, /reload, or instance zoning; Patch 8.0.1 adds
      isInitialLogin and isReloadingUi (AceEvent: event, isInitialLogin, isReloadingUi). Cold prefetch runs only
      when either flag is true (login/reload), not on zoning-only transitions.

    WN_NONUI_UI: `combatSafetyFrame` bootstrap uses a hidden CreateFrame shell (see SetupCombatSafety) — not addon tab UI.
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local DebugPrint = ns.DebugPrint

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
        local slice = P and P.enabled and label and P.SliceLabel and P:SliceLabel(P.CAT.INIT, label)
        if slice then
            P:Start(slice)
        end
        local ok, err = pcall(fn)
        if slice then
            P:Stop(slice)
        end
        if not ok then
            local msg = string.format("|cffff4444[Init ERROR]|r %s failed: %s", label or "?", tostring(err))
            DebugPrint(msg)
        end
    else
        table.insert(pendingInits, { fn = fn, label = label })
    end
end

-- Expose for Core.lua deferred inits (e.g. InitializePlanTracking, InitializeChatMessageService)
InitializationService.SafeInit = SafeInit

--- PLAYER_ENTERING_WORLD cold-cache anchor generation (login/reload). Cancels stale timer callbacks on repeat PEW.
local coldPrefetchGeneration = 0

--- Read-only token for staged cold-cache continuations (Gear warmup checks superseded PEW).
function InitializationService:GetColdPrefetchGeneration()
    return coldPrefetchGeneration
end

--[[
    Deferred hints after world enter (login or /reload only — not instance zoning).
    Uses SafeInit + bounded C_Timer.After; SOA: service-side prefetch only, SendMessage via existing metadata drain.

    Ordering (login/reload):
      1) T+3.5s: PrefetchSessionEquippedItemMetadata() — itemID metadata prime (ItemsCacheService).
      2) T+4.0s chained: WarmGearUpgradeSnapshotForSession(coldGen) — bounded staged ScanEquippedGear work,
         silent persist (no GEAR_UPDATED); aborts if PEW generation changes or another gear scan refreshes DB.

    Extension points: staged bag hash warm, currency snapshot hints, etc.
]]
function InitializationService:ScheduleColdCachePrefetchAfterWorldEnter(addon, isInitialLogin, isReloadingUi)
    if not addon then return end
    if not isInitialLogin and not isReloadingUi then
        return
    end

    coldPrefetchGeneration = coldPrefetchGeneration + 1
    local gen = coldPrefetchGeneration

    -- After P4 ItemsCache registration (T+3s) — metadata prime should not compete with first bag hooks.
    local DELAY_SEC = 3.5

    C_Timer.After(DELAY_SEC, function()
        if gen ~= coldPrefetchGeneration then return end
        SafeInit(function()
            if gen ~= coldPrefetchGeneration then return end
            if addon.PrefetchSessionEquippedItemMetadata then
                addon:PrefetchSessionEquippedItemMetadata()
            end
            -- Second stage: staggered gear tooltip / persist prime (GearService); yields across C_Timer.After ticks.
            C_Timer.After(0.5, function()
                if gen ~= coldPrefetchGeneration then return end
                SafeInit(function()
                    if gen ~= coldPrefetchGeneration then return end
                    if addon.WarmGearUpgradeSnapshotForSession then
                        addon:WarmGearUpgradeSnapshotForSession(gen)
                    end
                end, "ColdCache:GearUpgradeWarm")
            end)
        end, "ColdCache:EquippedItemMetadata")
    end)
end

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
    
    -- STAGE 5 message is handled in Core.lua:OnEnable().
end

--[[
    STAGE 1: Core Infrastructure
    Essential systems that other modules depend on
]]
function InitializationService:InitializeCoreInfrastructure(addon)
    
    -- T+0.5s: Single timer — Core event setup + P0 data inits + tracking popup probe share one wake-up
    -- (one C_Timer slot vs separate 0.5s from InitializeDataServices; same ordering: events before P0).
    C_Timer.After(0.5, function()
        SafeInit(function()
            if addon and addon.InitializeLootNotifications then
                addon:InitializeLootNotifications()
            end
            if addon and addon.InitializeEventManager then
                addon:InitializeEventManager()
            end
        end, "CoreEventSetup")

        SafeInit(function()
            if addon and addon.InitializeDailyQuestManager then
                addon:InitializeDailyQuestManager()
            end
            if addon and addon.InitializeCollectionCache then
                addon:InitializeCollectionCache()
            end
        end, "P0:LightweightInits")

        -- Character Tracking Confirmation: Check for new characters (same delay + retry)
        -- After /reload, GetNormalizedRealmName() can be empty briefly; deciding then used GetRealmName-only
        -- keys and missed db.global.characters[...] (trackingConfirmed), so the dialog reappeared.
        local attempts = 0
        local maxAttempts = 20 -- up to ~2s extra polling (0.1s steps)

        local function evaluateTrackingPopup()
            if not addon or not addon.db or not addon.db.global then return end

            local norm = GetNormalizedRealmName and GetNormalizedRealmName()
            local realmReady = type(norm) == "string" and not (issecretvalue and issecretvalue(norm)) and norm ~= ""

            if not realmReady and attempts < maxAttempts then
                attempts = attempts + 1
                C_Timer.After(0.1, evaluateTrackingPopup)
                return
            end

            -- Resolve row like IsCharacterTracked (GUID-keyed DB vs legacy Name-Realm index).
            local resolvedKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
                and ns.CharacterService:ResolveCharactersTableKey(addon)
            local charData = resolvedKey and addon.db.global.characters and addon.db.global.characters[resolvedKey]

            -- Only show popup if user has never completed the dialog (trackingConfirmed ~= true).
            -- NOTE: Do not use "not trackingConfirmed" alone: SaveMinimalCharacterData used to persist
            -- false for unconfirmed chars, and (not false) is true in Lua → infinite popup every login.
            local shouldShowPopup = not charData or charData.trackingConfirmed ~= true

            if shouldShowPopup then
                -- CRITICAL: DON'T set trackingConfirmed here!
                -- The flag will be set by ConfirmCharacterTracking() when user makes a choice
                -- This prevents the popup from appearing again

                -- Create stub entry with isTracked = false (prevents auto-save until user confirms)
                if not addon.db.global.characters then
                    addon.db.global.characters = {}
                end
                -- Persist under storage key (GUID when available) so stub matches migrated rows / saves.
                local persistKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
                    or ns.Utilities:GetCharacterKey()
                if not persistKey or persistKey == "" then return end
                if not addon.db.global.characters[persistKey] then
                    addon.db.global.characters[persistKey] = {}
                end
                local stub = addon.db.global.characters[persistKey]
                if not stub.name or not stub.realm then
                    local un = UnitName("player")
                    if un and type(un) == "string" and not (issecretvalue and issecretvalue(un)) then
                        stub.name = un
                    end
                    -- Reuse norm from realm-ready probe (avoids redundant GetNormalizedRealmName call)
                    local realm = norm
                    if not realm or (issecretvalue and issecretvalue(realm)) then
                        realm = GetRealmName and GetRealmName()
                    end
                    if realm and not (issecretvalue and issecretvalue(realm)) then
                        stub.realm = realm
                    end
                end
                if stub.isTracked == nil then
                    stub.isTracked = false
                end
                stub.lastSeen = time()

                C_Timer.After(2, function()
                    SafeInit(function()
                        if ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                            ns.CharacterService:ShowCharacterTrackingConfirmation(addon, persistKey)
                        end
                    end, "CharacterTrackingPopup")
                end)
            else
                -- Returning user (already tracked): show What's New on first login after update
                -- Trigger with 1.5s delay to ensure DB and UI are ready
                C_Timer.After(1.5, function()
                    if addon and addon.CheckNotificationsOnLogin then
                        addon:CheckNotificationsOnLogin()
                    end
                end)
            end
        end

        evaluateTrackingPopup()
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
    --   P0 (T+0.5s): Merged into InitializeCoreInfrastructure (same tick as CoreEventSetup)
    --   P1 (T+1s):   Heavy async collection build (4ms/frame budget)
    --   P2 (T+2s):   Character + tracked-only caches (batched)
    --   P3 (T+3s):   Items cache + vault (tracked only)
    --   P4 (T+6s):   Moderate index build (TryCounter, deferred for smoother reload)
    --   P5 (T+8s):   Full collection warmup (non-critical, on-demand still works)

    local modulesEnabled = addon and addon.db and addon.db.profile and addon.db.profile.modulesEnabled
    local collectionFeaturesEnabled = (not modulesEnabled) or modulesEnabled.collections ~= false or modulesEnabled.plans ~= false
    local tryCounterEnabled = (not modulesEnabled) or modulesEnabled.tryCounter ~= false

    -- P1: Owned lookup cache — RunCollectionOwnedCacheWarmup (quiet when SV store already warm; avoids duplicate LT vs collection_data).
    -- Run only when collection/plans features are enabled.
    if collectionFeaturesEnabled then
        C_Timer.After(1, function()
            SafeInit(function()
                if addon and addon.RunCollectionOwnedCacheWarmup then
                    addon:RunCollectionOwnedCacheWarmup()
                elseif addon and addon.BuildCollectionCache then
                    addon:BuildCollectionCache()
                end
            end, "P1:CollectionOwnedWarmup")
        end)
    end

    -- P5: Full collection data warmup (mount/pet/toy id+name+metadata in DB for search & UI)
    -- Deferred to reduce /reload hitch. Collections/Plans paths still trigger on-demand EnsureCollectionData().
    if collectionFeaturesEnabled then
        C_Timer.After(8, function()
            SafeInit(function()
                if addon and addon.EnsureFullCollectionData
                    and not (ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading) then
                    addon:EnsureFullCollectionData()
                end
            end, "P5:EnsureFullCollectionData")
        end)
    end

    -- P4: Moderate — TryCounter index build from CollectibleSourceDB
    -- Deferred further to keep /reload entry smoother; service remains functionally identical.
    if tryCounterEnabled then
        C_Timer.After(6, function()
            SafeInit(function()
                if addon and addon.InitializeTryCounter then
                    addon:InitializeTryCounter()
                end
            end, "P4:TryCounter")
        end)
    end

    -- P3: Character data + tracked-only caches (batched)
    -- CharacterCache is lightweight; Currency/PvE caches are event registration + DB init.
    -- Batching these saves 1s gap. Total frame cost: <3ms.
    -- Only register loading tracker for tracked characters (untracked skip cache init).
    local isTrackedEarly = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
    local LT = ns.LoadingTracker
    if LT and isTrackedEarly then LT:Register("caches", (ns.L and ns.L["LT_CURRENCY_CACHES"]) or "Currency & Caches") end
    C_Timer.After(2, function()
        SafeInit(function()
            -- Character cache events.
            if addon and addon.RegisterCharacterCacheEvents then
                addon:RegisterCharacterCacheEvents()
            end
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
            if isTracked and addon and addon.GetCharacterData then
                addon:GetCharacterData(true)
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

    -- P4: Items cache (tracked characters only)
    -- C_MythicPlus priming handled by RegisterPvECacheEvents (T+2s → +3s = T+5s).
    -- NOTE: OnUIInteract() removed — VaultScanner is the sole owner (PLAYER_ENTERING_WORLD, T+1s).
    -- P4 completes LoadingTracker "caches" — must run even if InitializeItemsCache errors or was deferred from combat.
    if isTrackedEarly then
        C_Timer.After(3, function()
            SafeInit(function()
                local ok, err = pcall(function()
                    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
                    if isTracked and addon and addon.InitializeItemsCache then
                        addon:InitializeItemsCache()
                    end
                end)
                if not ok then
                    if IsDebugModeEnabled and IsDebugModeEnabled() then
                        DebugPrint(string.format("|cffff4444[Init]|r P4 ItemsCache failed: %s", tostring(err)))
                    end
                end
                local LT = ns.LoadingTracker
                if LT then LT:Complete("caches") end
            end, "P4:ItemsCache")
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

    -- Tooltip item pre-cache: moved to first main-window show (UI.lua ShowMainWindow) so idle sessions
    -- never pay the scan cost in the background.
end

--[[
    STAGE 4: Background Services
    Non-critical systems that can load later
]]
function InitializationService:InitializeBackgroundServices(addon)
    -- Error Handler: Wrap critical functions (1.5s)
    -- NOTE: Must run AFTER all other modules are loaded
    C_Timer.After(1.5, function()
        SafeInit(function()
            if addon and addon.InitializeErrorHandler then
                addon:InitializeErrorHandler()
            end
        end, "ErrorHandler")
    end)
    
    -- Reminder Service: Time & zone-based plan reminders (4s)
    C_Timer.After(4, function()
        SafeInit(function()
            if addon and addon.InitializeReminderService then
                addon:InitializeReminderService()
            end
        end, "ReminderService")
    end)

    -- Bank money services are non-critical at startup; defer their event hooks.
    C_Timer.After(3, function()
        SafeInit(function()
            if addon and addon.InitializeGoldManagementService then
                addon:InitializeGoldManagementService()
            end
            if addon and addon.InitializeCharacterBankMoneyLogService then
                addon:InitializeCharacterBankMoneyLogService()
            end
        end, "BankMoneyServices")
    end)
    
    -- Database Optimizer: Auto-cleanup and optimization (5s); SafeInit defers if combat lockdown
    C_Timer.After(5, function()
        SafeInit(function()
            if addon and addon.InitializeDatabaseOptimizer then
                addon:InitializeDatabaseOptimizer()
            end
        end, "DatabaseOptimizer")
    end)
end

--[[
    Initialize minimap button (called from OnInitialize)
    This is separate because it needs database to be ready first
]]
function InitializationService:InitializeMinimapButton(addon)
    C_Timer.After(1, function()
        SafeInit(function()
            if addon and addon.InitializeMinimapButton then
                addon:InitializeMinimapButton()
            end
        end, "MinimapButton")
    end)
end

return InitializationService
