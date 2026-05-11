--[[
    Warband Nexus - Database Optimizer Module
    SavedVariables optimization and cleanup
    
    Features:
    - Remove stale character data (90+ days)
    - Remove deleted/invalid items
    - Deduplicate data
    - Database size reporting
    - Auto-cleanup on login (optional)
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local WarbandNexus = ns.WarbandNexus
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

-- Map cache name → DB path the cache is stored at. Backups + version-resets
-- operate via this table so the call sites stay declarative.
local CACHE_PATHS = {
    reputation = "reputationData",
    collection = "collectionCache",
    currency   = "currencyCache",
    pve        = "pveCache",
}

--- Backup a cache to db.global.cacheBackups[name] before invalidation.
--- A shallow copy is sufficient (caches re-fetch from API; backup is only for recovery).
local function BackupCache(self, name)
    local key = CACHE_PATHS[name]
    if not key then return end
    local current = self.db.global[key]
    if current == nil then return end
    self.db.global.cacheBackups = self.db.global.cacheBackups or {}
    self.db.global.cacheBackups[name] = {
        savedAt = time(),
        data    = current,
    }
end

--- Invalidate a single cache non-destructively.
--- Resets only the cache's version field so the next service initialise re-fetches
--- from the API. The data table itself stays intact — partial scans, obtained
--- markers, and weekly state survive. A backup snapshot is taken first.
---@param name string Cache name: "reputation", "collection", "currency", "pve"
---@param reason string|nil Diagnostic reason ("game_build", "schema_bump", manual)
function WarbandNexus:InvalidateCache(name, reason)
    local key = CACHE_PATHS[name]
    if not key then return end
    local cache = self.db.global[key]
    if not cache then return end
    BackupCache(self, name)
    cache.version = nil
    if cache.lastScan ~= nil then cache.lastScan = 0 end
end

--- Restore a cache from its most recent backup. Manual recovery hook.
function WarbandNexus:RestoreCacheBackup(name)
    local key = CACHE_PATHS[name]
    local backups = self.db.global.cacheBackups
    if not key or not backups or not backups[name] then return false end
    self.db.global[key] = backups[name].data
    return true
end

-- ============================================================================
-- DATABASE ANALYSIS
-- ============================================================================

--[[
    Calculate approximate database size
    @return number, table - Total size in KB and breakdown by section
]]
function WarbandNexus:GetDatabaseSize()
    local function estimateSize(tbl)
        if type(tbl) ~= "table" then
            return string.len(tostring(tbl))
        end
        
        local size = 0
        for k, v in pairs(tbl) do
            size = size + string.len(tostring(k))
            size = size + estimateSize(v)
        end
        return size
    end
    
    local breakdown = {
        characters = estimateSize(self.db.global.characters or {}),
        warbandBank = estimateSize(self.db.global.warbandBank or {}),
        profile = estimateSize(self.db.profile or {}),
        char = estimateSize(self.db.char or {}),
    }
    
    local total = 0
    for _, size in pairs(breakdown) do
        total = total + size
    end
    
    -- Convert to KB
    return total / 1024, {
        total = total / 1024,
        characters = breakdown.characters / 1024,
        warbandBank = breakdown.warbandBank / 1024,
        profile = breakdown.profile / 1024,
        char = breakdown.char / 1024,
    }
end

--[[
    Get database statistics
    @return table - Stats about database content
]]
function WarbandNexus:GetDatabaseStats()
    local stats = {
        characters = 0,
        staleCharacters = 0,
        warbandItems = 0,
        personalBankItems = 0,
    }
    
    -- Count characters
    if self.db.global.characters then
        local currentTime = time()
        local staleThreshold = 90 * 24 * 60 * 60 -- 90 days
        
        for key, charData in pairs(self.db.global.characters) do
            stats.characters = stats.characters + 1
            
            local lastSeen = charData.lastSeen or 0
            if (currentTime - lastSeen) > staleThreshold then
                stats.staleCharacters = stats.staleCharacters + 1
            end
            
            -- Count personal bank items
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, _ in pairs(bagData) do
                        stats.personalBankItems = stats.personalBankItems + 1
                    end
                end
            end
        end
    end
    
    -- Count warband items
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        for bagID, bagData in pairs(self.db.global.warbandBank.items) do
            for slotID, _ in pairs(bagData) do
                stats.warbandItems = stats.warbandItems + 1
            end
        end
    end
    
    return stats
end

-- ============================================================================
-- CLEANUP OPERATIONS
-- ============================================================================

--[[
    Remove invalid/deleted items from database
    @return number - Count of items removed
]]
function WarbandNexus:CleanupInvalidItems()
    local removed = 0
    
    -- Clean Warband Bank
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        for bagID, bagData in pairs(self.db.global.warbandBank.items) do
            for slotID, item in pairs(bagData) do
                -- Remove if no itemID or itemLink
                if not item.itemID or not item.itemLink then
                    self.db.global.warbandBank.items[bagID][slotID] = nil
                    removed = removed + 1
                end
            end
            
            -- Remove empty bags
            if not next(self.db.global.warbandBank.items[bagID]) then
                self.db.global.warbandBank.items[bagID] = nil
            end
        end
    end
    
    -- Clean Personal Banks
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        -- Remove if no itemID or itemLink
                        if not item.itemID or not item.itemLink then
                            charData.personalBank[bagID][slotID] = nil
                            removed = removed + 1
                        end
                    end
                    
                    -- Remove empty bags
                    if not next(charData.personalBank[bagID]) then
                        charData.personalBank[bagID] = nil
                    end
                end
            end
        end
    end
    
    return removed
end

--[[
    Remove characters with invalid data
    @return number - Count of characters removed
]]
function WarbandNexus:CleanupInvalidCharacters()
    local removed = 0
    
    if not self.db.global.characters then
        return 0
    end
    
    for key, charData in pairs(self.db.global.characters) do
        -- Check for required fields
        if not charData.name or not charData.realm or not charData.class then
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end
    
    return removed
end

--[[
    Delete a specific character's data
    @param characterKey string - Character key ("Name-Realm")
    @return boolean - Success status
]]
function WarbandNexus:DeleteCharacter(characterKey)
    if not characterKey or not self.db.global.characters then
        return false
    end
    
    -- Check if character exists
    if not self.db.global.characters[characterKey] then
        return false
    end
    
    -- Get character name for logging
    local charData = self.db.global.characters[characterKey]
    local charName = charData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    
    -- Remove from favorites if present
    if self.db.global.favoriteCharacters then
        local favs = self.db.global.favoriteCharacters
        for i = 1, #favs do
            local favKey = favs[i]
            if favKey == characterKey then
                table.remove(self.db.global.favoriteCharacters, i)
                break
            end
        end
    end
    
    -- Remove from character order lists (all buckets including custom group_* keys)
    if self.db.profile.characterOrder then
        for orderKey, ordList in pairs(self.db.profile.characterOrder) do
            if type(ordList) == "table" then
                for i = #ordList, 1, -1 do
                    if ordList[i] == characterKey then
                        table.remove(ordList, i)
                    end
                end
            end
        end
    end
    if self.db.profile.characterGroupAssignments then
        self.db.profile.characterGroupAssignments[characterKey] = nil
    end
    
    -- Delete character data
    self.db.global.characters[characterKey] = nil
    
    -- Fire event for UI refresh (DB-First pattern)
    local Constants = ns.Constants
    if Constants and Constants.EVENTS then
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = characterKey,
            isDeleted = true
        })
    end
    
    self:Print(string.format("Character deleted: |cff00ccff%s|r", charName))
    
    return true
