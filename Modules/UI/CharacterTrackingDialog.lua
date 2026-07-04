--[[
    Warband Nexus - Character tracking confirmation dialogs (view layer).
    Split from CharacterService.lua; service calls ns.CharacterTrackingDialog.
    Loaded after SharedWidgets (Factory / ApplyVisuals at runtime).
]]

local _, ns = ...
local issecretvalue = issecretvalue

ns.CharacterTrackingDialog = ns.CharacterTrackingDialog or {}

local function Factory()
    return ns.UI and ns.UI.Factory
end

local function ShellContainer(parent, width, height, withBorder, globalName)
    local F = Factory()
    assert(F and F.CreateContainer, "CharacterTrackingDialog requires UI.Factory")
    return F:CreateContainer(parent, width or 1, height or 1, withBorder == true, globalName)
end

local function ShellButton(parent, width, height, noBorder)
    local F = Factory()
    return F:CreateButton(parent, width, height, noBorder == true)
end

local function AccentHex()
    if ns.UI_GetAccentHexColor then
        return "|cff" .. ns.UI_GetAccentHexColor()
    end
    return "|cff9370DB"
end

local function ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function SemanticGoldHex()
    if ns.UI_GetSemanticGoldHex then
        return ns.UI_GetSemanticGoldHex()
    end
    return "|cffffcc00"
end

local function GetDialogShellBg()
    if ns.UI_GetExternalShellBackdrop then
        return ns.UI_GetExternalShellBackdrop()
    end
    local c = ns.UI_COLORS
    return c and c.bg or { 0.05, 0.05, 0.07, 1 }
end

local function ApplyChoiceCardChrome(frame, positive, hover)
    local bg, border
    if positive then
        if ns.UI_GetSemanticPositiveCard then
            bg, border = ns.UI_GetSemanticPositiveCard(hover)
        else
            bg = hover and { 0.15, 0.4, 0.25, 1 } or { 0.1, 0.3, 0.2, 1 }
            border = hover and { 0.3, 0.8, 0.4, 1 } or { 0.2, 0.6, 0.3, 1 }
        end
    else
        if ns.UI_GetSemanticNegativeCard then
            bg, border = ns.UI_GetSemanticNegativeCard(hover)
        else
            bg = hover and { 0.4, 0.15, 0.15, 1 } or { 0.3, 0.1, 0.1, 1 }
            border = hover and { 1, 0.3, 0.3, 1 } or { 0.8, 0.2, 0.2, 1 }
        end
    end
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(frame, bg, border)
    elseif frame.SetBackdropColor then
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        if frame.SetBackdropBorderColor and border then
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end
    end
end

function ns.CharacterTrackingDialog.RefreshTheme()
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus then return end
    local d = WarbandNexus.trackingDialog
    if d and d:IsShown() and d._wnRefreshTheme then
        d._wnRefreshTheme()
    end
    local c = WarbandNexus.trackingChangeDialog
    if c and c:IsShown() and c._wnRefreshTheme then
        c._wnRefreshTheme()
    end
end

