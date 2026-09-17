--[[
    Warband Nexus - Reagent & Warband Bank Deposit Popup
    Configuration window for automated and selective reagent/token deposits.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L
local E = ns.Constants.EVENTS

local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateButton = ns.UI_CreateButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local COLORS = ns.UI_COLORS
local FontManager = ns.FontManager

local CATEGORY_KEYS = {
    { key = "herbs",       icon = "Interface\\Icons\\Trade_Herbalism",            locKey = "REAGENT_CAT_HERBS",       default = "Herbs" },
    { key = "mining",      icon = "Interface\\Icons\\Trade_Mining",               locKey = "REAGENT_CAT_MINING",      default = "Metal & Stone" },
    { key = "leather",     icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",      locKey = "REAGENT_CAT_LEATHER",     default = "Leather & Hides" },
    { key = "cloth",       icon = "Interface\\Icons\\INV_Fabric_Silk_02",         locKey = "REAGENT_CAT_CLOTH",       default = "Cloth" },
    { key = "enchanting",  icon = "Interface\\Icons\\Trade_Engraving",            locKey = "REAGENT_CAT_ENCHANTING",  default = "Enchanting" },
    { key = "inscription", icon = "Interface\\Icons\\INV_Inscription_Tradeskill01", locKey = "REAGENT_CAT_INSCRIPTION", default = "Inscription" },
    { key = "cooking",     icon = "Interface\\Icons\\INV_Misc_Food_15",           locKey = "REAGENT_CAT_COOKING",     default = "Cooking" },
    { key = "gems",        icon = "Interface\\Icons\\INV_Misc_Gem_01",            locKey = "REAGENT_CAT_GEMS",        default = "Gems" },
    { key = "parts",       icon = "Interface\\Icons\\Trade_Engineering",          locKey = "REAGENT_CAT_PARTS",       default = "Engineering Parts" },
    { key = "elemental",   icon = "Interface\\Icons\\Spell_Fire_Volcano",         locKey = "REAGENT_CAT_ELEMENTAL",   default = "Elemental" },
    { key = "general",     icon = "Interface\\Icons\\INV_Misc_Rune_01",           locKey = "REAGENT_CAT_GENERAL",     default = "General Reagents" },
    { key = "tokens",      icon = "Interface\\Icons\\ability_pvp_gladiatormedallion", locKey = "REAGENT_CAT_TOKENS",  default = "Item Currencies (Marks)" },
    { key = "warbound",    icon = "Interface\\Icons\\INV_Chest_Plate_06",            locKey = "REAGENT_CAT_WARBOUND", default = "Warbound Gear (WuE)" },
}

---Shows the Reagent Deposit configuration popup
---@param anchorFrame Frame|nil Optional frame to anchor near
function WarbandNexus:ShowReagentDepositPopup(anchorFrame)
    local isPerChar = self.db.char.reagentDeposit and self.db.char.reagentDeposit.perCharacter or false

    local profileDefaults = {
        enabled           = true,
        autoDepositOnOpen = false,
        destination       = "warband",
        categories        = WarbandNexus:GetDefaultReagentCategories(),
    }

    if not self.db.profile.reagentDeposit then
        self.db.profile.reagentDeposit = CopyTable(profileDefaults)
    end

    local settings
    if isPerChar then
        settings = self.db.char.reagentDeposit
    else
        settings = self.db.profile.reagentDeposit
    end
    if not settings.categories then
        settings.categories = CopyTable(profileDefaults.categories)
    end

    local dialog, contentFrame, header = CreateExternalWindow({
        name = "WarbandBankDepositPopup",
        title = (L and L["REAGENT_DEPOSIT_TITLE"]) or "Reagent Deposit Manager",
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        width = 460,
        height = 538,
        preventDuplicates = true,
        onClose = function()
            if self.SendMessage then
                self:SendMessage(E.REAGENT_DEPOSIT_CHANGED)
            end
        end,
    })

    if not dialog then return end

    local PADDING = 14
    local contentWidth = contentFrame:GetWidth()
    local yOffset = 12

    -- Master Enable Checkbox
    local enabledCB = CreateThemedCheckbox(contentFrame, settings.enabled)
    enabledCB:SetPoint("TOPLEFT", PADDING, -yOffset)

    local enabledLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    enabledLabel:SetPoint("LEFT", enabledCB, "RIGHT", 8, 0)
    enabledLabel:SetText((L and L["REAGENT_DEPOSIT_ENABLE"]) or "Enable Deposit Manager")
    ns.UI_SetTextColorRole(enabledLabel, "Bright")

    yOffset = yOffset + 28

    -- Auto-deposit on Bank Open Checkbox
    local autoCB = CreateThemedCheckbox(contentFrame, settings.autoDepositOnOpen)
    autoCB:SetPoint("TOPLEFT", PADDING, -yOffset)

    local autoLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    autoLabel:SetPoint("LEFT", autoCB, "RIGHT", 8, 0)
    autoLabel:SetText((L and L["REAGENT_DEPOSIT_AUTO_OPEN"]) or "Auto-deposit when Bank opens")
    ns.UI_SetTextColorRole(autoLabel, "Bright")

    autoCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText((L and L["REAGENT_DEPOSIT_AUTO_OPEN_DESC"]) or "Automatically transfers matching items to bank every time you open the bank frame.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoCB:SetScript("OnLeave", GameTooltip_Hide)

    yOffset = yOffset + 28

    -- Per-character Checkbox
    local perCharCB = CreateThemedCheckbox(contentFrame, isPerChar)
    perCharCB:SetPoint("TOPLEFT", PADDING, -yOffset)

    local un = UnitName("player")
    local charName = (un and not (issecretvalue and issecretvalue(un))) and un or "?"
    local perCharLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    perCharLabel:SetPoint("LEFT", perCharCB, "RIGHT", 8, 0)
    perCharLabel:SetText(string.format((L and L["REAGENT_DEPOSIT_CHAR_ONLY"]) or "Only For This Character (%s)", charName))
    ns.UI_SetTextColorRole(perCharLabel, "Bright")

    yOffset = yOffset + 32

    -- Separator
    local sep1 = contentFrame:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", PADDING, -yOffset)
    sep1:SetPoint("TOPRIGHT", -PADDING, -yOffset)
    sep1:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4)

    yOffset = yOffset + 12

    -- Destination Selection Header
    local destTitle = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    destTitle:SetPoint("TOPLEFT", PADDING, -yOffset)
    destTitle:SetText((L and L["REAGENT_DEPOSIT_DESTINATION"]) or "Destination")
    ns.UI_SetTextColorRole(destTitle, "Bright")

    yOffset = yOffset + 24

    local warbandRadio = ns.UI_CreateThemedRadioButton(contentFrame, settings.destination ~= "reagent")
    warbandRadio:SetPoint("TOPLEFT", PADDING + 4, -yOffset)

    local warbandBtn = CreateButton(contentFrame, 200, 20, nil, nil, true)
    warbandBtn:SetPoint("TOPLEFT", PADDING + 4, -yOffset)
    warbandBtn.radioButton = warbandRadio

    local warbandLabel = FontManager:CreateFontString(warbandBtn, "body", "OVERLAY")
    warbandLabel:SetPoint("LEFT", warbandRadio, "RIGHT", 6, 0)
    warbandLabel:SetText((L and L["REAGENT_DEPOSIT_DEST_WARBAND"]) or "Warband Bank (Account)")
    ns.UI_SetTextColorRole(warbandLabel, "Bright")

    local reagentRadio = ns.UI_CreateThemedRadioButton(contentFrame, settings.destination == "reagent")
    reagentRadio:SetPoint("TOPLEFT", PADDING + 230, -yOffset)

    local reagentBtn = CreateButton(contentFrame, 190, 20, nil, nil, true)
    reagentBtn:SetPoint("TOPLEFT", PADDING + 230, -yOffset)
    reagentBtn.radioButton = reagentRadio

    local reagentLabel = FontManager:CreateFontString(reagentBtn, "body", "OVERLAY")
    reagentLabel:SetPoint("LEFT", reagentRadio, "RIGHT", 6, 0)
    reagentLabel:SetText((L and L["REAGENT_DEPOSIT_DEST_REAGENT"]) or "Personal Reagent Bank")
    ns.UI_SetTextColorRole(reagentLabel, "Bright")

    warbandBtn:SetScript("OnClick", function()
        warbandRadio.innerDot:Show()
        reagentRadio.innerDot:Hide()
        settings.destination = "warband"
    end)

    reagentBtn:SetScript("OnClick", function()
        reagentRadio.innerDot:Show()
        warbandRadio.innerDot:Hide()
        settings.destination = "reagent"
    end)

    yOffset = yOffset + 30

    -- Separator
    local sep2 = contentFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", PADDING, -yOffset)
    sep2:SetPoint("TOPRIGHT", -PADDING, -yOffset)
    sep2:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4)

    yOffset = yOffset + 12

    -- Categories Header & Select All / Clear All
    local catTitle = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    catTitle:SetPoint("TOPLEFT", PADDING, -yOffset)
    catTitle:SetText((L and L["REAGENT_DEPOSIT_CATEGORIES"]) or "Deposit Categories")
    ns.UI_SetTextColorRole(catTitle, "Bright")

    local selectAllBtn = CreateButton(contentFrame, 75, 18, nil, nil, true)
    selectAllBtn:SetPoint("TOPRIGHT", -PADDING - 75, -yOffset + 2)
    local selectAllLabel = FontManager:CreateFontString(selectAllBtn, "small", "OVERLAY")
    selectAllLabel:SetPoint("CENTER", 0, 0)
    selectAllLabel:SetText((L and L["REAGENT_DEPOSIT_SELECT_ALL"]) or "Select All")
    ns.UI_SetTextColorRole(selectAllLabel, "Accent")

    local clearAllBtn = CreateButton(contentFrame, 65, 18, nil, nil, true)
    clearAllBtn:SetPoint("TOPRIGHT", -PADDING, -yOffset + 2)
    local clearAllLabel = FontManager:CreateFontString(clearAllBtn, "small", "OVERLAY")
    clearAllLabel:SetPoint("CENTER", 0, 0)
    clearAllLabel:SetText((L and L["REAGENT_DEPOSIT_CLEAR_ALL"]) or "Clear All")
    ns.UI_SetTextColorRole(clearAllLabel, "Muted")

    yOffset = yOffset + 26

    -- Category Checkbox Grid (2 columns x 6 rows)
    local categoryCheckboxes = {}
    local colW = 210
    local rowH = 26

    for i = 1, #CATEGORY_KEYS do
        local catDef = CATEGORY_KEYS[i]
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local posX = PADDING + (col * colW)
        local posY = yOffset + (row * rowH)

        local isChecked = settings.categories[catDef.key] ~= false
        local cb = CreateThemedCheckbox(contentFrame, isChecked)
        cb:SetPoint("TOPLEFT", posX, -posY)

        local iconTex = contentFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(16, 16)
        iconTex:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        iconTex:SetTexture(catDef.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local lbl = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        lbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        lbl:SetText((L and L[catDef.locKey]) or catDef.default)
        ns.UI_SetTextColorRole(lbl, "Bright")

        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            if self.checkTexture then self.checkTexture:SetShown(v) end
            settings.categories[catDef.key] = v
        end)

        categoryCheckboxes[catDef.key] = cb
    end

    selectAllBtn:SetScript("OnClick", function()
        for k, cb in pairs(categoryCheckboxes) do
            cb:SetChecked(true)
            if cb.checkTexture then cb.checkTexture:SetShown(true) end
            settings.categories[k] = true
        end
    end)

    clearAllBtn:SetScript("OnClick", function()
        for k, cb in pairs(categoryCheckboxes) do
            cb:SetChecked(false)
            if cb.checkTexture then cb.checkTexture:SetShown(false) end
            settings.categories[k] = false
        end
    end)

    -- Bottom Action: Deposit Now Button
    local depositNowBtn = CreateButton(contentFrame, contentWidth - (PADDING * 2), 34)
    depositNowBtn:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 16)

    local btnText = FontManager:CreateFontString(depositNowBtn, "subtitle", "OVERLAY")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText((L and L["REAGENT_DEPOSIT_NOW"]) or "Deposit Items Now")
    ns.UI_SetTextColorRole(btnText, "Bright")

    local function UpdateDepositNowButtonState()
        local bankOpen = (WarbandNexus and WarbandNexus.bankIsOpen)
        if bankOpen then
            depositNowBtn:Enable()
            depositNowBtn:SetAlpha(1.0)
            depositNowBtn:SetScript("OnEnter", nil)
        else
            depositNowBtn:Disable()
            depositNowBtn:SetAlpha(0.45)
            depositNowBtn:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_TOP")
                GameTooltip:SetText((L and L["REAGENT_DEPOSIT_BANK_CLOSED_TIP"]) or "Open your bank or Warband bank to deposit items now.", 1, 0.82, 0.2, 1, true)
                GameTooltip:Show()
            end)
            depositNowBtn:SetScript("OnLeave", GameTooltip_Hide)
        end
    end

    UpdateDepositNowButtonState()

    depositNowBtn:SetScript("OnClick", function()
        if not WarbandNexus.bankIsOpen then return end
        if WarbandNexus.TriggerReagentDeposit then
            WarbandNexus:TriggerReagentDeposit(true)
            btnText:SetText((L and L["REAGENT_DEPOSIT_SENT"]) or "Depositing...")
            C_Timer.After(1.5, function()
                if btnText and btnText.SetText then
                    btnText:SetText((L and L["REAGENT_DEPOSIT_NOW"]) or "Deposit Items Now")
                end
            end)
        end
    end)

    -- Toggle Handlers
    enabledCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if self.checkTexture then self.checkTexture:SetShown(checked) end
        settings.enabled = checked
    end)

    autoCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if self.checkTexture then self.checkTexture:SetShown(checked) end
        settings.autoDepositOnOpen = checked
    end)

    perCharCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if self.checkTexture then self.checkTexture:SetShown(checked) end
        if checked then
            if not WarbandNexus.db.char.reagentDeposit then
                WarbandNexus.db.char.reagentDeposit = CopyTable(WarbandNexus.db.profile.reagentDeposit or profileDefaults)
            end
            WarbandNexus.db.char.reagentDeposit.perCharacter = true
            settings = WarbandNexus.db.char.reagentDeposit
        else
            if WarbandNexus.db.char.reagentDeposit then
                WarbandNexus.db.char.reagentDeposit.perCharacter = false
            end
            settings = WarbandNexus.db.profile.reagentDeposit
        end
        -- Refresh UI
        enabledCB:SetChecked(settings.enabled)
        if enabledCB.checkTexture then enabledCB.checkTexture:SetShown(settings.enabled) end
        autoCB:SetChecked(settings.autoDepositOnOpen)
        if autoCB.checkTexture then autoCB.checkTexture:SetShown(settings.autoDepositOnOpen) end
        if settings.destination == "reagent" then
            reagentRadio.innerDot:Show()
            warbandRadio.innerDot:Hide()
        else
            warbandRadio.innerDot:Show()
            reagentRadio.innerDot:Hide()
        end
        for k, cb in pairs(categoryCheckboxes) do
            local on = settings.categories and settings.categories[k] ~= false
            cb:SetChecked(on)
            if cb.checkTexture then cb.checkTexture:SetShown(on) end
        end
    end)

    dialog:Show()
end
