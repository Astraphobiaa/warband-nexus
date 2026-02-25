--[[
    Warband Nexus - Configuration Module
    Modern and organized settings panel
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

--============================================================================
-- HELPER FUNCTIONS (DRY - Don't Repeat Yourself)
--============================================================================

--- Create a module toggle handler (eliminates 6x duplicate code)
local function CreateModuleToggleHandler(moduleName)
    return function(_, value)
        WarbandNexus.db.profile.modulesEnabled[moduleName] = value
        WarbandNexus:SendMessage("WN_MODULE_TOGGLED", moduleName, value)
        if WarbandNexus.RefreshUI then
            WarbandNexus:RefreshUI()
        end
    end
end

-- AceConfig options table
local options = {
    name = function() return (ns.L and ns.L["CONFIG_HEADER"]) or "Warband Nexus" end,
    type = "group",
    args = {
        -- Header
        header = {
            order = 1,
            type = "description",
            name = function() return "|cff00ccff" .. ((ns.L and ns.L["CONFIG_HEADER"]) or "Warband Nexus") .. "|r\n" .. ((ns.L and ns.L["CONFIG_HEADER_DESC"]) or "Modern Warband management and cross-character tracking.") .. "\n\n" end,
            fontSize = "medium",
        },
        
        -- ===== GENERAL SETTINGS =====
        generalHeader = {
            order = 10,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_GENERAL"]) or "General Settings" end,
        },
        generalDesc = {
            order = 11,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_GENERAL_DESC"]) or "Basic addon settings and behavior options.") .. "\n" end,
        },
        enabled = {
            order = 12,
            type = "toggle",
            hidden = true,  -- Hidden from Config, functionality preserved
            name = function() return (ns.L and ns.L["CONFIG_ENABLE"]) or "Enable Addon" end,
            desc = function() return (ns.L and ns.L["CONFIG_ENABLE_DESC"]) or "Turn the addon on or off." end,
            width = 1.5,
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
            order = 13,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MINIMAP"]) or "Minimap Button" end,
            desc = function() return (ns.L and ns.L["CONFIG_MINIMAP_DESC"]) or "Show a button on the minimap for quick access." end,
            width = 1.5,
            get = function() return not WarbandNexus.db.profile.minimap.hide end,
            set = function(_, value)
                if WarbandNexus.SetMinimapButtonVisible then
                    WarbandNexus:SetMinimapButtonVisible(value)
                else
                    WarbandNexus.db.profile.minimap.hide = not value
                end
            end,
        },
        currentLanguageInfo = {
            order = 14,
            type = "description",
            hidden = true,  -- Removed from Config.lua, now in SettingsUI.lua
            name = function()
                local locale = GetLocale() or "enUS"
                local localeNames = {
                    enUS = "English (US)",
                    enGB = "English (GB)",
                    deDE = "Deutsch",
                    esES = "Español (EU)",
                    esMX = "Español (MX)",
                    frFR = "Français",
                    itIT = "Italiano",
                    koKR = "한국어",
                    ptBR = "Português",
                    ruRU = "Русский",
                    zhCN = "简体中文",
                    zhTW = "繁體中文",
                }
                local localeName = localeNames[locale] or locale
                return "|cff00ccffCurrent Language:|r " .. localeName .. "\n\n" ..
                       "|cffaaaaaa" ..
                       "Addon uses your WoW game client's language automatically. " ..
                       "Common text (Search, Close, Settings, Quality names, etc.) " ..
                       "uses Blizzard's built-in localized strings.\n\n" ..
                       "To change language, change your game client's language in Battle.net settings.|r\n"
            end,
            fontSize = "medium",
        },
        showTooltipItemCount = {
            order = 15,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP"]) or "Show Items in Tooltips" end,
            desc = function() return (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"]) or "Display Warband and Character item counts in item tooltips." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.showTooltipItemCount ~= false end,
            set = function(_, value)
                WarbandNexus.db.profile.showTooltipItemCount = value
            end,
        },
        
        -- ===== MODULE MANAGEMENT =====
        moduleManagementHeader = {
            order = 20,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_MODULES"]) or "Module Management" end,
        },
        moduleManagementDesc = {
            order = 21,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_MODULES_DESC"]) or "Enable or disable individual addon modules. Disabled modules will not collect data or display UI tabs.") .. "\n" end,
        },
        moduleCurrencies = {
            order = 22,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_CURRENCIES"]) or "Currencies" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_CURRENCIES_DESC"]) or "Track currencies across all characters." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.currencies ~= false end,
            set = CreateModuleToggleHandler("currencies"),
        },
        moduleReputations = {
            order = 23,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_REPUTATIONS"]) or "Reputations" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_REPUTATIONS_DESC"]) or "Track reputations across all characters." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.reputations ~= false end,
            set = CreateModuleToggleHandler("reputations"),
        },
        moduleItems = {
            order = 24,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_ITEMS"]) or "Items" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_ITEMS_DESC"]) or "Track items in bags and banks." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.items ~= false end,
            set = CreateModuleToggleHandler("items"),
        },
        moduleStorage = {
            order = 25,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_STORAGE"]) or "Storage" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_STORAGE_DESC"]) or "Storage tab for inventory and bank management." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.storage ~= false end,
            set = CreateModuleToggleHandler("storage"),
        },
        modulePvE = {
            order = 26,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_PVE"]) or "PvE" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_PVE_DESC"]) or "Track Great Vault, Mythic+, and raid lockouts." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.pve ~= false end,
            set = CreateModuleToggleHandler("pve"),
        },
        modulePlans = {
            order = 27,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_PLANS"]) or "Plans" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_PLANS_DESC"]) or "Collection plan tracking and completion goals." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.plans ~= false end,
            set = CreateModuleToggleHandler("plans"),
        },
        moduleProfessions = {
            order = 28,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_MOD_PROFESSIONS"]) or "Professions" end,
            desc = function() return (ns.L and ns.L["CONFIG_MOD_PROFESSIONS_DESC"]) or "Track profession skills, recipes, and concentration." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.professions ~= false end,
            set = CreateModuleToggleHandler("professions"),
        },
        spacer2a = {
            order = 29,
            type = "description",
            name = "\n",
        },
        
        -- ===== AUTOMATION =====
        automationHeader = {
            order = 40,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_AUTOMATION"]) or "Automation" end,
        },
        automationDesc = {
            order = 41,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_AUTOMATION_DESC"]) or "Control what happens automatically when you open your Warband Bank.") .. "\n" end,
        },
        autoOptimize = {
            order = 45,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE"]) or "Auto-Optimize Database" end,
            desc = function() return (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE_DESC"]) or "Automatically optimize the database on login to keep storage efficient." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoOptimize ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoOptimize = value end,
        },
        spacer3 = {
            order = 39,
            type = "description",
            name = "\n",
        },
        
        -- ===== DISPLAY =====
        displayHeader = {
            order = 40,
            type = "header",
            name = function() return (ns.L and ns.L["DISPLAY_SETTINGS"]) or "Display" end,
        },
        displayDesc = {
            order = 41,
            type = "description",
            name = function() return ((ns.L and ns.L["DISPLAY_SETTINGS_DESC"]) or "Customize how items and information are displayed.") .. "\n" end,
        },
        showItemCount = {
            order = 43,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_SHOW_ITEM_COUNT"]) or "Show Item Count" end,
            desc = function() return (ns.L and ns.L["CONFIG_SHOW_ITEM_COUNT_DESC"]) or "Display item count tooltips showing how many of each item you have across all characters." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.showItemCount end,
            set = function(_, value)
                WarbandNexus.db.profile.showItemCount = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
        recipeCompanionEnabled = {
            order = 44,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_RECIPE_COMPANION"]) or "Recipe Companion" end,
            desc = function() return (ns.L and ns.L["CONFIG_RECIPE_COMPANION_DESC"]) or "Show the Recipe Companion window alongside the Professions UI, displaying reagent availability per character." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.recipeCompanionEnabled ~= false end,
            set = function(_, value)
                WarbandNexus.db.profile.recipeCompanionEnabled = value
                if not value and ns.RecipeCompanionWindow then
                    ns.RecipeCompanionWindow.Hide()
                end
            end,
        },
        spacer4 = {
            order = 49,
            type = "description",
            name = "\n",
        },
        
        -- ===== THEME & APPEARANCE =====
        themeHeader = {
            order = 50,
            type = "header",
            name = function() return (ns.L and ns.L["THEME_APPEARANCE"]) or "Theme & Appearance" end,
        },
        themeDesc = {
            order = 51,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_THEME_COLOR_DESC"]) or "Choose the primary accent color for the addon UI.") .. " Changes apply in real-time!\n" end,
        },
        themeMasterColor = {
            order = 52,
            type = "color",
            name = function() return (ns.L and ns.L["CONFIG_THEME_COLOR"]) or "Master Theme Color" end,
            desc = function() return (ns.L and ns.L["CONFIG_THEME_COLOR_DESC"]) or "Choose the primary accent color for the addon UI." end,
            hasAlpha = false,
            width = "full",
            get = function()
                local c = WarbandNexus.db.profile.themeColors.accent
                return c[1], c[2], c[3]
            end,
            set = function(_, r, g, b)
                colorPickerConfirmed = true
                colorPickerOriginalColors = nil
                
                local finalColors = ns.UI_CalculateThemeColors(r, g, b)
                WarbandNexus.db.profile.themeColors = finalColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            end,
        },
        themePresetPurple = {
            order = 53,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_PURPLE"]) or "Purple Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_PURPLE_DESC"]) or "Classic purple theme (default)" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_PURPLE"]) or "Purple"))
            end,
        },
        themePresetBlue = {
            order = 54,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_BLUE"]) or "Blue Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_BLUE_DESC"]) or "Cool blue theme" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_BLUE"]) or "Blue"))
            end,
        },
        themePresetGreen = {
            order = 55,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_GREEN"]) or "Green Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_GREEN_DESC"]) or "Nature green theme" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_GREEN"]) or "Green"))
            end,
        },
        themePresetRed = {
            order = 56,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_RED"]) or "Red Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_RED_DESC"]) or "Fiery red theme" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_RED"]) or "Red"))
            end,
        },
        themePresetOrange = {
            order = 57,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_ORANGE"]) or "Orange Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_ORANGE_DESC"]) or "Warm orange theme" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_ORANGE"]) or "Orange"))
            end,
        },
        themePresetCyan = {
            order = 58,
            type = "execute",
            name = function() return (ns.L and ns.L["COLOR_CYAN"]) or "Cyan Theme" end,
            desc = function() return (ns.L and ns.L["COLOR_CYAN_DESC"]) or "Bright cyan theme" end,
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.00, 0.80, 1.00)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_CYAN"]) or "Cyan"))
            end,
        },
        themeResetButton = {
            order = 59,
            type = "execute",
            name = function() return ((ns.L and ns.L["RESET_DEFAULT"]) or "Reset to Default") .. " (" .. ((ns.L and ns.L["COLOR_PURPLE"]) or "Purple") .. ")" end,
            desc = function() return (ns.L and ns.L["CONFIG_THEME_RESET_DESC"]) or "Reset all theme colors to their default purple theme." end,
            width = "full",
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_THEME_APPLIED"]) or "%s theme applied!", (ns.L and ns.L["COLOR_PURPLE"]) or "Purple"))
            end,
        },
        spacer5 = {
            order = 59.5,
            type = "description",
            name = "\n",
        },
        
        -- ===== NOTIFICATIONS =====
        notificationsHeader = {
            order = 70,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_NOTIFICATIONS"]) or "Notifications" end,
        },
        notificationsDesc = {
            order = 71,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_NOTIFICATIONS_DESC"]) or "Configure which notifications appear.") .. "\n" end,
        },
        notificationsEnabled = {
            order = 72,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_ENABLE_NOTIFICATIONS"]) or "Enable Notifications" end,
            desc = function() return (ns.L and ns.L["CONFIG_ENABLE_NOTIFICATIONS_DESC"]) or "Show popup notifications for collectible events." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.enabled = value
                -- Master toggle affects Blizzard message suppression/restoration
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        showUpdateNotes = {
            order = 73,
            type = "toggle",
            hidden = true,  -- Hidden from Config.lua (always enabled, managed via Core.lua)
            name = function() return (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES"]) or "Show Update Notes" end,
            desc = function() return (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES_DESC"]) or "Display the What's New window on next login." end,
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showUpdateNotes end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showUpdateNotes = value end,
        },
        showVaultReminder = {
            order = 74,
            type = "toggle",
            name = function() return (ns.L and ns.L["VAULT_REMINDER"]) or "Weekly Vault Reminder" end,
            desc = function() return (ns.L and ns.L["VAULT_REMINDER_TOOLTIP"]) or "Show a reminder popup on login when you have unclaimed Great Vault rewards" end,
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        showLootNotifications = {
            order = 75,
            type = "toggle",
            name = function() return (ns.L and ns.L["LOOT_ALERTS"]) or "Mount/Pet/Toy Loot Alerts" end,
            desc = function() return (ns.L and ns.L["LOOT_ALERTS_TOOLTIP"]) or "Show a popup when a NEW mount, pet, toy, or achievement enters your collection." end,
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        showReputationGains = {
            order = 76,
            type = "toggle",
            name = function() return (ns.L and ns.L["REPUTATION_GAINS"]) or "Show Reputation Gains" end,
            desc = function() return (ns.L and ns.L["REPUTATION_GAINS_TOOLTIP"]) or "Display reputation gain messages in chat when you earn faction standing." end,
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showReputationGains end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.showReputationGains = value
                -- Update chat filter (suppress/restore Blizzard messages)
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        showCurrencyGains = {
            order = 76.5,
            type = "toggle",
            name = function() return (ns.L and ns.L["CURRENCY_GAINS"]) or "Show Currency Gains" end,
            desc = function() return (ns.L and ns.L["CURRENCY_GAINS_TOOLTIP"]) or "Display currency gain messages in chat when you earn currencies." end,
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showCurrencyGains end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.showCurrencyGains = value
                -- Update chat filter (suppress/restore Blizzard messages)
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        resetVersionButton = {
            order = 77,
            type = "execute",
            hidden = true,  -- Removed from Config.lua
            name = function() return (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES"]) or "Show Update Notes Again" end,
            desc = function() return (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES_DESC"]) or "Reset the 'last seen version' to show the update notification again on next login." end,
            width = 1.5,
            func = function()
                WarbandNexus.db.profile.notifications.lastSeenVersion = "0.0.0"
                WarbandNexus:Print((ns.L and ns.L["CONFIG_UPDATE_NOTES_SHOWN"]) or "Update notification will show on next login.")
            end,
        },
        resetCompletedPlansButton = {
            order = 78,
            type = "execute",
            hidden = true,  -- Moved to PlansUI.lua
            name = function() return (ns.L and ns.L["CONFIG_RESET_PLANS"]) or "Reset Completed Plans" end,
            desc = function() return (ns.L and ns.L["REMOVE_COMPLETED_TOOLTIP"]) or "Remove all completed plans from your My Plans list. This action cannot be undone!" end,
            width = 1.5,
            confirm = true,
            confirmText = "Are you sure you want to remove ALL completed plans? This cannot be undone!",
            func = function()
                if WarbandNexus.ResetCompletedPlans then
                    local count = WarbandNexus:ResetCompletedPlans()
                    WarbandNexus:Print(string.format((ns.L and ns.L["CONFIG_RESET_PLANS_FORMAT"]) or "Removed %d completed plan(s).", count))
                    if WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end
            end,
        },
        spacer7 = {
            order = 79,
            type = "description",
            name = "\n",
        },
        
        -- ===== TAB FILTERING =====
        tabHeader = {
            order = 100,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_TAB_FILTERING"]) or "Tab Filtering" end,
        },
        tabDesc = {
            order = 101,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_TAB_FILTERING_DESC"]) or "Choose which tabs are visible in the main window.") .. "\n" end,
        },
        ignoredTab1 = {
            order = 102,
            type = "toggle",
            name = function() return string.format((ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Tab %d", 1) end,
            desc = function() return (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) and string.format(ns.L["IGNORE_SCAN_FORMAT"], string.format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", 1)) or "Exclude this Warband Bank tab from automatic scanning" end,
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[1] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[1] = value end,
        },
        ignoredTab2 = {
            order = 103,
            type = "toggle",
            name = function() return string.format((ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Tab %d", 2) end,
            desc = function() return (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) and string.format(ns.L["IGNORE_SCAN_FORMAT"], string.format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", 2)) or "Exclude this Warband Bank tab from automatic scanning" end,
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[2] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[2] = value end,
        },
        ignoredTab3 = {
            order = 104,
            type = "toggle",
            name = function() return string.format((ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Tab %d", 3) end,
            desc = function() return (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) and string.format(ns.L["IGNORE_SCAN_FORMAT"], string.format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", 3)) or "Exclude this Warband Bank tab from automatic scanning" end,
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[3] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[3] = value end,
        },
        ignoredTab4 = {
            order = 105,
            type = "toggle",
            name = function() return string.format((ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Tab %d", 4) end,
            desc = function() return (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) and string.format(ns.L["IGNORE_SCAN_FORMAT"], string.format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", 4)) or "Exclude this Warband Bank tab from automatic scanning" end,
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[4] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[4] = value end,
        },
        ignoredTab5 = {
            order = 106,
            type = "toggle",
            name = function() return string.format((ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Tab %d", 5) end,
            desc = function() return (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) and string.format(ns.L["IGNORE_SCAN_FORMAT"], string.format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", 5)) or "Exclude this Warband Bank tab from automatic scanning" end,
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[5] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[5] = value end,
        },
        spacer9 = {
            order = 109,
            type = "description",
            name = "\n",
        },
        
        -- ===== CHARACTER MANAGEMENT =====
        characterManagementHeader = {
            order = 110,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_CHARACTER_MGMT"]) or "Character Management" end,
        },
        characterManagementDesc = {
            order = 111,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_CHARACTER_MGMT_DESC"]) or "Manage tracked characters and remove old data.") .. "\n\n|cffff9900Warning:|r Deleting a character removes all saved data. This action cannot be undone.\n" end,
        },
        deleteCharacterDropdown = {
            order = 112,
            type = "select",
            hidden = true,  -- Moved to CharactersUI.lua
            name = function() return (ns.L and ns.L["CONFIG_DELETE_CHAR"]) or "Select Character to Delete" end,
            desc = function() return (ns.L and ns.L["CONFIG_DELETE_CHAR_DESC"]) or "Choose a character from the list to delete their data" end,
            width = "full",
            values = function()
                local chars = {}
                local allChars = WarbandNexus:GetAllCharacters()
                
                local currentPlayerName = UnitName("player")
                local currentPlayerRealm = GetRealmName()
                local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
                
                for _, char in ipairs(allChars) do
                    local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                    if key ~= currentPlayerKey then
                        chars[key] = string.format("%s (%s) - Level %d", 
                            char.name or "Unknown", 
                            char.classFile or "?", 
                            char.level or 0)
                    end
                end
                
                return chars
            end,
            get = function() 
                return WarbandNexus.selectedCharacterToDelete 
            end,
            set = function(_, value)
                WarbandNexus.selectedCharacterToDelete = value
            end,
        },
        deleteCharacterButton = {
            order = 113,
            type = "execute",
            hidden = true,  -- Moved to CharactersUI.lua
            name = function() return (ns.L and ns.L["DELETE_CHARACTER"]) or "Delete Selected Character" end,
            desc = function() return (ns.L and ns.L["CONFIG_DELETE_CHAR_DESC"]) or "Permanently delete the selected character's data" end,
            width = "full",
            disabled = function()
                return not WarbandNexus.selectedCharacterToDelete
            end,
            confirm = function()
                if not WarbandNexus.selectedCharacterToDelete then
                    return false
                end
                local char = WarbandNexus.db.global.characters[WarbandNexus.selectedCharacterToDelete]
                if char then
                    return string.format(
                        "Are you sure you want to delete |cff00ccff%s|r?\n\n" ..
                        "This will remove:\n" ..
                        "• Gold data\n" ..
                        "• Personal bank cache\n" ..
                        "• Profession info\n" ..
                        "• PvE progress\n" ..
                        "• All statistics\n\n" ..
                        "|cffff0000This action cannot be undone!|r",
                        char.name or "this character"
                    )
                end
                return "Delete this character?"
            end,
            func = function()
                if WarbandNexus.selectedCharacterToDelete then
                    local success = WarbandNexus:DeleteCharacter(WarbandNexus.selectedCharacterToDelete)
                    if success then
                        WarbandNexus.selectedCharacterToDelete = nil
                        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                        AceConfigRegistry:NotifyChange("Warband Nexus")
                        if WarbandNexus.RefreshUI then
                            WarbandNexus:RefreshUI()
                        end
                    else
                        WarbandNexus:Print("|cffff0000Failed to delete character. Character may not exist.|r")
                    end
                end
            end,
        },
        spacerFont = {
            order = 119,
            type = "description",
            name = "\n",
        },
        
        -- ===== FONT & SCALING =====
        fontHeader = {
            order = 120,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_FONT_SCALING"]) or "Font & Scaling" end,
        },
        fontDesc = {
            order = 121,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_FONT_SCALING_DESC"]) or "Adjust font family and size scaling.") .. "\n" end,
        },
        fontFace = {
            order = 122,
            type = "select",
            name = function() return (ns.L and ns.L["CONFIG_FONT_FAMILY"]) or "Font Family" end,
            desc = function() return (ns.L and ns.L["FONT_FAMILY_TOOLTIP"]) or "Choose the font used throughout the addon UI" end,
            width = "full",
            values = function()
                return (ns.GetFilteredFontOptions and ns.GetFilteredFontOptions()) or {
                    ["Friz Quadrata TT"] = "Friz Quadrata TT",
                    ["Arial Narrow"] = "Arial Narrow",
                    ["Skurri"] = "Skurri",
                    ["Morpheus"] = "Morpheus",
                    ["Action Man"] = "Action Man",
                    ["Continuum Medium"] = "Continuum Medium",
                    ["Expressway"] = "Expressway",
                }
            end,
            get = function() return WarbandNexus.db.profile.fonts.fontFace end,
            set = function(_, value)
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM and LSM.IsValid and LSM.MediaType and not LSM:IsValid(LSM.MediaType.FONT, value) then
                    value = "Friz Quadrata TT"
                end
                WarbandNexus.db.profile.fonts.fontFace = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
                -- Defer RefreshUI after font warm-up completes
                C_Timer.After(0.3, function()
                    if WarbandNexus and WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end)
            end,
        },
        fontScale = {
            order = 123,
            type = "range",
            name = function() return (ns.L and ns.L["FONT_SCALE"]) or "Font Scale" end,
            desc = function() return (ns.L and ns.L["FONT_SCALE_TOOLTIP"]) or "Adjust font size across all UI elements." end,
            width = "full",
            min = 0.8,
            max = 1.5,
            step = 0.1,  -- Larger steps for visible changes (1.0, 1.1, 1.2, etc.)
            get = function() return WarbandNexus.db.profile.fonts.scaleCustom or 1.0 end,
            set = function(_, value)
                WarbandNexus.db.profile.fonts.scaleCustom = value
                WarbandNexus.db.profile.fonts.useCustomScale = true
                
                -- Immediate font refresh (no debounce - slider already snaps to discrete values)
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
            end,
        },
        antiAliasing = {
            order = 126,
            type = "select",
            name = function() return (ns.L and ns.L["ANTI_ALIASING"]) or "Anti-Aliasing" end,
            desc = function() return (ns.L and ns.L["ANTI_ALIASING_DESC"]) or "Font edge rendering style (affects readability)" end,
            width = 1.5,
            values = {
                none = "None (Smooth)",
                OUTLINE = "Outline (Default)",
                THICKOUTLINE = "Thick Outline (Bold)",
            },
            get = function() return WarbandNexus.db.profile.fonts.antiAliasing end,
            set = function(_, value)
                WarbandNexus.db.profile.fonts.antiAliasing = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
            end,
        },
        usePixelNormalization = {
            order = 127,
            type = "toggle",
            name = function() return (ns.L and ns.L["RESOLUTION_NORMALIZATION"]) or "Resolution Normalization" end,
            desc = function() return (ns.L and ns.L["RESOLUTION_NORMALIZATION_TOOLTIP"]) or "Adjust font sizes based on screen resolution and UI scale for consistent physical size across different displays" end,
            width = "full",
            get = function() return WarbandNexus.db.profile.fonts.usePixelNormalization end,
            set = function(_, value)
                WarbandNexus.db.profile.fonts.usePixelNormalization = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
            end,
        },
        fontPreview = {
            order = 128,
            type = "description",
            name = function()
                if ns.FontManager and ns.FontManager.GetPreviewText then
                    return "|cff00ccffCalculated Font Sizes:|r\n" .. ns.FontManager:GetPreviewText() .. "\n"
                end
                return ""
            end,
            fontSize = "medium",
        },
        spacer10 = {
            order = 899,
            type = "description",
            name = "\n\n",
        },
        
        -- ===== ADVANCED =====
        advancedHeader = {
            order = 900,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_ADVANCED"]) or "Advanced" end,
        },
        advancedDesc = {
            order = 901,
            type = "description",
            name = function() return ((ns.L and ns.L["CONFIG_ADVANCED_DESC"]) or "Advanced settings and database management. Use with caution!") .. "\n" end,
        },
        debugMode = {
            order = 902,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_DEBUG_MODE"]) or "Debug Mode" end,
            desc = function() return (ns.L and ns.L["CONFIG_DEBUG_MODE_DESC"]) or "Enable verbose logging for debugging purposes. Only enable if troubleshooting issues." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.debugMode end,
            set = function(_, value)
                WarbandNexus.db.profile.debugMode = value
                if value then
                    WarbandNexus:Print("|cff00ff00Debug mode enabled|r")
                else
                    WarbandNexus:Print("|cffff9900Debug mode disabled|r")
                end
            end,
        },
        debugVerbose = {
            order = 902.5,
            type = "toggle",
            name = function() return (ns.L and ns.L["CONFIG_DEBUG_VERBOSE"]) or "Debug Verbose (cache/scan/tooltip logs)" end,
            desc = function() return (ns.L and ns.L["CONFIG_DEBUG_VERBOSE_DESC"]) or "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam." end,
            width = 1.5,
            get = function() return WarbandNexus.db.profile.debugVerbose end,
            set = function(_, value) WarbandNexus.db.profile.debugVerbose = value end,
        },
        databaseStatsButton = {
            order = 903,
            type = "execute",
            hidden = true,  -- Removed from Config.lua
            name = function() return (ns.L and ns.L["CONFIG_DB_STATS"]) or "Show Database Statistics" end,
            desc = function() return (ns.L and ns.L["CONFIG_DB_STATS_DESC"]) or "Display current database size and optimization statistics." end,
            width = 1.5,
            func = function()
                if WarbandNexus.PrintDatabaseStats then
                    WarbandNexus:PrintDatabaseStats()
                else
                    WarbandNexus:Print("Database optimizer not loaded")
                end
            end,
        },
        optimizeDatabaseButton = {
            order = 904,
            type = "execute",
            hidden = true,  -- Removed from Config.lua (auto-optimized)
            name = function() return (ns.L and ns.L["CONFIG_OPTIMIZE_NOW"]) or "Optimize Database Now" end,
            desc = function() return (ns.L and ns.L["CONFIG_OPTIMIZE_NOW_DESC"]) or "Run the database optimizer to clean up and compress stored data." end,
            width = 1.5,
            func = function()
                if WarbandNexus.RunOptimization then
                    WarbandNexus:RunOptimization()
                else
                    WarbandNexus:Print("Database optimizer not loaded")
                end
            end,
        },
        spacerAdvanced = {
            order = 905,
            type = "description",
            name = "\n",
        },
        wipeAllData = {
            order = 999,
            type = "execute",
            name = "|cffff0000Wipe All Data|r",
            desc = "DELETE ALL addon data (characters, items, currency, reputations, settings). Cannot be undone!\n\n|cffff9900You will be prompted to type 'Accept' to confirm (case insensitive).|r",
            width = "full",
            confirm = false,  -- We use custom confirmation
            func = function()
                WarbandNexus:ShowWipeDataConfirmation()
            end,
        },
        spacer11 = {
            order = 199,
            type = "description",
            name = "\n",
        },
        
        -- ===== TRACK ITEM DB =====
        trackDBHeader = {
            order = 200,
            type = "header",
            name = function() return L["TRACK_ITEM_DB"] end,
        },
        trackDBDesc = {
            order = 201,
            type = "description",
            name = function() return L["TRACK_ITEM_DB_DESC"] .. "\n" end,
        },
        
        -- Add Custom Entry: Item ID Input
        trackDB_itemID = {
            order = 202,
            type = "input",
            name = function() return L["ITEM_ID_INPUT"] end,
            desc = function() return L["ITEM_ID_INPUT_DESC"] end,
            width = 1,
            get = function() return ns._trackDBForm and tostring(ns._trackDBForm.itemID or "") or "" end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.itemID = tonumber(val) or nil
                ns._trackDBForm.itemName = nil
                ns._trackDBForm.itemIcon = nil
                ns._trackDBForm.itemType = nil
            end,
        },
        trackDB_lookupBtn = {
            order = 203,
            type = "execute",
            name = function() return L["LOOKUP_ITEM"] end,
            desc = function() return L["LOOKUP_ITEM_DESC"] end,
            width = 0.7,
            func = function()
                if not ns._trackDBForm or not ns._trackDBForm.itemID then return end
                WarbandNexus:LookupItem(ns._trackDBForm.itemID, function(itemID, name, icon, cType)
                    if name then
                        ns._trackDBForm.itemName = name
                        ns._trackDBForm.itemIcon = icon
                        ns._trackDBForm.itemType = cType
                        WarbandNexus:Print(format(L["ITEM_RESOLVED"], name, cType))
                    else
                        WarbandNexus:Print(L["ITEM_LOOKUP_FAILED"])
                    end
                end)
            end,
        },
        trackDB_lookupResult = {
            order = 204,
            type = "description",
            name = function()
                if ns._trackDBForm and ns._trackDBForm.itemName then
                    local icon = ns._trackDBForm.itemIcon and ("|T" .. ns._trackDBForm.itemIcon .. ":16|t ") or ""
                    return icon .. "|cff00ff00" .. ns._trackDBForm.itemName .. "|r (" .. (ns._trackDBForm.itemType or "item") .. ")\n"
                end
                return ""
            end,
        },
        trackDB_sourceType = {
            order = 205,
            type = "select",
            name = function() return L["SOURCE_TYPE"] end,
            desc = function() return L["SOURCE_TYPE_DESC"] end,
            width = 1,
            values = { npc = L["SOURCE_TYPE_NPC"], object = L["SOURCE_TYPE_OBJECT"] },
            get = function()
                return ns._trackDBForm and ns._trackDBForm.sourceType or "npc"
            end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.sourceType = val
            end,
        },
        trackDB_sourceID = {
            order = 206,
            type = "input",
            name = function() return L["SOURCE_ID"] end,
            desc = function() return L["SOURCE_ID_DESC"] end,
            width = 1,
            get = function() return ns._trackDBForm and tostring(ns._trackDBForm.sourceID or "") or "" end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.sourceID = tonumber(val) or nil
            end,
        },
        trackDB_sourceName = {
            order = 207,
            type = "input",
            name = function() return L["SOURCE_NAME"] end,
            desc = function() return L["SOURCE_NAME_DESC"] end,
            width = 1.5,
            get = function() return ns._trackDBForm and ns._trackDBForm.sourceName or "" end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.sourceName = val ~= "" and val or nil
            end,
        },
        trackDB_repeatable = {
            order = 208,
            type = "toggle",
            name = function() return L["REPEATABLE_TOGGLE"] end,
            desc = function() return L["REPEATABLE_TOGGLE_DESC"] end,
            width = 1,
            get = function() return ns._trackDBForm and ns._trackDBForm.repeatable or false end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.repeatable = val
            end,
        },
        trackDB_statIds = {
            order = 209,
            type = "input",
            name = function() return L["STATISTIC_IDS"] end,
            desc = function() return L["STATISTIC_IDS_DESC"] end,
            width = 1.5,
            get = function() return ns._trackDBForm and ns._trackDBForm.statIds or "" end,
            set = function(_, val)
                if not ns._trackDBForm then ns._trackDBForm = {} end
                ns._trackDBForm.statIds = val
            end,
        },
        trackDB_addBtn = {
            order = 210,
            type = "execute",
            name = function() return L["ADD_ENTRY"] end,
            desc = function() return L["ADD_ENTRY_DESC"] end,
            width = "full",
            func = function()
                local f = ns._trackDBForm
                if not f or not f.itemID or not f.sourceID then
                    WarbandNexus:Print(L["ENTRY_ADD_FAILED"])
                    return
                end
                local drop = {
                    type = f.itemType or "item",
                    itemID = f.itemID,
                    name = f.itemName or ("Item " .. f.itemID),
                    repeatable = f.repeatable or nil,
                }
                -- Parse statistic IDs
                local statIds
                if f.statIds and f.statIds ~= "" then
                    statIds = {}
                    for id in f.statIds:gmatch("%d+") do
                        statIds[#statIds + 1] = tonumber(id)
                    end
                    if #statIds == 0 then statIds = nil end
                end
                local ok = WarbandNexus:AddCustomDrop(f.sourceType or "npc", f.sourceID, drop, statIds)
                if ok then
                    WarbandNexus:Print(L["ENTRY_ADDED"])
                    -- Reset form
                    ns._trackDBForm = {}
                else
                    WarbandNexus:Print(L["ENTRY_ADD_FAILED"])
                end
            end,
        },
        
        -- Custom Entries List
        trackDB_customHeader = {
            order = 220,
            type = "header",
            name = function() return L["CUSTOM_ENTRIES"] end,
        },
        trackDB_customDesc = {
            order = 221,
            type = "description",
            name = function()
                if not WarbandNexus.db or not WarbandNexus.db.global then return L["NO_CUSTOM_ENTRIES"] .. "\n" end
                local trackDB = WarbandNexus.db.global.trackDB
                if not trackDB or not trackDB.custom then return L["NO_CUSTOM_ENTRIES"] .. "\n" end
                
                local lines = {}
                -- NPC entries
                for npcID, drops in pairs(trackDB.custom.npcs or {}) do
                    for i = 1, #drops do
                        local d = drops[i]
                        lines[#lines + 1] = format("  |cff00ccffNPC %s|r: %s (ID: %d) [%s]",
                            tostring(npcID), d.name or "?", d.itemID or 0, d.type or "item")
                    end
                end
                -- Object entries
                for objID, drops in pairs(trackDB.custom.objects or {}) do
                    for i = 1, #drops do
                        local d = drops[i]
                        lines[#lines + 1] = format("  |cff00ccffObject %s|r: %s (ID: %d) [%s]",
                            tostring(objID), d.name or "?", d.itemID or 0, d.type or "item")
                    end
                end
                
                if #lines == 0 then return L["NO_CUSTOM_ENTRIES"] .. "\n" end
                return table.concat(lines, "\n") .. "\n"
            end,
        },
        trackDB_removeInput = {
            order = 222,
            type = "input",
            name = "Remove (SourceType:SourceID:ItemID)",
            desc = "Enter 'npc:12345:67890' or 'object:12345:67890' to remove a custom entry.",
            width = "full",
            get = function() return "" end,
            set = function(_, val)
                local sourceType, sourceID, itemID = strsplit(":", val)
                sourceID = tonumber(sourceID)
                itemID = tonumber(itemID)
                if sourceType and sourceID and itemID then
                    local ok = WarbandNexus:RemoveCustomDrop(sourceType, sourceID, itemID)
                    if ok then
                        WarbandNexus:Print(L["ENTRY_REMOVED"])
                    end
                end
            end,
        },
        
        -- Manage Built-in Tracking
        trackDB_builtinHeader = {
            order = 230,
            type = "header",
            name = function() return L["MANAGE_BUILTIN"] end,
        },
        trackDB_builtinDesc = {
            order = 231,
            type = "description",
            name = function() return L["MANAGE_BUILTIN_DESC"] .. "\n" end,
        },
        trackDB_searchInput = {
            order = 232,
            type = "input",
            name = function() return L["SEARCH_BUILTIN"] end,
            desc = function() return L["SEARCH_BUILTIN_DESC"] end,
            width = 1.5,
            get = function() return ns._trackDBSearch and tostring(ns._trackDBSearch.query or "") or "" end,
            set = function(_, val)
                if not ns._trackDBSearch then ns._trackDBSearch = {} end
                ns._trackDBSearch.query = tonumber(val)
                ns._trackDBSearch.results = nil
            end,
        },
        trackDB_searchBtn = {
            order = 233,
            type = "execute",
            name = function() return L["SEARCH_BUTTON"] end,
            width = 0.7,
            func = function()
                if not ns._trackDBSearch or not ns._trackDBSearch.query then return end
                local itemID = ns._trackDBSearch.query
                local results = {}
                local db = ns.CollectibleSourceDB
                if db then
                    -- Search NPC drops
                    for npcID, drops in pairs(db.npcs or {}) do
                        for i = 1, #drops do
                            if drops[i].itemID == itemID then
                                results[#results + 1] = {
                                    sourceType = "npc",
                                    sourceID = npcID,
                                    drop = drops[i],
                                    tracked = WarbandNexus:IsBuiltinTracked("npc", npcID, itemID),
                                }
                            end
                        end
                    end
                    -- Search Object drops
                    for objID, drops in pairs(db.objects or {}) do
                        for i = 1, #drops do
                            if drops[i].itemID == itemID then
                                results[#results + 1] = {
                                    sourceType = "object",
                                    sourceID = objID,
                                    drop = drops[i],
                                    tracked = WarbandNexus:IsBuiltinTracked("object", objID, itemID),
                                }
                            end
                        end
                    end
                end
                ns._trackDBSearch.results = results
            end,
        },
        trackDB_searchResults = {
            order = 234,
            type = "description",
            name = function()
                if not ns._trackDBSearch or not ns._trackDBSearch.results then return "" end
                local results = ns._trackDBSearch.results
                if #results == 0 then return L["NO_RESULTS"] .. "\n" end
                
                local lines = {}
                for _, r in ipairs(results) do
                    local status = r.tracked and ("|cff00ff00" .. L["TRACKED"] .. "|r") or ("|cffff0000" .. L["UNTRACKED"] .. "|r")
                    lines[#lines + 1] = format("  %s %s: %s (Item %d) - %s",
                        r.sourceType == "npc" and "NPC" or "Object",
                        tostring(r.sourceID),
                        r.drop.name or "?",
                        r.drop.itemID or 0,
                        status)
                end
                return table.concat(lines, "\n") .. "\n"
            end,
        },
        trackDB_toggleInput = {
            order = 235,
            type = "input",
            name = "Toggle (SourceType:SourceID:ItemID)",
            desc = "Enter 'npc:12345:67890' to toggle tracking for a built-in entry.",
            width = "full",
            get = function() return "" end,
            set = function(_, val)
                local sourceType, sourceID, itemID = strsplit(":", val)
                sourceID = tonumber(sourceID)
                itemID = tonumber(itemID)
                if sourceType and sourceID and itemID then
                    local isTracked = WarbandNexus:IsBuiltinTracked(sourceType, sourceID, itemID)
                    WarbandNexus:SetBuiltinTracked(sourceType, sourceID, itemID, not isTracked)
                    WarbandNexus:Print(format("%s:%s:%s is now %s",
                        sourceType, sourceID, itemID,
                        (not isTracked) and L["TRACKED"] or L["UNTRACKED"]))
                end
            end,
        },
        
        -- Currently Untracked List
        trackDB_untrackedHeader = {
            order = 240,
            type = "header",
            name = function() return L["CURRENTLY_UNTRACKED"] end,
        },
        trackDB_untrackedDesc = {
            order = 241,
            type = "description",
            name = function()
                if not WarbandNexus.db or not WarbandNexus.db.global then return "" end
                local trackDB = WarbandNexus.db.global.trackDB
                if not trackDB or not trackDB.disabled then return "" end
                
                local lines = {}
                local db = ns.CollectibleSourceDB
                for key in pairs(trackDB.disabled) do
                    local sourceType, sourceID, itemID = strsplit(":", key)
                    sourceID = tonumber(sourceID)
                    itemID = tonumber(itemID)
                    local dropName = "Item " .. (itemID or "?")
                    -- Try to find the name from CollectibleSourceDB
                    if db and sourceID and itemID then
                        local sourceDB = sourceType == "npc" and db.npcs or db.objects
                        if sourceDB and sourceDB[sourceID] then
                            for _, d in ipairs(sourceDB[sourceID]) do
                                if d.itemID == itemID then
                                    dropName = d.name or dropName
                                    break
                                end
                            end
                        end
                    end
                    lines[#lines + 1] = format("  |cffff6600%s %s|r: %s (ID: %d) — type |cff00ccff%s:%s:%s|r to re-enable",
                        sourceType == "npc" and "NPC" or "Object",
                        tostring(sourceID),
                        dropName,
                        itemID or 0,
                        sourceType, tostring(sourceID), tostring(itemID))
                end
                
                if #lines == 0 then return "None.\n" end
                return table.concat(lines, "\n") .. "\n"
            end,
        },
        
        spacer12 = {
            order = 949,
            type = "description",
            name = "\n",
        },
        
        -- ===== SLASH COMMANDS =====
        commandsHeader = {
            order = 950,
            type = "header",
            name = function() return (ns.L and ns.L["CONFIG_COMMANDS_HEADER"]) or "Slash Commands" end,
        },
        commandsDesc = {
            order = 951,
            type = "description",
            name = [[
|cff00ccff/wn|r or |cff00ccff/wn show|r - Toggle the main window
|cff00ccff/wn plan|r - Toggle Plans Tracker window
|cff00ccff/wn options|r - Open this settings panel
|cff00ccff/wn minimap|r - Toggle minimap button
|cff00ccff/wn changelog|r - Show changelog
|cff00ccff/wn help|r - Show all commands
]],
            fontSize = "medium",
        },
    },
}

-- ===== COLOR PICKER REAL-TIME PREVIEW HOOK =====
local colorPickerOriginalColors = nil
local colorPickerHookInstalled = false
local colorPickerTicker = nil
local lastR, lastG, lastB = nil, nil, nil
local colorPickerConfirmed = false

-- TAINT FIX: ColorPickerFrame hooks are now installed LAZILY (on first color picker open)
-- instead of during OnInitialize. Hooking Blizzard frames during addon init can taint
-- the frame's script handler chain, causing ADDON_ACTION_FORBIDDEN on /reload in TWW.
local function InstallColorPickerPreviewHook()
    if colorPickerHookInstalled then return end
    -- CRITICAL: Don't hook Blizzard frames during combat
    if InCombatLockdown() then return end
    if not ColorPickerFrame then return end
    colorPickerHookInstalled = true
    
    ColorPickerFrame:HookScript("OnShow", function()
        colorPickerConfirmed = false
        
        if WarbandNexus and WarbandNexus.ShowMainWindow then
            WarbandNexus:ShowMainWindow()
        end
        
        local current = WarbandNexus.db.profile.themeColors
        colorPickerOriginalColors = {
            accent = {current.accent[1], current.accent[2], current.accent[3]},
            accentDark = {current.accentDark[1], current.accentDark[2], current.accentDark[3]},
            border = {current.border[1], current.border[2], current.border[3]},
            tabActive = {current.tabActive[1], current.tabActive[2], current.tabActive[3]},
            tabHover = {current.tabHover[1], current.tabHover[2], current.tabHover[3]},
        }
        
        lastR, lastG, lastB = ColorPickerFrame:GetColorRGB()
        
        if colorPickerTicker then
            colorPickerTicker:Cancel()
        end
        
        colorPickerTicker = C_Timer.NewTicker(0.05, function()
            if not ColorPickerFrame:IsShown() then
                return
            end
            
            local r, g, b = ColorPickerFrame:GetColorRGB()
            
            local tolerance = 0.001
            if math.abs(r - (lastR or 0)) > tolerance or 
               math.abs(g - (lastG or 0)) > tolerance or 
               math.abs(b - (lastB or 0)) > tolerance then
                
                lastR, lastG, lastB = r, g, b
                
                local previewColors = ns.UI_CalculateThemeColors(r, g, b)
                WarbandNexus.db.profile.themeColors = previewColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            end
        end)
    end)
    
    local okayButton = ColorPickerFrame.Footer and ColorPickerFrame.Footer.OkayButton or ColorPickerOkayButton
    local cancelButton = ColorPickerFrame.Footer and ColorPickerFrame.Footer.CancelButton or ColorPickerCancelButton
    
    if okayButton then
        okayButton:HookScript("OnClick", function()
            colorPickerConfirmed = true
        end)
    end
    
    if cancelButton then
        cancelButton:HookScript("OnClick", function()
            colorPickerConfirmed = false
        end)
    end
    
    ColorPickerFrame:HookScript("OnHide", function()
        if colorPickerTicker then
            colorPickerTicker:Cancel()
            colorPickerTicker = nil
        end
        
        C_Timer.After(0.05, function()
            if not colorPickerConfirmed and colorPickerOriginalColors then
                WarbandNexus.db.profile.themeColors = colorPickerOriginalColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            end
            
            if not colorPickerConfirmed then
                colorPickerOriginalColors = nil
            end
            colorPickerConfirmed = false
            lastR, lastG, lastB = nil, nil, nil
        end)
    end)
end

-- Expose for lazy installation from SettingsUI color picker
ns.InstallColorPickerPreviewHook = InstallColorPickerPreviewHook

--[[
    Show Wipe Data Confirmation Popup
]]
function WarbandNexus:ShowWipeDataConfirmation()
    if not StaticPopupDialogs["WARBANDNEXUS_WIPE_CONFIRM"] then
        StaticPopupDialogs["WARBANDNEXUS_WIPE_CONFIRM"] = {
            text = "|cffff0000WIPE ALL DATA|r\n\n" ..
                   "This will permanently delete ALL data:\n" ..
                   "• All tracked characters\n" ..
                   "• All cached items\n" ..
                   "• All currency data\n" ..
                   "• All reputation data\n" ..
                   "• All PvE progress\n" ..
                   "• All settings\n\n" ..
                   "|cffffaa00This action CANNOT be undone!|r\n\n" ..
                   "Type |cff00ccffAccept|r to confirm:",
            button1 = "Cancel",
            button2 = nil,
            hasEditBox = true,
            maxLetters = 10,
            OnAccept = function(self)
                local editBox = self.EditBox or self.editBox
                local text = editBox and editBox:GetText()
                if text and text:lower() == "accept" then
                    WarbandNexus:WipeAllData()
                else
                    WarbandNexus:Print("|cffff6600You must type 'Accept' to confirm.|r")
                end
            end,
            OnShow = function(self)
                local editBox = self.EditBox or self.editBox
                if editBox then editBox:SetFocus() end
            end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                local text = self:GetText()
                if text and text:lower() == "accept" then
                    WarbandNexus:WipeAllData()
                    parent:Hide()
                else
                    WarbandNexus:Print("|cffff6600You must type 'Accept' to confirm.|r")
                end
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    
    StaticPopup_Show("WARBANDNEXUS_WIPE_CONFIRM")
end

--[[
    Initialize configuration
]]
function WarbandNexus:InitializeConfig()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")
    
    -- Store options on addon instance for custom UI access
    self.options = options
    
    -- Register main options
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    
    -- Add Profiles sub-category (register table now, add to Bliz options deferred)
    local profileOptions = AceDBOptions:GetOptionsTable(self.db)
    AceConfig:RegisterOptionsTable(ADDON_NAME .. "_Profiles", profileOptions)
    
    -- MIDNIGHT 12.0 TAINT FIX: AddToBlizOptions calls Settings.RegisterAddOnCategory()
    -- which is a protected Blizzard function. In Midnight 12.0, this triggers
    -- ADDON_ACTION_FORBIDDEN even from deferred/pcalled addon code.
    -- pcall does NOT suppress the event — it fires BEFORE Lua catches the error.
    --
    -- SOLUTION: Do NOT register with Blizzard's Settings panel at all.
    -- The addon has its own full custom settings UI accessible via:
    --   /wn → Settings tab, or minimap button → Settings
    -- Blizzard Settings integration is purely cosmetic/discovery and not worth the taint.
    --
    -- If Settings integration is ever needed again, it would require Blizzard to:
    --   a) make Settings.RegisterAddOnCategory() callable from addon code, or
    --   b) provide a non-protected registration API for addon categories.
    
    -- NOTE: ColorPickerFrame preview hook is now installed LAZILY on first color picker open
    -- (not during init) to prevent taint propagation. See InstallColorPickerPreviewHook()
    -- and ns.InstallColorPickerPreviewHook exposed for SettingsUI.
end

--[[
    [REMOVED] OpenOptions implemented in UI.lua (line 1081)
    This duplicate has been removed to prevent conflicts.
]]

--============================================================================
-- OVERFLOW WARNING SYSTEM (Removed - now handled in SettingsUI.lua)
--============================================================================
-- Real-time overflow detection is now integrated directly into the font scale slider