end

--[[
    Optimize database (run all cleanup operations)
    @return table - Results of cleanup
]]
function WarbandNexus:OptimizeDatabase()
    local results = {
        staleCharacters = 0,
        invalidItems = 0,
        invalidCharacters = 0,
        sizeBefore = 0,
        sizeAfter = 0,
    }
    
    -- Get size before
    results.sizeBefore = self:GetDatabaseSize()
    
    -- Cleanup stale characters
    if self.CleanupStaleCharacters then
        results.staleCharacters = self:CleanupStaleCharacters(90)
    end
    
    -- Cleanup invalid items
    results.invalidItems = self:CleanupInvalidItems()
    
    -- Cleanup invalid characters
    results.invalidCharacters = self:CleanupInvalidCharacters()
    
    -- Clear caches (force rebuild)
    if self.ClearAllCaches then
        self:ClearAllCaches()
    end
    
    -- Get size after
    results.sizeAfter = self:GetDatabaseSize()
    results.savedKB = results.sizeBefore - results.sizeAfter
    
    return results
end

-- ============================================================================
-- USER INTERFACE
-- ============================================================================

--[[
    Print database statistics
]]
function WarbandNexus:PrintDatabaseStats()
    local sizeKB, breakdown = self:GetDatabaseSize()
    local stats = self:GetDatabaseStats()
    
    self:Print("===== Database Statistics =====")
    self:Print(string.format("Total Size: %.2f KB", sizeKB))
    self:Print("Breakdown:")
    self:Print(string.format("  Characters: %.2f KB (%d chars, %d stale)", 
        breakdown.characters, stats.characters, stats.staleCharacters))
    self:Print(string.format("  Warband Bank: %.2f KB (%d items)", 
        breakdown.warbandBank, stats.warbandItems))
    self:Print(string.format("  Personal Banks: %d items total", stats.personalBankItems))
    self:Print(string.format("  Profile: %.2f KB", breakdown.profile))
    self:Print(string.format("  Per-Char: %.2f KB", breakdown.char))
