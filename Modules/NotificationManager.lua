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
    GENERIC TOAST NOTIFICATION SYSTEM (WITH STACKING)
============================================================================]]

-- Initialize toast tracking (if not already initialized)
if not WarbandNexus.activeToasts then
    WarbandNexus.activeToasts = {} -- Currently visible toasts (max 3)
end
if not WarbandNexus.toastQueue then
    WarbandNexus.toastQueue = {} -- Waiting toasts (if >3 active)
end

---Show a generic toast notification (unified style for all notifications)
---@param config table Configuration: {icon, title, message, color, autoDismiss, onClose}
function WarbandNexus:ShowToastNotification(config)
    -- If we already have 3 active toasts, queue this one
    if #self.activeToasts >= 3 then
        table.insert(self.toastQueue, config)
        return
    end
    
    -- Default values
    config = config or {}
    local iconTexture = config.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    local titleText = config.title or "Notification"
    local messageText = config.message or ""
    local titleColor = config.titleColor or {0.6, 0.4, 0.9} -- Purple by default
    local autoDismissDelay = config.autoDismiss or 10 -- seconds
    local onCloseCallback = config.onClose
    
    -- Calculate vertical position (stack toasts: 1st=-150, 2nd=-300, 3rd=-450)
    local toastIndex = #self.activeToasts + 1
    local yOffset = -150 * toastIndex
    
    -- Small popup frame (no full screen overlay - just a toast)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(450, 130)
    popup:SetPoint("TOP", UIParent, "TOP", 0, yOffset)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(1000 + toastIndex) -- Stack level
    popup:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.10, 1.0) -- 100% opaque (was 0.95)
    popup:SetBackdropBorderColor(0.4, 0.2, 0.58, 1) -- Purple border (consistent)
    
    -- Track this toast
    table.insert(self.activeToasts, popup)
    popup.toastIndex = toastIndex
    
    -- Subtle glow effect
    local glow = popup:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -8, 8)
    glow:SetPoint("BOTTOMRIGHT", 8, -8)
    glow:SetColorTexture(titleColor[1], titleColor[2], titleColor[3], 0.08)
    
    -- Icon (top, centered)
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(50, 50)
    icon:SetPoint("TOP", 0, -15)
    icon:SetTexture(iconTexture)
    
    -- Title (centered, below icon)
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
    title:SetJustifyH("CENTER")
    title:SetText(string.format("|cff%02x%02x%02x%s|r", 
        titleColor[1] * 255, titleColor[2] * 255, titleColor[3] * 255, titleText))
    
    -- Message (centered, single line, below title)
    local message = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOP", title, "BOTTOM", 0, -6)
    message:SetJustifyH("CENTER")
    message:SetText(messageText)
    message:SetTextColor(0.85, 0.85, 0.85)
    
    -- Helper function to remove this toast and process queue
    local function CloseToast()
        -- Remove from active toasts
        for i, toast in ipairs(self.activeToasts) do
            if toast == popup then
                table.remove(self.activeToasts, i)
                break
            end
        end
        
        popup:Hide()
        popup:SetParent(nil)
        
        -- Call user callback
        if onCloseCallback then onCloseCallback() end
        
        -- Reposition remaining toasts
        for i, toast in ipairs(self.activeToasts) do
            local newYOffset = -150 * i
            toast:ClearAllPoints()
            toast:SetPoint("TOP", UIParent, "TOP", 0, newYOffset)
            toast:SetFrameLevel(1000 + i)
            toast.toastIndex = i
        end
        
        -- Show next queued toast (if any)
        if #self.toastQueue > 0 then
            local nextConfig = table.remove(self.toastQueue, 1)
            C_Timer.After(0.2, function() -- Small delay for smooth appearance
                self:ShowToastNotification(nextConfig)
            end)
        end
    end
    
    -- Close button (X button, top-right)
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText("|cff888888×|r")
    
    closeBtn:SetScript("OnClick", function()
        CloseToast()
    end)
    
    closeBtn:SetScript("OnEnter", function()
        closeBtnText:SetText("|cffffffff×|r")
    end)
    
    closeBtn:SetScript("OnLeave", function()
        closeBtnText:SetText("|cff888888×|r")
    end)
    
    -- Auto-dismiss after animation completes + delay
    local totalDelay = 0.6 + autoDismissDelay -- 0.6s animation + user-defined delay
    C_Timer.After(totalDelay, function()
        if popup and popup:IsShown() then
            local fadeOutAg = popup:CreateAnimationGroup()
            local fadeOut = fadeOutAg:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(1)
            fadeOut:SetToAlpha(0)
            fadeOut:SetDuration(0.4)
            fadeOutAg:SetScript("OnFinished", function()
                CloseToast()
            end)
            fadeOutAg:Play()
        end
    end)
    
    -- Slide-in animation (smooth and visible)
    popup:SetAlpha(0)
    local startYOffset = yOffset + 70 -- Start 70px above final position
    popup:ClearAllPoints()
    popup:SetPoint("TOP", UIParent, "TOP", 0, startYOffset)
    
    local ag = popup:CreateAnimationGroup()
    
    -- Fade in
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(1)
    
    -- Slide down
    local slideDown = ag:CreateAnimation("Translation")
    slideDown:SetOffset(0, -70) -- Slide down 70px
    slideDown:SetDuration(0.6)
    slideDown:SetOrder(1)
    slideDown:SetSmoothing("OUT") -- Ease-out effect
    
    -- After animation, fix the position permanently
    ag:SetScript("OnFinished", function()
        popup:ClearAllPoints()
        popup:SetPoint("TOP", UIParent, "TOP", 0, yOffset)
        popup:SetAlpha(1)
    end)
    
    ag:Play()
    
    -- Click anywhere to dismiss
    popup:EnableMouse(true)
    popup:SetScript("OnMouseDown", function()
        CloseToast()
    end)
    
    -- Play a sound (if configured)
    if config.sound then
        PlaySound(config.sound)
    end
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
    
    -- Get item icon (use override if provided)
    local icon = iconOverride
    
    if not icon then
        if collectionType == "Mount" then
            icon = select(3, C_MountJournal.GetMountInfoByID(itemID)) or "Interface\\Icons\\Ability_Mount_RidingHorse"
        elseif collectionType == "Pet" then
            icon = select(2, C_PetJournal.GetPetInfoBySpeciesID(itemID)) or "Interface\\Icons\\INV_Pet_BabyBlizzardBear"
        else
            icon = select(10, GetItemInfo(itemID)) or "Interface\\Icons\\INV_Misc_Toy_01"
        end
    end
    
    -- Use the generic toast notification system
    self:ShowToastNotification({
        icon = icon,
        title = itemName,  -- Item name as title
        message = "You obtained this " .. collectionType:lower() .. "!",
        titleColor = {0.6, 0.4, 0.9}, -- Purple (consistent with other notifications)
        autoDismiss = 8, -- 8 seconds
        sound = 44335, -- SOUNDKIT.UI_EPICLOOT_TOAST
    })
