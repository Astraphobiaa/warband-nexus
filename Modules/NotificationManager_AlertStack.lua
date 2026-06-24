--[[
    Warband Nexus — toast alert stack (queue, layout geometry, dismiss/reposition).
    Loaded before NotificationManager.lua (ns.NotificationAlertStack).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local ToastChrome = ns.NotificationToastChrome
assert(ToastChrome, "NotificationAlertStack: load NotificationManager_ToastChrome.lua first")
local issecretvalue = issecretvalue

local TOAST_FADE_OUT_SEC = 0.32
local TOAST_COLLAPSE_DELAY_SEC = 0.14
local TOAST_REPOSITION_SEC = 0.38

local function NM_ApplyTextShadow(fs, strength)
    if not fs then return end
    strength = tonumber(strength) or 0.8
    fs:SetShadowColor(0, 0, 0, strength)
    if FontManager and FontManager.ApplyReadableEdge then
        FontManager:ApplyReadableEdge(fs, fs._fontCategory or "body", {})
    end
end

local AS = {}
ns.NotificationAlertStack = AS

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

-- Geometry (+15% popups). Typography uses separate scales (meta vs primary) for a balanced middle ground.
local TOAST_LAYOUT_SCALE = 1.15
local TOAST_FONT_SCALE_META = 1.0
local TOAST_FONT_SCALE_PRIMARY = 0.96
local TOAST_FONT_SCALE_PROGRESS_META = 0.94
local TOAST_FONT_SCALE_PROGRESS_PRIMARY = 0.90

local function ToastPx(value)
    return math.max(1, math.floor((tonumber(value) or 0) * TOAST_LAYOUT_SCALE + 0.5))
end

local function NM_ToastFontScaleForCategory(category, progressLane)
    if progressLane then
        if category == "small" then
            return TOAST_FONT_SCALE_PROGRESS_META
        end
        return TOAST_FONT_SCALE_PROGRESS_PRIMARY
    end
    if category == "small" then
        return TOAST_FONT_SCALE_META
    end
    if category == "title" or category == "subtitle" or category == "body" then
        return TOAST_FONT_SCALE_PRIMARY
    end
    return TOAST_FONT_SCALE_PRIMARY
end

local function NM_ToastFontSize(category, progressLane)
    local base
    if FontManager and FontManager.GetFontSize then
        base = FontManager:GetFontSize(category)
    else
        local defaults = { title = 14, small = 10, body = 12, subtitle = 12 }
        base = defaults[category] or 12
    end
    local scale = NM_ToastFontScaleForCategory(category, progressLane)
    return math.max(6, math.min(72, math.floor(base * scale + 0.5)))
end

local function NM_ApplyToastFont(fs, category, progressLane)
    if not fs or not FontManager then return end
    local fontPath = FontManager:GetFontFace()
    local fontSize = NM_ToastFontSize(category, progressLane)
    local flagOpts = {}
    if fs._colorType == "accent" then
        flagOpts.accentFill = true
    end
    local flags = FontManager:GetAAFlags(category, flagOpts)
    pcall(function()
        fs:SetFont(fontPath, fontSize, flags)
    end)
    if FontManager.ApplyReadableEdge then
        FontManager:ApplyReadableEdge(fs, category, flagOpts)
    end
end

local function NM_CreateToastFontString(parent, category, layer, colorType, progressLane)
    local fs = FontManager:CreateFontString(parent, category, layer, colorType)
    if fs then
        NM_ApplyToastFont(fs, category, progressLane)
    end
    return fs
end

-- Collection toasts: full card width. Progress lane (criteria / Traveler's Log): narrow criteria-bar sizing.
local ALERT_HEIGHT = ToastPx(64)
local ALERT_GAP = ToastPx(6)
local ALERT_SPACING = ALERT_HEIGHT + ALERT_GAP
-- Two fixed compact tiers only (no per-toast width/height drift).
-- Collectible: achievement earned, mount, pet, toy, try counter, plan reminder, vault-ready, etc.
-- Progress: criteria steps, Traveler's Log / ProgressAlertSystem payloads.
local ALERT_WIDTH_COLLECTIBLE = ToastPx(320)
local ALERT_HEIGHT_COLLECTIBLE = ToastPx(58)
local ALERT_WIDTH_PROGRESS = ToastPx(256)
local ALERT_HEIGHT_PROGRESS = ToastPx(50)
-- Legacy aliases (call sites / exports)
local ALERT_WIDTH_COMPACT = ALERT_WIDTH_COLLECTIBLE
local ALERT_HEIGHT_COMPACT = ALERT_HEIGHT_COLLECTIBLE
local ALERT_WIDTH_FIXED = ALERT_WIDTH_COLLECTIBLE
local ALERT_HEIGHT_PROGRESS_COMPACT = ALERT_HEIGHT_PROGRESS
local ALERT_HEIGHT_PROGRESS_MAX = ToastPx(92)
local ALERT_PROGRESS_ICON_SIZE = ToastPx(28)
local ALERT_PROGRESS_ICON_SLOT = ToastPx(40)
local ALERT_PRIMARY_MAX_LINES = 1
local ALERT_PROGRESS_PRIMARY_MAX_LINES = 2
local ALERT_ICON_SIZE = ToastPx(36)
local ALERT_ICON_SLOT = ToastPx(50)
local ALERT_ICON_SLOT_FULL = ToastPx(54)
local ALERT_ICON_SIZE_FULL = ToastPx(38)
local ALERT_ICON_BLING_FULL = ToastPx(52)
local ALERT_ICON_INSET_FULL = ToastPx(10)
local ACHIEVEMENT_TOAST_SHIELD_ONLY_SIZE = ToastPx(40)
local ACHIEVEMENT_SHIELD_ATLAS_POINTS = "UI-Achievement-Shield-1"
local ACHIEVEMENT_SHIELD_ATLAS_EMPTY = "UI-Achievement-Shield-NoPoints"
local CRITERIA_TOAST_FALLBACK_ICON = "Interface\\Icons\\Achievement_Quests_Completed_08"
local ACHIEVEMENT_CRITERIA_TYPE_LINKED = 8 -- criteriaType ACHIEVEMENT (sub-achievement row); wiki GetAchievementCriteriaInfo
local ALERT_PAD_LEFT = ToastPx(8)
local ALERT_PAD_RIGHT = ToastPx(10)
local ALERT_PAD_TEXT = ToastPx(6)
local ALERT_HEIGHT_TALL = ToastPx(74)
local ALERT_TEXT_LINE_GAP = ToastPx(2)
local ALERT_STACK_V_PAD = ToastPx(13)
local ALERT_STACK_V_PAD_PROGRESS = ToastPx(8)
local ALERT_HEIGHT_PROGRESS_MIN = ALERT_HEIGHT_PROGRESS
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

---Earned achievement compact lane: centered points shield only (readable, symmetric vs collectible icon+text).
---@return Texture|nil shieldTex anchor for FX metadata
local function NM_CreateAchievementShieldSlot(iconSlotCompact, points, accentRGB)
    if not iconSlotCompact then return nil end
    local numPts = tonumber(points)
    local hasPoints = numPts ~= nil and numPts > 0
    local atlas = hasPoints and ACHIEVEMENT_SHIELD_ATLAS_POINTS or ACHIEVEMENT_SHIELD_ATLAS_EMPTY

    local shieldTex = iconSlotCompact:CreateTexture(nil, "ARTWORK")
    shieldTex:SetSize(ACHIEVEMENT_TOAST_SHIELD_ONLY_SIZE, ACHIEVEMENT_TOAST_SHIELD_ONLY_SIZE)
    shieldTex:SetPoint("CENTER", iconSlotCompact, "CENTER", 0, 0)
    local ok = pcall(function()
        shieldTex:SetAtlas(atlas, false)
    end)
    if not ok then
        shieldTex:SetTexture(CRITERIA_TOAST_FALLBACK_ICON)
    end
    shieldTex:SetVertexColor(1, 1, 1, 1)
    shieldTex:SetAlpha(1)

    if hasPoints then
        local ptsFs = NM_CreateToastFontString(iconSlotCompact, "body", "OVERLAY")
        ptsFs:SetPoint("CENTER", shieldTex, "CENTER", 0, 1)
        ptsFs:SetJustifyH("CENTER")
        ptsFs:SetJustifyV("MIDDLE")
        ptsFs:SetText(tostring(numPts))
        ptsFs:SetTextColor(1, 1, 1)
        NM_ApplyTextShadow(ptsFs, 0.9)
    end

    ToastChrome.ApplyCompactIconBorder(iconSlotCompact, shieldTex, ACHIEVEMENT_TOAST_SHIELD_ONLY_SIZE, accentRGB)
    return shieldTex
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

---Fixed compact toast dimensions — exactly two tiers; no live Blizzard width probe.
local function ResolveCompactToastDimensions(laneUsesProgressLane)
    if laneUsesProgressLane then
        return ALERT_WIDTH_PROGRESS, ALERT_HEIGHT_PROGRESS, ALERT_PROGRESS_ICON_SLOT, ALERT_PROGRESS_ICON_SIZE
    end
    return ALERT_WIDTH_COLLECTIBLE, ALERT_HEIGHT_COLLECTIBLE, ALERT_ICON_SLOT, ALERT_ICON_SIZE
end

local function GetCompactToastWidth(laneUsesProgressSizing)
    return select(1, ResolveCompactToastDimensions(laneUsesProgressSizing))
end

local function GetCompactToastBaseHeight(laneUsesProgressSizing)
    local _, h = ResolveCompactToastDimensions(laneUsesProgressSizing)
    return h
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

---Unified stacks share one width and anchor X so mixed progress/collectible toasts stay flush.
local function GetStackAdjustedAnchorX(point, baseX, toastWidth, stackMaxWidth, toastLane)
    if UsesUnifiedToastLayout() then
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

-- Public API (NotificationManager.lua consumes via ns.NotificationAlertStack)
AS.TOAST_FADE_OUT_SEC = TOAST_FADE_OUT_SEC
AS.TOAST_COLLAPSE_DELAY_SEC = TOAST_COLLAPSE_DELAY_SEC
AS.TOAST_REPOSITION_SEC = TOAST_REPOSITION_SEC
AS.NOTIFICATION_MAX_VISIBLE_ALERTS = NOTIFICATION_MAX_VISIBLE_ALERTS
AS.EnqueueAlert = EnqueueAlert
AS.ToastPx = ToastPx
AS.NM_CreateToastFontString = NM_CreateToastFontString
AS.NM_ToastFontSize = NM_ToastFontSize
AS.NM_CreateAchievementShieldSlot = NM_CreateAchievementShieldSlot
AS.NM_ResolveAchievementToastPoints = NM_ResolveAchievementToastPoints
AS.FormatToastAttemptsLabel = FormatToastAttemptsLabel
AS.InferToastLane = InferToastLane
AS.ResolveToastAnchor = ResolveToastAnchor
AS.GetGrowthDirection = GetGrowthDirection
AS.GetCumulativeOffsetForNewAlert = GetCumulativeOffsetForNewAlert
AS.GetCompactToastWidth = GetCompactToastWidth
AS.GetCompactToastBaseHeight = GetCompactToastBaseHeight
AS.UsesUnifiedToastLayout = UsesUnifiedToastLayout
AS.RepositionAlerts = RepositionAlerts
AS.RequestDismissToast = RequestDismissToast
AS.ScheduleToastDismiss = ScheduleToastDismiss
AS.ALERT_WIDTH_COLLECTIBLE = ALERT_WIDTH_COLLECTIBLE
AS.ALERT_HEIGHT_COLLECTIBLE = ALERT_HEIGHT_COLLECTIBLE
AS.ALERT_HEIGHT_PROGRESS = ALERT_HEIGHT_PROGRESS
AS.ResolveCompactToastDimensions = ResolveCompactToastDimensions
AS.ALERT_WIDTH_COMPACT = ALERT_WIDTH_COMPACT
AS.ALERT_WIDTH_FIXED = ALERT_WIDTH_FIXED
AS.ALERT_WIDTH_PROGRESS = ALERT_WIDTH_PROGRESS
AS.ALERT_HEIGHT = ALERT_HEIGHT
AS.ALERT_HEIGHT_COMPACT = ALERT_HEIGHT_COMPACT
AS.ALERT_HEIGHT_TALL = ALERT_HEIGHT_TALL
AS.ALERT_HEIGHT_PROGRESS_COMPACT = ALERT_HEIGHT_PROGRESS_COMPACT
AS.ALERT_HEIGHT_PROGRESS_MAX = ALERT_HEIGHT_PROGRESS_MAX
AS.ALERT_ICON_SLOT_FULL = ALERT_ICON_SLOT_FULL
AS.ALERT_ICON_SIZE_FULL = ALERT_ICON_SIZE_FULL
AS.ALERT_ICON_INSET_FULL = ALERT_ICON_INSET_FULL
AS.ALERT_ICON_BLING_FULL = ALERT_ICON_BLING_FULL
AS.ALERT_GAP = ALERT_GAP
AS.ALERT_PAD_LEFT = ALERT_PAD_LEFT
AS.ALERT_PAD_RIGHT = ALERT_PAD_RIGHT
AS.ALERT_PAD_TEXT = ALERT_PAD_TEXT
AS.ALERT_TEXT_LINE_GAP = ALERT_TEXT_LINE_GAP
AS.ALERT_STACK_V_PAD = ALERT_STACK_V_PAD
AS.ALERT_STACK_V_PAD_PROGRESS = ALERT_STACK_V_PAD_PROGRESS
AS.ALERT_ICON_SIZE = ALERT_ICON_SIZE
AS.ALERT_ICON_SLOT = ALERT_ICON_SLOT
AS.ALERT_PROGRESS_ICON_SIZE = ALERT_PROGRESS_ICON_SIZE
AS.ALERT_PROGRESS_ICON_SLOT = ALERT_PROGRESS_ICON_SLOT
AS.ALERT_PRIMARY_MAX_LINES = ALERT_PRIMARY_MAX_LINES
AS.ALERT_PROGRESS_PRIMARY_MAX_LINES = ALERT_PROGRESS_PRIMARY_MAX_LINES
AS.CRITERIA_TOAST_FALLBACK_ICON = CRITERIA_TOAST_FALLBACK_ICON
AS.ACHIEVEMENT_CRITERIA_TYPE_LINKED = ACHIEVEMENT_CRITERIA_TYPE_LINKED
