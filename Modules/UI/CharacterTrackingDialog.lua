--[[
    Warband Nexus - Character tracking confirmation dialogs (view layer).
    Split from CharacterService.lua; service calls ns.CharacterTrackingDialog.
    Loaded after SharedWidgets (Factory / ApplyVisuals at runtime).
]]

local _, ns = ...
local issecretvalue = issecretvalue

ns.CharacterTrackingDialog = ns.CharacterTrackingDialog or {}

function ns.CharacterTrackingDialog.ShowInitial(addon, charKey)
    -- If dialog already exists and is visible, don't create a new one
    if addon.trackingDialog and addon.trackingDialog:IsVisible() then
        return
    end
    
    -- Clean up old StaticPopup if it exists (legacy system)
    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = nil
    
    -- Create custom dialog frame
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(480, 210)  -- Compact size
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")  -- Above everything
    dialog:SetFrameLevel(500)  -- Very high level
    
    -- Backdrop (FULLY OPAQUE - solid background)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",  -- Solid white texture
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 1,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)  -- Alpha = 1 (fully opaque)
    local accentColor = ns.UI_COLORS and ns.UI_COLORS.accent or {0.40, 0.20, 0.58}
    dialog:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    
    -- Make draggable
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- NO CLOSE BUTTON - User must make a choice
    
    -- Title (Centered)
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -20)
    titleText:SetText("|cff9370DB" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r")
    
    -- Main question
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -16)
    questionText:SetWidth(460)
    questionText:SetJustifyH("CENTER")
    questionText:SetText((ns.L and ns.L["TRACK_CHARACTER_QUESTION"]) or "Do you want to track this character?")
    
    -- Character name with class color
    -- charKey may be a player GUID (storage key): prefer row / live APIs for display, not key parsing.
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
    -- Avoid parsing storage GUID as Name-Realm (WoW player GUIDs look like Player-<realmId>-...).
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
    
    -- Class color from roster (classFile / classID / localized class → Blizzard token)
    local classColor = "|cffffcc00"  -- Default gold when unknown
    if charName and not (issecretvalue and issecretvalue(charName)) and ns.UI_GetClassColorHexForWarbandCharacter then
        local hex = ns.UI_GetClassColorHexForWarbandCharacter(charName)
        if hex and hex ~= "|cffaaaaaa" then
            classColor = hex
        end
    end
    
    local charNameText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    charNameText:SetPoint("TOP", questionText, "BOTTOM", 0, -8)
    charNameText:SetText(classColor .. charName .. " - " .. charRealm .. "|r")
    
    -- Option boxes container
    local optionsY = -20
    
    -- Tracked option (LEFT) - now a BUTTON
    local trackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    trackedFrame:SetSize(200, 75)  -- Compact size
    trackedFrame:SetPoint("TOP", charNameText, "BOTTOM", -110, optionsY)
    trackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    trackedFrame:SetBackdropColor(0.1, 0.3, 0.2, 1)
    trackedFrame:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    
    -- Hover effect for Tracked card
    trackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.4, 0.25, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(0.3, 0.8, 0.4, 1)
    end)
    trackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
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
    trackedDesc:SetText("|cff88ff88" .. ((ns.L and ns.L["TRACKED_DETAILED_LINE1"]) or "Full detailed data") .. "|r\n|cffffffff" .. ((ns.L and ns.L["TRACKED_DETAILED_LINE2"]) or "All features enabled") .. "|r")
    
    -- Untracked option (RIGHT) - now a BUTTON
    local untrackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    untrackedFrame:SetSize(200, 75)  -- Compact size
    untrackedFrame:SetPoint("TOP", charNameText, "BOTTOM", 110, optionsY)
    untrackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    untrackedFrame:SetBackdropColor(0.3, 0.1, 0.1, 1)
    untrackedFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    
    -- Hover effect for Untracked card
    untrackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.15, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    untrackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
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
    untrackedDesc:SetText("|cffff8888" .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE1"]) or "View-only mode") .. "|r\n|cffffffff" .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE2"]) or "Basic info only") .. "|r")
    
    -- ESC-to-close (combat-safe: SetPropagateKeyboardInput is protected in 12.0)
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            -- Treat ESC as "don't track" so state is consistent and user can enable later from Characters tab
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
            end
            self:Hide()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)

    -- OnHide cleanup: clear addon reference so dialog can be shown again (e.g. next login or Track from Characters tab)
    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        if ns.UI_RecycleBin then self:SetParent(ns.UI_RecycleBin) else self:SetParent(nil) end
        if addon then
            addon.trackingDialog = nil
        end
        _G["WarbandNexusTrackingDialog"] = nil
    end)
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference to prevent garbage collection
    addon.trackingDialog = dialog
