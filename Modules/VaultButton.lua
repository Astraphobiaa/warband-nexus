--[[ Warband Nexus - Easy Access - VaultButton.lua entry ]]

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
--[[ Entry chunk: bare names resolve via M (see VaultButton_Core.lua). Use M.EA_CAT_TIP etc. for shared tables. ]]

-- Easy Access shortcut menu (layout: M.VBGetEasyAccessMenuLayout in VaultButton_Core.lua)

function M.CountMenuSummaryLines()
    local n = 1
    if ShowEasyAccessDisplay("menuVault") then
        n = n + #GetEnabledCategoryDefs() + 1
    end
    if ShowEasyAccessDisplay("menuKeystone") then
        n = n + 1
    end
    if ShowEasyAccessDisplay("menuMythicScore") then
        n = n + 1
    end
    return n
end

function M.GetMenuSummaryHeight()
    return VBGetEasyAccessMenuSummaryHeight(CountMenuSummaryLines())
end

function M.RefreshMenuVaultSummary(menuFrame)
    if not menuFrame or not menuFrame.eaSummaryRows then return end
    local charKey = GetCurrentCharKey()
    local chars = GetCharacters()
    local charRow = charKey and chars and chars[charKey]
    local rows = menuFrame.eaSummaryRows
    local summaryH = GetMenuSummaryHeight()
    if menuFrame.eaSummaryPanel then
        menuFrame.eaSummaryPanel:SetShown(summaryH > 0)
        menuFrame.eaSummaryPanel:SetHeight(math.max(summaryH, 1))
    end
    if menuFrame.eaSummarySep then
        menuFrame.eaSummarySep:SetShown(summaryH > 0)
    end
    if menuFrame.menuItems then
        local lay = menuFrame._eaMenuLayout or VBGetEasyAccessMenuLayout()
        local itemCount = #menuFrame.menuItems
        menuFrame:SetHeight(VBComputeEasyAccessMenuHeight(lay, itemCount, summaryH))
    end
    if summaryH <= 0 then
        return
    end
    if not charRow or not charKey then
        rows.title:SetText("|cff888888" .. EAL("EA_TOOLTIP_NO_CHAR", "No character data yet.") .. "|r")
        for i = 2, #rows do
            if rows[i] then rows[i]:SetText("") end
        end
        return
    end
    local classHex = GetClassHex(charRow.classFile)
    local ilvl = charRow.itemLevel or 0
    local ilvlText = ilvl > 0 and ("  |cffffd700" .. ((ns.L and ns.L["ILVL_SHORT"]) or "iLvl") .. " " .. string.format("%.0f", ilvl) .. "|r") or ""
    rows.title:SetText("|cff" .. classHex .. (charRow.name or "?") .. "|r" .. ilvlText)

    local settings = GetSettings()
    local isReady, isPending, slotsEarned = ResolveVaultTooltipFlags(charKey, nil)
    local shiftHeld = IsShiftKeyDown and IsShiftKeyDown() or false
    local lineIndex = 2

    if ShowEasyAccessDisplay("menuVault") then
        local catDefs = GetEnabledCategoryDefs()
        for ci = 1, #catDefs do
            local fs = rows[lineIndex]
            if fs then
                local cat = catDefs[ci]
                local tipMeta = M.EA_CAT_TIP[cat.key]
                local slots = GetSlotData(charKey, cat.key)
                local label = EAL(tipMeta and tipMeta.key or "EA_TOOLTIP_CAT_RAID", tipMeta and tipMeta.fallback or cat.label)
                local right = ns.VaultFormatCategoryColumn(slots, cat.key, {
                    shiftHeld = shiftHeld,
                    showRewardProgress = settings.showRewardProgress,
                    showRewardItemLevel = settings.showRewardItemLevel,
                    vaultLootClaimable = isReady,
                })
                fs:SetText((ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. label .. ":|r " .. right)
            end
            lineIndex = lineIndex + 1
        end
        local statusFS = rows[lineIndex]
        if statusFS then
            local statusText
            if isReady then
                statusText = "|cff44ff44" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_READY", "Ready to claim") .. "|r"
            elseif slotsEarned and slotsEarned > 0 then
                statusText = "|cff66ddff" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_SLOTS", "%d slot(s) earned", slotsEarned) .. "|r"
            elseif isPending then
                statusText = "|cffffd700" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_PROGRESS", "In progress") .. "|r"
            elseif not CharHasVaultSnapshot(charKey) then
                statusText = "|cff888888" .. EAL("EA_TOOLTIP_NO_CHAR_VAULT", "No vault data for this character yet. Open the Great Vault once.") .. "|r"
            else
                statusText = "|cff888888-|r"
            end
            statusFS:SetText((ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. EAL("EA_TOOLTIP_SECTION_VAULT", "Great Vault") .. ":|r " .. statusText)
        end
        lineIndex = lineIndex + 1
    end

    if ShowEasyAccessDisplay("menuKeystone") then
        local fs = rows[lineIndex]
        if fs then
            fs:SetText((ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. EAL("EA_TOOLTIP_KEYSTONE_LABEL", "Keystone") .. ":|r "
                .. FormatKeystoneTooltipRight(charKey, charRow))
        end
        lineIndex = lineIndex + 1
    end

    if ShowEasyAccessDisplay("menuMythicScore") then
        local fs = rows[lineIndex]
        if fs then
            fs:SetText((ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. EAL("EA_TOOLTIP_MYTHIC_SCORE_LABEL", "M+ Rating") .. ":|r "
                .. FormatMythicScoreTooltipRight(charKey))
        end
        lineIndex = lineIndex + 1
    end

    for ri = lineIndex, #rows do
        if rows[ri] then rows[ri]:SetText("") end
    end
end

function M.CreateMenuItem(parent, opts, y)
    local lay = parent._eaMenuLayout or VBGetEasyAccessMenuLayout()
    local btnW = math.max(1, (parent:GetWidth() or lay.width) - (lay.contentPadH * 2))
    local btn = M.VBButton(parent, btnW, lay.rowH, true)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", lay.contentPadH, y)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or {0.40, 0.20, 0.58}
    if M.VBIsClassicChrome and M.VBIsClassicChrome() then
        hl:SetColorTexture(1, 1, 1, 0.10)
    else
        hl:SetColorTexture(accent[1], accent[2], accent[3], 0.25)
    end

    local MENU_ICON_SIZE = lay.iconSize or 20
    local hasIcon = opts.iconAtlas or opts.icon
    if hasIcon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(MENU_ICON_SIZE, MENU_ICON_SIZE)
        icon:SetPoint("LEFT", lay.innerPad, 0)
        if opts.iconAtlas and icon.SetAtlas then
            icon:SetTexture(nil)
            local ok = pcall(icon.SetAtlas, icon, opts.iconAtlas, false)
            if not ok and opts.icon then
                icon:SetTexture(opts.icon)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        elseif opts.icon then
            icon:SetTexture(opts.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local FontManager = ns.FontManager
    local label
    if FontManager and FontManager.CreateFontString then
        label = FontManager:CreateFontString(btn, "body", "OVERLAY")
    else
        label = VBFontString(btn, "body")
    end
    local labelLeft = lay.innerPad
    if hasIcon then
        labelLeft = lay.innerPad + MENU_ICON_SIZE + (lay.iconLabelGap or 6)
    end
    label:SetPoint("LEFT", labelLeft, 0)
    label:SetText(opts.label)
    ns.UI_SetTextColorRole(label, "Bright")

    -- Left-click indicator (larger than legacy GameFont "*" glyph)
    local STAR_SIZE = 18
    local star = btn:CreateTexture(nil, "OVERLAY")
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetPoint("RIGHT", btn, "RIGHT", -lay.innerPad, 0)
    star:Hide()
    if star.SetAtlas then
        local ok = pcall(star.SetAtlas, star, "PetJournal-FavoritesIcon", false)
        if ok then
            star:SetVertexColor(1, 0.9, 0.2)
        else
            star:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        end
    else
        star:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
    end
    btn.selectionStar = star
    btn.leftClickAction = opts.leftClickAction

    btn.RefreshSelection = function(self)
        local selected = self.leftClickAction and GetSettings().leftClickAction == self.leftClickAction
        if self.selectionStar then
            self.selectionStar:SetShown(selected == true)
        end
    end
    btn:RefreshSelection()

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self.leftClickAction then
            GetSettings().leftClickAction = self.leftClickAction
            if S.menuFrame then
                S.menuFrame.leftClickAction = self.leftClickAction
                for _, row in ipairs(S.menuFrame.menuItems or {}) do
                    if row.RefreshSelection then row:RefreshSelection() end
                end
            end
            return
        end
        HideMenu()
        if opts.action then opts.action() end
    end)
    return btn
end

function M.BuildMenu()
    if S.menuFrame and (S.menuFrame._eaMenuLayoutVersion or 0) >= M.EA_MENU_LAYOUT_VERSION then
        return
    end
    if S.menuFrame then
        S.menuFrame:Hide()
        S.menuFrame = nil
    end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local GetTabIcon = ns.UI_GetTabIcon
    local tabIcon = function(key)
        return (GetTabIcon and GetTabIcon(key)) or nil
    end

    local items = {}
    local menuOrder = M.LAUNCHER_MENU_ORDER or {}
    for mi = 1, #menuOrder do
        local actionId = menuOrder[mi]
        local def = M.LAUNCHER_ACTION_DEFS[actionId]
        if def then
            local iconTab = def.iconTab
            local opt = {
                label = GetLauncherActionLabel(actionId),
                iconAtlas = def.iconAtlas or (iconTab and tabIcon(iconTab)) or nil,
                icon = def.icon,
                action = (function(capturedActionId)
                    return function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        RunLauncherAction(capturedActionId, S.button)
                    end
                end)(actionId),
            }
            if def.menuLeftClick ~= false then
                opt.leftClickAction = actionId
            end
            items[#items + 1] = opt
        end
    end

    local lay = VBGetEasyAccessMenuLayout()
    local summaryH = GetMenuSummaryHeight()
    local H = VBComputeEasyAccessMenuHeight(lay, #items, summaryH)

    local f = M.VBContainer(UIParent, lay.width, H, false, "WarbandNexusVaultMenu")
    AddEscCloseFrame("WarbandNexusVaultMenu")
    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(f)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(f)
    end
    f:SetSize(lay.width, H)
    f._eaMenuLayout = lay
    f._eaMenuLayoutVersion = lay.version
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(220)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if M.VBApplyEasyAccessShell then
        M.VBApplyEasyAccessShell(f)
    elseif ns.UI_ApplyFloatingWindowShellChrome then
        ns.UI_ApplyFloatingWindowShellChrome(f)
    elseif ns.UI_ApplyStandardCardElevatedChrome and not (M.VBIsClassicChrome and M.VBIsClassicChrome()) then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, GetShellBackdrop(), {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()
    f.leftClickAction = GetSettings().leftClickAction

    -- Header band (symmetric shell inset)
    local header = M.VBContainer(f, 1, lay.headerH, false)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", lay.inset, -lay.inset)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -lay.inset, -lay.inset)
    if M.VBApplyEasyAccessHeader then
        M.VBApplyEasyAccessHeader(header)
    elseif ns.UI_ApplyFloatingWindowHeaderChrome then
        ns.UI_ApplyFloatingWindowHeaderChrome(header)
    elseif ApplyVisuals then
        ApplyVisuals(header, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end
    header:EnableMouse(true)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if ns.UI_GameTooltipAddRoleLine then
            ns.UI_GameTooltipAddRoleLine(GameTooltip, (ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access", "Bright")
        else
            GameTooltip:AddLine((ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access", 1, 1, 1)
        end
        local mr, mg, mb = 0.85, 0.85, 0.85
        GameTooltip:AddLine(EAL("EA_MENU_TOOLTIP_STAR", "Star marks your left-click action."), mr, mg, mb, true)
        GameTooltip:AddLine(EAL("EA_MENU_TOOLTIP_SET_ACTION", "Right-click a menu item to set the left-click action."), mr, mg, mb, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(16, 16)
    headerIcon:SetPoint("LEFT", lay.innerPad, 0)
    headerIcon:SetTexture(ICON_TEXTURE)
    if not headerIcon:GetTexture() then
        headerIcon:SetTexture(ICON_FALLBACK)
        headerIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    else
        headerIcon:SetTexCoord(0, 1, 0, 1)
    end

    local FontManager = ns.FontManager
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        titleFS = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        titleFS = VBFontString(header, "small")
    end
    titleFS:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
    titleFS:SetText((ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access")
    ns.UI_SetTextColorRole(titleFS, "Bright")

    f.eaSummaryPanel = nil
    f.eaSummarySep = nil
    f.eaSummaryRows = {}
    if summaryH > 0 then
        local summaryTopY = -(lay.inset + lay.headerH + lay.sectionGap)
        local summaryPanel = M.VBContainer(f, 1, summaryH, false)
        summaryPanel:SetPoint("TOPLEFT", f, "TOPLEFT", lay.inset, summaryTopY)
        summaryPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -lay.inset, summaryTopY)
        if M.VBIsClassicChrome and M.VBIsClassicChrome() then
            if ns.UI_ApplyClassicCardPanelChrome then
                ns.UI_ApplyClassicCardPanelChrome(summaryPanel)
            end
        elseif ApplyVisuals then
            ApplyVisuals(summaryPanel, { (COLORS.bgCard or COLORS.bgLight or COLORS.bg)[1], (COLORS.bgCard or COLORS.bgLight or COLORS.bg)[2], (COLORS.bgCard or COLORS.bgLight or COLORS.bg)[3], 0.95 }, {accent[1], accent[2], accent[3], 0.35})
        end
        f.eaSummaryPanel = summaryPanel
        local summaryTitle = VBFontString(summaryPanel, "body")
        summaryTitle:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", lay.summaryInnerPad, -lay.summaryTitleTop)
        summaryTitle:SetPoint("TOPRIGHT", summaryPanel, "TOPRIGHT", -lay.summaryInnerPad, -lay.summaryTitleTop)
        summaryTitle:SetJustifyH("LEFT")
        summaryTitle:SetHeight(lay.summaryTitleH)
        f.eaSummaryRows.title = summaryTitle
        local bodyTop = lay.summaryTitleTop + lay.summaryTitleH + lay.sectionGap
        for si = 1, M.EA_MENU_SUMMARY_MAX_LINES - 1 do
            local lineFS = VBFontString(summaryPanel, "small")
            local lineY = -(bodyTop + (si - 1) * lay.summaryLineH)
            lineFS:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", lay.summaryInnerPad, lineY)
            lineFS:SetPoint("TOPRIGHT", summaryPanel, "TOPRIGHT", -lay.summaryInnerPad, lineY)
            lineFS:SetJustifyH("LEFT")
            lineFS:SetHeight(lay.summaryLineH)
            f.eaSummaryRows[si + 1] = lineFS
        end

        local sepY = summaryTopY - summaryH
        if M.VBCreateEasyAccessSeparator then
            f.eaSummarySep = M.VBCreateEasyAccessSeparator(f, lay.inset, lay.inset, sepY)
        else
            local summarySep = f:CreateTexture(nil, "BORDER")
            summarySep:SetHeight(1)
            summarySep:SetPoint("TOPLEFT", f, "TOPLEFT", lay.inset, sepY)
            summarySep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -lay.inset, sepY)
            if M.VBIsClassicChrome and M.VBIsClassicChrome() then
                local bc = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border) or { 0.55, 0.48, 0.35, 1 }
                summarySep:SetColorTexture(bc[1], bc[2], bc[3], 0.65)
            else
                summarySep:SetColorTexture(accent[1], accent[2], accent[3], 0.45)
            end
            f.eaSummarySep = summarySep
        end
    end
    RefreshMenuVaultSummary(f)

    local listTopY = -(lay.inset + lay.headerH + lay.sectionGap + summaryH + (summaryH > 0 and lay.sectionGap or 0))
    f.menuItems = {}
    local rowY = listTopY
    for _, opt in ipairs(items) do
        local row = CreateMenuItem(f, opt, rowY)
        table.insert(f.menuItems, row)
        rowY = rowY - (lay.rowH + lay.rowGap)
    end

    -- Auto-hide on focus loss: close when mouse leaves and not over a child (OnUpdate only while menu is shown).
    f:SetScript("OnShow", function(self)
        self._hideElapsed = 0
        self:SetScript("OnUpdate", function(frame, elapsed)
            elapsed = elapsed or 0
            if frame:IsMouseOver() then
                frame._hideElapsed = 0
            else
                frame._hideElapsed = (frame._hideElapsed or 0) + elapsed
                if frame._hideElapsed > 2.5 then
                    frame:Hide()
                end
            end
        end)
    end)
    f:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self._hideElapsed = 0
    end)

    S.menuFrame = f
end

local ToggleMenu = function(anchor, atCursor)
    local leftClickAction = GetSettings().leftClickAction
    if S.menuFrame and S.menuFrame.leftClickAction ~= leftClickAction then
        S.menuFrame:Hide()
        S.menuFrame = nil
    end
    BuildMenu()
    if not S.menuFrame then return end
    if S.menuFrame:IsShown() and not atCursor then
        S.menuFrame:Hide()
        return
    end
    S.menuFrame:ClearAllPoints()
    if atCursor then
        local scale = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        x = (x or 0) / scale
        y = (y or 0) / scale

        local mw = S.menuFrame:GetWidth() or 200
        local mh = S.menuFrame:GetHeight() or 200
        local screenW = UIParent:GetWidth() or 1920
        local screenH = UIParent:GetHeight() or 1080
        local gap = 8

        x = math.max(gap, math.min(x + gap, screenW - mw - gap))
        y = math.max(mh + gap, math.min(y - gap, screenH - gap))
        S.menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        anchor = anchor or S.button
        if anchor then
            -- Anchor menu beside the button (never on top of it). Pick the side with the most room.
            local mw = S.menuFrame:GetWidth() or 200
            local mh = S.menuFrame:GetHeight() or 200
            local screenW = UIParent:GetWidth() or 1920
            local screenH = UIParent:GetHeight() or 1080
            local left   = anchor:GetLeft()   or 0
            local right  = anchor:GetRight()  or 0
            local top    = anchor:GetTop()    or 0
            local bottom = anchor:GetBottom() or 0
            local roomLeft   = left
            local roomRight  = screenW - right
            local roomBottom = bottom
            local gap = 6

            -- Prefer horizontal placement (looks more like a context menu)
            if roomRight >= mw + gap then
                -- Place to the RIGHT of the button
                local dy = (top - mh < 0) and (mh - (top - bottom)) or 0
                S.menuFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, dy)
            elseif roomLeft >= mw + gap then
                -- Place to the LEFT of the button
                local dy = (top - mh < 0) and (mh - (top - bottom)) or 0
                S.menuFrame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, dy)
            elseif roomBottom >= mh + gap then
                -- Place BELOW the button
                S.menuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
            else
                -- Place ABOVE the button
                S.menuFrame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
            end
        else
            S.menuFrame:SetPoint("CENTER")
        end
    end
    S.menuFrame._hideElapsed = 0
    RefreshMenuVaultSummary(S.menuFrame)
    S.menuFrame:Show()
end

function WarbandNexus:OpenVaultButtonQuickMenu(anchor)
    ToggleMenu(anchor or S.button)
end

function WarbandNexus:OpenVaultButtonQuickMenuAtCursor()
    ToggleMenu(nil, true)
end

function M.RunLeftClickAction(anchor)
    RunLauncherAction(GetSettings().leftClickAction, anchor)
end

function WarbandNexus:RunLauncherAction(action, anchor)
    if M.RunLauncherAction then
        M.RunLauncherAction(action, anchor)
    end
end

local RefreshButtonSettings = function()
    local tableWasShown = S.tableFrame and S.tableFrame:IsShown()
    if S.optionsFrame then
        if S.optionsFrame.RefreshValues then
            S.optionsFrame:RefreshValues()
        end
    end
    if S.menuFrame then
        S.menuFrame:Hide()
        S.menuFrame = nil
    end
    ApplyTheme()
    ApplyButtonVisibility(false)
    if tableWasShown and S.button and S.button:IsShown() then
        RefreshTable()
    end
end

function M.BuildButton()
    if S.button then return end

    local btn = CreateFrame("Button", "WarbandNexusVaultButton", UIParent, "BackdropTemplate")
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetClampedToScreen(true)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(50)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Borderless floater: transparent hit target; logo fills the full button.
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    btn:SetBackdropColor(0, 0, 0, 0)
    S.border = btn  -- backwards-compat: badge/theme hooks

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false) end
    if icon.SetTexelSnappingBias then icon:SetTexelSnappingBias(0) end
    icon:SetTexture(ICON_TEXTURE)
    if not icon:GetTexture() then
        icon:SetTexture(ICON_FALLBACK)
        icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)  -- Blizzard inventory icons: slight inset
    else
        icon:SetTexCoord(0, 1, 0, 1) -- packaged square `Media/icon.tga`: full UV (inset distorted the glyph)
    end
    S.icon = icon

    local badgeBg = btn:CreateTexture(nil, "OVERLAY")
    badgeBg:SetSize(BADGE_SIZE, BADGE_SIZE)
    badgeBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
    badgeBg:SetColorTexture(0.15, 0.75, 0.25, 1.0)
    badgeBg:Hide()
    badgeBg:EnableMouse(true)
    S.badgeBg = badgeBg

    local badge = VBFontString(btn, "small")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("CENTER", badgeBg, "CENTER", 0, 0)
    badge:SetJustifyH("CENTER")
    badge:SetJustifyV("MIDDLE")
    ns.UI_SetTextColorRole(badge, "Bright")
    badge:Hide()
    badge:EnableMouse(true)
    S.badge = badge

    local dragged = false

    -- Polled hover detection (OnEnter/OnLeave can flicker when alpha=0 with hideUntilMouseover,
    -- and Blizzard mouse events don't always fire reliably for low-alpha frames). Throttled to
    -- 100ms to keep cost trivial.
    btn._hoverPoll = 0
    btn._hovering  = false
    btn:SetScript("OnUpdate", function(self, elapsed)
        self._hoverPoll = (self._hoverPoll or 0) + elapsed
        if self._hoverPoll < 0.1 then return end
        self._hoverPoll = 0
        local overBadge = false
        if S.badgeBg and S.badgeBg:IsShown() then
            overBadge = S.badgeBg:IsMouseOver() or (S.badge and S.badge:IsMouseOver())
        end
        if overBadge then
            if not self._hoveringBadge then
                self._hoveringBadge = true
                self._hovering = false
                WNTooltipHide()
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                if M.ShowBadgeTooltip then
                    M.ShowBadgeTooltip(S.badgeBg)
                end
            end
            return
        elseif self._hoveringBadge then
            self._hoveringBadge = false
            WNTooltipHide()
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end
        local over = self:IsMouseOver() and self:IsVisible()
        -- Suppress tooltip while the context menu is open to prevent overlap
        local menuOpen = S.menuFrame and S.menuFrame:IsShown()
        if over ~= self._hovering then
            self._hovering = over
            if over and not menuOpen then
                ApplyButtonVisibility(true)
                ShowHoverTooltip(self)
            else
                WNTooltipHide()
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                if not over then
                    S.eaTooltipHover.anchor = nil
                    S.eaTooltipHover.charKey = nil
                    S.eaTooltipHover.entry = nil
                    ApplyButtonVisibility(false)
                end
            end
        elseif over and menuOpen then
            -- Menu opened while hovering — hide tooltip immediately
            WNTooltipHide()
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        dragged = true
        HideTable()
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SavePos(point, relativePoint, x, y)
        C_Timer.After(0.05, function() dragged = false end)
    end)
    btn:SetScript("OnClick", function(self, mouseButton)
        if dragged then return end
        -- Always hide tooltip on any click to prevent overlap with menu
        WNTooltipHide()
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            ToggleMenu(self)
        else
            HideMenu()
            RunLeftClickAction(self)
        end
    end)

    local pos = GetSavedPos()
    btn:ClearAllPoints()
    if pos and pos.x and pos.y then
        btn:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x, pos.y)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", 600, 0)
    end

    S.button = btn
    ApplyTheme()
    ApplyButtonVisibility(false)
    UpdateBadge()
end

-- Events
local eFrame = CreateFrame("Frame")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(2, function() BuildButton(); UpdateBadge() end)
end)

-- Coalesce burst of cache messages (PVE_UPDATED + CHARACTER_UPDATED + VAULT_* often fire in
-- the same frame) into a single redraw. Without this, each open Saved Instances toggle would
-- rebuild its rows up to four times per cache wave.
local pendingDataRefresh = false
function M.ScheduleDataRefresh()
    if M.UpdateBadge then
        M.UpdateBadge()
    elseif UpdateBadge then
        UpdateBadge()
    end
    if pendingDataRefresh then return end
    pendingDataRefresh = true
    C_Timer.After(0.1, function()
        pendingDataRefresh = false
        if M.UpdateBadge then
            M.UpdateBadge()
        elseif UpdateBadge then
            UpdateBadge()
        end
        if S.tableFrame and S.tableFrame:IsShown() then
            RefreshTable()
        end
        if S.savedFrame and S.savedFrame:IsShown() then
            RefreshSavedInstances()
        end
    end)
end

local OnDataChanged = ScheduleDataRefresh

function M.HookWNMessages()
    if not WarbandNexus or not WarbandNexus.RegisterMessage then return end
    local E = ns.Constants and ns.Constants.EVENTS
    if not E then return end
    local VBListeners = M._msgListeners or {}
    M._msgListeners = VBListeners
    if E.PVE_UPDATED then
        WarbandNexus.RegisterMessage(VBListeners, E.PVE_UPDATED, OnDataChanged)
    end
    if E.CHARACTER_UPDATED then
        WarbandNexus.RegisterMessage(VBListeners, E.CHARACTER_UPDATED, OnDataChanged)
    end
    if E.VAULT_REWARD_AVAILABLE then
        WarbandNexus.RegisterMessage(VBListeners, E.VAULT_REWARD_AVAILABLE, OnDataChanged)
    end
    if E.VAULT_SLOT_COMPLETED then
        WarbandNexus.RegisterMessage(VBListeners, E.VAULT_SLOT_COMPLETED, OnDataChanged)
    end
    if E.CURRENCY_UPDATED then
        WarbandNexus.RegisterMessage(VBListeners, E.CURRENCY_UPDATED, OnDataChanged)
    end
end

function WarbandNexus:RefreshVaultButtonSettings()
    if not S.button then
        BuildButton()
    end
    RebuildTableFrame()
    RefreshButtonSettings()
    UpdateBadge()
end

function WarbandNexus:RefreshVaultEasyAccessTheme()
    if M.ApplyTheme then
        M.ApplyTheme()
    end
    -- Rebuild quick menu on next open so shell/header/summary pick up classic vs modern chrome.
    if S.menuFrame then
        S.menuFrame:Hide()
        S.menuFrame = nil
    end
    local refreshShell = M.VBApplyEasyAccessShell or ns.UI_ApplyFloatingWindowShellChrome or ns.UI_ApplyStandardCardElevatedChrome
    if not refreshShell then return end
    if S.tableFrame and S.tableFrame:IsShown() then
        refreshShell(S.tableFrame)
    end
    if S.optionsFrame and S.optionsFrame:IsShown() then
        refreshShell(S.optionsFrame)
    end
    if S.savedFrame and S.savedFrame:IsShown() then
        refreshShell(S.savedFrame)
    end
end

function WarbandNexus:SetVaultButtonEnabled(enabled)
    GetSettings().enabled = enabled and true or false
    self:RefreshVaultButtonSettings()
end

--- Public toggle for the Vault Tracker quick window (used by /wn vt and the
--- minimap context menu).
function WarbandNexus:ToggleVaultTrackerWindow()
    if S.tableFrame and S.tableFrame:IsShown() then
        if HideTable then HideTable() end
        return
    end
    if RefreshTable then
        RefreshTable()
        if S.tableFrame and not S.tableFrame:GetPoint() then
            S.tableFrame:ClearAllPoints()
            S.tableFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
end

--- Public toggle for the Saved Instances window.
function WarbandNexus:ToggleSavedInstancesWindow()
    if ToggleSavedInstances then ToggleSavedInstances() end
end

--- Get vault status for a character (used by PvE tab Status column + Vault Tracker).
--- Logic:
---   * Logged-in char: prefer live `C_WeeklyRewards.HasAvailableRewards()` so post-reset
---     carry-over chests show Ready immediately (matches the Great Vault\226\128\153s own prompt).
---     When the player claims, WEEKLY_REWARDS_ITEM_CHANGED clears the cache automatically.
---   * Other chars: cached `hasAvailableRewards` is authoritative when true; if it's false
---     but the char had completed slots AND weekly reset has crossed, auto-flip to Ready
---     (those slots are now a sitting chest \226\128\148 they\226\128\153ll log in to claim).
--- Returns: { isReady, isPending, readySlots } or nil when there's no progress to show.
function WarbandNexus:GetVaultStatusForChar(charKey)
    if not charKey then return nil end
    local isReady = ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey) or false
    local currentKey = GetCurrentCharKey()
    if not isReady and currentKey and CharKeysMatch(charKey, currentKey)
        and WarbandNexus.HealStaleVaultRewardsCache then
        WarbandNexus:HealStaleVaultRewardsCache(charKey)
        isReady = ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey) or false
    end

    local claimedThisWeek = false
    local pveCache = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache
    local rewardData = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
        and LookupPveCacheSubtable(pveCache.greatVault.rewards, charKey)
    if rewardData and ns.VaultRewardsClaimedForCurrentWeek then
        claimedThisWeek = ns.VaultRewardsClaimedForCurrentWeek(rewardData) == true
    end

    local readySlots = CountReadySlots(charKey) or 0
    local hasProg = readySlots > 0 or HasAnyProgress(charKey)
    if not isReady and not hasProg then return nil end
    return {
        isReady         = isReady,
        isPending       = not isReady and hasProg and not claimedThisWeek,
        readySlots      = readySlots,
        claimedThisWeek = claimedThisWeek,
    }
end

function M.HookThemeRefresh()
    if ns._vaultButtonThemeRefreshHooked or not ns.UI_RefreshColors then return end
    ns._vaultButtonThemeRefreshHooked = true
    local originalRefreshColors = ns.UI_RefreshColors
    ns.UI_RefreshColors = function(...)
        originalRefreshColors(...)
        ApplyTheme()
        RefreshButtonSettings()
    end
end

local hFrame = CreateFrame("Frame")
hFrame:RegisterEvent("ADDON_LOADED")
hFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "WarbandNexus" then
        HookThemeRefresh()
        C_Timer.After(1, HookWNMessages)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

