--[[
    Warband Nexus - Data Migration Module
    Handles database schema versioning and migration between versions
    Ensures smooth upgrades without data loss
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Schema versions
local SCHEMA_VERSION_LEGACY = 0 -- Pre-compression format
local SCHEMA_VERSION_COMPRESSED = 1 -- Compression + normalized schema
local CURRENT_SCHEMA_VERSION = SCHEMA_VERSION_COMPRESSED

--[[
    Get current database schema version
    @return number - Schema version
]]
function WarbandNexus:GetDatabaseVersion()
    if not self.db or not self.db.global then
        return SCHEMA_VERSION_LEGACY
    end
    
    return self.db.global.schemaVersion or SCHEMA_VERSION_LEGACY
end

--[[
    Check if migration is needed
    @return boolean - True if migration needed
]]
function WarbandNexus:NeedsMigration()
    local currentVersion = self:GetDatabaseVersion()
    return currentVersion < CURRENT_SCHEMA_VERSION
end

--[[
    Perform database migration
    @return success boolean, message string
]]
function WarbandNexus:MigrateDatabase()
    local currentVersion = self:GetDatabaseVersion()
    
    if currentVersion >= CURRENT_SCHEMA_VERSION then
        return true, "Database is up to date (v" .. currentVersion .. ")"
    end
    
    self:Print("|cffff9900Warband Nexus:|r Database migration required...")
    self:Print("Current version: " .. currentVersion .. " → Target version: " .. CURRENT_SCHEMA_VERSION)
    
    -- Create backup before migration
    self:Print("Creating backup...")
    if not self:CreateMigrationBackup() then
        return false, "Failed to create backup - migration aborted"
    end
    
    -- Perform migrations step by step
    local success = true
    local message = ""
    
    if currentVersion == SCHEMA_VERSION_LEGACY then
        success, message = self:MigrateFromLegacy()
        if not success then
            self:Print("|cffff0000Migration failed:|r " .. message)
            self:Print("Attempting to restore from backup...")
            if self:RollbackMigration() then
                return false, "Migration failed, rolled back to previous version"
            else
                return false, "Migration failed and rollback failed - please restore from backup manually"
            end
        end
        currentVersion = SCHEMA_VERSION_COMPRESSED
    end
    
    -- Set final schema version
    self.db.global.schemaVersion = CURRENT_SCHEMA_VERSION
    self.db.global.lastMigration = time()
    
    self:Print("|cff00ff00Migration successful!|r " .. message)
    return true, message
end

--[[
    Migrate from legacy (uncompressed) format to compressed format
    @return success boolean, message string
]]
function WarbandNexus:MigrateFromLegacy()
    self:Print("Migrating from legacy format...")
    
    local startTime = debugprofilestop()
    
    -- Check if data exists
    if not self.db.global.characters or not next(self.db.global.characters) then
        self:Print("No character data found - initializing empty database")
        self.db.global.characters = {}
        return true, "Initialized empty database"
    end
    
    local success, result = pcall(function()
        local characterCount = 0
        local itemsNormalized = 0
        local reputationsReorganized = 0
        
        -- Step 1: Normalize character data
        for charKey, charData in pairs(self.db.global.characters) do
            characterCount = characterCount + 1
            
            -- Normalize inventory items (remove static data)
            if charData.bags then
                for bagIndex, bag in pairs(charData.bags) do
                    if bag.items then
                        for slot, item in pairs(bag.items) do
                            if item then
                                -- Keep only: id, count, slot
                                local normalized = {
                                    id = item.id or item.itemID,
                                    count = item.count or 1,
                                    slot = slot
                                }
                                bag.items[slot] = normalized
                                itemsNormalized = itemsNormalized + 1
                            end
                        end
                    end
                end
            end
            
            -- Normalize bank items
            if charData.bank then
                for slot, item in pairs(charData.bank) do
                    if item then
                        local normalized = {
                            id = item.id or item.itemID,
                            count = item.count or 1,
                            slot = slot
                        }
                        charData.bank[slot] = normalized
                        itemsNormalized = itemsNormalized + 1
                    end
                end
            end
            
            -- Add migration timestamp
            charData.migratedAt = time()
            charData.migrationVersion = SCHEMA_VERSION_COMPRESSED
        end
        
        -- Step 2: Separate account-wide reputations
        if not self.db.global.warbandData then
            self.db.global.warbandData = {
                reputations = {},
                bank = {}
            }
        end
        
        -- Move account-wide reputations to warband section
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.reputations then
                local charReps = {}
                for factionID, repData in pairs(charData.reputations) do
                    -- Check if account-wide (this will be properly implemented in reputation-split task)
                    -- For now, keep all in character data
                    charReps[factionID] = repData
                end
                charData.reputations = charReps
            end
        end
        
        -- Step 3: Initialize compression
        -- Note: Actual compression happens in DatabaseCompressor
        -- This migration just prepares the data structure
        
        local elapsed = debugprofilestop() - startTime
        
        local message = string.format(
            "Migrated %d characters, normalized %d items in %.0f ms",
            characterCount, itemsNormalized, elapsed
        )
        
        -- Add helpful note if no items were normalized
        if itemsNormalized == 0 then
            message = message .. "\n\n|cffffcc00Note:|r New scans already use optimized format.\nNo old-format items found to migrate."
        end
        
        return message
    end)
    
    if not success then
        return false, "Migration error: " .. tostring(result)
    end
    
    return true, result
end

--[[
    Create a migration backup
    @return success boolean
]]
function WarbandNexus:CreateMigrationBackup()
    if not self.db or not self.db.global then
        return false
    end
    
    local success = pcall(function()
        -- Create deep copy of current database state
        local backup = {
            characters = self:DeepCopy(self.db.global.characters or {}),
            schemaVersion = self.db.global.schemaVersion or SCHEMA_VERSION_LEGACY,
            timestamp = time()
        }
        
        -- Store in backup section
        if not self.db.global.migrationBackup then
            self.db.global.migrationBackup = {}
        end
        
        self.db.global.migrationBackup.preMigration = backup
        self.db.global.migrationBackup.created = time()
    end)
    
    return success
end

--[[
    Rollback migration to previous version
    @return success boolean
]]
function WarbandNexus:RollbackMigration()
    if not self.db or not self.db.global then
        self:Print("|cffff0000Error:|r Database not initialized")
        return false
    end
    
    if not self.db.global.migrationBackup or not self.db.global.migrationBackup.preMigration then
        self:Print("|cffff9900No migration backup found.|r")
        self:Print("Either migration never ran, or backup was already cleared.")
        return false
    end
    
    if not self.DeepCopy then
        self:Print("|cffff0000Error:|r DeepCopy function not available")
        return false
    end
    
    local success, err = pcall(function()
        local backup = self.db.global.migrationBackup.preMigration
        
        -- Restore characters
        self.db.global.characters = self:DeepCopy(backup.characters)
        
        -- Restore schema version
        self.db.global.schemaVersion = backup.schemaVersion
        
        -- Clear compressed data if any
        self.db.global.compressedData = nil
        
        self:Print("|cff00ff00Successfully rolled back to schema version " .. backup.schemaVersion .. "|r")
        self:Print("|cffffcc00/reload recommended to apply changes|r")
    end)
    
    if not success then
        self:Print("|cffff0000Rollback failed:|r " .. tostring(err))
    end
    
    return success
end

--[[
    Clear migration backup (after successful migration)
]]
function WarbandNexus:ClearMigrationBackup()
    if self.db.global.migrationBackup then
        -- Keep backup for 7 days after migration
        local backupAge = time() - (self.db.global.migrationBackup.created or 0)
        if backupAge > (7 * 86400) then
            self.db.global.migrationBackup = nil
            self:Debug("Cleared old migration backup")
        end
    end
end

--[[
    Deep copy a table (recursive)
    @param orig table - Original table
    @return table - Deep copy
]]
function WarbandNexus:DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[self:DeepCopy(orig_key)] = self:DeepCopy(orig_value)
        end
        setmetatable(copy, self:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    
    return copy
end

--[[
    Get migration status information
    @return table - Migration status
]]
function WarbandNexus:GetMigrationStatus()
    return {
        currentVersion = self:GetDatabaseVersion(),
        targetVersion = CURRENT_SCHEMA_VERSION,
        needsMigration = self:NeedsMigration(),
        hasBackup = self.db.global.migrationBackup ~= nil,
        lastMigration = self.db.global.lastMigration or 0
    }
end

--[[
    Initialize migration system
    Called on addon load - automatically migrates if needed
]]
function WarbandNexus:InitializeMigration()
    -- Check if migration is needed
    if self:NeedsMigration() then
        -- Perform automatic migration (no popup, no user interaction)
        local success, message = self:MigrateDatabase()
        
        if success then
            self:Print("|cff00ff00Database updated successfully!|r")
        else
            self:Print("|cffff0000Database update failed:|r " .. tostring(message))
            self:Print("Please report this issue if problems persist.")
        end
    else
        -- Database is up to date
        self:Debug("Database schema is up to date (v" .. self:GetDatabaseVersion() .. ")")
        
        -- Clean old migration backups (after 7 days)
        self:ClearMigrationBackup()
    end
end

--[[
    Export migration data for debugging
    @return string - Formatted migration info
]]
function WarbandNexus:ExportMigrationInfo()
    local status = self:GetMigrationStatus()
    local lines = {}
    
    table.insert(lines, "=== Warband Nexus Migration Info ===")
    table.insert(lines, "Current Schema Version: " .. status.currentVersion)
    table.insert(lines, "Target Schema Version: " .. status.targetVersion)
    table.insert(lines, "Needs Migration: " .. tostring(status.needsMigration))
    table.insert(lines, "Has Backup: " .. tostring(status.hasBackup))
    
    if status.lastMigration > 0 then
        table.insert(lines, "Last Migration: " .. date("%Y-%m-%d %H:%M:%S", status.lastMigration))
    else
        table.insert(lines, "Last Migration: Never")
    end
    
    if self.db.global.characters then
        local charCount = 0
        for _ in pairs(self.db.global.characters) do
            charCount = charCount + 1
        end
        table.insert(lines, "Character Count: " .. charCount)
    end
    
    if self.db.global.compressionStats then
        local stats = self.db.global.compressionStats
        table.insert(lines, string.format("Compression: %.2f KB → %.2f KB (%.1f%%)",
            stats.originalSize / 1024,
            stats.compressedSize / 1024,
            stats.ratio))
    end
    
    return table.concat(lines, "\n")
end

--[[
    Auto-initialize migration system when module loads
    This ensures automatic migration runs on first load
    No popup - fully automatic process
]]
if WarbandNexus and WarbandNexus.db then
    -- Module is loading after Core.lua initialized DB
    -- Safe to check and run migration immediately
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.InitializeMigration then
            WarbandNexus:InitializeMigration()
        end
    end)
end

