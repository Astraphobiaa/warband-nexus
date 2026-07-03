--[[
    Warband Nexus - Classic theme: literal Blizzard FrameXML chrome (Settings > Theme > Classic)
    Loaded before SharedWidgets.lua. Factory/SharedWidgets route here when themeMode == "classic".
    Reference: Interface/DialogFrame/UI-DialogBox-*, UIPanelButtonTemplate, OptionsSliderTemplate.

    Chrome routing (classic only):
    - Collapsible section headers (Currency, Storage, etc.) -> UIPanelButtonTemplate + UI_NormalizeBlizzardButtonChrome
    - Non-template list/section bars -> UI_ApplyClassicListHeaderChrome (AceGUI PaneBackdrop: tooltip border edge 16)
    - Cards / elevated panels / bordered containers -> UI_ApplyClassicCardPanelChrome (dialog-box border)
    - Main / external shells -> UI_ApplyBlizzardDialogBackdrop (full dialog insets)
    - Search with InputBoxTemplate child -> transparent host (_wnSearchEditBoxHost); no stacked border+input
    - Stats / filter strips (no edit box) -> UI_ApplyClassicPaneBackdrop via UI_ApplySearchBoxChrome
    - List rows -> transparent/minimal fill (Factory:ApplyRowBackground); no ApplyVisuals accent borders
]]

local ADDON_NAME, ns = ...

--- Surface/text keys match SURFACE_VARIANTS.classic in SharedWidgets.lua (fallback palette).
ns.UI_CLASSIC_SURFACE_VARIANT = {
    bg = { 0.065, 0.065, 0.075, 1 },
    surfaceViewport = { 0.075, 0.075, 0.085, 1 },
    bgLight = { 0.085, 0.085, 0.095, 1 },
    bgCard = { 0.095, 0.095, 0.105, 1 },
    surfaceHeaderChrome = { 0.080, 0.080, 0.090, 1 },
    surfaceRowEven = { 0.088, 0.088, 0.098, 0.96 },
    surfaceRowOdd = { 0.072, 0.072, 0.082, 0.96 },
    borderLight = { 0.55, 0.48, 0.35, 1 },
    tabInactive = { 0.055, 0.055, 0.065, 1 },
    tabActive = { 0.095, 0.095, 0.110, 0.98 },
    tabHover = { 0.105, 0.105, 0.120, 0.98 },
    gold = { 1.00, 0.82, 0.00, 1 },
    green = { 0.35, 0.85, 0.35, 1 },
    textBright = { 1.00, 0.97, 0.85, 1 },
    textNormal = { 0.92, 0.88, 0.78, 1 },
    textMuted = { 0.78, 0.72, 0.62, 1 },
    textDim = { 0.62, 0.58, 0.50, 1 },
}

--- Fixed accent/border/tab chrome for classic (no user accent / class-color override).
ns.UI_CLASSIC_ACCENT_THEME = {
    accent = { 0.85, 0.68, 0.20 },
    accentDark = { 0.60, 0.48, 0.14 },
    border = { 0.55, 0.48, 0.35 },
    tabActive = { 0.55, 0.45, 0.15 },
    tabHover = { 0.65, 0.52, 0.18 },
}

--- Blizzard dialog box backdrop (main windows / external dialogs).
ns.UI_CLASSIC_DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

--- Nested card/container border — same dialog-box art as main shell, tighter insets for panels inside the window.
ns.UI_CLASSIC_CARD_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

--- Legacy alias (classic card chrome no longer uses tooltip panel border).
ns.UI_CLASSIC_PANEL_BACKDROP = ns.UI_CLASSIC_CARD_BACKDROP

--- AceGUI PaneBackdrop (status areas, inline groups, tree panes): ChatFrameBackground + UI-Tooltip-Border.
ns.UI_CLASSIC_PANE_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 },
}

--- Small icon / action wells (plan cards, browse tiles): 1px stroke — not full dialog-box edge (32px).
ns.UI_CLASSIC_ICON_WELL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 16,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function ResolveWarbandProfile()
    local WN = _G.WarbandNexus or ns.WarbandNexus
    return WN and WN.db and WN.db.profile
