--[[
    Warband Nexus - Configuration Module
    AceConfig-3.0 based options panel
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- AceConfig options table
local options = {
    name = L["ADDON_NAME"],
    type = "group",
    args = {
        -- Header
        header = {
            order = 1,
            type = "description",
            name = L["ADDON_NAME"] .. " - A modern Warband management system\n\n",
            fontSize = "large",
        },
        
        -- General Settings Group
        generalSettings = {
            order = 10,
            type = "group",
            name = L["GENERAL_SETTINGS"],
            desc = L["GENERAL_SETTINGS_DESC"],
            inline = true,
            args = {
                enabled = {
                    order = 1,
                    type = "toggle",
                    name = L["ENABLE_ADDON"],
                    desc = L["ENABLE_ADDON_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.enabled end,
                    set = function(_, value)
                        WarbandNexus.db.profile.enabled = value
                        if value then
                            WarbandNexus:OnEnable()
                        else
                            WarbandNexus:OnDisable()
                        end
                    end,
                },
                minimapIcon = {
                    order = 2,
                    type = "toggle",
                    name = L["MINIMAP_ICON"],
                    desc = L["MINIMAP_ICON_DESC"],
                    width = "full",
                    get = function() return not WarbandNexus.db.profile.minimap.hide end,
                    set = function(_, value)
                        WarbandNexus.db.profile.minimap.hide = not value
                        local LDBIcon = LibStub("LibDBIcon-1.0", true)
                        if LDBIcon then
                            if value then
                                LDBIcon:Show(ADDON_NAME)
                            else
                                LDBIcon:Hide(ADDON_NAME)
                            end
                        end
                    end,
                },
                debugMode = {
                    order = 3,
                    type = "toggle",
                    name = L["DEBUG_MODE"],
                    desc = L["DEBUG_MODE_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.debug end,
                    set = function(_, value) WarbandNexus.db.profile.debug = value end,
                },
            },
        },
        
        -- Scanning Settings Group
        scanningSettings = {
            order = 20,
            type = "group",
            name = L["SCANNING_SETTINGS"],
            desc = L["SCANNING_SETTINGS_DESC"],
            inline = true,
            args = {
                autoScan = {
                    order = 1,
                    type = "toggle",
                    name = L["AUTO_SCAN"],
                    desc = L["AUTO_SCAN_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.autoScan end,
                    set = function(_, value) WarbandNexus.db.profile.autoScan = value end,
                },
                scanDelay = {
                    order = 2,
                    type = "range",
                    name = L["SCAN_DELAY"],
                    desc = L["SCAN_DELAY_DESC"],
                    min = 0.1,
                    max = 2.0,
                    step = 0.1,
                    width = "full",
                    get = function() return WarbandNexus.db.profile.scanDelay end,
                    set = function(_, value) WarbandNexus.db.profile.scanDelay = value end,
                },
            },
        },
        
        -- Deposit Settings Group
        depositSettings = {
            order = 30,
            type = "group",
            name = L["DEPOSIT_SETTINGS"],
            desc = L["DEPOSIT_SETTINGS_DESC"],
            inline = true,
            args = {
                goldReserve = {
                    order = 1,
                    type = "range",
                    name = L["GOLD_RESERVE"],
                    desc = L["GOLD_RESERVE_DESC"],
                    min = 0,
                    max = 1000000,
                    softMax = 100000,
                    step = 100,
                    bigStep = 1000,
                    width = "full",
                    get = function() return WarbandNexus.db.profile.goldReserve end,
                    set = function(_, value) WarbandNexus.db.profile.goldReserve = value end,
                },
                autoDepositReagents = {
                    order = 2,
                    type = "toggle",
                    name = L["AUTO_DEPOSIT_REAGENTS"],
                    desc = L["AUTO_DEPOSIT_REAGENTS_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.autoDepositReagents end,
                    set = function(_, value) WarbandNexus.db.profile.autoDepositReagents = value end,
                },
            },
        },
        
        -- Display Settings Group
        displaySettings = {
            order = 40,
            type = "group",
            name = L["DISPLAY_SETTINGS"],
            desc = L["DISPLAY_SETTINGS_DESC"],
            inline = true,
            args = {
                autoShowUI = {
                    order = 0,
                    type = "toggle",
                    name = L["AUTO_SHOW_UI"],
                    desc = L["AUTO_SHOW_UI_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.autoShowUI end,
                    set = function(_, value) WarbandNexus.db.profile.autoShowUI = value end,
                },
                showItemLevel = {
                    order = 1,
                    type = "toggle",
                    name = L["SHOW_ITEM_LEVEL"],
                    desc = L["SHOW_ITEM_LEVEL_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.showItemLevel end,
                    set = function(_, value)
                        WarbandNexus.db.profile.showItemLevel = value
                        WarbandNexus:RefreshUI()
                    end,
                },
                showItemCount = {
                    order = 2,
                    type = "toggle",
                    name = L["SHOW_ITEM_COUNT"],
                    desc = L["SHOW_ITEM_COUNT_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.showItemCount end,
                    set = function(_, value)
                        WarbandNexus.db.profile.showItemCount = value
                        WarbandNexus:RefreshUI()
                    end,
                },
                highlightQuality = {
                    order = 3,
                    type = "toggle",
                    name = L["HIGHLIGHT_QUALITY"],
                    desc = L["HIGHLIGHT_QUALITY_DESC"],
                    width = "full",
                    get = function() return WarbandNexus.db.profile.highlightQuality end,
                    set = function(_, value)
                        WarbandNexus.db.profile.highlightQuality = value
                        WarbandNexus:RefreshUI()
                    end,
                },
            },
        },
        
        -- Tab Settings Group
        tabSettings = {
            order = 50,
            type = "group",
            name = L["TAB_SETTINGS"],
            desc = L["TAB_SETTINGS_DESC"],
            inline = true,
            args = {
                ignoredTabsHeader = {
                    order = 0,
                    type = "description",
                    name = L["IGNORED_TABS_DESC"] .. "\n",
                },
                ignoredTab1 = {
                    order = 1,
                    type = "toggle",
                    name = L["TAB_1"],
                    get = function() return WarbandNexus.db.profile.ignoredTabs[1] end,
                    set = function(_, value) WarbandNexus.db.profile.ignoredTabs[1] = value end,
                },
                ignoredTab2 = {
                    order = 2,
                    type = "toggle",
                    name = L["TAB_2"],
                    get = function() return WarbandNexus.db.profile.ignoredTabs[2] end,
                    set = function(_, value) WarbandNexus.db.profile.ignoredTabs[2] = value end,
                },
                ignoredTab3 = {
                    order = 3,
                    type = "toggle",
                    name = L["TAB_3"],
                    get = function() return WarbandNexus.db.profile.ignoredTabs[3] end,
                    set = function(_, value) WarbandNexus.db.profile.ignoredTabs[3] = value end,
                },
                ignoredTab4 = {
                    order = 4,
                    type = "toggle",
                    name = L["TAB_4"],
                    get = function() return WarbandNexus.db.profile.ignoredTabs[4] end,
                    set = function(_, value) WarbandNexus.db.profile.ignoredTabs[4] = value end,
                },
                ignoredTab5 = {
                    order = 5,
                    type = "toggle",
                    name = L["TAB_5"],
                    get = function() return WarbandNexus.db.profile.ignoredTabs[5] end,
                    set = function(_, value) WarbandNexus.db.profile.ignoredTabs[5] = value end,
                },
            },
        },
    },
}

--[[
    Initialize configuration
    Register options with AceConfig and add to Blizzard settings
]]
function WarbandNexus:InitializeConfig()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")
    
    -- Register main options
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    
    -- Add to Blizzard Interface Options
    self.optionsFrame = AceConfigDialog:AddToBlizOptions(ADDON_NAME, L["ADDON_NAME"])
    
    -- Add Profiles sub-category
    options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
    options.args.profiles.order = 100
    options.args.profiles.name = L["PROFILES"]
    options.args.profiles.desc = L["PROFILES_DESC"]
    
    self:Debug("Configuration initialized")
end

--[[
    Open the options panel
]]
function WarbandNexus:OpenOptions()
    -- Try modern Settings API first (Dragonflight+)
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(L["ADDON_NAME"])
    else
        -- Fallback to legacy InterfaceOptionsFrame
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) -- Called twice due to Blizzard bug
    end
end


