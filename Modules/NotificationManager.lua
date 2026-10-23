--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders

    NOTIFICATION FLOW:
      WN_COLLECTIBLE_OBTAINED dispatch -> OnCollectibleObtained -> Notify -> ShowModalNotification (queue max 6)
      WN_PLAN_COMPLETED / WN_VAULT_* / WN_QUEST_COMPLETED -> handler -> Notify
      WN_SHOW_REMINDER_TOAST -> OnShowReminderToast
      Achievement lane (binary): ns.NotificationPresentation — Warband popups ON -> Blizzard AlertFrame
        events unregistered + WN toast from ACHIEVEMENT_EARNED / CRITERIA_EARNED / PERKS_ACTIVITY_COMPLETED;
        OFF -> native Blizzard alerts only (suppressToast on WN_COLLECTIBLE_OBTAINED for achievements)
      Currency/reputation: ChatMessageService only (not toast lane)

    WN_FACTORY: Changelog popup scroll-child + themed close use `ns.UI.Factory` / ApplyVisuals; toast layering
    (effects/backdrop/icon z-order) stays plain `CreateFrame`; screen flash overlay remains an intentional fullscreen host.
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local FontManager = ns.FontManager  -- Centralized font management
local ApplyVisuals = ns.UI_ApplyVisuals
local ToastFactory = ns.NotificationToastFactory

local function NMToastLayer(parent, width, height)
    assert(ToastFactory and ToastFactory.CreateToastLayer, "NotificationManager requires NotificationToastFactory")
    return ToastFactory:CreateToastLayer(parent, width, height)
end
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
local TestLootEnsureAchievementAlertUI, TestLootFireAchievementAddAlert

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

    local fxRoot = NMToastLayer(toastHost, toastWidth, toastHeight)
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
    local sunHost = NMToastLayer(fxRoot, sunSize, sunSize)
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

    local clipFrame = NMToastLayer(toastHost, toastWidth, toastHeight)
    clipFrame:SetFrameLevel(4)
    clipFrame:SetAllPoints(toastHost)
    clipFrame:SetClipsChildren(true)
    clipFrame:EnableMouse(false)
    NM_IgnoreParentAlpha(clipFrame)

    local shineH = toastHeight
    local shineW = math.max(72, math.floor(toastWidth * NM_SHEEN_WIDTH_RATIO))
    local shineHost = NMToastLayer(clipFrame, toastWidth, toastHeight)
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

---Entrance polish on every toast; intensity scales with tier so frequent toasts stay calm.
---  quiet (minimal/progress/reminder/compact): rim glow + icon flash + faint sheen
---  standard: stronger rim glow + icon flash + sheen
---  celebration (earned collectible/achievement): sun burst + all of the above
local function NM_PlayToastEntranceEffects(toastHost, toastWidth, toastHeight)
    if not toastHost or toastHost.isClosing or toastHost._removed or not toastHost:IsShown() then
        return false
    end
    local w, h = NM_ResolveToastFxSize(toastHost, toastWidth, toastHeight)
    if w < 1 or h < 1 then
        return false
    end
    local tier = toastHost._toastFxTier or "minimal"
    local edgePeak, flashPeak, sheenPeak
    if tier == "celebration" then
        edgePeak, flashPeak, sheenPeak = 1, 0.85, 0.34
        NM_PlayToastSunGlow(toastHost, w, h)
    elseif tier == "standard" then
        edgePeak, flashPeak, sheenPeak = 0.85, 0.7, 0.36
    else
        edgePeak, flashPeak, sheenPeak = 0.65, 0.5, 0.2
    end
    toastHost._toastFxSheenPeak = sheenPeak
    NM_PlayToastSweepShine(toastHost, w, h)
    ToastFx.PlayEdgeGlow(toastHost, w, h, edgePeak)
    ToastFx.PlayIconFlash(toastHost, flashPeak)
    return true
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
            if not (issecretvalue and issecretvalue(mid)) and mid and type(mid) == "number" and mid > 0 then
                id = mid
            end
        end
        return "mount\0" .. tostring(id)
    end
    if t == "pet" and C_PetJournal and C_PetJournal.GetPetInfoByItemID and type(id) == "number" then
        local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(id))
        if not (issecretvalue and issecretvalue(speciesID)) and speciesID and type(speciesID) == "number" and speciesID > 0 then
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
    elseif notification.type == "mail" then
        WarbandNexus:ShowExpiringMailReminder()
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
    mail = "Interface\\Icons\\INV_Letter_15",
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
    if issecretvalue and issecretvalue(safeIcon) then safeIcon = nil end
    local safeName = name
    if issecretvalue and issecretvalue(safeName) then safeName = nil end
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

--[[ Alert stack: NotificationManager_AlertStack.lua (ns.NotificationAlertStack) ]]
local AS = ns.NotificationAlertStack
assert(AS, "NotificationManager: load NotificationManager_AlertStack.lua first")

-- Blizzard MonthlyActivityFrameTemplate icon (Interface/AddOns/Blizzard_FrameXML/Mainline/AlertFrameSystems.xml).
local TRAVELERS_LOG_PROGRESS_ICON_ATLAS = "activities-toast-icon"

local function NM_IsTravelersLogProgressTitle(title)
    if issecretvalue and issecretvalue(title) then return false end
    if type(title) ~= "string" or title == "" then return false end
    local monthlyTitle = _G.MONTHLY_ACTIVITIES_PROGRESSED
    if type(monthlyTitle) == "string" and monthlyTitle ~= ""
        and not (issecretvalue and issecretvalue(monthlyTitle)) and title == monthlyTitle then
        return true
    end
    local lower = string.lower(title)
    if lower:find("traveler", 1, true) and lower:find("log", 1, true) then
        return true
    end
    if lower:find("reisenden", 1, true) and lower:find("log", 1, true) then
        return true
    end
    return false
