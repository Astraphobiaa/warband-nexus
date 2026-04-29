--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local FontManager = ns.FontManager  -- Centralized font management
local DebugPrint = ns.DebugPrint or function() end
local DebugVerbosePrint = ns.DebugVerbosePrint or DebugPrint

-- Unique AceEvent handler identity for NotificationManager
local NotificationEvents = {}

-- Current addon version (from Constants)
local Constants = ns.Constants
local E = Constants.EVENTS
local CURRENT_VERSION = Constants.ADDON_VERSION

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
        changelogText = (ns.L and ns.L["CHANGELOG_V264"]) or FALLBACK_CHANGELOG
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

local function NotifyDebug(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DebugPrint("|cff00ccff[Notification Debug]|r " .. tostring(msg))
end

--[[============================================================================
    THEME COLOR INTEGRATION
============================================================================]]

-- Get theme colors from SharedWidgets
local function GetThemeAccentColor()
    -- Try to get colors from namespace (SharedWidgets)
    if ns.UI_COLORS and ns.UI_COLORS.accent then
        return {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3]}
    end
    
    -- Fallback: Try database directly
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if db and db.themeColors and db.themeColors.accent then
        local c = db.themeColors.accent
        return {c[1], c[2], c[3]}
    end
    
    -- Final fallback: Default purple
    return {0.40, 0.20, 0.58}
end

-- Refresh notification colors when theme changes
-- This is called by SharedWidgets.RefreshColors()
function WarbandNexus:RefreshNotificationColors()
    -- Active notifications will keep their original colors
    -- New notifications will use the updated theme color
    -- This is intentional - notifications shouldn't change color mid-animation
    
    -- No action needed here - GetThemeAccentColor() will return updated colors
    -- for any new notifications created after theme change
end

--[[============================================================================
    NOTIFICATION QUEUE
============================================================================]]

local notificationQueue = {}
local notificationQueueHead = 1

-- TryCounter + CollectionService can both send WN_COLLECTIBLE_OBTAINED within a short window:
--   • bag scan right after loot (item hits bags while Try Counter already toasted), or
--   • NEW_MOUNT journal event after loot (name differs: item vs mount journal).
-- Bag duplicate is suppressed at source (TryCounterService + CollectionService); this is a second line of defense.
-- Dedupe popup only; dispatch consumers (TryCounter migration, Plans) still run first in handler order.
local lastCollectibleLootToastShownAt = {}
local COLLECTIBLE_LOOT_TOAST_DEDUP_SEC = 12

---@param data table|nil
---@return string|nil
local function BuildCollectibleLootToastDedupeKey(data)
    if not data or not data.type or data.id == nil then return nil end
    local t = data.type
    local id = data.id
    if t == "mount" then
        if C_MountJournal and C_MountJournal.GetMountFromItem and type(id) == "number" then
            local mid = C_MountJournal.GetMountFromItem(id)
            if mid and not (issecretvalue and issecretvalue(mid)) and type(mid) == "number" and mid > 0 then
                id = mid
            end
        end
        return "mount\0" .. tostring(id)
    end
    if t == "pet" and C_PetJournal and C_PetJournal.GetPetInfoByItemID and type(id) == "number" then
        local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(id))
        if speciesID and not (issecretvalue and issecretvalue(speciesID)) and type(speciesID) == "number" and speciesID > 0 then
            id = speciesID
        end
        return "pet\0" .. tostring(id)
    end
    if t == "toy" or t == "illusion" or t == "item" then
        return t .. "\0" .. tostring(id)
    end
    return nil
end

---Add a notification to the queue
---@param notification table Notification data
local function QueueNotification(notification)
    notificationQueue[#notificationQueue + 1] = notification
end

local function HasPendingNotifications()
    return notificationQueueHead <= #notificationQueue
end

local function DequeueNotification()
    if not HasPendingNotifications() then
        notificationQueue = {}
        notificationQueueHead = 1
        return nil
    end

    local notification = notificationQueue[notificationQueueHead]
    notificationQueue[notificationQueueHead] = nil
    notificationQueueHead = notificationQueueHead + 1

    if notificationQueueHead > 32 and notificationQueueHead > (#notificationQueue / 2) then
        local compacted = {}
        for i = notificationQueueHead, #notificationQueue do
            compacted[#compacted + 1] = notificationQueue[i]
        end
        notificationQueue = compacted
        notificationQueueHead = 1
    end

    return notification
end

---Process notification queue (show one at a time)
local function ProcessNotificationQueue()
    if not HasPendingNotifications() then
        return
    end
    
    -- Show first notification
    local notification = DequeueNotification()
    
    if notification.type == "update" then
        WarbandNexus:ShowUpdateNotification(notification.data)
    elseif notification.type == "vault" then
        WarbandNexus:ShowVaultReminder(notification.data)
    end
    
    -- Schedule next notification (2 second delay)
    if HasPendingNotifications() then
        C_Timer.After(2, ProcessNotificationQueue)
    end
end

--[[============================================================================
    VERSION CHECK & UPDATE NOTIFICATION
============================================================================]]

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
---@param scrollChild Frame
---@param scrollFrame Frame
---@param changelogData table
---@param geometry table { CONTENT_WIDTH, TEXT_WIDTH, TEXT_PAD, LINE_SPACING, SECTION_SPACING, PARAGRAPH_SPACING }
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
                line:SetTextColor(0.9, 0.9, 0.9)
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
---@param changelogData table Changelog data
function WarbandNexus:ShowUpdateNotification(changelogData)
    local accent = GetThemeAccentColor()
    local ar, ag, ab = accent[1], accent[2], accent[3]
    
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
    
    -- Logo/Icon
    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOP", 0, -20)
    logo:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title (nil-guard FontManager for first load)
    if FontManager and FontManager.CreateFontString then
        local title = FontManager:CreateFontString(popup, "header", "OVERLAY")
        title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
        title:SetText("|cff9966ff" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r")
        
        local versionText = FontManager:CreateFontString(popup, "body", "OVERLAY")
        versionText:SetPoint("TOP", title, "BOTTOM", 0, -5)
        local versionLabel = (ns.L and ns.L["VERSION"]) or "Version"
        versionText:SetText(versionLabel .. " " .. changelogData.version .. " - " .. changelogData.date)
        versionText:SetTextColor(0.6, 0.6, 0.6)
    end
    
    -- Separator line
    local separator = popup:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 30, -140)
    separator:SetPoint("TOPRIGHT", -30, -140)
    separator:SetColorTexture(ar, ag, ab, 0.6)
    
    if FontManager and FontManager.CreateFontString then
        local whatsNewLabel = FontManager:CreateFontString(popup, "title", "OVERLAY")
        whatsNewLabel:SetPoint("TOP", separator, "BOTTOM", 0, -15)
        local whatsNewText = (ns.L and ns.L["WHATS_NEW"]) or "What's New"
        whatsNewLabel:SetText("|cffffd700" .. whatsNewText .. "|r")
    end
    
    local CONTENT_WIDTH = 600 - 30 - 52
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
        scrollFrame:SetPoint("TOPLEFT", 30, -185)
        scrollFrame:SetPoint("BOTTOMRIGHT", -52, 60)
        if ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory.PositionScrollBarInContainer and scrollFrame.ScrollBar then
            local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(popup, 22, 185, 60)
            ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
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
        scrollChild:SetPoint("TOPLEFT", 30, -185)
        scrollChild:SetPoint("BOTTOMRIGHT", -30, 60)
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
        fallbackText:SetTextColor(0.9, 0.9, 0.9)
        scrollChild:SetScript("OnSizeChanged", function()
            fallbackText:SetWidth(scrollChild:GetWidth() - (TEXT_PAD * 2))
        end)
    end
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    closeBtn:SetSize(120, 35)
    closeBtn:SetPoint("BOTTOM", 0, 15)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    closeBtn:SetBackdropColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
    closeBtn:SetBackdropBorderColor(ar, ag, ab, 1)
    
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
        -- Mark version as seen
        self.db.profile.notifications.lastSeenVersion = CURRENT_VERSION
        
        -- Close popup
        backdrop:Hide()
        backdrop:SetParent(nil)
        
        -- Process next notification
        ProcessNotificationQueue()
    end)
    
    closeBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropColor(ar * 0.7, ag * 0.7, ab * 0.7, 1)
    end)
    
    closeBtn:SetScript("OnLeave", function(btn)
        btn:SetBackdropColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
    end)
    
    -- Escape key to close
    backdrop:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            closeBtn:Click()
        end
    end)
    if not InCombatLockdown() then backdrop:SetPropagateKeyboardInput(false) end
end

--[[============================================================================
    NOTIFICATION CONFIG FACTORY (DRY)
    Standardized config builders for all notification types.
    All share: playSound=true, glowAtlas=DEFAULT_GLOW, duration=DB setting.
============================================================================]]

local DEFAULT_GLOW = "TopBottom:UI-Frame-DastardlyDuos-Line"

-- Category fallback icons (when item-specific icon is missing)
local CATEGORY_ICONS = {
    mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
    pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
    toy = "Interface\\Icons\\INV_Misc_Toy_07",
    illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
    achievement = "Interface\\Icons\\Achievement_Quests_Completed_08",
    title = "Interface\\Icons\\INV_Scroll_11",
    plan = "Interface\\Icons\\INV_Misc_Note_06",
    vault = "Interface\\Icons\\achievement_guildperk_bountifulbags",
    reputation = "Interface\\Icons\\INV_Scroll_11",
    quest = "Interface\\Icons\\INV_Misc_Map_01",
    item = "Interface\\Icons\\INV_Misc_Bag_10",
    reminder = "minimap-genericevent-hornicon-small",
}

-- Action text mapping (subtitle line)
local ACTION_TEXT = {
    mount = (ns.L and ns.L["COLLECTED_MOUNT_MSG"]) or "You have collected a mount",
    pet = (ns.L and ns.L["COLLECTED_PET_MSG"]) or "You have collected a battle pet",
    toy = (ns.L and ns.L["COLLECTED_TOY_MSG"]) or "You have collected a toy",
    illusion = (ns.L and ns.L["COLLECTED_ILLUSION_MSG"]) or "You have collected an illusion",
    achievement = (ns.L and ns.L["ACHIEVEMENT_COMPLETED_MSG"]) or "Achievement completed!",
    criteria_progress = (ns.L and ns.L["CRITERIA_PROGRESS_MSG"]) or "Progress", -- "Progress X/Y" line
    title = (ns.L and ns.L["EARNED_TITLE_MSG"]) or "You have earned a title",
    plan = (ns.L and ns.L["COMPLETED_PLAN_MSG"]) or "You have completed a plan",
    item = (ns.L and ns.L["COLLECTED_ITEM_MSG"]) or "You received a rare drop",
    reminder = (ns.L and ns.L["REMINDER_PREFIX"]) or "Reminder",
}

---Build a standardized notification config
---@param notifType string Notification type key (mount/pet/toy/achievement/title/illusion/plan)
---@param name string Display name
---@param icon string|number|nil Icon path, texture ID, or nil (falls back to category icon)
---@param overrides table|nil Optional overrides for any config field
---@return table config Ready to pass to ShowModalNotification
function WarbandNexus:BuildNotificationConfig(notifType, name, icon, overrides)
    local resolvedIcon = icon or CATEGORY_ICONS[notifType] or "Interface\\Icons\\INV_Misc_QuestionMark"
    local config = {
        icon = resolvedIcon,
        itemName = name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
        action = ACTION_TEXT[notifType] or "",
        playSound = true,
        glowAtlas = DEFAULT_GLOW,
    }
    -- Auto-detect atlas names so the renderer uses SetAtlas instead of SetTexture
    if ns.Utilities:IsAtlasName(resolvedIcon) then
        config.iconAtlas = resolvedIcon
        config.icon = nil
    end
    if overrides then
        for k, v in pairs(overrides) do
            config[k] = v
        end
    end
    return config
end

---Shortcut: build config and immediately show notification
---@param notifType string Notification type key
---@param name string Display name
---@param icon string|number|nil Icon (falls back to category)
---@param overrides table|nil Optional config overrides
function WarbandNexus:Notify(notifType, name, icon, overrides)
    local config = self:BuildNotificationConfig(notifType, name, icon, overrides)
    self:ShowModalNotification(config)
end

--[[============================================================================
    ACHIEVEMENT-STYLE ALERT FRAME SYSTEM (WOW-STYLE)
============================================================================]]

