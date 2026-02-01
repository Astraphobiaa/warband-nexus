--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Current addon version (from Constants)
local Constants = ns.Constants
local CURRENT_VERSION = Constants.ADDON_VERSION

-- Changelog for current version (manual update required)
local CHANGELOG = {
    version = "1.2.4",
    date = "2025-01-30",
    changes = {
        "CRITICAL FIX: ALL collection types now use unified system!",
        "Mount, Pet, Toy, Illusion, Title getters refactored",
        "ALL now follow same pattern: cache-first → scan if empty → show loading state",
        "Removed old 'read-only cache' behavior (was causing 'No pets found')",
        "Every collection type now triggers scan when cache empty",
        "PlansLoadingState set for ALL types (mount, pet, toy, illusion, title, achievement)",
        "Previous: UI freeze fix (v1.2.3)",
    }
}

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

---Add a notification to the queue
---@param notification table Notification data
local function QueueNotification(notification)
    table.insert(notificationQueue, notification)
end

---Process notification queue (show one at a time)
local function ProcessNotificationQueue()
    if #notificationQueue == 0 then
        return
    end
    
    -- Show first notification
    local notification = table.remove(notificationQueue, 1)
    
    if notification.type == "update" then
        WarbandNexus:ShowUpdateNotification(notification.data)
    elseif notification.type == "vault" then
        WarbandNexus:ShowVaultReminder(notification.data)
    end
    
    -- Schedule next notification (2 second delay)
    if #notificationQueue > 0 then
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

---Show update notification popup
---@param changelogData table Changelog data
function WarbandNexus:ShowUpdateNotification(changelogData)
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
    
    -- Popup frame
    local popup = CreateFrame("Frame", nil, backdrop, "BackdropTemplate")
    popup:SetSize(450, 400)
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
    popup:SetBackdropBorderColor(0.4, 0.2, 0.58, 1)
    
    -- Glow effect
    local glow = popup:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", -10, 10)
    glow:SetPoint("BOTTOMRIGHT", 10, -10)
    glow:SetColorTexture(0.6, 0.4, 0.9, 0.1)
    
    -- Logo/Icon
    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOP", 0, -20)
    logo:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title
    local title = FontManager:CreateFontString(popup, "header", "OVERLAY")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    title:SetText("|cff9966ffWarband Nexus|r")
    
    -- Version subtitle
    local versionText = FontManager:CreateFontString(popup, "body", "OVERLAY")
    versionText:SetPoint("TOP", title, "BOTTOM", 0, -5)
    versionText:SetText("Version " .. changelogData.version .. " - " .. changelogData.date)
    versionText:SetTextColor(0.6, 0.6, 0.6)
    
    -- Separator line
    local separator = popup:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 30, -140)
    separator:SetPoint("TOPRIGHT", -30, -140)
    separator:SetColorTexture(0.4, 0.2, 0.58, 0.5)
    
    -- "What's New" label
    local whatsNewLabel = FontManager:CreateFontString(popup, "title", "OVERLAY")
    whatsNewLabel:SetPoint("TOP", separator, "BOTTOM", 0, -15)
    whatsNewLabel:SetText("|cffffd700What's New|r")
    
    -- Changelog scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT", 30, -185)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Populate changelog
    local yOffset = 0
    for i, change in ipairs(changelogData.changes) do
        local bullet = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        bullet:SetPoint("TOPLEFT", 0, -yOffset)
        bullet:SetPoint("TOPRIGHT", -20, -yOffset) -- Leave space for scrollbar
        bullet:SetJustifyH("LEFT")
        bullet:SetText("|cff9966ffâ€¢|r " .. change)
        bullet:SetTextColor(0.9, 0.9, 0.9)
        
        yOffset = yOffset + bullet:GetStringHeight() + 8
    end
    
    scrollChild:SetHeight(yOffset)
    
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
    closeBtn:SetBackdropColor(0.4, 0.2, 0.58, 1)
    closeBtn:SetBackdropBorderColor(0.6, 0.4, 0.9, 1)
    
    local closeBtnText = FontManager:CreateFontString(closeBtn, "body", "OVERLAY")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText("Got it!")
    
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
        btn:SetBackdropColor(0.5, 0.3, 0.7, 1)
    end)
    
    closeBtn:SetScript("OnLeave", function(btn)
        btn:SetBackdropColor(0.4, 0.2, 0.58, 1)
    end)
    
    -- Escape key to close
    backdrop:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            closeBtn:Click()
        end
    end)
    backdrop:SetPropagateKeyboardInput(false)
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
-- Queue processing debounce timer (prevents multiple simultaneous queue processing)
local queueProcessTimer = nil

---Reposition all active alerts (when one closes, others move up)
---@param instant boolean If true, cancel all animations and reposition instantly
local function RepositionAlerts(instant)
    local alertSpacing = 98 -- Space between alerts (88px height + 10px gap)
    
    for i, alert in ipairs(WarbandNexus.activeAlerts) do
        local newYOffset = -100 - ((i - 1) * alertSpacing) -- Updated to -100 start position
        
        -- CRITICAL: Skip repositioning if alert is closing (exit animation takes priority)
        -- ALSO skip if alert is still entering (entrance animation takes priority)
        if not alert.isClosing and not alert.isEntering then
            if instant then
                -- INSTANT REPOSITION: Cancel any existing animation and snap to position
                if alert.isAnimating then
                    alert:SetScript("OnUpdate", nil)
                    alert.isAnimating = false
                end
                
                if alert.currentYOffset ~= newYOffset then
                    alert:ClearAllPoints()
                    alert:SetPoint("TOP", UIParent, "TOP", 0, newYOffset)
                    alert.currentYOffset = newYOffset
                end
            elseif alert.currentYOffset ~= newYOffset then
                -- ANIMATED REPOSITION: Smooth animation
                -- Manual reposition animation (avoid Translation affecting rotation)
                local repositionStart = GetTime()
                local repositionDuration = 0.3
                local startY = alert.currentYOffset or newYOffset
                local moveDistance = newYOffset - startY
                
                -- Stop any existing OnUpdate
                if not alert.isAnimating then
                    alert.isAnimating = true
                    
                    alert:SetScript("OnUpdate", function(self, elapsed)
                        local elapsedTime = GetTime() - repositionStart
                        local progress = math.min(1, elapsedTime / repositionDuration)
                        
                        -- Smooth easing (IN_OUT)
                        local easedProgress
                        if progress < 0.5 then
                            easedProgress = 2 * progress * progress
                        else
                            easedProgress = 1 - math.pow(-2 * progress + 2, 2) / 2
                        end
                        
                        -- Calculate current position
                        local currentY = startY + (moveDistance * easedProgress)
                        
                        -- Update position
                        self:ClearAllPoints()
                        self:SetPoint("TOP", UIParent, "TOP", 0, currentY)
                        self.currentYOffset = currentY
                        
                        -- Animation complete
                        if progress >= 1 then
                            self:SetScript("OnUpdate", nil)
                            self.isAnimating = false
                            self.currentYOffset = newYOffset
                        end
                    end)
                end
            end
        end
        
        alert.alertIndex = i
    end
