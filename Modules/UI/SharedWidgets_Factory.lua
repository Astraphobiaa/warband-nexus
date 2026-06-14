--[[
    Warband Nexus - SharedWidgets SharedWidgets_Factory (ops-027 slice)
    Loaded after Modules/UI/SharedWidgets.lua core exports.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local issecretvalue = issecretvalue

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local COLORS = ns.UI_COLORS
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateButton = ns.UI_CreateButton
local CreateIcon = ns.UI_CreateIcon
local GetColors = function() return ns.UI_COLORS end
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

ns.SCROLL_CHROME_REGISTRY = ns.SCROLL_CHROME_REGISTRY or {}
local SCROLL_CHROME_REGISTRY = ns.SCROLL_CHROME_REGISTRY

local function ResolveScrollChromeBackdrop()
    if ns.UI_GetControlChromeHoverBackdrop then
        local c = ns.UI_GetControlChromeHoverBackdrop()
        return c[1], c[2], c[3], (c[4] or 1) * 0.92
    end
    return 0.08, 0.08, 0.10, 0.9
end

local function ApplyScrollChromeBackdrop(tex)
    if not tex or not tex.SetColorTexture then return end
    local r, g, b, a = ResolveScrollChromeBackdrop()
    tex:SetColorTexture(r, g, b, a)
end

local function RegisterScrollChrome(host)
    if host and not host._wnScrollChromeRegistered then
        host._wnScrollChromeRegistered = true
        table.insert(SCROLL_CHROME_REGISTRY, host)
    end
end

local function RefreshScrollChromeHost(host)
    if not host then return end
    if host.CustomTrack then
        ApplyScrollChromeBackdrop(host.CustomTrack)
    end
    if host.ScrollUpBtn and host.ScrollUpBtn.bg then
        ApplyScrollChromeBackdrop(host.ScrollUpBtn.bg)
    end
    if host.ScrollDownBtn and host.ScrollDownBtn.bg then
        ApplyScrollChromeBackdrop(host.ScrollDownBtn.bg)
    end
    if host.ScrollLeftBtn and host.ScrollLeftBtn.bg then
        ApplyScrollChromeBackdrop(host.ScrollLeftBtn.bg)
    end
    if host.ScrollRightBtn and host.ScrollRightBtn.bg then
        ApplyScrollChromeBackdrop(host.ScrollRightBtn.bg)
    end
end

function ns.UI_RefreshScrollChrome()
    for i = #SCROLL_CHROME_REGISTRY, 1, -1 do
        local host = SCROLL_CHROME_REGISTRY[i]
        if not host then
            table.remove(SCROLL_CHROME_REGISTRY, i)
        else
            RefreshScrollChromeHost(host)
        end
    end
end

local function ResolveIconShellBackdrop()
    if ns.UI_GetControlChromeBackdrop then
        local c = ns.UI_GetControlChromeBackdrop()
        return { c[1], c[2], c[3], (c[4] or 1) * 0.95 }
    end
    return { 0.12, 0.12, 0.14, 0.95 }
end

local function ResolveSurfaceTierColor(tier)
    if ns.UI_ResolveSurfaceTierColor then
        return ns.UI_ResolveSurfaceTierColor(tier)
    end
    local C = COLORS or {}
    if tier == "rowEven" then
        return C.surfaceRowEven or (UI_SPACING and UI_SPACING.ROW_COLOR_EVEN) or { 0.112, 0.112, 0.138, 0.96 }
    elseif tier == "rowOdd" then
        return C.surfaceRowOdd or (UI_SPACING and UI_SPACING.ROW_COLOR_ODD) or { 0.090, 0.090, 0.112, 0.96 }
    end
    return C.bg or { 0.065, 0.065, 0.082, 0.98 }
end

--[[
    Update border color for an existing frame (Factory Method)
    @param self table - Factory object
    @param frame frame - Frame with borders already created by ApplyVisuals
    @param borderColor table - Border color {r,g,b,a}
]]
function ns.UI.Factory:UpdateBorderColor(frame, borderColor)
    if not frame or not borderColor then return end

    if frame._wnMainShellBackdrop and frame.SetBackdropBorderColor then
        local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
        frame:SetBackdropBorderColor(r, g, b, a)
        return
    end

    if not frame.BorderTop then return end
    
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    frame.BorderTop:SetVertexColor(r, g, b, a)
    frame.BorderBottom:SetVertexColor(r, g, b, a)
    frame.BorderLeft:SetVertexColor(r, g, b, a)
    frame.BorderRight:SetVertexColor(r, g, b, a)
end

--[[
    Apply native highlight effect to a frame (Factory Method)
    Uses WoW's built-in SetHighlightTexture - NO manual texture creation
    
    @param self table - Factory object
    @param frame frame - Frame to apply highlight to
    @param color table - RGB color array (default: soft blue {0.4, 0.6, 0.9})
    @param alpha number - Alpha transparency (default: 0.15)
    
    Technical Details:
    - Uses native SetHighlightTexture (zero texture overhead)
    - NO OnEnter/OnLeave scripts needed (native handles it)
    - ADD blend mode for glow effect
    - Pixel snapping enabled to prevent ghosting
    - Works on all frame types (Button, Frame, etc.)
]]
function ns.UI.Factory:ApplyHighlight(frame, color, alpha)
    if not frame or not frame.SetHighlightTexture then return end

    if not color then
        if ns.UI_GetRowHoverHighlight then
            color, alpha = ns.UI_GetRowHoverHighlight()
        else
            color = { 0.4, 0.6, 0.9 }
            alpha = 0.15
        end
    end
    alpha = alpha or 0.15

    frame:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")

    local hl = frame:GetHighlightTexture()
    if hl then
        local light = ns.UI_IsLightMode and ns.UI_IsLightMode()
        hl:SetBlendMode(light and "BLEND" or "ADD")
        hl:SetVertexColor(color[1], color[2], color[3], alpha)
        hl:SetDrawLayer("HIGHLIGHT")
        hl:SetSnapToPixelGrid(true)
        hl:SetTexelSnappingBias(0)
    end

    ns.HIGHLIGHT_REGISTRY = ns.HIGHLIGHT_REGISTRY or {}
    if not frame._wnHighlightRegistered then
        frame._wnHighlightRegistered = true
        table.insert(ns.HIGHLIGHT_REGISTRY, frame)
    end
    frame._wnHighlightColor = color
    frame._wnHighlightAlpha = alpha
    frame._wnHighlightCustom = color ~= nil
end

local function RefreshRegisteredHighlights()
    local reg = ns.HIGHLIGHT_REGISTRY
    if not reg then return end
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.ApplyHighlight then return end
    for i = #reg, 1, -1 do
        local frame = reg[i]
        if not frame or not frame.SetHighlightTexture then
            table.remove(reg, i)
        else
        if frame._wnHighlightCustom then
            Factory:ApplyHighlight(frame, frame._wnHighlightColor, frame._wnHighlightAlpha)
        else
            Factory:ApplyHighlight(frame)
        end
        end
    end
end
ns.UI_RefreshRegisteredHighlights = RefreshRegisteredHighlights

-- Legacy wrapper for UpdateBorderColor
local function UpdateBorderColor(frame, borderColor)
    return ns.UI.Factory:UpdateBorderColor(frame, borderColor)
end

-- Export to namespace
ns.UI_UpdateBorderColor = UpdateBorderColor
-- TRY COUNT ROW (Factory — same click path as popup everywhere)

---@class WnTryCountClickableOptions
---@field height number|nil default 18
---@field fontCategory string|nil default "small"
---@field justifyH string|nil "LEFT" or "RIGHT" (default RIGHT)
---@field frameLevelOffset number|nil added to parent frame level (default 10)
---@field showTooltip boolean|nil default true
---@field popupOnLeftClick boolean|nil default true
---@field popupOnRightClick boolean|nil default true — To-Do list / tracker: set false so only left-click opens editor

---Creates a full-width (caller anchors) or fixed-size try-count button; mouse opens WNTryCount popup per options.
---@return Frame row with .text (FontString) and :WnUpdateTryCount(type, id, displayName)
function ns.UI.Factory:CreateTryCountClickable(parent, options)
    options = options or {}
    local height = options.height or 18
    local fontCategory = options.fontCategory or "small"
    local justify = options.justifyH or "RIGHT"
    local showTooltip = options.showTooltip ~= false
    local levelOff = options.frameLevelOffset or 10
    local popupOnLeft = options.popupOnLeftClick ~= false
    local popupOnRight = options.popupOnRightClick ~= false

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    if parent and parent.GetFrameStrata then
        row:SetFrameStrata(parent:GetFrameStrata())
        row:SetFrameLevel((parent:GetFrameLevel() or 0) + levelOff)
    end
    if row.RegisterForClicks then
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    local fs = FontManager:CreateFontString(row, fontCategory, "OVERLAY")
    if justify == "LEFT" then
        fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    else
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end
    fs:SetJustifyH(justify)
    fs:SetWordWrap(false)
    fs:EnableMouse(false)
    row.text = fs

    row._wnTryType = nil
    row._wnTryID = nil
    row._wnTryName = nil

    if showTooltip then
        row:SetScript("OnEnter", function(self)
            if not self:IsShown() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count", 1, 1, 1)
            local hint
            if popupOnLeft and popupOnRight then
                hint = (ns.L and ns.L["TRY_COUNT_CLICK_HINT"]) or "Click to edit attempt count."
            elseif popupOnLeft then
                hint = "Left-click to edit attempt count."
            elseif popupOnRight then
                hint = "Right-click to edit attempt count."
            else
                hint = (ns.L and ns.L["TRY_COUNT_CLICK_HINT"]) or "Click to edit attempt count."
            end
            local hintR, hintG, hintB = 0.7, 0.7, 0.7
            if options.tooltipHintWhite then
                hintR, hintG, hintB = 1, 1, 1
            end
            GameTooltip:AddLine(hint, hintR, hintG, hintB, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row:SetScript("OnClick", nil)
    row:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" and not popupOnLeft then return end
        if btn == "RightButton" and not popupOnRight then return end
        if btn ~= "LeftButton" and btn ~= "RightButton" then return end
        local t, id, name = self._wnTryType, self._wnTryID, self._wnTryName
        if not t or not id or not ns.UI_ShowTryCountPopup then return end
        ns.UI_ShowTryCountPopup(t, id, name)
    end)

    function row:WnUpdateTryCount(collectibleType, collectibleID, displayName)
        self._wnTryType = collectibleType
        self._wnTryID = collectibleID
        self._wnTryName = displayName
        if not collectibleType or not collectibleID or not WarbandNexus or not WarbandNexus.ShouldShowTryCountInUI then
            self:Hide()
            return
        end
        if not WarbandNexus:ShouldShowTryCountInUI(collectibleType, collectibleID) then
            self:Hide()
            return
        end
        local count = (WarbandNexus.GetTryCount and WarbandNexus:GetTryCount(collectibleType, collectibleID)) or 0
        local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
        self.text:SetText((ns.UI_GetSemanticInfoHex and ns.UI_GetSemanticInfoHex() or "|cffaaddff") .. triesLabel .. ":|r " .. (ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. tostring(count) .. "|r")
        self:Show()
    end

    row:Hide()
    return row
end

--- Blizzard achievement objective tracking: symmetric star (PetJournal-FavoritesIcon) + vertex tint by state.
--- Caller anchors the button from the right. Optional `opts.isDisabled` boolean or `function(): boolean` (e.g. plan complete).
---@return Button|nil
function ns.UI.Factory:CreateAchievementTrackPinButton(parent, achievementID, opts)
    opts = type(opts) == "table" and opts or {}
    if not parent or not achievementID or not WarbandNexus then return nil end
    local sz = tonumber(opts.size) or 28
    local btn = self:CreateButton(parent, sz, sz, true)
    if parent.GetFrameLevel then
        btn:SetFrameLevel((parent:GetFrameLevel() or 0) + (tonumber(opts.frameLevelOffset) or 25))
    end
    btn:RegisterForClicks("LeftButtonUp")
    local tex = btn:CreateTexture(nil, "OVERLAY")
    btn._wnTrackPinTex = tex
    local PCM = ns.UI_PLANS_CARD_METRICS
    local pad = (PCM and PCM.plansActionIconInset) or 3
    local iconSz = math.max(12, sz - pad * 2)
    tex:SetSize(iconSz, iconSz)
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local function pinDisabled()
        if type(opts.isDisabled) == "function" then
            local ok, v = pcall(opts.isDisabled)
            return ok and v == true
        end
        return opts.isDisabled == true
    end

    local function applyVisual(tracked, disabled)
        tex:SetTexCoord(0, 1, 0, 1)
        local usedWnPin = ns.UI_ApplyWnActionIcon
            and ns.UI_ApplyWnActionIcon(tex, "track", tracked, disabled)
        if not usedWnPin then
            if not (tex.SetAtlas and pcall(tex.SetAtlas, tex, "PetJournal-FavoritesIcon", true)) then
                tex:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
                tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            end
            tex:SetDesaturated(disabled)
            local vc = ns.UI_WnIconVertexForState(tracked and not disabled, disabled)
            tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
        end
    end

    function btn:WnRefreshAchievementTrackPin()
        local disabled = pinDisabled()
        local tracked = (WarbandNexus.IsAchievementTracked and WarbandNexus:IsAchievementTracked(achievementID)) == true
        applyVisual(tracked, disabled)
        -- NOTE: (not disabled) and WarbandNexus.ToggleAchievementTracking is a function, never == true — must test type.
        local canToggle = (not disabled) and type(WarbandNexus.ToggleAchievementTracking) == "function"
        btn:EnableMouse(true)
        if canToggle then
            btn:SetScript("OnClick", function()
                WarbandNexus:ToggleAchievementTracking(achievementID)
                btn:WnRefreshAchievementTrackPin()
            end)
        else
            btn:SetScript("OnClick", nil)
        end
    end

    btn:SetScript("OnEnter", function(b)
        local L = ns.L
        local title = (L and L["COLLECTIONS_TT_TRACK_TITLE"]) or "Objectives tracker"
        local body
        if pinDisabled() then
            body = (L and L["COLLECTIONS_TT_TRACK_COMPLETED"])
                or "This achievement is already completed. Tracking is not available."
        elseif WarbandNexus.IsAchievementTracked and WarbandNexus:IsAchievementTracked(achievementID) then
            body = (L and L["COLLECTIONS_TT_TRACK_DISABLE"])
                or "Left-click to stop tracking in Blizzard objectives."
        else
            body = (L and L["COLLECTIONS_TT_TRACK_ENABLE"])
                or "Left-click to show progress in Blizzard objectives (up to 10 at once)."
        end
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if ns.UI_GameTooltipSetRoleText then
            ns.UI_GameTooltipSetRoleText(GameTooltip, title, "Bright")
            ns.UI_GameTooltipAddRoleLine(GameTooltip, body, "Normal", true)
        else
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(body, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:WnRefreshAchievementTrackPin()
    return btn
end

-- Collections detail header: action slot (+ try row) + Wowhead (eye always flush right) — same geometry for Mounts / Pets / Toy Box.
ns.CollectionsDetailHeaderLayout = {
    DETAIL_ACTION_SIZE = 32,
    WOWHEAD_SIZE = 32,
    ACTION_SLOT_W = 74,
    ACTION_SLOT_H = 32,
    TRY_GAP = 4,
    TRY_ROW_H = 18,
    WOWHEAD_GAP = 6,
    DETAIL_ICON_PAD = 2,
    -- Plan cards / other tabs: Wowhead eye inset from card top (aligns with Collections detail feel)
    CARD_WOWHEAD_TOP_OFFSET = 10,
}

--- Shared edge color for Collections detail icon shells (Plan / Track / Wowhead / series rows).
function ns.UI.Factory:GetCollectionsDetailIconBorderColor()
    local b = COLORS.border or { 0.45, 0.48, 0.52, 0.75 }
    return { b[1], b[2], b[3], b[4] or 0.75 }
end

--- Bordered square host for Collections detail action icons (Plan / Track / Wowhead).
function ns.UI.Factory:CreateCollectionsDetailIconShell(parent, size, opts)
    if not parent then return nil end
    opts = type(opts) == "table" and opts or {}
    local L = ns.CollectionsDetailHeaderLayout
    size = math.floor(tonumber(size) or (L and L.DETAIL_ACTION_SIZE) or 32)
    local shell = self:CreateContainer(parent, size, size, true)
    if shell and ApplyVisuals then
        local edge = opts.borderColor or self:GetCollectionsDetailIconBorderColor()
        ApplyVisuals(shell, ResolveIconShellBackdrop(), edge)
    end
    if shell and shell.EnableMouse then
        shell:EnableMouse(false)
    end
    return shell
end

--- Center a borderless icon button inside a detail icon shell (visible chrome on shell only).
function ns.UI.Factory:CenterCollectionsDetailActionButton(shell, btn)
    if not shell or not btn then return end
    local L = ns.CollectionsDetailHeaderLayout
    local pad = (L and L.DETAIL_ICON_PAD) or 2
    btn:SetParent(shell)
    btn:ClearAllPoints()
    local shellSz = shell:GetWidth() or (L and L.DETAIL_ACTION_SIZE) or 28
    local inner = math.max(12, shellSz - pad * 2)
    btn:SetSize(inner, inner)
    btn:SetPoint("CENTER", shell, "CENTER", 0, 0)
    if self.ApplyIconOnlyButtonChrome then
        self:ApplyIconOnlyButtonChrome(btn)
    end
end

---Right column: [action slot][Wowhead] with optional try row aligned to the action slot only (not full column width).
---@return { root: Frame, actionSlot: Frame, wowheadBtn: Button, tryCountRow: Frame|nil }
function ns.UI.Factory:CreateCollectionsDetailRightColumn(parent, opts)
    opts = opts or {}
    local withTryRow = opts.withTryRow ~= false
    local L = ns.CollectionsDetailHeaderLayout
    local actionSlotW = opts.actionSlotWidth or L.ACTION_SLOT_W
    local actionSlotH = opts.actionSlotHeight or L.ACTION_SLOT_H
    local whSize = L.WOWHEAD_SIZE or L.DETAIL_ACTION_SIZE or actionSlotH
    local w = whSize + L.WOWHEAD_GAP + actionSlotW
    local h = actionSlotH
    if withTryRow then
        h = h + L.TRY_GAP + L.TRY_ROW_H
    end

    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(w, h)

    local actionSlot = CreateFrame("Frame", nil, root)
    actionSlot:SetSize(actionSlotW, actionSlotH)
    actionSlot:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(whSize + L.WOWHEAD_GAP), 0)

    local detailBorder = self.GetCollectionsDetailIconBorderColor and self:GetCollectionsDetailIconBorderColor()
    local whShell = self:CreateCollectionsDetailIconShell(root, whSize, { borderColor = detailBorder })
    local vOff = math.max(0, (actionSlotH - whSize) / 2)
    if whShell then
        whShell:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -vOff)
    end
    local wowheadParent = whShell or root
    local whPad = (L.DETAIL_ICON_PAD or 2)
    local whInner = math.max(12, whSize - whPad * 2)
    local wowheadBtn = CreateFrame("Button", nil, wowheadParent)
    wowheadBtn:SetSize(whInner, whInner)
    wowheadBtn:SetPoint("CENTER", wowheadParent, "CENTER", 0, 0)
    local whAtlasOk = pcall(function() wowheadBtn:SetNormalAtlas("socialqueuing-icon-eye") end)
    if not whAtlasOk then
        local whTex = wowheadBtn:CreateTexture(nil, "ARTWORK")
        whTex:SetAllPoints()
        ns.UI_SetWnIconTexture(whTex, "link", { vertexColor = ns.WN_ICON_VERTEX_WHITE })
        wowheadBtn._wnIconTex = whTex
    end
    wowheadBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wowheadBtn:SetFrameLevel((wowheadParent:GetFrameLevel() or 0) + 8)
    wowheadBtn._wnDetailIconShell = whShell
    local loc = ns.L
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:SetText((loc and loc["WOWHEAD_LABEL"]) or "Wowhead", 1, 1, 1)
        GameTooltip:AddLine((loc and loc["CLICK_TO_COPY_LINK"]) or "Left-click to copy the Wowhead link.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    wowheadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowheadBtn:Hide()

    local tryCountRow = nil
    if withTryRow then
        tryCountRow = self:CreateTryCountClickable(root, {
            height = L.TRY_ROW_H,
            frameLevelOffset = 10,
            justifyH = "RIGHT",
            tooltipHintWhite = true,
        })
        if tryCountRow then
            tryCountRow:SetPoint("TOPLEFT", actionSlot, "BOTTOMLEFT", 0, -L.TRY_GAP)
            tryCountRow:SetPoint("TOPRIGHT", actionSlot, "BOTTOMRIGHT", 0, -L.TRY_GAP)
        end
    end

    return {
        root = root,
        actionSlot = actionSlot,
        wowheadBtn = wowheadBtn,
        wowheadShell = whShell,
        tryCountRow = tryCountRow,
    }
end
-- (UI_CreateDBVersionBadge / UI_CreateCardHeaderLayout are exported from
-- SharedWidgets.lua, where their local definitions live — assigning them here
-- resolved to nil globals and broke five tabs.)

local function GetDropdownScrollFitSlack()
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    return layout.DROPDOWN_SCROLL_FIT_SLACK or 8
end

---@param scrollFrame ScrollFrame
---@param contentHeight number
---@param frameHeight number
---@param slack number|nil
---@return boolean needsScroll
local function DropdownScrollFrameNeedsScroll(scrollFrame, contentHeight, frameHeight, slack)
    slack = slack or GetDropdownScrollFitSlack()
    if scrollFrame and scrollFrame._wnDropdownRowCount and scrollFrame._wnDropdownMaxVisible then
        if scrollFrame._wnDropdownRowCount > scrollFrame._wnDropdownMaxVisible then
            return true
        end
    end
    if frameHeight and frameHeight >= 2 then
        return (contentHeight or 0) > frameHeight + slack
    end
    local vh = scrollFrame and scrollFrame._wnDropdownViewportH
    if vh then
        return (contentHeight or 0) > vh + slack
    end
    return (contentHeight or 0) > (frameHeight or 0) + slack
end

-- FACTORY METHODS (Standardized Frame Creation)

-- NOTE: CreateContainer implementation moved to line 4789 (Factory pattern wrapper)
-- NOTE: CreateButton implementation moved to line 4809 (Factory pattern wrapper)
-- These duplicate implementations were removed to avoid confusion

--- Create a scroll frame with styled vertical scroll bar (Button | Bar | Button).
--- Bar and buttons are created but not positioned; caller must call PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
--- Use CreateScrollBarColumn(parent, width, topInset, bottomInset) to get a container, or your own frame (e.g. Collections list/detail columns).
---@return ScrollFrame scrollFrame The created scroll frame
function ns.UI.Factory:CreateScrollFrame(parent, template, customStyle)
    if not parent then
        DebugPrint("|cffff4444[WN Factory ERROR]|r CreateScrollFrame: parent is nil")
        return nil
    end
    
    -- Default to UIPanelScrollFrameTemplate if no template provided
    template = template or "UIPanelScrollFrameTemplate"
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, template)
    
    -- Apply modern custom scroll bar styling (default: true)
    if customStyle ~= false and scrollFrame.ScrollBar then
        local scrollBar = scrollFrame.ScrollBar
        local function GetScrollStep()
            local addon = _G.WarbandNexus or ns.WarbandNexus
            local base = ns.UI_LAYOUT.SCROLL_BASE_STEP or 28
            local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or ns.UI_LAYOUT.SCROLL_SPEED_DEFAULT or 1.0
            return math.floor(base * speed + 0.5)
        end
        
        -- Hide default up/down buttons (modern minimalist look)
        if scrollBar.ScrollUpButton then
            scrollBar.ScrollUpButton:Hide()
            scrollBar.ScrollUpButton:SetSize(0.1, 0.1)
        end
        if scrollBar.ScrollDownButton then
            scrollBar.ScrollDownButton:Hide()
            scrollBar.ScrollDownButton:SetSize(0.1, 0.1)
        end
        
        -- Create custom track (background) with visible border
        if not scrollBar.CustomTrack then
            scrollBar.CustomTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
            scrollBar.CustomTrack:SetAllPoints(scrollBar)
            ApplyScrollChromeBackdrop(scrollBar.CustomTrack)
        end
        RegisterScrollChrome(scrollBar)
        
        -- Create pixel-perfect borders for track
        local pixelScale = GetPixelScale()
        
        if not scrollBar.BorderLeft then
            scrollBar.BorderLeft = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderLeft:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.BorderLeft:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
            scrollBar.BorderLeft:SetWidth(pixelScale)
            scrollBar.BorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderRight then
            scrollBar.BorderRight = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderRight:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            scrollBar.BorderRight:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            scrollBar.BorderRight:SetWidth(pixelScale)
            scrollBar.BorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderTop then
            scrollBar.BorderTop = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderTop:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.BorderTop:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            scrollBar.BorderTop:SetHeight(pixelScale)
            scrollBar.BorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderBottom then
            scrollBar.BorderBottom = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderBottom:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
            scrollBar.BorderBottom:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            scrollBar.BorderBottom:SetHeight(pixelScale)
            scrollBar.BorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        -- Register scrollBar for theme refresh
        if scrollBar.BorderTop and scrollBar.BorderBottom and scrollBar.BorderLeft and scrollBar.BorderRight then
            scrollBar._borderType = "accent"
            scrollBar._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar)
        end
        
        -- Create custom thumb (draggable part) with modern styling
        if scrollBar.ThumbTexture then
            -- Main thumb background
            scrollBar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
            scrollBar.ThumbTexture:SetSize(14, 60)  -- Match scroll bar width (14px for thumb inside 16px bar)
            
            -- Store reference for theme refresh
            scrollBar._thumbTexture = scrollBar.ThumbTexture
            
            -- Hover effects (these still use COLORS directly for immediate feedback)
            scrollBar:SetScript("OnEnter", function(self)
                if self.ThumbTexture then
                    local currentColors = GetColors()
                    self.ThumbTexture:SetColorTexture(
                        currentColors.accent[1] * 1.2,
                        currentColors.accent[2] * 1.2,
                        currentColors.accent[3] * 1.2,
                        1
                    )
                end
            end)
            
            scrollBar:SetScript("OnLeave", function(self)
                if self.ThumbTexture then
                    local currentColors = GetColors()
                    self.ThumbTexture:SetColorTexture(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 0.9)
                end
            end)
        end
        
        local btnSize = UI_SPACING.SCROLL_BAR_BUTTON_SIZE or 16
        local barWidth = UI_SPACING.SCROLL_BAR_WIDTH or 16
        -- Create scroll up button (top) — standard Button | Bar | Button layout
        if not scrollBar.ScrollUpBtn then
            scrollBar.ScrollUpBtn = CreateFrame("Button", nil, scrollFrame:GetParent())
            scrollBar.ScrollUpBtn:SetSize(btnSize, btnSize)
            -- Position via PositionScrollBarInContainer(scrollBar, container, inset) only

            -- Background
            local upBg = scrollBar.ScrollUpBtn:CreateTexture(nil, "BACKGROUND")
            upBg:SetAllPoints()
            ApplyScrollChromeBackdrop(upBg)
            scrollBar.ScrollUpBtn.bg = upBg
            
            -- Pixel-perfect borders (matching scroll bar)
            local pixelScale = GetPixelScale()
            
            local upBorderTop = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderTop:SetPoint("TOPLEFT", 0, 0)
            upBorderTop:SetPoint("TOPRIGHT", 0, 0)
            upBorderTop:SetHeight(pixelScale)
            upBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderBottom = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
            upBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
            upBorderBottom:SetHeight(pixelScale)
            upBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderLeft = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderLeft:SetPoint("TOPLEFT", 0, 0)
            upBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
            upBorderLeft:SetWidth(pixelScale)
            upBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderRight = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderRight:SetPoint("TOPRIGHT", 0, 0)
            upBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
            upBorderRight:SetWidth(pixelScale)
            upBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            -- Store border textures for registry
            scrollBar.ScrollUpBtn.BorderTop = upBorderTop
            scrollBar.ScrollUpBtn.BorderBottom = upBorderBottom
            scrollBar.ScrollUpBtn.BorderLeft = upBorderLeft
            scrollBar.ScrollUpBtn.BorderRight = upBorderRight
            
            -- Register for theme refresh
            scrollBar.ScrollUpBtn._borderType = "accent"
            scrollBar.ScrollUpBtn._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar.ScrollUpBtn)
            
            -- Arrow icon
            local upIcon = scrollBar.ScrollUpBtn:CreateTexture(nil, "ARTWORK")
            upIcon:SetSize(12, 12)
            upIcon:SetPoint("CENTER")
            upIcon:SetAtlas("common-icon-offscreen", false)
            upIcon:SetRotation(-math.pi / 2)
            upIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            scrollBar.ScrollUpBtn.icon = upIcon
            scrollBar.ScrollUpBtn._iconTexture = upIcon  -- Store for theme refresh
            
            -- Click handler (pixel-snapped)
            scrollBar.ScrollUpBtn:SetScript("OnClick", function()
                local step = GetScrollStep()
                local current = scrollFrame:GetVerticalScroll()
                local val = math.max(0, current - step)
                local PS = ns.PixelSnap
                if PS then val = PS(val) end
                scrollFrame:SetVerticalScroll(val)
            end)
            
            -- Hover effects
            scrollBar.ScrollUpBtn:SetScript("OnEnter", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
                self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
            end)
            
            scrollBar.ScrollUpBtn:SetScript("OnLeave", function(self)
                local currentColors = GetColors()
                ApplyScrollChromeBackdrop(self.bg)
                self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
            end)
        end
        
        -- Create scroll down button (bottom)
        if not scrollBar.ScrollDownBtn then
            scrollBar.ScrollDownBtn = CreateFrame("Button", nil, scrollFrame:GetParent())
            scrollBar.ScrollDownBtn:SetSize(btnSize, btnSize)
            -- Position via PositionScrollBarInContainer(scrollBar, container, inset) only

            -- Background
            local downBg = scrollBar.ScrollDownBtn:CreateTexture(nil, "BACKGROUND")
            downBg:SetAllPoints()
            ApplyScrollChromeBackdrop(downBg)
            scrollBar.ScrollDownBtn.bg = downBg
            
            -- Pixel-perfect borders (matching scroll bar)
            local pixelScale = GetPixelScale()
            
            local downBorderTop = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderTop:SetPoint("TOPLEFT", 0, 0)
            downBorderTop:SetPoint("TOPRIGHT", 0, 0)
            downBorderTop:SetHeight(pixelScale)
            downBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderBottom = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
            downBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
            downBorderBottom:SetHeight(pixelScale)
            downBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderLeft = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderLeft:SetPoint("TOPLEFT", 0, 0)
            downBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
            downBorderLeft:SetWidth(pixelScale)
            downBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderRight = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderRight:SetPoint("TOPRIGHT", 0, 0)
            downBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
            downBorderRight:SetWidth(pixelScale)
            downBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            -- Store border textures for registry
            scrollBar.ScrollDownBtn.BorderTop = downBorderTop
            scrollBar.ScrollDownBtn.BorderBottom = downBorderBottom
            scrollBar.ScrollDownBtn.BorderLeft = downBorderLeft
            scrollBar.ScrollDownBtn.BorderRight = downBorderRight
            
            -- Register for theme refresh
            scrollBar.ScrollDownBtn._borderType = "accent"
            scrollBar.ScrollDownBtn._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar.ScrollDownBtn)
            
            -- Arrow icon
            local downIcon = scrollBar.ScrollDownBtn:CreateTexture(nil, "ARTWORK")
            downIcon:SetSize(12, 12)
            downIcon:SetPoint("CENTER")
            downIcon:SetAtlas("common-icon-offscreen", false)
            downIcon:SetRotation(math.pi / 2)
            downIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            scrollBar.ScrollDownBtn.icon = downIcon
            scrollBar.ScrollDownBtn._iconTexture = downIcon  -- Store for theme refresh
            
            -- Click handler (pixel-snapped)
            scrollBar.ScrollDownBtn:SetScript("OnClick", function()
                local step = GetScrollStep()
                local current = scrollFrame:GetVerticalScroll()
                local maxScroll = scrollFrame:GetVerticalScrollRange()
                local val = math.min(maxScroll, current + step)
                local PS = ns.PixelSnap
                if PS then val = PS(val) end
                scrollFrame:SetVerticalScroll(val)
            end)
            
            -- Hover effects
            scrollBar.ScrollDownBtn:SetScript("OnEnter", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
                self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
            end)
            
            scrollBar.ScrollDownBtn:SetScript("OnLeave", function(self)
                local currentColors = GetColors()
                ApplyScrollChromeBackdrop(self.bg)
                self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
            end)
        end

        -- Bar/buttons are positioned only via PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
        -- Hide until positioned so they do not appear at (0,0).
        scrollBar:Hide()
        if scrollBar.ScrollUpBtn then scrollBar.ScrollUpBtn:Hide() end
        if scrollBar.ScrollDownBtn then scrollBar.ScrollDownBtn:Hide() end

        -- When scroll bar is reparented (e.g. into scrollBarContainer), Blizzard's OnValueChanged
        -- calls GetParent():SetVerticalScroll() which fails. Keep explicit reference and override.
        scrollBar._scrollFrame = scrollFrame
        scrollBar:SetScript("OnValueChanged", function(self, value)
            if self._scrollFrame and self._scrollFrame.SetVerticalScroll then
                self._scrollFrame:SetVerticalScroll(value)
            end
        end)
    end
    
    -- Debug log (only first call; verbose-only so normal debug mode stays readable)
    if not self._scrollLogged then
        if ns.DebugVerbosePrint then
            ns.DebugVerbosePrint("|cff9370DB[WN Factory]|r CreateScrollFrame initialized with modern scroll bar")
        end
        self._scrollLogged = true
    end
    
    -- Auto-hide scroll bar when content fits (call after content is populated).
    -- When bar is in an external container (reparented), always show bar and buttons so the column does not flicker.
    scrollFrame.UpdateScrollBarVisibility = function(self)
        if not self.ScrollBar then return end
        local bar = self.ScrollBar
        local scrollChild = self:GetScrollChild()
        if not scrollChild then return end
        local slack = GetDropdownScrollFitSlack()
        local contentHeight = scrollChild:GetHeight() or 0
        local frameHeight = self:GetHeight() or 0
        local isDropdown = self._wnDropdownRowCount or self._wnDropdownViewportH
        local needsScroll = DropdownScrollFrameNeedsScroll(self, contentHeight, frameHeight, slack)

        if not needsScroll and isDropdown and scrollChild and frameHeight >= 2 then
            if contentHeight > frameHeight and contentHeight <= frameHeight + slack then
                scrollChild:SetHeight(frameHeight)
                contentHeight = frameHeight
            end
        end

        self._wnDropdownNeedsScroll = isDropdown and needsScroll or nil

        local barInExternalContainer = (bar.GetParent and bar:GetParent() ~= self)
        local col = self._wnScrollBarColumn
        local host = self._wnScrollHost
        local tl = self._wnScrollAnchorTL
        local brHidden = self._wnScrollAnchorBRHidden
        local brShown = self._wnScrollAnchorBRShown

        if col and host and tl and brHidden and brShown then
            self:ClearAllPoints()
            self:SetPoint(tl.a1 or "TOPLEFT", tl.frame, tl.a2 or "TOPLEFT", tl.x or 0, tl.y or 0)
            if needsScroll then
                col:Show()
                self:SetPoint(brShown.a1 or "BOTTOMRIGHT", brShown.frame, brShown.a2 or "BOTTOMLEFT", brShown.x or -2, brShown.y or 0)
            else
                col:Hide()
                self:SetPoint(brHidden.a1 or "BOTTOMRIGHT", brHidden.frame, brHidden.a2 or "BOTTOMRIGHT", brHidden.x or 0, brHidden.y or 0)
                if self.SetVerticalScroll then
                    self:SetVerticalScroll(0)
                end
            end
        end

        if self.EnableMouseWheel then
            if isDropdown then
                self:EnableMouseWheel(needsScroll)
            else
                self:EnableMouseWheel(true)
            end
        end

        if barInExternalContainer then
            if needsScroll then
                bar:Show()
                if bar.ScrollUpBtn then bar.ScrollUpBtn:Show() end
                if bar.ScrollDownBtn then bar.ScrollDownBtn:Show() end
            else
                bar:Hide()
                if bar.ScrollUpBtn then bar.ScrollUpBtn:Hide() end
                if bar.ScrollDownBtn then bar.ScrollDownBtn:Hide() end
            end
            return
        end

        if needsScroll then
            bar:Show()
            if bar.ScrollUpBtn then bar.ScrollUpBtn:Show() end
            if bar.ScrollDownBtn then bar.ScrollDownBtn:Show() end
        else
            bar:Hide()
            if bar.ScrollUpBtn then bar.ScrollUpBtn:Hide() end
            if bar.ScrollDownBtn then bar.ScrollDownBtn:Hide() end
        end
    end
    
    -- Smooth scroll: base step * speed multiplier from profile
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local isDropdown = self._wnDropdownRowCount or self._wnDropdownViewportH
        local maxScroll = self:GetVerticalScrollRange()
        if isDropdown then
            local slack = GetDropdownScrollFitSlack()
            if self._wnDropdownNeedsScroll == false or maxScroll <= slack then
                if self.SetVerticalScroll then
                    self:SetVerticalScroll(0)
                end
                return
            end
        end
        local addon = _G.WarbandNexus or ns.WarbandNexus
        local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
        local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
        local step = math.floor(base * speed + 0.5)
        -- Shift+Wheel routes to horizontal when available; default wheel keeps vertical behavior.
        if IsShiftKeyDown and IsShiftKeyDown() and self.GetHorizontalScrollRange and self.SetHorizontalScroll then
            local maxH = self:GetHorizontalScrollRange() or 0
            if maxH > 0 then
                local currentH = self:GetHorizontalScroll() or 0
                local newH = math.max(0, math.min(maxH, currentH - (delta * step)))
                self:SetHorizontalScroll(newH)
                if self.HorizontalScrollBar then
                    self.HorizontalScrollBar:SetValue(newH)
                end
                return
            end
        end

        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * step)))
        local PS = ns.PixelSnap
        if PS then newScroll = PS(newScroll) end
        self:SetVerticalScroll(newScroll)
    end)
    
    return scrollFrame