-- Initialize AlertFrame tracking (like WoW's AlertFrame system)
if not WarbandNexus.activeAlerts then
    WarbandNexus.activeAlerts = {} -- Currently visible alerts (max 3)
end
if not WarbandNexus.alertQueue then
    WarbandNexus.alertQueue = {} -- Waiting alerts (if >3 active)
end
WarbandNexus.alertQueueHead = WarbandNexus.alertQueueHead or 1
-- Queue processing debounce timer (prevents multiple simultaneous queue processing)
local queueProcessTimer = nil

local function HasQueuedAlerts()
    return WarbandNexus.alertQueueHead <= #WarbandNexus.alertQueue
end

local function EnqueueAlert(config)
    WarbandNexus.alertQueue[#WarbandNexus.alertQueue + 1] = config
end

local function DequeueAlert()
    if not HasQueuedAlerts() then
        WarbandNexus.alertQueue = {}
        WarbandNexus.alertQueueHead = 1
        return nil
    end

    local nextConfig = WarbandNexus.alertQueue[WarbandNexus.alertQueueHead]
    WarbandNexus.alertQueue[WarbandNexus.alertQueueHead] = nil
    WarbandNexus.alertQueueHead = WarbandNexus.alertQueueHead + 1

    if WarbandNexus.alertQueueHead > 16 and WarbandNexus.alertQueueHead > (#WarbandNexus.alertQueue / 2) then
        local compacted = {}
        for i = WarbandNexus.alertQueueHead, #WarbandNexus.alertQueue do
            compacted[#compacted + 1] = WarbandNexus.alertQueue[i]
        end
        WarbandNexus.alertQueue = compacted
        WarbandNexus.alertQueueHead = 1
    end

    return nextConfig
end

-- Alert positioning constants
local ALERT_HEIGHT = 88       -- Full toast height (fixed for all variants)
local ALERT_HEIGHT_COMPACT = 88  -- Same as full: fixed stack geometry and no height jump between types
local ALERT_GAP = 10          -- Pixel gap between stacked alerts
local ALERT_SPACING = ALERT_HEIGHT + ALERT_GAP  -- Legacy: total slot spacing (98px)
-- Fixed outer width for all toast variants (text wraps/clamps inside; avoids shrink-wrap layout jumps)
local ALERT_WIDTH_FIXED = 400

---Get Blizzard's alert frame position so we can match it when "Use AlertFrame Position" is on.
---Tries AchievementAlertFrame1, CriteriaAlertFrame1, AlertFrameHolder, then any visible AlertFrame child.
---@return string|nil point, number|nil x, number|nil y Or nil if frame not found.
local function GetBlizzardAlertFramePosition()
    local tryNames = { "AchievementAlertFrame1", "CriteriaAlertFrame1", "AlertFrameHolder", "GroupLootFrame1" }
    local f
    for _, name in ipairs(tryNames) do
        f = _G[name]
        if f and f.GetPoint and f:GetNumPoints() >= 1 then break end
        f = nil
    end
    if not f then
        if AlertFrame and AlertFrame.GetNumChildren then
            for i = 1, AlertFrame:GetNumChildren() do
                local child = select(i, AlertFrame:GetChildren())
                if child and child.GetPoint and child:GetNumPoints() >= 1 and child:IsShown() then f = child break end
            end
        end
    end
    if not f or not f.GetPoint then return nil, nil, nil end
    local point, relativeTo, relativePoint, x, y = f:GetPoint(1)
    if not point then return nil, nil, nil end
    x, y = tonumber(x) or 0, tonumber(y) or -100
    if relativeTo == UIParent then
        return point, x, y
    end
    local fLeft, fTop = f:GetLeft(), f:GetTop()
    if not fLeft or not fTop then return nil, nil, nil end
    local w = f:GetWidth() or 400
    local uiw = UIParent:GetWidth()
    local uiTop = UIParent:GetTop()
    local centerX = fLeft + (w / 2)
    local offsetX = math.floor(centerX - (uiw / 2))
    local offsetY = math.floor(fTop - uiTop)
    return "TOP", offsetX, offsetY
end

---Get saved notification position from DB. When useAlertFramePosition is set, returns Blizzard's frame position.
---When compact is true but compact position equals main position, returns main so all notifications share one anchor and stack (no overlap).
---@param compact boolean|nil If true and separate criteria position is set, return that; else return main position.
---@return string point, number x, number y
local function GetSavedPosition(compact)
    local db = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not db then return "TOP", 0, -100 end
    if db.useAlertFramePosition then
        local pt, px, py = GetBlizzardAlertFramePosition()
        if pt and px and py then return pt, px, py end
    end
    local mainPt, mainX, mainY = db.popupPoint or "TOP", db.popupX or 0, db.popupY or -100
    if compact and db.popupPointCompact then
        local cX, cY = db.popupXCompact or 0, db.popupYCompact or -100
        -- Same position for all: use single anchor so achievement/criteria/collectible stack without overlapping
        if db.popupPointCompact == mainPt and cX == mainX and cY == mainY then
            return mainPt, mainX, mainY
        end
        return db.popupPointCompact, cX, cY
    end
    return mainPt, mainX, mainY
end

---Determine growth direction based on anchor position on screen (always AUTO)
---Returns 1 for DOWN (negative Y), -1 for UP (positive Y)
---@param point string|nil Optional anchor point (else from GetSavedPosition)
---@param x number|nil Optional X (else from GetSavedPosition)
---@param y number|nil Optional Y (else from GetSavedPosition)
---@return number direction (1 = down, -1 = up)
local function GetGrowthDirection(point, x, y)
    if not point then
        point, x, y = GetSavedPosition()
    end
    local screenHeight = UIParent:GetHeight()
    
    -- Calculate approximate Y position of anchor on screen (0 = bottom, screenHeight = top)
    local anchorScreenY
    if point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
        anchorScreenY = screenHeight + y
    elseif point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
        anchorScreenY = y
    else -- CENTER variants
        anchorScreenY = (screenHeight / 2) + y
    end
    
    -- If anchor is in the top 55% of screen → grow DOWN, else grow UP
    if anchorScreenY > screenHeight * 0.45 then
        return 1   -- DOWN (negative Y offsets)
    else
        return -1   -- UP (positive Y offsets)
    end
end

---Get height of an alert frame (full and compact both fixed) for stacking
---@param alert Frame
---@return number height in pixels
local function GetAlertHeight(alert)
    return (alert and alert._alertHeight) or ALERT_HEIGHT
end

---Calculate Y offset for a new alert that will be appended to a group (cumulative height of existing alerts in that anchor).
---Used so achievement and criteria progress never overlap regardless of order or mix.
---@param anchorKey string Key from (point.."|"..bx.."|"..by)
---@param direction number 1 = down, -1 = up
---@return number yOffset from baseY (positive = down from anchor when direction 1)
local function GetCumulativeOffsetForNewAlert(anchorKey, direction)
    local cumulative = 0
    for _, alert in ipairs(WarbandNexus.activeAlerts) do
        local pt = alert._anchorPoint
        local bx, by = alert._baseX, alert._baseY
        if pt and bx and by then
            local key = pt .. "|" .. tostring(bx) .. "|" .. tostring(by)
            if key == anchorKey then
                cumulative = cumulative + GetAlertHeight(alert) + ALERT_GAP
            end
        end
    end
    return cumulative * -direction
end

---Reposition all active alerts (when one closes, others fill the gap). Alerts with same anchor stack together; slot Y uses each alert's actual height so full and compact never overlap.
---@param instant boolean If true, cancel all animations and reposition instantly
local function RepositionAlerts(instant)
    local defaultPoint, defaultX, defaultY = GetSavedPosition()
    -- Group alerts by anchor (point,x,y) so each stack has its own slot indices
    local groups = {}
    for i, alert in ipairs(WarbandNexus.activeAlerts) do
        local pt = alert._anchorPoint or defaultPoint
        local bx = alert._baseX or defaultX
        local by = alert._baseY or defaultY
        local key = pt .. "|" .. tostring(bx) .. "|" .. tostring(by)
        if not groups[key] then groups[key] = {} end
        table.insert(groups[key], alert)
    end
    for key, list in pairs(groups) do
        local pt = list[1]._anchorPoint or defaultPoint
        local bx = list[1]._baseX or defaultX
        local by = list[1]._baseY or defaultY
        local direction = GetGrowthDirection(pt, bx, by)
        local cumulativeOffset = 0
        for slotInGroup, alert in ipairs(list) do
            local newYOffset = by + (cumulativeOffset * -direction)
            cumulativeOffset = cumulativeOffset + GetAlertHeight(alert) + ALERT_GAP
            if not alert.isClosing then
                if alert.isAnimating then
                    alert:SetScript("OnUpdate", nil)
                    alert.isAnimating = false
                end
                if alert.isEntering then
                    if alert._entranceTargetY ~= newYOffset then
                        alert._entranceStartY = alert.currentYOffset or newYOffset
                        alert._entranceTargetY = newYOffset
                        alert._entranceStartTime = GetTime()
                    end
                elseif instant then
                    if alert.currentYOffset ~= newYOffset then
                        alert:ClearAllPoints()
                        alert:SetPoint(pt, UIParent, pt, bx, newYOffset)
                        alert.currentYOffset = newYOffset
                    end
                elseif alert.currentYOffset ~= newYOffset then
                    local repositionStart = GetTime()
                    local repositionDuration = 0.25
                    local startY = alert.currentYOffset or newYOffset
                    local moveDistance = newYOffset - startY
                    local _point, _baseX = pt, bx
                    alert.isAnimating = true
                    alert:SetScript("OnUpdate", function(self, elapsed)
                        local elapsedTime = GetTime() - repositionStart
                        local progress = math.min(1, elapsedTime / repositionDuration)
                        local easedProgress = progress < 0.5 and (2 * progress * progress) or (1 - math.pow(-2 * progress + 2, 2) / 2)
                        local currentY = startY + (moveDistance * easedProgress)
                        self:ClearAllPoints()
                        self:SetPoint(_point, UIParent, _point, _baseX, currentY)
                        self.currentYOffset = currentY
                        if progress >= 1 then
                            self:SetScript("OnUpdate", nil)
                            self.isAnimating = false
                            self.currentYOffset = newYOffset
                        end
                    end)
                end
            end
        end
    end
    for i, alert in ipairs(WarbandNexus.activeAlerts) do
        alert.alertIndex = i
    end
end

---Remove alert and process queue
---@param alert Frame The alert frame to remove
local function RemoveAlert(alert)
    if not alert then 
        return
    end
    
    -- Prevent double-removal
    if alert._removed then return end
    alert._removed = true
    
    -- Cancel any active timers
    if alert.dismissTimer then
        alert.dismissTimer:Cancel()
        alert.dismissTimer = nil
    end
    
    -- Stop timer animations
    if alert.timerAg then
        alert.timerAg:Stop()
    end
    if alert.timerRotateAg then
        alert.timerRotateAg:Stop()
    end
    
    -- Stop any OnUpdate scripts
    alert:SetScript("OnUpdate", nil)
    alert.isAnimating = false
    alert.isClosing = false
    alert.isEntering = false
    
    -- Clear all scripts for proper cleanup
    alert:SetScript("OnEnter", nil)
    alert:SetScript("OnLeave", nil)
    alert:SetScript("OnMouseDown", nil)
    
    -- Find and remove from active alerts
    for i, a in ipairs(WarbandNexus.activeAlerts) do
        if a == alert then
            table.remove(WarbandNexus.activeAlerts, i)
            break
        end
    end
    
    alert:Hide()
    alert:SetParent(nil)
    
    -- IMMEDIATELY reposition remaining alerts to fill the gap (no delay)
    if WarbandNexus and WarbandNexus.activeAlerts and #WarbandNexus.activeAlerts > 0 then
        RepositionAlerts()
    end
    
    -- Process queue with debounce (prevents multiple simultaneous dismissals from spawning too many alerts)
    if HasQueuedAlerts() then
        -- Cancel any existing queue timer
        if queueProcessTimer then
            queueProcessTimer:Cancel()
        end
        
        -- Short debounce to batch rapid dismissals, then process queue
        queueProcessTimer = C_Timer.NewTimer(0.15, function()
            queueProcessTimer = nil
            
            -- Process queue: show ONE alert at a time with staggered entrance
            local function ProcessNextInQueue()
                if not WarbandNexus or not WarbandNexus.activeAlerts then return end
                if HasQueuedAlerts() and #WarbandNexus.activeAlerts < 3 then
                    local nextConfig = DequeueAlert()
                    
                    if WarbandNexus.ShowModalNotification then
                        WarbandNexus:ShowModalNotification(nextConfig)
                        
                        -- If more slots available, stagger next alert after entrance completes
                        if HasQueuedAlerts() and #WarbandNexus.activeAlerts < 3 then
                            C_Timer.After(0.25, ProcessNextInQueue)
                        end
                    end
                end
            end
            
            ProcessNextInQueue()
        end)
    end
end

---Show an achievement-style notification with all visual effects (WoW AlertFrame style)
---Addon-created toast frames are not secure; showing them during combat is safe (no taint).
---@param config table Configuration: {icon, title, message, subtitle, category, glowAtlas}
function WarbandNexus:ShowModalNotification(config)
    -- Queue system: max 3 alerts visible at once
    if #self.activeAlerts >= 3 then
        EnqueueAlert(config)
        return
    end
    
    -- Default values
    config = config or {}
    local iconTexture = config.iconFileID or config.icon or "Interface\\Icons\\Achievement_Quests_Completed_08"
    local iconAtlas = config.iconAtlas or nil
    
    -- Auto-detect atlas if not explicitly set (factory pattern — centralized detection)
    if not iconAtlas and ns.Utilities:IsAtlasName(iconTexture) then
        iconAtlas = iconTexture
        iconTexture = nil
    end
    
    -- NEW LAYOUT SYSTEM
    local itemName = config.itemName or config.title or ((ns.L and ns.L["NOTIFICATION_DEFAULT_TITLE"]) or "Notification")  -- Title (big, red)
    local actionText = config.action or config.message or ""            -- Subtitle (small, gray)
    local categoryText = config.category or nil  -- Optional, only for special cases (Renown)
    
    -- BACKWARD COMPATIBILITY
    local titleText = itemName
    local messageText = actionText
    local subtitleText = config.subtitle or ""
    
    local playSound = config.playSound ~= false
    local titleColor = config.titleColor or GetThemeAccentColor()
    local glowAtlas = config.glowAtlas or DEFAULT_GLOW
    -- Duration: use config override, then DB setting, then default 5s (matches Blizzard)
    local dbDuration = self.db and self.db.profile and self.db.profile.notifications
        and self.db.profile.notifications.popupDuration
    local autoDismissDelay = config.autoDismiss or dbDuration or 5
    
    -- Calculate alert position (direction-aware, screen-safe). Same anchor = same stack; offset by cumulative height so achievement and criteria never overlap.
    local isCompact = not not config.compact
    local point, baseX, baseY = GetSavedPosition(isCompact)
    local direction = GetGrowthDirection(point, baseX, baseY)
    local anchorKey = point .. "|" .. tostring(baseX) .. "|" .. tostring(baseY)
    local yOffset = baseY + GetCumulativeOffsetForNewAlert(anchorKey, direction)
    
    -- Compact toast: icon left, content (backdrop + ornaments + text) right — same layout as full achievement
    if config.compact then
        local COMPACT_HEIGHT = ALERT_HEIGHT_COMPACT
        local ICON_SLOT_WIDTH_COMPACT = 62
        local iconSizeCompact = 40
        local contentFrameCompactW = ALERT_WIDTH_FIXED - ICON_SLOT_WIDTH_COMPACT
        local compactPopup = CreateFrame("Frame", nil, UIParent)
        compactPopup:SetSize(ALERT_WIDTH_FIXED, COMPACT_HEIGHT)
        compactPopup:SetFrameStrata("HIGH")
        compactPopup:SetFrameLevel(1000)
        compactPopup:SetClampedToScreen(true)
        compactPopup:EnableMouse(true)
        compactPopup.currentYOffset = yOffset
        compactPopup.achievementID = config.achievementID
        compactPopup._anchorPoint = point
        compactPopup._baseX = baseX
        compactPopup._baseY = baseY
        compactPopup._alertHeight = ALERT_HEIGHT_COMPACT
        table.insert(self.activeAlerts, compactPopup)
        compactPopup.isEntering = true
        RepositionAlerts(true)
        
        -- Layer 0: effects (glow lines) behind the black frame
        local effectsFrameCompact = CreateFrame("Frame", nil, compactPopup)
        effectsFrameCompact:SetFrameLevel(0)
        effectsFrameCompact:SetAllPoints(compactPopup)
        local contentEffectsFrameCompact = CreateFrame("Frame", nil, effectsFrameCompact)
        contentEffectsFrameCompact:SetPoint("LEFT", effectsFrameCompact, "LEFT", ICON_SLOT_WIDTH_COMPACT, 0)
        contentEffectsFrameCompact:SetSize(contentFrameCompactW, COMPACT_HEIGHT)
        -- Layer 1: black background on top of effects
        local backdropFrameCompact = CreateFrame("Frame", nil, compactPopup, "BackdropTemplate")
        backdropFrameCompact:SetFrameLevel(1)
        backdropFrameCompact:SetAllPoints(compactPopup)
        backdropFrameCompact:EnableMouse(false)
        backdropFrameCompact:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            tile = false,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        backdropFrameCompact:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
        backdropFrameCompact:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
        
        -- Layer 2: icon slot (icon + bling only)
        local iconSlotCompact = CreateFrame("Frame", nil, compactPopup)
        iconSlotCompact:SetFrameLevel(2)
        iconSlotCompact:SetSize(ICON_SLOT_WIDTH_COMPACT, COMPACT_HEIGHT)
        iconSlotCompact:SetPoint("LEFT", compactPopup, "LEFT", 0, 0)
        
        local iconCompact = iconSlotCompact:CreateTexture(nil, "ARTWORK")
        iconCompact:SetSize(iconSizeCompact, iconSizeCompact)
        iconCompact:SetPoint("LEFT", iconSlotCompact, "LEFT", (ICON_SLOT_WIDTH_COMPACT - iconSizeCompact) / 2, 0)
        if config.iconAtlas and config.iconAtlas ~= "" then
            iconCompact:SetAtlas(config.iconAtlas)
        else
            iconCompact:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local tex = config.iconFileID or config.icon or CATEGORY_ICONS.achievement
            if type(tex) == "number" then
                iconCompact:SetTexture(tex)
            else
                iconCompact:SetTexture(tex and tex:gsub("\\", "/") or "Interface/Icons/INV_Misc_QuestionMark")
            end
        end
        local iconBlingCompact = iconSlotCompact:CreateTexture(nil, "OVERLAY", nil, 7)
        iconBlingCompact:SetSize(iconSizeCompact + 8, iconSizeCompact + 8)
        iconBlingCompact:SetPoint("CENTER", iconCompact, "CENTER", 0, 0)
        iconBlingCompact:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
        iconBlingCompact:SetTexCoord(0, 0.5625, 0, 0.5625)
        iconBlingCompact:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        iconBlingCompact:SetBlendMode("BLEND")
        
        -- Content frame (right): text only (ornaments in contentEffectsFrameCompact)
        local contentFrameCompact = CreateFrame("Frame", nil, compactPopup)
        contentFrameCompact:SetFrameLevel(2)
        contentFrameCompact:SetPoint("LEFT", compactPopup, "LEFT", ICON_SLOT_WIDTH_COMPACT, 0)
        
        -- Theme: TopBottom glow in effects layer (behind black)
        if glowAtlas and glowAtlas:find("TopBottom:") then
            local baseAtlas = glowAtlas:gsub("TopBottom:", "")
            local topLine = contentEffectsFrameCompact:CreateTexture(nil, "BACKGROUND", nil, 0)
            topLine:SetPoint("TOPLEFT", contentEffectsFrameCompact, "TOPLEFT", 0, 2)
            topLine:SetPoint("TOPRIGHT", contentEffectsFrameCompact, "TOPRIGHT", 0, 2)
            topLine:SetHeight(32)
            topLine:SetAtlas(baseAtlas .. "-Top", true)
            topLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
            topLine:SetBlendMode("ADD")
            local bottomLine = contentEffectsFrameCompact:CreateTexture(nil, "BACKGROUND", nil, 0)
            bottomLine:SetPoint("BOTTOMLEFT", contentEffectsFrameCompact, "BOTTOMLEFT", 0, -2)
            bottomLine:SetPoint("BOTTOMRIGHT", contentEffectsFrameCompact, "BOTTOMRIGHT", 0, -2)
            bottomLine:SetHeight(32)
            bottomLine:SetAtlas(baseAtlas .. "-bottom", true)
            bottomLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
            bottomLine:SetBlendMode("ADD")
        end
        -- Criteria progress toast: "Achievement Progress" (centered, theme) + criteria name only. Other compact: progress line + name.
        local criteriaTitle = config.criteriaTitle
        local progressStr = (messageText or actionText or "")
        local nameStr = (itemName or "")
        local tr = math.floor(math.min(255, titleColor[1] * 255 * 1.35))
        local tg = math.floor(math.min(255, titleColor[2] * 255 * 1.35))
        local tb = math.floor(math.min(255, titleColor[3] * 255 * 1.35))
        local accentHex = string.format("|cff%02x%02x%02x", tr, tg, tb)
        local progressLine, nameLine
        if criteriaTitle then
            progressLine = FontManager:CreateFontString(contentFrameCompact, "subtitle", "OVERLAY")
            progressLine:SetJustifyH("CENTER")
            progressLine:SetWordWrap(true)
            progressLine:SetMaxLines(2)
            progressLine:SetText(accentHex .. (criteriaTitle or "") .. "|r")
            progressLine:SetShadowOffset(1, -1)
            progressLine:SetShadowColor(0, 0, 0, 0.9)
            nameLine = FontManager:CreateFontString(contentFrameCompact, "body", "OVERLAY")
            nameLine:SetJustifyH("CENTER")
            nameLine:SetWordWrap(true)
            nameLine:SetMaxLines(2)
            nameLine:SetText("|cffffffff" .. (nameStr or "") .. "|r")
            nameLine:SetShadowOffset(1, -1)
            nameLine:SetShadowColor(0, 0, 0, 0.6)
        else
            progressLine = FontManager:CreateFontString(contentFrameCompact, "body", "OVERLAY")
            progressLine:SetJustifyH("LEFT")
            progressLine:SetWordWrap(false)
            progressLine:SetText("|cffb0b0b0" .. progressStr .. "|r")
            progressLine:SetShadowOffset(1, -1)
            progressLine:SetShadowColor(0, 0, 0, 0.6)
            nameLine = FontManager:CreateFontString(contentFrameCompact, "title", "OVERLAY")
            nameLine:SetJustifyH("LEFT")
            nameLine:SetText(accentHex .. (nameStr or "") .. "|r")
            nameLine:SetShadowOffset(1, -1)
            nameLine:SetShadowColor(0, 0, 0, 0.9)
        end
        contentFrameCompact:SetSize(contentFrameCompactW, COMPACT_HEIGHT)
        contentEffectsFrameCompact:SetSize(contentFrameCompactW, COMPACT_HEIGHT)
        compactPopup:SetSize(ALERT_WIDTH_FIXED, COMPACT_HEIGHT)

        local textPad = 10
        local textUseW = contentFrameCompactW - textPad * 2
        -- Vertically balanced for ALERT_HEIGHT_COMPACT (88px): two-line block below top padding
        local line1Y, line2Y = -20, -42
        progressLine:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", textPad, line1Y)
        progressLine:SetWidth(textUseW)
        nameLine:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", textPad, line2Y)
        nameLine:SetWidth(textUseW)
        nameLine:SetWordWrap(true)
        nameLine:SetMaxLines(2)
        if not criteriaTitle then
            progressLine:SetWordWrap(true)
            progressLine:SetMaxLines(2)
        end
        
        if config.playSound then
            PlaySound(config.soundID or 44295)
        end
        
        compactPopup:SetScript("OnMouseDown", function(self, button)
            if self.isClosing or self._removed then return end
            self.isClosing = true
            if button == "LeftButton" and self.achievementID and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, self.achievementID)
            end
            if self.dismissTimer then self.dismissTimer:Cancel(); self.dismissTimer = nil end
            if self.timerAg then self.timerAg:Stop() end
            self:SetScript("OnUpdate", nil)
            local t0 = GetTime()
            self:SetScript("OnUpdate", function(self, elapsed)
                local p = math.min(1, (GetTime() - t0) / 0.25)
                self:SetAlpha(1 - p)
                if p >= 1 then self:SetScript("OnUpdate", nil); RemoveAlert(self) end
            end)
        end)
        
        local compactDuration = config.autoDismiss or 3
        compactPopup:SetAlpha(0)
        compactPopup:SetPoint(point, UIParent, point, baseX, yOffset + 50 * -direction)
        compactPopup._entranceStartY = yOffset + 50 * -direction
        compactPopup._entranceTargetY = yOffset
        compactPopup._entranceStartTime = GetTime()
        compactPopup._anchorPoint = point
        compactPopup._baseX = baseX
        compactPopup._direction = direction
        local _pt, _bx = point, baseX
        compactPopup:Show()
        compactPopup:SetScript("OnUpdate", function(self, elapsed)
            local prog = math.min(1, (GetTime() - (self._entranceStartTime or 0)) / 0.3)
            local ease = 1 - math.pow(1 - prog, 2)
            local cy = (self._entranceStartY or 0) + ((self._entranceTargetY or 0) - (self._entranceStartY or 0)) * ease
            self:SetAlpha(math.min(1, self:GetAlpha() + elapsed * 4))
            self:ClearAllPoints()
            self:SetPoint(_pt, UIParent, _pt, _bx, cy)
            self.currentYOffset = cy
            if prog >= 1 then
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(1)
                self.currentYOffset = self._entranceTargetY
                self.isEntering = false
            end
        end)
        
        compactPopup.dismissTimer = C_Timer.NewTimer(compactDuration, function()
            if not compactPopup:IsShown() or compactPopup.isClosing or compactPopup._removed then return end
            compactPopup.isClosing = true
            if compactPopup.dismissTimer then compactPopup.dismissTimer:Cancel(); compactPopup.dismissTimer = nil end
            local t0 = GetTime()
            compactPopup:SetScript("OnUpdate", function(self, elapsed)
                local p = math.min(1, (GetTime() - t0) / 0.25)
                self:SetAlpha(1 - p)
                if p >= 1 then self:SetScript("OnUpdate", nil); RemoveAlert(self) end
            end)
        end)
        return
    end
    
    -- Full achievement popup: fixed width; long titles/subtitles wrap inside the text area
    local popupWidthFull = ALERT_WIDTH_FIXED
    
    -- WoW Achievement-style: container = icon slot (left) + content frame (text + ornaments only). Animations stay behind icon.
    local ICON_SLOT_WIDTH = 62  -- 14 pad + 42 icon + 6 gap
    local contentFrameWidth = popupWidthFull - ICON_SLOT_WIDTH
    
    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetSize(popupWidthFull, 88)
    popup:SetFrameStrata("HIGH")
    popup:SetFrameLevel(1000)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMouseClickEnabled(true)
    
    -- Layer 0: effects (rings, border glow, glows) — drawn behind the black frame
    local effectsFrame = CreateFrame("Frame", nil, popup)
    effectsFrame:SetFrameLevel(0)
    effectsFrame:SetAllPoints(popup)
    local iconEffectsFrame = CreateFrame("Frame", nil, effectsFrame)
    iconEffectsFrame:SetPoint("LEFT", effectsFrame, "LEFT", 0, 0)
    iconEffectsFrame:SetSize(ICON_SLOT_WIDTH, 88)
    local contentEffectsFrame = CreateFrame("Frame", nil, effectsFrame)
    contentEffectsFrame:SetPoint("LEFT", effectsFrame, "LEFT", ICON_SLOT_WIDTH, 0)
    contentEffectsFrame:SetSize(contentFrameWidth, 88)
    
    -- Layer 1: single black background (drawn on top of effects)
    local backdropFrame = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    backdropFrame:SetFrameLevel(1)
    backdropFrame:SetAllPoints(popup)
    backdropFrame:EnableMouse(false)
    backdropFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    backdropFrame:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    backdropFrame:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    
    -- Layer 2: icon slot (icon + bling only; rings live in iconEffectsFrame)
    local iconSlot = CreateFrame("Frame", nil, popup)
    iconSlot:SetFrameLevel(2)
    iconSlot:SetSize(ICON_SLOT_WIDTH, 88)
    iconSlot:SetPoint("LEFT", popup, "LEFT", 0, 0)
    
    local iconSize = 42
    local icon = iconSlot:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", iconSlot, "LEFT", 14, 0)
    if iconAtlas and iconAtlas ~= "" then
        icon:SetAtlas(iconAtlas)
    else
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if type(iconTexture) == "number" then
            icon:SetTexture(iconTexture)
        elseif iconTexture and iconTexture ~= "" then
            icon:SetTexture(iconTexture:gsub("\\", "/"))
        else
            icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
        end
    end
    
    local ringSize = 180
    local iconCenterX = 14 + (iconSize / 2)
    local iconCenterY = 88 / 2
    -- Ring 1 exactly behind icon center; ring 2 mirrored to the right side.
    local mirroredRightX = popupWidthFull - iconCenterX
    local ring1 = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring1:SetSize(ringSize, ringSize)
    ring1:SetPoint("CENTER", popup, "BOTTOMLEFT", iconCenterX, iconCenterY)
    ring1:SetTexture("Interface\\Cooldown\\star4")
    ring1:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    ring1:SetBlendMode("ADD")
    local ring2 = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring2:SetSize(ringSize, ringSize)
    ring2:SetPoint("CENTER", popup, "BOTTOMLEFT", mirroredRightX, iconCenterY)
    ring2:SetTexture("Interface\\Cooldown\\star4")
    ring2:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    ring2:SetBlendMode("ADD")
    
    -- Flash shine: one-time overlay when notification first appears
    local flashShine = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    flashShine:SetAllPoints(effectsFrame)
    flashShine:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    flashShine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    flashShine:SetBlendMode("ADD")
    flashShine:SetAlpha(0)
    
    local iconBling = iconSlot:CreateTexture(nil, "OVERLAY", nil, 7)
    iconBling:SetSize(64, 64)
    iconBling:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBling:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    iconBling:SetTexCoord(0, 0.5625, 0, 0.5625)
    iconBling:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    iconBling:SetBlendMode("BLEND")
    
    -- Layer 2: content frame (text + timer only; effects live in contentEffectsFrame)
    local contentFrame = CreateFrame("Frame", nil, popup)
    contentFrame:SetFrameLevel(2)
    contentFrame:SetSize(contentFrameWidth, 88)
    contentFrame:SetPoint("LEFT", popup, "LEFT", ICON_SLOT_WIDTH, 0)
    
    local popupHeight = 88
    if glowAtlas:find("TopBottom:") then
        local baseAtlas = glowAtlas:gsub("TopBottom:", "")
        local topLine = contentEffectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        topLine:SetPoint("TOPLEFT", contentEffectsFrame, "TOPLEFT", 0, 2)
        topLine:SetPoint("TOPRIGHT", contentEffectsFrame, "TOPRIGHT", 0, 2)
        topLine:SetHeight(56)
        topLine:SetAtlas(baseAtlas .. "-Top", true)
        topLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        topLine:SetBlendMode("ADD")
        local bottomLine = contentEffectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        bottomLine:SetPoint("BOTTOMLEFT", contentEffectsFrame, "BOTTOMLEFT", 0, -2)
        bottomLine:SetPoint("BOTTOMRIGHT", contentEffectsFrame, "BOTTOMRIGHT", 0, -2)
        bottomLine:SetHeight(56)
        bottomLine:SetAtlas(baseAtlas .. "-bottom", true)
        bottomLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        bottomLine:SetBlendMode("ADD")
        local topGlowAg = contentEffectsFrame:CreateAnimationGroup()
        topGlowAg:SetLooping("REPEAT")
        local topGlowIn = topGlowAg:CreateAnimation("Alpha")
        topGlowIn:SetTarget(topLine)
        topGlowIn:SetFromAlpha(0.7)
        topGlowIn:SetToAlpha(1.0)
        topGlowIn:SetDuration(1.2)
        topGlowIn:SetSmoothing("IN_OUT")
        local topGlowOut = topGlowAg:CreateAnimation("Alpha")
        topGlowOut:SetTarget(topLine)
        topGlowOut:SetFromAlpha(1.0)
        topGlowOut:SetToAlpha(0.7)
        topGlowOut:SetDuration(1.2)
        topGlowOut:SetSmoothing("IN_OUT")
        topGlowOut:SetStartDelay(1.2)
        topGlowAg:Play()
        local bottomGlowAg = contentEffectsFrame:CreateAnimationGroup()
        bottomGlowAg:SetLooping("REPEAT")
        local bottomGlowIn = bottomGlowAg:CreateAnimation("Alpha")
        bottomGlowIn:SetTarget(bottomLine)
        bottomGlowIn:SetFromAlpha(0.7)
        bottomGlowIn:SetToAlpha(1.0)
        bottomGlowIn:SetDuration(1.2)
        bottomGlowIn:SetSmoothing("IN_OUT")
        local bottomGlowOut = bottomGlowAg:CreateAnimation("Alpha")
        bottomGlowOut:SetTarget(bottomLine)
        bottomGlowOut:SetFromAlpha(1.0)
        bottomGlowOut:SetToAlpha(0.7)
        bottomGlowOut:SetDuration(1.2)
        bottomGlowOut:SetSmoothing("IN_OUT")
        bottomGlowOut:SetStartDelay(1.2)
        bottomGlowAg:Play()
    else
        local borderGlow = contentEffectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        if glowAtlas:find("Line%-Top") then
            borderGlow:SetPoint("TOPLEFT", contentEffectsFrame, "TOPLEFT", 0, 4)
            borderGlow:SetPoint("TOPRIGHT", contentEffectsFrame, "TOPRIGHT", 0, 4)
            borderGlow:SetHeight(40)
        elseif glowAtlas:find("Line%-Bottom") or glowAtlas:find("Line%-bottom") then
            borderGlow:SetPoint("BOTTOMLEFT", contentEffectsFrame, "BOTTOMLEFT", 0, -4)
            borderGlow:SetPoint("BOTTOMRIGHT", contentEffectsFrame, "BOTTOMRIGHT", 0, -4)
            borderGlow:SetHeight(40)
        elseif glowAtlas:find("DastardlyDuos%-Bar") then
            borderGlow:SetPoint("TOPLEFT", contentEffectsFrame, "TOPLEFT", 8, -8)
            borderGlow:SetPoint("BOTTOMRIGHT", contentEffectsFrame, "BOTTOMRIGHT", -8, 8)
        else
            borderGlow:SetAllPoints(contentEffectsFrame)
        end
        borderGlow:SetAtlas(glowAtlas, true)
        borderGlow:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        borderGlow:SetBlendMode("ADD")
        borderGlow:SetAlpha(0.9)
    end
    local edgeShine = contentEffectsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    edgeShine:SetHeight(1)
    edgeShine:SetPoint("TOPLEFT", contentEffectsFrame, "TOPLEFT", 1, -1)
    edgeShine:SetPoint("TOPRIGHT", contentEffectsFrame, "TOPRIGHT", -1, -1)
    edgeShine:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.3)
    edgeShine:SetBlendMode("ADD")
    
    -- Track this alert (container = popup for stacking)
    popup.currentYOffset = yOffset
    popup.achievementID = config.achievementID
    popup._alertHeight = ALERT_HEIGHT
    table.insert(self.activeAlerts, popup)
    popup.isEntering = true
    RepositionAlerts(true)
    
    -- === CONTENT: text centered in content frame (ornaments only in this frame) ===
    -- Symmetric layout: text block center = content frame center.
    local popupWidth = contentFrameWidth
    local popupHeight = 88
    local textCenterX = contentFrameWidth / 2
    local textAreaWidth = math.max(40, contentFrameWidth - 20)
    
    -- Font metrics (adjusted for better centering)
    local smallFontHeight = 13  -- Small font actual height
    local mediumFontHeight = 14  -- Medium font actual height
    local largeFontHeight = 16  -- Large font actual height
    local lineSpacing = 4
    
    -- Determine layout
    local showCategory = categoryText and categoryText ~= ""
    local showTitle = titleText and titleText ~= ""
    local showSubtitle = messageText and messageText ~= ""
    
    -- Calculate total content height
    local totalHeight = 0
    if showCategory then totalHeight = totalHeight + smallFontHeight end
    if showTitle then totalHeight = totalHeight + largeFontHeight end
    if showSubtitle then totalHeight = totalHeight + mediumFontHeight end
    
    -- Add line spacing
    local lineCount = (showCategory and 1 or 0) + (showTitle and 1 or 0) + (showSubtitle and 1 or 0)
    if lineCount > 1 then
        totalHeight = totalHeight + ((lineCount - 1) * lineSpacing)
    end
    
    -- Vertical: same logic as criteria-progress — text block centered in usable height between ornaments (88px).
    -- Use negative offset so block sits in the middle; -8 matches compact toast visual balance.
    local startY = totalHeight / 2 - 8
    
    -- LINE 1: Category (optional)
    -- NOTE: All text FontStrings use OVERLAY sublevel 7 to render above
    -- glow textures (TopBottom lines at sublevel 5, edgeShine at 6, iconBling at 7)
    if showCategory then
        local category = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        category:SetDrawLayer("OVERLAY", 7)
        category:SetPoint("CENTER", contentFrame, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        category:SetWidth(textAreaWidth)
        category:SetJustifyH("CENTER")
        category:SetText("|cffaaaaaa" .. categoryText .. "|r")
        category:SetWordWrap(false)
        category:SetShadowOffset(1, -1)
        category:SetShadowColor(0, 0, 0, 0.8)
        startY = startY - smallFontHeight - lineSpacing
    end
    
    -- LINE 2: Title (BIG, ACCENT COLOR, NORMAL FONT)
    if showTitle then
        local title = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        title:SetDrawLayer("OVERLAY", 7)
        title:SetPoint("CENTER", contentFrame, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        title:SetWidth(textAreaWidth)
        title:SetJustifyH("CENTER")
        title:SetWordWrap(true)
        title:SetMaxLines(2)
        title:SetShadowOffset(1, -1)
        title:SetShadowColor(0, 0, 0, 0.9)
        
        -- Compute brightened accent color for title
        local tr = math.floor(math.min(255, titleColor[1] * 255 * 1.4))
        local tg = math.floor(math.min(255, titleColor[2] * 255 * 1.4))
        local tb = math.floor(math.min(255, titleColor[3] * 255 * 1.4))
        local titleGradient = string.format("|cff%02x%02x%02x%s|r", tr, tg, tb, titleText)
        title:SetText(titleGradient)
        
        startY = startY - largeFontHeight - lineSpacing
    end
    
    -- LINE 3: Subtitle (MEDIUM SIZE, NORMAL FONT)
    if showSubtitle then
        local subtitle = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        subtitle:SetDrawLayer("OVERLAY", 7)
        subtitle:SetPoint("CENTER", contentFrame, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        subtitle:SetWidth(textAreaWidth)
        subtitle:SetJustifyH("CENTER")
        subtitle:SetText("|cffffffff" .. messageText .. "|r")
        subtitle:SetWordWrap(true)
        subtitle:SetMaxLines(2)
        subtitle:SetShadowOffset(1, -1)
        subtitle:SetShadowColor(0, 0, 0, 0.6)
    end
    
    -- Legacy subtitle support
    if not showSubtitle and subtitleText and subtitleText ~= "" then
        local legacySub = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        legacySub:SetDrawLayer("OVERLAY", 7)
        legacySub:SetPoint("CENTER", contentFrame, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        legacySub:SetWidth(textAreaWidth)
        legacySub:SetJustifyH("CENTER")
        legacySub:SetText("|cffffffff" .. subtitleText .. "|r")
        legacySub:SetWordWrap(true)
        legacySub:SetMaxLines(2)
        legacySub:SetShadowOffset(1, -1)
        legacySub:SetShadowColor(0, 0, 0, 0.6)
    end
    
    -- === CIRCULAR PROGRESS TIMER (bottom-right corner) ===
    local timerSize = 24
    local timerFrame = CreateFrame("Frame", nil, contentFrame)
    timerFrame:SetSize(timerSize, timerSize)
    timerFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -6, 6)
    
    -- Timer spinner (WoW naval map glow trails)
    local timerSpinner = timerFrame:CreateTexture(nil, "OVERLAY")
    timerSpinner:SetAllPoints()
    timerSpinner:SetAtlas("NavalMap-CircleGlowTrails")
    timerSpinner:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1.0)
    timerSpinner:SetBlendMode("ADD")
    
    -- Left-click: open achievement UI + dismiss | Right-click: dismiss only
    popup:SetScript("OnMouseDown", function(self, button)
        if self.isClosing or self._removed then return end
        self.isClosing = true
        
        -- Achievement left-click: open the achievement frame to the specific achievement
        if button == "LeftButton" and self.achievementID and not InCombatLockdown() then
            local achID = self.achievementID
            -- OpenAchievementFrameToAchievement loads Blizzard_AchievementUI on demand
            if OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, achID)
            end
        end
        -- Right-click (or any other button): just dismiss without opening UI
        
        -- Cancel auto-dismiss timer
        if self.dismissTimer then
            self.dismissTimer:Cancel()
            self.dismissTimer = nil
        end
        
        -- Stop timer animations
        if self.timerAg then
            self.timerAg:Stop()
        end
        if self.timerRotateAg then
            self.timerRotateAg:Stop()
        end
        
        -- Stop any existing OnUpdate (like entrance animation)
        self:SetScript("OnUpdate", nil)
        
        -- Quick fade out on click (manual animation)
        local clickStartTime = GetTime()
        local clickDuration = 0.25
        local clickStartAlpha = self:GetAlpha()
        
        self:SetScript("OnUpdate", function(self, elapsed)
            local elapsedTime = GetTime() - clickStartTime
            local progress = math.min(1, elapsedTime / clickDuration)
            
            -- Fade out
            self:SetAlpha(clickStartAlpha * (1 - progress))
            
            -- Animation complete
            if progress >= 1 then
                self:SetScript("OnUpdate", nil)
                RemoveAlert(self)
                end
            end)
    end)
    
    -- Hover effect
    popup:SetScript("OnEnter", function()
        backdropFrame:SetBackdropBorderColor(
            math.min(1, titleColor[1]*1.3),
            math.min(1, titleColor[2]*1.3),
            math.min(1, titleColor[3]*1.3),
            1
        )
    end)
    
    popup:SetScript("OnLeave", function()
        backdropFrame:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    end)
    
    popup.isClosing = false
    
    -- === PLAY SOUND ===
    if playSound then
        PlaySound(config.soundID or 44295)
    end
    
    -- === ANIMATIONS (WoW-STYLE SLIDE DOWN) ===
    
    -- Store anchor info on the popup for later repositioning (and for RepositionAlerts when using separate criteria position)
    popup._anchorPoint = point
    popup._baseX = baseX
    popup._baseY = baseY
    popup._direction = direction
    
    -- Entrance animation: slide FROM the direction we're growing
    -- Growing DOWN → entrance from above (+50), Growing UP → entrance from below (-50)
    local slideOffset = 50 * -direction  -- opposite of growth = where we come from
    local startYOffset = yOffset + slideOffset
    local finalYOffset = yOffset
    
    popup:SetAlpha(0)
    popup:SetPoint(point, UIParent, point, baseX, startYOffset)
    popup.currentYOffset = startYOffset
    popup:Show()
    
    -- Store entrance animation parameters on the frame for dynamic repositioning
    -- RepositionAlerts can update these if the target position changes mid-entrance
    popup._entranceStartY = startYOffset
    popup._entranceTargetY = finalYOffset
    popup._entranceStartTime = GetTime()
    
    -- Note: isEntering was already set to true before RepositionAlerts was called
    
    -- Smooth slide-in animation using OnUpdate (reads targets from frame properties)
    local slideDuration = 0.4
    
    -- Capture anchor for closure
    local _point, _bx = point, baseX
    
    popup:SetScript("OnUpdate", function(self, elapsed)
        local elapsedTime = GetTime() - (self._entranceStartTime or 0)
        local progress = math.min(1, elapsedTime / slideDuration)
        
        -- Smooth easing (OUT)
        local easedProgress = 1 - math.pow(1 - progress, 3)
        
        -- Calculate current position using dynamic targets (may be updated by RepositionAlerts)
        local entryStart = self._entranceStartY or startYOffset
        local entryTarget = self._entranceTargetY or finalYOffset
        local currentY = entryStart + ((entryTarget - entryStart) * easedProgress)
        
        -- Fade in
        self:SetAlpha(math.min(1, self:GetAlpha() + elapsed * 3))
        
        -- Update position
        self:ClearAllPoints()
        self:SetPoint(_point, UIParent, _point, _bx, currentY)
        self.currentYOffset = currentY
        
        -- Animation complete
        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            self.currentYOffset = entryTarget
            self.isEntering = false -- Clear entering flag
            
            -- FLASH SHINE: one-time on appear
            local flashAg = popup:CreateAnimationGroup()
            local flashIn = flashAg:CreateAnimation("Alpha")
            flashIn:SetTarget(flashShine)
            flashIn:SetFromAlpha(0)
            flashIn:SetToAlpha(0.55)
            flashIn:SetDuration(0.08)
            flashIn:SetSmoothing("OUT")
            local flashOut = flashAg:CreateAnimation("Alpha")
            flashOut:SetTarget(flashShine)
            flashOut:SetFromAlpha(0.55)
            flashOut:SetToAlpha(0)
            flashOut:SetDuration(0.4)
            flashOut:SetSmoothing("IN")
            flashOut:SetStartDelay(0.06)
            flashAg:Play()

            -- ROTATING RINGS only
            ring1:SetAlpha(1.0)
            local rotateAg1 = popup:CreateAnimationGroup()
            rotateAg1:SetLooping("REPEAT")
            local rotate1 = rotateAg1:CreateAnimation("Rotation")
            rotate1:SetTarget(ring1)
            rotate1:SetOrigin("CENTER", 0, 0)
            rotate1:SetDegrees(360)
            rotate1:SetDuration(5.4)
            rotateAg1:Play()

            ring2:SetAlpha(1.0)
            local rotateAg2 = popup:CreateAnimationGroup()
            rotateAg2:SetLooping("REPEAT")
            local rotate2 = rotateAg2:CreateAnimation("Rotation")
            rotate2:SetTarget(ring2)
            rotate2:SetOrigin("CENTER", 0, 0)
            rotate2:SetDegrees(-360)
            rotate2:SetDuration(6.2)
            rotateAg2:Play()
        
        -- ICON BLING: always full opacity
        iconBling:SetAlpha(1.0)
        
        -- START CIRCULAR PROGRESS TIMER (rotate + fade)
        -- Rotation animation (continuous loop)
        local rotateLoopAg = timerFrame:CreateAnimationGroup()
        rotateLoopAg:SetLooping("REPEAT")
        local rotateLoop = rotateLoopAg:CreateAnimation("Rotation")
        rotateLoop:SetTarget(timerSpinner)
        rotateLoop:SetOrigin("CENTER", 0, 0)
        rotateLoop:SetDegrees(-360) -- Counter-clockwise for smoother look
        rotateLoop:SetDuration(2.0) -- 2 seconds per rotation
        rotateLoopAg:Play()
        popup.timerRotateAg = rotateLoopAg
        
        -- Fade out animation (shows time remaining)
        local fadeAg = timerFrame:CreateAnimationGroup()
        local timerFade = fadeAg:CreateAnimation("Alpha")
        timerFade:SetTarget(timerSpinner)
        timerFade:SetFromAlpha(1.0)
        timerFade:SetToAlpha(0)
        timerFade:SetDuration(autoDismissDelay)
        timerFade:SetSmoothing("NONE") -- Linear fade
        fadeAg:Play()
        popup.timerAg = fadeAg
        
        -- AUTO-DISMISS: Fade out after configured delay
        local popupRef = popup -- Capture popup reference explicitly
        popup.dismissTimer = C_Timer.NewTimer(autoDismissDelay, function()
            if not popupRef or not popupRef:IsShown() or popupRef.isClosing or popupRef._removed then
                return 
            end
            
            popupRef.isClosing = true
            
            -- Stop timer animations (if still running)
            if popupRef.timerAg then
                popupRef.timerAg:Stop()
            end
            if popupRef.timerRotateAg then
                popupRef.timerRotateAg:Stop()
            end
            
            -- Stop any existing OnUpdate
            popupRef:SetScript("OnUpdate", nil)
            
            -- Fade out and slide away animation (direction-aware)
            local exitStartTime = GetTime()
            local exitDuration = 0.5
            local exitStartY = popupRef.currentYOffset or finalYOffset
            -- Slide away from growth direction: growing DOWN → exit slides UP, growing UP → exit slides DOWN
            local exitDir = popupRef._direction or direction
            local exitEndY = exitStartY + (30 * exitDir)  -- Slide back toward origin
            local exitPoint = popupRef._anchorPoint or point
            local exitBaseX = popupRef._baseX or baseX
            
            popupRef:SetScript("OnUpdate", function(self, elapsed)
                if not self or not self:IsShown() then
                    return
                end
                local elapsedTime = GetTime() - exitStartTime
                local progress = math.min(1, elapsedTime / exitDuration)
                
                -- Smooth easing (IN cubic)
                local easedProgress = math.pow(progress, 3)
                
                -- Fade out
                self:SetAlpha(1 - easedProgress)
                
                -- Slide away
                local currentY = exitStartY + ((exitEndY - exitStartY) * easedProgress)
                self:ClearAllPoints()
                self:SetPoint(exitPoint, UIParent, exitPoint, exitBaseX, currentY)
                
                -- Animation complete
                if progress >= 1 then
                    self:SetScript("OnUpdate", nil)
                    RemoveAlert(self)  -- Use 'self', not 'popup'!
        end
    end)
        end)
        end
    end)
end

--[[============================================================================
    VAULT REMINDER
============================================================================]]

---Check if player has unclaimed vault rewards for the *current* reward period.
---Uses AreRewardsForCurrentRewardPeriod() and CanClaimRewards() when available (Midnight+)
---so expired/previous-period rewards do not trigger the reminder.
---@return boolean hasRewards
function WarbandNexus:HasUnclaimedVaultRewards()
    if not C_WeeklyRewards or not C_WeeklyRewards.HasAvailableRewards then
        return false
    end
    if not C_WeeklyRewards.HasAvailableRewards() then
        return false
    end
    -- Midnight+: only current period and actually claimable
    if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
        local isCurrent = C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()
        if not isCurrent then
            return false
        end
    end
    if C_WeeklyRewards.CanClaimRewards then
        local canClaim = C_WeeklyRewards.CanClaimRewards()
        if not canClaim then
            return false
        end
    end
    -- Midnight+: current-period + can-claim checks are authoritative.
    if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and C_WeeklyRewards.CanClaimRewards then
        return true
    end

    -- Legacy fallback when one/both newer APIs are unavailable.
    local activities = (C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()) or nil
    return activities ~= nil and #activities > 0
end

---Show vault reminder popup (simplified wrapper)
---@param data table Vault data
---@deprecated Use SendMessage(E.VAULT_REWARD_AVAILABLE) instead
function WarbandNexus:ShowVaultReminder(data)
    -- Send vault reward event
    self:SendMessage(E.VAULT_REWARD_AVAILABLE, data or {})
end

--[[============================================================================
    NOTIFICATION SYSTEM INITIALIZATION
============================================================================]]

---Check and queue notifications on login
---Idempotent: safe to call multiple times, only processes once per session
function WarbandNexus:CheckNotificationsOnLogin()
    -- Idempotency guard: prevent double-processing from multiple trigger points
    if self._notificationsChecked then
        return
    end
    
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    local notifs = self.db.profile.notifications
    
    -- Check if notifications are enabled
    if not notifs.enabled then
        return
    end
    
    -- Mark as checked (idempotent - only one trigger path wins)
    self._notificationsChecked = true

    -- Chat line: locale WELCOME_* was unused before; popup alone is invisible in chat-only UIs (e.g. Chattynator).
    C_Timer.After(2, function()
        if WarbandNexus and WarbandNexus.PrintSessionLoginChat then
            WarbandNexus:PrintSessionLoginChat()
        end
    end)
    
    -- 1. Check for new version (What's New)
    if notifs.showUpdateNotes and self:IsNewVersion() then
        QueueNotification({
            type = "update",
            data = CHANGELOG
        })
    end
    
    -- 2. Check for vault rewards (only current reward period + claimable; uses AreRewardsForCurrentRewardPeriod/CanClaimRewards when available)
    if notifs.showVaultReminder then
        C_Timer.After(0.5, function()
            if not C_WeeklyRewards then
                DebugVerbosePrint("|cff888888[Vault]|r C_WeeklyRewards = nil")
                return
            end
            local hasRewards = C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards()
            local isCurrentPeriod = true
            if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
                isCurrentPeriod = C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()
            end
            local canClaim = true
            if C_WeeklyRewards.CanClaimRewards then
                canClaim = C_WeeklyRewards.CanClaimRewards()
            end
            local activities = (C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()) or nil
            local activityCount = activities and #activities or 0
            local secsUntilReset = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()) or nil
            DebugVerbosePrint(string.format("|cff00ccff[Vault]|r HasAvailableRewards=%s | isCurrentPeriod=%s | canClaim=%s | activities=%s | secsUntilReset=%s",
                tostring(hasRewards), tostring(isCurrentPeriod), tostring(canClaim), tostring(activityCount), secsUntilReset and tostring(secsUntilReset) or "n/a"))
            if activities and activityCount > 0 then
                local a1 = activities[1]
                if a1 then
                    DebugVerbosePrint(string.format("|cff00ccff[Vault]|r First activity: type=%s progress=%s threshold=%s",
                        tostring(a1.type), tostring(a1.progress), tostring(a1.threshold)))
                end
            end
            local shouldShow = hasRewards and isCurrentPeriod and canClaim and activities and activityCount > 0
            if shouldShow then
                DebugVerbosePrint("|cff00ccff[Vault]|r Showing reminder (current period, claimable).")
                QueueNotification({
                    type = "vault",
                    data = {}
                })
            else
                if not hasRewards then
                    DebugVerbosePrint("|cff888888[Vault]|r NOT showing: HasAvailableRewards=false.")
                elseif not isCurrentPeriod then
                    DebugVerbosePrint("|cff888888[Vault]|r NOT showing: rewards not for current period (e.g. expired/old season).")
                elseif not canClaim then
                    DebugVerbosePrint("|cff888888[Vault]|r NOT showing: CanClaimRewards=false.")
                else
                    DebugVerbosePrint("|cff888888[Vault]|r NOT showing: no activities.")
                end
            end
        end)
    end
    
    -- Process queue with minimal delay (update notification is immediately queued)
    if HasPendingNotifications() then
        C_Timer.After(0.5, ProcessNotificationQueue)
    else
        -- Vault check has 0.5s delay, check again after it completes
        C_Timer.After(1.5, function()
            if HasPendingNotifications() then
                ProcessNotificationQueue()
            end
        end)
    end
end


--[[============================================================================
    EVENT-DRIVEN NOTIFICATION SYSTEM
    Central event listener for all notification types
============================================================================]]

---Initialize event-driven notification system
function WarbandNexus:InitializeNotificationListeners()
    -- Register for custom notification events
    self:RegisterMessage(E.SHOW_NOTIFICATION, "OnShowNotification")
    
    -- ── BULLETPROOF COLLECTIBLE DISPATCH ──────────────────────────────────────
    -- WN_COLLECTIBLE_OBTAINED has MULTIPLE consumers on WarbandNexus:
    --   1. OnTryCounterCollectibleObtained (try counter reconciliation — TryCounterService)
    --   2. OnCollectibleObtained (popup notification — NotificationManager)
    --   3. OnPlanCollectionUpdated (plan completion detection — PlansManager)
    --
    -- WHY THIS PATTERN:
    --   AceEvent allows only ONE handler per event per object. Without this dispatch,
    --   the last module to register silently overwrites the others — causing notifications
    --   to stop working with NO error message (the root cause of past breakage).
    --
    -- HOW IT WORKS:
    --   Single RegisterMessage handler iterates a dispatch table with pcall protection.
    --   Each consumer is isolated: if one throws an error, the others still run.
    --
    -- ⚠ ADDING A NEW CONSUMER:
    --   Add a new entry to collectibleDispatch below. Do NOT register for
    --   WN_COLLECTIBLE_OBTAINED via RegisterMessage anywhere else in the codebase.
    -- ─────────────────────────────────────────────────────────────────────────
    -- Direct dispatch with pcall isolation.
    -- Each consumer is called explicitly (no table indirection).
    -- pcall ensures one consumer's error doesn't break the others.
    self:RegisterMessage(E.COLLECTIBLE_OBTAINED, function(event, data)
        DebugPrint("|cff00ccff[WN Dispatch]|r WN_COLLECTIBLE_OBTAINED received:"
            .. " type=" .. tostring(data and data.type)
            .. " name=" .. tostring(data and data.name))
        
        -- 1. Try counter reconciliation FIRST (key migration before read)
        if self.OnTryCounterCollectibleObtained then
            local ok, err = pcall(self.OnTryCounterCollectibleObtained, self, event, data)
            if not ok then
                DebugPrint("|cffff0000[WN Dispatch]|r tryCounter ERROR: " .. tostring(err))
            end
        end
        
        -- 2. Popup notification (user feedback)
        if self.OnCollectibleObtained then
            local ok, err = pcall(self.OnCollectibleObtained, self, event, data)
            if not ok then
                DebugPrint("|cffff0000[WN Dispatch]|r notification ERROR: " .. tostring(err))
            end
        end
        
        -- 3. Plan completion detection
        if self.OnPlanCollectionUpdated then
            local ok, err = pcall(self.OnPlanCollectionUpdated, self, event, data)
            if not ok then
                DebugPrint("|cffff0000[WN Dispatch]|r planCompletion ERROR: " .. tostring(err))
            end
        end
    end)
    
    self:RegisterMessage(E.PLAN_COMPLETED, "OnPlanCompleted")
    self:RegisterMessage(E.VAULT_CHECKPOINT_COMPLETED, "OnVaultCheckpointCompleted")
    self:RegisterMessage(E.VAULT_SLOT_COMPLETED, "OnVaultSlotCompleted")
    self:RegisterMessage(E.VAULT_PLAN_COMPLETED, "OnVaultPlanCompleted")
    self:RegisterMessage(E.QUEST_COMPLETED, "OnQuestCompleted")
    -- WN_REPUTATION_GAINED is handled in Core.lua (chat notifications)
    self:RegisterMessage(E.VAULT_REWARD_AVAILABLE, "OnVaultRewardAvailable")
    -- Reminders now use progress-based indicators on plan cards (no popup)
    
    -- Font change listener (low-impact: active notifications auto-dismiss quickly, new ones will use updated font)
    -- NOTE: Uses NotificationEvents as 'self' key to avoid overwriting PlansTrackerWindow's handler.
    WarbandNexus.RegisterMessage(NotificationEvents, E.FONT_CHANGED, function()
        -- Active notifications will pick up new font on next creation
        -- No action needed for already-visible notifications (they auto-dismiss)
    end)
    
    -- Suppress Blizzard's achievement popup if user opted in (apply now and again when Blizzard UI loads)
    self:ApplyBlizzardAchievementAlertSuppression()
    C_Timer.After(0, function()
        if WarbandNexus and WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
            WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
        end
    end)
    self:RegisterEvent("ADDON_LOADED", function(_, event, addonName)
        if addonName == "Blizzard_SharedXML" or addonName == "Blizzard_AchievementUI" then
            if self.ApplyBlizzardAchievementAlertSuppression then
                self:ApplyBlizzardAchievementAlertSuppression()
            end
        end
    end)
end

---Shorten Blizzard's long criteria description to a display name (e.g. "Player Has Opened all X" -> "X").
---@param criteriaString string Full criteria text from GetAchievementCriteriaInfo
---@return string Short display name
local function ShortenCriteriaDisplayName(criteriaString)
    if not criteriaString or criteriaString == "" then return (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
    local s = criteriaString:gsub("^%s+", ""):gsub("%s+$", "")
    local prefixes = {
        "player has opened all ", "player has opened ", "player has open ", "player has collected all ", "player has collected ",
        "player has discovered ", "player has find ", "you have opened all ", "you have opened ", "you have collected ",
        "you've opened ", "you've collected ", "open all ", "opened all ", "open ", "opened ", "collect all ", "collect ",
        "discover ", "find all ", "find ", "earn ", "obtain ", "all ",
    }
    local changed = true
    while changed do
        changed = false
        local lower = s:lower()
        for _, p in ipairs(prefixes) do
            if lower:sub(1, #p) == p then
                s = s:sub(#p + 1):gsub("^%s+", ""):gsub("%s+$", "")
                changed = true
                break
            end
        end
    end
    return (s ~= "" and s) or criteriaString
end

---Show toast for progressive achievements (e.g. Treasures of X, multi-step): one step completed = "Achievement Progress" title + criteria name only.
---Gated by showCriteriaProgressNotifications.
---@param achievementID number
---@param criteriaIndex number|nil Optional; if nil we still show progress for the achievement.
function WarbandNexus:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
    if not achievementID or type(achievementID) ~= "number" then return end
    local db = self.db and self.db.profile and self.db.profile.notifications
    if not db or not db.showCriteriaProgressNotifications then return end
    -- Dependency rule: criteria progress is an achievement sub-notification.
    -- If achievement or collectible popups are disabled, skip progress toasts too.
    if not db.showAchievementNotifications or not db.showLootNotifications then return end
    if issecretvalue and issecretvalue(achievementID) then return end

    -- Do not show progress toast when achievement is already completed (avoids overlap with "Achievement Earned" / collectible toast)
    local _, _, _, completed = GetAchievementInfo(achievementID)
    if completed then return end

    local numCriteria = GetAchievementNumCriteria(achievementID)
    if not numCriteria or numCriteria == 0 then return end

    -- Blizzard AddAlert passes (achievementID, criteriaName) — that string IS the display name (progress completed). Use it as-is.
    local displayNameFromEvent = nil
    if type(criteriaIndex) == "string" and criteriaIndex ~= "" then
        displayNameFromEvent = criteriaIndex
        if issecretvalue and issecretvalue(displayNameFromEvent) then displayNameFromEvent = nil end
        local wantName = criteriaIndex
        criteriaIndex = nil
        for i = 1, numCriteria do
            local name = GetAchievementCriteriaInfo(achievementID, i)
            if issecretvalue and name and issecretvalue(name) then name = nil end
            if name and name == wantName then criteriaIndex = i break end
        end
    elseif type(criteriaIndex) ~= "number" or criteriaIndex < 1 or criteriaIndex > numCriteria then
        criteriaIndex = nil
    end

    local completed = 0
    local criteriaName = ""
    if criteriaIndex and criteriaIndex >= 1 and criteriaIndex <= numCriteria then
        for i = 1, numCriteria do
            local _, _, comp = GetAchievementCriteriaInfo(achievementID, i)
            if comp then completed = completed + 1 end
        end
        criteriaName = displayNameFromEvent or ""
        if criteriaName == "" then
            local name = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
            if issecretvalue and name and issecretvalue(name) then name = nil end
            criteriaName = (name and name ~= "" and name) and ShortenCriteriaDisplayName(name) or (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria"
        end
    else
        for i = 1, numCriteria do
            local name, _, comp = GetAchievementCriteriaInfo(achievementID, i)
            if comp then completed = completed + 1 end
            if not criteriaName or criteriaName == "" then
                if issecretvalue and name and issecretvalue(name) then name = nil end
                criteriaName = (name and name ~= "" and name) and ShortenCriteriaDisplayName(name) or ""
            end
        end
        if criteriaName == "" then criteriaName = (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
    end
    
    if displayNameFromEvent and displayNameFromEvent ~= "" then
        criteriaName = displayNameFromEvent
    end
    
    local _, achName, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(achievementID)
    if issecretvalue and achName and issecretvalue(achName) then achName = nil end
    if issecretvalue and achIcon and issecretvalue(achIcon) then achIcon = nil end
    
    local criteriaTitleText = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"
    
    self:ShowModalNotification({
        compact = true,
        criteriaTitle = criteriaTitleText,
        icon = achIcon or CATEGORY_ICONS.achievement,
        itemName = criteriaName,
        action = nil,
        achievementID = achievementID,
        playSound = false,
        autoDismiss = 3,
    })
end

---Install frame-level suppression: when "Replace Achievement Popup" is on, Blizzard alert
---frames are hidden as soon as they Show(), so we never see their toast.
local function shouldSuppressBlizzardAlert()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    return db and db.hideBlizzardAchievementAlert
end

---Only hide Blizzard *criteria* toast frames (used when we suppress criteria progress).
---Full achievement path is left as-is; do not hide AchievementAlertFrame here.
local function HideVisibleBlizzardCriteriaFramesOnly()
    if not shouldSuppressBlizzardAlert() then return end
    local max = _G.MAX_ACHIEVEMENT_ALERTS or 4
    for i = 1, max do
        local f = _G["CriteriaAlertFrame" .. i]
        if f and f.IsShown and f:IsShown() and f.Hide then pcall(function() f:Hide() end) end
    end
    local cf = _G.CriteriaAlertFrame
    if cf and cf.IsShown and cf:IsShown() and cf.Hide then pcall(function() cf:Hide() end) end
end

---Only hook Criteria* frames so we hide Blizzard criteria toasts; leave Achievement* frames untouched.
local function InstallBlizzardAlertFrameHooks()
    local function hideIfSuppress(frame)
        if frame and frame.Hide and shouldSuppressBlizzardAlert() then
            frame:Hide()
        end
    end
    local max = _G.MAX_ACHIEVEMENT_ALERTS or 4
    for i = 1, max do
        local f = _G["CriteriaAlertFrame" .. i]
        if f and not f._wnHideHooked then
            f:HookScript("OnShow", function(self) hideIfSuppress(self) end)
            f._wnHideHooked = true
        end
    end
    local cf = _G.CriteriaAlertFrame
    if cf and not cf._wnHideHooked then
        cf:HookScript("OnShow", function(self) hideIfSuppress(self) end)
        cf._wnHideHooked = true
    end
end

---Suppress or restore Blizzard's default achievement alert popup
---When "Replace Achievement Popup" is enabled: suppress Blizzard, show only our notification.
---1) AddAlert hook so we show ours and don't call Blizzard. 2) Frame OnShow hook so if
---Blizzard's frame still appears it is hidden immediately.
function WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
    local shouldHide = self.db and self.db.profile and self.db.profile.notifications
        and self.db.profile.notifications.hideBlizzardAchievementAlert

    -- 1) AddAlert hook: we show our notification and skip Blizzard
    if AchievementAlertSystem then
        if not self._origAchievementAddAlert then
            self._origAchievementAddAlert = AchievementAlertSystem.AddAlert
        end
        local orig = self._origAchievementAddAlert
        if shouldHide then
            AchievementAlertSystem.AddAlert = function(sys, a1, a2, ...)
                local hasExtra = (a2 ~= nil) or (select("#", ...) > 0)
                -- Full achievement: show ours when "Replace" is on; if we don't show (e.g. notifications off), fallback to Blizzard next frame
                if not hasExtra and type(a1) == "number" then
                    local arg1, arg2 = a1, a2
                    if WarbandNexus.ShowAchievementNotification then
                        WarbandNexus:ShowAchievementNotification(a1)
                    end
                    C_Timer.After(0, function()
                        if not ns.achievementNotificationShown then
                            pcall(orig, sys, arg1, arg2)
                        end
                        ns.achievementNotificationShown = nil
                    end)
                    return
                end
                -- Progressive achievement: defer one frame so client has updated completed state; then show full achievement only if completed, else progress.
                if hasExtra and type(a1) == "number" then
                    local aid, a2copy = a1, a2
                    C_Timer.After(0, function()
                        local _, _, _, completed = GetAchievementInfo(aid)
                        if completed and WarbandNexus.ShowAchievementNotification then
                            WarbandNexus:ShowAchievementNotification(aid)
                        else
                            WarbandNexus:ShowCriteriaProgressNotification(aid, a2copy)
                        end
                        HideVisibleBlizzardCriteriaFramesOnly()
                    end)
                    return
                end
                return orig(sys, a1, a2, ...)
            end
        else
            AchievementAlertSystem.AddAlert = orig
        end
    end

    if CriteriaAlertSystem and CriteriaAlertSystem.AddAlert then
        if not self._origCriteriaAddAlert then
            self._origCriteriaAddAlert = CriteriaAlertSystem.AddAlert
        end
        local origCrit = self._origCriteriaAddAlert
        if shouldHide then
            CriteriaAlertSystem.AddAlert = function(sys, a1, a2, ...)
                if type(a1) == "number" then
                    local aid, a2copy = a1, a2
                    C_Timer.After(0, function()
                        local _, _, _, completed = GetAchievementInfo(aid)
                        if completed and WarbandNexus.ShowAchievementNotification then
                            WarbandNexus:ShowAchievementNotification(aid)
                        else
                            WarbandNexus:ShowCriteriaProgressNotification(aid, a2copy)
                        end
                    end)
                    return
                end
                return origCrit(sys, a1, a2, ...)
            end
        else
            CriteriaAlertSystem.AddAlert = origCrit
        end
    end

    -- 2) Frame-level: hook OnShow so frames hide when shown; retry so we catch lazily-created frames
    if shouldHide then
        InstallBlizzardAlertFrameHooks()
        C_Timer.After(0.5, InstallBlizzardAlertFrameHooks)
        C_Timer.After(2, InstallBlizzardAlertFrameHooks)
    end
end

---Generic notification handler
---@param event string Event name
---@param payload table Notification payload
function WarbandNexus:OnShowNotification(event, payload)
    if not payload or not payload.data then return end
    
    -- Direct passthrough to ShowModalNotification
    self:ShowModalNotification(payload.data)
end

-- ============================================================================
-- SCREEN FLASH EFFECT
-- ============================================================================

local screenFlashFrame = nil

---Play a full-screen flash effect (accent-colored edge vignette that fades out)
---@param duration number Duration in seconds (default 0.6)
function WarbandNexus:PlayScreenFlash(duration)
    duration = duration or 0.6
    
    -- Check setting
    if not self.db or not self.db.profile or not self.db.profile.notifications then return end
    if not self.db.profile.notifications.screenFlashEffect then return end
    
    -- Don't flash during combat
    if InCombatLockdown() then return end
    
    -- Create frame on first use
    if not screenFlashFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(9999)
        f:EnableMouse(false)
        f:SetMouseClickEnabled(false)
        
        -- Center flash (full screen, soft white → transparent)
        local flash = f:CreateTexture(nil, "BACKGROUND")
        flash:SetAllPoints()
        flash:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        flash:SetBlendMode("ADD")
        f.flash = flash
        
        -- Edge vignette (accent-colored glow around screen edges)
        local vignette = f:CreateTexture(nil, "ARTWORK")
        vignette:SetAllPoints()
        vignette:SetAtlas("Vignetting", true)
        vignette:SetBlendMode("ADD")
        f.vignette = vignette
        
        -- Animation group for fade out
        local ag = f:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetSmoothing("OUT")
        ag:SetScript("OnFinished", function()
            f:Hide()
        end)
        f.fadeAnim = ag
        f.fadeOut = fadeOut
        
        screenFlashFrame = f
    end
    
    local f = screenFlashFrame
    
    -- Get theme accent color
    local accentColor = (ns.UI_COLORS and ns.UI_COLORS.accent) or {0.40, 0.20, 0.58}
    
    -- Set colors: center flash is subtle white, vignette is accent-colored
    f.flash:SetVertexColor(1, 1, 1, 0.15)
    f.vignette:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    
    -- Configure and play
    f.fadeOut:SetDuration(duration)
    f:SetAlpha(1)
    f:Show()
    f.fadeAnim:Stop()
    f.fadeAnim:Play()
end

---Collectible obtained handler (mount/pet/toy/achievement/title/illusion)
---@param event string Event name
---@param data table {type, id, name, icon}
function WarbandNexus:OnCollectibleObtained(event, data)
    if not data or not data.type then return end
    -- Achievement can have nil/empty name (hidden achievements); use fallback for display
    local displayName = data.name
    if (not displayName or displayName == "") and data.type == "achievement" then
        displayName = (ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement"
    end
    if not displayName or displayName == "" then return end
    
    NotifyDebug("Collectible obtained: %s - %s (ID: %s)",
        data.type or "nil",
        displayName or "nil",
        tostring(data.id or "nil"))
    
    -- Check if loot notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        NotifyDebug("|cffff6600BLOCKED: notifications table missing|r")
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
        NotifyDebug("|cffff6600BLOCKED: showLootNotifications = false|r")
        return
    end
    
    -- Per-type toggle check
    local typeToggleMap = {
        mount = "showMountNotifications",
        pet = "showPetNotifications",
        toy = "showToyNotifications",
        transmog = "showTransmogNotifications",
        illusion = "showIllusionNotifications",
        title = "showTitleNotifications",
        achievement = "showAchievementNotifications",
    }
    local toggleKey = typeToggleMap[data.type]
    if toggleKey and self.db.profile.notifications[toggleKey] == false then
        NotifyDebug("|cffff6600BLOCKED: %s = false|r", toggleKey)
        return
    end

    -- TryCounter fires on loot; CollectionService fires on NEW_MOUNT / journal — same mount, two toasts.
    -- Normalize mount itemID → mountID so both payloads share one dedupe key.
    local lootToastDedupeKey = BuildCollectibleLootToastDedupeKey(data)
    if lootToastDedupeKey then
        local nowDedupe = GetTime()
        local prevToast = lastCollectibleLootToastShownAt[lootToastDedupeKey]
        if prevToast and (nowDedupe - prevToast) < COLLECTIBLE_LOOT_TOAST_DEDUP_SEC then
            NotifyDebug("|cff888888Skipped duplicate collectible loot toast: %s|r", lootToastDedupeKey)
            return
        end
    end
    
    -- Achievement notifications: only show ours when we're hiding Blizzard's
    -- If hideBlizzardAchievementAlert is false (unchecked), Blizzard shows its own popup,
    -- so we skip ours to avoid duplicate notifications
    if data.type == "achievement" and not self.db.profile.notifications.hideBlizzardAchievementAlert then
        NotifyDebug("|cffff6600BLOCKED: achievement (Blizzard popup enabled)|r")
        return
    end
    
    -- Build try count message for mount/pet/toy/illusion/item (the "BAM" moment — farmed drop obtained)
    -- When TryCounter sends preResetTryCount, we always show the celebratory message and flash.
    local tryMessage = nil
    local hasTryCount = false
    local tryCountTypes = { mount = true, pet = true, toy = true, illusion = true, item = true }
    if tryCountTypes[data.type] and data.id then
        -- If TryCounter sent preResetTryCount, this is a detected drop — always treat as drop source for celebration
        local isDropSource = (data.preResetTryCount ~= nil) or (self.IsDropSourceCollectible and self:IsDropSourceCollectible(data.type, data.id))
        -- Use preResetTryCount if provided (0 = first try; counter was reset before notification fired)
        local failedCount = (data.preResetTryCount ~= nil) and data.preResetTryCount or (self.GetTryCount and self:GetTryCount(data.type, data.id)) or 0

        NotifyDebug("Try count: isDropSource=%s, failedCount=%d, preResetTryCount=%s",
            tostring(isDropSource),
            failedCount,
            tostring(data.preResetTryCount))

        local isGuaranteed = self.IsGuaranteedCollectible and self:IsGuaranteedCollectible(data.type, data.id)
        if not isGuaranteed then
            -- Add +1 for the current successful attempt if the item is a known drop source
            -- This gives the real total: e.g. 0 failed + 1 success = "first try!"
            local count = isDropSource and (failedCount + 1) or failedCount
            if count > 0 then
                hasTryCount = true
                -- Subtitle only: item name is already the title line (avoid "grind + N attempts" redundancy).
                if count == 1 then
                    tryMessage = (ns.L and ns.L["NOTIFICATION_FIRST_TRY"]) or "You got it on your first try!"
                else
                    local fmt = (ns.L and ns.L["NOTIFICATION_GOT_IT_AFTER"]) or "You got it after %d attempts!"
                    tryMessage = string.format(fmt, count)
                end
            end
        end
    end
    
    NotifyDebug("SHOWING notification: hasTryCount=%s, tryMessage=%s",
        tostring(hasTryCount),
        tryMessage or "nil")
    
    -- Show notification (try message replaces default subtitle for farmed drops only)
    local overrides = {}
    if tryMessage then
        overrides.action = tryMessage
    end
    -- Attach achievement ID so click handler can open the achievement UI
    if data.type == "achievement" and data.id then
        overrides.achievementID = data.id
        local pts = tonumber(data.achievementPoints)
        if pts == nil or pts < 0 then
            local ok, _, _, p = pcall(GetAchievementInfo, data.id)
            if ok and type(p) == "number" and p >= 0 then
                pts = p
            else
                pts = 0
            end
        end
        local doneMsg = (ns.L and ns.L["ACHIEVEMENT_COMPLETED_MSG"]) or "Achievement completed!"
        local ptsFmt = (ns.L and ns.L["ACHIEVEMENT_POINTS_FORMAT"]) or "%d pts"
        overrides.action = string.format("%s  ·  %s", doneMsg, string.format(ptsFmt, pts))
    end
    -- So AddAlert hook fallback knows we showed ours (don't show Blizzard)
    if data.type == "achievement" then
        ns.achievementNotificationShown = true
    end
    -- Farmed drop obtained: keep notification on screen longer for the "yeeey" moment
    if hasTryCount then
        overrides.autoDismiss = 7
    end
    self:Notify(data.type, displayName, data.icon, overrides)
    if lootToastDedupeKey then
        lastCollectibleLootToastShownAt[lootToastDedupeKey] = GetTime()
    end

    -- Screen flash (setting: screenFlashEffect) + optional screenshot — try-tracked collectible drop
    if hasTryCount then
        self:PlayScreenFlash(0.6)
        if self.db.profile.notifications.tryCounterDropScreenshot ~= false then
            C_Timer.After(0.3, function()
                local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
                if db and db.tryCounterDropScreenshot ~= false and Screenshot then
                    Screenshot()
                end
            end)
        end
    end
end

---Plan completed handler
---@param event string Event name
---@param data table {planType, name, icon}
function WarbandNexus:OnPlanCompleted(event, data)
    if not data or not data.name then return end
    
    -- Use planType icon fallback chain: data.icon → planType category icon → plan default
    local icon = data.icon or CATEGORY_ICONS[data.planType] or CATEGORY_ICONS.plan
    self:Notify("plan", data.name, icon)
end

-- Shared vault/quest lookup tables (defined once, used by multiple handlers)
local VAULT_CATEGORIES = {
    dungeon = {name = (ns.L and ns.L["DUNGEON_CAT"]) or "Dungeon", atlas = "questlog-questtypeicon-heroic", thresholds = {1, 4, 8}},
    raid    = {name = (ns.L and ns.L["RAID_CAT"]) or "Raid",    atlas = "questlog-questtypeicon-raid",   thresholds = {2, 4, 6}},
    world   = {name = (ns.L and ns.L["WORLD_CAT"]) or "World",   atlas = "questlog-questtypeicon-Delves", thresholds = {2, 4, 8}},
}

local QUEST_CATEGORIES = {
    dailyQuests         = {name = (ns.L and ns.L["DAILY_QUEST_CAT"]) or "Daily Quest",         atlas = "questlog-questtypeicon-heroic"},
    worldQuests         = {name = (ns.L and ns.L["WORLD_QUEST_CAT"]) or "World Quest",         atlas = "questlog-questtypeicon-Delves"},
    weeklyQuests        = {name = (ns.L and ns.L["WEEKLY_QUEST_CAT"]) or "Weekly Quest",        atlas = "questlog-questtypeicon-raid"},
    assignments         = {name = (ns.L and ns.L["SPECIAL_ASSIGNMENT_CAT"]) or "Assignment",    atlas = "questlog-questtypeicon-heroic"},
    events              = {name = (ns.L and ns.L["QUEST_CAT_CONTENT_EVENTS"]) or "Content Event", atlas = "worldquest-questmarker-epic"},
    specialAssignments  = {name = (ns.L and ns.L["SPECIAL_ASSIGNMENT_CAT"]) or "Special Assignment",  atlas = "questlog-questtypeicon-heroic"},
    delves              = {name = (ns.L and ns.L["DELVE_CAT"]) or "Delve",               atlas = "questlog-questtypeicon-Delves"},
}

---Vault checkpoint completed handler (individual progress gain)
---@param event string Event name
---@param data table {characterName, category, progress}
function WarbandNexus:OnVaultCheckpointCompleted(event, data)
    if not data or not data.characterName or not data.category or not data.progress then return end
    
    local cat = VAULT_CATEGORIES[data.category] or {name = (ns.L and ns.L["ACTIVITY_CAT"]) or "Activity", atlas = "greatVault-whole-normal", thresholds = {1, 4, 8}}
    
    -- Find current threshold
    local currentThreshold = cat.thresholds[#cat.thresholds]
    for _, t in ipairs(cat.thresholds) do
        if data.progress <= t then currentThreshold = t; break end
    end
    
    self:Notify("vault", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = string.format((ns.L and ns.L["PROGRESS_COUNT_FORMAT"]) or "%d/%d Progress", data.progress, currentThreshold),
    })
end

---Vault slot completed handler
---@param event string Event name
---@param data table {characterName, category, slotIndex, threshold}
function WarbandNexus:OnVaultSlotCompleted(event, data)
    if not data or not data.characterName or not data.category then return end

    local cat = VAULT_CATEGORIES[data.category] or {name = (ns.L and ns.L["ACTIVITY_CAT"]) or "Activity", atlas = "greatVault-whole-normal", thresholds = {1, 4, 8}}
    local threshold = data.threshold or 0

    -- Small progress toast (Progress 2/2, 4/4 + category name) when user has progress toasts enabled
    local db = self.db and self.db.profile and self.db.profile.notifications
    if db and db.showCriteriaProgressNotifications and threshold and threshold > 0 then
        self:ShowModalNotification({
            compact = true,
            iconAtlas = cat.atlas,
            itemName = cat.name,
            action = string.format((ns.L and ns.L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", threshold, threshold),
            playSound = false,
            autoDismiss = 3,
        })
    end

    self:Notify("vault", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = string.format((ns.L and ns.L["PROGRESS_COMPLETED_FORMAT"]) or "%d/%d Progress Completed", threshold, threshold),
    })
end

---Vault plan fully completed handler
---@param event string Event name
---@param data table {characterName}
function WarbandNexus:OnVaultPlanCompleted(event, data)
    if not data or not data.characterName then return end
    
    self:Notify("vault", string.format((ns.L and ns.L["WEEKLY_VAULT_PLAN_FORMAT"]) or "Weekly Vault Plan - %s", data.characterName), nil, {
        iconAtlas = "greatVault-whole-normal",
        action = (ns.L and ns.L["ALL_SLOTS_COMPLETE"]) or "All Slots Complete!",
    })
end

---Quest completed handler
---@param event string Event name
---@param data table {characterName, category, questTitle}
function WarbandNexus:OnQuestCompleted(event, data)
    if not data or not data.characterName or not data.questTitle then return end
    
    local cat = QUEST_CATEGORIES[data.category] or {name = (ns.L and ns.L["QUEST_LABEL"]) or "Quest:", atlas = "questlog-questtypeicon-heroic"}
    
    self:Notify("quest", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = data.questTitle .. " " .. ((ns.L and ns.L["QUEST_COMPLETED_SUFFIX"]) or "Completed"),
    })
end


---Vault reward available handler
---@param event string Event name
---@param data table Vault reward data (optional)
function WarbandNexus:OnVaultRewardAvailable(event, data)
    -- Check if vault notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showVaultReminder then
        return
    end
    
    self:Notify("vault", (ns.L and ns.L["WEEKLY_VAULT_READY"]) or "Weekly Vault Ready!", CATEGORY_ICONS.vault, {
        action = (ns.L and ns.L["UNCLAIMED_REWARDS"]) or "You have unclaimed rewards",
    })
end

--[[============================================================================
    LOOT NOTIFICATIONS (MOUNT/PET/TOY)
============================================================================]]

---Show loot notification (compatibility wrapper — resolves icon then delegates to Notify)
---@param itemID number Item ID (or mount/pet ID)
---@param itemLink string Item link
---@param itemName string Item name
---Initialize loot notification system
function WarbandNexus:InitializeLootNotifications()
    -- Initialize event-driven notification system
    self:InitializeNotificationListeners()
    
    -- CollectionService handles collection detection
    -- NotificationManager only provides display functions
end


---Test loot notification system (All notification types with real data)
function WarbandNexus:TestLootNotification(type, id, step)
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Notification Test (simulate events) ===|r")
        self:Print("|cff44ff44/wn testloot earn [id]|r - Simulate achievement EARNED (only WN notification, no Blizzard)")
        self:Print("|cff44ff44/wn testloot progress [id] [step]|r - Simulate PROGRESSIVE step (Progress X/Y toast, e.g. Treasures of X)")
        self:Print("|cff44ff44/wn testloot both [id] [step]|r - Show BOTH progress toast + full notification (for UI testing)")
        self:Print("|cff888888  /wn testloot earn 6|r  Level 10 earned")
        self:Print("|cff888888  /wn testloot progress|r  or |cff888888progress 6|r  (auto-picks ID with criteria)")
        self:Print("|cff888888  /wn testloot both|r  or |cff888888both 6|r  (both toasts)")
        self:Print("|cffffcc00/wn testloot mount [id]|r - Mount | |cffffcc00pet|r | |cffffcc00toy|r | |cffffcc00achievement [id]|r | |cffffcc00plan [id]|r")
        self:Print("|cffffcc00/wn testloot blizzard [id]|r - Legacy: trigger Blizzard AddAlert (may show both)")
        return
    end

    -- Simulate "achievement earned" — only our notification, no Blizzard. Shows exactly what addon shows when you earn one.
    if type == "earn" then
        local achievementID = tonumber(id) or 6
        local ok, name, _, _, _, _, _, _, _, icon = pcall(GetAchievementInfo, achievementID)
        if not ok or not name then
            self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
            return
        end
        self:Print("|cff00ccffSimulating achievement earned (ID " .. achievementID .. ") — only WN notification:|r " .. tostring(name))
        self:Notify("achievement", name, icon)
        return
    end

    -- Resolve achievement ID for progress/both: try preferredID first, then fallback list (40752 may not exist on all clients).
    local function resolveAchievementWithCriteria(preferredID)
        local tryIDs = { 6, 7, 8, 11, 12, 60981, 40752 }
        if preferredID then
            tryIDs = { preferredID, 6, 7, 8, 11, 12, 60981, 40752 }
        end
        for _, fid in ipairs(tryIDs) do
            local name = select(2, GetAchievementInfo(fid))
            if name and name ~= "" then
                local ok, n = pcall(GetAchievementNumCriteria, fid)
                if ok and n and n > 0 then
                    return fid, n
                end
            end
        end
        return nil, 0
    end

    -- Simulate "progressive achievement step" (e.g. Treasures of X — one step done). Only our Progress X/Y toast.
    if type == "progress" then
        local preferredID = tonumber(id)
        local achievementID, numCriteria = resolveAchievementWithCriteria(preferredID)
        if not achievementID then
            self:Print("|cffff0000No valid achievement with criteria found. Try: /wn testloot progress 6|r")
            return
        end
        local criteriaIndex = math.min(tonumber(step) or 1, numCriteria)
        if criteriaIndex < 1 then criteriaIndex = 1 end
        local _, name = GetAchievementInfo(achievementID)
        self:Print("|cff00ccffSimulating progressive step (ID " .. achievementID .. ", step " .. criteriaIndex .. "/" .. numCriteria .. ") — only WN toast:|r " .. tostring(name))
        self:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
        return
    end

    -- Show both progress toast and full achievement notification (stacked, for UI testing)
    if type == "both" then
        local preferredID = tonumber(id)
        local achievementID, numCriteria = resolveAchievementWithCriteria(preferredID)
        if not achievementID then
            self:Print("|cffff0000No valid achievement with criteria found. Try: /wn testloot both 6|r")
            return
        end
        local criteriaIndex = math.min(tonumber(step) or 1, numCriteria)
        if criteriaIndex < 1 then criteriaIndex = 1 end
        local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
        self:Print("|cff00ccffShowing BOTH (progress + full) for UI test:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
        self:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
        C_Timer.After(0.4, function()
            if WarbandNexus and WarbandNexus.Notify then
                WarbandNexus:Notify("achievement", name, icon, { achievementID = achievementID })
            end
        end)
        return
    end

    -- Legacy: Test Blizzard achievement popup vs our notification
    -- Loads Blizzard_AchievementUI first so AddAlert works without errors
    if type == "blizzard" then
        local achievementID = id or 6  -- Default: Level 10
        local _, achievementName, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(achievementID)
        if not achievementName then
            self:Print("|cffff0000Invalid achievement ID: " .. achievementID .. "|r")
            return
        end
        
        -- Ensure Blizzard_AchievementUI is loaded (provides AchievementShield_OnLoad etc.)
        -- TAINT GUARD: LoadAddOn is a protected action; cannot call during combat
        if not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
            Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
        end
        
        -- Check suppression state
        local isSuppressed = self.db and self.db.profile and self.db.profile.notifications
            and self.db.profile.notifications.hideBlizzardAchievementAlert
        
        self:Print("|cff00ccff=== Blizzard Achievement Alert Test ===|r")
        self:Print("|cffffcc00Achievement:|r " .. achievementName .. " (ID: " .. achievementID .. ")")
        self:Print("|cffffcc00Blizzard Alert Suppressed:|r " .. (isSuppressed and "|cff44ff44YES|r" or "|cffff4444NO|r"))
        
        -- Trigger Blizzard's popup through the CURRENT AddAlert function (our hook swallows it when suppressed)
        if AchievementAlertSystem and AchievementAlertSystem.AddAlert then
            local success, err = pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID)
            if success then
                if isSuppressed then
                    self:Print("|cff888888Blizzard popup suppressed - you should NOT see it|r")
                    -- Test-only: some builds show Blizzard frame via another path; hide it so test shows only ours
                    local function hideBlizzardFramesForTest()
                        for i = 1, (_G.MAX_ACHIEVEMENT_ALERTS or 4) do
                            local f = _G["AchievementAlertFrame" .. i]
                            if f and f.Hide then pcall(function() f:Hide() end) end
                        end
                    end
                    C_Timer.After(0, hideBlizzardFramesForTest)
                    C_Timer.After(0.1, hideBlizzardFramesForTest)
                    C_Timer.After(0.35, hideBlizzardFramesForTest)
                else
                    self:Print("|cff00ff00Blizzard popup triggered - you should see it at top of screen|r")
                end
            else
                self:Print("|cffff8800Blizzard alert error: " .. tostring(err) .. "|r")
            end
        end
        
        -- Show OUR notification
        C_Timer.After(0.3, function()
            self:Notify("achievement", achievementName, achIcon)
        end)
        
        self:Print("|cff888888Toggle: Settings > Notifications > Replace Achievement Popup (Hide Blizzard)|r")
        return
    end
    
    -- Test suppression: trigger Blizzard's *criteria progress* alert; with "Replace Popup" ON only our toast should appear
    if type == "suppress" then
        local achievementID = id or 40752
        local ok, n = pcall(GetAchievementNumCriteria, achievementID)
        local numCriteria = (ok and n and n > 0) and n or nil
        if not numCriteria then
            local fallbackAchIds = { 6, 7, 8, 60981 }
            for fi = 1, #fallbackAchIds do
                local fid = fallbackAchIds[fi]
                local ok2, n2 = pcall(GetAchievementNumCriteria, fid)
                if ok2 and n2 and n2 > 0 then achievementID = fid; numCriteria = n2; break end
            end
        end
        if not numCriteria or numCriteria == 0 then
            self:Print("|cffff0000No achievement with criteria. Try: /wn testloot suppress 40752|r")
            return
        end
        local _, achievementName = GetAchievementInfo(achievementID)
        if not achievementName then
            self:Print("|cffff0000Invalid achievement ID: " .. achievementID .. "|r")
            return
        end
        if not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
            Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
        end
        local isSuppressed = self.db and self.db.profile and self.db.profile.notifications
            and self.db.profile.notifications.hideBlizzardAchievementAlert
        self:Print("|cff00ccff=== Suppression Test (Criteria Progress) ===|r")
        self:Print("|cffffcc00Achievement:|r " .. achievementName .. " (ID: " .. achievementID .. ", criteria 1/" .. numCriteria .. ")")
        self:Print("|cffffcc00Replace Achievement Popup:|r " .. (isSuppressed and "|cff44ff44ON - only WN toast should appear|r" or "|cffff4444OFF - Blizzard toast may appear too|r"))
        -- Trigger Blizzard's criteria progress AddAlert(achievementID, criteriaIndex); our hook shows our toast and suppresses theirs when setting is ON
        if AchievementAlertSystem and AchievementAlertSystem.AddAlert then
            pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID, 1)
        end
        self:Print("|cff888888Toggle: Settings > Notifications > Replace Achievement Popup|r")
        return
    end
    
    -- Test criteria progress toast (small Progress X/Y + criteria name); always shows for testing
    if type == "criteria" then
        local achievementID = id or 40752  -- Default: The Loremaster (has many criteria)
        local ok, n = pcall(GetAchievementNumCriteria, achievementID)
        local numCriteria = (ok and n and n > 0) and n or nil
        if not numCriteria then
            local tryAchIds = { 6, 7, 8, 60981, 11, 12 }
            for ti = 1, #tryAchIds do
                local fid = tryAchIds[ti]
                local ok2, n2 = pcall(GetAchievementNumCriteria, fid)
                if ok2 and n2 and n2 > 0 then achievementID = fid; numCriteria = n2; break end
            end
        end
        if not numCriteria or numCriteria == 0 then
            self:Print("|cffff0000No achievement with criteria. Try: /wn testloot criteria 40752|r")
            return
        end
        local completed = 0
        local criteriaName = ""
        for i = 1, numCriteria do
            local name, _, comp = GetAchievementCriteriaInfo(achievementID, i)
            if comp then completed = completed + 1 end
            if i == 1 and name and name ~= "" then criteriaName = name end
        end
        if criteriaName == "" then criteriaName = (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
        local _, _, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(achievementID)
        local progressStr = string.format((ns.L and ns.L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", completed, numCriteria)
        self:ShowModalNotification({
            compact = true,
            icon = achIcon or CATEGORY_ICONS.achievement,
            itemName = criteriaName,
            action = progressStr,
            achievementID = achievementID,
            playSound = false,
            autoDismiss = 3,
        })
        self:Print("|cff00ff00Criteria progress toast shown (achievement ID: " .. achievementID .. ", " .. progressStr .. ")|r")
        return
    end
    
    -- Test weekly vault slot progress toast (2/2, 4/4 style)
    if type == "vaultprogress" then
        local db = self.db and self.db.profile and self.db.profile.notifications
        if not db or not db.showCriteriaProgressNotifications then
            self:Print("|cffff8800Enable Settings > Notifications > Criteria Progress Toast to see vault progress toasts.|r")
        end
        local cat = VAULT_CATEGORIES.dungeon or {name = "Dungeon", atlas = "questlog-questtypeicon-heroic"}
        self:ShowModalNotification({
            compact = true,
            iconAtlas = cat.atlas,
            itemName = cat.name,
            action = string.format((ns.L and ns.L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", 4, 4),
            playSound = false,
            autoDismiss = 3,
        })
        self:Print("|cff00ff00Vault progress toast shown (4/4 " .. cat.name .. ")|r")
        return
    end
    
    local delay = 0
    
    -- Show mount test (Real mount ID: 460 = Grand Black War Mammoth)
    if type == "mount" or type == "all" then
        C_Timer.After(delay, function()
            local mountID = id or 460
            local mountName, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
            if mountName then
                self:Notify("mount", mountName, icon)
                self:Print("|cff00ff00Mount notification: " .. mountName .. " (ID: " .. mountID .. ")|r")
            else
                self:Print("|cffff0000Invalid mount ID: " .. mountID .. "|r")
            end
        end)
        if type == "mount" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show pet test
    if type == "pet" or type == "all" then
        C_Timer.After(delay, function()
            local speciesID = id or 39
            local speciesName, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            if speciesName then
                self:Notify("pet", speciesName, icon)
                self:Print("|cff00ff00Pet notification: " .. speciesName .. " (ID: " .. speciesID .. ")|r")
            else
                self:Print("|cffff0000Invalid pet species ID: " .. speciesID .. "|r")
            end
        end)
        if type == "pet" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show toy test
    if type == "toy" or type == "all" then
        C_Timer.After(delay, function()
            local toyItemID = id or 54452
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, icon = GetItemInfoFn(toyItemID)
            if itemName then
                self:Notify("toy", itemName, icon)
                self:Print("|cff00ff00Toy notification: " .. itemName .. " (ID: " .. toyItemID .. ")|r")
            else
                self:Print("|cffff0000Invalid toy item ID: " .. toyItemID .. "|r")
            end
        end)
        if type == "toy" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show achievement test
    if type == "achievement" or type == "all" then
        C_Timer.After(delay, function()
            local achievementID = id or 60981
            local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
            if achievementName then
                self:Notify("achievement", achievementName, icon)
                self:Print("|cff00ff00Achievement notification: " .. achievementName .. " (ID: " .. achievementID .. ")|r")
            else
                self:Print("|cffff0000Invalid achievement ID: " .. achievementID .. "|r")
            end
        end)
        if type == "achievement" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show illusion test
    if type == "illusion" or type == "all" then
        C_Timer.After(delay, function()
            self:Notify("illusion", "Illusion: Mongoose", 134400)
            self:Print("|cff00ff00Illusion notification: Illusion: Mongoose|r")
        end)
        if type == "illusion" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show title test
    if type == "title" or type == "all" then
        C_Timer.After(delay, function()
            -- Try to get a real title name (titleID 62 = "the Patient")
            local titleName = "the Patient"
            if GetTitleName then
                local rawTitle = GetTitleName(62)
                if rawTitle and rawTitle ~= "" then
                    titleName = rawTitle:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",%s*$", "")
                end
            end
            self:Notify("title", titleName)
            self:Print("|cff00ff00Title notification: " .. titleName .. " (titleID: 62)|r")
        end)
        if type == "title" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show plan completion tests
    if type == "plan" or type == "all" then
        if id then
            -- Test with specific achievement ID
            C_Timer.After(delay, function()
                local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if achievementName then
                    self:Notify("plan", achievementName, icon)
                    self:Print("|cff00ff00Plan completion: " .. achievementName .. " (ID: " .. id .. ")|r")
                else
                    self:Print("|cffff0000Invalid achievement ID: " .. id .. "|r")
                end
            end)
        else
            -- Show multiple example plans
            C_Timer.After(delay, function()
                self:Notify("plan", "Bloodsail Admiral", "Interface\\Icons\\INV_Scroll_11")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Greater Darkmoon Feast", "Interface\\Icons\\INV_Scroll_08")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Illusion: Mongoose", "Interface\\Icons\\INV_Enchant_Disenchant")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Collect All Mounts")
            end)
        end
        
        if type == "plan" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show reputation test (2-line: Faction name, then Renown level)
    if type == "reputation" or type == "all" then
        C_Timer.After(delay, function()
            self:Notify("reputation", "The Assembly of the Deeps", nil, {
                action = "Renown 15",
            })
        end)
        if type == "reputation" then
            self:Print("|cff00ff00Test reputation notification shown!|r")
            return
        end
        delay = delay + 0.5
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing all notification types with real data!|r")
    else
        self:Print("|cffff0000Unknown notification type. Use |cffffcc00/wn testloot help|r for available options.|r")
    end
end

---Test event-driven notification system
function WarbandNexus:TestNotificationEvents(type, id)
    type = type and strlower(type) or "all"
    
    self:Print("|cff00ccff[Event Test]|r Testing notification events (type: " .. type .. ")")
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Event System Test Commands ===|r")
        self:Print("|cffffcc00/wn testevents|r - Test all event types")
        self:Print("|cffffcc00/wn testevents collectible [id]|r - Test collectible event")
        self:Print("|cffffcc00/wn testevents plan [achievementID]|r - Test plan completion event")
        self:Print("|cffffcc00/wn testevents vault|r - Test vault slot event")
        self:Print("|cffffcc00/wn testevents vaultreward|r - Test vault reward available")
        self:Print("|cffffcc00/wn testevents quest|r - Test quest completion event")
        self:Print("|cffffcc00/wn testevents reputation|r - Test reputation gain event")
        self:Print("|cffffcc00/wn testevents reputation valeera|r - Test Valeera Sanguinar (delve companion) rep message")
        self:Print("|cff888888Examples:|r")
        self:Print("|cff888888  /wn testevents plan 60981|r")
        self:Print("|cff888888  /wn testevents collectible 460|r")
        return
    end
    
    local delay = 0
    
    -- Test collectible event
    if type == "collectible" or type == "all" then
        C_Timer.After(delay, function()
            local mountID = id or 460
            local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
            self:SendMessage(E.COLLECTIBLE_OBTAINED, {
                type = "mount",
                id = mountID,
                name = mountName or "Test Mount (Event)",
                icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse"
            })
        end)
        if type == "collectible" then
            self:Print("|cff00ff00Test collectible event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test plan completion event
    if type == "plan" or type == "all" then
        C_Timer.After(delay, function()
            local planName, planIcon
            if id then
                -- Use real achievement data
                local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if achievementName then
                    planName = achievementName
                    planIcon = icon
                    self:Print("|cff00ff00Plan event sent: " .. achievementName .. " (ID: " .. id .. ")|r")
                else
                    self:Print("|cffff0000Invalid achievement ID: " .. id .. "|r")
                    return
                end
            else
                planName = "Test Plan (Event)"
                planIcon = "Interface\\Icons\\INV_Misc_Note_06"
            end
            
            self:SendMessage(E.PLAN_COMPLETED, {
                planType = "achievement",
                name = planName,
                icon = planIcon
            })
        end)
        if type == "plan" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Test vault slot event
    if type == "vault" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.VAULT_SLOT_COMPLETED, {
                characterName = "TestChar",
                category = "dungeon",
                slotIndex = 1,
                threshold = 4
            })
        end)
        if type == "vault" then
            self:Print("|cff00ff00Test vault slot event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test vault reward available event
    if type == "vaultreward" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.VAULT_REWARD_AVAILABLE, {})
        end)
        if type == "vaultreward" then
            self:Print("|cff00ff00Test vault reward event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test quest completion event
    if type == "quest" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.QUEST_COMPLETED, {
                characterName = "TestChar",
                category = "dailyQuests",
                questTitle = "Test Daily Quest"
            })
        end)
        if type == "quest" then
            self:Print("|cff00ff00Test quest event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test reputation gain event (Snapshot-Diff payload)
    if type == "reputation" or type == "all" then
        local idLower = id and strlower(tostring(id))
        -- Valeera Sanguinar (delve companion): full pipeline test if she's in rep cache
        if (type == "reputation") and (idLower == "valeera" or idLower == "sanguinar") then
            local RC = ns.ReputationCache
            local factionID = RC and RC._nameToID and (RC._nameToID["Valeera Sanguinar"] or RC._nameToID["Valeera"])
            if factionID and factionID > 0 then
                RC:SimulateReputationGain("Valeera Sanguinar", factionID, 250)
                self:Print("|cff00ff00Valeera Sanguinar rep gain simulated (full pipeline). Check chat in ~0.5s.|r")
            else
                self:Print("|cffff9900Valeera Sanguinar not in reputation cache.|r Open the |cffffcc00Reputation|r tab once (so she is loaded), then run |cffffcc00/wn testevents reputation valeera|r again.")
            end
            return
        end
        C_Timer.After(delay, function()
            self:SendMessage(E.REPUTATION_GAINED, {
                factionID = 2590,
                factionName = "The Assembly of the Deeps",
                gainAmount = 250,
                currentRep = 3500,
                maxRep = 7500,
                wasStandingUp = false,
            })
        end)
        if type == "reputation" then
            self:Print("|cff00ff00Test reputation event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing all event types!|r")
    else
        self:Print("|cffff0000Unknown event type. Use |cffffcc00/wn testevents help|r for available options.|r")
    end
end

---Test different visual effects on notifications
function WarbandNexus:TestNotificationEffects()
    self:Print("|cff00ccff=== Testing Notification Styles ===|r")
    
    -- Test 1: Full frame glow
    self:ShowModalNotification({
        title = "Full Frame Glow",
        message = "Subtle glow around entire frame",
        icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
        -- titleColor = {1.0, 0.5, 0.0}, -- Custom color override (commented to use theme)
        playSound = false,
        glowAtlas = "communitiesfinder_card_highlight",
    })
    
    -- Test 2: Top + Bottom lines
    C_Timer.After(0.3, function()
        self:ShowModalNotification({
            title = "Top & Bottom Lines",
            message = "Clean border highlighting",
            icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
            -- titleColor = {1.0, 0.0, 1.0}, -- Custom color override (commented to use theme)
            playSound = false,
            glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
        })
    end)
end

---Manual test function for vault check (slash command)
function WarbandNexus:TestVaultCheck()
    self:Print("|cff00ccff=== VAULT CHECK TEST ===|r")
    
    -- Check API
    if not C_WeeklyRewards then
        self:Print("|cffff0000ERROR: C_WeeklyRewards API not found!|r")
        return
    else
        self:Print("|cff00ff00âœ“ C_WeeklyRewards API available|r")
    end
    
    if not C_WeeklyRewards.HasAvailableRewards then
        self:Print("|cffff0000ERROR: HasAvailableRewards function not found!|r")
        return
    else
        self:Print("|cff00ff00âœ“ HasAvailableRewards function available|r")
    end
    
    -- Check rewards and current-period/claimable APIs
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    local isCurrent = (C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()) or nil
    local canClaim = (C_WeeklyRewards.CanClaimRewards and C_WeeklyRewards.CanClaimRewards()) or nil
    local activities = (C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()) or nil
    local count = activities and #activities or 0
    self:Print(string.format("HasAvailableRewards=%s | AreRewardsForCurrentRewardPeriod=%s | CanClaimRewards=%s | GetActivities count=%s",
        tostring(hasRewards), tostring(isCurrent), tostring(canClaim), tostring(count)))
    local wouldShow = self:HasUnclaimedVaultRewards()
    self:Print("HasUnclaimedVaultRewards() (would show reminder): " .. tostring(wouldShow))
    if wouldShow then
        self:Print("|cff00ff00âœ“ YOU HAVE UNCLAIMED REWARDS!|r")
        self:ShowVaultReminder({})
    else
        self:Print("|cff888888âœ— No unclaimed (or not current period / not claimable)|r")
    end
    
    self:Print("|cff00ccff======================|r")
end




