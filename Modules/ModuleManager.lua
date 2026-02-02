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
    
    if enabled then
        -- Register reputation events
        self:RegisterEvent("UPDATE_FACTION", "OnReputationChangedThrottled")
        self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnReputationChangedThrottled")
        self:RegisterEvent("MAJOR_FACTION_UNLOCKED", "OnReputationChangedThrottled")
    else
        -- Unregister reputation events
        pcall(function() self:UnregisterEvent("UPDATE_FACTION") end)
        pcall(function() self:UnregisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED") end)
        pcall(function() self:UnregisterEvent("MAJOR_FACTION_UNLOCKED") end)
    end
    
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
    
    if enabled then
        -- Register currency events
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChangedThrottled")
    else
        -- Unregister currency events
        pcall(function() self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE") end)
    end
    
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
    
    if enabled then
        -- Register PvE events
        self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnPvEDataChangedThrottled")
        self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnPvEDataChangedThrottled")
        self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnPvEDataChangedThrottled")
        
        -- AUTOMATIC: Start data collection with staggered approach (performance optimized)
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        C_Timer.After(1, function()
            if WarbandNexus and WarbandNexus.CollectPvEDataStaggered then
                WarbandNexus:CollectPvEDataStaggered(charKey)
            end
        end)
    else
        -- Unregister PvE events
        pcall(function() self:UnregisterEvent("WEEKLY_REWARDS_UPDATE") end)
        pcall(function() self:UnregisterEvent("UPDATE_INSTANCE_INFO") end)
        pcall(function() self:UnregisterEvent("CHALLENGE_MODE_COMPLETED") end)
        
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
