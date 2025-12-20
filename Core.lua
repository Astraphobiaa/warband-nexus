--[[
    Warband Nexus - Core Module
    Main addon initialization and control logic
    
    A modern and functional Warband management system for World of Warcraft
]]

local ADDON_NAME, ns = ...

---@class WarbandNexus : AceAddon, AceEvent-3.0, AceConsole-3.0, AceHook-3.0, AceTimer-3.0, AceBucket-3.0
local WarbandNexus = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceEvent-3.0",
    "AceConsole-3.0",
    "AceHook-3.0",
    "AceTimer-3.0",
    "AceBucket-3.0"
)

-- Store in namespace for module access
ns.WarbandNexus = WarbandNexus

-- Localization
-- Note: Language override is applied in OnInitialize (after DB loads)
-- At this point, we use default game locale
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.L = L

-- Constants
local WARBAND_TAB_COUNT = 5

-- Warband Bank Bag IDs (13-17, NOT 12!)
local WARBAND_BAGS = {
    Enum.BagIndex.AccountBankTab_1 or 13,
    Enum.BagIndex.AccountBankTab_2 or 14,
    Enum.BagIndex.AccountBankTab_3 or 15,
    Enum.BagIndex.AccountBankTab_4 or 16,
    Enum.BagIndex.AccountBankTab_5 or 17,
}

-- Personal Bank Bag IDs
-- Note: NUM_BANKBAGSLOTS is typically 7, plus the main bank slot
local PERSONAL_BANK_BAGS = {}

-- Main bank container (BANK = -1 in most clients)
if Enum.BagIndex.Bank then
    table.insert(PERSONAL_BANK_BAGS, Enum.BagIndex.Bank)
end

-- Bank bag slots (6-11 in TWW, bag 12 is Warband now!)
for i = 1, NUM_BANKBAGSLOTS or 7 do
    local bagEnum = Enum.BagIndex["BankBag_" .. i]
    if bagEnum then
        -- Skip bag 12 - it's now Warband's first tab in TWW!
        if bagEnum ~= 12 and bagEnum ~= Enum.BagIndex.AccountBankTab_1 then
        table.insert(PERSONAL_BANK_BAGS, bagEnum)
        end
    end
end

-- Fallback: if enums didn't work, use numeric IDs (6-11, NOT 12!)
if #PERSONAL_BANK_BAGS == 0 then
    PERSONAL_BANK_BAGS = { -1, 6, 7, 8, 9, 10, 11 }
end

-- Item Categories for grouping
local ITEM_CATEGORIES = {
    WEAPON = 1,
    ARMOR = 2,
    CONSUMABLE = 3,
    TRADEGOODS = 4,  -- Materials
    RECIPE = 5,
    GEM = 6,
    MISCELLANEOUS = 7,
    QUEST = 8,
    CONTAINER = 9,
    OTHER = 10,
}

-- Export to namespace
ns.WARBAND_BAGS = WARBAND_BAGS
ns.PERSONAL_BANK_BAGS = PERSONAL_BANK_BAGS
ns.WARBAND_TAB_COUNT = WARBAND_TAB_COUNT
ns.ITEM_CATEGORIES = ITEM_CATEGORIES

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date
local time = time

--[[
    Database Defaults
    Profile-based structure for per-character settings
    Global structure for cross-character data (Warband cache)
]]
local defaults = {
    profile = {
        enabled = true,
        minimap = {
            hide = false,
            minimapPos = 220,
            lock = false,
        },
        
        -- Bank addon conflict resolution (per-addon choices)
        bankConflictChoices = {},
        
        -- Behavior settings
        autoScan = true,           -- Auto-scan when bank opens
        autoOpenWindow = true,     -- Auto-open addon window when bank opens
        autoSaveChanges = true,    -- Live sync while bank is open
        replaceDefaultBank = true, -- Replace default bank UI with addon
        debugMode = false,         -- Debug logging (verbose)
        
        -- Display settings
        showItemLevel = true,
        showItemCount = true,
        
        -- Gold settings
        goldReserve = 0,           -- Minimum gold to keep when depositing
        
        -- Tab filtering (true = ignored)
        ignoredTabs = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false,
            [5] = false,
        },
        
        -- Storage tab expanded state
        storageExpanded = {
            warband = true,  -- Warband Bank expanded by default
            personal = false,  -- Personal collapsed by default
            categories = {},  -- {["warband_TradeGoods"] = true, ["personal_CharName_TradeGoods"] = false}
        },
        
        -- Character list sorting preferences
        characterSort = {
            key = nil,        -- nil = no sorting (default order), "name", "level", "gold", "lastSeen"
            ascending = true, -- true = ascending, false = descending
        },
        
        -- PvE list sorting preferences
        pveSort = {
            key = nil,        -- nil = no sorting (default order)
            ascending = true,
        },
        
        -- Notification settings
        notifications = {
            enabled = true,                    -- Master toggle
            showUpdateNotes = true,            -- Show changelog on new version
            showVaultReminder = true,          -- Show vault reminder
            showLootNotifications = true,      -- Show mount/pet/toy loot notifications
            lastSeenVersion = "0.0.0",         -- Last addon version seen
            lastVaultCheck = 0,                -- Last time vault was checked
            dismissedNotifications = {},       -- Array of dismissed notification IDs
        },
    },
    global = {
        -- Warband bank cache (SHARED across all characters)
        warbandBank = {
            items = {},            -- { [bagID] = { [slotID] = itemData } }
            gold = 0,              -- Warband bank gold
            lastScan = 0,          -- Last scan timestamp
        },
        
        -- All tracked characters
        -- Key: "CharacterName-RealmName"
        characters = {},
        
        -- Favorite characters (always shown at top)
        -- Array of "CharacterName-RealmName" keys
        favoriteCharacters = {},
        
        -- Window size persistence
        window = {
            width = 700,
            height = 550,
        },
    },
    char = {
        -- Personal bank cache (per-character)
        personalBank = {
            items = {},
            lastScan = 0,
        },
        lastKnownGold = 0,
    },
}

