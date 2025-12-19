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
    -- Just a placeholder - CollectionManager handles everything now
    -- NotificationManager only provides toast display functions
end

---Show collectible toast notification (called by CollectionManager)
---@param data table {type, name, icon} from CollectionManager
function WarbandNexus:ShowCollectibleToast(data)
    if not data or not data.type or not data.name then return end
    
    -- Capitalize type for display
    local typeCapitalized = data.type:sub(1,1):upper() .. data.type:sub(2)
    
    -- Show toast using existing system
    self:ShowLootNotification(
        0, -- itemID not needed for display
        "|cff0070dd[" .. data.name .. "]|r", -- Fake link
        data.name,
        typeCapitalized,
        data.icon
    )
end

---Check if item is a collectible we DON'T already own
---@param itemID number The item ID
---@param containerHyperlink string|nil Optional hyperlink
---@return boolean True if uncollected mount/pet/toy
function WarbandNexus:IsUncollectedItem(itemID, containerHyperlink)
    self:Debug("=== IsUncollectedItem START for itemID=" .. itemID)
    self:Debug("containerHyperlink=" .. tostring(containerHyperlink))
    
    local itemName, itemLink, _, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(itemID)
    
    self:Debug("GetItemInfo result: itemName=" .. tostring(itemName) .. " classID=" .. tostring(classID) .. " subclassID=" .. tostring(subclassID))
    
    if not classID then
        self:Debug("No classID for item " .. itemID .. ", requesting load...")
        C_Item.RequestLoadItemDataByID(itemID)
        return false
    end
    
    -- MOUNT (classID 15, subclass 5)
    if classID == 15 and subclassID == 5 then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        self:Debug("Mount check: itemID=" .. itemID .. " mountID=" .. tostring(mountID))
        if mountID then
            local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            self:Debug("Mount " .. (name or "?") .. " isCollected=" .. tostring(isCollected))
            return name and not isCollected
        end
    end
    
    -- PET (classID 17)
    if classID == 17 then
        self:Debug("*** PET DETECTED (classID=17) ***")
        local speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        self:Debug("C_PetJournal.GetPetInfoByItemID returned: " .. tostring(speciesID))
        
        -- TWW: Try extracting from hyperlink if API fails
        if not speciesID and containerHyperlink then
            self:Debug("Trying to extract speciesID from hyperlink...")
            speciesID = tonumber(containerHyperlink:match("|Hbattlepet:(%d+):"))
            self:Debug("Extracted speciesID from hyperlink: " .. tostring(speciesID))
        end
        
        self:Debug("Final speciesID for pet check: " .. tostring(speciesID))
        
        if speciesID then
            -- Get collection status
            local numOwned, maxAllowed = C_PetJournal.GetNumCollectedInfo(speciesID)
            self:Debug("Pet species " .. speciesID .. " numOwned=" .. tostring(numOwned) .. " maxAllowed=" .. tostring(maxAllowed))
            
            -- Show notification if we don't own ANY of this pet
            local isUncollected = (numOwned or 0) == 0
            self:Debug("Pet isUncollected result: " .. tostring(isUncollected))
            return isUncollected
        else
            -- Couldn't get speciesID, show notification anyway (better to over-notify than under-notify)
            self:Debug("Pet species unknown, showing notification anyway (returning true)")
            return true
        end
    end
    
    -- TOY - Check first with PlayerHasToy (most reliable)
    if PlayerHasToy and PlayerHasToy(itemID) ~= nil then
        self:Debug("*** TOY DETECTED ***")
        local hasToy = PlayerHasToy(itemID)
        self:Debug("Toy check (PlayerHasToy): itemID=" .. itemID .. " hasToy=" .. tostring(hasToy))
        return not hasToy
    end
    
    self:Debug("=== IsUncollectedItem END: No collectible type matched, returning false")
    return false
end