function ns.CharacterTrackingDialog.ShowInitial(addon, charKey)
    if addon.trackingDialog and addon.trackingDialog:IsVisible() then
        return
    end

    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = nil

    local dialog = ShellContainer(UIParent, 480, 210, false, "WarbandNexusTrackingDialog")
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(500)

    if ns.UI_ApplyMainWindowShellFill then
        ns.UI_ApplyMainWindowShellFill(dialog)
    elseif ns.UI_ApplyVisuals then
        local accentColor = ns.UI_COLORS and ns.UI_COLORS.accent or { 0.40, 0.20, 0.58 }
        ns.UI_ApplyVisuals(dialog, GetDialogShellBg(), { accentColor[1], accentColor[2], accentColor[3], 1 })
    end
    local accentColor = ns.UI_COLORS and ns.UI_COLORS.accent or { 0.40, 0.20, 0.58 }
    dialog._wnAccent = accentColor

    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -20)
    titleText:SetText(AccentHex() .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r")

    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -16)
    questionText:SetWidth(460)
    questionText:SetJustifyH("CENTER")
    questionText:SetText((ns.L and ns.L["TRACK_CHARACTER_QUESTION"]) or "Do you want to track this character?")
    ns.UI_SetTextColorRole(questionText, "Normal")

    local charName, charRealmRaw = nil, nil
    local row = addon.db.global.characters and charKey and addon.db.global.characters[charKey]
    if type(row) == "table" then
        local n = row.name
        local r = row.realm
        if type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
            charName = n
        end
        if type(r) == "string" and r ~= "" and not (issecretvalue and issecretvalue(r)) then
            charRealmRaw = r
        end
    end
    local guidLike = charKey and type(charKey) == "string" and not (issecretvalue and issecretvalue(charKey))
        and charKey:match("^Player%-%d+%-") ~= nil
    if not charName and charKey and not guidLike and not (issecretvalue and issecretvalue(charKey)) then
        charName = charKey:match("^([^%-]+)") or charKey
        charRealmRaw = charRealmRaw or charKey:match("%-(.+)")
    end
    if not charName then
        local un = UnitName("player")
        if un and type(un) == "string" and not (issecretvalue and issecretvalue(un)) then
            charName = un
        end
    end
    if not charRealmRaw or charRealmRaw == "" then
        local norm = GetNormalizedRealmName and GetNormalizedRealmName()
        if type(norm) == "string" and norm ~= "" and not (issecretvalue and issecretvalue(norm)) then
            charRealmRaw = norm
        elseif GetRealmName then
            charRealmRaw = GetRealmName() or ""
            if issecretvalue and charRealmRaw and issecretvalue(charRealmRaw) then charRealmRaw = "" end
        end
    end
    charRealmRaw = charRealmRaw or ""
    local charRealm = (charRealmRaw ~= "" and ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(charRealmRaw)) or charRealmRaw
    if charName and issecretvalue and issecretvalue(charName) then
        charName = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
    end
    if charRealm and issecretvalue and issecretvalue(charRealm) then
        charRealm = ""
    end

    local classColor = "|cffffcc00"
    if charName and not (issecretvalue and issecretvalue(charName)) and ns.UI_GetClassColorHexForWarbandCharacter then
        local hex = ns.UI_GetClassColorHexForWarbandCharacter(charName)
        if hex and hex ~= "|cffaaaaaa" then
            classColor = hex
        end
    end

    local charNameText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    charNameText:SetPoint("TOP", questionText, "BOTTOM", 0, -8)
    charNameText:SetText(classColor .. charName .. " - " .. charRealm .. "|r")

    local optionsY = -20

    local trackedFrame = ShellButton(dialog, 200, 75, false)
    trackedFrame:SetPoint("TOP", charNameText, "BOTTOM", -110, optionsY)
    trackedFrame._wnPositiveCard = true
    ApplyChoiceCardChrome(trackedFrame, true, false)

    trackedFrame:SetScript("OnEnter", function(self)
        ApplyChoiceCardChrome(self, true, true)
    end)
    trackedFrame:SetScript("OnLeave", function(self)
        ApplyChoiceCardChrome(self, true, false)
    end)
    trackedFrame:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
        end
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)

    local trackedTitle = ns.FontManager:CreateFontString(trackedFrame, "header", "OVERLAY")
    trackedTitle:SetPoint("TOP", 0, -12)
    trackedTitle:SetText("|cff00ff00" .. ((ns.L and ns.L["TRACKED_LABEL"]) or "Tracked") .. "|r")

    local trackedDesc = ns.FontManager:CreateFontString(trackedFrame, "body", "OVERLAY")
    trackedDesc:SetPoint("TOP", trackedTitle, "BOTTOM", 0, -5)
    trackedDesc:SetWidth(185)
    trackedDesc:SetJustifyH("CENTER")
    trackedDesc:SetText("|cff88ff88" .. ((ns.L and ns.L["TRACKED_DETAILED_LINE1"]) or "Full detailed data") .. "|r\n" .. ThemeTextHex("Bright") .. ((ns.L and ns.L["TRACKED_DETAILED_LINE2"]) or "All features enabled") .. "|r")

    local untrackedFrame = ShellButton(dialog, 200, 75, false)
    untrackedFrame:SetPoint("TOP", charNameText, "BOTTOM", 110, optionsY)
    untrackedFrame._wnNegativeCard = true
    ApplyChoiceCardChrome(untrackedFrame, false, false)

    untrackedFrame:SetScript("OnEnter", function(self)
        ApplyChoiceCardChrome(self, false, true)
    end)
    untrackedFrame:SetScript("OnLeave", function(self)
        ApplyChoiceCardChrome(self, false, false)
    end)
    untrackedFrame:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
        end
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)

    local untrackedTitle = ns.FontManager:CreateFontString(untrackedFrame, "header", "OVERLAY")
    untrackedTitle:SetPoint("TOP", 0, -12)
    untrackedTitle:SetText("|cffff4444" .. ((ns.L and ns.L["UNTRACKED_LABEL"]) or "Untracked") .. "|r")

    local untrackedDesc = ns.FontManager:CreateFontString(untrackedFrame, "body", "OVERLAY")
    untrackedDesc:SetPoint("TOP", untrackedTitle, "BOTTOM", 0, -5)
    untrackedDesc:SetWidth(185)
    untrackedDesc:SetJustifyH("CENTER")
    untrackedDesc:SetText("|cffff8888" .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE1"]) or "View-only mode") .. "|r\n" .. ThemeTextHex("Bright") .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE2"]) or "Basic info only") .. "|r")

    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
            end
            self:Hide()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)

    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        if ns.UI_UnregisterScaledFrame then
            ns.UI_UnregisterScaledFrame(self)
        end
        if ns.UI_RecycleBin then self:SetParent(ns.UI_RecycleBin) else self:SetParent(nil) end
        if addon then
            addon.trackingDialog = nil
        end
        _G["WarbandNexusTrackingDialog"] = nil
    end)

    dialog._wnRefreshTheme = function()
        if ns.UI_ApplyMainWindowShellFill then
            ns.UI_ApplyMainWindowShellFill(dialog)
        elseif ns.UI_ApplyVisuals then
            local ac = ns.UI_COLORS and ns.UI_COLORS.accent or accentColor
            ns.UI_ApplyVisuals(dialog, GetDialogShellBg(), { ac[1], ac[2], ac[3], 1 })
        end
        ApplyChoiceCardChrome(trackedFrame, true, false)
        ApplyChoiceCardChrome(untrackedFrame, false, false)
    end

    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(dialog)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(dialog)
    end

    dialog:Show()
    addon.trackingDialog = dialog
