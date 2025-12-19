--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Import shared UI components from SharedWidgets
local COLORS = ns.UI_COLORS
local QUALITY_COLORS = ns.UI_QUALITY_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local GetTypeIcon = ns.UI_GetTypeIcon
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseItemRow = ns.UI_ReleaseItemRow
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date

-- Constants
local DEFAULT_WIDTH = 680
local DEFAULT_HEIGHT = 500
local MIN_WIDTH = 500
local MIN_HEIGHT = 400
local ROW_HEIGHT = 26

local mainFrame = nil
local goldTransferFrame = nil
local currentTab = "chars" -- Default to Characters tab
local currentItemsSubTab = "warband" -- Default to Warband Bank
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Search text state (exposed to namespace for sub-modules to access directly)
ns.itemsSearchText = ""
ns.storageSearchText = ""

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_SetItemsSubTab = function(val)
    currentItemsSubTab = val
    -- CRITICAL: Sync WoW's BankFrame tab when switching sub-tabs
    if WarbandNexus and WarbandNexus.SyncBankTab then
        WarbandNexus:SyncBankTab()
    end
end
ns.UI_GetItemsSearchText = function() return ns.itemsSearchText end
ns.UI_GetStorageSearchText = function() return ns.storageSearchText end
ns.UI_GetExpandedGroups = function() return expandedGroups end

--============================================================================
-- Gold Transfer Popup
--============================================================================