--[[
    Initialize the addon
    Called when the addon is first loaded
]]
function WarbandNexus:OnInitialize()
    -- Initialize database with defaults
    self.db = LibStub("AceDB-3.0"):New("WarbandNexusDB", defaults, true)
    
    -- Register database callbacks for profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    -- Initialize configuration (defined in Config.lua)
    self:InitializeConfig()
    
    -- Setup slash commands
    self:RegisterChatCommand("wn", "SlashCommand")
    self:RegisterChatCommand("warbandnexus", "SlashCommand")
    
    -- Initialize minimap button (LibDBIcon)
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.InitializeMinimapButton then
            WarbandNexus:InitializeMinimapButton()
        end
    end)
    
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function WarbandNexus:OnEnable()
    if not self.db.profile.enabled then
        return
    end
    
    -- Initialize conflict queue and guards
    self._conflictQueue = {}
    self._isProcessingConflict = false
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- Register events
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnPlayerLevelUp")
    
    -- PvE tracking events are now managed by EventManager (throttled versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Collection tracking events are now managed by EventManager (debounced versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Setup BankFrame suppress hook
    -- This prevents BankFrame from showing when bank is opened
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.SetupBankFrameHook then
            WarbandNexus:SetupBankFrameHook()
        end
    end)
    
    -- Hook container clicks to ensure UI refreshes on item move
    -- Note: ContainerFrameItemButton_OnModifiedClick was removed in TWW (11.0+)
    -- We now rely on BAG_UPDATE_DELAYED event for UI updates
    if not self.containerHooked then
        self.containerHooked = true
    end
    
    -- Initialize advanced modules
    -- API Wrapper: Initialize first (other modules may use it)
    if self.InitializeAPIWrapper then
        self:InitializeAPIWrapper()
    end
    
    -- Cache Manager: Smart caching for performance
    if self.WarmupCaches then
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.WarmupCaches then
                WarbandNexus:WarmupCaches()
            end
        end)
    end
    
    -- Event Manager: Throttled/debounced event handling
    if self.InitializeEventManager then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeEventManager then
                WarbandNexus:InitializeEventManager()
            end
        end)
    end
    
    -- Tooltip Enhancer: Add item locations to tooltips
    if self.InitializeTooltipEnhancer then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeTooltipEnhancer then
                WarbandNexus:InitializeTooltipEnhancer()
            end
        end)
    end
    
    -- Tooltip Click Handler: Shift+Click to search
    if self.InitializeTooltipClickHandler then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeTooltipClickHandler then
                WarbandNexus:InitializeTooltipClickHandler()
            end
        end)
    end
    
    -- Error Handler: Wrap critical functions for production safety
    -- NOTE: This must run AFTER all other modules are loaded
    if self.InitializeErrorHandler then
        C_Timer.After(1.5, function()
            if WarbandNexus and WarbandNexus.InitializeErrorHandler then
                WarbandNexus:InitializeErrorHandler()
            end
        end)
    end
    
    -- Database Optimizer: Auto-cleanup and optimization
    if self.InitializeDatabaseOptimizer then
        C_Timer.After(5, function()
            if WarbandNexus and WarbandNexus.InitializeDatabaseOptimizer then
                WarbandNexus:InitializeDatabaseOptimizer()
            end
        end)
    end

    -- Collection Tracking: Mount/Pet/Toy detection
    -- CollectionManager handles bag scanning and event registration
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.InitializeCollectionTracking then
            WarbandNexus:InitializeCollectionTracking()
        else
            WarbandNexus:Print("|cffff0000ERROR: InitializeCollectionTracking not found!|r")
        end
    end)

    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
end

--[[
    Save character data - called once per login
]]
function WarbandNexus:SaveCharacter()
    -- Prevent duplicate saves
    if self.characterSaved then
        return
    end
    
    local success, err = pcall(function()
        self:SaveCurrentCharacterData()
    end)
    
    if success then
        self.characterSaved = true
    else
        self:Print("Error saving character: " .. tostring(err))
    end
end


--[[
    Disable the addon
    Called when the addon becomes disabled
]]
function WarbandNexus:OnDisable()
    -- Unregister all events
    self:UnregisterAllEvents()
    self:UnregisterAllBuckets()
end

--[[
    Handle profile changes
    Refresh settings when profile is changed/copied/reset
]]
function WarbandNexus:OnProfileChanged()
    -- Refresh UI elements if they exist
    if self.RefreshUI then
        self:RefreshUI()
    end
    
end

