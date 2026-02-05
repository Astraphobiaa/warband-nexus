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
    
    -- HYBRID: Broadcast event for modules to react (event-driven component)
    addon:SendMessage("WN_CHARACTER_TRACKING_CHANGED", {
        charKey = charKey,
        isTracked = isTracked
    })
    
    if isTracked then
        addon:Print("|cff00ff00Character tracking enabled.|r Data collection will begin.")
        
        -- CRITICAL: Reset characterSaved flag (in case of DB wipe without reload)
        addon.characterSaved = false
        
        -- Trigger reputation scan
        C_Timer.After(1, function()
            if addon.ScanReputations then
                addon:ScanReputations()
            end
        end)
        
        -- Trigger currency scan
        C_Timer.After(1.5, function()
            if ns.CurrencyCache and ns.CurrencyCache.PerformFullScan then
                ns.CurrencyCache:PerformFullScan(true)  -- bypass throttle
            end
        end)
        
        -- Trigger initial save
        C_Timer.After(2, function()
            if addon.SaveCharacter then
                addon:SaveCharacter()
            end
        end)
        
        -- Trigger UI refresh
        C_Timer.After(3, function()
            if addon.RefreshUI then
                addon:RefreshUI()
            end
        end)
    else
        addon:Print("|cffff8800Character tracking disabled.|r Running in read-only mode.")
    end
    
    DebugPrint("|cff00ff00[WN CharacterService]|r Tracking status updated")
end

---Check if current character is tracked
---@param addon table The WarbandNexus addon instance
---@return boolean true if tracked, false if untracked or not found
function CharacterService:IsCharacterTracked(addon)
    local charKey = ns.Utilities:GetCharacterKey()
    
    if not addon.db or not addon.db.global or not addon.db.global.characters then
        return false
    end
    
    local charData = addon.db.global.characters[charKey]
    
    -- Default to false for new characters (require explicit opt-in)
    if not charData then
        return false
    end
    
    -- Default to true for backward compatibility (existing characters)
    return charData.isTracked ~= false
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
    dialog:SetSize(500, 270)  -- Reduced height
    dialog:SetPoint("CENTER", 0, 180)  -- Much higher up
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(100)
    
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
    
    -- Character name
    local charName = charKey:match("^([^%-]+)") or charKey
    local charNameText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    charNameText:SetPoint("TOP", questionText, "BOTTOM", 0, -8)
    charNameText:SetText("|cffffcc00" .. charName .. "|r")
    
    -- Option boxes container
    local optionsY = -20
    
    -- Tracked option (LEFT)
    local trackedFrame = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    trackedFrame:SetSize(220, 70)
    trackedFrame:SetPoint("TOP", charNameText, "BOTTOM", -120, optionsY)  -- More left offset
    trackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    trackedFrame:SetBackdropColor(0.1, 0.3, 0.2, 1)  -- Alpha = 1 (fully opaque)
    trackedFrame:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    
    local trackedTitle = ns.FontManager:CreateFontString(trackedFrame, "body", "OVERLAY")
    trackedTitle:SetPoint("TOP", 0, -10)
    trackedTitle:SetText("|cff00ff00Tracked|r")
    
    local trackedDesc = ns.FontManager:CreateFontString(trackedFrame, "small", "OVERLAY")
    trackedDesc:SetPoint("TOP", trackedTitle, "BOTTOM", 0, -6)
    trackedDesc:SetWidth(200)
    trackedDesc:SetJustifyH("CENTER")
    trackedDesc:SetText("|cffffffffData collection, API calls,\nnotifications|r")  -- White
    
    -- Untracked option (RIGHT) - RED theme
    local untrackedFrame = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    untrackedFrame:SetSize(220, 70)
    untrackedFrame:SetPoint("TOP", charNameText, "BOTTOM", 120, optionsY)  -- More right offset
    untrackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    untrackedFrame:SetBackdropColor(0.3, 0.1, 0.1, 1)  -- Red background (fully opaque)
    untrackedFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)  -- Red border
    
    local untrackedTitle = ns.FontManager:CreateFontString(untrackedFrame, "body", "OVERLAY")
    untrackedTitle:SetPoint("TOP", 0, -10)
    untrackedTitle:SetText("|cffff4444Untracked|r")  -- Red title
    
    local untrackedDesc = ns.FontManager:CreateFontString(untrackedFrame, "small", "OVERLAY")
    untrackedDesc:SetPoint("TOP", untrackedTitle, "BOTTOM", 0, -6)
    untrackedDesc:SetWidth(200)
    untrackedDesc:SetJustifyH("CENTER")
    untrackedDesc:SetText("|cffffffffRead-only mode,\nno data updates|r")  -- White
    
    -- Buttons (centered between cards and bottom)
    local buttonWidth = 210
    local buttonHeight = 34
    
    -- Yes button - centered under Tracked card
    local yesButton = ns.UI_CreateThemedButton(dialog, "Yes, Track This Character", buttonWidth, buttonHeight)
    yesButton:SetPoint("TOP", trackedFrame, "BOTTOM", 0, -22)  -- 22px gap
    yesButton:SetScript("OnClick", function()
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    -- No button - centered under Untracked card
    local noButton = ns.UI_CreateThemedButton(dialog, "No, Read-Only Mode", buttonWidth, buttonHeight)
    noButton:SetPoint("TOP", untrackedFrame, "BOTTOM", 0, -22)  -- 22px gap
    noButton:SetScript("OnClick", function()
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    -- Info text at bottom (small, centered, warning yellow)
    local infoText = ns.FontManager:CreateFontString(dialog, "small", "OVERLAY")
    infoText:SetPoint("BOTTOM", 0, 16)  -- More space from bottom
    infoText:SetWidth(460)
    infoText:SetJustifyH("CENTER")
    infoText:SetText("|cffffcc00You can change tracking status anytime in Settings|r")  -- Gold/Yellow
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference to prevent garbage collection
    addon.trackingDialog = dialog
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
