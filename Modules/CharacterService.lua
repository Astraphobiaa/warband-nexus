--[[
    Warband Nexus - Character Service
    Manages character tracking, favorites, and character-specific operations
    Extracted from Core.lua for proper separation of concerns
]]

local ADDON_NAME, ns = ...

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
    
    print("|cff9370DB[WN CharacterService]|r ConfirmCharacterTracking: " .. charKey .. " = " .. tostring(isTracked))
    
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
        -- Trigger initial save
        C_Timer.After(1, function()
            if addon.SaveCharacter then
                addon:SaveCharacter()
            end
        end)
        -- Show reload popup (systems need to reinitialize)
        C_Timer.After(1.5, function()
            if addon.ShowReloadPopup then
                addon:ShowReloadPopup()
            end
        end)
    else
        addon:Print("|cffff8800Character tracking disabled.|r Running in read-only mode.")
    end
    
    print("|cff00ff00[WN CharacterService]|r Tracking status updated")
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

---Show character tracking confirmation dialog
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
function CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
    print("|cff9370DB[WN CharacterService]|r ShowCharacterTrackingConfirmation for " .. charKey)
    
    -- Create popup dialog
    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = {
        text = "|cff00ccffWarband Nexus|r\n\nDo you want to track this character?\n\n|cffffffffTracked:|r Data collection, API calls, notifications\n|cffffffffUntracked:|r Read-only mode, no data updates",
        button1 = "Yes, Track This Character",
        button2 = "No, Read-Only Mode",
        OnAccept = function(self)
            local charKey = self.data
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
            end
        end,
        OnCancel = function(self)
            local charKey = self.data
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,  -- Force user to make a choice
        exclusive = true,
        preferredIndex = 3,
    }
    
    local dialog = StaticPopup_Show("WARBANDNEXUS_ADD_CHARACTER")
    if dialog then
        dialog.data = charKey
    end
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
    
    print("|cff9370DB[WN CharacterService]|r ToggleFavoriteCharacter: " .. characterKey)
    
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
                print("|cff00ff00[WN CharacterService]|r Favorite removed")
                break
            end
        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        addon:Print("|cffffd700Added to favorites:|r " .. characterKey)
        print("|cff00ff00[WN CharacterService]|r Favorite added")
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