--[[
    Slash command handler
    @param input string The command input
]]
function WarbandNexus:SlashCommand(input)
    local cmd = self:GetArgs(input, 1)
    
    if not cmd or cmd == "" or cmd == "help" then
        self:Print(L["SLASH_HELP"])
        self:Print("  |cff00ccff/wn show|r - " .. L["SLASH_SHOW"])
        self:Print("  |cff00ccff/wn options|r - " .. L["SLASH_OPTIONS"])
        self:Print("  |cff00ccff/wn cleanup|r - Remove inactive characters (90+ days)")
        self:Print("  |cff00ccff/wn clearcache|r - Clear all caches (force refresh)")
        return
    end
    
    -- Debug commands menu (hidden, accessible only by typing /wn debug)
    if cmd == "debug" then
        -- Toggle debug mode
        self.db.profile.debugMode = not self.db.profile.debugMode
        if self.db.profile.debugMode then
            self:Print("|cff00ff00Debug mode ENABLED|r")
            self:Print(" ")
            self:Print("|cffffaa00=== Debug/Advanced Commands ===|r")
            self:Print("  /wn scan - Manual bank scan")
            self:Print("  /wn storage - Open Storage tab")
            self:Print("  /wn chars - List tracked characters")
            self:Print("  /wn pve - Open PvE tab")
            self:Print("  /wn pvedata - Print PvE data")
            self:Print("  /wn cache - Cache statistics")
            self:Print("  /wn events - Event statistics")
            self:Print("  /wn minimap - Toggle minimap button")
            self:Print("  /wn bankcheck - Check bank conflicts")
            self:Print("  /wn bankreset - Reset bank choices")
            self:Print("  /wn vaultcheck - Test vault notifications")
            self:Print("  /wn testloot - Test loot notifications")
            self:Print("  /wn errors - Show error log")
            self:Print("  /wn recover - Emergency recovery")
            self:Print("  /wn dbstats - Database stats")
            self:Print("  /wn optimize - Optimize database")
            self:Print("|cffffaa00================================|r")
        else
            self:Print("|cffff9900Debug mode DISABLED|r")
        end
        return
    end
    
    if cmd == "options" or cmd == "config" or cmd == "settings" then
        self:OpenOptions()
    elseif cmd == "scan" then
        self:ScanWarbandBank()
    elseif cmd == "show" or cmd == "toggle" then
        self:ToggleMainWindow()
    elseif cmd == "chars" or cmd == "characters" then
        self:PrintCharacterList()
    elseif cmd == "storage" or cmd == "browse" then
        -- Show Storage tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "storage"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pve" then
        -- Show PvE tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "pve"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pvedata" or cmd == "pveinfo" then
        -- Print current character's PvE data
        self:PrintPvEData()
    elseif cmd == "enumcheck" then
        -- Debug: Check Enum values
        self:Print("=== Enum.WeeklyRewardChestThresholdType Values ===")
        if Enum and Enum.WeeklyRewardChestThresholdType then
            self:Print("  Raid: " .. tostring(Enum.WeeklyRewardChestThresholdType.Raid))
            self:Print("  Activities (M+): " .. tostring(Enum.WeeklyRewardChestThresholdType.Activities))
            self:Print("  RankedPvP: " .. tostring(Enum.WeeklyRewardChestThresholdType.RankedPvP))
            self:Print("  World: " .. tostring(Enum.WeeklyRewardChestThresholdType.World))
        else
            self:Print("  Enum.WeeklyRewardChestThresholdType not available")
        end
        self:Print("=============================================")
        -- Also collect and show current vault activities
        if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities and #activities > 0 then
                self:Print("Current Vault Activities:")
                for i, activity in ipairs(activities) do
                    self:Print(string.format("  [%d] type=%s, index=%s, progress=%s/%s", 
                        i, tostring(activity.type), tostring(activity.index),
                        tostring(activity.progress), tostring(activity.threshold)))
                end
            else
                self:Print("No current vault activities")
            end
        end
    elseif cmd == "dumpbank" then
        -- Debug command to dump BankFrame structure
        if self.DumpBankFrameInfo then
            self:DumpBankFrameInfo()
        else
            self:Print("DumpBankFrameInfo not available")
        end
    elseif cmd == "cache" or cmd == "cachestats" then
        if self.PrintCacheStats then
            self:PrintCacheStats()
        else
            self:Print("CacheManager not loaded")
        end
    elseif cmd == "events" or cmd == "eventstats" then
        if self.PrintEventStats then
            self:PrintEventStats()
        else
            self:Print("EventManager not loaded")
        end
    elseif cmd == "clearcache" then
        if self.ClearAllCaches then
            self:ClearAllCaches()
            self:Print("All caches cleared!")
        end
    elseif cmd == "cleanup" then
        if self.CleanupStaleCharacters then
            local removed = self:CleanupStaleCharacters(90)
            if removed == 0 then
                self:Print("No stale characters found (90+ days inactive)")
            end
        end
    elseif cmd == "resetprof" then
        if self.ResetProfessionData then
            self:ResetProfessionData()
            self:Print("Profession data reset.")
        else
            -- Manual fallback
            local name = UnitName("player")
            local realm = GetRealmName()
            local key = name .. "-" .. realm
            if self.db.global.characters and self.db.global.characters[key] then
                self.db.global.characters[key].professions = nil
                self:Print("Professions reset for " .. key)
                if self.InvalidateCharacterCache then self:InvalidateCharacterCache() end
                if self.RefreshUI then self:RefreshUI() end
            end
        end
    elseif cmd == "minimap" then
        if self.ToggleMinimapButton then
            self:ToggleMinimapButton()
        else
            self:Print("Minimap button module not loaded")
        end
    
    elseif cmd == "bankcheck" then
        -- Check for bank addon conflicts
        local conflicts = self:DetectBankAddonConflicts()
        
        self:Print("=== Bank Conflict Status ===")
        
        if conflicts and #conflicts > 0 then
            self:Print("Conflicting addons detected:")
            for _, addonName in ipairs(conflicts) do
                local choice = self.db.profile.bankConflictChoices[addonName]
                if choice == "useWarband" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff00ff00Using Warband Nexus|r", addonName))
                elseif choice == "useOther" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff888888Using %s|r", addonName, addonName))
                else
                    self:Print(string.format("  |cff00ccff%s|r: |cffff9900Not resolved yet|r", addonName))
                end
            end
            self:Print("")
            self:Print("To reset: Type |cff00ccff/wn bankreset|r")
        else
            self:Print("|cff00ff00✓ No conflicts detected|r")
            self:Print("Warband Nexus is managing your bank UI!")
        end
        
        self:Print("==========================")
    
    elseif cmd == "bankreset" then
        -- Reset ALL bank conflict choices
        self.db.profile.bankConflictChoices = {}
        self:ClearConflictCache()
        self:Print("|cff00ff00All bank conflict choices reset!|r")
        self:Print("Type |cff00ccff/reload|r to see conflict popups again.")
    
    elseif cmd == "vaultcheck" or cmd == "testvault" then
        -- Test vault notification system
        if self.TestVaultCheck then
            self:TestVaultCheck()
        else
            self:Print("Vault check module not loaded")
        end
    
    elseif cmd == "testloot" then
        -- Test loot notification system
        -- Parse the type argument (mount/pet/toy or nil for all)
        local typeArg = input:match("^testloot%s+(%w+)") -- Extract word after "testloot "
        self:Print("|cff888888[DEBUG] testloot command: typeArg = " .. tostring(typeArg) .. "|r")
        if self.TestLootNotification then
            self:TestLootNotification(typeArg)
        else
            self:Print("|cffff0000Loot notification module not loaded!|r")
            self:Print("|cffff6600Attempting to initialize...|r")
            if self.InitializeLootNotifications then
                self:InitializeLootNotifications()
                self:Print("|cff00ff00Manual initialization complete. Try /wn testloot again.|r")
            else
                self:Print("|cffff0000InitializeLootNotifications function not found!|r")
            end
        end
    
    elseif cmd == "initloot" then
        -- Debug: Force initialize loot notifications
        self:Print("|cff00ccff[DEBUG] Forcing InitializeLootNotifications...|r")
        if self.InitializeLootNotifications then
            self:InitializeLootNotifications()
        else
            self:Print("|cffff0000ERROR: InitializeLootNotifications not found!|r")
        end

    -- Hidden/Debug commands
    elseif cmd == "errors" then
        local subCmd = self:GetArgs(input, 2, 1)
        if subCmd == "full" or subCmd == "all" then
            self:PrintRecentErrors(20)
        elseif subCmd == "clear" then
            if self.ClearErrorLog then
                self:ClearErrorLog()
            end
        elseif subCmd == "stats" then
            if self.PrintErrorStats then
                self:PrintErrorStats()
            end
        elseif subCmd == "export" then
            if self.ExportErrorLog then
                local log = self:ExportErrorLog()
                self:Print("Error log copied to clipboard (if supported)")
                -- Note: Actual clipboard copy would need additional library
                print(log)
            end
        elseif tonumber(subCmd) then
            if self.ShowErrorDetails then
                self:ShowErrorDetails(tonumber(subCmd))
            end
        else
            if self.PrintRecentErrors then
                self:PrintRecentErrors(5)
            end
        end
    elseif cmd == "recover" or cmd == "emergency" then
        if self.EmergencyRecovery then
            self:EmergencyRecovery()
        end
    elseif cmd == "dbstats" or cmd == "dbinfo" then
        if self.PrintDatabaseStats then
            self:PrintDatabaseStats()
        end
    elseif cmd == "optimize" or cmd == "dboptimize" then
        if self.RunOptimization then
            self:RunOptimization()
        end
    elseif cmd == "apireport" or cmd == "apicompat" then
        if self.PrintAPIReport then
            self:PrintAPIReport()
        end
    else
        self:Print("Unknown command: " .. cmd)
    end
end

