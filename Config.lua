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
            hidden = true,  -- Hidden from Config, functionality preserved
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
            name = "Show Items in Tooltips",
            desc = "Display Warband and Character item counts in tooltips (WN Search).",
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
            name = "Module Management",
        },
        moduleManagementDesc = {
            order = 21,
            type = "description",
            name = "Enable or disable specific data collection modules. Disabling a module will stop its data updates and hide its tab from the UI.\n",
        },
        moduleCurrencies = {
            order = 22,
            type = "toggle",
            name = "Currencies Module",
            desc = "Track account-wide and character-specific currencies (Gold, Honor, Conquest, etc.)",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.currencies ~= false end,
            set = CreateModuleToggleHandler("currencies"),
        },
        moduleReputations = {
            order = 23,
            type = "toggle",
            name = "Reputations Module",
            desc = "Track reputation progress with factions, renown levels, and paragon rewards",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.reputations ~= false end,
            set = CreateModuleToggleHandler("reputations"),
        },
        moduleItems = {
            order = 24,
            type = "toggle",
            name = "Items Module",
            desc = "Track Warband Bank items, search functionality, and item categories",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.items ~= false end,
            set = CreateModuleToggleHandler("items"),
        },
        moduleStorage = {
            order = 25,
            type = "toggle",
            name = "Storage Module",
            desc = "Track character bags, personal bank, and Warband Bank storage",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.storage ~= false end,
            set = CreateModuleToggleHandler("storage"),
        },
        modulePvE = {
            order = 26,
            type = "toggle",
            name = "PvE Module",
            desc = "Track Mythic+ dungeons, raid progress, and Weekly Vault rewards",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.pve ~= false end,
            set = CreateModuleToggleHandler("pve"),
        },
        modulePlans = {
            order = 27,
            type = "toggle",
            name = "Plans Module",
            desc = "Track personal goals for mounts, pets, toys, achievements, and custom tasks",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.modulesEnabled.plans ~= false end,
            set = CreateModuleToggleHandler("plans"),
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
            name = "Automation",
        },
        automationDesc = {
            order = 41,
            type = "description",
            name = "Control what happens automatically when you open your Warband Bank.\n",
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
            hidden = true,  -- Hidden from Config.lua (always enabled, managed via Core.lua)
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
        showReputationGains = {
            order = 76,
            type = "toggle",
            name = "Show Reputation Gains",
            desc = "Show chat messages when you gain reputation with factions. When enabled, default Blizzard reputation messages are hidden.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showReputationGains end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.showReputationGains = value
                -- Update chat filter (suppress/restore Blizzard messages)
                if WarbandNexus.UpdateChatFilter then
                    local repEnabled = value
                    local currEnabled = WarbandNexus.db.profile.notifications.showCurrencyGains
                    WarbandNexus:UpdateChatFilter(repEnabled, currEnabled)
                end
            end,
        },
        showCurrencyGains = {
            order = 76.5,
            type = "toggle",
            name = "Show Currency Gains",
            desc = "Show chat messages when you gain currencies. When enabled, default Blizzard currency messages are hidden.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showCurrencyGains end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.showCurrencyGains = value
                -- Update chat filter (suppress/restore Blizzard messages)
                if WarbandNexus.UpdateChatFilter then
                    local repEnabled = WarbandNexus.db.profile.notifications.showReputationGains
                    local currEnabled = value
                    WarbandNexus:UpdateChatFilter(repEnabled, currEnabled)
                end
            end,
        },
        resetVersionButton = {
            order = 77,
            type = "execute",
            hidden = true,  -- Removed from Config.lua
            name = "Show Update Notes Again",
            desc = "Reset the 'last seen version' to show the update notification again on next login.",
            width = 1.5,
            func = function()
                WarbandNexus.db.profile.notifications.lastSeenVersion = "0.0.0"
                WarbandNexus:Print("Update notification will show on next login.")
            end,
        },
        resetCompletedPlansButton = {
            order = 78,
            type = "execute",
            hidden = true,  -- Moved to PlansUI.lua
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
            hidden = true,  -- Moved to CharactersUI.lua
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
            hidden = true,  -- Moved to CharactersUI.lua
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
        spacerFont = {
            order = 119,
            type = "description",
            name = "\n",
        },
        
        -- ===== FONT & SCALING =====
        fontHeader = {
            order = 120,
            type = "header",
            name = "Font & Scaling",
        },
        fontDesc = {
            order = 121,
            type = "description",
            name = "Customize font appearance and scaling. Applies to all UI elements.\n",
        },
        fontFace = {
            order = 122,
            type = "select",
            name = "Font Family",
            desc = "Choose the font used throughout the addon UI",
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
            name = "Font Scale",
            desc = "Adjust font size across all UI elements. Overflow warnings will appear if text doesn't fit.",
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
            name = "Anti-Aliasing",
            desc = "Font edge rendering style (affects readability)",
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
            name = "Resolution Normalization",
            desc = "Adjust font sizes based on screen resolution and UI scale for consistent physical size across different displays",
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
            hidden = true,  -- Removed from Config.lua
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
            hidden = true,  -- Removed from Config.lua (auto-optimized)
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
