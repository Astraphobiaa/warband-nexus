--[[
    Warband Nexus - SharedWidgets TryCountPopup (split from SharedWidgets.lua)
    Try count edit popup (Plans / Collections / Tracker).
    Loaded right after Modules/UI/SharedWidgets.lua (TOC) so every later file still finds these ns.UI_* exports.
]]

local _, ns = ...
assert(ns.UI and ns.UI_ApplyVisuals and ns.UI_CreateCard, "SharedWidgets_TryCountPopup: load after SharedWidgets.lua")
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local FontManager = ns.FontManager
local ThemeAPI = ns.UITheme.ThemeAPI
local ApplyVisuals = ns.UI_ApplyVisuals

--- Semantic UI role → category (FontManager.FONT_ROLE / single theme source)
local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- TRY COUNT POPUP (Plans / Collections / Tracker)

local tryCountPopupFrame = nil

function ns.UI_ShowTryCountPopup(collectibleType, collectibleID, displayName)
    if not collectibleType or not collectibleID then return end
    local COLORS = ns.UI_COLORS or { accent = { 0.40, 0.20, 0.58 }, accentDark = { 0.28, 0.14, 0.41 }, bg = { 0.06, 0.06, 0.08 }, border = { 0.20, 0.20, 0.25 } }

    if not tryCountPopupFrame then
        local f = CreateFrame("Frame", "WNTryCountPopup", UIParent, "BackdropTemplate")
        f:SetSize(300, 160)
        local tryPosKey = "WNTryCountPopup"
        local function SaveTryCountPosition()
            if ns.WindowManager and ns.WindowManager.SavePosition then
                ns.WindowManager:SavePosition(f, tryPosKey)
            end
        end
        if not (ns.WindowManager and ns.WindowManager.RestorePosition
                and ns.WindowManager:RestorePosition(f, tryPosKey)) then
            f:SetPoint("CENTER")
        end
        f:EnableMouse(true)
        f:SetMovable(true)

        if ns.WindowManager then
            ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:InstallESCHandler(f)
            ns.WindowManager:InstallDragHandler(f, f, SaveTryCountPosition)
        else
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetFrameLevel(200)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                SaveTryCountPosition()
            end)
        end

        local tryShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local tryInset = tryShell.FRAME_CONTENT_INSET or 2
        local tryHdrH = tryShell.TRY_COUNT_POPUP_HEADER_HEIGHT or 32
        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(tryHdrH)
        header:SetPoint("TOPLEFT", tryInset, -tryInset)
        header:SetPoint("TOPRIGHT", -tryInset, -tryInset)
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })

        local headerTitle = FontManager:CreateFontString(header, UIFontRole("tryPopupHeader"), "OVERLAY")
        headerTitle:SetPoint("CENTER")
        headerTitle:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count")

        -- Close button: same IconRegistry "close" glyph + red tint as WindowFactory dialogs.
        local tryCloseSz = math.max(16, tryHdrH - 8)
        local tryCloseBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
        tryCloseBtn:SetSize(tryCloseSz, tryCloseSz)
        tryCloseBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
        local tryCloseIcon = tryCloseBtn:CreateTexture(nil, "ARTWORK")
        tryCloseIcon:SetSize(tryCloseSz - 10, tryCloseSz - 10)
        tryCloseIcon:SetPoint("CENTER")
        if not (ns.UI_SetIcon and ns.UI_SetIcon(tryCloseIcon, "close")) then
            tryCloseIcon:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        end
        tryCloseIcon:SetVertexColor(0.9, 0.3, 0.3)
        tryCloseBtn:SetScript("OnEnter", function() tryCloseIcon:SetVertexColor(1, 0.2, 0.2) end)
        tryCloseBtn:SetScript("OnLeave", function() tryCloseIcon:SetVertexColor(0.9, 0.3, 0.3) end)
        tryCloseBtn:SetScript("OnClick", function() f:Hide() end)
        f.closeBtn = tryCloseBtn
        ns.UI_SetTextColorRole(headerTitle, "Bright")
        f.headerTitle = headerTitle

        local nameLabel = FontManager:CreateFontString(f, UIFontRole("tryPopupBody"), "OVERLAY")
        nameLabel:SetPoint("TOP", header, "BOTTOM", 0, -12)
        nameLabel:SetJustifyH("CENTER")
        ns.UI_SetTextColorRole(nameLabel, "Bright")
        f.nameLabel = nameLabel

        local editBoxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        editBoxBg:SetSize(120, 28)
        editBoxBg:SetPoint("TOP", nameLabel, "BOTTOM", 0, -10)
        f.editBoxBg = editBoxBg

        local editBox = CreateFrame("EditBox", nil, editBoxBg)
        editBox:SetPoint("TOPLEFT", 8, -4)
        editBox:SetPoint("BOTTOMRIGHT", -8, 4)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(6)
        editBox:SetFontObject(ChatFontNormal) -- required initial FontObject (WoW crashes without one)
        if FontManager and FontManager.ApplyFontToEditBox then
            FontManager:ApplyFontToEditBox(editBox, "body")
            FontManager:RegisterManagedEditBox(editBox, "body")
        end
        ns.UI_SetTextColorRole(editBox, "Bright")
        editBox:SetJustifyH("CENTER")
        f.editBox = editBox

        local btnWidth, btnHeight = 90, 26

        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(btnWidth, btnHeight)
        saveBtn:SetPoint("TOPRIGHT", editBoxBg, "BOTTOM", -4, -10)
        local saveBtnText = FontManager:CreateFontString(saveBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText((ns.L and ns.L["SAVE"]) or "Save")
        ns.UI_SetTextColorRole(saveBtnText, "Bright")
        saveBtn:SetScript("OnEnter", function(self)
            ApplyVisuals(self, ThemeAPI.GetControlChromeHoverBackdrop(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
        end)
        saveBtn:SetScript("OnLeave", function(self)
            ApplyVisuals(self, ThemeAPI.GetControlChromeBackdrop(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end)
        f.saveBtn = saveBtn

        local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        cancelBtn:SetSize(btnWidth, btnHeight)
        cancelBtn:SetPoint("TOPLEFT", editBoxBg, "BOTTOM", 4, -10)
        local cancelBtnText = FontManager:CreateFontString(cancelBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText(_G.CANCEL or "Cancel")
        ns.UI_SetTextColorRole(cancelBtnText, "Normal")
        cancelBtn:SetScript("OnEnter", function(self)
            ApplyVisuals(self, ThemeAPI.GetControlChromeHoverBackdrop(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
        end)
        cancelBtn:SetScript("OnLeave", function(self)
            ApplyVisuals(self, ThemeAPI.GetControlChromeBackdrop(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        end)
        f.cancelBtn = cancelBtn

        --- Theme fills (re-run on every show: the frame is reused across light/dark toggles).
        function f._wnApplyTryChrome()
            local C = ns.UI_COLORS or COLORS
            local shell = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or C.bg
            ApplyVisuals(f, shell, { C.accent[1], C.accent[2], C.accent[3], 0.9 })
            ApplyVisuals(header, { C.accentDark[1], C.accentDark[2], C.accentDark[3], 1 }, { C.accent[1], C.accent[2], C.accent[3], 0.6 })
            ApplyVisuals(editBoxBg, ThemeAPI.GetControlChromeBackdrop(), { C.accent[1], C.accent[2], C.accent[3], 0.6 })
            ApplyVisuals(saveBtn, ThemeAPI.GetControlChromeBackdrop(), { C.accent[1], C.accent[2], C.accent[3], 0.8 })
            ApplyVisuals(cancelBtn, ThemeAPI.GetControlChromeBackdrop(), { C.border[1], C.border[2], C.border[3], 0.6 })
        end
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        editBox:SetScript("OnEnterPressed", function()
            f.saveBtn:Click()
        end)
        editBox:SetScript("OnEscapePressed", function()
            f:Hide()
        end)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)

        tryCountPopupFrame = f
        if ns.UI_RegisterScaledFrame then
            ns.UI_RegisterScaledFrame(f)
        elseif ns.UI_ApplyAddonUIScale then
            ns.UI_ApplyAddonUIScale(f)
        end
    end

    local popup = tryCountPopupFrame
    if popup._wnApplyTryChrome then popup._wnApplyTryChrome() end
    popup.nameLabel:SetText(displayName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"))

    local currentCount = 0
    if WarbandNexus and WarbandNexus.GetTryCount then
        currentCount = WarbandNexus:GetTryCount(collectibleType, collectibleID) or 0
    end
    popup.editBox:SetText(tostring(currentCount))

    popup._wnTryType = collectibleType
    popup._wnTryID = collectibleID

    popup.saveBtn:SetScript("OnClick", function()
        local rawCount = popup.editBox:GetText()
        if issecretvalue and issecretvalue(rawCount) then
            popup:Hide()
            return
        end
        local count = tonumber(rawCount)
        if count and count >= 0 and WarbandNexus and WarbandNexus.SetTryCount and popup._wnTryType and popup._wnTryID then
            WarbandNexus:SetTryCount(popup._wnTryType, popup._wnTryID, count)
        end
        popup:Hide()
    end)

    popup:Show()
    if popup.Raise then popup:Raise() end
    if not InCombatLockdown() and popup.editBox then
        local txt = tostring(currentCount)
        popup.editBox:SetFocus()
        local len = string.len(txt)
        popup.editBox:SetCursorPosition(len)
    end
end

--- Opens the try-count editor immediately (never use MenuUtil here: on Midnight the context menu often
--- registers success but shows nothing, which prevented the popup from ever opening.)
function ns.UI_OpenTryCountFromContext(_anchorFrame, collectibleType, collectibleID, displayName)
    if not collectibleType or not collectibleID or not ns.UI_ShowTryCountPopup then return end
    ns.UI_ShowTryCountPopup(collectibleType, collectibleID, displayName)
end

assert(ns.UI_ShowTryCountPopup and ns.UI_OpenTryCountFromContext, "SharedWidgets_TryCountPopup: exports missing")