end

--- Shared dropdown layout (all tab scroll dropdowns: Gear char picker, Settings, Plans tracker, etc.).
---@return table
function ns.UI.Factory:GetDropdownLayout()
    local sp = ns.UI_SPACING or UI_SPACING or {}
    local layout = ns.UI_LAYOUT or {}
    return {
        rowHeight = sp.DROPDOWN_MENU_ROW_HEIGHT or sp.ROW_HEIGHT or 26,
        maxVisibleRows = layout.DROPDOWN_MAX_VISIBLE_ROWS or sp.DROPDOWN_MAX_VISIBLE_ROWS or 6,
        menuEdge = layout.DROPDOWN_MENU_EDGE or sp.DROPDOWN_MENU_EDGE or 4,
        insetTop = layout.DROPDOWN_INSET_TOP or sp.DROPDOWN_INSET_TOP or 4,
        insetBottom = layout.DROPDOWN_INSET_BOTTOM or sp.DROPDOWN_INSET_BOTTOM or 4,
        scrollGap = layout.DROPDOWN_SCROLL_GAP or sp.DROPDOWN_SCROLL_GAP or 2,
        scrollFitSlack = layout.DROPDOWN_SCROLL_FIT_SLACK or sp.DROPDOWN_SCROLL_FIT_SLACK or 8,
        scrollBarW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or sp.SCROLLBAR_COLUMN_WIDTH or 26,
    }