end

---Remove alert and process queue
---@param alert Frame The alert frame to remove
local function RemoveAlert(alert)
    if not alert then 
        return
    end
    
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
    
    -- Find and remove from active alerts
    for i, a in ipairs(WarbandNexus.activeAlerts) do
        if a == alert then
            table.remove(WarbandNexus.activeAlerts, i)
            break
        end
    end
    
    alert:Hide()
    alert:SetParent(nil)
    
    -- FIRST: Reposition remaining alerts to fill the gap
    -- Delay slightly to ensure removal is complete
    C_Timer.After(0.05, function()
        if WarbandNexus and WarbandNexus.activeAlerts and #WarbandNexus.activeAlerts > 0 then
            RepositionAlerts()
        end
    end)
    
    -- THEN: Process queue with debounce (prevents multiple simultaneous dismissals from spawning too many alerts)
    if #WarbandNexus.alertQueue > 0 then
        -- Cancel any existing queue timer
        if queueProcessTimer then
            queueProcessTimer:Cancel()
        end
        
        -- Start new debounced timer (shorter delay for better responsiveness)
        queueProcessTimer = C_Timer.After(0.35, function()
            queueProcessTimer = nil
            
            -- Process queue: show ONE alert, then recursively process if more slots available
            -- This prevents multiple instant repositions from conflicting
            local function ProcessNextInQueue()
                if #WarbandNexus.alertQueue > 0 and #WarbandNexus.activeAlerts < 3 then
                    local nextConfig = table.remove(WarbandNexus.alertQueue, 1)
                    
                    if WarbandNexus and WarbandNexus.ShowModalNotification then
                        WarbandNexus:ShowModalNotification(nextConfig)
                        
                        -- If more slots available, process next alert after entrance animation
                        if #WarbandNexus.alertQueue > 0 and #WarbandNexus.activeAlerts < 3 then
                            C_Timer.After(0.15, ProcessNextInQueue)
                        end
                    end
                end
            end
            
            ProcessNextInQueue()
        end)
    end
end

