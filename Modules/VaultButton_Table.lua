--[[ Warband Nexus - Easy Access - VaultButton_Table.lua ]]

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
--[[ Shared API: M.* / S.* only across VaultButton_* chunks (see VaultButton_Core.lua). ]]
function M.ReleaseSavedInstanceRows()
    if not S.savedRows then
        S.savedRows = {}
        return
    end

    local bin = ns.UI_RecycleBin
    for i = 1, #S.savedRows do
        local row = S.savedRows[i]
        if row then
            if row.SetScript then
                pcall(row.SetScript, row, "OnClick", nil)
                pcall(row.SetScript, row, "OnEnter", nil)
                pcall(row.SetScript, row, "OnLeave", nil)
                pcall(row.SetScript, row, "OnMouseWheel", nil)
            end
            if row.Hide then pcall(row.Hide, row) end
            if row.ClearAllPoints then pcall(row.ClearAllPoints, row) end
            if row.SetParent then
                pcall(row.SetParent, row, bin or nil)
            end
        end
    end
    S.savedRows = {}
end

function M.AddEscCloseFrame(frameName)
    if not frameName or not UISpecialFrames then return end
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

local RebuildTableFrame = function()
    local wasShown = S.tableFrame and S.tableFrame:IsShown()
    if wasShown and S.tableFrame then
        savedPoint, _, savedRelativePoint, savedX, savedY = S.tableFrame:GetPoint()
    end
    if S.tableFrame then
        S.tableFrame:Hide()
        S.tableFrame = nil
        S.tableScroll = nil
        S.tableContent = nil
        S.title = nil
        S.headerBg = nil
        S.separator = nil
        S.rows = {}
    end
    if wasShown then
        if savedX and savedY then
            SaveTablePos(savedPoint, savedRelativePoint, savedX, savedY)
        end
        C_Timer.After(0, function()
            RefreshTable()
            if S.tableFrame then
                S.tableFrame:ClearAllPoints()
                local saved = GetSavedTablePos()
                if saved and saved.x and saved.y then
                    S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
                end
            end
        end)
    end
    return wasShown
end

function M.ApplyTheme()
    if M.SyncEasyAccessThemeInk then
        M.SyncEasyAccessThemeInk()
    end
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    local accentDark = colors.accentDark or {0.28, 0.14, 0.41}
    local border = colors.border or accent

    if S.button and S.button.BorderTop then
        local VF = ns.UI.Factory
        local readyCount = CountReady()
        local r, g, b, a
        if readyCount > 0 then
            r, g, b, a = accent[1], accent[2], accent[3], 1
        else
            r, g, b, a = border[1], border[2], border[3], 0.85
        end
        if VF and VF.UpdateBorderColor then
            VF:UpdateBorderColor(S.button, {r, g, b, a})
        end
    end
    if S.badgeBg then
        S.badgeBg:SetColorTexture(accent[1], accent[2], accent[3], 1)
    end
    -- tableFrame / chrome / optionsFrame border colors auto-update via ns.BORDER_REGISTRY
    if S.separator then
        if S.separator._wnClassicRailDivider and S.separator.Hide then
            if M.VBIsClassicChrome and M.VBIsClassicChrome() then
                S.separator:Show()
            else
                S.separator:Hide()
            end
        elseif S.separator.SetColorTexture then
            S.separator:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
        end
    end
    if S.headerBg and M.VBApplyEasyAccessHeader then
        M.VBApplyEasyAccessHeader(S.headerBg)
    end
    if S.optionsFrame then
        if S.optionsFrame.columnLabel then
            if ns.UI_SetInkColor then
                ns.UI_SetInkColor(S.optionsFrame.columnLabel, accent[1], accent[2], accent[3], 1)
            else
                S.optionsFrame.columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
            end
        end
        if S.optionsFrame.opacitySlider then
            local thumb = S.optionsFrame.opacitySlider:GetThumbTexture()
            if thumb then
                thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
            end
        end
    end
    -- Saved Instances rows/headers are rebuilt with current theme colors.
    if S.savedFrame and S.savedFrame:IsShown() and RefreshSavedInstances then
        RefreshSavedInstances()
    end