--[[
    Print list of tracked characters
]]
function WarbandNexus:PrintCharacterList()
    self:Print("=== Tracked Characters ===")
    
    local chars = self:GetAllCharacters()
    if #chars == 0 then
        self:Print("No characters tracked yet.")
        return
    end
    
    for _, char in ipairs(chars) do
        local lastSeenText = ""
        if char.lastSeen then
            local diff = time() - char.lastSeen
            if diff < 60 then
                lastSeenText = "now"
            elseif diff < 3600 then
                lastSeenText = math.floor(diff / 60) .. "m ago"
            elseif diff < 86400 then
                lastSeenText = math.floor(diff / 3600) .. "h ago"
            else
                lastSeenText = math.floor(diff / 86400) .. "d ago"
            end
        end
        
        self:Print(string.format("  %s (%s Lv%d) - %s",
            char.name or "?",
            char.classFile or "?",
            char.level or 0,
            lastSeenText
        ))
    end
    
    self:Print("Total: " .. #chars .. " characters")
    self:Print("==========================")
end

-- InitializeDataBroker() moved to Modules/MinimapButton.lua (now InitializeMinimapButton)

--[[
    Event Handlers
]]

function WarbandNexus:OnBankOpened()
    self.bankIsOpen = true
    
    -- Check if ANY conflict addon was chosen as "useOther" (background mode)
    local useOtherAddon = self:IsUsingOtherBankAddon()
    
    if not useOtherAddon then
        -- Normal mode: WarbandNexus manages bank UI
        -- Read which tab Blizzard selected when bank opened
        local blizzardSelectedTab = nil
        if BankFrame then
            blizzardSelectedTab = BankFrame.selectedTab or BankFrame.activeTabIndex
            if not blizzardSelectedTab and BankFrame.TabSystem then
                blizzardSelectedTab = BankFrame.TabSystem.selectedTab
            end
        end
        
        local warbandTabID = BankFrame and BankFrame.accountBankTabID or 2
        
        -- Determine bank type: Default to Personal Bank unless Warband tab is selected
        if blizzardSelectedTab == warbandTabID then
            self.currentBankType = "warband"
        else
            self.currentBankType = "personal"
        end
        
        -- Open player bags (only in normal mode)
        if OpenAllBags then
            OpenAllBags()
        end
    end
    
    -- PERFORMANCE: Batch scan operations
    if self.db.profile.autoScan then
        if self.ScanPersonalBank then
            self:ScanPersonalBank()
        end
    end
    
    -- PERFORMANCE: Single delayed callback instead of nested timers
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end
        
        -- Check Warband bank accessibility
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        
        if numSlots and numSlots > 0 then
            WarbandNexus.warbandBankIsOpen = true
            
            -- Scan warband bank
            if WarbandNexus.db.profile.autoScan and WarbandNexus.ScanWarbandBank then
                WarbandNexus:ScanWarbandBank()
            end
        end
        
        -- Auto-open window ONLY if using WarbandNexus mode
        local useOther = WarbandNexus:IsUsingOtherBankAddon()
        if not useOther and WarbandNexus.db.profile.autoOpenWindow ~= false then
            if WarbandNexus and WarbandNexus.ShowMainWindowWithItems then
                WarbandNexus:ShowMainWindowWithItems(WarbandNexus.currentBankType)
            end
        end
    end)
end

-- Note: We no longer use UnregisterAllEvents because it triggers BANKFRAME_CLOSED
-- Instead we just hide and move the frame off-screen

--[[
    Detect conflicting bank addons (CACHED)
    @return string|nil - Name of conflicting addon, or nil if none detected
]]
function WarbandNexus:DetectBankAddonConflicts()
    -- Wrap in pcall to prevent errors from breaking the addon
    local success, conflicts = pcall(function()
        local found = {}
        
        -- TWW (11.0+) uses C_AddOns.IsAddOnLoaded(), older versions use IsAddOnLoaded()
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        
        -- Check for popular bank/inventory management addons
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        
        -- List of known conflicting addons
        local conflictingAddons = {
            "BankUI", "InventoryManager", "BagAddon", "BankModifier",
            "CustomBank", "AdvancedInventory", "BagSystem"
        }
        
        for _, addonName in ipairs(conflictingAddons) do
            if IsLoaded(addonName) then
                table.insert(found, addonName)
            end
        end
        
        return found
    end)
    
    if success then
        return conflicts
    else
        return {}
    end
end

--[[
    Helper: Check if any conflict addon is set to "useOther"
    Safe wrapper to prevent nil table errors
]]
function WarbandNexus:IsUsingOtherBankAddon()
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return false
    end
    
    for addonName, choice in pairs(self.db.profile.bankConflictChoices) do
        if choice == "useOther" then
            return true
        end
    end
    
    return false
end

--[[
    Clear conflict cache (call this after disabling an addon)
]]
function WarbandNexus:ClearConflictCache()
    self._conflictCheckCache = nil
end

