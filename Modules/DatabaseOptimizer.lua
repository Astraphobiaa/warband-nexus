--[[
    Warband Nexus - Database Optimizer Module
    SavedVariables cleanup, cache backup/reset, and optional login trim.
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local WarbandNexus = ns.WarbandNexus
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- CACHE MANAGEMENT

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

-- DATABASE ANALYSIS

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
            
            local age = self.GetCharacterLastSeenAge and self:GetCharacterLastSeenAge(charData, currentTime)
            if age and self.IsCharacterEligibleForStaleRemoval and self:IsCharacterEligibleForStaleRemoval(charData, staleThreshold, currentTime) then
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

-- CLEANUP OPERATIONS

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
        if self.IsCharacterRowStructurallyInvalid and self:IsCharacterRowStructurallyInvalid(key, charData) then
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 and self.InvalidateGetAllCharactersCache then
        self:InvalidateGetAllCharactersCache()
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

    local resolvedKey = characterKey
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        resolvedKey = U:GetCanonicalCharacterKey(characterKey) or characterKey
    end
    if not self.db.global.characters[resolvedKey] then
        for key in pairs(self.db.global.characters) do
            if key == characterKey or (ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(key, characterKey)) then
                resolvedKey = key
                break
            end
        end
    end
    characterKey = resolvedKey

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
    
    local CS = ns.CharacterService
    if CS and CS.RemoveCharacterSubsidiaryKeys then
        CS:RemoveCharacterSubsidiaryKeys(self, characterKey)
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
    -- Stale row removal only clears `db.global.characters` entries; orphan subsidiary keys are handled elsewhere (CleanupOrphanedData).
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

-- USER INTERFACE

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

-- AUTO-OPTIMIZATION

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
        local results = self:OptimizeDatabase()
        self.db.profile.lastOptimize = time()
        if results and results.staleCharacters and results.staleCharacters > 0 then
            self:Print("|cff00ff00" .. string.format(
                (ns.L and ns.L["CLEANUP_REMOVED_FORMAT"]) or "Removed %d inactive character(s).",
                results.staleCharacters) .. "|r")
        end
    end
end

-- Constants
local MAX_CHARACTERS = 70  -- Maximum characters per account (configurable limit)

--[[
    Enforce maximum character limit
    Removes oldest characters (by lastSeen), protects favorites
    @param limit number - Maximum characters to keep (default MAX_CHARACTERS, currently 70)
    @return number - Characters removed
]]
function WarbandNexus:EnforceCharacterLimit(limit)
    limit = limit or MAX_CHARACTERS
    
    local characters = self.db.global.characters or {}
    local CS = ns.CharacterService
    local favoriteKeySet = (CS and CS.BuildFavoriteKeySet) and CS:BuildFavoriteKeySet(self) or {}
    
    local removable = {}
    local total = 0

    for charKey, charData in pairs(characters) do
        total = total + 1
        if type(charData) ~= "table" then
            removable[#removable + 1] = { key = charKey, lastSeen = 0, name = (ns.L and ns.L["UNKNOWN"]) or "Unknown" }
        else
            local isFavorite = CS and CS.IsFavoriteFromKeySet and CS:IsFavoriteFromKeySet(favoriteKeySet, charKey)
            local lastSeen = (type(charData.lastSeen) == "number" and charData.lastSeen > 0) and charData.lastSeen or nil
            if isFavorite or charData.isTracked ~= false or not lastSeen then
                -- Protected: favorites, tracked/default rows, unknown-age legacy rows
            else
                removable[#removable + 1] = {
                    key = charKey,
                    lastSeen = lastSeen,
                    name = charData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
                }
            end
        end
    end

    if total <= limit then
        return 0
    end

    table.sort(removable, function(a, b)
        return (a.lastSeen or 0) < (b.lastSeen or 0)
    end)
    
    local removed = 0
    local count = total
    for i = 1, #removable do
        if count <= limit then break end
        local entry = removable[i]
        local charKey = entry.key
        local charName = entry.name
        
        if CS and CS.RemoveCharacterSubsidiaryKeys then
            CS:RemoveCharacterSubsidiaryKeys(self, charKey)
        end
        
        -- Remove from character order lists (all buckets including custom group_* keys)
        if self.db.profile.characterOrder then
            for orderKey, ordList in pairs(self.db.profile.characterOrder) do
                if type(ordList) == "table" then
                    for j = #ordList, 1, -1 do
                        if ordList[j] == charKey then
                            table.remove(ordList, j)
                        end
                    end
                end
            end
        end
        
        -- Remove character
        characters[charKey] = nil
        removed = removed + 1
        count = count - 1
        
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
    local CS = ns.CharacterService

    -- SAFETY: if the roster looks empty/not-yet-loaded, every subsidiary bucket would
    -- be classified as orphaned and deleted — exactly the "all my other characters'
    -- data is wiped between sessions" failure mode. Never purge against an empty roster.
    local chars = self.db.global.characters
    if type(chars) ~= "table" or next(chars) == nil then
        return 0
    end

    -- Subsidiary tables may carry NON-character keys that must never be purged
    -- (itemStorage.warbandBank is the account-wide bank bucket).
    local PROTECTED_KEYS = { warbandBank = true }

    local function keyStillOwned(charKey)
        if PROTECTED_KEYS[charKey] then return true end
        if CS and CS.CharacterOwnsSubsidiaryKey then
            return CS:CharacterOwnsSubsidiaryKey(self, charKey)
        end
        return chars[charKey] ~= nil
    end

    local function purgeOrphans(tbl)
        if type(tbl) ~= "table" then return end
        for charKey in pairs(tbl) do
            if not keyStillOwned(charKey) then
                tbl[charKey] = nil
                removed = removed + 1
            end
        end
    end

    -- Clean currencies (v2.0: Direct DB architecture)
    if self.db.global.currencyData then
        if self.db.global.currencyData.currencies then
            purgeOrphans(self.db.global.currencyData.currencies)
        end
        if self.db.global.currencyData.totalEarned then
            purgeOrphans(self.db.global.currencyData.totalEarned)
        end
    end

    -- Clean reputations (legacy v1 per-faction chars)
    for factionID, repData in pairs(self.db.global.reputations or {}) do
        if repData.chars then
            purgeOrphans(repData.chars)
        end
    end

    if self.db.global.reputationData and self.db.global.reputationData.characters then
        purgeOrphans(self.db.global.reputationData.characters)
    end

    purgeOrphans(self.db.global.gearData)
    purgeOrphans(self.db.global.pveProgress)
    purgeOrphans(self.db.global.statisticSnapshots)
    purgeOrphans(self.db.global.personalBanks)
    purgeOrphans(self.db.global.itemStorage)

    local pc = self.db.global.pveCache
    if type(pc) == "table" then
        local mp = pc.mythicPlus
        if mp then
            purgeOrphans(mp.keystones)
            purgeOrphans(mp.bestRuns)
            purgeOrphans(mp.dungeonScores)
            purgeOrphans(mp.runHistory)
        end
        local gv = pc.greatVault
        if gv then
            purgeOrphans(gv.activities)
            purgeOrphans(gv.rewards)
        end
        local lo = pc.lockouts
        if lo then
            purgeOrphans(lo.raids)
            purgeOrphans(lo.dungeons)
            purgeOrphans(lo.worldBosses)
        end
        if pc.delves and pc.delves.characters then
            purgeOrphans(pc.delves.characters)
        end
    end

    if removed > 0 and ns.DebugPrint then
        ns.DebugPrint("|cffff8000[WN Cleanup]|r Orphan subsidiary keys removed: " .. removed)
    end

    return removed
end

-- INITIALIZATION

--[[
    Initialize database optimizer
    Called during OnEnable
]]
function WarbandNexus:InitializeDatabaseOptimizer()
    -- Set default for auto-optimize if not set
    if self.db.profile.autoOptimize == nil then
        self.db.profile.autoOptimize = true
    end

    -- Yield one frame before limit/orphan work so we don't extend the T+5s timer callback
    -- (same scheduled delays relative to login; slightly smoother frame pacing).
    local addon = self
    C_Timer.After(0, function()
        if not addon or not addon.db then return end

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
    
    -- NOTE: no warbandBank -> warbandBankV2 migration here. warbandBankV2 is
    -- deprecated (DatabaseCleanup deletes it every login) and has no readers;
    -- recreating it from the legacy table was a pure write-then-delete cycle.
    -- ItemsCacheService owns the live warband bank storage.

    -- Check if auto-optimization should run
    C_Timer.After(5, function()
        if WarbandNexus and WarbandNexus.CheckAutoOptimization then
            WarbandNexus:CheckAutoOptimization()
        end
    end)
    end)
end
