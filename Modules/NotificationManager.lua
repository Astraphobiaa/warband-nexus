--[[
    Warband Nexus - Notification Manager
    Handles in-game notifications and reminders
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Unique AceEvent handler identity for NotificationManager
local NotificationEvents = {}

-- Current addon version (from Constants)
local Constants = ns.Constants
local CURRENT_VERSION = Constants.ADDON_VERSION

-- Changelog for current version (loaded from locale)
local function BuildChangelog()
    local changelogText = (ns.L and ns.L["CHANGELOG_V211"]) or
        "IMPROVEMENTS:\n" ..
        "- Professions: Concentration tracking now correctly identifies each profession independently.\n" ..
        "- Data Integrity: Standardized character key normalization across all modules.\n" ..
        "- Plans: Duplicate plan detection prevents adding the same item twice.\n" ..
        "- Plans: GetPlanByID now searches both standard and custom plan lists.\n" ..
        "- Currency: Stricter tracking filter prevents untracked characters from appearing.\n" ..
        "- Events: Throttle function sets timer before execution to prevent re-entrancy.\n" ..
        "- Try Counter: Expanded difficulty mapping (Normal, 10N, 25N, LFR).\n" ..
        "\n" ..
        "BUG FIXES:\n" ..
        "- Fixed concentration data being overwritten between professions (e.g., Alchemy showing Inscription values).\n" ..
        "- Fixed concentration swapping when opening different profession windows.\n" ..
        "- Fixed event queue crash when handler or args were nil.\n" ..
        "- Fixed PvE cache clear crash when database was not yet initialized.\n" ..
        "- Fixed card layout division by zero when parent frame had no width.\n" ..
        "\n" ..
        "CLEANUP:\n" ..
        "- Removed unused Gold Transfer UI code and related locale keys.\n" ..
        "- Removed unused scan status UI elements.\n" ..
        "\n" ..
        "Thank you for your continued support!\n" ..
        "\n" ..
        "To report issues or share feedback, leave a comment on CurseForge - Warband Nexus."

    local changes = {}
    for line in changelogText:gmatch("([^\n]*)") do
        changes[#changes + 1] = line
    end
    return changes
end

local CHANGELOG = {
    version = "2.1.1",
    date = "2026-02-18",
    changes = BuildChangelog()
}

-- Export CHANGELOG to namespace for command access
ns.CHANGELOG = CHANGELOG

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
        local fallbackText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
}

-- Action text mapping (subtitle line)
local ACTION_TEXT = {
    mount = (ns.L and ns.L["COLLECTED_MOUNT_MSG"]) or "You have collected a mount",
    pet = (ns.L and ns.L["COLLECTED_PET_MSG"]) or "You have collected a battle pet",
    toy = (ns.L and ns.L["COLLECTED_TOY_MSG"]) or "You have collected a toy",
    illusion = (ns.L and ns.L["COLLECTED_ILLUSION_MSG"]) or "You have collected an illusion",
    achievement = (ns.L and ns.L["ACHIEVEMENT_COMPLETED_MSG"]) or "Achievement completed!",
    title = (ns.L and ns.L["EARNED_TITLE_MSG"]) or "You have earned a title",
    plan = (ns.L and ns.L["COMPLETED_PLAN_MSG"]) or "You have completed a plan",
    item = (ns.L and ns.L["COLLECTED_ITEM_MSG"]) or "You received a rare drop",
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
-- Combat queue for notifications that arrive during combat
if not WarbandNexus._combatQueue then
    WarbandNexus._combatQueue = {}
end
-- Queue processing debounce timer (prevents multiple simultaneous queue processing)
local queueProcessTimer = nil

-- Alert positioning constants
local ALERT_HEIGHT = 88
local ALERT_GAP = 10    -- Pixel gap between stacked alerts
local ALERT_SPACING = ALERT_HEIGHT + ALERT_GAP  -- Total slot spacing (98px)

---Get saved notification position from DB
---@return string point, number x, number y
local function GetSavedPosition()
    local db = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    local point = db and db.popupPoint or "TOP"
    local x = db and db.popupX or 0
    local y = db and db.popupY or -100
    return point, x, y
end

---Determine growth direction based on anchor position on screen (always AUTO)
---Returns 1 for DOWN (negative Y), -1 for UP (positive Y)
---@return number direction (1 = down, -1 = up)
local function GetGrowthDirection()
    -- Always AUTO: determine based on anchor's screen position (DOWN/UP options removed from UI)
    local point, x, y = GetSavedPosition()
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

---Calculate Y offset for a specific alert slot index (direction-aware)
---@param slotIndex number 1-based slot index
---@param direction number 1 = down, -1 = up
---@return number yOffset
local function GetAlertSlotOffset(slotIndex, direction)
    return (slotIndex - 1) * ALERT_SPACING * -direction
end

---Reposition all active alerts (when one closes, others fill the gap)
---@param instant boolean If true, cancel all animations and reposition instantly
local function RepositionAlerts(instant)
    local point, baseX, baseY = GetSavedPosition()
    local direction = GetGrowthDirection()
    
    for i, alert in ipairs(WarbandNexus.activeAlerts) do
        local newYOffset = baseY + GetAlertSlotOffset(i, direction)
        
        -- Skip alerts that are closing (they manage their own fade-out position)
        -- But DO NOT skip isEntering — they need correct target positions
        if not alert.isClosing then
            -- Cancel any ongoing animation to prevent conflicts
            if alert.isAnimating then
                alert:SetScript("OnUpdate", nil)
                alert.isAnimating = false
            end
            
            if alert.isEntering then
                -- Alert is mid-entrance animation: redirect it to new target position
                -- Update the dynamic target so the OnUpdate handler picks it up seamlessly
                if alert._entranceTargetY ~= newYOffset then
                    alert._entranceStartY = alert.currentYOffset or newYOffset
                    alert._entranceTargetY = newYOffset
                    alert._entranceStartTime = GetTime()
                end
            elseif instant then
                -- Instant reposition: snap to target position immediately
                if alert.currentYOffset ~= newYOffset then
                    alert:ClearAllPoints()
                    alert:SetPoint(point, UIParent, point, baseX, newYOffset)
                    alert.currentYOffset = newYOffset
                end
            elseif alert.currentYOffset ~= newYOffset then
                -- Animated reposition: smooth slide from current position
                local repositionStart = GetTime()
                local repositionDuration = 0.25
                local startY = alert.currentYOffset or newYOffset
                local moveDistance = newYOffset - startY
                local _point, _baseX = point, baseX
                
                alert.isAnimating = true
                
                alert:SetScript("OnUpdate", function(self, elapsed)
                    local elapsedTime = GetTime() - repositionStart
                    local progress = math.min(1, elapsedTime / repositionDuration)
                    
                    -- Smooth easing (IN_OUT quadratic)
                    local easedProgress
                    if progress < 0.5 then
                        easedProgress = 2 * progress * progress
                    else
                        easedProgress = 1 - math.pow(-2 * progress + 2, 2) / 2
                    end
                    
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
    if #WarbandNexus.alertQueue > 0 then
        -- Cancel any existing queue timer
        if queueProcessTimer then
            queueProcessTimer:Cancel()
        end
        
        -- Short debounce to batch rapid dismissals, then process queue
        queueProcessTimer = C_Timer.After(0.15, function()
            queueProcessTimer = nil
            
            -- Process queue: show ONE alert at a time with staggered entrance
            local function ProcessNextInQueue()
                if not WarbandNexus or not WarbandNexus.activeAlerts then return end
                if #WarbandNexus.alertQueue > 0 and #WarbandNexus.activeAlerts < 3 then
                    local nextConfig = table.remove(WarbandNexus.alertQueue, 1)
                    
                    if WarbandNexus.ShowModalNotification then
                        WarbandNexus:ShowModalNotification(nextConfig)
                        
                        -- If more slots available, stagger next alert after entrance completes
                        if #WarbandNexus.alertQueue > 0 and #WarbandNexus.activeAlerts < 3 then
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
---@param config table Configuration: {icon, title, message, subtitle, category, glowAtlas}
function WarbandNexus:ShowModalNotification(config)
    -- Combat safety: Queue notifications during combat
    if InCombatLockdown() then
        -- Queue for after combat
        self._combatQueue = self._combatQueue or {}
        table.insert(self._combatQueue, config)
        if not self._combatQueueRegistered then
            self._combatQueueRegistered = true
            -- Register for combat end
            local combatFrame = CreateFrame("Frame")
            combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatFrame:SetScript("OnEvent", function()
                combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                self._combatQueueRegistered = false
                -- Process queued notifications
                if self._combatQueue then
                    for _, data in ipairs(self._combatQueue) do
                        self:ShowModalNotification(data)
                    end
                    wipe(self._combatQueue)
                end
            end)
        end
        return
    end
    
    -- Queue system: max 3 alerts visible at once
    if #self.activeAlerts >= 3 then
        table.insert(self.alertQueue, config)
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
    
    -- Calculate alert position (direction-aware, screen-safe)
    local point, baseX, baseY = GetSavedPosition()
    local direction = GetGrowthDirection()
    
    -- Simple sequential slot: new alert always goes at the next position
    -- after all existing alerts (array index is the slot)
    local alertIndex = #self.activeAlerts + 1
    local yOffset = baseY + GetAlertSlotOffset(alertIndex, direction)
    
    -- WoW Achievement-style popup frame (exact WoW dimensions: 400x88)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(400, 88)
    popup:SetFrameStrata("HIGH")
    popup:SetFrameLevel(1000)
    popup:SetClampedToScreen(true)  -- Prevent overflow off screen edges
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
    popup.achievementID = config.achievementID  -- nil unless achievement notification
    
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
    -- Visual balance: midpoint between popup center and text-area center
    -- Pure text-area center (229px) looks right-shifted; popup center (200px) ignores icon
    local textAreaCenter = iconRight + (textAreaWidth / 2)  -- 229px
    local textCenterX = (popupWidth / 2 + textAreaCenter) / 2  -- ~215px (visual balance)
    
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
    -- NOTE: All text FontStrings use OVERLAY sublevel 7 to render above
    -- glow textures (TopBottom lines at sublevel 5, edgeShine at 6, iconBling at 7)
    if showCategory then
        local category = FontManager:CreateFontString(popup, "small", "OVERLAY")
        category:SetDrawLayer("OVERLAY", 7)
        category:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        category:SetWidth(textAreaWidth - 20)
        category:SetJustifyH("CENTER")
        category:SetText("|cffaaaaaa" .. categoryText .. "|r")
        category:SetWordWrap(false)
        category:SetShadowOffset(1, -1)
        category:SetShadowColor(0, 0, 0, 0.8)
        startY = startY - smallFontHeight - lineSpacing
    end
    
    -- LINE 2: Title (BIG, ACCENT COLOR, NORMAL FONT)
    if showTitle then
        local title = FontManager:CreateFontString(popup, "title", "OVERLAY")
        title:SetDrawLayer("OVERLAY", 7)
        title:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        title:SetWidth(textAreaWidth - 20)
        title:SetJustifyH("CENTER")
        title:SetWordWrap(false)
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
        local subtitle = FontManager:CreateFontString(popup, "body", "OVERLAY")
        subtitle:SetDrawLayer("OVERLAY", 7)
        subtitle:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        subtitle:SetWidth(textAreaWidth - 20)
        subtitle:SetJustifyH("CENTER")
        subtitle:SetText("|cffffffff" .. messageText .. "|r")
        subtitle:SetWordWrap(true)
        subtitle:SetMaxLines(2)
        subtitle:SetShadowOffset(1, -1)
        subtitle:SetShadowColor(0, 0, 0, 0.6)
    end
    
    -- Legacy subtitle support
    if not showSubtitle and subtitleText and subtitleText ~= "" then
        local legacySub = FontManager:CreateFontString(popup, "body", "OVERLAY")
        legacySub:SetDrawLayer("OVERLAY", 7)
        legacySub:SetPoint("CENTER", popup, "BOTTOMLEFT", textCenterX, (popupHeight / 2) + startY)
        legacySub:SetWidth(textAreaWidth - 20)
        legacySub:SetJustifyH("CENTER")
        legacySub:SetText("|cffffffff" .. subtitleText .. "|r")
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
    
    -- Store anchor info on the popup for later repositioning
    popup._anchorPoint = point
    popup._baseX = baseX
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
    
    -- 1. Check for new version (What's New)
    if notifs.showUpdateNotes and self:IsNewVersion() then
        QueueNotification({
            type = "update",
            data = CHANGELOG
        })
    end
    
    -- 2. Check for vault rewards
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
    
    -- Process queue with minimal delay (update notification is immediately queued)
    if #notificationQueue > 0 then
        C_Timer.After(0.5, ProcessNotificationQueue)
    else
        -- Vault check has 0.5s delay, check again after it completes
        C_Timer.After(1.5, function()
            if #notificationQueue > 0 then
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
    self:RegisterMessage("WN_SHOW_NOTIFICATION", "OnShowNotification")
    
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
    local DebugPrint = ns.DebugPrint or function() end
    
    -- Direct dispatch with pcall isolation.
    -- Each consumer is called explicitly (no table indirection).
    -- pcall ensures one consumer's error doesn't break the others.
    self:RegisterMessage("WN_COLLECTIBLE_OBTAINED", function(event, data)
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
    
    self:RegisterMessage("WN_PLAN_COMPLETED", "OnPlanCompleted")
    self:RegisterMessage("WN_VAULT_CHECKPOINT_COMPLETED", "OnVaultCheckpointCompleted")
    self:RegisterMessage("WN_VAULT_SLOT_COMPLETED", "OnVaultSlotCompleted")
    self:RegisterMessage("WN_VAULT_PLAN_COMPLETED", "OnVaultPlanCompleted")
    self:RegisterMessage("WN_QUEST_COMPLETED", "OnQuestCompleted")
    -- WN_REPUTATION_GAINED is handled in Core.lua (chat notifications)
    self:RegisterMessage("WN_VAULT_REWARD_AVAILABLE", "OnVaultRewardAvailable")
    
    -- Font change listener (low-impact: active notifications auto-dismiss quickly, new ones will use updated font)
    -- NOTE: Uses NotificationEvents as 'self' key to avoid overwriting PlansTrackerWindow's handler.
    WarbandNexus.RegisterMessage(NotificationEvents, "WN_FONT_CHANGED", function()
        -- Active notifications will pick up new font on next creation
        -- No action needed for already-visible notifications (they auto-dismiss)
    end)
    
    -- Suppress Blizzard's achievement popup if user opted in
    self:ApplyBlizzardAchievementAlertSuppression()
end

---Suppress or restore Blizzard's default achievement alert popup
---When enabled, hides the default "Achievement Earned!" popup since WarbandNexus shows its own
---Uses AddAlert hook instead of UnregisterAlertSystem to avoid loading Blizzard_AchievementUI
---which causes "Unknown function AchievementShield_OnLoad" errors
function WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
    if not AchievementAlertSystem then return end
    
    local shouldHide = self.db and self.db.profile and self.db.profile.notifications
        and self.db.profile.notifications.hideBlizzardAchievementAlert
    
    -- Store original AddAlert only once
    if not self._origAchievementAddAlert then
        self._origAchievementAddAlert = AchievementAlertSystem.AddAlert
    end
    
    if shouldHide then
        -- Replace AddAlert with a no-op so achievement popups are silently swallowed
        AchievementAlertSystem.AddAlert = function() end
    else
        -- Restore original AddAlert
        if self._origAchievementAddAlert then
            AchievementAlertSystem.AddAlert = self._origAchievementAddAlert
        end
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
    if not data or not data.type or not data.name then return end
    
    -- Check if loot notifications are enabled
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
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
        return
    end
    
    -- Achievement notifications: only show ours when we're hiding Blizzard's
    -- If hideBlizzardAchievementAlert is false (unchecked), Blizzard shows its own popup,
    -- so we skip ours to avoid duplicate notifications
    if data.type == "achievement" and not self.db.profile.notifications.hideBlizzardAchievementAlert then
        return
    end
    
    -- Build try count message for mount/pet/toy/illusion
    -- Try count is shown only for farmable drop sources or items with manual counts.
    -- All collectibles get a notification regardless of source (vendor, quest, drop).
    local tryMessage = nil
    local hasTryCount = false
    local tryCountTypes = { mount = true, pet = true, toy = true, illusion = true, item = true }
    if tryCountTypes[data.type] and data.id then
        local isDropSource = self.IsDropSourceCollectible and self:IsDropSourceCollectible(data.type, data.id)
        -- Use preResetTryCount if provided (0 = first try; counter was reset before notification fired)
        local failedCount = (data.preResetTryCount ~= nil) and data.preResetTryCount or (self.GetTryCount and self:GetTryCount(data.type, data.id)) or 0
        
        local isGuaranteed = self.IsGuaranteedCollectible and self:IsGuaranteedCollectible(data.type, data.id)
        if not isGuaranteed then
            -- Add +1 for the current successful attempt if the item is a known drop source
            -- This gives the real total: e.g. 0 failed + 1 success = "first try!"
            local count = isDropSource and (failedCount + 1) or failedCount
            if count > 0 then
                hasTryCount = true
                if count == 1 then
                    tryMessage = "You got it on your first try!"
                elseif count > 100 then
                    tryMessage = "What a grind! " .. count .. " attempts!"
                else
                    tryMessage = "You got it after " .. count .. " tries!"
                end
            end
        end
    end
    
    -- Show notification (try message only for farmed items)
    local overrides = {
        action = tryMessage,
    }
    -- Attach achievement ID so click handler can open the achievement UI
    if data.type == "achievement" and data.id then
        overrides.achievementID = data.id
    end
    self:Notify(data.type, data.name, data.icon, overrides)
    
    -- Screen flash effect — ONLY for items obtained through farming (try count > 0)
    -- No flash for: vendor purchases, quest rewards, achievement rewards, 100% drops
    if hasTryCount then
        self:PlayScreenFlash(0.6)
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
function WarbandNexus:TestLootNotification(type, id)
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Notification Test Commands ===|r")
        self:Print("|cffffcc00/wn testloot|r - Show all notification types")
        self:Print("|cffffcc00/wn testloot mount [id]|r - Test mount notification")
        self:Print("|cffffcc00/wn testloot pet [id]|r - Test pet notification")
        self:Print("|cffffcc00/wn testloot toy [id]|r - Test toy notification")
        self:Print("|cffffcc00/wn testloot achievement [id]|r - Test achievement notification")
        self:Print("|cffffcc00/wn testloot illusion|r - Test illusion notification")
        self:Print("|cffffcc00/wn testloot title|r - Test title notification")
        self:Print("|cffffcc00/wn testloot plan [achievementID]|r - Test plan completion")
        self:Print("|cffffcc00/wn testloot reputation|r - Test reputation notification")
        self:Print("|cffffcc00/wn testloot blizzard [id]|r - Test Blizzard vs WN achievement alert")
        self:Print("|cff888888Examples:|r")
        self:Print("|cff888888  /wn testloot achievement 40752|r  (The Loremaster)")
        self:Print("|cff888888  /wn testloot mount 1039|r  (Ashes of Al'ar)")
        self:Print("|cff888888  /wn testloot pet 3390|r  (Lil' Xt)")
        self:Print("|cff888888  /wn testloot toy 188680|r  (Piccolo of the Flaming Fire)")
        self:Print("|cff888888  /wn testloot blizzard 6|r  (Level 10)")
        return
    end
    
    -- Test Blizzard achievement popup vs our notification
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
        if not InCombatLockdown() then
            if C_AddOns and C_AddOns.LoadAddOn then
                pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
            elseif LoadAddOn then
                pcall(LoadAddOn, "Blizzard_AchievementUI")
            end
        end
        
        -- Check suppression state
        local isSuppressed = self.db and self.db.profile and self.db.profile.notifications
            and self.db.profile.notifications.hideBlizzardAchievementAlert
        
        self:Print("|cff00ccff=== Blizzard Achievement Alert Test ===|r")
        self:Print("|cffffcc00Achievement:|r " .. achievementName .. " (ID: " .. achievementID .. ")")
        self:Print("|cffffcc00Blizzard Alert Suppressed:|r " .. (isSuppressed and "|cff44ff44YES|r" or "|cffff4444NO|r"))
        
        -- Trigger Blizzard's popup through the CURRENT AddAlert function
        -- If suppressed → our no-op swallows it → no Blizzard popup
        -- If not suppressed → original AddAlert runs → Blizzard popup appears
        if AchievementAlertSystem and AchievementAlertSystem.AddAlert then
            local success, err = pcall(AchievementAlertSystem.AddAlert, AchievementAlertSystem, achievementID)
            if success then
                if isSuppressed then
                    self:Print("|cff888888Blizzard popup suppressed - you should NOT see it|r")
                else
                    self:Print("|cff00ff00Blizzard popup triggered - you should see it at top of screen|r")
                end
            else
                self:Print("|cffff8800Blizzard alert error: " .. tostring(err) .. "|r")
            end
        end
        
        -- Also show OUR notification for side-by-side comparison
        C_Timer.After(0.3, function()
            self:Notify("achievement", achievementName, achIcon)
        end)
        
        self:Print("|cff888888Toggle: Settings > Notifications > Hide Blizzard Achievement Alert|r")
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
    
    -- Test reputation gain event (Snapshot-Diff payload)
    if type == "reputation" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage("WN_REPUTATION_GAINED", {
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




