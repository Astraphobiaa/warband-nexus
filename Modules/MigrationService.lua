--[[
    WarbandNexus - Migration Service
    Handles database migrations and upgrades across versions
    
    Responsibilities:
    - One-time data migrations
    - Database schema upgrades
    - Backward compatibility fixes
    - Data format conversions
    - Version tracking and cache invalidation
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
---@class MigrationService
local MigrationService = {}
ns.MigrationService = MigrationService

--[[
    Check for addon version updates and invalidate caches if needed
    This ensures users get clean data after addon updates
]]
function MigrationService:CheckAddonVersion(db, addon)
    -- Get current addon version from Constants
    local ADDON_VERSION = ns.Constants and ns.Constants.ADDON_VERSION or "1.1.0"
    
    -- Get saved version from DB
    local savedVersion = db.global.addonVersion or "0.0.0"
    
    -- Check if version changed
    if savedVersion ~= ADDON_VERSION then
        DebugPrint(string.format("|cff9370DB[WN]|r New version detected: %s → %s", savedVersion, ADDON_VERSION))
        DebugPrint("|cffffcc00[WN]|r Invalidating all caches for clean migration...")
        
        -- Force refresh all caches (delegate to DatabaseOptimizer)
        if addon.ForceRefreshAllCaches then
            addon:ForceRefreshAllCaches()
        end
        
        -- Update saved version
        db.global.addonVersion = ADDON_VERSION
        
        DebugPrint("|cff00ff00[WN]|r Cache invalidation complete! All data will refresh on next login.")
    end
end

-- Schema version: Increment on breaking DB changes to trigger full reset
local CURRENT_SCHEMA_VERSION = 3

--[[
    Run all database migrations
    Called during OnInitialize after database is loaded
]]
function MigrationService:RunMigrations(db)
    if not db then
        DebugPrint("|cffff0000[WN MigrationService]|r No database provided!")
        return
    end

    -- Schema version check: full reset if outdated
    if self:CheckSchemaReset(db) then
        return -- Everything was wiped and re-created from defaults, no further migrations needed
    end

    self:MigrateThemeColors(db)
    self:MigrateReputationMetadata(db)
    self:MigrateReputationToV2(db)
    self:MigrateGenderField(db)
    self:MigrateTrackingField(db)
    self:MigrateTrackingConfirmed(db)
    self:MigrateGoldFormat(db)
end

--[[
    Full SavedVariables reset when schema version is outdated.
    Wipes global/char/profile data so AceDB re-creates from defaults.
    @return boolean - true if reset was performed
]]
function MigrationService:CheckSchemaReset(db)
    local storedVersion = db.global._schemaVersion or 0
    if storedVersion >= CURRENT_SCHEMA_VERSION then
        return false
    end

    _G.print("|cff6a0dadWarband Nexus|r: Database schema updated (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. "). Performing full reset...")

    -- Wipe global and char data (plain tables, AceDB re-populates via __index)
    if db.global then wipe(db.global) end
    if db.char then wipe(db.char) end

    -- Reset profile via AceDB API so defaults are properly re-applied
    if db.ResetProfile then
        db:ResetProfile(nil, true) -- silent reset, no callback fire
    elseif db.profile then
        wipe(db.profile)
    end

    -- Stamp current schema version
    db.global._schemaVersion = CURRENT_SCHEMA_VERSION

    _G.print("|cff6a0dadWarband Nexus|r: Reset complete. All data will be rescanned automatically.")
    return true
end

--[[
    Migrate theme colors to new format with calculated variations
]]
function MigrationService:MigrateThemeColors(db)
    if not db.profile.themeColors then
        return
    end
    
    local colors = db.profile.themeColors
    
    -- If missing calculated variations, regenerate them
    if not colors.accentDark or not colors.tabHover then
        if ns.UI_CalculateThemeColors and colors.accent then
            local accent = colors.accent
            db.profile.themeColors = ns.UI_CalculateThemeColors(accent[1], accent[2], accent[3])
            DebugPrint("|cff9370DB[WN MigrationService]|r Migrated theme colors to calculated format")
        end
    end
end

--[[
    Migrate reputation data to v2 with isAccountWide field
]]
function MigrationService:MigrateReputationMetadata(db)
    if not db.global.reputations or db.global.reputationMigrationV2 then
        return
    end
    
    local needsMigration = false
    for factionID, repData in pairs(db.global.reputations) do
        if repData and repData.isAccountWide == nil then
            needsMigration = true
            break
        end
    end
    
    if needsMigration then
        DebugPrint("|cffff9900[WN MigrationService]|r Migrating reputation data to v2 (API-based)")
        db.global.reputationMigrationV2 = true
        -- The actual update will happen on next ScanReputations() which runs on PLAYER_ENTERING_WORLD
    end
end

--[[
    Add gender field to existing characters
    Runs on every login until all characters are fixed
]]
function MigrationService:MigrateGenderField(db)
    if not db.global.characters then
        return
    end
    
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    local currentKey = currentName .. "-" .. currentRealm
    
    -- Fix current character's gender on every login (in case it's wrong)
    if db.global.characters[currentKey] then
        local savedGender = db.global.characters[currentKey].gender
        
        -- Detect current gender using C_PlayerInfo (most reliable)
        local detectedGender = UnitSex("player")
        local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
        if raceInfo and raceInfo.gender ~= nil then
            detectedGender = (raceInfo.gender == 1) and 3 or 2
        end
        
        -- Update if different or missing
        if not savedGender or savedGender ~= detectedGender then
            db.global.characters[currentKey].gender = detectedGender
            DebugPrint(string.format("|cff9370DB[WN MigrationService]|r Gender auto-fix: %s → %s", 
                savedGender and (savedGender == 3 and "Female" or "Male") or "Unknown",
                detectedGender == 3 and "Female" or "Male"))
        end
    end
    
    -- ONE-TIME: Add default gender to characters that don't have it
    if not db.global.genderMigrationV1 then
        local updated = 0
        for charKey, charData in pairs(db.global.characters) do
            if charData and not charData.gender then
                -- Default to male (2) - will be corrected on next login
                charData.gender = 2
                updated = updated + 1
            end
        end
        if updated > 0 then
            DebugPrint("|cff9370DB[WN MigrationService]|r Gender migration: Added default gender to " .. updated .. " characters")
        end
        db.global.genderMigrationV1 = true
    end
end

--[[
    Add isTracked field to existing characters
]]
function MigrationService:MigrateTrackingField(db)
    if not db.global.characters or db.global.trackingMigrationV1 then
        return
    end
    
    local updated = 0
    for charKey, charData in pairs(db.global.characters) do
        if charData and charData.isTracked == nil then
            -- Existing characters automatically tracked (backward compatibility)
            charData.isTracked = true
            updated = updated + 1
        end
    end
    
    if updated > 0 then
        DebugPrint("|cff9370DB[WN MigrationService]|r Tracking migration: Marked " .. updated .. " existing characters as tracked")
    end
    
    db.global.trackingMigrationV1 = true
end

--[[
    Convert totalCopper to gold/silver/copper breakdown
    Prevents SavedVariables from exceeding 32-bit limits
    Runs on EVERY load to ensure data integrity
]]
---Migrate reputation cache to v2.0.0 (complete rewrite)
function MigrationService:MigrateReputationToV2(db)
    if not db or not db.global then
        return
    end
    
    local oldCache = db.global.reputationCache
    local newCache = db.global.reputationData
    
    -- If new cache exists with correct version, no migration needed
    if newCache and newCache.version == ns.Constants.REPUTATION_CACHE_VERSION then
        return
    end
    
    DebugPrint("|cffffcc00[WN MigrationService]|r Migrating reputation to v2.0.0...")
    
    -- STRATEGY: Complete wipe and rescan
    -- Reason: Data structure is completely different (normalized progress, type-safe)
    
    -- Clear old cache
    if oldCache then
        local oldVersion = oldCache.version or "unknown"
        local oldCount = 0
        if oldCache.factions then
            for _ in pairs(oldCache.factions) do oldCount = oldCount + 1 end
        end
        DebugPrint("|cffffcc00[WN]|r Clearing old cache (v" .. oldVersion .. ", " .. oldCount .. " factions)")
        db.global.reputationCache = nil
    end
    
    -- Initialize new cache structure
    db.global.reputationData = {
        version = ns.Constants.REPUTATION_CACHE_VERSION,
        lastScan = 0,
        factions = {},
        headers = {},
    }
    
    DebugPrint("|cff00ff00[WN]|r Reputation migration complete - new cache initialized")
    DebugPrint("|cff00ff00[WN]|r Full rescan will trigger automatically on Reputation tab open")
end

---Migrate reputation cache to v2.0.0 (complete rewrite)
function MigrationService:MigrateReputationToV2(db)
    if not db or not db.global then
        return
    end
    
    local oldCache = db.global.reputationCache
    local newCache = db.global.reputationData
    
    -- If new cache exists with correct version, no migration needed
    if newCache and newCache.version == ns.Constants.REPUTATION_CACHE_VERSION and newCache.accountWide and newCache.characters then
        return  -- Already migrated to v2.1
    end
    
    DebugPrint("|cffffcc00[WN MigrationService]|r Migrating reputation to v2.1.0 (per-character storage)...")
    
    -- STRATEGY: Complete wipe and rescan
    -- Reason: Data structure is completely different (v2.1: accountWide + per-character)
    
    -- Clear old cache (any version)
    if oldCache then
        local oldVersion = oldCache.version or "unknown"
        local oldCount = 0
        if oldCache.factions then
            for _ in pairs(oldCache.factions) do oldCount = oldCount + 1 end
        end
        DebugPrint("|cffffcc00[WN]|r Clearing old cache (v" .. oldVersion .. ", " .. oldCount .. " factions)")
        db.global.reputationCache = nil
    end
    
    -- Also clear v2.0 cache if exists (pre-per-character)
    if newCache and newCache.factions then
        DebugPrint("|cffffcc00[WN]|r Clearing v2.0 cache (upgrading to v2.1 per-character storage)")
    end
    
    -- Initialize new cache structure (v2.1: Per-character storage)
    db.global.reputationData = {
        version = ns.Constants.REPUTATION_CACHE_VERSION,
        lastScan = 0,
        accountWide = {},    -- Account-wide reputations
        characters = {},     -- Per-character reputations
        headers = {},
    }
    
    DebugPrint("|cff00ff00[WN]|r Reputation migration complete - v2.1 cache initialized (per-character storage)")
    DebugPrint("|cff00ff00[WN]|r Full rescan will trigger automatically on Reputation tab open")
end

--[[
    Add trackingConfirmed flag to legacy tracked characters
    Prevents tracking popup from appearing for existing tracked characters
]]
function MigrationService:MigrateTrackingConfirmed(db)
    if not db.global.characters then
        return
    end
    
    local migratedCount = 0
    
    for charKey, charData in pairs(db.global.characters) do
        -- If character is tracked but doesn't have trackingConfirmed flag, add it
        if charData.isTracked == true and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
            migratedCount = migratedCount + 1
            DebugPrint(string.format("|cff00ff00[Migration]|r Added trackingConfirmed flag to: %s", charKey))
        end
        
        -- Also add flag to untracked characters with explicit isTracked=false
        if charData.isTracked == false and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
            migratedCount = migratedCount + 1
            DebugPrint(string.format("|cff00ff00[Migration]|r Added trackingConfirmed flag to untracked: %s", charKey))
        end
    end
    
    if migratedCount > 0 then
        DebugPrint(string.format("|cff00ff00[Migration]|r trackingConfirmed flag added to %d characters", migratedCount))
    end
end

function MigrationService:MigrateGoldFormat(db)
    if not db.global.characters then
        return
    end
    
    local migrated = 0
    
    -- Migrate characters
    for charKey, charData in pairs(db.global.characters) do
        if charData then
            -- If old totalCopper exists, convert to breakdown
            if charData.totalCopper then
                local totalCopper = math.floor(tonumber(charData.totalCopper) or 0)
                charData.gold = math.floor(totalCopper / 10000)
                charData.silver = math.floor((totalCopper % 10000) / 100)
                charData.copper = math.floor(totalCopper % 100)
                -- DELETE old field to prevent overflow
                charData.totalCopper = nil
                migrated = migrated + 1
            end
            
            -- If very old format exists (gold/silver/copper as separate fields), ensure floored
            if charData.gold or charData.silver or charData.copper then
                charData.gold = math.floor(tonumber(charData.gold) or 0)
                charData.silver = math.floor(tonumber(charData.silver) or 0)
                charData.copper = math.floor(tonumber(charData.copper) or 0)
            end
            
            -- CRITICAL: Delete ALL legacy fields that might cause overflow
            charData.goldAmount = nil
            charData.silverAmount = nil
            charData.copperAmount = nil
        end
    end
    
    -- Migrate warband bank
    if db.global.warbandBank then
        local wb = db.global.warbandBank
        
        -- If old totalCopper exists, convert to breakdown
        if wb.totalCopper then
            local totalCopper = math.floor(tonumber(wb.totalCopper) or 0)
            wb.gold = math.floor(totalCopper / 10000)
            wb.silver = math.floor((totalCopper % 10000) / 100)
            wb.copper = math.floor(totalCopper % 100)
            wb.totalCopper = nil  -- DELETE to prevent overflow
            migrated = migrated + 1
        end
        
        -- Ensure breakdown values are integers
        if wb.gold or wb.silver or wb.copper then
            wb.gold = math.floor(tonumber(wb.gold) or 0)
            wb.silver = math.floor(tonumber(wb.silver) or 0)
            wb.copper = math.floor(tonumber(wb.copper) or 0)
        end
        
        -- Delete legacy fields
        wb.goldAmount = nil
        wb.silverAmount = nil
        wb.copperAmount = nil
    end
    
    if migrated > 0 then
        DebugPrint("|cff9370DB[WN MigrationService]|r Gold format migration: Converted " .. migrated .. " entries")
    end
end

return MigrationService