---Show an achievement-style notification with all visual effects (WoW AlertFrame style)
---@param config table Configuration: {icon, title, message, subtitle, category, glowAtlas}
function WarbandNexus:ShowModalNotification(config)
    -- Queue system: max 3 alerts visible at once
    if #self.activeAlerts >= 3 then
        table.insert(self.alertQueue, config)
        return
    end
    
    -- Default values
    config = config or {}
    local iconTexture = config.iconFileID or config.icon or "Interface\\Icons\\Achievement_Quests_Completed_08"
    local iconAtlas = config.iconAtlas or nil
    
    -- NEW LAYOUT SYSTEM
    local itemName = config.itemName or config.title or "Notification"  -- Title (big, red)
    local actionText = config.action or config.message or ""            -- Subtitle (small, gray)
    local categoryText = config.category or nil  -- Optional, only for special cases (Renown)
    
    -- BACKWARD COMPATIBILITY
    local titleText = itemName
    local messageText = actionText
    local subtitleText = config.subtitle or ""
    
    local playSound = config.playSound ~= false
    local titleColor = config.titleColor or GetThemeAccentColor()
    local glowAtlas = config.glowAtlas or "communitiesfinder_card_highlight"
    local autoDismissDelay = config.autoDismiss or 10
    
    -- Calculate alert position based on current active alerts (WoW AlertFrame style)
    -- Find the first available position slot (1, 2, or 3)
    -- If position 1 is free, use it. Otherwise use the next available.
    local usedPositions = {}
    for _, alert in ipairs(self.activeAlerts) do
        if alert.alertIndex then
            usedPositions[alert.alertIndex] = true
        end
    end
    
    -- Find first free position
    local alertIndex = 1
    while usedPositions[alertIndex] and alertIndex <= 3 do
        alertIndex = alertIndex + 1
    end
    
    local alertSpacing = 98
    local yOffset = -100 - ((alertIndex - 1) * alertSpacing)
    
    -- WoW Achievement-style popup frame (exact WoW dimensions: 400x88)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(400, 88) -- WoW standard achievement size
    popup:SetFrameStrata("HIGH")
    popup:SetFrameLevel(1000)
    popup:EnableMouse(true)
    popup:SetMouseClickEnabled(true)
    
    popup:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        tile = false,
        edgeSize = 1,  -- Reduced from 2 for thinner border
        insets = { left = 1, right = 1, top = 1, bottom = 1 },  -- Adjusted insets to match
    })
    popup:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    popup:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    
    -- Track this alert
    popup.currentYOffset = yOffset
    popup.alertIndex = alertIndex
    
    -- Add to active alerts array
    table.insert(self.activeAlerts, popup)
    
    -- CRITICAL: Mark as entering BEFORE repositioning
    -- This ensures RepositionAlerts skips this new alert
    popup.isEntering = true
    
    -- CRITICAL: Reposition existing alerts BEFORE starting entrance animation
    -- This pushes existing alerts down to make room for the new one at -100
    -- Use INSTANT reposition to avoid animation conflicts
    RepositionAlerts(true) -- instant=true to cancel any ongoing animations
    
    -- Popup dimensions for calculations
    local popupWidth = 400
    local popupHeight = 88
    local ringSize = 180 -- Larger rings for more visibility
    
    -- === ICON (LEFT SIDE - Achievement style) ===
    local iconSize = 42 -- Icon size: 36 + 6px = 42px
    local icon = popup:CreateTexture(nil, "ARTWORK", nil, 0) -- ARTWORK layer, sublevel 0
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", popup, "LEFT", 14, 0) -- Centered positioning
    
    -- Handle atlas, numeric IDs, and texture paths
    if iconAtlas and iconAtlas ~= "" then
        -- Use atlas (no TexCoord needed)
        icon:SetAtlas(iconAtlas)
    else
        -- Use texture with standard crop
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if type(iconTexture) == "number" then
            icon:SetTexture(iconTexture)
        elseif iconTexture and iconTexture ~= "" then
            local cleanPath = iconTexture:gsub("\\", "/")
            icon:SetTexture(cleanPath)
        else
            icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
        end
    end
    
    -- === RING GLOW OBJECTS (USER SPECIFIED POSITIONS) ===
    -- Symmetric positioning: left ring behind icon, right ring at same distance from right edge
    local iconCenterFromLeft = 14 + (iconSize / 2) -- Icon is 14px from left + half icon size (42/2) = 35px
    
    -- Ring 1: Left side - behind the icon
    local ring1 = popup:CreateTexture(nil, "BACKGROUND", nil, -3) -- Behind everything
    ring1:SetSize(ringSize, ringSize)
    ring1:SetPoint("CENTER", icon, "CENTER", 0, 0) -- Exact center on icon
    ring1:SetTexture("Interface\\Cooldown\\star4")
    ring1:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    ring1:SetBlendMode("ADD")
    
    -- Ring 2: Right side - symmetric position from right edge
    local ring2 = popup:CreateTexture(nil, "BACKGROUND", nil, -3) -- Behind everything
    ring2:SetSize(ringSize, ringSize)
    ring2:SetPoint("CENTER", popup, "RIGHT", -iconCenterFromLeft, 0) -- Same distance from right edge as left ring from left edge
    ring2:SetTexture("Interface\\Cooldown\\star4")
    ring2:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
    ring2:SetBlendMode("ADD")
    
    -- === BORDER GLOW (Configurable atlas) ===
    -- Different atlases need different positioning
    
    local borderGlow = nil -- Declare variable first
    
    -- Special case: If glowAtlas has "TopBottom" prefix, create both top and bottom lines
    if glowAtlas:find("TopBottom:") then
        -- Extract the base atlas name (e.g., "TopBottom:UI-Frame-DastardlyDuos-Line")
        local baseAtlas = glowAtlas:gsub("TopBottom:", "")
        
        -- Top line - positioned to align glow with border (not popup edge)
        local topLine = popup:CreateTexture(nil, "OVERLAY", nil, 5)
        topLine:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 2)  -- Reduced offset for slight separation
        topLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 2)
        topLine:SetHeight(56)  -- Increased for more visible glow
        topLine:SetAtlas(baseAtlas .. "-Top", true)
        topLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        topLine:SetBlendMode("ADD")
        topLine:SetAlpha(1.0)  -- Full opacity
        
        -- Bottom line - positioned to align glow with border (not popup edge)
        local bottomLine = popup:CreateTexture(nil, "OVERLAY", nil, 5)
        bottomLine:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 0, -2)  -- Reduced offset for slight separation
        bottomLine:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, -2)
        bottomLine:SetHeight(56)  -- Increased for more visible glow
        bottomLine:SetAtlas(baseAtlas .. "-bottom", true)  -- lowercase "bottom" in atlas name
        bottomLine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        bottomLine:SetBlendMode("ADD")
        bottomLine:SetAlpha(1.0)  -- Full opacity
        
        -- Breathing animation for both lines
        local topGlowAg = popup:CreateAnimationGroup()
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
        
        local bottomGlowAg = popup:CreateAnimationGroup()
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
        
        -- borderGlow remains nil for TopBottom case
    else
        -- Create single borderGlow for non-TopBottom cases
        borderGlow = popup:CreateTexture(nil, "OVERLAY", nil, 5)
        
        -- Position based on atlas type
        if glowAtlas:find("Line%-Top") then
            -- Top line only - align with border
            borderGlow:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 4)
            borderGlow:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 4)
            borderGlow:SetHeight(40)  -- Focused on border area
        elseif glowAtlas:find("Line%-Bottom") or glowAtlas:find("Line%-bottom") then
            -- Bottom line only - align with border
            borderGlow:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 0, -4)
            borderGlow:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, -4)
            borderGlow:SetHeight(40)  -- Focused on border area
        elseif glowAtlas:find("DastardlyDuos%-Bar") then
            -- Duos Bar has padding, pull inward slightly
            borderGlow:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
            borderGlow:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -8, 8)
        else
            -- Full frame glow - cover entire popup
            borderGlow:SetAllPoints(popup)
        end
        
        borderGlow:SetAtlas(glowAtlas, true)
        borderGlow:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1)
        borderGlow:SetBlendMode("ADD")
        borderGlow:SetAlpha(0.9)
    end
    
    -- === STARBURST EFFECT (Small, subtle) ===
    local starburst = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
    starburst:SetSize(popupWidth * 0.8, popupHeight * 1.5) -- More compact, frame-fitting
    starburst:SetPoint("CENTER", popup, "CENTER", 0, 0)
    starburst:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
    starburst:SetTexCoord(0, 0.78125, 0, 0.78125)
    starburst:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0)
    starburst:SetBlendMode("ADD")
    
    -- === EDGE SHINE (Subtle top highlight) ===
    local edgeShine = popup:CreateTexture(nil, "OVERLAY", nil, 6)
    edgeShine:SetHeight(1)  -- Reduced from 3 to 1 for subtle effect
    edgeShine:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1)
    edgeShine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1)
    edgeShine:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    edgeShine:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.3) -- Reduced alpha from 0.5
    edgeShine:SetBlendMode("ADD")
    
    -- Icon glow frame (icon already created above with rings) - DISABLED
    -- local iconFrame = popup:CreateTexture(nil, "OVERLAY", nil, 7)
    -- iconFrame:SetSize(iconSize * 2.2, iconSize * 2.2)
    -- iconFrame:SetPoint("CENTER", icon, "CENTER", 0, 0)
    -- iconFrame:SetAtlas("collections-upgradeglow")
    -- iconFrame:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.8)
    -- iconFrame:SetBlendMode("ADD")
    
    -- Icon bling border (overlays on top of icon for clean border)
    local iconBling = popup:CreateTexture(nil, "OVERLAY", nil, 7)
    iconBling:SetSize(64, 64) -- Frame size: 56 + 8px = 64px, overlays on 42px icon
    iconBling:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBling:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    iconBling:SetTexCoord(0, 0.5625, 0, 0.5625)
    iconBling:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1.0) -- Full opacity always
    iconBling:SetBlendMode("BLEND") -- BLEND mode so frame border shows clearly over icon
    
    -- === CONTENT (RIGHT SIDE - CENTERED IN TEXT AREA) ===
    
    -- Text area dimensions
    local popupWidth = 400
    local popupHeight = 88
    local iconRight = 14 + 42 + 12  -- 68px (icon left + width + gap)
    local textAreaWidth = popupWidth - iconRight - 10  -- 322px
    -- Center text in the popup window (aligned with center ornament)
    local textCenterX = popupWidth / 2  -- 200px from left (popup center)
    
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
    
    -- Start from center, adjusted to align with decorative borders (not just geometric center)
    -- The visual center is slightly lower due to top decorative elements
    local startY = (totalHeight / 2) - 6  -- -6 for visual balance with ornaments
    
    -- LINE 1: Category (optional)
    if showCategory then
        local category = FontManager:CreateFontString(popup, "small", "OVERLAY")
        category:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        category:SetWidth(textAreaWidth - 20)
        category:SetJustifyH("CENTER")
        category:SetText("|cffaaaaaa" .. categoryText .. "|r")
        category:SetWordWrap(false)
        category:SetShadowOffset(1, -1)
        category:SetShadowColor(0, 0, 0, 0.8)
        startY = startY - smallFontHeight - lineSpacing
    end
    
    -- LINE 2: Title (BIG, RED, NORMAL FONT)
    if showTitle then
        local title = FontManager:CreateFontString(popup, "title", "OVERLAY")
        title:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        title:SetWidth(textAreaWidth - 20)
        title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
        
        -- Normal font without outline flags for clean rendering
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 0.9)
    
    local titleGradient = string.format("|cff%02x%02x%02x%s|r",
            math.floor(math.min(255, titleColor[1]*255*1.4)),
            math.floor(math.min(255, titleColor[2]*255*1.4)),
            math.floor(math.min(255, titleColor[3]*255*1.4)),
        titleText)
    title:SetText(titleGradient)
    
        startY = startY - largeFontHeight - lineSpacing
    end
    
    -- LINE 3: Subtitle (MEDIUM SIZE, NORMAL FONT)
    if showSubtitle then
        local subtitle = FontManager:CreateFontString(popup, "body", "OVERLAY")
        subtitle:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        subtitle:SetWidth(textAreaWidth - 20)
        subtitle:SetJustifyH("CENTER")
        
        -- Normal font without outline for clean rendering
        subtitle:SetText("|cffffffff" .. messageText .. "|r")  -- White text
        subtitle:SetWordWrap(true)
        subtitle:SetMaxLines(2)
        subtitle:SetShadowOffset(1, -1)
        subtitle:SetShadowColor(0, 0, 0, 0.6)
    end
    
    -- Legacy subtitle support
    if not showSubtitle and subtitleText and subtitleText ~= "" then
        local legacySub = FontManager:CreateFontString(popup, "body", "OVERLAY")
        legacySub:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        legacySub:SetWidth(textAreaWidth - 20)
        legacySub:SetJustifyH("CENTER")
        
        -- Normal font without outline
        legacySub:SetText("|cffffffff" .. subtitleText .. "|r")  -- White text
        legacySub:SetWordWrap(true)
        legacySub:SetMaxLines(2)
        legacySub:SetShadowOffset(1, -1)
        legacySub:SetShadowColor(0, 0, 0, 0.6)
    end
    
    -- === CIRCULAR PROGRESS TIMER (bottom-right corner) ===
    local timerSize = 24
    local timerFrame = CreateFrame("Frame", nil, popup)
    timerFrame:SetSize(timerSize, timerSize)
    timerFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -6, 6)
    
    -- Timer spinner (WoW naval map glow trails)
    local timerSpinner = timerFrame:CreateTexture(nil, "OVERLAY")
    timerSpinner:SetAllPoints()
    timerSpinner:SetAtlas("NavalMap-CircleGlowTrails")
    timerSpinner:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 1.0)
    timerSpinner:SetBlendMode("ADD")
    
    -- Click anywhere to dismiss
    popup:SetScript("OnMouseDown", function(self, button)
        if self.isClosing then return end
        self.isClosing = true
        
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
    popup:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(
            math.min(1, titleColor[1]*1.3),
            math.min(1, titleColor[2]*1.3),
            math.min(1, titleColor[3]*1.3),
            1
        )
    end)
    
    popup:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(titleColor[1], titleColor[2], titleColor[3], 1)
    end)
    
    popup.isClosing = false
    
    -- === PLAY SOUND ===
    if playSound then
        PlaySound(44295) -- SOUNDKIT.UI_EPICACHIEVEMENTUNLOCKED
    end
    
    -- === ANIMATIONS (WoW-STYLE SLIDE DOWN) ===
    
    -- Each alert slides into its OWN position (not always top)
    local startYOffset = yOffset + 50 -- Start 50px above target position
    local finalYOffset = yOffset -- Slide to its designated position
    
    popup:SetAlpha(0)
    popup:SetPoint("TOP", UIParent, "TOP", 0, startYOffset)
    popup.currentYOffset = startYOffset
    popup:Show()
    
    -- Note: isEntering was already set to true before RepositionAlerts was called
    
    -- Manual slide animation using OnUpdate (more reliable than Translation)
    local slideStartTime = GetTime()
    local slideDuration = 0.4
    local slideDistance = finalYOffset - startYOffset -- How far to move (negative = down)
    
    local frameCount = 0
    popup:SetScript("OnUpdate", function(self, elapsed)
        local elapsedTime = GetTime() - slideStartTime
        local progress = math.min(1, elapsedTime / slideDuration)
        
        -- Smooth easing (OUT)
        local easedProgress = 1 - math.pow(1 - progress, 3)
        
        -- Calculate current position
        local currentY = startYOffset + (slideDistance * easedProgress)
        
        -- Fade in
        self:SetAlpha(easedProgress)
        
        -- Update position
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "TOP", 0, currentY)
        self.currentYOffset = currentY
        
        -- Animation complete
        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            self.currentYOffset = finalYOffset
            popup.isEntering = false -- Clear entering flag
            
            -- Start visual effects
            -- STARBURST: Achievement-style burst effect
            local burstAg = popup:CreateAnimationGroup()
            
            starburst:SetAlpha(0)
            local burstScale = burstAg:CreateAnimation("Scale")
            burstScale:SetTarget(starburst)
            burstScale:SetOrigin("CENTER", 0, 0)
        burstScale:SetScale(1.5, 1.5)
            burstScale:SetDuration(0.4)
            burstScale:SetSmoothing("OUT")
            
            local burstFadeIn = burstAg:CreateAnimation("Alpha")
            burstFadeIn:SetTarget(starburst)
            burstFadeIn:SetFromAlpha(0)
            burstFadeIn:SetToAlpha(0.9)
            burstFadeIn:SetDuration(0.15)
            
            local burstFadeOut = burstAg:CreateAnimation("Alpha")
            burstFadeOut:SetTarget(starburst)
            burstFadeOut:SetFromAlpha(0.9)
            burstFadeOut:SetToAlpha(0)
            burstFadeOut:SetDuration(0.5)
            burstFadeOut:SetStartDelay(0.2)
            
            burstAg:Play()
            
        -- ROTATING RINGS: Synchronized rotation
        ring1:SetAlpha(1.0)
            local rotateAg1 = popup:CreateAnimationGroup()
            rotateAg1:SetLooping("REPEAT")
            
            local rotate1 = rotateAg1:CreateAnimation("Rotation")
            rotate1:SetTarget(ring1)
            rotate1:SetOrigin("CENTER", 0, 0)
            rotate1:SetDegrees(360)
        rotate1:SetDuration(6)
            
            rotateAg1:Play()
            
        ring2:SetAlpha(1.0)
            local rotateAg2 = popup:CreateAnimationGroup()
            rotateAg2:SetLooping("REPEAT")
            
            local rotate2 = rotateAg2:CreateAnimation("Rotation")
            rotate2:SetTarget(ring2)
            rotate2:SetOrigin("CENTER", 0, 0)
            rotate2:SetDegrees(-360)
        rotate2:SetDuration(6)
            
            rotateAg2:Play()
        
        -- BREATHING GLOW: Pulsing border glow (single texture, skip if TopBottom already animated)
        if borderGlow then
            local glowAg = popup:CreateAnimationGroup()
            glowAg:SetLooping("REPEAT")
            
            local glowIn = glowAg:CreateAnimation("Alpha")
            glowIn:SetTarget(borderGlow)
            glowIn:SetFromAlpha(0.7)
            glowIn:SetToAlpha(1.0)
            glowIn:SetDuration(1.2)
            glowIn:SetSmoothing("IN_OUT")
            
            local glowOut = glowAg:CreateAnimation("Alpha")
            glowOut:SetTarget(borderGlow)
            glowOut:SetFromAlpha(1.0)
            glowOut:SetToAlpha(0.7)
            glowOut:SetDuration(1.2)
            glowOut:SetSmoothing("IN_OUT")
            glowOut:SetStartDelay(1.2)
            
            glowAg:Play()
        end
        
        -- EDGE SHINE: Top edge highlight pulse
        local shineAg = popup:CreateAnimationGroup()
        local shineIn = shineAg:CreateAnimation("Alpha")
        shineIn:SetTarget(edgeShine)
        shineIn:SetFromAlpha(0.5)
        shineIn:SetToAlpha(0.9)
        shineIn:SetDuration(0.3)
        shineIn:SetStartDelay(0.2)
        
        local shineOut = shineAg:CreateAnimation("Alpha")
        shineOut:SetTarget(edgeShine)
        shineOut:SetFromAlpha(0.9)
        shineOut:SetToAlpha(0.5)
        shineOut:SetDuration(0.4)
        shineOut:SetStartDelay(0.5)
        
        shineAg:Play()
        
        -- ICON BLING: No animation, always full opacity
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
            if not popup or not popup:IsShown() or popup.isClosing then
                return 
            end
            
            popup.isClosing = true
            
            -- Stop timer animations (if still running)
            if popup.timerAg then
                popup.timerAg:Stop()
            end
            if popup.timerRotateAg then
                popup.timerRotateAg:Stop()
            end
            
            -- Stop any existing OnUpdate
            popup:SetScript("OnUpdate", nil)
            
            -- Fade out and slide up animation (manual)
            local exitStartTime = GetTime()
            local exitDuration = 0.5
            local exitStartY = popup.currentYOffset or finalYOffset
            local exitEndY = exitStartY - 30 -- Slide up 30px
            
            popup:SetScript("OnUpdate", function(self, elapsed)
                local elapsedTime = GetTime() - exitStartTime
                local progress = math.min(1, elapsedTime / exitDuration)
                
                -- Smooth easing (IN)
                local easedProgress = math.pow(progress, 3)
                
                -- Fade out
                self:SetAlpha(1 - easedProgress)
                
                -- Slide up
                local currentY = exitStartY + ((exitEndY - exitStartY) * easedProgress)
                self:ClearAllPoints()
                self:SetPoint("TOP", UIParent, "TOP", 0, currentY)
                
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
    GENERIC TOAST NOTIFICATION SYSTEM (WITH STACKING)
============================================================================]]