end

---Initialize loot notification system
function WarbandNexus:InitializeLootNotifications()
    -- Use BAG_UPDATE_DELAYED to detect items entering bags (Rarity-style)
    -- This fires WHEN the item drops/is bought, not when it's learned
    -- 0.2s throttle for faster detection (was 0.5s)
    self:RegisterBucketEvent("BAG_UPDATE_DELAYED", 0.2, "OnBagUpdateForCollectibles")
    
    -- Initialize bag cache to track new items
    self.lastBagContents = {}
    self:CacheBagContents()
    
    self:Print("|cff00ff00[Loot Notifications] Initialized! (Rarity-style bag detection - 0.2s throttle)|r")
    self:Print("|cff888888Type /wn testloot to test mount/pet/toy notifications.|r")
end

---Cache current bag contents for comparison
function WarbandNexus:CacheBagContents()
    self.lastBagContents = {}
    
    for bag = 0, 4 do -- Player bags only (0-4)
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.itemID then
                local key = bag .. "_" .. slot
                self.lastBagContents[key] = itemInfo.itemID
            end
        end
    end
end

---Handle BAG_UPDATE_DELAYED for collectible detection (Rarity-style)
---Detects when mounts/toys are added to bags (before being learned)
function WarbandNexus:OnBagUpdateForCollectibles()
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end
    
    if not self.db.profile.notifications.showLootNotifications then
        return
    end
    
    -- Check all bags for NEW items
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.itemID then
                local key = bag .. "_" .. slot
                local itemID = itemInfo.itemID
                
                -- Check if this is a NEW item (not in cache)
                if not self.lastBagContents[key] or self.lastBagContents[key] ~= itemID then
                    -- New item detected! Check if it's a collectible
                    self:CheckNewCollectible(itemID)
                    
                    -- Update cache
                    self.lastBagContents[key] = itemID
                end
            else
                -- Slot is empty, remove from cache
                local key = bag .. "_" .. slot
                self.lastBagContents[key] = nil
            end
        end
    end
