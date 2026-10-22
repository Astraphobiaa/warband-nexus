--[[
    Warband Nexus - Module Manager
    Handles enabling/disabling of modules and their associated events
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS

--[[
    Enable/disable reputation module
    Registers or unregisters associated events
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetReputationModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.reputations = enabled
    
    -- UPDATE_FACTION / MAJOR_FACTION_*: owned by ReputationCacheService (single owner)
    -- Module toggle only affects UI visibility, not event registration
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "reputations", enabled)
end

--[[
    Enable/disable currency module
    Registers or unregisters associated events
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetCurrencyModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.currencies = enabled
    
    -- CURRENCY_DISPLAY_UPDATE: owned by CurrencyCacheService (single owner)
    -- Module toggle only affects UI visibility, not event registration
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "currencies", enabled)
end

--[[
    Enable/disable storage module
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetStorageModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.storage = enabled
    
    -- Storage module doesn't have specific events to unregister
    -- BAG_UPDATE is used by multiple modules
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "storage", enabled)
end

--[[
    Enable/disable items module
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetItemsModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.items = enabled
    
    -- Items module shares BAG_UPDATE with other modules
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "items", enabled)
end

--[[
    Enable/disable PvE module
    Registers or unregisters associated events
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetPvEModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.pve = enabled
    
    -- WEEKLY_REWARDS_UPDATE / UPDATE_INSTANCE_INFO / CHALLENGE_MODE_COMPLETED: owned by PvECacheService
    -- Module toggle only affects UI visibility, not event registration
    -- PvECacheService internally guards with module-enabled checks
    
    if enabled then
        -- Trigger initial data collection when re-enabled
        local charKey = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and WarbandNexus
            and ns.CharacterService:ResolveSubsidiaryCharacterKey(WarbandNexus, nil))
            or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        C_Timer.After(1, function()
            if WarbandNexus and WarbandNexus.CollectPvEDataStaggered then
                WarbandNexus:CollectPvEDataStaggered(charKey)
            end
        end)
    else
        -- Clear loading state when disabled
        if ns.PvELoadingState then
            self:UpdatePvELoadingState({
                isLoading = false,
                attempts = 0,
                loadingProgress = 0,
                currentStage = nil,
            })
        end
    end
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "pve", enabled)
end

--[[
    Enable/disable PvP module
    PvPService owns PVP_MATCH_COMPLETE / PVP_MATCH_ACTIVE / HONOR_* / PVP_RATED_STATS_UPDATE
    exclusively, so disabling unregisters them outright: no API calls, no db writes, no emits.
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetPvPModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end

    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.pvp = enabled

    -- Service owns event registration + re-seed on enable (UI never drives collection).
    if ns.PvPService and ns.PvPService.OnModuleToggled then
        ns.PvPService:OnModuleToggled(enabled)
    end

    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "pvp", enabled)
end

--[[
    Enable/disable Plans module
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetPlansModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.plans = enabled
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "plans", enabled)
end

--[[
    Enable/disable Try Counter module
    Controls automatic try counting for NPC/boss/fishing/container drop attempts
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetTryCounterModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.tryCounter = enabled
    
    -- Try counter events stay registered (protected API, cannot re-register safely).
    -- IsTryCounterModuleEnabled() / IsAutoTryCounterEnabled() guard handler bodies;
    -- spellcast handlers also bail when the module is off (no per-cast GetSpellInfo work).
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "tryCounter", enabled)
end

--[[
    Enable/disable Professions module
    Controls profession tracking, concentration, knowledge, and recipe companion
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetProfessionModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.professions = enabled
    
    if not enabled then
        -- Hide companion window when disabling
        if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.Hide then
            ns.RecipeCompanionWindow:Hide()
        end
        -- Stop recharge timer when disabling
        if self.StopRechargeTimer then
            self:StopRechargeTimer()
        end
    elseif enabled and ns.CharacterService and ns.CharacterService:IsCharacterTracked(self) then
        -- Re-enable mid-session: login-time C_Timer.After does not run again
        if self.StartRechargeTimer then
            self:StartRechargeTimer()
        end
    end
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage(E.MODULE_TOGGLED, "professions", enabled)
end

-- Profile switch support (2026-10-22; called from Core OnInitialize / OnProfileChanged).
-- Module keys (Settings > Modules) and the ModuleManager setter that owns each one's side effects
-- (PvP event registration, recharge timer, PvE loading state). gear / collections have no setter:
-- their listeners act on WN_MODULE_TOGGLED alone.
local MODULE_ENABLE_KEYS = {
    "currencies", "reputations", "items", "storage", "pve", "pvp",
    "plans", "professions", "gear", "collections", "tryCounter",
}
local MODULE_ENABLE_SETTERS = {
    currencies = "SetCurrencyModuleEnabled",
    reputations = "SetReputationModuleEnabled",
    items = "SetItemsModuleEnabled",
    storage = "SetStorageModuleEnabled",
    pve = "SetPvEModuleEnabled",
    pvp = "SetPvPModuleEnabled",
    plans = "SetPlansModuleEnabled",
    professions = "SetProfessionModuleEnabled",
    tryCounter = "SetTryCounterModuleEnabled",
}
-- Enabled state the WN_MODULE_TOGGLED listeners were last told about (key -> boolean).
local moduleEnabledSnapshot = {}
local moduleSnapshotSink = {}

---Toggle one module the same way Settings does: through its ModuleManager setter (writes
---profile.modulesEnabled, runs side effects, sends WN_MODULE_TOGGLED). Setter-less keys write the
---flag and send the message.
---@param moduleName string
---@param enabled boolean
function WarbandNexus:SetModuleEnabled(moduleName, enabled)
    local setterName = MODULE_ENABLE_SETTERS[moduleName]
    local setter = setterName and self[setterName]
    if setter then
        setter(self, enabled)
        return
    end
    if not self.db or not self.db.profile then return end
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled[moduleName] = enabled
    self:SendMessage(E.MODULE_TOGGLED, moduleName, enabled)
end

---Record the current module state and follow every later toggle (any sender of WN_MODULE_TOGGLED).
function WarbandNexus:TrackModuleEnabledState()
    local U = ns.Utilities
    if not (U and U.IsModuleEnabled) then return end
    for i = 1, #MODULE_ENABLE_KEYS do
        local key = MODULE_ENABLE_KEYS[i]
        moduleEnabledSnapshot[key] = U:IsModuleEnabled(key)
    end
    if not moduleSnapshotSink.registered and self.RegisterMessage then
        moduleSnapshotSink.registered = true
        self.RegisterMessage(moduleSnapshotSink, E.MODULE_TOGGLED, function(_, moduleName, enabled)
            if moduleName and moduleEnabledSnapshot[moduleName] ~= nil then
                moduleEnabledSnapshot[moduleName] = (enabled ~= false)
            end
        end)
    end
end

---Profile switch / copy / reset (2026-10-22): the new profile may carry a different modulesEnabled set,
---but nothing told the services (PvP events stayed registered, collection listeners stayed off, ...).
---Every module whose state differs from what listeners last heard goes through SetModuleEnabled.
function WarbandNexus:ResyncModulesAfterProfileChange()
    local U = ns.Utilities
    if not (U and U.IsModuleEnabled) then return end
    for i = 1, #MODULE_ENABLE_KEYS do
        local key = MODULE_ENABLE_KEYS[i]
        local before = moduleEnabledSnapshot[key]
        local enabled = U:IsModuleEnabled(key)
        if before ~= nil and before ~= enabled then
            self:SetModuleEnabled(key, enabled)
        end
    end
end