---Show a generic toast notification (simplified wrapper for ShowModalNotification)
---@param config table Configuration: {icon, title, message, color, autoDismiss, onClose}
---@deprecated Use ShowModalNotification directly for better performance
function WarbandNexus:ShowToastNotification(config)
    -- Direct passthrough to ShowModalNotification
    -- This wrapper exists only for backward compatibility
    config = config or {}
    
    -- Default to TopBottom glow if not specified
    if not config.glowAtlas then
        config.glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line"
    end
    
    self:ShowModalNotification(config)
end

--[[============================================================================
    VAULT REMINDER
============================================================================]]

---Check if player has unclaimed vault rewards
---@return boolean hasRewards
function WarbandNexus:HasUnclaimedVaultRewards()
    -- Check if API is available
    if not C_WeeklyRewards or not C_WeeklyRewards.HasAvailableRewards then
        return false
    end
    
    -- Check for rewards
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    return hasRewards
end

---Show vault reminder popup (simplified wrapper)
---@param data table Vault data
---@deprecated Use SendMessage("WN_VAULT_REWARD_AVAILABLE") instead
function WarbandNexus:ShowVaultReminder(data)
    -- Send vault reward event
    self:SendMessage("WN_VAULT_REWARD_AVAILABLE", data or {})
end