end

--[[
    Run database optimization and report results
]]
function WarbandNexus:RunOptimization()
    self:Print("|cff00ff00Optimizing database...|r")
    
    local results = self:OptimizeDatabase()
    
    self:Print("===== Optimization Results =====")
    if results.staleCharacters > 0 then
        self:Print(string.format("Removed %d stale character(s)", results.staleCharacters))
    end
    if results.invalidItems > 0 then
        self:Print(string.format("Removed %d invalid item(s)", results.invalidItems))
    end
    if results.invalidCharacters > 0 then
        self:Print(string.format("Removed %d invalid character(s)", results.invalidCharacters))
    end
    
    if results.savedKB > 0 then
        self:Print(string.format("Saved %.2f KB of space", results.savedKB))
    end
    
    if results.staleCharacters == 0 and results.invalidItems == 0 and results.invalidCharacters == 0 then
        self:Print("Database is already optimized!")
    else
        self:Print("|cff00ff00Optimization complete!|r")
    end
end

-- ============================================================================
-- AUTO-OPTIMIZATION
-- ============================================================================

--[[
    Check if auto-optimization should run
    Runs on login if enabled and last run was > 7 days ago
]]
function WarbandNexus:CheckAutoOptimization()
    if not self.db.profile.autoOptimize then
        return
    end
    
    local lastOptimize = self.db.profile.lastOptimize or 0
    local daysSince = (time() - lastOptimize) / (24 * 60 * 60)
    
    if daysSince >= 7 then
        self:OptimizeDatabase()
        self.db.profile.lastOptimize = time()
    end
end

-- ============================================================================
-- DATABASE MIGRATION (v1 -> v2)
-- ============================================================================

-- Constants
local Constants = ns.Constants
local MAX_CHARACTERS = 70  -- Maximum characters per account (configurable limit)
local CURRENT_DB_VERSION = Constants.DB_VERSION

