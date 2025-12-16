--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Constants
local DEFAULT_WIDTH = 680
local DEFAULT_HEIGHT = 500
local MIN_WIDTH = 500
local MIN_HEIGHT = 400
local ROW_HEIGHT = 26

-- Modern Color Palette
local COLORS = {
    bg = {0.06, 0.06, 0.08, 0.98},
    bgLight = {0.10, 0.10, 0.12, 1},
    bgCard = {0.08, 0.08, 0.10, 1},
    border = {0.20, 0.20, 0.25, 1},
    borderLight = {0.30, 0.30, 0.38, 1},
    accent = {0.40, 0.20, 0.58, 1},      -- Deep Epic Purple
    accentDark = {0.32, 0.16, 0.46, 1},  -- Darker Purple
    gold = {1.00, 0.82, 0.00, 1},
    green = {0.30, 0.90, 0.30, 1},
    red = {0.95, 0.30, 0.30, 1},
    textBright = {1, 1, 1, 1},
    textNormal = {0.85, 0.85, 0.85, 1},
    textDim = {0.55, 0.55, 0.55, 1},
}

-- Quality colors (hex)
local QUALITY_COLORS = {
    [0] = "9d9d9d",
    [1] = "ffffff",
    [2] = "1eff00",
    [3] = "0070dd",
    [4] = "a335ee",
    [5] = "ff8000",
    [6] = "e6cc80",
    [7] = "00ccff",
}

local mainFrame = nil
local goldTransferFrame = nil
local currentSearchText = ""
local currentTab = "chars" -- Default to Characters tab

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
            self.balanceText:SetText("Your Gold: " .. GetCoinTextureString(playerBalance))
        else
            self.titleText:SetText("Withdraw from Warband Bank")
            self.balanceText:SetText("Warband Bank: " .. GetCoinTextureString(warbandBalance))
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
-- HELPERS
--============================================================================
local function GetQualityHex(quality)
    return QUALITY_COLORS[quality] or "ffffff"
end

