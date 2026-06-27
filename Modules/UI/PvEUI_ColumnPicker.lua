--[[
    Warband Nexus - PvE tab column picker + low-level hide filter flyout.
    Split from PvEUI.lua (Lua 5.1 local limit).
    Loaded after Modules/UI/PvEUI.lua (uses ns.PvEUI column helpers).
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ColumnOrder = ns.ColumnOrder
local ApplyVisuals = ns.UI_ApplyVisuals
local HideTooltip = ns.UI_HideTooltip
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox

local function ControlChromeBackdrop()
    if ns.UI_GetControlChromeBackdrop then
        return ns.UI_GetControlChromeBackdrop()
    end
    return COLORS.bgCard or COLORS.bgLight or COLORS.bg or { 0.08, 0.08, 0.10, 1 }
end

local function ControlChromeHoverBackdrop()
    if ns.UI_GetControlChromeHoverBackdrop then
        return ns.UI_GetControlChromeHoverBackdrop()
    end
    return COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg or { 0.10, 0.10, 0.12, 1 }
end

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

local function PvEUI()
    return ns.PvEUI or {}
end

local function GetPvEDawnCrestColumnDefinitions()
    local fn = PvEUI().GetPvEDawnCrestColumnDefinitions
    return (fn and fn()) or {}
end

local function EnsurePvEColumnOrder(profile)
    local fn = PvEUI().EnsurePvEColumnOrder
    if fn then return fn(profile) end
    return profile and profile.pveColumnOrder or {}
end

local function EnsureVaultButtonColumnsForPvE(profile)
    local fn = PvEUI().EnsureVaultButtonColumnsForPvE
    return (fn and fn(profile)) or {}
end

local function EnsurePvEExtraVisibleColumns(profile)
    local fn = PvEUI().EnsurePvEExtraVisibleColumns
    return (fn and fn(profile)) or {}
end

local function GetPvEDefaultColumnKeyOrder(profile)
    local fn = PvEUI().GetPvEDefaultColumnKeyOrder
    if fn then return fn(profile) end
    return {}
end

local function GetLowLevelHideThreshold(profile)
    local fn = PvEUI().GetLowLevelHideThreshold
    if fn then return fn(profile) end
    return 0
end

local function GetLowLevelHideLabel(threshold)
    local fn = PvEUI().GetLowLevelHideLabel
    if fn then return fn(threshold) end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

local function ApplyLowLevelHideThreshold(addon, threshold)
    local fn = PvEUI().ApplyLowLevelHideThreshold
    if fn then fn(addon, threshold) end
end
-- PvE Columns dropdown: fullscreen dialog layer for interactive menus (avoid tooltip strata misuse).
local PVE_COLUMN_PICKER_STRATA = "FULLSCREEN_DIALOG"
local PVE_COLUMN_PICKER_MENU_LEVEL = 5100
local PVE_COLUMN_PICKER_CATCHER_LEVEL = 5050

local function PvE_ColumnPickerHideTooltipLayers()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    if HideTooltip then HideTooltip() end
end

local function PvE_ColumnPickerHideCatcher()
    local c = WarbandNexus._wnPvEColumnPickerCatcher
    if c and c:IsShown() then c:Hide() end
end

function WarbandNexus:HidePvEColumnPickerMenu()
    PvE_ColumnPickerHideCatcher()
    local m = WarbandNexus._wnPvEColumnPickerMenu
    if m then m:Hide() end
end

local function PvE_ColumnPickerPositionMenu(menu, anchorBtn)
    if not menu or not anchorBtn then return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
end

local function PvE_ColumnPickerShowCatcher(menu)
    local c = WarbandNexus._wnPvEColumnPickerCatcher
    if not c then
        -- Intentionally raw Button: global name for debugging plus plain Button click-dismiss behavior on UIParent.
        c = CreateFrame("Button", "WarbandNexusPvEColumnPickerCatcher", UIParent)
        c:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
        c:SetFrameLevel(PVE_COLUMN_PICKER_CATCHER_LEVEL)
        c:SetAllPoints(UIParent)
        c:SetAlpha(0)
        c:EnableMouse(true)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if c.SetPropagateMouseClicks then c:SetPropagateMouseClicks(false) end
        c:SetScript("OnClick", function()
            WarbandNexus:HidePvEColumnPickerMenu()
        end)
        WarbandNexus._wnPvEColumnPickerCatcher = c
    end
    c:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    c:SetFrameLevel(PVE_COLUMN_PICKER_CATCHER_LEVEL)
    c:Show()
    menu:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    menu:SetFrameLevel(PVE_COLUMN_PICKER_MENU_LEVEL)
    menu:Raise()
end

local function PvE_GetOrCreateColumnPickerMenu()
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateContainer then return nil end
    local m = WarbandNexus._wnPvEColumnPickerMenu
    if m then return m end
    local accent = COLORS.accent or { 0.40, 0.20, 0.58 }
    m = Factory:CreateContainer(UIParent, 320, 320, true)
    if not m then return nil end
    m:SetClampedToScreen(true)
    m:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    m:SetFrameLevel(PVE_COLUMN_PICKER_MENU_LEVEL)
    m:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(m, ControlChromeBackdrop(), { accent[1], accent[2], accent[3], 1 })
    end
    m:Hide()
    WarbandNexus._wnPvEColumnPickerMenu = m
    if Factory.EnsureDropdownEscClose then
        Factory:EnsureDropdownEscClose(m)
    end
    return m
end

-- Forward declaration: referenced inside PvE_ColumnPickerPopulateMenu callback.
local PvE_ColumnPickerTryRefreshAfterDraw

--- Rebuild scroll contents from DB. Caller raises menu + catcher.
local function PvE_ColumnPickerPopulateMenu(menu, addon)
    local Factory = ns.UI and ns.UI.Factory
    if not menu or not Factory or not addon then return end

    local profile = addon.db and addon.db.profile
    if not profile then return end

    local accent = COLORS.accent or { 0.40, 0.20, 0.58 }
    local menuW = 320
    local ROW = 26
    local HEADER_H = 22
    local dl = Factory.GetDropdownLayout and Factory:GetDropdownLayout() or {}
    local menuPad = dl.menuEdge or 4
    local scrollBarW = dl.scrollBarW or 26

    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    local colOrder = EnsurePvEColumnOrder(profile)
    local toggleCount = #crestDefs + 8
    local contentH = HEADER_H + toggleCount * ROW + ROW + ROW + 10
    -- Fixed column list: show every toggle without a scroll cap (unlike generic dropdown menus).
    local viewportInnerH = contentH
    local menuH = viewportInnerH + 2 * menuPad

    menu:SetSize(menuW, menuH)
    menu:SetParent(UIParent)

    local bin = ns.UI_RecycleBin
    local children = { menu:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end

    local scrollFrame = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", menuPad, -menuPad)
    scrollFrame:SetPoint("BOTTOMRIGHT", -scrollBarW, menuPad)
    scrollFrame:EnableMouseWheel(true)

    local scrollBarColumn = Factory:CreateScrollBarColumn(menu, scrollBarW, menuPad, menuPad)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end
    if Factory.WireScrollBarColumnLayout then
        Factory:WireScrollBarColumnLayout(scrollFrame, menu, scrollBarColumn, { menuEdge = menuPad })
    end

    local btnWidth = menuW - menuPad * 2 - scrollBarW
    local scrollChild
    if Factory and Factory.CreateContainer then
        scrollChild = Factory:CreateContainer(scrollFrame, btnWidth, contentH, false)
    end
    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(btnWidth)
        scrollChild:SetHeight(contentH)
    end
    scrollFrame:SetScrollChild(scrollChild)

    local logicalRows = math.max(1, math.ceil(contentH / ROW))
    scrollFrame._wnDropdownRowCount = logicalRows
    scrollFrame._wnDropdownMaxVisible = logicalRows
    scrollFrame._wnDropdownViewportH = viewportInnerH

    if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(scrollFrame) end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Factory.UpdateScrollBarVisibility and scrollFrame then
                Factory:UpdateScrollBarVisibility(scrollFrame)
            end
        end)
    end

    local columnHdr = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    columnHdr:SetPoint("TOPLEFT", 14, -8)
    columnHdr:SetText(GetLocalizedText("COLUMNS_BUTTON", "Columns"))
    columnHdr:SetTextColor(accent[1], accent[2], accent[3], 1)
    if columnHdr.EnableMouse then columnHdr:EnableMouse(false) end

    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)

    local function applyColumnPickerChange(vaultColTouched)
        if vaultColTouched and WarbandNexus.RefreshVaultButtonSettings then
            WarbandNexus:RefreshVaultButtonSettings()
        end
        if ns.PvEUI and ns.PvEUI.InvalidateBodyCache then
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf.scrollChild then
                ns.PvEUI.InvalidateBodyCache(mf.scrollChild)
            end
        end
        PvE_ColumnPickerHideTooltipLayers()
        if addon and addon.SendMessage then
            addon:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
        end
        C_Timer.After(0, function()
            local picker = WarbandNexus._wnPvEColumnPickerMenu
            if not picker or not picker:IsShown() then return end
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if not mf or mf.currentTab ~= "pve" then
                WarbandNexus:HidePvEColumnPickerMenu()
                return
            end
            PvE_ColumnPickerTryRefreshAfterDraw(WarbandNexus)
        end)
    end

    local function RepopulatePvEColumnPicker()
        applyColumnPickerChange(false)
    end

    local function addCheckboxRow(y, labelText, isChecked, onToggle, reorderKey)
        local rowHost = Factory:CreateContainer(scrollChild, btnWidth, ROW, false)
        if not rowHost then return y end
        rowHost:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        local cb = CreateThemedCheckbox(rowHost, isChecked)
        if not cb then return y - ROW end
        cb:SetPoint("LEFT", rowHost, "LEFT", 14, 0)
        cb:EnableMouse(true)
        local lbl = FontManager:CreateFontString(rowHost, "body", "OVERLAY")
        lbl:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
        lbl:SetText(labelText)
        ns.UI_SetTextColorRole(lbl, "Bright")
        lbl:SetJustifyH("LEFT")
        if lbl.EnableMouse then lbl:EnableMouse(false) end
        local prevClick = cb:GetScript("OnClick")
        cb:SetScript("OnClick", function(self, ...)
            if prevClick then prevClick(self, ...) end
            onToggle(self:GetChecked() and true or false)
        end)
        if reorderKey and ColumnOrder and ColumnOrder.AttachPickerReorderButtons then
            ColumnOrder.AttachPickerReorderButtons(rowHost, colOrder, reorderKey, RepopulatePvEColumnPicker)
        end
        return y - ROW
    end

    local pickerRows = {}
    for i = 1, #crestDefs do
        local id = crestDefs[i].id
        local labelKey = crestDefs[i].labelKey
        local crestLabel = labelKey and GetLocalizedText(labelKey, GetLocalizedText("PVE_CREST_GENERIC", "Dawncrest")) or GetLocalizedText("PVE_CREST_GENERIC", "Dawncrest")
        local ck = "crest_" .. tostring(id)
        pickerRows[#pickerRows + 1] = {
            key = ck,
            label = crestLabel,
            checked = ex[ck] ~= false,
            vault = false,
            toggle = function(checked)
                ex[ck] = checked
                applyColumnPickerChange(false)
            end,
        }
    end
    pickerRows[#pickerRows + 1] = { key = "coffer_shards", label = GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"), checked = ex.coffer_shards ~= false, vault = false, toggle = function(checked) ex.coffer_shards = checked applyColumnPickerChange(false) end }
    pickerRows[#pickerRows + 1] = { key = "restored_key", label = GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"), checked = ex.restored_key ~= false, vault = false, toggle = function(checked) ex.restored_key = checked applyColumnPickerChange(false) end }
    pickerRows[#pickerRows + 1] = { key = "shard_of_dundun", label = GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"), checked = ex.shard_of_dundun ~= false, vault = false, toggle = function(checked) ex.shard_of_dundun = checked applyColumnPickerChange(false) end }
    pickerRows[#pickerRows + 1] = { key = "voidcore", label = GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"), checked = vc.voidcore ~= false, vault = true, toggle = function(checked) vc.voidcore = checked applyColumnPickerChange(true) end }
    pickerRows[#pickerRows + 1] = { key = "manaflux", label = GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"), checked = vc.manaflux == true, vault = true, toggle = function(checked) vc.manaflux = checked profile.vaultButton = profile.vaultButton or {} profile.vaultButton.showManaflux = checked applyColumnPickerChange(true) end }
    pickerRows[#pickerRows + 1] = { key = "slot1", label = GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"), checked = vc.raids ~= false, vault = true, toggle = function(checked) vc.raids = checked applyColumnPickerChange(true) end }
    pickerRows[#pickerRows + 1] = { key = "slot2", label = GetLocalizedText("VAULT_DUNGEON", "Dungeon"), checked = vc.mythicPlus ~= false, vault = true, toggle = function(checked) vc.mythicPlus = checked applyColumnPickerChange(true) end }
    pickerRows[#pickerRows + 1] = { key = "slot3", label = GetLocalizedText("VAULT_SLOT_WORLD", "World"), checked = vc.world ~= false, vault = true, toggle = function(checked) vc.world = checked applyColumnPickerChange(true) end }
    pickerRows[#pickerRows + 1] = { key = "bountiful", label = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty"), checked = vc.bounty ~= false, vault = true, toggle = function(checked) vc.bounty = checked applyColumnPickerChange(true) end }

    local rank = {}
    for ri = 1, #colOrder do rank[colOrder[ri]] = ri end
    table.sort(pickerRows, function(a, b)
        return (rank[a.key] or 9999) < (rank[b.key] or 9999)
    end)

    local y = -HEADER_H
    for pri = 1, #pickerRows do
        local pr = pickerRows[pri]
        y = addCheckboxRow(y, pr.label, pr.checked, pr.toggle, pr.key)
    end

    local resetOrderBtn = Factory:CreateButton(scrollChild, btnWidth - 28, ROW - 2, false)
    if resetOrderBtn and ApplyVisuals then
        ApplyVisuals(resetOrderBtn, ControlChromeHoverBackdrop(), { accent[1], accent[2], accent[3], 0.5 })
    end
    if resetOrderBtn then
        resetOrderBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14, y - 4)
        local resetOrderLbl = FontManager:CreateFontString(resetOrderBtn, "small", "OVERLAY")
        resetOrderLbl:SetPoint("CENTER", 0, 0)
        local hexOrder = (UI_GetAccentHexColor and UI_GetAccentHexColor()) or "aaaaee"
        resetOrderLbl:SetText("|cff" .. hexOrder .. (GetLocalizedText("RESET_COLUMN_ORDER", "Reset Order")) .. "|r")
        if resetOrderLbl.EnableMouse then resetOrderLbl:EnableMouse(false) end
        resetOrderBtn:SetScript("OnClick", function()
            if ColumnOrder then
                ColumnOrder.ResetToDefault(colOrder, GetPvEDefaultColumnKeyOrder(profile), nil)
            end
            RepopulatePvEColumnPicker()
        end)
        if Factory.ApplyHighlight then Factory:ApplyHighlight(resetOrderBtn) end
        y = y - ROW - 4
    end

    local resetBtn = Factory:CreateButton(scrollChild, btnWidth - 28, ROW - 2, false)
    if resetBtn and ApplyVisuals then
        ApplyVisuals(resetBtn, ControlChromeHoverBackdrop(), { accent[1], accent[2], accent[3], 0.5 })
    end
    if resetBtn then
        resetBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14, y - 4)
        local resetLbl = FontManager:CreateFontString(resetBtn, "small", "OVERLAY")
        resetLbl:SetPoint("CENTER", 0, 0)
        local hex = (UI_GetAccentHexColor and UI_GetAccentHexColor()) or "aaaaee"
        resetLbl:SetText("|cff" .. hex .. (GetLocalizedText("SHOW_ALL", "Show All")) .. "|r")
        if resetLbl.EnableMouse then resetLbl:EnableMouse(false) end
        resetBtn:SetScript("OnClick", function()
            for j = 1, #crestDefs do
                ex["crest_" .. tostring(crestDefs[j].id)] = true
            end
            ex.coffer_shards = true
            ex.restored_key = true
            ex.shard_of_dundun = true
            vc.raids = true
            vc.mythicPlus = true
            vc.world = true
            vc.bounty = true
            vc.voidcore = true
            vc.manaflux = true
            profile.vaultButton = profile.vaultButton or {}
            profile.vaultButton.showManaflux = true
            applyColumnPickerChange(true)
        end)
        if Factory.ApplyHighlight then Factory:ApplyHighlight(resetBtn) end
    end

    if scrollFrame and scrollChild and Factory.UpdateScrollBarVisibility then
        local fh = scrollFrame:GetHeight()
        if fh and fh > 0 then
            local slack = (ns.UI_LAYOUT and ns.UI_LAYOUT.DROPDOWN_SCROLL_FIT_SLACK) or 8
            local ch = scrollChild:GetHeight() or 0
            if ch > fh and ch <= fh + slack then
                scrollChild:SetHeight(fh)
            end
        end
        Factory:UpdateScrollBarVisibility(scrollFrame)
    end
end

PvE_ColumnPickerTryRefreshAfterDraw = function(addon)
    local menu = WarbandNexus._wnPvEColumnPickerMenu
    local anchor = WarbandNexus._wnPvEColumnPickerAnchorBtn
    if not menu or not menu:IsShown() or not anchor or not addon then return end
    PvE_ColumnPickerPopulateMenu(menu, addon)
    PvE_ColumnPickerPositionMenu(menu, anchor)
    PvE_ColumnPickerHideTooltipLayers()
    menu:Show()
    PvE_ColumnPickerShowCatcher(menu)
end

--- PvE header: single toggle between Current and Weekly currency/vault display.
local function PvE_RefreshCurrencyDisplayToggleChrome(toggleBtn, toggleLbl)
    local profile = WarbandNexus.db and WarbandNexus.db.profile
    local mode = (profile and profile.pveCurrencyDisplayMode == "weekly") and "weekly" or "current"
    local accent = COLORS.accent or { 0.40, 0.20, 0.58 }
    local idle = ControlChromeBackdrop()
    local active = (ns.UI_GetNavRailActiveBackdrop and ns.UI_GetNavRailActiveBackdrop())
        or ControlChromeHoverBackdrop()
    local border = { accent[1], accent[2], accent[3], 0.6 }
    if toggleBtn and ApplyVisuals then
        ApplyVisuals(toggleBtn, active, border)
    end
    if toggleLbl and toggleLbl.SetText then
        if mode == "weekly" then
            toggleLbl:SetText(GetLocalizedText("PVE_CURRENCY_VIEW_WEEKLY", "Weekly"))
        else
            toggleLbl:SetText(GetLocalizedText("PVE_CURRENCY_VIEW_CURRENT", "Current"))
        end
    end
end

local function PvE_AttachCurrencyDisplayToggle(titleCard, sortAnchor, addon)
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateButton then return sortAnchor end

    local btnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local toggleBtn = Factory:CreateButton(titleCard, 88, btnH, false)
    if not toggleBtn then return sortAnchor end

    local hdrGap = (ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics().gap) or 8
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(toggleBtn, titleCard, sortAnchor, "LEFT", -hdrGap)
    else
        toggleBtn:SetPoint("RIGHT", sortAnchor, "LEFT", -hdrGap, 0)
    end

    local toggleLbl = FontManager:CreateFontString(toggleBtn, "body", "OVERLAY")
    toggleLbl:SetPoint("CENTER", 0, 0)
    ns.UI_SetTextColorRole(toggleLbl, "Bright")

    if Factory.ApplyHighlight then
        Factory:ApplyHighlight(toggleBtn)
    end

    PvE_RefreshCurrencyDisplayToggleChrome(toggleBtn, toggleLbl)
    WarbandNexus._wnPvECurrencyViewToggleBtn = toggleBtn
    WarbandNexus._wnPvECurrencyViewToggleLbl = toggleLbl

    local shiftHint = GetLocalizedText(
        "PVE_CURRENCY_VIEW_SHIFT_HINT",
        "Hold Shift to temporarily show the other view."
    )
    local toggleHint = GetLocalizedText(
        "PVE_CURRENCY_VIEW_TOGGLE_HINT",
        "Click to switch between Current and Weekly view."
    )

    toggleBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local mode = (ns.UI_GetPvECurrencyDisplayMode and ns.UI_GetPvECurrencyDisplayMode()) or "current"
        local activeLabel = (mode == "weekly")
            and GetLocalizedText("PVE_CURRENCY_VIEW_WEEKLY", "Weekly")
            or GetLocalizedText("PVE_CURRENCY_VIEW_CURRENT", "Current")
        GameTooltip:SetText(activeLabel, 1, 1, 1)
        GameTooltip:AddLine(toggleHint, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(shiftHint, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    toggleBtn:SetScript("OnClick", function()
        if ns.UI_TogglePvECurrencyDisplayMode then
            ns.UI_TogglePvECurrencyDisplayMode()
        elseif ns.UI_SetPvECurrencyDisplayMode then
            local mode = (ns.UI_GetPvECurrencyDisplayMode and ns.UI_GetPvECurrencyDisplayMode()) or "current"
            ns.UI_SetPvECurrencyDisplayMode((mode == "weekly") and "current" or "weekly")
        end
        PvE_RefreshCurrencyDisplayToggleChrome(toggleBtn, toggleLbl)
    end)

    return toggleBtn
end

local function PvE_AttachInlineColumnPicker(titleCard, sortAnchor, addon)
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateButton then return sortAnchor end

    local hideBtn = Factory:CreateButton(titleCard, 84, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32, false)
    if ApplyVisuals then
        ApplyVisuals(hideBtn, ControlChromeBackdrop(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    WarbandNexus._wnPvEHideFilterBtn = hideBtn
    local hideBtnText = FontManager:CreateFontString(hideBtn, "body", "OVERLAY")
    hideBtnText:SetPoint("CENTER", 0, 0)
    hideBtnText:SetJustifyH("CENTER")
    ns.UI_SetTextColorRole(hideBtnText, "Bright")
    hideBtnText:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"))
    if Factory.ApplyHighlight then Factory:ApplyHighlight(hideBtn) end
    local hdrGapPicker = (ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics().gap) or 8
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(hideBtn, titleCard, sortAnchor, "LEFT", -hdrGapPicker)
    else
        hideBtn:SetPoint("RIGHT", sortAnchor, "LEFT", -hdrGapPicker, 0)
    end

    local function HideMenuClose()
        if hideBtn._menu and hideBtn._menu:IsShown() then hideBtn._menu:Hide() end
        if hideBtn._catcher and hideBtn._catcher:IsShown() then hideBtn._catcher:Hide() end
    end
    local function HideMenuApply(threshold, keepMenuOpen)
        ApplyLowLevelHideThreshold(addon, threshold)
        if not keepMenuOpen then
            HideMenuClose()
        end
    end
    local function HideMenuBuild()
        local menu = hideBtn._menu
        if not menu then
            menu = Factory:CreateContainer(UIParent, 132, 66, false)
            if not menu then
                menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                menu:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                menu:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
                menu:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75)
            elseif ApplyVisuals then
                ApplyVisuals(menu, ControlChromeBackdrop(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75 })
            else
                if not menu.SetBackdrop and BackdropTemplateMixin then
                    Mixin(menu, BackdropTemplateMixin)
                end
                menu:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                menu:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
                menu:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75)
            end
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(5200)
            hideBtn._menu = menu
            if Factory.EnsureDropdownEscClose then
                Factory:EnsureDropdownEscClose(menu)
            end
        end
        local profile = addon and addon.db and addon.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        local options = {
            { value = 80, label = GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") },
            { value = 90, label = GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") },
        }
        local children = { menu:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #children do
            children[i]:Hide()
            if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
        end
        local rowH = 30
        local menuInnerW = math.max(42, menu:GetWidth() - 6)
        for i = 1, #options do
            local opt = options[i]
            -- Factory shell + single ApplyVisuals pass (avoid default CreateButton fill before row tint).
            local row = Factory:CreateButton(menu, menuInnerW, rowH - 2, true)
            row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * rowH)
            row:SetHeight(rowH - 2)
            row:RegisterForClicks("LeftButtonUp")
            local selBg = ControlChromeHoverBackdrop()
            if (opt.value == cur) then
                selBg = { selBg[1] * 1.08, selBg[2] * 1.08, selBg[3] * 1.08, selBg[4] or 1 }
            end
            if ApplyVisuals then
                ApplyVisuals(row, selBg, { COLORS.accent[1] * 0.45, COLORS.accent[2] * 0.45, COLORS.accent[3] * 0.45, 0.45 })
            else
                if not row.SetBackdrop and BackdropTemplateMixin then
                    Mixin(row, BackdropTemplateMixin)
                end
                if row.SetBackdrop then
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                    row:SetBackdropColor(selBg, selBg, (opt.value == cur) and 0.20 or 0.10, 1)
                end
            end
            local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, opt.value == cur)
            if not cb then return menu end
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", row, "LEFT", 6, 0)
            cb:EnableMouse(false)
            local fs = FontManager:CreateFontString(row, "body", "OVERLAY")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(opt.label)
            ns.UI_SetTextColorRole(fs, "Bright")
            row:SetScript("OnClick", function()
                local active = GetLowLevelHideThreshold(addon and addon.db and addon.db.profile)
                local nextThreshold = (active == opt.value) and 0 or opt.value
                HideMenuApply(nextThreshold, true)
                HideMenuBuild()
            end)
        end
        return menu
    end
    hideBtn:SetScript("OnClick", function(self)
        local menu = hideBtn._menu
        if menu and menu:IsShown() then
            HideMenuClose()
            return
        end
        -- avoid overlap with columns menu
        WarbandNexus:HidePvEColumnPickerMenu()
        menu = HideMenuBuild()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        menu:Show()
        local catcher = hideBtn._catcher
        if not catcher then
            -- Intentionally raw fullscreen dismiss layer (parity with Columns picker catcher; strata/order).
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetFrameLevel(5199)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function(_, button)
                if menu and menu:IsShown() and not menu:IsMouseOver() and not hideBtn:IsMouseOver() then
                    HideMenuClose()
                end
            end)
            hideBtn._catcher = catcher
        end
        catcher:Show()
    end)
    hideBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"), 1, 1, 1)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_TOGGLE", "Toggle filters: Level 80 / Level 90"), 0.8, 0.8, 0.8)
        local profile = addon and addon.db and addon.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_CURRENT", "Current: %s"):format(GetLowLevelHideLabel(cur)), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local columnsBtn = Factory:CreateButton(titleCard, 86, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32, false)
    if ApplyVisuals then
        ApplyVisuals(columnsBtn, ControlChromeBackdrop(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local columnsBtnText = FontManager:CreateFontString(columnsBtn, "body", "OVERLAY")
    columnsBtnText:SetPoint("CENTER", 0, 0)
    columnsBtnText:SetJustifyH("CENTER")
    columnsBtnText:SetText(GetLocalizedText("COLUMNS_BUTTON", "Columns"))
    ns.UI_SetTextColorRole(columnsBtnText, "Bright")
    if Factory.ApplyHighlight then Factory:ApplyHighlight(columnsBtn) end
    columnsBtn:SetPoint("RIGHT", hideBtn, "LEFT", -8, 0)

    WarbandNexus._wnPvEColumnPickerAnchorBtn = columnsBtn

    columnsBtn:SetScript("OnClick", function(btn)
        WarbandNexus._wnPvEColumnPickerAnchorBtn = btn
        local menu = WarbandNexus._wnPvEColumnPickerMenu
        if menu and menu:IsShown() then
            WarbandNexus:HidePvEColumnPickerMenu()
            return
        end

        menu = PvE_GetOrCreateColumnPickerMenu()
        if not menu then return end

        PvE_ColumnPickerPopulateMenu(menu, addon)
        PvE_ColumnPickerPositionMenu(menu, btn)
        PvE_ColumnPickerHideTooltipLayers()
        menu:Show()
        PvE_ColumnPickerShowCatcher(menu)
    end)

    return columnsBtn
end

ns.PvE_RefreshCurrencyDisplayToggleChrome = PvE_RefreshCurrencyDisplayToggleChrome
ns.PvE_AttachCurrencyDisplayToggle = PvE_AttachCurrencyDisplayToggle
ns.PvE_AttachInlineColumnPicker = PvE_AttachInlineColumnPicker
-- PvEDrawLibs snapshots ns refs at PvEUI.lua load; patch after this satellite loads.
if ns.PvEDrawLibs then
    ns.PvEDrawLibs.PvE_AttachCurrencyDisplayToggle = PvE_AttachCurrencyDisplayToggle
    ns.PvEDrawLibs.PvE_AttachInlineColumnPicker = PvE_AttachInlineColumnPicker
end
