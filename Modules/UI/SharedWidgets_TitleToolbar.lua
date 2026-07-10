--[[
    Warband Nexus - Standard tab title-card toolbar buttons (single chrome + widths).
    Loaded after SharedWidgets_CharacterFilter.lua (WarbandNexus.toc).
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS

local function ChromeBackdrop()
    return ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { 0.12, 0.12, 0.15, 1 }
end

local function ChromeHoverBackdrop()
    return ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.15, 0.15, 0.15, 0.8 }
end

local function AccentBorderRGBA(alpha)
    local acc = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
    return { acc[1], acc[2], acc[3], alpha or 0.6 }
end

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

local PRESET_FALLBACK = {
    filter = 96,
    columns = 86,
    hide = 84,
    toggle = 88,
    default = 80,
    action = 100,
}

---@param preset string|nil filter|columns|hide|toggle|default|action
function ns.UI_GetTitleToolbarPresetWidth(preset)
    preset = preset or "default"
    local m = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics()
    if m then
        if preset == "filter" then return m.filterW end
        if preset == "columns" then return m.columnsW end
        if preset == "hide" then return m.hideW end
        if preset == "toggle" then return m.toggleW end
        if preset == "action" then return m.actionW end
        return m.filterW and m.filterW or PRESET_FALLBACK.default
    end
    return PRESET_FALLBACK[preset] or PRESET_FALLBACK.default
end

function ns.UI_AnchorTitleToolbarControlRight(titleCard, btn)
    if not btn or not titleCard then return end
    local m = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local inset = m.edgeInset or 0
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(btn, titleCard, titleCard, "RIGHT", -inset)
    else
        btn:SetPoint("RIGHT", titleCard, "RIGHT", -inset, 0)
    end
end

--- Chain toolbar control immediately left of anchorTo (returns btn for further chaining).
function ns.UI_ChainTitleToolbarControl(titleCard, btn, anchorTo)
    if not btn or not anchorTo then return anchorTo end
    local m = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local gap = m.gap or 8
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(btn, titleCard, anchorTo, "LEFT", -gap)
    else
        btn:SetPoint("RIGHT", anchorTo, "LEFT", -gap, 0)
    end
    return btn
end

--- Standard title-card text toolbar button (Factory chrome, 32px height, preset widths).
--- opts: preset, width, text, localeKey, autoWidth, padH, noBorder, onClick, onEnter, onLeave
---@return Button|nil btn, FontString|nil label
function ns.UI_CreateTitleToolbarTextButton(parent, opts)
    opts = opts or {}
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateButton or not parent then return nil end

    local btnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local width = opts.width
    if not width and opts.preset then
        width = ns.UI_GetTitleToolbarPresetWidth(opts.preset)
    end
    width = width or ns.UI_GetTitleToolbarPresetWidth("default")

    local btn = Factory:CreateButton(parent, width, btnH, opts.noBorder == true)
    if not btn then return nil end

    local useBlizzardBtn = btn._wnBlizzardButton == true

    if not useBlizzardBtn then
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(btn, ChromeBackdrop(), AccentBorderRGBA(0.6))
        end
        if Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
        end
    end

    local labelText = opts.text
    if not labelText and opts.localeKey then
        labelText = GetLocalizedText(opts.localeKey, opts.localeKey)
    end
    labelText = labelText or ""

    local fs
    if useBlizzardBtn then
        btn:SetText(labelText)
    else
        fs = FontManager:CreateFontString(btn, "body", "OVERLAY")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        fs:SetText(labelText)
        if ns.UI_SetTextColorRole then
            ns.UI_SetTextColorRole(fs, "Bright")
        end
        btn._toolbarLabel = fs
    end

    if opts.autoWidth then
        local padH = opts.padH or 12
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if useBlizzardBtn and btn and btn.GetFontString then
                    local bfs = btn:GetFontString()
                    if bfs and bfs.GetStringWidth and bfs:GetStringWidth() > 0 then
                        btn:SetWidth(bfs:GetStringWidth() + padH * 2)
                    end
                elseif fs and btn and fs.GetStringWidth and fs:GetStringWidth() > 0 then
                    btn:SetWidth(fs:GetStringWidth() + padH * 2)
                end
            end)
        end
    end

    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    if opts.onEnter then btn:SetScript("OnEnter", opts.onEnter) end
    if opts.onLeave then btn:SetScript("OnLeave", opts.onLeave) end

    return btn, fs
end

-- Low-level hide filter (shared PvE / Gear profile keys)
function ns.UI_GetLowLevelHideThreshold(profile)
    if not profile then return 0 end
    local threshold = tonumber(profile.hideLowLevelThreshold) or 0
    if threshold >= 90 then return 90 end
    if threshold >= 80 then return 80 end
    if profile.hideLowLevelCharacters == true then
        return 80
    end
    return 0
end