end

---Check if a new item is a mount/pet/toy and show notification
function WarbandNexus:CheckNewCollectible(itemID)
    if not itemID then return end
    
    -- Force load item data (for icon/name cache)
    C_Item.RequestLoadItemDataByID(itemID)
    
    -- Get item info for classification
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, 
          itemStackCount, itemEquipLoc, iconFileDataID, sellPrice, classID, subclassID = GetItemInfo(itemID)
    
    -- ========================================
    -- 1. MOUNT DETECTION (Most reliable)
    -- ========================================
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID then
            -- Get mount info from Journal API (locale-correct, always accurate)
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, 
                  isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            
            -- Only show if NOT collected
            if name and not isCollected then
                C_Timer.After(0.15, function()
                    local freshItemName, freshItemLink = GetItemInfo(itemID)
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. name .. "]|r")
                    
                    self:ShowLootNotification(mountID, displayLink, name, "Mount", icon)
                end)
            end
            return
        end
    end
    
    -- ========================================
    -- 2. PET DETECTION (classID 17 = Companion Pets)
    -- ========================================
    if classID == 17 then
        -- Try to get speciesID (works in some TWW versions)
        local speciesID = nil
        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            local result = C_PetJournal.GetPetInfoByItemID(itemID)
            if type(result) == "number" then
                speciesID = result
            end
        end
        
        if speciesID then
            -- SUCCESS: We have speciesID, use Pet Journal API (most reliable)
            local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
            
            -- Only show if NOT collected
            if speciesName and numCollected == 0 then
                C_Timer.After(0.15, function()
                    local freshItemName, freshItemLink = GetItemInfo(itemID)
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. speciesName .. "]|r")
                    
                    self:ShowLootNotification(speciesID, displayLink, speciesName, "Pet", speciesIcon)
                end)
            end
        else
            -- FALLBACK: Can't get speciesID (TWW API issue)
            -- Try battlePetName field first, then tooltip parsing, then accept "Pet Cage"
            C_Item.RequestLoadItemDataByID(itemID)
            
            -- Wait for tooltip cache to load (0.5s for TWW cache loading)
            C_Timer.After(0.5, function()
                local freshItemName, freshItemLink, _, _, _, _, _, _, _, freshIcon = GetItemInfo(itemID)
                
                -- Try Core.lua's GetPetNameFromTooltip (includes battlePetName check + line parsing)
                local tooltipPetName = nil
                if WarbandNexus.GetPetNameFromTooltip then
                    tooltipPetName = WarbandNexus:GetPetNameFromTooltip(itemID)
                end
                
                -- If tooltip parsing succeeded, use actual pet name
                if tooltipPetName and tooltipPetName ~= "" then
                    local displayName = tooltipPetName
                    local displayIcon = freshIcon or iconFileDataID or "Interface\\Icons\\INV_Pet_BabyBlizzardBear"
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. displayName .. "]|r")
                    
                    self:ShowLootNotification(itemID, displayLink, displayName, "Pet", displayIcon)
                else
                    -- Tooltip parsing failed, use generic "Pet Cage" (acceptable)
                    local displayName = freshItemName or itemName or "Pet Cage"
                    local displayIcon = freshIcon or iconFileDataID or 132599 -- Generic cage icon
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. displayName .. "]|r")
                    
                    self:ShowLootNotification(itemID, displayLink, displayName, "Pet", displayIcon)
                end
            end)
        end
        return
    end
    
    -- ========================================
    -- 3. TOY DETECTION
    -- ========================================
    if C_ToyBox and C_ToyBox.GetToyInfo and PlayerHasToy then
        local toyName = C_ToyBox.GetToyInfo(itemID)
        if toyName then
            -- Only show if NOT collected
            if not PlayerHasToy(itemID) then
                -- Use GetItemInfo for reliable name/icon (C_ToyBox.GetToyInfo sometimes returns itemID as string)
                C_Timer.After(0.15, function()
                    local freshItemName, freshItemLink, _, _, _, _, _, _, _, freshIcon = GetItemInfo(itemID)
                    
                    local displayName = freshItemName or itemName or toyName
                    local displayIcon = freshIcon or iconFileDataID or "Interface\\Icons\\INV_Misc_Toy_01"
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. displayName .. "]|r")
                    
                    self:ShowLootNotification(itemID, displayLink, displayName, "Toy", displayIcon)
                end)
            end
            return
        end
    end
