--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
-- CRITICAL: FontManager is lazy-loaded to prevent initialization errors
local FontManager  -- Will be set on first access
local L = ns.L

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- Lazy-load FontManager (prevent race conditions)
local function GetFontManager()
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then
            error("FontManager not available in namespace!")
        end
    end
    return FontManager
end

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
local CreateThemedButton = ns.UI_CreateThemedButton
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date

-- Layout Constants (computed dynamically)
local CONTENT_MIN_WIDTH = 1560   -- Characters tab minimum (increased by 17.5% from 1330)
local CONTENT_MIN_HEIGHT = 650  -- Multi-level structures minimum
local ROW_HEIGHT = 26

-- Window size (computed on-demand)
local function GetWindowDimensions()
    -- Get cached values from savedvariables or calculate fresh
    if WarbandNexus.db and WarbandNexus.db.profile.windowWidth then
        local savedWidth = WarbandNexus.db.profile.windowWidth
        local savedHeight = WarbandNexus.db.profile.windowHeight
        
        -- Validate saved values are within bounds
        local screen = WarbandNexus:API_GetScreenInfo()
        local maxWidth = math.floor(screen.width * 0.90)
        local maxHeight = math.floor(screen.height * 0.90)
        
        savedWidth = math.max(CONTENT_MIN_WIDTH, math.min(savedWidth, maxWidth))
        savedHeight = math.max(CONTENT_MIN_HEIGHT, math.min(savedHeight, maxHeight))
        
        return savedWidth, savedHeight
    end
    
    -- First time: calculate optimal size
    local defaultWidth, defaultHeight, maxWidth, maxHeight = 
        WarbandNexus:API_CalculateOptimalWindowSize(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT)
    
    return defaultWidth, defaultHeight
end

local mainFrame = nil
local goldTransferFrame = nil
-- REMOVED: local currentTab - now using mainFrame.currentTab (fixes tab switching bug)
local currentItemsSubTab = "personal" -- Default to Personal Items (Bank + Inventory)
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_SetItemsSubTab = function(val)
    currentItemsSubTab = val
    -- No longer syncing BankFrame tabs (read-only mode)
end
ns.UI_GetExpandedGroups = function() return expandedGroups end
ns.UI_GetExpandAllActive = function() return WarbandNexus.itemsExpandAllActive end

--============================================================================
-- Gold Transfer Popup
--============================================================================