--[[
    Check if migration is needed
    @return boolean - True if migration should run
]]
function WarbandNexus:NeedsMigration()
    local version = self.db.global.dataVersion or 1
    return version < CURRENT_DB_VERSION
end

--[[
    Migrate database from v1 (per-character) to v2 (data-centric)
    Runs automatically on first load after update
    @return boolean - True if migration was performed
]]
function WarbandNexus:MigrateToV2()
    -- Check if already migrated
    if not self:NeedsMigration() then
        return false
    end
    
    -- Silent migration - no user notification unless debug mode
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        self:Print("|cff00ccffMigrating database to v2 (optimized structure)...|r")
    end
    
    -- Create backup for safety (in memory only)
    local backup = {
        characters = {},
        hadError = false
    }
    
    -- Deep copy character data for backup
    for charKey, charData in pairs(self.db.global.characters or {}) do
        backup.characters[charKey] = {
            currencies = charData.currencies,
            currencyHeaders = charData.currencyHeaders,
            reputations = charData.reputations,
            reputationHeaders = charData.reputationHeaders,
            pve = charData.pve,
            personalBank = charData.personalBank,
        }
    end
    
    local success, err = pcall(function()
        -- v2.0: Currency migration now handled by CurrencyCacheService
        -- Legacy migration code removed - new Direct DB architecture
        
        local currenciesMigrated = 0
        local reputationsMigrated = 0
        local charactersMigrated = 0
        
        -- ========== MIGRATE CURRENCIES (DEPRECATED) ==========
        -- Currency data is now managed by CurrencyCacheService
        -- Old character.currencies data is no longer migrated
        -- New system will populate db.global.currencyData automatically on first scan
        
        -- ========== MIGRATE REPUTATIONS ==========
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.reputations then
                for factionID, repData in pairs(charData.reputations) do
                    factionID = tonumber(factionID) or factionID
                    
                    -- Get metadata from factionMetadata if available
                    local metadata = self.db.global.factionMetadata and self.db.global.factionMetadata[factionID]
                    
                    -- First time seeing this faction - store metadata
                    if not self.db.global.reputations[factionID] then
                        local isMajorFaction = repData.isMajorFaction or repData.renownLevel ~= nil
                        local isAccountWide = isMajorFaction -- Major factions are account-wide
                        
                        self.db.global.reputations[factionID] = {
                            name = (metadata and metadata.name)
                                or repData.name
                                or (((ns.L and ns.L["REP_FACTION_FALLBACK"]) or "Faction") .. " " .. tostring(factionID)),
                            icon = metadata and metadata.icon,
                            isMajorFaction = isMajorFaction,
                            isRenown = repData.renownLevel ~= nil,
                            isAccountWide = isAccountWide,
                            header = metadata and metadata.header,
                        }
                        
                        if isAccountWide then
                            -- Account-wide: store single value
                            self.db.global.reputations[factionID].value = {
                                standingID = repData.standingID,
                                currentValue = repData.currentValue or 0,
                                maxValue = repData.maxValue or 0,
                                renownLevel = repData.renownLevel,
                                renownMaxLevel = repData.renownMaxLevel,
                                paragonValue = repData.paragonValue,
                                paragonThreshold = repData.paragonThreshold,
                                hasParagonReward = repData.hasParagonReward,
                            }
                        else
                            -- Character-specific: initialize chars table
                            self.db.global.reputations[factionID].chars = {}
                        end
                        
                        reputationsMigrated = reputationsMigrated + 1
                    end
                    
                    -- Store character progress (only for non-account-wide)
                    local repGlobal = self.db.global.reputations[factionID]
                    if repGlobal and not repGlobal.isAccountWide then
                        repGlobal.chars = repGlobal.chars or {}
                        repGlobal.chars[charKey] = {
                            standingID = repData.standingID,
                            currentValue = repData.currentValue or 0,
                            maxValue = repData.maxValue or 0,
                            renownLevel = repData.renownLevel,
                            renownMaxLevel = repData.renownMaxLevel,
                            paragonValue = repData.paragonValue,
                            paragonThreshold = repData.paragonThreshold,
                            hasParagonReward = repData.hasParagonReward,
                        }
                    end
                end
                
                -- Migrate reputation headers (take from first character that has them)
                if charData.reputationHeaders and next(charData.reputationHeaders) then
                    if not next(self.db.global.reputationHeaders) then
                        self.db.global.reputationHeaders = charData.reputationHeaders
                    end
                end
            end
            
            charactersMigrated = charactersMigrated + 1
        end
        
        -- ========== MIGRATE PVE DATA TO GLOBAL STORAGE ==========
        self.db.global.pveMetadata = self.db.global.pveMetadata or { dungeons = {}, raids = {}, lastUpdate = 0 }
        self.db.global.pveProgress = self.db.global.pveProgress or {}
        
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.pve then
                -- Use the v2 update function to migrate
                if self.UpdatePvEDataV2 then
                    self:UpdatePvEDataV2(charKey, charData.pve)
                end
            end
        end
        
        -- ========== MIGRATE PERSONAL BANK DATA TO GLOBAL STORAGE ==========
        self.db.global.personalBanks = self.db.global.personalBanks or {}
        
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.personalBank then
                -- Use the v2 update function to migrate (with compression)
                if self.UpdatePersonalBankV2 then
                    self:UpdatePersonalBankV2(charKey, charData.personalBank)
                end
            end
        end
        
        -- ========== MIGRATE WARBAND BANK TO V2 (COMPRESSED) ==========
        if self.db.global.warbandBank and self.db.global.warbandBank.items and next(self.db.global.warbandBank.items) then
            if self.UpdateWarbandBankV2 and not self.db.global.warbandBankV2 then
                self:UpdateWarbandBankV2(self.db.global.warbandBank)
            end
        end
        
        -- ========== CLEAN UP OLD DATA FROM CHARACTERS ==========
        for charKey, charData in pairs(self.db.global.characters or {}) do
            charData.currencies = nil
            charData.currencyHeaders = nil
            charData.reputations = nil
            charData.reputationHeaders = nil
            charData.reputationsLastScan = nil
            charData.pve = nil  -- Migrated to global.pveProgress
            charData.personalBank = nil  -- Migrated to global.personalBanks
        end
        
        -- Set timestamps
        self.db.global.currencyLastUpdate = time()
        self.db.global.reputationLastUpdate = time()
        self.db.global.personalBanksLastUpdate = time()
        
        -- Mark as migrated
        self.db.global.dataVersion = CURRENT_DB_VERSION
        
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            self:Print(string.format("|cff00ff00Migration complete:|r %d currencies, %d reputations from %d characters", 
                currenciesMigrated, reputationsMigrated, charactersMigrated))
        end
    end)
    
    if not success then
        -- Restore backup on failure
        backup.hadError = true
        for charKey, backupData in pairs(backup.characters) do
            if self.db.global.characters[charKey] then
                self.db.global.characters[charKey].currencies = backupData.currencies
                self.db.global.characters[charKey].currencyHeaders = backupData.currencyHeaders
                self.db.global.characters[charKey].reputations = backupData.reputations
                self.db.global.characters[charKey].reputationHeaders = backupData.reputationHeaders
                self.db.global.characters[charKey].pve = backupData.pve
                self.db.global.characters[charKey].personalBank = backupData.personalBank
            end
        end
        
        -- Clear any partially migrated global data
        self.db.global.pveProgress = nil
        self.db.global.pveMetadata = nil
        self.db.global.personalBanks = nil
        
        self:Print("|cffff0000Database migration failed. Data restored.|r")
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            self:Print("Error: " .. tostring(err))
        end
        return false
    end
    
    return true
