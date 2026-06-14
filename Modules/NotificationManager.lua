--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders

    WN_FACTORY: Changelog popup scroll-child + themed close use `ns.UI.Factory` / ApplyVisuals; toast layering
    (effects/backdrop/icon z-order) stays plain `CreateFrame`; screen flash overlay remains an intentional fullscreen host.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local FontManager = ns.FontManager  -- Centralized font management
local ApplyVisuals = ns.UI_ApplyVisuals
local ToastFactory = ns.NotificationToastFactory
local DebugPrint = ns.DebugPrint or function() end
local DebugVerbosePrint = ns.DebugVerbosePrint or DebugPrint
local issecretvalue = issecretvalue

-- Unique AceEvent handler identity for NotificationManager
local NotificationEvents = {}

-- Current addon version (from Constants)
local Constants = ns.Constants
local E = Constants.EVENTS
-- Dedupe Blizzard progressive criteria: AchievementAlertSystem / CriteriaAlertSystem may both enqueue.
local lastCriteriaProgressEmitKey = nil
local lastCriteriaProgressEmitTime = nil
local TestLootEnsureAchievementAlertUI, TestLootFireAchievementAddAlert, TestLootResolveAchievementWithCriteria

-- Changelog / What's New: NotificationManager_Changelog.lua (ns.NotificationChangelog, ns.CHANGELOG)
local NotificationChangelog = ns.NotificationChangelog
assert(NotificationChangelog and ns.CHANGELOG, "NotificationManager: load NotificationManager_Changelog.lua first")

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

local function NM_GetShellContentInset()
    if NotificationChangelog and NotificationChangelog.GetShellContentInset then
        return NotificationChangelog.GetShellContentInset()
    end
    return 2
end

--- Toast / flat-panel fill RGBA (Phase 2: theme `surfaceElevated`, not magic grays).
local function NM_GetElevatedBackdropFillRGBA()
    local c = ns.UI_COLORS or {}
    local s = c.surfaceElevated or c.bgLight or c.bg
    if s then
        local a = s[4]
        if type(a) ~= "number" or a ~= a or a <= 0 or a > 1 then a = 0.94 end
        return s[1], s[2], s[3], a
    end
    return 0.03, 0.03, 0.05, 0.98
end

local function NM_ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    if role == "Muted" then return "|cffaaaaaa" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function NM_TextShadow(strength)
    if ns.UI_GetTextShadowRGBA then
        return ns.UI_GetTextShadowRGBA(strength)
    end
    local s = strength or 1
    return 0, 0, 0, 0.9 * s
end

local function NM_ApplyTextShadow(fs, strength)
    if not fs or not fs.SetShadowColor then return end
    local sr, sg, sb, sa = NM_TextShadow(strength)
    fs:SetShadowColor(sr, sg, sb, sa)
end

-- Toast entrance VFX: sun-like pulse + horizontal sweep (custom textures only).
local NM_SUN_WASH_PEAK = 0.58
local NM_SUN_CORE_PEAK = 1
local NM_SUN_WASH_RGB = { 1, 0.96, 0.82 }
local NM_SUN_CORE_RGB = { 1, 1, 0.92 }
local NM_SHEEN_PEAK_ALPHA = 0.72
local NM_SHEEN_WIDTH_RATIO = 0.44

local function NM_IgnoreParentAlpha(fxFrame)
    if fxFrame and fxFrame.SetIgnoreParentAlpha then
        fxFrame:SetIgnoreParentAlpha(true)
    end
end

---Sun-like radial burst + warm full-panel wash on toast appear.
local function NM_PlayToastSunGlow(toastHost, toastWidth, toastHeight)
    if not toastHost or not toastWidth or not toastHeight then
        return
    end
    if not toastHost:IsShown() or toastHost.isClosing or toastHost._removed then
        return
    end

    local fxRoot = CreateFrame("Frame", nil, toastHost)
    fxRoot:SetFrameLevel(3)
    fxRoot:SetAllPoints(toastHost)
    fxRoot:SetClipsChildren(true)
    fxRoot:EnableMouse(false)
    NM_IgnoreParentAlpha(fxRoot)

    local wash = fxRoot:CreateTexture(nil, "ARTWORK", nil, 0)
    wash:SetAllPoints(fxRoot)
    wash:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    wash:SetBlendMode("ADD")
    wash:SetVertexColor(NM_SUN_WASH_RGB[1], NM_SUN_WASH_RGB[2], NM_SUN_WASH_RGB[3], 1)

    local sunSize = math.floor(math.max(toastWidth, toastHeight) * 1.25)
    local sunHost = CreateFrame("Frame", nil, fxRoot)
    sunHost:SetSize(sunSize, sunSize)
    sunHost:SetPoint("CENTER", fxRoot, "CENTER", 0, 0)

    local sunHalo = sunHost:CreateTexture(nil, "BACKGROUND", nil, -1)
    sunHalo:SetSize(sunSize * 1.35, sunSize * 1.35)
    sunHalo:SetPoint("CENTER", sunHost, "CENTER", 0, 0)
    sunHalo:SetTexture("Interface\\Cooldown\\star4")
    sunHalo:SetBlendMode("ADD")
    sunHalo:SetVertexColor(NM_SUN_WASH_RGB[1], NM_SUN_WASH_RGB[2], NM_SUN_WASH_RGB[3], 0.85)

    local sunCore = sunHost:CreateTexture(nil, "ARTWORK", nil, 1)
    sunCore:SetSize(sunSize * 0.72, sunSize * 0.72)
    sunCore:SetPoint("CENTER", sunHost, "CENTER", 0, 0)
    sunCore:SetTexture("Interface\\Cooldown\\star4")
    sunCore:SetBlendMode("ADD")
    sunCore:SetVertexColor(NM_SUN_CORE_RGB[1], NM_SUN_CORE_RGB[2], NM_SUN_CORE_RGB[3], 1)

    fxRoot:SetAlpha(0)
    sunHost:SetAlpha(0)

    local ag = fxRoot:CreateAnimationGroup()
    ag:SetScript("OnFinished", function()
        fxRoot:Hide()
    end)

    local washIn = ag:CreateAnimation("Alpha")
    washIn:SetTarget(fxRoot)
    washIn:SetFromAlpha(0)
    washIn:SetToAlpha(NM_SUN_WASH_PEAK)
    washIn:SetDuration(0.09)
    washIn:SetSmoothing("OUT")

    local sunIn = ag:CreateAnimation("Alpha")
    sunIn:SetTarget(sunHost)
    sunIn:SetFromAlpha(0)
    sunIn:SetToAlpha(NM_SUN_CORE_PEAK)
    sunIn:SetDuration(0.07)
    sunIn:SetSmoothing("OUT")

    local sunScale = ag:CreateAnimation("Scale")
    sunScale:SetTarget(sunHost)
    sunScale:SetOrigin("CENTER", 0, 0)
    sunScale:SetScale(1.55, 1.55)
    sunScale:SetDuration(0.48)
    sunScale:SetSmoothing("OUT")

    local washHold = ag:CreateAnimation("Alpha")
    washHold:SetTarget(fxRoot)
    washHold:SetFromAlpha(NM_SUN_WASH_PEAK)
    washHold:SetToAlpha(NM_SUN_WASH_PEAK * 0.78)
    washHold:SetDuration(0.14)
    washHold:SetStartDelay(0.09)
    washHold:SetSmoothing("NONE")

    local sunHold = ag:CreateAnimation("Alpha")
    sunHold:SetTarget(sunHost)
    sunHold:SetFromAlpha(NM_SUN_CORE_PEAK)
    sunHold:SetToAlpha(NM_SUN_CORE_PEAK * 0.55)
    sunHold:SetDuration(0.16)
    sunHold:SetStartDelay(0.07)
    sunHold:SetSmoothing("NONE")

    local washOut = ag:CreateAnimation("Alpha")
    washOut:SetTarget(fxRoot)
    washOut:SetFromAlpha(NM_SUN_WASH_PEAK * 0.78)
    washOut:SetToAlpha(0)
    washOut:SetDuration(0.4)
    washOut:SetStartDelay(0.23)
    washOut:SetSmoothing("IN")

    local sunOut = ag:CreateAnimation("Alpha")
    sunOut:SetTarget(sunHost)
    sunOut:SetFromAlpha(NM_SUN_CORE_PEAK * 0.55)
    sunOut:SetToAlpha(0)
    sunOut:SetDuration(0.42)
    sunOut:SetStartDelay(0.2)
    sunOut:SetSmoothing("IN")

    ag:Play()
end

---White horizontal sweep across toast (custom band, clipped to frame).
local function NM_PlayToastSweepShine(toastHost, toastWidth, toastHeight)
    if not toastHost or not toastWidth or not toastHeight then
        return
    end
    if not toastHost:IsShown() or toastHost.isClosing or toastHost._removed then
        return
    end

    local clipFrame = CreateFrame("Frame", nil, toastHost)
    clipFrame:SetFrameLevel(4)
    clipFrame:SetAllPoints(toastHost)
    clipFrame:SetClipsChildren(true)
    clipFrame:EnableMouse(false)
    NM_IgnoreParentAlpha(clipFrame)

    local shineH = toastHeight
    local shineW = math.max(72, math.floor(toastWidth * NM_SHEEN_WIDTH_RATIO))
    local shineHost = CreateFrame("Frame", nil, clipFrame)
    shineHost:SetSize(shineW, shineH)
    shineHost:SetPoint("LEFT", clipFrame, "LEFT", -shineW, 0)

    local function addBand(width, alpha, relPoint, relTo, xOff)
        local band = shineHost:CreateTexture(nil, "ARTWORK")
        band:SetSize(width, shineH)
        band:SetPoint(relPoint, relTo, relPoint, xOff, 0)
        band:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        band:SetVertexColor(1, 1, 0.95, alpha)
        band:SetBlendMode("ADD")
        return band
    end

    local coreW = math.max(28, math.floor(shineW * 0.36))
    local wingW = math.max(22, math.floor((shineW - coreW) * 0.5))
    local core = addBand(coreW, 1, "CENTER", shineHost, 0)
    addBand(wingW, 0.5, "RIGHT", core, "LEFT", 0)
    addBand(wingW, 0.5, "LEFT", core, "RIGHT", 0)

    local travel = toastWidth + shineW
    local duration = 0.58
    local ag = clipFrame:CreateAnimationGroup()
    ag:SetScript("OnFinished", function()
        clipFrame:Hide()
    end)

    local move = ag:CreateAnimation("Translation")
    move:SetTarget(shineHost)
    move:SetOffset(travel, 0)
    move:SetDuration(duration)
    move:SetSmoothing("IN_OUT")

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetTarget(shineHost)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(NM_SHEEN_PEAK_ALPHA)
    fadeIn:SetDuration(0.05)
    fadeIn:SetSmoothing("OUT")

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetTarget(shineHost)
    fadeOut:SetFromAlpha(NM_SHEEN_PEAK_ALPHA)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.16)
    fadeOut:SetStartDelay(math.max(0, duration - 0.1))
    fadeOut:SetSmoothing("IN")

    ag:Play()