local function CreateCard(parent, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(unpack(COLORS.bgCard))
    card:SetBackdropBorderColor(unpack(COLORS.border))
    return card
end

local function FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return goldStr .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

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
    
    -- Set the correct sub-tab based on which bank NPC was clicked
    -- "warband" = Warband Bank NPC, "personal" = Regular Banker NPC
    local subTab = bankType or "warband"
    if self.SetItemsSubTab then
        self:SetItemsSubTab(subTab)
    end
    
    -- Bank open defaults to Items tab
    mainFrame.currentTab = "items"
    
    self:Debug("ShowMainWindowWithItems: Opening Items tab with subTab=" .. subTab)
    self:PopulateContent()
    mainFrame:Show()
    
    -- Sync with WoW BankFrame
    self:SyncBankTab()
end

function WarbandNexus:HideMainWindow()
    -- #region agent log [HideMainWindow]
    self:Debug("HideMainWindow: Called, mainFrame exists=" .. tostring(mainFrame ~= nil))
    -- #endregion
    if mainFrame then
        mainFrame:Hide()
        -- #region agent log [HideMainWindow]
        self:Debug("HideMainWindow: mainFrame hidden")
        -- #endregion
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
    f:SetFrameStrata("HIGH")
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
    
    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText("|cffffffffWarband Nexus|r")
    
    -- Status badge
    local statusBadge = CreateFrame("Frame", nil, header, "BackdropTemplate")
    statusBadge:SetSize(70, 22)
    statusBadge:SetPoint("LEFT", title, "RIGHT", 15, 0)
    statusBadge:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    statusBadge:SetBackdropBorderColor(0, 0, 0, 0.5)
    f.statusBadge = statusBadge
    
    local statusText = statusBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("CENTER")
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
    nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    nav:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    f.nav = nav
    f.currentTab = "chars" -- Start with Characters tab
    f.tabButtons = {}
    
    -- Tab styling function
    local function CreateTabButton(parent, text, key, xOffset)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(90, 30)
        btn:SetPoint("LEFT", xOffset, 0)
        btn.key = key
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        btn.bg = bg
        
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetText(text)
        btn.label = label
        
        btn:SetScript("OnEnter", function(self)
            if self.active then return end
            bg:SetColorTexture(0.25, 0.15, 0.35, 1)  -- Light purple hover
        end)
        btn:SetScript("OnLeave", function(self)
            if self.active then return end
            bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        end)
        btn:SetScript("OnClick", function(self)
            f.currentTab = self.key
            WarbandNexus:PopulateContent()
        end)
        
        return btn
    end
    
    f.tabButtons["chars"] = CreateTabButton(nav, "Characters", "chars", 10)
    f.tabButtons["items"] = CreateTabButton(nav, "Items", "items", 105)
    f.tabButtons["pve"] = CreateTabButton(nav, "PvE", "pve", 200)
    f.tabButtons["stats"] = CreateTabButton(nav, "Statistics", "stats", 295)
    
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
    
    -- Search box (custom implementation)
    local searchFrame = CreateFrame("Frame", nil, nav, "BackdropTemplate")
    searchFrame:SetSize(150, 24)
    searchFrame:SetPoint("RIGHT", settingsBtn, "LEFT", -10, 0)
    searchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    searchFrame:SetBackdropColor(0.1, 0.1, 0.12, 1)
    searchFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    
    local searchBox = CreateFrame("EditBox", "WarbandNexusSearchBox", searchFrame)
    searchBox:SetPoint("TOPLEFT", 8, -4)
    searchBox:SetPoint("BOTTOMRIGHT", -8, 4)
    searchBox:SetFontObject("GameFontHighlight")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Placeholder text
    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholder:SetPoint("LEFT", 0, 0)
    placeholder:SetText("Search...")
    placeholder:SetTextColor(0.5, 0.5, 0.5)
    searchBox.placeholder = placeholder
    
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        -- Show/hide placeholder
        if text and text ~= "" then
            self.placeholder:Hide()
            currentSearchText = text:lower()
        else
            self.placeholder:Show()
            currentSearchText = ""
        end
        WarbandNexus:PopulateContent()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        currentSearchText = ""
        self.placeholder:Show()
        WarbandNexus:PopulateContent()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        searchFrame:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        searchFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    end)
    
    f.searchBox = searchBox
    
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
    
    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", "WarbandNexusScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    f.scroll = scroll
    
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(scroll:GetWidth() - 5)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild
    
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
        -- #region agent log [Classic Bank button click]
        WarbandNexus:Debug("CLASSIC-BTN: Clicked, bankIsOpen=" .. tostring(WarbandNexus.bankIsOpen))
        -- #endregion
        if WarbandNexus.bankIsOpen then
            WarbandNexus:ShowDefaultBankFrame()
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
    
    -- Clear
    for _, child in pairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in pairs({scrollChild:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Update tabs
    for key, btn in pairs(mainFrame.tabButtons) do
        if key == mainFrame.currentTab then
            btn.active = true
            btn.bg:SetColorTexture(unpack(COLORS.accentDark))
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.active = false
            btn.bg:SetColorTexture(0.15, 0.15, 0.18, 1)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    
    -- Draw based on current tab
    local height
    if mainFrame.currentTab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif mainFrame.currentTab == "items" then
        height = self:DrawItemList(scrollChild)
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
    
    local isOpen = self.bankIsOpen
    if isOpen then
        mainFrame.statusBadge:SetBackdropColor(0.2, 0.7, 0.3, 1)
        mainFrame.statusText:SetText("Bank On")
        mainFrame.statusText:SetTextColor(0.4, 1, 0.4)
    else
        mainFrame.statusBadge:SetBackdropColor(0.25, 0.25, 0.28, 1)
        mainFrame.statusText:SetText("Bank Off")
        mainFrame.statusText:SetTextColor(0.6, 0.6, 0.6)
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
        mainFrame.classicBtn:SetEnabled(bankOpen)
        mainFrame.classicBtn:SetAlpha(bankOpen and 1 or 0.5)
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
    
    mainFrame.footerText:SetText(totalCount .. " items cached • Last scan: " .. scanText)
    
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
local expandedGroups = {}

function WarbandNexus:DrawItemList(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 16
    
    self:Debug("DrawItemList: START. subTab=" .. tostring(currentItemsSubTab) .. ", width=" .. width)
    
    -- CRITICAL: Sync WoW bank tab whenever we draw the item list
    -- This ensures right-click deposits go to the correct bank
    if self.bankIsOpen then
        self:SyncBankTab()
    end
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_36")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeBank Items|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Browse and manage your Warband and Personal bank")
    
    yOffset = yOffset + 80
    
    -- Sub-tab buttons (Personal FIRST, then Warband)
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetSize(width, 32)
    tabFrame:SetPoint("TOPLEFT", 8, -yOffset)
    
    -- PERSONAL BANK BUTTON (First/Left)
    local personalBtn = CreateFrame("Button", nil, tabFrame)
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    local personalBg = personalBtn:CreateTexture(nil, "BACKGROUND")
    personalBg:SetAllPoints()
    local isPersonalActive = currentItemsSubTab == "personal"
    personalBg:SetColorTexture(isPersonalActive and 0.20 or 0.08, isPersonalActive and 0.12 or 0.08, isPersonalActive and 0.30 or 0.10, 1)
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText(isPersonalActive and "|cff88ff88Personal Bank|r" or "|cff888888Personal Bank|r")
    
    personalBtn:SetScript("OnClick", function()
        WarbandNexus:Debug("TAB-SWITCH: User clicked Personal sub-tab")
        currentItemsSubTab = "personal"
        WarbandNexus:SyncBankTab()
        WarbandNexus:RefreshUI()
    end)
    personalBtn:SetScript("OnEnter", function(self) personalBg:SetColorTexture(0.25, 0.15, 0.35, 1) end)
    personalBtn:SetScript("OnLeave", function(self)
        local active = currentItemsSubTab == "personal"
        personalBg:SetColorTexture(active and 0.20 or 0.08, active and 0.12 or 0.08, active and 0.30 or 0.10, 1)
    end)
    
    -- WARBAND BANK BUTTON (Second/Right)
    local warbandBtn = CreateFrame("Button", nil, tabFrame)
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    local warbandBg = warbandBtn:CreateTexture(nil, "BACKGROUND")
    warbandBg:SetAllPoints()
    local isWarbandActive = currentItemsSubTab == "warband"
    warbandBg:SetColorTexture(isWarbandActive and 0.20 or 0.08, isWarbandActive and 0.12 or 0.08, isWarbandActive and 0.30 or 0.10, 1)
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText(isWarbandActive and "|cffa335eeWarband Bank|r" or "|cff888888Warband Bank|r")
    
    warbandBtn:SetScript("OnClick", function()
        WarbandNexus:Debug("TAB-SWITCH: User clicked Warband sub-tab")
        currentItemsSubTab = "warband"
        WarbandNexus:SyncBankTab()
        WarbandNexus:RefreshUI()
    end)
    warbandBtn:SetScript("OnEnter", function(self) warbandBg:SetColorTexture(0.25, 0.15, 0.35, 1) end)
    warbandBtn:SetScript("OnLeave", function(self) 
        local active = currentItemsSubTab == "warband"
        warbandBg:SetColorTexture(active and 0.20 or 0.08, active and 0.12 or 0.08, active and 0.30 or 0.10, 1)
    end)
    
    -- Gold controls (Warband Bank ONLY - Personal Bank doesn't support gold storage)
    if currentItemsSubTab == "warband" then
        -- Gold display for Warband Bank
        local goldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -160, 0)
        local warbandGold = WarbandNexus:GetWarbandBankMoney() or 0
        goldDisplay:SetText(GetCoinTextureString(warbandGold))
        
        -- Deposit button
        local depositBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
        depositBtn:SetSize(70, 24)
        depositBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -80, 0)
        depositBtn:SetText("Deposit")
        depositBtn:SetScript("OnClick", function()
            if not WarbandNexus.bankIsOpen then
                WarbandNexus:Print("|cffff6600Bank must be open to deposit gold.|r")
                return
            end
            WarbandNexus:ShowGoldTransferPopup("warband", "deposit")
        end)
        depositBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Deposit Gold", 1, 0.82, 0)
            GameTooltip:AddLine("Deposit gold to Warband Bank", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        depositBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Withdraw button
        local withdrawBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
        withdrawBtn:SetSize(70, 24)
        withdrawBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)
        withdrawBtn:SetText("Withdraw")
        withdrawBtn:SetScript("OnClick", function()
            if not WarbandNexus.bankIsOpen then
                WarbandNexus:Print("|cffff6600Bank must be open to withdraw gold.|r")
                return
            end
            WarbandNexus:ShowGoldTransferPopup("warband", "withdraw")
        end)
        withdrawBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Withdraw Gold", 1, 0.82, 0)
            GameTooltip:AddLine("Withdraw gold from Warband Bank", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        withdrawBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 40
    
    -- Get items based on selected sub-tab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    else
        items = self:GetPersonalBankItems() or {}
    end
    
    -- Apply search filter
    if currentSearchText and currentSearchText ~= "" then
        local filtered = {}
        local searchLower = currentSearchText:lower()
        for _, item in ipairs(items) do
            local itemName = (item.name or ""):lower()
            local itemLink = (item.itemLink or ""):lower()
            if itemName:find(searchLower, 1, true) or itemLink:find(searchLower, 1, true) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end
    
    -- Sort items alphabetically by name
    table.sort(items, function(a, b)
        local nameA = (a.name or ""):lower()
        local nameB = (b.name or ""):lower()
        return nameA < nameB
    end)
    
    -- Show stats bar
    local statsBar = CreateFrame("Frame", nil, parent)
    statsBar:SetSize(width, 24)
    statsBar:SetPoint("TOPLEFT", 8, -yOffset)
    
    local statsBg = statsBar:CreateTexture(nil, "BACKGROUND")
    statsBg:SetAllPoints()
    statsBg:SetColorTexture(0.08, 0.08, 0.10, 1)
    
    local statsText = statsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsText:SetPoint("LEFT", 10, 0)
    local bankStats = self:GetBankStatistics()
    
    if currentItemsSubTab == "warband" then
        local wb = bankStats.warband
        statsText:SetText(string.format("|cffa335ee%d items|r  •  %d/%d slots  •  Last: %s",
            #items, wb.usedSlots, wb.totalSlots,
            wb.lastScan > 0 and date("%H:%M", wb.lastScan) or "Never"))
    else
        local pb = bankStats.personal
        statsText:SetText(string.format("|cff88ff88%d items|r  •  %d/%d slots  •  Last: %s",
            #items, pb.usedSlots, pb.totalSlots,
            pb.lastScan > 0 and date("%H:%M", pb.lastScan) or "Never"))
    end
    statsText:SetTextColor(0.6, 0.6, 0.6)
    
    yOffset = yOffset + 28
    
    if #items == 0 then
        return self:DrawEmptyState(parent, yOffset, currentSearchText ~= "")
    end
    
    -- Group items by type (itemType field from scan)
    local groups = {}
    local groupOrder = {}
    
    for _, item in ipairs(items) do
        local typeName = item.itemType or "Miscellaneous"
        if not groups[typeName] then
            -- Use persisted expanded state, default to true (expanded)
            local groupKey = currentItemsSubTab .. "_" .. typeName
            if expandedGroups[groupKey] == nil then
                expandedGroups[groupKey] = true
            end
            groups[typeName] = { name = typeName, items = {}, groupKey = groupKey }
            table.insert(groupOrder, typeName)
        end
        table.insert(groups[typeName].items, item)
    end
    
    -- Sort group names alphabetically
    table.sort(groupOrder)
    
    -- Draw groups
    local rowIdx = 0
    for _, typeName in ipairs(groupOrder) do
        local group = groups[typeName]
        local isExpanded = expandedGroups[group.groupKey]
        
        -- Group header
        local groupHeader = CreateFrame("Button", nil, parent)
        groupHeader:SetSize(width, 24)
        groupHeader:SetPoint("TOPLEFT", 8, -yOffset)
        
        local ghBg = groupHeader:CreateTexture(nil, "BACKGROUND")
        ghBg:SetAllPoints()
        ghBg:SetColorTexture(0.12, 0.12, 0.16, 1)
        
        local ghArrow = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ghArrow:SetPoint("LEFT", 8, 0)
        ghArrow:SetText(isExpanded and "-" or "+")
        ghArrow:SetTextColor(0.7, 0.7, 0.7)
        
        local ghTitle = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ghTitle:SetPoint("LEFT", 22, 0)
        ghTitle:SetText("|cffffcc00" .. typeName .. "|r |cff888888(" .. #group.items .. ")|r")
        
        -- Click to expand/collapse (uses persisted state)
        local gKey = group.groupKey
        groupHeader:SetScript("OnClick", function()
            expandedGroups[gKey] = not expandedGroups[gKey]
            WarbandNexus:RefreshUI()
        end)
        groupHeader:SetScript("OnEnter", function() ghBg:SetColorTexture(0.16, 0.16, 0.22, 1) end)
        groupHeader:SetScript("OnLeave", function() ghBg:SetColorTexture(0.12, 0.12, 0.16, 1) end)
        
        yOffset = yOffset + 26
        
        -- Draw items in this group (if expanded)
        if isExpanded then
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                local i = rowIdx
                
                local row = CreateFrame("Button", nil, parent)
                row:SetSize(width, ROW_HEIGHT)
                row:SetPoint("TOPLEFT", 8, -yOffset)
                row:EnableMouse(true)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                row.bg = bg
                row.idx = i
                
                -- Count (at the beginning)
                local qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                qty:SetPoint("LEFT", 15, 0)
                qty:SetWidth(45)
                qty:SetJustifyH("RIGHT")
                qty:SetText("|cffffff00" .. (item.stackCount or 1) .. "|r")
                
                -- Icon
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(22, 22)
                icon:SetPoint("LEFT", 70, 0)
                icon:SetTexture(item.iconFileID or 134400)
                
                -- Name
                local nameWidth = width - 200
                local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                name:SetPoint("LEFT", 98, 0)
                name:SetWidth(nameWidth)
                name:SetJustifyH("LEFT")
                name:SetWordWrap(false)
                
                local displayName = item.name or item.itemLink or ("Item " .. (item.itemID or "?"))
                name:SetText("|cff" .. GetQualityHex(item.quality) .. displayName .. "|r")
                
                -- Location (clearer text)
                local loc = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                loc:SetPoint("RIGHT", -10, 0)
                loc:SetWidth(60)
                loc:SetJustifyH("RIGHT")
                
                local locText = ""
                if currentItemsSubTab == "warband" then
                    locText = item.tabIndex and ("Tab " .. item.tabIndex) or ""
                else
                    locText = item.bagIndex and ("Bag " .. item.bagIndex) or ""
                end
                loc:SetText(locText)
                loc:SetTextColor(0.5, 0.5, 0.5)
                
                row:SetScript("OnEnter", function(self)
                    bg:SetColorTexture(0.15, 0.15, 0.20, 1)
                    if item.itemLink then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        GameTooltip:AddLine(" ")
                        
                        if WarbandNexus.bankIsOpen then
                            GameTooltip:AddLine("|cff00ff00Right-Click|r Move to bag", 1, 1, 1)
                            if item.stackCount and item.stackCount > 1 then
                                GameTooltip:AddLine("|cff00ff00Shift+Right-Click|r Split stack", 1, 1, 1)
                            end
                            GameTooltip:AddLine("|cff888888Left-Click|r Pick up", 0.7, 0.7, 0.7)
                        else
                            GameTooltip:AddLine("|cffff6600Bank not open|r", 1, 1, 1)
                        end
                        GameTooltip:AddLine("|cff888888Shift+Left-Click|r Link in chat", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    bg:SetColorTexture(self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.09 or 0.06, 1)
                    GameTooltip:Hide()
                end)
                
                -- Helper to get bag/slot IDs
                local function GetItemBagSlot()
                    local bagID, slotID
                    -- #region agent log [GetItemBagSlot Debug]
                    WarbandNexus:Debug("GetItemBagSlot: subTab=" .. tostring(currentItemsSubTab) .. ", tabIndex=" .. tostring(item.tabIndex) .. ", bagIndex=" .. tostring(item.bagIndex) .. ", slotID=" .. tostring(item.slotID))
                    -- #endregion
                    
                    if currentItemsSubTab == "warband" and item.tabIndex then
                        local warbandBags = {
                            Enum.BagIndex.AccountBankTab_1,
                            Enum.BagIndex.AccountBankTab_2,
                            Enum.BagIndex.AccountBankTab_3,
                            Enum.BagIndex.AccountBankTab_4,
                            Enum.BagIndex.AccountBankTab_5,
                        }
                        bagID = warbandBags[item.tabIndex]
                        slotID = item.slotID
                    elseif currentItemsSubTab == "personal" and item.bagIndex then
                        -- Use stored bagID from item data if available
                        if item.actualBagID then
                            bagID = item.actualBagID
                        else
                            -- Use enum-based lookup
                            local personalBags = { 
                                Enum.BagIndex.Bank or -1, 
                                Enum.BagIndex.BankBag_1 or 6, 
                                Enum.BagIndex.BankBag_2 or 7, 
                                Enum.BagIndex.BankBag_3 or 8, 
                                Enum.BagIndex.BankBag_4 or 9, 
                                Enum.BagIndex.BankBag_5 or 10, 
                                Enum.BagIndex.BankBag_6 or 11, 
                                Enum.BagIndex.BankBag_7 or 12 
                            }
                            bagID = personalBags[item.bagIndex]
                        end
                        slotID = item.slotID
                    end
                    -- #region agent log [GetItemBagSlot Debug]
                    WarbandNexus:Debug("GetItemBagSlot: RESULT bagID=" .. tostring(bagID) .. ", slotID=" .. tostring(slotID))
                    -- #endregion
                    return bagID, slotID
                end
                
                -- Click handlers for item interaction (using OnMouseUp for reliable right-click)
                row:SetScript("OnMouseUp", function(self, button)
                    local bagID, slotID = GetItemBagSlot()
                    
                    -- #region agent log [Click Debug]
                    WarbandNexus:Debug("CLICK: button=" .. tostring(button) .. ", bagID=" .. tostring(bagID) .. ", slotID=" .. tostring(slotID))
                    WarbandNexus:Debug("CLICK: bankIsOpen=" .. tostring(WarbandNexus.bankIsOpen) .. ", itemName=" .. tostring(item.name))
                    -- #endregion
                    
                    -- Bank must be open to interact with items
                    local canInteract = WarbandNexus.bankIsOpen
                    
                    -- Left-click: Pick up item or link in chat
                    if button == "LeftButton" then
                        if IsShiftKeyDown() and item.itemLink then
                            ChatEdit_InsertLink(item.itemLink)
                            return
                        end
                        
                        if canInteract and bagID and slotID then
                            C_Container.PickupContainerItem(bagID, slotID)
                        else
                            WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                        end
                    
                    -- Right-click: Move item to bag (UseContainerItem)
                    elseif button == "RightButton" then
                        -- #region agent log [Right-click Debug]
                        WarbandNexus:Debug("RIGHT-CLICK: canInteract=" .. tostring(canInteract))
                        -- #endregion
                        
                        if not canInteract then
                            WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                            return
                        end
                        
                        if not bagID or not slotID then 
                            -- #region agent log [Right-click Debug]
                            WarbandNexus:Debug("RIGHT-CLICK: Missing bagID or slotID, aborting")
                            -- #endregion
                            return 
                        end
                        
                        -- Shift+Right-click: Split stack
                        if IsShiftKeyDown() and item.stackCount and item.stackCount > 1 then
                            -- #region agent log [Right-click Debug]
                            WarbandNexus:Debug("RIGHT-CLICK: Split stack mode")
                            -- #endregion
                            C_Container.PickupContainerItem(bagID, slotID)
                            if OpenStackSplitFrame then
                                OpenStackSplitFrame(item.stackCount, self, "BOTTOMLEFT", "TOPLEFT")
                            end
                        else
                            -- Normal right-click: Move entire stack to bag
                            -- #region agent log [Right-click Debug]
                            WarbandNexus:Debug("RIGHT-CLICK: Moving item from bagID=" .. bagID .. ", slotID=" .. slotID)
                            -- #endregion
                            
                            -- Pick up the item
                            C_Container.PickupContainerItem(bagID, slotID)
                            
                            -- Check if we have an item on cursor
                            local cursorType, cursorItemID = GetCursorInfo()
                            -- #region agent log [Right-click Debug]
                            WarbandNexus:Debug("RIGHT-CLICK: After pickup, cursorType=" .. tostring(cursorType) .. ", itemID=" .. tostring(cursorItemID))
                            -- #endregion
                            
                            if cursorType == "item" then
                                -- Find a free slot in player bags and place item there
                                local placed = false
                                
                                -- #region agent log [Right-click Debug]
                                WarbandNexus:Debug("RIGHT-CLICK: Looking for free slot in bags 0-4")
                                -- #endregion
                                
                                for destBag = 0, 4 do
                                    local numSlots = C_Container.GetContainerNumSlots(destBag) or 0
                                    local freeSlots = C_Container.GetContainerNumFreeSlots(destBag) or 0
                                    
                                    -- #region agent log [Right-click Debug]
                                    WarbandNexus:Debug("RIGHT-CLICK: Bag " .. destBag .. " has " .. freeSlots .. "/" .. numSlots .. " free")
                                    -- #endregion
                                    
                                    if freeSlots > 0 then
                                        -- Find the actual empty slot
                                        for destSlot = 1, numSlots do
                                            local slotInfo = C_Container.GetContainerItemInfo(destBag, destSlot)
                                            if not slotInfo then
                                                -- Empty slot found! Place item here
                                                -- #region agent log [Right-click Debug]
                                                WarbandNexus:Debug("RIGHT-CLICK: Found empty slot at bag=" .. destBag .. ", slot=" .. destSlot)
                                                -- #endregion
                                                
                                                C_Container.PickupContainerItem(destBag, destSlot)
                                                placed = true
                                                
                                                -- #region agent log [Right-click Debug]
                                                local newCursor = GetCursorInfo()
                                                WarbandNexus:Debug("RIGHT-CLICK: After place, cursor=" .. tostring(newCursor))
                                                -- #endregion
                                                break
                                            end
                                        end
                                        if placed then break end
                                    end
                                end
                                
                                if not placed then
                                    ClearCursor()
                                    WarbandNexus:Print("|cffff6600No free bag space!|r")
                                    -- #region agent log [Right-click Debug]
                                    WarbandNexus:Debug("RIGHT-CLICK: No free slot found, cleared cursor")
                                    -- #endregion
                                end
                            else
                                -- #region agent log [Right-click Debug]
                                WarbandNexus:Debug("RIGHT-CLICK: Pickup failed, cursor empty")
                                -- #endregion
                            end
                            
                            -- Fast re-scan and refresh UI
                            C_Timer.After(0.1, function()
                                if not WarbandNexus then return end
                                
                                -- #region agent log [UI Refresh Debug]
                                WarbandNexus:Debug("REFRESH: Re-scanning after item move")
                                -- #endregion
                                
                                -- Re-scan the appropriate bank
                                if currentItemsSubTab == "warband" then
                                    if WarbandNexus.ScanWarbandBank then
                                        WarbandNexus:ScanWarbandBank()
                                    end
                                else
                                    if WarbandNexus.ScanPersonalBank then
                                        WarbandNexus:ScanPersonalBank()
                                    end
                                end
                                
                                -- Then refresh UI
                                if WarbandNexus.RefreshUI then
                                    WarbandNexus:RefreshUI()
                                end
                                
                                -- #region agent log [UI Refresh Debug]
                                WarbandNexus:Debug("REFRESH: Complete")
                                -- #endregion
                            end)
                        end
                    end
                end)
                
                yOffset = yOffset + ROW_HEIGHT + 1
            end  -- for item in group.items
        end  -- if group.expanded
    end  -- for typeName in groupOrder
    
    return yOffset + 20
end

--============================================================================
-- DRAW EMPTY STATE
--============================================================================
function WarbandNexus:DrawEmptyState(parent, startY, isSearch)
    local yOffset = startY + 50
    
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", 0, -yOffset)
    icon:SetTexture(isSearch and "Interface\\Icons\\INV_Misc_Spyglass_02" or "Interface\\Icons\\INV_Misc_Bag_10_Blue")
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    yOffset = yOffset + 60
    
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -yOffset)
    title:SetText(isSearch and "|cff666666No results|r" or "|cff666666No items cached|r")
    yOffset = yOffset + 30
    
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", 0, -yOffset)
    desc:SetTextColor(0.5, 0.5, 0.5)
    desc:SetText(isSearch and ("No items match '" .. currentSearchText .. "'") or "Open your Warband Bank to scan items")
    
    return yOffset + 50
end

--============================================================================
-- DRAW STATISTICS (Modern Design)
--============================================================================
function WarbandNexus:DrawStatistics(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 20
    local cardWidth = (width - 15) / 2
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeAccount Statistics|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Collection progress, gold, and storage overview")
    
    yOffset = yOffset + 80
    
    local stats = self:GetBankStatistics()
    local warbandGold = self:GetWarbandBankMoney() or 0
    local playerGold = GetMoney() or 0
    local depositable = self:GetDepositableGold() or 0
    
    -- Calculate total gold across all characters
    local totalAccountGold = 0
    for charKey, charData in pairs(self.db.global.characters or {}) do
        if charData.gold then
            totalAccountGold = totalAccountGold + charData.gold
        end
    end
    
    -- ===== GOLD CARDS ROW =====
    -- Warband Bank Gold Card
    local goldCard1 = CreateCard(parent, 90)
    goldCard1:SetWidth(cardWidth)
    goldCard1:SetPoint("TOPLEFT", 10, -yOffset)
    
    local gc1Icon = goldCard1:CreateTexture(nil, "ARTWORK")
    gc1Icon:SetSize(36, 36)
    gc1Icon:SetPoint("LEFT", 15, 0)
    gc1Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    
    local gc1Label = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc1Label:SetPoint("TOPLEFT", gc1Icon, "TOPRIGHT", 12, -2)
    gc1Label:SetText("WARBAND BANK")
    gc1Label:SetTextColor(0.6, 0.6, 0.6)
    
    local gc1Value = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    gc1Value:SetPoint("BOTTOMLEFT", gc1Icon, "BOTTOMRIGHT", 12, 0)
    gc1Value:SetText("|cffffd700" .. FormatGold(warbandGold) .. "|r")
    
    local gc1Full = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc1Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc1Full:SetText("")
    gc1Full:SetTextColor(0.5, 0.5, 0.5)
    
    -- Your Gold Card
    local goldCard2 = CreateCard(parent, 90)
    goldCard2:SetWidth(cardWidth)
    goldCard2:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local gc2Icon = goldCard2:CreateTexture(nil, "ARTWORK")
    gc2Icon:SetSize(36, 36)
    gc2Icon:SetPoint("LEFT", 15, 0)
    gc2Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    
    local gc2Label = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc2Label:SetPoint("TOPLEFT", gc2Icon, "TOPRIGHT", 12, -2)
    gc2Label:SetText("CURRENT CHARACTER")
    gc2Label:SetTextColor(0.6, 0.6, 0.6)
    
    local gc2Value = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    gc2Value:SetPoint("BOTTOMLEFT", gc2Icon, "BOTTOMRIGHT", 12, 0)
    gc2Value:SetText("|cffffff00" .. FormatGold(playerGold) .. "|r")
    
    local gc2Full = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc2Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc2Full:SetText("|cff888888Total: " .. FormatGold(totalAccountGold) .. "|r")
    gc2Full:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== COLLECTION STATS TITLE =====
    local collectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    collectionTitle:SetPoint("TOPLEFT", 15, -yOffset)
    collectionTitle:SetText("|cffa335eeCollection Progress|r")
    
    yOffset = yOffset + 30
    
    -- ===== PLAYER STATS CARDS =====
    -- TWW Note: Achievements are now account-wide (warband), no separate character score
    local achievementPoints = GetTotalAchievementPoints() or 0
    
    -- Calculate card width for 3 cards in a row
    -- Formula: (Total width - left margin - right margin - total spacing) / 3
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Get mount count using proper API
    local numCollectedMounts = 0
    local numTotalMounts = 0
    if C_MountJournal then
        local mountIDs = C_MountJournal.GetMountIDs()
        numTotalMounts = #mountIDs
        
        -- Count collected mounts
        for _, mountID in ipairs(mountIDs) do
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected then
                numCollectedMounts = numCollectedMounts + 1
            end
        end
    end
    
    -- Get pet count
    local numPets = 0
    local numCollectedPets = 0
    if C_PetJournal then
        C_PetJournal.SetSearchFilter("")
        C_PetJournal.ClearSearchFilter()
        numPets, numCollectedPets = C_PetJournal.GetNumPets()
    end
    
    -- Get toy count
    local numCollectedToys = 0
    local numTotalToys = 0
    if C_ToyBox then
        -- TWW API: Count toys manually
        numTotalToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
        numCollectedToys = C_ToyBox.GetNumLearnedDisplayedToys() or 0
    end
    
    -- Achievement Card (Account-wide since TWW) - Full width
    local achCard = CreateCard(parent, 90)
    achCard:SetPoint("TOPLEFT", 10, -yOffset)
    achCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local achIcon = achCard:CreateTexture(nil, "ARTWORK")
    achIcon:SetSize(36, 36)
    achIcon:SetPoint("LEFT", 15, 0)
    achIcon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")
    
    local achLabel = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achLabel:SetPoint("TOPLEFT", achIcon, "TOPRIGHT", 12, -2)
    achLabel:SetText("ACHIEVEMENT POINTS")
    achLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local achValue = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    achValue:SetPoint("BOTTOMLEFT", achIcon, "BOTTOMRIGHT", 12, 0)
    achValue:SetText("|cffffcc00" .. achievementPoints .. "|r")
    
    local achNote = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText("|cff888888Account-wide|r")
    achNote:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- Mount Card (3-column layout)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(threeCardWidth)
    mountCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    local mountIcon = mountCard:CreateTexture(nil, "ARTWORK")
    mountIcon:SetSize(36, 36)
    mountIcon:SetPoint("LEFT", 15, 0)
    mountIcon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    
    local mountLabel = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountLabel:SetPoint("TOPLEFT", mountIcon, "TOPRIGHT", 12, -2)
    mountLabel:SetText("MOUNTS COLLECTED")
    mountLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local mountValue = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mountValue:SetPoint("BOTTOMLEFT", mountIcon, "BOTTOMRIGHT", 12, 0)
    mountValue:SetText("|cff0099ff" .. numCollectedMounts .. "/" .. numTotalMounts .. "|r")
    
    local mountNote = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText("|cff888888Account-wide|r")
    mountNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Pet Card (Center)
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    local petIcon = petCard:CreateTexture(nil, "ARTWORK")
    petIcon:SetSize(36, 36)
    petIcon:SetPoint("LEFT", 15, 0)
    petIcon:SetTexture("Interface\\Icons\\INV_Box_PetCarrier_01")
    
    local petLabel = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petLabel:SetPoint("TOPLEFT", petIcon, "TOPRIGHT", 12, -2)
    petLabel:SetText("BATTLE PETS")
    petLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local petValue = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    petValue:SetPoint("BOTTOMLEFT", petIcon, "BOTTOMRIGHT", 12, 0)
    petValue:SetText("|cffff69b4" .. numCollectedPets .. "/" .. numPets .. "|r")
    
    local petNote = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petNote:SetPoint("BOTTOMRIGHT", -10, 10)
    petNote:SetText("|cff888888Account-wide|r")
    petNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Toys Card (Right)
    local toyCard = CreateCard(parent, 90)
    toyCard:SetWidth(threeCardWidth)
    toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
    -- Also anchor to right to ensure it fills the space
    toyCard:SetPoint("RIGHT", -rightMargin, 0)
    
    local toyIcon = toyCard:CreateTexture(nil, "ARTWORK")
    toyIcon:SetSize(36, 36)
    toyIcon:SetPoint("LEFT", 15, 0)
    toyIcon:SetTexture("Interface\\Icons\\INV_Misc_Toy_10")
    
    local toyLabel = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyLabel:SetPoint("TOPLEFT", toyIcon, "TOPRIGHT", 12, -2)
    toyLabel:SetText("TOYS")
    toyLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local toyValue = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    toyValue:SetPoint("BOTTOMLEFT", toyIcon, "BOTTOMRIGHT", 12, 0)
    toyValue:SetText("|cffff66ff" .. numCollectedToys .. "/" .. numTotalToys .. "|r")
    
    local toyNote = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText("|cff888888Account-wide|r")
    toyNote:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 120)
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = storageCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    stTitle:SetText("|cffa335eeStorage Overview|r")
    
    -- Stats grid
    local function AddStat(parent, label, value, x, y, color)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.6, 0.6, 0.6)
        
        local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        v:SetPoint("TOPLEFT", x, y - 14)
        v:SetText(value)
        if color then v:SetTextColor(unpack(color)) end
    end
    
    -- Use warband stats from new structure
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local totalSlots = (wb.totalSlots or 0) + (pb.totalSlots or 0)
    local usedSlots = (wb.usedSlots or 0) + (pb.usedSlots or 0)
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0)
    local usedPct = totalSlots > 0 and math.floor((usedSlots / totalSlots) * 100) or 0
    
    AddStat(storageCard, "WARBAND SLOTS", (wb.usedSlots or 0) .. "/" .. (wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, "PERSONAL SLOTS", (pb.usedSlots or 0) .. "/" .. (pb.totalSlots or 0), 160, -40)
    AddStat(storageCard, "TOTAL FREE", tostring(freeSlots), 320, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, "TOTAL ITEMS", tostring((wb.itemCount or 0) + (pb.itemCount or 0)), 420, -40)
    
    -- Progress bar (Warband usage)
    local wbPct = (wb.totalSlots or 0) > 0 and math.floor(((wb.usedSlots or 0) / (wb.totalSlots or 1)) * 100) or 0
    
    local barBg = storageCard:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(storageCard:GetWidth() - 30, 8)
    barBg:SetPoint("BOTTOMLEFT", 15, 15)
    barBg:SetColorTexture(0.2, 0.2, 0.2, 1)
    
    local barFill = storageCard:CreateTexture(nil, "ARTWORK")
    barFill:SetHeight(8)
    barFill:SetPoint("BOTTOMLEFT", 15, 15)
    barFill:SetWidth(math.max(1, (storageCard:GetWidth() - 30) * (wbPct / 100)))
    
    if wbPct > 90 then
        barFill:SetColorTexture(0.9, 0.3, 0.3, 1)
    elseif wbPct > 70 then
        barFill:SetColorTexture(0.9, 0.7, 0.2, 1)
    else
        barFill:SetColorTexture(0, 0.8, 0.9, 1)  -- Cyan for warband
    end
    
    yOffset = yOffset + 130
    
    -- Last scan info
    local wbScan = wb.lastScan or 0
    local pbScan = pb.lastScan or 0
    local scanInfo = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanInfo:SetPoint("TOPLEFT", 15, -yOffset)
    scanInfo:SetTextColor(0.4, 0.4, 0.4)
    
    local scanText = ""
    if wbScan > 0 then
        scanText = "Warband: " .. date("%H:%M", wbScan)
    end
    if pbScan > 0 then
        if scanText ~= "" then scanText = scanText .. "  •  " end
        scanText = scanText .. "Personal: " .. date("%H:%M", pbScan)
    end
    if scanText == "" then
        scanText = "Never scanned - visit a banker to scan"
    else
        scanText = "Last scan - " .. scanText
    end
    scanInfo:SetText(scanText)
    
    return yOffset + 40
end

--============================================================================
-- DRAW CHARACTER LIST (Main Tab)
--============================================================================
function WarbandNexus:DrawCharacterList(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    -- Title Card
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Character_Human_Female")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeYour Characters|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(#characters .. " characters tracked")
    
    yOffset = yOffset + 80
    
    -- Total gold display
    local totalGold = 0
    for _, char in ipairs(characters) do
        totalGold = totalGold + (char.gold or 0)
    end
    
    local goldCard = CreateCard(parent, 50)
    goldCard:SetPoint("TOPLEFT", 10, -yOffset)
    goldCard:SetPoint("TOPRIGHT", -10, -yOffset)
    goldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    goldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local goldIcon = goldCard:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(28, 28)
    goldIcon:SetPoint("LEFT", 15, 0)
    goldIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    
    local goldLabel = goldCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldLabel:SetPoint("LEFT", goldIcon, "RIGHT", 10, 0)
    goldLabel:SetText("Total Gold: |cffffd700" .. FormatGold(totalGold) .. "|r")
    
    yOffset = yOffset + 60
    
    -- Character list header
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, 28)
    header:SetPoint("TOPLEFT", 10, -yOffset)
    
    local hdrBg = header:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetAllPoints()
    hdrBg:SetColorTexture(0.12, 0.12, 0.15, 1)
    
    local colName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colName:SetPoint("LEFT", 12, 0)
    colName:SetText("CHARACTER")
    colName:SetTextColor(0.6, 0.6, 0.6)
    
    local colLevel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colLevel:SetPoint("LEFT", 200, 0)
    colLevel:SetText("LEVEL")
    colLevel:SetTextColor(0.6, 0.6, 0.6)
    
    local colGold = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colGold:SetPoint("RIGHT", -120, 0)
    colGold:SetText("GOLD")
    colGold:SetTextColor(0.6, 0.6, 0.6)
    
    local colSeen = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colSeen:SetPoint("RIGHT", -20, 0)
    colSeen:SetText("LAST SEEN")
    colSeen:SetTextColor(0.6, 0.6, 0.6)
    
    yOffset = yOffset + 32
    
    -- Check if no characters
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(48, 48)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 30)
        emptyIcon:SetTexture("Interface\\Icons\\Ability_Spy")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText("|cff666666No characters tracked yet|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 115)
        emptyDesc:SetTextColor(0.5, 0.5, 0.5)
        emptyDesc:SetText("Characters are automatically registered on login")
        
        return yOffset + 200
    end
    
    -- Character rows
    for i, char in ipairs(characters) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(width, 36)
        row:SetPoint("TOPLEFT", 10, -yOffset)
        row:EnableMouse(true)
        
        -- Row background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local bgColor = i % 2 == 0 and {0.08, 0.08, 0.10, 1} or {0.05, 0.05, 0.06, 1}
        bg:SetColorTexture(unpack(bgColor))
        row.bgColor = bgColor
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        
        -- Class icon
        local classIcon = row:CreateTexture(nil, "ARTWORK")
        classIcon:SetSize(24, 24)
        classIcon:SetPoint("LEFT", 12, 0)
        local coords = CLASS_ICON_TCOORDS[char.classFile]
        if coords then
            classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            classIcon:SetTexCoord(unpack(coords))
        else
            classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        -- Character name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 44, 0)
        nameText:SetWidth(145)
        nameText:SetJustifyH("LEFT")
        nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name or "Unknown"))
        
        -- Level (in class color)
        local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        levelText:SetPoint("LEFT", 200, 0)
        levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.level or 1))
        
        -- Gold
        local goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldText:SetPoint("RIGHT", -120, 0)
        goldText:SetJustifyH("RIGHT")
        goldText:SetText("|cffffd700" .. FormatGold(char.gold or 0) .. "|r")
        
        -- Last seen
        local lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lastSeenText:SetPoint("RIGHT", -20, 0)
        lastSeenText:SetTextColor(0.5, 0.5, 0.5)
        if char.lastSeen then
            local timeDiff = time() - char.lastSeen
            if timeDiff < 60 then
                lastSeenText:SetText("Just now")
            elseif timeDiff < 3600 then
                lastSeenText:SetText(math.floor(timeDiff / 60) .. "m ago")
            elseif timeDiff < 86400 then
                lastSeenText:SetText(math.floor(timeDiff / 3600) .. "h ago")
            else
                lastSeenText:SetText(math.floor(timeDiff / 86400) .. "d ago")
            end
        else
            lastSeenText:SetText("Unknown")
        end
        
        -- Hover effect
        row:SetScript("OnEnter", function(self)
            bg:SetColorTexture(0.18, 0.18, 0.25, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(char.name or "Unknown", classColor.r, classColor.g, classColor.b)
            GameTooltip:AddLine(char.realm or "", 0.5, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Class:", char.class or "Unknown", 1, 1, 1, classColor.r, classColor.g, classColor.b)
            GameTooltip:AddDoubleLine("Level:", tostring(char.level or 1), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gold:", FormatGold(char.gold or 0), 1, 1, 1, 1, 0.82, 0)
            if char.faction then
                GameTooltip:AddDoubleLine("Faction:", char.faction, 1, 1, 1, 0.7, 0.7, 0.7)
            end
            if char.race then
                GameTooltip:AddDoubleLine("Race:", char.race, 1, 1, 1, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            bg:SetColorTexture(unpack(self.bgColor))
            GameTooltip:Hide()
        end)
        
        yOffset = yOffset + 38
    end
    
    return yOffset + 20
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================
function WarbandNexus:DrawPvEProgress(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eePvE Progress|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Great Vault, Raid Lockouts & Mythic+ across your Warband")
    
    -- Weekly reset timer
    local resetText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetText:SetPoint("RIGHT", -15, 0)
    resetText:SetTextColor(0.3, 0.9, 0.3) -- Green color
    
    -- Calculate time until weekly reset
    local function GetWeeklyResetTime()
        local serverTime = GetServerTime()
        local resetTime
        
        -- Try C_DateAndTime first (modern API)
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
            local secondsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
            if secondsUntil then
                return secondsUntil
            end
        end
        
        -- Fallback: Calculate manually (US reset = Tuesday 15:00 UTC, EU = Wednesday 07:00 UTC)
        local region = GetCVar("portal")
        local resetDay = (region == "EU") and 3 or 2 -- 2=Tuesday, 3=Wednesday
        local resetHour = (region == "EU") and 7 or 15
        
        local currentDate = date("*t", serverTime)
        local currentWeekday = currentDate.wday -- 1=Sunday, 2=Monday, etc.
        
        -- Days until next reset
        local daysUntil = (resetDay - currentWeekday + 7) % 7
        if daysUntil == 0 and currentDate.hour >= resetHour then
            daysUntil = 7
        end
        
        -- Calculate exact reset time
        local nextReset = serverTime + (daysUntil * 86400)
        local nextResetDate = date("*t", nextReset)
        nextResetDate.hour = resetHour
        nextResetDate.min = 0
        nextResetDate.sec = 0
        
        resetTime = time(nextResetDate)
        return resetTime - serverTime
    end
    
    local function FormatResetTime(seconds)
        if not seconds or seconds <= 0 then
            return "Soon"
        end
        
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        
        if days > 0 then
            return string.format("%dd %dh", days, hours)
        elseif hours > 0 then
            return string.format("%dh %dm", hours, mins)
        else
            return string.format("%dm", mins)
        end
    end
    
    -- Update timer
    local secondsUntil = GetWeeklyResetTime()
    resetText:SetText(FormatResetTime(secondsUntil))
    
    -- Refresh every minute
    titleCard:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceUpdate = (self.timeSinceUpdate or 0) + elapsed
        if self.timeSinceUpdate >= 60 then
            self.timeSinceUpdate = 0
            local seconds = GetWeeklyResetTime()
            resetText:SetText(FormatResetTime(seconds))
        end
    end)
    
    yOffset = yOffset + 80
    
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(64, 64)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 50)
        emptyIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        emptyText:SetPoint("TOP", 0, -yOffset - 130)
        emptyText:SetText("|cff666666No Characters Found|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 160)
        emptyDesc:SetTextColor(0.6, 0.6, 0.6)
        emptyDesc:SetText("Log in to any character to start tracking PvE progress")
        
        local emptyHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyHint:SetPoint("TOP", 0, -yOffset - 185)
        emptyHint:SetTextColor(0.5, 0.5, 0.5)
        emptyHint:SetText("Great Vault, Mythic+ and Raid Lockouts will be displayed here")
        
        return yOffset + 240
    end
    
    -- Loop through each character
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        
        -- Character card
        local charCard = CreateCard(parent, 0) -- Height will be set dynamically
        charCard:SetPoint("TOPLEFT", 10, -yOffset)
        charCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local cardYOffset = 12
        
        -- Character header
        local charHeader = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        charHeader:SetPoint("TOPLEFT", 15, -cardYOffset)
        charHeader:SetText(string.format("|cff%02x%02x%02x%s|r |cff888888Lv %d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name, char.level or 1))
        
        -- Last updated time
        local lastSeen = char.lastSeen or 0
        local lastSeenText = ""
        if lastSeen > 0 then
            local diff = time() - lastSeen
            if diff < 60 then
                lastSeenText = "Updated: Just now"
            elseif diff < 3600 then
                lastSeenText = string.format("Updated: %dm ago", math.floor(diff / 60))
            elseif diff < 86400 then
                lastSeenText = string.format("Updated: %dh ago", math.floor(diff / 3600))
            else
                lastSeenText = string.format("Updated: %dd ago", math.floor(diff / 86400))
            end
        else
            lastSeenText = "Never updated"
        end
        
        local lastSeenLabel = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lastSeenLabel:SetPoint("TOPRIGHT", -15, -cardYOffset)
        lastSeenLabel:SetText("|cff888888" .. lastSeenText .. "|r")
        
        cardYOffset = cardYOffset + 25
        
        local pve = char.pve or {}
        
        -- Create three-column layout for symmetrical display
        local columnWidth = (width - 60) / 3  -- 3 equal columns with spacing
        local columnStartY = cardYOffset
        
        -- === COLUMN 1: GREAT VAULT ===
        local vaultX = 15
        local vaultY = columnStartY
        
        local vaultTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vaultTitle:SetPoint("TOPLEFT", vaultX, -vaultY)
        vaultTitle:SetText("|cffffd700Great Vault|r")
        vaultY = vaultY + 22  -- Increased spacing after title
        
        if pve.greatVault and #pve.greatVault > 0 then
            -- Group by type using Enum values
            local vaultByType = {}
            for _, activity in ipairs(pve.greatVault) do
                local typeName = "Unknown"
                local typeNum = activity.type
                
                -- Try Enum first if available, fallback to numeric comparison
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then
                        typeName = "Raid"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then
                        typeName = "M+"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                        typeName = "PvP"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then
                        typeName = "World"
                    end
                else
                    -- Fallback: numeric comparison
                    -- Based on C_WeeklyRewards.ActivityType
                    if typeNum == 1 then typeName = "Raid"
                    elseif typeNum == 2 then typeName = "M+"
                    elseif typeNum == 3 then typeName = "PvP"
                    elseif typeNum == 4 then typeName = "World"
                    end
                end
                
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            -- Display in order: Raid, M+, World, PvP
            local sortedTypes = {"Raid", "M+", "World", "PvP"}
            for _, typeName in ipairs(sortedTypes) do
                local activities = vaultByType[typeName]
                if activities then
                    -- Create label (fixed width for alignment)
                    local label = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    label:SetPoint("TOPLEFT", vaultX + 10, -vaultY)
                    label:SetWidth(50) -- Fixed width for type name
                    label:SetText(typeName .. ":")
                    label:SetTextColor(0.85, 0.85, 0.85)
                    label:SetJustifyH("LEFT")
                    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    
                    -- Create progress display (aligned to the right of label)
                    local progressLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    progressLine:SetPoint("TOPLEFT", vaultX + 60, -vaultY)
                    progressLine:SetWidth(columnWidth - 65)
                    
                    local progressParts = {}
                    for _, a in ipairs(activities) do
                        -- Cap progress at threshold (don't show 3/2, show 2/2)
                        local progress = a.progress or 0
                        local threshold = a.threshold or 0
                        if progress > threshold and threshold > 0 then
                            progress = threshold
                        end
                        
                        local pct = threshold > 0 and (progress / threshold * 100) or 0
                        local color = pct >= 100 and "|cff00ff00" or "|cffffcc00"
                        table.insert(progressParts, string.format("%s%d/%d|r", color, progress, threshold))
                    end
                    progressLine:SetText(table.concat(progressParts, " "))
                    progressLine:SetTextColor(0.85, 0.85, 0.85)
                    progressLine:SetJustifyH("LEFT")
                    progressLine:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    vaultY = vaultY + 17  -- Slightly more spacing between lines
                end
            end
        else
            local noVault = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noVault:SetPoint("TOPLEFT", vaultX + 10, -vaultY)
            noVault:SetText("|cff666666No data|r")
            noVault:SetTextColor(0.5, 0.5, 0.5)
            vaultY = vaultY + 15
        end
        
        -- === COLUMN 2: MYTHIC+ ===
        local mplusX = 15 + columnWidth
        local mplusY = columnStartY
        
        local mplusTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mplusTitle:SetPoint("TOPLEFT", mplusX, -mplusY)
        mplusTitle:SetText("|cffa335eeM+ Keystone|r")
        mplusY = mplusY + 22  -- Increased spacing after title
        
        if pve.mythicPlus and (pve.mythicPlus.keystone or pve.mythicPlus.weeklyBest or pve.mythicPlus.runsThisWeek) then
            -- Current keystone
            if pve.mythicPlus.keystone then
                local keystoneInfo = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                keystoneInfo:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                keystoneInfo:SetWidth(columnWidth - 20)
                keystoneInfo:SetText(string.format("|cffff8000%s +%d|r", 
                    pve.mythicPlus.keystone.name or "Unknown", 
                    pve.mythicPlus.keystone.level or 0))
                keystoneInfo:SetJustifyH("LEFT")
                mplusY = mplusY + 15
            end
            
            -- Weekly stats
            if pve.mythicPlus.weeklyBest and pve.mythicPlus.weeklyBest > 0 then
                local bestLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bestLine:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                bestLine:SetText(string.format("Best: |cff00ff00+%d|r", pve.mythicPlus.weeklyBest))
                bestLine:SetTextColor(0.8, 0.8, 0.8)
                mplusY = mplusY + 15
            end
            
            if pve.mythicPlus.runsThisWeek and pve.mythicPlus.runsThisWeek > 0 then
                local runsLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                runsLine:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                runsLine:SetText(string.format("Runs: |cffa335ee%d|r", pve.mythicPlus.runsThisWeek))
                runsLine:SetTextColor(0.8, 0.8, 0.8)
                mplusY = mplusY + 15
            end
        else
            local noMplus = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noMplus:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
            noMplus:SetText("|cff666666No keystone|r")
            noMplus:SetTextColor(0.5, 0.5, 0.5)
            mplusY = mplusY + 15
        end
        
        -- === COLUMN 3: RAID LOCKOUTS ===
        local lockoutX = 15 + (columnWidth * 2)
        local lockoutY = columnStartY
        
        local lockoutTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockoutTitle:SetPoint("TOPLEFT", lockoutX, -lockoutY)
        lockoutTitle:SetText("|cff0070ddRaid Lockouts|r")
        lockoutY = lockoutY + 24  -- Increased spacing after title
        
        if pve.lockouts and #pve.lockouts > 0 then
            -- Group lockouts by raid name
            local raidGroups = {}
            local raidOrder = {}
            
            for _, lockout in ipairs(pve.lockouts) do
                local raidName = lockout.name or "Unknown"
                raidName = raidName:gsub("%s*%(.*%)%s*$", "")
                raidName = raidName:gsub("%s*%-.*$", "")
                raidName = raidName:gsub("%s+$", ""):gsub("^%s+", "")
                
                if not raidGroups[raidName] then
                    raidGroups[raidName] = {}
                    table.insert(raidOrder, raidName)
                end
                table.insert(raidGroups[raidName], lockout)
            end
            
            -- Collapsible raid grid (3x4 layout)
            local boxWidth = 50
            local boxHeight = 24
            local boxSpacing = 4
            local cols = 4
            local rows = 3
            local maxVisible = cols * rows -- 12 raids visible
            local startIndex = charCard.raidScrollOffset or 0
            
            -- Scroll buttons container
            if #raidOrder > maxVisible then
                if not charCard.scrollLeftBtn then
                    local leftBtn = CreateFrame("Button", nil, charCard, "BackdropTemplate")
                    leftBtn:SetSize(16, (rows * (boxHeight + boxSpacing)) - boxSpacing)
                    leftBtn:SetPoint("TOPLEFT", lockoutX + 10 + (cols * (boxWidth + boxSpacing)), -lockoutY)
                    leftBtn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    leftBtn:SetBackdropColor(0.1, 0.1, 0.12, 1)
                    leftBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
                    
                    local arrow = leftBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    arrow:SetPoint("CENTER")
                    arrow:SetText(">")
                    arrow:SetTextColor(0.7, 0.7, 0.7)
                    
                    leftBtn:SetScript("OnClick", function()
                        charCard.raidScrollOffset = (charCard.raidScrollOffset or 0) + maxVisible
                        if charCard.raidScrollOffset >= #raidOrder then
                            charCard.raidScrollOffset = 0
                        end
                        self:RefreshUI()
                    end)
                    
                    leftBtn:SetScript("OnEnter", function(btn)
                        btn:SetBackdropColor(0.15, 0.15, 0.18, 1)
                    end)
                    leftBtn:SetScript("OnLeave", function(btn)
                        btn:SetBackdropColor(0.1, 0.1, 0.12, 1)
                    end)
                    
                    charCard.scrollLeftBtn = leftBtn
                end
                charCard.scrollLeftBtn:Show()
            elseif charCard.scrollLeftBtn then
                charCard.scrollLeftBtn:Hide()
            end
            
            local raidCount = 0
            for i = startIndex + 1, math.min(startIndex + maxVisible, #raidOrder) do
                local raidName = raidOrder[i]
                local difficulties = raidGroups[raidName]
                
                local col = raidCount % cols
                local row = math.floor(raidCount / cols)
                
                -- Create raid box container
                local raidBar = CreateFrame("Button", nil, charCard, "BackdropTemplate")
                raidBar:SetSize(boxWidth, boxHeight)
                raidBar:SetPoint("TOPLEFT", lockoutX + 10 + (col * (boxWidth + boxSpacing)), -(lockoutY + (row * (boxHeight + boxSpacing))))
                
                raidBar:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                raidBar:SetBackdropColor(0.10, 0.10, 0.12, 1)
                raidBar:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
                
                -- Raid name abbreviated (centered)
                local initials = ""
                for word in raidName:gmatch("%S+") do
                    initials = initials .. word:sub(1, 1)
                    if #initials >= 3 then break end
                end
                
                local nameLabel = raidBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLabel:SetPoint("CENTER", 0, 0)
                nameLabel:SetText(initials:upper())
                nameLabel:SetTextColor(0.8, 0.8, 0.8)
                nameLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                
                -- Expanded state
                raidBar.expanded = false
                raidBar.difficulties = difficulties
                raidBar.raidName = raidName
                    
                -- Click to expand/collapse
                raidBar:SetScript("OnClick", function(self)
                    self.expanded = not self.expanded
                    
                    if self.expanded then
                        -- Show difficulties
                        if not self.diffFrame then
                            local diffFrame = CreateFrame("Frame", nil, self, "BackdropTemplate")
                            diffFrame:SetSize(boxWidth + 14, 38)
                            diffFrame:SetPoint("BOTTOM", self, "TOP", 0, 4)
                            diffFrame:SetBackdrop({
                                bgFile = "Interface\\Buttons\\WHITE8x8",
                                edgeFile = "Interface\\Buttons\\WHITE8x8",
                                edgeSize = 1,
                            })
                            diffFrame:SetBackdropColor(0.08, 0.08, 0.10, 1)
                            diffFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)
                            self.diffFrame = diffFrame
                            
                            -- Map difficulties
                            local diffMap = {L = nil, N = nil, H = nil, M = nil}
                            for _, lockout in ipairs(self.difficulties) do
                                local diffName = lockout.difficultyName or "Normal"
                                if diffName:find("Mythic") then
                                    diffMap.M = lockout
                                elseif diffName:find("Heroic") then
                                    diffMap.H = lockout
                                elseif diffName:find("Raid Finder") or diffName:find("LFR") then
                                    diffMap.L = lockout
                                else
                                    diffMap.N = lockout
                                end
                            end
                            
                            -- 2x2 grid layout: L N / H M (bigger cells)
                            local diffOrder = {
                                {key = "L", x = 0, y = 0, color = {1, 0.5, 0}},
                                {key = "N", x = 32, y = 0, color = {0.3, 0.9, 0.3}},
                                {key = "H", x = 0, y = -19, color = {0, 0.44, 0.87}},
                                {key = "M", x = 32, y = -19, color = {0.64, 0.21, 0.93}}
                            }
                            
                            for i, diff in ipairs(diffOrder) do
                                local lockout = diffMap[diff.key]
                                local cell = CreateFrame("Frame", nil, diffFrame, "BackdropTemplate")
                                cell:SetSize(30, 17)
                                cell:SetPoint("TOPLEFT", diff.x + 2, diff.y - 2)
                                
                                cell:SetBackdrop({
                                    bgFile = "Interface\\Buttons\\WHITE8x8",
                                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                                    edgeSize = 1,
                                })
                                
                                if lockout then
                                    local r, g, b = diff.color[1], diff.color[2], diff.color[3]
                                    cell:SetBackdropColor(r * 0.4, g * 0.4, b * 0.4, 1)
                                    cell:SetBackdropBorderColor(r, g, b, 1)
                                    
                                    local progress = lockout.progress or 0
                                    local total = lockout.total or 0
                                    if progress > total and total > 0 then progress = total end
                                    
                                    local cellText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                    cellText:SetPoint("CENTER", 0, 0)
                                    cellText:SetText(diff.key)
                                    cellText:SetTextColor(r, g, b, 1)
                                    cellText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                                    
                                    -- Tooltip
                                    cell:EnableMouse(true)
                                    cell:SetScript("OnEnter", function(c)
                                        GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
                                        GameTooltip:SetText(self.raidName, 1, 1, 1)
                                        GameTooltip:AddLine(" ")
                                        local diffNames = {L = "LFR", N = "Normal", H = "Heroic", M = "Mythic"}
                                        GameTooltip:AddDoubleLine("Difficulty:", diffNames[diff.key], nil, nil, nil, r, g, b)
                                        local progressPct = total > 0 and (progress / total * 100) or 0
                                        local pc = progress == total and {0, 1, 0} or {1, 1, 0}
                                        GameTooltip:AddDoubleLine("Progress:", string.format("%d/%d (%.0f%%)", progress, total, progressPct), nil, nil, nil, pc[1], pc[2], pc[3])
                                        if lockout.reset then
                                            local timeLeft = lockout.reset - time()
                                            if timeLeft > 0 then
                                                local days = math.floor(timeLeft / 86400)
                                                local hours = math.floor((timeLeft % 86400) / 3600)
                                                local resetStr = days > 0 and string.format("%dd %dh", days, hours) or string.format("%dh", hours)
                                                GameTooltip:AddDoubleLine("Resets in:", resetStr, nil, nil, nil, 1, 1, 1)
                                            end
                                        end
                                        if lockout.extended then
                                            GameTooltip:AddLine(" ")
                                            GameTooltip:AddLine("|cffff8000[Extended]|r", 1, 0.5, 0)
                                        end
                                        GameTooltip:Show()
                                    end)
                                    cell:SetScript("OnLeave", function(c) GameTooltip:Hide() end)
                                else
                                    cell:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
                                    cell:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.5)
                                    local cellText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                    cellText:SetPoint("CENTER", 0, 0)
                                    cellText:SetText(diff.key)
                                    cellText:SetTextColor(0.3, 0.3, 0.3, 0.5)
                                    cellText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
                                end
                            end
                        end
                        self.diffFrame:Show()
                    else
                        -- Hide difficulties
                        if self.diffFrame then
                            self.diffFrame:Hide()
                        end
                    end
                end)
                
                -- Hover highlight
                raidBar:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.15, 0.15, 0.18, 1)
                end)
                raidBar:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.10, 0.10, 0.12, 1)
                end)
                
                raidCount = raidCount + 1
            end
            
            local actualRows = math.ceil(math.min(raidCount, maxVisible) / cols)
            lockoutY = lockoutY + (actualRows * (boxHeight + boxSpacing)) + 5
        else
            local noLockouts = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noLockouts:SetPoint("TOPLEFT", lockoutX + 10, -lockoutY)
            noLockouts:SetText("|cff666666No lockouts|r")
            noLockouts:SetTextColor(0.5, 0.5, 0.5)
            lockoutY = lockoutY + 15
        end
        
        -- Calculate final height (use tallest column)
        local maxColumnHeight = math.max(vaultY, mplusY, lockoutY)
        cardYOffset = maxColumnHeight + 10
        
        -- Set card height
        charCard:SetHeight(cardYOffset)
        yOffset = yOffset + cardYOffset + 10
    end
    
    return yOffset + 20
end

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
        self:Debug("SYNC: Bank not open, skipping")
        return 
    end
    
    self:Debug("SYNC: Syncing WoW BankFrame to match: " .. tostring(currentItemsSubTab))

    local status, err = pcall(function()
        if not BankFrame then 
            self:Debug("SYNC: BankFrame not found")
            return 
        end
        
        -- TWW Tab System:
        -- characterBankTabID = 1 (Personal Bank)
        -- accountBankTabID = 2 (Warband Bank)
        -- Use BankFrame:SetTab(tabID) to switch
        
        local targetTabID
        if currentItemsSubTab == "warband" then
            targetTabID = BankFrame.accountBankTabID or 2
            self:Debug("SYNC: Switching to WARBAND (tabID=" .. targetTabID .. ")")
        else
            targetTabID = BankFrame.characterBankTabID or 1
            self:Debug("SYNC: Switching to PERSONAL (tabID=" .. targetTabID .. ")")
        end
        
        -- Primary method: Use SetTab function
        if BankFrame.SetTab then
            self:Debug("SYNC: Using BankFrame:SetTab(" .. targetTabID .. ")")
            BankFrame:SetTab(targetTabID)
            return
        end
        
        -- Fallback: Try SelectDefaultTab
        if BankFrame.SelectDefaultTab then
            self:Debug("SYNC: Using BankFrame:SelectDefaultTab(" .. targetTabID .. ")")
            BankFrame:SelectDefaultTab(targetTabID)
            return
        end
        
        -- Fallback: Try GetTabButton and click it
        if BankFrame.GetTabButton then
            local tabButton = BankFrame:GetTabButton(targetTabID)
            if tabButton and tabButton.Click then
                self:Debug("SYNC: Clicking tab button from GetTabButton")
                tabButton:Click()
                return
            end
        end
        
        self:Debug("SYNC: No suitable method found to switch tabs!")
    end)

    if not status then
        self:Debug("SYNC ERROR: " .. tostring(err))
    end
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