end

---Test loot notification system (Mounts, Pets, & Toys)
---With stacking system: all toasts can be shown at once (max 3 visible, rest queued)
function WarbandNexus:TestLootNotification(type)
    type = type and strlower(type) or "all"
    
    -- Special test: "spam" shows 5 toasts to test queue system
    if type == "spam" then
        for i = 1, 5 do
            local icons = {
                "Interface\\Icons\\Ability_Mount_Invincible",
                "Interface\\Icons\\INV_Pet_BabyBlizzardBear",
                "Interface\\Icons\\INV_Misc_Toy_01",
                "Interface\\Icons\\achievement_guildperk_bountifulbags",
                "Interface\\Icons\\INV_Misc_QuestionMark"
            }
            self:ShowToastNotification({
                icon = icons[i],
                title = "Test Toast #" .. i,
                message = "Testing stacking & queue system",
                titleColor = {0.6, 0.4, 0.9},
                autoDismiss = 6,
            })
        end
        self:Print("|cff00ff00Spawned 5 toasts! Max 3 visible, 2 queued.|r")
        return
    end
    
    if type == "mount" or type == "all" then
        self:ShowToastNotification({
            icon = "Interface\\Icons\\Ability_Mount_Invincible",
            title = "Test Mount",
            message = "You obtained this mount!",
            titleColor = {0.6, 0.4, 0.9},
            autoDismiss = 8,
            sound = 44335,
        })
        
        -- If only testing mount, stop here
        if type == "mount" then return end
    end
    
    if type == "pet" or type == "all" then
        -- No delay needed! Stacking system handles it
        self:ShowToastNotification({
            icon = "Interface\\Icons\\INV_Pet_BabyBlizzardBear",
            title = "Test Pet",
            message = "You obtained this pet!",
            titleColor = {0.6, 0.4, 0.9},
            autoDismiss = 8,
            sound = 44335,
        })
        
        -- If only testing pet, stop here
        if type == "pet" then return end
    end
    
    if type == "toy" or type == "all" then
        -- No delay needed! Stacking system handles it
        self:ShowToastNotification({
            icon = "Interface\\Icons\\INV_Misc_Toy_01",
            title = "Test Toy",
            message = "You obtained this toy!",
            titleColor = {0.6, 0.4, 0.9},
            autoDismiss = 8,
            sound = 44335,
        })
    end
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

