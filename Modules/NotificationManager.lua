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
        WarbandNexus:Print("|cff888888[Notifications] Queue is empty|r")
        return
    end
    
    WarbandNexus:Print("|cff00ccff[Notifications] Showing notification... (Queue: " .. #notificationQueue .. " remaining)|r")
    
    -- Show first notification
    local notification = table.remove(notificationQueue, 1)
    
    if notification.type == "update" then
        WarbandNexus:Print("|cff9966ff[Notifications] Showing UPDATE notification|r")
        WarbandNexus:ShowUpdateNotification(notification.data)
    elseif notification.type == "vault" then
        WarbandNexus:Print("|cffffd700[Notifications] Showing VAULT notification|r")
        WarbandNexus:ShowVaultReminder(notification.data)
    end
    
    -- Schedule next notification (2 second delay)
    if #notificationQueue > 0 then
        WarbandNexus:Print("|cff00ccff[Notifications] Next notification in 2 seconds...|r")
        C_Timer.After(2, ProcessNotificationQueue)
    else
        WarbandNexus:Print("|cff00ff00[Notifications] All notifications shown!|r")
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
        bullet:SetText("|cff9966ff•|r " .. change)
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
    VAULT REMINDER
============================================================================]]

---Check if player has unclaimed vault rewards
---@return boolean hasRewards
function WarbandNexus:HasUnclaimedVaultRewards()
    -- Check if API is available
    if not C_WeeklyRewards then
        self:Print("|cffff6600[Vault Check] C_WeeklyRewards API not available|r")
        return false
    end
    
    if not C_WeeklyRewards.HasAvailableRewards then
        self:Print("|cffff6600[Vault Check] HasAvailableRewards function not available|r")
        return false
    end
    
    -- Check for rewards
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    
    -- Debug output
    if hasRewards then
        self:Print("|cff00ff00[Vault Check] You have unclaimed rewards! Queueing notification...|r")
    else
        self:Print("|cff888888[Vault Check] No unclaimed rewards at this time.|r")
    end
    
    return hasRewards
end

---Show vault reminder popup (small toast notification)
---@param data table Vault data
function WarbandNexus:ShowVaultReminder(data)
    -- Small popup frame (no backdrop, no full screen overlay)
    local popup = CreateFrame("Frame", "WarbandNexusVaultNotification", UIParent, "BackdropTemplate")
    popup:SetSize(450, 130)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -150) -- Top-center of screen
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(1000)
    popup:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.2, 0.58, 1)
    
    -- Subtle glow effect
    local glow = popup:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -8, 8)
    glow:SetPoint("BOTTOMRIGHT", 8, -8)
    glow:SetColorTexture(0.6, 0.4, 0.9, 0.08)
    
    -- Icon (top, centered)
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(50, 50)
    icon:SetPoint("TOP", 0, -15)
    icon:SetTexture("Interface\\Icons\\achievement_guildperk_bountifulbags")
    
    -- Title (centered, below icon)
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
    title:SetJustifyH("CENTER")
    title:SetText("|cff9966ffWeekly Vault Ready!|r")
    
    -- Message (centered, single line, below title)
    local message = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOP", title, "BOTTOM", 0, -6)
    message:SetJustifyH("CENTER")
    message:SetText("You have unclaimed Weekly Vault Rewards")
    message:SetTextColor(0.85, 0.85, 0.85)
    
    -- Close button (X button, top-right)
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText("|cff888888×|r")
    
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
        popup:SetParent(nil)
        ProcessNotificationQueue()
    end)
    
    closeBtn:SetScript("OnEnter", function()
        closeBtnText:SetText("|cffffffff×|r")
    end)
    
    closeBtn:SetScript("OnLeave", function()
        closeBtnText:SetText("|cff888888×|r")
    end)
    
    -- Auto-dismiss after animation completes + 10 seconds (0.6s animation + 10s = 10.6s total)
    C_Timer.After(10.6, function()
        if popup and popup:IsShown() then
            -- Fade out animation before closing
            local fadeOutAg = popup:CreateAnimationGroup()
            local fadeOut = fadeOutAg:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(1)
            fadeOut:SetToAlpha(0)
            fadeOut:SetDuration(0.4)
            fadeOutAg:SetScript("OnFinished", function()
                popup:Hide()
                popup:SetParent(nil)
                ProcessNotificationQueue()
            end)
            fadeOutAg:Play()
        end
    end)
    
    -- Slide-in animation (smooth and visible)
    popup:SetAlpha(0)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -80) -- Start position (higher up)
    
    local ag = popup:CreateAnimationGroup()
    
    -- Fade in (slower)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(1)
    
    -- Slide down (slower, smooth)
    local slideDown = ag:CreateAnimation("Translation")
    slideDown:SetOffset(0, -70) -- Slide down 70px (from -80 to -150)
    slideDown:SetDuration(0.6)
    slideDown:SetOrder(1)
    slideDown:SetSmoothing("OUT") -- Ease-out effect
    
    -- After animation, fix the position permanently
    ag:SetScript("OnFinished", function()
        popup:ClearAllPoints()
        popup:SetPoint("TOP", UIParent, "TOP", 0, -150)
        popup:SetAlpha(1)
    end)
    
    ag:Play()
    
    -- Click anywhere on popup to dismiss
    popup:EnableMouse(true)
    popup:SetScript("OnMouseDown", function()
        closeBtn:Click()
    end)