end

local function NM_ResolveToastFxSize(toastHost, toastWidth, toastHeight)
    local w = toastHost:GetWidth() or toastHost._toastFxWidth or toastWidth or 0
    local h = toastHost:GetHeight() or toastHost._toastFxHeight or toastHeight or 0
    if w < 1 then w = toastWidth or toastHost._toastFxWidth or 400 end
    if h < 1 then h = toastHeight or toastHost._toastFxHeight or 88 end
    return w, h
end

---Sun glow + sweep together when the toast appears.
local function NM_PlayToastEntranceEffects(toastHost, toastWidth, toastHeight)
    if not toastHost or toastHost.isClosing or toastHost._removed or not toastHost:IsShown() then
        return false
    end
    local w, h = NM_ResolveToastFxSize(toastHost, toastWidth, toastHeight)
    if w < 1 or h < 1 then
        return false
    end
    NM_PlayToastSunGlow(toastHost, w, h)
    NM_PlayToastSweepShine(toastHost, w, h)
    return true
end

---Play entrance VFX once per toast; retry briefly if layout is not ready yet.
local function NM_TriggerToastEntranceEffects(toastHost, toastWidth, toastHeight)
    if not toastHost then return end
    toastHost._toastFxWidth = toastWidth
    toastHost._toastFxHeight = toastHeight

    if toastHost._effectTimer then
        toastHost._effectTimer:Cancel()
        toastHost._effectTimer = nil
    end

    local function playOnce()
        if toastHost._entranceFxPlayed or toastHost.isClosing or toastHost._removed then
            return true
        end
        if NM_PlayToastEntranceEffects(toastHost, toastWidth, toastHeight) then
            toastHost._entranceFxPlayed = true
            return true
        end
        return false
    end

    if playOnce() then
        return
    end

    toastHost._effectTimer = C_Timer.NewTimer(0.03, function()
        toastHost._effectTimer = nil
        if playOnce() then return end
        toastHost._effectTimer = C_Timer.NewTimer(0.06, function()
            toastHost._effectTimer = nil
            playOnce()
        end)
    end)
end

---Fallback if entrance finishes before deferred VFX could run (stack spam / timer coalesce).
local function NM_EnsureToastEntranceEffects(toastHost)
    if not toastHost or toastHost._entranceFxPlayed then return end
    NM_TriggerToastEntranceEffects(toastHost, toastHost._toastFxWidth, toastHost._toastFxHeight)
end

--[[============================================================================
    NOTIFICATION QUEUE
============================================================================]]

local notificationQueue = {}
local notificationQueueHead = 1

-- TryCounter + CollectionService can both send WN_COLLECTIBLE_OBTAINED within a short window:
--   â€¢ bag scan right after loot (item hits bags while Try Counter already toasted), or
--   â€¢ NEW_MOUNT journal event after loot (name differs: item vs mount journal).
-- Bag duplicate is suppressed at source (TryCounterService + CollectionService); this is a second line of defense.
-- Dedupe popup only; dispatch consumers (TryCounter migration, Plans) still run first in handler order.
local lastCollectibleLootToastShownAt = {}
local COLLECTIBLE_LOOT_TOAST_DEDUP_SEC = 12

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

ns.NotificationManagerHooks = ns.NotificationManagerHooks or {}
ns.NotificationManagerHooks.ProcessNotificationQueue = ProcessNotificationQueue

--[[============================================================================
    NOTIFICATION CONFIG FACTORY (DRY)
    Standardized config builders for all notification types.
    All share: playSound=true, glowAtlas=DEFAULT_GLOW, duration=DB setting.
============================================================================]]

local DEFAULT_GLOW = "TopBottom:UI-Frame-DastardlyDuos-Line"
local DEFAULT_NOTIFICATION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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
    reminder = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
}

-- Action text mapping (subtitle line)
local ACTION_TEXT = {
    mount = (ns.L and ns.L["COLLECTED_MOUNT_MSG"]) or "You have collected a mount",
    pet = (ns.L and ns.L["COLLECTED_PET_MSG"]) or "You have collected a battle pet",
    toy = (ns.L and ns.L["COLLECTED_TOY_MSG"]) or "You have collected a toy",
    illusion = (ns.L and ns.L["COLLECTED_ILLUSION_MSG"]) or "You have collected an illusion",
    achievement = (ns.L and ns.L["ACHIEVEMENT_COMPLETED_MSG"]) or "Achievement completed!",
    criteria_progress = (ns.L and ns.L["CRITERIA_PROGRESS_MSG"]) or "Progress",
    title = (ns.L and ns.L["EARNED_TITLE_MSG"]) or "You have earned a title",
    plan = (ns.L and ns.L["COMPLETED_PLAN_MSG"]) or "You have completed a plan",
    item = (ns.L and ns.L["COLLECTED_ITEM_MSG"]) or "You received a rare drop",
    reminder = (ns.L and ns.L["REMINDER_PREFIX"]) or "Reminder",
}

