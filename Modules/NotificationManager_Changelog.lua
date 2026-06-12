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
        changelogText = (ns.L and ns.L["CHANGELOG_V304"]) or (ns.L and ns.L["CHANGELOG_V303"]) or (ns.L and ns.L["CHANGELOG_V302"]) or (ns.L and ns.L["CHANGELOG_V300"]) or FALLBACK_CHANGELOG
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
    if not scrollChild or not scrollFrame or not changelogData or not changelogData.changes or not geometry then return end
    local CONTENT_WIDTH = geometry.CONTENT_WIDTH
    local TEXT_WIDTH = geometry.TEXT_WIDTH
    local TEXT_PAD = geometry.TEXT_PAD
    local LINE_SPACING = geometry.LINE_SPACING
    local SECTION_SPACING = geometry.SECTION_SPACING
    local PARAGRAPH_SPACING = geometry.PARAGRAPH_SPACING
    -- Robust MIN_LINE_HEIGHT: safe fallback 14 when font not ready (first-time users)
    local bodyFontSize = (FontManager and FontManager.GetFontSize and FontManager:GetFontSize("body")) or 12
    local MIN_LINE_HEIGHT = (bodyFontSize and bodyFontSize > 0 and (bodyFontSize + 2)) or 14

    local topPad = 12
    local bottomPad = 12
    local yOffset = topPad
    for i, change in ipairs(changelogData.changes) do
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
                line:SetTextColor(1, 0.84, 0)
            else
                ns.UI_SetTextColorRole(line, "Bright")
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
    scrollChild:SetHeight(yOffset + bottomPad)
    if ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    end
end

