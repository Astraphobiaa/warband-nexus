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

        -- Behavior settings
        autoScan = true,           -- Auto-scan when bank opens
        autoOpenWindow = true,     -- Auto-open addon window when bank opens
        autoSaveChanges = true,    -- Live sync while bank is open
        replaceDefaultBank = true, -- Replace default bank UI with addon
        
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
            showLootNotifications = false,     -- Show looted items (future)
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
    -- #region agent log [Hypothesis D - Addon loading]
    print("|cff00ff00[WarbandNexus]|r OnInitialize started")
    -- #endregion
    
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
    
    -- #region agent log [Hypothesis D - Addon loading]
    print("|cff00ff00[WarbandNexus]|r OnInitialize complete - Slash commands: /wn, /warbandnexus")
    -- #endregion
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function WarbandNexus:OnEnable()
    -- #region agent log [Hypothesis D - Addon loading]
    print("|cff00ff00[WarbandNexus]|r OnEnable started, enabled=" .. tostring(self.db.profile.enabled))
    -- #endregion
    
    if not self.db.profile.enabled then
        return
    end
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- Register events
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnPlayerLevelUp")
    
    -- PvE tracking events
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnPvEDataChanged")  -- Great Vault updates
    self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnPvEDataChanged")   -- Raid lockout updates
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnPvEDataChanged") -- M+ completion
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnKeystoneChanged")    -- Keystone changes
    
    -- Collection tracking events (instant updates)
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionChanged")     -- Mount learned (instant)
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionChanged")       -- Pet learned (instant)
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionChanged")       -- Toy learned (instant)
    self:RegisterEvent("TOYS_UPDATED", "OnCollectionChanged")        -- Toy collection updated
    self:RegisterEvent("PET_JOURNAL_LIST_UPDATE", "OnPetListChanged") -- Pet caged/released (throttled)
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Setup bank frame hooks to auto-hide default UI
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.SetupBankHook then
            WarbandNexus:SetupBankHook()
        end
    end)
    
    -- Hook container clicks to ensure UI refreshes on item move
    -- Note: ContainerFrameItemButton_OnModifiedClick was removed in TWW (11.0+)
    -- We now rely on BAG_UPDATE_DELAYED event for UI updates
    if not self.containerHooked then
        self:Debug("Container monitoring initialized (using BAG_UPDATE_DELAYED event)")
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
    
    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
    
    -- #region agent log [Hypothesis D - Addon loading]
    print("|cff00ff00[WarbandNexus]|r OnEnable complete - Events registered")
    print("|cff6a0dad[WarbandNexus]|r Core: APIWrapper ✓")
    print("|cff6a0dad[WarbandNexus]|r Production: ErrorHandler ✓ DatabaseOptimizer ✓")
    print("|cff6a0dad[WarbandNexus]|r Advanced: DataService ✓ CacheManager ✓ EventManager ✓ TooltipEnhancer ✓")
    -- #endregion
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
    
    self:Debug("OnDisable complete")
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
        self:Print("  /wn show - " .. L["SLASH_SHOW"])
        self:Print("  /wn options - " .. L["SLASH_OPTIONS"])
        self:Print("  /wn scan - " .. L["SLASH_SCAN"])
        self:Print("  /wn storage - Show Storage Browser tab")
        self:Print("  /wn chars - List tracked characters")
        self:Print("  /wn pve - Show PvE tab (Great Vault, M+, Lockouts)")
        self:Print("  /wn pvedata - Print current character's PvE data")
        self:Print("  /wn cache - Show cache statistics (performance)")
        self:Print("  /wn events - Show event statistics (throttling)")
        self:Print("  /wn cleanup - Remove characters inactive for 90+ days")
        self:Print("  /wn clearcache - Clear all caches (force refresh)")
        self:Print("  /wn minimap - Toggle minimap button visibility")
        self:Print("  /wn vaultcheck - Test Weekly Vault notification system")
        self:Print("  /wn enumcheck - Debug: Check Enum values & vault activities")
        self:Print("  /wn debug - Toggle debug mode")
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
    elseif cmd == "minimap" then
        if self.ToggleMinimapButton then
            self:ToggleMinimapButton()
        else
            self:Print("Minimap button module not loaded")
        end
    
    elseif cmd == "vaultcheck" or cmd == "testvault" then
        -- Test vault notification system
        if self.TestVaultCheck then
            self:TestVaultCheck()
        else
            self:Print("Vault check module not loaded")
        end

    -- Hidden/Debug commands (not shown in help)
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
    
    -- Read which tab Blizzard selected when bank opened
    -- Tab 1 = Personal Bank, Tab 2 = Warband Bank
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
    
    self:Debug("OPEN: Selected bank type = " .. self.currentBankType)
    
    -- Scan personal bank BEFORE suppressing BankFrame
    if self.db.profile.autoScan and self.ScanPersonalBank then
        self:ScanPersonalBank()
    end
    
    -- Suppress default bank frame
    if self.db.profile.replaceDefaultBank ~= false then
        self:SuppressDefaultBankFrame()
        if OpenAllBags then
            OpenAllBags()
        end
    end
    
    -- Delayed operations for Warband bank
    C_Timer.After(0.2, function()
        if not WarbandNexus then return end
        
        -- Check Warband bank accessibility
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        
        if numSlots and numSlots > 0 then
            WarbandNexus.warbandBankIsOpen = true
            
            if WarbandNexus.db.profile.autoScan and WarbandNexus.ScanWarbandBank then
                WarbandNexus:ScanWarbandBank()
            end
        end
        
        -- Auto-open addon window with CORRECT tab based on NPC type
        if WarbandNexus.db.profile.autoOpenWindow ~= false then
            C_Timer.After(0.1, function()
                if WarbandNexus and WarbandNexus.ShowMainWindowWithItems then
                    WarbandNexus:ShowMainWindowWithItems(WarbandNexus.currentBankType)
                end
            end)
        end
    end)