end

---@return number menuOuterH, number scrollContentH
function ns.UI.Factory:ComputeDropdownMenuHeights(rowCount, rowHeight, opts)
    opts = opts or {}
    local dl = self:GetDropdownLayout()
    rowHeight = rowHeight or dl.rowHeight
    local maxRows = opts.maxVisibleRows or dl.maxVisibleRows
    local insetTop = opts.insetTop or dl.insetTop
    local insetBottom = opts.insetBottom or dl.insetBottom
    local menuEdge = opts.menuEdge or dl.menuEdge
    rowCount = tonumber(rowCount) or 0
    if rowCount <= 0 then
        local emptyInner = insetTop + rowHeight + insetBottom
        return emptyInner + 2 * menuEdge, emptyInner
    end
    local visibleRows = math.min(rowCount, maxRows)
    local scrollContentH = insetTop + rowCount * rowHeight + insetBottom
    local scrollViewportH = insetTop + visibleRows * rowHeight + insetBottom
    local menuOuterH = scrollViewportH + 2 * menuEdge
    return menuOuterH, scrollContentH
end

--- Anchor metadata for UpdateScrollBarVisibility (hide scrollbar column when content fits).
function ns.UI.Factory:WireScrollBarColumnLayout(scrollFrame, host, barColumn, opts)
    if not scrollFrame or not host or not barColumn then return end
    opts = opts or {}
    local dl = self:GetDropdownLayout()
    local edge = opts.menuEdge or dl.menuEdge
    local gap = opts.scrollGap or dl.scrollGap
    scrollFrame._wnScrollBarColumn = barColumn
    scrollFrame._wnScrollHost = host
    scrollFrame._wnScrollAnchorTL = { frame = host, a1 = "TOPLEFT", a2 = "TOPLEFT", x = edge, y = -edge }
    scrollFrame._wnScrollAnchorBRShown = { frame = barColumn, a1 = "BOTTOMRIGHT", a2 = "BOTTOMLEFT", x = -gap, y = edge }
    scrollFrame._wnScrollAnchorBRHidden = { frame = host, a1 = "BOTTOMRIGHT", a2 = "BOTTOMRIGHT", x = -edge, y = edge }
