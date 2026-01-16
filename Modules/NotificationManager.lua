--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Current addon version
local CURRENT_VERSION = "1.0.0"

-- Changelog for current version (manual update required)
local CHANGELOG = {
    version = "1.0.0",
    date = "2024-12-16",
    changes = {
        "Added Smart Character Sorting System",
        "Added Favorite Characters feature",
        "Added ToS Compliance documentation",
        "Added Modern UI with rounded tabs and badges",
        "Added Minimap button with tooltip",
        "Added Enhanced item tooltips",
        "Added Cross-character PvE tracking",
    }
}

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
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    title:SetText("|cff9966ffWarband Nexus|r")
    
    -- Version subtitle
    local versionText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    local whatsNewLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
        local bullet = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

---Reposition all active alerts (when one closes, others move up)
local function RepositionAlerts()
    local alertSpacing = 98 -- Space between alerts (88px height + 10px gap)
    
    for i, alert in ipairs(WarbandNexus.activeAlerts) do
        local newYOffset = -100 - ((i - 1) * alertSpacing) -- Updated to -100 start position
        
        -- Smooth reposition animation
        alert:ClearAllPoints()
        alert:SetPoint("TOP", UIParent, "TOP", 0, alert.currentYOffset or newYOffset)
        
        -- CRITICAL: Skip repositioning if alert is closing (exit animation takes priority)
        if not alert.isClosing and alert.currentYOffset ~= newYOffset then
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
        
        alert.alertIndex = i
    end
end

---Remove alert and process queue
---@param alert Frame The alert frame to remove
local function RemoveAlert(alert)
    if not alert then return end
    
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
    
    -- DON'T reposition during removal - causes overlapping during exit animations
    -- The remaining alerts will stay in their current positions until naturally dismissed
    
    -- Show next queued alert
    if #WarbandNexus.alertQueue > 0 then
        local nextConfig = table.remove(WarbandNexus.alertQueue, 1)
        C_Timer.After(0.3, function()
            if WarbandNexus and WarbandNexus.ShowModalNotification then
                WarbandNexus:ShowModalNotification(nextConfig)
            end
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
    local iconTexture = config.icon or "Interface\\Icons\\Achievement_Quests_Completed_08"
    local titleText = config.title or "Notification"
    local messageText = config.message or ""
    local subtitleText = config.subtitle or ""
    local categoryText = config.category or nil
    local playSound = config.playSound ~= false
    local titleColor = config.titleColor or {0.6, 0.4, 0.9} -- Purple default
    local glowAtlas = config.glowAtlas or "communitiesfinder_card_highlight"  -- Default glow atlas
    local autoDismissDelay = config.autoDismiss or 10 -- Default 10 seconds, can be overridden
    
    -- Calculate alert position based on number of active alerts
    local alertIndex = #self.activeAlerts + 1
    local alertSpacing = 98
    local yOffset = -100 - ((alertIndex - 1) * alertSpacing) -- Start at -100 instead of -15
    
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
    popup.alertIndex = alertIndex
    popup.currentYOffset = yOffset
    table.insert(self.activeAlerts, popup)
    
    -- Popup dimensions for calculations
    local popupWidth = 400
    local popupHeight = 88
    local ringSize = 180 -- Larger rings for more visibility
    
    -- === ICON (LEFT SIDE - Achievement style) ===
    local iconSize = 42 -- Icon size: 36 + 6px = 42px
    local icon = popup:CreateTexture(nil, "ARTWORK", nil, 0) -- ARTWORK layer, sublevel 0
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", popup, "LEFT", 14, 0) -- Centered positioning
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- Standard crop
    
    -- Handle both numeric IDs and texture paths
    if type(iconTexture) == "number" then
        icon:SetTexture(iconTexture)
    elseif iconTexture and iconTexture ~= "" then
        local cleanPath = iconTexture:gsub("\\", "/")
        icon:SetTexture(cleanPath)
    else
        icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
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
    
    -- === CONTENT (RIGHT SIDE - Achievement style) ===
    
    -- Title (right of icon, near top) - WoW compact style
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)  -- Reduced from -6 to move up
    title:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, -2)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 0.9)
    
    local titleGradient = string.format("|cff%02x%02x%02x%s|r",
        math.floor(math.min(255, titleColor[1]*255*1.4)),
        math.floor(math.min(255, titleColor[2]*255*1.4)),
        math.floor(math.min(255, titleColor[3]*255*1.4)),
        titleText)
    title:SetText(titleGradient)
    
    -- Subtitle (below title) - compact spacing
    local contentYOffset = -22  -- Adjusted from -26 to move up
    if subtitleText and subtitleText ~= "" then
        local subtitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subtitle:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, contentYOffset)
        subtitle:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, contentYOffset)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText("|cffcccccc" .. subtitleText .. "|r")
        subtitle:SetWordWrap(true)
        subtitle:SetMaxLines(1)
        subtitle:SetShadowOffset(1, -1)
        subtitle:SetShadowColor(0, 0, 0, 0.6)
        contentYOffset = contentYOffset - 16
    end
    
    -- Message (below subtitle) - compact
    if messageText and messageText ~= "" then
        local message = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        message:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, contentYOffset)
        message:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, contentYOffset)
    message:SetJustifyH("LEFT")
    message:SetText(messageText)
        message:SetTextColor(0.9, 0.9, 0.9)
    message:SetWordWrap(true)
        message:SetMaxLines(1)
    message:SetShadowOffset(1, -1)
    message:SetShadowColor(0, 0, 0, 0.9)
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
    
    -- Each alert starts ABOVE its final position (like old toast system)
    local finalYOffset = yOffset -- Alert's final position (-15, -113, -211, etc.)
    local startYOffset = finalYOffset + 50 -- Start 50px ABOVE final position (more positive = higher)
    
    popup:SetAlpha(0)
    popup:SetPoint("TOP", UIParent, "TOP", 0, startYOffset)
    popup.currentYOffset = startYOffset
    popup:Show()
    
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
        local alertIndex = #WarbandNexus.activeAlerts -- Track which alert this is (use global ref)
        popup.dismissTimer = C_Timer.NewTimer(autoDismissDelay, function()
            if not popup or not popup:IsShown() or popup.isClosing then return end
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
                    RemoveAlert(popup)
                end
    end)
        end)
        end
    end)