end

function ns.CharacterTrackingDialog.ShowChange(addon, charKey, charName, enableTracking)
    if addon.trackingChangeDialog and addon.trackingChangeDialog:IsVisible() then
        return
    end

    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.4, 0.2, 0.58 }

    local dialog, contentFrame, header
    if CreateExternalWindow then
        dialog, contentFrame, header = CreateExternalWindow({
            name = "TrackingChangeDialog",
            title = (ns.L and ns.L["CONFIRM_ACTION"]) or "Confirm Action",
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            width = 320,
            height = 160,
            preventDuplicates = true,
        })
    end

    if not dialog or not contentFrame then
        dialog = ShellContainer(UIParent, 320, 140, false, "WarbandNexusTrackingChangeDialog")
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(500)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(dialog, GetDialogShellBg(), { accent[1], accent[2], accent[3], 0.9 })
        end
        contentFrame = ShellContainer(dialog, 300, 100, false)
        contentFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, -36)
        contentFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 10)
    end

    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    local questionText = ns.FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    questionText:SetPoint("TOP", contentFrame, "TOP", 0, -8)
    questionText:SetWidth(300)
    questionText:SetJustifyH("CENTER")
    if enableTracking then
        questionText:SetText(string.format(
            (ns.L and ns.L["ENABLE_TRACKING_FORMAT"]) or "Enable tracking for %s?",
            SemanticGoldHex() .. charName .. "|r"
        ))
    else
        questionText:SetText(string.format(
            (ns.L and ns.L["DISABLE_TRACKING_FORMAT"]) or "Disable tracking for %s?",
            SemanticGoldHex() .. charName .. "|r"
        ))
    end

    local btnW, btnH, btnMarginBottom, gap = 100, 28, 8, 16

    local yesCard = ShellButton(dialog, btnW, btnH, false)
    yesCard:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -(gap / 2), btnMarginBottom)
    ApplyChoiceCardChrome(yesCard, true, false)
    yesCard:SetScript("OnEnter", function(self) ApplyChoiceCardChrome(self, true, true) end)
    yesCard:SetScript("OnLeave", function(self) ApplyChoiceCardChrome(self, true, false) end)
    yesCard:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, enableTracking)
        end
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)
    local yesText = ns.FontManager:CreateFontString(yesCard, "body", "OVERLAY")
    yesText:SetPoint("CENTER")
    yesText:SetText("|cff90ff90" .. ((ns.L and ns.L["CONFIRM"]) or "Confirm") .. "|r")

    local noCard = ShellButton(dialog, btnW, btnH, false)
    noCard:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", (gap / 2), btnMarginBottom)
    ApplyChoiceCardChrome(noCard, false, false)
    noCard:SetScript("OnEnter", function(self) ApplyChoiceCardChrome(self, false, true) end)
    noCard:SetScript("OnLeave", function(self) ApplyChoiceCardChrome(self, false, false) end)
    noCard:SetScript("OnClick", function()
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)
    local noText = ns.FontManager:CreateFontString(noCard, "body", "OVERLAY")
    noText:SetPoint("CENTER")
    noText:SetText("|cffff8080" .. (CANCEL or "Cancel") .. "|r")

    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            self:Hide()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)

    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        if ns.UI_UnregisterScaledFrame then
            ns.UI_UnregisterScaledFrame(self)
        end
        if ns.UI_RecycleBin then self:SetParent(ns.UI_RecycleBin) else self:SetParent(nil) end
        _G["WarbandNexusTrackingChangeDialog"] = nil
        addon.trackingChangeDialog = nil
    end)

    dialog._wnRefreshTheme = function()
        if ns.UI_ApplyMainWindowShellFill and dialog._wnExternalShell then
            ns.UI_ApplyMainWindowShellFill(dialog)
        elseif ns.UI_ApplyVisuals then
            local ac = ns.UI_COLORS and ns.UI_COLORS.accent or accent
            ns.UI_ApplyVisuals(dialog, GetDialogShellBg(), { ac[1], ac[2], ac[3], 0.9 })
        end
        ApplyChoiceCardChrome(yesCard, true, false)
        ApplyChoiceCardChrome(noCard, false, false)
    end

    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(dialog)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(dialog)
    end

    dialog:Show()
    addon.trackingChangeDialog = dialog
end

do
    local WarbandNexus = ns.WarbandNexus
    local Constants = ns.Constants
    local ev = Constants and Constants.EVENTS and Constants.EVENTS.CHARACTER_TRACKING_DIALOG_REQUESTED
    if ev and WarbandNexus and WarbandNexus.RegisterMessage then
        local TrackingDialogEvents = {}
        WarbandNexus.RegisterMessage(TrackingDialogEvents, ev, function(_, payload)
            if not payload or not payload.mode then return end
            local addon = WarbandNexus
            if payload.mode == "initial" then
                ns.CharacterTrackingDialog.ShowInitial(addon, payload.charKey)
            elseif payload.mode == "change" then
                ns.CharacterTrackingDialog.ShowChange(addon, payload.charKey, payload.charName, payload.enableTracking == true)
            end
        end)
    end
end