local function CreateGoldTransferPopup()
    if goldTransferFrame then return goldTransferFrame end
    
    local frame = CreateFrame("Frame", "WarbandNexusGoldTransfer", UIParent)
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
    
    -- No backdrop (naked frame)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    
    -- Title text
    frame.titleText = FontManager:CreateFontString(titleBar, "title", "OVERLAY")
    frame.titleText:SetPoint("LEFT", 12, 0)
    frame.titleText:SetTextColor(1, 0.82, 0, 1)
    frame.titleText:SetText((ns.L and ns.L["GOLD_TRANSFER"]) or "Gold Transfer")
    
    -- Close button (Factory pattern with atlas icon)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -6, 0)
    
    -- Apply custom visuals
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(14, 14)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
        end
    end)
    
    -- Balance display
    frame.balanceText = FontManager:CreateFontString(frame, "body", "OVERLAY")
    frame.balanceText:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)
    frame.balanceText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Input row - horizontal layout with fixed positions
    local inputRow = CreateFrame("Frame", nil, frame)
    inputRow:SetSize(300, 45)
    inputRow:SetPoint("TOP", frame.balanceText, "BOTTOM", 0, -8)
    
    -- Gold
    local goldLabel = FontManager:CreateFontString(inputRow, "small", "OVERLAY")
    goldLabel:SetPoint("TOPLEFT", 10, 0)
    goldLabel:SetText((ns.L and ns.L["GOLD_LABEL"]) or "Gold")
    goldLabel:SetTextColor(1, 0.82, 0)
    
    frame.goldInput = CreateFrame("EditBox", nil, inputRow, "InputBoxTemplate")
    frame.goldInput:SetSize(90, 22)
    frame.goldInput:SetPoint("TOPLEFT", 10, -14)
    frame.goldInput:SetAutoFocus(false)
    frame.goldInput:SetNumeric(true)
    frame.goldInput:SetMaxLetters(7)
    frame.goldInput:SetText("0")
    
    -- Silver
    local silverLabel = FontManager:CreateFontString(inputRow, "small", "OVERLAY")
    silverLabel:SetPoint("TOPLEFT", 115, 0)
    silverLabel:SetText((ns.L and ns.L["SILVER_LABEL"]) or "Silver")
    silverLabel:SetTextColor(0.75, 0.75, 0.75)
    
    frame.silverInput = CreateFrame("EditBox", nil, inputRow, "InputBoxTemplate")
    frame.silverInput:SetSize(50, 22)
    frame.silverInput:SetPoint("TOPLEFT", 115, -14)
    frame.silverInput:SetAutoFocus(false)
    frame.silverInput:SetNumeric(true)
    frame.silverInput:SetMaxLetters(2)
    frame.silverInput:SetText("0")
    
    -- Copper
    local copperLabel = FontManager:CreateFontString(inputRow, "small", "OVERLAY")
    copperLabel:SetPoint("TOPLEFT", 180, 0)
    copperLabel:SetText((ns.L and ns.L["COPPER_LABEL"]) or "Copper")
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
        local btn = CreateThemedButton(quickFrame, quickLabels[i], btnWidth)
        btn:SetPoint("LEFT", quickFrame, "LEFT", startX + (i-1) * (btnWidth + spacing), 0)
        btn.goldAmount = amount
        btn:SetScript("OnClick", function()
            -- Get available gold based on mode
            local availableGold = 0
            if frame.mode == "deposit" then
                availableGold = math.floor(GetMoney() / 10000)
            else
                availableGold = math.floor((ns.Utilities:GetWarbandBankMoney() or 0) / 10000)
            end
            
            local finalAmount
            if amount == "all" then
                finalAmount = availableGold
            else
                finalAmount = math.min(amount, availableGold)
            end
            
            if finalAmount <= 0 then
                WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["NOT_ENOUGH_GOLD"]) or "Not enough gold available.") .. "|r")
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
            availableGold = math.floor((ns.Utilities:GetWarbandBankMoney() or 0) / 10000)
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
    frame.depositBtn = CreateThemedButton(btnFrame, (ns.L and ns.L["DEPOSIT"]) or "Deposit", 200)
    frame.depositBtn:SetPoint("CENTER", 0, 0)
    frame.depositBtn:SetScript("OnClick", function()
        local gold = tonumber(frame.goldInput:GetText()) or 0
        local silver = tonumber(frame.silverInput:GetText()) or 0
        local copper = tonumber(frame.copperInput:GetText()) or 0
        local totalCopper = (gold * 10000) + (silver * 100) + copper
        
        if totalCopper <= 0 then
            WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["ENTER_AMOUNT"]) or "Please enter an amount.") .. "|r")
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
    frame.withdrawBtn = CreateThemedButton(btnFrame, (ns.L and ns.L["WITHDRAW"]) or "Withdraw", 200)
    frame.withdrawBtn:SetPoint("CENTER", 0, 0)
    frame.withdrawBtn:SetScript("OnClick", function()
        local gold = tonumber(frame.goldInput:GetText()) or 0
        local silver = tonumber(frame.silverInput:GetText()) or 0
        local copper = tonumber(frame.copperInput:GetText()) or 0
        local totalCopper = (gold * 10000) + (silver * 100) + copper
        
        if totalCopper <= 0 then
            WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["ENTER_AMOUNT"]) or "Please enter an amount.") .. "|r")
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
        local warbandBalance = ns.Utilities:GetWarbandBankMoney() or 0
        local playerBalance = GetMoney() or 0
        
        if self.mode == "deposit" then
            self.titleText:SetText((ns.L and ns.L["DEPOSIT_TO_WARBAND"]) or "Deposit to Warband Bank")
            self.balanceText:SetText(format((ns.L and ns.L["YOUR_GOLD_FORMAT"]) or "Your Gold: %s", WarbandNexus:API_FormatMoney(playerBalance)))
        else
            self.titleText:SetText((ns.L and ns.L["WITHDRAW_FROM_WARBAND"]) or "Withdraw from Warband Bank")
            self.balanceText:SetText(format((ns.L and ns.L["WARBAND_BANK_FORMAT"]) or "Warband Bank: %s", WarbandNexus:API_FormatMoney(warbandBalance)))
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
            WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["ONLY_WARBAND_GOLD"]) or "Only Warband Bank supports gold transfer.") .. "|r")
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