--[[============================================================================
    NOTIFICATION SYSTEM INITIALIZATION
============================================================================]]

---Check and queue notifications on login
function WarbandNexus:CheckNotificationsOnLogin()
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    local notifs = self.db.profile.notifications
    
    -- Check if notifications are enabled
    if not notifs.enabled then
        return
    end
    
    -- 1. Check for new version
    if notifs.showUpdateNotes and self:IsNewVersion() then
        QueueNotification({
            type = "update",
            data = CHANGELOG
        })
    end
    
    -- 2. Check for vault rewards (no extra delay - already delayed by Core.lua)
    if notifs.showVaultReminder then
        -- Small delay to ensure C_WeeklyRewards API is stable
        C_Timer.After(0.5, function()
            if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
                local hasRewards = C_WeeklyRewards.HasAvailableRewards()
                if hasRewards then
                    QueueNotification({
                        type = "vault",
                        data = {}
                    })
                end
            end
        end)
    end
    
    -- Process queue (delayed by 2 seconds to allow all checks to complete)
    if #notificationQueue > 0 then
        C_Timer.After(2, ProcessNotificationQueue)
    else
        -- Check again after all checks complete
        C_Timer.After(3, function()
            if #notificationQueue > 0 then
                ProcessNotificationQueue()
            end
        end)
    end