end

--[[
    Enforce maximum character limit
    Removes oldest characters (by lastSeen), protects favorites
    @param limit number - Maximum characters to keep (default MAX_CHARACTERS, currently 70)
    @return number - Characters removed
]]
function WarbandNexus:EnforceCharacterLimit(limit)
    limit = limit or MAX_CHARACTERS
    
    local characters = self.db.global.characters or {}
    local favorites = self.db.global.favoriteCharacters or {}
    
    -- Build list of characters with metadata
    local charList = {}
    for charKey, charData in pairs(characters) do
        local isFavorite = false
        for fi = 1, #favorites do
            local favKey = favorites[fi]
            if favKey == charKey then
                isFavorite = true
                break
            end
        end
        
        table.insert(charList, {
            key = charKey,
            lastSeen = charData.lastSeen or 0,
            isFavorite = isFavorite,
            name = charData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        })
    end
    
    -- Sort: favorites first, then by lastSeen (newest first)
    table.sort(charList, function(a, b)
        if a.isFavorite ~= b.isFavorite then
            return a.isFavorite
        end
        return a.lastSeen > b.lastSeen
    end)
    
    -- Remove excess characters
    local removed = 0
    for i = limit + 1, #charList do
        local charKey = charList[i].key
        local charName = charList[i].name
        
        -- Clean up currency references for this character (v2.0: Direct DB)
        if self.db.global.currencyData and self.db.global.currencyData.currencies then
            self.db.global.currencyData.currencies[charKey] = nil
        end
        
        -- Clean up reputation references for this character
        for factionID, repData in pairs(self.db.global.reputations or {}) do
            if repData.chars then
                repData.chars[charKey] = nil
            end
        end
        
        -- Remove from character order lists
        if self.db.profile.characterOrder then
            if self.db.profile.characterOrder.regular then
                local regOrderRm = self.db.profile.characterOrder.regular
                for j = 1, #regOrderRm do
                    local key = regOrderRm[j]
                    if key == charKey then
                        table.remove(self.db.profile.characterOrder.regular, j)
                        break
                    end
                end
            end
        end
        
        -- Remove character
        characters[charKey] = nil
        removed = removed + 1
        
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            self:Print(string.format("Removed old character: %s", charName))
        end
    end
    
    return removed