-- Clear all search state on main tab change
local function ClearAllSearchBoxes()
    local SSM = ns.SearchStateManager
    if SSM and SSM.ClearSearch then
        -- Clear all known search IDs
        local tabIds = { "items", "currency", "storage", "reputation", "plans_mount", "plans_pet", "plans_toy", "plans_transmog", "plans_illusion", "plans_title", "plans_achievement" }
        for _, id in ipairs(tabIds) do
            SSM:ClearSearch(id)
        end
    end
    -- Clear My Plans active search
    ns._plansActiveSearch = nil
end

function WarbandNexus:ToggleMainWindow()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
        self.mainFrame = nil  -- Clear reference
    else
        self:ShowMainWindow()
    end
end

-- Manual open via /wn show or minimap click -> Opens Characters tab
function WarbandNexus:ShowMainWindow()
    -- TAINT PROTECTION: Prevent UI manipulation during combat
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not ready. Please wait a moment and try again.")
        -- Try again after 1 second
        C_Timer.After(1.0, function()
            if WarbandNexus and WarbandNexus.ShowMainWindow then
                WarbandNexus:ShowMainWindow()
            end
        end)
        return
    end
    
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
        
        -- GUARD: Check if CreateMainWindow succeeded
        if not mainFrame then
            DebugPrint("|cffff0000[WN UI]|r ERROR: Failed to create main window. See /wn errors for details.")
            return
        end
    end
    
    -- Store reference for external access (FontManager, etc.)
    self.mainFrame = mainFrame
    
    -- Manual open defaults to Characters tab
    mainFrame.currentTab = "chars"
    mainFrame.isMainTabSwitch = true  -- First open = main tab switch
    
    self:PopulateContent()
    mainFrame.isMainTabSwitch = false  -- Reset flag
    mainFrame:Show()
end

-- Bank open -> Opens Items tab with correct sub-tab based on NPC type
-- User must manually open via /wn or minimap button

function WarbandNexus:HideMainWindow()
    if mainFrame then
        mainFrame:Hide()
    end
end