---Build a standardized notification config
---@return table config Ready to pass to ShowModalNotification
function WarbandNexus:BuildNotificationConfig(notifType, name, icon, overrides)
    local safeIcon = icon
    if safeIcon and issecretvalue and issecretvalue(safeIcon) then safeIcon = nil end
    local safeName = name
    if safeName and issecretvalue and issecretvalue(safeName) then safeName = nil end
    local resolvedIcon = safeIcon or CATEGORY_ICONS[notifType] or DEFAULT_NOTIFICATION_ICON
    local config = {
        icon = resolvedIcon,
        itemName = safeName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
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
function WarbandNexus:Notify(notifType, name, icon, overrides)
    local config = self:BuildNotificationConfig(notifType, name, icon, overrides)
    self:ShowModalNotification(config)
end

--- Settings / QA: achievement + criteria-style + To-Do reminder in quick succession (same anchor stack).
local function ShowTestReminderToastModal(addon)
    if not addon or not addon.ShowModalNotification then return end
    local L = ns.L
    local hornRGB = (ns.Constants and ns.Constants.REMINDER_HORN_UI_COLOR) or { 1, 0.82, 0.22 }
    addon:ShowModalNotification({
        compact = true,
        planReminderToast = true,
        criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do reminder",
        itemName = (L and L["TEST_STACK_REMINDER"]) or "Plan reminder (test)",
        icon = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
        playSound = false,
        autoDismiss = 4,
        titleColor = { hornRGB[1], hornRGB[2], hornRGB[3] },
        progressGlow = true,
    })
end

function WarbandNexus:TestNotificationStack()
    local L = ns.L
    local db = self.db and self.db.profile and self.db.profile.notifications
    if not db or not db.enabled then return end

    local useWnAchievementPopups = db.hideBlizzardAchievementAlert == true

    if useWnAchievementPopups then
        self:Notify(
            "achievement",
            (L and L["TEST_NOTIFICATION_TITLE"]) or "Test Notification",
            nil,
            { action = (L and L["TEST_NOTIFICATION_MSG"]) or "Achievement lane", playSound = false, autoDismiss = 4 }
        )
        C_Timer.After(0.12, function()
            if not self.ShowModalNotification then return end
            self:ShowModalNotification({
                compact = true,
                criteriaTitle = (L and L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress",
                itemName = (L and L["TEST_STACK_CRITERIA"]) or "Criteria progress (test)",
                icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
                playSound = false,
                autoDismiss = 4,
            })
        end)
        C_Timer.After(0.24, function()
            ShowTestReminderToastModal(self)
        end)
        return
    end

    -- Warband achievement popups OFF: exercise Blizzard AlertFrame for earned + criteria (collectible popups unchanged).
    TestLootEnsureAchievementAlertUI(self)
    local earnedID = 6
    local okEarn, errEarn = TestLootFireAchievementAddAlert(self, earnedID, nil)
    if not okEarn and self.Print then
        self:Print("|cffff8800Blizzard achievement test failed: " .. tostring(errEarn) .. "|r")
    end
    C_Timer.After(0.55, function()
        local addon = WarbandNexus
        if not addon then return end
        TestLootEnsureAchievementAlertUI(addon)
        local achievementID, numCriteria = TestLootResolveAchievementWithCriteria(6)
        if achievementID then
            local criteriaIndex = math.min(1, numCriteria or 1)
            local okCrit, errCrit = TestLootFireAchievementAddAlert(addon, achievementID, criteriaIndex)
            if not okCrit and addon.Print then
                addon:Print("|cffff8800Blizzard criteria test failed: " .. tostring(errCrit) .. "|r")
            end
        end
    end)
    C_Timer.After(1.05, function()
        ShowTestReminderToastModal(WarbandNexus)
    end)
end

--[[============================================================================
    ACHIEVEMENT-STYLE ALERT FRAME SYSTEM (WOW-STYLE)
============================================================================]]

-- Max simultaneous toasts (rest queue with C_Timer debounce). Raised so mixed lanes can briefly co-exist.
local NOTIFICATION_MAX_VISIBLE_ALERTS = 6

-- Initialize AlertFrame tracking (like WoW's AlertFrame system)
if not WarbandNexus.activeAlerts then
    WarbandNexus.activeAlerts = {} -- Currently visible alerts (capped; see NOTIFICATION_MAX_VISIBLE_ALERTS)
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
local ALERT_HEIGHT = 88       -- Full achievement toast height
local ALERT_HEIGHT_COMPACT = 88  -- Compact notification lane (collectibles, etc.) â€” wide frame
local ALERT_GAP = 10          -- Pixel gap between stacked alerts
local ALERT_SPACING = ALERT_HEIGHT + ALERT_GAP  -- Legacy: total slot spacing (98px)
-- Full + compact notification width (achievement / collector lane)
local ALERT_WIDTH_FIXED = 400
-- Progress / criteria / To-Do reminder: outer width resolved at show time via GetBlizzardProgressAlertToastWidth().
-- Height is fitted per toast (stacked header / title / detail) between min and max.
local ALERT_HEIGHT_PROGRESS_MIN = 68
-- Allow wrapped title + up to 3-line body + optional detail without clipping (dynamic height from GetStringHeight).
local ALERT_HEIGHT_PROGRESS_MAX = 120
local ALERT_HEIGHT_PROGRESS = 74
-- Reference width used to scale progress-lane icon column when matching a narrower Blizzard criteria bar.
local ALERT_PROGRESS_LAYOUT_REF_WIDTH = 400
-- Left inset inside the toast so the icon column matches full compact lane breathing room (criteria felt flush to border).
local ALERT_PROGRESS_ICON_LEADING_PAD = 10

---Get Blizzard's alert frame position so we can match it when "Use AlertFrame Position" is on.
---Tries AchievementAlertFrame1, CriteriaAlertFrame1, AlertFrameHolder, then any visible AlertFrame child.
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

---Match Blizzard criteria alert position when "Use CriteriaAlert position" is on (criteria lane only).
local function GetBlizzardCriteriaAlertFramePosition()
    local f = _G.CriteriaAlertFrame1
    if not f or not f.GetPoint or f:GetNumPoints() < 1 then return nil, nil, nil end
    local point, relativeTo, relativePoint, x, y = f:GetPoint(1)
    if not point then return nil, nil, nil end
    x, y = tonumber(x) or 0, tonumber(y) or -100
    if relativeTo == UIParent then
        return point, x, y
    end
    local fLeft, fTop = f:GetLeft(), f:GetTop()
    if not fLeft or not fTop then return nil, nil, nil end
    local w = f:GetWidth() or 300
    local uiw = UIParent:GetWidth()
    local uiTop = UIParent:GetTop()
    local centerX = fLeft + (w / 2)
    local offsetX = math.floor(centerX - (uiw / 2))
    local offsetY = math.floor(fTop - uiTop)
    return "TOP", offsetX, offsetY
end

local function CriteriaAnchorFromDb(db)
    if not db then return "TOP", 0, -100 end
    if db.useCriteriaAlertFramePosition then
        local pt, px, py = GetBlizzardCriteriaAlertFramePosition()
        if pt and px ~= nil and py ~= nil then return pt, px, py end
    end
    return db.popupPointCompact or db.popupPoint or "TOP",
        db.popupXCompact ~= nil and db.popupXCompact or (db.popupX or 0),
        db.popupYCompact ~= nil and db.popupYCompact or (db.popupY or -100)
end

---Resolve UIParent anchor for a toast lane. unifiedToastLayout=true uses one stack anchor for all lanes.
local function ResolveToastAnchor(lane)
    local db = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not db then return "TOP", 0, -100 end
    local unified = db.unifiedToastLayout ~= false

    if unified then
        if db.useAlertFramePosition then
            local pt, px, py = GetBlizzardAlertFramePosition()
            if pt and px ~= nil and py ~= nil then return pt, px, py end
        end
        return db.popupPoint or "TOP", db.popupX or 0, db.popupY or -100
    end

    if lane == "achievement" then
        if db.useAlertFramePosition then
            local pt, px, py = GetBlizzardAlertFramePosition()
            if pt and px ~= nil and py ~= nil then return pt, px, py end
        end
        return db.popupPoint or "TOP", db.popupX or 0, db.popupY or -100
    elseif lane == "criteria" then
        return CriteriaAnchorFromDb(db)
    elseif lane == "tryCounter" then
        return db.tryCounterToastPoint or db.popupPoint or "TOP",
            db.tryCounterToastX ~= nil and db.tryCounterToastX or (db.popupX or 0),
            db.tryCounterToastY ~= nil and db.tryCounterToastY or (db.popupY or -100)
    elseif lane == "reminder" then
        if db.reminderToastUseCriteriaLane ~= false then
            return CriteriaAnchorFromDb(db)
        end
        return db.reminderToastPoint or "TOPRIGHT",
            db.reminderToastX or -42,
            db.reminderToastY or -172
    end
    return "TOP", 0, -100
end

local function InferToastLane(config)
    if type(config.toastLane) == "string" and config.toastLane ~= "" then
        return config.toastLane
    end
    if config.planReminderToast then
        return "reminder"
    end
    local isCompact = config.compact and true or false
    local hasCrit = type(config.criteriaTitle) == "string" and config.criteriaTitle ~= ""
    if isCompact and (config.progressAnchor or hasCrit) then
        return "criteria"
    end
    return "achievement"
end

local function GetSavedPosition(compact)
    return ResolveToastAnchor("achievement")
end

---Outer width for progress-lane toasts (criteria, vault checkpoints, To-Do reminders): match live Blizzard CriteriaAlertFrame* when loaded.
---Fallback 300 matches AchievementAlertFrameTemplate (FrameXML alert lane) before CriteriaAlert frames exist.
local function GetBlizzardProgressAlertToastWidth()
    for i = 1, 10 do
        local f = _G["CriteriaAlertFrame" .. i]
        if f and type(f.GetWidth) == "function" and not (f.IsForbidden and f:IsForbidden()) then
            local ok, w = pcall(function()
                return f:GetWidth()
            end)
            if ok and type(w) == "number" and w >= 160 and w <= 900 then
                return math.floor(w + 0.5)
            end
        end
    end
    return 300
end

---Determine growth direction based on anchor position on screen (always AUTO)
---Returns 1 for DOWN (negative Y), -1 for UP (positive Y)
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
    
    -- If anchor is in the top 55% of screen â†’ grow DOWN, else grow UP
    if anchorScreenY > screenHeight * 0.45 then
        return 1   -- DOWN (negative Y offsets)
    else
        return -1   -- UP (positive Y offsets)
    end
end

---Get height of an alert frame (full and compact both fixed) for stacking
local function GetAlertHeight(alert)
    return (alert and alert._alertHeight) or ALERT_HEIGHT
end

---Calculate Y offset for a new alert that will be appended to a group (cumulative height of existing alerts in that anchor).
---Used so achievement and criteria progress never overlap regardless of order or mix.
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
                -- Z-order: same strata, rising frame level for higher stack slots (newer toasts) so the latest message paints on top.
                alert:SetFrameStrata("HIGH")
                alert:SetFrameLevel(1000 + slotInGroup * 5)
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
    if alert._effectTimer then
        alert._effectTimer:Cancel()
        alert._effectTimer = nil
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
    do
        local bin = ns.UI_RecycleBin
        if bin then alert:SetParent(bin) else alert:SetParent(nil) end
    end
    
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
                if HasQueuedAlerts() and #WarbandNexus.activeAlerts < NOTIFICATION_MAX_VISIBLE_ALERTS then
                    local nextConfig = DequeueAlert()
                    
                    if WarbandNexus.ShowModalNotification then
                        WarbandNexus:ShowModalNotification(nextConfig)
                        
                        -- If more slots available, stagger next alert after entrance completes
                        if HasQueuedAlerts() and #WarbandNexus.activeAlerts < NOTIFICATION_MAX_VISIBLE_ALERTS then
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
function WarbandNexus:ShowModalNotification(config)
    -- Queue when at capacity; dequeue on dismiss via C_Timer (no polling queue logic).
    if #self.activeAlerts >= NOTIFICATION_MAX_VISIBLE_ALERTS then
        EnqueueAlert(config)
        return
    end
    
    -- Default values
    config = config or {}
    local iconTexture = config.iconFileID or config.icon or "Interface\\Icons\\Achievement_Quests_Completed_08"
    local iconAtlas = config.iconAtlas or nil
    
    -- Auto-detect atlas if not explicitly set (factory pattern â€” centralized detection)
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
    
    -- Calculate alert position (direction-aware, screen-safe). Lanes: achievement / criteria / tryCounter / reminder.
    local isCompact = not not config.compact
    local isPlanReminderToast = config.planReminderToast == true
    local criteriaTitleStr = config.criteriaTitle
    local useProgressSlot = not isPlanReminderToast and (
        config.progressAnchor == true
            or (isCompact and type(criteriaTitleStr) == "string" and criteriaTitleStr ~= "")
    )
    local useReminderSlot = isPlanReminderToast
    local toastLane = InferToastLane(config)
    local point, baseX, baseY = ResolveToastAnchor(toastLane)
    local dbN = self.db and self.db.profile and self.db.profile.notifications
    local direction = GetGrowthDirection(point, baseX, baseY)
    -- Per-lane prefix when anchors are split so two lanes at the same pixel do not share one vertical stack slot.
    local lanePrefix = (dbN and dbN.unifiedToastLayout == false) and (toastLane .. "|") or ""
    local anchorKey = lanePrefix .. point .. "|" .. tostring(baseX) .. "|" .. tostring(baseY)
    local yOffset = baseY + GetCumulativeOffsetForNewAlert(anchorKey, direction)
    
    -- Compact toast: icon left, content (backdrop + text) right.
    -- Progress lane (criteria / vault / To-Do reminders): Blizzard criteria-bar width scaling.
    if config.compact then
        local laneUsesProgressSizing = useProgressSlot or useReminderSlot

        local COMPACT_HEIGHT = laneUsesProgressSizing and ALERT_HEIGHT_PROGRESS or ALERT_HEIGHT_COMPACT
        local popupWidthCompact = laneUsesProgressSizing and GetBlizzardProgressAlertToastWidth() or ALERT_WIDTH_FIXED
        -- Progress lane: icon column scales with Blizzard criteria bar width (ref = wide compact at 400px).
        local refW = ALERT_PROGRESS_LAYOUT_REF_WIDTH
        local ICON_SLOT_WIDTH_COMPACT = laneUsesProgressSizing
            and math.max(52, math.floor(72 * popupWidthCompact / refW + 0.5))
            or 62
        local iconSizeCompact = laneUsesProgressSizing
            and math.max(36, math.floor(54 * popupWidthCompact / refW + 0.5))
            or 42
        local laneIconLeadingPad = laneUsesProgressSizing and ALERT_PROGRESS_ICON_LEADING_PAD or 0
        local contentFrameCompactW = popupWidthCompact - ICON_SLOT_WIDTH_COMPACT - laneIconLeadingPad
        local compactPopup = (ToastFactory and ToastFactory.CreateToastHost)
            and ToastFactory:CreateToastHost(UIParent, popupWidthCompact, COMPACT_HEIGHT, { strata = "HIGH", frameLevel = 1000 })
            or CreateFrame("Frame", nil, UIParent)
        compactPopup:SetSize(popupWidthCompact, COMPACT_HEIGHT)
        compactPopup.currentYOffset = yOffset
        compactPopup.achievementID = config.achievementID
        compactPopup._toastLane = toastLane
        compactPopup._anchorPoint = point
        compactPopup._baseX = baseX
        compactPopup._baseY = baseY
        compactPopup._alertHeight = COMPACT_HEIGHT
        if ns.UI_ApplyAddonUIScale then
            ns.UI_ApplyAddonUIScale(compactPopup)
        end
        
        -- Layer 0: effects (glow lines) behind the black frame
        local effectsFrameCompact = CreateFrame("Frame", nil, compactPopup)
        effectsFrameCompact:SetFrameLevel(0)
        effectsFrameCompact:SetAllPoints(compactPopup)
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
        backdropFrameCompact:SetBackdropColor(NM_GetElevatedBackdropFillRGBA())
        if laneUsesProgressSizing then
            backdropFrameCompact:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 0.58)
        else
            backdropFrameCompact:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
        end
        
        -- Layer 2: icon slot (icon + bling only)
        local iconSlotCompact = CreateFrame("Frame", nil, compactPopup)
        iconSlotCompact:SetFrameLevel(2)
        iconSlotCompact:SetSize(ICON_SLOT_WIDTH_COMPACT, COMPACT_HEIGHT)
        iconSlotCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad, 0)
        
        local iconCompact = iconSlotCompact:CreateTexture(nil, "ARTWORK")
        iconCompact:SetSize(iconSizeCompact, iconSizeCompact)
        iconCompact:SetPoint("CENTER", iconSlotCompact, "CENTER", 0, 0)
        -- Use resolved atlas/fileID locals (IsAtlasName promotes config.icon â†’ iconAtlas; compact must not read config.iconAtlas only).
        if iconAtlas and iconAtlas ~= "" then
            iconCompact:SetAtlas(iconAtlas)
        else
            iconCompact:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if type(iconTexture) == "number" then
                iconCompact:SetTexture(iconTexture)
            elseif iconTexture and iconTexture ~= "" then
                iconCompact:SetTexture(iconTexture:gsub("\\", "/"))
            else
                iconCompact:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
            end
        end
        local iconBlingCompact = iconSlotCompact:CreateTexture(nil, "OVERLAY", nil, 7)
        iconBlingCompact:SetSize(iconSizeCompact + 10, iconSizeCompact + 10)
        iconBlingCompact:SetPoint("CENTER", iconCompact, "CENTER", 0, 0)
        iconBlingCompact:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
        iconBlingCompact:SetTexCoord(0, 0.5625, 0, 0.5625)
        iconBlingCompact:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        iconBlingCompact:SetBlendMode("BLEND")
        -- Match achievement toast icon chrome (UI-Achievement-IconFrame). Progress lane showed â€œnakedâ€ icons before.
        if laneUsesProgressSizing and config.progressAchievementFrame == false then
            iconBlingCompact:Hide()
        end
        
        -- Content frame (right): text only
        local contentFrameCompact = CreateFrame("Frame", nil, compactPopup)
        contentFrameCompact:SetFrameLevel(2)
        contentFrameCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad + ICON_SLOT_WIDTH_COMPACT, 0)
        
        -- Theme: TopBottom glow in effects layer (behind black) â€” spans ENTIRE toast for Blizzard-style coverage
        -- Progress slot defaults to no glow (helper/criteria-like).
        local compactGlowAtlas = glowAtlas
        if laneUsesProgressSizing and config.progressGlow ~= true then
            compactGlowAtlas = nil
        end
        if compactGlowAtlas and type(compactGlowAtlas) == "string" and compactGlowAtlas:find("TopBottom:") then
            local gInset = NM_GetShellContentInset()
            local baseAtlas = compactGlowAtlas:gsub("TopBottom:", "")
            local topLine = effectsFrameCompact:CreateTexture(nil, "BACKGROUND", nil, 0)
            topLine:SetPoint("TOPLEFT", effectsFrameCompact, "TOPLEFT", 0, gInset)
            topLine:SetPoint("TOPRIGHT", effectsFrameCompact, "TOPRIGHT", 0, gInset)
            topLine:SetHeight(40)
            topLine:SetAtlas(baseAtlas .. "-Top", true)
            topLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
            topLine:SetBlendMode("ADD")
            local bottomLine = effectsFrameCompact:CreateTexture(nil, "BACKGROUND", nil, 0)
            bottomLine:SetPoint("BOTTOMLEFT", effectsFrameCompact, "BOTTOMLEFT", 0, -gInset)
            bottomLine:SetPoint("BOTTOMRIGHT", effectsFrameCompact, "BOTTOMRIGHT", 0, -gInset)
            bottomLine:SetHeight(40)
            bottomLine:SetAtlas(baseAtlas .. "-bottom", true)
            bottomLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
            bottomLine:SetBlendMode("ADD")
        end
        -- Progress lane (criteria + To-Do reminder): one layout â€” accent header, white body, optional gray detail; symmetric padding in the text column (icon column separate).
        local criteriaTitle = config.criteriaTitle
        local progressStr = (messageText or actionText or "")
        if type(progressStr) == "string" and issecretvalue and issecretvalue(progressStr) then progressStr = "" end
        local nameStr = (itemName or "")
        if type(nameStr) == "string" and issecretvalue and issecretvalue(nameStr) then nameStr = "" end
        local detailStr = actionText or ""
        if type(detailStr) == "string" and issecretvalue and issecretvalue(detailStr) then detailStr = "" end
        local critTitleSafe = criteriaTitle
        if type(critTitleSafe) == "string" and issecretvalue and issecretvalue(critTitleSafe) then critTitleSafe = "" end
        local tr = math.floor(math.min(255, titleColor[1] * 255 * 1.35))
        local tg = math.floor(math.min(255, titleColor[2] * 255 * 1.35))
        local tb = math.floor(math.min(255, titleColor[3] * 255 * 1.35))
        local accentHex = string.format("|cff%02x%02x%02x", tr, tg, tb)
        local progressLine, nameLine
        if criteriaTitle then
            progressLine = FontManager:CreateFontString(contentFrameCompact, "subtitle", "OVERLAY")
            progressLine:SetJustifyH("LEFT")
            progressLine:SetWordWrap(true)
            progressLine:SetMaxLines(2)
            progressLine:SetText(accentHex .. (critTitleSafe or "") .. "|r")
            progressLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(progressLine, 0.9)
            nameLine = FontManager:CreateFontString(contentFrameCompact, "body", "OVERLAY")
            nameLine:SetJustifyH("LEFT")
            nameLine:SetWordWrap(true)
            nameLine:SetMaxLines(3)
            nameLine:SetText(NM_ThemeTextHex("Bright") .. (nameStr or "") .. "|r")
            nameLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(nameLine, 0.6)
        else
            progressLine = FontManager:CreateFontString(contentFrameCompact, "body", "OVERLAY")
            progressLine:SetJustifyH("LEFT")
            progressLine:SetWordWrap(false)
            progressLine:SetText(NM_ThemeTextHex("Muted") .. progressStr .. "|r")
            progressLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(progressLine, 0.6)
            nameLine = FontManager:CreateFontString(contentFrameCompact, "title", "OVERLAY")
            nameLine:SetJustifyH("LEFT")
            nameLine:SetText(accentHex .. (nameStr or "") .. "|r")
            nameLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(nameLine, 0.9)
        end
        contentFrameCompact:SetSize(contentFrameCompactW, COMPACT_HEIGHT)
        compactPopup:SetSize(popupWidthCompact, COMPACT_HEIGHT)

        local textPad = laneUsesProgressSizing and 12 or 10
        local textUseW = math.max(40, contentFrameCompactW - textPad * 2)

        local detailLine = nil
        if criteriaTitle then
            progressLine:SetWidth(textUseW)
            nameLine:SetWidth(textUseW)
            if detailStr ~= "" then
                detailLine = FontManager:CreateFontString(contentFrameCompact, "small", "OVERLAY")
                detailLine:SetWidth(textUseW)
                detailLine:SetJustifyH("LEFT")
                detailLine:SetWordWrap(true)
                detailLine:SetMaxLines(2)
                detailLine:SetText(NM_ThemeTextHex("Dim") .. detailStr .. "|r")
                detailLine:SetShadowOffset(1, -1)
                NM_ApplyTextShadow(detailLine, 0.55)
            end

            local gapMid = 4
            local gapDetail = 3
            local h1 = progressLine:GetStringHeight()
            local h2 = nameLine:GetStringHeight()
            local h3 = detailLine and detailLine:GetStringHeight() or 0
            local stackH = h1 + gapMid + h2 + (detailLine and (gapDetail + h3) or 0)
            local padV = 8
            local newH = math.min(ALERT_HEIGHT_PROGRESS_MAX, math.max(ALERT_HEIGHT_PROGRESS_MIN, math.ceil(stackH + padV * 2)))

            compactPopup:SetHeight(newH)
            iconSlotCompact:SetHeight(newH)
            contentFrameCompact:SetHeight(newH)
            compactPopup._alertHeight = newH

            local padTop = math.max(6, (newH - stackH) / 2)
            progressLine:ClearAllPoints()
            nameLine:ClearAllPoints()
            progressLine:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", textPad, -padTop)
            nameLine:SetPoint("TOPLEFT", progressLine, "BOTTOMLEFT", 0, -gapMid)
            if detailLine then
                detailLine:ClearAllPoints()
                detailLine:SetPoint("TOPLEFT", nameLine, "BOTTOMLEFT", 0, -gapDetail)
            end
        else
            local line1Y, line2Y = -20, -42
            progressLine:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", textPad, line1Y)
            progressLine:SetWidth(textUseW)
            nameLine:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", textPad, line2Y)
            nameLine:SetWidth(textUseW)
            nameLine:SetWordWrap(true)
            nameLine:SetMaxLines(2)
            progressLine:SetWordWrap(true)
            progressLine:SetMaxLines(2)
        end
        
        if config.playSound then
            local Constants = ns.Constants
            local defaultSound
            if laneUsesProgressSizing then
                defaultSound = (SOUNDKIT and (SOUNDKIT.UI_AUTO_QUEST_COMPLETE or SOUNDKIT.AUTO_QUEST_COMPLETE))
                    or (Constants and Constants.NOTIFICATION_SOUND_PROGRESS)
                    or 44294
            else
                defaultSound = (Constants and Constants.NOTIFICATION_SOUND_COMPACT_DEFAULT) or 44295
            end
            PlaySound(config.soundID or defaultSound)
        end
        
        compactPopup:SetScript("OnMouseDown", function(self, button)
            if self.isClosing or self._removed then return end
            self.isClosing = true
            if button == "LeftButton" and self.achievementID and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, self.achievementID)
            end
            if self.dismissTimer then self.dismissTimer:Cancel(); self.dismissTimer = nil end
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

        table.insert(self.activeAlerts, compactPopup)
        compactPopup.isEntering = true
        RepositionAlerts(true)
        compactPopup:Show()
        NM_TriggerToastEntranceEffects(compactPopup, popupWidthCompact, compactPopup:GetHeight() or COMPACT_HEIGHT)
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
                NM_EnsureToastEntranceEffects(self)
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
    
    -- WoW Achievement-style: container = icon slot (left) + content frame (text).
    local ICON_SLOT_WIDTH = 62  -- 14 pad + 42 icon + 6 gap
    local contentFrameWidth = popupWidthFull - ICON_SLOT_WIDTH
    
    local popup = (ToastFactory and ToastFactory.CreateToastHost)
        and ToastFactory:CreateToastHost(UIParent, popupWidthFull, ALERT_HEIGHT, { strata = "HIGH", frameLevel = 1000 })
        or CreateFrame("Frame", nil, UIParent)
    popup:SetSize(popupWidthFull, ALERT_HEIGHT)
    popup:SetMouseClickEnabled(true)
    if ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(popup)
    end
    
    -- Layer 0: glow / edge effects (behind backdrop)
    local effectsFrame = CreateFrame("Frame", nil, popup)
    effectsFrame:SetFrameLevel(0)
    effectsFrame:SetAllPoints(popup)
    
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
    backdropFrame:SetBackdropColor(NM_GetElevatedBackdropFillRGBA())
    backdropFrame:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    
    -- Layer 2: icon slot (icon + bling only)
    local iconSlot = CreateFrame("Frame", nil, popup)
    iconSlot:SetFrameLevel(2)
    iconSlot:SetSize(ICON_SLOT_WIDTH, ALERT_HEIGHT)
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
    
    local iconBling = iconSlot:CreateTexture(nil, "OVERLAY", nil, 7)
    iconBling:SetSize(64, 64)
    iconBling:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBling:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    iconBling:SetTexCoord(0, 0.5625, 0, 0.5625)
    iconBling:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    iconBling:SetBlendMode("BLEND")
    
    -- Layer 2: content frame (text only)
    local contentFrame = CreateFrame("Frame", nil, popup)
    contentFrame:SetFrameLevel(2)
    contentFrame:SetSize(contentFrameWidth, ALERT_HEIGHT)
    contentFrame:SetPoint("LEFT", popup, "LEFT", ICON_SLOT_WIDTH, 0)
    
    local popupHeight = ALERT_HEIGHT
    -- Glow lines span ENTIRE toast width (effectsFrame) for full Blizzard-style coverage
    if glowAtlas:find("TopBottom:") then
        local gInset = NM_GetShellContentInset()
        local baseAtlas = glowAtlas:gsub("TopBottom:", "")
        local topLine = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        topLine:SetPoint("TOPLEFT", effectsFrame, "TOPLEFT", 0, gInset)
        topLine:SetPoint("TOPRIGHT", effectsFrame, "TOPRIGHT", 0, gInset)
        topLine:SetHeight(56)
        topLine:SetAtlas(baseAtlas .. "-Top", true)
        topLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        topLine:SetBlendMode("ADD")
        local bottomLine = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        bottomLine:SetPoint("BOTTOMLEFT", effectsFrame, "BOTTOMLEFT", 0, -gInset)
        bottomLine:SetPoint("BOTTOMRIGHT", effectsFrame, "BOTTOMRIGHT", 0, -gInset)
        bottomLine:SetHeight(56)
        bottomLine:SetAtlas(baseAtlas .. "-bottom", true)
        bottomLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        bottomLine:SetBlendMode("ADD")
        local topGlowAg = effectsFrame:CreateAnimationGroup()
        topGlowAg:SetLooping("REPEAT")
        local topGlowIn = topGlowAg:CreateAnimation("Alpha")
        topGlowIn:SetTarget(topLine)
        topGlowIn:SetFromAlpha(0.6)
        topGlowIn:SetToAlpha(1.0)
        topGlowIn:SetDuration(1.4)
        topGlowIn:SetSmoothing("IN_OUT")
        local topGlowOut = topGlowAg:CreateAnimation("Alpha")
        topGlowOut:SetTarget(topLine)
        topGlowOut:SetFromAlpha(1.0)
        topGlowOut:SetToAlpha(0.6)
        topGlowOut:SetDuration(1.4)
        topGlowOut:SetSmoothing("IN_OUT")
        topGlowOut:SetStartDelay(1.4)
        topGlowAg:Play()
        local bottomGlowAg = effectsFrame:CreateAnimationGroup()
        bottomGlowAg:SetLooping("REPEAT")
        local bottomGlowIn = bottomGlowAg:CreateAnimation("Alpha")
        bottomGlowIn:SetTarget(bottomLine)
        bottomGlowIn:SetFromAlpha(0.6)
        bottomGlowIn:SetToAlpha(1.0)
        bottomGlowIn:SetDuration(1.4)
        bottomGlowIn:SetSmoothing("IN_OUT")
        local bottomGlowOut = bottomGlowAg:CreateAnimation("Alpha")
        bottomGlowOut:SetTarget(bottomLine)
        bottomGlowOut:SetFromAlpha(1.0)
        bottomGlowOut:SetToAlpha(0.6)
        bottomGlowOut:SetDuration(1.4)
        bottomGlowOut:SetSmoothing("IN_OUT")
        bottomGlowOut:SetStartDelay(1.4)
        bottomGlowAg:Play()
    else
        local borderGlow = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        if glowAtlas:find("Line%-Top") then
            borderGlow:SetPoint("TOPLEFT", effectsFrame, "TOPLEFT", 0, 4)
            borderGlow:SetPoint("TOPRIGHT", effectsFrame, "TOPRIGHT", 0, 4)
            borderGlow:SetHeight(40)
        elseif glowAtlas:find("Line%-Bottom") or glowAtlas:find("Line%-bottom") then
            borderGlow:SetPoint("BOTTOMLEFT", effectsFrame, "BOTTOMLEFT", 0, -4)
            borderGlow:SetPoint("BOTTOMRIGHT", effectsFrame, "BOTTOMRIGHT", 0, -4)
            borderGlow:SetHeight(40)
        elseif glowAtlas:find("DastardlyDuos%-Bar") then
            borderGlow:SetPoint("TOPLEFT", effectsFrame, "TOPLEFT", 4, -4)
            borderGlow:SetPoint("BOTTOMRIGHT", effectsFrame, "BOTTOMRIGHT", -4, 4)
        else
            borderGlow:SetAllPoints(effectsFrame)
        end
        borderGlow:SetAtlas(glowAtlas, true)
        borderGlow:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        borderGlow:SetBlendMode("ADD")
        borderGlow:SetAlpha(0.9)
    end
    -- Edge shine spans full toast top edge
    local edgeShine = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    edgeShine:SetHeight(1)
    edgeShine:SetPoint("TOPLEFT", effectsFrame, "TOPLEFT", 1, -1)
    edgeShine:SetPoint("TOPRIGHT", effectsFrame, "TOPRIGHT", -1, -1)
    edgeShine:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.3)
    edgeShine:SetBlendMode("ADD")
    -- Bottom edge shine
    local edgeShineBottom = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    edgeShineBottom:SetHeight(1)
    edgeShineBottom:SetPoint("BOTTOMLEFT", effectsFrame, "BOTTOMLEFT", 1, 1)
    edgeShineBottom:SetPoint("BOTTOMRIGHT", effectsFrame, "BOTTOMRIGHT", -1, 1)
    edgeShineBottom:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShineBottom:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.2)
    edgeShineBottom:SetBlendMode("ADD")
    
    -- Symmetric layout: text block center = content frame center.
    local popupWidth = contentFrameWidth
    local popupHeight = ALERT_HEIGHT
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
    
    -- Vertical: text block centered in the toast panel.
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
        category:SetText(NM_ThemeTextHex("Muted") .. categoryText .. "|r")
        category:SetWordWrap(false)
        category:SetShadowOffset(1, -1)
        NM_ApplyTextShadow(category, 0.8)
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
        NM_ApplyTextShadow(title, 0.9)
        
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
        subtitle:SetText(NM_ThemeTextHex("Bright") .. messageText .. "|r")
        subtitle:SetWordWrap(true)
        subtitle:SetMaxLines(2)
        subtitle:SetShadowOffset(1, -1)
        NM_ApplyTextShadow(subtitle, 0.6)
    end
    
    -- Legacy subtitle support
    if not showSubtitle and subtitleText and subtitleText ~= "" then
        local legacySub = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        legacySub:SetDrawLayer("OVERLAY", 7)
        legacySub:SetPoint("CENTER", contentFrame, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        legacySub:SetWidth(textAreaWidth)
        legacySub:SetJustifyH("CENTER")
        legacySub:SetText(NM_ThemeTextHex("Bright") .. subtitleText .. "|r")
        legacySub:SetWordWrap(true)
        legacySub:SetMaxLines(2)
        legacySub:SetShadowOffset(1, -1)
        NM_ApplyTextShadow(legacySub, 0.6)
    end
    
    -- Left-click: open achievement UI + dismiss | Right-click: dismiss only
    popup:SetScript("OnMouseDown", function(self, button)
        if self.isClosing or self._removed then return end
        self.isClosing = true
        
        if button == "LeftButton" and self.achievementID and not InCombatLockdown() then
            local achID = self.achievementID
            if OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, achID)
            end
        end
        
        if self.dismissTimer then
            self.dismissTimer:Cancel()
            self.dismissTimer = nil
        end
        
        self:SetScript("OnUpdate", nil)
        
        local clickStartTime = GetTime()
        local clickDuration = 0.25
        local clickStartAlpha = self:GetAlpha()
        
        self:SetScript("OnUpdate", function(self, elapsed)
            local elapsedTime = GetTime() - clickStartTime
            local progress = math.min(1, elapsedTime / clickDuration)
            self:SetAlpha(clickStartAlpha * (1 - progress))
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
    
    if playSound then
        local Constants = ns.Constants
        PlaySound(config.soundID or (Constants and Constants.NOTIFICATION_SOUND_COMPACT_DEFAULT) or 44295)
    end
    
    local slideOffset = 50 * -direction
    local startYOffset = yOffset + slideOffset
    local finalYOffset = yOffset

    popup._anchorPoint = point
    popup._baseX = baseX
    popup._baseY = baseY
    popup._direction = direction
    popup._toastLane = toastLane
    popup._alertHeight = ALERT_HEIGHT
    popup.achievementID = config.achievementID

    table.insert(self.activeAlerts, popup)
    popup.isEntering = true

    popup:SetAlpha(0)
    popup:SetPoint(point, UIParent, point, baseX, startYOffset)
    popup.currentYOffset = startYOffset
    popup._entranceStartY = startYOffset
    popup._entranceTargetY = finalYOffset
    popup._entranceStartTime = GetTime()

    RepositionAlerts(true)
    popup:Show()
    NM_TriggerToastEntranceEffects(popup, popupWidthFull, ALERT_HEIGHT)

    local slideDuration = 0.3
    local _point, _bx = point, baseX

    popup:SetScript("OnUpdate", function(self, elapsed)
        local prog = math.min(1, (GetTime() - (self._entranceStartTime or 0)) / slideDuration)
        local ease = 1 - math.pow(1 - prog, 2)
        local cy = (self._entranceStartY or 0) + ((self._entranceTargetY or 0) - (self._entranceStartY or 0)) * ease
        self:SetAlpha(math.min(1, self:GetAlpha() + elapsed * 4))
        self:ClearAllPoints()
        self:SetPoint(_point, UIParent, _point, _bx, cy)
        self.currentYOffset = cy
        if prog >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            self.currentYOffset = self._entranceTargetY
            self.isEntering = false
            NM_EnsureToastEntranceEffects(self)
        end
    end)

    popup.dismissTimer = C_Timer.NewTimer(autoDismissDelay, function()
        if not popup:IsShown() or popup.isClosing or popup._removed then return end
        popup.isClosing = true
        if popup.dismissTimer then popup.dismissTimer:Cancel(); popup.dismissTimer = nil end
        popup:SetScript("OnUpdate", nil)

        local exitStartTime = GetTime()
        local exitDuration = 0.5
        local exitStartY = popup.currentYOffset or finalYOffset
        local exitDir = popup._direction or direction
        local exitEndY = exitStartY + (30 * exitDir)
        local exitPoint = popup._anchorPoint or point
        local exitBaseX = popup._baseX or baseX

        popup:SetScript("OnUpdate", function(self, elapsed)
            if not self or not self:IsShown() then return end
            local progress = math.min(1, (GetTime() - exitStartTime) / exitDuration)
            local easedProgress = math.pow(progress, 3)
            self:SetAlpha(1 - easedProgress)
            local currentY = exitStartY + ((exitEndY - exitStartY) * easedProgress)
            self:ClearAllPoints()
            self:SetPoint(exitPoint, UIParent, exitPoint, exitBaseX, currentY)
            if progress >= 1 then
                self:SetScript("OnUpdate", nil)
                RemoveAlert(self)
            end
        end)
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
    if ns.WeeklyVaultHasPendingRewards then
        return ns.WeeklyVaultHasPendingRewards()
    end
    if not C_WeeklyRewards or not C_WeeklyRewards.HasAvailableRewards then
        return false
    end
    if not C_WeeklyRewards.HasAvailableRewards() then
        return false
    end
    if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
        local isCurrent = C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()
        if not isCurrent then
            return false
        end
    end
    return true
end

---Show vault reminder popup (simplified wrapper)
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
            local hasRewards = ns.WeeklyVaultHasPendingRewards and ns.WeeklyVaultHasPendingRewards()
                or (C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards())
            local canClaim = ns.WeeklyVaultCanClaimAtLocation and ns.WeeklyVaultCanClaimAtLocation()
            local activities = (C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()) or nil
            local activityCount = activities and #activities or 0
            local secsUntilReset = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()) or nil
            DebugVerbosePrint(string.format("|cff00ccff[Vault]|r pending=%s | canClaimAtLocation=%s | activities=%s | secsUntilReset=%s",
                tostring(hasRewards), tostring(canClaim), tostring(activityCount), secsUntilReset and tostring(secsUntilReset) or "n/a"))
            if activities and activityCount > 0 then
                local a1 = activities[1]
                if a1 then
                    DebugVerbosePrint(string.format("|cff00ccff[Vault]|r First activity: type=%s progress=%s threshold=%s",
                        tostring(a1.type), tostring(a1.progress), tostring(a1.threshold)))
                end
            end
            local shouldShow = hasRewards == true
            if shouldShow then
                DebugVerbosePrint("|cff00ccff[Vault]|r Showing reminder (unclaimed rewards, current period).")
                QueueNotification({
                    type = "vault",
                    data = { canClaimAtLocation = canClaim == true }
                })
            else
                DebugVerbosePrint("|cff888888[Vault]|r NOT showing: no pending vault rewards for current period.")
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
    self:RegisterMessage(E.SHOW_REMINDER_TOAST, "OnShowReminderToast")
    self:RegisterMessage(E.SHOW_CRITERIA_PROGRESS, "OnShowCriteriaProgressMessage")
    
    -- â”€â”€ BULLETPROOF COLLECTIBLE DISPATCH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- WN_COLLECTIBLE_OBTAINED has MULTIPLE consumers on WarbandNexus:
    --   1. OnTryCounterCollectibleObtained (try counter reconciliation â€” TryCounterService)
    --   2. OnCollectibleObtained (popup notification â€” NotificationManager)
    --   3. OnPlanCollectionUpdated (plan completion detection â€” PlansManager)
    --
    -- WHY THIS PATTERN:
    --   AceEvent allows only ONE handler per event per object. Without this dispatch,
    --   the last module to register silently overwrites the others â€” causing notifications
    --   to stop working with NO error message (the root cause of past breakage).
    --
    -- HOW IT WORKS:
    --   Single RegisterMessage handler iterates a dispatch table with pcall protection.
    --   Each consumer is isolated: if one throws an error, the others still run.
    --
    -- âš  ADDING A NEW CONSUMER:
    --   Add a new entry to collectibleDispatch below. Do NOT register for
    --   WN_COLLECTIBLE_OBTAINED via RegisterMessage anywhere else in the codebase.
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
    -- Plan reminders: optional compact toast via WN_SHOW_REMINDER_TOAST (not Blizzard AddAlert hooks)
    
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
    -- AceEvent: callback is (eventName, ...wowArgs); ADDON_LOADED's sole payload is the loaded addon name.
    self:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "Blizzard_SharedXML" or loadedAddon == "Blizzard_AchievementUI"
            or loadedAddon == "Blizzard_AdventureGuide" then
            if self.ApplyBlizzardAchievementAlertSuppression then
                self:ApplyBlizzardAchievementAlertSuppression()
            end
        end
    end)
    self:RegisterEvent("PLAYER_LOGIN", function()
        if self.ApplyBlizzardAchievementAlertSuppression then
            self:ApplyBlizzardAchievementAlertSuppression()
        end
    end)
end

---Shorten Blizzard's long criteria description to a display name (e.g. "Player Has Opened all X" -> "X").
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

local function GetNotificationProfileDb()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
end

---Replace Achievement Popup ON => WN alerts; OFF => Blizzard only (no WN achievement/criteria toasts).
local function ShouldUseWnAchievementAlert()
    local db = GetNotificationProfileDb()
    return db and db.hideBlizzardAchievementAlert == true
end

---WN criteria progress toast (only when replace mode + criteria toggle).
local function ShouldUseWnCriteriaProgress()
    local db = GetNotificationProfileDb()
    return db and db.hideBlizzardAchievementAlert == true and db.showCriteriaProgressNotifications ~= false
end

---Normalize AddAlert first arg (number, numeric string, or alert payload table).
local function ResolveAchievementAlertID(a1)
    if type(a1) == "number" then return a1 end
    if type(a1) == "string" then return tonumber(a1) end
    if type(a1) == "table" then
        local id = a1.achievementID or a1.id
        if type(id) == "number" then return id end
        if type(id) == "string" then return tonumber(id) end
    end
    return nil
end

---Deduped criteria progress toast; returns true when WN handled (or duplicate suppressed).
local function TryDispatchCriteriaProgressToast(achievementID, criteriaIndex)
    if not ShouldUseWnCriteriaProgress() then return false end
    if not achievementID or type(achievementID) ~= "number" then return false end
    if issecretvalue and issecretvalue(achievementID) then return false end

    local key = tostring(achievementID) .. "|" .. tostring(criteriaIndex == nil and "nil" or criteriaIndex)
    local now = GetTime()
    if lastCriteriaProgressEmitKey == key and lastCriteriaProgressEmitTime
        and (now - lastCriteriaProgressEmitTime) < 0.45 then
        return true
    end

    local shown = WarbandNexus and WarbandNexus.ShowCriteriaProgressNotification
        and WarbandNexus:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
    if shown then
        lastCriteriaProgressEmitKey = key
        lastCriteriaProgressEmitTime = now
        return true
    end
    return false
end

local wnAddAlertWrappers = setmetatable({}, { __mode = "k" })

local function MarkWnAddAlertWrapper(fn)
    if type(fn) == "function" then
        wnAddAlertWrappers[fn] = true
    end
end

local function IsWnAddAlertWrapper(fn)
    return type(fn) == "function" and wnAddAlertWrappers[fn] == true
end

local function CaptureBlizzardAddAlertHandlers(addon)
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
    end
    if AchievementAlertSystem and type(AchievementAlertSystem.AddAlert) == "function" then
        local fn = AchievementAlertSystem.AddAlert
        if not IsWnAddAlertWrapper(fn) then
            addon._blizzAchievementAddAlert = fn
        end
    end
    if CriteriaAlertSystem and type(CriteriaAlertSystem.AddAlert) == "function" then
        local fn = CriteriaAlertSystem.AddAlert
        if not IsWnAddAlertWrapper(fn) then
            addon._blizzCriteriaAddAlert = fn
        end
    end
end

local function InstallBlizzardAlertFrameHideHooks()
    local max = _G.MAX_ACHIEVEMENT_ALERTS or 4
    for i = 1, max do
        local achF = _G["AchievementAlertFrame" .. i]
        if achF and not achF._wnAchAlertHideHooked then
            achF:HookScript("OnShow", function(self)
                if self.Hide and ShouldUseWnAchievementAlert() then
                    self:Hide()
                end
            end)
            achF._wnAchAlertHideHooked = true
        end
        local critF = _G["CriteriaAlertFrame" .. i]
        if critF and not critF._wnCritAlertHideHooked then
            critF:HookScript("OnShow", function(self)
                -- Only hide criteria bars when WN criteria lane is active; leave Blizzard
                -- criteria alerts visible when Criteria Progress Toast is off.
                if self.Hide and ShouldUseWnCriteriaProgress() then
                    self:Hide()
                end
            end)
            critF._wnCritAlertHideHooked = true
        end
    end
    local cf = _G.CriteriaAlertFrame
    if cf and not cf._wnCritAlertHideHooked then
        cf:HookScript("OnShow", function(self)
            if self.Hide and ShouldUseWnCriteriaProgress() then
                self:Hide()
            end
        end)
        cf._wnCritAlertHideHooked = true
    end
end

local function BuildAchievementAddAlertReplacement(orig)
    return function(sys, a1, a2, ...)
        if not ShouldUseWnAchievementAlert() then
            return orig(sys, a1, a2, ...)
        end
        local achievementID = ResolveAchievementAlertID(a1)
        if not achievementID then
            return orig(sys, a1, a2, ...)
        end
        local hasExtra = (a2 ~= nil) or (select("#", ...) > 0)
        if not hasExtra then
            local shown = WarbandNexus and WarbandNexus.ShowAchievementNotification
                and WarbandNexus:ShowAchievementNotification(achievementID)
            if not shown then
                -- WN toast will not appear (notifications off / dedup) — fall back to
                -- Blizzard's popup instead of swallowing the alert entirely.
                return orig(sys, a1, a2, ...)
            end
            return
        end
        local origA1, origA2 = a1, a2
        local arg1, arg2 = achievementID, a2
        local rest = { ... }
        C_Timer.After(0, function()
            if not ShouldUseWnAchievementAlert() then
                pcall(orig, sys, origA1, origA2, unpack(rest))
                return
            end
            local _, _, _, completed = GetAchievementInfo(arg1)
            if completed then
                local shown = WarbandNexus and WarbandNexus.ShowAchievementNotification
                    and WarbandNexus:ShowAchievementNotification(arg1)
                if not shown then
                    pcall(orig, sys, origA1, origA2, unpack(rest))
                end
                return
            end
            if TryDispatchCriteriaProgressToast(arg1, arg2) then
                return
            end
            pcall(orig, sys, origA1, origA2, unpack(rest))
        end)
    end
end

local function BuildCriteriaAddAlertReplacement(orig)
    return function(sys, a1, a2, ...)
        if not ShouldUseWnAchievementAlert() then
            return orig(sys, a1, a2, ...)
        end
        local achievementID = ResolveAchievementAlertID(a1)
        if not achievementID then
            return orig(sys, a1, a2, ...)
        end
        local origA1, origA2 = a1, a2
        local arg1, arg2 = achievementID, a2
        local rest = { ... }
        C_Timer.After(0, function()
            if not ShouldUseWnAchievementAlert() then
                pcall(orig, sys, origA1, origA2, unpack(rest))
                return
            end
            local _, _, _, completed = GetAchievementInfo(arg1)
            if completed then
                local shown = WarbandNexus and WarbandNexus.ShowAchievementNotification
                    and WarbandNexus:ShowAchievementNotification(arg1)
                if not shown then
                    pcall(orig, sys, origA1, origA2, unpack(rest))
                end
                return
            end
            if TryDispatchCriteriaProgressToast(arg1, arg2) then
                return
            end
            pcall(orig, sys, origA1, origA2, unpack(rest))
        end)
    end
end

---Show toast for progressive achievements (e.g. Treasures of X, multi-step): one step completed = "Achievement Progress" title + criteria name only.
---Only when Replace Achievement Popup is ON and Criteria Progress Toast is enabled.
---@return boolean shown true when the WN criteria toast was queued
function WarbandNexus:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
    if not achievementID or type(achievementID) ~= "number" then return false end
    local db = self.db and self.db.profile and self.db.profile.notifications
    if not db or not db.hideBlizzardAchievementAlert then return false end
    if not db.showCriteriaProgressNotifications then return false end
    if db.enabled == false then return false end
    if issecretvalue and issecretvalue(achievementID) then return false end

    -- Do not show progress toast when achievement is already completed (avoids overlap with "Achievement Earned" / collectible toast)
    local _, _, _, completed = GetAchievementInfo(achievementID)
    if completed then return false end

    -- Blizzard AddAlert passes (achievementID, criteriaName) — that string IS the display name (progress completed). Use it as-is.
    local displayNameFromEvent = nil
    if type(criteriaIndex) == "string" and criteriaIndex ~= "" then
        displayNameFromEvent = criteriaIndex
        if issecretvalue and issecretvalue(displayNameFromEvent) then displayNameFromEvent = nil end
    end

    local numCriteria = GetAchievementNumCriteria(achievementID)
    local hasEventCriteriaText = displayNameFromEvent and displayNameFromEvent ~= ""
    if (not numCriteria or numCriteria == 0) and not hasEventCriteriaText then
        return false
    end

    local wantName = nil
    if type(criteriaIndex) == "string" and criteriaIndex ~= "" then
        wantName = criteriaIndex
        criteriaIndex = nil
    elseif type(criteriaIndex) ~= "number" or criteriaIndex < 1 or (numCriteria and criteriaIndex > numCriteria) then
        criteriaIndex = nil
    end

    if wantName and numCriteria and numCriteria > 0 then
        for i = 1, numCriteria do
            local name = GetAchievementCriteriaInfo(achievementID, i)
            if issecretvalue and name and issecretvalue(name) then name = nil end
            if name and name == wantName then criteriaIndex = i break end
        end
    end

    local completedCount = 0
    local criteriaName = ""
    if numCriteria and numCriteria > 0 then
        if criteriaIndex and criteriaIndex >= 1 and criteriaIndex <= numCriteria then
            for i = 1, numCriteria do
                local _, _, comp = GetAchievementCriteriaInfo(achievementID, i)
                if comp then completedCount = completedCount + 1 end
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
                if comp then completedCount = completedCount + 1 end
                if not criteriaName or criteriaName == "" then
                    if issecretvalue and name and issecretvalue(name) then name = nil end
                    criteriaName = (name and name ~= "" and name) and ShortenCriteriaDisplayName(name) or ""
                end
            end
            if criteriaName == "" then criteriaName = (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
        end
    end

    if displayNameFromEvent and displayNameFromEvent ~= "" then
        criteriaName = displayNameFromEvent
    elseif criteriaName == "" and hasEventCriteriaText then
        criteriaName = displayNameFromEvent
    end
    if criteriaName == "" then
        criteriaName = (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria"
    end
    
    local _, achName, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(achievementID)
    if issecretvalue and achName and issecretvalue(achName) then achName = nil end
    if issecretvalue and achIcon and issecretvalue(achIcon) then achIcon = nil end
    
    local criteriaTitleText = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"
    
    self:ShowModalNotification({
        compact = true,
        progressAnchor = true,
        criteriaTitle = criteriaTitleText,
        icon = achIcon or CATEGORY_ICONS.achievement,
        itemName = criteriaName,
        action = nil,
        achievementID = achievementID,
        playSound = false,
        autoDismiss = 3,
    })
    return true
end

---Swap or restore Blizzard AddAlert based on Replace Achievement Popup (live db read on each call).
function WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
    CaptureBlizzardAddAlertHandlers(self)
    local useWn = ShouldUseWnAchievementAlert()

    if AchievementAlertSystem and type(self._blizzAchievementAddAlert) == "function" then
        if useWn then
            local wrapper = BuildAchievementAddAlertReplacement(self._blizzAchievementAddAlert)
            MarkWnAddAlertWrapper(wrapper)
            AchievementAlertSystem.AddAlert = wrapper
        else
            AchievementAlertSystem.AddAlert = self._blizzAchievementAddAlert
        end
    end

    if CriteriaAlertSystem and type(self._blizzCriteriaAddAlert) == "function" then
        if useWn then
            local wrapperCrit = BuildCriteriaAddAlertReplacement(self._blizzCriteriaAddAlert)
            MarkWnAddAlertWrapper(wrapperCrit)
            CriteriaAlertSystem.AddAlert = wrapperCrit
        else
            CriteriaAlertSystem.AddAlert = self._blizzCriteriaAddAlert
        end
    end

    if useWn then
        InstallBlizzardAlertFrameHideHooks()
        C_Timer.After(0.5, InstallBlizzardAlertFrameHideHooks)
        C_Timer.After(2, InstallBlizzardAlertFrameHideHooks)
    end
end

---Ensure achievement UI + current Replace toggle is applied (test + live share one AddAlert path).
function TestLootEnsureAchievementAlertUI(addon)
    if not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
    end
    if addon and addon.ApplyBlizzardAchievementAlertSuppression then
        addon:ApplyBlizzardAchievementAlertSuppression()
    end
end

local function TestLootPrintAchievementReplaceMode(addon)
    local useWn = addon.db and addon.db.profile and addon.db.profile.notifications
        and addon.db.profile.notifications.hideBlizzardAchievementAlert
    if useWn then
        addon:Print("|cffffcc00Mode:|r Replace ON â€” WN alert only")
    else
        addon:Print("|cffffcc00Mode:|r Replace OFF â€” Blizzard alert only")
    end
end

function TestLootFireAchievementAddAlert(addon, achievementID, criteriaIndex)
    TestLootEnsureAchievementAlertUI(addon)
    if not AchievementAlertSystem or not AchievementAlertSystem.AddAlert then
        addon:Print("|cffff8800AchievementAlertSystem not loaded. Try /reload.|r")
        return false, "no system"
    end
    if criteriaIndex ~= nil then
        return pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID, criteriaIndex)
    end
    return pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID)
end

function TestLootResolveAchievementWithCriteria(preferredID)
    local tryIDs = { 6, 7, 8, 11, 12, 60981, 40752 }
    if preferredID then
        tryIDs = { preferredID, 6, 7, 8, 11, 12, 60981, 40752 }
    end
    for ti = 1, #tryIDs do
        local fid = tryIDs[ti]
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

---Blizzard hooked progressive achievement / criteria AddAlert routes here (never calls ShowCriteriaProgressNotification directly â€” avoids stacking duplicate Alerts with WN_REMINDER lane).
function WarbandNexus:OnShowCriteriaProgressMessage(_, payload)
    if not payload then return end
    TryDispatchCriteriaProgressToast(payload.achievementID, payload.criteriaIndex)
end

---Dedicated To-Do reminder toast lane (ReminderService ActivateReminder â†’ WN_SHOW_REMINDER_TOAST).
function WarbandNexus:OnShowReminderToast(_, payload)
    if not payload or not payload.data then return end
    self:ShowModalNotification(payload.data)
end

---Generic notification handler (nonâ€“reminder modals â€” legacy / external callers)
local showNotificationDebounceTimer = nil
local showNotificationPendingData = nil
local SHOW_NOTIFICATION_DEBOUNCE = 0.08

function WarbandNexus:OnShowNotification(event, payload)
    if not payload or not payload.data then return end
    showNotificationPendingData = payload.data
    if showNotificationDebounceTimer and showNotificationDebounceTimer.Cancel then
        showNotificationDebounceTimer:Cancel()
    end
    showNotificationDebounceTimer = C_Timer.NewTimer(SHOW_NOTIFICATION_DEBOUNCE, function()
        showNotificationDebounceTimer = nil
        local data = showNotificationPendingData
        showNotificationPendingData = nil
        if data and WarbandNexus.ShowModalNotification then
            WarbandNexus:ShowModalNotification(data)
        end
    end)
end

-- SCREEN FLASH EFFECT

local screenFlashFrame = nil

---Play a full-screen flash effect (accent-colored edge vignette that fades out)
function WarbandNexus:PlayScreenFlash(duration)
    duration = duration or 0.6
    
    -- Check setting
    if not self.db or not self.db.profile or not self.db.profile.notifications then return end
    if not self.db.profile.notifications.screenFlashEffect then return end
    
    -- Don't flash during combat
    if InCombatLockdown() then return end
    
    -- Create frame on first use (intentional fullscreen texture host â€” not SharedWidgets bordered shell)
    if not screenFlashFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(9999)
        f:EnableMouse(false)
        f:SetMouseClickEnabled(false)
        
        -- Center flash (full screen, soft white â†’ transparent)
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
function WarbandNexus:OnCollectibleObtained(event, data)
    if not data or not data.type then return end
    -- Classic achievement mode: the message feeds try-counter/recent/caches upstream,
    -- but Blizzard's own popup is the visible alert — no WN toast on top of it.
    if data.suppressToast then return end
    -- Achievement can have nil/empty name (hidden achievements); use fallback for display
    local displayName = data.name
    if displayName and issecretvalue and issecretvalue(displayName) then return end
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
    
    if not self.db.profile.notifications.enabled then
        NotifyDebug("|cffff6600BLOCKED: notifications.enabled = false|r")
        return
    end

    -- Replace Achievement Popup: OFF => Blizzard classic only (never WN achievement toast).
    if data.type == "achievement" and not self.db.profile.notifications.hideBlizzardAchievementAlert then
        NotifyDebug("|cffff6600BLOCKED: achievement (Blizzard classic mode)|r")
        return
    end

    -- Loot master + per-type toggles (achievement in replace mode uses hideBlizzardAchievementAlert only).
    if data.type ~= "achievement" then
        if not self.db.profile.notifications.showLootNotifications then
            NotifyDebug("|cffff6600BLOCKED: showLootNotifications = false|r")
            return
        end

        local typeToggleMap = {
            mount = "showMountNotifications",
            pet = "showPetNotifications",
            toy = "showToyNotifications",
            transmog = "showTransmogNotifications",
            illusion = "showIllusionNotifications",
            title = "showTitleNotifications",
        }
        local toggleKey = typeToggleMap[data.type]
        if toggleKey and self.db.profile.notifications[toggleKey] == false then
            NotifyDebug("|cffff6600BLOCKED: %s = false|r", toggleKey)
            return
        end
    end

    -- TryCounter fires on loot; CollectionService fires on NEW_MOUNT / journal â€” same mount, two toasts.
    -- Normalize mount itemID â†’ mountID so both payloads share one dedupe key.
    local lootToastDedupeKey = BuildCollectibleLootToastDedupeKey(data)
    if lootToastDedupeKey then
        local nowDedupe = GetTime()
        local prevToast = lastCollectibleLootToastShownAt[lootToastDedupeKey]
        if prevToast and (nowDedupe - prevToast) < COLLECTIBLE_LOOT_TOAST_DEDUP_SEC then
            NotifyDebug("|cff888888Skipped duplicate collectible loot toast: %s|r", lootToastDedupeKey)
            return
        end
    end
    -- Build try count message for mount/pet/toy/illusion/item (the "BAM" moment â€” farmed drop obtained)
    -- When TryCounter sends preResetTryCount, we always show the celebratory message and flash.
    local tryMessage = nil
    local hasTryCount = false
    local tryCountTypes = { mount = true, pet = true, toy = true, illusion = true, item = true }
    if tryCountTypes[data.type] and data.id then
        -- If TryCounter sent preResetTryCount, this is a detected drop â€” always treat as drop source for celebration
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
    if hasTryCount then
        overrides.toastLane = "tryCounter"
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
        overrides.action = string.format("%s  Â·  %s", doneMsg, string.format(ptsFmt, pts))
    end
    -- Farmed drop obtained: keep notification on screen longer for the "yeeey" moment
    if hasTryCount then
        overrides.autoDismiss = 7
    end
    -- Intentionally omit data.obtainedBy from toast body (Collections Recent still uses it elsewhere).
    self:Notify(data.type, displayName, data.icon, overrides)
    if lootToastDedupeKey then
        lastCollectibleLootToastShownAt[lootToastDedupeKey] = GetTime()
    end

    -- Screen flash (setting: screenFlashEffect) + optional screenshot â€” try-tracked collectible drop
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
function WarbandNexus:OnPlanCompleted(event, data)
    if not data or not data.name then return end
    
    -- Use planType icon fallback chain: data.icon â†’ planType category icon â†’ plan default
    local icon = data.icon or CATEGORY_ICONS[data.planType] or CATEGORY_ICONS.plan
    self:Notify("plan", data.name, icon)
end

-- Shared vault/quest lookup tables (defined once, used by multiple handlers)
local VAULT_CATEGORIES = {
    dungeon = {name = (ns.L and ns.L["DUNGEON_CAT"]) or "Dungeon", atlas = "questlog-questtypeicon-heroic", thresholds = {1, 4, 8}},
    raid    = {name = (ns.L and ns.L["RAID_CAT"]) or "Raid",    atlas = "questlog-questtypeicon-raid",   thresholds = {2, 4, 6}},
    world   = {name = (ns.L and ns.L["WORLD_CAT"]) or "World",   atlas = "questlog-questtypeicon-Delves", thresholds = {2, 4, 8}},
    specialAssignment = {name = (ns.L and ns.L["SPECIAL_ASSIGNMENT_CAT"]) or "Assignment", atlas = "questlog-questtypeicon-important", thresholds = {1, 2}},
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
function WarbandNexus:OnVaultCheckpointCompleted(event, data)
    if not data or not data.characterName or not data.category or not data.progress then return end
    
    local cat = VAULT_CATEGORIES[data.category] or {name = (ns.L and ns.L["ACTIVITY_CAT"]) or "Activity", atlas = "greatVault-whole-normal", thresholds = {1, 4, 8}}
    local thresholds = cat.thresholds or {1, 4, 8}
    local maxT = thresholds[#thresholds] or 8
    local raw = tonumber(data.progress) or 0
    if raw < 0 then raw = 0 end
    -- API can exceed the final vault threshold (e.g. extra runs); never show "10/8" style vs track cap.
    local dispCur = math.min(raw, maxT)
    local dispCap = maxT
    
    self:Notify("vault", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = string.format((ns.L and ns.L["PROGRESS_COUNT_FORMAT"]) or "%d/%d Progress", dispCur, dispCap),
    })
end

---Vault slot completed handler
function WarbandNexus:OnVaultSlotCompleted(event, data)
    if not data or not data.characterName or not data.category then return end

    local cat = VAULT_CATEGORIES[data.category] or {name = (ns.L and ns.L["ACTIVITY_CAT"]) or "Activity", atlas = "greatVault-whole-normal", thresholds = {1, 4, 8}}
    local threshold = data.threshold or 0

    -- Do not use showCriteriaProgressNotifications here: that path is for achievement criteria toasts.
    -- Vault slot completion already uses the full Notify line below; a second compact toast duplicated the same milestone.

    self:Notify("vault", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = string.format((ns.L and ns.L["PROGRESS_COMPLETED_FORMAT"]) or "%d/%d Progress Completed", threshold, threshold),
    })
end

---Vault plan fully completed handler
function WarbandNexus:OnVaultPlanCompleted(event, data)
    if not data or not data.characterName then return end
    
    self:Notify("vault", string.format((ns.L and ns.L["WEEKLY_VAULT_PLAN_FORMAT"]) or "Weekly Vault Plan - %s", data.characterName), nil, {
        iconAtlas = "greatVault-whole-normal",
        action = (ns.L and ns.L["ALL_SLOTS_COMPLETE"]) or "All Slots Complete!",
    })
end

---Quest completed handler
function WarbandNexus:OnQuestCompleted(event, data)
    if not data or not data.characterName or not data.questTitle then return end
    
    local cat = QUEST_CATEGORIES[data.category] or {name = (ns.L and ns.L["QUEST_LABEL"]) or "Quest:", atlas = "questlog-questtypeicon-heroic"}
    
    self:Notify("quest", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = data.questTitle .. " " .. ((ns.L and ns.L["QUEST_COMPLETED_SUFFIX"]) or "Completed"),
    })