---Show update notification popup
function WarbandNexus:ShowUpdateNotification(changelogData)
    local accent = GetThemeAccentColor()
    local ar, ag, ab = accent[1], accent[2], accent[3]
    local changelogSidePad = NM_WhatsNewPopupSidePad()
    local changelogCloseBottom = math.max(15, NM_GetShellContentInset() * 7 + 1)
    --- Distinct layout band: separator â†’ label â†’ scroll (must match scrollbar column inset).
    local changelogScrollTop = 185
    local changelogScrollBottom = 60
    
    -- Create backdrop frame
    local backdrop = CreateFrame("Frame", "WarbandNexusUpdateBackdrop", UIParent)
    backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    backdrop:SetFrameLevel(1000)
    backdrop:SetAllPoints()
    backdrop:EnableMouse(true)
    backdrop:SetScript("OnMouseDown", function() end) -- Block clicks
    
    -- Semi-transparent black overlay
    local bg = backdrop:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Popup frame (increased size for better content visibility)
    local popup = CreateFrame("Frame", nil, backdrop, "BackdropTemplate")
    popup:SetSize(600, 550)  -- Increased from 450x400 to 600x550
    popup:SetPoint("CENTER", 0, 50)
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
        popup:SetBackdropColor(0.08, 0.08, 0.10, 1)
        popup:SetBackdropBorderColor(ar, ag, ab, 1)
    end
    
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
    local separator = popup:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", changelogSidePad, -140)
    separator:SetPoint("TOPRIGHT", -changelogSidePad, -140)
    separator:SetColorTexture(ar, ag, ab, 0.6)
    
    if FontManager and FontManager.CreateFontString then
        local whatsNewLabel = FontManager:CreateFontString(popup, "title", "OVERLAY")
        whatsNewLabel:SetPoint("TOP", separator, "BOTTOM", 0, -15)
        local whatsNewText = (ns.L and ns.L["WHATS_NEW"]) or "What's New"
        whatsNewLabel:SetText("|cffffd700" .. whatsNewText .. "|r")
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
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateScrollFrame and FontManager and FontManager.CreateFontString then
        scrollFrame = ns.UI.Factory:CreateScrollFrame(popup, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", changelogSidePad, -changelogScrollTop)
        scrollFrame:SetPoint("BOTTOMRIGHT", -changelogRightInset, changelogScrollBottom)
        if ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory.PositionScrollBarInContainer and scrollFrame.ScrollBar then
            local chgSbColW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
            local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(popup, chgSbColW, changelogScrollTop, changelogScrollBottom)
            ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
        if ns.UI.Factory.CreateContainer then
            scrollChild = ns.UI.Factory:CreateContainer(scrollFrame, CONTENT_WIDTH, 8, false)
        end
        if not scrollChild then
            scrollChild = CreateFrame("Frame", nil, scrollFrame)
        end
        scrollChild:SetWidth(CONTENT_WIDTH)
        scrollFrame:SetScrollChild(scrollChild)
        -- Defer content layout to next frame so fonts/layout are ready (fixes first-time user layout)
        C_Timer.After(0, function()
            if scrollChild and scrollFrame and not scrollChild._changelogPopulated then
                scrollChild._changelogPopulated = true
                PopulateChangelogContent(scrollChild, scrollFrame, changelogData, geometry)
            end
        end)
    else
        -- Fallback: simple non-scrolling text block so popup never breaks
        scrollChild = CreateFrame("Frame", nil, popup)
        scrollChild:SetPoint("TOPLEFT", changelogSidePad, -changelogScrollTop)
        scrollChild:SetPoint("BOTTOMRIGHT", -changelogSidePad, changelogScrollBottom)
        scrollFrame = nil
        local fallbackText
        if FontManager and FontManager.CreateFontString then
            fallbackText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        else
            fallbackText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        fallbackText:SetPoint("TOPLEFT", TEXT_PAD, 0)
        fallbackText:SetWidth(TEXT_WIDTH)
        fallbackText:SetJustifyH("LEFT")
        fallbackText:SetWordWrap(true)
        fallbackText:SetText((changelogData.changes and table.concat(changelogData.changes, "\n")) or "")
        ns.UI_SetTextColorRole(fallbackText, "Bright")
        scrollChild:SetScript("OnSizeChanged", function()
            fallbackText:SetWidth(scrollChild:GetWidth() - (TEXT_PAD * 2))
        end)
    end
    
    -- Close button (Factory rim + accent fill; preserves hover brighten via ApplyVisuals)
    local closeBtn
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
        closeBtn = ns.UI.Factory:CreateButton(popup, 120, 35, false)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
        end
    end
    if not closeBtn then
        closeBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        closeBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        closeBtn:SetBackdropColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
        closeBtn:SetBackdropBorderColor(ar, ag, ab, 1)
    end
    closeBtn:SetPoint("BOTTOM", 0, changelogCloseBottom)
    
    local closeBtnText
    if FontManager and FontManager.CreateFontString then
        closeBtnText = FontManager:CreateFontString(closeBtn, "body", "OVERLAY")
    else
        closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    closeBtnText:SetPoint("CENTER")
    local gotItText = (ns.L and ns.L["GOT_IT"]) or "Got it!"
    closeBtnText:SetText(gotItText)
    
    closeBtn:SetScript("OnClick", function()
        if WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications then
            WarbandNexus.db.profile.notifications.lastSeenVersion = CURRENT_VERSION
        end
        backdrop:Hide()
        local bin = ns.UI_RecycleBin
        if bin then backdrop:SetParent(bin) else backdrop:SetParent(nil) end
        local hooks = ns.NotificationManagerHooks
        if hooks and hooks.ProcessNotificationQueue then
            hooks.ProcessNotificationQueue()
        end
    end)
    
    closeBtn:SetScript("OnEnter", function(btn)
        if ApplyVisuals then
            ApplyVisuals(btn, { ar * 0.7, ag * 0.7, ab * 0.7, 1 }, { ar, ag, ab, 1 })
        elseif btn.SetBackdropColor then
            btn:SetBackdropColor(ar * 0.7, ag * 0.7, ab * 0.7, 1)
        end
    end)

    closeBtn:SetScript("OnLeave", function(btn)
        if ApplyVisuals then
            ApplyVisuals(btn, { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
        elseif btn.SetBackdropColor then
            btn:SetBackdropColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
        end
    end)
    
    -- Escape key to close
    backdrop:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            closeBtn:Click()
        end
    end)
    if not InCombatLockdown() then backdrop:SetPropagateKeyboardInput(false) end
end
Chg.CURRENT_VERSION = CURRENT_VERSION
Chg.CHANGELOG = CHANGELOG
Chg.VersionToChangelogKey = VersionToChangelogKey
Chg.GetShellContentInset = NM_GetShellContentInset
Chg.GetWhatsNewPopupSidePad = NM_WhatsNewPopupSidePad

assert(WarbandNexus.ShowUpdateNotification, "NotificationManager_Changelog: ShowUpdateNotification missing")
