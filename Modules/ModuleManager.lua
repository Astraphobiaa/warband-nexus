--[[
    Warband Nexus - Module Manager
    Handles enabling/disabling of modules and their associated events
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

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
    self:SendMessage("WN_MODULE_TOGGLED", "reputations", enabled)
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
    self:SendMessage("WN_MODULE_TOGGLED", "currencies", enabled)
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
    self:SendMessage("WN_MODULE_TOGGLED", "storage", enabled)
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
    self:SendMessage("WN_MODULE_TOGGLED", "items", enabled)
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
        local charKey = UnitName("player") .. "-" .. GetRealmName()
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
    self:SendMessage("WN_MODULE_TOGGLED", "pve", enabled)
end

--[[
    Enable/disable Plans module
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetPlansModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.plans = enabled
    
    -- Also control CollectionScanner (dependent on Plans)
    if enabled then
        if self.CollectionScanner and self.CollectionScanner.Enable then
            self.CollectionScanner:Enable()
        end
    else
        if self.CollectionScanner and self.CollectionScanner.Disable then
            self.CollectionScanner:Disable()
        end
    end
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage("WN_MODULE_TOGGLED", "plans", enabled)
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
    end
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    self:SendMessage("WN_MODULE_TOGGLED", "professions", enabled)
end
