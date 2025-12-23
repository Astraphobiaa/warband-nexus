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
        currentLanguageInfo = {
            order = 13,
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
            desc = "Hide the default WoW bank window and use Warband Nexus instead. You can still access the classic bank using the 'Classic Bank' button.\n\n|cffff9900Note:|r If you use third-party bank addons, this setting is automatically disabled to prevent conflicts.",
            width = 1.5,
            disabled = function()
                -- Disable if any conflicting bank addon is detected
                local conflicts = WarbandNexus:DetectBankAddonConflicts()
                return conflicts and #conflicts > 0
            end,
            get = function() return WarbandNexus.db.profile.replaceDefaultBank ~= false end,
            set = function(_, value) WarbandNexus.db.profile.replaceDefaultBank = value end,
        },
        bankAddonConflict = {
            order = 26,
            type = "description",
            name = function()
                local conflictingAddons = WarbandNexus:DetectBankAddonConflicts()
                if conflictingAddons and #conflictingAddons > 0 then
                    local conflictingAddon = conflictingAddons[1]  -- Show first conflict
                    return string.format(
                        "|cffff9900⚠ Bank Addon Conflict:|r\n\n" ..
                        "You have |cff00ccff%s|r installed, which conflicts with Warband Nexus's bank replacement feature.\n\n" ..
                        "|cffffffffTo use both addons together:|r\n" ..
                        "• Disable %s's bank module in its settings\n" ..
                        "• OR keep this setting OFF and use %s for your bank UI\n\n" ..
                        "|cff00ff00Note:|r Warband Nexus will still track and cache your items regardless of this setting!\n",
                        conflictingAddon, conflictingAddon, conflictingAddon
                    )
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
        autoOptimize = {
            order = 27,
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
        
        -- ===== THEME & APPEARANCE =====
        themeHeader = {
            order = 35,
            type = "header",
            name = "Theme & Appearance",
        },
        themeDesc = {
            order = 36,
            type = "description",
            name = "Choose your primary theme color. All variations (borders, tabs, highlights) will be automatically generated. Changes apply in real-time!\n",
        },
        themeMasterColor = {
            order = 37,
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
                -- This is called when user clicks OK in the color picker
                print(string.format("COLOR SET CALLBACK: R=%.2f, G=%.2f, B=%.2f", r, g, b))
                print(string.format("Before setting confirmed: %s", tostring(colorPickerConfirmed)))
                
                -- Mark as confirmed so OnHide doesn't restore
                colorPickerConfirmed = true
                
                print(string.format("After setting confirmed: %s", tostring(colorPickerConfirmed)))
                
                -- Clear backup immediately - user confirmed
                colorPickerOriginalColors = nil
                print("Backup cleared in set callback")
                
                -- Save the final color to database
                local finalColors = ns.UI_CalculateThemeColors(r, g, b)
                WarbandNexus.db.profile.themeColors = finalColors
                
                print("COLOR SAVED TO DB")
                
                -- Refresh UI with final colors
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                    print("COLOR REFRESH CALLED")
                end
            end,
        },
         themePresetPurple = {
            order = 38,
            type = "execute",
            name = "Purple Theme",
            desc = "Classic purple theme (default)",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 39,
            type = "execute",
            name = "Blue Theme",
            desc = "Cool blue theme",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 40,
            type = "execute",
            name = "Green Theme",
            desc = "Nature green theme",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 41,
            type = "execute",
            name = "Red Theme",
            desc = "Fiery red theme",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 42,
            type = "execute",
            name = "Orange Theme",
            desc = "Warm orange theme",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 43,
            type = "execute",
            name = "Cyan Theme",
            desc = "Bright cyan theme",
            width = 0.5,
            func = function()
                -- Show addon window to see the color change
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
            order = 44,
            type = "execute",
            name = "Reset to Default (Purple)",
            desc = "Reset all theme colors to their default purple theme.",
            width = "full",
            func = function()
                -- Show addon window to see the color change
                if WarbandNexus.ShowMainWindow then
                    WarbandNexus:ShowMainWindow()
                end
                
                -- Reset to defaults using calculation
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                -- Refresh colors
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                WarbandNexus:Print("Theme colors reset to default!")
            end,
        },
        
        -- ===== TAB FILTERING =====
        tabHeader = {
            order = 45,
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
        
        -- ===== CHARACTER MANAGEMENT =====
        characterManagementHeader = {
            order = 48,
            type = "header",
            name = "Character Management",
        },
        characterManagementDesc = {
            order = 49,
            type = "description",
            name = "Manage your tracked characters. You can delete character data that you no longer need.\n\n|cffff9900Warning:|r Deleting a character removes all saved data (gold, professions, PvE progress, etc.). This action cannot be undone.\n",
        },
        deleteCharacterDropdown = {
            order = 49.1,
            type = "select",
            name = "Select Character to Delete",
            desc = "Choose a character from the list to delete their data",
            width = "full",
            values = function()
                local chars = {}
                local allChars = WarbandNexus:GetAllCharacters()
                
                -- Get current player
                local currentPlayerName = UnitName("player")
                local currentPlayerRealm = GetRealmName()
                local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
                
                for _, char in ipairs(allChars) do
                    local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                    -- Don't allow deleting current character
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
            order = 49.2,
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
                        -- Refresh options panel (character list changed)
                        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                        AceConfigRegistry:NotifyChange("Warband Nexus")
                        -- Refresh UI if open
                        if WarbandNexus.RefreshUI then
                            WarbandNexus:RefreshUI()
                        end
                    else
                        WarbandNexus:Print("|cffff0000Failed to delete character. Character may not exist.|r")
                    end
                end
            end,
        },
        
        -- ===== NOTIFICATIONS =====
        notificationsHeader = {
            order = 50,
            type = "header",
            name = "Notifications",
        },
        notificationsDesc = {
            order = 51,
            type = "description",
            name = "Control in-game pop-up notifications and reminders.\n",
        },
        notificationsEnabled = {
            order = 52,
            type = "toggle",
            name = "Enable Notifications",
            desc = "Master toggle for all notification pop-ups.",
            width = 1.5,
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(_, value) WarbandNexus.db.profile.notifications.enabled = value end,
        },
        showUpdateNotes = {
            order = 53,
            type = "toggle",
            name = "Show Update Notes",
            desc = "Display a pop-up with changelog when addon is updated to a new version.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showUpdateNotes end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showUpdateNotes = value end,
        },
        showVaultReminder = {
            order = 54,
            type = "toggle",
            name = "Weekly Vault Reminder",
            desc = "Show a reminder when you have unclaimed Weekly Vault rewards on login.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        showLootNotifications = {
            order = 55,
            type = "toggle",
            name = "Mount/Pet/Toy Loot Alerts",
            desc = "Show a notification when a NEW mount, pet, or toy enters your bag. Triggers when item is looted/bought, not when learned. Only shows for uncollected items.",
            width = 1.5,
            disabled = function() return not WarbandNexus.db.profile.notifications.enabled end,
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(_, value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        resetVersionButton = {
            order = 56,
            type = "execute",
            name = "Show Update Notes Again",
            desc = "Reset the 'last seen version' to show the update notification again on next login.",
            width = 1.5,
            func = function()
                WarbandNexus.db.profile.notifications.lastSeenVersion = "0.0.0"
                WarbandNexus:Print("Update notification will show on next login.")
            end,
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

-- ===== COLOR PICKER REAL-TIME PREVIEW HOOK =====
local colorPickerOriginalColors = nil
local colorPickerHookInstalled = false
local colorPickerTicker = nil
local lastR, lastG, lastB = nil, nil, nil
local colorPickerConfirmed = false

-- Polling-based ColorPickerFrame hook for real-time preview
-- This approach works reliably with AceConfig which overrides ColorPickerFrame.func
local function InstallColorPickerPreviewHook()
    if colorPickerHookInstalled then return end
    colorPickerHookInstalled = true
    
    -- Monitor when ColorPickerFrame is shown
    ColorPickerFrame:HookScript("OnShow", function()
        print("COLOR PICKER OPENED")
        
        -- Reset confirmation flag
        colorPickerConfirmed = false
        
        -- Show addon window when color picker opens
        if WarbandNexus and WarbandNexus.ShowMainWindow then
            WarbandNexus:ShowMainWindow()
        end
        
        -- Backup original colors when picker opens
        local current = WarbandNexus.db.profile.themeColors
        colorPickerOriginalColors = {
            accent = {current.accent[1], current.accent[2], current.accent[3]},
            accentDark = {current.accentDark[1], current.accentDark[2], current.accentDark[3]},
            border = {current.border[1], current.border[2], current.border[3]},
            tabActive = {current.tabActive[1], current.tabActive[2], current.tabActive[3]},
            tabHover = {current.tabHover[1], current.tabHover[2], current.tabHover[3]},
        }
        
        print(string.format("BACKED UP COLORS: R=%.2f, G=%.2f, B=%.2f", current.accent[1], current.accent[2], current.accent[3]))
        
        -- Initialize last known RGB values
        lastR, lastG, lastB = ColorPickerFrame:GetColorRGB()
        
        -- Start polling ticker (20 times per second)
        if colorPickerTicker then
            colorPickerTicker:Cancel()
        end
        
        colorPickerTicker = C_Timer.NewTicker(0.05, function()
            if not ColorPickerFrame:IsShown() then
                -- Picker closed, ticker will be cancelled by OnHide
                return
            end
            
            local r, g, b = ColorPickerFrame:GetColorRGB()
            
            -- Check if color changed (with small tolerance for floating point comparison)
            local tolerance = 0.001
            if math.abs(r - (lastR or 0)) > tolerance or 
               math.abs(g - (lastG or 0)) > tolerance or 
               math.abs(b - (lastB or 0)) > tolerance then
                
                lastR, lastG, lastB = r, g, b
                
                print(string.format("COLOR PREVIEW: R=%.2f, G=%.2f, B=%.2f", r, g, b))
                
                -- Update preview (temporary, not saved to DB yet)
                local previewColors = ns.UI_CalculateThemeColors(r, g, b)
                WarbandNexus.db.profile.themeColors = previewColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            end
        end)
    end)
    
    -- Hook ColorPickerFrame buttons to detect confirmation/cancellation
    -- Try both old and new API structures
    local okayButton = ColorPickerFrame.Footer and ColorPickerFrame.Footer.OkayButton
                    or ColorPickerOkayButton  -- Fallback for older API
    local cancelButton = ColorPickerFrame.Footer and ColorPickerFrame.Footer.CancelButton
                      or ColorPickerCancelButton  -- Fallback for older API
    
    if okayButton then
        okayButton:HookScript("OnClick", function()
            print("OKAY BUTTON CLICKED - CONFIRMING COLOR")
            colorPickerConfirmed = true
        end)
    else
        print("WARNING: Could not find ColorPicker Okay button")
    end
    
    if cancelButton then
        cancelButton:HookScript("OnClick", function()
            print("CANCEL BUTTON CLICKED - REVERTING COLOR")
            colorPickerConfirmed = false
        end)
    end
    
    -- Monitor when ColorPickerFrame is hidden
    ColorPickerFrame:HookScript("OnHide", function()
        print("COLOR PICKER CLOSED")
        
        -- Stop polling ticker
        if colorPickerTicker then
            colorPickerTicker:Cancel()
            colorPickerTicker = nil
        end
        
        -- Delay to allow set callback to fire first
        C_Timer.After(0.05, function()
            print(string.format("ONHIDE CLEANUP: confirmed=%s, hasBackup=%s", tostring(colorPickerConfirmed), tostring(colorPickerOriginalColors ~= nil)))
            
            -- If not confirmed and backup exists, user cancelled
            if not colorPickerConfirmed and colorPickerOriginalColors then
                print("RESTORING ORIGINAL COLORS (USER CANCELLED)")
                WarbandNexus.db.profile.themeColors = colorPickerOriginalColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            elseif colorPickerConfirmed then
                print("COLOR CONFIRMED (OK BUTTON CLICKED)")
                -- Ensure the final color is saved (already saved by ticker, just confirm)
                colorPickerOriginalColors = nil
            end
            
            -- Clean up
            if not colorPickerConfirmed then
                -- Only clear backup if cancelled
                colorPickerOriginalColors = nil
            end
            colorPickerConfirmed = false
            lastR, lastG, lastB = nil, nil, nil
        end)
    end)
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
    -- Install color picker preview hook (once)
    InstallColorPickerPreviewHook()
    
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("Warband Nexus")
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end