---Check if a new item is a mount/pet/toy and show notification
---@param itemID number The item ID
---@param containerHyperlink string|nil Optional hyperlink from container (for battle pets)
function WarbandNexus:CheckNewCollectible(itemID, containerHyperlink)
    if not itemID then return end
    
    -- Force load item data (for icon/name cache)
    C_Item.RequestLoadItemDataByID(itemID)
    
    -- Get item info for classification
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, 
          itemStackCount, itemEquipLoc, iconFileDataID, sellPrice, classID, subclassID = GetItemInfo(itemID)
    
    -- Use container hyperlink if available (better for battle pets)
    if containerHyperlink then
        itemLink = containerHyperlink
    end
    
    -- ========================================
    -- 1. MOUNT DETECTION (Most reliable)
    -- ========================================
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID then
            -- Get mount info from Journal API (locale-correct, always accurate)
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, 
                  isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            
            -- ALWAYS show toast for bag items (don't check collection status)
            -- User just got this item in their bag, show notification
            if name then
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
        self:Debug("CheckNewCollectible: Pet detected, itemID=" .. itemID)
        
        -- Try to get speciesID from item
        local speciesID = nil
        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            local result = C_PetJournal.GetPetInfoByItemID(itemID)
            if type(result) == "number" then
                speciesID = result
            end
        end
        
        self:Debug("CheckNewCollectible: speciesID from API=" .. tostring(speciesID))
        
        if speciesID then
            -- SUCCESS: We have speciesID, use Pet Journal API (most reliable)
            local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            
            self:Debug("CheckNewCollectible: speciesName=" .. tostring(speciesName) .. " icon=" .. tostring(speciesIcon))
            
            if speciesName then
                C_Timer.After(0.15, function()
                    local freshItemName, freshItemLink = GetItemInfo(itemID)
                    local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. speciesName .. "]|r")
                    
                    self:Debug("CheckNewCollectible: Showing pet notification for " .. speciesName)
                    self:ShowLootNotification(speciesID, displayLink, speciesName, "Pet", speciesIcon)
                end)
            else
                self:Debug("CheckNewCollectible: No speciesName, can't show notification")
            end
        else
            -- TWW: Try to extract pet info from hyperlink (for caged pets)
            self:Debug("CheckNewCollectible: No speciesID from API, trying hyperlink parse. itemLink=" .. tostring(itemLink))
            
            local extractedSpeciesID, extractedPetName = nil, nil
            
            if itemLink then
                -- Extract speciesID from hyperlink
                extractedSpeciesID = tonumber(itemLink:match("|Hbattlepet:(%d+):"))
                -- Extract pet name from [Pet Name]
                extractedPetName = itemLink:match("%[(.-)%]")
            end
            
            self:Debug("CheckNewCollectible: Extracted from hyperlink - speciesID=" .. tostring(extractedSpeciesID) .. " name=" .. tostring(extractedPetName))
            
            if extractedSpeciesID and extractedPetName then
                -- We got both speciesID and name from hyperlink!
                local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(extractedSpeciesID)
                
                if speciesName then
                    C_Timer.After(0.15, function()
                        local freshItemName, freshItemLink = GetItemInfo(itemID)
                        local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. speciesName .. "]|r")
                        
                        self:Debug("CheckNewCollectible: Showing pet notification (from hyperlink) for " .. speciesName)
                        self:ShowLootNotification(extractedSpeciesID, displayLink, speciesName, "Pet", speciesIcon)
                    end)
                else
                    self:Debug("CheckNewCollectible: Hyperlink parse failed - no speciesName")
                end
            else
                -- FALLBACK: Can't extract from hyperlink either
                self:Debug("CheckNewCollectible: Hyperlink parse failed, trying tooltip as last resort")
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
                        -- All methods failed, use generic "Pet Cage"
                        local displayName = freshItemName or itemName or "Pet Cage"
                        local displayIcon = freshIcon or iconFileDataID or 132599 -- Generic cage icon
                        local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. displayName .. "]|r")
                        
                        self:ShowLootNotification(itemID, displayLink, displayName, "Pet", displayIcon)
                    end
                end)
            end
        end
        return
    end
    
    -- ========================================
    -- 3. TOY DETECTION
    -- ========================================
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local toyName = C_ToyBox.GetToyInfo(itemID)
        if toyName then
            -- ALWAYS show toast for bag items (don't check collection status)
            -- User just got this item in their bag, show notification
            -- Use GetItemInfo for reliable name/icon (C_ToyBox.GetToyInfo sometimes returns itemID as string)
            C_Timer.After(0.15, function()
                local freshItemName, freshItemLink, _, _, _, _, _, _, _, freshIcon = GetItemInfo(itemID)
                
                local displayName = freshItemName or itemName or toyName
                local displayIcon = freshIcon or iconFileDataID or "Interface\\Icons\\INV_Misc_Toy_01"
                local displayLink = freshItemLink or itemLink or ("|cff0070dd[" .. displayName .. "]|r")
                
                self:ShowLootNotification(itemID, displayLink, displayName, "Toy", displayIcon)
            end)
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
                "Interface\\Icons\\Ability_Mount_Drake_Azure",
                "Interface\\Icons\\INV_Pet_BabyEbonWhelp"
            }
            local names = {"Test Mount " .. i, "Test Pet " .. i, "Test Toy " .. i, "Test Mount " .. (i+1), "Test Pet " .. (i+1)}
            local types = {"Mount", "Pet", "Toy", "Mount", "Pet"}
            
            C_Timer.After(i * 0.3, function()
                self:ShowLootNotification(i, "|cff0070dd[" .. names[i] .. "]|r", names[i], types[i], icons[i])
            end)
        end
        self:Print("|cff00ff005 test toasts queued! (spam test)|r")
        return
    end
    
    -- Show mount test
    if type == "mount" or type == "all" then
        self:ShowLootNotification(
            1234,
            "|cff0070dd[Test Mount]|r",
            "Test Mount",
            "Mount",
            "Interface\\Icons\\Ability_Mount_Invincible"
        )
        if type == "mount" then
            self:Print("|cff00ff00Test mount notification shown!|r")
            return
        end
    end
    
    -- Show pet test
    if type == "pet" or type == "all" then
        C_Timer.After(type == "all" and 0.5 or 0, function()
            self:ShowLootNotification(
                5678,
                "|cff0070dd[Test Pet]|r",
                "Test Pet",
                "Pet",
                "Interface\\Icons\\INV_Pet_BabyBlizzardBear"
            )
            if type == "pet" then
                self:Print("|cff00ff00Test pet notification shown!|r")
            end
        end)
        if type == "pet" then return end
    end
    
    -- Show toy test
    if type == "toy" or type == "all" then
        C_Timer.After(type == "all" and 1.0 or 0, function()
            self:ShowLootNotification(
                9012,
                "|cff0070dd[Test Toy]|r",
                "Test Toy",
                "Toy",
                "Interface\\Icons\\INV_Misc_Toy_01"
            )
            if type == "toy" then
                self:Print("|cff00ff00Test toy notification shown!|r")
            end
        end)
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing all 3 collectible types! (with stacking)|r")
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






