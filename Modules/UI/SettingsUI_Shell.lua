--[[
    Warband Nexus - Settings UI shell (category nav + panel routing)
    Split from SettingsUI.lua to keep chunk locals under limit.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS or { accent = { 0.40, 0.20, 0.58, 1 } }
local ApplyVisuals = ns.UI_ApplyVisuals

ns.SettingsUI = ns.SettingsUI or {}

local M = ns.SettingsUI

M.PANEL_ORDER = {
    "general",
    "modules",
    "access",
    "filters",
    "notifications",
    "appearance",
    "advanced",
}

local PANEL_META = {
    general = {
        locale = "SETTINGS_PANEL_GENERAL",
        descLocale = "SETTINGS_PANEL_GENERAL_DESC",
        fallback = "General",
        descFallback = "Display, shortcuts, keybinding, and window scaling.",
        iconKey = "settings",
    },
    modules = {
        locale = "SETTINGS_PANEL_MODULES",
        descLocale = "SETTINGS_PANEL_MODULES_DESC",
        fallback = "Modules",
        descFallback = "Turn data modules on or off and control which tabs appear.",
        iconKey = "professions",
    },
    access = {
        locale = "SETTINGS_PANEL_ACCESS",
        descLocale = "SETTINGS_PANEL_ACCESS_DESC",
        fallback = "Easy Access",
        descFallback = "Floating shortcut button and quick-open actions.",
        iconKey = "pve",
    },
    filters = {
        locale = "SETTINGS_PANEL_FILTERS",
        descLocale = "SETTINGS_PANEL_FILTERS_DESC",
        fallback = "Tab filters",
        descFallback = "Choose which main tabs show in the navigation.",
        iconKey = "items",
    },
    notifications = {
        locale = "SETTINGS_PANEL_NOTIFICATIONS",
        descLocale = "SETTINGS_PANEL_NOTIFICATIONS_DESC",
        fallback = "Notifications",
        descFallback = "Popups, chat alerts, collectibles, and try-counter behavior.",
        iconKey = "plans",
    },
    appearance = {
        locale = "SETTINGS_PANEL_APPEARANCE",
        descLocale = "SETTINGS_PANEL_APPEARANCE_DESC",
        fallback = "Theme",
        descFallback = "Theme colors, fonts, and preset palettes.",
        iconKey = "collections",
    },
    advanced = {
        locale = "SETTINGS_PANEL_ADVANCED",
        descLocale = "SETTINGS_PANEL_ADVANCED_DESC",
        fallback = "Advanced",
        descFallback = "Debug logging, cache refresh, and item tracking.",
        iconKey = "stats",
    },
}

local VALID_PANEL = {}
for i = 1, #M.PANEL_ORDER do
    VALID_PANEL[M.PANEL_ORDER[i]] = true
end

local function PanelMeta(panelId)
    return PANEL_META[panelId]
end

function M.PanelLabel(panelId)
    local meta = PanelMeta(panelId)
    if not meta then return panelId end
    return (ns.L and ns.L[meta.locale]) or meta.fallback
end

function M.PanelDescription(panelId)
    local meta = PanelMeta(panelId)
    if not meta then return nil end
    return (ns.L and ns.L[meta.descLocale]) or meta.descFallback
end

function M.PanelIconKey(panelId)
    local meta = PanelMeta(panelId)
    return meta and meta.iconKey or "settings"
end

function M.GetActivePanel()
    local db = WarbandNexus.db and WarbandNexus.db.profile
    local p = db and db.settingsPanel
    if p == "about" then
        return "general"
    end
    if p and VALID_PANEL[p] then return p end
    return "general"
end

function M.SetActivePanel(panelId)
    if not VALID_PANEL[panelId] then return end
    local db = WarbandNexus.db and WarbandNexus.db.profile
    if not db then return end
    db.settingsPanel = panelId
    if ns.UI_UpdateMainFrameTabButtonStates and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        ns.UI_UpdateMainFrameTabButtonStates(WarbandNexus.UI.mainFrame)
    end
end

function M.PanelActive(layoutOpts, panelId)
    if not layoutOpts or not layoutOpts.panel then return true end
    return layoutOpts.panel == panelId
end

---Rail-matched active/idle visuals for settings category buttons.
---@param parent Frame nav column (holds _wnSettingsNavButtons)
---@param activeId string
function M.ApplyCategoryNavStates(parent, activeId)
    if not parent or not parent._wnSettingsNavButtons then return end
    local freshColors = ns.UI_COLORS or COLORS
    local accentColor = freshColors.accent or COLORS.accent
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local railActiveA = (ns.UI_GetNavRailActiveBgAlpha and ns.UI_GetNavRailActiveBgAlpha())
        or shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.38
    local fm = FontManager

    for i = 1, #parent._wnSettingsNavButtons do
        local btn = parent._wnSettingsNavButtons[i]
        if btn and btn:IsShown() then
            local panelId = btn._wnSettingsPanelId
            local isActive = (panelId == activeId)
            if btn._wnBlizzardButton then
                if ns.UI_ApplyClassicNavTabActiveState then
                    ns.UI_ApplyClassicNavTabActiveState(btn, isActive)
                end
                if btn.activeBar and btn.activeBar.Hide then
                    btn.activeBar:Hide()
                end
                btn.active = isActive
                if btn.label then
                    if isActive then
                        if ns.UI_GetSemanticGoldColor then
                            local gr, gg, gb = ns.UI_GetSemanticGoldColor()
                            btn.label:SetTextColor(gr, gg, gb)
                        else
                            ns.UI_SetTextColorRole(btn.label, "Bright")
                        end
                        if ns.UI_SetNavLabelFontStyle then
                            ns.UI_SetNavLabelFontStyle(btn.label, true)
                        end
                    else
                        ns.UI_SetTextColorRole(btn.label, "Muted")
                        if ns.UI_SetNavLabelFontStyle then
                            ns.UI_SetNavLabelFontStyle(btn.label, false)
                        elseif fm then
                            fm:ApplyFont(btn.label, "body")
                        end
                    end
                end
                if btn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                    ns.UI_ApplyNavTabIconStyle(btn.tabIcon, isActive, { packaged = btn.tabIcon._wnNavPackagedIcon, rail = true })
                end
            elseif isActive then
                btn.active = true
                if btn.label then
                    ns.UI_SetTextColorRole(btn.label, "Bright")
                    if ns.UI_SetNavLabelFontStyle then
                        ns.UI_SetNavLabelFontStyle(btn.label, true)
                    end
                end
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if btn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                    ns.UI_ApplyNavTabIconStyle(btn.tabIcon, true, { packaged = btn.tabIcon._wnNavPackagedIcon, rail = true })
                end
                if btn._wnRailTextMode and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    local activeBg = ns.UI_GetNavRailActiveBackdrop and ns.UI_GetNavRailActiveBackdrop()
                    if activeBg then
                        btn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 0.98)
                    else
                        btn:SetBackdropColor(accentColor[1] * railActiveA, accentColor[2] * railActiveA, accentColor[3] * railActiveA, 0.98)
                    end
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, true, accentColor)
                end
            else
                btn.active = false
                if btn.label then
                    ns.UI_SetTextColorRole(btn.label, "Bright")
                    if ns.UI_SetNavLabelFontStyle then
                        ns.UI_SetNavLabelFontStyle(btn.label, false)
                    elseif fm then
                        fm:ApplyFont(btn.label, "body")
                    end
                end
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if btn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                    ns.UI_ApplyNavTabIconStyle(btn.tabIcon, false, { packaged = btn.tabIcon._wnNavPackagedIcon, rail = true })
                end
                if btn._wnRailTextMode and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.4 }
                    btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 0.4)
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, false, accentColor)
                end
            end
        end
    end
