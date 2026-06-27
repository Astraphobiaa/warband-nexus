--[[
    Warband Nexus - Settings UI module toggles panel.
    Split from SettingsUI.lua (ops-038).
    Loaded before Modules/UI/SettingsUI.lua.
]]

local _, ns = ...

ns.SettingsUI = ns.SettingsUI or {}

function ns.SettingsUI.AppendModulesPanel(ctx)
    if not ctx or not ctx.parent then return ctx and ctx.yOffset or 0 end
    local WarbandNexus = ns.WarbandNexus
    local E = ns.Constants and ns.Constants.EVENTS
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset or 0
    local yOffset = ctx.yOffset or 0
    local H = ctx.helpers or {}
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local CreateSection = H.CreateSection
    local AnchorSectionTop = H.AnchorSectionTop
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local GetHeaderToolbarGap = H.GetHeaderToolbarGap
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP or 20
    if not (AppendSettingsPanelIntro and CreateSection and StackSettingsSubPanel and CreateCheckboxGrid) then
        return yOffset
    end

    yOffset = AppendSettingsPanelIntro(parent, "modules", effectiveWidth, yOffset, sideInset)
    local moduleSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(moduleSection, yOffset)

    local moduleContentW = effectiveWidth - 30
    local moduleStackY = 0
    moduleStackY = StackSettingsSubPanel(moduleSection.content, moduleContentW, moduleStackY, function(inner, iw)
        local cy = 0
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_MODULES_LIST"]) or "Enabled modules",
            iw, cy, { skipGapBefore = true })
        cy = cy - GetHeaderToolbarGap()

        local moduleOptions = {
            {
                key = "currencies",
                label = (ns.L and ns.L["MODULE_CURRENCIES"]) or "Currencies",
                tooltip = (ns.L and ns.L["MODULE_CURRENCIES_DESC"]) or "Track account-wide and character-specific currencies (Gold, Honor, Conquest, etc.)",
                get = function() return WarbandNexus.db.profile.modulesEnabled.currencies ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.currencies = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "currencies", value)
                end,
            },
            {
                key = "reputations",
                label = (ns.L and ns.L["MODULE_REPUTATIONS"]) or "Reputations",
                tooltip = (ns.L and ns.L["MODULE_REPUTATIONS_DESC"]) or "Track reputation progress with factions, renown levels, and paragon rewards",
                get = function() return WarbandNexus.db.profile.modulesEnabled.reputations ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.reputations = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "reputations", value)
                end,
            },
            {
                key = "items",
                label = (ns.L and ns.L["MODULE_ITEMS"]) or "Items",
                tooltip = (ns.L and ns.L["MODULE_ITEMS_DESC"]) or "Track Warband Bank items, search functionality, and item categories",
                get = function() return WarbandNexus.db.profile.modulesEnabled.items ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.items = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "items", value)
                end,
            },
            {
                key = "storage",
                label = (ns.L and ns.L["MODULE_STORAGE"]) or "Storage",
                tooltip = (ns.L and ns.L["MODULE_STORAGE_DESC"]) or "Track character bags, personal bank, and Warband Bank storage",
                get = function() return WarbandNexus.db.profile.modulesEnabled.storage ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.storage = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "storage", value)
                end,
            },
            {
                key = "pve",
                label = (ns.L and ns.L["MODULE_PVE"]) or "PvE",
                tooltip = (ns.L and ns.L["MODULE_PVE_DESC"]) or "Track Mythic+ dungeons, raid progress, and Weekly Vault rewards",
                get = function() return WarbandNexus.db.profile.modulesEnabled.pve ~= false end,
                set = function(value)
                    if WarbandNexus.SetPvEModuleEnabled then
                        WarbandNexus:SetPvEModuleEnabled(value)
                    else
                        WarbandNexus.db.profile.modulesEnabled.pve = value
                        WarbandNexus:SendMessage(E.MODULE_TOGGLED, "pve", value)
                    end
                end,
            },
            {
                key = "plans",
                label = (ns.L and ns.L["MODULE_PLANS"]) or "Plans",
                tooltip = (ns.L and ns.L["MODULE_PLANS_DESC"]) or "Track personal goals for mounts, pets, toys, achievements, and custom tasks",
                get = function() return WarbandNexus.db.profile.modulesEnabled.plans ~= false end,
                set = function(value)
                    if WarbandNexus.SetPlansModuleEnabled then
                        WarbandNexus:SetPlansModuleEnabled(value)
                    else
                        WarbandNexus.db.profile.modulesEnabled.plans = value
                        WarbandNexus:SendMessage(E.MODULE_TOGGLED, "plans", value)
                    end
                end,
            },
            {
                key = "professions",
                label = (ns.L and ns.L["MODULE_PROFESSIONS"]) or "Professions",
                tooltip = (ns.L and ns.L["MODULE_PROFESSIONS_DESC"]) or "Track profession skills, tools, concentration, knowledge, and recipes across characters. Shows Recipe Companion reagent counts while a profession window is open.",
                get = function() return WarbandNexus.db.profile.modulesEnabled.professions ~= false end,
                set = function(value)
                    if WarbandNexus.SetProfessionModuleEnabled then
                        WarbandNexus:SetProfessionModuleEnabled(value)
                    else
                        WarbandNexus.db.profile.modulesEnabled.professions = value
                        WarbandNexus:SendMessage(E.MODULE_TOGGLED, "professions", value)
                    end
                end,
            },
            {
                key = "gear",
                label = (ns.L and ns.L["MODULE_GEAR"]) or "Gear",
                tooltip = (ns.L and ns.L["MODULE_GEAR_DESC"]) or "Gear management and item level tracking across characters",
                get = function() return WarbandNexus.db.profile.modulesEnabled.gear ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.gear = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "gear", value)
                end,
            },
            {
                key = "collections",
                label = (ns.L and ns.L["MODULE_COLLECTIONS"]) or "Collections",
                tooltip = (ns.L and ns.L["MODULE_COLLECTIONS_DESC"]) or "Mounts, pets, toys, and collection overview",
                get = function() return WarbandNexus.db.profile.modulesEnabled.collections ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.modulesEnabled.collections = value
                    WarbandNexus:SendMessage(E.MODULE_TOGGLED, "collections", value)
                end,
            },
            {
                key = "tryCounter",
                label = (ns.L and ns.L["MODULE_TRY_COUNTER"]) or "Try Counter",
                tooltip = (ns.L and ns.L["MODULE_TRY_COUNTER_DESC"]) or "Automatic drop attempt tracking for NPC kills, bosses, fishing, and containers. Disabling stops all try count processing, tooltips, and notifications.",
                get = function() return WarbandNexus.db.profile.modulesEnabled.tryCounter ~= false end,
                set = function(value)
                    if WarbandNexus.SetTryCounterModuleEnabled then
                        WarbandNexus:SetTryCounterModuleEnabled(value)
                    else
                        WarbandNexus.db.profile.modulesEnabled.tryCounter = value
                        WarbandNexus:SendMessage(E.MODULE_TOGGLED, "tryCounter", value)
                    end
                end,
            },
        }

        cy = CreateCheckboxGrid(inner, moduleOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_MODULES_PROFESSION_TOOLS"]) or "Profession tools",
            iw, cy, {})
        cy = CreateCheckboxGrid(inner, {
            {
                key = "recipeCompanionEnabled",
                label = (ns.L and ns.L["CONFIG_RECIPE_COMPANION"]) or "Recipe Companion",
                tooltip = (ns.L and ns.L["CONFIG_RECIPE_COMPANION_DESC"]) or "Show the Recipe Companion window alongside the Professions UI, displaying reagent availability per character.",
                get = function() return WarbandNexus.db.profile.recipeCompanionEnabled ~= false end,
                set = function(value)
                    WarbandNexus.db.profile.recipeCompanionEnabled = value
                    if not value and ns.RecipeCompanionWindow then
                        ns.RecipeCompanionWindow.Hide()
                    end
                end,
            },
        }, cy, iw)
        return cy
    end, { flat = true, noTrailingGap = true })

    local moduleContentHeight = SettingsMeasuredSectionContentHeight(moduleStackY)
    FinalizeSettingsSectionHeight(moduleSection, moduleContentHeight, false)

    yOffset = yOffset - moduleSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
