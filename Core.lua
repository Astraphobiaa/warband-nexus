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
local WARBAND_TAB_START = Enum.BagIndex.AccountBankTab_1
local WARBAND_TAB_END = Enum.BagIndex.AccountBankTab_5
local WARBAND_TAB_COUNT = 5

-- Warband Bank Bag IDs (for convenience)
ns.WARBAND_BAGS = {
    Enum.BagIndex.AccountBankTab_1,
    Enum.BagIndex.AccountBankTab_2,
    Enum.BagIndex.AccountBankTab_3,
    Enum.BagIndex.AccountBankTab_4,
    Enum.BagIndex.AccountBankTab_5,
}

-- Export constants
ns.WARBAND_TAB_START = WARBAND_TAB_START
ns.WARBAND_TAB_END = WARBAND_TAB_END
ns.WARBAND_TAB_COUNT = WARBAND_TAB_COUNT

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
        
        -- Scanning settings
        autoScan = true,
        scanDelay = 0.5,
        
        -- Deposit settings
        goldReserve = 0,
        autoDepositReagents = false,
        
        -- Display settings
        showItemLevel = true,
        showItemCount = true,
        highlightQuality = true,
        autoShowUI = true, -- Auto-show UI when bank opens
        
        -- Tab settings (ignored tabs for operations)
        ignoredTabs = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false,
            [5] = false,
        },
    },
    global = {
        -- Warband bank item cache (shared across all characters)
        warbandCache = {},
        
        -- Statistics
        stats = {
            totalScans = 0,
            totalDeposits = 0,
            lastScanTime = 0,
        },
        
        -- Item database for offline viewing
        itemDB = {},
    },
    char = {
        -- Character-specific settings
        depositQueue = {},
        lastKnownGold = 0,
        
        -- Personal bank cache (character-specific)
        personalBankCache = {},
        personalBankStats = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            lastScanTime = 0,
        },
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
    
    -- Initialize LibDataBroker for minimap icon
    self:InitializeDataBroker()
    
    -- Debug print
    self:Debug("OnInitialize complete")
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function WarbandNexus:OnEnable()
    if not self.db.profile.enabled then
        self:Debug("Addon is disabled in settings")
        return
    end
    
    -- Register events
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    self:RegisterEvent("PLAYER_MONEY", "OnPlayerMoneyChanged")
    
    -- Register bucket events for bag updates (throttled)
    self:RegisterBucketEvent("BAG_UPDATE", self.db.profile.scanDelay, "OnBagUpdate")
    
    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
    
    self:Debug("OnEnable complete")
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
        self:Print("  /wn options - " .. L["SLASH_OPTIONS"])
        self:Print("  /wn scan - " .. L["SLASH_SCAN"])
        self:Print("  /wn show - " .. L["SLASH_SHOW"])
        self:Print("  /wn deposit - " .. L["SLASH_DEPOSIT"])
        self:Print("  /wn search <item> - " .. L["SLASH_SEARCH"])
        return
    end
    
    if cmd == "options" or cmd == "config" or cmd == "settings" then
        self:OpenOptions()
    elseif cmd == "scan" then
        self:ScanWarbandBank()
    elseif cmd == "show" or cmd == "toggle" then
        self:ToggleMainWindow()
    elseif cmd == "deposit" then
        self:OpenDepositQueue()
    elseif cmd == "search" then
        local _, searchTerm = self:GetArgs(input, 2)
        self:SearchItems(searchTerm)
    elseif cmd == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        self:Print("Debug mode: " .. (self.db.profile.debug and "ON" or "OFF"))
    else
        self:Print("Unknown command: " .. cmd)
    end
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
    self:Debug("Bank opened")
    
    -- Cancel any pending bank open timers to prevent race conditions
    if self.bankOpenTimer then
        self:CancelTimer(self.bankOpenTimer)
        self.bankOpenTimer = nil
    end
    
    -- Delay slightly to let WoW settle the bank state
    self.bankOpenTimer = self:ScheduleTimer(function()
        self:ProcessBankOpened()
    end, 0.1)