end

---Vault reward available handler
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

---Show loot notification (compatibility wrapper â€” resolves icon then delegates to Notify)
---Initialize loot notification system
function WarbandNexus:InitializeLootNotifications()
    -- Initialize event-driven notification system
    self:InitializeNotificationListeners()
    
    -- CollectionService handles collection detection
    -- NotificationManager only provides display functions
end

---Test loot notification system (All notification types with real data)
function WarbandNexus:TestLootNotification(type, id, step)
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Achievement alert test (same path as in-game) ===|r")
        self:Print("|cff44ff44/wn testloot earn [id]|r - Full achievement earned (AddAlert)")
        self:Print("|cff44ff44/wn testloot progress [id] [step]|r - Criteria step complete (AddAlert)")
        self:Print("|cff888888Replace ON => WN only. Replace OFF => Blizzard only.|r")
        self:Print("|cffffcc00/wn testloot mount|r | |cffffcc00pet|r | |cffffcc00toy|r | |cffffcc00plan|r | |cffffcc00all|r")
        return
    end

    -- Aliases (same AddAlert pipeline as earn / progress)
    if type == "blizzard" or type == "achievement" then
        type = "earn"
    elseif type == "suppress" or type == "criteria" then
        type = "progress"
    elseif type == "both" then
        self:Print("|cffff8800Use |cff44ff44/wn testloot earn|r and |cff44ff44/wn testloot progress|r separately (one alert system).|r")
        return
    end

    -- Full achievement earned â€” single AddAlert(achievementID); respects Replace toggle.
    if type == "earn" then
        local achievementID = tonumber(id) or 6
        local okInfo, name = pcall(GetAchievementInfo, achievementID)
        if not okInfo or not name then
            self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
            return
        end
        TestLootPrintAchievementReplaceMode(self)
        self:Print("|cff00ccffAchievement earned test:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
        local ok, err = TestLootFireAchievementAddAlert(self, achievementID, nil)
        if not ok then
            self:Print("|cffff8800AddAlert failed: " .. tostring(err) .. "|r")
        end
        return
    end

    -- Criteria / progress step â€” single AddAlert(achievementID, criteriaIndex).
    if type == "progress" then
        local preferredID = tonumber(id)
        local achievementID, numCriteria = TestLootResolveAchievementWithCriteria(preferredID)
        if not achievementID then
            self:Print("|cffff0000No valid achievement with criteria found. Try: /wn testloot progress 6|r")
            return
        end
        local criteriaIndex = math.min(tonumber(step) or 1, numCriteria)
        if criteriaIndex < 1 then criteriaIndex = 1 end
        local _, name = GetAchievementInfo(achievementID)
        TestLootPrintAchievementReplaceMode(self)
        self:Print("|cff00ccffCriteria progress test:|r " .. tostring(name) .. " (ID " .. achievementID .. ", step " .. criteriaIndex .. "/" .. numCriteria .. ")")
        local ok, err = TestLootFireAchievementAddAlert(self, achievementID, criteriaIndex)
        if not ok then
            self:Print("|cffff8800AddAlert failed: " .. tostring(err) .. "|r")
        end
        return
    end

    local delay = 0
    if type == "vaultprogress" then
        local db = self.db and self.db.profile and self.db.profile.notifications
        if not db or not db.showCriteriaProgressNotifications then
            self:Print("|cffff8800Enable Settings > Notifications > Criteria Progress Toast to see vault progress toasts.|r")
        end
        local cat = VAULT_CATEGORIES.dungeon or {name = "Dungeon", atlas = "questlog-questtypeicon-heroic"}
        self:ShowModalNotification({
            compact = true,
            progressAnchor = true,
            iconAtlas = cat.atlas,
            criteriaTitle = string.format((ns.L and ns.L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", 4, 4),
            itemName = cat.name,
            playSound = false,
            autoDismiss = 3,
        })
        self:Print("|cff00ff00Vault progress toast shown (4/4 " .. cat.name .. ")|r")
        return
    end

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
    
    -- Achievement in "all" bundle uses the same AddAlert path as earn.
    if type == "all" then
        C_Timer.After(delay, function()
            local addon = WarbandNexus or self
            local achievementID = id or 60981
            TestLootFireAchievementAddAlert(addon, achievementID, nil)
            local _, achievementName = GetAchievementInfo(achievementID)
            if achievementName then
                addon:Print("|cff00ff00Achievement alert (AddAlert): " .. achievementName .. " (ID: " .. achievementID .. ")|r")
            end
        end)
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
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
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
        self:Print("|cff00ff00Ã¢Å“â€œ C_WeeklyRewards API available|r")
    end
    
    if not C_WeeklyRewards.HasAvailableRewards then
        self:Print("|cffff0000ERROR: HasAvailableRewards function not found!|r")
        return
    else
        self:Print("|cff00ff00Ã¢Å“â€œ HasAvailableRewards function available|r")
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
        self:Print("|cff00ff00Ã¢Å“â€œ YOU HAVE UNCLAIMED REWARDS!|r")
        self:ShowVaultReminder({})
    else
        self:Print("|cff888888Ã¢Å“â€” No unclaimed (or not current period / not claimable)|r")
    end
    
    self:Print("|cff00ccff======================|r")
end

