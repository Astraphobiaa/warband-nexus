--[[
    Warband Nexus - Character Service
    Manages character tracking, favorites, and character-specific operations
    Extracted from Core.lua for proper separation of concerns
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
---@class CharacterService
local CharacterService = {}
ns.CharacterService = CharacterService

--============================================================================
-- CHARACTER TRACKING
--============================================================================

---Confirm character tracking status and update database
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
---@param isTracked boolean Whether to track this character
function CharacterService:ConfirmCharacterTracking(addon, charKey, isTracked)
    if not addon.db or not addon.db.global then return end
    
    DebugPrint("|cff9370DB[WN CharacterService]|r ConfirmCharacterTracking: " .. charKey .. " = " .. tostring(isTracked))
    
    -- Initialize character entry if it doesn't exist
    if not addon.db.global.characters then
        addon.db.global.characters = {}
    end
    
    if not addon.db.global.characters[charKey] then
        addon.db.global.characters[charKey] = {}
    end
    
    -- Set tracking status
    addon.db.global.characters[charKey].isTracked = isTracked
    addon.db.global.characters[charKey].lastSeen = time()
    addon.db.global.characters[charKey].trackingConfirmed = true  -- User made a choice, don't ask again
    
    -- HYBRID: Broadcast event for modules to react (event-driven component)
    addon:SendMessage("WN_CHARACTER_TRACKING_CHANGED", {
        charKey = charKey,
        isTracked = isTracked
    })
    
    if isTracked then
        addon:Print("|cff00ff00Character tracking enabled.|r Data collection will begin.")
        
        -- CRITICAL: Reset characterSaved flag (in case of DB wipe without reload)
        addon.characterSaved = false
        
        -- STEP 1: Register event listeners (for real-time updates)
        C_Timer.After(0.05, function()
            local addonInstance = _G.WarbandNexus or addon
            
            -- Register Items Cache events (BAG_UPDATE, BANKFRAME_OPENED, etc.)
            if addonInstance and addonInstance.InitializeItemsCache then
                addonInstance:InitializeItemsCache()
            end
            
            -- Register Currency Cache events (CURRENCY_DISPLAY_UPDATE, PLAYER_MONEY)
            if addonInstance and addonInstance.RegisterCurrencyCacheEvents then
                addonInstance:RegisterCurrencyCacheEvents()
            end
            
            -- Register Reputation Cache events
            if addonInstance and addonInstance.RegisterReputationCacheEvents then
                addonInstance:RegisterReputationCacheEvents()
            end
            
            -- Register PvE Cache events (M+, Vault, etc.)
            if addonInstance and addonInstance.RegisterPvECacheEvents then
                addonInstance:RegisterPvECacheEvents()
            end
            
            DebugPrint("|cff00ff00[CharacterService]|r Event listeners registered for tracked character")
        end)
        
        -- STEP 2: Initial character data save (basic info)
        C_Timer.After(0.1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.SaveCharacter then
                addonInstance:SaveCharacter()
                DebugPrint("|cff00ff00[CharacterService]|r Initial character data saved")
            end
        end)
        
        -- STEP 3: Trigger items scan (fixes ItemsUI empty on first tracking)
        C_Timer.After(0.2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.ScanInventoryBags then
                local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
                addonInstance:ScanInventoryBags(charKey)
                
                -- Update loading state
                if ns.ItemsLoadingState then
                    ns.ItemsLoadingState.isLoading = false
                    ns.ItemsLoadingState.scanProgress = 100
                    ns.ItemsLoadingState.currentStage = nil
                end
            end
        end)
        
        -- STEP 4: Trigger reputation scan
        C_Timer.After(1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.ScanReputations then
                addonInstance:ScanReputations()
            end
        end)
        
        -- STEP 5: Trigger currency scan
        C_Timer.After(1.5, function()
            if ns.CurrencyCache and ns.CurrencyCache.PerformFullScan then
                ns.CurrencyCache:PerformFullScan(true)  -- bypass throttle
            end
        end)
        
        -- STEP 6: Force item level update (triggers PLAYER_EQUIPMENT_CHANGED)
        C_Timer.After(1.2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.UpdateCharacterCache then
                addonInstance:UpdateCharacterCache("itemLevel")
                DebugPrint("|cff00ff00[CharacterService]|r Forced item level update")
            end
        end)
        
        -- STEP 7: Re-save character data (ensures all data is fresh)
        C_Timer.After(1.8, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance then
                -- Reset flag to allow second save
                addonInstance.characterSaved = false
                
                if addonInstance.SaveCharacter then
                    addonInstance:SaveCharacter()
                    DebugPrint("|cff00ff00[CharacterService]|r Character data refreshed (full save)")
                end
            end
        end)
        
        -- STEP 8: Trigger UI refresh (show collected data)
        C_Timer.After(2.2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.RefreshUI then
                addonInstance:RefreshUI()
            end
        end)
    else
        addon:Print("|cffff8800Character tracking disabled.|r Running in read-only mode.")
        
        -- Save minimal character data for untracked characters
        addon.characterSaved = false  -- Reset flag
        C_Timer.After(0.1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.SaveCharacter then
                addonInstance:SaveCharacter()  -- Will call SaveMinimalCharacterData
            end
            
            -- Refresh UI to show minimal data
            C_Timer.After(0.5, function()
                if addonInstance and addonInstance.RefreshUI then
                    addonInstance:RefreshUI()
                end
            end)
        end)
    end
    
    DebugPrint("|cff00ff00[WN CharacterService]|r Tracking status updated")
end

---Check if current character is tracked
---@param addon table The WarbandNexus addon instance
---@return boolean true if tracked, false if untracked or not found
function CharacterService:IsCharacterTracked(addon)
    -- Safety check: addon must exist
    if not addon then
        return false
    end
    
    local charKey = ns.Utilities:GetCharacterKey()
    
    if not addon.db or not addon.db.global or not addon.db.global.characters then
        return false
    end
    
    local charData = addon.db.global.characters[charKey]
    
    -- Default to false for new characters (require explicit opt-in)
    if not charData then
        return false
    end
    
    -- CRITICAL: Explicit true check - only track if user explicitly enabled tracking
    -- nil or false = not tracked (requires user action to enable)
    return charData.isTracked == true
end

---Enable tracking for current character
---@param addon table The WarbandNexus addon instance
function CharacterService:EnableTracking(addon)
    if not addon then
        return
    end
    local charKey = ns.Utilities:GetCharacterKey()
    self:ConfirmCharacterTracking(addon, charKey, true)
end

---Show character tracking confirmation dialog (Custom UI)
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
function CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
    DebugPrint("|cff9370DB[WN CharacterService]|r ShowCharacterTrackingConfirmation for " .. charKey)
    
    -- CRITICAL: If dialog already exists and is visible, don't create a new one
    if addon.trackingDialog and addon.trackingDialog:IsVisible() then
        DebugPrint("|cffffcc00[WN CharacterService]|r Tracking dialog already visible, skipping...")
        return
    end
    
    -- Clean up old StaticPopup if it exists (legacy system)
    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = nil
    
    -- Create custom dialog frame
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(480, 210)  -- Compact size
    dialog:SetPoint("CENTER", 0, 180)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")  -- Above everything
    dialog:SetFrameLevel(500)  -- Very high level
    
    -- Backdrop (FULLY OPAQUE - solid background)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",  -- Solid white texture
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 1,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)  -- Alpha = 1 (fully opaque)
    dialog:SetBackdropBorderColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 1)
    
    -- Make draggable
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- NO CLOSE BUTTON - User must make a choice
    
    -- Title (Centered)
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -20)
    titleText:SetText("|cff9370DBWarband Nexus|r")
    
    -- Main question
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -16)
    questionText:SetWidth(460)
    questionText:SetJustifyH("CENTER")
    questionText:SetText("Do you want to track this character?")
    
    -- Character name with class color
    local charName = charKey:match("^([^%-]+)") or charKey
    local charRealm = charKey:match("%-(.+)") or GetRealmName()
    
    -- Get character data for class color
    local charData = addon.db and addon.db.global and addon.db.global.characters and addon.db.global.characters[charKey]
    local classColor = "|cffffcc00"  -- Default gold
    
    if charData and charData.class then
        local classColorTable = C_ClassColor and C_ClassColor.GetClassColor(charData.class)
        if classColorTable then
            classColor = string.format("|cff%02x%02x%02x", classColorTable.r * 255, classColorTable.g * 255, classColorTable.b * 255)
        end
    end
    
    local charNameText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    charNameText:SetPoint("TOP", questionText, "BOTTOM", 0, -8)
    charNameText:SetText(classColor .. charName .. " - " .. charRealm .. "|r")
    
    -- Option boxes container
    local optionsY = -20
    
    -- Tracked option (LEFT) - now a BUTTON
    local trackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    trackedFrame:SetSize(200, 75)  -- Compact size
    trackedFrame:SetPoint("TOP", charNameText, "BOTTOM", -110, optionsY)
    trackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    trackedFrame:SetBackdropColor(0.1, 0.3, 0.2, 1)
    trackedFrame:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    
    -- Hover effect for Tracked card
    trackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.4, 0.25, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(0.3, 0.8, 0.4, 1)
    end)
    trackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    end)
    trackedFrame:SetScript("OnClick", function()
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local trackedTitle = ns.FontManager:CreateFontString(trackedFrame, "header", "OVERLAY")
    trackedTitle:SetPoint("TOP", 0, -12)
    trackedTitle:SetText("|cff00ff00Tracked|r")
    
    local trackedDesc = ns.FontManager:CreateFontString(trackedFrame, "body", "OVERLAY")
    trackedDesc:SetPoint("TOP", trackedTitle, "BOTTOM", 0, -5)
    trackedDesc:SetWidth(185)
    trackedDesc:SetJustifyH("CENTER")
    trackedDesc:SetText("|cff88ff88Full detailed data|r\n|cffffffffAll features enabled|r")
    
    -- Untracked option (RIGHT) - now a BUTTON
    local untrackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    untrackedFrame:SetSize(200, 75)  -- Compact size
    untrackedFrame:SetPoint("TOP", charNameText, "BOTTOM", 110, optionsY)
    untrackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    untrackedFrame:SetBackdropColor(0.3, 0.1, 0.1, 1)
    untrackedFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    
    -- Hover effect for Untracked card
    untrackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.15, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    untrackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    end)
    untrackedFrame:SetScript("OnClick", function()
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local untrackedTitle = ns.FontManager:CreateFontString(untrackedFrame, "header", "OVERLAY")
    untrackedTitle:SetPoint("TOP", 0, -12)
    untrackedTitle:SetText("|cffff4444Untracked|r")
    
    local untrackedDesc = ns.FontManager:CreateFontString(untrackedFrame, "body", "OVERLAY")
    untrackedDesc:SetPoint("TOP", untrackedTitle, "BOTTOM", 0, -5)
    untrackedDesc:SetWidth(185)
    untrackedDesc:SetJustifyH("CENTER")
    untrackedDesc:SetText("|cffff8888View-only mode|r\n|cffffffffBasic info only|r")
    
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference to prevent garbage collection
    addon.trackingDialog = dialog
end

---Show tracking change confirmation (smaller popup for Enable/Disable from Characters tab)
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
---@param charName string Character name (for display)
---@param enableTracking boolean True to enable, False to disable
function CharacterService:ShowTrackingChangeConfirmation(addon, charKey, charName, enableTracking)
    -- CRITICAL: If dialog already exists and is visible, don't create a new one
    if addon.trackingChangeDialog and addon.trackingChangeDialog:IsVisible() then
        return
    end
    
    -- Create custom confirmation dialog
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingChangeDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(440, 200)  -- Compact size
    dialog:SetPoint("CENTER", 0, 150)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")  -- Above everything
    dialog:SetFrameLevel(500)  -- Very high level
    
    -- Backdrop
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 1,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)
    dialog:SetBackdropBorderColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 1)
    
    -- Make draggable
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- Close button (X) - acts as Cancel
    local closeBtn = CreateFrame("Button", nil, dialog)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetNormalAtlas("transmog-icon-remove")
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.8)
    end)
    closeBtn:SetAlpha(0.8)
    
    -- Title
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -20)
    titleText:SetText("|cff9370DBConfirm Action|r")
    
    -- Question text
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -16)
    questionText:SetWidth(400)
    questionText:SetJustifyH("CENTER")
    
    if enableTracking then
        questionText:SetText(string.format("Enable tracking for |cffffcc00%s|r?", charName))
    else
        questionText:SetText(string.format("Disable tracking for |cffffcc00%s|r?", charName))
    end
    
    -- Yes/No Cards (clickable buttons)
    local cardWidth = 180
    local cardHeight = 70
    local cardSpacing = 20
    
    -- YES card (LEFT) - Green theme
    local yesCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    yesCard:SetSize(cardWidth, cardHeight)
    yesCard:SetPoint("TOP", questionText, "BOTTOM", -(cardWidth/2 + cardSpacing/2), -20)
    yesCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    yesCard:SetBackdropColor(0.1, 0.3, 0.2, 1)
    yesCard:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    
    -- Hover effect for YES
    yesCard:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.4, 0.25, 1)
        self:SetBackdropBorderColor(0.3, 0.8, 0.4, 1)
    end)
    yesCard:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    end)
    yesCard:SetScript("OnClick", function()
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, enableTracking)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local yesIcon = yesCard:CreateTexture(nil, "ARTWORK")
    yesIcon:SetAtlas("campaign-complete-seal-checkmark")
    yesIcon:SetSize(32, 32)
    yesIcon:SetPoint("TOP", 0, -10)
    
    local yesText = ns.FontManager:CreateFontString(yesCard, "body", "OVERLAY")
    yesText:SetPoint("TOP", yesIcon, "BOTTOM", 0, -4)
    yesText:SetText("|cff00ff00Confirm|r")
    
    -- NO card (RIGHT) - Red theme
    local noCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    noCard:SetSize(cardWidth, cardHeight)
    noCard:SetPoint("TOP", questionText, "BOTTOM", (cardWidth/2 + cardSpacing/2), -20)
    noCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    noCard:SetBackdropColor(0.3, 0.1, 0.1, 1)
    noCard:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    
    -- Hover effect for NO
    noCard:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    noCard:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    end)
    noCard:SetScript("OnClick", function()
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local noIcon = noCard:CreateTexture(nil, "ARTWORK")
    noIcon:SetAtlas("transmog-icon-remove")
    noIcon:SetSize(32, 32)
    noIcon:SetPoint("TOP", 0, -10)
    
    local noText = ns.FontManager:CreateFontString(noCard, "body", "OVERLAY")
    noText:SetPoint("TOP", noIcon, "BOTTOM", 0, -4)
    noText:SetText("|cffff4444Cancel|r")
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference
    addon.trackingChangeDialog = dialog
end

--============================================================================
-- FAVORITE CHARACTERS
--============================================================================

---Check if a character is marked as favorite
---@param addon table The WarbandNexus addon instance
---@param characterKey string Character key ("Name-Realm")
---@return boolean Whether the character is a favorite
function CharacterService:IsFavoriteCharacter(addon, characterKey)
    if not addon.db or not addon.db.global or not addon.db.global.favoriteCharacters then
        return false
    end
    
    for _, favKey in ipairs(addon.db.global.favoriteCharacters) do
        if favKey == characterKey then
            return true
        end
    end
    
    return false
end

---Toggle favorite status for a character
---@param addon table The WarbandNexus addon instance
---@param characterKey string Character key ("Name-Realm")
---@return boolean New favorite status
function CharacterService:ToggleFavoriteCharacter(addon, characterKey)
    if not addon.db or not addon.db.global then
        return false
    end
    
    DebugPrint("|cff9370DB[WN CharacterService]|r ToggleFavoriteCharacter: " .. characterKey)
    
    -- Initialize if needed
    if not addon.db.global.favoriteCharacters then
        addon.db.global.favoriteCharacters = {}
    end
    
    local favorites = addon.db.global.favoriteCharacters
    local isFavorite = self:IsFavoriteCharacter(addon, characterKey)
    
    if isFavorite then
        -- Remove from favorites
        for i, favKey in ipairs(favorites) do
            if favKey == characterKey then
                table.remove(favorites, i)
                addon:Print("|cffffff00Removed from favorites:|r " .. characterKey)
                DebugPrint("|cff00ff00[WN CharacterService]|r Favorite removed")
                break
            end
        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        addon:Print("|cffffd700Added to favorites:|r " .. characterKey)
        DebugPrint("|cff00ff00[WN CharacterService]|r Favorite added")
        return true
    end
end

---Get all favorite characters
---@param addon table The WarbandNexus addon instance
---@return table Array of favorite character keys
function CharacterService:GetFavoriteCharacters(addon)
    if not addon.db or not addon.db.global or not addon.db.global.favoriteCharacters then
        return {}
    end
    
    return addon.db.global.favoriteCharacters
end

--============================================================================
-- EXPORT
--============================================================================

return CharacterService