local function CreateGoldTransferPopup()
    if goldTransferFrame then return goldTransferFrame end
    
    local frame = CreateFrame("Frame", "WarbandNexusGoldTransfer", UIParent, "BackdropTemplate")
    frame:SetSize(340, 200)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    titleBar:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    titleBar:SetBackdropColor(0.12, 0.12, 0.15, 1)
    
    -- Title text
    frame.titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.titleText:SetPoint("LEFT", 12, 0)
    frame.titleText:SetTextColor(1, 0.82, 0, 1)
    frame.titleText:SetText("Gold Transfer")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -6, 0)
    closeBtn:SetNormalFontObject("GameFontNormalLarge")
    closeBtn:SetText("x")
    closeBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.7, 0.7, 0.7) end)
    
    -- Balance display
    frame.balanceText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.balanceText:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)
    frame.balanceText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Input row - horizontal layout with fixed positions
    local inputRow = CreateFrame("Frame", nil, frame)
    inputRow:SetSize(300, 45)
    inputRow:SetPoint("TOP", frame.balanceText, "BOTTOM", 0, -8)
    
    -- Gold
    local goldLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldLabel:SetPoint("TOPLEFT", 10, 0)
    goldLabel:SetText("Gold")
    goldLabel:SetTextColor(1, 0.82, 0)
    
    frame.goldInput = CreateFrame("EditBox", nil, inputRow, "InputBoxTemplate")
    frame.goldInput:SetSize(90, 22)
    frame.goldInput:SetPoint("TOPLEFT", 10, -14)
    frame.goldInput:SetAutoFocus(false)
    frame.goldInput:SetNumeric(true)
    frame.goldInput:SetMaxLetters(7)
    frame.goldInput:SetText("0")
    
    -- Silver
    local silverLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    silverLabel:SetPoint("TOPLEFT", 115, 0)
    silverLabel:SetText("Silver")
    silverLabel:SetTextColor(0.75, 0.75, 0.75)
    
    frame.silverInput = CreateFrame("EditBox", nil, inputRow, "InputBoxTemplate")
    frame.silverInput:SetSize(50, 22)
    frame.silverInput:SetPoint("TOPLEFT", 115, -14)
    frame.silverInput:SetAutoFocus(false)
    frame.silverInput:SetNumeric(true)
    frame.silverInput:SetMaxLetters(2)
    frame.silverInput:SetText("0")
    
    -- Copper
    local copperLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copperLabel:SetPoint("TOPLEFT", 180, 0)
    copperLabel:SetText("Copper")
    copperLabel:SetTextColor(0.72, 0.45, 0.20)
    
    frame.copperInput = CreateFrame("EditBox", nil, inputRow, "InputBoxTemplate")
    frame.copperInput:SetSize(50, 22)
    frame.copperInput:SetPoint("TOPLEFT", 180, -14)
    frame.copperInput:SetAutoFocus(false)
    frame.copperInput:SetNumeric(true)
    frame.copperInput:SetMaxLetters(2)
    frame.copperInput:SetText("0")
    
    -- Quick amount buttons: 10k, 100k, 500k, 1m, All
    local quickFrame = CreateFrame("Frame", nil, frame)
    quickFrame:SetSize(300, 24)
    quickFrame:SetPoint("TOP", inputRow, "BOTTOM", 0, -4)
    
    local quickAmounts = {10000, 100000, 500000, 1000000, "all"}
    local quickLabels = {"10k", "100k", "500k", "1m", "All"}
    local btnWidth = 54
    local spacing = 4
    local totalWidth = (#quickAmounts * btnWidth) + ((#quickAmounts - 1) * spacing)
    local startX = (300 - totalWidth) / 2
    
    frame.quickButtons = {}
    for i, amount in ipairs(quickAmounts) do
        local btn = CreateFrame("Button", nil, quickFrame, "UIPanelButtonTemplate")
        btn:SetSize(btnWidth, 22)
        btn:SetPoint("LEFT", quickFrame, "LEFT", startX + (i-1) * (btnWidth + spacing), 0)
        btn:SetText(quickLabels[i])
        btn.goldAmount = amount
        btn:SetScript("OnClick", function()
            -- Get available gold based on mode
            local availableGold = 0
            if frame.mode == "deposit" then
                availableGold = math.floor(GetMoney() / 10000)
            else
                availableGold = math.floor((WarbandNexus:GetWarbandBankMoney() or 0) / 10000)
            end
            
            local finalAmount
            if amount == "all" then
                finalAmount = availableGold
            else
                finalAmount = math.min(amount, availableGold)
            end
            
            if finalAmount <= 0 then
                WarbandNexus:Print("|cffff6600Not enough gold available.|r")
                return
            end
            
            frame.goldInput:SetText(tostring(finalAmount))
            frame.silverInput:SetText("0")
            frame.copperInput:SetText("0")
        end)
        frame.quickButtons[i] = btn
    end
    
    -- Function to update quick buttons based on available gold
    function frame:UpdateQuickButtons()
        local availableGold = 0
        if self.mode == "deposit" then
            availableGold = math.floor(GetMoney() / 10000)
        else
            availableGold = math.floor((WarbandNexus:GetWarbandBankMoney() or 0) / 10000)
        end
        
        for i, btn in ipairs(self.quickButtons) do
            local amount = btn.goldAmount
            if amount == "all" then
                -- All button always enabled if there's any gold
                if availableGold > 0 then
                    btn:Enable()
                    btn:SetAlpha(1)
                else
                    btn:Disable()
                    btn:SetAlpha(0.5)
                end
            else
                if amount <= availableGold then
                    btn:Enable()
                    btn:SetAlpha(1)
                else
                    btn:Disable()
                    btn:SetAlpha(0.5)
                end
            end
        end
    end
    
    -- Action button container
    local btnFrame = CreateFrame("Frame", nil, frame)
    btnFrame:SetSize(280, 36)
    btnFrame:SetPoint("BOTTOM", 0, 12)
    
    -- Deposit button
    frame.depositBtn = CreateFrame("Button", nil, btnFrame, "UIPanelButtonTemplate")
    frame.depositBtn:SetSize(200, 32)
    frame.depositBtn:SetPoint("CENTER", 0, 0)
    frame.depositBtn:SetText("Deposit")
    frame.depositBtn:SetScript("OnClick", function()
        local gold = tonumber(frame.goldInput:GetText()) or 0
        local silver = tonumber(frame.silverInput:GetText()) or 0
        local copper = tonumber(frame.copperInput:GetText()) or 0
        local totalCopper = (gold * 10000) + (silver * 100) + copper
        
        if totalCopper <= 0 then
            WarbandNexus:Print("|cffff6600Please enter an amount.|r")
            return
        end
        
        WarbandNexus:DepositGoldAmount(totalCopper)
        
        -- Close popup after successful operation
        frame:Hide()
        
        C_Timer.After(0.2, function()
            WarbandNexus:RefreshUI()
        end)
    end)
    
    -- Withdraw button
    frame.withdrawBtn = CreateFrame("Button", nil, btnFrame, "UIPanelButtonTemplate")
    frame.withdrawBtn:SetSize(200, 32)
    frame.withdrawBtn:SetPoint("CENTER", 0, 0)
    frame.withdrawBtn:SetText("Withdraw")
    frame.withdrawBtn:SetScript("OnClick", function()
        local gold = tonumber(frame.goldInput:GetText()) or 0
        local silver = tonumber(frame.silverInput:GetText()) or 0
        local copper = tonumber(frame.copperInput:GetText()) or 0
        local totalCopper = (gold * 10000) + (silver * 100) + copper
        
        if totalCopper <= 0 then
            WarbandNexus:Print("|cffff6600Please enter an amount.|r")
            return
        end
        
        WarbandNexus:WithdrawGoldAmount(totalCopper)
        
        -- Close popup after successful operation
        frame:Hide()
        
        C_Timer.After(0.2, function()
            WarbandNexus:RefreshUI()
        end)
    end)
    
    -- Update balance function (Warband Bank only)
    function frame:UpdateBalance()
        local warbandBalance = WarbandNexus:GetWarbandBankMoney() or 0
        local playerBalance = GetMoney() or 0
        
        if self.mode == "deposit" then
            self.titleText:SetText("Deposit to Warband Bank")
            self.balanceText:SetText(format("Your Gold: %s", GetCoinTextureString(playerBalance)))
        else
            self.titleText:SetText("Withdraw from Warband Bank")
            self.balanceText:SetText(format("Warband Bank: %s", GetCoinTextureString(warbandBalance)))
        end
        
        -- Update quick buttons availability
        if self.UpdateQuickButtons then
            self:UpdateQuickButtons()
        end
    end
    
    -- Show function (Warband Bank only - Personal Bank doesn't support gold)
    function frame:ShowForBank(bankType, mode)
        -- Only Warband Bank supports gold transfer
        if bankType ~= "warband" then
            WarbandNexus:Print("|cffff6600Only Warband Bank supports gold transfer.|r")
            return
        end
        
        self.bankType = "warband"
        self.mode = mode or "deposit"
        self.goldInput:SetText("0")
        self.silverInput:SetText("0")
        self.copperInput:SetText("0")
        self:UpdateBalance()
        
        -- Show only the relevant button
        if self.mode == "deposit" then
            self.depositBtn:Show()
            self.withdrawBtn:Hide()
        else
            self.depositBtn:Hide()
            self.withdrawBtn:Show()
        end
        
        self:Show()
        self.goldInput:SetFocus()
    end
    
    -- ESC to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    
    goldTransferFrame = frame
    return frame
end

-- Public function to show gold transfer popup
function WarbandNexus:ShowGoldTransferPopup(bankType, mode)
    local popup = CreateGoldTransferPopup()
    popup:ShowForBank(bankType, mode)
end

--============================================================================
-- UI-SPECIFIC HELPERS
--============================================================================
-- (Shared helpers are now imported from SharedWidgets at top of file)

--============================================================================
-- MAIN FUNCTIONS
--============================================================================
function WarbandNexus:ToggleMainWindow()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:ShowMainWindow()
    end
end

-- Manual open via /wn show or minimap click -> Opens Characters tab
function WarbandNexus:ShowMainWindow()
    self:Debug("ShowMainWindow: Called (manual open), mainFrame exists=" .. tostring(mainFrame ~= nil))
    
    if not mainFrame then
        self:Debug("ShowMainWindow: Creating new mainFrame")
        mainFrame = self:CreateMainWindow()
    end
    
    -- Manual open defaults to Characters tab
    mainFrame.currentTab = "chars"
    
    self:Debug("ShowMainWindow: PopulateContent with chars tab")
    self:PopulateContent()
    mainFrame:Show()
end

-- Bank open -> Opens Items tab with correct sub-tab based on NPC type
function WarbandNexus:ShowMainWindowWithItems(bankType)
    self:Debug("ShowMainWindowWithItems: Called with bankType=" .. tostring(bankType))
    
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
    end
    
    -- CRITICAL: Match addon's sub-tab to Blizzard's current tab (don't force it!)
    -- Blizzard already chose the correct tab when bank opened
    local subTab = (bankType == "warband") and "warband" or "personal"
    
    -- IMPORTANT: Use direct assignment to avoid triggering SyncBankTab
    -- We're matching Blizzard's choice, not forcing it
    currentItemsSubTab = subTab
    self:Debug("ShowMainWindowWithItems: Matching Blizzard's tab - subTab=" .. subTab)
    
    -- Bank open defaults to Items tab
    mainFrame.currentTab = "items"
    
    self:PopulateContent()
    mainFrame:Show()
    
    -- NO SyncBankTab here! We're following Blizzard's lead, not forcing our choice.
    -- SyncBankTab only runs when USER manually switches tabs inside the addon.
end

function WarbandNexus:HideMainWindow()
    self:Debug("HideMainWindow: Called, mainFrame exists=" .. tostring(mainFrame ~= nil))
    if mainFrame then
        mainFrame:Hide()
        self:Debug("HideMainWindow: mainFrame hidden")
    end
end

--============================================================================
-- CREATE MAIN WINDOW
--============================================================================
function WarbandNexus:CreateMainWindow()
    local savedWidth = self.db and self.db.profile.windowWidth or DEFAULT_WIDTH
    local savedHeight = self.db and self.db.profile.windowHeight or DEFAULT_HEIGHT
    
    -- Main frame
    local f = CreateFrame("Frame", "WarbandNexusFrame", UIParent, "BackdropTemplate")
    f:SetSize(savedWidth, savedHeight)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 1200, 900)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")  -- DIALOG is above HIGH, ensures we're above BankFrame
    f:SetFrameLevel(100)         -- Extra high level for safety
    f:SetClampedToScreen(true)
    
    -- Modern backdrop
    f:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    f:SetBackdropColor(unpack(COLORS.bg))
    f:SetBackdropBorderColor(unpack(COLORS.accent))
    
    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if WarbandNexus.db and WarbandNexus.db.profile then
            WarbandNexus.db.profile.windowWidth = f:GetWidth()
            WarbandNexus.db.profile.windowHeight = f:GetHeight()
        end
        WarbandNexus:PopulateContent()
    end)
    
    -- ===== HEADER BAR =====
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    header:SetBackdropColor(unpack(COLORS.accentDark))

    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")

    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("|cffffffffWarband Nexus|r")
    
    -- Status badge (modern rounded pill badge with NineSlice)
    local statusBadge = CreateFrame("Frame", nil, header)
    statusBadge:SetSize(76, 24)
    statusBadge:SetPoint("LEFT", title, "RIGHT", 12, 0)
    f.statusBadge = statusBadge
    
    -- Background with rounded corners using NineSlice
    local bg = statusBadge:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.7, 0.3, 0.25)
    statusBadge.bg = bg
    
    -- Border using NineSlice for smooth rounded edges
    if statusBadge.SetBorderBlendMode then
        statusBadge:SetBorderBlendMode("ADD")
    end
    
    -- Create rounded border using textures
    local border = CreateFrame("Frame", nil, statusBadge, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropBorderColor(0.2, 0.7, 0.3, 0.6)
    statusBadge.border = border

    local statusText = statusBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("CENTER", 0, 0)
    statusText:SetFont(statusText:GetFont(), 11, "OUTLINE")
    f.statusText = statusText
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetNormalTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    tinsert(UISpecialFrames, "WarbandNexusFrame")
    
    -- ===== NAV BAR =====
    local nav = CreateFrame("Frame", nil, f)
    nav:SetHeight(36)
    nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4) -- 4px gap below header
    nav:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    f.nav = nav
    f.currentTab = "chars" -- Start with Characters tab
    f.tabButtons = {}
    
    -- Tab styling function
    local function CreateTabButton(parent, text, key, xOffset)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(105, 34)  -- Slightly taller for modern look
        btn:SetPoint("LEFT", xOffset, 0)
        btn.key = key

        -- Rounded background using backdrop with rounded edge texture
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
        btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        
        -- Glow overlay for active/hover states
        local glow = btn:CreateTexture(nil, "ARTWORK")
        glow:SetPoint("TOPLEFT", 3, -3)
        glow:SetPoint("BOTTOMRIGHT", -3, 3)
        glow:SetColorTexture(0.6, 0.4, 0.9, 0.15)
        glow:SetAlpha(0)
        btn.glow = glow
        
        -- Active indicator bar (bottom, rounded)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(0.6, 0.4, 0.9, 1)  -- Purple
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(text)
        label:SetFont(label:GetFont(), 12, "")
        btn.label = label

        btn:SetScript("OnEnter", function(self)
            if self.active then return end
            self:SetBackdropColor(0.20, 0.14, 0.28, 1)  -- Purple tint hover
            self:SetBackdropBorderColor(0.6, 0.4, 0.9, 0.8)  -- Purple border
            glow:SetAlpha(0.3)
        end)
        btn:SetScript("OnLeave", function(self)
            if self.active then return end
            self:SetBackdropColor(0.12, 0.12, 0.15, 1)
            self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            glow:SetAlpha(0)
        end)
        btn:SetScript("OnClick", function(self)
            f.currentTab = self.key
            WarbandNexus:PopulateContent()
        end)

        return btn
    end
    
    -- Create tabs with equal spacing (105px width + 5px gap = 110px spacing)
    local tabSpacing = 110
    f.tabButtons["chars"] = CreateTabButton(nav, "Characters", "chars", 10)
    f.tabButtons["items"] = CreateTabButton(nav, "Items", "items", 10 + tabSpacing)
    f.tabButtons["storage"] = CreateTabButton(nav, "Storage", "storage", 10 + tabSpacing * 2)
    f.tabButtons["pve"] = CreateTabButton(nav, "PvE", "pve", 10 + tabSpacing * 3)
    f.tabButtons["stats"] = CreateTabButton(nav, "Statistics", "stats", 10 + tabSpacing * 4)
    
    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, nav)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", nav, "RIGHT", -10, 0)
    settingsBtn:SetNormalTexture("Interface\\BUTTONS\\UI-OptionsButton")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() WarbandNexus:OpenOptions() end)
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Settings")
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- ===== CONTENT AREA =====
    local content = CreateFrame("Frame", nil, f, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "BOTTOMLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 45)
    content:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    content:SetBackdropColor(0.04, 0.04, 0.05, 1)
    content:SetBackdropBorderColor(unpack(COLORS.border))
    f.content = content
    
    -- ===== PERSISTENT SEARCH AREA (for Items & Storage tabs) =====
    -- This area is NEVER cleared/refreshed, only shown/hidden
    local searchArea = CreateFrame("Frame", nil, content)
    searchArea:SetHeight(48) -- Search box (32px) + padding (8+8)
    searchArea:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    searchArea:SetPoint("TOPRIGHT", content, "TOPRIGHT", -24, 0) -- Account for scroll bar
    searchArea:Hide() -- Hidden by default
    f.searchArea = searchArea
    
    -- Scroll frame (dynamically positioned based on whether searchArea is visible)
    local scroll = CreateFrame("ScrollFrame", "WarbandNexusScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0) -- Will be adjusted
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, 4)
    f.scroll = scroll
    
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1) -- Temporary, will be updated
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild
    
    -- Update scrollChild width when scroll frame is resized
    scroll:SetScript("OnSizeChanged", function(self, width, height)
        if scrollChild then
            scrollChild:SetWidth(width)
        end
    end)
    
    -- ===== FOOTER =====
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(35)
    footer:SetPoint("BOTTOMLEFT", 8, 5)
    footer:SetPoint("BOTTOMRIGHT", -8, 5)
    
    local footerText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerText:SetPoint("LEFT", 5, 0)
    footerText:SetTextColor(unpack(COLORS.textDim))
    f.footerText = footerText
    
    -- Action buttons (right side)
    -- Note: Button states are updated in UpdateButtonStates()
    
    local classicBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    classicBtn:SetSize(90, 24)
    classicBtn:SetPoint("RIGHT", -10, 0)
    classicBtn:SetText("Classic Bank")
    classicBtn:SetScript("OnClick", function()
        if WarbandNexus.bankIsOpen then
            -- Enter Classic Bank mode
            WarbandNexus.classicBankMode = true
            
            -- Close addon window
            WarbandNexus:HideMainWindow()
            
            -- Restore classic bank UI to default position
            WarbandNexus:RestoreDefaultBankFrame()
        else
            WarbandNexus:Print("|cffff6600You must be near a banker.|r")
        end
    end)
    classicBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Classic Bank", 1, 1, 1)
        GameTooltip:AddLine("Open the default WoW bank interface", 0.7, 0.7, 0.7)
        if not WarbandNexus.bankIsOpen then
            GameTooltip:AddLine("|cffff6600Requires bank access|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    classicBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.classicBtn = classicBtn
    
    local sortBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    sortBtn:SetSize(55, 24)
    sortBtn:SetPoint("RIGHT", classicBtn, "LEFT", -5, 0)
    sortBtn:SetText("Sort")
    sortBtn:SetScript("OnClick", function()
        if WarbandNexus.bankIsOpen then
            WarbandNexus:SortWarbandBank()
        else
            WarbandNexus:Print("|cffff6600Bank must be open to sort!|r")
        end
    end)
    f.sortBtn = sortBtn
    
    local scanBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    scanBtn:SetSize(55, 24)
    scanBtn:SetPoint("RIGHT", sortBtn, "LEFT", -5, 0)
    scanBtn:SetText("Scan")
    scanBtn:SetScript("OnClick", function()
        local scannedAny = false
        
        if WarbandNexus.bankIsOpen then
            WarbandNexus:ScanPersonalBank()
            scannedAny = true
        end
        
        if WarbandNexus:IsWarbandBankOpen() then
            WarbandNexus:ScanWarbandBank()
            scannedAny = true
        end
        
        if scannedAny then
            WarbandNexus:PopulateContent()
        else
            WarbandNexus:Print("|cffff6600Bank is closed - showing cached data.|r")
        end
    end)
    f.scanBtn = scanBtn
    
    -- Up-to-Date status label (left of Scan button)
    local scanStatus = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanStatus:SetPoint("RIGHT", scanBtn, "LEFT", -10, 0)
    scanStatus:SetText("")
    f.scanStatus = scanStatus
    
    -- Store reference in WarbandNexus for cross-module access
    if not WarbandNexus.UI then
        WarbandNexus.UI = {}
    end
    WarbandNexus.UI.mainFrame = f
    
    f:Hide()
    return f
end

--============================================================================
-- POPULATE CONTENT
--============================================================================
function WarbandNexus:PopulateContent()
    if not mainFrame then return end
    
    local scrollChild = mainFrame.scrollChild
    if not scrollChild then return end
    
    scrollChild:SetWidth(mainFrame.scroll:GetWidth() - 5)
    
    -- PERFORMANCE: Only clear/hide children, don't SetParent(nil)
    for _, child in pairs({scrollChild:GetChildren()}) do
        child:Hide()
    end
    for _, region in pairs({scrollChild:GetRegions()}) do
        region:Hide()
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Update tabs with modern active state (rounded style)
    for key, btn in pairs(mainFrame.tabButtons) do
        if key == mainFrame.currentTab then
            btn.active = true
            btn:SetBackdropColor(0.18, 0.12, 0.24, 1)  -- Darker purple for active
            btn:SetBackdropBorderColor(0.6, 0.4, 0.9, 1)  -- Bright purple border
            btn.label:SetTextColor(1, 1, 1)
            btn.label:SetFont(btn.label:GetFont(), 12, "OUTLINE")
            if btn.glow then
                btn.glow:SetAlpha(0.25)  -- Show glow for active
            end
            if btn.activeBar then
                btn.activeBar:SetAlpha(1)  -- Show active indicator
            end
        else
            btn.active = false
            btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
            btn.label:SetFont(btn.label:GetFont(), 12, "")
            if btn.glow then
                btn.glow:SetAlpha(0)  -- Hide glow
            end
            if btn.activeBar then
                btn.activeBar:SetAlpha(0)  -- Hide active indicator
            end
        end
    end
    
    -- Show/hide searchArea and create persistent search boxes
    local isSearchTab = (mainFrame.currentTab == "items" or mainFrame.currentTab == "storage")
    
    if mainFrame.searchArea then
        if isSearchTab then
            mainFrame.searchArea:Show()
            
            -- Reposition scroll below searchArea
            mainFrame.scroll:ClearAllPoints()
            mainFrame.scroll:SetPoint("TOPLEFT", mainFrame.searchArea, "BOTTOMLEFT", 0, 0)
            mainFrame.scroll:SetPoint("BOTTOMRIGHT", mainFrame.content, "BOTTOMRIGHT", -24, 4)
            
            -- Create persistent search boxes (only once)
            if not mainFrame.persistentSearchBoxes then
                mainFrame.persistentSearchBoxes = {}
                
                local CreateSearchBox = ns.UI_CreateSearchBox
                local width = mainFrame.searchArea:GetWidth() - 20 -- 10px padding each side
                
                -- Items search box
                local itemsSearch, itemsClear = CreateSearchBox(
                    mainFrame.searchArea,
                    width,
                    "Search items...",
                    function(searchText)
                        ns.itemsSearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                itemsSearch:SetPoint("TOPLEFT", 10, -8)
                itemsSearch:Hide()
                mainFrame.persistentSearchBoxes.items = itemsSearch
                
                -- Storage search box
                local storageSearch, storageClear = CreateSearchBox(
                    mainFrame.searchArea,
                    width,
                    "Search storage...",
                    function(searchText)
                        ns.storageSearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                storageSearch:SetPoint("TOPLEFT", 10, -8)
                storageSearch:Hide()
                mainFrame.persistentSearchBoxes.storage = storageSearch
            end
            
            -- Show appropriate search box
            if mainFrame.currentTab == "items" then
                mainFrame.persistentSearchBoxes.items:Show()
                mainFrame.persistentSearchBoxes.storage:Hide()
            else -- storage
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Show()
            end
        else
            mainFrame.searchArea:Hide()
            
            -- Reposition scroll at top
            mainFrame.scroll:ClearAllPoints()
            mainFrame.scroll:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, 0)
            mainFrame.scroll:SetPoint("BOTTOMRIGHT", mainFrame.content, "BOTTOMRIGHT", -24, 4)
            
            -- Hide all search boxes
            if mainFrame.persistentSearchBoxes then
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Hide()
            end
        end
    end
    
    -- Draw based on current tab (search boxes are now in persistent searchArea!)
    local height
    if mainFrame.currentTab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif mainFrame.currentTab == "items" then
        height = self:DrawItemList(scrollChild)
    elseif mainFrame.currentTab == "storage" then
        height = self:DrawStorageTab(scrollChild)
    elseif mainFrame.currentTab == "pve" then
        height = self:DrawPvEProgress(scrollChild)
    elseif mainFrame.currentTab == "stats" then
        height = self:DrawStatistics(scrollChild)
    else
        height = self:DrawCharacterList(scrollChild)
    end
    
    scrollChild:SetHeight(math.max(height, mainFrame.scroll:GetHeight()))
    self:UpdateFooter()
end

--============================================================================
-- UPDATE STATUS
--============================================================================
function WarbandNexus:UpdateStatus()
    if not mainFrame then return end

    -- Check if using another addon (background mode)
    local useOtherAddon = self:IsUsingOtherBankAddon()
    local isOpen = self.bankIsOpen
    
    if useOtherAddon then
        -- Purple badge for "Background Mode" (always cached)
        if mainFrame.statusBadge.bg then
            mainFrame.statusBadge.bg:SetColorTexture(0.3, 0.2, 0.4, 0.25)
        end
        if mainFrame.statusBadge.border then
            mainFrame.statusBadge.border:SetBackdropBorderColor(0.6, 0.4, 0.9, 0.6)
        end
        mainFrame.statusText:SetText("CACHED")
        mainFrame.statusText:SetTextColor(0.8, 0.7, 0.9)
    elseif isOpen then
        -- Green badge for "Bank On" (rounded style)
        if mainFrame.statusBadge.bg then
            mainFrame.statusBadge.bg:SetColorTexture(0.15, 0.6, 0.25, 0.25)
        end
        if mainFrame.statusBadge.border then
            mainFrame.statusBadge.border:SetBackdropBorderColor(0.2, 0.9, 0.3, 0.8)
        end
        mainFrame.statusText:SetText("LIVE")
        mainFrame.statusText:SetTextColor(0.3, 1, 0.4)
    else
        -- Gray badge for "Bank Off" (rounded style)
        if mainFrame.statusBadge.bg then
            mainFrame.statusBadge.bg:SetColorTexture(0.2, 0.2, 0.22, 0.25)
        end
        if mainFrame.statusBadge.border then
            mainFrame.statusBadge.border:SetBackdropBorderColor(0.5, 0.5, 0.54, 0.6)
        end
        mainFrame.statusText:SetText("CACHED")
        mainFrame.statusText:SetTextColor(0.6, 0.6, 0.65)
    end

    -- Update button states based on bank status
    self:UpdateButtonStates()
end

--============================================================================
-- UPDATE BUTTON STATES
--============================================================================
function WarbandNexus:UpdateButtonStates()
    if not mainFrame then return end
    
    local bankOpen = self.bankIsOpen
    
    -- Footer buttons
    if mainFrame.sortBtn then
        mainFrame.sortBtn:SetEnabled(bankOpen)
        mainFrame.sortBtn:SetAlpha(bankOpen and 1 or 0.5)
    end
    
    if mainFrame.scanBtn then
        mainFrame.scanBtn:SetEnabled(bankOpen)
        mainFrame.scanBtn:SetAlpha(bankOpen and 1 or 0.5)
    end
    
    if mainFrame.classicBtn then
        -- Classic Bank butonu her zaman aktif (bank off-screen olduğu için)
        mainFrame.classicBtn:SetEnabled(true)
        mainFrame.classicBtn:SetAlpha(1)
    end
end

--============================================================================
-- UPDATE FOOTER
--============================================================================
function WarbandNexus:UpdateFooter()
    if not mainFrame or not mainFrame.footerText then return end
    
    local stats = self:GetBankStatistics()
    local wbCount = stats.warband and stats.warband.itemCount or 0
    local pbCount = stats.personal and stats.personal.itemCount or 0
    local totalCount = wbCount + pbCount
    
    local wbScan = stats.warband and stats.warband.lastScan or 0
    local pbScan = stats.personal and stats.personal.lastScan or 0
    local lastScan = math.max(wbScan, pbScan)
    local scanText = lastScan > 0 and date("%m/%d %H:%M", lastScan) or "Never"
    
    mainFrame.footerText:SetText(format("%d items cached • Last scan: %s", totalCount, scanText))
    
    -- Update "Up-to-Date" status indicator (next to Scan button)
    if mainFrame.scanStatus then
        -- Check if recently scanned (within 60 seconds while bank is open)
        local isUpToDate = self.bankIsOpen and lastScan > 0 and (time() - lastScan < 60)
        if isUpToDate then
            mainFrame.scanStatus:SetText("|cff00ff00Up-to-Date|r")
        elseif lastScan > 0 then
            mainFrame.scanStatus:SetText("|cffaaaaaa" .. scanText .. "|r")
        else
            mainFrame.scanStatus:SetText("|cffff6600Never Scanned|r")
        end
    end
end

--============================================================================
-- DRAW ITEM LIST
--============================================================================
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
local currentItemsSubTab = "personal"  -- "personal" or "warband"

-- Setter for currentItemsSubTab (called from Core.lua)
function WarbandNexus:SetItemsSubTab(subTab)
    if subTab == "warband" or subTab == "personal" then
        currentItemsSubTab = subTab
        self:Debug("SetItemsSubTab: Set to " .. subTab)
    end
end

function WarbandNexus:GetItemsSubTab()
    return currentItemsSubTab
end

-- Track expanded state for each category (persists across refreshes)
local expandedGroups = {} -- Used by ItemsUI for group expansion state

--============================================================================
-- TAB DRAWING FUNCTIONS (All moved to separate modules)
--============================================================================
-- DrawCharacterList moved to Modules/UI/CharactersUI.lua
-- DrawItemList moved to Modules/UI/ItemsUI.lua
-- DrawEmptyState moved to Modules/UI/ItemsUI.lua
-- DrawStorageTab moved to Modules/UI/StorageUI.lua
-- DrawPvEProgress moved to Modules/UI/PvEUI.lua
-- DrawStatistics moved to Modules/UI/StatisticsUI.lua


--============================================================================
-- REFRESH
--============================================================================
--============================================================================
-- HELPER: SYNC WOW BANK TAB
-- Forces WoW's BankFrame to match our Addon's selected tab
-- This is CRITICAL for right-click item deposits to go to correct bank!
--============================================================================
function WarbandNexus:SyncBankTab()
    if not self.bankIsOpen then 
        -- Silently skip if bank not open (don't spam logs)
        return 
    end
    
    -- Don't sync classic UI tabs if user chose to use another addon
    if self:IsUsingOtherBankAddon() then
        return
    end

    local status, err = pcall(function()
        if not BankFrame then 
            return 
        end
        
        -- TWW Tab System:
        -- characterBankTabID = 1 (Personal Bank)
        -- accountBankTabID = 2 (Warband Bank)
        -- Use BankFrame:SetTab(tabID) to switch
        
        -- CRITICAL FIX: Use namespace getter instead of local variable
        local currentSubTab = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "warband"
        
        local targetTabID
        if currentSubTab == "warband" then
            targetTabID = BankFrame.accountBankTabID or 2
        else
            targetTabID = BankFrame.characterBankTabID or 1
        end
        
        -- Primary method: Use SetTab function
        if BankFrame.SetTab then
            BankFrame:SetTab(targetTabID)
            return
        end
        
        -- Fallback: Try SelectDefaultTab
        if BankFrame.SelectDefaultTab then
            BankFrame:SelectDefaultTab(targetTabID)
            return
        end
        
        -- Fallback: Try GetTabButton and click it
        if BankFrame.GetTabButton then
            local tabButton = BankFrame:GetTabButton(targetTabID)
            if tabButton and tabButton.Click then
                tabButton:Click()
                return
            end
        end
    end)
    
    -- Silently handle errors
end

-- Debug function to dump BankFrame structure
function WarbandNexus:DumpBankFrameInfo()
    self:Print("=== BankFrame Debug Info ===")
    
    if not BankFrame then
        self:Print("BankFrame is nil!")
        return
    end
    
    self:Print("BankFrame exists: " .. tostring(BankFrame:GetName()))
    self:Print("BankFrame:IsShown(): " .. tostring(BankFrame:IsShown()))
    
    -- Check for known properties
    local props = {"selectedTab", "activeTabIndex", "TabSystem", "Tabs", "AccountBankTab", "CharacterBankTab", "BankTab", "WarbandBankTab"}
    for _, prop in ipairs(props) do
        self:Print("  BankFrame." .. prop .. " = " .. tostring(BankFrame[prop]))
    end
    
    -- List children
    self:Print("Children:")
    for i, child in ipairs({BankFrame:GetChildren()}) do
        local name = child:GetName() or "(unnamed)"
        local objType = child:GetObjectType()
        local shown = child:IsShown() and "shown" or "hidden"
        self:Print("  " .. i .. ": " .. name .. " [" .. objType .. "] " .. shown)
    end
    
    -- Check global tab references
    self:Print("Global Tab References:")
    for i = 1, 5 do
        local tabName = "BankFrameTab" .. i
        local tab = _G[tabName]
        if tab then
            self:Print("  " .. tabName .. " exists, shown=" .. tostring(tab:IsShown()))
        else
            self:Print("  " .. tabName .. " = nil")
        end
    end
    
    self:Print("============================")
end

-- Throttled refresh to prevent spam
local lastRefreshTime = 0
local REFRESH_THROTTLE = 0.03 -- Ultra-fast refresh (30ms minimum between updates)

function WarbandNexus:RefreshUI()
    -- Throttle rapid refresh calls
    local now = GetTime()
    if (now - lastRefreshTime) < REFRESH_THROTTLE then
        -- Schedule a delayed refresh instead
        if not self.pendingRefresh then
            self.pendingRefresh = true
            C_Timer.After(REFRESH_THROTTLE, function()
                self.pendingRefresh = false
                WarbandNexus:RefreshUI()
            end)
        end
        return
    end
    lastRefreshTime = now
    
    if mainFrame and mainFrame:IsShown() then
        self:PopulateContent()
        self:SyncBankTab()
    end
end

function WarbandNexus:RefreshMainWindow() self:RefreshUI() end
function WarbandNexus:RefreshMainWindowContent() self:RefreshUI() end
function WarbandNexus:ShowDepositQueueUI() self:Print("Coming soon!") end
function WarbandNexus:RefreshDepositQueueUI() end
