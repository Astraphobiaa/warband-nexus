--[[
    Warband Nexus - Settings UI tab filtering panel.
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_Filters.lua loaded before SettingsUI.lua - check the TOC")

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendFiltersPanel(ctx)
    local H = M._H
    local WarbandNexus = H.WarbandNexus
    local ns = H.ns
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- TAB FILTERING
    yOffset = AppendSettingsPanelIntro(parent, "filters", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local tabSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(tabSection, yOffset)

    local warbandOptions = {}
    local tabFmt = (ns.L and ns.L["TAB_FORMAT"]) or "Tab %d"
    local ignoreTabFmt = (ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Warband Bank Tab %d from automatic scanning"
    for i = 1, 5 do
        table.insert(warbandOptions, {
            key = "tab" .. i,
            label = string.format(tabFmt, i),
            tooltip = string.format(ignoreTabFmt, i),
            get = function() return WarbandNexus.db.profile.ignoredTabs[i] end,
            set = function(value) WarbandNexus.db.profile.ignoredTabs[i] = value end,
        })
    end

    local personalBankOptions = {}
    local bankLbl = (ns.L and ns.L["BANK_LABEL"]) or "Bank"
    local bagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local ignoreScanFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local personalBankLabels = {bankLbl, string.format(bagFmt, 6), string.format(bagFmt, 7), string.format(bagFmt, 8), string.format(bagFmt, 9), string.format(bagFmt, 10), string.format(bagFmt, 11)}
    local personalBankBags = ns.PERSONAL_BANK_BAGS
    for i = 1, #personalBankBags do
        local bagID = personalBankBags[i]
        local label = personalBankLabels[i] or string.format(bagFmt, bagID)
        table.insert(personalBankOptions, {
            key = "pbank" .. bagID,
            label = label,
            tooltip = string.format(ignoreScanFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                return WarbandNexus.db.profile.ignoredPersonalBankBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                WarbandNexus.db.profile.ignoredPersonalBankBags[bagID] = value
            end,
        })
    end

    local inventoryOptions = {}
    local backpackLabel = (ns.L and ns.L["BACKPACK_LABEL"]) or "Backpack"
    local reagentLabel = (ns.L and ns.L["REAGENT_LABEL"]) or "Reagent"
    local invBagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local invIgnoreFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local inventoryLabels = {backpackLabel, string.format(invBagFmt, 1), string.format(invBagFmt, 2), string.format(invBagFmt, 3), string.format(invBagFmt, 4), reagentLabel}
    local inventoryBags = ns.INVENTORY_BAGS
    for i = 1, #inventoryBags do
        local bagID = inventoryBags[i]
        local label = inventoryLabels[i] or string.format(invBagFmt, bagID)
        table.insert(inventoryOptions, {
            key = "inv" .. bagID,
            label = label,
            tooltip = string.format(invIgnoreFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                return WarbandNexus.db.profile.ignoredInventoryBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                WarbandNexus.db.profile.ignoredInventoryBags[bagID] = value
            end,
        })
    end

    local tabInnerW = GetSettingsSectionContentWidth(effectiveWidth)
    local tabStackY = 0
    tabStackY = StackSettingsSubPanel(tabSection.content, tabInnerW, 0, function(inner, iw)
        local cy = 0
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_WARBAND"]) or "Warband Bank",
            iw, cy, { skipGapBefore = true })
        cy = CreateCheckboxGrid(inner, warbandOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_PERSONAL_BANK"]) or "Personal Bank",
            iw, cy)
        cy = CreateCheckboxGrid(inner, personalBankOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_INVENTORY"]) or "Inventory",
            iw, cy)
        cy = CreateCheckboxGrid(inner, inventoryOptions, cy, iw)
        return cy
    end, { flat = true, noTrailingGap = true })

    local contentHeight = SettingsMeasuredSectionContentHeight(tabStackY)
    FinalizeSettingsSectionHeight(tabSection, contentHeight, false)

    -- Move to next section
    yOffset = yOffset - tabSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
