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

-- Local references
local L = ns.L

--============================================================================
-- GOLD MANAGEMENT POPUP
--============================================================================

---Shows the Gold Management configuration popup
---@param anchorFrame Frame|nil Optional frame to anchor near (default: center screen)
function WarbandNexus:ShowGoldManagementPopup(anchorFrame)
    -- Get current settings from DB
    local settings = self.db.profile.goldManagement or {
        enabled = false,  -- Default: disabled
        mode = "both",  -- "deposit", "withdraw", "both"
        targetAmount = 100000,  -- In copper (10g default)
    }
    
    -- Ensure settings exist in DB
    if not self.db.profile.goldManagement then
        self.db.profile.goldManagement = settings
    end
    
    -- Create external window
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "GoldManagementPopup",
        title = L["GOLD_MANAGEMENT_TITLE"] or "Gold Manager",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        width = 440,
        height = 480,
        preventDuplicates = true,
        onClose = function()
            -- Save settings on close
            self.db.profile.goldManagement = settings
            
            -- Send message to update UI
            if self.SendMessage then
                self:SendMessage("WN_GOLD_MANAGEMENT_CHANGED")
            end
        end
    })
    
    if not dialog then return end  -- Already open or creation failed
    
    local yOffset = 12
    local PADDING = 12
    local contentWidth = contentFrame:GetWidth()
    
    -- Enabled checkbox (top) - Custom themed checkbox
    local checkboxContainer = CreateFrame("Frame", nil, contentFrame)
    checkboxContainer:SetSize(contentWidth - PADDING * 2, 28)
    checkboxContainer:SetPoint("TOPLEFT", PADDING, -yOffset)
    
    -- Checkbox square
    local checkboxSize = 20
    local checkbox = CreateFrame("Button", nil, checkboxContainer)
    checkbox:SetSize(checkboxSize, checkboxSize)
    checkbox:SetPoint("LEFT", 0, 0)
    
    -- Background
    ApplyVisuals(checkbox, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Checkmark texture (hidden by default)
    local checkTexture = checkbox:CreateTexture(nil, "OVERLAY")
    checkTexture:SetSize(14, 14)
    checkTexture:SetPoint("CENTER")
    checkTexture:SetAtlas("common-icon-checkmark")
    checkTexture:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    checkTexture:SetShown(settings.enabled)
    
    -- Label
    local checkLabel = FontManager:CreateFontString(checkboxContainer, "body", "OVERLAY")
    checkLabel:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    checkLabel:SetText(L["GOLD_MANAGEMENT_ENABLE"] or "Enable Gold Management")
    checkLabel:SetTextColor(1, 1, 1)
    
    -- Click handler
    checkbox:SetScript("OnClick", function(self)
        settings.enabled = not settings.enabled
        checkTexture:SetShown(settings.enabled)
    end)
    
    -- Make label clickable too
    checkboxContainer:SetScript("OnMouseUp", function()
        checkbox:Click()
    end)
    
    yOffset = yOffset + 36
    
    -- Mode selection (Radio buttons) - more compact
    local modeLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    modeLabel:SetPoint("TOPLEFT", PADDING, -yOffset)
    modeLabel:SetText(L["GOLD_MANAGEMENT_MODE"] or "Management Mode")
    modeLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    yOffset = yOffset + 28  -- Increased spacing between title and options
    
    -- Radio button helper
    local selectedModeBtn = nil
    local RADIO_INDENT = 0  -- No indent - flush left
    local DESC_INDENT = 24  -- Description indent (radio 16px + 8px gap)
    
    local function CreateModeRadio(mode, label, description, yPos)
        -- Use shared widget for radio button
        local radioButton = ns.UI_CreateThemedRadioButton(contentFrame, settings.mode == mode)
        radioButton:SetPoint("TOPLEFT", PADDING + RADIO_INDENT, -yPos)
        
        -- Clickable button (invisible, covers whole line)
        local btn = CreateFrame("Button", nil, contentFrame)
        btn:SetSize(contentWidth - PADDING * 2, 20)
        btn:SetPoint("TOPLEFT", PADDING, -yPos)
        btn.radioButton = radioButton
        
        -- Label
        local labelText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        labelText:SetPoint("LEFT", radioButton, "RIGHT", 6, 0)
        labelText:SetText(label)
        labelText:SetTextColor(1, 1, 1)
        
        -- Description - always aligned to same fixed position
        local descText = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        descText:SetPoint("TOPLEFT", PADDING + DESC_INDENT, -(yPos + 24))
        descText:SetPoint("TOPRIGHT", -PADDING, -(yPos + 24))
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetText(description)
        descText:SetTextColor(0.7, 0.7, 0.7)
        
        -- Set initial state
        if settings.mode == mode then
            selectedModeBtn = btn
        end
        
        -- Click handler
        btn:SetScript("OnClick", function(self)
            if selectedModeBtn and selectedModeBtn ~= self then
                selectedModeBtn.radioButton.innerDot:Hide()
            end
            self.radioButton.innerDot:Show()
            selectedModeBtn = self
            settings.mode = mode
        end)
        
        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if UpdateBorderColor then
                local radio = self.radioButton
                UpdateBorderColor(radio, radio.hoverBorderColor)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if UpdateBorderColor then
                local radio = self.radioButton
                UpdateBorderColor(radio, radio.defaultBorderColor)
            end
        end)
        
        return descText:GetStringHeight() + 28
    end
    
    local depositHeight = CreateModeRadio(
        "deposit",
        L["GOLD_MANAGEMENT_MODE_DEPOSIT"] or "Deposit Only",
        L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] or "If you have more than X gold, you'll be notified to deposit the excess to warband bank.",
        yOffset
    )
    yOffset = yOffset + depositHeight + 8
    
    local withdrawHeight = CreateModeRadio(
        "withdraw",
        L["GOLD_MANAGEMENT_MODE_WITHDRAW"] or "Withdraw Only",
        L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] or "If you have less than X gold, you'll be notified to withdraw from warband bank.",
        yOffset
    )
    yOffset = yOffset + withdrawHeight + 8
    
    local bothHeight = CreateModeRadio(
        "both",
        L["GOLD_MANAGEMENT_MODE_BOTH"] or "Both (Maintain)",
        L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] or "Automatically notify you to keep exactly X gold on your character (deposit if over, withdraw if under).",
        yOffset
    )
    yOffset = yOffset + bothHeight + 20  -- Increased spacing before Target section
    
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
    inputBox:SetMaxLetters(10)
    inputBox:SetNumeric(false)  -- Allow decimal input (we'll parse it)
    
    -- Apply custom visuals
    if ApplyVisuals then
        ApplyVisuals(inputBox, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Font - Use standard WoW font object
    inputBox:SetFontObject(GameFontHighlight)
    inputBox:SetTextInsets(8, 8, 0, 0)
    inputBox:SetTextColor(1, 1, 1)
    
    -- Convert copper to gold string (e.g., 10000 -> "1")
    local function CopperToGoldString(copper)
        return tostring(math.floor(copper / 10000))
    end
    
    -- Convert gold string to copper (e.g., "1.5" -> 15000)
    local function GoldStringToCopper(str)
        local num = tonumber(str)
        if not num or num < 0 then return 0 end
        return math.floor(num * 10000)
    end
    
    -- Set initial value
    inputBox:SetText(CopperToGoldString(settings.targetAmount))
    
    -- Gold icon next to input (no label text)
    local goldIcon = contentFrame:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(18, 18)
    goldIcon:SetPoint("LEFT", inputBox, "RIGHT", 8, 0)
    goldIcon:SetAtlas("coin-gold")
    
    -- Helper text
    local helperText = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
    helperText:SetPoint("TOPLEFT", inputBox, "BOTTOMLEFT", 0, -6)
    helperText:SetPoint("TOPRIGHT", -PADDING, -(yOffset + 32 + 6))
    helperText:SetJustifyH("LEFT")
    helperText:SetWordWrap(true)
    helperText:SetText(L["GOLD_MANAGEMENT_HELPER"] or "Enter the amount of gold you want to keep on this character. The addon will notify you when you need to move gold.")
    helperText:SetTextColor(0.6, 0.6, 0.6)
    
    -- Save input on focus lost
    inputBox:SetScript("OnEditFocusLost", function(self)
        local value = GoldStringToCopper(self:GetText())
        if value <= 0 then
            value = 10000  -- Default to 1g if invalid
            self:SetText(CopperToGoldString(value))
        end
        settings.targetAmount = value
    end)
    
    inputBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    inputBox:SetScript("OnEscapePressed", function(self)
        self:SetText(CopperToGoldString(settings.targetAmount))  -- Reset to saved value
        self:ClearFocus()
    end)
    
    dialog:Show()
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_ShowGoldManagementPopup = function(...) WarbandNexus:ShowGoldManagementPopup(...) end