end

--[[============================================================================
    GENERIC TOAST NOTIFICATION SYSTEM (WITH STACKING)
============================================================================]]

---Show a generic toast notification (unified style for all notifications)
---@param config table Configuration: {icon, title, message, color, autoDismiss, onClose}
function WarbandNexus:ShowToastNotification(config)
    -- ShowToastNotification now uses ShowModalNotification with toast-specific defaults
    -- This ensures consistent styling across all notifications
    
    config = config or {}
    
    -- If category not explicitly set, remove it for cleaner look
    if config.category == nil then
        config.category = nil
    end
    
    -- Default to TopBottom glow if not specified
    if not config.glowAtlas then
        config.glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line"
    end
    
    -- Use ShowModalNotification with the same config
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

---Show vault reminder popup (small toast notification)
---@param data table Vault data
function WarbandNexus:ShowVaultReminder(data)
    -- Use the generic toast notification system (with stacking support)
    self:ShowToastNotification({
        icon = "Interface\\Icons\\achievement_guildperk_bountifulbags",
        title = "Weekly Vault Ready!",
        message = "You have unclaimed Weekly Vault Rewards",
        titleColor = {0.6, 0.4, 0.9}, -- Purple
        autoDismiss = 10, -- 10 seconds
        onClose = function()
            -- Toast stacking system handles queue automatically
            -- Only process main notification queue (for update popups)
            ProcessNotificationQueue()
        end
    })
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
    
    -- 2. Check for vault rewards (delayed to ensure API is ready)
    C_Timer.After(2, function()
        if notifs.showVaultReminder and self:HasUnclaimedVaultRewards() then
            QueueNotification({
                type = "vault",
                data = {}
            })
        end
    end)
    
    -- Process queue (delayed by 3 seconds after login)
    if #notificationQueue > 0 then
        C_Timer.After(3, ProcessNotificationQueue)
    else
        -- Check again after vault check completes
        C_Timer.After(4, function()
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
    LOOT NOTIFICATIONS (MOUNT/PET/TOY)
============================================================================]]

