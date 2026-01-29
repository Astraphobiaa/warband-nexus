--[[
    Warband Nexus - Module Manager
    Handles enabling/disabling of modules and their associated events
    Event-Driven: Listens to WN_MODULE_TOGGLED and manages module state
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--============================================================================
-- EVENT-DRIVEN MODULE MANAGEMENT
--============================================================================

--[[
    Initialize module manager and register event listeners
]]
function WarbandNexus:InitializeModuleManager()
    -- Listen to module toggle events from Settings UI
    self:RegisterMessage("WN_MODULE_TOGGLED", "OnModuleToggled")
end

--[[
    Handle module toggle events
    @param event string - Event name (WN_MODULE_TOGGLED)
    @param moduleName string - Module identifier (currencies, reputations, etc.)
    @param enabled boolean - New enabled state
]]
function WarbandNexus:OnModuleToggled(event, moduleName, enabled)
    -- Route to appropriate module handler
    if moduleName == "currencies" then
        self:SetCurrencyModuleEnabled(enabled)
    elseif moduleName == "reputations" then
        self:SetReputationModuleEnabled(enabled)
    elseif moduleName == "items" then
        self:SetItemsModuleEnabled(enabled)
    elseif moduleName == "storage" then
        self:SetStorageModuleEnabled(enabled)
    elseif moduleName == "pve" then
        self:SetPvEModuleEnabled(enabled)
    elseif moduleName == "plans" then
        self:SetPlansModuleEnabled(enabled)
    end
end

--============================================================================
-- MODULE-SPECIFIC HANDLERS
--============================================================================

--[[
    Enable/disable reputation module
    Registers or unregisters associated events
    @param enabled boolean - True to enable, false to disable
]]
function WarbandNexus:SetReputationModuleEnabled(enabled)
    if not self.db or not self.db.profile then return end
    
    self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
    self.db.profile.modulesEnabled.reputations = enabled
    
    -- Note: Event handlers are managed by EventManager
    -- EventManager's OnReputationChangedThrottled checks module enabled status
    -- No need to register/unregister events here
    
    -- Note: UI refresh handled by caller (Config.lua)
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
    
    -- Note: Event handlers are managed by EventManager
    -- EventManager's OnCurrencyChangedThrottled checks module enabled status
    -- No need to register/unregister events here
    
    -- Note: UI refresh handled by caller (Config.lua)
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
    
    -- Note: UI refresh handled by caller (Config.lua)
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
    
    -- Note: UI refresh handled by caller (Config.lua)
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
    
    -- Note: Event handlers are managed by EventManager
    -- EventManager's PvE handlers check module enabled status
    -- No need to register/unregister events here
        
        -- AUTOMATIC: Start data collection with staggered approach (performance optimized)
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
    
    -- Note: UI refresh handled by caller (Config.lua)
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
    
    -- Note: UI refresh handled by caller (Config.lua)
end
