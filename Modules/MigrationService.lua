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
        DebugPrint("|cff9370DB[WN Migration]|r [Migration Event] VERSION_UPDATE triggered (" .. savedVersion .. " → " .. ADDON_VERSION .. ")")
        
        -- Force refresh all caches (delegate to DatabaseOptimizer)
        if addon.ForceRefreshAllCaches then
            addon:ForceRefreshAllCaches()
        end
        
        -- Update saved version
        db.global.addonVersion = ADDON_VERSION
    end
end

-- Schema version: Increment on breaking DB changes to trigger full reset.
-- When incremented, ALL existing users get a one-time full SV wipe on next login (fresh start).
-- New users are unaffected (they start with empty DB + defaults).
local CURRENT_SCHEMA_VERSION = 13

---Run all database migrations. Returns true if a full schema reset was performed.
---@param db table AceDB instance
---@return boolean didReset
function MigrationService:RunMigrations(db)
    if not db then
        return false
    end

    -- Schema version check: full reset if outdated
    if self:CheckSchemaReset(db) then
        return true -- Everything was wiped; caller should re-apply defaults
    end

    self:MigrateThemeColors(db)
    self:MigrateReputationMetadata(db)
    self:MigrateReputationToV2(db)
    self:MigrateGenderField(db)
    self:MigrateTrackingField(db)
    self:MigrateTrackingConfirmed(db)
    self:MigrateGoldFormat(db)
    return false
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

    DebugPrint("|cff9370DB[WN Migration]|r [Migration Event] SCHEMA_RESET triggered (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. ")")
    _G.print("|cff6a0dadWarband Nexus|r: Database schema updated (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. "). Performing full reset...")

    -- Wipe global (itemStorage, reputationData, characters, etc.)
    if db.global then wipe(db.global) end

    -- CRITICAL: db.char is only the current character's slice. Wipe the raw SV char table
    -- so ALL characters (Y, Z, ...) are removed; otherwise other chars stay in SV.
    local raw = _G.WarbandNexusDB
    if raw and raw.char then
        wipe(raw.char)
    end
    if db.char then wipe(db.char) end

    -- Reset profile via AceDB API so defaults are properly re-applied
    if db.ResetProfile then
        db:ResetProfile(nil, true) -- silent reset, no callback fire
    elseif db.profile then
        wipe(db.profile)
    end

    -- Stamp current schema version (must be after wipe so it persists)
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
        -- Gender migration applied silently
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
    
    -- Tracking migration applied silently
    
    db.global.trackingMigrationV1 = true
end

---Migrate reputation cache to v2.1.0 (per-character storage)
---CRITICAL: This migration only converts OLD reputationCache → NEW reputationData format.
---It MUST NOT wipe existing reputationData when the structure is already valid.
---The version field inside reputationData is managed by ReputationCacheService (may differ
---from Constants.REPUTATION_CACHE_VERSION after version bumps) — that's normal and expected.
function MigrationService:MigrateReputationToV2(db)
    if not db or not db.global then
        return
    end
    
    local oldCache = db.global.reputationCache
    local newCache = db.global.reputationData
    
    -- If new cache exists with valid STRUCTURE, no migration needed.
    -- CRITICAL: Check structure (accountWide + characters tables exist), NOT version string.
    -- ReputationCacheService manages its own version field and may bump it independently.
    -- Matching on exact version here caused data wipe on every login when versions diverged.
    if newCache and type(newCache) == "table"
        and type(newCache.accountWide) == "table"
        and type(newCache.characters) == "table" then
        -- Structure is valid — clean up old cache if it still exists and return
        if oldCache then
            db.global.reputationCache = nil
        end
        return
    end
    
    -- No valid new cache exists — need to create one (fresh install or legacy migration)
    
    -- Clear old cache (any version)
    if oldCache then
        db.global.reputationCache = nil
    end
    
    -- Initialize new cache structure (v2.1: Per-character storage)
    -- Version set to "0" — ReputationCacheService will detect mismatch and trigger a rescan
    db.global.reputationData = {
        version = "0",
        lastScan = 0,
        accountWide = {},    -- Account-wide reputations
        characters = {},     -- Per-character reputations
        headers = {},
    }
    
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
        end
        
        -- Also add flag to untracked characters with explicit isTracked=false
        if charData.isTracked == false and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
            migratedCount = migratedCount + 1
        end
    end
    
    -- trackingConfirmed migration applied silently
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
    
    -- Gold format migration applied silently
end

return MigrationService
