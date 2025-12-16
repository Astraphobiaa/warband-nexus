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

-- Warband Bank Bag IDs
local WARBAND_BAGS = {
    Enum.BagIndex.AccountBankTab_1,
    Enum.BagIndex.AccountBankTab_2,
    Enum.BagIndex.AccountBankTab_3,
    Enum.BagIndex.AccountBankTab_4,
    Enum.BagIndex.AccountBankTab_5,
}

-- Personal Bank Bag IDs
-- Note: NUM_BANKBAGSLOTS is typically 7, plus the main bank slot
local PERSONAL_BANK_BAGS = {}

-- Main bank container (BANK = -1 in most clients)
if Enum.BagIndex.Bank then
    table.insert(PERSONAL_BANK_BAGS, Enum.BagIndex.Bank)
end

-- Bank bag slots (6-12 in Dragonflight+, or use Reagent/BankBag enums)
for i = 1, NUM_BANKBAGSLOTS or 7 do
    local bagEnum = Enum.BagIndex["BankBag_" .. i]
    if bagEnum then
        table.insert(PERSONAL_BANK_BAGS, bagEnum)
    end
end

-- Fallback: if enums didn't work, use numeric IDs
if #PERSONAL_BANK_BAGS == 0 then
    PERSONAL_BANK_BAGS = { -1, 6, 7, 8, 9, 10, 11, 12 }
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
        debug = false,
        
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
    
    -- Initialize LibDataBroker for minimap icon
    self:InitializeDataBroker()
    
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
        self:Debug("Addon is disabled in settings")
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
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Setup bank frame hooks to auto-hide default UI
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.SetupBankHook then
            WarbandNexus:SetupBankHook()
        end
    end)
    
    -- Hook container clicks to ensure UI refreshes on item move
    if not self.containerHooked then
        -- This hook fires when player right-clicks an item in their bag
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn, button)
            if not WarbandNexus then return end
            
            -- Only care about right-clicks when bank is open
            if button == "RightButton" and WarbandNexus.bankIsOpen then
                WarbandNexus:Debug("HOOK: Right-click in bag. WarbandTabActive=" .. tostring(WarbandNexus.warbandBankIsOpen))
                
                -- Fast UI refresh after item movement
                C_Timer.After(0.1, function()
                    if WarbandNexus and WarbandNexus.RefreshUI then
                        if WarbandNexus.ScanWarbandBank then WarbandNexus:ScanWarbandBank() end
                        if WarbandNexus.ScanPersonalBank then WarbandNexus:ScanPersonalBank() end
                        WarbandNexus:RefreshUI()
                    end
                end)
            end
        end)
        self.containerHooked = true
    end
    
    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
    
    -- #region agent log [Hypothesis D - Addon loading]
    print("|cff00ff00[WarbandNexus]|r OnEnable complete - Events registered")
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
        self:Debug("Character data saved")
    else
        self:Debug("Error saving character: " .. tostring(err))
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
    
    self:Debug("Profile changed")
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
        self:Print("  /wn chars - List tracked characters")
        self:Print("  /wn pve - Show PvE tab (Great Vault, M+, Lockouts)")
        self:Print("  /wn pvedata - Print current character's PvE data")
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
    elseif cmd == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        self:Print("Debug mode: " .. (self.db.profile.debug and "ON" or "OFF"))
    elseif cmd == "dumpbank" then
        -- Debug command to dump BankFrame structure
        if self.DumpBankFrameInfo then
            self:DumpBankFrameInfo()
        else
            self:Print("DumpBankFrameInfo not available")
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

--[[
    Initialize LibDataBroker for minimap icon
]]
function WarbandNexus:InitializeDataBroker()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    
    if not LDB or not LDBIcon then
        self:Debug("LibDataBroker or LibDBIcon not found")
        return
    end
    
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = L["ADDON_NAME"],
        icon = "Interface\\AddOns\\WarbandNexus\\Media\\icon",
        OnClick = function(_, button)
            if button == "LeftButton" then
                self:ToggleMainWindow()
            elseif button == "RightButton" then
                self:OpenOptions()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(L["ADDON_NAME"])
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00ff00Left-Click:|r " .. L["SLASH_SHOW"])
            tooltip:AddLine("|cff00ff00Right-Click:|r " .. L["SLASH_OPTIONS"])
        end,
    })
    
    LDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
    
    self:Debug("DataBroker initialized")