end

local function NM_FormatToastBadgeLabel(label)
    if issecretvalue and issecretvalue(label) then return label end
    if type(label) ~= "string" or label == "" then return label end
    if NM_IsTravelersLogProgressTitle(label) then
        return (ns.L and ns.L["TOAST_BADGE_TRAVELERS_LOG"]) or "Traveler's Log"
    end
    local achProgress = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"
    if label == achProgress then
        return (ns.L and ns.L["TOAST_CAT_ACHIEVEMENT"]) or "Achievement"
    end
    local progressSuffix = " Progress"
    if #label > #progressSuffix and label:sub(-#progressSuffix) == progressSuffix then
        return label:sub(1, #label - #progressSuffix)
    end
    return label
end

local function NM_EnsureTravelersLogProgressIcon(payload)
    if not payload then return payload end
    if payload.iconAtlas and payload.iconAtlas ~= "" then return payload end
    if payload.iconFileID or payload.icon then return payload end
    if NM_IsTravelersLogProgressTitle(payload.title) then
        payload.iconAtlas = TRAVELERS_LOG_PROGRESS_ICON_ATLAS
    end
    return payload
end

---Open the Blizzard achievement journal on `achievementID` (statistics use their own entry point).
---Blizzard_AchievementUI is load-on-demand and OpenAchievementFrameToAchievement no longer exists in
---12.1.5 FrameXML; shared by toast clicks and the Collections achievement rows (2026-10-22).
function ns.UI_OpenAchievementInJournal(achievementID)
    if not achievementID or InCombatLockdown() then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    if not Utilities:CheckAddOnLoaded("Blizzard_AchievementUI") then
        Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
    end
    local frame = _G.AchievementFrame
    if not frame then
        NotifyDebug("AchievementFrame missing after LoadAddOn")
        return
    end
    -- Selecting alone does not raise the panel — Blizzard always shows it first.
    -- ShowUIPanel goes through Blizzard's secure panel delegate, so the panel's OnShow does not run
    -- in our execution; the Toggle helper is only a fallback.
    if not frame:IsShown() then
        if type(ShowUIPanel) == "function" then
            pcall(ShowUIPanel, frame)
        elseif type(AchievementFrame_ToggleAchievementFrame) == "function" then
            pcall(AchievementFrame_ToggleAchievementFrame)
        end
    end
    -- OpenAchievementFrameToAchievement no longer exists in FrameXML; mirror
    -- AchievementFrame_SelectSearchItem (statistics use a different entry point).
    local okInfo, isStatistic = pcall(function()
        return select(15, GetAchievementInfo(achievementID))
    end)
    if not okInfo or (issecretvalue and issecretvalue(isStatistic)) then
        isStatistic = nil
    end
    if isStatistic and type(AchievementFrame_ViewStatisticByAchievementID) == "function" then
        local ok, err = pcall(AchievementFrame_ViewStatisticByAchievementID, achievementID)
        if not ok then NotifyDebug("ViewStatisticByAchievementID failed: %s", tostring(err)) end
    elseif type(AchievementFrame_SelectAchievement) == "function" then
        local ok, err = pcall(AchievementFrame_SelectAchievement, achievementID, true)
        if not ok then NotifyDebug("SelectAchievement failed: %s", tostring(err)) end
    elseif type(OpenAchievementFrameToAchievement) == "function" then
        pcall(OpenAchievementFrameToAchievement, achievementID)  -- legacy clients
    else
        NotifyDebug("no achievement open path available")
    end
end

---Left-click target for a toast: Blizzard achievement UI, or the Traveler's Log tab of the
---Adventure Guide. Both panels are load-on-demand, so the addon must be pulled in first —
---OpenAchievementFrameToAchievement / EncounterJournal simply do not exist until then.
local function NM_OpenToastTarget(toast)
    if not toast then return end
    NotifyDebug("toast click: achievementID=%s openTarget=%s combat=%s",
        tostring(toast.achievementID), tostring(toast.openTarget), tostring(InCombatLockdown()))
    if InCombatLockdown() then return end

    local achievementID = toast.achievementID
    if achievementID then
        ns.UI_OpenAchievementInJournal(achievementID)
        return
    end

    if toast.openTarget ~= "travelersLog" then return end
    -- Tab is hidden when the log is unavailable (Blizzard gates it the same way).
    if C_PlayerInfo and C_PlayerInfo.IsTravelersLogAvailable then
        local okAvail, available = pcall(C_PlayerInfo.IsTravelersLogAvailable)
        if okAvail and not (issecretvalue and issecretvalue(available)) and available == false then return end
    end
    if not Utilities:CheckAddOnLoaded("Blizzard_EncounterJournal") then
        Utilities:SafeLoadAddOn("Blizzard_EncounterJournal")
    end
    local ej = _G.EncounterJournal
    if not ej then
        NotifyDebug("EncounterJournal missing after LoadAddOn")
        return
    end
    if not ej:IsShown() and type(ShowUIPanel) == "function" then
        local okShow, errShow = pcall(ShowUIPanel, ej)
        if not okShow then NotifyDebug("ShowUIPanel failed: %s", tostring(errShow)) end
    end
    -- Same path Blizzard's own EncounterJournal_OpenTo* helpers use.
    local tab = ej.MonthlyActivitiesTab
    if tab and tab.GetID and type(EJ_ContentTab_Select) == "function" then
        local okTab, errTab = pcall(EJ_ContentTab_Select, tab:GetID())
        if not okTab then NotifyDebug("EJ_ContentTab_Select failed: %s", tostring(errTab)) end
    else
        NotifyDebug("MonthlyActivitiesTab or EJ_ContentTab_Select unavailable")
    end
end


---Show an achievement-style notification with all visual effects (WoW AlertFrame style)
---Addon-created toast frames are not secure; showing them during combat is safe (no taint).
function WarbandNexus:ShowModalNotification(config)
    -- Queue when at capacity; dequeue on dismiss via C_Timer (no polling queue logic).
    if #self.activeAlerts >= AS.NOTIFICATION_MAX_VISIBLE_ALERTS then
        AS.EnqueueAlert(config)
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
    local toastLane = AS.InferToastLane(config)
    local point, baseX, baseY = AS.ResolveToastAnchor(toastLane)
    local dbN = self.db and self.db.profile and self.db.profile.notifications
    local direction = AS.GetGrowthDirection(point, baseX, baseY)
    -- Per-lane prefix when anchors are split so two lanes at the same pixel do not share one vertical stack slot.
    local lanePrefix = (dbN and dbN.unifiedToastLayout == false) and (toastLane .. "|") or ""
    local anchorKey = lanePrefix .. point .. "|" .. tostring(baseX) .. "|" .. tostring(baseY)
    local yOffset = baseY + AS.GetCumulativeOffsetForNewAlert(anchorKey, direction)
    
    -- Compact toast: icon left, content (backdrop + text) right.
    if config.compact then
        local laneUsesProgressLane = (config.progressAnchor == true or config.notifType == "criteria")
            and not isPlanReminderToast

        local popupWidthCompact, COMPACT_HEIGHT, ICON_SLOT_WIDTH_COMPACT, iconSizeCompact
        if AS.ResolveCompactToastDimensions then
            popupWidthCompact, COMPACT_HEIGHT, ICON_SLOT_WIDTH_COMPACT, iconSizeCompact =
                AS.ResolveCompactToastDimensions(laneUsesProgressLane)
        else
            COMPACT_HEIGHT = AS.GetCompactToastBaseHeight(laneUsesProgressLane)
            popupWidthCompact = AS.GetCompactToastWidth(laneUsesProgressLane)
            ICON_SLOT_WIDTH_COMPACT = laneUsesProgressLane and AS.ALERT_PROGRESS_ICON_SLOT or AS.ALERT_ICON_SLOT
            iconSizeCompact = laneUsesProgressLane and AS.ALERT_PROGRESS_ICON_SIZE or AS.ALERT_ICON_SIZE
        end
        local laneIconLeadingPad = AS.ALERT_PAD_LEFT
        if config.criteriaNoIcon == true and not iconAtlas and (not iconTexture or iconTexture == "") then
            iconTexture = AS.CRITERIA_TOAST_FALLBACK_ICON
        end
        local iconLaneWidth = ICON_SLOT_WIDTH_COMPACT
        local compactPopup = ToastFactory:CreateToastHost(UIParent, popupWidthCompact, COMPACT_HEIGHT, { strata = "HIGH", frameLevel = 1000 })
        compactPopup:SetSize(popupWidthCompact, COMPACT_HEIGHT)
        compactPopup.currentYOffset = yOffset
        compactPopup.achievementID = config.achievementID
        compactPopup.openTarget = config.openTarget
        compactPopup._toastLane = toastLane
        compactPopup._anchorPoint = point
        compactPopup._baseX = baseX
        compactPopup._baseY = baseY
        compactPopup._alertHeight = COMPACT_HEIGHT
        if ns.UI_ApplyAddonUIScale then
            ns.UI_ApplyAddonUIScale(compactPopup)
        end
        
        -- Layer 0: effects (glow lines) behind the black frame
        local effectsFrameCompact = NMToastLayer(compactPopup, popupWidthCompact, COMPACT_HEIGHT)
        effectsFrameCompact:SetFrameLevel(0)
        effectsFrameCompact:SetAllPoints(compactPopup)
        -- Layer 1: black background on top of effects
        local backdropFrameCompact = NMToastLayer(compactPopup, popupWidthCompact, COMPACT_HEIGHT)
        backdropFrameCompact:SetFrameLevel(1)
        backdropFrameCompact:SetAllPoints(compactPopup)
        backdropFrameCompact:EnableMouse(false)
        backdropFrameCompact:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            tile = false,
            edgeSize = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(backdropFrameCompact)) or 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        backdropFrameCompact:SetBackdropColor(NM_GetElevatedBackdropFillRGBA())
        ToastChrome.ApplyCompactBackdropChrome(backdropFrameCompact, titleColor, 0.38)
        
        -- Layer 2: icon slot (always reserved so stacked toasts share one left gutter)
        local iconSlotCompact = NMToastLayer(compactPopup, iconLaneWidth, COMPACT_HEIGHT)
        iconSlotCompact:SetFrameLevel(2)
        iconSlotCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad, 0)

        local iconCompact
        local isAchievementEarnedToast = config.notifType == "achievement"
        if isAchievementEarnedToast then
            local achPts = AS.NM_ResolveAchievementToastPoints(config)
            iconCompact = AS.NM_CreateAchievementShieldSlot(iconSlotCompact, achPts, titleColor)
        else
        iconCompact = iconSlotCompact:CreateTexture(nil, "ARTWORK")
        iconCompact:SetSize(iconSizeCompact, iconSizeCompact)
        iconCompact:SetPoint("CENTER", iconSlotCompact, "CENTER", 0, 0)
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
        ToastChrome.ApplyCompactIconBorder(iconSlotCompact, iconCompact, iconSizeCompact, titleColor)
        end
        
        -- Content frame (right): text only
        local contentFrameCompact = NMToastLayer(compactPopup, 1, COMPACT_HEIGHT)
        contentFrameCompact:SetFrameLevel(2)
        contentFrameCompact:SetPoint("TOP", compactPopup, "TOP", 0, 0)
        contentFrameCompact:SetPoint("BOTTOM", compactPopup, "BOTTOM", 0, 0)
        contentFrameCompact:SetPoint("LEFT", compactPopup, "LEFT", laneIconLeadingPad + iconLaneWidth, 0)
        contentFrameCompact:SetPoint("RIGHT", compactPopup, "RIGHT", -AS.ALERT_PAD_RIGHT, 0)
        contentFrameCompact:SetClipsChildren(true)
        -- Compact card: small category/header on top, primary title below; text block vertically centered in content lane.
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
            tryCountStr = AS.FormatToastAttemptsLabel(config.tryCount) or ""
        elseif config.tryCountText and config.tryCountText ~= "" then
            tryCountStr = config.tryCountText
        end
        if type(tryCountStr) == "string" and issecretvalue and issecretvalue(tryCountStr) then tryCountStr = "" end
        if config.notifType == "tryCounter" and tryCountStr == "" and detailStr ~= "" then
            tryCountStr = detailStr
            detailStr = ""
        end
        local isTryCounterToast = config.notifType == "tryCounter"
        local tryCounterCountLine = nil
        if isTryCounterToast then
            if type(config.tryCount) == "number" and config.tryCount > 0 then
                tryCounterCountLine = AS.FormatToastAttemptsLabel(config.tryCount) or tostring(config.tryCount)
            elseif tryCountStr ~= "" then
                tryCounterCountLine = tryCountStr
            end
            headerTitle = (ns.L and ns.L["TOAST_BADGE_ATTEMPTS"]) or "Attempts"
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
        local categoryFirstLayout = useTwoLineCard
        local titleLine, headerLine
        -- Sized by the SetPoint pair below and the explicit SetSize once textUseW/stackH exist.
        local textGroup = NMToastLayer(contentFrameCompact)
        textGroup:SetFrameLevel(1)
        textGroup:SetPoint("TOPLEFT", contentFrameCompact, "TOPLEFT", 0, 0)
        textGroup:SetPoint("BOTTOMRIGHT", contentFrameCompact, "BOTTOMRIGHT", 0, 0)

        -- Balanced stack: small category + primary line; progress lane uses narrower body typography.
        local primaryFontRole = laneUsesProgressLane and "body" or "title"
        local maxPrimaryLines = laneUsesProgressLane and AS.ALERT_PROGRESS_PRIMARY_MAX_LINES or AS.ALERT_PRIMARY_MAX_LINES
        titleLine = AS.NM_CreateToastFontString(textGroup, primaryFontRole, "OVERLAY", nil, laneUsesProgressLane)
        titleLine:SetJustifyH("LEFT")
        titleLine:SetWordWrap(true)
        titleLine:SetMaxLines(maxPrimaryLines)
        if not laneUsesProgressLane then
            titleLine:SetWordWrap(false)
        end
        titleLine:SetText(titleHex .. (nameStr or "") .. "|r")
        titleLine:SetShadowOffset(1, -1)
        NM_ApplyTextShadow(titleLine, 0.85)

        if useTwoLineCard then
            headerLine = AS.NM_CreateToastFontString(textGroup, "small", "OVERLAY", nil, laneUsesProgressLane)
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWordWrap(false)
            headerLine:SetMaxLines(1)
            if isTryCounterToast then
                headerLine:SetText(categoryHex .. (headerSafe or "") .. "|r")
                headerLine:SetShadowOffset(1, -1)
                NM_ApplyTextShadow(headerLine, 0.8)
            else
                local badgeLabel = NM_FormatToastBadgeLabel(headerSafe)
                headerLine:SetText(categoryHex .. (badgeLabel or "") .. "|r")
                headerLine:SetShadowOffset(1, -1)
                NM_ApplyTextShadow(headerLine, 0.8)
            end
        elseif config.emphasizeAction then
            -- Single prominent line (vault "unclaimed rewards"): larger + bright; centered below.
            headerLine = AS.NM_CreateToastFontString(textGroup, "title", "OVERLAY", nil, false)
            headerLine:SetJustifyH("CENTER")
            headerLine:SetWordWrap(true)
            headerLine:SetMaxLines(2)
            headerLine:SetText(NM_ThemeTextHex("Bright") .. progressStr .. "|r")
            headerLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(headerLine, 0.85)
        else
            headerLine = AS.NM_CreateToastFontString(textGroup, "small", "OVERLAY", nil, laneUsesProgressLane)
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWordWrap(true)
            headerLine:SetMaxLines(2)
            headerLine:SetText(NM_ThemeTextHex("Normal") .. progressStr .. "|r")
            headerLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(headerLine, 0.6)
        end

        local textUseW = math.max(48, popupWidthCompact - laneIconLeadingPad - iconLaneWidth - AS.ALERT_PAD_RIGHT - AS.ALERT_PAD_TEXT * 2)
        titleLine:SetWidth(textUseW)
        headerLine:SetWidth(textUseW)

        local tryCountLine = nil
        local detailLine = nil

        if isTryCounterToast and tryCounterCountLine and tryCounterCountLine ~= "" then
            detailLine = AS.NM_CreateToastFontString(textGroup, "title", "OVERLAY", nil, false)
            detailLine:SetWidth(textUseW)
            detailLine:SetJustifyH("LEFT")
            detailLine:SetWordWrap(false)
            detailLine:SetMaxLines(1)
            detailLine:SetText(titleHex .. tryCounterCountLine .. "|r")
            detailLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(detailLine, 0.85)
        elseif useTwoLineCard and detailStr ~= "" and detailStr ~= (ACTION_TEXT[config.notifType] or "") then
            detailLine = AS.NM_CreateToastFontString(textGroup, "small", "OVERLAY")
            detailLine:SetWidth(textUseW)
            detailLine:SetJustifyH("LEFT")
            detailLine:SetWordWrap(false)
            detailLine:SetMaxLines(1)
            detailLine:SetText(NM_ThemeTextHex("Muted") .. detailStr .. "|r")
            detailLine:SetShadowOffset(1, -1)
            NM_ApplyTextShadow(detailLine, 0.6)
        end

        local gapTitle = AS.ALERT_TEXT_LINE_GAP
        local hTitle = titleLine:GetStringHeight()
        local hHeader = headerLine:GetStringHeight()
        local hDetail = detailLine and detailLine:GetStringHeight() or 0
        local stackH
        if categoryFirstLayout then
            stackH = hTitle + (detailLine and (gapTitle + hDetail) or 0)
        else
            stackH = hTitle + gapTitle + hHeader + (detailLine and (gapTitle + hDetail) or 0)
        end

        local newH = COMPACT_HEIGHT
        compactPopup:SetHeight(newH)
        iconSlotCompact:SetHeight(newH)
        contentFrameCompact:SetHeight(newH)
        compactPopup._alertHeight = newH
        compactPopup._toastTier = laneUsesProgressLane and "progress" or "collectible"

        textGroup:SetSize(textUseW, stackH)
        local compactTextMode = "legacySingle"
        if categoryFirstLayout then
            compactTextMode = "standard"
        end
        if ToastFactory and ToastFactory.ApplyCompactTextLayout then
            ToastFactory:ApplyCompactTextLayout({
                mode = compactTextMode,
                contentFrame = contentFrameCompact,
                textGroup = textGroup,
                headerLine = headerLine,
                titleLine = titleLine,
                detailLine = detailLine,
                textUseW = textUseW,
                stackH = stackH,
                hHeader = hHeader,
                gapTitle = gapTitle,
                emphasizeAction = config.emphasizeAction == true,
            })
        end
        
        if config.playSound then
            local Constants = ns.Constants
            local defaultSound
            if laneUsesProgressLane then
                defaultSound = (SOUNDKIT and (SOUNDKIT.UI_AUTO_QUEST_COMPLETE or SOUNDKIT.AUTO_QUEST_COMPLETE))
                    or (Constants and Constants.NOTIFICATION_SOUND_PROGRESS)
                    or 44294
            else
                defaultSound = (Constants and Constants.NOTIFICATION_SOUND_COMPACT_DEFAULT) or 44295
            end
            PlaySound(config.soundID or defaultSound)
        end
        
        -- Left-click: open the related Blizzard panel + dismiss | Right-click: dismiss only
        compactPopup:SetScript("OnMouseDown", function(self, button)
            if self.isClosing or self._removed then return end
            if button == "LeftButton" then
                NM_OpenToastTarget(self)
            end
            AS.RequestDismissToast(self)
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
        AS.RepositionAlerts(true)
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

        AS.ScheduleToastDismiss(compactPopup, compactDuration)
        MaybeScheduleTryCounterCelebration(config, compactPopup)
        return true
    end
    
    -- Full achievement popup: fixed width; long titles/subtitles wrap inside the text area
    local popupWidthFull = AS.ALERT_WIDTH_FIXED
    
    -- WoW Achievement-style: container = icon slot (left) + content frame (text).
    local ICON_SLOT_WIDTH = AS.ALERT_ICON_SLOT_FULL
    local contentFrameWidth = popupWidthFull - ICON_SLOT_WIDTH
    
    local popup = ToastFactory:CreateToastHost(UIParent, popupWidthFull, AS.ALERT_HEIGHT, { strata = "HIGH", frameLevel = 1000 })
    popup:SetSize(popupWidthFull, AS.ALERT_HEIGHT)
    popup:SetMouseClickEnabled(true)
    if ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(popup)
    end
    
    -- Layer 0: glow / edge effects (behind backdrop)
    local effectsFrame = NMToastLayer(popup, popupWidthFull, AS.ALERT_HEIGHT)
    effectsFrame:SetFrameLevel(0)
    effectsFrame:SetAllPoints(popup)
    
    -- Layer 1: single black background (drawn on top of effects)
    local backdropFrame = NMToastLayer(popup, popupWidthFull, AS.ALERT_HEIGHT)
    backdropFrame:SetFrameLevel(1)
    backdropFrame:SetAllPoints(popup)
    backdropFrame:EnableMouse(false)
    backdropFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        tile = false,
        edgeSize = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(backdropFrame)) or 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    backdropFrame:SetBackdropColor(NM_GetElevatedBackdropFillRGBA())
    backdropFrame:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    
    -- Layer 2: icon slot (icon + bling only)
    local iconSlot = NMToastLayer(popup, ICON_SLOT_WIDTH, AS.ALERT_HEIGHT)
    iconSlot:SetFrameLevel(2)
    iconSlot:SetPoint("LEFT", popup, "LEFT", 0, 0)
    
    local iconSize = AS.ALERT_ICON_SIZE_FULL
    local icon = iconSlot:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", iconSlot, "LEFT", AS.ALERT_ICON_INSET_FULL, 0)
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
    iconBling:SetSize(AS.ALERT_ICON_BLING_FULL, AS.ALERT_ICON_BLING_FULL)
    iconBling:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBling:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    iconBling:SetTexCoord(0, 0.5625, 0, 0.5625)
    iconBling:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    iconBling:SetBlendMode("BLEND")
    
    -- Layer 2: content frame (text only)
    local contentFrame = NMToastLayer(popup, contentFrameWidth, AS.ALERT_HEIGHT)
    contentFrame:SetFrameLevel(2)
    contentFrame:SetSize(contentFrameWidth, AS.ALERT_HEIGHT)
    contentFrame:SetPoint("LEFT", popup, "LEFT", ICON_SLOT_WIDTH, 0)
    
    local popupHeight = AS.ALERT_HEIGHT
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
    if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(edgeShine, "horizontal", 1) else edgeShine:SetHeight(1) end
    edgeShine:SetPoint("TOPLEFT", effectsFrame, "TOPLEFT", 1, -1)
    edgeShine:SetPoint("TOPRIGHT", effectsFrame, "TOPRIGHT", -1, -1)
    edgeShine:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.3)
    edgeShine:SetBlendMode("ADD")
    -- Bottom edge shine
    local edgeShineBottom = effectsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(edgeShineBottom, "horizontal", 1) else edgeShineBottom:SetHeight(1) end
    edgeShineBottom:SetPoint("BOTTOMLEFT", effectsFrame, "BOTTOMLEFT", 1, 1)
    edgeShineBottom:SetPoint("BOTTOMRIGHT", effectsFrame, "BOTTOMRIGHT", -1, 1)
    edgeShineBottom:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShineBottom:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.2)
    edgeShineBottom:SetBlendMode("ADD")
    
    -- Symmetric layout: text block center = content frame center.
    local popupWidth = contentFrameWidth
    local popupHeight = AS.ALERT_HEIGHT
    local textCenterX = contentFrameWidth / 2
    local textAreaWidth = math.max(AS.ToastPx(40), contentFrameWidth - AS.ToastPx(20))
    
    -- Font metrics (scaled with toast layout)
    local smallFontHeight = AS.NM_ToastFontSize("small")
    local mediumFontHeight = AS.NM_ToastFontSize("body")
    local largeFontHeight = AS.NM_ToastFontSize("title")
    local lineSpacing = AS.ToastPx(3)
    
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
    local textVerticalBias = -AS.ToastPx(7)
    local startY = (totalHeight / 2) + textVerticalBias
    
    -- LINE 1: Category (optional)
    -- NOTE: All text FontStrings use OVERLAY sublevel 7 to render above
    -- glow textures (TopBottom lines at sublevel 5, edgeShine at 6, iconBling at 7)
    if showCategory then
        local category = AS.NM_CreateToastFontString(contentFrame, "small", "OVERLAY")
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
        local title = AS.NM_CreateToastFontString(contentFrame, "title", "OVERLAY")
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
        local subtitle = AS.NM_CreateToastFontString(contentFrame, "body", "OVERLAY")
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
        local legacySub = AS.NM_CreateToastFontString(contentFrame, "body", "OVERLAY")
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
    
    -- Left-click: open the related Blizzard panel + dismiss | Right-click: dismiss only
    popup:SetScript("OnMouseDown", function(self, button)
        if self.isClosing or self._removed then return end
        if button == "LeftButton" then
            NM_OpenToastTarget(self)
        end
        AS.RequestDismissToast(self)
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
    popup._alertHeight = AS.ALERT_HEIGHT
    popup.achievementID = config.achievementID
    popup.openTarget = config.openTarget

    table.insert(self.activeAlerts, popup)
    popup.isEntering = true

    popup:SetAlpha(0)
    popup:SetPoint(point, UIParent, point, baseX, startYOffset)
    popup.currentYOffset = startYOffset
    popup._entranceStartY = startYOffset
    popup._entranceTargetY = finalYOffset
    popup._entranceStartTime = GetTime()

    AS.RepositionAlerts(true)
    NM_AssignToastFxMetadata(popup, config, titleColor, icon, backdropFrame)
    popup:Show()
    NM_TriggerToastEntranceEffects(popup, popupWidthFull, AS.ALERT_HEIGHT)

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

    AS.ScheduleToastDismiss(popup, autoDismissDelay)
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
    local okHas, hasAvail = pcall(C_WeeklyRewards.HasAvailableRewards)
    if not okHas or not hasAvail then
        return false
    end
    -- No AreRewardsForCurrentRewardPeriod gate here: loot earned in an earlier reward period is
    -- still in the chest and still claimable (Blizzard shows its own "previous reward" notice for
    -- that case), so a vault left unclaimed for a week or more must still count as unclaimed.
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
            data = ns.CHANGELOG
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
            if not hasRewards and C_WeeklyRewards.HasAvailableRewards then
                local okHas, v = pcall(C_WeeklyRewards.HasAvailableRewards)
                hasRewards = okHas and v or false
            end
            local canClaim = ns.WeeklyVaultCanClaimAtLocation and ns.WeeklyVaultCanClaimAtLocation()
            local activities
            if C_WeeklyRewards.GetActivities then
                local okAct, v = pcall(C_WeeklyRewards.GetActivities)
                activities = okAct and v or nil
            end
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
    
    -- 3. Mail about to expire on any tracked character. Delayed past the
    -- PLAYER_ENTERING_WORLD mail scan (2s + 0.3s debounce) so this character's own inbox is
    -- counted with fresh data; alts contribute from their stored snapshots. Queued late, so
    -- it drives the queue itself rather than relying on the 0.5s/1.5s pumps below.
    if notifs.showMailReminder ~= false then
        C_Timer.After(3.5, function()
            local MS = ns.MailSnapshot
            if not (WarbandNexus and MS and MS.GetExpiringMailSummary) then return end
            local count = MS.GetExpiringMailSummary(WarbandNexus)
            if not count or count < 1 then return end
            QueueNotification({ type = "mail" })
            ProcessNotificationQueue()
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
    -- WN_REPUTATION_GAINED is handled in ChatMessageService.lua (chat notifications)
    self:RegisterMessage(E.VAULT_REWARD_AVAILABLE, "OnVaultRewardAvailable")
    -- Plan reminders: optional compact toast via WN_SHOW_REMINDER_TOAST (not Blizzard AddAlert hooks)
    
    -- Font change listener (low-impact: active notifications auto-dismiss quickly, new ones will use updated font)
    -- NOTE: Uses NotificationEvents as 'self' key to avoid overwriting PlansTrackerWindow's handler.
    WarbandNexus.RegisterMessage(NotificationEvents, E.FONT_CHANGED, function()
        -- Active notifications will pick up new font on next creation
        -- No action needed for already-visible notifications (they auto-dismiss)
    end)
    
    -- Suppress Blizzard achievement/criteria/Traveler's Log alerts the WN lanes replace (event-level, taint-free).
    self:ApplyBlizzardAchievementAlertSuppression()
    self:RegisterEvent("CRITERIA_EARNED", "OnCriteriaEarned")
    self:RegisterEvent("PERKS_ACTIVITY_COMPLETED", "OnPerksActivityCompleted")
end

---Shorten Blizzard's long criteria description to a display name (e.g. "Player Has Opened all X" -> "X").
local function ShortenCriteriaDisplayName(criteriaString)
    if issecretvalue and issecretvalue(criteriaString) then return (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria" end
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
    elseif channel == "mail" then
        return db.showMailReminder ~= false
    elseif channel == "reminder" then
        return db.showPlanReminderToast ~= false
    end
    return true
end

---ProgressAlertSystem payloads (Traveler's Log, etc.) — no achievementID required.
local function ResolveProgressAlertPayload(a1, a2, ...)
    local function safeStr(v)
        if issecretvalue and issecretvalue(v) then return nil end
        if type(v) ~= "string" or v == "" then return nil end
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
    -- PERKS_ACTIVITY_COMPLETED(perksActivityID): resolve the activity (12.1.5 API:
    -- C_PerksActivities.GetPerksActivityInfo(id) -> PerksActivityInfo? with activityName).
    if type(a1) == "number" and not (issecretvalue and issecretvalue(a1))
        and C_PerksActivities and C_PerksActivities.GetPerksActivityInfo then
        local ok, info = pcall(C_PerksActivities.GetPerksActivityInfo, a1)
        if ok and type(info) == "table" then
            -- PerksActivityInfo carries both activityName and description; the generic text
            -- chain would pick description first, the toast shows the activity name.
            local payload = fromTable(info)
            local name = safeStr(info.activityName)
            if payload and name then payload.text = name end
            return payload
        end
        return nil
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
    return NM_EnsureTravelersLogProgressIcon(payload)
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
    elseif type(criteriaHint) == "string" and ((issecretvalue and issecretvalue(criteriaHint)) or criteriaHint ~= "") then
        if issecretvalue and issecretvalue(criteriaHint) then return nil end
        for i = 1, numCriteria do
            local name = GetAchievementCriteriaInfo(achievementID, i)
            if not (issecretvalue and issecretvalue(name)) and name and name == criteriaHint then
                criteriaIndex = i
                break
            end
        end
    end
    if not criteriaIndex or criteriaIndex < 1 or criteriaIndex > numCriteria then
        return nil
    end

    -- GetAchievementCriteriaInfo: ..., charName(6), flags(7), assetID(8)
    local ok, _, criteriaType, _, _, _, _, _, assetID = pcall(GetAchievementCriteriaInfo, achievementID, criteriaIndex)
    if not ok then return nil end

    local linkedID = nil
    local ct = tonumber(criteriaType)
    if ct == AS.ACHIEVEMENT_CRITERIA_TYPE_LINKED and assetID
        and not (issecretvalue and issecretvalue(assetID)) then
        local n = tonumber(assetID)
        if n and n > 0 then
            linkedID = n
        end
    end

    local linkedIcon = nil
    if linkedID then
        local okInfo, _, _, _, _, _, _, _, _, _, icon = pcall(GetAchievementInfo, linkedID) -- icon = 10th
        if okInfo and not (issecretvalue and issecretvalue(icon)) and icon then
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

---Wiki: CRITERIA_EARNED achievementID, description, achievementAlreadyEarnedOnAccount
function WarbandNexus:OnCriteriaEarned(_, achievementID, description, achievementAlreadyEarnedOnAccount)
    if not NP.UseWarbandAchievementPopups() and not NP.UseWarbandCriteriaProgressPopups() then return end
    if not achievementID or type(achievementID) ~= "number" then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    if issecretvalue and issecretvalue(achievementAlreadyEarnedOnAccount) then achievementAlreadyEarnedOnAccount = nil end
    if achievementAlreadyEarnedOnAccount then return end
    if issecretvalue and issecretvalue(description) then
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
            if issecretvalue and issecretvalue(name) then name = nil end
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
                if issecretvalue and issecretvalue(name) then name = nil end
                criteriaName = (name and name ~= "" and name) and ShortenCriteriaDisplayName(name) or (ns.L and ns.L["CRITERIA_PROGRESS_CRITERION"]) or "Criteria"
            end
        else
            for i = 1, numCriteria do
                local name, _, comp = GetAchievementCriteriaInfo(achievementID, i)
                if comp then completedCount = completedCount + 1 end
                if not criteriaName or criteriaName == "" then
                    if issecretvalue and issecretvalue(name) then name = nil end
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
        criteriaTitle = NM_FormatToastBadgeLabel(payload.title),
        itemName = payload.text,
        titleColor = ToastChrome.CriteriaAccent(),
        playSound = true,
        autoDismiss = 3,
        openTarget = "travelersLog",  -- no achievementID on this lane; click opens the log tab
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

--- Blizzard AlertFrame events each WN lane replaces. AlertFrame:UnregisterEvent is a C call: unlike
--- swapping AlertSystem.AddAlert (or hiding pooled alert frames) it leaves no Lua taint in Blizzard's
--- alert pipeline, which also drives instance loot alerts that carry secret values.
--- Blizzard shows its own alert exactly when the matching WN toast cannot (lane or sub-toggle off).
local SUPPRESSIBLE_ALERT_EVENTS = {
    { event = "ACHIEVEMENT_EARNED", lane = "achievement" },
    { event = "CRITERIA_EARNED", lane = "progress" },
    { event = "PERKS_ACTIVITY_COMPLETED", lane = "progress" },
}
local suppressedAlertEvents = {}

---Unregister / re-register Blizzard AlertFrame events from the live notification settings.
function WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
    local alertFrame = _G.AlertFrame
    if not alertFrame or type(alertFrame.UnregisterEvent) ~= "function" then return end
    local suppressAchievement = NP.CanShowWarbandAchievementEarnedToast()
    local suppressProgress = NP.CanShowWarbandCriteriaProgressToast()
    for i = 1, #SUPPRESSIBLE_ALERT_EVENTS do
        local entry = SUPPRESSIBLE_ALERT_EVENTS[i]
        local suppress = (entry.lane == "achievement") and suppressAchievement or suppressProgress
        if suppress and not suppressedAlertEvents[entry.event] then
            alertFrame:UnregisterEvent(entry.event)
            suppressedAlertEvents[entry.event] = true
        elseif not suppress and suppressedAlertEvents[entry.event] then
            -- Only ever re-register what we unregistered; never touch Blizzard's set otherwise.
            alertFrame:RegisterEvent(entry.event)
            suppressedAlertEvents[entry.event] = nil
        end
    end
end

---PERKS_ACTIVITY_COMPLETED (Traveler's Log step) -> WN progress toast; Blizzard's alert is
---unregistered while this lane can show.
function WarbandNexus:OnPerksActivityCompleted(_, perksActivityID)
    if not NP.CanShowWarbandCriteriaProgressToast() then return end
    if issecretvalue and issecretvalue(perksActivityID) then return end
    TryDispatchProgressAlertToast(ResolveProgressAlertPayload(perksActivityID))
end

---Ensure the current presentation toggle is applied before a test fires.
TestLootEnsureAchievementAlertUI = function(addon)
    if addon and addon.ApplyBlizzardAchievementAlertSuppression then
        addon:ApplyBlizzardAchievementAlertSuppression()
    end
end

---Test: drive the same handlers the live ACHIEVEMENT_EARNED / CRITERIA_EARNED events use.
---Never calls Blizzard's AlertSystem:AddAlert from our code (that taints the alert pipeline).
TestLootFireAchievementAddAlert = function(addon, achievementID, criteriaIndex)
    TestLootEnsureAchievementAlertUI(addon)
    if not NP.UseWarbandAchievementPopups() then
        addon:Print("|cffff8800Warband achievement popups OFF: Blizzard alerts are native-only and are not simulated (avoids taint).|r")
        return false, "native lane"
    end
    if criteriaIndex ~= nil then
        return pcall(addon.OnCriteriaEarned, addon, "CRITERIA_EARNED", achievementID, criteriaIndex, false)
    end
    return pcall(addon.ShowAchievementNotification, addon, achievementID)
end

-- Production helpers the test satellite (NotificationManager_Tests.lua) reuses.
ns.NotificationManagerHooks.TestLootEnsureAchievementAlertUI = TestLootEnsureAchievementAlertUI
ns.NotificationManagerHooks.TestLootFireAchievementAddAlert = TestLootFireAchievementAddAlert
ns.NotificationManagerHooks.TRAVELERS_LOG_PROGRESS_ICON_ATLAS = TRAVELERS_LOG_PROGRESS_ICON_ATLAS

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
    if issecretvalue and issecretvalue(displayName) then return end
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
ns.NotificationManagerHooks.VAULT_CATEGORIES = VAULT_CATEGORIES

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

---Login reminder for mail that is about to expire (a week or less left) on any tracked
---character. Reads persisted snapshots only, so alts count without opening their mailbox.
---@return boolean shown
function WarbandNexus:ShowExpiringMailReminder()
    if not self:CanShowToast("mail") then return false end
    local MS = ns.MailSnapshot
    if not (MS and MS.GetExpiringMailSummary) then return false end

    local count, soonestLeft, soonestName = MS.GetExpiringMailSummary(self)
    if not count or count < 1 or not soonestLeft or soonestLeft <= 0 then return false end

    local L = ns.L
    local timeText = soonestLeft and MS.FormatMailTimeRemaining and MS.FormatMailTimeRemaining(time() + soonestLeft)
    local action
    if timeText then
        action = string.format((L and L["MAIL_REMINDER_ACTION"]) or "You have %d mail(s) expiring, soonest in %s",
            count, timeText)
    else
        action = string.format((L and L["MAIL_REMINDER_ACTION_SIMPLE"]) or "You have %d mail(s) expiring soon", count)
    end
    -- Name the owner so an alt's inbox is actionable from the toast alone.
    local title = (L and L["MAIL_REMINDER_TITLE"]) or "Mail Expiring Soon!"
    if not (issecretvalue and issecretvalue(soonestName)) and soonestName and soonestName ~= "" then
        title = title .. " - " .. soonestName
    end

    return self:Notify("mail", title, CATEGORY_ICONS.mail, {
        action = action,
    })
end

---Vault reward available handler
function WarbandNexus:OnVaultRewardAvailable(event, data)
    if data and data.claimable == false then return end
    if not self:CanShowToast("vault") then return end

    self:Notify("vault", (ns.L and ns.L["WEEKLY_VAULT_READY"]) or "Weekly Vault Ready!", CATEGORY_ICONS.vault, {
        action = (ns.L and ns.L["UNCLAIMED_REWARDS"]) or "You have unclaimed rewards",
        categoryTitle = "",
        -- Single-line vault toast: render the message centered, larger and bright instead of the
        -- faint small-grey default (it read as barely visible).
        emphasizeAction = true,
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