end

function M.GetButtonVisibleForReadyState()
    local settings = GetSettings()
    if not settings.enabled then return false end
    if settings.hideUntilReady and CountReady() == 0 then return false end
    return true
end

function M.ApplyButtonVisibility(isMouseOver)
    if not S.button then return end
    local settings = GetSettings()
    if GetButtonVisibleForReadyState() then
        S.button:Show()
        if isMouseOver then
            S.button:SetAlpha(1)
        elseif settings.hideUntilMouseover then
            S.button:SetAlpha(0)
        else
            S.button:SetAlpha(settings.opacity or 1.0)
        end
    else
        S.button:Hide()
        HideTable()
        if S.optionsFrame then S.optionsFrame:Hide() end
    end
end

-- Table frame
local HideTable = function()
    if S.tableFrame then S.tableFrame:Hide() end
    if S.optionsFrame then S.optionsFrame:Hide() end
end

local HideMenu = function() 
    if S.menuFrame then S.menuFrame:Hide() end 
    if S.menuCatcher then S.menuCatcher:Hide() end
end
local HideSavedInstances = function()
    if S.savedFrame then S.savedFrame:Hide() end
    StopSavedInstancesLiveRefresh()
end

function M.HideAllPanels()
    HideTable()
    HideMenu()
    HideSavedInstances()
end