end

--[[
    Process bank opened after a short delay
    This helps avoid race conditions with multiple BANKFRAME_OPENED events
]]
function WarbandNexus:ProcessBankOpened()
    local isWarbandBankOpen = C_Bank and C_Bank.IsOpen and C_Bank.IsOpen(Enum.BankType.Account)
    local isPersonalBankOpen = C_Bank and C_Bank.IsOpen and C_Bank.IsOpen(Enum.BankType.Character)
    
    self:Debug(string.format("ProcessBankOpened: Warband=%s, Personal=%s", 
        tostring(isWarbandBankOpen), tostring(isPersonalBankOpen)))
    
    -- Determine which bank type to prioritize
    -- In WoW 11.0, both may be "open" simultaneously in the unified bank UI
    -- We need to detect which one the player actually interacted with
    local targetBankType = nil
    
    if isWarbandBankOpen and isPersonalBankOpen then
        -- Both are open - check which tab is currently selected in Blizzard UI
        -- Try to detect via the AccountBankPanel visibility
        if AccountBankPanel and AccountBankPanel:IsShown() then
            targetBankType = "warband"
            self:Debug("Detected: AccountBankPanel is shown - selecting Warband")
        elseif BankFrame and BankFrame:IsShown() then
            -- Check if we're on the character bank tab
            targetBankType = "personal"
            self:Debug("Detected: BankFrame shown without AccountBank - selecting Personal")
        else
            -- Fallback: prefer warband if it's accessible
            targetBankType = "warband"
            self:Debug("Fallback: Both open, defaulting to Warband")
        end
    elseif isWarbandBankOpen then
        targetBankType = "warband"
        self:Debug("Only Warband bank is open")
    elseif isPersonalBankOpen then
        targetBankType = "personal"
        self:Debug("Only Personal bank is open")
    else
        self:Debug("No bank detected as open")
        return
    end
    
    -- Store the current bank type for reference
    self.currentBankType = targetBankType
    
    -- Auto-scan based on bank type
    if self.db.profile.autoScan then
        if targetBankType == "warband" then
            self:ScheduleTimer("ScanWarbandBank", 0.2)
        else
            self:ScheduleTimer("ScanPersonalBank", 0.2)
        end
    end
    
    -- Open UI and select appropriate tab
    if self.db.profile.autoShowUI then
        self:ScheduleTimer(function()
            self:ShowMainWindowWithTab(self.currentBankType)
        end, 0.3)
    end
end

function WarbandNexus:OnBankClosed()
    self:Debug("Bank closed")
    
    -- Clear the current bank type
    self.currentBankType = nil
    
    -- Cancel any pending bank timers
    if self.bankOpenTimer then
        self:CancelTimer(self.bankOpenTimer)
        self.bankOpenTimer = nil
    end
end

function WarbandNexus:OnPlayerMoneyChanged()
    self.db.char.lastKnownGold = GetMoney()
    self:Debug("Player money changed: " .. GetCoinTextureString(GetMoney()))
end

---@param bagIDs table Table of bag IDs that were updated
function WarbandNexus:OnBagUpdate(bagIDs)
    -- Check if any Warband bags were updated
    local warbandUpdated = false
    
    for bagID in pairs(bagIDs) do
        if self:IsWarbandBag(bagID) then
            warbandUpdated = true
            break
        end
    end
    
    if warbandUpdated then
        self:Debug("Warband bag updated")
        -- Trigger cache update if bank is open
        if self:IsWarbandBankOpen() then
            self:ScheduleTimer("ScanWarbandBank", 0.1)
        end
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
---@return boolean
function WarbandNexus:IsWarbandBankOpen()
    if C_Bank and C_Bank.IsOpen then
        return C_Bank.IsOpen(Enum.BankType.Account)
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

function WarbandNexus:OpenOptions()
    -- Will be properly implemented in Config.lua
    Settings.OpenToCategory(ADDON_NAME)
end

function WarbandNexus:InitializeConfig()
    -- Implemented in Config.lua
    self:Debug("InitializeConfig called (stub)")
end