--============================================================================
-- CREATE MAIN WINDOW
--============================================================================
function WarbandNexus:CreateMainWindow()
    -- ZOMBIE FRAME CLEANUP: Check for orphaned frames from failed initialization
    -- If a frame exists in global namespace but we don't have a reference, it's a zombie
    local existingGlobalFrame = _G["WarbandNexusFrame"]
    if existingGlobalFrame then
        -- Check if we already have a valid reference to this frame
        if mainFrame and mainFrame == existingGlobalFrame then
            -- Frame is valid and already created, just return it
            DebugPrint("|cff00ff00[WN UI]|r Main window already exists, reusing.")
            return mainFrame
        else
            -- Zombie frame detected - cleanup and recreate
            DebugPrint("|cffffff00[WN UI]|r WARNING: Zombie frame detected, cleaning up...")
            existingGlobalFrame:Hide()
            existingGlobalFrame:SetParent(nil)
            existingGlobalFrame:ClearAllPoints()
            
            -- Try to properly release the frame
            if existingGlobalFrame.UnregisterAllEvents then
                pcall(function() existingGlobalFrame:UnregisterAllEvents() end)
            end
            
            -- Clear global reference to allow new frame creation
            _G["WarbandNexusFrame"] = nil
        end
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        -- Log error instead of throwing (prevent addon from breaking)
        if self.ErrorLog then
            self.ErrorLog:LogError("CreateMainWindow", "FontManager not initialized", {
                fontManagerExists = ns.FontManager ~= nil,
                createFontStringExists = ns.FontManager and ns.FontManager.CreateFontString ~= nil,
            })
        end
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not initialized. Cannot create UI.")
        return nil
    end
    
    -- Update local reference (for rest of function)
    FontManager = fm
    
    -- Calculate window dimensions dynamically
    local windowWidth, windowHeight = GetWindowDimensions()
    
    -- Calculate bounds
    local screen = self:API_GetScreenInfo()
    local maxWidth = math.floor(screen.width * 0.90)
    local maxHeight = math.floor(screen.height * 0.90)
    
    -- Main frame
    local f = CreateFrame("Frame", "WarbandNexusFrame", UIParent)
    f:SetSize(windowWidth, windowHeight)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    -- Dynamic bounds based on screen
    f:SetResizeBounds(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT, maxWidth, maxHeight)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")  -- DIALOG is above HIGH, ensures we're above BankFrame
    f:SetFrameLevel(100)         -- Extra high level for safety
    f:SetClampedToScreen(true)
    
    -- Close all plan dialogs when main window is hidden
    f:SetScript("OnHide", function()
        WarbandNexus:CloseAllPlanDialogs()
    end)
    
    -- Apply pixel-perfect visuals (dark background, accent border)
    local ApplyVisuals = ns.UI_ApplyVisuals
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
    end
    
    -- OnSizeChanged handler - Update borders and scrollChild width
    -- Content will refresh on OnMouseUp (when resize is complete)
    f:SetScript("OnSizeChanged", function(self, width, height)
        -- CRITICAL: Snap dimensions to physical pixels to prevent blur
        local PixelSnap = ns.PixelSnap
        if PixelSnap then
            width = PixelSnap(width)
            height = PixelSnap(height)
        end
        
        -- CRITICAL: Recalculate border thickness during resize
        -- This prevents border "thickening/thinning" artifacts
        if self.BorderTop then
            local GetPixelScale = ns.GetPixelScale
            if GetPixelScale then
                local pixelScale = GetPixelScale()
                
                -- Reset border thickness to pixel-perfect value
                self.BorderTop:SetHeight(pixelScale)
                self.BorderBottom:SetHeight(pixelScale)
                self.BorderLeft:SetWidth(pixelScale)
                self.BorderRight:SetWidth(pixelScale)
                
                -- Adjust corner offsets (borders shouldn't overlap)
                self.BorderLeft:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -pixelScale)
                self.BorderLeft:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, pixelScale)
                self.BorderRight:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -pixelScale)
                self.BorderRight:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, pixelScale)
            end
        end
        
        -- Update scrollChild width to match new scroll width
        if self.scrollChild and self.scroll then
            self.scrollChild:SetWidth(self.scroll:GetWidth())
        end
        -- DO NOT refresh content here (causes severe lag during resize)
        -- Content is refreshed in OnMouseUp when resize is complete
    end)
    
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
        -- Ensure scrollChild width is updated BEFORE PopulateContent
        if f.scrollChild and f.scroll then
            f.scrollChild:SetWidth(f.scroll:GetWidth())
        end
        WarbandNexus:PopulateContent()
    end)
    
    -- ===== HEADER BAR =====
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    f.header = header  -- Store reference for color updates
    
    -- Apply header visuals (accent dark background, accent border)
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")

    -- Title (WHITE - never changes with theme)
    local title = FontManager:CreateFontString(header, "title", "OVERLAY")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Warband Nexus")
    title:SetTextColor(1, 1, 1)  -- Always white
    f.title = title  -- Store reference
    
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
    
    -- Border removed (no backdrop)

    local statusText = FontManager:CreateFontString(statusBadge, "small", "OVERLAY")
    statusText:SetPoint("CENTER", 0, 0)
    statusText:SetFont(statusText:GetFont(), 11, "OUTLINE")
    f.statusText = statusText
    
    -- Close button (Factory pattern with atlas icon)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply custom visuals
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    
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
    local DEFAULT_TAB_WIDTH = 95
    local TAB_HEIGHT = 34
    local TAB_PAD = 20  -- text padding inside button (10px each side)
    local TAB_GAP = 5   -- gap between tabs
    
    local function CreateTabButton(parent, text, key)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(DEFAULT_TAB_WIDTH, TAB_HEIGHT)
        btn.key = key

        -- Apply border and background
        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        
        -- Active indicator bar (bottom, rounded) (dynamic color)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        local accentColor = COLORS.accent
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(text)
        btn.label = label
        
        -- Keep default 95px, only expand if text doesn't fit
        local textWidth = label:GetStringWidth() or 0
        if textWidth + TAB_PAD > DEFAULT_TAB_WIDTH then
            btn:SetWidth(textWidth + TAB_PAD)
        end

        btn:SetScript("OnClick", function(self)
            local previousTab = f.currentTab
            f.currentTab = self.key
            
            -- ABORT PROTOCOL: Cancel all async operations from previous tab
            -- This prevents race conditions when user switches tabs rapidly
            if WarbandNexus.AbortTabOperations then
                WarbandNexus:AbortTabOperations(previousTab)
            end
            
            -- Flag that this is a MAIN tab switch (not a sub-tab or refresh)
            f.isMainTabSwitch = true
            
            -- Clear all search boxes when switching main tabs
            ClearAllSearchBoxes()
            
            -- Close any open plan dialogs when switching tabs (if function exists)
            if WarbandNexus.CloseAllPlanDialogs then
                WarbandNexus:CloseAllPlanDialogs()
            end
            WarbandNexus:PopulateContent()
            
            -- Reset flag after populate
            f.isMainTabSwitch = false
        end)

        return btn
    end
    
    -- Tab definitions with locale keys
    local tabDefs = {
        { key = "chars",       text = (ns.L and ns.L["TAB_CHARACTERS"]) or "Characters" },
        { key = "items",       text = (ns.L and ns.L["TAB_ITEMS"]) or "Items" },
        { key = "storage",     text = (ns.L and ns.L["TAB_STORAGE"]) or "Storage" },
        { key = "pve",         text = (ns.L and ns.L["TAB_PVE"]) or "PvE" },
        { key = "reputations", text = (ns.L and ns.L["TAB_REPUTATIONS"]) or "Reputations" },
        { key = "currency",    text = (ns.L and ns.L["TAB_CURRENCIES"]) or "Currencies" },
        { key = "plans",       text = (ns.L and ns.L["TAB_PLANS"]) or "Plans" },
        { key = "stats",       text = (ns.L and ns.L["TAB_STATISTICS"]) or "Statistics" },
    }
    
    -- Create tabs: default 95px + 5px gap, expand only when needed
    local prevBtn = nil
    for _, def in ipairs(tabDefs) do
        local btn = CreateTabButton(nav, def.text, def.key)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP, 0)
        else
            btn:SetPoint("LEFT", nav, "LEFT", 10, 0)
        end
        f.tabButtons[def.key] = btn
        prevBtn = btn
    end
    
    -- Function to update tab colors dynamically
    f.UpdateTabColors = function()
        local freshColors = ns.UI_COLORS
        local accentColor = freshColors.accent
        for _, btn in pairs(f.tabButtons) do
            if btn.activeBar then
                btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
            end
            
            -- Update colors based on active state (same as Plans tabs)
            if btn.active then
                btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
                btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
            else
                btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
                btn:SetBackdropBorderColor(accentColor[1] * 0.8, accentColor[2] * 0.8, accentColor[3] * 0.8, 1)
            end
        end
    end
    
    -- Information button
    local infoBtn = CreateFrame("Button", nil, nav)
    infoBtn:SetSize(28, 28)
    infoBtn:SetPoint("RIGHT", nav, "RIGHT", -48, 0)
    infoBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    infoBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    infoBtn:SetScript("OnClick", function() WarbandNexus:ShowInfoDialog() end)
    
    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, nav)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", nav, "RIGHT", -10, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() WarbandNexus:OpenOptions() end)
    
    -- ===== CONTENT AREA =====
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", nav, "BOTTOMLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 45)
    f.content = content
    
    -- Apply content area visuals (slightly lighter background, subtle border)
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(content, {0.04, 0.04, 0.05, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    -- Scroll frame (using Factory pattern with modern custom scroll bar)
    -- IMPORTANT: Leave space on the right for scroll bar system (22px)
    -- Scroll bar is at -4px from content edge, 16px wide, plus 2px gap = 22px total
    local scroll = ns.UI.Factory:CreateScrollFrame(content, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -6)    -- 2px left, 6px top inset
    scroll:SetPoint("TOPRIGHT", content, "TOPRIGHT", -22, -6) -- 22px scroll bar + gap, 6px top inset
    scroll:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 6) -- 2px left, 6px bottom inset
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -22, 6) -- 22px scroll bar, 6px bottom inset
    f.scroll = scroll
    
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1) -- Temporary, will be updated dynamically
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild
    
    -- Note: scrollChild width is managed in PopulateContent() for consistency
    
    -- ===== FOOTER =====
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(35)
    footer:SetPoint("BOTTOMLEFT", 8, 5)
    footer:SetPoint("BOTTOMRIGHT", -8, 5)
    
    local footerText = FontManager:CreateFontString(footer, "small", "OVERLAY")
    footerText:SetPoint("LEFT", 5, 0)
    footerText:SetTextColor(unpack(COLORS.textDim))
    f.footerText = footerText
    
    -- Action buttons removed (read-only mode)
    -- No Classic Bank button, no bank manipulation
    
    -- Store reference in WarbandNexus for cross-module access
    if not WarbandNexus.UI then
        WarbandNexus.UI = {}
    end
    WarbandNexus.UI.mainFrame = f
    
    -- ===== EVENT-DRIVEN UI UPDATES (DB-First Pattern) =====
    -- UI automatically refreshes when DB data changes
    local Constants = ns.Constants
    
    WarbandNexus:RegisterMessage(Constants.EVENTS.CHARACTER_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "chars" then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage(Constants.EVENTS.ITEMS_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "storage") then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage(Constants.EVENTS.PVE_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "pve" then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage("WARBAND_CURRENCIES_UPDATED", function()
        if f and f:IsShown() and f.currentTab == "currency" then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage("WARBAND_REPUTATIONS_UPDATED", function()
        if f and f:IsShown() and f.currentTab == "reputations" then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage("WARBAND_PLANS_UPDATED", function()
        if f and f:IsShown() and f.currentTab == "plans" then
            WarbandNexus:PopulateContent()
        end
    end)
    
    WarbandNexus:RegisterMessage("WN_BAGS_UPDATED", function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "storage") then
            WarbandNexus:PopulateContent()
        end
    end)
    
    -- Close plan dialogs and clear search boxes when addon window closes
    f:SetScript("OnHide", function(self)
        if WarbandNexus.CloseAllPlanDialogs then
            WarbandNexus:CloseAllPlanDialogs()
        end
        ClearAllSearchBoxes()
    end)
    
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
    
    -- Get scroll frame width (already reduced by 24px for scroll bar)
    local scrollWidth = mainFrame.scroll:GetWidth()
    
    -- Set scrollChild width to full scroll frame width (no extra padding needed)
    scrollChild:SetWidth(scrollWidth)
    
    -- CRITICAL FIX: Reset scrollChild height to prevent layout corruption across tabs
    scrollChild:SetHeight(1)  -- Reset to minimal height, will expand as content is added
    
    -- PERFORMANCE: Only clear/hide children, don't SetParent(nil)
    local children = {scrollChild:GetChildren()}
    for _, child in pairs(children) do
        child:Hide()
    end
    for _, region in pairs({scrollChild:GetRegions()}) do
        region:Hide()
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Update tabs with modern active state (rounded style) - Dynamic colors
    local freshColors = ns.UI_COLORS
    local accentColor = freshColors.accent
    for key, btn in pairs(mainFrame.tabButtons) do
        if key == mainFrame.currentTab then
            btn.active = true
            btn.label:SetTextColor(1, 1, 1)
            -- Keep FontManager's size, only add outline for active tab
            local font, size = btn.label:GetFont()
            btn.label:SetFont(font, size, "OUTLINE")
            if btn.activeBar then
                btn.activeBar:SetAlpha(1)  -- Show active indicator
            end
            -- Update border color for active state
            if UpdateBorderColor then
                UpdateBorderColor(btn, {accentColor[1], accentColor[2], accentColor[3], 1})
            end
            -- Update background for active state
            if btn.SetBackdropColor then
                btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
            end
        else
            btn.active = false
            btn.label:SetTextColor(0.7, 0.7, 0.7)
            -- Keep FontManager's size, only remove outline
            local font, size = btn.label:GetFont()
            btn.label:SetFont(font, size, "")  -- No outline for inactive tabs
            if btn.activeBar then
                btn.activeBar:SetAlpha(0)  -- Hide active indicator
            end
            -- Update border color for inactive state
            if UpdateBorderColor then
                UpdateBorderColor(btn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            end
            -- Update background for inactive state
            if btn.SetBackdropColor then
                btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            end
        end
    end
    
    -- Draw based on current tab
    local height
    
    if mainFrame.currentTab == "chars" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCharacterList(scrollChild)
    elseif mainFrame.currentTab == "currency" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCurrencyTab(scrollChild)
    elseif mainFrame.currentTab == "items" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawItemList(scrollChild)
    elseif mainFrame.currentTab == "storage" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawStorageTab(scrollChild)
    elseif mainFrame.currentTab == "pve" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawPvEProgress(scrollChild)
    elseif mainFrame.currentTab == "reputations" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawReputationTab(scrollChild)
    elseif mainFrame.currentTab == "stats" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawStatistics(scrollChild)
    elseif mainFrame.currentTab == "plans" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawPlansTab(scrollChild)
    else
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCharacterList(scrollChild)
    end
    
    -- Set scrollChild height based on content
    -- CRITICAL: Use math.max to ensure scrollChild is at least viewport size
    -- Otherwise, WoW scroll frame won't work properly when content < viewport
    scrollChild:SetHeight(math.max(height, mainFrame.scroll:GetHeight()))
    
    -- Update scroll bar visibility (hide if content fits)
    if ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    
    -- CRITICAL: Reset scroll position ONLY on MAIN tab switches (not sub-tab or header expand)
    if mainFrame.isMainTabSwitch then
        mainFrame.scroll:SetVerticalScroll(0)
    end
    
    self:UpdateFooter()
end

--============================================================================
-- UPDATE STATUS
--============================================================================
function WarbandNexus:UpdateStatus()
    if not mainFrame then return end

    -- Status badge update (simplified - no conflict detection)
    local isOpen = self.bankIsOpen
    
    if isOpen then
        -- Green badge for "Bank is Active" (rounded style)
        if mainFrame.statusBadge.bg then
            mainFrame.statusBadge.bg:SetColorTexture(0.15, 0.6, 0.25, 0.25)
        end
        if mainFrame.statusBadge.border then
            mainFrame.statusBadge.border:SetBackdropBorderColor(0.2, 0.9, 0.3, 0.8)
        end
        mainFrame.statusText:SetText((ns.L and ns.L["BANK_IS_ACTIVE"]) or "Bank is Active")
        mainFrame.statusText:SetTextColor(0.3, 1, 0.4)
    else
        -- Hide badge when bank closed (cached)
        if mainFrame.statusBadge.bg then
            mainFrame.statusBadge.bg:SetColorTexture(0, 0, 0, 0)
        end
        if mainFrame.statusBadge.border then
            mainFrame.statusBadge.border:SetBackdropBorderColor(0, 0, 0, 0)
        end
        mainFrame.statusText:SetText("")
        mainFrame.statusText:SetTextColor(0, 0, 0, 0)
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
    
    -- Footer buttons (Scan and Sort removed - not needed)
    
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
    
    mainFrame.footerText:SetText(format((ns.L and ns.L["ITEMS_CACHED_FORMAT"]) or "%d items cached", totalCount))
    
    -- Update "Up-to-Date" status indicator (next to Scan button)
    if mainFrame.scanStatus then
        local wbScan = stats.warband and stats.warband.lastScan or 0
        local pbScan = stats.personal and stats.personal.lastScan or 0
        local lastScan = math.max(wbScan, pbScan)
        
        -- Check if recently scanned (within 60 seconds while bank is open)
        local isUpToDate = self.bankIsOpen and lastScan > 0 and (time() - lastScan < 60)
        if isUpToDate then
            mainFrame.scanStatus:SetText("|cff00ff00" .. ((ns.L and ns.L["UP_TO_DATE"]) or "Up-to-Date") .. "|r")
        elseif lastScan > 0 then
            local scanText = date("%m/%d %H:%M", lastScan)
            mainFrame.scanStatus:SetText("|cffaaaaaa" .. scanText .. "|r")
        else
            mainFrame.scanStatus:SetText("|cffff6600" .. ((ns.L and ns.L["NEVER_SCANNED"]) or "Never Scanned") .. "|r")
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
    if subTab == "warband" or subTab == "personal" or subTab == "guild" then
        currentItemsSubTab = subTab
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

-- Refresh throttle constants
local REFRESH_THROTTLE = 0.05 -- Small delay for batching follow-up refreshes

function WarbandNexus:RefreshUI()
    -- Prevent recursive calls during populate (safety flag)
    if self.isRefreshing then
        -- Schedule a follow-up refresh instead of executing recursively
        if not self.pendingRefresh then
            self.pendingRefresh = true
            C_Timer.After(REFRESH_THROTTLE, function()
                if WarbandNexus and WarbandNexus.pendingRefresh then
                    WarbandNexus.pendingRefresh = false
                    WarbandNexus:RefreshUI()
                end
            end)
        end
        return
    end
    
    -- CRITICAL FIX: Always execute the refresh immediately (no throttle on user actions)
    -- This ensures rows are always drawn when headers are toggled or tabs are switched
    self.isRefreshing = true
    
    -- Use pcall to ensure isRefreshing flag is always reset even if there's an error
    local success, err = pcall(function()
        if mainFrame and mainFrame:IsShown() then
            self:PopulateContent()
        end
    end)
    
    self.isRefreshing = false
    
    -- Report error if one occurred (silent for production)
    if not success then
        -- Error logged silently
    end
end

-- REMOVED: RefreshMainWindow() and RefreshMainWindowContent() - duplicate wrappers, use RefreshUI() directly

--[[
    [CONSOLIDATED] RefreshUI duplicate removed (line 1040)
    The implementation at line 997 with throttling and recursive call prevention is kept.
    This duplicate (which closed/reopened the window) has been removed to prevent conflicts.
    The consolidated RefreshUI handles both normal refreshes and font/scale changes.
]]

--[[
    Force refresh of PvE tab if currently visible
    Provides instant refresh for responsive UI
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:RefreshPvEUI()
    DebugPrint("|cff9370DB[WN UI]|r RefreshPvEUI triggered")
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
                DebugPrint("|cff00ff00[WN UI]|r PvE tab refreshed")
            end
        end
    end
end

--[[
    Open addon settings/options UI
    Shows custom settings UI with themed widgets
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:OpenOptions()
    DebugPrint("|cff9370DB[WN UI]|r OpenOptions triggered")
    -- Show custom settings UI (renders AceConfig with themed widgets)
    if self.ShowSettings then
        self:ShowSettings()
    elseif ns.ShowSettings then
        ns.ShowSettings()
    else
        -- Fallback to Blizzard settings panel
        Settings.OpenToCategory(ADDON_NAME)
    end
end