end

local function CreateSettingsNavButton(parent, panelId, label, btnW, rowH)
    local useClassic = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
    local btn
    if useClassic then
        btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        local tabH = (ns.UI_GetNavRailTabHeight and ns.UI_GetNavRailTabHeight()) or rowH
        btn:SetSize(btnW, tabH)
        btn:SetHeight(tabH)
        btn:SetText("")
        btn._wnBlizzardButton = true
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(btn)
        end
    else
        btn = CreateFrame("Button", nil, parent)
        btn:SetSize(btnW, rowH)
    end
    btn._wnRailTextMode = true
    btn._wnSettingsPanelId = panelId

    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local iconSz = shell.RAIL_TAB_ICON_SIZE or 22
    local iconInsetL = shell.NAV_RAIL_ICON_INSET or 8
    local iconGap = shell.TAB_ICON_GAP or 6
    local ac = COLORS.accent or { 0.6, 0.4, 1 }

    if not useClassic then
        if ns.UI_ApplyBorderlessSurface then
            local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.45 }
            ns.UI_ApplyBorderlessSurface(btn, idle)
        elseif ApplyVisuals then
            local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.45 }
            ApplyVisuals(btn, idle, { ac[1], ac[2], ac[3], 0.12 })
            if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(btn) end
        end
    end

    if not useClassic then
        if ns.UI_ApplyNavButtonHighlight then
            ns.UI_ApplyNavButtonHighlight(btn)
        elseif ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
    end

    local activeBar = btn:CreateTexture(nil, "OVERLAY")
    activeBar:SetColorTexture(ac[1], ac[2], ac[3], 1)
    activeBar:SetWidth(3)
    activeBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -3)
    activeBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 3)
    activeBar:SetAlpha(0)
    if useClassic then
        activeBar:Hide()
    end
    btn.activeBar = activeBar

    local tabIcon = btn:CreateTexture(nil, "ARTWORK")
    tabIcon:SetSize(iconSz, iconSz)
    tabIcon:SetPoint("LEFT", btn, "LEFT", iconInsetL, 0)
    if tabIcon.SetSnapToPixelGrid then tabIcon:SetSnapToPixelGrid(false) end
    if tabIcon.SetTexelSnappingBias then tabIcon:SetTexelSnappingBias(0) end
    btn.tabIcon = tabIcon
    local iconKey = M.PanelIconKey(panelId)
    local usedWnIcon = false
    if panelId == "about" and ns.UI_SetWnIconTexture then
        usedWnIcon = ns.UI_SetWnIconTexture(tabIcon, "credits", { 0.88, 0.88, 0.92, 1 })
    end
    if not usedWnIcon and ns.UI_ApplyMainNavTabGlyph then
        ns.UI_ApplyMainNavTabGlyph(tabIcon, iconKey)
    elseif not usedWnIcon then
        local atlasNm = ns.UI_GetTabIcon and ns.UI_GetTabIcon(iconKey) or nil
        local atlasOk = atlasNm and type(atlasNm) == "string" and pcall(tabIcon.SetAtlas, tabIcon, atlasNm, false)
        if not atlasOk then
            tabIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            tabIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    tabIcon._wnNavPackagedIcon = usedWnIcon or nil
    tabIcon._wnNavRailIcon = true
    if ns.UI_ApplyNavTabIconStyle then
        ns.UI_ApplyNavTabIconStyle(tabIcon, false, { packaged = usedWnIcon, rail = true })
    end

    local fs = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabLabel"), "OVERLAY")
    fs._wnNavLabel = true
    fs:SetPoint("LEFT", tabIcon, "RIGHT", iconGap, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(label)
    ns.UI_SetTextColorRole(fs, "Bright")
    btn.label = fs

    return btn
end

---Vertical category list (rail parity: icons, separators, active strip).
---@param parent Frame
---@param width number
---@param activeId string
---@param onSelect function|nil `(panelId)`
---@return number totalHeight
function M.BuildCategoryNav(parent, width, activeId, onSelect)
    if not parent then return 0 end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local rowH = (ns.UI_GetNavRailTabHeight and ns.UI_GetNavRailTabHeight()) or shell.NAV_RAIL_TAB_HEIGHT or 38
    local vGap = shell.NAV_RAIL_TAB_V_GAP or 4
    local pad = shell.SETTINGS_NAV_PAD or shell.NAV_RAIL_PAD or 6
    local sepH = shell.NAV_RAIL_TAB_SEP_HEIGHT or 1
    local sepA = shell.NAV_RAIL_TAB_SEP_ALPHA or 0.4
    local ac = COLORS.accent or { 0.6, 0.4, 1 }
    local btnW = math.max(80, width - (pad * 2))

    parent._wnSettingsNavButtons = parent._wnSettingsNavButtons or {}
    wipe(parent._wnSettingsNavButtons)

    local prevBtn = nil
    local topInset = pad

    for i = 1, #M.PANEL_ORDER do
        local panelId = M.PANEL_ORDER[i]
        local label = M.PanelLabel(panelId)
        local btn = CreateSettingsNavButton(parent, panelId, label, btnW, rowH)

        if prevBtn then
            local sep = btn._wnRailSepAbove
            if not sep and ns.UI.Factory and ns.UI.Factory.CreateRailTabSeparator then
                sep = ns.UI.Factory:CreateRailTabSeparator(parent, { height = sepH })
                btn._wnRailSepAbove = sep
            end
            local gapAbove = math.floor(vGap * 0.5)
            local gapBelow = vGap - gapAbove
            if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
                if sep and sep.Hide then sep:Hide() end
                btn:ClearAllPoints()
                btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -(gapAbove + sepH + gapBelow))
                btn:SetPoint("LEFT", parent, "LEFT", pad, 0)
                btn:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
            elseif sep then
                sep:ClearAllPoints()
                sep:SetPoint("LEFT", parent, "LEFT", pad, 0)
                sep:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
                sep:SetPoint("TOP", prevBtn, "BOTTOM", 0, -gapAbove)
                sep:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOP", sep, "BOTTOM", 0, -gapBelow)
                btn:SetPoint("LEFT", parent, "LEFT", pad, 0)
                btn:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
            else
                btn:ClearAllPoints()
                btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -vGap)
                btn:SetPoint("LEFT", parent, "LEFT", pad, 0)
                btn:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
            end
        else
            btn:ClearAllPoints()
            btn:SetPoint("TOP", parent, "TOP", 0, -topInset)
            btn:SetPoint("LEFT", parent, "LEFT", pad, 0)
            btn:SetPoint("RIGHT", parent, "RIGHT", -pad, 0)
        end

        btn:SetScript("OnClick", function()
            if panelId == activeId then return end
            M.SetActivePanel(panelId)
            M.ApplyCategoryNavStates(parent, panelId)
            if onSelect then onSelect(panelId) end
        end)
        local tipDesc = M.PanelDescription(panelId)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if tipDesc and tipDesc ~= "" then
                GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tipDesc, 0.82, 0.82, 0.86, true)
            else
                GameTooltip:SetText(label, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        parent._wnSettingsNavButtons[i] = btn
        prevBtn = btn
    end

    M.ApplyCategoryNavStates(parent, activeId)

    local totalH = topInset
    if prevBtn then
        local bot = prevBtn:GetBottom()
        local top = parent:GetTop()
        if bot and top then
            totalH = top - bot + pad
        else
            totalH = topInset + (#M.PANEL_ORDER * (rowH + vGap)) + pad
        end
    end
    parent:SetHeight(math.max(totalH, rowH + pad * 2))
    return parent:GetHeight() or totalH
end

--- Re-apply settings nav chrome after theme/accent refresh (no full settings rebuild).
function M.RefreshThemeChrome()
    local mf = _G.WarbandNexusFrame
    local navCol = mf and mf._wnSettingsNavCol
    if not navCol then return end
    local useClassic = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    local navBg = (ns.UI_GetNavRailSurfaceBackdrop and ns.UI_GetNavRailSurfaceBackdrop())
        or (ns.UI_COLORS and (ns.UI_COLORS.surfaceViewport or ns.UI_COLORS.bg))
    if useClassic then
        if ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(navCol)
        end
    elseif navBg and ns.UI_ApplyBorderlessSurface then
        local railOpts = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and { surfaceTier = "surfaceViewport" } or { bgType = "bg" }
        ns.UI_ApplyBorderlessSurface(navCol, { navBg[1], navBg[2], navBg[3], 0.92 }, railOpts)
    end
    local navDivider = navCol._wnSettingsNavDivider
    if navDivider then
        if ns.UI.Factory and ns.UI.Factory.RefreshThemeDivider then
            ns.UI.Factory:RefreshThemeDivider(navDivider)
        end
        if navDivider.Show then
            navDivider:Show()
        end
    end
    local bodyRow = mf and mf._wnSettingsBodyRow
    if bodyRow and bodyRow._wnClassicTopBorder then
        bodyRow._wnClassicTopBorder:Hide()
    end
    if useClassic and ns.UI_ApplyClassicTransparentInterior then
        if bodyRow then ns.UI_ApplyClassicTransparentInterior(bodyRow) end
        local host = mf and mf._wnSettingsHost
        if host then ns.UI_ApplyClassicTransparentInterior(host) end
        local navCol = mf and mf._wnSettingsNavCol
        if navCol then ns.UI_ApplyClassicTransparentInterior(navCol) end
    end
    M.ApplyCategoryNavStates(navCol, M.GetActivePanel())
end
