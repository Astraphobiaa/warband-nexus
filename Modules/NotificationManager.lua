--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders

    NOTIFICATION FLOW:
      WN_COLLECTIBLE_OBTAINED dispatch -> OnCollectibleObtained -> Notify -> ShowModalNotification (queue max 6)
      WN_PLAN_COMPLETED / WN_VAULT_* / WN_QUEST_COMPLETED -> handler -> Notify
      WN_SHOW_REMINDER_TOAST -> OnShowReminderToast
      Achievement lane (binary): ns.NotificationPresentation — Warband popups ON -> AddAlert hook + WN toast;
        OFF -> native Blizzard AddAlert only (suppressToast on WN_COLLECTIBLE_OBTAINED for achievements)
      Currency/reputation: ChatMessageService only (not toast lane)

    WN_FACTORY: Changelog popup scroll-child + themed close use `ns.UI.Factory` / ApplyVisuals; toast layering
    (effects/backdrop/icon z-order) stays plain `CreateFrame`; screen flash overlay remains an intentional fullscreen host.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local FontManager = ns.FontManager  -- Centralized font management
local ApplyVisuals = ns.UI_ApplyVisuals
local ToastFactory = ns.NotificationToastFactory
local NP = ns.NotificationPresentation
assert(NP, "NotificationManager: load NotificationManager_Presentation.lua first")
local ToastFx = ns.NotificationToastFx
assert(ToastFx, "NotificationManager: load NotificationManager_ToastFx.lua first")
local ToastChrome = ns.NotificationToastChrome
assert(ToastChrome, "NotificationManager: load NotificationManager_ToastChrome.lua first")
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
local lastProgressAlertEmitKey = nil
local lastProgressAlertEmitTime = nil
local TOAST_FADE_OUT_SEC = 0.32
local TOAST_COLLAPSE_DELAY_SEC = 0.14
local TOAST_REPOSITION_SEC = 0.38
local TOAST_ENTRANCE_SEC = 0.3
local TOAST_TRY_COUNTER_FLASH_DELAY_SEC = 0.35
local TestLootEnsureAchievementAlertUI, TestLootFireAchievementAddAlert, TestLootFireProgressAddAlert
local TestLootResolveAchievementWithCriteria, TestLootPrintAchievementReplaceMode

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
local NM_SUN_WASH_PEAK = 0.32
local NM_SUN_CORE_PEAK = 0.55
local NM_SUN_WASH_RGB = { 1, 0.96, 0.88 }
local NM_SUN_CORE_RGB = { 1, 1, 0.95 }
local NM_SHEEN_PEAK_ALPHA = 0.38
local NM_SHEEN_WIDTH_RATIO = 0.36

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

    local sunScaleMult = 1
    if toastHost._toastFxSunScale and type(toastHost._toastFxSunScale) == "number" then
        sunScaleMult = toastHost._toastFxSunScale
    end
    local washPeak = NM_SUN_WASH_PEAK * sunScaleMult
    local corePeak = math.min(1, NM_SUN_CORE_PEAK * sunScaleMult)

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
    washIn:SetToAlpha(washPeak)
    washIn:SetDuration(0.09)
    washIn:SetSmoothing("OUT")

    local sunIn = ag:CreateAnimation("Alpha")
    sunIn:SetTarget(sunHost)
    sunIn:SetFromAlpha(0)
    sunIn:SetToAlpha(corePeak)
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
    washHold:SetFromAlpha(washPeak)
    washHold:SetToAlpha(washPeak * 0.78)
    washHold:SetDuration(0.14)
    washHold:SetStartDelay(0.09)
    washHold:SetSmoothing("NONE")

    local sunHold = ag:CreateAnimation("Alpha")
    sunHold:SetTarget(sunHost)
    sunHold:SetFromAlpha(corePeak)
    sunHold:SetToAlpha(corePeak * 0.55)
    sunHold:SetDuration(0.16)
    sunHold:SetStartDelay(0.07)
    sunHold:SetSmoothing("NONE")

    local washOut = ag:CreateAnimation("Alpha")
    washOut:SetTarget(fxRoot)
    washOut:SetFromAlpha(washPeak * 0.78)
    washOut:SetToAlpha(0)
    washOut:SetDuration(0.4)
    washOut:SetStartDelay(0.23)
    washOut:SetSmoothing("IN")

    local sunOut = ag:CreateAnimation("Alpha")
    sunOut:SetTarget(sunHost)
    sunOut:SetFromAlpha(corePeak * 0.55)
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
    local sheenPeak = (toastHost._toastFxSheenPeak and type(toastHost._toastFxSheenPeak) == "number")
        and toastHost._toastFxSheenPeak or NM_SHEEN_PEAK_ALPHA
    fadeIn:SetToAlpha(sheenPeak)
    fadeIn:SetDuration(0.05)
    fadeIn:SetSmoothing("OUT")

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetTarget(shineHost)
    fadeOut:SetFromAlpha(sheenPeak)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.16)
    fadeOut:SetStartDelay(math.max(0, duration - 0.1))
    fadeOut:SetSmoothing("IN")

    ag:Play()
end

local function NM_ResolveToastFxSize(toastHost, toastWidth, toastHeight)
    local w = toastHost:GetWidth() or toastHost._toastFxWidth or toastWidth or 0
    local h = toastHost:GetHeight() or toastHost._toastFxHeight or toastHeight or 0
    if w < 1 then w = toastWidth or toastHost._toastFxWidth or 360 end
    if h < 1 then h = toastHeight or toastHost._toastFxHeight or 64 end
    return w, h
end

---Optional entrance polish — default off; only explicit celebration gets a soft sheen.
local function NM_PlayToastEntranceEffects(toastHost, toastWidth, toastHeight)
    if not toastHost or toastHost.isClosing or toastHost._removed or not toastHost:IsShown() then
        return false
    end
    local tier = toastHost._toastFxTier or "minimal"
    if tier == "minimal" or tier == "progress" or tier == "reminder" or tier == "compact" then
        return false
    end
    local w, h = NM_ResolveToastFxSize(toastHost, toastWidth, toastHeight)
    if w < 1 or h < 1 then
        return false
    end
    if tier == "standard" then
        toastHost._toastFxSheenPeak = 0.36
        NM_PlayToastSweepShine(toastHost, w, h)
        return true
    end
    if tier == "celebration" then
        toastHost._toastFxSheenPeak = 0.34
        NM_PlayToastSweepShine(toastHost, w, h)
        return true
    end
    return false
end

local function NM_AssignToastFxMetadata(toastHost, config, titleColor, iconFrame, backdropFrame)
    if not toastHost then return end
    toastHost._toastFxTier = (config and config.toastFxTier) or (ToastFx and ToastFx.InferTier(config)) or "standard"
    toastHost._toastFxIcon = iconFrame
    toastHost._toastFxBackdrop = backdropFrame
    toastHost._toastFxAccent = titleColor
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
    All compact toasts: icon flipbook chrome only (no card-wide glow).
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
    tryCounter = "Interface\\Icons\\INV_Misc_Lucky_MoneyEnvelope",
}

-- Action text mapping (subtitle line)
local ACTION_TEXT = {
    mount = (ns.L and ns.L["COLLECTED_MOUNT_MSG"]) or "You have collected a mount",
    pet = (ns.L and ns.L["COLLECTED_PET_MSG"]) or "You have collected a battle pet",
    toy = (ns.L and ns.L["COLLECTED_TOY_MSG"]) or "You have collected a toy",
    illusion = (ns.L and ns.L["COLLECTED_ILLUSION_MSG"]) or "You have collected an illusion",
    achievement = "",
    criteria_progress = (ns.L and ns.L["CRITERIA_PROGRESS_MSG"]) or "Progress",
    title = (ns.L and ns.L["EARNED_TITLE_MSG"]) or "You have earned a title",
    plan = (ns.L and ns.L["COMPLETED_PLAN_MSG"]) or "You have completed a plan",
    item = (ns.L and ns.L["COLLECTED_ITEM_MSG"]) or "You received a rare drop",
    reminder = (ns.L and ns.L["REMINDER_PREFIX"]) or "Reminder",
    tryCounter = "",
}

