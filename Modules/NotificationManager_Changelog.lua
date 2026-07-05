--[[
    Warband Nexus - Notification changelog / What's New (ops-035 slice)
    Loaded before NotificationManager.lua.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local ApplyVisuals = ns.UI_ApplyVisuals
local Constants = ns.Constants
local CURRENT_VERSION = Constants.ADDON_VERSION

local Chg = ns.NotificationChangelog or {}
ns.NotificationChangelog = Chg

local function GetThemeAccentColor()
    if ns.UI_COLORS and ns.UI_COLORS.accent then
        return { ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3] }
    end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if db and db.themeColors and db.themeColors.accent then
        local c = db.themeColors.accent
        return { c[1], c[2], c[3] }
    end
    return { 0.40, 0.20, 0.58 }
end
-- Changelog for current version only: locale key CHANGELOG_V + numeric x.y.z triple (e.g. 2.5.15-beta1 -> CHANGELOG_V2515)
local FALLBACK_CHANGELOG = "v" .. tostring(CURRENT_VERSION) .. "\n- See Locales for CHANGELOG_V key matching this version.\n\nCurseForge: Warband Nexus"

local function VersionToChangelogKey(version)
    if not version or type(version) ~= "string" then return nil end
    -- Numeric x.y.z only (supports suffixes like -beta1 on ADDON_VERSION; maps to CHANGELOG_V2515)
    local a, b, c = version:match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return nil end
    return "CHANGELOG_V" .. a .. b .. c
end

local function BuildChangelog()
    local key = VersionToChangelogKey(CURRENT_VERSION)
    local changelogText = key and ns.L and ns.L[key]
    if not changelogText or changelogText == "" then
        changelogText = FALLBACK_CHANGELOG
    end
    if not changelogText or changelogText == "" then
        changelogText = FALLBACK_CHANGELOG
    end
    local changes = {}
    for line in (changelogText or ""):gmatch("([^\n]*)") do
        changes[#changes + 1] = line
    end
    return changes
end

local CHANGELOG = {
    version = CURRENT_VERSION,
    date = (Constants and Constants.ADDON_RELEASE_DATE) or "",
    changes = BuildChangelog()
}

local function RefreshChangelogCache()
    CHANGELOG.version = CURRENT_VERSION
    CHANGELOG.date = (Constants and Constants.ADDON_RELEASE_DATE) or ""
    CHANGELOG.changes = BuildChangelog()
    ns.CHANGELOG = CHANGELOG
    return CHANGELOG
end

local function ResolveChangelogData(incoming)
    local fresh = RefreshChangelogCache()
    if incoming and type(incoming) == "table" then
        return {
            version = incoming.version or fresh.version,
            date = incoming.date or fresh.date,
            changes = (incoming.changes and #incoming.changes > 0) and incoming.changes or fresh.changes,
        }
    end
    return fresh
end

local function NM_DisposeWhatsNewBackdrop()
    local existing = _G.WarbandNexusUpdateBackdrop
    if not existing then
        return
    end
    existing:Hide()
    existing:EnableKeyboard(false)
    existing:SetScript("OnKeyDown", nil)
    local bin = ns.UI_RecycleBin
    if bin then
        existing:SetParent(bin)
    else
        existing:SetParent(nil)
    end
    _G.WarbandNexusUpdateBackdrop = nil
end

local function NM_ClearChangelogScrollChild(scrollChild)
    if not scrollChild then
        return
    end
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        children[i]:SetParent(nil)
    end
    scrollChild._changelogPopulated = nil
    scrollChild:SetHeight(8)
end

-- Export CHANGELOG to namespace for command access
ns.CHANGELOG = CHANGELOG
--- Aligns changelog backdrop padding with `MAIN_SHELL` / `UI_SPACING` (SharedWidgets loads before this file).
local function NM_GetShellContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

--- Replaces legacy hard-coded horizontal `30` (â‰ˆ three Ã— `SIDE_MARGIN` at defaults).
local function NM_WhatsNewPopupSidePad()
    local side = (ns.UI_SPACING and ns.UI_SPACING.SIDE_MARGIN) or 10
    return math.max(side * 3, NM_GetShellContentInset() * 12)
end
---Check if there's a new version
---@return boolean isNewVersion
function WarbandNexus:IsNewVersion()
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return false
    end
    
    local lastSeen = self.db.profile.notifications.lastSeenVersion or "0.0.0"
    return CURRENT_VERSION ~= lastSeen
end

---Populate changelog content (deferred to first show so fonts/layout are ready)
local function PopulateChangelogContent(scrollChild, scrollFrame, changelogData, geometry)
    if not scrollChild or not scrollFrame or not changelogData or not changelogData.changes or not geometry then
        return
    end
    if not FontManager or not FontManager.CreateFontString then
        return
    end
    local TEXT_WIDTH = geometry.TEXT_WIDTH
    local TEXT_PAD = geometry.TEXT_PAD
    local LINE_SPACING = geometry.LINE_SPACING
    local SECTION_SPACING = geometry.SECTION_SPACING
    local PARAGRAPH_SPACING = geometry.PARAGRAPH_SPACING
    local bodyFontSize = (FontManager.GetFontSize and FontManager:GetFontSize("body")) or 12
    local MIN_LINE_HEIGHT = (bodyFontSize and bodyFontSize > 0 and (bodyFontSize + 2)) or 14

    NM_ClearChangelogScrollChild(scrollChild)

    local topPad = 12
    local bottomPad = 12
    local yOffset = topPad
    for i = 1, #changelogData.changes do
        local change = changelogData.changes[i]
        if change == "" then
            yOffset = yOffset + PARAGRAPH_SPACING
        else
            local line = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
            line:SetWidth(TEXT_WIDTH)
            line:SetPoint("TOPLEFT", TEXT_PAD, -yOffset)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(true)
            line:SetNonSpaceWrap(false)
            line:SetText(change)
            if change:match(":$") then
                local sgR, sgG, sgB, sgA
                if ns.UI_GetSemanticGoldColor then
                    sgR, sgG, sgB, sgA = ns.UI_GetSemanticGoldColor()
                end
                if type(sgR) == "number" and type(sgG) == "number" and type(sgB) == "number" then
                    line:SetTextColor(sgR, sgG, sgB, (type(sgA) == "number" and sgA) or 1)
                else
                    line:SetTextColor(1, 0.84, 0, 1)
                end
            elseif ns.UI_SetTextColorRole then
                ns.UI_SetTextColorRole(line, "Bright")
            else
                line:SetTextColor(0.92, 0.92, 0.92, 1)
            end
            local lineH = line:GetStringHeight() or 0
            if lineH < MIN_LINE_HEIGHT then
                lineH = MIN_LINE_HEIGHT
            end
            yOffset = yOffset + lineH
            if change:match(":$") then
                yOffset = yOffset + SECTION_SPACING
            else
                yOffset = yOffset + LINE_SPACING
            end
        end
    end
    scrollChild:SetHeight(math.max(8, yOffset + bottomPad))
    scrollChild._changelogPopulated = true
    if ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    end
    scrollFrame:SetVerticalScroll(0)
end

local function NM_TryPopulateChangelog(scrollChild, scrollFrame, changelogData, geometry)
    if not scrollChild or scrollChild._changelogPopulated then
        return false
    end
    if not scrollFrame or not changelogData or not changelogData.changes or #changelogData.changes == 0 then
        return false
    end
    PopulateChangelogContent(scrollChild, scrollFrame, changelogData, geometry)
    return scrollChild._changelogPopulated == true
end

local function NM_ScheduleChangelogPopulate(scrollChild, scrollFrame, changelogData, geometry)
    local delays = { 0, 0.05, 0.2 }
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if scrollChild and scrollFrame and scrollFrame:IsShown() then
                NM_TryPopulateChangelog(scrollChild, scrollFrame, changelogData, geometry)
            end
        end)
    end
end

local function NM_CreateWhatsNewDismiss()
    return function()
        if WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications then
            WarbandNexus.db.profile.notifications.lastSeenVersion = CURRENT_VERSION
        end
        NM_DisposeWhatsNewBackdrop()
        local hooks = ns.NotificationManagerHooks
        if hooks and hooks.ProcessNotificationQueue then
            hooks.ProcessNotificationQueue()
        end
    end
end

local function NM_CreateWhatsNewCloseIcon(parent, onDismiss, popupLevel, ar, ag, ab)
    local btn = ns.UI.Factory:CreateButton(parent, 28, 28, false)
    assert(btn, "What's New close button requires UI.Factory")
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    btn:SetFrameLevel((popupLevel or parent:GetFrameLevel() or 0) + 50)
    if ApplyVisuals then
        local closeBg = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { 0.15, 0.15, 0.15, 0.9 }
        ApplyVisuals(btn, closeBg, { ar, ag, ab, 0.6 })
    end
    local closeIcon = btn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(18, 18)
    closeIcon:SetPoint("CENTER")
    if not (ns.UI_SetMainChromeIcon and ns.UI_SetMainChromeIcon(closeIcon, "close", { 0.9, 0.3, 0.3 })) then
        if closeIcon.SetAtlas then
            closeIcon:SetAtlas("uitools-icon-close")
        end
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    end
    btn:SetScript("OnClick", onDismiss)
    return btn
end

---Show update notification popup
function WarbandNexus:ShowUpdateNotification(changelogData)
    changelogData = ResolveChangelogData(changelogData)
    NM_DisposeWhatsNewBackdrop()
    local accent = GetThemeAccentColor()
    local ar, ag, ab = accent[1], accent[2], accent[3]
    local changelogSidePad = NM_WhatsNewPopupSidePad()
    local changelogCloseBottom = math.max(15, NM_GetShellContentInset() * 7 + 1)
    --- Distinct layout band: separator â†’ label â†’ scroll (must match scrollbar column inset).
    local changelogScrollTop = 185
    local changelogScrollBottom = 72
    local dismiss = NM_CreateWhatsNewDismiss()

    local ToastFactory = ns.NotificationToastFactory
    assert(ToastFactory and ToastFactory.CreateToastHost, "What's New requires NotificationToastFactory")
    assert(ns.UI and ns.UI.Factory, "What's New requires UI.Factory")

    -- Global name via CreateFrame (Frame has no SetName API — only AceGUI widgets do).
    local host = ToastFactory:CreateToastHost(UIParent, UIParent:GetWidth() or 1, UIParent:GetHeight() or 1, {
        strata = "DIALOG",
        frameLevel = 200,
        enableMouse = false,
        globalName = "WarbandNexusUpdateBackdrop",
    })
    host:SetAllPoints()
    host:EnableKeyboard(true)
    host:SetPropagateKeyboardInput(false)

    local scrim = ToastFactory:CreateToastLayer(host, 1, 1)
    scrim:SetAllPoints()
    scrim:SetFrameLevel(host:GetFrameLevel())
    scrim:EnableMouse(true)
    scrim:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            dismiss()
        end
    end)
    local dim = ns.UI_GetOverlayDimColor and ns.UI_GetOverlayDimColor() or { 0, 0, 0, 0.7 }
    local scrimBg = scrim:CreateTexture(nil, "BACKGROUND")
    scrimBg:SetAllPoints()
    scrimBg:SetColorTexture(dim[1], dim[2], dim[3], dim[4] or 1)
    host._wnDimTexture = scrimBg

    local popup = ns.UI.Factory:CreateContainer(host, 600, 550, false)
    assert(popup, "What's New popup requires UI.Factory")
    popup:SetPoint("CENTER", 0, 50)
    popup:SetFrameLevel(host:GetFrameLevel() + 20)
    popup:EnableMouse(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(popup)
    else
        popup:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        popup:SetBackdropColor((ns.UI_COLORS and ns.UI_COLORS.bgCard and ns.UI_COLORS.bgCard[1]) or 0.08,
            (ns.UI_COLORS and ns.UI_COLORS.bgCard and ns.UI_COLORS.bgCard[2]) or 0.08,
            (ns.UI_COLORS and ns.UI_COLORS.bgCard and ns.UI_COLORS.bgCard[3]) or 0.10, 1)
        popup:SetBackdropBorderColor(ar, ag, ab, 1)
    end
    host._wnPopup = popup

    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(popup)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(popup)
    end

    NM_CreateWhatsNewCloseIcon(popup, dismiss, popup:GetFrameLevel(), ar, ag, ab)
    
    -- Logo/Icon
    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOP", 0, -20)
    logo:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
    
    -- Title (nil-guard FontManager for first load)
    if FontManager and FontManager.CreateFontString then
        local title = FontManager:CreateFontString(popup, "header", "OVERLAY")
        title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
        local function ARGBByte(x)
            return math.max(0, math.min(255, math.floor((tonumber(x) or 0) * 255 + 0.5)))
        end
        title:SetText(string.format("|cff%02x%02x%02x%s|r", ARGBByte(ar), ARGBByte(ag), ARGBByte(ab),
            ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")))
        
        local versionText = FontManager:CreateFontString(popup, "body", "OVERLAY")
        versionText:SetPoint("TOP", title, "BOTTOM", 0, -5)
        local versionLabel = (ns.L and ns.L["VERSION"]) or "Version"
        versionText:SetText(versionLabel .. " " .. changelogData.version .. " - " .. changelogData.date)
        ns.UI_SetTextColorRole(versionText, "Muted")
    end
    
    -- Separator line
    local separator = ns.UI.Factory:CreateThemeDivider(popup, {
        orientation = "horizontal",
        variant = "section",
        thickness = 1,
    })
    if separator then
        separator:SetPoint("TOPLEFT", changelogSidePad, -140)
        separator:SetPoint("TOPRIGHT", -changelogSidePad, -140)
    end
    
    if FontManager and FontManager.CreateFontString then
        local whatsNewLabel = FontManager:CreateFontString(popup, "title", "OVERLAY")
        whatsNewLabel:SetPoint("TOP", separator, "BOTTOM", 0, -15)
        local whatsNewText = (ns.L and ns.L["WHATS_NEW"]) or "What's New"
        whatsNewLabel:SetText((ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex() or "|cffffd700") .. whatsNewText .. "|r")
    end
    
    local POPUP_INNER_W = 600
    local SCROLL_EDGE_GUTTER = 24
    --- Right inset = scrollbar lane (`column + gap`) + fixed gutter to popup chrome (formerly hard-coded 52).
    local changelogRightInset = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()
        or 28) + SCROLL_EDGE_GUTTER
    local CONTENT_WIDTH = POPUP_INNER_W - changelogSidePad - changelogRightInset
    local TEXT_PAD = 10
    local TEXT_WIDTH = CONTENT_WIDTH - (TEXT_PAD * 2)
    local geometry = {
        CONTENT_WIDTH = CONTENT_WIDTH,
        TEXT_WIDTH = TEXT_WIDTH,
        TEXT_PAD = TEXT_PAD,
        LINE_SPACING = 6,
        SECTION_SPACING = 12,
        PARAGRAPH_SPACING = 14,
    }
    
    local scrollFrame, scrollChild
    assert(
        ns.UI.Factory.CreateScrollFrame and FontManager and FontManager.CreateFontString,
        "What's New scroll requires UI.Factory + FontManager"
    )
    scrollFrame = ns.UI.Factory:CreateScrollFrame(popup, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetFrameLevel(popup:GetFrameLevel() + 5)
    scrollFrame:SetPoint("TOPLEFT", changelogSidePad, -changelogScrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", -changelogRightInset, changelogScrollBottom)
    if ns.UI.Factory.EnsureScrollBarColumnSync and scrollFrame.ScrollBar then
        local chgSbColW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
        local scrollBarColumn = ns.UI.Factory:CreateBareScrollBarColumn(popup, chgSbColW)
        if scrollBarColumn then
            scrollBarColumn:SetFrameLevel(popup:GetFrameLevel() + 6)
            ns.UI.Factory:EnsureScrollBarColumnSync(scrollFrame, scrollBarColumn, { width = chgSbColW, gap = 2 })
        end
    elseif ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory.PositionScrollBarInContainer and scrollFrame.ScrollBar then
        local chgSbColW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
        local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(popup, chgSbColW, 0, 0)
        scrollBarColumn:SetFrameLevel(popup:GetFrameLevel() + 6)
        ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end
    scrollChild = ns.UI.Factory:CreateContainer(scrollFrame, CONTENT_WIDTH, 8, false)
    assert(scrollChild, "What's New scroll child requires UI.Factory")
    scrollChild:SetWidth(CONTENT_WIDTH)
    scrollFrame:SetScrollChild(scrollChild)
    NM_ScheduleChangelogPopulate(scrollChild, scrollFrame, changelogData, geometry)
    
    -- Close button (Factory rim + accent fill; preserves hover brighten via ApplyVisuals)
    local closeBtn = ns.UI.Factory:CreateButton(popup, 120, 35, false)
    assert(closeBtn, "What's New close button requires UI.Factory")
    if ApplyVisuals then
        local idle = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()
        ApplyVisuals(closeBtn, idle or { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
    end
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 40)
    closeBtn:SetPoint("BOTTOM", 0, changelogCloseBottom)
    
    local closeBtnText = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(closeBtn, "body", "OVERLAY")
        or closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetPoint("CENTER")
    local gotItText = (ns.L and ns.L["GOT_IT"]) or "Got it!"
    closeBtnText:SetText(gotItText)
    ns.UI_SetTextColorRole(closeBtnText, "Bright")
    
    closeBtn:SetScript("OnClick", dismiss)
    
    closeBtn:SetScript("OnEnter", function(btn)
        if ApplyVisuals then
            local hover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop()
            if hover then
                ApplyVisuals(btn, hover, { ar, ag, ab, 1 })
            else
                ApplyVisuals(btn, { ar * 0.7, ag * 0.7, ab * 0.7, 1 }, { ar, ag, ab, 1 })
            end
        elseif btn.SetBackdropColor then
            btn:SetBackdropColor(ar * 0.7, ag * 0.7, ab * 0.7, 1)
        end
    end)

    closeBtn:SetScript("OnLeave", function(btn)
        if ApplyVisuals then
            local idle = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()
            if idle then
                ApplyVisuals(btn, idle, { ar, ag, ab, 1 })
            else
                ApplyVisuals(btn, { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
            end
        elseif btn.SetBackdropColor then
            btn:SetBackdropColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
        end
    end)
    
    host:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            dismiss()
        end
    end)

    host:Show()
end

function WarbandNexus:RefreshWhatsNewTheme()
    local backdrop = _G.WarbandNexusUpdateBackdrop
    if not backdrop or not backdrop:IsShown() then return end
    if backdrop._wnDimTexture then
        local dim = ns.UI_GetOverlayDimColor and ns.UI_GetOverlayDimColor() or { 0, 0, 0, 0.7 }
        backdrop._wnDimTexture:SetColorTexture(dim[1], dim[2], dim[3], dim[4] or 1)
    end
    local popup = backdrop._wnPopup
    if popup and ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(popup)
    end
end

Chg.RefreshChangelogCache = RefreshChangelogCache
Chg.CURRENT_VERSION = CURRENT_VERSION
Chg.CHANGELOG = CHANGELOG
Chg.VersionToChangelogKey = VersionToChangelogKey
Chg.GetShellContentInset = NM_GetShellContentInset
Chg.GetWhatsNewPopupSidePad = NM_WhatsNewPopupSidePad

assert(WarbandNexus.ShowUpdateNotification, "NotificationManager_Changelog: ShowUpdateNotification missing")