end

--- Create or reuse scroll + scrollbar column on a dropdown menu host; sizes viewport to shared row cap.
---@return ScrollFrame|nil scroll, Frame|nil scrollChild, Frame|nil barColumn, number menuOuterH, number scrollContentH
function ns.UI.Factory:ApplyDropdownScrollLayout(menu, rowCount, rowHeight, opts)
    if not menu then return nil, nil, nil, 0, 0 end
    opts = opts or {}
    local dl = self:GetDropdownLayout()
    rowHeight = rowHeight or dl.rowHeight
    local menuEdge = opts.menuEdge or dl.menuEdge
    local scrollGap = opts.scrollGap or dl.scrollGap
    local scrollBarW = dl.scrollBarW
    local maxRows = opts.maxVisibleRows or dl.maxVisibleRows
    rowCount = tonumber(rowCount) or 0
    local visibleRows = math.min(math.max(rowCount, 0), maxRows)
    local scrollViewportH = dl.insetTop + visibleRows * rowHeight + dl.insetBottom
    local scrollContentH = (rowCount > 0)
        and (dl.insetTop + rowCount * rowHeight + dl.insetBottom)
        or (dl.insetTop + rowHeight + dl.insetBottom)
    local menuOuterH = scrollViewportH + 2 * menuEdge
    menu:SetHeight(menuOuterH)

    local scroll = menu._wnDropdownScroll
    local scrollChild = menu._wnDropdownScrollChild
    local barColumn = menu._wnDropdownBarColumn
    if not scroll or opts.recreate then
        barColumn = self:CreateScrollBarColumn(menu, scrollBarW, menuEdge, menuEdge)
        scroll = self:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        if not scroll then return nil, nil, nil, menuOuterH, scrollContentH end
        scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", menuEdge, -menuEdge)
        scroll:SetPoint("BOTTOMRIGHT", barColumn, "BOTTOMLEFT", -scrollGap, menuEdge)
        if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
        self:WireScrollBarColumnLayout(scroll, menu, barColumn, opts)
        local menuW = menu:GetWidth() or 200
        local initW = math.max(56, menuW - scrollBarW - menuEdge * 2 - scrollGap)
        local initChildH = (rowCount <= maxRows) and scrollViewportH or scrollContentH
        scrollChild = self:CreateContainer(scroll, initW, initChildH, false)
        if not scrollChild then
            scrollChild = CreateFrame("Frame", nil, scroll)
            scrollChild:SetSize(initW, initChildH)
        end
        scroll:SetScrollChild(scrollChild)
        menu._wnDropdownScroll = scroll
        menu._wnDropdownScrollChild = scrollChild
        menu._wnDropdownBarColumn = barColumn
        if scroll.ScrollBar and barColumn then
            self:PositionScrollBarInContainer(scroll.ScrollBar, barColumn, 0)
        end
        if not scroll._wnDropdownWidthHook then
            scroll._wnDropdownWidthHook = true
            scroll:SetScript("OnSizeChanged", function(frame, w)
                local sc = menu._wnDropdownScrollChild
                if sc and w and w > 0 then sc:SetWidth(w) end
            end)
        end
    else
        self:WireScrollBarColumnLayout(scroll, menu, barColumn, opts)
    end

    if scroll then
        scroll._wnDropdownRowCount = rowCount
        scroll._wnDropdownMaxVisible = maxRows
        scroll._wnDropdownViewportH = scrollViewportH
    end
    if scrollChild then
        if rowCount <= maxRows then
            scrollChild:SetHeight(scrollViewportH)
        else
            scrollChild:SetHeight(math.max(scrollContentH, 1))
        end
    end
    if scroll then
        scroll:SetVerticalScroll(0)
        local sw = scroll:GetWidth()
        if sw and sw > 0 and scrollChild then
            scrollChild:SetWidth(sw)
        end
        local function syncBar()
            if scroll and scroll.GetScrollChild and scroll:GetScrollChild() then
                self:UpdateScrollBarVisibility(scroll)
            end
        end
        syncBar()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, syncBar)
        end
        self:EnsureDropdownEscClose(menu)
    end
    return scroll, scrollChild, barColumn, menuOuterH, scrollContentH
