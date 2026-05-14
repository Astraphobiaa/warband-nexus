--[[
    Warband Nexus — Storage tab layout constants.

    Type section pixel height (collapsible strip). Animated tab-list tweens were removed;
    expand/collapse uses immediate redraw (same pattern as other main tabs).
]]

local ADDON_NAME, ns = ...

local StorageSectionLayout = {}

function StorageSectionLayout.GetTypeSectionHeaderHeight()
    local lay = ns.UI_LAYOUT
    return (lay and lay.SECTION_COLLAPSE_HEADER_HEIGHT) or 36
end

ns.StorageSectionLayout = StorageSectionLayout
