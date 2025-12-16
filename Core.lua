local WarbandNexus = LibStub("AceAddon-3.0"):NewAddon("WarbandNexus", "AceConsole-3.0", "AceEvent-3.0", "AceBucket-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("WarbandNexus", true)

-- Initialize the addon
function WarbandNexus:OnInitialize()
    -- Load database
    self.db = LibStub("AceDB-3.0"):New("WarbandNexusDB", {
        profile = {
            minimap = {
                hide = false,
            },
            autoRepair = false,
            ignoredSlots = {},
            -- Add other default settings here
        },
        global = {
            warbandCache = {}, -- Cache for Warband items
            characters = {},   -- Cache for character banks/bags
        },
    }, true)

    -- Register chat command
    self:RegisterChatCommand("wn", "OnChatCommand")
    self:RegisterChatCommand("warbandnexus", "OnChatCommand")

    -- Initialize modules
    self:InitializeModules()
    
    -- Register Minimap Icon
    self:RegisterMinimapIcon()
end

-- Called when the addon is enabled
function WarbandNexus:OnEnable()
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    
    -- Throttled event for bag updates (runs at most once every 0.2 seconds)
    self:RegisterBucketEvent("BAG_UPDATE", 0.2, "OnBagUpdate")
    
    -- Monitor money changes
    self:RegisterEvent("PLAYER_MONEY", "OnPlayerMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnAccountMoneyChanged") -- For Warband Bank gold
    
    self:Print("Enabled. Type /wn for options.")
end

function WarbandNexus:OnDisable()
    -- Unregister events if necessary
end

-- Chat command handler
function WarbandNexus:OnChatCommand(input)
    if not input or input:trim() == "" then
        -- Default action: Show Main Window (Characters tab)
        self:ShowMainWindow()
    elseif input:trim() == "show" then
        self:ShowMainWindow()
    elseif input:trim() == "options" then
        LibStub("AceConfigDialog-3.0"):Open("WarbandNexus")
    else
        self:Print("Unknown command. Usage: /wn [show|options]")
    end
end

-- Initialize modules
function WarbandNexus:InitializeModules()
    -- Ensure modules are loaded
    if self.GetModule then
        local Scanner = self:GetModule("Scanner", true)
        local Banker = self:GetModule("Banker", true)
        local UI = self:GetModule("UI", true)
        
        if Scanner then Scanner:Enable() end
        if Banker then Banker:Enable() end
        if UI then UI:Enable() end
    end
end

-- Event Handlers
function WarbandNexus:OnBankOpened()
    -- Detect which bank tab is active using the Modern WoW API
    local activeTab = C_Bank.GetActiveBankTab()
    
    -- Determine bank type based on the active tab
    -- Tab 1: Character Bank (Personal)
    -- Tab 2: Account Bank (Warband)
    -- Tab 3: Reagent Bank
    local bankType = "personal" -- Default to personal
    
    if activeTab == 2 then
        bankType = "warband"
    end
    
    -- Open the UI with the Items tab and the correct sub-tab
    self:ShowMainWindowWithItems(bankType)
    
    -- Scan bank content
    local Scanner = self:GetModule("Scanner", true)
    if Scanner then
        if bankType == "warband" then
            Scanner:ScanWarbandBank()
        else
            Scanner:ScanPersonalBank()
        end
    end
end

function WarbandNexus:OnBankClosed()
    local UI = self:GetModule("UI", true)
    if UI then
        UI:HideMainWindow()
    end
end

function WarbandNexus:OnBagUpdate()
    -- Only scan if the frame is open to save performance
    local UI = self:GetModule("UI", true)
    if UI and UI:IsFrameShown() then
        local Scanner = self:GetModule("Scanner", true)
        if Scanner then
            -- Determine what to scan based on context, 
            -- or just scan bags + current bank
            Scanner:ScanBags()
            if C_Bank.IsOpen() then
                 -- Check which bank is actually open
                 local activeTab = C_Bank.GetActiveBankTab()
                 if activeTab == 2 then
                     Scanner:ScanWarbandBank()
                 else
                     Scanner:ScanPersonalBank()
                 end
            end
        end
        -- Refresh UI
        UI:RefreshItemList()
    end
end

function WarbandNexus:OnPlayerMoneyChanged()
    local UI = self:GetModule("UI", true)
    if UI and UI:IsFrameShown() then
        UI:RefreshMoneyDisplay()
        UI:RefreshGoldPopup() -- Refresh popup if open
    end
end

function WarbandNexus:OnAccountMoneyChanged()
    local UI = self:GetModule("UI", true)
    if UI and UI:IsFrameShown() then
        UI:RefreshMoneyDisplay()
        UI:RefreshGoldPopup() -- Refresh popup if open
    end
end

function WarbandNexus:RegisterMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("WarbandNexus", {
        type = "data source",
        text = "Warband Nexus",
        icon = "Interface\\Icons\\Inv_misc_bag_10", -- Placeholder icon
        OnClick = function(_, button)
            if button == "LeftButton" then
                self:ShowMainWindow() -- Minimap click opens Characters tab by default
            elseif button == "RightButton" then
                LibStub("AceConfigDialog-3.0"):Open("WarbandNexus")
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Warband Nexus")
            tooltip:AddLine("Left-Click: Open Window")
            tooltip:AddLine("Right-Click: Options")
        end,
    })

    local icon = LibStub("LibDBIcon-1.0")
    icon:Register("WarbandNexus", LDB, self.db.profile.minimap)
end

-- Wrapper functions to access UI module methods easily
function WarbandNexus:ShowMainWindow()
    local UI = self:GetModule("UI", true)
    if UI then
        UI:ShowMainWindow()
    end
end

function WarbandNexus:ShowMainWindowWithItems(bankType)
    local UI = self:GetModule("UI", true)
    if UI then
        UI:ShowMainWindowWithItems(bankType)
    end
end