end

--- Create a frame for the vertical scroll bar column (same pattern as Collections: list | bar column | details).
--- Caller anchors this to the right of the scroll content, then calls PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
---@return Frame container The frame to pass to PositionScrollBarInContainer
function ns.UI.Factory:CreateScrollBarColumn(parent, width, topInset, bottomInset)
    if not parent then return nil end
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local w = width or layout.SCROLLBAR_COLUMN_WIDTH or 26
    local top = (topInset == nil) and 0 or topInset
    local bottom = (bottomInset == nil) and 0 or bottomInset
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -top)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottom)
    container:SetWidth(w)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

--- Standard layout when scroll bar is placed in an external container (e.g. list | gap | scrollbar | gap | details).
--- Ensures Button (top) | Bar | Button (bottom) with same dimensions everywhere (SCROLL_BAR_BUTTON_SIZE, SCROLL_BAR_WIDTH).
function ns.UI.Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, inset)
    if not scrollBar or not scrollBarContainer then return end
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local btnSize = layout.SCROLL_BAR_BUTTON_SIZE or 16
    local barWidth = layout.SCROLL_BAR_WIDTH or 16
    local gap = (inset == nil) and 2 or inset

    local containerLevel = scrollBarContainer:GetFrameLevel()
    scrollBar:SetParent(scrollBarContainer)
    scrollBar:SetFrameLevel(containerLevel + 1)
    scrollBar:Show()

    -- Buttons fully inside container (no -gap/+gap) so they are never clipped by adjacent panels
    if scrollBar.ScrollUpBtn then
        scrollBar.ScrollUpBtn:SetParent(scrollBarContainer)
        scrollBar.ScrollUpBtn:SetFrameLevel(containerLevel + 3)
        scrollBar.ScrollUpBtn:ClearAllPoints()
        scrollBar.ScrollUpBtn:SetSize(btnSize, btnSize)
        scrollBar.ScrollUpBtn:SetPoint("TOP", scrollBarContainer, "TOP", 0, 0)
        scrollBar.ScrollUpBtn:Show()
    end
    if scrollBar.ScrollDownBtn then
        scrollBar.ScrollDownBtn:SetParent(scrollBarContainer)
        scrollBar.ScrollDownBtn:SetFrameLevel(containerLevel + 3)
        scrollBar.ScrollDownBtn:ClearAllPoints()
        scrollBar.ScrollDownBtn:SetSize(btnSize, btnSize)
        scrollBar.ScrollDownBtn:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, 0)
        scrollBar.ScrollDownBtn:Show()
    end
    scrollBar:ClearAllPoints()
    if scrollBar.ScrollUpBtn and scrollBar.ScrollDownBtn then
        scrollBar:SetPoint("TOP", scrollBar.ScrollUpBtn, "BOTTOM", 0, 0)
        scrollBar:SetPoint("BOTTOM", scrollBar.ScrollDownBtn, "TOP", 0, 0)
    else
        scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, 0)
        scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, 0)
    end
    -- Fixed width (never stretch): bar and buttons stay barWidth/btnSize so all windows look identical
    scrollBar:SetWidth(barWidth)
    scrollBar:SetPoint("CENTER", scrollBarContainer, "CENTER", 0, 0)
end

---Update scroll bar visibility based on content height (call after content changes)
function ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    if scrollFrame and scrollFrame.UpdateScrollBarVisibility then
        scrollFrame:UpdateScrollBarVisibility()
    end
end

-- DROPDOWN ESC: close flyouts before main / settings windows (WindowManager:CloseTopWindow).

local dropdownEscCloseHooks = {}

---Optional: register an extra close hook (return true when a menu was open and is now closed).
function ns.UI_RegisterDropdownEscClose(closeFn)
    if type(closeFn) ~= "function" then return end
    dropdownEscCloseHooks[#dropdownEscCloseHooks + 1] = closeFn
end

---Install ESC-to-close on a dropdown menu host (combobox popover). Safe to call once per menu frame.
function ns.UI.Factory:EnsureDropdownEscClose(menu)
    if not menu or menu._wnDropdownEscInstalled then return end
    menu._wnDropdownEscInstalled = true
    if not InCombatLockdown() and menu.EnableKeyboard then
        menu:EnableKeyboard(true)
    end
    if menu.SetPropagateKeyboardInput then
        menu:SetPropagateKeyboardInput(false)
    end
    menu:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then return end
        if ns.UI_CloseOpenDropdownMenus and ns.UI_CloseOpenDropdownMenus() then
            ns._wnEscJustHandled = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() ns._wnEscJustHandled = nil end)
            end
        elseif self.Hide then
            self:Hide()
        end
    end)
end

---@return boolean closed Any open dropdown / flyout menu was dismissed.
function ns.UI_CloseOpenDropdownMenus()
    local closed = false

    for i = 1, #dropdownEscCloseHooks do
        local ok, did = pcall(dropdownEscCloseHooks[i])
        if ok and did then
            closed = true
        end
    end

    if ns.UI_CloseSettingsOpenDropdown and ns.UI_CloseSettingsOpenDropdown() then
        closed = true
    end

    local WN = ns.WarbandNexus
    if WN then
        if WN._wnPvEColumnPickerMenu and WN._wnPvEColumnPickerMenu:IsShown() and WN.HidePvEColumnPickerMenu then
            WN:HidePvEColumnPickerMenu()
            closed = true
        end
        local hideBtn = WN._wnPvEHideFilterBtn
        if hideBtn then
            if hideBtn._menu and hideBtn._menu:IsShown() then
                hideBtn._menu:Hide()
                closed = true
            end
            if hideBtn._catcher and hideBtn._catcher:IsShown() then
                hideBtn._catcher:Hide()
                closed = true
            end
        end
        if WN.HideProfessionColumnPicker then
            local profMenu = WN._wnProfColumnPickerMenu
            if profMenu and profMenu:IsShown() then
                WN:HideProfessionColumnPicker()
                closed = true
            end
        end
    end

    if ns.HideGearToolbarDropdowns and ns.HideGearToolbarDropdowns() then
        closed = true
    end

    if ns.UI_CloseCharacterTabFlyoutMenus and ns.UI_CloseCharacterTabFlyoutMenus() then
        closed = true
    end

    if ns.PlansTracker_CloseOpenDropdown and ns.PlansTracker_CloseOpenDropdown() then
        closed = true
    end

    return closed
end

ns.UI_ApplyDropdownScrollLayout = function(menu, rowCount, rowHeight, opts)
    local F = ns.UI and ns.UI.Factory
    if F and F.ApplyDropdownScrollLayout then
        return F:ApplyDropdownScrollLayout(menu, rowCount, rowHeight, opts)
    end
    return nil, nil, nil, 0, 0
end