end

--[[
    Event Handlers
]]

function WarbandNexus:OnBankOpened()
    self:Debug("=== BANKFRAME_OPENED EVENT ===")
    
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

-- Suppress default Blizzard bank frames by putting our addon on top
-- CRITICAL: Do NOT modify BankFrame at all - just cover it with our window
function WarbandNexus:SuppressDefaultBankFrame()
    -- #region agent log [Bank Suppress Debug]
    self:Debug("SUPPRESS-START: bankIsOpen=" .. tostring(self.bankIsOpen))
    -- #endregion
    
    -- NEW STRATEGY: Don't touch BankFrame at all!
    -- Just let it be fully functional behind our addon window
    -- Our addon has HIGH strata, so it will be on top visually
    
    -- Only set the flag - don't modify BankFrame
    self.bankFrameSuppressed = true
    
    -- #region agent log [Bank Suppress Debug]
    self:Debug("SUPPRESS-END: BankFrame untouched, our HIGH strata addon covers it")
    -- #endregion
end

-- Restore default Blizzard bank frames (for Classic Bank button or bank close)
function WarbandNexus:RestoreDefaultBankFrame()
    -- #region agent log [Bank Restore Debug]
    self:Debug("RESTORE-START: bankFrameSuppressed=" .. tostring(self.bankFrameSuppressed))
    -- #endregion
    
    -- Just clear the flag - we never modified BankFrame
    self.bankFrameSuppressed = false
    
    -- #region agent log [Bank Restore Debug]
    self:Debug("RESTORE-END: bankFrameSuppressed=false")
    -- #endregion
end

-- Hide the default Blizzard bank frame - now does nothing (we overlay instead)
function WarbandNexus:HideDefaultBankFrame()
    -- Do nothing - let BankFrame work normally
    -- Our addon window overlays it with HIGH strata
end

-- Show the default Blizzard bank frame (Classic Bank button)
function WarbandNexus:ShowDefaultBankFrame()
    -- #region agent log [Classic Bank button]
    self:Debug("CLASSIC-BANK: ShowDefaultBankFrame called, bankIsOpen=" .. tostring(self.bankIsOpen))
    -- #endregion
    
    if not self.bankIsOpen then
        self:Print("|cffff6600You must be near a banker to open the bank.|r")
        return
    end
    
    -- #region agent log [Classic Bank button]
    self:Debug("CLASSIC-BANK: Hiding addon window first")
    -- #endregion
    
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
    
    self:Debug("Bank hooks disabled - using overlay method")
    self.bankHookSetup = true
end

function WarbandNexus:OnBankClosed()
    -- #region agent log [Bank Close Debug]
    self:Debug("=== BANKFRAME_CLOSED EVENT ===")
    self:Debug("CLOSE: Previous bankIsOpen=" .. tostring(self.bankIsOpen))
    -- #endregion
    
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
        
        self:Debug("PvE data updated for " .. key)
        
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
    Save current character's data to global database
]]
function WarbandNexus:SaveCurrentCharacterData()
    local name = UnitName("player")
    local realm = GetRealmName()
    
    -- Safety check
    if not name or name == "" or name == "Unknown" then
        return false
    end
    if not realm or realm == "" then
        return false
    end
    
    local key = name .. "-" .. realm
    
    -- Get character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    local gold = GetMoney()
    local faction = UnitFactionGroup("player")
    local _, race = UnitRace("player")
    
    -- Validate we have critical info
    if not classFile or not level or level == 0 then
        return false
    end
    
    -- Initialize characters table if needed
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    -- Check if new character
    local isNew = (self.db.global.characters[key] == nil)
    
    -- Collect PvE data (Great Vault, Lockouts, M+)
    local pveData = self:CollectPvEData()
    
    -- Store character data
    self.db.global.characters[key] = {
        name = name,
        realm = realm,
        class = className,
        classFile = classFile,
        classID = classID,
        level = level,
        gold = gold,
        faction = faction,
        race = race,
        lastSeen = time(),
        pve = pveData,  -- Store PvE data
    }
    
    -- Notify only for new characters
    if isNew then
        self:Print("|cff00ff00" .. name .. "|r registered.")
    end
    
    self:Debug("Character saved: " .. key)
    return true