end

---Export current version
function WarbandNexus:GetAddonVersion()
    return CURRENT_VERSION
end

--[[============================================================================
    EVENT-DRIVEN NOTIFICATION SYSTEM
    Central event listener for all notification types
============================================================================]]

---Initialize event-driven notification system
function WarbandNexus:InitializeNotificationListeners()
    -- Register for custom notification events
    self:RegisterMessage("WN_SHOW_NOTIFICATION", "OnShowNotification")
    self:RegisterMessage("WN_COLLECTIBLE_OBTAINED", "OnCollectibleObtained")
    self:RegisterMessage("WN_PLAN_COMPLETED", "OnPlanCompleted")
    self:RegisterMessage("WN_VAULT_CHECKPOINT_COMPLETED", "OnVaultCheckpointCompleted")
    self:RegisterMessage("WN_VAULT_SLOT_COMPLETED", "OnVaultSlotCompleted")
    self:RegisterMessage("WN_VAULT_PLAN_COMPLETED", "OnVaultPlanCompleted")
    self:RegisterMessage("WN_QUEST_COMPLETED", "OnQuestCompleted")
    self:RegisterMessage("WN_REPUTATION_GAINED", "OnReputationGained")
    self:RegisterMessage("WN_VAULT_REWARD_AVAILABLE", "OnVaultRewardAvailable")
end

---Generic notification handler
---@param event string Event name
---@param payload table Notification payload
function WarbandNexus:OnShowNotification(event, payload)
    if not payload or not payload.data then return end
    
    -- Direct passthrough to ShowModalNotification
    self:ShowModalNotification(payload.data)
end