end

function ns.CharacterTrackingDialog.ShowChange(addon, charKey, charName, enableTracking)
    -- If dialog already exists and is visible, don't create a new one
    if addon.trackingChangeDialog and addon.trackingChangeDialog:IsVisible() then
        return
    end
    
    -- Create confirmation dialog (standardized custom UI: ApplyVisuals + compact buttons, no icons)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local UpdateBorderColor = ns.UI_UpdateBorderColor
    local COLORS = ns.UI_COLORS and ns.UI_COLORS.accent and ns.UI_COLORS or { accent = { 0.4, 0.2, 0.58 } }
    local accent = COLORS.accent
    
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingChangeDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(320, 140)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(500)
    
    if ApplyVisuals then
        ApplyVisuals(dialog, { 0.05, 0.05, 0.07, 1 }, { accent[1], accent[2], accent[3], 0.9 })
    else
        dialog:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)
        dialog:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end
    
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- Close button (standardized: small, accent border, X icon)
    local closeBtn = CreateFrame("Button", nil, dialog)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, { 0.15, 0.15, 0.15, 0.9 }, { accent[1], accent[2], accent[3], 0.8 })
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(12, 12)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)
    closeBtn:SetScript("OnEnter", function(self)
        if closeIcon then closeIcon:SetVertexColor(1, 0.2, 0.2) end
    end)
    closeBtn:SetScript("OnLeave", function(self)
        if closeIcon then closeIcon:SetVertexColor(0.9, 0.3, 0.3) end
    end)
    
    -- Title
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -16)
    titleText:SetText("|cff9370DB" .. ((ns.L and ns.L["CONFIRM_ACTION"]) or "Confirm Action") .. "|r")
    
    -- Question text
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
    questionText:SetWidth(320)
    questionText:SetJustifyH("CENTER")
    if enableTracking then
        questionText:SetText(string.format((ns.L and ns.L["ENABLE_TRACKING_FORMAT"]) or "Enable tracking for |cffffcc00%s|r?", charName))
    else
        questionText:SetText(string.format((ns.L and ns.L["DISABLE_TRACKING_FORMAT"]) or "Disable tracking for |cffffcc00%s|r?", charName))
    end
    
    -- Compact buttons (no icons): Confirm (green), Cancel (red)
    -- Anchored to dialog BOTTOM for symmetric positioning regardless of content
    local btnW, btnH, btnMarginBottom, gap = 100, 28, 16, 16
    
    -- Confirm (left) - anchored to dialog bottom-left area
    local yesCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    yesCard:SetSize(btnW, btnH)
    yesCard:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -(gap / 2), btnMarginBottom)
    if ApplyVisuals then
        ApplyVisuals(yesCard, { 0.1, 0.28, 0.18, 1 }, { 0.25, 0.65, 0.35, 1 })
    else
        yesCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        yesCard:SetBackdropColor(0.1, 0.3, 0.2, 1)
        yesCard:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    end
    yesCard:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.14, 0.35, 0.22, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.35, 0.8, 0.45, 1 }) end
    end)
    yesCard:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.1, 0.28, 0.18, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.25, 0.65, 0.35, 1 }) end
    end)
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
    
    -- Cancel (right) - anchored to dialog bottom-right area
    local noCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    noCard:SetSize(btnW, btnH)
    noCard:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", (gap / 2), btnMarginBottom)
    if ApplyVisuals then
        ApplyVisuals(noCard, { 0.28, 0.1, 0.1, 1 }, { 0.75, 0.22, 0.22, 1 })
    else
        noCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        noCard:SetBackdropColor(0.3, 0.1, 0.1, 1)
        noCard:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    end
    noCard:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.38, 0.14, 0.14, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 1, 0.3, 0.3, 1 }) end
    end)
    noCard:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.28, 0.1, 0.1, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.75, 0.22, 0.22, 1 }) end
    end)
    noCard:SetScript("OnClick", function()
        dialog:Hide()
        if ns.UI_RecycleBin then dialog:SetParent(ns.UI_RecycleBin) else dialog:SetParent(nil) end
    end)
    local noText = ns.FontManager:CreateFontString(noCard, "body", "OVERLAY")
    noText:SetPoint("CENTER")
    noText:SetText("|cffff8080" .. (CANCEL or "Cancel") .. "|r")
    
    -- ESC-to-close (combat-safe: SetPropagateKeyboardInput is protected in 12.0)
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

    -- OnHide cleanup
    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        if ns.UI_RecycleBin then self:SetParent(ns.UI_RecycleBin) else self:SetParent(nil) end
        _G["WarbandNexusTrackingChangeDialog"] = nil
    end)
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference
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
