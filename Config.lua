--[[
    Warband Nexus - Configuration Module
    Modern and organized settings panel
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
        
        -- ===== GENERAL SETTINGS =====
        generalHeader = {
            order = 10,
            type = "header",
            name = "General Settings",
        },
        generalDesc = {
            order = 11,
            type = "description",
            name = "Basic addon settings and minimap button configuration.\n",
        },
        enabled = {
            order = 12,
            type = "toggle",
            name = "Enable Addon",
            desc = "Turn the addon on or off.",
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
            name = "Minimap Button",
            desc = "Show a button on the minimap to open Warband Nexus.",
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
        
        -- ===== BANK UI =====
        bankUIHeader = {
            order = 20,
            type = "header",
            name = "Bank UI",
        },
        bankUIDesc = {
            order = 21,
            type = "description",
            name = "Control whether Warband Nexus manages the bank interface.\n",
        },
        bankModuleEnabled = {
            order = 22,
            type = "toggle",
            name = "Enable Bank UI Features",
            desc = "Control whether Warband Nexus replaces the default bank UI. When disabled, you can use other bank addons without conflicts.\n\n|cff00ff00Data caching continues regardless of this setting.|r\n\n|cffff9900Requires /reload to take effect.|r",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.bankModuleEnabled ~= false end,
            set = function(_, value)
                local wasEnabled = WarbandNexus.db.profile.bankModuleEnabled
                WarbandNexus.db.profile.bankModuleEnabled = value
                
                if value and not wasEnabled then
                    -- User is re-enabling bank module
                    local toggledAddons = WarbandNexus.db.profile.toggledAddons or {}
                    local needsReload = false
                    
                    for addonName, previousState in pairs(toggledAddons) do
                        if previousState == "enabled" then
                            local success = WarbandNexus:DisableConflictingBankModule(addonName)
                            if success then
                                needsReload = true
                                WarbandNexus.db.profile.toggledAddons[addonName] = "disabled"
                            end
                        end
                    end
                    
                    WarbandNexus.db.profile.bankConflictChoices = {}
                    
                    if needsReload then
                        WarbandNexus:Print("|cff00ff00Bank UI enabled. Conflicting addons will be disabled.|r")
                        WarbandNexus:ShowReloadPopup()
                    else
                        WarbandNexus:Print("|cff00ff00Bank UI features enabled.|r Use /reload to apply changes.")
                    end
                elseif not value then
                    -- User is disabling bank module
                    local toggledAddons = WarbandNexus.db.profile.toggledAddons or {}
                    local needsReload = false
                    
                    for addonName, previousState in pairs(toggledAddons) do
                        if previousState == "disabled" then
                            local success = WarbandNexus:EnableConflictingBankModule(addonName)
                            if success then
                                needsReload = true
                                WarbandNexus.db.profile.toggledAddons[addonName] = "enabled"
                            end
                        end
                    end
                    
                    if needsReload then
                        WarbandNexus:Print("|cffffaa00Bank UI disabled. Previous addons will be re-enabled.|r")
                        WarbandNexus:ShowReloadPopup()
                    else
                        WarbandNexus:Print("|cffffaa00Bank UI features disabled.|r You can now use other bank addons. Use /reload to apply changes.")
                    end
                end
            end,
        },
        replaceDefaultBank = {
            order = 23,
            type = "toggle",
            name = "Replace Default Bank",
            desc = "Hide the default WoW bank window and use Warband Nexus instead. You can still access the classic bank using the 'Classic Bank' button.\n\n|cffff9900Note:|r If you use other bank addons, this setting is automatically disabled to prevent conflicts.",
            width = 1.5,
            disabled = function()
                local conflicts = WarbandNexus:DetectBankAddonConflicts()
                return conflicts and #conflicts > 0
            end,
            get = function() return WarbandNexus.db.profile.replaceDefaultBank ~= false end,
            set = function(_, value) WarbandNexus.db.profile.replaceDefaultBank = value end,
        },
        bankAddonConflict = {
            order = 24,
            type = "description",
            name = function()
                local conflictingAddons = WarbandNexus:DetectBankAddonConflicts()
                if conflictingAddons and #conflictingAddons > 0 then
                    return "|cffff9900Bank Addon Conflict:|r\n\n" ..
                           "A conflicting bank addon is detected, which conflicts with Warband Nexus's bank replacement feature.\n\n" ..
                           "|cffffffffTo use both addons together:|r\n" ..
                           "- Disable the other addon's bank module in its settings\n" ..
                           "- OR keep 'Enable Bank UI Features' OFF and use the other addon for your bank UI\n\n" ..
                           "|cff00ff00Note:|r Warband Nexus will still track and cache your items regardless of this setting!\n"
                else
                    return ""
                end
            end,
            fontSize = "medium",
            hidden = function()
                local conflictingAddons = WarbandNexus:DetectBankAddonConflicts()
                return not conflictingAddons or #conflictingAddons == 0
            end,
        },
        spacer1 = {
            order = 25,
            type = "description",
            name = "\n",
        },
        
        -- ===== AUTOMATION =====
        automationHeader = {
            order = 40,
            type = "header",
            name = "Automation",
        },
        automationDesc = {
            order = 41,
            type = "description",
            name = "Control what happens automatically when you open your Warband Bank.\n",
        },
        autoScan = {
            order = 42,
            type = "toggle",
            name = "Auto-Scan Items",
            desc = "Automatically scan and cache your Warband Bank items when you open the bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoScan end,
            set = function(_, value) WarbandNexus.db.profile.autoScan = value end,
        },
        autoOpenWindow = {
            order = 43,
            type = "toggle",
            name = "Auto-Open Window",
            desc = "Automatically open the Warband Nexus window when you open your Warband Bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoOpenWindow ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoOpenWindow = value end,
        },
        autoSaveChanges = {
            order = 44,
            type = "toggle",
            name = "Live Sync",
            desc = "Keep the item cache updated in real-time while the bank is open. This lets you see accurate data even when away from the bank.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.autoSaveChanges ~= false end,
            set = function(_, value) WarbandNexus.db.profile.autoSaveChanges = value end,
        },
        autoOptimize = {
            order = 45,
            type = "toggle",
            name = "Auto-Optimize Database",
            desc = "Automatically clean up stale data and optimize the database every 7 days.",
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
            name = "Display",
        },
        displayDesc = {
            order = 41,
            type = "description",
            name = "Customize how items and information are displayed.\n",
        },
        showItemLevel = {
            order = 42,
            type = "toggle",
            name = "Show Item Level",
            desc = "Display item level badges on equipment in the item list.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.showItemLevel end,
            set = function(_, value)
                WarbandNexus.db.profile.showItemLevel = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
        showItemCount = {
            order = 43,
            type = "toggle",
            name = "Show Item Count",
            desc = "Display stack count next to item names.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.showItemCount end,
            set = function(_, value)
                WarbandNexus.db.profile.showItemCount = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
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
            name = "Theme & Appearance",
        },
        themeDesc = {
            order = 51,
            type = "description",
            name = "Choose your primary theme color. All variations (borders, tabs, highlights) will be automatically generated. Changes apply in real-time!\n",
        },
        themeMasterColor = {
            order = 52,
            type = "color",
            name = "Master Theme Color",
            desc = "Choose your primary theme color. All variations (borders, tabs, highlights) will be automatically generated.",
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
            name = "Purple Theme",
            desc = "Classic purple theme (default)",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Purple theme applied!")
            end,
        },
        themePresetBlue = {
            order = 54,
            type = "execute",
            name = "Blue Theme",
            desc = "Cool blue theme",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Blue theme applied!")
            end,
        },
        themePresetGreen = {
            order = 55,
            type = "execute",
            name = "Green Theme",
            desc = "Nature green theme",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Green theme applied!")
            end,
        },
        themePresetRed = {
            order = 56,
            type = "execute",
            name = "Red Theme",
            desc = "Fiery red theme",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Red theme applied!")
            end,
        },
        themePresetOrange = {
            order = 57,
            type = "execute",
            name = "Orange Theme",
            desc = "Warm orange theme",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Orange theme applied!")
            end,
        },
        themePresetCyan = {
            order = 58,
            type = "execute",
            name = "Cyan Theme",
            desc = "Bright cyan theme",
            width = 0.5,
            func = function()
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.00, 0.80, 1.00)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                WarbandNexus:Print("Cyan theme applied!")
            end,
        },
        themeResetButton = {
            order = 59,
            type = "execute",
            name = "Reset to Default (Purple)",
            desc = "Reset all theme colors to their default purple theme.",
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
                WarbandNexus:Print("Theme colors reset to default!")
            end,
        },
        spacer5 = {
            order = 59.5,
            type = "description",
            name = "\n",
        },
        
        -- ===== TOOLTIP ENHANCEMENTS =====
        tooltipHeader = {
            order = 60,
            type = "header",
            name = "Tooltip Enhancements",
        },
        tooltipDesc = {
            order = 61,
            type = "description",
            name = "Add useful information to item tooltips.\n",
        },
        tooltipEnhancement = {
            order = 62,
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
            order = 63,
            type = "toggle",
            name = "Show Click Hint",
            desc = "Show 'Shift+Click to search' hint in tooltips.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.tooltipEnhancement end,
            get = function() return WarbandNexus.db.profile.tooltipClickHint end,
            set = function(_, value) WarbandNexus.db.profile.tooltipClickHint = value end,
        },
        spacer6 = {
            order = 69,
            type = "description",
            name = "\n",
        },
        
        -- ===== NOTIFICATIONS =====
        notificationsHeader = {
            order = 70,
            type = "header",
            name = "Notifications",
        },
        notificationsDesc = {
            order = 71,
            type = "description",
            name = "Control in-game pop-up notifications and reminders.\n",
        },
        notificationsEnabled = {
            order = 72,
            type = "toggle",
            name = "Enable Notifications",
            desc = "Master toggle for all notification pop-ups.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(_, value) WarbandNexus.db.profile.notifications.enabled = value end,
        },
        showUpdateNotes = {
            order = 73,
            type = "toggle",
            name = "Show Update Notes",
            desc = "Display a pop-up with changelog when addon is updated to a new version.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showUpdateNotes end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showUpdateNotes = value end,
        },
        showVaultReminder = {
            order = 74,
            type = "toggle",
            name = "Weekly Vault Reminder",
            desc = "Show a reminder when you have unclaimed Weekly Vault rewards on login.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        showLootNotifications = {
            order = 75,
            type = "toggle",
            name = "Mount/Pet/Toy Loot Alerts",
            desc = "Show a notification when a NEW mount, pet, or toy enters your bag. Triggers when item is looted/bought, not when learned. Only shows for uncollected items.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        resetVersionButton = {
            order = 76,
            type = "execute",
            name = "Show Update Notes Again",
            desc = "Reset the 'last seen version' to show the update notification again on next login.",
            width = 1.5,
            func = function()
                WarbandNexus.db.profile.notifications.lastSeenVersion = "0.0.0"
                WarbandNexus:Print("Update notification will show on next login.")
            end,
        },
        resetCompletedPlansButton = {
            order = 77,
            type = "execute",
            name = "Reset Completed Plans",
            desc = "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!",
            width = 1.5,
            confirm = true,
            confirmText = "Are you sure you want to remove ALL completed plans? This cannot be undone!",
            func = function()
                if WarbandNexus.ResetCompletedPlans then
                    local count = WarbandNexus:ResetCompletedPlans()
                    WarbandNexus:Print(string.format("Removed %d completed plan(s).", count))
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
        
        -- ===== CURRENCY =====
        currencyHeader = {
            order = 80,
            type = "header",
            name = "Currency",
        },
        currencyDesc = {
            order = 81,
            type = "description",
            name = "Configure how currencies are displayed in the Currency tab.\n",
        },
        currencyFilterMode = {
            order = 82,
            type = "select",
            name = "Filter Mode",
            desc = "Choose which currencies to display in the Currency tab.",
            width = 1.5,
            values = {
                filtered = "Important Only (Recommended)",
                nonfiltered = "Show All Currencies",
            },
            get = function() return WarbandNexus.db.profile.currencyFilterMode or "filtered" end,
            set = function(_, value)
                WarbandNexus.db.profile.currencyFilterMode = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
        currencyShowZero = {
            order = 83,
            type = "toggle",
            name = "Show Zero Quantities",
            desc = "Display currencies even if their quantity is 0.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.currencyShowZero end,
            set = function(_, value)
                WarbandNexus.db.profile.currencyShowZero = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
        spacer8 = {
            order = 89,
            type = "description",
            name = "\n",
        },
        
        -- ===== TAB FILTERING =====
        tabHeader = {
            order = 100,
            type = "header",
            name = "Tab Filtering",
        },
        tabDesc = {
            order = 101,
            type = "description",
            name = "Exclude specific Warband Bank tabs from scanning. Useful if you want to ignore certain tabs.\n",
        },
        ignoredTab1 = {
            order = 102,
            type = "toggle",
            name = "Ignore Tab 1",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[1] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[1] = value end,
        },
        ignoredTab2 = {
            order = 103,
            type = "toggle",
            name = "Ignore Tab 2",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[2] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[2] = value end,
        },
        ignoredTab3 = {
            order = 104,
            type = "toggle",
            name = "Ignore Tab 3",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[3] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[3] = value end,
        },
        ignoredTab4 = {
            order = 105,
            type = "toggle",
            name = "Ignore Tab 4",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return WarbandNexus.db.profile.ignoredTabs[4] end,
            set = function(_, value) WarbandNexus.db.profile.ignoredTabs[4] = value end,
        },
        ignoredTab5 = {
            order = 106,
            type = "toggle",
            name = "Ignore Tab 5",
            desc = "Exclude this Warband Bank tab from automatic scanning",
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
            name = "Character Management",
        },
        characterManagementDesc = {
            order = 111,
            type = "description",
            name = "Manage your tracked characters. You can delete character data that you no longer need.\n\n|cffff9900Warning:|r Deleting a character removes all saved data (gold, professions, PvE progress, etc.). This action cannot be undone.\n",
        },
        deleteCharacterDropdown = {
            order = 112,
            type = "select",
            name = "Select Character to Delete",
            desc = "Choose a character from the list to delete their data",
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
            name = "Delete Selected Character",
            desc = "Permanently delete the selected character's data",
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
        spacer10 = {
            order = 899,
            type = "description",
            name = "\n\n",
        },
        
        -- ===== ADVANCED =====
        advancedHeader = {
            order = 900,
            type = "header",
            name = "Advanced",
        },
        advancedDesc = {
            order = 901,
            type = "description",
            name = "Advanced settings and database management. Use with caution!\n",
        },
        debugMode = {
            order = 902,
            type = "toggle",
            name = "Debug Mode",
            desc = "Enable verbose logging for debugging purposes. Only enable if troubleshooting issues.",
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
        databaseStatsButton = {
            order = 903,
            type = "execute",
            name = "Show Database Statistics",
            desc = "Display detailed information about your database size and content.",
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
            name = "Optimize Database Now",
            desc = "Manually run database optimization to clean up stale data and reduce file size.",
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
            order = 949,
            type = "description",
            name = "\n",
        },
        
        -- ===== SLASH COMMANDS =====
        commandsHeader = {
            order = 950,
            type = "header",
            name = "Slash Commands",
        },
        commandsDesc = {
            order = 951,
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

-- ===== COLOR PICKER REAL-TIME PREVIEW HOOK =====
local colorPickerOriginalColors = nil
local colorPickerHookInstalled = false
local colorPickerTicker = nil
local lastR, lastG, lastB = nil, nil, nil
local colorPickerConfirmed = false

local function InstallColorPickerPreviewHook()
    if colorPickerHookInstalled then return end
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

--[[
    Show Wipe Data Confirmation Popup
]]
function WarbandNexus:ShowWipeDataConfirmation()
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
            local text = self.editBox:GetText()
            if text and text:lower() == "accept" then
                WarbandNexus:WipeAllData()
            else
                WarbandNexus:Print("|cffff6600You must type 'Accept' to confirm.|r")
            end
        end,
        OnShow = function(self)
            self.editBox:SetFocus()
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
    
    StaticPopup_Show("WARBANDNEXUS_WIPE_CONFIRM")
end

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
    InstallColorPickerPreviewHook()
    
    -- TWW (11.0+): Use modern Settings API
    if Settings and Settings.OpenToCategory then
        -- Try opening by category name (string is acceptable in TWW)
        Settings.OpenToCategory("Warband Nexus")
    -- Legacy: Use InterfaceOptionsFrame
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) -- Double call sometimes needed
    end
end
