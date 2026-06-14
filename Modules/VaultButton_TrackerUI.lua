--[[ Warband Nexus - Easy Access - VaultButton_TrackerUI.lua ]]

local ADDON_NAME, ns = ...
local M = assert(ns.VaultButton)
local WarbandNexus = ns.WarbandNexus
local S = M.state

local function VB__setfenv()
    return setmetatable({ M = M, ns = ns, WarbandNexus = WarbandNexus, S = M.state }, {
        __index = function(_, k)
            local v = M[k]
            if v ~= nil then return v end
            return _G[k]
        end,
    })
end
setfenv(1, VB__setfenv())
-- Main button
function M.CreateMenuCheckbox(parent, labelText, y, getValue, setValue, tooltipText)
    if ns.UI_CreateThemedCheckbox then
        cb = ns.UI_CreateThemedCheckbox(parent, getValue() == true)
    else
        cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetChecked(getValue())
    end
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)

    local FontManager = ns.FontManager
    if FontManager and FontManager.CreateFontString then
        label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    else
        label = VBFontString(parent, "small")
    end
    label:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
    label:SetText(labelText)
    ns.UI_SetTextColorRole(label, "Bright")
    label:SetJustifyH("LEFT")

    if tooltipText and tooltipText ~= "" then
        function M.ShowTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if ns.UI_GameTooltipAddRoleLine then
                ns.UI_GameTooltipAddRoleLine(GameTooltip, labelText, "Bright")
            else
                GameTooltip:AddLine(labelText, 1, 1, 1)
            end
            local mr, mg, mb = 0.85, 0.85, 0.85
            GameTooltip:AddLine(tooltipText, mr, mg, mb, true)
            GameTooltip:Show()
        end
        cb:SetScript("OnEnter", ShowTooltip)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        label:EnableMouse(true)
        label:SetScript("OnEnter", ShowTooltip)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- ThemedCheckbox already has OnClick that toggles innerDot; chain our handler
    local prevOnClick = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(self, ...)
        if prevOnClick then prevOnClick(self, ...) end
        setValue(self:GetChecked() and true or false)
        RefreshButtonSettings()
    end)

    cb.RefreshValue = function(self)
        local v = getValue() == true
        self:SetChecked(v)
        if self.innerDot then self.innerDot:SetShown(v) end
    end
    table.insert(S.optionsWidgets, cb)
    return cb
end

function M.BuildOptionsFrame()
    if S.optionsFrame then return end

    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusVaultButtonOptions", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultButtonOptions")
    f:SetSize(286, 372)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(210)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, GetShellBackdrop(), {accent[1], accent[2], accent[3], 1})
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local shell = GetShellBackdrop()
        f:SetBackdropColor(shell[1], shell[2], shell[3], shell[4] or 0.98)
    end
    f:Hide()

    -- Chrome header
    local chrome = VF:CreateContainer(f, 32, 32, false)
    VBAnchorChromeBandTop(chrome, f)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    if ApplyVisuals then
        ApplyVisuals(chrome, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end

    local titleIcon = chrome:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture(ICON_TEXTURE)
    if not titleIcon:GetTexture() then titleIcon:SetTexture(ICON_FALLBACK) end

    local FontManager = ns.FontManager
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        title = FontManager:CreateFontString(chrome, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        title = VBFontString(chrome, "body")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Vault Tracker")
    ns.UI_SetTextColorRole(title, "Bright")
    f.title = title

    local close = VF:CreateButton(chrome, 28, 28, true)
    close:SetPoint("RIGHT", -8, 0)
    local closeBtnBg = (ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop()) or { 0.15, 0.15, 0.15, 0.9 }
    if ApplyVisuals then
        ApplyVisuals(close, closeBtnBg, {accent[1], accent[2], accent[3], 0.8})
    end
    local closeIcon = close:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then ApplyVisuals(close, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1}) end
    end)
    close:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then ApplyVisuals(close, closeBtnBg, {accent[1], accent[2], accent[3], 0.8}) end
    end)

    CreateMenuCheckbox(f, "Show Realm Names", -52,
        function() return GetSettings().showRealmName == true end,
        function(value)
            GetSettings().showRealmName = value
            if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
        end)
    CreateMenuCheckbox(f, "Show Reward iLvl", -78,
        function() return GetSettings().showRewardItemLevel == true end,
        function(value)
            GetSettings().showRewardItemLevel = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Show Reward Progress", -104,
        function() return GetSettings().showRewardProgress == true end,
        function(value)
            GetSettings().showRewardProgress = value
            RebuildTableFrame()
        end,
        "Show current progress toward the next vault reward threshold.")
    CreateMenuCheckbox(f, "Include Delver's Bounty", -130,
        function() return GetSettings().includeBountyOnly == true end,
        function(value)
            GetSettings().includeBountyOnly = value
            RebuildTableFrame()
        end,
        "Also show characters that have only looted a Delver's Bounty.")
    local columnLabel = VBFontString(f, "small")
    columnLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -168)
    columnLabel:SetText("Columns")
    if ns.UI_SetInkColor then
        ns.UI_SetInkColor(columnLabel, accent[1], accent[2], accent[3], 1)
    else
        columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    f.columnLabel = columnLabel

    CreateMenuCheckbox(f, "Raid", -188,
        function() return GetSettings().columns.raids ~= false end,
        function(value)
            GetSettings().columns.raids = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dungeon", -214,
        function() return GetSettings().columns.mythicPlus ~= false end,
        function(value)
            GetSettings().columns.mythicPlus = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "World", -240,
        function() return GetSettings().columns.world ~= false end,
        function(value)
            GetSettings().columns.world = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Trovehunter's Bounty", -266,
        function() return GetSettings().columns.bounty ~= false end,
        function(value)
            GetSettings().columns.bounty = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Gilded Stashes", -292,
        function() return GetSettings().columns.gildedStash == true end,
        function(value)
            GetSettings().columns.gildedStash = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Nebulous Voidcore", -318,
        function() return GetSettings().columns.voidcore ~= false end,
        function(value)
            GetSettings().columns.voidcore = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dawnlight Manaflux", -344,
        function() return GetSettings().columns.manaflux == true end,
        function(value)
            GetSettings().columns.manaflux = value
            GetSettings().showManaflux = value
            RebuildTableFrame()
        end)
    f.RefreshValues = function()
        S.refreshingOptions = true
        for _, widget in ipairs(S.optionsWidgets) do
            if widget and widget.RefreshValue then
                widget:RefreshValue()
            end
        end
        S.refreshingOptions = false
    end

    S.optionsFrame = f
end

local ToggleOptionsFrame = function(anchor, placement)
    BuildOptionsFrame()
    if not S.optionsFrame then return end
    if S.optionsFrame:IsShown() then
        S.optionsFrame:Hide()
        return
    end
    S.optionsFrame:ClearAllPoints()
    anchor = anchor or S.button
    if anchor and placement == "RIGHT" then
        S.optionsFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    elseif anchor then
        S.optionsFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    else
        S.optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    S.optionsFrame:Show()
    ApplyTheme()
end

M.ToggleOptionsFrame = ToggleOptionsFrame