end

--[[
    Clean up orphaned data in currencies/reputations
    Removes character references that no longer exist
    @return number - Orphaned entries removed
]]
function WarbandNexus:CleanupOrphanedData()
    local removed = 0
    local characters = self.db.global.characters or {}
    
    -- Clean currencies (v2.0: Direct DB architecture)
    if self.db.global.currencyData and self.db.global.currencyData.currencies then
        for charKey in pairs(self.db.global.currencyData.currencies) do
            if not characters[charKey] then
                self.db.global.currencyData.currencies[charKey] = nil
                removed = removed + 1
            end
        end
    end
    
    -- Clean reputations
    for factionID, repData in pairs(self.db.global.reputations or {}) do
        if repData.chars then
            for charKey in pairs(repData.chars) do
                if not characters[charKey] then
                    repData.chars[charKey] = nil
                    removed = removed + 1
                end
            end
        end
    end
    
    return removed
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize database optimizer
    Called during OnEnable
]]
function WarbandNexus:InitializeDatabaseOptimizer()
    -- Set default for auto-optimize if not set
    if self.db.profile.autoOptimize == nil then
        self.db.profile.autoOptimize = true
    end

    -- Yield one frame before migration/limit/orphan work so we don't extend the T+5s timer callback
    -- (same scheduled delays relative to login; slightly smoother frame pacing).
    local addon = self
    C_Timer.After(0, function()
        if not addon or not addon.db then return end

    -- Run migration if needed (silent, automatic)
    if addon:NeedsMigration() then
        addon:MigrateToV2()
    end
    
    -- Enforce character limit
    addon:EnforceCharacterLimit(MAX_CHARACTERS)
    
    -- Clean up orphaned data
    addon:CleanupOrphanedData()
    
    -- Check if global data needs to be rebuilt (empty after migration)
    local needsRepScan = not addon.db.global.reputationData or not next(addon.db.global.reputationData.characters or {})
    local needsRepHeaderRebuild = false -- Reputation headers not used in v2.0
    local needsCurrScan = not addon.db.global.currencyData or not next(addon.db.global.currencyData.currencies or {})
    local needsCurrHeaderRebuild = false -- Currency headers stored in currencyData.headers
    
    if needsRepScan or needsRepHeaderRebuild then
        -- Trigger a reputation scan after a short delay to rebuild global data
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.ScanReputations then
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    addon:Print("|cff00ccffRebuilding reputation data...|r")
                end
                WarbandNexus.currentTrigger = "POST_MIGRATION"
                WarbandNexus:ScanReputations()
            end
        end)
    end
    
    -- Check if currency data needs rebuild (v2.0: Check version)
    local needsCurrRebuild = false
    if addon.db.global.currencyData then
        local dbVersion = addon.db.global.currencyData.version or "1.0.0"
        local currentVersion = "1.0.0"
        if dbVersion ~= currentVersion then
            needsCurrRebuild = true
        end
    end
    
    if needsCurrScan or needsCurrHeaderRebuild or needsCurrRebuild then
        -- Trigger a currency update after a short delay to rebuild global data
        C_Timer.After(3, function()
            if WarbandNexus and WarbandNexus.UpdateCurrencyData then
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    addon:Print("|cff00ccffRebuilding currency data...|r")
                end
                WarbandNexus.currentTrigger = "POST_MIGRATION"
                WarbandNexus:UpdateCurrencyData()
            end
        end)
    end
    
    -- Check if PvE/PersonalBank data needs migration (still in per-character storage)
    local needsPveMigration = false
    local needsBankMigration = false
    
    for charKey, charData in pairs(addon.db.global.characters or {}) do
        if charData.pve then
            needsPveMigration = true
        end
        if charData.personalBank then
            needsBankMigration = true
        end
        if needsPveMigration and needsBankMigration then
            break
        end
    end
    
    if needsPveMigration or needsBankMigration then
        -- Migrate remaining per-character data to global storage
        C_Timer.After(4, function()
            if WarbandNexus then
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    addon:Print("|cff00ccffMigrating PvE and bank data to v2 format...|r")
                end
                
                for charKey, charData in pairs(addon.db.global.characters or {}) do
                    -- Migrate PvE
                    if charData.pve and WarbandNexus.UpdatePvEDataV2 then
                        WarbandNexus:UpdatePvEDataV2(charKey, charData.pve)
                        charData.pve = nil
                    end
                    
                    -- Migrate Personal Bank
                    if charData.personalBank and WarbandNexus.UpdatePersonalBankV2 then
                        WarbandNexus:UpdatePersonalBankV2(charKey, charData.personalBank)
                        charData.personalBank = nil
                    end
                end
                
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    addon:Print("|cff00ff00PvE and bank data migration complete!|r")
                end
            end
        end)
    end
    
    -- Check if Warband Bank needs migration to v2 (compressed)
    local needsWarbandMigration = addon.db.global.warbandBank 
        and addon.db.global.warbandBank.items 
        and next(addon.db.global.warbandBank.items)
        and not addon.db.global.warbandBankV2
    
    if needsWarbandMigration then
        C_Timer.After(4.5, function()
            if WarbandNexus and WarbandNexus.UpdateWarbandBankV2 then
                WarbandNexus:UpdateWarbandBankV2(WarbandNexus.db.global.warbandBank)
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    addon:Print("|cff00ff00Warband bank migrated to v2 format!|r")
                end
            end
        end)
    end
    
    -- Check if auto-optimization should run
    C_Timer.After(5, function()
        if WarbandNexus and WarbandNexus.CheckAutoOptimization then
            WarbandNexus:CheckAutoOptimization()
        end
    end)
    end)
end
