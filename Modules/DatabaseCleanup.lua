--[[
    Warband Nexus - Database Cleanup Module
    Removes duplicate characters and deprecated storage
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local WarbandNexus = ns.WarbandNexus

--============================================================================
-- DATABASE CLEANUP
--============================================================================

---Clean duplicate characters and deprecated storage
---Should be called once on addon load
function WarbandNexus:CleanupDatabase()
    if not self.db or not self.db.global then
        return
    end
    
    -- Check if cleanup already ran this session (to prevent re-cleaning saved data)
    if self.db.profile.lastCleanupSession then
        local currentSession = time()
        -- If cleanup ran less than 1 hour ago, skip
        if (currentSession - self.db.profile.lastCleanupSession) < 3600 then
            return { duplicates = 0, invalidEntries = 0, deprecatedStorage = 0 }
        end
    end
    
    local cleaned = {
        duplicates = 0,
        invalidEntries = 0,
        deprecatedStorage = 0,
    }
    
    -- Step 1: Remove invalid character entries (no name/realm)
    if self.db.global.characters then
        local toRemove = {}
        
        for charKey, charData in pairs(self.db.global.characters) do
            if not charData.name or not charData.realm or charData.name == "" or charData.realm == "" then
                toRemove[charKey] = true
                cleaned.invalidEntries = cleaned.invalidEntries + 1
            end
        end
        
        -- Remove invalid entries
        for key in pairs(toRemove) do
            self.db.global.characters[key] = nil
            DebugPrint("|cffff8000[WN Cleanup]|r Removed invalid character: " .. key)
        end
    end
    
    -- Step 2: Remove duplicate characters (keep newest by lastSeen)
    if self.db.global.characters then
        local seen = {}  -- [normalizedKey] = originalKey
        local toRemove = {}
        
        for charKey, charData in pairs(self.db.global.characters) do
            -- Normalize key (remove spaces, lowercase)
            local normalizedName = (charData.name or ""):gsub("%s+", ""):lower()
            local normalizedRealm = (charData.realm or ""):gsub("%s+", ""):lower()
            local normalizedKey = normalizedName .. "-" .. normalizedRealm
            
            if seen[normalizedKey] then
                -- Duplicate found! Keep the one with newest lastSeen
                local existingKey = seen[normalizedKey]
                local existingData = self.db.global.characters[existingKey]
                local existingTime = existingData.lastSeen or 0
                local newTime = charData.lastSeen or 0
                
                if newTime > existingTime then
                    -- Current one is newer, remove old one
                    toRemove[existingKey] = true
                    seen[normalizedKey] = charKey
                    cleaned.duplicates = cleaned.duplicates + 1
                else
                    -- Existing one is newer, remove current one
                    toRemove[charKey] = true
                    cleaned.duplicates = cleaned.duplicates + 1
                end
            else
                seen[normalizedKey] = charKey
            end
        end
        
        -- Remove duplicates
        for key in pairs(toRemove) do
            self.db.global.characters[key] = nil
            DebugPrint("|cffff8000[WN Cleanup]|r Removed duplicate: " .. key)
        end
    end
    
    -- Step 3: Clean deprecated storage structures
    if self.db.global.personalBanks then
        -- Old compressed storage (deprecated)
        self.db.global.personalBanks = nil
        cleaned.deprecatedStorage = cleaned.deprecatedStorage + 1
    end
    
    if self.db.global.warbandBankV2 then
        -- Old compressed warband storage (deprecated)
        self.db.global.warbandBankV2 = nil
        cleaned.deprecatedStorage = cleaned.deprecatedStorage + 1
    end
    
    -- Step 4: Clean old per-character storage
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            -- Remove old storage fields (moved to ItemsCacheService)
            if charData.personalBank then
                charData.personalBank = nil
                cleaned.deprecatedStorage = cleaned.deprecatedStorage + 1
            end
            
            if charData.bags and charData.bags.items then
                -- Old bag storage format
                charData.bags = nil
                cleaned.deprecatedStorage = cleaned.deprecatedStorage + 1
            end
        end
    end
    
    -- Step 5: Clean old warband bank
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        -- Keep gold tracking, remove items (moved to ItemsCacheService)
        self.db.global.warbandBank.items = nil
        cleaned.deprecatedStorage = cleaned.deprecatedStorage + 1
    end
    
    -- Mark cleanup as done for this session
    if not self.db.profile.lastCleanupSession then
        self.db.profile.lastCleanupSession = 0
    end
    self.db.profile.lastCleanupSession = time()
    
    -- Silently return results (no spam in chat)
    return cleaned
end

---Force cleanup (slash command)
function WarbandNexus:ForceCleanupDatabase()
    DebugPrint("|cff00ff00[WN Cleanup]|r Starting forced database cleanup...")
    
    -- Reset session check to allow forced cleanup
    if self.db.profile.lastCleanupSession then
        self.db.profile.lastCleanupSession = 0
    end
    
    local result = self:CleanupDatabase()
    
    if result.duplicates == 0 and result.invalidEntries == 0 and result.deprecatedStorage == 0 then
        DebugPrint("|cff00ff00[WN Cleanup]|r Database is already clean!")
    else
        DebugPrint(string.format("|cff00ff00[WN Cleanup]|r Removed %d duplicate(s), %d invalid(s), %d deprecated storage(s)", 
            result.duplicates, result.invalidEntries, result.deprecatedStorage))
        DebugPrint("|cff00ff00[WN Cleanup]|r Please /reload to see changes.")
    end
end

-- Module loaded - verbose logging removed