---Create a horizontal scrollbar matching the vertical scrollbar style.
---Usage: attach to an existing ScrollFrame and call UpdateHorizontalScrollBarVisibility after content width changes.
---@return Slider|nil hBar The created horizontal slider
function ns.UI.Factory:CreateHorizontalScrollBar(scrollFrame, parent, customStyle)
    if not scrollFrame or not parent then return nil end
    if customStyle == false then return nil end

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local btnSize = layout.SCROLL_BAR_BUTTON_SIZE or 16
    -- Single height for track + arrows (layout HORIZONTAL_SCROLL_BAR_HEIGHT should match btnSize)
    local barHeight = btnSize

    local function GetScrollStep()
        local addon = _G.WarbandNexus or ns.WarbandNexus
        local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
        local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
        return math.floor(base * speed + 0.5)
    end

    local hBar = CreateFrame("Slider", nil, parent)
    hBar:SetOrientation("HORIZONTAL")
    hBar:SetMinMaxValues(0, 0)
    hBar:SetValueStep(1)
    hBar:SetObeyStepOnDrag(true)
    hBar:SetHeight(barHeight)
    hBar:Hide()

    -- Track background
    hBar.CustomTrack = hBar:CreateTexture(nil, "BACKGROUND")
    hBar.CustomTrack:SetAllPoints(hBar)
    ApplyScrollChromeBackdrop(hBar.CustomTrack)
    RegisterScrollChrome(hBar)

    -- Pixel borders
    local pixelScale = GetPixelScale()
    hBar.BorderLeft = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderLeft:SetPoint("TOPLEFT", hBar, "TOPLEFT", 0, 0)
    hBar.BorderLeft:SetPoint("BOTTOMLEFT", hBar, "BOTTOMLEFT", 0, 0)
    hBar.BorderLeft:SetWidth(pixelScale)
    hBar.BorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderRight = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderRight:SetPoint("TOPRIGHT", hBar, "TOPRIGHT", 0, 0)
    hBar.BorderRight:SetPoint("BOTTOMRIGHT", hBar, "BOTTOMRIGHT", 0, 0)
    hBar.BorderRight:SetWidth(pixelScale)
    hBar.BorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderTop = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderTop:SetPoint("TOPLEFT", hBar, "TOPLEFT", 0, 0)
    hBar.BorderTop:SetPoint("TOPRIGHT", hBar, "TOPRIGHT", 0, 0)
    hBar.BorderTop:SetHeight(pixelScale)
    hBar.BorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderBottom = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderBottom:SetPoint("BOTTOMLEFT", hBar, "BOTTOMLEFT", 0, 0)
    hBar.BorderBottom:SetPoint("BOTTOMRIGHT", hBar, "BOTTOMRIGHT", 0, 0)
    hBar.BorderBottom:SetHeight(pixelScale)
    hBar.BorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar._borderType = "accent"
    hBar._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar)

    -- Thumb width 60; height inside track (bar and buttons share barHeight)
    local thumbH = math.max(6, math.min(16, barHeight - 4))
    hBar.ThumbTexture = hBar:CreateTexture(nil, "ARTWORK")
    hBar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    hBar.ThumbTexture:SetSize(60, thumbH)
    hBar:SetThumbTexture(hBar.ThumbTexture)
    hBar._thumbTexture = hBar.ThumbTexture

    -- Left button
    hBar.ScrollLeftBtn = CreateFrame("Button", nil, parent)
    hBar.ScrollLeftBtn:SetSize(btnSize, btnSize)
    hBar.ScrollLeftBtn:Hide()
    local leftBg = hBar.ScrollLeftBtn:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints()
    ApplyScrollChromeBackdrop(leftBg)
    hBar.ScrollLeftBtn.bg = leftBg
    local leftBorderTop = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderTop:SetPoint("TOPLEFT", 0, 0)
    leftBorderTop:SetPoint("TOPRIGHT", 0, 0)
    leftBorderTop:SetHeight(pixelScale)
    leftBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderBottom = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    leftBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    leftBorderBottom:SetHeight(pixelScale)
    leftBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderLeft = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderLeft:SetPoint("TOPLEFT", 0, 0)
    leftBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    leftBorderLeft:SetWidth(pixelScale)
    leftBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderRight = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderRight:SetPoint("TOPRIGHT", 0, 0)
    leftBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    leftBorderRight:SetWidth(pixelScale)
    leftBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    hBar.ScrollLeftBtn.BorderTop = leftBorderTop
    hBar.ScrollLeftBtn.BorderBottom = leftBorderBottom
    hBar.ScrollLeftBtn.BorderLeft = leftBorderLeft
    hBar.ScrollLeftBtn.BorderRight = leftBorderRight
    hBar.ScrollLeftBtn._borderType = "accent"
    hBar.ScrollLeftBtn._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar.ScrollLeftBtn)
    -- Icon: common-icon-offscreen (default left); accent color
    local leftIcon = hBar.ScrollLeftBtn:CreateTexture(nil, "ARTWORK")
    leftIcon:SetSize(12, 12)
    leftIcon:SetPoint("CENTER")
    leftIcon:SetAtlas("common-icon-offscreen", false)
    leftIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    hBar.ScrollLeftBtn.icon = leftIcon
    hBar.ScrollLeftBtn._iconTexture = leftIcon

    -- Right button
    hBar.ScrollRightBtn = CreateFrame("Button", nil, parent)
    hBar.ScrollRightBtn:SetSize(btnSize, btnSize)
    hBar.ScrollRightBtn:Hide()
    local rightBg = hBar.ScrollRightBtn:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints()
    ApplyScrollChromeBackdrop(rightBg)
    hBar.ScrollRightBtn.bg = rightBg
    local rightBorderTop = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderTop:SetPoint("TOPLEFT", 0, 0)
    rightBorderTop:SetPoint("TOPRIGHT", 0, 0)
    rightBorderTop:SetHeight(pixelScale)
    rightBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderBottom = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    rightBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    rightBorderBottom:SetHeight(pixelScale)
    rightBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderLeft = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderLeft:SetPoint("TOPLEFT", 0, 0)
    rightBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    rightBorderLeft:SetWidth(pixelScale)
    rightBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderRight = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderRight:SetPoint("TOPRIGHT", 0, 0)
    rightBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    rightBorderRight:SetWidth(pixelScale)
    rightBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    hBar.ScrollRightBtn.BorderTop = rightBorderTop
    hBar.ScrollRightBtn.BorderBottom = rightBorderBottom
    hBar.ScrollRightBtn.BorderLeft = rightBorderLeft
    hBar.ScrollRightBtn.BorderRight = rightBorderRight
    hBar.ScrollRightBtn._borderType = "accent"
    hBar.ScrollRightBtn._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar.ScrollRightBtn)
    -- Icon: common-icon-offscreen rotated 180° (right)
    local rightIcon = hBar.ScrollRightBtn:CreateTexture(nil, "ARTWORK")
    rightIcon:SetSize(12, 12)
    rightIcon:SetPoint("CENTER")
    rightIcon:SetAtlas("common-icon-offscreen", false)
    rightIcon:SetRotation(math.pi)
    rightIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    hBar.ScrollRightBtn.icon = rightIcon
    hBar.ScrollRightBtn._iconTexture = rightIcon

    local function ButtonHoverOn(self)
        local currentColors = GetColors()
        self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
        self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
    end
    local function ButtonHoverOff(self)
        local currentColors = GetColors()
        ApplyScrollChromeBackdrop(self.bg)
        self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
    end
    hBar.ScrollLeftBtn:SetScript("OnEnter", ButtonHoverOn)
    hBar.ScrollLeftBtn:SetScript("OnLeave", ButtonHoverOff)
    hBar.ScrollRightBtn:SetScript("OnEnter", ButtonHoverOn)
    hBar.ScrollRightBtn:SetScript("OnLeave", ButtonHoverOff)

    hBar:SetScript("OnEnter", function(self)
        if self.ThumbTexture then
            local currentColors = GetColors()
            self.ThumbTexture:SetColorTexture(currentColors.accent[1] * 1.2, currentColors.accent[2] * 1.2, currentColors.accent[3] * 1.2, 1)
        end
    end)
    hBar:SetScript("OnLeave", function(self)
        if self.ThumbTexture then
            local currentColors = GetColors()
            self.ThumbTexture:SetColorTexture(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 0.9)
        end
    end)

    hBar._scrollFrame = scrollFrame
    hBar:SetScript("OnValueChanged", function(self, value)
        if self._scrollFrame and self._scrollFrame.SetHorizontalScroll then
            self._scrollFrame:SetHorizontalScroll(value)
        end
    end)

    hBar.ScrollLeftBtn:SetScript("OnClick", function()
        local current = scrollFrame:GetHorizontalScroll() or 0
        scrollFrame:SetHorizontalScroll(math.max(0, current - GetScrollStep()))
        hBar:SetValue(scrollFrame:GetHorizontalScroll() or 0)
    end)
    hBar.ScrollRightBtn:SetScript("OnClick", function()
        local current = scrollFrame:GetHorizontalScroll() or 0
        local getRange = scrollFrame.GetHorizontalScrollRange
        local maxScroll = 0
        if getRange then
            maxScroll = math.max(0, getRange(scrollFrame) or 0)
        end
        scrollFrame:SetHorizontalScroll(math.min(maxScroll, current + GetScrollStep()))
        hBar:SetValue(scrollFrame:GetHorizontalScroll() or 0)
    end)

    -- Position helpers
    hBar.PositionInContainer = function(self, container, inset)
        if not container then return end
        local gap = (inset == nil) and 0 or inset
        local level = container:GetFrameLevel()

        self:SetParent(container)
        self:SetFrameLevel(level + 1)
        self:ClearAllPoints()
        self:SetPoint("LEFT", container, "LEFT", btnSize + gap, 0)
        self:SetPoint("RIGHT", container, "RIGHT", -(btnSize + gap), 0)
        self:SetPoint("CENTER", container, "CENTER", 0, 0)

        if self.ScrollLeftBtn then
            self.ScrollLeftBtn:SetParent(container)
            self.ScrollLeftBtn:SetFrameLevel(level + 3)
            self.ScrollLeftBtn:ClearAllPoints()
            -- One anchor: center of button on mid-left of strip (avoid LEFT+CENTER conflict with bar height)
            self.ScrollLeftBtn:SetPoint("CENTER", container, "LEFT", btnSize / 2, 0)
        end
        if self.ScrollRightBtn then
            self.ScrollRightBtn:SetParent(container)
            self.ScrollRightBtn:SetFrameLevel(level + 3)
            self.ScrollRightBtn:ClearAllPoints()
            self.ScrollRightBtn:SetPoint("CENTER", container, "RIGHT", -btnSize / 2, 0)
        end
    end

    scrollFrame.HorizontalScrollBar = hBar

    scrollFrame.UpdateHorizontalScrollBarVisibility = function(self)
        local bar = self.HorizontalScrollBar
        if not bar then return end
        local child = self:GetScrollChild()
        if not child then return end

        local contentWidth = child:GetWidth() or 0
        local frameWidth = self:GetWidth() or 0
        local maxScroll = math.max(0, contentWidth - frameWidth)
        bar:SetMinMaxValues(0, maxScroll)

        if maxScroll > 1 then
            bar:Show()
            if bar.ScrollLeftBtn then bar.ScrollLeftBtn:Show() end
            if bar.ScrollRightBtn then bar.ScrollRightBtn:Show() end
            local current = self:GetHorizontalScroll() or 0
            if current > maxScroll then
                current = maxScroll
                self:SetHorizontalScroll(current)
            end
            bar:SetValue(current)
        else
            self:SetHorizontalScroll(0)
            bar:SetValue(0)
            bar:Hide()
            if bar.ScrollLeftBtn then bar.ScrollLeftBtn:Hide() end
            if bar.ScrollRightBtn then bar.ScrollRightBtn:Hide() end
        end
    end

    return hBar
end

---Update horizontal scrollbar visibility based on content width (call after content changes)
function ns.UI.Factory:UpdateHorizontalScrollBarVisibility(scrollFrame)
    if scrollFrame and scrollFrame.UpdateHorizontalScrollBarVisibility then
        scrollFrame:UpdateHorizontalScrollBarVisibility()
    end
end

---Return current scroll step (pixels per step) computed from base * speed multiplier.
---@return number
function ns.UI_GetScrollStep()
    local addon = _G.WarbandNexus or ns.WarbandNexus
    local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
    local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
    return math.floor(base * speed + 0.5)
end
-- FACTORY PATTERN BRIDGE (ns.UI.Factory.* → Local Functions)
-- Bridge ns.UI.Factory calls to internal functions
-- Ensures PlansUI and other modules can use Factory pattern

--- Create a basic frame container (NO BORDERS by default)
---@return Frame container
function ns.UI.Factory:CreateContainer(parent, width, height, withBorder, globalName)
    if not parent then return nil end
    
    local container = CreateFrame("Frame", globalName, parent)
    container:SetSize(width or 100, height or 100)
    
    -- ONLY apply border if explicitly requested
    if withBorder then
        local shellBg = ResolveSurfaceTierColor("rowOdd")
        ApplyVisuals(container, shellBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end
    
    return container
end

--- Create a button with theme
---@return Button button
function ns.UI.Factory:CreateButton(parent, width, height, noBorder)
    return CreateButton(parent, width, height, nil, nil, noBorder)
end

--- Strip panel backdrop from icon-only row controls (pooled rows may predate transparent noBorder).
function ns.UI.Factory:ApplyIconOnlyButtonChrome(btn)
    if not btn or not btn.SetBackdrop then return end
    pcall(btn.SetBackdrop, btn, nil)
end

--- Create a themed horizontal slider (accent-colored thumb + border).
--- Single source of truth for slider styling; SettingsUI and tracker popups both use this
--- so the look stays consistent and we don't reinvent the widget for each call site.
---@return Slider slider
function ns.UI.Factory:CreateThemedSlider(parent, opts)
    if not parent then return nil end
    opts = opts or {}
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(opts.height or 20)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 0.1)
    slider:SetObeyStepOnDrag(true)

    if slider.SetBackdrop then
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 1, edgeSize = 2,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        local trackBg = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.1, 0.1, 0.12, 1 }
        slider:SetBackdropColor(trackBg[1], trackBg[2], trackBg[3], trackBg[4] or 1)
        local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }
        slider:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
        slider._wnMainShellBackdrop = true
        slider._borderType = "accent"
        slider._borderAlpha = 0.6
        slider._bgType = "controlChromeHover"
        if not slider._borderRegistered and ns.BORDER_REGISTRY then
            slider._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, slider)
        end
    end

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 18)
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }
    thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
    slider:SetThumbTexture(thumb)

    if opts.value ~= nil then slider:SetValue(opts.value) end

    if opts.onChange then
        slider:SetScript("OnValueChanged", function(self, value)
            local step = opts.step or 0.1
            value = math.floor(value / step + 0.5) * step
            if math.abs(self:GetValue() - value) > 0.001 then
                self:SetValue(value)
                return
            end
            opts.onChange(value)
        end)
    end

    return slider
