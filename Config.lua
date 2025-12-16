local WarbandNexus = LibStub("AceAddon-3.0"):GetAddon("WarbandNexus")
local Config = WarbandNexus:NewModule("Config")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local options = {
    name = "Warband Nexus",
    handler = WarbandNexus,
    type = "group",
    args = {
        general = {
            type = "group",
            name = "General Settings",
            order = 1,
            args = {
                header = {
                    type = "header",
                    name = "General",
                    order = 1,
                },
                minimap = {
                    type = "toggle",
                    name = "Show Minimap Icon",
                    desc = "Toggles the minimap icon.",
                    order = 2,
                    get = function(info) return not WarbandNexus.db.profile.minimap.hide end,
                    set = function(info, val)
                        WarbandNexus.db.profile.minimap.hide = not val
                        if val then
                            LibStub("LibDBIcon-1.0"):Show("WarbandNexus")
                        else
                            LibStub("LibDBIcon-1.0"):Hide("WarbandNexus")
                        end
                    end,
                },
                autoRepair = {
                    type = "toggle",
                    name = "Auto Repair",
                    desc = "Automatically repair items when visiting a merchant (Coming Soon).",
                    order = 3,
                    get = function(info) return WarbandNexus.db.profile.autoRepair end,
                    set = function(info, val) WarbandNexus.db.profile.autoRepair = val end,
                },
            },
        },
    },
}

function Config:OnInitialize()
    AceConfig:RegisterOptionsTable("WarbandNexus", options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("WarbandNexus", "Warband Nexus")
end