end

--- True when Factory/SharedWidgets must use Blizzard templates instead of custom chrome.
local function ShouldUseBlizzardChrome()
    if ns.UI_IsClassicMode then
        return ns.UI_IsClassicMode()
    end
    local db = ResolveWarbandProfile()
    if db and db.uiTheme == "classic" then
        return true
    end
    return db and db.themeMode == "classic"
end
ns.UI_ShouldUseBlizzardChrome = ShouldUseBlizzardChrome

local BORDER_QUARTET_KEYS = { "BorderTop", "BorderBottom", "BorderLeft", "BorderRight" }

local function HideCustomBorderQuartet(frame)
    if not frame then return end
    for i = 1, #BORDER_QUARTET_KEYS do
        local tex = frame[BORDER_QUARTET_KEYS[i]]
        if tex and tex.Hide then
            tex:Hide()
        end
    end
end

local function EnsureBackdropMixin(frame)
    if not frame then return false end
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
    end
    return frame.SetBackdrop ~= nil
end

--- Apply standard Blizzard dialog box chrome; hides WN custom border textures.
---@param frame Frame
---@param bgColor table|nil optional vertex tint (defaults 1,1,1)
function ns.UI_ApplyBlizzardDialogBackdrop(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_DIALOG_BACKDROP)
    local c = bgColor or { 1, 1, 1, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    if frame._wnShellBorderOverlay and frame._wnShellBorderOverlay.Hide then
        frame._wnShellBorderOverlay:Hide()
    end
    frame._wnBlizzardChrome = true
    frame._wnMainShellBackdrop = true
    frame._wnBorderlessSurface = false
end

--- Dialog-box bordered nested surface (cards, sections, ApplyVisuals classic parity with modern accent borders).
---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyBlizzardCardBackdrop(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_CARD_BACKDROP)
    local c = bgColor or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
        or { 1, 1, 1, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnBlizzardChrome = true
    frame._wnBorderlessSurface = false
    frame._wnClassicCard = true
end

--- 1px gold-tinted stroke for list rows, collapsible headers, ApplyVisuals parity (not dialog-box corners).
ns.UI_CLASSIC_THIN_BORDER_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 16,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyClassicThinBorderChrome(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_THIN_BORDER_BACKDROP)
    local c = bgColor
        or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
        or (ns.UI_COLORS and (ns.UI_COLORS.bgCard or ns.UI_COLORS.bgLight))
        or { 0.08, 0.08, 0.09, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    local bc = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border)
        or { 0.55, 0.48, 0.35, 1 }
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnClassicThinBorder = true
    frame._wnClassicCard = nil
    frame._wnClassicIconWell = nil
    frame._wnThinBorderBg = { c[1], c[2], c[3], c[4] or 1 }
    frame._wnBlizzardChrome = true
    frame._wnBorderlessSurface = false
end

--- Compact dialog-box border for collapsible section headers (Currency, Storage, etc.).
ns.UI_CLASSIC_SECTION_HEADER_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyClassicSectionHeaderPanelChrome(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_SECTION_HEADER_BACKDROP)
    local c = bgColor
        or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
        or (ns.UI_COLORS and (ns.UI_COLORS.surfaceHeaderChrome or ns.UI_COLORS.bgCard))
        or { 0.08, 0.08, 0.09, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnClassicThinBorder = nil
    frame._wnClassicCard = true
    frame._wnSectionHeaderPanelBg = { c[1], c[2], c[3], c[4] or 1 }
    frame._wnBlizzardChrome = true
    frame._wnBorderlessSurface = false
end

--- AceGUI PaneBackdrop for non-template section/list header bars (tooltip border — not thin 1px stroke).
---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyClassicPaneBackdrop(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_PANE_BACKDROP)
    local c = bgColor
        or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
        or (ns.UI_COLORS and (ns.UI_COLORS.surfaceHeaderChrome or ns.UI_COLORS.bgCard))
        or { 0.08, 0.08, 0.09, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnClassicPaneBackdrop = true
    frame._wnClassicThinBorder = nil
    frame._wnClassicCard = nil
    frame._wnPaneBackdropBg = { c[1], c[2], c[3], c[4] or 1 }
    frame._wnBlizzardChrome = true
    frame._wnBorderlessSurface = false
end

--- Non-template collapsible / virtual-list section headers — PaneBackdrop (prefer UIPanelButtonTemplate for primary headers).
---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyClassicListHeaderChrome(frame, bgColor)
    if not frame then return end
    if frame._wnBlizzardButton then return end
    local hdrBg = bgColor
        or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
        or (ns.UI_COLORS and (ns.UI_COLORS.surfaceHeaderChrome or ns.UI_COLORS.bgCard))
        or { 0.08, 0.08, 0.09, 1 }
    if ns.UI_ApplyClassicPaneBackdrop then
        ns.UI_ApplyClassicPaneBackdrop(frame, hdrBg)
    else
        ns.UI_ApplyClassicThinBorderChrome(frame, hdrBg)
    end
    frame._wnSectionHeaderPanelBg = nil
end

--- Thin bordered square for item/plan icons (avoids stacked dialog-box + custom quartet borders).
---@param frame Frame|nil
---@param bgColor table|nil
function ns.UI_ApplyClassicIconWellChrome(frame, bgColor)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_ICON_WELL_BACKDROP)
    local c = bgColor
        or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
        or (ns.UI_COLORS and (ns.UI_COLORS.bgCard or ns.UI_COLORS.bgLight))
        or { 0.08, 0.08, 0.09, 1 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    local bc = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border)
        or { 0.55, 0.48, 0.35, 1 }
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnClassicIconWell = true
    frame._wnBlizzardChrome = true
    frame._wnBorderlessSurface = false
end

--- Standard bordered card/section panel (Statistics cards, Settings sections, elevated surfaces).
---@param frame Frame|nil
function ns.UI_ApplyClassicCardPanelChrome(frame)
    if not frame or not ns.UI_ApplyBlizzardCardBackdrop then return end
    local cardBg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
        or (ns.UI_COLORS and (ns.UI_COLORS.bgCard or ns.UI_COLORS.bgLight or ns.UI_COLORS.bg))
        or { 1, 1, 1, 1 }
    ns.UI_ApplyBlizzardCardBackdrop(frame, cardBg)
end

--- Apply nested dialog-box bordered panel (classic parity for modern ApplyVisuals / CreateCard borders).
---@param frame Frame
---@param bgColor table|nil
function ns.UI_ApplyBlizzardPanelBackdrop(frame, bgColor)
    if not frame or not ns.UI_ApplyBlizzardCardBackdrop then return end
    ns.UI_ApplyBlizzardCardBackdrop(frame, bgColor)
end

--- Flat interior fill inside a Blizzard dialog shell (no nested panel border).
---@param frame Frame
---@param bgColor table|nil rgba; alpha 0 = transparent (dialog bg shows through)
function ns.UI_ApplyClassicInteriorFlatFill(frame, bgColor)
    if not frame then return end
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
    end
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    local c = bgColor or { 0, 0, 0, 0 }
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 0)
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnBlizzardChrome = nil
    frame._wnClassicInteriorFlat = true
    frame._wnBorderlessSurface = true
    frame._wnMainShellBackdrop = true
end

--- Clear interior host fills so Blizzard dialog/panel chrome shows through (classic main shell).
---@param frame Frame
function ns.UI_ApplyClassicTransparentInterior(frame)
    if not frame then return end
    ns.UI_ApplyClassicInteriorFlatFill(frame, { 0, 0, 0, 0 })
    if frame._wnViewportAtlasUnderlay and frame._wnViewportAtlasUnderlay.Hide then
        frame._wnViewportAtlasUnderlay:Hide()
    end
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    frame._wnClassicTransparentInterior = true
end

--- Main window interior rect insets for `UI_ApplyMainShellLayout`.
--- Classic: dialog backdrop tile insets (`UI_CLASSIC_DIALOG_BACKDROP.insets`) so header/nav/content/footer
--- anchor inside the decorative border. Dark/light: `MAIN_SHELL.INTERIOR_INSET_*` (0 full-bleed).
---@return number insetLeft, number insetRight, number insetTop, number insetBottom
function ns.UI_GetMainShellFrameInsets()
    if ShouldUseBlizzardChrome() then
        local bd = ns.UI_CLASSIC_DIALOG_BACKDROP and ns.UI_CLASSIC_DIALOG_BACKDROP.insets
        if bd then
            return bd.left or 11, bd.right or 12, bd.top or 12, bd.bottom or 11
        end
    end
    local shell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    local left = shell.INTERIOR_INSET_LEFT
    if left == nil then
        left = shell.FRAME_CONTENT_INSET or 0
    end
    local right = shell.INTERIOR_INSET_RIGHT
    if right == nil then
        right = left
    end
    local top = shell.INTERIOR_INSET_TOP
    if top == nil then
        top = left
    end
    local bottom = shell.INTERIOR_INSET_BOTTOM
    if bottom == nil then
        bottom = shell.FRAME_CONTENT_INSET_BOTTOM
        if bottom == nil then
            bottom = left
        end
    end
    return left, right, top, bottom
end

--- Classic sub-tab / nav UIPanelButtonTemplate: no LockHighlight tint — active state is label color only.
---@param btn Button|nil
---@param isActive boolean
function ns.UI_NormalizeBlizzardButtonChrome(btn)
    if not btn or not btn._wnBlizzardButton then return end
    if btn.UnlockHighlight then
        btn:UnlockHighlight()
    end
    local function neutral(tex)
        if tex and tex.SetVertexColor then
            tex:SetVertexColor(1, 1, 1, 1)
        end
    end
    if btn.GetNormalTexture then neutral(btn:GetNormalTexture()) end
    if btn.GetHighlightTexture then neutral(btn:GetHighlightTexture()) end
    if btn.GetPushedTexture then neutral(btn:GetPushedTexture()) end
    if btn.GetDisabledTexture then neutral(btn:GetDisabledTexture()) end
end

function ns.UI_ApplyClassicNavTabActiveState(btn, isActive)
    ns.UI_NormalizeBlizzardButtonChrome(btn)
end

--- Blizzard template widgets and explicit opt-outs keep literal template art.
---@param frame Frame|nil
---@return boolean
function ns.UI_CanApplyCustomChrome(frame)
    if not frame then return false end
    if frame._wnBlizzardButton or frame._wnBlizzardChrome or frame._wnBlizzardScroll
        or frame._wnBlizzardEditBox or frame._wnBlizzardSlider or frame._wnClassicIconWell then
        return false
    end
    if frame._wnSkipCustomChrome then
        return false
    end
    return true
end

--- Header Patreon/Discord URL copy shell (classic = nested dialog card; modern = flat control chrome).
---@param frame Frame
function ns.UI_ApplyHeaderCopyUrlShell(frame)
    if not frame then return end
    if ShouldUseBlizzardChrome() then
        ns.UI_ApplyClassicCardPanelChrome(frame)
        return
    end
    if not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local shellBg = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or { 0.08, 0.08, 0.10, 0.95 }
    frame:SetBackdropColor(shellBg[1], shellBg[2], shellBg[3], shellBg[4] or 0.95)
    local C = ns.UI_COLORS or {}
    local accent = C.accent or { 0.4, 0.2, 0.58, 1 }
    frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.8)
end

--- Main shell tracking status chip (classic = flat header band + thin stroke; modern = control chrome).
---@param chip Frame
---@param iconBack Frame|nil nested icon plate; classic uses transparent fill
function ns.UI_ApplyTrackingChipChrome(chip, iconBack)
    if not chip then return end
    if ShouldUseBlizzardChrome() then
        if ns.UI_ApplyClassicInteriorFlatFill then
            ns.UI_ApplyClassicInteriorFlatFill(chip, { 0, 0, 0, 0 })
        end
        if ns.UI_ApplyClassicThinBorderChrome then
            local hdrBg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
                or (ns.UI_COLORS and (ns.UI_COLORS.surfaceHeaderChrome or ns.UI_COLORS.bgLight))
                or { 0.08, 0.08, 0.09, 0.35 }
            ns.UI_ApplyClassicThinBorderChrome(chip, { hdrBg[1], hdrBg[2], hdrBg[3], 0.35 })
        end
        if iconBack then
            if iconBack.SetBackdrop then
                iconBack:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            end
            if iconBack.SetBackdropColor then
                iconBack:SetBackdropColor(0, 0, 0, 0)
            end
        end
        return
    end
    if not ns.UI_ApplyVisuals then return end
    local chipBg, chipBorder
    if ns.UI_GetTrackingChipBackdrop then
        chipBg, chipBorder = ns.UI_GetTrackingChipBackdrop()
    else
        chipBg = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or { 0.12, 0.12, 0.15, 0.92 }
        local C = ns.UI_COLORS or {}
        local accent = C.accent or { 0.4, 0.2, 0.58, 1 }
        chipBorder = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor()) or { accent[1], accent[2], accent[3], 0.24 }
    end
    ns.UI_ApplyVisuals(chip, chipBg, chipBorder)
    if iconBack and iconBack.SetBackdropColor then
        local iconBackBg = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop())
            or { 0.12, 0.12, 0.15, 0.5 }
        iconBack:SetBackdropColor(iconBackBg[1], iconBackBg[2], iconBackBg[3], (iconBackBg[4] or 1) * 0.55)
    end
