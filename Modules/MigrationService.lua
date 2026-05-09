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
local DebugPrint = ns.DebugPrint

local function PrintUserMessage(message)
    if not message or message == "" then return end
    local addon = _G.WarbandNexus
    if addon and addon.Print then
        addon:Print(message)
    else
        _G.print(message)
    end
end

---@class MigrationService
local MigrationService = {}
ns.MigrationService = MigrationService

--[[
    Single-roof version check.

    Three independent version axes are tracked under db.global.versions:
      - addon: bumps on every release. NEVER triggers cache invalidation by itself.
      - game:  Blizzard build (select(4, GetBuildInfo())). When this changes the
               WoW API surface may have shifted — invalidate API-bound caches.
      - cache.<name>: per-cache schema versions from Constants.VERSIONS.CACHE.
               Bump these manually when a cache's stored shape becomes
               incompatible. Each is checked independently; only the cache
               whose version moved is invalidated.

    Invalidation is non-destructive (resets cache.version field, keeps data) and
    always backs up the prior table to db.global.cacheBackups[name] first, so a
    misfire can be reverted via /wn ... or InvalidateCache/RestoreCacheBackup.
]]
function MigrationService:CheckVersions(db, addon)
    local Constants = ns.Constants or {}
    local currentAddon  = Constants.ADDON_VERSION or "0.0.0"
    local currentGame   = (select(4, GetBuildInfo()))
    local currentCacheV = (Constants.VERSIONS and Constants.VERSIONS.CACHE) or {}

    db.global.versions = db.global.versions or {}
    local v = db.global.versions
    v.cache = v.cache or {}

    -- Migrate legacy single-key db.global.addonVersion into the unified registry
    -- so existing users do not get a phantom "version changed" on first run.
    if db.global.addonVersion and not v.addon then
        v.addon = db.global.addonVersion
    end
    db.global.addonVersion = nil

    -- 1. Addon version: track only, never invalidate caches.
    if v.addon ~= currentAddon then
        DebugPrint("|cff9370DB[WN Migration]|r addon " .. tostring(v.addon) .. " → " .. tostring(currentAddon) .. " (no cache action)")
        v.addon = currentAddon
    end

    -- 2. Game build: invalidate API-bound caches (reputation, collection) whose
    --    server-side data shape may have changed after a patch.
    if currentGame and v.game ~= currentGame then
        DebugPrint("|cff9370DB[WN Migration]|r game build " .. tostring(v.game) .. " → " .. tostring(currentGame) .. " (invalidating API caches)")
        if addon.InvalidateCache then
            addon:InvalidateCache("reputation", "game_build")
            addon:InvalidateCache("collection", "game_build")
        end
        v.game = currentGame
    end

    -- 3. Per-cache schema bump: invalidate only the cache whose schema integer
    --    in Constants.VERSIONS.CACHE was raised in this release.
    for name, version in pairs(currentCacheV) do
        if v.cache[name] ~= version then
            local prev = v.cache[name]
            DebugPrint("|cff9370DB[WN Migration]|r cache schema '" .. name .. "' " .. tostring(prev) .. " → " .. tostring(version) .. " (invalidating)")
            if prev ~= nil and addon.InvalidateCache then
                addon:InvalidateCache(name, "schema_bump")
            end
            v.cache[name] = version
        end
    end
end

