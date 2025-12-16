--[[
    Warband Nexus - Configuration Module
    Clean and organized settings panel
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- AceConfig options table
local options = {
    name = "Warband Nexus",
    type = "group",
    args = {
        -- Header
        header = {
            order = 1,
            type = "description",
            name = "|cff00ccffWarband Nexus|r\nView and manage your Warband Bank items from anywhere.\n\n",
            fontSize = "medium",
        },
        
        -- ===== GENERAL =====
        generalHeader = {
            order = 10,
            type = "header",
            name = "General",
        },
        enabled = {
            order = 11,
            type = "toggle",
            name = "Enable Addon",
            desc = "Turn the addon on or off.",
            width = 1.2,
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
            order = 12,
            type = "toggle",
            name = "Minimap Button",
            desc = "Show a button on the minimap to open Warband Nexus.",
            width = 1.2,
            get = function() return not WarbandNexus.db.profile.minimap.hide end,
            set = function(_, value)
                if WarbandNexus.SetMinimapButtonVisible then
                    WarbandNexus:SetMinimapButtonVisible(value)
                else
                    WarbandNexus.db.profile.minimap.hide = not value
                end
            end,
        },

        -- ===== TOOLTIP =====
        tooltipHeader = {
            order = 15,
            type = "header",
            name = "Tooltip Enhancements",
        },
        tooltipEnhancement = {
            order = 16,
            type = "toggle",
            name = "Show Item Locations",
            desc = "Add item location information to tooltips (Warband Bank, Personal Banks).",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.tooltipEnhancement end,
            set = function(_, value)
                WarbandNexus.db.profile.tooltipEnhancement = value
                if value then
                    WarbandNexus:Print("Tooltip enhancement enabled")
                else
                    WarbandNexus:Print("Tooltip enhancement disabled")
                end
            end,
        },
        tooltipClickHint = {
            order = 17,
            type = "toggle",
            name = "Show Click Hint",
            desc = "Show 'Shift+Click to search' hint in tooltips.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.tooltipEnhancement end,
            get = function() return WarbandNexus.db.profile.tooltipClickHint end,
            set = function(_, value) WarbandNexus.db.profile.tooltipClickHint = value end,
        },
        
        -- ===== AUTOMATION =====
        automationHeader = {
            order = 20,
            type = "header",
            name = "Automation",
        },
        automationDesc = {
            order = 21,
            type = "description",
            name = "Control what happens automatically when you open your Warband Bank.\n",
        },
        autoScan = {
            order = 22,
            type = "toggle",
            name = "Auto-Scan Items",
            desc = "Automatically scan and cache your Warband Bank items when you open the bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoScan end,
            set = function(_, value) WarbandNexus.db.profile.autoScan = value end,
        },
        autoOpenWindow = {
            order = 23,
            type = "toggle",
            name = "Auto-Open Window",
            desc = "Automatically open the Warband Nexus window when you open your Warband Bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoOpenWindow ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoOpenWindow = value end,
        },
        autoSaveChanges = {
            order = 24,
            type = "toggle",
            name = "Live Sync",
            desc = "Keep the item cache updated in real-time while the bank is open. This lets you see accurate data even when away from the bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoSaveChanges ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoSaveChanges = value end,
        },
        replaceDefaultBank = {
            order = 25,
            type = "toggle",
            name = "Replace Default Bank",
            desc = "Hide the default WoW bank window and use Warband Nexus instead. You can still access the classic bank using the 'Classic Bank' button.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.replaceDefaultBank ~= false end,
            set = function(_, value) WarbandNexus.db.profile.replaceDefaultBank = value end,
        },
        autoOptimize = {
            order = 26,
            type = "toggle",
            name = "Auto-Optimize Database",
            desc = "Automatically clean up stale data and optimize the database every 7 days.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoOptimize ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoOptimize = value end,
        },
        
        -- ===== GOLD MANAGEMENT =====
        goldHeader = {
            order = 30,
            type = "header",
            name = "Gold Deposit",
        },
        goldDesc = {
            order = 31,
            type = "description",
            name = "Configure how much gold to keep on your character when depositing to Warband Bank.\n",
        },
        goldReserve = {
            order = 32,
            type = "range",
            name = "Keep This Much Gold",
            desc = "When you click 'Deposit Gold', this amount will stay on your character. The rest goes to Warband Bank.\n\nExample: If set to 1000g and you have 5000g, clicking Deposit will transfer 4000g.",
            min = 0,
            max = 100000,
            softMax = 10000,
            step = 100,
            bigStep = 500,
            width = "full",
            get = function() return WarbandNexus.db.profile.goldReserve end,
            set = function(_, value) WarbandNexus.db.profile.goldReserve = value end,
        },
        
        -- ===== TAB FILTERING =====
        tabHeader = {
            order = 40,
            type = "header",
            name = "Tab Filtering",
        },
        tabDesc = {
            order = 41,
            type = "description",
            name = "Exclude specific Warband Bank tabs from scanning. Useful if you want to ignore certain tabs.\n",
        },
        ignoredTab1 = {
            order = 42,
            type = "toggle",
            name = "Ignore Tab 1",
            width = 0.7,
            get = function() return WarbandNexus.db.profile.ignoredTabs[1] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[1] = value end,
        },
        ignoredTab2 = {
            order = 43,
            type = "toggle",
            name = "Ignore Tab 2",
            width = 0.7,
            get = function() return WarbandNexus.db.profile.ignoredTabs[2] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[2] = value end,
        },
        ignoredTab3 = {
            order = 44,
            type = "toggle",
            name = "Ignore Tab 3",
            width = 0.7,
            get = function() return WarbandNexus.db.profile.ignoredTabs[3] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[3] = value end,
        },
        ignoredTab4 = {
            order = 45,
            type = "toggle",
            name = "Ignore Tab 4",
            width = 0.7,
            get = function() return WarbandNexus.db.profile.ignoredTabs[4] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[4] = value end,
        },
        ignoredTab5 = {
            order = 46,
            type = "toggle",
            name = "Ignore Tab 5",
            width = 0.7,
            get = function() return WarbandNexus.db.profile.ignoredTabs[5] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[5] = value end,
        },
        
        -- ===== COMMANDS =====
        commandsHeader = {
            order = 90,
            type = "header",
            name = "Slash Commands",
        },
        commandsDesc = {
            order = 91,
            type = "description",
            name = [[
|cff00ccff/wn|r or |cff00ccff/wn show|r - Toggle the main window
|cff00ccff/wn scan|r - Scan Warband Bank (must be at banker)
|cff00ccff/wn search <item>|r - Search for an item
|cff00ccff/wn options|r - Open this settings panel
]],
            fontSize = "medium",
        },
    },
}

--[[
    Initialize configuration
]]
function WarbandNexus:InitializeConfig()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")
    
    -- Register main options
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    
    -- Add to Blizzard Interface Options
    self.optionsFrame = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Warband Nexus")
    
    -- Add Profiles sub-category
    local profileOptions = AceDBOptions:GetOptionsTable(self.db)
    AceConfig:RegisterOptionsTable(ADDON_NAME .. "_Profiles", profileOptions)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME .. "_Profiles", "Profiles", "Warband Nexus")
end

--[[
    Open the options panel
]]
function WarbandNexus:OpenOptions()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("Warband Nexus")
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end