end

--[[============================================================================
    NOTIFICATION SYSTEM INITIALIZATION
============================================================================]]

---Check and queue notifications on login
function WarbandNexus:CheckNotificationsOnLogin()
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        self:Print("|cffff6600[Notifications] Database not initialized|r")
        return
    end
    
    local notifs = self.db.profile.notifications
    
    -- Check if notifications are enabled
    if not notifs.enabled then
        self:Print("|cff888888[Notifications] Notifications are disabled in settings|r")
        return
    end
    
    self:Print("|cff00ccff[Notifications] Checking for notifications...|r")
    
    -- 1. Check for new version
    if notifs.showUpdateNotes and self:IsNewVersion() then
        self:Print("|cff00ff00[Notifications] New version detected! Queueing update notification...|r")
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
        self:Print("|cff00ccff[Notifications] Processing queue in 3 seconds...|r")
        C_Timer.After(3, ProcessNotificationQueue)
    else
        -- Check again after vault check completes
        C_Timer.After(4, function()
            if #notificationQueue > 0 then
                self:Print("|cff00ccff[Notifications] Processing vault notification...|r")
                ProcessNotificationQueue()
            end
        end)
    end
end

---Export current version
function WarbandNexus:GetAddonVersion()
    return CURRENT_VERSION
end

---Manual test function for vault check (slash command)
function WarbandNexus:TestVaultCheck()
    self:Print("|cff00ccff=== VAULT CHECK TEST ===|r")
    
    -- Check API
    if not C_WeeklyRewards then
        self:Print("|cffff0000ERROR: C_WeeklyRewards API not found!|r")
        return
    else
        self:Print("|cff00ff00✓ C_WeeklyRewards API available|r")
    end
    
    if not C_WeeklyRewards.HasAvailableRewards then
        self:Print("|cffff0000ERROR: HasAvailableRewards function not found!|r")
        return
    else
        self:Print("|cff00ff00✓ HasAvailableRewards function available|r")
    end
    
    -- Check rewards
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    self:Print("Result: " .. tostring(hasRewards))
    
    if hasRewards then
        self:Print("|cff00ff00✓ YOU HAVE UNCLAIMED REWARDS!|r")
        self:Print("Showing vault notification...")
        self:ShowVaultReminder({})
    else
        self:Print("|cff888888✗ No unclaimed rewards|r")
    end
    
    self:Print("|cff00ccff======================|r")
end
