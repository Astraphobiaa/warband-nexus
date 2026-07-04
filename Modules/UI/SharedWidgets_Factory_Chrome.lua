--[[
    Warband Nexus - SharedWidgets Factory Chrome primitives
    Theme-routed dividers, borders, search/radio/progress/list facades.
    Loaded after SharedWidgets_ClassicTheme.lua + SharedWidgets.lua, before SharedWidgets_Factory.lua.
]]

local _, ns = ...

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local Factory = ns.UI.Factory
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals

ns.DIVIDER_REGISTRY = ns.DIVIDER_REGISTRY or {}

local DIVIDER_THICKNESS = {
    railVertical = 10,
    railHorizontal = 8,
    sectionHorizontal = 2,
    classicHairline = 1,
}

local function ClassicHairlineColor()
    return (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
        or (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border)
        or { 0.55, 0.48, 0.35, 0.40 }
end

--- 1px stroke only — dialog-box backdrop on thin frames draws corner caps (boxed footer/rail).
local function ApplyClassicHairlineDivider(frame)
    if not frame then return end
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
    local tex = frame._wnClassicHairlineTex
    if not tex then
        tex = frame:CreateTexture(nil, "ARTWORK")
        frame._wnClassicHairlineTex = tex
    end
    tex:ClearAllPoints()
    tex:SetAllPoints()
    local div = ClassicHairlineColor()
    tex:SetColorTexture(div[1], div[2], div[3], div[4] or 0.40)
    frame._wnClassicHairlineDivider = true
    frame._wnClassicRailDivider = nil
end

local function ApplyClassicDividerBackdrop(frame, variant)
    if not frame then return end
    -- section + rail: thin hairline only (never pane/dialog box on 1–10px frames).
    ApplyClassicHairlineDivider(frame)
end

local function ModernDividerColors(variant)
    local C = COLORS or {}
    local border = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
        or { C.accent and C.accent[1] or 0.5, C.accent and C.accent[2] or 0.4, C.accent and C.accent[3] or 0.7, 0.35 }
    local bg = { (C.border and C.border[1]) or 0.12, (C.border and C.border[2]) or 0.12, (C.border and C.border[3]) or 0.15, 0.10 }
    if variant == "section" then
        bg = { (C.border and C.border[1]) or 0.12, (C.border and C.border[2]) or 0.12, (C.border and C.border[3]) or 0.15, 0.08 }
        border = { (C.border and C.border[1]) or 0.12, (C.border and C.border[2]) or 0.12, (C.border and C.border[3]) or 0.15, 0.22 }
    end
    return bg, border
end

local function PaintModernDividerFrame(divider, variant)
    if not divider or not ApplyVisuals then return end
    local bg, border = ModernDividerColors(variant)
    ApplyVisuals(divider, bg, border)
    divider._borderType = (variant == "section") and "border" or "accent"
    divider._bgType = "divider"
    divider._borderAlpha = border[4]
end

local function IsClassicChrome()
    return ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
end

local function RegisterThemeDivider(divider)
    if divider and not divider._wnDividerRegistered then
        divider._wnDividerRegistered = true
        table.insert(ns.DIVIDER_REGISTRY, divider)
    end
end

function Factory:RefreshThemeDivider(divider)
    if not divider or not divider._wnThemeDivider then return end
    if IsClassicChrome() then
        ApplyClassicHairlineDivider(divider)
        return
    end
    local opts = divider._wnThemeDividerOpts or {}
    local variant = opts.variant or "rail"
    PaintModernDividerFrame(divider, variant)
end

function ns.UI_RefreshThemeDividers()
    local reg = ns.DIVIDER_REGISTRY
    if not reg or not Factory.RefreshThemeDivider then return end
    for i = #reg, 1, -1 do
        local d = reg[i]
        if not d or not d._wnThemeDivider then
            table.remove(reg, i)
        else
            Factory:RefreshThemeDivider(d)
        end
    end
end

--- Theme-routed separator (classic 1px hairline or modern ApplyVisuals quartet).
--- opts.orientation = "vertical"|"horizontal", variant = "rail"|"section", thickness (optional)
--- opts.classicGapOnly = true -> nil in classic (stack buttons with gap only).
function Factory:CreateThemeDivider(parent, opts)
    if not parent then return nil end
    opts = type(opts) == "table" and opts or {}
    if IsClassicChrome() and opts.classicGapOnly then
        return nil
    end
    local orientation = opts.orientation or "horizontal"
    local variant = opts.variant or "rail"
    local thickness = tonumber(opts.thickness)
    local classicMode = IsClassicChrome()
    if not thickness then
        if classicMode then
            thickness = DIVIDER_THICKNESS.classicHairline
        elseif orientation == "vertical" then
            thickness = DIVIDER_THICKNESS.railVertical
        elseif variant == "section" then
            thickness = DIVIDER_THICKNESS.sectionHorizontal
        else
            thickness = DIVIDER_THICKNESS.railHorizontal
        end
    elseif classicMode then
        thickness = DIVIDER_THICKNESS.classicHairline
    end

    local divider
    if classicMode then
        divider = CreateFrame("Frame", nil, parent)
        if orientation == "vertical" then
            divider:SetWidth(thickness)
        else
            divider:SetHeight(thickness)
        end
        ApplyClassicHairlineDivider(divider)
    else
        divider = Factory:CreateContainer(parent, orientation == "vertical" and thickness or 4, orientation == "horizontal" and thickness or 4, false)
        if not divider then
            divider = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            if orientation == "vertical" then
                divider:SetWidth(thickness)
            else
                divider:SetHeight(thickness)
            end
        end
        PaintModernDividerFrame(divider, variant)
    end

    divider._wnThemeDivider = true
    divider._wnThemeDividerOpts = {
        orientation = orientation,
        variant = variant,
        thickness = thickness,
    }
    RegisterThemeDivider(divider)
    return divider
end

ns.UI_CreateThemeDivider = function(parent, opts)
    return Factory:CreateThemeDivider(parent, opts)
end

ns.UI_CreateProgressBar = function(parent, width, height, bgColor, borderColor, noBorder)
    return Factory:CreateProgressBar(parent, width, height, bgColor, borderColor, noBorder)
end

--- Single entry for painting borders on arbitrary frames (classic vs modern).
--- opts.tier = shell|card|panel|thin|iconWell|none; optional bgColor table
function Factory:ApplyBorder(frame, opts)
    if not frame then return end
    opts = type(opts) == "table" and opts or {}
    local tier = opts.tier or "thin"
    local bg = opts.bgColor

    if tier == "none" then
        if IsClassicChrome() and ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(frame)
        elseif ns.UI_ApplyBorderlessSurface then
            ns.UI_ApplyBorderlessSurface(frame, bg or { 0, 0, 0, 0 })
        end
        return
    end

    if IsClassicChrome() then
        if tier == "shell" and ns.UI_ApplyBlizzardDialogBackdrop then
            ns.UI_ApplyBlizzardDialogBackdrop(frame)
        elseif tier == "card" and ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        elseif tier == "panel" and ns.UI_ApplyClassicPaneBackdrop then
            local panelBg = bg or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
                or (COLORS and COLORS.bgCard)
            ns.UI_ApplyClassicPaneBackdrop(frame, panelBg)
        elseif tier == "iconWell" and ns.UI_ApplyClassicIconWellChrome then
            ns.UI_ApplyClassicIconWellChrome(frame, bg)
        elseif ns.UI_ApplyClassicThinBorderChrome then
            ns.UI_ApplyClassicThinBorderChrome(frame, bg or (COLORS and COLORS.bgCard))
        end
        return
    end

    local C = COLORS or {}
    local shellBg = bg or C.bgCard or C.bgLight or C.bg
    local border = { C.accent[1], C.accent[2], C.accent[3], 0.55 }
    if tier == "shell" and ns.UI_ApplyMainWindowShellFill then
        ns.UI_ApplyMainWindowShellFill(frame, shellBg)
        return
    end
    if tier == "card" and ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
        return
    end
    if tier == "iconWell" and ns.UI_ApplyIconWellChrome then
        ns.UI_ApplyIconWellChrome(frame)
        return
    end
    if ApplyVisuals then
        local bdr = (tier == "panel") and { C.border[1], C.border[2], C.border[3], 0.35 } or border
        ApplyVisuals(frame, shellBg, bdr)
    end
end

ns.UI_FactoryApplyBorder = function(frame, opts)
    return Factory:ApplyBorder(frame, opts)
end

--- Toolbar / search strip chrome (classic pane or modern accent border).
function Factory:ApplyToolbarChrome(frame, opts)
    if not frame then return end
    opts = type(opts) == "table" and opts or {}
    if IsClassicChrome() then
        if opts.editBoxHost and ns.UI_ApplyClassicTransparentInterior then
            frame._wnSearchEditBoxHost = true
            ns.UI_ApplyClassicTransparentInterior(frame)
        elseif ns.UI_ApplySearchBoxChrome then
            ns.UI_ApplySearchBoxChrome(frame, opts)
        elseif ns.UI_ApplyClassicPaneBackdrop then
            local bg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
                or (COLORS and COLORS.surfaceHeaderChrome)
            ns.UI_ApplyClassicPaneBackdrop(frame, bg)
        end
        return
    end
    if ns.UI_ApplySearchBoxChrome then
        ns.UI_ApplySearchBoxChrome(frame, opts)
    elseif Factory.ApplyBorder then
        Factory:ApplyBorder(frame, { tier = "panel", bgColor = { 0, 0, 0, 0 } })
    end
end

--- Search box shell + Factory edit field (wraps SearchBoxComponent).
function Factory:CreateSearchBox(parent, width, placeholder, onChange, initialText, registryKey)
    if ns.UI_CreateSearchBox then
        return ns.UI_CreateSearchBox(parent, width, placeholder, onChange, initialText, registryKey)
    end
    return nil
end

--- Radio indicator (classic UIRadioButtonTemplate or modern toggle dot).
function Factory:CreateRadioButton(parent, isSelected)
    if ns.UI_CreateThemedRadioButton then
        return ns.UI_CreateThemedRadioButton(parent, isSelected)
    end
    return nil
end

--- Status / progress bar (classic StatusBar template routing in UI_CreateStatusBar).
function Factory:CreateProgressBar(parent, width, height, bgColor, borderColor, noBorder)
    if ns.UI_CreateStatusBar then
        return ns.UI_CreateStatusBar(parent, width, height, bgColor, borderColor, noBorder)
    end
    return nil
end

--- List row chrome entry (delegates to pooled row factories by kind).
function Factory:CreateListRow(parent, kind, width, height)
    kind = kind or "character"
    local w = width or 200
    local h = height or 26
    if kind == "currency" and ns.UI_AcquireCurrencyRow then
        return ns.UI_AcquireCurrencyRow(parent, w, h)
    end
    if kind == "item" and ns.UI_AcquireItemRow then
        return ns.UI_AcquireItemRow(parent, w, h)
    end
    if kind == "reputation" and ns.UI_AcquireReputationRow then
        return ns.UI_AcquireReputationRow(parent, w, h)
    end
    if kind == "storage" and ns.UI_AcquireStorageRow then
        return ns.UI_AcquireStorageRow(parent, w, h)
    end
    if kind == "profession" and ns.UI_AcquireProfessionRow then
        return ns.UI_AcquireProfessionRow(parent, w, h)
    end
    if ns.UI_AcquireCharacterRow then
        return ns.UI_AcquireCharacterRow(parent, w, h)
    end
    return nil
end

--- Nav tab button hook — UI.lua registers builder at load; Factory exposes stable API.
ns.UI.NavTabBuilder = ns.UI.NavTabBuilder or {}

function ns.UI.NavTabBuilder.Register(createFn)
    ns.UI.NavTabBuilder._create = createFn
end

function Factory:CreateNavTabButton(parent, text, key)
    local createFn = ns.UI.NavTabBuilder and ns.UI.NavTabBuilder._create
    if createFn then
        return createFn(parent, text, key)
    end
    return Factory:CreateButton(parent, 120, 32, false)
end

--- Rail/tab horizontal separator between stacked nav buttons (modern section; classic uses gap only).
function Factory:CreateRailTabSeparator(parent, opts)
    opts = type(opts) == "table" and opts or {}
    if IsClassicChrome() and opts.classicGapOnly ~= false then
        return nil
    end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local sepH = opts.height or shell.NAV_RAIL_TAB_SEP_HEIGHT or 2
    local divider = Factory:CreateThemeDivider(parent, {
        orientation = "horizontal",
        variant = opts.variant or "section",
        thickness = math.max(2, sepH),
    })
    return divider
end
