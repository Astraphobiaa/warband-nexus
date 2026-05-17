--[[
    Warband Nexus - Gear tab layout coordinator hook
    Loaded after GearUI.lua (keeps GearUI.lua under the 200 local limit per chunk).
]]

local ADDON_NAME, ns = ...

if ns.UI_LayoutCoordinator then
    local function RelayoutGearViewport(mf)
        if not mf or mf.currentTab ~= "gear" then return false end
        if ns.GearUI_RelayoutGearTabViewportFill then
            return ns.GearUI_RelayoutGearTabViewportFill(mf) == true
        end
        return false
    end
    ns.UI_LayoutCoordinator:RegisterTabAdapter("gear", {
        OnViewportWidthChanged = function(_scrollChild, _contentWidth, mf)
            return RelayoutGearViewport(mf)
        end,
        OnViewportLayoutCommit = RelayoutGearViewport,
    })
end