-- Backwards-compat alias: old callers still invoke CheckAddonVersion.
function MigrationService:CheckAddonVersion(db, addon)
    return self:CheckVersions(db, addon)
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
    self:MigrateRealmSuffixRepairFromCharKey(db)
    self:MigrateCharacterKeyNormalize(db)
    self:MigrateRestedDataReset(db)
    self:MigrateRarityMountSyncReseed(db)
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
    PrintUserMessage("|cff6a0dad" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r: " .. ((ns.L and ns.L["DATABASE_UPDATED_MSG"]) or "Database updated to a new version.") .. " (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. ")")

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

    PrintUserMessage("|cff6a0dad" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r: " .. ((ns.L and ns.L["MIGRATION_RESET_COMPLETE"]) or "Reset complete. All data will be rescanned automatically."))
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
    
    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey())
    if not currentKey then return end
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
        for charKey, charData in pairs(db.global.characters) do
            if charData and not charData.gender then
                -- Default to male (2) - will be corrected on next login
                charData.gender = 2
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
    
    for charKey, charData in pairs(db.global.characters) do
        if charData and charData.isTracked == nil then
            -- Existing characters automatically tracked (backward compatibility)
            charData.isTracked = true
        end
    end
    
    -- Tracking migration applied silently
    
    db.global.trackingMigrationV1 = true
end

--[[
    One-time: remove legacy rested XP fields from character records.
    Rested XP tracking was removed from the addon; keep DB schema clean.
]]
function MigrationService:MigrateRestedDataReset(db)
    if not db or not db.global or not db.global.characters then
        return
    end
    if db.global.restedDataRemovedV4 then
        return
    end

    for _, charData in pairs(db.global.characters) do
        if type(charData) == "table" then
            charData.restedXP = nil
            charData.xpMax = nil
            charData.xpCurrent = nil
            charData.isResting = nil
            charData.restedUpdatedAt = nil
        end
    end

    db.global.restedDataResetV1 = true
    db.global.restedDataResetV2 = true
    db.global.restedDataResetV3 = true
    db.global.restedDataRemovedV4 = true
end

--[[
    One-time per revision: clear informational legacyMountTrackerSeedComplete (preview / bookkeeping).
    SyncRarityMountAttemptsMax does NOT read this flag — merge already runs on a timer after login
    and after Statistics seed. Bump RARITY_MOUNT_SYNC_RESEED_REVISION after policy changes if you
    want users to see "seed done: false" once; for a manual re-merge run Rarity sync from Try Counter settings (Rarity enabled).
]]
local RARITY_MOUNT_SYNC_RESEED_REVISION = 1

function MigrationService:MigrateRarityMountSyncReseed(db)
    if not db or not db.global then
        return
    end
    local doneRev = db.global._rarityMountSyncReseedRevision or 0
    if doneRev >= RARITY_MOUNT_SYNC_RESEED_REVISION then
        return
    end
    local tc = db.global.tryCounts
    if tc and type(tc) == "table" then
        tc.legacyMountTrackerSeedComplete = false
    end
    db.global._rarityMountSyncReseedRevision = RARITY_MOUNT_SYNC_RESEED_REVISION
    DebugPrint("|cff9370DB[WN Migration]|r Rarity mount max-sync reseed (revision "
        .. tostring(RARITY_MOUNT_SYNC_RESEED_REVISION) .. "): legacyMountTrackerSeedComplete cleared")
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
    
    for charKey, charData in pairs(db.global.characters) do
        -- If character is tracked but doesn't have trackingConfirmed flag, add it
        if charData.isTracked == true and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
        end
        
        -- Also add flag to untracked characters with explicit isTracked=false
        if charData.isTracked == false and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
        end
    end
    
    -- trackingConfirmed migration applied silently
end

function MigrationService:MigrateGoldFormat(db)
    if not db.global.characters then
        return
    end
    
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

---Fix charData.realm when it was truncated by greedy "Name-Realm" parsing (realm contains hyphens, e.g. Azjol-Nerub).
---Table key is authoritative: first hyphen separates name from full realm suffix.
function MigrationService:MigrateRealmSuffixRepairFromCharKey(db)
    if not db.global or db.global._realmSuffixRepairV1 then return end
    local Utilities = ns.Utilities
    if not Utilities or not Utilities.GetCharacterKey or not Utilities.SplitCharacterKey then
        return
    end
    local chars = db.global.characters
    if type(chars) ~= "table" then
        db.global._realmSuffixRepairV1 = true
        return
    end
    for charKey, charData in pairs(chars) do
        if type(charKey) == "string" and type(charData) == "table" and charData.name then
            local nKey, rKey = Utilities:SplitCharacterKey(charKey)
            if nKey and rKey then
                local nameNorm = tostring(charData.name):gsub("%s+", "")
                if nameNorm == nKey then
                    local splitCanon = Utilities:GetCharacterKey(nKey, rKey)
                    if splitCanon == charKey then
                        local rStored = charData.realm
                        local currentCanon = (type(rStored) == "string" and rStored ~= "")
                            and Utilities:GetCharacterKey(nameNorm, rStored) or nil
                        if currentCanon ~= charKey then
                            charData.realm = rKey
                        end
                    end
                end
            end
        end
    end
    db.global._realmSuffixRepairV1 = true
end

---Normalize character keys across all character-keyed tables to canonical form
---(Utilities:GetCharacterKey(name, realm)). Handles collision: keep newest by lastSeen, merge non-conflicting fields.
function MigrationService:MigrateCharacterKeyNormalize(db)
    if not db.global then return end
    if db.global.charactersKeyNormalized then return end
    local Utilities = ns.Utilities
    if not Utilities or not Utilities.GetCharacterKey then return end

    local renames = {} -- [oldKey] = newKey (only when newKey ~= oldKey)
    if db.global.characters then
        for charKey, charData in pairs(db.global.characters) do
            if type(charData) == "table" and charData.name and charData.realm then
                local newKey = Utilities:GetCharacterKey(charData.name, charData.realm)
                if newKey and newKey ~= charKey then
                    renames[charKey] = newKey
                end
            end
        end
    end

    if not next(renames) then
        db.global.charactersKeyNormalized = true
        return
    end

    local chars = db.global.characters
    for oldKey, newKey in pairs(renames) do
        if not chars[oldKey] then
            -- already moved or removed
        elseif not chars[newKey] then
            chars[newKey] = chars[oldKey]
            chars[oldKey] = nil
        else
            -- Collision: keep newest by lastSeen
            local oldData = chars[oldKey]
            local newData = chars[newKey]
            local oldSeen = (type(oldData.lastSeen) == "number") and oldData.lastSeen or 0
            local newSeen = (type(newData.lastSeen) == "number") and newData.lastSeen or 0
            if oldSeen > newSeen then
                chars[newKey] = oldData
            end
            chars[oldKey] = nil
        end
    end

    -- currencyData.currencies
    local cd = db.global.currencyData
    if cd and cd.currencies then
        for oldKey, newKey in pairs(renames) do
            if cd.currencies[oldKey] and not cd.currencies[newKey] then
                cd.currencies[newKey] = cd.currencies[oldKey]
                cd.currencies[oldKey] = nil
            elseif cd.currencies[oldKey] then
                cd.currencies[oldKey] = nil
            end
        end
    end

    -- gearData
    if db.global.gearData then
        for oldKey, newKey in pairs(renames) do
            if db.global.gearData[oldKey] and not db.global.gearData[newKey] then
                db.global.gearData[newKey] = db.global.gearData[oldKey]
                db.global.gearData[oldKey] = nil
            elseif db.global.gearData[oldKey] then
                db.global.gearData[oldKey] = nil
            end
        end
    end

    -- pveProgress
    if db.global.pveProgress then
        for oldKey, newKey in pairs(renames) do
            if db.global.pveProgress[oldKey] and not db.global.pveProgress[newKey] then
                db.global.pveProgress[newKey] = db.global.pveProgress[oldKey]
                db.global.pveProgress[oldKey] = nil
            elseif db.global.pveProgress[oldKey] then
                db.global.pveProgress[oldKey] = nil
            end
        end
    end

    -- statisticSnapshots
    if db.global.statisticSnapshots then
        for oldKey, newKey in pairs(renames) do
            if db.global.statisticSnapshots[oldKey] and not db.global.statisticSnapshots[newKey] then
                db.global.statisticSnapshots[newKey] = db.global.statisticSnapshots[oldKey]
                db.global.statisticSnapshots[oldKey] = nil
            elseif db.global.statisticSnapshots[oldKey] then
                db.global.statisticSnapshots[oldKey] = nil
            end
        end
    end

    -- personalBanks
    if db.global.personalBanks then
        for oldKey, newKey in pairs(renames) do
            if db.global.personalBanks[oldKey] and not db.global.personalBanks[newKey] then
                db.global.personalBanks[newKey] = db.global.personalBanks[oldKey]
                db.global.personalBanks[oldKey] = nil
            elseif db.global.personalBanks[oldKey] then
                db.global.personalBanks[oldKey] = nil
            end
        end
    end

    -- favoriteCharacters (array): replace keys, then dedupe
    if db.global.favoriteCharacters and type(db.global.favoriteCharacters) == "table" then
        local seen = {}
        local favs = db.global.favoriteCharacters
        for i = 1, #favs do
            local key = favs[i]
            local canonical = renames[key] or key
            db.global.favoriteCharacters[i] = canonical
            seen[canonical] = true
        end
        local deduped = {}
        for i = 1, #db.global.favoriteCharacters do
            local k = db.global.favoriteCharacters[i]
            if seen[k] then
                deduped[#deduped + 1] = k
                seen[k] = nil
            end
        end
        db.global.favoriteCharacters = deduped
    end

    -- profile.characterOrder (favorites, regular, untracked arrays)
    if db.profile and db.profile.characterOrder then
        local orderKeys = { "favorites", "regular", "untracked" }
        for oki = 1, #orderKeys do
            local orderKey = orderKeys[oki]
            local arr = db.profile.characterOrder[orderKey]
            if type(arr) == "table" then
                for i = 1, #arr do
                    local key = arr[i]
                    arr[i] = renames[key] or key
                end
            end
        end
    end

    db.global.charactersKeyNormalized = true
end

return MigrationService