end

--- Create an EditBox
---@return EditBox editbox
function ns.UI.Factory:CreateEditBox(parent)
    if not parent then return nil end
    
    local editBox = CreateFrame("EditBox", nil, parent)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal) -- required initial FontObject (WoW crashes without one)
    if ns.FontManager then
        ns.FontManager:RegisterManagedEditBox(editBox)
        ns.FontManager:ApplyFontToEditBox(editBox)
    end
    editBox:SetMaxLetters(256)
    editBox:SetTextInsets(5, 5, 0, 0)
    
    -- Scripts for better UX
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    return editBox
end

--- Apply alternating row background color to any frame.
--- Central helper that replaces inline ROW_COLOR_EVEN/ODD logic across all tabs.
--- Works with both newly created rows and pooled/reused rows.
function ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    if not row then return end
    local tier = (rowIndex % 2 == 0) and "rowEven" or "rowOdd"
    local bgColor = ResolveSurfaceTierColor(tier)
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor
end

---Apply (or clear) the online-character highlight on a character row or header.
---Uses the live theme accent color so it respects user customization.
function ns.UI.Factory:ApplyOnlineCharacterHighlight(frame, isOnline)
    if not frame then return end
    local ac = COLORS and COLORS.accent or ns.UI_COLORS and ns.UI_COLORS.accent
    if isOnline and ac then
        if not frame.bg then
            frame.bg = frame:CreateTexture(nil, "BACKGROUND")
            frame.bg:SetAllPoints()
        end
        local light = ns.UI_IsLightMode and ns.UI_IsLightMode()
        if light and ns.UI_GetRowSelectionTint then
            local tint = ns.UI_GetRowSelectionTint()
            frame.bg:SetColorTexture(tint[1], tint[2], tint[3], tint[4] or 1)
        else
            local r, g, b = ac[1] * 0.55, ac[2] * 0.55, ac[3] * 0.55
            frame.bg:SetColorTexture(r * 0.4, g * 0.4, b * 0.4, 1)
        end
        if not frame.onlineAccent then
            frame.onlineAccent = frame:CreateTexture(nil, "BORDER")
            frame.onlineAccent:SetWidth(3)
            frame.onlineAccent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.onlineAccent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        frame.onlineAccent:SetColorTexture(ac[1], ac[2], ac[3], light and 0.85 or 1)
        frame.onlineAccent:Show()
    else
        if frame.onlineAccent then frame.onlineAccent:Hide() end
        if frame.bg and frame.bgColor then
            local c = frame.bgColor
            frame.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

--- Create a data row with alternating background color.
--- Standard pattern for creating new rows with proper positioning and alternating bg.
--- For pooled/reused rows, use Factory:ApplyRowBackground() instead.
---@return Frame row, number newYOffset
function ns.UI.Factory:CreateDataRow(parent, yOffset, rowIndex, height)
    if not parent then return nil, yOffset end

    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:Show()

    self:ApplyRowBackground(row, rowIndex)

    return row, yOffset + h
end

--- Create a collapsible section header with border, arrow, title, hover.
--- Uses ApplyVisuals for consistent border rendering (same as CharactersUI/PlansUI headers).
---@return number newYOffset, Frame header
function ns.UI.Factory:CreateSectionHeader(parent, yOffset, isCollapsed, titleStr, rightStr, onToggle, height, leftIndent)
    if not parent then return yOffset, nil end

    local sp = UI_SPACING
    local h = height or sp.SECTION_COLLAPSE_HEADER_HEIGHT or sp.HEADER_HEIGHT
    local indent = leftIndent or 0
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(h)
    header:SetPoint("TOPLEFT", indent, -yOffset)
    header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    -- Draw above virtual-scroll row frames so nothing shows through behind header
    header:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    header:Show()

    local surf = COLORS.surfaceHeaderChrome or COLORS.surfaceElevated or COLORS.bgLight
  -- Opaque background (1.0) so row text does not show through behind header
    local sbr, sbg, sbb, sba = 0.45, 0.45, 0.5, 0.45
    if ns.UI_GetSectionHeaderBorderRGBA then
        sbr, sbg, sbb, sba = ns.UI_GetSectionHeaderBorderRGBA()
    else
        sbr, sbg, sbb = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        sba = 0.45
    end
    ApplyVisuals(header, {surf[1], surf[2], surf[3], 1}, { sbr, sbg, sbb, sba })
    header._wnSectionHeaderBaseBg = {surf[1], surf[2], surf[3], 1}

    if ns.UI_ApplySectionChromeUnderlay then
        ns.UI_ApplySectionChromeUnderlay(header)
    end

    -- Collapse/expand chevron (same control as tab section headers)
    local collapseBtn = ns.UI_CreateCollapseExpandControl(header, not isCollapsed, { enableMouse = true })
    local chevLeft = sp.SECTION_HEADER_FACTORY_CHEVRON_LEFT or 10
    collapseBtn:SetPoint("LEFT", chevLeft + indent, 0)

    -- Title text
    local title = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderTitle"), "OVERLAY")
    title:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    -- Right-side text (optional)
    if rightStr then
        local rightLabel = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderRight"), "OVERLAY")
        rightLabel:SetPoint("RIGHT", header, "RIGHT", -sp.SIDE_MARGIN, 0)
        rightLabel:SetJustifyH("RIGHT")
        rightLabel:SetText(rightStr)
        ns.UI_SetTextColorRole(rightLabel, "Muted")
        title:SetPoint("RIGHT", rightLabel, "LEFT", -6, 0)
    end

    title:SetText(titleStr)
    ns.UI_SetTextColorRole(title, "Bright")

    -- Click handlers
    header:SetScript("OnClick", onToggle)
    collapseBtn:SetScript("OnClick", onToggle)

    -- Hover highlight (token-driven base from `surfaceElevated`)
    header:SetScript("OnEnter", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(
                math.min(1, b[1] * 1.12),
                math.min(1, b[2] * 1.12),
                math.min(1, b[3] * 1.12),
                b[4] or 1
            )
        end
    end)
    header:SetScript("OnLeave", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
        end
    end)

    return yOffset + h, header
end

local COLLECTION_PLAN_SLOT_SIZE = math.floor(19 * 1.25 + 0.5)

local function SetCollectionPlanSlotTooltip(btn, tip)
    if not btn then return end
    local hasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
        and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(tip)
    if not hasTip and type(tip) == "string" and tip ~= "" then
        hasTip = true
    end
    if not hasTip then
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        return
    end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 4, 6)
        GameTooltip:ClearLines()
        local wR, wG, wB = 1, 1, 1
        if type(tip) == "table" then
            if tip.title and tip.title ~= "" then
                GameTooltip:SetText(tip.title, wR, wG, wB)
            end
            local lines = tip.lines
            if type(lines) == "table" then
                for i = 1, #lines do
                    local line = lines[i]
                    if line and line ~= "" then
                        GameTooltip:AddLine(line, wR, wG, wB, true)
                    end
                end
            end
        else
            GameTooltip:SetText(tip, wR, wG, wB)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CreateCollectionPlanSlotButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:Hide()
    b:SetFrameLevel((row:GetFrameLevel() or 0) + 12)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    b._wnIcon = tex
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function EnsureCollectionRowPlanSlotButtons(row)
    if not row then return end
    if row.todoSlotBtn and row.trackSlotBtn then return end
    if row.rowTodoIcon then
        row.rowTodoIcon:Hide()
    end
    if row.rowTrackIcon then
        row.rowTrackIcon:Hide()
    end
    row.todoSlotBtn = row.todoSlotBtn or CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = row.trackSlotBtn or CreateCollectionPlanSlotButton(row)
end

--- Collection list row: status icon (check/cross) + item icon + label. Same layout for Mounts, Pets, Achievements.
--- Caller sets position (virtual scroll). Use ApplyCollectionListRowContent to set content and selection.
---@return Frame row
function ns.UI.Factory:CreateCollectionListRow(parent, height)
    if not parent then return nil end
    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:EnableMouse(true)

    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local collIconScale = 1.25
    local statusSize = math.floor(16 * collIconScale + 0.5)
    local iconSize = math.floor((UI_SPACING.ROW_ICON_SIZE or 20) * collIconScale + 0.5)

    local statusIcon = row:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(statusSize, statusSize)
    statusIcon:SetPoint("LEFT", pad, 0)
    row.statusIcon = statusIcon

    row.todoSlotBtn = CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = CreateCollectionPlanSlotButton(row)

    local iconBorder = self:CreateContainer(row, iconSize, iconSize, true)
    if iconBorder then
        local shellBg = ResolveIconShellBackdrop()
        local bc = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
        if ApplyVisuals then
            ApplyVisuals(iconBorder, shellBg, { bc[1], bc[2], bc[3], 0.72 })
        end
        iconBorder:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        row._iconBorder = iconBorder
    end
    local iconHost = row._iconBorder or row
    local icon = iconHost:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHost, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHost, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local label = FontManager:CreateFontString(row, UIFontRole("factoryDataRowLabel"), "OVERLAY")
    label:SetPoint("LEFT", iconHost, "RIGHT", gap, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local rightLabel = FontManager:CreateFontString(row, UIFontRole("factoryDataRowRight"), "OVERLAY")
    rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    rightLabel:SetJustifyH("RIGHT")
    rightLabel:SetWordWrap(false)
    rightLabel:Hide()
    row.rightLabel = rightLabel

    return row
end

local COLLECTION_ROW_ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local COLLECTION_ROW_ICON_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function CollectionListRowIconHost(row)
    return row._iconBorder or row.icon
end

local function CollectionRowTextLeftX(row, pad, gap, slotGap)
    local x = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    if row.statusIcon and row.statusIcon:IsShown() then
        x = x + (row.statusIcon:GetWidth() or 0) + gap
    end
    if row.todoSlotBtn and row.todoSlotBtn:IsShown() then
        x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        if row.trackSlotBtn and row.trackSlotBtn:IsShown() then
            x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        end
    end
    local iconHost = CollectionListRowIconHost(row)
    if iconHost and iconHost.GetWidth then
        x = x + (iconHost:GetWidth() or 0) + gap
    end
    return x
end

--- Vertically center label (and optional subtitle) in the row; two-line block height never exceeds item icon.
local function LayoutCollectionListRowText(row, pad, gap, slotGap)
    if not row or not row.label then return end
    pad = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    local iconHost = CollectionListRowIconHost(row)
    if not iconHost then return end
    local rowH = row:GetHeight() or (UI_SPACING.ROW_HEIGHT or 32)
    local iconH = iconHost:GetHeight() or 25
    local textX = CollectionRowTextLeftX(row, pad, gap, slotGap)
    local subText = row.subtitle and row.subtitle:GetText()
    local hasSub = row.subtitle and row.subtitle:IsShown()
        and subText and not (issecretvalue and issecretvalue(subText))
        and subText ~= ""
    row.label:ClearAllPoints()
    if hasSub and row.subtitle then
        row.subtitle:ClearAllPoints()
        local lineGap = 2
        local lh = row.label:GetStringHeight() or 12
        local sh = row.subtitle:GetStringHeight() or 10
        local blockH = lh + lineGap + sh
        if blockH > iconH then
            lineGap = 1
            blockH = lh + lineGap + sh
        end
        if blockH > iconH then
            blockH = iconH
            lineGap = math.max(0, blockH - lh - sh)
        end
        local blockTop = (rowH - blockH) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.subtitle:SetJustifyH("LEFT")
        row.subtitle:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
        row.subtitle:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -lineGap)
        if row.rightLabel and row.rightLabel:IsShown() then
            row.subtitle:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
        else
            row.subtitle:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
        end
    else
        local lh = row.label:GetStringHeight() or 12
        local blockTop = (rowH - lh) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
    end
    if row.rightLabel and row.rightLabel:IsShown() then
        row.rightLabel:ClearAllPoints()
        row.rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.label:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
    end