function M.BuildTableFrame()
    if S.tableFrame then return end
    local tableW = GetTableWidth()
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusVaultTable", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultTable")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    M.VBApplyEasyAccessShell(f)
    f:Hide()

    local inset = VBGetFrameContentInset()

    -- ===== CHROME HEADER (matches main window) =====
    local chrome = VF:CreateContainer(f, 32, 32, false)
    local chromeBandH = VBAnchorChromeBandTop(chrome, f)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint()
        SaveTablePos(point, relativePoint, x, y)
    end)
    M.VBApplyEasyAccessHeader(chrome)
    S.headerBg = chrome  -- repurposed for theme refresh

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
    S.title = title

    -- Close button (atlas style, matches main window)
    local closeBtnBg = (ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop()) or { 0.15, 0.15, 0.15, 0.9 }
    local closeBtn = M.VBCreateEasyAccessCloseButton(chrome, HideTable)
    if not closeBtn then
        closeBtn = VF:CreateButton(chrome, 28, 28, true)
        closeBtn:SetPoint("RIGHT", -8, 0)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, closeBtnBg, {accent[1], accent[2], accent[3], 0.8})
        end
        local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
        closeIcon:SetSize(16, 16)
        closeIcon:SetPoint("CENTER")
        closeIcon:SetAtlas("uitools-icon-close")
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        closeBtn:SetScript("OnClick", HideTable)
        closeBtn:SetScript("OnEnter", function()
            closeIcon:SetVertexColor(1, 0.2, 0.2)
            if ApplyVisuals then ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1}) end
        end)
        closeBtn:SetScript("OnLeave", function()
            closeIcon:SetVertexColor(0.9, 0.3, 0.3)
            if ApplyVisuals then ApplyVisuals(closeBtn, closeBtnBg, {accent[1], accent[2], accent[3], 0.8}) end
        end)
    end

    -- Settings (gear) button — opens options frame
    local settingsBtn = VF:CreateButton(chrome, 28, 28, true)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() ToggleOptionsFrame(f, "RIGHT") end)

    -- Column header row
    local headerY = -(chromeBandH + 6)
    local hRow = VF:CreateContainer(f, tableW - inset * 2, HEADER_H, false)
    hRow:SetPoint("TOPLEFT", f, "TOPLEFT", inset, headerY)
    local hdr = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()
        or COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bg
    local br = COLORS.border or accent
    M.VBApplyEasyAccessListHeader(hRow, hdr, { br[1], br[2], br[3], 0.6 })

    -- Header cells
    function M.HCell(text, x, w, isIcon, iconTex, tooltipTitle, tooltipText, tooltipKind, tooltipID)
        if isIcon and iconTex then
            local icon = hRow:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("CENTER", hRow, "LEFT", x + w/2, 0)
            icon:SetTexture(iconTex)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if tooltipTitle then
                local hover = VF:CreateContainer(hRow, w, HEADER_H, false)
                hover:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
                hover:EnableMouse(true)
                hover:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    if tooltipKind == "item" and tooltipID then
                        if GameTooltip.SetItemByID then
                            GameTooltip:SetItemByID(tooltipID)
                        else
                            GameTooltip:SetHyperlink("item:" .. tooltipID)
                        end
                    elseif tooltipKind == "currency" and tooltipID and GameTooltip.SetCurrencyByID then
                        GameTooltip:SetCurrencyByID(tooltipID)
                    else
                        if ns.UI_GameTooltipAddRoleLine then
                            ns.UI_GameTooltipAddRoleLine(GameTooltip, tooltipTitle, "Bright")
                        else
                            GameTooltip:AddLine(tooltipTitle, 1, 1, 1)
                        end
                        if tooltipText then
                            GameTooltip:AddLine(tooltipText, 0.75, 0.75, 0.75, true)
                        end
                    end
                    GameTooltip:Show()
                end)
                hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        else
            local fs = VBFontString(hRow, "small")
            fs:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
            fs:SetSize(w, HEADER_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            ns.UI_SetTextColorRole(fs, "Bright")
            fs:SetText(text)
        end
    end

    local hx = 0
    HCell("Character",  hx, COL_NAME,    false)              ; hx = hx + COL_NAME
    HCell("iLvl",       hx, COL_ILVL,    false)              ; hx = hx + COL_ILVL
    for _, cat in ipairs(GetEnabledCategoryDefs()) do
        HCell(nil,      hx, cat.width,    true,  cat.icon, cat.label) ; hx = hx + cat.width
    end
    local columns = GetSettings().columns or {}
    if columns.bounty ~= false then
        HCell(nil,      hx, COL_BOUNTY,  true,  TRACK_ICONS.bounty, "Trovehunter's Bounty", nil, "item", BOUNTY_ITEM_ID) ; hx = hx + COL_BOUNTY
    end
    if columns.gildedStash == true then
        HCell(nil,      hx, COL_STASH,   true,  TRACK_ICONS.gildedStash, EAL("EA_TOOLTIP_STASH_LABEL", "Gilded Stashes"),
            EAL("EA_TOOLTIP_STASH_HEADER_DESC", "T11 Bountiful Delve Gilded Stash claims this week.")) ; hx = hx + COL_STASH
    end
    if columns.voidcore ~= false then
        HCell(nil,      hx, COL_VOIDCORE,true,  TRACK_ICONS.voidcore, "Nebulous Voidcore", nil, "currency", VOIDCORE_ID) ; hx = hx + COL_VOIDCORE
    end
    if columns.manaflux == true then
        HCell(nil,      hx, COL_MANAFLUX,true,  GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux), "Dawnlight Manaflux", nil, "currency", MANAFLUX_ID) ; hx = hx + COL_MANAFLUX
    end
    HCell("Status",     hx, COL_STATUS,  false)

    local dividerXs = BuildVaultTableColumnDividerXs(GetEnabledCategoryDefs(), columns)
    if ns.UI_SyncGridColumnDividers and #dividerXs > 0 then
        ns.UI_SyncGridColumnDividers(hRow, dividerXs, HEADER_H)
    end

    -- Separator
    local sep = M.VBCreateEasyAccessSeparator(f, inset, inset, headerY - HEADER_H)
    S.separator = sep

    -- Scroll (factory-styled scrollbar; matches Saved Instances / main UI)
    local scroll = VF:CreateScrollFrame(f, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     inset, headerY - HEADER_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    local scrollInnerW = M.VBGetEasyAccessScrollChildWidth(tableW - inset * 2)
    local content = VF:CreateContainer(scroll, scrollInnerW, 8, false)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = scroll:GetVerticalScroll() or 0
        local maxY = math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
        scroll:SetVerticalScroll(math.min(maxY, math.max(0, cur - delta * ROW_H * 2)))
    end)

    S.tableFrame   = f
    S.tableScroll  = scroll
    S.tableContent = content
    ApplyTheme()
