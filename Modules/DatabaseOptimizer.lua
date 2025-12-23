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
local WarbandNexus = ns.WarbandNexus

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
            self:Debug("Removing invalid character: " .. key)
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
    local charName = charData.name or "Unknown"
    
    -- Remove from favorites if present
    if self.db.global.favoriteCharacters then
        for i, favKey in ipairs(self.db.global.favoriteCharacters) do
            if favKey == characterKey then
                table.remove(self.db.global.favoriteCharacters, i)
                break
            end
        end
    end
    
    -- Remove from character order lists
    if self.db.profile.characterOrder then
        if self.db.profile.characterOrder.favorites then
            for i, key in ipairs(self.db.profile.characterOrder.favorites) do
                if key == characterKey then
                    table.remove(self.db.profile.characterOrder.favorites, i)
                    break
                end
            end
        end
        if self.db.profile.characterOrder.regular then
            for i, key in ipairs(self.db.profile.characterOrder.regular) do
                if key == characterKey then
                    table.remove(self.db.profile.characterOrder.regular, i)
                    break
                end
            end
        end
    end
    
    -- Delete character data
    self.db.global.characters[characterKey] = nil
    
    -- Invalidate character cache
    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
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
        self:Debug("Running auto-optimization (last run: " .. math.floor(daysSince) .. " days ago)")
        
        local results = self:OptimizeDatabase()
        
        -- Only notify if something was cleaned
        local totalCleaned = results.staleCharacters + results.invalidItems + results.invalidCharacters
        if totalCleaned > 0 then
            self:Print(string.format("|cff00ff00Auto-optimized database:|r Removed %d items", totalCleaned))
        end
        
        self.db.profile.lastOptimize = time()
    end
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
    
    -- Check if auto-optimization should run
    C_Timer.After(5, function()
        if WarbandNexus and WarbandNexus.CheckAutoOptimization then
            WarbandNexus:CheckAutoOptimization()
        end
    end)
end
