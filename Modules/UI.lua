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
    accent = {0.00, 0.75, 0.95, 1},      -- Cyan
    accentDark = {0.00, 0.55, 0.75, 1},
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
local currentSearchText = ""
local currentTab = "chars" -- Default to Characters tab

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
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    
    if gold >= 1000000 then
        return string.format("%.1fM", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.1fK", gold / 1000)
    else
        return tostring(gold)
    end
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

function WarbandNexus:ShowMainWindow()
    -- #region agent log [ShowMainWindow execution]
    self:Debug("ShowMainWindow: Called, mainFrame exists=" .. tostring(mainFrame ~= nil))
    -- #endregion
    
    if not mainFrame then
        -- #region agent log [ShowMainWindow creating]
        self:Debug("ShowMainWindow: Creating new mainFrame")
        -- #endregion
        mainFrame = self:CreateMainWindow()
    end
    
    -- #region agent log [ShowMainWindow populating]
    self:Debug("ShowMainWindow: PopulateContent and Show")
    -- #endregion
    self:PopulateContent()
    mainFrame:Show()
    
    -- Sync initial tab state with WoW BankFrame
    if mainFrame.currentTab == "items" then
        -- Find the active button and simulate a click to trigger sync logic
        -- But don't cause infinite loop - direct call
        if currentItemsSubTab == "warband" then
            if BankFrame and BankFrame:IsShown() and BankFrameTab3 then
                BankFrameTab3:Click()
                if AccountBankPanel then AccountBankPanel:Show() end
                if BankSlotsFrame then BankSlotsFrame:Hide() end
            end
        else
            if BankFrame and BankFrame:IsShown() and BankFrameTab1 then
                BankFrameTab1:Click()
                if AccountBankPanel then AccountBankPanel:Hide() end
                if BankSlotsFrame then BankSlotsFrame:Show() end
            end
        end
    end
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
    header:SetBackdropColor(0.00, 0.55, 0.75, 1)
    
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
            bg:SetColorTexture(0.20, 0.20, 0.25, 1)
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
            btn.bg:SetColorTexture(0.00, 0.55, 0.75, 1)
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
local currentItemsSubTab = "warband"  -- "warband" or "personal"

-- Track expanded state for each category (persists across refreshes)
local expandedGroups = {}

function WarbandNexus:DrawItemList(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 16
    
    -- Sub-tab buttons (Warband / Personal)
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetSize(width, 32)
    tabFrame:SetPoint("TOPLEFT", 8, -yOffset)
    
    local warbandBtn = CreateFrame("Button", nil, tabFrame)
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", 0, 0)
    
    local warbandBg = warbandBtn:CreateTexture(nil, "BACKGROUND")
    warbandBg:SetAllPoints()
    local isWarbandActive = currentItemsSubTab == "warband"
    -- #region agent log [DrawItemList Debug]
    WarbandNexus:Debug("DrawItemList: isWarbandActive=" .. tostring(isWarbandActive))
    -- #endregion
    warbandBg:SetColorTexture(isWarbandActive and 0.15 or 0.08, isWarbandActive and 0.15 or 0.08, isWarbandActive and 0.20 or 0.10, 1)
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText(isWarbandActive and "|cff00ccffWarband Bank|r" or "|cff888888Warband Bank|r")
    
    warbandBtn:SetScript("OnClick", function()
        currentItemsSubTab = "warband"
        WarbandNexus:RefreshUI() -- This calls SyncBankTab internally
    end)
    warbandBtn:SetScript("OnEnter", function(self) warbandBg:SetColorTexture(0.18, 0.18, 0.25, 1) end)
    warbandBtn:SetScript("OnLeave", function(self) 
        local active = currentItemsSubTab == "warband"
        warbandBg:SetColorTexture(active and 0.15 or 0.08, active and 0.15 or 0.08, active and 0.20 or 0.10, 1)
    end)
    
    local personalBtn = CreateFrame("Button", nil, tabFrame)
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
    
    local personalBg = personalBtn:CreateTexture(nil, "BACKGROUND")
    personalBg:SetAllPoints()
    local isPersonalActive = currentItemsSubTab == "personal"
    personalBg:SetColorTexture(isPersonalActive and 0.15 or 0.08, isPersonalActive and 0.15 or 0.08, isPersonalActive and 0.20 or 0.10, 1)
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText(isPersonalActive and "|cff88ff88Personal Bank|r" or "|cff888888Personal Bank|r")
    
    personalBtn:SetScript("OnClick", function()
        currentItemsSubTab = "personal"
        WarbandNexus:RefreshUI() -- This calls SyncBankTab internally
    end)
    personalBtn:SetScript("OnEnter", function(self) personalBg:SetColorTexture(0.18, 0.18, 0.25, 1) end)
    personalBtn:SetScript("OnLeave", function(self)
        local active = currentItemsSubTab == "personal"
        personalBg:SetColorTexture(active and 0.15 or 0.08, active and 0.15 or 0.08, active and 0.20 or 0.10, 1)
    end)
    
    -- Deposit button (right side)
    local depositBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
    depositBtn:SetSize(70, 24)
    depositBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -80, 0)
    depositBtn:SetText("Deposit")
    depositBtn:SetScript("OnClick", function()
        if not WarbandNexus.bankIsOpen then
            WarbandNexus:Print("|cffff6600Bank must be open to deposit.|r")
            return
        end
        -- Deposit all depositable items
        if currentItemsSubTab == "warband" then
            WarbandNexus:Print("|cffff6600Use the default bank UI to deposit items.|r")
        else
            -- For personal bank, try to deposit reagents
            if C_Container.DepositReagentBank then
                C_Container.DepositReagentBank()
                WarbandNexus:Print("|cff00ff00Reagents deposited to reagent bank.|r")
            end
        end
    end)
    depositBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Deposit", 1, 1, 1)
        GameTooltip:AddLine("Deposit reagents to bank", 0.7, 0.7, 0.7)
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
            WarbandNexus:Print("|cffff6600Bank must be open to withdraw.|r")
            return
        end
        WarbandNexus:Print("|cff888888Right-click items to withdraw them.|r")
    end)
    withdrawBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Withdraw", 1, 1, 1)
        GameTooltip:AddLine("Right-click items in the list to withdraw", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    withdrawBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
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
        statsText:SetText(string.format("|cff00ccff%d items|r  •  %d/%d slots  •  Last: %s",
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
                            
                            -- Re-scan and refresh UI after a short delay
                            C_Timer.After(0.3, function()
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
    
    local stats = self:GetBankStatistics()
    local warbandGold = self:GetWarbandBankMoney() or 0
    local playerGold = GetMoney() or 0
    local depositable = self:GetDepositableGold() or 0
    
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
    gc1Value:SetText("|cffffd700" .. FormatGold(warbandGold) .. "g|r")
    
    local gc1Full = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc1Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc1Full:SetText(GetCoinTextureString(warbandGold))
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
    gc2Label:SetText("YOUR CHARACTER")
    gc2Label:SetTextColor(0.6, 0.6, 0.6)
    
    local gc2Value = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    gc2Value:SetPoint("BOTTOMLEFT", gc2Icon, "BOTTOMRIGHT", 12, 0)
    gc2Value:SetText("|cffffff00" .. FormatGold(playerGold) .. "g|r")
    
    local gc2Full = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc2Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc2Full:SetText(GetCoinTextureString(playerGold))
    gc2Full:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== GOLD TRANSFER CARD =====
    local transferCard = CreateCard(parent, 110)
    transferCard:SetPoint("TOPLEFT", 10, -yOffset)
    transferCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local transferTitle = transferCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    transferTitle:SetPoint("TOPLEFT", 15, -10)
    transferTitle:SetText("|cffffd700Gold Transfer|r")
    
    -- Amount input
    local amountFrame = CreateFrame("Frame", nil, transferCard, "BackdropTemplate")
    amountFrame:SetSize(150, 28)
    amountFrame:SetPoint("TOPLEFT", 15, -35)
    amountFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    amountFrame:SetBackdropColor(0.1, 0.1, 0.12, 1)
    amountFrame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    
    local amountInput = CreateFrame("EditBox", nil, amountFrame)
    amountInput:SetPoint("TOPLEFT", 8, -6)
    amountInput:SetPoint("BOTTOMRIGHT", -8, 6)
    amountInput:SetFontObject("GameFontHighlight")
    amountInput:SetAutoFocus(false)
    amountInput:SetNumeric(true)
    amountInput:SetMaxLetters(10)
    
    local amountPlaceholder = amountInput:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    amountPlaceholder:SetPoint("LEFT", 0, 0)
    amountPlaceholder:SetText("Amount (gold)")
    amountPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    
    amountInput:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then
            amountPlaceholder:Hide()
        else
            amountPlaceholder:Show()
        end
    end)
    amountInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    
    -- Check if bank is open for enabling buttons
    local bankOpen = self.bankIsOpen
    
    -- Deposit button
    local depositBtn = CreateFrame("Button", nil, transferCard, "UIPanelButtonTemplate")
    depositBtn:SetSize(90, 26)
    depositBtn:SetPoint("LEFT", amountFrame, "RIGHT", 10, 0)
    depositBtn:SetText("Deposit")
    depositBtn:SetEnabled(bankOpen)
    if not bankOpen then
        depositBtn:SetAlpha(0.5)
    end
    depositBtn:SetScript("OnClick", function()
        if not WarbandNexus.bankIsOpen then
            WarbandNexus:Print("|cffff6600Bank must be open to deposit!|r")
            return
        end
        local amount = tonumber(amountInput:GetText()) or 0
        if amount <= 0 then
            amount = math.floor(depositable / 10000)
        end
        if amount > 0 then
            local copper = amount * 10000
            WarbandNexus:DepositGoldAmount(copper)
            amountInput:SetText("")
            C_Timer.After(0.5, function()
                WarbandNexus:PopulateContent()
            end)
        end
    end)
    
    -- Withdraw button
    local withdrawBtn = CreateFrame("Button", nil, transferCard, "UIPanelButtonTemplate")
    withdrawBtn:SetSize(90, 26)
    withdrawBtn:SetPoint("LEFT", depositBtn, "RIGHT", 5, 0)
    withdrawBtn:SetText("Withdraw")
    withdrawBtn:SetEnabled(bankOpen)
    if not bankOpen then
        withdrawBtn:SetAlpha(0.5)
    end
    withdrawBtn:SetScript("OnClick", function()
        if not WarbandNexus.bankIsOpen then
            WarbandNexus:Print("|cffff6600Bank must be open to withdraw!|r")
            return
        end
        local amount = tonumber(amountInput:GetText()) or 0
        if amount <= 0 then
            WarbandNexus:Print("|cffff6600Enter an amount to withdraw.|r")
            return
        end
        local copper = amount * 10000
        WarbandNexus:WithdrawGoldAmount(copper)
        amountInput:SetText("")
        C_Timer.After(0.5, function()
            WarbandNexus:PopulateContent()
        end)
    end)
    
    -- Bank status warning
    if not bankOpen then
        local warning = transferCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        warning:SetPoint("TOPRIGHT", -15, -10)
        warning:SetText("|cffff6600Bank Offline|r")
    end
    
    -- Quick buttons row
    local quickLabel = transferCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quickLabel:SetPoint("TOPLEFT", 15, -72)
    quickLabel:SetText("Quick:")
    quickLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local quickAmounts = {100, 1000, 10000, "All"}
    local qx = 55
    for _, amt in ipairs(quickAmounts) do
        local qBtn = CreateFrame("Button", nil, transferCard)
        qBtn:SetSize(50, 20)
        qBtn:SetPoint("TOPLEFT", qx, -70)
        
        local qBg = qBtn:CreateTexture(nil, "BACKGROUND")
        qBg:SetAllPoints()
        qBg:SetColorTexture(0.15, 0.15, 0.18, 1)
        
        local qText = qBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qText:SetPoint("CENTER")
        qText:SetText(amt == "All" and "All" or (amt >= 1000 and (amt/1000) .. "k" or amt .. "g"))
        
        qBtn:SetScript("OnClick", function()
            if amt == "All" then
                amountInput:SetText(math.floor(depositable / 10000))
            else
                amountInput:SetText(amt)
            end
            amountPlaceholder:Hide()
        end)
        qBtn:SetScript("OnEnter", function() qBg:SetColorTexture(0.25, 0.25, 0.30, 1) end)
        qBtn:SetScript("OnLeave", function() qBg:SetColorTexture(0.15, 0.15, 0.18, 1) end)
        
        qx = qx + 55
    end
    
    -- Status info
    local statusInfo = transferCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusInfo:SetPoint("TOPRIGHT", -15, -72)
    statusInfo:SetText("Available: |cff00ff00" .. FormatGold(depositable) .. "g|r")
    statusInfo:SetTextColor(0.7, 0.7, 0.7)
    
    yOffset = yOffset + 120
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 120)
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = storageCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    stTitle:SetText("|cff00ccffStorage Overview|r")
    
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
    titleText:SetPoint("TOPLEFT", titleIcon, "TOPRIGHT", 12, -5)
    titleText:SetText("|cff00ccffYour Characters|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOPLEFT", titleIcon, "TOPRIGHT", 12, -25)
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
    goldLabel:SetText("Total Gold: |cffffd700" .. GetCoinTextureString(totalGold) .. "|r")
    
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
    colGold:SetPoint("LEFT", 280, 0)
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
        goldText:SetPoint("LEFT", 280, 0)
        goldText:SetText("|cffffd700" .. FormatGold(char.gold or 0) .. "g|r")
        
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
            GameTooltip:AddDoubleLine("Gold:", GetCoinTextureString(char.gold or 0), 1, 1, 1, 1, 0.82, 0)
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
    
    -- Title
    local titleCard = CreateCard(parent, 60)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(36, 36)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cff00ccffPvE Progress|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Great Vault, Raid Lockouts & Mythic+ across your Warband")
    
    yOffset = yOffset + 70
    
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(48, 48)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 40)
        emptyIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyText:SetPoint("TOP", 0, -yOffset - 100)
        emptyText:SetText("|cff666666No PvE data available|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 125)
        emptyDesc:SetTextColor(0.5, 0.5, 0.5)
        emptyDesc:SetText("Log in to each character to collect their PvE progress")
        
        return yOffset + 180
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
        charHeader:SetText(string.format("|cff%02x%02x%02x%s|r |cff888888(%d)|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name, char.level or 1))
        
        cardYOffset = cardYOffset + 25
        
        local pve = char.pve or {}
        
        -- === GREAT VAULT ===
        local vaultTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vaultTitle:SetPoint("TOPLEFT", 15, -cardYOffset)
        vaultTitle:SetText("|cffffd700Great Vault|r")
        cardYOffset = cardYOffset + 18
        
        if pve.greatVault and #pve.greatVault > 0 then
            -- Group by type
            local vaultByType = {}
            for _, activity in ipairs(pve.greatVault) do
                local typeName = "Unknown"
                if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                    typeName = "Raid"
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                    typeName = "Dungeons/Delves"
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                    typeName = "World"
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                    typeName = "PvP"
                end
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            for typeName, activities in pairs(vaultByType) do
                local vaultLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                vaultLine:SetPoint("TOPLEFT", 25, -cardYOffset)
                
                local progressParts = {}
                for _, a in ipairs(activities) do
                    local pct = a.threshold > 0 and (a.progress / a.threshold * 100) or 0
                    local color = pct >= 100 and "|cff00ff00" or "|cffffcc00"
                    table.insert(progressParts, string.format("%s%d/%d|r", color, a.progress, a.threshold))
                end
                vaultLine:SetText(typeName .. ": " .. table.concat(progressParts, " | "))
                vaultLine:SetTextColor(0.8, 0.8, 0.8)
                cardYOffset = cardYOffset + 15
            end
        else
            local noVault = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noVault:SetPoint("TOPLEFT", 25, -cardYOffset)
            noVault:SetText("No vault data - log in to update")
            noVault:SetTextColor(0.5, 0.5, 0.5)
            cardYOffset = cardYOffset + 15
        end
        
        cardYOffset = cardYOffset + 8
        
        -- === MYTHIC+ ===
        local mplusTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mplusTitle:SetPoint("TOPLEFT", 15, -cardYOffset)
        mplusTitle:SetText("|cffa335eeM+ Keystone|r")
        cardYOffset = cardYOffset + 18
        
        if pve.mythicPlus then
            local mplusInfo = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            mplusInfo:SetPoint("TOPLEFT", 25, -cardYOffset)
            
            local mplusText = ""
            if pve.mythicPlus.keystone then
                mplusText = string.format("%s +%d", 
                    pve.mythicPlus.keystone.name or "Unknown", 
                    pve.mythicPlus.keystone.level or 0)
            else
                mplusText = "No keystone"
            end
            
            if pve.mythicPlus.weeklyBest and pve.mythicPlus.weeklyBest > 0 then
                mplusText = mplusText .. string.format(" | Weekly Best: +%d", pve.mythicPlus.weeklyBest)
            end
            
            if pve.mythicPlus.runsThisWeek and pve.mythicPlus.runsThisWeek > 0 then
                mplusText = mplusText .. string.format(" | %d runs this week", pve.mythicPlus.runsThisWeek)
            end
            
            mplusInfo:SetText(mplusText)
            mplusInfo:SetTextColor(0.8, 0.8, 0.8)
            cardYOffset = cardYOffset + 15
        else
            local noMplus = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noMplus:SetPoint("TOPLEFT", 25, -cardYOffset)
            noMplus:SetText("No M+ data")
            noMplus:SetTextColor(0.5, 0.5, 0.5)
            cardYOffset = cardYOffset + 15
        end
        
        cardYOffset = cardYOffset + 8
        
        -- === LOCKOUTS ===
        local lockoutTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockoutTitle:SetPoint("TOPLEFT", 15, -cardYOffset)
        lockoutTitle:SetText("|cff0070ddRaid Lockouts|r")
        cardYOffset = cardYOffset + 18
        
        if pve.lockouts and #pve.lockouts > 0 then
            for j, lockout in ipairs(pve.lockouts) do
                if j <= 5 then -- Limit display
                    local lockLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lockLine:SetPoint("TOPLEFT", 25, -cardYOffset)
                    lockLine:SetText(string.format("%s (%s): %d/%d", 
                        lockout.name or "Unknown", 
                        lockout.difficultyName or "Normal",
                        lockout.progress or 0, 
                        lockout.total or 0))
                    lockLine:SetTextColor(0.8, 0.8, 0.8)
                    cardYOffset = cardYOffset + 15
                end
            end
            if #pve.lockouts > 5 then
                local more = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                more:SetPoint("TOPLEFT", 25, -cardYOffset)
                more:SetText("... and " .. (#pve.lockouts - 5) .. " more")
                more:SetTextColor(0.5, 0.5, 0.5)
                cardYOffset = cardYOffset + 15
            end
        else
            local noLockouts = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noLockouts:SetPoint("TOPLEFT", 25, -cardYOffset)
            noLockouts:SetText("No active lockouts")
            noLockouts:SetTextColor(0.5, 0.5, 0.5)
            cardYOffset = cardYOffset + 15
        end
        
        cardYOffset = cardYOffset + 10
        
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
--============================================================================
function WarbandNexus:SyncBankTab()
    if not self.bankIsOpen then return end
    
    -- Critical log: Only show sync attempts
    WarbandNexus:Debug("SYNC: Attempting to switch WoW frame to " .. tostring(currentItemsSubTab))

    pcall(function()
        if not BankFrame then return end
        
        -- Helper to force click
        local function ForceClickTab(tabBtn)
            if tabBtn and tabBtn:IsEnabled() then
                local onClick = tabBtn:GetScript("OnClick")
                if onClick then onClick(tabBtn) else tabBtn:Click() end
            end
        end
        
        if currentItemsSubTab == "warband" then
            -- FORCE WARBAND
            if BankFrameTab3 then ForceClickTab(BankFrameTab3) end
            BankFrame.activeTabIndex = 3
            if PanelTemplates_SetTab then PanelTemplates_SetTab(BankFrame, 3) end
            
            -- Visibility override
            if AccountBankPanel then AccountBankPanel:Show() end
            if BankSlotsFrame then BankSlotsFrame:Hide() end
            if ReagentBankFrame then ReagentBankFrame:Hide() end
            
        else -- personal
            -- FORCE PERSONAL
            if BankFrameTab1 then ForceClickTab(BankFrameTab1) end
            BankFrame.activeTabIndex = 1
            if PanelTemplates_SetTab then PanelTemplates_SetTab(BankFrame, 1) end
            
            -- Visibility override
            if AccountBankPanel then AccountBankPanel:Hide() end
            if BankSlotsFrame then BankSlotsFrame:Show() end
        end
    end)
end

function WarbandNexus:RefreshUI()
    if mainFrame and mainFrame:IsShown() then
        self:PopulateContent()
        
        -- Sync WoW frames whenever we refresh UI (keeps them in sync)
        self:SyncBankTab()
        
        -- Double-tap sync after a tiny delay to override any Blizzard UI auto-updates
        C_Timer.After(0.1, function()
            if WarbandNexus and WarbandNexus.SyncBankTab then
                WarbandNexus:SyncBankTab()
            end
        end)
    end
end

function WarbandNexus:RefreshMainWindow() self:RefreshUI() end
function WarbandNexus:RefreshMainWindowContent() self:RefreshUI() end
function WarbandNexus:ShowDepositQueueUI() self:Print("Coming soon!") end
function WarbandNexus:RefreshDepositQueueUI() end