end

--- To-Do / Track column beside collected check (Collections + To-Do browse). `planSlotState` nil = hidden (e.g. Recent cards).
--- planSlotState: `onTodo`, `onTrack`, optional `achievementRow`, `achievementCollected`, optional `showTrackSlot`, optional `onTodoClick` / `onTrackClick` (toggle supported by caller), optional `todoTooltip` / `trackTooltip` (hover; non-interactive slots still show tooltip when text set and mouse enabled).
local function ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    EnsureCollectionRowPlanSlotButtons(row)
    local todoBtn = row.todoSlotBtn
    local trackBtn = row.trackSlotBtn
    local iconHost = row and CollectionListRowIconHost(row)
    local statusIcon = row and row.statusIcon
    if not todoBtn or not trackBtn or not iconHost or not statusIcon then return end
    gap = gap or 4
    slotGap = slotGap or 3
    if not planSlotState then
        todoBtn:Hide()
        trackBtn:Hide()
        todoBtn:SetScript("OnClick", nil)
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(todoBtn, nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        todoBtn:EnableMouse(false)
        trackBtn:EnableMouse(false)
        todoBtn:ClearAllPoints()
        trackBtn:ClearAllPoints()
        iconHost:ClearAllPoints()
        iconHost:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        return
    end
    local onTodo = planSlotState.onTodo == true
    local onTrack = planSlotState.onTrack == true
    local achRow = planSlotState.achievementRow == true
    local achCollected = planSlotState.achievementCollected == true
    local showTrackSlot
    if planSlotState.showTrackSlot == false then
        showTrackSlot = false
    elseif planSlotState.showTrackSlot == true then
        showTrackSlot = true
    else
        showTrackSlot = achRow
    end

    local todoTex = todoBtn._wnIcon
    local trackTex = trackBtn._wnIcon
    if not todoTex or not trackTex then return end

    todoBtn:ClearAllPoints()
    trackBtn:ClearAllPoints()
    todoBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    trackBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    todoBtn:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
    todoBtn:Show()

    local todoDisabled = achCollected == true
    if ns.UI_ApplyWnActionIcon then
        ns.UI_ApplyWnActionIcon(todoTex, "todo", onTodo, todoDisabled)
    else
        ns.UI_SetWnIconTexture(todoTex, "todo", {
            desaturate = todoDisabled,
            vertexColor = ns.UI_WnIconVertexForKey("todo", onTodo, todoDisabled),
        })
    end

    local todoClickable = (type(planSlotState.onTodoClick) == "function") and (onTodo or not achCollected)
    local todoTip = planSlotState.todoTooltip
    local todoHasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
        and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(todoTip)
    if not todoHasTip and type(todoTip) == "string" and todoTip ~= "" then
        todoHasTip = true
    end
    local todoMouse = todoClickable or todoHasTip
    todoBtn:EnableMouse(todoMouse)
    if todoClickable then
        todoBtn:SetScript("OnClick", function()
            planSlotState.onTodoClick()
        end)
    else
        todoBtn:SetScript("OnClick", nil)
    end
    SetCollectionPlanSlotTooltip(todoBtn, todoMouse and todoHasTip and todoTip or nil)

    iconHost:ClearAllPoints()
    if showTrackSlot then
        trackBtn:SetPoint("LEFT", todoBtn, "RIGHT", slotGap, 0)
        trackBtn:Show()
        local trackDisabled = achCollected == true
        if ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(trackTex, "track", onTrack, trackDisabled)
        else
            ns.UI_SetWnIconTexture(trackTex, "track", {
                desaturate = trackDisabled,
                vertexColor = ns.UI_WnIconVertexForKey("track", onTrack, trackDisabled),
            })
        end
        local trackClickable = (type(planSlotState.onTrackClick) == "function") and (not achCollected)
        local trackTip = planSlotState.trackTooltip
        local trackHasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
            and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(trackTip)
        if not trackHasTip and type(trackTip) == "string" and trackTip ~= "" then
            trackHasTip = true
        end
        local trackMouse = trackClickable or trackHasTip
        trackBtn:EnableMouse(trackMouse)
        if trackClickable then
            trackBtn:SetScript("OnClick", function()
                planSlotState.onTrackClick()
            end)
        else
            trackBtn:SetScript("OnClick", nil)
        end
        SetCollectionPlanSlotTooltip(trackBtn, trackMouse and trackHasTip and trackTip or nil)
        iconHost:SetPoint("LEFT", trackBtn, "RIGHT", gap, 0)
    else
        trackBtn:Hide()
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        trackBtn:EnableMouse(false)
        iconHost:SetPoint("LEFT", todoBtn, "RIGHT", gap, 0)
    end
end

--- Apply content and selection to a collection list row (from CreateCollectionListRow). Use for virtual scroll.
function ns.UI.Factory:ApplyCollectionListRowContent(row, rowIndex, iconPath, labelText, isCollected, isSelected, onClick, rightAlignedText, subtitleText, planSlotState)
    if not row then return end
    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local slotGap = 3
    self:ApplyRowBackground(row, rowIndex or 1)
    if row.statusIcon then
        row.statusIcon:SetTexture(isCollected and COLLECTION_ROW_ICON_READY or COLLECTION_ROW_ICON_NOT_READY)
        row.statusIcon:Show()
    end
    if planSlotState and rawget(planSlotState, "achievementCollected") == nil then
        planSlotState.achievementCollected = isCollected == true
    end
    ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    if row.icon then
        local iconTex = (iconPath and iconPath ~= "") and iconPath or "Interface\\Icons\\Achievement_General"
        row.icon:SetTexture(iconTex)
        row.icon:Show()
    end
    local hasSub = subtitleText and subtitleText ~= ""
    if row.label then
        row.label:SetText(labelText or "")
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("MIDDLE")
        row.label:SetWordWrap(false)
    end
    if hasSub then
        if not row.subtitle then
            row.subtitle = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.subtitle:SetJustifyH("LEFT")
            row.subtitle:SetJustifyV("MIDDLE")
            row.subtitle:SetWordWrap(false)
            ns.UI_SetTextColorRole(row.subtitle, "Bright")
        end
        row.subtitle:SetText(subtitleText)
        row.subtitle:Show()
    elseif row.subtitle then
        row.subtitle:SetText("")
        row.subtitle:Hide()
    end
    if row.rightLabel and rightAlignedText and rightAlignedText ~= "" then
        row.rightLabel:SetText(rightAlignedText)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.rightLabel:Show()
    else
        if row.rightLabel then
            row.rightLabel:SetText("")
            row.rightLabel:Hide()
        end
    end
    if row.label and CollectionListRowIconHost(row) then
        LayoutCollectionListRowText(row, pad, gap, slotGap)
    end
    row:SetScript("OnMouseDown", onClick)
    if not row.selBg then
        row.selBg = row:CreateTexture(nil, "BORDER")
        row.selBg:SetAllPoints()
    end
    if isSelected then
        if ns.UI_GetRowSelectionTint then
            local tint = ns.UI_GetRowSelectionTint()
            row.selBg:SetColorTexture(tint[1], tint[2], tint[3], tint[4] or 1)
        else
            local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
            row.selBg:SetColorTexture(r, g, b, 0.25)
        end
        row.selBg:Show()
    else
        row.selBg:Hide()
    end
end

-- WOWHEAD URL COPY POPUP

local wowheadCopyFrame = nil

---Show a small popup with a Wowhead URL for the user to copy (Ctrl+C).
function ns.UI.Factory:ShowWowheadCopyURL(entityType, id, anchorFrame)
    if not ns.Utilities or not ns.Utilities.GetWowheadURL then return end
    local url = ns.Utilities:GetWowheadURL(entityType, id)
    if not url then return end

    if not wowheadCopyFrame then
        local f = CreateFrame("Frame", "WarbandNexus_WowheadCopy", UIParent, "BackdropTemplate")
        f:SetSize(360, 60)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(500)
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        local shellBg = ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop() or { 0.06, 0.06, 0.08, 0.97 }
        f:SetBackdropColor(shellBg[1], shellBg[2], shellBg[3], shellBg[4] or 0.97)
        f._wnMainShellBackdrop = true
        f._borderType = "accent"
        f._borderAlpha = 0.8
        f._bgType = "externalShell"
        if not f._borderRegistered and ns.BORDER_REGISTRY then
            f._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, f)
        end
        local COLORS = ns.UI_COLORS or { accent = {0.5, 0.4, 0.7} }
        f:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = FontManager and FontManager:CreateFontString(f, "small", "OVERLAY") or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if title and not title._wnInkHooked and ns.UI_HookFontStringInk then
            ns.UI_HookFontStringInk(title)
        end
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText(
            ns.UI_GetSemanticGoldHex() .. ((ns.L and ns.L["WOWHEAD_LABEL"]) or "Wowhead") .. "|r  "
            .. (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim") or "|cff888888")
            .. ((ns.L and ns.L["CTRL_C_LABEL"]) or "Ctrl+C") .. "|r"
        )
        f._title = title

        local closeBtn = self:CreateButton(f, 20, 20, true) or CreateFrame("Button", nil, f)
        closeBtn:SetSize(20, 20)
        local closeInset = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL and ns.UI_LAYOUT.MAIN_SHELL.FRAME_CONTENT_INSET) or 2
        closeBtn:SetPoint("TOPRIGHT", -closeInset, -closeInset)
        local closeLbl = FontManager and FontManager:CreateFontString(closeBtn, "body", "OVERLAY") or closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if closeLbl and not closeLbl._wnInkHooked and ns.UI_HookFontStringInk then
            ns.UI_HookFontStringInk(closeLbl)
        end
        closeLbl:SetPoint("CENTER")
        closeLbl:SetText("x")
        ns.UI_SetTextColorRole(closeLbl, "Bright")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local editBox = self:CreateEditBox(f) or CreateFrame("EditBox", nil, f)
        editBox:SetSize(336, 22)
        editBox:SetPoint("BOTTOMLEFT", 12, 8)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(512)
        if FontManager then
            FontManager:RegisterManagedEditBox(editBox)
            FontManager:ApplyFontToEditBox(editBox)
        end
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        editBox:SetScript("OnChar", function(self) self:SetText(f._url or ""); self:HighlightText() end)
        f._editBox = editBox

        wowheadCopyFrame = f
    end

    wowheadCopyFrame._url = url
    wowheadCopyFrame._editBox:SetText(url)

    if anchorFrame and anchorFrame.GetCenter then
        wowheadCopyFrame:ClearAllPoints()
        wowheadCopyFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
    else
        wowheadCopyFrame:ClearAllPoints()
        wowheadCopyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end

    wowheadCopyFrame:Show()
    wowheadCopyFrame._editBox:SetFocus()
    wowheadCopyFrame._editBox:HighlightText()
end

-- Load message
-- Factory loaded - verbose logging hidden (debug mode only)
assert(ns.UI.Factory and ns.UI.Factory.CreateContainer, "SharedWidgets_Factory: methods missing")
