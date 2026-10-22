--[[
    Warband Nexus - Plans dialogs
    Custom plan dialog + storage, Great Vault (weekly) plan dialog, CloseAllPlanDialogs.
    WN_FACTORY: Vault slot grid uses Factory first (`CreateContainer` / `CreateButton`); Custom Plan dialogs
    (reset-cycle toggles / duration +/-) use Factory-backed buttons where `ApplyVisuals` borders apply;
    legacy `BackdropTemplate` path kept when Factory returns nil.
    Split from PlansUI.lua (Lua 5.1 local limit). Loaded before PlansUI.lua, which calls Dialogs.Install.
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management
local issecretvalue = issecretvalue

local Dialogs = ns.PlansUI_Dialogs or {}
ns.PlansUI_Dialogs = Dialogs

local COLORS = ns.UI_COLORS
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateIcon = ns.UI_CreateIcon
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateExternalWindow = ns.UI_CreateExternalWindow
local FormatNumber = ns.UI_FormatNumber
local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing
local format = string.format

-- Bound from PlansUI.lua via Dialogs.Install (file-local helpers there).
local SafePlayerName
local SafeRealmName
local ControlChromeBackdrop
local ApplyPlansChrome

function Dialogs.Install(addon, deps)
    SafePlayerName = deps.SafePlayerName
    SafeRealmName = deps.SafeRealmName
    ControlChromeBackdrop = deps.ControlChromeBackdrop
    ApplyPlansChrome = deps.ApplyPlansChrome
end

-- CUSTOM PLAN DIALOG

function WarbandNexus:ShowCustomPlanDialog()
    -- Disable Add Custom button to prevent multiple dialogs
    if self.addCustomBtn then
        self.addCustomBtn:Disable()
        self.addCustomBtn:SetAlpha(0.5)
    end

    -- All dialog geometry lives here; blocks stack top-down via relative anchors.
    local ps = (ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK) or {}
    local shellLayout = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local LAYOUT = {
        PAD = ps.SIDE or 12,
        BLOCK_GAP = ps.BLOCK_GAP or 8,
        SECTION_GAP = ps.SECTION_GAP or 12,
        BOTTOM_PAD = ps.BOTTOM_PAD or 12,
        HEADER_H = shellLayout.HEADER_BAR_HEIGHT or shellLayout.EXTERNAL_DIALOG_HEADER_HEIGHT or 40,
        DIALOG_W = 480,
        MIN_CONTENT_W = 280,
        CHAR_HDR_H = 45,
        CHAR_ICON = 36,
        CHAR_ICON_INNER = 28,
        CHAR_ICON_X = 12,
        CHAR_NAME_GAP = 10,
        LABEL_H = 16,          -- reserve; grown to the measured font height below
        LABEL_GAP = 6,         -- label -> its control
        INPUT_H = 35,
        INPUT_INSET_X = 8,
        INPUT_INSET_Y = 2,
        MIN_INPUT_W = 120,
        TOGGLE_H = 28,
        TOGGLE_GAP = ps.BLOCK_GAP or 8,
        STEPPER = 28,
        STEPPER_GAP = 12,
        UNIT_GAP = 10,
        COUNT_W = 30,
        COUNT_W_INFINITE = 56,
        DURATION_LABEL_W = 160,
        CHECK_ROW_H = 20,
        CHECK_LABEL_GAP = 8,
        FOOTER_BTN_W = 100,
        FOOTER_BTN_GAP = 10,
        BUTTON_H = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32,
    }
    -- Duration row: stepper line, gap, "repeat forever" checkbox line.
    LAYOUT.DURATION_H = LAYOUT.STEPPER + LAYOUT.LABEL_GAP + LAYOUT.CHECK_ROW_H
    local PAD = LAYOUT.PAD
    local classicBd = ns.UI_CLASSIC_DIALOG_BACKDROP and ns.UI_CLASSIC_DIALOG_BACKDROP.insets
    local isClassicShell = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    local shellInset = (isClassicShell and classicBd and classicBd.left) or 0
    local shellInsetV = (isClassicShell and classicBd and ((classicBd.top or 0) + (classicBd.bottom or 0))) or 0
    local CONTENT_W = math.max(LAYOUT.MIN_CONTENT_W, LAYOUT.DIALOG_W - (shellInset * 2) - (PAD * 2))
    local INPUT_H = LAYOUT.INPUT_H
    local CHAR_HDR_H = LAYOUT.CHAR_HDR_H

    --- Sum of the stacked blocks (duration row is always reserved so toggling never clips).
    local function StackedDialogHeight(labelH)
        local fieldH = labelH + LAYOUT.LABEL_GAP + INPUT_H + LAYOUT.SECTION_GAP
        local contentH = PAD + CHAR_HDR_H + LAYOUT.SECTION_GAP
            + fieldH * 2
            + labelH + LAYOUT.LABEL_GAP + LAYOUT.TOGGLE_H
            + LAYOUT.BLOCK_GAP + LAYOUT.DURATION_H
            + LAYOUT.SECTION_GAP + LAYOUT.BUTTON_H + LAYOUT.BOTTOM_PAD
        return LAYOUT.HEADER_H + shellInsetV + contentH
    end

    --- Full-width stacking: TOP edges hang under `prev` with symmetric left/right edges.
    local function StackBelow(frame, prev, gap, height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
        frame:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -gap)
        if height then frame:SetHeight(height) end
    end
    local DIALOG_H = StackedDialogHeight(LAYOUT.LABEL_H)

    -- Get character info
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "CustomPlanDialog",
        title = (ns.L and ns.L["CREATE_CUSTOM_PLAN"]) or "Create Custom Plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,
        width = LAYOUT.DIALOG_W,
        height = DIALOG_H,
        onClose = function()
            -- Re-enable Add Custom button
            if WarbandNexus.addCustomBtn then
                WarbandNexus.addCustomBtn:Enable()
                WarbandNexus.addCustomBtn:SetAlpha(1)
            end
        end
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        if self.addCustomBtn then
            self.addCustomBtn:Enable()
            self.addCustomBtn:SetAlpha(1)
        end
        return
    end
    
    -- Character section with icon (using Factory pattern)
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, CONTENT_W, CHAR_HDR_H, false)
    if ns.UI_PageStack_AnchorBody then
        ns.UI_PageStack_AnchorBody(contentFrame, charFrame, PAD)
    else
        charFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)
        charFrame:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD)
    end
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    -- Character race icon with border (using Factory pattern)
    local iconContainer = ns.UI.Factory:CreateContainer(charFrame, LAYOUT.CHAR_ICON, LAYOUT.CHAR_ICON)
    iconContainer:SetPoint("LEFT", LAYOUT.CHAR_ICON_X, 0)
    
    -- Apply border with class color (thin icon well in classic)
    if ApplyPlansChrome then
        ApplyPlansChrome(iconContainer, COLORS.bgCard, nil, { iconWell = true })
    end
    
    -- Character race icon (using atlas)
    local charIconFrame = CreateIcon(iconContainer, raceAtlas, LAYOUT.CHAR_ICON_INNER, true, nil, true)
    charIconFrame:SetPoint("CENTER", 0, 0)
    charIconFrame:Show()
    
    -- Character name with class color (larger font)
    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", LAYOUT.CHAR_NAME_GAP, 0)
    if classColors then
        charText:SetTextColor(classColors.r, classColors.g, classColors.b)
    elseif ns.UI_GetSemanticGoldColor then
        local gr, gg, gb = ns.UI_GetSemanticGoldColor()
        charText:SetTextColor(gr, gg, gb)
    else
        charText:SetTextColor(1, 0.8, 0)
    end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- Title label
    local titleLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    local mutedHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"
    titleLabel:SetText(mutedHex .. ((ns.L and ns.L["TITLE_LABEL"]) or "Title:") .. "|r")
    -- One label height for every field label: reserve, grown to the live font height.
    local labelH = math.max(LAYOUT.LABEL_H, math.ceil(titleLabel:GetStringHeight() or 0))
    titleLabel:SetJustifyH("LEFT")
    StackBelow(titleLabel, charFrame, LAYOUT.SECTION_GAP, labelH)
    
    -- Title input container (using Factory pattern)
    local titleInputBg = ns.UI.Factory:CreateContainer(contentFrame, CONTENT_W, INPUT_H)
    StackBelow(titleInputBg, titleLabel, LAYOUT.LABEL_GAP, INPUT_H)
    
    if ns.UI_ApplyInputChrome then
        ns.UI_ApplyInputChrome(titleInputBg)
    end
    
    local titleInput = ns.UI.Factory:CreateEditBox(titleInputBg)
    titleInput:SetSize(math.max(LAYOUT.MIN_INPUT_W, CONTENT_W - LAYOUT.INPUT_INSET_X * 2), INPUT_H - LAYOUT.INPUT_INSET_Y * 2)
    titleInput:SetPoint("LEFT", LAYOUT.INPUT_INSET_X, 0)
    ns.UI_SetTextColorRole(titleInput, "Bright")
    titleInput:SetAutoFocus(false)
    titleInput:SetMaxLetters(32)  -- Max 32 characters
    titleInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Prevent Enter key from creating new lines
    titleInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            if not text or (issecretvalue and issecretvalue(text)) then return end
            self:SetText(text:gsub("[\n\r]", ""))
        end
    end)
    
    -- Make container clickable to focus EditBox
    titleInputBg:EnableMouse(true)
    titleInputBg:SetScript("OnMouseDown", function()
        titleInput:SetFocus()
    end)
    
    -- Description label
    local descLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    descLabel:SetJustifyH("LEFT")
    StackBelow(descLabel, titleInputBg, LAYOUT.SECTION_GAP, labelH)
    descLabel:SetText(mutedHex .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
    
    -- Description input container (scrollable, single line) (using Factory pattern)
    local descInputBg = ns.UI.Factory:CreateContainer(contentFrame, CONTENT_W, INPUT_H)
    StackBelow(descInputBg, descLabel, LAYOUT.LABEL_GAP, INPUT_H)
    
    if ns.UI_ApplyInputChrome then
        ns.UI_ApplyInputChrome(descInputBg)
    end
    
    local descInput = ns.UI.Factory:CreateEditBox(descInputBg)
    descInput:SetSize(math.max(LAYOUT.MIN_INPUT_W, CONTENT_W - LAYOUT.INPUT_INSET_X * 2), INPUT_H - LAYOUT.INPUT_INSET_Y * 2)
    descInput:SetPoint("LEFT", LAYOUT.INPUT_INSET_X, 0)
    ns.UI_SetTextColorRole(descInput, "Bright")
    descInput:SetAutoFocus(false)
    descInput:SetMultiLine(false)  -- Single line only - prevents Enter from creating new lines
    descInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Limit to 300 characters total, max 30 characters per word
    descInput:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if not text then return end
        if issecretvalue and issecretvalue(text) then return end
        -- Remove any newlines that might have been inserted
        text = text:gsub("[\n\r]", " ")
        
        -- Enforce word length limit (max 30 chars per word)
        local maxWordLength = 30
        local words = {}
        local modified = false
        
        for word in text:gmatch("%S+") do  -- Split by whitespace
            if string.len(word) > maxWordLength then
                -- Truncate long word
                word = string.sub(word, 1, maxWordLength)
                modified = true
            end
            table.insert(words, word)
        end
        
        -- Reconstruct text with single spaces
        if modified then
            text = table.concat(words, " ")
        end
        
        -- Enforce 300 character limit
        local maxChars = 300
        if string.len(text) > maxChars then
            text = string.sub(text, 1, maxChars)
            modified = true
        end
        
        -- Update text if modified
        if modified then
            local cur = self:GetText()
            if cur and issecretvalue and issecretvalue(cur) then return end
            if text ~= cur then
                local cursorPos = self:GetCursorPosition()
                self:SetText(text)
                self:SetCursorPosition(math.min(cursorPos, string.len(text)))
            end
        end
    end)
    
    -- Prevent Enter key from creating new lines
    descInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            if not text or (issecretvalue and issecretvalue(text)) then return end
            local cursorPos = self:GetCursorPosition()
            self:SetText(text:gsub("[\n\r]", " "))
            self:SetCursorPosition(cursorPos)
        end
    end)
    
    -- Make container clickable to focus EditBox
    descInputBg:EnableMouse(true)
    descInputBg:SetScript("OnMouseDown", function()
        descInput:SetFocus()
    end)
    
    -- Reset Cycle selection
    local resetLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    resetLabel:SetJustifyH("LEFT")
    StackBelow(resetLabel, descInputBg, LAYOUT.SECTION_GAP, labelH)
    resetLabel:SetText(mutedHex .. ((ns.L and ns.L["RESET_CYCLE_LABEL"]) or "Reset Cycle:") .. "|r")
    
    local PlanDlgF = ns.UI and ns.UI.Factory
    
    --- Factory rows use BORDER_REGISTRY textures (UpdateBorderColor); legacy uses SetBackdropBorderColor.
    local function PlanDlgPulseBorder(btn, borderRgb)
        if not btn then return end
        if btn.BorderTop and UpdateBorderColor then
            UpdateBorderColor(btn, borderRgb)
        elseif btn.SetBackdropBorderColor then
            local r, g, b, a = borderRgb[1], borderRgb[2], borderRgb[3], borderRgb[4] or 1
            btn:SetBackdropBorderColor(r, g, b, a)
        end
    end

    -- Reset cycle toggle state
    local selectedResetType = "none"
    local selectedCycleCount = 7  -- Default cycle count
    local selectedInfiniteRepeat = false
    
    -- Three equal toggle columns across the content width; the last absorbs rounding.
    local TOGGLE_COUNT = 3
    local toggleColW = math.floor((CONTENT_W - LAYOUT.TOGGLE_GAP * (TOGGLE_COUNT - 1)) / TOGGLE_COUNT)

    local function CreateResetToggle(parent, label, value, colIndex)
        local colW = toggleColW
        if colIndex == TOGGLE_COUNT then
            colW = CONTENT_W - (toggleColW + LAYOUT.TOGGLE_GAP) * (TOGGLE_COUNT - 1)
        end
        local btn = PlanDlgF and PlanDlgF:CreateButton(parent, colW, LAYOUT.TOGGLE_H, false)
        if btn then btn._wnPlanDlgFactoryToggle = true end
        local useClassic = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
        if not btn and useClassic then
            btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            btn:SetSize(colW, LAYOUT.TOGGLE_H)
            btn:SetText("")
            btn._wnBlizzardButton = true
            btn._wnPlanDlgFactoryToggle = true
        elseif not btn and not useClassic then
            btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetSize(colW, LAYOUT.TOGGLE_H)
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(btn)) or 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            btn:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1)
            btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
        elseif btn and ApplyPlansChrome then
            ApplyPlansChrome(btn, { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1 },
                { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        end
        btn:SetSize(colW, LAYOUT.TOGGLE_H)
        btn:SetPoint("TOPLEFT", resetLabel, "BOTTOMLEFT", (colIndex - 1) * (toggleColW + LAYOUT.TOGGLE_GAP), -LAYOUT.LABEL_GAP)

        local text = FontManager:CreateFontString(btn, "body", "OVERLAY")
        text:SetPoint("CENTER")
        text:SetText(label)
        ns.UI_SetTextColorRole(text, "Muted")
        btn.label = text
        btn.value = value

        return btn
    end
    
    local resetBtnNone = CreateResetToggle(contentFrame, (ns.L and ns.L["RESET_NONE"]) or "None", "none", 1)
    local resetBtnDaily = CreateResetToggle(contentFrame, (ns.L and ns.L["DAILY_RESET"]) or "Daily Reset", "daily", 2)
    local resetBtnWeekly = CreateResetToggle(contentFrame, (ns.L and ns.L["WEEKLY_RESET"]) or "Weekly Reset", "weekly", 3)
    
    local resetButtons = { resetBtnNone, resetBtnDaily, resetBtnWeekly }
    
    -- Duration row (hidden by default, shown when Daily/Weekly selected)
    local durationRow = PlanDlgF and PlanDlgF:CreateContainer(contentFrame, CONTENT_W, LAYOUT.DURATION_H, false)
    if not durationRow then
        durationRow = CreateFrame("Frame", nil, contentFrame)
        durationRow:SetSize(CONTENT_W, LAYOUT.DURATION_H)
    end
    -- Spans the toggle row exactly (first toggle's left edge .. last toggle's right edge).
    durationRow:ClearAllPoints()
    durationRow:SetPoint("TOPLEFT", resetBtnNone, "BOTTOMLEFT", 0, -LAYOUT.BLOCK_GAP)
    durationRow:SetPoint("TOPRIGHT", resetBtnWeekly, "BOTTOMRIGHT", 0, -LAYOUT.BLOCK_GAP)
    durationRow:SetHeight(LAYOUT.DURATION_H)
    durationRow:Hide()
    
    local durationLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    durationLabel:SetPoint("LEFT", durationRow, "TOPLEFT", 0, -LAYOUT.STEPPER / 2)
    ns.UI_SetTextColorRole(durationLabel, "Muted")
    
    -- Minus button (paired with Factory +plusBtn where SharedWidgets Factory is live)
    local minusBtn = PlanDlgF and PlanDlgF:CreateButton(durationRow, LAYOUT.STEPPER, LAYOUT.STEPPER, false)
    if minusBtn then minusBtn._wnPlanDlgDurStepper = true end
    local chromeBg = ControlChromeBackdrop()
    local planDlgClassic = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
    if not minusBtn and planDlgClassic then
        minusBtn = CreateFrame("Button", nil, durationRow, "UIPanelButtonTemplate")
        minusBtn:SetSize(LAYOUT.STEPPER, LAYOUT.STEPPER)
        minusBtn:SetText("-")
        minusBtn._wnBlizzardButton = true
        minusBtn._wnPlanDlgDurStepper = true
    elseif not minusBtn and not planDlgClassic then
        minusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
        minusBtn:SetSize(LAYOUT.STEPPER, LAYOUT.STEPPER)
        minusBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(minusBtn)) or 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        minusBtn:SetBackdropColor(chromeBg[1], chromeBg[2], chromeBg[3], chromeBg[4] or 1)
        minusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    elseif minusBtn and ApplyPlansChrome then
        ApplyPlansChrome(minusBtn, chromeBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end
    minusBtn:SetPoint("TOPLEFT", durationRow, "TOPLEFT", LAYOUT.DURATION_LABEL_W, 0)
    if minusBtn._wnBlizzardButton then
        minusBtn:SetText("-")
    else
        local minusText = FontManager:CreateFontString(minusBtn, "title", "OVERLAY")
        minusText:SetPoint("CENTER", 0, 1)
        minusText:SetText("-")
        ns.UI_SetTextColorRole(minusText, "Bright")
    end
    
    -- Count display
    local countDisplay = FontManager:CreateFontString(durationRow, "title", "OVERLAY")
    countDisplay:SetPoint("LEFT", minusBtn, "RIGHT", LAYOUT.STEPPER_GAP, 0)
    ns.UI_SetTextColorRole(countDisplay, "Bright")
    countDisplay:SetWidth(LAYOUT.COUNT_W)
    countDisplay:SetJustifyH("CENTER")
    
    local plusBtn = PlanDlgF and PlanDlgF:CreateButton(durationRow, LAYOUT.STEPPER, LAYOUT.STEPPER, false)
    if plusBtn then plusBtn._wnPlanDlgDurStepper = true end
    if not plusBtn and planDlgClassic then
        plusBtn = CreateFrame("Button", nil, durationRow, "UIPanelButtonTemplate")
        plusBtn:SetSize(LAYOUT.STEPPER, LAYOUT.STEPPER)
        plusBtn:SetText("+")
        plusBtn._wnBlizzardButton = true
        plusBtn._wnPlanDlgDurStepper = true
    elseif not plusBtn and not planDlgClassic then
        plusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
        plusBtn:SetSize(LAYOUT.STEPPER, LAYOUT.STEPPER)
        plusBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(plusBtn)) or 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        plusBtn:SetBackdropColor(chromeBg[1], chromeBg[2], chromeBg[3], chromeBg[4] or 1)
        plusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    elseif plusBtn and ApplyPlansChrome then
        ApplyPlansChrome(plusBtn, chromeBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end
    plusBtn:SetPoint("LEFT", countDisplay, "RIGHT", LAYOUT.STEPPER_GAP, 0)
    if plusBtn._wnBlizzardButton then
        plusBtn:SetText("+")
    else
        local plusText = FontManager:CreateFontString(plusBtn, "title", "OVERLAY")
        plusText:SetPoint("CENTER", 0, 1)
        plusText:SetText("+")
        ns.UI_SetTextColorRole(plusText, "Bright")
    end
    
    -- Update duration display
    local function UpdateDurationDisplay()
        countDisplay:SetText(tostring(selectedCycleCount))
        durationLabel:SetText(((ns.L and ns.L["DURATION_LABEL"]) or "Duration") .. ":  ")
    end
    
    -- Unit label after count
    local unitLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    unitLabel:SetPoint("LEFT", plusBtn, "RIGHT", LAYOUT.UNIT_GAP, 0)
    ns.UI_SetTextColorRole(unitLabel, "Muted")

    local foreverCb = CreateThemedCheckbox(durationRow, false)
    local foreverY = -(LAYOUT.STEPPER + LAYOUT.LABEL_GAP)
    if foreverCb then
        foreverCb:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, foreverY)
    end
    local foreverLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    if foreverCb then
        foreverLabel:SetPoint("LEFT", foreverCb, "RIGHT", LAYOUT.CHECK_LABEL_GAP, 0)
    else
        foreverLabel:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, foreverY)
    end
    foreverLabel:SetPoint("TOPRIGHT", durationRow, "TOPRIGHT", 0, foreverY)
    foreverLabel:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(foreverLabel, "Muted")
    foreverLabel:SetWordWrap(true)
    foreverLabel:SetMaxLines(2)
    foreverLabel:SetText((ns.L and ns.L["CUSTOM_PLAN_REPEAT_UNTIL_REMOVED"]) or "Repeat until this plan is deleted")
    
    local function UpdateUnitLabel()
        if selectedResetType == "daily" then
            unitLabel:SetText((ns.L and ns.L["DAYS_LABEL"]) or "days")
        elseif selectedResetType == "weekly" then
            unitLabel:SetText((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
        end
    end
    
    minusBtn:SetScript("OnClick", function()
        if selectedCycleCount > 1 then
            selectedCycleCount = selectedCycleCount - 1
            UpdateDurationDisplay()
        end
    end)
    minusBtn:SetScript("OnEnter", function(self)
        PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end)
    minusBtn:SetScript("OnLeave", function(self)
        PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end)
    
    plusBtn:SetScript("OnClick", function()
        if selectedCycleCount < 99 then
            selectedCycleCount = selectedCycleCount + 1
            UpdateDurationDisplay()
        end
    end)
    plusBtn:SetScript("OnEnter", function(self)
        PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end)
    plusBtn:SetScript("OnLeave", function(self)
        PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end)

    local function UpdateInfiniteDurationUI()
        if foreverCb then
            foreverCb:SetChecked(selectedInfiniteRepeat)
            if foreverCb.innerDot then
                foreverCb.innerDot:SetShown(selectedInfiniteRepeat)
            end
        end
        if selectedInfiniteRepeat then
            minusBtn:Disable()
            plusBtn:Disable()
            countDisplay:SetWidth(LAYOUT.COUNT_W_INFINITE)
            countDisplay:SetText("--")
            unitLabel:SetText("")
        else
            minusBtn:Enable()
            plusBtn:Enable()
            countDisplay:SetWidth(LAYOUT.COUNT_W)
            UpdateDurationDisplay()
            UpdateUnitLabel()
        end
    end

    if foreverCb then
        foreverCb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            if self.innerDot then
                self.innerDot:SetShown(checked)
            end
            selectedInfiniteRepeat = (checked == true or checked == 1)
            UpdateInfiniteDurationUI()
        end)
    end
    
    -- Update button visuals based on selection
    local function UpdateResetButtons()
        for bi = 1, #resetButtons do
            local btn = resetButtons[bi]
            local isSel = (btn.value == selectedResetType)
            if btn._wnPlanDlgFactoryToggle and btn._wnBlizzardButton then
                if ns.UI_ApplyClassicNavTabActiveState then
                    ns.UI_ApplyClassicNavTabActiveState(btn, isSel)
                end
                if isSel then
                    if ns.UI_GetSemanticGoldColor then
                        local gr, gg, gb = ns.UI_GetSemanticGoldColor()
                        btn.label:SetTextColor(gr, gg, gb)
                    else
                        ns.UI_SetTextColorRole(btn.label, "Bright")
                    end
                else
                    ns.UI_SetTextColorRole(btn.label, "Muted")
                end
            elseif btn._wnPlanDlgFactoryToggle and ApplyPlansChrome then
                if isSel then
                    ApplyPlansChrome(btn,
                        { COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1 },
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
                else
                    ApplyPlansChrome(btn,
                        { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1 },
                        { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
                end
                btn.label:SetTextColor(isSel and 1 or 0.7,
                    isSel and 1 or 0.7,
                    isSel and 1 or 0.7)
            elseif isSel and btn.SetBackdropColor and not planDlgClassic then
                btn:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
                ns.UI_SetTextColorRole(btn.label, "Bright")
            elseif btn.SetBackdropColor and not planDlgClassic then
                btn:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1)
                btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
                ns.UI_SetTextColorRole(btn.label, "Muted")
            end
        end
        
        -- Show/hide duration row based on selection
        if selectedResetType == "none" then
            selectedInfiniteRepeat = false
            durationRow:Hide()
        else
            -- Set default cycle counts based on type
            if selectedResetType == "daily" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            elseif selectedResetType == "weekly" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            end
            UpdateDurationDisplay()
            UpdateUnitLabel()
            UpdateInfiniteDurationUI()
            durationRow:Show()
        end
    end
    
    for bi = 1, #resetButtons do
        local btn = resetButtons[bi]
        btn:SetScript("OnClick", function(self)
            selectedResetType = self.value
            -- Set sensible defaults when switching type
            if self.value == "daily" then
                selectedCycleCount = 7
            elseif self.value == "weekly" then
                selectedCycleCount = 4
            end
            UpdateResetButtons()
        end)
        btn:SetScript("OnEnter", function(self)
            if self._wnBlizzardButton then return end
            if self.value ~= selectedResetType then
                PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._wnBlizzardButton then return end
            if self.value ~= selectedResetType then
                PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
            end
        end)
    end
    
    -- Set initial state (None selected)
    UpdateResetButtons()
    
    -- Buttons (symmetrically centered with more spacing from inputs)
    local footerX = (LAYOUT.FOOTER_BTN_W + LAYOUT.FOOTER_BTN_GAP) / 2
    local saveBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["SAVE"]) or "Save", LAYOUT.FOOTER_BTN_W)
    saveBtn:SetPoint("BOTTOM", -footerX, LAYOUT.BOTTOM_PAD)
    saveBtn:SetScript("OnClick", function()
        local title = titleInput:GetText()
        local description = descInput:GetText()
        if title and issecretvalue and issecretvalue(title) then return end
        if description and issecretvalue and issecretvalue(description) then
            description = nil
        end
        
        if title and title ~= "" then
            local cycleCount = (selectedResetType ~= "none") and selectedCycleCount or nil
            local infiniteRepeat = (selectedResetType ~= "none") and selectedInfiniteRepeat or false
            WarbandNexus:SaveCustomPlan(title, description, selectedResetType, cycleCount, infiniteRepeat)
            dialog.Close()
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", LAYOUT.FOOTER_BTN_W)
    cancelBtn:SetPoint("BOTTOM", footerX, LAYOUT.BOTTOM_PAD)
    cancelBtn:SetScript("OnClick", function()
        dialog.Close()
    end)

    -- Re-derive the dialog height when the live label font is taller than the reserve.
    if labelH ~= LAYOUT.LABEL_H then
        dialog:SetHeight(StackedDialogHeight(labelH))
    end
    
    dialog:Show()
    titleInput:SetFocus()
end

-- CUSTOM PLAN STORAGE: SaveCustomPlan / GetCustomPlans / CompleteCustomPlan live in
-- Modules/PlansManager.lua (2026-10-22: the View no longer writes db.global.customPlans).

-- WEEKLY VAULT PLAN DIALOG

function WarbandNexus:ShowWeeklyPlanDialog()
    local COLORS = ns.UI_COLORS
    -- All dialog geometry lives here; the create form stacks top-down via relative anchors.
    local ps = (ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK) or {}
    local shellLayout = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local LAYOUT = {
        PAD = ps.SIDE or 12,
        BLOCK_GAP = ps.BLOCK_GAP or 8,
        SECTION_GAP = ps.SECTION_GAP or 12,
        BOTTOM_PAD = ps.BOTTOM_PAD or 12,
        HEADER_H = shellLayout.HEADER_BAR_HEIGHT or shellLayout.EXTERNAL_DIALOG_HEADER_HEIGHT or 40,
        DIALOG_W = 640,
        DIALOG_H_HAS = 280,    -- "plan already exists" notice (wrapped text height is runtime)
        MIN_CONTENT_W = 320,
        CHAR_HDR_H = 48,
        CHAR_ICON = 36,
        CHAR_ICON_INNER = 28,
        CHAR_NAME_GAP = 10,
        PROGRESS_HEADER_H = 20,
        COL_SPACING = 16,
        -- Card height = icon + title + slot row + padding (no per-slot panel fills).
        ICON_TOP_PAD = 10,
        ICON_SIZE = 48,
        TITLE_UNDER_ICON = 6,
        TITLE_BLOCK = 26,
        BAND_TOP_GAP = 6,
        SLOT_STAR = 24,
        SLOT_STAR_TEXT_GAP = 6,
        SLOT_TEXT_BLOCK = 22,
        CARD_BOTTOM_PAD = 10,
        FOOTER_BTN_W = 120,
        FOOTER_BTN_GAP = 10,
        BUTTON_H = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32,
    }
    LAYOUT.SLOTS_BAND_H = LAYOUT.SLOT_STAR + LAYOUT.SLOT_STAR_TEXT_GAP + LAYOUT.SLOT_TEXT_BLOCK
    LAYOUT.COL_H = LAYOUT.ICON_TOP_PAD + LAYOUT.ICON_SIZE + LAYOUT.TITLE_UNDER_ICON + LAYOUT.TITLE_BLOCK
        + LAYOUT.BAND_TOP_GAP + LAYOUT.SLOTS_BAND_H + LAYOUT.CARD_BOTTOM_PAD
    local PAD = LAYOUT.PAD
    local VAULT_DLG_W = LAYOUT.DIALOG_W
    local classicBd = ns.UI_CLASSIC_DIALOG_BACKDROP and ns.UI_CLASSIC_DIALOG_BACKDROP.insets
    local isClassicShell = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    local shellInset = (isClassicShell and classicBd and classicBd.left) or 0
    local shellInsetV = (isClassicShell and classicBd and ((classicBd.top or 0) + (classicBd.bottom or 0))) or 0
    local CONTENT_W = math.max(LAYOUT.MIN_CONTENT_W, VAULT_DLG_W - (shellInset * 2) - (PAD * 2))
    local CHAR_HDR_H = LAYOUT.CHAR_HDR_H
    -- Create form: char bar, progress header, card row, footer buttons.
    local VAULT_DLG_H_NEW = LAYOUT.HEADER_H + shellInsetV
        + PAD + CHAR_HDR_H + LAYOUT.SECTION_GAP
        + LAYOUT.PROGRESS_HEADER_H + LAYOUT.BLOCK_GAP + LAYOUT.COL_H
        + LAYOUT.SECTION_GAP + LAYOUT.BUTTON_H + LAYOUT.BOTTOM_PAD

    -- Get current character info
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    
    -- Check if current character already has a weekly plan
    local existingPlan = self:HasActiveWeeklyPlan(currentName, currentRealm)
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "WeeklyPlanDialog",
        title = (ns.L and ns.L["WEEKLY_VAULT_TRACKER"]) or "Weekly Vault Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",  -- Same as Daily Quest
        width = VAULT_DLG_W,
        height = existingPlan and LAYOUT.DIALOG_H_HAS or VAULT_DLG_H_NEW
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        return
    end
    
    -- Content area starts at top of content frame
    local contentY = -PAD
    
    -- Show existing plan message or creation form
    if existingPlan then
        -- Character already has a weekly plan
        local warningIconFrame3 = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther", 48, false, nil, true)
        warningIconFrame3:SetPoint("TOP", contentFrame, "TOP", 0, contentY)
        warningIconFrame3:Show()
        local warningIcon = warningIconFrame3.texture
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -15)
        local warnR, warnG, warnB = 1, 0.6, 0
        if ns.UI_GetSemanticOrangeColor then warnR, warnG, warnB = ns.UI_GetSemanticOrangeColor() end
        warningText:SetTextColor(warnR, warnG, warnB)
        warningText:SetText((ns.L and ns.L["WEEKLY_PLAN_EXISTS"]) or "Weekly Plan Already Exists")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -10)
        infoText:SetWidth(CONTENT_W)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        local descText = (ns.L and ns.L["WEEKLY_PLAN_EXISTS_DESC"] and format(ns.L["WEEKLY_PLAN_EXISTS_DESC"], currentName .. "-" .. currentRealm)) or (currentName .. "-" .. currentRealm .. " already has an active weekly vault plan. You can find it in the 'My Plans' category.")
        ns.UI_SetTextColorRole(infoText, "Muted")
        infoText:SetText(descText)
        
        -- Calculate text height to position button below
        local textHeight = infoText:GetStringHeight()
        
        -- OK button (positioned below text)
        local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -20)
        okBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    else
        -- Create new weekly plan form
        
        -- Same horizontal band as the three vault cards (symmetric content pad).
        local charBarW = CONTENT_W
        local charFrame = ns.UI.Factory:CreateContainer(contentFrame, charBarW, CHAR_HDR_H, false)
        if ns.UI_PageStack_AnchorBody then
            ns.UI_PageStack_AnchorBody(contentFrame, charFrame, PAD)
        else
            charFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)
            charFrame:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD)
        end
        
        -- Character race and class info
        local _, currentClass = UnitClass("player")
        local classColors = RAID_CLASS_COLORS[currentClass]
        local _, englishRace = UnitRace("player")
        local gender = UnitSex("player")
        local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
        
        -- Character race icon with border (centered within charFrame) (using Factory pattern)
        local iconContainer = ns.UI.Factory:CreateContainer(charFrame, LAYOUT.CHAR_ICON, LAYOUT.CHAR_ICON)
        iconContainer:SetPoint("LEFT", 0, 0)  -- Start from left edge
        
        -- Apply thin icon well (classic) / accent border (modern)
        if ApplyPlansChrome then
            ApplyPlansChrome(iconContainer, COLORS.bgCard, nil, { iconWell = true })
        end
        
        -- Character race icon (using atlas)
        local charIconFrame = CreateIcon(iconContainer, raceAtlas, LAYOUT.CHAR_ICON_INNER, true, nil, true)
        charIconFrame:SetPoint("CENTER", 0, 0)
        charIconFrame:Show()
        
        -- Character name with class color (larger font)
        local charName = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
        charName:SetPoint("LEFT", iconContainer, "RIGHT", LAYOUT.CHAR_NAME_GAP, 0)
        if classColors then
            charName:SetTextColor(classColors.r, classColors.g, classColors.b)
        else
            ns.UI_SetTextColorRole(charName, "Bright")
        end
        charName:SetText(currentName .. "-" .. currentRealm)
        
        -- Current progress preview (if API available)
        local progress = self:GetWeeklyVaultProgress(currentName, currentRealm)
        
        -- Fallback: If API not ready, use 0/0/0 progress
        if not progress then
            progress = {
                dungeonCount = 0,
                raidBossCount = 0,
                worldActivityCount = 0
            }
        end
        
        -- Weekly plan: which vault rows to track (toggled by clicking Mythic+ / Raids / World cards)
        local selectedSlots = { dungeon = true, raid = true, world = true }
        local slotColumnRefreshers = {}
        local function RefreshWeeklyPlanSlotSelections()
            for ri = 1, #slotColumnRefreshers do
                slotColumnRefreshers[ri]()
            end
        end

        if progress then
            local progressHeader = FontManager:CreateFontString(contentFrame, "header", "OVERLAY")
            progressHeader:SetPoint("TOPLEFT", charFrame, "BOTTOMLEFT", 0, -LAYOUT.SECTION_GAP)
            progressHeader:SetPoint("TOPRIGHT", charFrame, "BOTTOMRIGHT", 0, -LAYOUT.SECTION_GAP)
            progressHeader:SetHeight(LAYOUT.PROGRESS_HEADER_H)
            progressHeader:SetJustifyH("CENTER")
            ns.UI_SetTextColorRole(progressHeader, "Bright")
            progressHeader:SetText((ns.L and ns.L["CURRENT_PROGRESS"]) or "Current Progress")

            -- Card row: three equal columns; width from content column budget.
            local colSpacing = LAYOUT.COL_SPACING
            local colWidth = math.floor((CONTENT_W - 2 * colSpacing) / 3)
            local totalWidth = colWidth * 3 + colSpacing * 2
            local ICON_TOP_PAD = LAYOUT.ICON_TOP_PAD
            local ICON_SIZE = LAYOUT.ICON_SIZE
            local TITLE_UNDER_ICON = LAYOUT.TITLE_UNDER_ICON
            local BAND_TOP_GAP = LAYOUT.BAND_TOP_GAP
            local SLOT_STAR = LAYOUT.SLOT_STAR
            local SLOT_STAR_TEXT_GAP = LAYOUT.SLOT_STAR_TEXT_GAP
            local slotsBandH = LAYOUT.SLOTS_BAND_H
            local colHeight = LAYOUT.COL_H
            local startX = -(totalWidth / 2) + (colWidth / 2)
            local accentBorder = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.95 }
            local unselectedBorder = { 0.32, 0.32, 0.36, 0.8 }
            local disabledBorder = { 0.22, 0.22, 0.25, 0.45 }
            local baseBg = COLORS.bgLight
            local unselBg = COLORS.bg
            local disabledBg = COLORS.bg

            local function CreateProgressCol(index, iconAtlas, title, current, thresholds, slotKey)
                local xPos = startX + (index - 1) * (colWidth + colSpacing)
                local maxThreshold = thresholds[#thresholds] or 0
                local fullyComplete = maxThreshold > 0 and (current >= maxThreshold)
                if fullyComplete then
                    selectedSlots[slotKey] = false
                end

                local col = ns.UI.Factory:CreateContainer(contentFrame, colWidth, colHeight)
                col:SetPoint("TOP", progressHeader, "BOTTOM", xPos, -LAYOUT.BLOCK_GAP)
                col:SetClipsChildren(true)

                -- Large category icon
                local iconFrame2 = CreateIcon(col, iconAtlas, ICON_SIZE, true, nil, true)
                iconFrame2:SetPoint("TOP", 0, -ICON_TOP_PAD)
                iconFrame2:Show()

                local titleText = FontManager:CreateFontString(col, "title", "OVERLAY")
                titleText:SetWidth(colWidth - 10)
                titleText:SetWordWrap(true)
                if titleText.SetMaxLines then titleText:SetMaxLines(2) end
                titleText:SetJustifyH("CENTER")
                titleText:SetPoint("TOP", iconFrame2, "BOTTOM", 0, -TITLE_UNDER_ICON)
                ns.UI_SetTextColorRole(titleText, "Bright")
                titleText:SetText(title)

                -- Three vault slots in a row: star + text only (no slot panel background).
                local bandPad = 8
                local PUF = ns.UI and ns.UI.Factory
                local slotsBand = PUF and PUF:CreateContainer(col, math.max(40, colWidth - bandPad * 2), slotsBandH, false)
                if not slotsBand then
                    slotsBand = CreateFrame("Frame", nil, col)
                end
                slotsBand:SetSize(colWidth - bandPad * 2, slotsBandH)
                slotsBand:SetPoint("TOP", titleText, "BOTTOM", 0, -BAND_TOP_GAP)

                local nSlots = #thresholds
                local slotGap = 8
                local slotW = (slotsBand:GetWidth() - (nSlots - 1) * slotGap) / nSlots

                for ti = 1, nSlots do
                    local box = PUF and PUF:CreateContainer(slotsBand, math.max(8, slotW), slotsBandH, false)
                    if not box then
                        box = CreateFrame("Frame", nil, slotsBand)
                    end
                    box:SetSize(slotW, slotsBandH)
                    box:SetPoint("TOPLEFT", slotsBand, "TOPLEFT", (ti - 1) * (slotW + slotGap), 0)

                    local isComplete = current >= thresholds[ti]

                    local starTex = box:CreateTexture(nil, "ARTWORK")
                    starTex:SetSize(SLOT_STAR, SLOT_STAR)
                    starTex:SetPoint("TOP", box, "TOP", 0, -2)
                    starTex:SetAtlas("PetJournal-FavoritesIcon")
                    if isComplete then
                        starTex:SetVertexColor(1, 0.9, 0.25)
                    else
                        starTex:SetVertexColor(0.32, 0.32, 0.34)
                    end

                    local milestoneText = FontManager:CreateFontString(box, "subtitle", "OVERLAY")
                    milestoneText:SetWidth(slotW - 4)
                    milestoneText:SetPoint("TOP", starTex, "BOTTOM", 0, -SLOT_STAR_TEXT_GAP)
                    milestoneText:SetJustifyH("CENTER")
                    if milestoneText.SetJustifyV then milestoneText:SetJustifyV("MIDDLE") end
                    if isComplete then
                        if ns.UI_GetSemanticGreenColor then
                            local gr, gg, gb = ns.UI_GetSemanticGreenColor()
                            milestoneText:SetTextColor(gr, gg, gb)
                        else
                            milestoneText:SetTextColor(0.35, 1, 0.4)
                        end
                    else
                        ns.UI_SetTextColorRole(milestoneText, "Muted")
                    end
                    milestoneText:SetText(
                        format("%s / %s", FormatNumber(math.min(current, thresholds[ti])), FormatNumber(thresholds[ti]))
                    )
                end

                local clickPad = PUF and PUF:CreateButton(col, math.max(40, colWidth), 120, true)
                if not clickPad then
                    clickPad = CreateFrame("Button", nil, col)
                end
                clickPad:SetAllPoints()
                clickPad:SetFrameLevel((col:GetFrameLevel() or 0) + 25)
                clickPad:RegisterForClicks("LeftButtonUp")
                clickPad:EnableMouse(not fullyComplete)
                local hl = clickPad:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)
                clickPad:SetHighlightTexture(hl)
                if fullyComplete then
                    clickPad:Hide()
                end
                clickPad:SetScript("OnClick", function(_, btn)
                    if btn ~= "LeftButton" or fullyComplete then return end
                    selectedSlots[slotKey] = not selectedSlots[slotKey]
                    RefreshWeeklyPlanSlotSelections()
                end)

                local function refreshThisColumn()
                    if fullyComplete then
                        if ApplyPlansChrome then
                            ApplyPlansChrome(col, disabledBg, disabledBorder, { cardPanel = true })
                        end
                        col:SetAlpha(0.42)
                        clickPad:Hide()
                    elseif selectedSlots[slotKey] then
                        if ApplyPlansChrome then
                            ApplyPlansChrome(col, baseBg, accentBorder, { cardPanel = true })
                        end
                        col:SetAlpha(1)
                        clickPad:Show()
                        clickPad:EnableMouse(true)
                    else
                        if ApplyPlansChrome then
                            ApplyPlansChrome(col, unselBg, unselectedBorder, { cardPanel = true })
                        end
                        col:SetAlpha(0.58)
                        clickPad:Show()
                        clickPad:EnableMouse(true)
                    end
                end
                table.insert(slotColumnRefreshers, refreshThisColumn)
                refreshThisColumn()
            end
            
            -- Dungeons (column 1)
            CreateProgressCol(
                1,
                "questlog-questtypeicon-heroic",
                (ns.L and ns.L["MYTHIC_PLUS_LABEL"]) or "Mythic+",
                progress.dungeonCount,
                {1, 4, 8},  -- Thresholds
                "dungeon"
            )
            
            -- Raids (column 2)
            CreateProgressCol(
                2,
                "questlog-questtypeicon-raid",
                (ns.L and ns.L["RAIDS_LABEL"]) or "Raids",
                progress.raidBossCount,
                {2, 4, 6},  -- Thresholds
                "raid"
            )
            
            -- World (column 3)
            CreateProgressCol(
                3,
                "questlog-questtypeicon-Delves",
                (ns.L and ns.L["QUEST_CAT_WORLD"]) or "World",
                progress.worldActivityCount,
                {2, 4, 8},  -- Thresholds
                "world"
            )
        end
        
        -- Buttons (symmetrically centered)
        local footerX = (LAYOUT.FOOTER_BTN_W + LAYOUT.FOOTER_BTN_GAP) / 2
        local createBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["CREATE_PLAN"]) or "Create Plan", LAYOUT.FOOTER_BTN_W)
        createBtn:SetPoint("BOTTOM", -footerX, LAYOUT.BOTTOM_PAD)
        createBtn:SetScript("OnClick", function()
            -- Create the weekly plan with selected slots
            local plan = self:CreateWeeklyPlan(currentName, currentRealm, selectedSlots)
            if plan then
                -- Close dialog
                dialog.Close()
            end
        end)
        
        local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", LAYOUT.FOOTER_BTN_W)
        cancelBtn:SetPoint("BOTTOM", footerX, LAYOUT.BOTTOM_PAD)
        cancelBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    end
    
    dialog:Show()
end

-- CLOSE ALL PLAN DIALOGS

function WarbandNexus:CloseAllPlanDialogs()
    -- Close Weekly Plan Dialog
    if _G["WarbandNexus_WeeklyPlanDialog"] and _G["WarbandNexus_WeeklyPlanDialog"].Close then
        _G["WarbandNexus_WeeklyPlanDialog"].Close()
    end
    
    -- Close Daily Plan Dialog
    if _G["WarbandNexus_DailyPlanDialog"] and _G["WarbandNexus_DailyPlanDialog"].Close then
        _G["WarbandNexus_DailyPlanDialog"].Close()
    end
    
    -- Close Custom Plan Dialog
    if _G["WarbandNexus_CustomPlanDialog"] and _G["WarbandNexus_CustomPlanDialog"].Close then
        _G["WarbandNexus_CustomPlanDialog"].Close()
    end
end