---Show loot notification toast (mount/pet/toy)
---Uses generic toast notification system for consistent style
---@param itemID number Item ID (or mount/pet ID)
---@param itemLink string Item link
---@param itemName string Item name
---@param collectionType string Type: "Mount", "Pet", or "Toy"
---@param iconOverride number|nil Optional icon override
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
        if apiIcon then
            icon = apiIcon
        else
            -- Use default icons from typeIcons table
            local typeMap = {
                Mount = "mount",
                Pet = "pet",
                Toy = "toy",
            }
            local planType = typeMap[collectionType]
            local typeIcons = {
                mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
                pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
                toy = "Interface\\Icons\\INV_Misc_Toy_07",
            }
            icon = typeIcons[planType] or "Interface\\Icons\\INV_Misc_QuestionMark"
        end
    end
    
    -- Map collection type to planType for consistent styling
    local planTypeMap = {
        Mount = "mount",
        Pet = "pet",
        Toy = "toy",
    }
    local planType = planTypeMap[collectionType] or "custom"
    
    -- Use the generic toast notification system
    self:ShowToastNotification({
        icon = icon,
        title = itemName,
        message = "New " .. collectionType .. " collected!",
        planType = planType,
        autoDismiss = 8,
        playSound = true,
    })
end

---Initialize loot notification system
function WarbandNexus:InitializeLootNotifications()
    -- Just a placeholder - CollectionManager handles everything now
    -- NotificationManager only provides toast display functions
end

---Show collectible toast notification (called by CollectionManager)
---@param data table {type, name, icon, id} from CollectionManager
function WarbandNexus:ShowCollectibleToast(data)
    if not data or not data.type or not data.name then return end
    
    -- Capitalize type for display
    local typeCapitalized = data.type:sub(1,1):upper() .. data.type:sub(2)
    
    -- Show toast using existing system
    self:ShowLootNotification(
        data.id or 0, -- itemID
        "|cff0070dd[" .. data.name .. "]|r", -- Fake link
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
---@param data table {type, name, id} from CollectionManager
---@return table|nil - The completed plan or nil
function WarbandNexus:CheckItemForPlanCompletion(data)
    if not self.db or not self.db.profile or not self.db.profile.plans then
        return nil
    end
    
    for planId, plan in pairs(self.db.profile.plans) do
        if not plan.completed and not plan.completionNotified then
            -- Check if plan matches the collected item
            if plan.type == data.type and plan.name == data.name then
                -- Mark as completed
                plan.completed = true
                plan.completionNotified = true
                return plan
            end
        end
    end
    return nil
end

---Test loot notification system (Mounts, Pets, & Toys)
function WarbandNexus:TestLootNotification(type)
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Notification Test Commands ===|r")
        self:Print("|cffffcc00/wn testloot|r - Show all notification types")
        self:Print("|cffffcc00/wn testloot mount|r - Test mount notification")
        self:Print("|cffffcc00/wn testloot pet|r - Test pet notification")
        self:Print("|cffffcc00/wn testloot toy|r - Test toy notification")
        return
    end
    
    local delay = 0
    
    -- Show mount test
    if type == "mount" or type == "all" then
        C_Timer.After(delay, function()
            self:ShowLootNotification(
                1234,
                "|cff0070dd[Invincible's Reins]|r",
                "Invincible's Reins",
                "Mount",
                "Interface\\Icons\\Ability_Mount_Invincible"
            )
        end)
        if type == "mount" then
            self:Print("|cff00ff00Test mount notification shown!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Show pet test
    if type == "pet" or type == "all" then
        C_Timer.After(delay, function()
            self:ShowLootNotification(
                5678,
                "|cff0070dd[Lil' Ragnaros]|r",
                "Lil' Ragnaros",
                "Pet",
                "Interface\\Icons\\INV_Pet_BabyBlizzardBear"
            )
        end)
        if type == "pet" then
            self:Print("|cff00ff00Test pet notification shown!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Show toy test
    if type == "toy" or type == "all" then
        C_Timer.After(delay, function()
            self:ShowLootNotification(
                9012,
                "|cff0070dd[Toy Train Set]|r",
                "Toy Train Set",
                "Toy",
                "Interface\\Icons\\INV_Misc_Toy_01"
            )
        end)
        if type == "toy" then
            self:Print("|cff00ff00Test toy notification shown!|r")
            return
        end
        delay = delay + 0.5
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing basic notification types!|r")
    else
        self:Print("|cffff0000Unknown notification type. Use |cffffcc00/wn testloot help|r for available options.|r")
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
        titleColor = {1.0, 0.5, 0.0},
        playSound = false,
        glowAtlas = "communitiesfinder_card_highlight",
    })
    
    -- Test 2: Top + Bottom lines
    C_Timer.After(0.3, function()
        self:ShowModalNotification({
            title = "Top & Bottom Lines",
            message = "Clean border highlighting",
            icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
            titleColor = {1.0, 0.0, 1.0},
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