end

--- Floating tracker / companion outer shell (classic = dialog box; modern = elevated card).
---@param frame Frame|nil
function ns.UI_ApplyFloatingWindowShellChrome(frame)
    if not frame then return end
    if ShouldUseBlizzardChrome() and ns.UI_ApplyBlizzardDialogBackdrop then
        local bg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bg)
            or { 1, 1, 1, 1 }
        ns.UI_ApplyBlizzardDialogBackdrop(frame, bg)
        return
    end
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    elseif ns.UI_ApplyVisuals and ns.UI_COLORS then
        local C = ns.UI_COLORS
        local shell = C.bgCard or C.bgLight or C.bg
        ns.UI_ApplyVisuals(frame, shell, { C.accent[1], C.accent[2], C.accent[3], 0.55 })
    end
end

--- Thin dialog-border strip (transparent interior) for classic rail separators.
---@param frame Frame
local function ApplyClassicRailDividerBackdrop(frame)
    if not frame or not EnsureBackdropMixin(frame) then return end
    frame:SetBackdrop(ns.UI_CLASSIC_CARD_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    frame._wnClassicRailDivider = true
end

--- Vertical separator between main nav rail and viewport, or settings nav and content.
---@param parent Frame
---@return Frame|nil
function ns.UI_CreateClassicVerticalRailDivider(parent)
    if not parent then return nil end
    local divider = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    divider:SetWidth(8)
    ApplyClassicRailDividerBackdrop(divider)
    return divider
end

--- Horizontal separator above settings dual-rail body (below title card).
---@param parent Frame
---@return Frame|nil
function ns.UI_CreateClassicHorizontalRailDivider(parent)
    if not parent then return nil end
    local divider = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    divider:SetHeight(8)
    ApplyClassicRailDividerBackdrop(divider)
    return divider
end
---@param frame Frame
function ns.UI_StripCustomChromeForBlizzard(frame)
    if not frame then return end
    HideCustomBorderQuartet(frame)
    if frame._wnShellFill and frame._wnShellFill.Hide then
        frame._wnShellFill:Hide()
    end
    if frame._wnShellBorderOverlay and frame._wnShellBorderOverlay.Hide then
        frame._wnShellBorderOverlay:Hide()
    end
    if frame._wnExternalContentFill and frame._wnExternalContentFill.Hide then
        frame._wnExternalContentFill:Hide()
    end
end