end


--[[
    Update only gold for current character (called on PLAYER_MONEY)
]]
function WarbandNexus:UpdateCharacterGold()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].gold = GetMoney()
        self.db.global.characters[key].lastSeen = time()
    end
end

--[[
    Collect PvE data (Great Vault, Lockouts, M+)
]]
function WarbandNexus:CollectPvEData()
    local pve = {
        greatVault = {},
        lockouts = {},
        mythicPlus = {},
    }
    
    -- Great Vault Progress
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        if activities then
            for _, activity in ipairs(activities) do
                -- Debug: Log all activity types we see
                if self.db and self.db.profile and self.db.profile.debug then
                    self:Debug(string.format("Vault Activity: type=%s, index=%s, progress=%s/%s", 
                        tostring(activity.type), tostring(activity.index),
                        tostring(activity.progress), tostring(activity.threshold)))
                end
                
                table.insert(pve.greatVault, {
                    type = activity.type,
                    index = activity.index,
                    progress = activity.progress,
                    threshold = activity.threshold,
                    level = activity.level,
                })
            end
        end
    end
    
    -- Raid/Instance Lockouts
    if GetNumSavedInstances then
        local numSaved = GetNumSavedInstances()
        for i = 1, numSaved do
            local instanceName, lockoutID, resetTime, difficultyID, locked, extended, 
                  instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, 
                  encounterProgress, extendDisabled, instanceID = GetSavedInstanceInfo(i)
            
            if locked or extended then
                table.insert(pve.lockouts, {
                    name = instanceName,
                    id = lockoutID,
                    reset = resetTime,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    isRaid = isRaid,
                    maxPlayers = maxPlayers,
                    progress = encounterProgress,
                    total = numEncounters,
                    extended = extended,
                })
            end
        end
    end
    
    -- Mythic+ Data
    if C_MythicPlus then
        -- Current keystone - scan player's bags for keystone item
        local keystoneMapID, keystoneLevel
        for bagID = 0, NUM_BAG_SLOTS do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        -- Keystone items have ID 180653 (Mythic Keystone base)
                        -- But actual keystones have different IDs per dungeon
                        local itemName, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemInfo.itemID)
                        if itemName and itemName:find("Keystone") then
                            -- Get keystone level from item link
                            local itemLink = itemInfo.hyperlink
                            if itemLink then
                                -- Extract level from link (format: [Keystone: Dungeon Name +15])
                                keystoneLevel = itemLink:match("%+(%d+)")
                                if keystoneLevel then
                                    keystoneLevel = tonumber(keystoneLevel)
                                    keystoneName = itemName:match("Keystone:%s*(.+)") or itemName
                                    keystoneMapID = itemInfo.itemID
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if keystoneMapID and keystoneLevel then
            pve.mythicPlus.keystone = {
                mapID = keystoneMapID,
                name = keystoneName,
                level = keystoneLevel,
            }
        end
        
        -- Weekly best - use Great Vault data instead (no direct M+ weekly best API)
        -- This is now tracked via C_WeeklyRewards in Great Vault section
        
        -- Run history this week
        if C_MythicPlus.GetRunHistory then
            local includeIncomplete = false
            local includePreviousWeeks = false
            local runs = C_MythicPlus.GetRunHistory(includeIncomplete, includePreviousWeeks)
            if runs then
                pve.mythicPlus.runsThisWeek = #runs
                -- Get highest run level for weekly best
                local bestLevel = 0
                for _, run in ipairs(runs) do
                    if run.level and run.level > bestLevel then
                        bestLevel = run.level
                    end
                end
                if bestLevel > 0 then
                    pve.mythicPlus.weeklyBest = bestLevel
                end
            else
                pve.mythicPlus.runsThisWeek = 0
            end
        end
    end
    
    return pve