---Build a standardized notification config
---@return table config Ready to pass to ShowModalNotification
function WarbandNexus:BuildNotificationConfig(notifType, name, icon, overrides)
    local safeIcon = icon
    if safeIcon and issecretvalue and issecretvalue(safeIcon) then safeIcon = nil end
    local safeName = name
    if safeName and issecretvalue and issecretvalue(safeName) then safeName = nil end
    local resolvedIcon = safeIcon or CATEGORY_ICONS[notifType] or DEFAULT_NOTIFICATION_ICON
    local chrome = ToastChrome.Resolve(notifType)
    local config = {
        compact = true,
        notifType = notifType,
        icon = resolvedIcon,
        itemName = safeName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
        action = ACTION_TEXT[notifType] or "",
        categoryTitle = chrome.categoryLabel,
        titleColor = chrome.accent,
        playSound = true,
        glowAtlas = nil,
        progressGlow = false,
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
    if notifType == "tryCounter" or (type(config.tryCount) == "number" and config.tryCount > 0) then
        config.categoryTitle = nil
    end
    return config
end

---Shortcut: build config and immediately show notification
---@return boolean shown false when queued at capacity
function WarbandNexus:Notify(notifType, name, icon, overrides)
    local config = self:BuildNotificationConfig(notifType, name, icon, overrides)
    return self:ShowModalNotification(config) == true
end

local function MaybeScheduleTryCounterCelebration(config, toastHost)
    if not config or not config.deferScreenFlash or not toastHost then return end
    local flashDelay = tonumber(TOAST_TRY_COUNTER_FLASH_DELAY_SEC) or 0.35
    C_Timer.After(flashDelay, function()
        if not WarbandNexus or not toastHost or toastHost._removed or toastHost.isClosing then return end
        if not toastHost:IsShown() or toastHost:GetAlpha() < 0.05 then return end
        WarbandNexus:PlayScreenFlash(0.6)
        local db = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
        if db and db.tryCounterDropScreenshot ~= false then
            C_Timer.After(0.3, function()
                local db2 = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
                if db2 and db2.tryCounterDropScreenshot ~= false and Screenshot then
                    Screenshot()
                end
            end)
        end
    end)
end

--- Settings / QA: achievement + criteria-style + To-Do reminder in quick succession (same anchor stack).
local function ShowTestReminderToastModal(addon)
    if not addon or not addon.ShowModalNotification then return end
    local L = ns.L
    addon:ShowModalNotification({
        compact = true,
        planReminderToast = true,
        criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do reminder",
        itemName = (L and L["TEST_STACK_REMINDER"]) or "Plan reminder (test)",
        icon = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
        playSound = false,
        autoDismiss = 4,
        titleColor = ToastChrome.ReminderAccent(),
    })
end

function WarbandNexus:PrintNotificationTestHelp()
    self:Print("|cff00ccff=== Notification test (Settings button = stack) ===|r")
    self:Print("|cff44ff44/wn alerttest|r (alias: |cff44ff44/wn testalert|r) — Live AddAlert paths + collectible lanes")
    self:Print("|cff44ff44/wn notif stack|r — Achievement + criteria + reminder (respects Warband achievement popups toggle)")
    self:Print("|cff44ff44/wn notif earn [id]|r — Live path: Blizzard AchievementAlertSystem:AddAlert (earned)")
    self:Print("|cff44ff44/wn notif progress [id] [step]|r — Live path: CriteriaAlertSystem:AddAlert (criteria step)")
    self:Print("|cff44ff44/wn notif traveler|r — Traveler's Log progress toast (AddAlert hook or WN direct)")
    self:Print("|cff44ff44/wn notif earned [id]|r — Live path: ACHIEVEMENT_EARNED event (CollectionService)")
    self:Print("|cff44ff44/wn notif hierarchy|r — Criteria -> sub (type 8) -> meta chain (62901 / 12918 / 40958)")
    self:Print("|cff888888Toggle Settings > Notifications > Warband achievement popups ON/OFF, then re-run.|r")
    self:Print("|cff888888Default test achievement id is 6 if omitted.|r")
end

---@return boolean ok false when master notifications toggle is off
local function EnsureNotificationTestsEnabled(addon)
    local db = addon.db and addon.db.profile and addon.db.profile.notifications
    if not db or not db.enabled then
        addon:Print("|cffff8800Enable Settings > Notifications master toggle first.|r")
        return false
    end
    return true
end

---Same pipeline as in-game when the client shows an earned achievement alert.
function WarbandNexus:TestAchievementAlertEarn(achievementID)
    if not EnsureNotificationTestsEnabled(self) then return end
    achievementID = tonumber(achievementID) or 6
    local okInfo, name = pcall(GetAchievementInfo, achievementID)
    if not okInfo or not name then
        self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccffAchievement earned (AddAlert):|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
    local ok, err = TestLootFireAchievementAddAlert(self, achievementID, nil)
    if not ok then
        self:Print("|cffff8800AddAlert failed: " .. tostring(err) .. " — try /reload.|r")
    end
end

---Same pipeline as in-game criteria progress alerts.
function WarbandNexus:TestAchievementAlertProgress(achievementID, step)
    if not EnsureNotificationTestsEnabled(self) then return end
    local preferredID = tonumber(achievementID)
    local achID, numCriteria = TestLootResolveAchievementWithCriteria(preferredID)
    if not achID then
        self:Print("|cffff0000No valid achievement with criteria found. Try: /wn notif progress 6|r")
        return
    end
    local criteriaIndex = math.min(tonumber(step) or 1, numCriteria)
    if criteriaIndex < 1 then criteriaIndex = 1 end
    local _, name = GetAchievementInfo(achID)
    TestLootPrintAchievementReplaceMode(self)
    if not NP.UseWarbandCriteriaProgressPopups() then
        self:Print("|cffff8800Criteria progress popups OFF — expect Blizzard criteria bar. Enable Settings > Criteria progress popup.|r")
    end
    self:Print("|cff00ccffCriteria progress (AddAlert):|r " .. tostring(name)
        .. " (ID " .. achID .. ", step " .. criteriaIndex .. "/" .. numCriteria .. ")")
    local ok, err = TestLootFireAchievementAddAlert(self, achID, criteriaIndex)
    if not ok then
        self:Print("|cffff8800AddAlert failed: " .. tostring(err) .. " — try /reload.|r")
    end
end

---Fires ACHIEVEMENT_EARNED like a real completion (CollectionService + optional fallback timer).
function WarbandNexus:TestAchievementEarnedEvent(achievementID)
    if not EnsureNotificationTestsEnabled(self) then return end
    achievementID = tonumber(achievementID) or 6
    local okInfo, name = pcall(GetAchievementInfo, achievementID)
    if not okInfo or not name then
        self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccffACHIEVEMENT_EARNED event:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
    if self.OnAchievementEarned then
        self:OnAchievementEarned("ACHIEVEMENT_EARNED", achievementID)
    else
        self:Print("|cffff8800CollectionService handler not loaded.|r")
        return
    end
    if NP.UseWarbandAchievementPopups() then
        self:Print("|cff888888Warband popups ON: expect WN toast via AddAlert hook or ~1.25s fallback.|r")
    else
        self:Print("|cff888888Warband popups OFF: expect Blizzard gold alert (AddAlert from client).|r")
    end
end

---Public slash command: /wn notif [stack|earn|progress|earned|help]
function WarbandNexus:RunNotificationSlashCommand(type, id, step)
    type = type and strlower(type) or "help"
    if type == "help" or type == "?" then
        self:PrintNotificationTestHelp()
        return
    end
    if type == "stack" then
        self:TestNotificationStack()
        return
    end
    if type == "earn" or type == "achievement" or type == "blizzard" then
        self:TestAchievementAlertEarn(id)
        return
    end
    if type == "progress" or type == "criteria" then
        self:TestAchievementAlertProgress(id, step)
        return
    end
    if type == "traveler" or type == "travelerslog" or type == "progressalert" then
        self:TestProgressAlert()
        return
    end
    if type == "earned" or type == "event" then
        self:TestAchievementEarnedEvent(id)
        return
    end
    if type == "hierarchy" or type == "chain" or type == "meta" then
        self:TestAchievementAlertHierarchy()
        return
    end
    self:Print("|cffff0000Unknown subcommand.|r")
    self:PrintNotificationTestHelp()
end

local ALERT_TEST_STEP_SEC = 0.55
local ALERT_TEST_DISMISS_SEC = 9

---Public QA: /wn alerttest — stagger every WN toast lane (no debug mode).
function WarbandNexus:TestAlertTest(sub)
    sub = sub and strlower(sub) or "all"
    if sub == "help" or sub == "?" then
        self:Print("|cff00ccff=== /wn alerttest ===|r")
        self:Print("|cff44ff44/wn alerttest|r — All toast types in one stack (unified layout)")
        self:Print("|cff8888881.|r Achievement earned — live AddAlert (shield + points)")
        self:Print("|cff8888882.|r Criteria step — live CriteriaAlertSystem (no points shield)")
        self:Print("|cff8888883.|r Traveler's Log — live ProgressAlertSystem")
        self:Print("|cff8888884.|r To-Do reminder — compact reminder lane")
        self:Print("|cff8888885.|r Mount — Notify collectible lane")
        self:Print("|cff8888886.|r Pet — Notify collectible lane")
        self:Print("|cff8888887.|r Toy — Notify collectible lane")
        self:Print("|cff8888888.|r Plan completed — Notify plan lane")
        self:Print("|cff8888889.|r Try-counter mount — COLLECTIBLE_OBTAINED + attempts")
        self:Print("|cff88888810.|r Vault progress — compact criteria-style (no shield)")
        self:Print("|cff44ff44/wn alerttest hierarchy|r — Criteria -> sub -> meta chain only")
        return
    end
    if sub == "hierarchy" or sub == "chain" or sub == "meta" then
        self:TestAchievementAlertHierarchy()
        return
    end
    if not EnsureNotificationTestsEnabled(self) then return end

    local L = ns.L
    local delay = 0
    local function step(after, fn)
        C_Timer.After(after, function()
            if WarbandNexus and fn then fn(WarbandNexus) end
        end)
    end

    self:Print("|cff00ccff[WN Alert Test]|r Firing live alert pipelines — watch the unified stack.")

    step(delay, function(addon)
        addon:TestAchievementAlertEarn(6)
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:TestAchievementAlertProgress(nil, 1)
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        if addon.TestProgressAlert then
            addon:TestProgressAlert()
        end
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local L = ns.L
        addon:ShowModalNotification({
            compact = true,
            planReminderToast = true,
            criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do reminder",
            itemName = (L and L["TEST_STACK_REMINDER"]) or "Plan reminder (test)",
            icon = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
            playSound = false,
            autoDismiss = ALERT_TEST_DISMISS_SEC,
            titleColor = ToastChrome.ReminderAccent(),
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local mountID = 460
        local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
        if mountName then
            addon:Notify("mount", mountName, icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
        else
            addon:Notify("mount", "Grand Black War Mammoth", "Interface\\Icons\\Ability_Mount_Mammoth_Black", {
                playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC,
            })
        end
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local speciesID = 39
        local speciesName, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        addon:Notify("pet", speciesName or "Mechanical Squirrel Box", icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local toyItemID = 54452
        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
        local itemName, _, _, _, _, _, _, _, _, icon = GetItemInfoFn(toyItemID)
        addon:Notify("toy", itemName or "Magic Pet Mirror", icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:Notify("plan", "Bloodsail Admiral", "Interface\\Icons\\INV_Scroll_11", {
            playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC,
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local mountID = 418
        local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
        addon:SendMessage(E.COLLECTIBLE_OBTAINED, {
            type = "mount",
            id = mountID,
            name = mountName or "Armored Razzashi Raptor",
            icon = icon or "Interface\\Icons\\Ability_Mount_Raptor",
            preResetTryCount = 12,
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:ShowModalNotification({
            compact = true,
            progressAnchor = true,
            iconAtlas = "questlog-questtypeicon-heroic",
            criteriaTitle = string.format((L and L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", 4, 8),
            itemName = (L and L["DUNGEON"]) or "Dungeon",
            titleColor = ToastChrome.CriteriaAccent(),
            playSound = false,
            autoDismiss = ALERT_TEST_DISMISS_SEC,
        })
    end)
end

function WarbandNexus:TestNotificationStack()
    local L = ns.L
    if not EnsureNotificationTestsEnabled(self) then return end
    local db = self.db.profile.notifications
    local useWarbandAchievementPopups = NP.UseWarbandAchievementPopups(db)

    if useWarbandAchievementPopups then
        self:Print("|cff00ccff[WN Notif]|r Warband achievement popups ON — live AddAlert earn + criteria + progress + reminder.")
        self:TestAchievementAlertEarn(6)
        C_Timer.After(0.12, function()
            if WarbandNexus and WarbandNexus.TestAchievementAlertProgress then
                WarbandNexus:TestAchievementAlertProgress(nil, 1)
            end
        end)
        C_Timer.After(0.24, function()
            if WarbandNexus and WarbandNexus.TestProgressAlert then
                WarbandNexus:TestProgressAlert()
            end
        end)
        C_Timer.After(0.36, function()
            ShowTestReminderToastModal(WarbandNexus)
        end)
        return
    end

    self:Print("|cff00ccff[WN Notif]|r Warband achievement popups OFF — Blizzard earn + criteria via AddAlert, then WN reminder.")
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
local stackRepositionWatchTicker = nil
local dismissQueue = {}
local dismissQueueHead = 1
local dismissSessionActive = false
local RequestDismissToast
local RemoveAlert
local BeginDismissToast

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

-- Collection toasts: full card width. Progress/criteria/reminder: narrower Blizzard criteria-bar width.
local ALERT_HEIGHT = 64
local ALERT_HEIGHT_COMPACT = 58
local ALERT_GAP = 6
local ALERT_SPACING = ALERT_HEIGHT + ALERT_GAP
local ALERT_WIDTH_COMPACT = 320
local ALERT_WIDTH_FIXED = ALERT_WIDTH_COMPACT
local ALERT_WIDTH_PROGRESS = 276
local ALERT_ICON_SIZE = 36
local ALERT_ICON_SLOT = 50
local ACHIEVEMENT_SHIELD_SIZE = 32
local ACHIEVEMENT_SHIELD_GAP = 1
local ACHIEVEMENT_SHIELD_ATLAS_POINTS = "UI-Achievement-Shield-1"
local ACHIEVEMENT_SHIELD_ATLAS_EMPTY = "UI-Achievement-Shield-NoPoints"
local ACHIEVEMENT_CRITERIA_TYPE_LINKED = 8 -- criteriaType ACHIEVEMENT (sub-achievement row); wiki GetAchievementCriteriaInfo
local ALERT_PAD_LEFT = 8
local ALERT_PAD_RIGHT = 10
local ALERT_PAD_TEXT = 6
local ALERT_HEIGHT_TALL = 74
local ALERT_HEIGHT_PROGRESS_MIN = ALERT_HEIGHT_COMPACT
local ALERT_HEIGHT_PROGRESS_MAX = ALERT_HEIGHT_TALL
local ALERT_HEIGHT_PROGRESS = ALERT_HEIGHT_COMPACT
local ALERT_PROGRESS_LAYOUT_REF_WIDTH = ALERT_WIDTH_PROGRESS
local ALERT_PROGRESS_ICON_LEADING_PAD = ALERT_PAD_LEFT

local function FormatToastAttemptsLabel(count)
    count = tonumber(count)
    if not count or count < 1 then
        return nil
    end
    local fmt = (ns.L and ns.L["NOTIFICATION_ATTEMPTS_FMT"])
        or (ns.L and ns.L["COLLECTION_LIST_ATTEMPTS_FMT"])
        or "%d Attempts"
    return string.format(fmt, count)
end

---Resolve achievement points for toast shield (config override or GetAchievementInfo).
local function NM_ResolveAchievementToastPoints(config)
    if not config then return nil end
    local pts = config.achievementPoints
    if pts == nil and config.achievementID then
        local achID = config.achievementID
        if not (issecretvalue and issecretvalue(achID)) then
            local ok, _, _, p = pcall(GetAchievementInfo, achID)
            if ok and type(p) == "number" then
                pts = p
            end
        end
    end
    return tonumber(pts)
end

---Blizzard-style points shield to the right of the achievement icon.
---@return Frame|nil shieldFrame
---@return number extraWidth additional icon-lane width consumed
local function NM_AttachAchievementPointsShield(iconSlotCompact, iconCompact, points)
    if not iconSlotCompact or not iconCompact then return nil, 0 end
    local numPts = tonumber(points)
    local hasPoints = numPts ~= nil and numPts > 0
    local atlas = hasPoints and ACHIEVEMENT_SHIELD_ATLAS_POINTS or ACHIEVEMENT_SHIELD_ATLAS_EMPTY

    local shieldFrame = CreateFrame("Frame", nil, iconSlotCompact)
    shieldFrame:SetSize(ACHIEVEMENT_SHIELD_SIZE, ACHIEVEMENT_SHIELD_SIZE)
    shieldFrame:SetPoint("LEFT", iconCompact, "RIGHT", ACHIEVEMENT_SHIELD_GAP, 0)

    local shieldTex = shieldFrame:CreateTexture(nil, "ARTWORK")
    shieldTex:SetAllPoints()
    local ok = pcall(function()
        shieldTex:SetAtlas(atlas, false)
    end)
    if not ok then
        shieldFrame:Hide()
        return nil, 0
    end
    shieldTex:SetSnapToPixelGrid(false)
    shieldTex:SetTexelSnappingBias(0)

    if hasPoints then
        local ptsFs = FontManager:CreateFontString(shieldFrame, "body", "OVERLAY")
        ptsFs:SetPoint("CENTER", shieldTex, "CENTER", 0, 0)
        ptsFs:SetJustifyH("CENTER")
        ptsFs:SetJustifyV("MIDDLE")
        ptsFs:SetText(tostring(numPts))
        ptsFs:SetTextColor(1, 1, 1)
        NM_ApplyTextShadow(ptsFs, 1)
    end

    shieldFrame:SetFrameLevel((iconSlotCompact.GetFrameLevel and iconSlotCompact:GetFrameLevel() or 2) + 4)

    return shieldFrame, ACHIEVEMENT_SHIELD_SIZE + ACHIEVEMENT_SHIELD_GAP
end

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
    local w = f:GetWidth() or ALERT_WIDTH_FIXED
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
    if isCompact and (config.progressAnchor == true or config.planReminderToast) then
        return "criteria"
    end
    if isCompact and hasCrit and not config.categoryTitle then
        return "criteria"
    end
    if config.notifType == "tryCounter" or config.toastLane == "tryCounter" then
        return "tryCounter"
    end
    if config.notifType == "criteria" then
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

local function UsesUnifiedToastLayout()
    local db = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    return db == nil or db.unifiedToastLayout ~= false
end

---Progress lane (criteria, vault, reminders) uses Blizzard CriteriaAlertFrame width when available.
local function GetCompactToastWidth(laneUsesProgressSizing)
    if laneUsesProgressSizing then
        local blizzW = GetBlizzardProgressAlertToastWidth()
        if blizzW and blizzW >= 160 and blizzW <= ALERT_WIDTH_COMPACT then
            return math.min(blizzW, 300)
        end
        return ALERT_WIDTH_PROGRESS
    end
    return ALERT_WIDTH_COMPACT
end

local function GetCompactToastBaseHeight(_laneUsesProgressSizing)
    return ALERT_HEIGHT_COMPACT
end

local function GetStackMaxToastWidth(alertList)
    local maxW = ALERT_WIDTH_PROGRESS
    for i = 1, #alertList do
        local w = alertList[i]._toastWidth
        if type(w) == "number" and w > maxW then
            maxW = w
        end
    end
    return maxW
end

---Narrow progress lane stays screen-centered; wide collection toasts left-align in a mixed stack.
local function GetStackAdjustedAnchorX(point, baseX, toastWidth, stackMaxWidth, toastLane)
    if not UsesUnifiedToastLayout() then
        return baseX
    end
    if toastLane == "criteria" or toastLane == "reminder" then
        return baseX
    end
    if toastWidth and toastWidth <= ALERT_WIDTH_PROGRESS + 4 then
        return baseX
    end
    if not stackMaxWidth or not toastWidth or stackMaxWidth <= toastWidth then
        return baseX
    end
    local halfDelta = (toastWidth - stackMaxWidth) * 0.5
    if point == "TOP" or point == "BOTTOM" or point == "CENTER" then
        return baseX + halfDelta
    elseif point == "TOPRIGHT" or point == "BOTTOMRIGHT" or point == "RIGHT" then
        return baseX - halfDelta
    end
    return baseX
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

local function HasAnyClosingAlert()
    local alerts = WarbandNexus and WarbandNexus.activeAlerts
    if not alerts then return false end
    for i = 1, #alerts do
        if alerts[i].isClosing then
            return true
        end
    end
    return false
end

local function StopStackRepositionWatch()
    if stackRepositionWatchTicker then
        stackRepositionWatchTicker:Cancel()
        stackRepositionWatchTicker = nil
    end
end

local RepositionAlerts

local function RunStackRepositionIfIdle()
    if HasAnyClosingAlert() then
        return false
    end
    StopStackRepositionWatch()
    if WarbandNexus and WarbandNexus.activeAlerts and #WarbandNexus.activeAlerts > 0 then
        RepositionAlerts()
    end
    return true
end

---Wait until no toast is mid-fade before sliding the stack (avoids overlap when several dismiss together).
local function RequestStackReposition()
    C_Timer.After(0.02, function()
        if RunStackRepositionIfIdle() then
            return
        end
        if not stackRepositionWatchTicker then
            stackRepositionWatchTicker = C_Timer.NewTicker(0.05, function()
                RunStackRepositionIfIdle()
            end)
        end
    end)
end

---Reposition all active alerts (when one closes, others fill the gap). Alerts with same anchor stack together; slot Y uses each alert's actual height so full and compact never overlap.
RepositionAlerts = function(instant, force)
    if not force and not instant and (HasAnyClosingAlert() or dismissSessionActive) then
        return
    end
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
        local stackMaxW = GetStackMaxToastWidth(list)
        local cumulativeOffset = 0
        for slotInGroup, alert in ipairs(list) do
            local newYOffset = by + (cumulativeOffset * -direction)
            cumulativeOffset = cumulativeOffset + GetAlertHeight(alert) + ALERT_GAP
            local ax = GetStackAdjustedAnchorX(pt, bx, alert._toastWidth or ALERT_WIDTH_COMPACT, stackMaxW, alert._toastLane)
            alert._anchorX = ax
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
                    local cy = alert.currentYOffset or alert._entranceTargetY or newYOffset
                    alert:ClearAllPoints()
                    alert:SetPoint(pt, UIParent, pt, ax, cy)
                elseif instant then
                    alert:ClearAllPoints()
                    alert:SetPoint(pt, UIParent, pt, ax, newYOffset)
                    alert.currentYOffset = newYOffset
                    alert._lastAnchorX = ax
                elseif alert.currentYOffset ~= newYOffset or alert._lastAnchorX ~= ax then
                    local repositionStart = GetTime()
                    local repositionDuration = TOAST_REPOSITION_SEC
                    local startY = alert.currentYOffset or newYOffset
                    local moveDistance = newYOffset - startY
                    local _point, _anchorX = pt, ax
                    alert._lastAnchorX = ax
                    alert.isAnimating = true
                    alert:SetScript("OnUpdate", function(self, elapsed)
                        local elapsedTime = GetTime() - repositionStart
                        local progress = math.min(1, elapsedTime / repositionDuration)
                        local easedProgress = progress < 0.5 and (2 * progress * progress) or (1 - math.pow(-2 * progress + 2, 2) / 2)
                        local currentY = startY + (moveDistance * easedProgress)
                        self:ClearAllPoints()
                        self:SetPoint(_point, UIParent, _point, _anchorX, currentY)
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

local function GetAlertStackKey(alert)
    if not alert then return nil end
    local pt = alert._anchorPoint
    local bx = alert._baseX
    local by = alert._baseY
    if not pt or bx == nil or by == nil then return nil end
    return pt .. "|" .. tostring(bx) .. "|" .. tostring(by)
end

local function EnqueueDismissToast(toast)
    if not toast then return end
    for i = dismissQueueHead, #dismissQueue do
        if dismissQueue[i] == toast then
            return
        end
    end
    dismissQueue[#dismissQueue + 1] = toast
end

local function DequeueDismissToast()
    if dismissQueueHead > #dismissQueue then
        dismissQueue = {}
        dismissQueueHead = 1
        return nil
    end
    local toast = dismissQueue[dismissQueueHead]
    dismissQueueHead = dismissQueueHead + 1
    return toast
end

local function PauseStackDismissTimers(stackKey, exceptToast)
    if not stackKey then return end
    local alerts = WarbandNexus and WarbandNexus.activeAlerts
    if not alerts then return end
    for i = 1, #alerts do
        local alert = alerts[i]
        if alert ~= exceptToast and GetAlertStackKey(alert) == stackKey and not alert.isClosing and not alert._removed then
            if alert.dismissTimer then
                if alert._dismissDeadline then
                    alert._dismissPausedRemaining = math.max(0, alert._dismissDeadline - GetTime())
                end
                alert.dismissTimer:Cancel()
                alert.dismissTimer = nil
                alert._dismissTimerPaused = true
            end
        end
    end
end

local function ResumeStackDismissTimers(stackKey)
    if not stackKey then return end
    local alerts = WarbandNexus and WarbandNexus.activeAlerts
    if not alerts then return end
    for i = 1, #alerts do
        local alert = alerts[i]
        if GetAlertStackKey(alert) == stackKey and alert._dismissTimerPaused and not alert.isClosing and not alert._removed then
            local delay = alert._dismissPausedRemaining
            if type(delay) ~= "number" or delay <= 0 then
                delay = 0.05
            end
            alert._dismissTimerPaused = nil
            alert._dismissPausedRemaining = nil
            alert._dismissDeadline = GetTime() + delay
            alert.dismissTimer = C_Timer.NewTimer(delay, function()
                alert.dismissTimer = nil
                alert._dismissDeadline = nil
                if not alert:IsShown() or alert.isClosing or alert._removed then return end
                RequestDismissToast(alert)
            end)
        end
    end
end

local function ScheduleToastDismiss(toast, delay)
    if not toast then return end
    delay = tonumber(delay)
    if not delay or delay <= 0 then return end
    if toast.dismissTimer then
        toast.dismissTimer:Cancel()
        toast.dismissTimer = nil
    end
    toast._dismissTimerPaused = nil
    toast._dismissPausedRemaining = nil
    toast._dismissDeadline = GetTime() + delay
    toast.dismissTimer = C_Timer.NewTimer(delay, function()
        toast.dismissTimer = nil
        toast._dismissDeadline = nil
        if not toast:IsShown() or toast.isClosing or toast._removed then return end
        RequestDismissToast(toast)
    end)
end

local function ProcessDismissQueue()
    if HasAnyClosingAlert() then return end
    local nextToast = DequeueDismissToast()
    if not nextToast or nextToast._removed or nextToast.isClosing then
        return
    end
    dismissSessionActive = true
    PauseStackDismissTimers(GetAlertStackKey(nextToast), nextToast)
    BeginDismissToast(nextToast)
end

local function FinishDismissStep(removedToast)
    local stackKey = removedToast and GetAlertStackKey(removedToast)

    local function continueAfterCollapse()
        if HasAnyClosingAlert() then
            return
        end
        if dismissQueueHead <= #dismissQueue then
            ProcessDismissQueue()
            return
        end
        dismissSessionActive = false
        StopStackRepositionWatch()
        if stackKey then
            ResumeStackDismissTimers(stackKey)
        end
    end

    local alerts = WarbandNexus and WarbandNexus.activeAlerts
    if alerts and #alerts > 0 then
        C_Timer.After(0.02, function()
            if HasAnyClosingAlert() then return end
            RepositionAlerts(false, true)
            C_Timer.After(TOAST_REPOSITION_SEC + 0.02, continueAfterCollapse)
        end)
    else
        continueAfterCollapse()
    end
end

---Fade out in place; stack collapse waits until every fading toast in the stack has been removed.
BeginDismissToast = function(toast)
    if not toast or toast.isClosing or toast._removed then return end
    toast.isClosing = true
    toast.isEntering = false
    toast.isAnimating = false
    if toast.dismissTimer then
        toast.dismissTimer:Cancel()
        toast.dismissTimer = nil
    end
    if toast.EnableMouse then
        toast:EnableMouse(false)
    end
    if toast.SetFrameLevel and toast.GetFrameLevel then
        toast:SetFrameLevel(math.max(1, toast:GetFrameLevel() - 100))
    end
    local t0 = GetTime()
    toast:SetScript("OnUpdate", function(self, elapsed)
        local p = math.min(1, (GetTime() - t0) / TOAST_FADE_OUT_SEC)
        self:SetAlpha(math.max(0, 1 - p))
        if p >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(0)
            C_Timer.After(TOAST_COLLAPSE_DELAY_SEC, function()
                if self and not self._removed then
                    RemoveAlert(self)
                end
            end)
        end
    end)
end

RequestDismissToast = function(toast)
    if not toast or toast.isClosing or toast._removed then return end
    if toast.dismissTimer then
        toast.dismissTimer:Cancel()
        toast.dismissTimer = nil
    end
    toast._dismissTimerPaused = nil
    toast._dismissPausedRemaining = nil
    toast._dismissDeadline = nil

    if HasAnyClosingAlert() then
        EnqueueDismissToast(toast)
        return
    end

    dismissSessionActive = true
    PauseStackDismissTimers(GetAlertStackKey(toast), toast)
    BeginDismissToast(toast)
end

---Remove alert and process queue
RemoveAlert = function(alert)
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
    
    -- One toast gone: slide stack, then resume paused timers / next queued dismiss.
    FinishDismissStep(alert)
    
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
        return false
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
    local categoryTitleStr = config.categoryTitle
    local headerTitleStr = criteriaTitleStr or categoryTitleStr
    local isCriteriaPopup = (config.progressAnchor == true)
        or (type(criteriaTitleStr) == "string" and criteriaTitleStr ~= "" and not categoryTitleStr)
    local useProgressSlot = isPlanReminderToast or isCriteriaPopup
    local useReminderSlot = isPlanReminderToast
    if config.notifType and not config.titleColor then
        local chrome = ToastChrome.Resolve(config.notifType)
        config.titleColor = chrome.accent
        if not categoryTitleStr and not criteriaTitleStr and chrome.categoryLabel then
            config.categoryTitle = chrome.categoryLabel
            categoryTitleStr = chrome.categoryLabel
            headerTitleStr = chrome.categoryLabel
        end
        if config.progressGlow == nil then
            config.progressGlow = false
        end
    end
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

        local COMPACT_HEIGHT = GetCompactToastBaseHeight(laneUsesProgressSizing)
        local popupWidthCompact = GetCompactToastWidth(laneUsesProgressSizing)
        local ICON_SLOT_WIDTH_COMPACT = ALERT_ICON_SLOT
        local iconSizeCompact = ALERT_ICON_SIZE
        local laneIconLeadingPad = ALERT_PAD_LEFT
        local hideCompactIcon = config.criteriaNoIcon == true
        local iconLaneWidth = hideCompactIcon and 0 or ICON_SLOT_WIDTH_COMPACT
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
        ToastChrome.ApplyCompactBackdropChrome(backdropFrameCompact, titleColor, 0.38)
        
        -- Layer 2: icon slot (icon + bling only); criteria lane may omit icon entirely.
        local iconSlotCompact = CreateFrame("Frame", nil, compactPopup)
        iconSlotCompact:SetFrameLevel(2)
        iconSlotCompact:SetSize(iconLaneWidth, COMPACT_HEIGHT)
        if not hideCompactIcon then
            iconSlotCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad, 0)
        else
            iconSlotCompact:Hide()
        end

        local iconCompact
        local achievementShieldExtra = 0
        local isAchievementEarnedToast = config.notifType == "achievement"
        if not hideCompactIcon then
        iconCompact = iconSlotCompact:CreateTexture(nil, "ARTWORK")
        iconCompact:SetSize(iconSizeCompact, iconSizeCompact)
        if isAchievementEarnedToast then
            iconCompact:SetPoint("LEFT", iconSlotCompact, "LEFT", 4, 0)
        else
            iconCompact:SetPoint("CENTER", iconSlotCompact, "CENTER", 0, 0)
        end
        -- Use resolved atlas/fileID locals (IsAtlasName promotes config.icon â†’ iconAtlas; compact must not read config.iconAtlas only).
        if iconAtlas and iconAtlas ~= "" then
            iconCompact:SetAtlas(iconAtlas)
        else
            iconCompact:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if type(iconTexture) == "number" then
                iconCompact:SetTexture(iconTexture)
            elseif iconTexture and iconTexture ~= "" then
                iconCompact:SetTexture(iconTexture:gsub("\\", "/"))
            else
                iconCompact:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
            end
        end
        iconCompact:SetVertexColor(1, 1, 1, 1)
        iconCompact:SetAlpha(1)
        if isAchievementEarnedToast then
            local iconBling = iconSlotCompact:CreateTexture(nil, "OVERLAY", nil, 3)
            iconBling:SetSize(iconSizeCompact + 14, iconSizeCompact + 14)
            iconBling:SetPoint("CENTER", iconCompact, "CENTER", 0, 0)
            iconBling:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
            iconBling:SetTexCoord(0, 0.5625, 0, 0.5625)
            iconBling:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
            iconBling:SetBlendMode("BLEND")
        end
        ToastChrome.ApplyCompactIconBorder(iconSlotCompact, iconCompact, iconSizeCompact, titleColor)
        if isAchievementEarnedToast then
            local achPts = NM_ResolveAchievementToastPoints(config)
            local _, extraW = NM_AttachAchievementPointsShield(iconSlotCompact, iconCompact, achPts)
            achievementShieldExtra = extraW or 0
            if achievementShieldExtra > 0 then
                iconSlotCompact:SetWidth(iconLaneWidth + achievementShieldExtra)
            end
        end
        end
        
        -- Content frame (right): text only
        local contentFrameCompact = CreateFrame("Frame", nil, compactPopup)
        contentFrameCompact:SetFrameLevel(2)
        contentFrameCompact:SetPoint("TOP", compactPopup, "TOP", 0, 0)
        contentFrameCompact:SetPoint("BOTTOM", compactPopup, "BOTTOM", 0, 0)
        contentFrameCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad + iconLaneWidth + achievementShieldExtra, 0)
        contentFrameCompact:SetPoint("RIGHT", compactPopup, "RIGHT", -ALERT_PAD_RIGHT, 0)
        
        -- Compact: accent lives on the icon flipbook frame only (no card-wide TopBottom streaks).
        -- Card layout: title (large) on top, category/description (small) below; progress lane text centered.
        local headerTitle = headerTitleStr
        if type(headerTitle) == "string" and issecretvalue and issecretvalue(headerTitle) then headerTitle = nil end
        local progressStr = (messageText or actionText or "")
        if type(progressStr) == "string" and issecretvalue and issecretvalue(progressStr) then progressStr = "" end
        local nameStr = (itemName or "")
        if type(nameStr) == "string" and issecretvalue and issecretvalue(nameStr) then nameStr = "" end
        local detailStr = actionText or ""
        if type(detailStr) == "string" and issecretvalue and issecretvalue(detailStr) then detailStr = "" end
        local tryCountStr = ""
        if type(config.tryCount) == "number" and config.tryCount > 0 then
            tryCountStr = FormatToastAttemptsLabel(config.tryCount) or ""
        elseif config.tryCountText and config.tryCountText ~= "" then
            tryCountStr = config.tryCountText
        end
        if type(tryCountStr) == "string" and issecretvalue and issecretvalue(tryCountStr) then tryCountStr = "" end
        if config.notifType == "tryCounter" and tryCountStr == "" and detailStr ~= "" then
            tryCountStr = detailStr
            detailStr = ""
        end
        local isTryCounterToast = config.notifType == "tryCounter"
        if isTryCounterToast and tryCountStr ~= "" then
            headerTitle = tryCountStr
            tryCountStr = ""
        end
        if config.notifType == "achievement" then
            detailStr = ""
        end
        local headerSafe = headerTitle
        if type(headerSafe) == "string" and issecretvalue and issecretvalue(headerSafe) then headerSafe = nil end
        local titleHex = ToastChrome.TitleHex(titleColor)
        local categoryHex = ToastChrome.CategoryHex(titleColor)
        local useTwoLineCard = headerSafe and headerSafe ~= ""
        local titleLine, headerLine
        local textGroup = CreateFrame("Frame", nil, contentFrameCompact)
        textGroup:SetFrameLevel(1)
        textGroup:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", 0, 0)
        textGroup:SetPoint("BOTTOMRIGHT", contentFrameCompact, "BOTTOMRIGHT", 0, 0)

        titleLine = FontManager:CreateFontString(textGroup, "title", "OVERLAY")
        titleLine:SetJustifyH("LEFT")
        titleLine:SetWordWrap(true)
        titleLine:SetMaxLines(2)
        titleLine:SetText(titleHex .. (nameStr or "") .. "|r")
        titleLine:SetShadowOffset(1, -1)
        NM_ApplyTextShadow(titleLine, 0.85)

        if useTwoLineCard then
            headerLine = FontManager:CreateFontString(textGroup, "small", "OVERLAY")
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWordWrap(false)
            headerLine:SetMaxLines(1)
            if isTryCounterToast then
                headerLine:SetText(NM_ThemeTextHex("Bright") .. (headerSafe or "") .. "|r")
                headerLine:SetShadowOffset(1, -1)
                NM_ApplyTextShadow(headerLine, 0.85)
            else
                headerLine:SetText(categoryHex .. (headerSafe or "") .. "|r")
                headerLine:SetShadowOffset(1, -1)
                NM_ApplyTextShadow(headerLine, 0.8)
            end
        else
            headerLine = FontManager:CreateFontString(textGroup, "small", "OVERLAY")
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWordWrap(true)
            headerLine:SetMaxLines(2)
            headerLine:SetText(NM_ThemeTextHex("Normal") .. progressStr .. "|r")
            headerLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(headerLine, 0.6)
        end

        local textUseW = math.max(48, popupWidthCompact - laneIconLeadingPad - iconLaneWidth - achievementShieldExtra - ALERT_PAD_RIGHT - ALERT_PAD_TEXT * 2)
        titleLine:SetWidth(textUseW)
        headerLine:SetWidth(textUseW)

        local tryCountLine = nil
        local detailLine = nil

        if useTwoLineCard and detailStr ~= "" and detailStr ~= (ACTION_TEXT[config.notifType] or "") then
            detailLine = FontManager:CreateFontString(textGroup, "small", "OVERLAY")
            detailLine:SetWidth(textUseW)
            detailLine:SetJustifyH("LEFT")
            detailLine:SetWordWrap(false)
            detailLine:SetMaxLines(1)
            detailLine:SetText(NM_ThemeTextHex("Muted") .. detailStr .. "|r")
            detailLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(detailLine, 0.6)
        end

        local gapTitle = 2
        local hTitle = titleLine:GetStringHeight()
        local hHeader = headerLine:GetStringHeight()
        local titleWraps = hTitle > ((FontManager.GetFontSize and FontManager:GetFontSize("title")) or 14) + 4
        local hDetail = detailLine and detailLine:GetStringHeight() or 0
        local stackH = hTitle + gapTitle + hHeader + (detailLine and (gapTitle + hDetail) or 0)
        local newH = (titleWraps or detailLine) and ALERT_HEIGHT_TALL or ALERT_HEIGHT_COMPACT
        newH = math.max(ALERT_HEIGHT_COMPACT, math.min(ALERT_HEIGHT_TALL, math.ceil(stackH + 10)))

        compactPopup:SetHeight(newH)
        iconSlotCompact:SetHeight(newH)
        contentFrameCompact:SetHeight(newH)
        compactPopup._alertHeight = newH

        local padTop = math.floor((newH - stackH) * 0.5 + 0.5)
        titleLine:ClearAllPoints()
        headerLine:ClearAllPoints()
        titleLine:SetPoint("TOPLEFT", textGroup, "TOPLEFT", ALERT_PAD_TEXT, -padTop)
        headerLine:SetPoint("TOPLEFT", titleLine, "BOTTOMLEFT", 0, -gapTitle)
        if detailLine then
            detailLine:ClearAllPoints()
            detailLine:SetPoint("TOPLEFT", headerLine, "BOTTOMLEFT", 0, -gapTitle)
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
            if button == "LeftButton" and self.achievementID and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, self.achievementID)
            end
            RequestDismissToast(self)
        end)
        
        local compactDuration = config.autoDismiss or 3
        compactPopup._toastWidth = popupWidthCompact
        compactPopup:SetMouseClickEnabled(true)
        compactPopup:SetAlpha(0)
        compactPopup:SetPoint(point, UIParent, point, baseX, yOffset + 50 * -direction)
        compactPopup._entranceStartY = yOffset + 50 * -direction
        compactPopup._entranceTargetY = yOffset
        compactPopup._entranceStartTime = GetTime()
        compactPopup._anchorPoint = point
        compactPopup._baseX = baseX
        compactPopup._baseY = baseY
        compactPopup._direction = direction
        local _pt = point

        table.insert(self.activeAlerts, compactPopup)
        compactPopup.isEntering = true
        RepositionAlerts(true)
        local _bx = compactPopup._anchorX or baseX
        NM_AssignToastFxMetadata(compactPopup, config, titleColor, iconCompact, backdropFrameCompact)
        compactPopup:Show()
        NM_TriggerToastEntranceEffects(compactPopup, popupWidthCompact, compactPopup:GetHeight() or COMPACT_HEIGHT)
        compactPopup:SetScript("OnUpdate", function(self, elapsed)
            local prog = math.min(1, (GetTime() - (self._entranceStartTime or 0)) / TOAST_ENTRANCE_SEC)
            local ease = 1 - math.pow(1 - prog, 2)
            local cy = (self._entranceStartY or 0) + ((self._entranceTargetY or 0) - (self._entranceStartY or 0)) * ease
            self:SetAlpha(math.min(1, self:GetAlpha() + elapsed * 4))
            self:ClearAllPoints()
            self:SetPoint(_pt, UIParent, _pt, self._anchorX or _bx, cy)
            self.currentYOffset = cy
            if prog >= 1 then
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(1)
                self.currentYOffset = self._entranceTargetY
                self.isEntering = false
                NM_EnsureToastEntranceEffects(self)
            end
        end)

        ScheduleToastDismiss(compactPopup, compactDuration)
        MaybeScheduleTryCounterCelebration(config, compactPopup)
        return true
    end
    
    -- Full achievement popup: fixed width; long titles/subtitles wrap inside the text area
    local popupWidthFull = ALERT_WIDTH_FIXED
    
    -- WoW Achievement-style: container = icon slot (left) + content frame (text).
    local ICON_SLOT_WIDTH = 54
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
    
    local iconSize = 38
    local icon = iconSlot:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", iconSlot, "LEFT", 10, 0)
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
    iconBling:SetSize(52, 52)
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
    local smallFontHeight = 12
    local mediumFontHeight = 13
    local largeFontHeight = 15
    local lineSpacing = 3
    
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
    
    -- Vertical: text block centered in the toast panel (more negative = nudge block down).
    local textVerticalBias = -7
    local startY = (totalHeight / 2) + textVerticalBias
    
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
        if button == "LeftButton" and self.achievementID and not InCombatLockdown() then
            local achID = self.achievementID
            if OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, achID)
            end
        end
        RequestDismissToast(self)
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
    NM_AssignToastFxMetadata(popup, config, titleColor, icon, backdropFrame)
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

    ScheduleToastDismiss(popup, autoDismissDelay)
    MaybeScheduleTryCounterCelebration(config, popup)
    return true
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

local function ScheduleAlertSuppressionRetries(addon)
    if not addon or not addon.ApplyBlizzardAchievementAlertSuppression then return end
    local delays = { 0.5, 2.0, 5.0 }
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if addon.ApplyBlizzardAchievementAlertSuppression then
                addon:ApplyBlizzardAchievementAlertSuppression()
            end
        end)
    end
end

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
    
    -- Suppress Blizzard achievement/criteria popups when Warband achievement popups are ON
    self:ApplyBlizzardAchievementAlertSuppression()
    C_Timer.After(0, function()
        if WarbandNexus and WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
            WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
            ScheduleAlertSuppressionRetries(WarbandNexus)
        end
    end)
    -- AceEvent: callback is (eventName, ...wowArgs); ADDON_LOADED's sole payload is the loaded addon name.
    self:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if IsAlertSourceAddOn(loadedAddon) then
            if self.ApplyBlizzardAchievementAlertSuppression then
                self:ApplyBlizzardAchievementAlertSuppression()
                ScheduleAlertSuppressionRetries(self)
            end
        end
    end)
    self:RegisterEvent("PLAYER_LOGIN", function()
        if self.ApplyBlizzardAchievementAlertSuppression then
            self:ApplyBlizzardAchievementAlertSuppression()
        end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0, function()
            if WarbandNexus and WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                ScheduleAlertSuppressionRetries(WarbandNexus)
            end
        end)
    end)
    self:RegisterEvent("CRITERIA_EARNED", "OnCriteriaEarned")
end

---Shorten Blizzard's long criteria description to a display name (e.g. "Player Has Opened all X" -> "X").
local function ShortenCriteriaDisplayName(criteriaString)
    if not criteriaString or criteriaString == "" then return (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
    if issecretvalue and issecretvalue(criteriaString) then return (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
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
    return NP.GetNotificationsDb()
end

---Central toast gate: master enabled + per-channel toggles.
---@param channel string "achievement"|"loot"|"plan"|"vault"|"quest"|"reminder"
---@param lootType string|nil mount/pet/toy/... when channel is loot
---@return boolean
function WarbandNexus:CanShowToast(channel, lootType)
    local db = GetNotificationProfileDb()
    if not db or not db.enabled then return false end
    if channel == "achievement" then
        return NP.CanShowWarbandAchievementEarnedToast()
    elseif channel == "loot" then
        if not db.showLootNotifications then return false end
        if lootType then
            local typeToggleMap = {
                mount = "showMountNotifications",
                pet = "showPetNotifications",
                toy = "showToyNotifications",
                illusion = "showIllusionNotifications",
                title = "showTitleNotifications",
            }
            local toggleKey = typeToggleMap[lootType]
            if toggleKey and db[toggleKey] == false then return false end
        end
        return true
    elseif channel == "plan" or channel == "quest" then
        return true
    elseif channel == "vault" then
        return db.showVaultReminder ~= false
    elseif channel == "reminder" then
        return db.showPlanReminderToast ~= false
    end
    return true
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

---Criteria index or display string from AddAlert / CRITERIA_EARNED (table payloads included).
local function ResolveAchievementAlertCriteria(a1, a2, ...)
    if type(a1) == "table" then
        local s = a1.criteriaString or a1.description or a1.text or a1.name
        if type(s) == "string" and s ~= "" and not (issecretvalue and issecretvalue(s)) then
            return s
        end
        local idx = a1.criteriaIndex or a1.index
        if type(idx) == "number" then return idx end
    end
    if type(a2) == "string" and a2 ~= "" then
        if issecretvalue and issecretvalue(a2) then return nil end
        return a2
    end
    if type(a2) == "number" then return a2 end
    if type(a2) == "table" then
        local s = a2.criteriaString or a2.description or a2.text or a2.name
        if type(s) == "string" and s ~= "" and not (issecretvalue and issecretvalue(s)) then
            return s
        end
        local idx = a2.criteriaIndex or a2.index
        if type(idx) == "number" then return idx end
    end
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v)) then
            return v
        end
    end
    return nil
end

---ProgressAlertSystem payloads (Traveler's Log, etc.) — no achievementID required.
local function ResolveProgressAlertPayload(a1, a2, ...)
    local function safeStr(v)
        if type(v) ~= "string" or v == "" then return nil end
        if issecretvalue and issecretvalue(v) then return nil end
        return v
    end

    local function fromTable(t)
        if type(t) ~= "table" then return nil end
        local nested = t.progressAlertInfo or t.alertInfo or t.info
        if type(nested) == "table" then
            local nestedPayload = fromTable(nested)
            if nestedPayload then return nestedPayload end
        end
        return {
            title = safeStr(t.title) or safeStr(t.label) or safeStr(t.header) or safeStr(t.categoryTitle)
                or safeStr(t.headerText) or safeStr(t.topLine) or safeStr(t.activityTitle) or safeStr(t.parentTitle),
            text = safeStr(t.text) or safeStr(t.description) or safeStr(t.name) or safeStr(t.subtitle)
                or safeStr(t.criteriaString) or safeStr(t.body) or safeStr(t.bodyText) or safeStr(t.message)
                or safeStr(t.criteriaText) or safeStr(t.objectiveText) or safeStr(t.taskName)
                or safeStr(t.activityName) or safeStr(t.activityDescription),
            icon = t.icon,
            iconAtlas = safeStr(t.iconAtlas) or safeStr(t.atlas) or safeStr(t.textureAtlas),
            iconFileID = (type(t.iconFileID) == "number" and t.iconFileID)
                or (type(t.fileID) == "number" and t.fileID) or nil,
        }
    end

    if type(a1) == "table" then
        return fromTable(a1)
    end
    local title = safeStr(a1)
    local text = safeStr(a2)
    if title or text then
        return { title = title, text = text }
    end
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "table" then
            return fromTable(v)
        end
    end
    return nil
end

local function NormalizeProgressAlertPayload(payload)
    if not payload then return nil end
    local title = payload.title
    local text = payload.text
    if (not text or text == "") and title and title ~= "" then
        text = title
        title = nil
    end
    if not text or text == "" then return nil end
    if not title or title == "" then
        title = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"
    end
    payload.title = title
    payload.text = text
    return payload
end

---Deduped generic progress toast (Traveler's Log / ProgressAlertSystem lane).
local function TryDispatchProgressAlertToast(payload)
    if not NP.UseWarbandCriteriaProgressPopups() then return false end
    payload = NormalizeProgressAlertPayload(payload)
    if not payload then return false end

    local key = "prog|" .. tostring(payload.title) .. "|" .. tostring(payload.text)
    local now = GetTime()
    if lastProgressAlertEmitKey == key and lastProgressAlertEmitTime
        and (now - lastProgressAlertEmitTime) < 0.45 then
        return true
    end

    local shown = WarbandNexus and WarbandNexus.ShowGenericProgressNotification
        and WarbandNexus:ShowGenericProgressNotification(payload)
    if shown then
        lastProgressAlertEmitKey = key
        lastProgressAlertEmitTime = now
        return true
    end
    return false
end

---Resolve criteria row for AddAlert / CRITERIA_EARNED hint (name or index).
---@return table|nil { index, criteriaType, linkedAchievementID, linkedIcon }
local function NM_FindCriteriaRowForHint(achievementID, criteriaHint)
    if not achievementID or type(achievementID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(achievementID) then return nil end
    local numCriteria = GetAchievementNumCriteria(achievementID)
    if not numCriteria or numCriteria < 1 then return nil end

    local criteriaIndex = nil
    if type(criteriaHint) == "number" then
        criteriaIndex = criteriaHint
    elseif type(criteriaHint) == "string" and criteriaHint ~= "" then
        if issecretvalue and issecretvalue(criteriaHint) then return nil end
        for i = 1, numCriteria do
            local name = GetAchievementCriteriaInfo(achievementID, i)
            if name and not (issecretvalue and issecretvalue(name)) and name == criteriaHint then
                criteriaIndex = i
                break
            end
        end
    end
    if not criteriaIndex or criteriaIndex < 1 or criteriaIndex > numCriteria then
        return nil
    end

    local ok, _, criteriaType, _, _, _, _, assetID = pcall(GetAchievementCriteriaInfo, achievementID, criteriaIndex)
    if not ok then return nil end

    local linkedID = nil
    local ct = tonumber(criteriaType)
    if ct == ACHIEVEMENT_CRITERIA_TYPE_LINKED and assetID then
        local n = tonumber(assetID)
        if n and n > 0 and not (issecretvalue and issecretvalue(assetID)) then
            linkedID = n
        end
    end

    local linkedIcon = nil
    if linkedID then
        local okInfo, _, _, _, _, _, _, _, _, icon = pcall(GetAchievementInfo, linkedID)
        if okInfo and icon and not (issecretvalue and issecretvalue(icon)) then
            linkedIcon = icon
        end
    end

    return {
        index = criteriaIndex,
        criteriaType = ct,
        linkedAchievementID = linkedID,
        linkedIcon = linkedIcon,
    }
end

---Main earned (no hint), sub-achievement row (criteriaType 8), or plain criteria progress.
---@return string route "earned"|"criteria"
---@return number routeAchievementID id for earned toast or parent id for criteria toast
local function NM_ResolveAchievementAlertRoute(achievementID, criteriaHint)
    if criteriaHint == nil then
        return "earned", achievementID
    end
    local row = NM_FindCriteriaRowForHint(achievementID, criteriaHint)
    if row and row.linkedAchievementID then
        return "earned", row.linkedAchievementID
    end
    return "criteria", achievementID
end

---Deduped criteria progress toast; returns true when WN handled (or duplicate suppressed).
local function TryDispatchCriteriaProgressToast(achievementID, criteriaIndex)
    if not NP.UseWarbandCriteriaProgressPopups() then return false end
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

---When WN criteria lane is active, never fall back to Blizzard criteria/progress alert frames.
local function FinishCriteriaProgressAddAlert(orig, sys, origA1, origA2, achievementID, criteriaHint, rest)
    if TryDispatchCriteriaProgressToast(achievementID, criteriaHint) then
        return
    end
    if NP.UseWarbandCriteriaProgressPopups() then
        return
    end
    pcall(orig, sys, origA1, origA2, unpack(rest))
end

---Wiki: CRITERIA_EARNED achievementID, description, achievementAlreadyEarnedOnAccount
function WarbandNexus:OnCriteriaEarned(_, achievementID, description, achievementAlreadyEarnedOnAccount)
    if not NP.UseWarbandAchievementPopups() and not NP.UseWarbandCriteriaProgressPopups() then return end
    if not achievementID or type(achievementID) ~= "number" then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    if achievementAlreadyEarnedOnAccount then return end
    if description and issecretvalue and issecretvalue(description) then
        description = nil
    end
    C_Timer.After(0, function()
        local route, routeID = NM_ResolveAchievementAlertRoute(achievementID, description)
        if route == "earned" then
            if NP.UseWarbandAchievementPopups()
                and WarbandNexus and WarbandNexus.ShowAchievementNotification then
                WarbandNexus:ShowAchievementNotification(routeID)
            end
            return
        end
        if not NP.UseWarbandCriteriaProgressPopups() then return end
        TryDispatchCriteriaProgressToast(achievementID, description)
    end)
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

--- Midnight may omit _G.ProgressAlertSystem; try known globals after alert addons load.
local PROGRESS_ALERT_SYSTEM_GLOBALS = {
    "ProgressAlertSystem",
    "MonthlyActivitiesAlertSystem",
    "PerksActivitiesAlertSystem",
}

local function FindProgressAlertSystem()
    for i = 1, #PROGRESS_ALERT_SYSTEM_GLOBALS do
        local sys = _G[PROGRESS_ALERT_SYSTEM_GLOBALS[i]]
        if sys and type(sys.AddAlert) == "function" then
            return sys
        end
    end
    return nil
end

local function SafeAlertFrameText(region)
    if not region or not region.GetText then return nil end
    local ok, text = pcall(region.GetText, region)
    if not ok or type(text) ~= "string" or text == "" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    return text
end

---Scrape title/body from Blizzard progress alert frames when AddAlert hook is unavailable.
local function ScrapeProgressAlertFrameText(frame)
    if not frame then return nil, nil end
    local lines = {}
    local function collectRegion(region)
        if not region then return end
        if region.IsObjectType and region:IsObjectType("FontString") then
            local text = SafeAlertFrameText(region)
            if text then lines[#lines + 1] = text end
            return
        end
        if region.GetRegions then
            local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z =
                pcall(region.GetRegions, region)
            if ok then
                local regions = { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z }
                for ri = 1, #regions do
                    collectRegion(regions[ri])
                end
            end
        end
    end
    collectRegion(frame)
    if frame.GetChildren then
        local ok, c1, c2, c3, c4, c5, c6, c7, c8 = pcall(frame.GetChildren, frame)
        if ok then
            local children = { c1, c2, c3, c4, c5, c6, c7, c8 }
            for ci = 1, #children do
                collectRegion(children[ci])
            end
        end
    end
    local named = { "Header", "Label", "Name", "Text", "Title", "TopText", "BottomText" }
    for ni = 1, #named do
        local child = frame[named[ni]]
        if child then
            if child.IsObjectType and child:IsObjectType("FontString") then
                local text = SafeAlertFrameText(child)
                if text then lines[#lines + 1] = text end
            elseif child.GetText then
                local text = SafeAlertFrameText(child)
                if text then lines[#lines + 1] = text end
            end
        end
    end
    if #lines == 0 then return nil, nil end
    if #lines == 1 then return nil, lines[1] end
    return lines[1], lines[2]
end

local function MirrorAndSuppressProgressAlertFrame(frame)
    if not frame or not NP.UseWarbandCriteriaProgressPopups() then return end
    if frame._wnProgMirrorPending then return end
    local title, text = ScrapeProgressAlertFrameText(frame)
    if title or text then
        TryDispatchProgressAlertToast({ title = title, text = text })
    else
        frame._wnProgMirrorPending = true
        C_Timer.After(0, function()
            frame._wnProgMirrorPending = nil
            if not frame.IsShown or not frame:IsShown() then return end
            local retryTitle, retryText = ScrapeProgressAlertFrameText(frame)
            if retryTitle or retryText then
                TryDispatchProgressAlertToast({ title = retryTitle, text = retryText })
            end
        end)
    end
    if frame.Hide then
        frame:Hide()
    end
end

local function FrameLooksLikeProgressAlert(frame)
    if not frame or not frame.GetName then return false end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" or name == "" then return false end
    if name:find("ProgressAlert", 1, true) then return true end
    if name:find("MonthlyActiv", 1, true) then return true end
    if name:find("PerksActiv", 1, true) then return true end
    if name:find("Traveler", 1, true) then return true end
    return false
end

local function ScanAlertFrameForProgressAlerts()
    if not NP.UseWarbandCriteriaProgressPopups() then return end
    local alertFrame = _G.AlertFrame
    if not alertFrame or not alertFrame.GetNumChildren then return end
    local ok, n = pcall(alertFrame.GetNumChildren, alertFrame)
    if not ok or not n or n < 1 then return end
    for i = 1, n do
        local child = select(i, alertFrame:GetChildren())
        if child and child.IsShown and child:IsShown() and FrameLooksLikeProgressAlert(child) then
            MirrorAndSuppressProgressAlertFrame(child)
        end
    end
end

--- Blizzard addons that may define ProgressAlertSystem / alert frames (load order varies by patch).
local ALERT_SOURCE_ADDONS = {
    "Blizzard_SharedXML",
    "Blizzard_AchievementUI",
    "Blizzard_AdventureGuide",
    "Blizzard_MonthlyActivities",
    "Blizzard_PerksActivities",
    "Blizzard_TradingPostUI",
}

local function IsAlertSourceAddOn(loadedAddon)
    if not loadedAddon or loadedAddon == "" then return false end
    for i = 1, #ALERT_SOURCE_ADDONS do
        if loadedAddon == ALERT_SOURCE_ADDONS[i] then
            return true
        end
    end
    return false
end

local function LoadAlertSourceAddOns()
    if Utilities and Utilities.SafeLoadAddOn then
        for i = 1, #ALERT_SOURCE_ADDONS do
            Utilities:SafeLoadAddOn(ALERT_SOURCE_ADDONS[i])
        end
    end
end

local function CaptureBlizzardAddAlertHandlers(addon)
    LoadAlertSourceAddOns()
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
    addon._blizzProgressAddAlertOrig = addon._blizzProgressAddAlertOrig or {}
    for i = 1, #PROGRESS_ALERT_SYSTEM_GLOBALS do
        local globalName = PROGRESS_ALERT_SYSTEM_GLOBALS[i]
        local sys = _G[globalName]
        if sys and type(sys.AddAlert) == "function" then
            local fn = sys.AddAlert
            if not IsWnAddAlertWrapper(fn) then
                addon._blizzProgressAddAlertOrig[globalName] = fn
            end
        end
    end
end

local function InstallBlizzardAlertFrameHideHooks()
    local max = _G.MAX_ACHIEVEMENT_ALERTS or 4
    for i = 1, max do
        local achF = _G["AchievementAlertFrame" .. i]
        if achF and not achF._wnAchAlertHideHooked then
            achF:HookScript("OnShow", function(self)
                if self.Hide and NP.UseWarbandAchievementPopups() then
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
                if self.Hide and NP.UseWarbandCriteriaProgressPopups() then
                    self:Hide()
                end
            end)
            critF._wnCritAlertHideHooked = true
        end
    end
    local cf = _G.CriteriaAlertFrame
    if cf and not cf._wnCritAlertHideHooked then
        cf:HookScript("OnShow", function(self)
            if self.Hide and NP.UseWarbandCriteriaProgressPopups() then
                self:Hide()
            end
        end)
        cf._wnCritAlertHideHooked = true
    end
    for i = 1, max do
        local progF = _G["ProgressAlertFrame" .. i]
        if progF and not progF._wnProgAlertHideHooked then
            progF:HookScript("OnShow", function(self)
                MirrorAndSuppressProgressAlertFrame(self)
            end)
            progF._wnProgAlertHideHooked = true
        end
    end
    local progRoot = _G.ProgressAlertFrame
    if progRoot and not progRoot._wnProgAlertHideHooked then
        progRoot:HookScript("OnShow", function(self)
            MirrorAndSuppressProgressAlertFrame(self)
        end)
        progRoot._wnProgAlertHideHooked = true
    end
    local alertFrame = _G.AlertFrame
    if alertFrame and not alertFrame._wnProgressAlertScanHooked then
        alertFrame:HookScript("OnShow", function()
            ScanAlertFrameForProgressAlerts()
        end)
        alertFrame._wnProgressAlertScanHooked = true
    end
end

local function BuildAchievementAddAlertReplacement(orig)
    return function(sys, a1, a2, ...)
        if not NP.UseWarbandAchievementPopups() then
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
        local arg1 = achievementID
        local criteriaHint = ResolveAchievementAlertCriteria(a1, a2, ...)
        local rest = { ... }
        C_Timer.After(0, function()
            if not NP.UseWarbandAchievementPopups() then
                pcall(orig, sys, origA1, origA2, unpack(rest))
                return
            end
            local route, routeID = NM_ResolveAchievementAlertRoute(arg1, criteriaHint)
            if route == "earned" then
                local shown = WarbandNexus and WarbandNexus.ShowAchievementNotification
                    and WarbandNexus:ShowAchievementNotification(routeID)
                if not shown then
                    pcall(orig, sys, origA1, origA2, unpack(rest))
                end
                return
            end
            FinishCriteriaProgressAddAlert(orig, sys, origA1, origA2, arg1, criteriaHint, rest)
        end)
    end
end

local function BuildCriteriaAddAlertReplacement(orig)
    return function(sys, a1, a2, ...)
        if not NP.UseWarbandAchievementPopups() then
            return orig(sys, a1, a2, ...)
        end
        local achievementID = ResolveAchievementAlertID(a1)
        if not achievementID then
            return orig(sys, a1, a2, ...)
        end
        local origA1, origA2 = a1, a2
        local arg1 = achievementID
        local criteriaHint = ResolveAchievementAlertCriteria(a1, a2, ...)
        local rest = { ... }
        C_Timer.After(0, function()
            if not NP.UseWarbandAchievementPopups() then
                pcall(orig, sys, origA1, origA2, unpack(rest))
                return
            end
            local route, routeID = NM_ResolveAchievementAlertRoute(arg1, criteriaHint)
            if route == "earned" then
                local shown = WarbandNexus and WarbandNexus.ShowAchievementNotification
                    and WarbandNexus:ShowAchievementNotification(routeID)
                if not shown then
                    pcall(orig, sys, origA1, origA2, unpack(rest))
                end
                return
            end
            FinishCriteriaProgressAddAlert(orig, sys, origA1, origA2, arg1, criteriaHint, rest)
        end)
    end
end

local function BuildProgressAddAlertReplacement(orig)
    return function(sys, a1, a2, ...)
        if not NP.UseWarbandCriteriaProgressPopups() then
            return orig(sys, a1, a2, ...)
        end
        local payload = NormalizeProgressAlertPayload(ResolveProgressAlertPayload(a1, a2, ...))
        if not payload then
            return orig(sys, a1, a2, ...)
        end
        TryDispatchProgressAlertToast(payload)
        -- WN criteria lane active: suppress Blizzard progress alert frames (never call orig).
    end
end

---Show toast for progressive achievements (e.g. Treasures of X, multi-step): one step completed = "Achievement Progress" title + criteria name only.
---Only when Warband achievement popups are ON and criteria progress toggle is enabled.
---@return boolean shown true when the WN criteria toast was queued
function WarbandNexus:ShowCriteriaProgressNotification(achievementID, criteriaIndex)
    if not achievementID or type(achievementID) ~= "number" then return false end
    if not NP.CanShowWarbandCriteriaProgressToast() then return false end
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

    local criteriaRow = NM_FindCriteriaRowForHint(achievementID, criteriaIndex)
    local criteriaIcon = nil
    if criteriaRow and criteriaRow.linkedAchievementID and criteriaRow.linkedIcon then
        criteriaIcon = criteriaRow.linkedIcon
    end

    local criteriaTitleText = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"

    self:ShowModalNotification({
        compact = true,
        progressAnchor = true,
        notifType = "criteria",
        criteriaNoIcon = (criteriaIcon == nil),
        criteriaTitle = criteriaTitleText,
        icon = criteriaIcon,
        itemName = criteriaName,
        action = nil,
        achievementID = achievementID,
        titleColor = ToastChrome.CriteriaAccent(),
        playSound = true,
        autoDismiss = 3,
    })
    return true
end

---Traveler's Log / ProgressAlertSystem compact toast (no achievement ID).
---@return boolean shown
function WarbandNexus:ShowGenericProgressNotification(payload)
    if not NP.CanShowWarbandCriteriaProgressToast() then return false end
    payload = NormalizeProgressAlertPayload(payload)
    if not payload then return false end

    local config = {
        compact = true,
        progressAnchor = true,
        criteriaTitle = payload.title,
        itemName = payload.text,
        titleColor = ToastChrome.CriteriaAccent(),
        playSound = true,
        autoDismiss = 3,
    }
    if payload.iconAtlas and payload.iconAtlas ~= "" then
        config.iconAtlas = payload.iconAtlas
    elseif payload.iconFileID then
        config.iconFileID = payload.iconFileID
    elseif payload.icon then
        config.icon = payload.icon
    end

    return self:ShowModalNotification(config) == true
end

---Swap or restore Blizzard AddAlert based on Warband achievement popups (live db read on each call).
function WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
    CaptureBlizzardAddAlertHandlers(self)
    local useWarbandPopups = NP.UseWarbandAchievementPopups()

    if AchievementAlertSystem and type(self._blizzAchievementAddAlert) == "function" then
        if useWarbandPopups then
            local wrapper = BuildAchievementAddAlertReplacement(self._blizzAchievementAddAlert)
            MarkWnAddAlertWrapper(wrapper)
            AchievementAlertSystem.AddAlert = wrapper
        else
            AchievementAlertSystem.AddAlert = self._blizzAchievementAddAlert
        end
    end

    if CriteriaAlertSystem and type(self._blizzCriteriaAddAlert) == "function" then
        if useWarbandPopups then
            local wrapperCrit = BuildCriteriaAddAlertReplacement(self._blizzCriteriaAddAlert)
            MarkWnAddAlertWrapper(wrapperCrit)
            CriteriaAlertSystem.AddAlert = wrapperCrit
        else
            CriteriaAlertSystem.AddAlert = self._blizzCriteriaAddAlert
        end
    end

    local useCriteriaLane = NP.UseWarbandCriteriaProgressPopups()
    self._blizzProgressAddAlertOrig = self._blizzProgressAddAlertOrig or {}
    for i = 1, #PROGRESS_ALERT_SYSTEM_GLOBALS do
        local globalName = PROGRESS_ALERT_SYSTEM_GLOBALS[i]
        local sys = _G[globalName]
        if sys and type(sys.AddAlert) == "function" then
            local orig = self._blizzProgressAddAlertOrig[globalName]
            if type(orig) ~= "function" then
                local fn = sys.AddAlert
                if not IsWnAddAlertWrapper(fn) then
                    orig = fn
                    self._blizzProgressAddAlertOrig[globalName] = orig
                end
            end
            if useCriteriaLane and type(orig) == "function" then
                local wrapperProg = BuildProgressAddAlertReplacement(orig)
                MarkWnAddAlertWrapper(wrapperProg)
                sys.AddAlert = wrapperProg
            elseif type(orig) == "function" then
                sys.AddAlert = orig
            end
        end
    end

    if useWarbandPopups or useCriteriaLane then
        InstallBlizzardAlertFrameHideHooks()
        C_Timer.After(0.5, InstallBlizzardAlertFrameHideHooks)
        C_Timer.After(2, InstallBlizzardAlertFrameHideHooks)
    end
end

---Ensure achievement UI + current presentation toggle is applied (test + live share one AddAlert path).
TestLootEnsureAchievementAlertUI = function(addon)
    if not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
        LoadAlertSourceAddOns()
    end
    if addon and addon.ApplyBlizzardAchievementAlertSuppression then
        addon:ApplyBlizzardAchievementAlertSuppression()
    end
end

TestLootPrintAchievementReplaceMode = function(addon)
    if NP.UseWarbandAchievementPopups() then
        addon:Print("|cffffcc00Mode:|r Warband achievement popups ON")
    else
        addon:Print("|cffffcc00Mode:|r Warband achievement popups OFF (Blizzard alerts)")
    end
end

TestLootFireAchievementAddAlert = function(addon, achievementID, criteriaIndex)
    TestLootEnsureAchievementAlertUI(addon)
    if criteriaIndex ~= nil then
        if CriteriaAlertSystem and CriteriaAlertSystem.AddAlert then
            return pcall(CriteriaAlertSystem.AddAlert, CriteriaAlertSystem, achievementID, criteriaIndex)
        end
        if not AchievementAlertSystem or not AchievementAlertSystem.AddAlert then
            addon:Print("|cffff8800CriteriaAlertSystem not loaded. Try /reload.|r")
            return false, "no system"
        end
        return pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID, criteriaIndex)
    end
    if not AchievementAlertSystem or not AchievementAlertSystem.AddAlert then
        addon:Print("|cffff8800AchievementAlertSystem not loaded. Try /reload.|r")
        return false, "no system"
    end
    return pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID)
end

TestLootFireProgressAddAlert = function(addon, payload)
    TestLootEnsureAchievementAlertUI(addon)
    if Utilities and Utilities.SafeLoadAddOn then
        LoadAlertSourceAddOns()
    end
    if addon and addon.ApplyBlizzardAchievementAlertSuppression then
        addon:ApplyBlizzardAchievementAlertSuppression()
    end
    local progressSys = FindProgressAlertSystem()
    if progressSys and progressSys.AddAlert then
        return pcall(progressSys.AddAlert, progressSys, payload)
    end
    if addon and addon.ShowGenericProgressNotification then
        local shown = addon:ShowGenericProgressNotification(payload)
        if shown then
            addon:Print("|cff44ff44WN progress toast shown|r (ProgressAlertSystem unavailable in this client).")
            return true, "direct"
        end
        return false, "toast blocked"
    end
    addon:Print("|cffff8800Progress toast blocked — enable Notifications + Warband achievement popups + Criteria progress.|r")
    return false, "no system"
end

---Same pipeline as Traveler's Log / ProgressAlertSystem alerts.
function WarbandNexus:TestProgressAlert()
    if not EnsureNotificationTestsEnabled(self) then return end
    if not NP.UseWarbandCriteriaProgressPopups() then
        self:Print("|cffff8800Criteria progress popups OFF — enable Settings > Criteria progress popup.|r")
    end
    TestLootPrintAchievementReplaceMode(self)
    local payload = {
        title = "Traveler's Log Progress",
        text = "Void Assaults: Complete 5 Void Strikes",
        iconAtlas = "QuestLog-Questtypeicon-Quest",
    }
    self:Print("|cff00ccffProgress alert (AddAlert):|r " .. payload.title .. " - " .. payload.text)
    local ok, err = TestLootFireProgressAddAlert(self, payload)
    if ok then return end
    if err == "toast blocked" then
        self:Print("|cffff8800Progress toast blocked — check Notifications settings.|r")
        return
    end
    self:Print("|cffff8800Progress AddAlert failed: " .. tostring(err) .. "|r")
end

TestLootResolveAchievementWithCriteria = function(preferredID)
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

--- Wiki-backed QA chain: plain criteria -> sub-achievement (type 8) -> meta earned.
--- Fixture: Heroic: Power Creep (62901) checklist, Have a Heart (12918) row on Full Heart, Can't Lose (40958).
local HIERARCHY_FIXTURE_PLAIN_ID = 62901
local HIERARCHY_FIXTURE_SUB_ID = 12918
local HIERARCHY_FIXTURE_META_ID = 40958
local HIERARCHY_TEST_STEP_SEC = 0.65

local function TestHierarchyAchievementName(achievementID)
    if not achievementID then return nil end
    local ok, name = pcall(GetAchievementInfo, achievementID)
    if not ok or not name or name == "" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    return name
end

local function TestHierarchyFirstPlainCriteriaHint(achievementID)
    if not achievementID or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return nil end
    local okN, numCriteria = pcall(GetAchievementNumCriteria, achievementID)
    if not okN or not numCriteria or numCriteria < 1 then return nil end
    for i = 1, numCriteria do
        local ok, criteriaName, criteriaType = pcall(GetAchievementCriteriaInfo, achievementID, i)
        if ok then
            local ct = tonumber(criteriaType)
            if ct ~= ACHIEVEMENT_CRITERIA_TYPE_LINKED then
                if criteriaName and criteriaName ~= ""
                    and not (issecretvalue and issecretvalue(criteriaName)) then
                    return criteriaName, i
                end
                return i, i
            end
        end
    end
    return 1, 1
end

local function TestHierarchyLinkedSubCriteriaHint(metaID, subID)
    if not metaID or not subID or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then
        return "Have a Heart"
    end
    local okN, numCriteria = pcall(GetAchievementNumCriteria, metaID)
    if not okN or not numCriteria or numCriteria < 1 then
        return "Have a Heart"
    end
    for i = 1, numCriteria do
        local ok, criteriaName, criteriaType, _, _, _, _, assetID =
            pcall(GetAchievementCriteriaInfo, metaID, i)
        if ok and tonumber(criteriaType) == ACHIEVEMENT_CRITERIA_TYPE_LINKED then
            local linked = tonumber(assetID)
            if linked and linked == subID then
                if criteriaName and criteriaName ~= ""
                    and not (issecretvalue and issecretvalue(criteriaName)) then
                    return criteriaName
                end
                return TestHierarchyAchievementName(subID) or "Have a Heart"
            end
        end
    end
    return TestHierarchyAchievementName(subID) or "Have a Heart"
end

local function TestResolveHierarchyFixture()
    local plainID = HIERARCHY_FIXTURE_PLAIN_ID
    local subID = HIERARCHY_FIXTURE_SUB_ID
    local metaID = HIERARCHY_FIXTURE_META_ID
    local plainName = TestHierarchyAchievementName(plainID)
    local subName = TestHierarchyAchievementName(subID)
    local metaName = TestHierarchyAchievementName(metaID)
    if not plainName or not subName or not metaName then
        return nil
    end
    local plainHint, plainIndex = TestHierarchyFirstPlainCriteriaHint(plainID)
    local subHint = TestHierarchyLinkedSubCriteriaHint(metaID, subID)
    return {
        plain = { id = plainID, name = plainName, hint = plainHint, index = plainIndex },
        sub = { id = subID, name = subName, parentID = metaID, hint = subHint },
        meta = { id = metaID, name = metaName },
    }
end

--- Live AddAlert chain: criteria progress (puansiz) -> sub earned (puanli) -> meta earned (puanli).
function WarbandNexus:TestAchievementAlertHierarchy()
    if not EnsureNotificationTestsEnabled(self) then return end
    local fix = TestResolveHierarchyFixture()
    if not fix then
        self:Print("|cffff0000Hierarchy fixture unavailable.|r")
        self:Print("|cff888888Need client data for IDs 62901, 12918, 40958 (Midnight Void Assaults + Heart of Azeroth meta).|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccff[WN Hierarchy Test]|r Criteria -> Sub -> Meta (live AddAlert)")
    self:Print("|cff888888Fixture:|r " .. fix.plain.name .. " / " .. fix.sub.name .. " / " .. fix.meta.name)
    self:Print("|cff8888881.|r Criteria on |cffcccccc" .. fix.plain.name .. "|r — expect |cff00ccffAchievement Progress|r, no shield")
    self:Print("|cff8888882.|r Sub row |cffcccccc" .. tostring(fix.sub.hint) .. "|r on meta — expect |cffffff00earned|r + shield for |cffcccccc" .. fix.sub.name .. "|r")
    self:Print("|cff8888883.|r Meta |cffcccccc" .. fix.meta.name .. "|r — expect |cffffff00earned|r + shield")

    local delay = 0
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        local hint = fix.plain.hint or fix.plain.index or 1
        WarbandNexus:Print("|cff00ccff[1/3] Criteria progress|r — " .. fix.plain.name .. " / " .. tostring(hint))
        TestLootFireAchievementAddAlert(WarbandNexus, fix.plain.id, hint)
    end)
    delay = delay + HIERARCHY_TEST_STEP_SEC
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        WarbandNexus:Print("|cff00ccff[2/3] Sub-achievement earned|r — meta row " .. tostring(fix.sub.hint))
        TestLootFireAchievementAddAlert(WarbandNexus, fix.sub.parentID, fix.sub.hint)
    end)
    delay = delay + HIERARCHY_TEST_STEP_SEC
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        WarbandNexus:Print("|cff00ccff[3/3] Meta earned|r — " .. fix.meta.name)
        TestLootFireAchievementAddAlert(WarbandNexus, fix.meta.id, nil)
    end)
end

---Production Blizzard achievement alert fallback (when Warband popups cannot show a toast).
function WarbandNexus:InvokeBlizzardAchievementAddAlert(achievementID, criteriaIndex)
    if not achievementID or type(achievementID) ~= "number" then return false end
    if issecretvalue and issecretvalue(achievementID) then return false end
    TestLootEnsureAchievementAlertUI(self)
    local ok = TestLootFireAchievementAddAlert(self, achievementID, criteriaIndex)
    return ok == true
end

---Blizzard hooked progressive achievement / criteria AddAlert routes here (never calls ShowCriteriaProgressNotification directly â€” avoids stacking duplicate Alerts with WN_REMINDER lane).
function WarbandNexus:OnShowCriteriaProgressMessage(_, payload)
    if not payload then return end
    TryDispatchCriteriaProgressToast(payload.achievementID, payload.criteriaIndex)
end

---Dedicated To-Do reminder toast lane (ReminderService ActivateReminder -> WN_SHOW_REMINDER_TOAST).
function WarbandNexus:OnShowReminderToast(_, payload)
    if not payload or not payload.data then return end
    if not self:CanShowToast("reminder") then return end
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

local CollectNotify = ns.CollectionNotify

---Record toast display ack + permanent dedup after modal is queued (not at emit time).
local function MarkCollectibleToastAcknowledged(data)
    if not CollectNotify or not data or not data.type or not data.id then return end
    local t, id = data.type, data.id
    if t == "achievement" then
        if CollectNotify.MarkAchievementToastDisplayed then
            CollectNotify.MarkAchievementToastDisplayed(id)
        end
        if CollectNotify.ClearPendingAchievementToast then
            CollectNotify.ClearPendingAchievementToast(id)
        end
        if CollectNotify.MarkAsNotified then
            CollectNotify.MarkAsNotified(t, id)
        end
    end
    local permanentTypes = { mount = true, pet = true, toy = true, illusion = true, achievement = true, title = true }
    if permanentTypes[t] and CollectNotify.MarkAsPermanentlyNotified then
        CollectNotify.MarkAsPermanentlyNotified(t, id)
    end
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

    if data.type == "achievement" then
        if not self:CanShowToast("achievement") then
            NotifyDebug("|cffff6600BLOCKED: achievement toast (settings)|r")
            return
        end
    elseif not self:CanShowToast("loot", data.type) then
        NotifyDebug("|cffff6600BLOCKED: loot toast (settings)|r")
        return
    end

    -- TryCounter fires on loot; CollectionService fires on NEW_MOUNT / journal — same mount, two toasts.
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
    local tryCountNum = nil
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
                tryCountNum = count
            end
        end
    end
    
    NotifyDebug("SHOWING notification: hasTryCount=%s, tryCount=%s",
        tostring(hasTryCount),
        tostring(tryCountNum))

    local overrides = {}
    if tryCountNum then
        overrides.tryCount = tryCountNum
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
        overrides.achievementPoints = pts
        overrides.action = nil
    end
    if hasTryCount then
        overrides.deferScreenFlash = true
        overrides.autoDismiss = 7
        overrides.toastFxTier = "celebration"
    end
    local notifyType = hasTryCount and "tryCounter" or data.type
    self:Notify(notifyType, displayName, data.icon, overrides)
    MarkCollectibleToastAcknowledged(data)
    if lootToastDedupeKey then
        lastCollectibleLootToastShownAt[lootToastDedupeKey] = GetTime()
    end
end

---Plan completed handler
function WarbandNexus:OnPlanCompleted(event, data)
    if not data or not data.name then return end
    if not self:CanShowToast("plan") then return end

    -- Use planType icon fallback chain: data.icon -> planType category icon -> plan default
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
    if not self:CanShowToast("vault") then return end
    
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
    if not self:CanShowToast("vault") then return end

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
    if not self:CanShowToast("vault") then return end
    
    self:Notify("vault", string.format((ns.L and ns.L["WEEKLY_VAULT_PLAN_FORMAT"]) or "Weekly Vault Plan - %s", data.characterName), nil, {
        iconAtlas = "greatVault-whole-normal",
        action = (ns.L and ns.L["ALL_SLOTS_COMPLETE"]) or "All Slots Complete!",
    })
end

---Quest completed handler
function WarbandNexus:OnQuestCompleted(event, data)
    if not data or not data.characterName or not data.questTitle then return end
    if not self:CanShowToast("quest") then return end
    
    local cat = QUEST_CATEGORIES[data.category] or {name = (ns.L and ns.L["QUEST_LABEL"]) or "Quest:", atlas = "questlog-questtypeicon-heroic"}
    
    self:Notify("quest", cat.name .. " - " .. data.characterName, nil, {
        iconAtlas = cat.atlas,
        action = data.questTitle .. " " .. ((ns.L and ns.L["QUEST_COMPLETED_SUFFIX"]) or "Completed"),
    })
end

---Vault reward available handler
function WarbandNexus:OnVaultRewardAvailable(event, data)
    if data and data.claimable == false then return end
    if not self:CanShowToast("vault") then return end

    self:Notify("vault", (ns.L and ns.L["WEEKLY_VAULT_READY"]) or "Weekly Vault Ready!", CATEGORY_ICONS.vault, {
        action = (ns.L and ns.L["UNCLAIMED_REWARDS"]) or "You have unclaimed rewards",
        categoryTitle = "",
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
        if self.PrintNotificationTestHelp then
            self:PrintNotificationTestHelp()
        end
        self:Print("|cff888888Debug-only loot/plan samples:|r /wn testloot mount | pet | toy | plan | all")
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

    if type == "earn" then
        self:TestAchievementAlertEarn(id)
        return
    end

    if type == "progress" then
        self:TestAchievementAlertProgress(id, step)
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
                if rawTitle and rawTitle ~= "" and not (issecretvalue and issecretvalue(rawTitle)) then
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
        self:Print("|cffff0000Unknown notification type. Use |cffffcc00/wn notif help|r (or /wn testloot help with debug on).|r")
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
        self:Print("|cffffcc00/wn testevents achievementfallback [id]|r - ACHIEVEMENT_EARNED without AddAlert (replace fallback)")
        self:Print("|cffffcc00/wn testevents queueflood|r - 8 plan toasts (queue drain, max 6 visible)")
        self:Print("|cff888888Examples:|r")
        self:Print("|cff888888  /wn testevents plan 60981|r")
        self:Print("|cff888888  /wn testevents collectible 460|r")
        return
    end

    -- Replace-mode achievement fallback: fire ACHIEVEMENT_EARNED only (no AddAlert); expect WN toast ~1.25s
    if type == "achievementfallback" or type == "achfallback" then
        local achievementID = tonumber(id) or 6
        local okInfo, name = pcall(GetAchievementInfo, achievementID)
        if not okInfo or not name then
            self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
            return
        end
        if not NP.UseWarbandAchievementPopups() then
            self:Print("|cffff8800Warband achievement popups must be ON for this test.|r")
            return
        end
        self:Print("|cff00ccffAchievement fallback test:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
        if self.OnAchievementEarned then
            self:OnAchievementEarned("ACHIEVEMENT_EARNED", achievementID)
        end
        self:Print("|cff888888Watch for WN toast within ~1.25s (ScheduleAchievementToastFallback).|r")
        return
    end

    -- Queue flood: 8 toasts enqueued; all should appear (6 visible, rest after dismiss)
    if type == "queueflood" or type == "queue" then
        if not self:CanShowToast("plan") then
            self:Print("|cffff8800Notifications disabled; enable master toggle first.|r")
            return
        end
        for i = 1, 8 do
            local n = i
            C_Timer.After((n - 1) * 0.08, function()
                if WarbandNexus and WarbandNexus.Notify then
                    WarbandNexus:Notify("plan", "Queue flood test " .. n, nil, {
                        playSound = false,
                        autoDismiss = 10,
                    })
                end
            end)
        end
        self:Print("|cff00ff00Queue flood: 8 plan toasts scheduled (max 6 visible at once).|r")
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

