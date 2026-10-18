--[[
    Warband Nexus - PvE tab column picker + low-level hide filter flyout.
    Split from PvEUI.lua (Lua 5.1 local limit).
    Loaded after Modules/UI/PvEUI.lua (uses ns.PvEUI column helpers).
]]

local _, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals

--- Skip ApplyVisuals on Blizzard template widgets (classic dropdown guards).
local function ApplyPvEChrome(frame, bg, border)
    if not frame or not ApplyVisuals then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    ApplyVisuals(frame, bg, border)
end

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
-- PvE Columns dropdown: shared TK.ColumnPicker shell (SharedWidgets_TableKit.lua) + PvE row adapter.
-- Storage: profile.pveColumnOrder (order), pveExtraVisibleColumns (crest/extra keys), vaultButton columns.
local PvEColumnPicker

local function PvE_ColumnPickerProfile()
    return WarbandNexus.db and WarbandNexus.db.profile
end

--- One row per PvE toggle; vault = true rows also refresh the Great Vault button.
local function PvE_BuildColumnPickerRows()
    local profile = PvE_ColumnPickerProfile()
    if not profile then return nil end
    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)
    local rows = {}
    for i = 1, #crestDefs do
        local id = crestDefs[i].id
        local labelKey = crestDefs[i].labelKey
        local crestLabel = labelKey and GetLocalizedText(labelKey, GetLocalizedText("PVE_CREST_GENERIC", "Mistcrest")) or GetLocalizedText("PVE_CREST_GENERIC", "Mistcrest")
        local ck = "crest_" .. tostring(id)
        rows[#rows + 1] = { key = ck, label = crestLabel, checked = ex[ck] ~= false, vault = false, onToggle = function(checked) ex[ck] = checked end }
    end
    rows[#rows + 1] = { key = "coffer_shards", label = GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"), checked = ex.coffer_shards ~= false, vault = false, onToggle = function(checked) ex.coffer_shards = checked end }
    rows[#rows + 1] = { key = "restored_key", label = GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"), checked = ex.restored_key ~= false, vault = false, onToggle = function(checked) ex.restored_key = checked end }
    rows[#rows + 1] = { key = "shard_of_dundun", label = GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"), checked = ex.shard_of_dundun ~= false, vault = false, onToggle = function(checked) ex.shard_of_dundun = checked end }
    rows[#rows + 1] = { key = "voidcore", label = GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"), checked = vc.voidcore ~= false, vault = true, onToggle = function(checked) vc.voidcore = checked end }
    local manafluxLabel = (ns.PvEUI and ns.PvEUI.GetPvEManafluxName and ns.PvEUI.GetPvEManafluxName()) or "Venomblight Manaflux"
    rows[#rows + 1] = { key = "manaflux", label = manafluxLabel, checked = vc.manaflux == true, vault = true, onToggle = function(checked) vc.manaflux = checked profile.vaultButton = profile.vaultButton or {} profile.vaultButton.showManaflux = checked end }
    rows[#rows + 1] = { key = "slot1", label = GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"), checked = vc.raids ~= false, vault = true, onToggle = function(checked) vc.raids = checked end }
    rows[#rows + 1] = { key = "slot2", label = GetLocalizedText("VAULT_DUNGEON", "Dungeon"), checked = vc.mythicPlus ~= false, vault = true, onToggle = function(checked) vc.mythicPlus = checked end }
    rows[#rows + 1] = { key = "slot3", label = GetLocalizedText("VAULT_SLOT_WORLD", "World"), checked = vc.world ~= false, vault = true, onToggle = function(checked) vc.world = checked end }
    rows[#rows + 1] = { key = "bountiful", label = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty"), checked = vc.bounty ~= false, vault = true, onToggle = function(checked) vc.bounty = checked end }
    rows[#rows + 1] = { key = "nightmare_task", label = GetLocalizedText("PVE_COL_NIGHTMARE_TASK", "A Nightmarish Task"), checked = ex.nightmare_task ~= false, vault = false, onToggle = function(checked) ex.nightmare_task = checked end }
    rows[#rows + 1] = { key = "tormented_soul", label = GetLocalizedText("PVE_COL_TORMENTED_SOUL", "Tormented Soul"), checked = ex.tormented_soul ~= false, vault = false, onToggle = function(checked) ex.tormented_soul = checked end }
    rows[#rows + 1] = { key = "purging_vaults", label = GetLocalizedText("PVE_COL_PURGING_VAULTS", "Purging the Vaults"), checked = ex.purging_vaults ~= false, vault = false, onToggle = function(checked) ex.purging_vaults = checked end }
    rows[#rows + 1] = { key = "delve_nemesis", label = GetLocalizedText("PVE_COL_DELVE_NEMESIS", "Delve Nemesis"), checked = ex.delve_nemesis ~= false, vault = false, onToggle = function(checked) ex.delve_nemesis = checked end }
    return rows
end

local function PvE_ColumnPickerShowAll()
    local profile = PvE_ColumnPickerProfile()
    if not profile then return end
    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)
    for j = 1, #crestDefs do
        ex["crest_" .. tostring(crestDefs[j].id)] = true
    end
    ex.coffer_shards = true
    ex.restored_key = true
    ex.shard_of_dundun = true
    ex.nightmare_task = true
    ex.tormented_soul = true
    ex.purging_vaults = true
    ex.delve_nemesis = true
    vc.raids = true
    vc.mythicPlus = true
    vc.world = true
    vc.bounty = true
    vc.voidcore = true
    vc.manaflux = true
    profile.vaultButton = profile.vaultButton or {}
    profile.vaultButton.showManaflux = true
end

local function PvE_ColumnPickerOnChange(_, reason, row)
    local vaultColTouched = (reason == "showAll") or (row ~= nil and row.vault == true)
    if vaultColTouched and WarbandNexus.RefreshVaultButtonSettings then
        WarbandNexus:RefreshVaultButtonSettings()
    end
    if ns.PvEUI and ns.PvEUI.InvalidateBodyCache then
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mf and mf.scrollChild then
            ns.PvEUI.InvalidateBodyCache(mf.scrollChild)
        end
    end
    WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
end

local function PvE_GetColumnPicker()
    if PvEColumnPicker then return PvEColumnPicker end
    local TK = ns.UI_TableKit
    if not TK or not TK.ColumnPicker then return nil end
    PvEColumnPicker = TK.ColumnPicker.Create({
        owner = WarbandNexus,
        menuRef = "_wnPvEColumnPickerMenu",
        anchorRef = "_wnPvEColumnPickerAnchorBtn",
        catcherRef = "_wnPvEColumnPickerCatcher",
        catcherName = "WarbandNexusPvEColumnPickerCatcher",
        getRows = PvE_BuildColumnPickerRows,
        getOrder = function()
            return EnsurePvEColumnOrder(PvE_ColumnPickerProfile())
        end,
        getDefaultOrder = function()
            return GetPvEDefaultColumnKeyOrder(PvE_ColumnPickerProfile()), nil
        end,
        showAll = PvE_ColumnPickerShowAll,
        onChange = PvE_ColumnPickerOnChange,
        isContextActive = function()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            return mf ~= nil and mf.currentTab == "pve"
        end,
    })
    return PvEColumnPicker
end

function WarbandNexus:HidePvEColumnPickerMenu()
    local picker = PvE_GetColumnPicker()
    if picker then picker:Close() end
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
    if toggleBtn and ApplyPvEChrome then
        ApplyPvEChrome(toggleBtn, active, border)
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
    if not sortAnchor then return sortAnchor end

    local toggleBtn, toggleLbl = ns.UI_CreateTitleToolbarTextButton(titleCard, {
        preset = "toggle",
        text = GetLocalizedText("PVE_CURRENCY_VIEW_CURRENT", "Current"),
    })
    if not toggleBtn then return sortAnchor end

    ns.UI_ChainTitleToolbarControl(titleCard, toggleBtn, sortAnchor)

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
        local bodyR, bodyG, bodyB = 0.8, 0.8, 0.8
        if ns.UI_GetTooltipDescColor then
            bodyR, bodyG, bodyB = ns.UI_GetTooltipDescColor()
        end
        GameTooltip:AddLine(toggleHint, bodyR, bodyG, bodyB)
        GameTooltip:AddLine(shiftHint, bodyR, bodyG, bodyB)
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

local function PvE_AttachPvEColumnsButton(titleCard, sortAnchor, addon)
    if not sortAnchor then return sortAnchor end

    local columnsBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
        preset = "columns",
        localeKey = "COLUMNS_BUTTON",
        onClick = function(btn)
            local picker = PvE_GetColumnPicker()
            if picker then picker:Toggle(btn) end
        end,
    })
    if not columnsBtn then return sortAnchor end

    ns.UI_ChainTitleToolbarControl(titleCard, columnsBtn, sortAnchor)
    WarbandNexus._wnPvEColumnPickerAnchorBtn = columnsBtn
    return columnsBtn
end

local function PvE_AttachHideLevelFilterButton(titleCard, sortAnchor, addon)
    if not sortAnchor then return sortAnchor end

    local hideBtn = ns.UI_CreateTitleToolbarHideLevelButton(titleCard, {
        addon = addon,
        globalRefKey = "_wnPvEHideFilterBtn",
        onBeforeOpen = function()
            if WarbandNexus.HidePvEColumnPickerMenu then
                WarbandNexus:HidePvEColumnPickerMenu()
            end
        end,
    })
    if not hideBtn then return sortAnchor end

    ns.UI_ChainTitleToolbarControl(titleCard, hideBtn, sortAnchor)
    return hideBtn
end

ns.PvE_RefreshCurrencyDisplayToggleChrome = PvE_RefreshCurrencyDisplayToggleChrome
ns.PvE_AttachCurrencyDisplayToggle = PvE_AttachCurrencyDisplayToggle
ns.PvE_AttachPvEColumnsButton = PvE_AttachPvEColumnsButton
ns.PvE_AttachHideLevelFilterButton = PvE_AttachHideLevelFilterButton
-- PvEDrawLibs snapshots ns refs at PvEUI.lua load; patch after this satellite loads.
if ns.PvEDrawLibs then
    ns.PvEDrawLibs.PvE_AttachCurrencyDisplayToggle = PvE_AttachCurrencyDisplayToggle
    ns.PvEDrawLibs.PvE_AttachPvEColumnsButton = PvE_AttachPvEColumnsButton
    ns.PvEDrawLibs.PvE_AttachHideLevelFilterButton = PvE_AttachHideLevelFilterButton
end