---Collectible obtained handler (mount/pet/toy)
---@param event string Event name
---@param data table {type, id, name, icon}
function WarbandNexus:OnCollectibleObtained(event, data)
    if not data or not data.type or not data.name then return end
    
    -- Check if loot notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
        return
    end
    
    -- Icon mapping for collectible types
    local typeIcons = {
        mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
        pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
        toy = "Interface\\Icons\\INV_Misc_Toy_07",
        illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
    }
    
    -- Action text mapping
    local actionTexts = {
        mount = "You have collected a mount",
        pet = "You have collected a battle pet",
        toy = "You have collected a toy",
        illusion = "You have collected an illusion",
    }
    
    local icon = data.icon or typeIcons[data.type] or "Interface\\Icons\\INV_Misc_QuestionMark"
    local actionText = actionTexts[data.type] or "You have collected"
    
    self:ShowModalNotification({
        icon = icon,
        itemName = data.name,
        action = actionText,
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Plan completed handler
---@param event string Event name
---@param data table {planType, name, icon}
function WarbandNexus:OnPlanCompleted(event, data)
    if not data or not data.name then return end
    
    -- Icon mapping for plan types
    local planTypeIcons = {
        mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
        pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
        toy = "Interface\\Icons\\INV_Misc_Toy_07",
        achievement = "Interface\\Icons\\Achievement_Quests_Completed_08",
        illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
        title = "Interface\\Icons\\INV_Scroll_11",
        recipe = "Interface\\Icons\\INV_Scroll_08",
        custom = "Interface\\Icons\\INV_Misc_Note_06",
    }
    
    local icon = data.icon or planTypeIcons[data.planType] or "Interface\\Icons\\INV_Misc_Note_06"
    
    self:ShowModalNotification({
        icon = icon,
        itemName = data.name,
        action = "You have completed a plan",
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Vault checkpoint completed handler (individual progress gain)
---@param event string Event name
---@param data table {characterName, category, progress}
function WarbandNexus:OnVaultCheckpointCompleted(event, data)
    if not data or not data.characterName or not data.category or not data.progress then return end
    
    local categoryNames = {
        dungeon = "Dungeon",
        raid = "Raid",
        world = "World"
    }
    
    local categoryAtlas = {
        dungeon = "questlog-questtypeicon-heroic",
        raid = "questlog-questtypeicon-raid",
        world = "questlog-questtypeicon-Delves"
    }
    
    local categoryName = categoryNames[data.category] or "Activity"
    local atlas = categoryAtlas[data.category] or "greatVault-whole-normal"
    
    -- Determine slot context (1/1, 2/4, 3/4, etc.)
    local slotThresholds = {
        dungeon = {1, 4, 8},
        raid = {2, 4, 6},
        world = {2, 4, 8}
    }
    
    local thresholds = slotThresholds[data.category] or {1, 4, 8}
    local currentThreshold = 0
    for _, threshold in ipairs(thresholds) do
        if data.progress <= threshold then
            currentThreshold = threshold
            break
        end
    end
    
    -- If progress exceeds all thresholds, use the last one
    if currentThreshold == 0 then
        currentThreshold = thresholds[#thresholds]
    end
    
    local progressText = string.format("%d/%d Progress", data.progress, currentThreshold)
    
    self:ShowModalNotification({
        iconAtlas = atlas,
        itemName = categoryName .. " - " .. data.characterName,
        action = progressText,
        autoDismiss = 5,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Vault slot completed handler
---@param event string Event name
---@param data table {characterName, category, slotIndex, threshold}
function WarbandNexus:OnVaultSlotCompleted(event, data)
    if not data or not data.characterName or not data.category then return end
    
    local categoryNames = {
        dungeon = "Dungeon",
        raid = "Raid",
        world = "World"
    }
    
    local categoryAtlas = {
        dungeon = "questlog-questtypeicon-heroic",
        raid = "questlog-questtypeicon-raid",
        world = "questlog-questtypeicon-Delves"
    }
    
    local categoryName = categoryNames[data.category] or "Activity"
    local atlas = categoryAtlas[data.category] or "greatVault-whole-normal"
    local threshold = data.threshold or 0
    
    local progressText = string.format("%d/%d Progress Completed", threshold, threshold)
    
    self:ShowModalNotification({
        iconAtlas = atlas,
        itemName = categoryName .. " - " .. data.characterName,
        action = progressText,
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Vault plan fully completed handler
---@param event string Event name
---@param data table {characterName}
function WarbandNexus:OnVaultPlanCompleted(event, data)
    if not data or not data.characterName then return end
    
    self:ShowModalNotification({
        iconAtlas = "greatVault-whole-normal",
        itemName = "Weekly Vault Plan - " .. data.characterName,
        action = "All Slots Complete!",
        autoDismiss = 15,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Quest completed handler
---@param event string Event name
---@param data table {characterName, category, questTitle}
function WarbandNexus:OnQuestCompleted(event, data)
    if not data or not data.characterName or not data.questTitle then return end
    
    local categoryInfo = {
        dailyQuests = {name = "Daily Quest", atlas = "questlog-questtypeicon-heroic"},
        worldQuests = {name = "World Quest", atlas = "questlog-questtypeicon-Delves"},
        weeklyQuests = {name = "Weekly Quest", atlas = "questlog-questtypeicon-raid"},
        specialAssignments = {name = "Special Assignment", atlas = "questlog-questtypeicon-heroic"},
        delves = {name = "Delve", atlas = "questlog-questtypeicon-Delves"}
    }
    
    local catData = categoryInfo[data.category] or {name = "Quest", atlas = "questlog-questtypeicon-heroic"}
    
    self:ShowModalNotification({
        iconAtlas = catData.atlas,
        itemName = catData.name .. " - " .. data.characterName,
        action = data.questTitle .. " Completed",
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Reputation gained handler (Renown/Friendship/Standard reputation)
---@param event string Event name
---@param data table {factionID, factionName, oldLevel, newLevel, isRenown, isFriendship, isStandard, reactionName, texture}
function WarbandNexus:OnReputationGained(event, data)
    if not data or not data.factionName then return end
    
    -- Check if reputation notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
        return
    end
    
    -- Format the level text based on reputation type
    local levelText
    if data.isRenown then
        levelText = "Renown " .. data.newLevel
    elseif data.isFriendship then
        levelText = "Friendship " .. data.newLevel
    elseif data.isStandard then
        levelText = data.reactionName or ("Level " .. data.newLevel)
    else
        levelText = "Level " .. data.newLevel
    end
    
    -- Get icon (use faction texture or default reputation icon)
    local icon = "Interface\\Icons\\Achievement_Reputation_01"  -- Default reputation icon
    
    -- Try to use faction texture if available
    if data.texture then
        if type(data.texture) == "number" then
            icon = data.texture
        elseif type(data.texture) == "string" and data.texture ~= "" then
            -- Use texture path if it's a valid string
            icon = data.texture
        end
    end
    
    self:ShowModalNotification({
        icon = icon,
        itemName = data.factionName,
        action = levelText,
        autoDismiss = 8,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
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
    
    self:ShowModalNotification({
        icon = "Interface\\Icons\\achievement_guildperk_bountifulbags",
        itemName = "Weekly Vault Ready!",
        action = "You have unclaimed rewards",
        autoDismiss = 12,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

--[[============================================================================
    LOOT NOTIFICATIONS (MOUNT/PET/TOY)
============================================================================]]

---Show loot notification toast (mount/pet/toy)
---Uses generic toast notification system for consistent style
---@param itemID number Item ID (or mount/pet ID)
---Show loot notification (simplified wrapper with icon resolution)
---@param itemID number Item ID
---@param itemLink string Item link
---@param itemName string Item name
---@param collectionType string Type: "Mount", "Pet", or "Toy"
---@param iconOverride number|nil Optional icon override
---@deprecated Use ShowModalNotification directly after resolving icon
function WarbandNexus:ShowLootNotification(itemID, itemLink, itemName, collectionType, iconOverride)
    -- Check if loot notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
        return
    end
    
    -- Get item icon (use override if provided, or fetch from API, or use default)
    local icon = iconOverride
    
    if not icon then
        -- Try to get icon from game APIs
        local apiIcon
        if collectionType == "Mount" then
            apiIcon = select(3, C_MountJournal.GetMountInfoByID(itemID))
        elseif collectionType == "Pet" then
            apiIcon = select(2, C_PetJournal.GetPetInfoBySpeciesID(itemID))
        else
            apiIcon = select(10, GetItemInfo(itemID))
        end
        
        -- Use API icon or fallback to default
        icon = apiIcon or ({
            Mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
            Pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
            Toy = "Interface\\Icons\\INV_Misc_Toy_07",
        })[collectionType] or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    
    -- Build action text based on collection type
    local actionTexts = {
        Mount = "You have collected a mount",
        Pet = "You have collected a battle pet",
        Toy = "You have collected a toy",
        Title = "You have earned a new title",
        Recipe = "You have learned a recipe",
        Illusion = "You have collected an illusion",
    }
    local actionText = actionTexts[collectionType] or "You have collected"
    
    -- Direct call to ShowModalNotification with new layout (NO CATEGORY!)
    self:ShowModalNotification({
        icon = icon,
        itemName = itemName,          -- Title (big, red)
        action = actionText,          -- Subtitle (small, gray)
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

---Initialize loot notification system
function WarbandNexus:InitializeLootNotifications()
    -- Initialize event-driven notification system
    self:InitializeNotificationListeners()
    
    -- CollectionService handles collection detection
    -- NotificationManager only provides display functions
end

---Show collectible toast notification (simplified wrapper)
---@param data table {type, name, icon, id} from CollectionService
---@deprecated Use ShowLootNotification or ShowModalNotification directly
function WarbandNexus:ShowCollectibleToast(data)
    if not data or not data.type or not data.name then return end
    
    -- Capitalize type for display
    local typeCapitalized = data.type:sub(1,1):upper() .. data.type:sub(2)
    
    -- Direct call to ShowLootNotification (which calls ShowModalNotification)
    self:ShowLootNotification(
        data.id or 0,
        "|cff0070dd[" .. data.name .. "]|r",
        data.name,
        typeCapitalized,
        data.icon
    )
    
    -- Check if this item completes a plan
    local completedPlan = self:CheckItemForPlanCompletion(data)
    if completedPlan then
        -- Queue plan notification (0.3 second delay for stacking)
        C_Timer.After(0.3, function()
            self:ShowPlanCompletedNotification(completedPlan)
        end)
    end
end

---Check if a collected item completes an active plan
---@param data table {type, name, id} from CollectionService
---@return table|nil - The completed plan or nil
function WarbandNexus:CheckItemForPlanCompletion(data)
    if not self.db or not self.db.global or not self.db.global.plans then
        return nil
    end
    
    -- Use global plans (shared across characters) - same as PlansManager
    for _, plan in ipairs(self.db.global.plans) do
        if not plan.completed and not plan.completionNotified then
            -- Check if plan matches the collected item
            if plan.type == data.type and plan.name == data.name then
                -- Mark as completed and notified
                plan.completed = true
                plan.completionNotified = true
                return plan
            end
        end
    end
    return nil
end

---Test loot notification system (All notification types with real data)
function WarbandNexus:TestLootNotification(type, id)
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Notification Test Commands ===|r")
        self:Print("|cffffcc00/wn testloot|r - Show all notification types")
        self:Print("|cffffcc00/wn testloot mount [id]|r - Test mount notification")
        self:Print("|cffffcc00/wn testloot pet [id]|r - Test pet notification")
        self:Print("|cffffcc00/wn testloot toy [id]|r - Test toy notification")
        self:Print("|cffffcc00/wn testloot plan [achievementID]|r - Test plan completion")
        self:Print("|cffffcc00/wn testloot reputation|r - Test reputation notification")
        self:Print("|cffffcc00/wn testloot achievement [id]|r - Test achievement notification")
        self:Print("|cff888888Examples:|r")
        self:Print("|cff888888  /wn testloot achievement 60981|r")
        self:Print("|cff888888  /wn testloot mount 460|r")
        return
    end
    
    local delay = 0
    
    -- Show mount test (Real mount ID: 460 = Grand Black War Mammoth)
    if type == "mount" or type == "all" then
        C_Timer.After(delay, function()
            local mountID = id or 460
            local mountName, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
            if mountName then
                self:ShowModalNotification({
                    icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                    itemName = mountName,
                    action = "You have collected a mount",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
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
                self:ShowModalNotification({
                    icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                    itemName = speciesName,
                    action = "You have collected a battle pet",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
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
            local itemName, _, _, _, _, _, _, _, _, icon = GetItemInfo(toyItemID)
            if itemName then
                self:ShowModalNotification({
                    icon = icon or "Interface\\Icons\\INV_Misc_Toy_01",
                    itemName = itemName,
                    action = "You have collected a toy",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
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
                self:ShowModalNotification({
                    icon = icon or "Interface\\Icons\\Achievement_Quests_Completed_08",
                    itemName = achievementName,
                    action = "You have earned an achievement",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
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
    
    -- Show plan completion tests
    if type == "plan" or type == "all" then
        if id then
            -- Test with specific achievement ID
            C_Timer.After(delay, function()
                local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if achievementName then
                    self:ShowModalNotification({
                        icon = icon or "Interface\\Icons\\INV_Misc_Note_06",
                        itemName = achievementName,
                        action = "You have completed a plan",
                        autoDismiss = 10,
                        playSound = true,
                        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                    })
                    self:Print("|cff00ff00Plan completion: " .. achievementName .. " (ID: " .. id .. ")|r")
                else
                    self:Print("|cffff0000Invalid achievement ID: " .. id .. "|r")
                end
            end)
        else
            -- Show multiple example plans
            C_Timer.After(delay, function()
                self:ShowModalNotification({
                    icon = "Interface\\Icons\\INV_Scroll_11",
                    itemName = "Bloodsail Admiral",
                    action = "You have completed a plan",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:ShowModalNotification({
                    icon = "Interface\\Icons\\INV_Scroll_08",
                    itemName = "Greater Darkmoon Feast",
                    action = "You have completed a plan",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:ShowModalNotification({
                    icon = "Interface\\Icons\\INV_Enchant_Disenchant",
                    itemName = "Illusion: Mongoose",
                    action = "You have completed a plan",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:ShowModalNotification({
                    icon = "Interface\\Icons\\INV_Misc_Note_06",
                    itemName = "Collect All Mounts",
                    action = "You have completed a plan",
                    autoDismiss = 10,
                    playSound = true,
                    glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
                })
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
            self:ShowModalNotification({
                icon = "Interface\\Icons\\INV_Scroll_11",
                itemName = "The Assembly of the Deeps",    -- Line 1 (big, red)
                action = "Renown 15",                      -- Line 2 (small, gray)
                autoDismiss = 10,
                playSound = true,
                glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
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
            self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
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
            
            self:SendMessage("WN_PLAN_COMPLETED", {
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
            self:SendMessage("WN_VAULT_SLOT_COMPLETED", {
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
            self:SendMessage("WN_VAULT_REWARD_AVAILABLE", {})
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
            self:SendMessage("WN_QUEST_COMPLETED", {
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
    
    -- Test reputation gain event
    if type == "reputation" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage("WN_REPUTATION_GAINED", {
                factionID = 2590,
                factionName = "The Assembly of the Deeps",
                oldLevel = 14,
                newLevel = 15,
                isRenown = true,
                texture = "Interface\\Icons\\INV_Scroll_11"
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
    
    -- Check rewards
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    self:Print("Result: " .. tostring(hasRewards))
    
    if hasRewards then
        self:Print("|cff00ff00âœ“ YOU HAVE UNCLAIMED REWARDS!|r")
        self:Print("Showing vault notification...")
        self:ShowVaultReminder({})
    else
        self:Print("|cff888888âœ— No unclaimed rewards|r")
    end
    
    self:Print("|cff00ccff======================|r")
end