function ns.UI_GetLowLevelHideLabel(threshold)
    if threshold == 90 then return GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") end
    if threshold == 80 then return GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

function ns.UI_ApplyLowLevelHideThreshold(addon, threshold)
    local addonRef = addon or WarbandNexus
    local profile = addonRef and addonRef.db and addonRef.db.profile
    if not profile then return end
    local nextThreshold = tonumber(threshold) or 0
    if nextThreshold ~= 80 and nextThreshold ~= 90 then
        nextThreshold = 0
    end
    profile.hideLowLevelThreshold = nextThreshold
    profile.hideLowLevelCharacters = (nextThreshold >= 80)
    local events = ns.Constants and ns.Constants.EVENTS
    if addonRef and addonRef.SendMessage and events and events.CHARACTER_TRACKING_CHANGED then
        addonRef:SendMessage(events.CHARACTER_TRACKING_CHANGED, {
            source = "HideFilter",
            threshold = nextThreshold,
        })
    end
end

--- Hide level 80/90 flyout (title toolbar preset width + shared menu).
--- opts: addon, onBeforeOpen, globalRefKey (WarbandNexus field name)
function ns.UI_CreateTitleToolbarHideLevelButton(parent, opts)
    opts = opts or {}
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateButton or not parent then return nil end

    local addon = opts.addon or WarbandNexus
    local btn, hideBtnText = ns.UI_CreateTitleToolbarTextButton(parent, {
        preset = "hide",
        localeKey = "HIDE_FILTER_BUTTON",
        text = GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"),
    })
    if not btn then return nil end

    if opts.globalRefKey and WarbandNexus then
        WarbandNexus[opts.globalRefKey] = btn
    end

    local function HideMenuClose()
        if btn._menu and btn._menu:IsShown() then btn._menu:Hide() end
        if btn._catcher and btn._catcher:IsShown() then btn._catcher:Hide() end
    end
    local function HideMenuApply(threshold, keepMenuOpen)
        ns.UI_ApplyLowLevelHideThreshold(addon, threshold)
        if not keepMenuOpen then
            HideMenuClose()
        end
    end
    local function HideMenuBuild()
        local menu = btn._menu
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
                local acc = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
                menu:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.75)
            elseif ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(menu, ChromeBackdrop(), AccentBorderRGBA(0.75))
            end
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(5200)
            btn._menu = menu
            if Factory.EnsureDropdownEscClose then
                Factory:EnsureDropdownEscClose(menu)
            end
        end
        local profile = addon and addon.db and addon.db.profile
        local cur = ns.UI_GetLowLevelHideThreshold(profile)
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
            local row = Factory:CreateButton(menu, menuInnerW, rowH - 2, true)
            row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * rowH)
            row:SetHeight(rowH - 2)
            row:RegisterForClicks("LeftButtonUp")
            local selBg = ChromeHoverBackdrop()
            if opt.value == cur then
                selBg = { selBg[1] * 1.08, selBg[2] * 1.08, selBg[3] * 1.08, selBg[4] or 1 }
            end
            if ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(row, selBg, AccentBorderRGBA(0.45))
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
            if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(fs, "Bright") end
            row:SetScript("OnClick", function()
                local active = ns.UI_GetLowLevelHideThreshold(addon and addon.db and addon.db.profile)
                local nextThreshold = (active == opt.value) and 0 or opt.value
                HideMenuApply(nextThreshold, true)
                HideMenuBuild()
            end)
        end
        return menu
    end

    btn:SetScript("OnClick", function(self)
        local menu = btn._menu
        if menu and menu:IsShown() then
            HideMenuClose()
            return
        end
        if opts.onBeforeOpen then opts.onBeforeOpen() end
        menu = HideMenuBuild()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        menu:Show()
        local catcher = btn._catcher
        if not catcher then
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetFrameLevel(5199)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function()
                -- Catcher sits above the toolbar button, so it eats the second click before the button's
                -- own toggle OnClick can fire. Close on any click outside the menu (button included) so
                -- clicking Hide again closes it. Clicks inside the menu land on the higher-level rows.
                if menu and menu:IsShown() and not menu:IsMouseOver() then
                    HideMenuClose()
                end
            end)
            btn._catcher = catcher
        end
        catcher:Show()
    end)
    btn:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"), 1, 1, 1)
        local bodyR, bodyG, bodyB = 0.8, 0.8, 0.8
        if ns.UI_GetTooltipDescColor then
            bodyR, bodyG, bodyB = ns.UI_GetTooltipDescColor()
        end
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_TOGGLE", "Toggle filters: Level 80 / Level 90"), bodyR, bodyG, bodyB)
        local profile = addon and addon.db and addon.db.profile
        local cur = ns.UI_GetLowLevelHideThreshold(profile)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_CURRENT", "Current: %s"):format(ns.UI_GetLowLevelHideLabel(cur)), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return btn, hideBtnText
end