end

-- Note: We no longer use UnregisterAllEvents because it triggers BANKFRAME_CLOSED
-- Instead we just hide and move the frame off-screen

-- Suppress default Blizzard bank frames by moving them off-screen
function WarbandNexus:SuppressDefaultBankFrame()
    -- Move BankFrame off-screen (keeps events working but not visible/interactable)
    if BankFrame then
        BankFrame:ClearAllPoints()
        BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, -10000)
        BankFrame:SetFrameStrata("BACKGROUND")
        BankFrame:EnableMouse(false)
        BankFrame:SetAlpha(0)
    end
    
    -- Also move AccountBankPanel off-screen
    if AccountBankPanel then
        AccountBankPanel:ClearAllPoints()
        AccountBankPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, -10000)
        AccountBankPanel:SetFrameStrata("BACKGROUND")
        AccountBankPanel:EnableMouse(false)
        AccountBankPanel:SetAlpha(0)
    end

    self.bankFrameSuppressed = true
end

-- Restore default Blizzard bank frames (for Classic Bank button or bank close)
function WarbandNexus:RestoreDefaultBankFrame()
    -- Move BankFrame back to screen
    if BankFrame then
        BankFrame:ClearAllPoints()
        BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
        BankFrame:SetFrameStrata("HIGH")
        BankFrame:EnableMouse(true)
        BankFrame:SetAlpha(1)
    end
    
    -- Move AccountBankPanel back
    if AccountBankPanel then
        AccountBankPanel:ClearAllPoints()
        AccountBankPanel:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 0, 0)
        AccountBankPanel:SetFrameStrata("HIGH")
        AccountBankPanel:EnableMouse(true)
        AccountBankPanel:SetAlpha(1)
    end

    self.bankFrameSuppressed = false
end

-- Hide the default Blizzard bank frame
function WarbandNexus:HideDefaultBankFrame()
    self:SuppressDefaultBankFrame()
end

-- Show the default Blizzard bank frame (Classic Bank button)
function WarbandNexus:ShowDefaultBankFrame()
    
    if not self.bankIsOpen then
        self:Print("|cffff6600You must be near a banker to open the bank.|r")
        return
    end
    
    
    -- Hide our addon window FIRST
    if self.HideMainWindow then
        self:HideMainWindow()
    end
    
    -- #region agent log [Classic Bank button]
    self:Debug("CLASSIC-BANK: Restoring default bank frame")
    -- #endregion
    
    -- Restore the default bank frame (alpha, mouse, position)
    self:RestoreDefaultBankFrame()
    
    -- Explicitly show the frames
    if BankFrame then
        BankFrame:Show()
    end
    if AccountBankPanel and self.warbandBankIsOpen then
        AccountBankPanel:Show()
    end
    
    -- Also open player bags (since we suppressed the default behavior)
    if OpenAllBags then
        OpenAllBags()
    end
end

-- Setup hook - we no longer modify bank frame, just track state
function WarbandNexus:SetupBankHook()
    if self.bankHookSetup then return end
    
    -- We don't hook anything anymore - let BankFrame work normally
    -- Our addon window with HIGH strata will cover it visually
    
    self.bankHookSetup = true
end

function WarbandNexus:OnBankClosed()
    
    -- ALWAYS process bank closing (since we no longer use fake-close logic)
    
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
    self.bankFrameSuppressed = false
    
    -- Restore default bank frame properties (alpha, strata, position)
    self:RestoreDefaultBankFrame()
    
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
    -- Debug mode removed for production
    -- Use ErrorHandler for critical logging
end

--[[
    Placeholder functions for modules
    These will be implemented in their respective module files
]]

function WarbandNexus:ScanWarbandBank()
    -- Implemented in Modules/Scanner.lua
    self:Debug("ScanWarbandBank called (stub)")
end

function WarbandNexus:ToggleMainWindow()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:OpenDepositQueue()
    -- Implemented in Modules/Banker.lua
end

function WarbandNexus:SearchItems(searchTerm)
    -- Implemented in Modules/UI.lua
    self:Debug("SearchItems called: " .. tostring(searchTerm))
end

function WarbandNexus:RefreshUI()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:RefreshPvEUI()
    -- Force refresh of PvE tab if currently visible (instant)
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            if self.db.profile.debug then
                self:Debug("PvE data changed - refreshing PvE UI")
            end
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