end

--[[
    Get all tracked characters
    @return table - Array of character data sorted by level then name
]]
function WarbandNexus:GetAllCharacters()
    local characters = {}
    
    if not self.db.global.characters then
        return characters
    end
    
    for key, data in pairs(self.db.global.characters) do
        data._key = key  -- Include key for reference
        table.insert(characters, data)
    end
    
    -- Sort by level (highest first), then by name
    table.sort(characters, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then
            return (a.level or 0) > (b.level or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    
    return characters
end

---@param bagIDs table Table of bag IDs that were updated
function WarbandNexus:OnBagUpdate(bagIDs)
    -- #region agent log [BagUpdate Debug]
    self:Debug("BAG_UPDATE fired, bankIsOpen=" .. tostring(self.bankIsOpen))
    -- #endregion
    
    -- Check if bank is open at all
    if not self.bankIsOpen then return end
    
    local warbandUpdated = false
    local personalUpdated = false
    local inventoryUpdated = false
    
    for bagID in pairs(bagIDs) do
        -- #region agent log [BagUpdate Debug]
        self:Debug("BAG_UPDATE: bagID=" .. tostring(bagID))
        -- #endregion
        
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
    
    -- #region agent log [BagUpdate Debug]
    self:Debug("BAG_UPDATE: warband=" .. tostring(warbandUpdated) .. ", personal=" .. tostring(personalUpdated) .. ", inventory=" .. tostring(inventoryUpdated))
    -- #endregion
    
    -- If inventory changed while bank is open, we need to re-scan banks too
    -- (item may have been moved from bank to inventory)
    local needsRescan = warbandUpdated or personalUpdated or inventoryUpdated
    
    -- Batch updates with a timer to avoid spam
    if needsRescan then
        if self.pendingScanTimer then
            self:CancelTimer(self.pendingScanTimer)
        end
        self.pendingScanTimer = self:ScheduleTimer(function()
            -- #region agent log [BagUpdate Debug]
            self:Debug("BAG_UPDATE: Timer fired, re-scanning...")
            -- #endregion
            
            -- Re-scan both banks when any change occurs (items can move between them)
            if self.warbandBankIsOpen and self.ScanWarbandBank then
                self:ScanWarbandBank()
            end
            if self.bankIsOpen and self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
            
            -- Refresh UI
            if self.RefreshUI then
                self:RefreshUI()
            end
            
            -- #region agent log [BagUpdate Debug]
            self:Debug("BAG_UPDATE: Scan and refresh complete")
            -- #endregion
            
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
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID)
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bagID)
    end
    return 0
end

---Print a debug message
---@param message string The message to print
function WarbandNexus:Debug(message)
    if self.db and self.db.profile.debug then
        self:Print("|cff888888[Debug]|r " .. tostring(message))
    end
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
    self:Debug("ToggleMainWindow called (stub)")
end

function WarbandNexus:OpenDepositQueue()
    -- Implemented in Modules/Banker.lua
    self:Debug("OpenDepositQueue called (stub)")
end

function WarbandNexus:SearchItems(searchTerm)
    -- Implemented in Modules/UI.lua
    self:Debug("SearchItems called: " .. tostring(searchTerm))
end

function WarbandNexus:RefreshUI()
    -- Implemented in Modules/UI.lua
    self:Debug("RefreshUI called (stub)")
end

function WarbandNexus:RefreshPvEUI()
    -- Force refresh of PvE tab if currently visible
    if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "pve" then
        if self.RefreshUI then
            self:RefreshUI()
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
    self:Debug("InitializeConfig called (stub)")
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