--[[
    Disable conflicting addon's bank module
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function WarbandNexus:DisableConflictingBankModule(addonName)
    -- Generic addon disable logic
    local DisableAddon = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
    
    if addonName and addonName ~= "" then
        DisableAddon(addonName)
        return true, string.format("%s disabled. Please /reload to apply changes.", addonName)
    end
    
    return false, "Unknown addon. Please disable manually."
end

--[[
    Enable conflicting addon's bank module (when user chooses to use it)
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function WarbandNexus:EnableConflictingBankModule(addonName)
    if not addonName then
        return false, "No addon name provided"
    end
    
    local EnableAddon = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn
    
    EnableAddon(addonName)
    return true, string.format("%s enabled. Please /reload to apply changes.", addonName)
end

--[[
    Show bank addon conflict warning popup with disable option
    @param addonName string - Name of conflicting addon
]]
function WarbandNexus:QueueConflictPopup(addonName)
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    table.insert(self._conflictQueue, addonName)
end

function WarbandNexus:ShowNextConflictPopup()
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    
    if self._isProcessingConflict or #self._conflictQueue == 0 then
        return
    end
    
    self._isProcessingConflict = true
    local addonName = table.remove(self._conflictQueue, 1)
    self:ShowBankAddonConflictWarning(addonName)
end

function WarbandNexus:CheckBankConflictsOnLogin()
    -- Initialize flags
    self._needsReload = false
    
    -- Safety check: Ensure db is initialized
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return
    end
    
    -- Detect all conflicting addons
    local conflicts = self:DetectBankAddonConflicts()
    
    if not conflicts or #conflicts == 0 then
        return -- No conflicts
    end
    
    -- Filter out addons that user already made a choice for
    -- BUT: If user chose "useWarband" and re-enabled the addon, ask again!
    local unresolvedConflicts = {}
    for _, addonName in ipairs(conflicts) do
        local choice = self.db.profile.bankConflictChoices[addonName]
        
        -- Always show popup if:
        -- 1. No choice recorded yet
        -- 2. User chose "useWarband" but addon is active again (user re-enabled it!)
        if not choice or choice == "useWarband" then
            table.insert(unresolvedConflicts, addonName)
        end
        -- Skip if choice == "useOther" (user wants to keep the other addon)
    end
    
    if #unresolvedConflicts == 0 then
        return -- All conflicts already resolved
    end
    
    -- Queue all unresolved conflicts
    for _, addonName in ipairs(unresolvedConflicts) do
        self:QueueConflictPopup(addonName)
    end
    
    -- Start showing popups
    self:ShowNextConflictPopup()
end

function WarbandNexus:ShowReloadPopup()
    -- Create reload confirmation popup
    StaticPopupDialogs["WARBANDNEXUS_RELOAD_UI"] = {
        text = "|cff00ff00Addon settings changed!|r\n\nA UI reload is required to apply changes.\n\nReload now?",
        button1 = "Reload",
        button2 = "Later",
        OnAccept = function()
            -- CRITICAL: Call ReloadUI() directly from popup button (not protected!)
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("WARBANDNEXUS_RELOAD_UI")
end

function WarbandNexus:ShowBankAddonConflictWarning(addonName)
    -- Create or update popup dialog
    StaticPopupDialogs["WARBANDNEXUS_BANK_CONFLICT"] = {
        text = "",
        button1 = "Use Warband Nexus",
        button2 = "Use " .. addonName,
        OnAccept = function(self)
            -- Button 1: User wants to use Warband Nexus - disable conflicting addon
            WarbandNexus.db.profile.bankConflictChoices[self.data] = "useWarband"
            
            local success, message = WarbandNexus:DisableConflictingBankModule(self.data)
            if not success then
                WarbandNexus:Print(message)
            end
            
            -- Mark that we need reload (if addon was disabled)
            if success then
                WarbandNexus._needsReload = true
                WarbandNexus:ClearConflictCache()
            end
            
            WarbandNexus._isProcessingConflict = false
            
            -- Process next conflict OR reload if no more conflicts
            if #WarbandNexus._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if WarbandNexus then
                        WarbandNexus:ShowNextConflictPopup()
                    end
                end)
            elseif WarbandNexus._needsReload then
                -- All done, show reload popup
                WarbandNexus:ShowReloadPopup()
            end
        end,
        OnCancel = function(self)
            -- Button 2: User wants to keep the other addon
            WarbandNexus.db.profile.bankConflictChoices[self.data] = "useOther"
            
            -- Enable the conflicting addon (make sure it's active)
            local success, message = WarbandNexus:EnableConflictingBankModule(self.data)
            if success then
                WarbandNexus._needsReload = true
            end
            
            WarbandNexus._isProcessingConflict = false
            
            -- Process next conflict OR finish if no more conflicts
            if #WarbandNexus._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if WarbandNexus then
                        WarbandNexus:ShowNextConflictPopup()
                    end
                end)
            elseif WarbandNexus._needsReload then
                -- Some addons were enabled/disabled, show reload popup
                WarbandNexus:ShowReloadPopup()
            else
                -- All done, no reload needed
                WarbandNexus:Print("|cff00ff00All conflicts resolved! No reload needed.|r")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false, -- Force user to choose
        preferredIndex = 3,
    }
    
    -- Set dynamic text
    local warningText = string.format(
        "|cffff9900Bank Addon Conflict|r\n\n" ..
        "You have |cff00ccff%s|r installed.\n\n" ..
        "Which addon do you want to use for bank UI?\n\n" ..
        "|cff00ff00Use Warband Nexus:|r Disable %s automatically\n" ..
        "|cff888888Use %s:|r WarbandNexus works in background mode\n\n" ..
        "Characters, PvE, and Statistics tabs work regardless of choice.",
        addonName, addonName, addonName
    )
    
    StaticPopupDialogs["WARBANDNEXUS_BANK_CONFLICT"].text = warningText
    local dialog = StaticPopup_Show("WARBANDNEXUS_BANK_CONFLICT")
    if dialog then
        dialog.data = addonName
    end
end

-- Setup BankFrame hook to make it invisible (but NOT hidden - keeps API working!)
function WarbandNexus:SetupBankFrameHook()
    if not BankFrame then return end
    if self.bankFrameHooked then return end
    
    -- Check for conflicting addons (if user chose another addon, don't suppress)
    if self:IsUsingOtherBankAddon() then
        -- User chose to use another addon, don't suppress bank frame
        self.bankFrameSuppressed = false
        return
    end
    
    -- Hook OnShow event
    -- This fires EVERY TIME WoW tries to show the BankFrame
    BankFrame:HookScript("OnShow", function(frame)
        -- If we're suppressing, make invisible (but don't Hide()!)
        if WarbandNexus and WarbandNexus.bankFrameSuppressed then
            -- Standard suppression method: Invisible but active
            frame:SetAlpha(0)                    -- Invisible
            frame:EnableMouse(false)             -- No clicks
            frame:SetScale(0.001)                -- Minimum size
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000) -- Far off-screen
        end
    end)
    
    self.bankFrameHooked = true
    self.bankFrameSuppressed = true
    
    -- Initial suppress (if already shown)
    if BankFrame:IsShown() then
        BankFrame:SetAlpha(0)
        BankFrame:EnableMouse(false)
        BankFrame:SetScale(0.001)
        BankFrame:ClearAllPoints()
        BankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
    end
end

-- Suppress (make invisible)
function WarbandNexus:SuppressDefaultBankFrame()
    -- Check user's choice about bank addon conflict
    if self:IsUsingOtherBankAddon() then
        return -- User chose another addon, don't suppress
    end
    
    self.bankFrameSuppressed = true

    if BankFrame and BankFrame:IsShown() then
        -- DON'T Hide()! Just make invisible and move off-screen
        BankFrame:SetAlpha(0)
        BankFrame:EnableMouse(false)
        BankFrame:SetScale(0.001)
        BankFrame:ClearAllPoints()
        BankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
        
        -- DON'T recursively disable children - let them stay enabled
        -- This way when we restore, they'll already work
    end
end

-- Restore (make visible again)
function WarbandNexus:RestoreDefaultBankFrame()
    -- Check user's choice about bank addon conflict
    if self:IsUsingOtherBankAddon() then
        return -- User chose another addon, don't restore
    end

    if not BankFrame then
        return
    end

    -- Disable suppression FIRST
    self.bankFrameSuppressed = false

    -- Reset position and properties to default
    BankFrame:SetAlpha(1)
    BankFrame:SetScale(1)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    BankFrame:EnableMouse(true)

    -- Show the frame
    BankFrame:Show()

    -- Simple re-enable (children should already be enabled since we didn't disable them)
    C_Timer.After(0.05, function()
        if BankFrame and BankFrame:IsShown() then
            BankFrame:SetAlpha(1)
            BankFrame:EnableMouse(true)
            self:Print("Classic Bank restored - items should work now")
        end
    end)
end

-- Hide the default Blizzard bank frame (deprecated - frames are already suppressed)
function WarbandNexus:HideDefaultBankFrame()
    -- Bank frames are already off-screen from SuppressDefaultBankFrame()
    -- No need to do anything
end

-- Show the default Blizzard bank frame (Classic Bank button)
function WarbandNexus:ShowDefaultBankFrame()
    
    -- Simply restore frame positions (bank frame is always visible, just off-screen)
    self:RestoreDefaultBankFrame()
    
    -- Open player bags
    if OpenAllBags then
        OpenAllBags()
    end
end

function WarbandNexus:OnBankClosed()
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
    
    -- If user was using Classic Bank mode, hide bank again
    if self.classicBankMode then
        self.classicBankMode = false
        self:SuppressDefaultBankFrame()
    else
        -- Normal bank close (addon was already visible)
    -- Show warning if addon window is open
    if self:IsMainWindowShown() then
        -- Refresh title/status immediately
        if self.UpdateStatus then
             self:UpdateStatus()
        end
        self:Print("|cffff9900Bank connection lost. Showing cached data.|r")
    end
    
    -- Refresh UI if open (to update buttons/status)
    if self.RefreshUI then
        self:RefreshUI()
        end
    end
end

-- Check if main window is visible
function WarbandNexus:IsMainWindowShown()
    local UI = self.UI
    if UI and UI.mainFrame and UI.mainFrame:IsShown() then
        return true
    end
    -- Fallback check
    if WarbandNexusMainFrame and WarbandNexusMainFrame:IsShown() then
        return true
    end
    return false
end

-- Called when player or Warband Bank gold changes (PLAYER_MONEY, ACCOUNT_MONEY)
function WarbandNexus:OnMoneyChanged()
    self.db.char.lastKnownGold = GetMoney()
    
    -- Update character gold in global tracking
    self:UpdateCharacterGold()
    
    -- INSTANT UI refresh if addon window is open
    if self.bankIsOpen and self.RefreshUI then
        -- Use very short delay to batch multiple money events
        if not self.moneyRefreshPending then
            self.moneyRefreshPending = true
            C_Timer.After(0.05, function()
                self.moneyRefreshPending = false
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when player enters the world (login or reload)
]]
function WarbandNexus:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    -- Reset save flag on new login
    if isInitialLogin then
        self.characterSaved = false
        
        -- Check for notifications on initial login only (not on reload)
        if self.CheckNotificationsOnLogin then
            self:CheckNotificationsOnLogin()
        end
    end
    
    -- Single save attempt after 2 seconds (enough for character data to load)
    C_Timer.After(2, function()
        if WarbandNexus then
            WarbandNexus:SaveCharacter()
        end
    end)
    
    -- Check for bank addon conflicts after a delay
    -- Wait for all addons to fully load (5 seconds after entering world)
    if isInitialLogin or isReloadingUi then
        C_Timer.After(5, function()
            if WarbandNexus then
                WarbandNexus:CheckBankConflictsOnLogin()
            end
        end)
    end
end

--[[
    Called when player levels up
]]
function WarbandNexus:OnPlayerLevelUp(event, level)
    -- Force update on level up
    self.characterSaved = false
    self:SaveCharacter()
end

--[[
    Called when PvE data changes (Great Vault, Lockouts, M+ completion)
]]
function WarbandNexus:OnPvEDataChanged()
    -- Re-collect and update PvE data for current character
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        local pveData = self:CollectPvEData()
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate PvE cache for current character
        if self.InvalidatePvECache then
            self:InvalidatePvECache(key)
        end
        
        -- Refresh UI if PvE tab is open
        if self.RefreshPvEUI then
            self:RefreshPvEUI()
        end
    end
end

--[[
    Called when keystone might have changed (delayed bag update)
]]
function WarbandNexus:OnKeystoneChanged()
    -- Throttle keystone checks to avoid spam
    if not self.keystoneCheckPending then
        self.keystoneCheckPending = true
        C_Timer.After(1, function()
            self.keystoneCheckPending = false
            if WarbandNexus and WarbandNexus.OnPvEDataChanged then
                WarbandNexus:OnPvEDataChanged()
            end
        end)
    end
end

--[[
    Event handler for collection changes (mounts, pets, toys)
    Ultra-fast update with minimal throttle for instant UI feedback
]]
function WarbandNexus:OnCollectionChanged(event)
    -- Minimal throttle only for TOYS_UPDATED (can fire frequently)
    -- NEW_* events are single-fire, no throttle needed
    local needsThrottle = (event == "TOYS_UPDATED")
    
    if needsThrottle and self.collectionCheckPending then
        return -- Skip if throttled
    end
    
    if needsThrottle then
        self.collectionCheckPending = true
        C_Timer.After(0.2, function()
            if WarbandNexus then
                WarbandNexus.collectionCheckPending = false
            end
        end)
    end
    
    -- Update character data
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        -- Update timestamp
        self.db.global.characters[key].lastSeen = time()
        
        -- Debug logging
        if self.db.profile.debug then
            local collectionType = "item"
            if event == "NEW_MOUNT_ADDED" then
                collectionType = "mount"
            elseif event == "NEW_PET_ADDED" then
                collectionType = "pet"
            elseif event == "NEW_TOY_ADDED" or event == "TOYS_UPDATED" then
                collectionType = "toy"
            end
        end
        
        -- Invalidate collection cache (data changed)
        if self.InvalidateCollectionCache then
            self:InvalidateCollectionCache()
        end
        
        -- INSTANT UI refresh if Statistics tab is active
        if self.UI and self.UI.mainFrame then
            local mainFrame = self.UI.mainFrame
            if mainFrame:IsShown() and mainFrame.currentTab == "stats" then
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end
        end
    end
end

--[[
    Event handler for pet journal changes (cage/release)
    Smart tracking: Only update when pet count actually changes
]]
function WarbandNexus:OnPetListChanged()
    -- Only process if UI is open on stats tab
    if not self.UI or not self.UI.mainFrame then return end
    
    local mainFrame = self.UI.mainFrame
    if not mainFrame:IsShown() or mainFrame.currentTab ~= "stats" then
        return -- Skip if UI not visible or wrong tab
    end
    
    -- Get current pet count
    local _, currentPetCount = C_PetJournal.GetNumPets()
    
    -- Initialize cache if needed
    if not self.lastPetCount then
        self.lastPetCount = currentPetCount
        return -- First call, just cache
    end
    
    -- Check if count actually changed
    if currentPetCount == self.lastPetCount then
        return -- No change, skip update
    end
    
    -- Count changed! Update cache
    self.lastPetCount = currentPetCount
    
    -- Throttle to batch rapid changes
    if self.petListCheckPending then return end
    
    self.petListCheckPending = true
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end
        WarbandNexus.petListCheckPending = false
        
        -- Update timestamp
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[key] then
            WarbandNexus.db.global.characters[key].lastSeen = time()
            
            if WarbandNexus.db.profile.debug then
                WarbandNexus:Debug("Pet count changed: " .. (WarbandNexus.lastPetCount or 0) .. " - refreshing UI")
            end
            
            -- Instant UI refresh
            if WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end
    end)
end

-- SaveCurrentCharacterData() moved to Modules/DataService.lua


-- UpdateCharacterGold() moved to Modules/DataService.lua

-- CollectPvEData() moved to Modules/DataService.lua


-- GetAllCharacters() moved to Modules/DataService.lua

---@param bagIDs table Table of bag IDs that were updated
function WarbandNexus:OnBagUpdate(bagIDs)
    
    -- Check if bank is open at all
    if not self.bankIsOpen then return end
    
    local warbandUpdated = false
    local personalUpdated = false
    local inventoryUpdated = false
    
    for bagID in pairs(bagIDs) do
        
        -- Check Warband bags
        if self:IsWarbandBag(bagID) then
            warbandUpdated = true
        end
        -- Check Personal bank bags (including main bank -1 and bags 6-12)
        if bagID == -1 or (bagID >= 6 and bagID <= 12) then
            personalUpdated = true
        end
        -- Check player inventory bags (0-4) - item moved TO inventory
        if bagID >= 0 and bagID <= 4 then
            inventoryUpdated = true
        end
    end
    
    
    -- If inventory changed while bank is open, we need to re-scan banks too
    -- (item may have been moved from bank to inventory)
    local needsRescan = warbandUpdated or personalUpdated or inventoryUpdated
    
    -- Batch updates with a timer to avoid spam
    if needsRescan then
        if self.pendingScanTimer then
            self:CancelTimer(self.pendingScanTimer)
        end
        self.pendingScanTimer = self:ScheduleTimer(function()
            
            -- Re-scan both banks when any change occurs (items can move between them)
            if self.warbandBankIsOpen and self.ScanWarbandBank then
                self:ScanWarbandBank()
            end
            if self.bankIsOpen and self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
            
            -- Invalidate item caches (data changed)
            if self.InvalidateItemCache then
                self:InvalidateItemCache()
            end
            
            -- Invalidate tooltip cache (items changed)
            if self.InvalidateTooltipCache then
                self:InvalidateTooltipCache()
            end
            
            -- Refresh UI
            if self.RefreshUI then
                self:RefreshUI()
            end
            
            
            self.pendingScanTimer = nil
        end, 0.5)
    end
end

--[[
    Utility Functions
]]

---Check if a bag ID is a Warband bank bag
---@param bagID number The bag ID to check
---@return boolean
function WarbandNexus:IsWarbandBag(bagID)
    for _, warbandBagID in ipairs(ns.WARBAND_BAGS) do
        if bagID == warbandBagID then
            return true
        end
    end
    return false
end

---Check if Warband bank is currently open
---Uses event-based tracking combined with bag access verification
---@return boolean
function WarbandNexus:IsWarbandBankOpen()
    -- Primary method: Use our tracked state from BANKFRAME events
    if self.warbandBankIsOpen then
        return true
    end
    
    -- Secondary method: If bank event flag is set, verify we can access Warband bags
    if self.bankIsOpen then
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        if firstBagID then
            local numSlots = C_Container.GetContainerNumSlots(firstBagID)
            if numSlots and numSlots > 0 then
                -- We can access Warband bank, update flag
                self.warbandBankIsOpen = true
                return true
            end
        end
    end
    
    -- Fallback: Direct bag access check (in case events were missed)
    local firstBagID = Enum.BagIndex.AccountBankTab_1
    if firstBagID then
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        -- In TWW, purchased Warband Bank tabs have 98 slots
        -- Only return true if we also see the bank is truly accessible
        if numSlots and numSlots > 0 then
            -- Try to verify by checking if BankFrame exists and is shown
            if BankFrame and BankFrame:IsShown() then
                self.warbandBankIsOpen = true
                self.bankIsOpen = true
                return true
            end
        end
    end
    
    return false
end

---Get the number of slots in a bag (with fallback)
---@param bagID number The bag ID
---@return number
function WarbandNexus:GetBagSize(bagID)
    -- Use API wrapper for future-proofing
    return self:API_GetBagSize(bagID)
end

---Debug function (disabled for production)
---@param message string The message to print
function WarbandNexus:Debug(message)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print("|cff888888[DEBUG]|r " .. tostring(message))
    end
end

---Get display name for an item (handles caged pets)
---Caged pets show "Pet Cage" in item name but have the real pet name in tooltip line 3
---@param itemID number The item ID
---@param itemName string The item name from cache
---@param classID number|nil The item class ID (17 = Battle Pet)
---@return string displayName The display name (pet name for caged pets, item name otherwise)
function WarbandNexus:GetItemDisplayName(itemID, itemName, classID)
    -- If this is a caged pet (classID 17), try to get the pet name from tooltip
    if classID == 17 and itemID then
        local petName = self:GetPetNameFromTooltip(itemID)
        if petName then
            return petName
        end
    end
    
    -- Fallback: Use item name
    return itemName or "Unknown Item"
end

---Extract pet name from item tooltip (locale-independent)
---Used for caged pets where item name is "Pet Cage" but tooltip has the real pet name
---@param itemID number The item ID
---@return string|nil petName The pet's name extracted from tooltip
function WarbandNexus:GetPetNameFromTooltip(itemID)
    if not itemID then
        return nil
    end
    
    -- METHOD 1: Try C_PetJournal API first (most reliable)
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local result = C_PetJournal.GetPetInfoByItemID(itemID)
        
        -- If result is a number, it's speciesID (old behavior)
        if type(result) == "number" and result > 0 then
            local speciesName = C_PetJournal.GetPetInfoBySpeciesID(result)
            if speciesName and speciesName ~= "" then
                return speciesName
            end
        end
        
        -- If result is a string, it's the pet name (TWW behavior)
        if type(result) == "string" and result ~= "" then
            return result
        end
    end
    
    -- METHOD 2: Tooltip parsing (fallback)
    if not C_TooltipInfo then
        return nil
    end
    
    local tooltipData = C_TooltipInfo.GetItemByID(itemID)
    if not tooltipData then
        return nil
    end
    
    -- METHOD 2A: CHECK battlePetName FIELD (TWW 11.0+ feature!)
    -- Surface args to expose all fields
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(tooltipData)
    end
    
    -- Check if battlePetName field exists (TWW API)
    if tooltipData.battlePetName and tooltipData.battlePetName ~= "" then
        return tooltipData.battlePetName
    end
    
    -- METHOD 2B: FALLBACK TO LINE PARSING
    if not tooltipData.lines then
        return nil
    end
    
    -- Caged pet tooltip structure (TWW):
    -- Line 1: Item name ("Pet Cage" / "BattlePet")
    -- Line 2: Category ("Battle Pet")
    -- Line 3: Pet's actual name OR empty OR quality/level
    -- Line 4+: Stats or "Use:" description
    
    -- Strategy: Find first line that:
    -- 1. Is NOT the item name
    -- 2. Is NOT "Battle Pet" or translations
    -- 3. Does NOT contain ":"
    -- 4. Is NOT quality/level info
    -- 5. Is a reasonable name length (3-35 chars)
    
    local knownBadPatterns = {
        "^Battle Pet",      -- Category (EN)
        "^BattlePet",       -- Item name
        "^Pet Cage",        -- Item name
        "^Kampfhaustier",   -- Category (DE)
        "^Mascotte",        -- Category (FR)
        "^Companion",       -- Old category
        "^Use:",            -- Description
        "^Requires:",       -- Requirement
        "Level %d",         -- Level info
        "^Poor",            -- Quality
        "^Common",          -- Quality
        "^Uncommon",        -- Quality
        "^Rare",            -- Quality
        "^Epic",            -- Quality
        "^Legendary",       -- Quality
        "^%d+$",            -- Just numbers
    }
    
    -- Parse tooltip lines for pet name
    for i = 1, math.min(#tooltipData.lines, 8) do
        local line = tooltipData.lines[i]
        if line and line.leftText then
            local text = line.leftText
            
            -- Clean color codes and formatting
            local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h", ""):gsub("|H", "")
            cleanText = cleanText:match("^%s*(.-)%s*$") or ""
            
            -- Check if this line is a valid pet name
            if #cleanText >= 3 and #cleanText <= 35 then
                local isBadLine = false
                
                -- Check against known bad patterns
                for _, pattern in ipairs(knownBadPatterns) do
                    if cleanText:match(pattern) then
                        isBadLine = true
                        break
                    end
                end
                
                -- Additional checks: contains ":" or starts with digit
                if not isBadLine then
                    if cleanText:match(":") or cleanText:match("^%d") then
                        isBadLine = true
                    end
                end
                
                if not isBadLine then
                    return cleanText
                end
            end
        end
    end

    return nil
end

--[[
    Placeholder functions for modules
    These will be implemented in their respective module files
]]

function WarbandNexus:ScanWarbandBank()
    -- Implemented in Modules/Scanner.lua
end

function WarbandNexus:ToggleMainWindow()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:OpenDepositQueue()
    -- Implemented in Modules/Banker.lua
end

function WarbandNexus:SearchItems(searchTerm)
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:RefreshUI()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:RefreshPvEUI()
    -- Force refresh of PvE tab if currently visible (instant)
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
            end
        end
    end
end

function WarbandNexus:OpenOptions()
    -- Will be properly implemented in Config.lua
    Settings.OpenToCategory(ADDON_NAME)
end

---Print bank debug information to help diagnose detection issues
function WarbandNexus:PrintBankDebugInfo()
    self:Print("=== Bank Debug Info ===")
    
    -- Internal state flags
    self:Print("Internal Flags:")
    self:Print("  self.bankIsOpen: " .. tostring(self.bankIsOpen))
    self:Print("  self.warbandBankIsOpen: " .. tostring(self.warbandBankIsOpen))
    
    -- BankFrame check
    self:Print("BankFrame:")
    self:Print("  exists: " .. tostring(BankFrame ~= nil))
    if BankFrame then
        self:Print("  IsShown: " .. tostring(BankFrame:IsShown()))
    end
    
    -- Bag slot check (most reliable)
    self:Print("Warband Bank Bags:")
    for i = 1, 5 do
        local bagID = Enum.BagIndex["AccountBankTab_" .. i]
        if bagID then
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            local itemCount = 0
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info and info.itemID then
                        itemCount = itemCount + 1
                    end
                end
            end
            self:Print("  Tab " .. i .. ": BagID=" .. bagID .. ", Slots=" .. tostring(numSlots) .. ", Items=" .. itemCount)
        end
    end
    
    -- Final result
    self:Print("IsWarbandBankOpen(): " .. tostring(self:IsWarbandBankOpen()))
    self:Print("======================")
end

---Force scan without checking if bank is open (for debugging)
function WarbandNexus:ForceScanWarbandBank()
    self:Print("Force scanning Warband Bank (bypassing open check)...")
    
    -- Initialize structure if needed
    if not self.db.global.warbandBank then
        self.db.global.warbandBank = { items = {}, gold = 0, lastScan = 0 }
    end
    if not self.db.global.warbandBank.items then
        self.db.global.warbandBank.items = {}
    end
    
    -- Wipe existing items
    wipe(self.db.global.warbandBank.items)
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Try to scan all Warband bank tabs
    for tabIndex, bagID in ipairs(ns.WARBAND_BAGS) do
        local numSlots = self:GetBagSize(bagID)
        self:Print("Tab " .. tabIndex .. " (BagID " .. bagID .. "): " .. numSlots .. " slots")
        totalSlots = totalSlots + numSlots
        
        if numSlots > 0 then
            self.db.global.warbandBank.items[tabIndex] = {}
            
            for slotID = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                          _, _, itemTexture, _, classID, subclassID = C_Item.GetItemInfo(itemInfo.itemID)
                    
                    self.db.global.warbandBank.items[tabIndex][slotID] = {
                        itemID = itemInfo.itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality or itemQuality or 0,
                        iconFileID = itemInfo.iconFileID or itemTexture,
                        name = itemName,
                        itemLevel = itemLevel,
                        itemType = itemType,
                        itemSubType = itemSubType,
                        classID = classID,
                        subclassID = subclassID,
                    }
                end
            end
        end
    end
    
    -- Update metadata
    self.db.global.warbandBank.lastScan = time()
    self.db.global.warbandBank.totalSlots = totalSlots
    self.db.global.warbandBank.usedSlots = usedSlots
    
    -- Get Warband bank gold
    if C_Bank and C_Bank.FetchDepositedMoney then
        self.db.global.warbandBank.gold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end
    
    self:Print("Force scan complete: " .. totalItems .. " items in " .. usedSlots .. "/" .. totalSlots .. " slots")
    
    -- Refresh UI
    if self.RefreshUI then
        self:RefreshUI()
    end
end

function WarbandNexus:InitializeConfig()
    -- Implemented in Config.lua
end

--[[
    Print current character's PvE data for debugging
]]
function WarbandNexus:PrintPvEData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    self:Print("=== PvE Data for " .. name .. " ===")
    
    local pveData = self:CollectPvEData()
    
    -- Great Vault
    self:Print("|cffffd700Great Vault:|r")
    if pveData.greatVault and #pveData.greatVault > 0 then
        for i, activity in ipairs(pveData.greatVault) do
            local typeName = "Unknown"
            local typeNum = activity.type
            
            -- Try Enum first, fallback to numbers
            if Enum and Enum.WeeklyRewardChestThresholdType then
                if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                end
            else
                -- Fallback to numeric values
                if typeNum == 1 then typeName = "Raid"
                elseif typeNum == 2 then typeName = "M+"
                elseif typeNum == 3 then typeName = "PvP"
                elseif typeNum == 4 then typeName = "World"
                end
            end
            
            self:Print(string.format("  %s (type=%d) [%d]: %d/%d (Level %d)", 
                typeName, typeNum, activity.index or 0, 
                activity.progress or 0, activity.threshold or 0,
                activity.level or 0))
        end
    else
        self:Print("  No vault data available")
    end
    
    -- Mythic+
    self:Print("|cffa335eeM+ Keystone:|r")
    if pveData.mythicPlus and pveData.mythicPlus.keystone then
        local ks = pveData.mythicPlus.keystone
        self:Print(string.format("  %s +%d", ks.name or "Unknown", ks.level or 0))
    else
        self:Print("  No keystone")
    end
    if pveData.mythicPlus then
        if pveData.mythicPlus.weeklyBest then
            self:Print(string.format("  Weekly Best: +%d", pveData.mythicPlus.weeklyBest))
        end
        if pveData.mythicPlus.runsThisWeek then
            self:Print(string.format("  Runs This Week: %d", pveData.mythicPlus.runsThisWeek))
        end
    end
    
    -- Lockouts
    self:Print("|cff0070ddRaid Lockouts:|r")
    if pveData.lockouts and #pveData.lockouts > 0 then
        for i, lockout in ipairs(pveData.lockouts) do
            self:Print(string.format("  %s (%s): %d/%d", 
                lockout.name or "Unknown",
                lockout.difficultyName or "Normal",
                lockout.progress or 0,
                lockout.total or 0))
        end
    else
        self:Print("  No active lockouts")
    end
    
    self:Print("===========================")
    
    -- Save the data
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        self:Print("|cff00ff00Data saved! Use /wn pve to view in UI|r")
    end
end

--[[============================================================================
    FAVORITE CHARACTERS MANAGEMENT
============================================================================]]

---Check if a character is favorited
---@param characterKey string Character key ("Name-Realm")
---@return boolean
function WarbandNexus:IsFavoriteCharacter(characterKey)
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return false
    end
    
    for _, favKey in ipairs(self.db.global.favoriteCharacters) do
        if favKey == characterKey then
            return true
                    end
                end
    
    return false
    end
    
---Toggle favorite status for a character
---@param characterKey string Character key ("Name-Realm")
---@return boolean New favorite status
function WarbandNexus:ToggleFavoriteCharacter(characterKey)
    if not self.db or not self.db.global then
        return false
    end
    
    -- Initialize if needed
    if not self.db.global.favoriteCharacters then
        self.db.global.favoriteCharacters = {}
    end
    
    local favorites = self.db.global.favoriteCharacters
    local isFavorite = self:IsFavoriteCharacter(characterKey)
    
    if isFavorite then
        -- Remove from favorites
        for i, favKey in ipairs(favorites) do
            if favKey == characterKey then
                table.remove(favorites, i)
                self:Print("|cffffff00Removed from favorites:|r " .. characterKey)
                                break
                            end
                        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        self:Print("|cffffd700Added to favorites:|r " .. characterKey)
        return true
        end
    end
    
---Get all favorite characters
---@return table Array of favorite character keys
function WarbandNexus:GetFavoriteCharacters()
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return {}
    end
    
    return self.db.global.favoriteCharacters
end

-- PerformItemSearch() moved to Modules/DataService.lua