end

--- Clamp scroll child height and hide the bar when all rows fit (avoids 1–2px overflow on first open).
function M.VBSyncVaultTableScrollBar(list, content, contentH)
    if not S.tableScroll or not content then return end
    local vf = ns.UI.Factory
    if not vf or not vf.UpdateScrollBarVisibility then return end
    local scrollH = S.tableScroll:GetHeight() or 0
    if list and #list > 0 and #list <= MAX_ROWS and scrollH > 1 then
        content:SetHeight(math.min(contentH, scrollH))
    else
        content:SetHeight(contentH)
    end
    vf:UpdateScrollBarVisibility(S.tableScroll)
end

local RefreshTable = function()
    BuildTableFrame()
    local VF = ns.UI.Factory
    local tableW = GetTableWidth()
    local content = S.tableContent
    local list    = BuildCharList()

    for _, row in ipairs(S.rows) do row:Hide() end
    S.rows = {}

    if #list == 0 then
        S.tableFrame:SetSize(tableW, VBGetChromeBandHeight() + HEADER_H + 80)
        local inset = VBGetFrameContentInset()
        local scrollInnerW = M.VBGetEasyAccessScrollChildWidth(tableW - inset * 2)
        content:SetSize(scrollInnerW, 40)
        local msg = VBFontString(content, "body")
        msg:SetPoint("CENTER", content, "CENTER")
        ns.UI_SetTextColorRole(msg, "Dim")
        msg:SetText("No vault activity this week.")
        S.tableFrame:Show()
        VBSyncVaultTableScrollBar(list, content, 40)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if S.tableFrame and S.tableFrame:IsShown() then
                    VBSyncVaultTableScrollBar(list, content, 40)
                end
            end)
        end
        return
    end

    local catDefs = GetEnabledCategoryDefs()
    local columns = GetSettings().columns or {}
    local vaultColumnDividerXs = BuildVaultTableColumnDividerXs(catDefs, columns)
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    local borderC = colors.border or accent
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffd4af37"
    local mutedHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"

    for i, e in ipairs(list) do
        local row = VF:CreateContainer(content, M.VBGetEasyAccessScrollChildWidth(tableW - VBGetFrameContentInset() * 2), ROW_H, false)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:EnableMouse(true)

        if VF and VF.ApplyRowBackground then
            VF:ApplyRowBackground(row, i)
        else
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local stripe = (i % 2 == 0) and (COLORS.surfaceRowEven or { 0.08, 0.08, 0.11, 0.95 })
                or (COLORS.surfaceRowOdd or { 0.05, 0.05, 0.08, 0.95 })
            bg:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 0.95)
        end
        if VF and VF.ApplyOnlineCharacterHighlight then
            VF:ApplyOnlineCharacterHighlight(row, e.isCurrent)
        end

        -- Hover highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(accent[1], accent[2], accent[3], 0.25)

        -- Left stripe
        local stripe = row:CreateTexture(nil, "BORDER")
        stripe:SetWidth(3)
        stripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
        stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        if e.isReady then
            stripe:SetColorTexture(0.2, 0.9, 0.3, 1)
        else
            stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
        end

        -- Row separator
        if i > 1 then
            local rowSep = row:CreateTexture(nil, "BORDER")
            rowSep:SetHeight(1)
            rowSep:SetPoint("TOPLEFT",  row, "TOPLEFT",  3, 0)
            rowSep:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            rowSep:SetColorTexture(borderC[1], borderC[2], borderC[3], 0.5)
        end

        -- Name
        local x = 0
        local nameFS = VBFontString(row, "body")
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", x+6, 0)
        nameFS:SetSize(COL_NAME-6, ROW_H)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetText(FormatCharacterName(e))
        x = x + COL_NAME

        -- iLvl
        local ilvlFS = VBFontString(row, "body")
        ilvlFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        ilvlFS:SetSize(COL_ILVL, ROW_H)
        ilvlFS:SetJustifyH("CENTER")
        ilvlFS:SetJustifyV("MIDDLE")
        ilvlFS:SetText(e.itemLevel > 0
            and (goldHex .. string.format("%.0f", e.itemLevel) .. "|r")
            or  DASH)
        x = x + COL_ILVL

        -- Vault columns
        local allSlots = {}
        for _, cat in ipairs(catDefs) do
            local slots = GetSlotData(e.charKey, cat.key)
            allSlots[cat.key] = slots
            local settings = GetSettings()
            local bindPayload = {
                slots = slots,
                category = cat.key,
                showRewardProgress = settings.showRewardProgress,
                showRewardItemLevel = settings.showRewardItemLevel,
                vaultLootClaimable = e.isReady == true,
            }
            if ns.UI_BindVaultColumnCells then
                ns.UI_BindVaultColumnCells(row, x, cat.width, bindPayload)
            else
                local fs = VBFontString(row, "body")
                fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
                fs:SetSize(cat.width, ROW_H)
                fs:SetJustifyH("CENTER")
                fs:SetJustifyV("MIDDLE")
                if ns.UI_BindVaultColumnDisplay then
                    ns.UI_BindVaultColumnDisplay(fs, bindPayload)
                else
                    fs:SetText(SlotSymbols(slots, cat.key, e.isReady))
                end
            end
            x = x + cat.width
        end

        local b = e.bounty
        if columns.bounty ~= false then
            local bountyFS = VBFontString(row, "body")
            bountyFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            bountyFS:SetSize(COL_BOUNTY, ROW_H)
            bountyFS:SetJustifyH("CENTER")
            bountyFS:SetJustifyV("MIDDLE")
            bountyFS:SetText(b == nil and DASH or (b and CHECK or CROSS))
            x = x + COL_BOUNTY
        end

        if columns.gildedStash == true then
            local stashFS = VBFontString(row, "body")
            stashFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            stashFS:SetSize(COL_STASH, ROW_H)
            stashFS:SetJustifyH("CENTER")
            stashFS:SetJustifyV("MIDDLE")
            if stashFS.SetWordWrap then stashFS:SetWordWrap(false) end
            local stash = e.gildedStash
            if not stash then
                stashFS:SetText(DASH)
            elseif stash.unknown then
                stashFS:SetText(mutedHex .. "?/|r" .. goldHex .. (stash.max or 4) .. "|r")
            else
                local color = (stash.current or 0) >= (stash.max or 4) and "|cff44ff44" or "|cffd4af37"
                stashFS:SetText(color .. (stash.current or 0) .. "|r" .. mutedHex .. "/|r" .. goldHex .. (stash.max or 4) .. "|r")
            end
            x = x + COL_STASH
        end

        -- Nebulous Voidcore (current / seasonMax)
        local vc = e.voidcore
        if columns.voidcore ~= false then
            local voidcoreFS = VBFontString(row, "body")
            voidcoreFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            voidcoreFS:SetSize(COL_VOIDCORE, ROW_H)
            voidcoreFS:SetJustifyH("CENTER")
            voidcoreFS:SetJustifyV("MIDDLE")
            if not vc then
                voidcoreFS:SetText(DASH)
            else
                local sm = vc.seasonMax or 0
                if sm > 0 then
                    local capColor = vc.isCapped and "|cffdd3333" or goldHex
                    voidcoreFS:SetText(capColor .. vc.progress .. "|r" .. mutedHex .. "/|r" .. goldHex .. sm .. "|r")
                else
                    voidcoreFS:SetText(goldHex .. vc.quantity .. "|r")
                end
            end
            x = x + COL_VOIDCORE
        end

        -- Dawnlight Manaflux
        if columns.manaflux == true then
            local manafluxFS = VBFontString(row, "body")
            manafluxFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            manafluxFS:SetSize(COL_MANAFLUX, ROW_H)
            manafluxFS:SetJustifyH("CENTER")
            manafluxFS:SetJustifyV("MIDDLE")
            local mf = e.manaflux
            manafluxFS:SetText(mf and (goldHex .. (mf.quantity or 0) .. "|r") or DASH)
            x = x + COL_MANAFLUX
        end

        -- Status
        local statusFS = VBFontString(row, "body")
        statusFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        statusFS:SetSize(COL_STATUS, ROW_H)
        statusFS:SetJustifyH("CENTER")
        statusFS:SetJustifyV("MIDDLE")
        local readyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
        local pendingLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."
        local slotsReadyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_SLOTS_READY"]) or "Slots Ready"
        if e.isReady then
            statusFS:SetText("|cff44ff44" .. readyLabel .. "|r")
        elseif (e.slots or 0) > 0 then
            statusFS:SetText("|cff66ddff" .. slotsReadyLabel .. "|r")
        else
            statusFS:SetText("|cffffd700" .. pendingLabel .. "|r")
        end

        if ns.UI_SyncGridColumnDividers and #vaultColumnDividerXs > 0 then
            ns.UI_SyncGridColumnDividers(row, vaultColumnDividerXs, ROW_H)
        end

        -- Row tooltip: readable vault summary (table cells keep icons)
        row:SetScript("OnEnter", function(self)
            EnsureVaultShiftWatcher()
            S.eaTooltipHover.anchor = self
            S.eaTooltipHover.charKey = e.charKey
            S.eaTooltipHover.entry = e
            RefreshEasyAccessHoverTooltip()
        end)
        row:SetScript("OnLeave", function()
            S.eaTooltipHover.anchor = nil
            S.eaTooltipHover.charKey = nil
            S.eaTooltipHover.entry = nil
            WNTooltipHide()
        end)

        -- Click row to open WN PvE tab
        row:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" then
                HideTable()
                OpenWNPveTab()
            end
        end)

        table.insert(S.rows, row)
    end

    local visRows  = math.min(#list, MAX_ROWS)
    local contentH = #list * ROW_H
    local viewH    = visRows * ROW_H
    local inset = VBGetFrameContentInset()
    local totalH   = VBGetChromeBandHeight() + 6 + HEADER_H + 2 + viewH + inset

    S.tableFrame:SetSize(tableW, totalH)
    S.tableScroll:SetVerticalScroll(0)
    content:SetWidth(M.VBGetEasyAccessScrollChildWidth(tableW - inset * 2))
    VBSyncVaultTableScrollBar(list, content, contentH)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if S.tableFrame and S.tableFrame:IsShown() then
                VBSyncVaultTableScrollBar(list, content, contentH)
            end
        end)
    end
    S.tableFrame:Show()
end

function M.ToggleTable()
    if S.tableFrame and S.tableFrame:IsShown() then
        HideTable()
    else
        HideSavedInstances()
        RefreshTable()
        if S.tableFrame and S.button then
            S.tableFrame:ClearAllPoints()
            local saved = GetSavedTablePos()
            if saved and saved.x and saved.y then
                S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
            else
                local bY = S.button:GetTop() or 0
                if bY > GetScreenHeight() / 2 then
                    S.tableFrame:SetPoint("BOTTOMLEFT", S.button, "TOPLEFT", 0, 4)
                else
                    S.tableFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -4)
                end
            end
        end
    end
end

function M.ShowQuickView(anchor)
    HideAllPanels()
    RefreshTable()
    if S.tableFrame and (anchor or S.button) then
        anchor = anchor or S.button
        S.tableFrame:ClearAllPoints()
        local saved = GetSavedTablePos()
        if saved and saved.x and saved.y then
            S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
        else
            S.tableFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        end
    end
end

M.HideTable = HideTable
M.HideMenu = HideMenu
M.HideSavedInstances = HideSavedInstances
M.RefreshTable = RefreshTable
M.RebuildTableFrame = RebuildTableFrame

