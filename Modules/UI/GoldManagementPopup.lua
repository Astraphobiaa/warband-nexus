--[[
    Warband Nexus - Gold Management Popup
    
    Provides a UI for configuring automatic gold management between character and warband bank.
    
    Features:
    - Deposit: Keep X gold on character, deposit excess to warband bank
    - Withdraw: Keep X gold on character, withdraw from warband bank if below
    - Both: Automatically maintain X gold on character (deposit/withdraw as needed)
    
    NOTE: WoW does NOT provide API functions to move gold programmatically.
    This feature MONITORS gold and NOTIFIES the user when action is needed.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateCard = ns.UI_CreateCard

-- Local references
local L = ns.L

local MODE_LABELS = {
    deposit  = function() return L["GOLD_MANAGEMENT_MODE_DEPOSIT"]  or "Deposit Only" end,
    withdraw = function() return L["GOLD_MANAGEMENT_MODE_WITHDRAW"] or "Withdraw Only" end,
    both     = function() return L["GOLD_MANAGEMENT_MODE_BOTH"]     or "Both" end,
}

local MODE_SHORT = {
    deposit  = function() return L["GOLD_MGMT_MODE_SHORT_DEPOSIT"]  or "Deposit" end,
    withdraw = function() return L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] or "Withdraw" end,
    both     = function() return L["GOLD_MGMT_MODE_SHORT_BOTH"]     or "Both" end,
}

local MAX_GOLD = 9999999

-- Format number with thousand separators: 1234567 → "1.234.567"
local function FormatGoldNumber(n)
    local s = tostring(math.floor(n))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if formatted:sub(1, 1) == "." then formatted = formatted:sub(2) end
    return formatted
end

-- Strip dots/spaces/commas → pure digit string
local function StripFormatting(str)
    return (str or ""):gsub("[^%d]", "")
end

local function CopperToGoldDisplay(copper)
    local gold = math.floor((copper or 0) / 10000)
    return FormatGoldNumber(gold) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

--============================================================================
-- GOLD MANAGEMENT POPUP
--============================================================================

---Shows the Gold Management configuration popup
---@param anchorFrame Frame|nil Optional frame to anchor near (default: center screen)
function WarbandNexus:ShowGoldManagementPopup(anchorFrame)
    -- Determine which settings to edit: per-character or profile
    local isPerChar = self.db.char.goldManagement and self.db.char.goldManagement.perCharacter or false
    
    local profileDefaults = {
        enabled = false,
        mode = "both",
        targetAmount = 100000,
    }
    
    -- Ensure profile settings exist
    if not self.db.profile.goldManagement then
        self.db.profile.goldManagement = profileDefaults
    end
    
    -- Resolve which settings table to edit
    local settings
    if isPerChar then
        settings = self.db.char.goldManagement
    else
        settings = self.db.profile.goldManagement
    end
    
    -- Create external window
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "GoldManagementPopup",
        title = L["GOLD_MANAGEMENT_TITLE"] or "Gold Manager",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        width = 440,
        height = 380,
        preventDuplicates = true,
        onClose = function()
            -- Settings are already written to the correct DB table (profile or char)
            -- via direct reference; just notify the service
            if self.SendMessage then
                self:SendMessage("WN_GOLD_MANAGEMENT_CHANGED")
            end
        end
    })
    
    if not dialog then return end  -- Already open or creation failed
    
    local yOffset = 12
    local PADDING = 12
    local contentWidth = contentFrame:GetWidth()
    
    -- Enabled checkbox (using shared themed widget)
    local enabledCB = CreateThemedCheckbox(contentFrame, settings.enabled)
    enabledCB:SetPoint("TOPLEFT", PADDING, -yOffset)
    
    local enabledLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    enabledLabel:SetPoint("LEFT", enabledCB, "RIGHT", 8, 0)
    enabledLabel:SetText(L["GOLD_MANAGEMENT_ENABLE"] or "Enable Gold Management")
    enabledLabel:SetTextColor(1, 1, 1)
    
    yOffset = yOffset + 32
    
    -- "Only For This Character" checkbox (using shared themed widget)
    local perCharCB = CreateThemedCheckbox(contentFrame, isPerChar)
    perCharCB:SetPoint("TOPLEFT", PADDING, -yOffset)
    
    local charName = UnitName("player") or "?"
    local perCharLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    perCharLabel:SetPoint("LEFT", perCharCB, "RIGHT", 8, 0)
    perCharLabel:SetText(string.format(L["GOLD_MANAGEMENT_CHAR_ONLY"] or "Only For This Character (%s)", charName))
    perCharLabel:SetTextColor(1, 1, 1)
    
    -- Tooltip for per-char checkbox
    local perCharTooltip = L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] or "Use separate gold management settings for this character only. Other characters will use the shared profile settings."
    perCharCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(perCharTooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    perCharCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Per-char toggle: switch which settings table the UI edits
    local function SwitchToPerChar()
        isPerChar = true
        if not self.db.char.goldManagement then
            -- First time: copy profile as starting point
            self.db.char.goldManagement = {
                perCharacter = true,
                enabled = settings.enabled,
                mode = settings.mode,
                targetAmount = settings.targetAmount,
            }
        else
            self.db.char.goldManagement.perCharacter = true
        end
        settings = self.db.char.goldManagement
    end
    
    local function SwitchToProfile()
        isPerChar = false
        -- Preserve char settings (just deactivate, don't destroy)
        if self.db.char.goldManagement then
            self.db.char.goldManagement.perCharacter = false
        end
        settings = self.db.profile.goldManagement
    end
    
    local syncUIToSettings  -- forward-declared, assigned after inputBox + radios exist
    local updateSummary     -- forward-declared, assigned after summary card exists
    
    perCharCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(checked) end
        if checked then
            SwitchToPerChar()
        else
            SwitchToProfile()
        end
        isPerChar = checked
        enabledCB:SetChecked(settings.enabled)
        if enabledCB.checkTexture then enabledCB.checkTexture:SetShown(settings.enabled) end
        if syncUIToSettings then syncUIToSettings() end
    end)
    
    yOffset = yOffset + 32
    
    -- Mode selection (Radio buttons) - more compact
    local modeLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    modeLabel:SetPoint("TOPLEFT", PADDING, -yOffset)
    modeLabel:SetText(L["GOLD_MANAGEMENT_MODE"] or "Management Mode")
    modeLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    yOffset = yOffset + 28  -- Increased spacing between title and options
    
    -- Radio button helper
    local selectedModeBtn = nil
    local RADIO_INDENT = 0
    
    local RADIO_ROW_HEIGHT = 26
    
    local function CreateModeRadio(mode, label, description, yPos)
        local radioButton = ns.UI_CreateThemedRadioButton(contentFrame, settings.mode == mode)
        radioButton:SetPoint("TOPLEFT", PADDING + RADIO_INDENT, -yPos)
        
        local btn = CreateFrame("Button", nil, contentFrame)
        btn:SetSize(contentWidth - PADDING * 2, 20)
        btn:SetPoint("TOPLEFT", PADDING, -yPos)
        btn.radioButton = radioButton
        
        local labelText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        labelText:SetPoint("LEFT", radioButton, "RIGHT", 6, 0)
        labelText:SetText(label)
        labelText:SetTextColor(1, 1, 1)
        
        if settings.mode == mode then
            selectedModeBtn = btn
        end
        
        btn:SetScript("OnClick", function(self)
            if selectedModeBtn and selectedModeBtn ~= self then
                selectedModeBtn.radioButton.innerDot:Hide()
            end
            self.radioButton.innerDot:Show()
            selectedModeBtn = self
            settings.mode = mode
            if updateSummary then updateSummary() end
        end)
        
        btn:SetScript("OnEnter", function(self)
            if UpdateBorderColor then
                local radio = self.radioButton
                UpdateBorderColor(radio, radio.hoverBorderColor)
            end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(description, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        
        btn:SetScript("OnLeave", function(self)
            if UpdateBorderColor then
                local radio = self.radioButton
                UpdateBorderColor(radio, radio.defaultBorderColor)
            end
            GameTooltip:Hide()
        end)
        
        return RADIO_ROW_HEIGHT
    end
    
    CreateModeRadio(
        "deposit",
        L["GOLD_MANAGEMENT_MODE_DEPOSIT"] or "Deposit Only",
        L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] or "If you have more than X gold, you'll be notified to deposit the excess to warband bank.",
        yOffset
    )
    yOffset = yOffset + RADIO_ROW_HEIGHT
    
    CreateModeRadio(
        "withdraw",
        L["GOLD_MANAGEMENT_MODE_WITHDRAW"] or "Withdraw Only",
        L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] or "If you have less than X gold, you'll be notified to withdraw from warband bank.",
        yOffset
    )
    yOffset = yOffset + RADIO_ROW_HEIGHT
    
    CreateModeRadio(
        "both",
        L["GOLD_MANAGEMENT_MODE_BOTH"] or "Both (Maintain)",
        L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] or "Automatically notify you to keep exactly X gold on your character (deposit if over, withdraw if under).",
        yOffset
    )
    yOffset = yOffset + RADIO_ROW_HEIGHT + 16
    
    -- Target amount input
    local targetLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    targetLabel:SetPoint("TOPLEFT", PADDING, -yOffset)
    targetLabel:SetText(L["GOLD_MANAGEMENT_TARGET"] or "Target Gold Amount")
    targetLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    yOffset = yOffset + 28  -- Increased spacing between title and input
    
    -- Input box for gold amount
    local inputBox = CreateFrame("EditBox", nil, contentFrame)
    inputBox:SetSize(140, 32)
    inputBox:SetPoint("TOPLEFT", PADDING, -yOffset)  -- Flush left with padding
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(15)
    inputBox:SetNumeric(false)
    
    -- Apply custom visuals
    if ApplyVisuals then
        ApplyVisuals(inputBox, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Font - Use standard WoW font object
    inputBox:SetFontObject(GameFontHighlight)
    inputBox:SetTextInsets(8, 8, 0, 0)
    inputBox:SetTextColor(1, 1, 1)
    
    local function CopperToGoldString(copper)
        return FormatGoldNumber(math.floor(copper / 10000))
    end
    
    local function GoldStringToCopper(str)
        local digits = StripFormatting(str)
        local num = tonumber(digits)
        if not num or num < 0 then return 0 end
        return num * 10000
    end
    
    -- Set initial value
    inputBox:SetText(CopperToGoldString(settings.targetAmount))
    
    -- Gold icon next to input
    local goldIcon = contentFrame:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(18, 18)
    goldIcon:SetPoint("LEFT", inputBox, "RIGHT", 8, 0)
    goldIcon:SetAtlas("coin-gold")
    
    -- Tooltip for target input
    local targetTooltip = L["GOLD_MANAGEMENT_HELPER"] or "Enter the amount of gold you want to keep on this character. The addon will notify you when you need to move gold."
    inputBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(targetTooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    inputBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    inputBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    inputBox:SetScript("OnEscapePressed", function(self)
        self:SetText(CopperToGoldString(settings.targetAmount))
        self:ClearFocus()
    end)
    
    -- Live thousand-separator formatting as the user types
    inputBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        
        local text = self:GetText()
        local cursor = self:GetCursorPosition()
        
        -- Count pure digits before cursor position
        local digitsBefore = 0
        for i = 1, cursor do
            if text:sub(i, i):match("%d") then
                digitsBefore = digitsBefore + 1
            end
        end
        
        local digits = StripFormatting(text)
        if digits == "" then return end
        local num = tonumber(digits) or 0
        if num > MAX_GOLD then num = MAX_GOLD end
        local formatted = FormatGoldNumber(num)
        
        -- Restore cursor: advance through formatted string until we pass the same digit count
        local newCursor = 0
        local count = 0
        for i = 1, #formatted do
            if formatted:sub(i, i):match("%d") then
                count = count + 1
            end
            newCursor = i
            if count >= digitsBefore then break end
        end
        if digitsBefore == 0 then newCursor = 0 end
        
        self:SetText(formatted)
        self:SetCursorPosition(newCursor)
    end)
    
    -- ===== SETTINGS OVERVIEW CARD =====
    yOffset = yOffset + 42
    
    local summaryCard = CreateCard(contentFrame, 1)
    summaryCard:SetPoint("TOPLEFT", PADDING, -yOffset)
    summaryCard:SetPoint("TOPRIGHT", -PADDING, -yOffset)
    
    local summaryPad = 10
    local summaryY = summaryPad
    local halfWidth = math.floor((contentWidth - PADDING * 2 - summaryPad * 3) / 2)
    
    local hexColor = string.format("%02x%02x%02x", COLORS.accent[1] * 255, COLORS.accent[2] * 255, COLORS.accent[3] * 255)
    
    -- Profile column (left)
    local profileTitle = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
    profileTitle:SetPoint("TOPLEFT", summaryPad, -summaryY)
    profileTitle:SetWidth(halfWidth)
    profileTitle:SetJustifyH("LEFT")
    
    local profileInfo = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
    profileInfo:SetPoint("TOPLEFT", summaryPad, -(summaryY + 16))
    profileInfo:SetWidth(halfWidth)
    profileInfo:SetJustifyH("LEFT")
    
    -- Vertical separator
    local sep = summaryCard:CreateTexture(nil, "ARTWORK")
    sep:SetSize(1, 1)
    sep:SetPoint("TOP", summaryCard, "TOP", 0, -summaryPad)
    sep:SetPoint("BOTTOM", summaryCard, "BOTTOM", 0, summaryPad)
    sep:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
    
    -- Character column (right)
    local charTitle = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
    charTitle:SetPoint("TOPRIGHT", -summaryPad, -summaryY)
    charTitle:SetWidth(halfWidth)
    charTitle:SetJustifyH("LEFT")
    
    local charInfo = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
    charInfo:SetPoint("TOPRIGHT", -summaryPad, -(summaryY + 16))
    charInfo:SetWidth(halfWidth)
    charInfo:SetJustifyH("LEFT")
    
    local function UpdateSummaryCard()
        local profSettings = self.db.profile.goldManagement or profileDefaults
        local charSettings = self.db.char.goldManagement
        local usingChar = charSettings and charSettings.perCharacter
        
        local checkMark = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t "
        local crossMark = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t "
        
        -- Profile column
        local profLabel = (L and L["GOLD_MGMT_PROFILE_TITLE"]) or "Profile"
        local profIcon = profSettings.enabled and checkMark or crossMark
        profileTitle:SetText(profIcon .. "|cff" .. hexColor .. profLabel .. "|r")
        
        local profMode = MODE_SHORT[profSettings.mode or "both"]
        local profModeStr = profMode and profMode() or "Both"
        local profGold = CopperToGoldDisplay(profSettings.targetAmount or 0)
        profileInfo:SetText("|cffffffff" .. profModeStr .. "  " .. profGold .. "|r")
        
        -- Character column
        if charSettings and charSettings.perCharacter then
            local charIcon = charSettings.enabled and checkMark or crossMark
            charTitle:SetText(charIcon .. "|cff" .. hexColor .. charName .. "|r")
            
            local charMode = MODE_SHORT[charSettings.mode or "both"]
            local charModeStr = charMode and charMode() or "Both"
            local charGold = CopperToGoldDisplay(charSettings.targetAmount or 0)
            charInfo:SetText("|cffffffff" .. charModeStr .. "  " .. charGold .. "|r")
        else
            charTitle:SetText(crossMark .. "|cff" .. hexColor .. charName .. "|r")
            local usingProfileLabel = (L and L["GOLD_MGMT_USING_PROFILE"]) or "Using profile"
            charInfo:SetText("|cff888888" .. usingProfileLabel .. "|r")
        end
    end
    
    summaryCard:SetHeight(summaryY + 16 + summaryPad + 6)
    summaryCard:Show()
    updateSummary = UpdateSummaryCard
    UpdateSummaryCard()
    
    syncUIToSettings = function()
        inputBox:SetText(CopperToGoldString(settings.targetAmount or 100000))
        enabledCB:SetChecked(settings.enabled)
        if enabledCB.checkTexture then enabledCB.checkTexture:SetShown(settings.enabled) end
        if selectedModeBtn then
            selectedModeBtn.radioButton.innerDot:Hide()
            selectedModeBtn = nil
        end
        UpdateSummaryCard()
    end
    
    enabledCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(checked) end
        settings.enabled = checked
        UpdateSummaryCard()
    end)
    
    -- Hook input box to update summary on save
    inputBox:SetScript("OnEditFocusLost", function(self)
        local value = GoldStringToCopper(self:GetText())
        local maxCopper = MAX_GOLD * 10000
        if value > maxCopper then value = maxCopper end
        if value <= 0 then value = 10000 end
        self:SetText(CopperToGoldString(value))
        settings.targetAmount = value
        UpdateSummaryCard()
    end)
    
    dialog:Show()
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_ShowGoldManagementPopup = function(...) WarbandNexus:ShowGoldManagementPopup(...) end
