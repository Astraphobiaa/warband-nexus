--[[
    Warband Nexus - Database Compressor Module
    Handles compression/decompression of character data using LibDeflate and LibSerialize
    Replaces the deletion-focused DatabaseOptimizer approach with archival compression
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Library references
local LibDeflate = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

-- Configuration
local COMPRESSION_LEVEL = 5 -- Balance between speed and ratio (0-9)
local ARCHIVE_THRESHOLD_DAYS = 7 -- Archive characters inactive for 7+ days
local BACKUP_RETENTION_DAYS = 30 -- Keep backups for 30 days

--[[
    Pack (compress) the entire character database
    Called on PLAYER_LOGOUT to minimize SavedVariables size
    @return success boolean, error string
]]
function WarbandNexus:PackDatabase()
    if not self.db or not self.db.global then
        return false, "Database not initialized"
    end
    
    local startTime = debugprofilestop()
    
    -- Don't compress if already compressed
    if self.db.global.compressedData then
        return true, "Database already compressed"
    end
    
    -- Don't compress if no character data
    if not self.db.global.characters or not next(self.db.global.characters) then
        return true, "No character data to compress"
    end
    
    local success, result = pcall(function()
        -- Step 1: Serialize (AceSerializer returns success, data)
        local serialized = AceSerializer:Serialize(self.db.global.characters)
        if not serialized then
            error("Serialization failed")
        end
        
        -- Step 2: Compress
        local compressed = LibDeflate:CompressDeflate(serialized, {level = COMPRESSION_LEVEL})
        if not compressed then
            error("Compression failed")
        end
        
        -- Step 3: Encode for SavedVariables
        local encoded = LibDeflate:EncodeForPrint(compressed)
        if not encoded then
            error("Encoding failed")
        end
        
        -- Calculate compression ratio
        local originalSize = #serialized
        local compressedSize = #encoded
        local ratio = (1 - compressedSize / originalSize) * 100
        
        -- Store compressed data
        self.db.global.compressedData = encoded
        self.db.global.compressionStats = {
            originalSize = originalSize,
            compressedSize = compressedSize,
            ratio = ratio,
            timestamp = time(),
            version = 1
        }
        
        -- Clear uncompressed data to free memory
        self.db.global.characters = nil
        
        local elapsed = debugprofilestop() - startTime
        return string.format("Compressed %.2f KB → %.2f KB (%.1f%% reduction) in %.0f ms", 
            originalSize / 1024, compressedSize / 1024, ratio, elapsed)
    end)
    
    if not success then
        return false, "Compression error: " .. tostring(result)
    end
    
    return true, result
end

--[[
    Unpack (decompress) the character database
    Called on PLAYER_LOGIN to restore data for use
    @return success boolean, error string
]]
function WarbandNexus:UnpackDatabase()
    if not self.db or not self.db.global then
        return false, "Database not initialized"
    end
    
    local startTime = debugprofilestop()
    
    -- Check if data is compressed
    if not self.db.global.compressedData then
        -- Data is already uncompressed
        if self.db.global.characters then
            return true, "Database already uncompressed"
        else
            -- No data at all (fresh install)
            self.db.global.characters = {}
            return true, "Initialized empty database"
        end
    end
    
    local success, result = pcall(function()
        -- Step 1: Decode
        local compressed = LibDeflate:DecodeForPrint(self.db.global.compressedData)
        if not compressed then
            error("Decoding failed")
        end
        
        -- Step 2: Decompress
        local serialized = LibDeflate:DecompressDeflate(compressed)
        if not serialized then
            error("Decompression failed")
        end
        
        -- Step 3: Deserialize (AceSerializer returns success, data)
        local deserializeSuccess, characters = AceSerializer:Deserialize(serialized)
        if not deserializeSuccess then
            error("Deserialization failed: " .. tostring(characters))
        end
        
        -- Restore data
        self.db.global.characters = characters
        
        -- Clear compressed data from memory (keep in SavedVariables for next logout)
        -- We keep it in db.global so it persists, but we could optionally nil it here
        -- to save memory during gameplay. For safety, we'll keep it.
        
        local elapsed = debugprofilestop() - startTime
        local stats = self.db.global.compressionStats
        if stats then
            return string.format("Decompressed %.2f KB in %.0f ms", 
                stats.compressedSize / 1024, elapsed)
        else
            return string.format("Decompressed database in %.0f ms", elapsed)
        end
    end)
    
    if not success then
        -- Critical error - attempt to restore from backup
        self:Print("|cffff0000Database decompression failed!|r")
        self:Print("Error: " .. tostring(result))
        
        if self:RestoreFromBackup() then
            return true, "Restored from backup"
        else
            return false, "Decompression failed and no backup available"
        end
    end
    
    return true, result
end

--[[
    Archive an inactive character (compress individually)
    @param charKey string - Character key (Name-Realm)
    @return success boolean
]]
function WarbandNexus:ArchiveCharacter(charKey)
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return false
    end
    
    local charData = self.db.global.characters[charKey]
    
    -- Check if character is inactive
    local lastLogin = charData.lastLogin or 0
    local daysSinceLogin = (time() - lastLogin) / 86400
    
    if daysSinceLogin < ARCHIVE_THRESHOLD_DAYS then
        return false -- Character is still active
    end
    
    local success, result = pcall(function()
        -- Serialize and compress character data
        local serialized = LibSerialize:Serialize(charData)
        local compressed = LibDeflate:CompressDeflate(serialized, {level = 9}) -- Max compression for archives
        local encoded = LibDeflate:EncodeForPrint(compressed)
        
        -- Store in archived section
        if not self.db.global.archivedCharacters then
            self.db.global.archivedCharacters = {}
        end
        
        self.db.global.archivedCharacters[charKey] = {
            data = encoded,
            archivedAt = time(),
            lastLogin = lastLogin,
            name = charData.name,
            realm = charData.realm,
            class = charData.class,
            level = charData.level
        }
        
        -- Remove from active characters
        self.db.global.characters[charKey] = nil
        
        return true
    end)
    
    return success
end

--[[
    Restore an archived character
    @param charKey string - Character key (Name-Realm)
    @return success boolean
]]
function WarbandNexus:RestoreCharacter(charKey)
    if not self.db.global.archivedCharacters or not self.db.global.archivedCharacters[charKey] then
        return false
    end
    
    local archive = self.db.global.archivedCharacters[charKey]
    
    local success, charData = pcall(function()
        -- Decompress and deserialize
        local compressed = LibDeflate:DecodeForPrint(archive.data)
        local serialized = LibDeflate:DecompressDeflate(compressed)
        local deserializeSuccess, data = AceSerializer:Deserialize(serialized)
        
        if not deserializeSuccess then
            error("Failed to deserialize archived character")
        end
        
        return data
    end)
    
    if success then
        -- Restore to active characters
        if not self.db.global.characters then
            self.db.global.characters = {}
        end
        self.db.global.characters[charKey] = charData
        
        -- Remove from archives
        self.db.global.archivedCharacters[charKey] = nil
        
        return true
    end
    
    return false
end

--[[
    Create a backup of the current database
    @return success boolean
]]
function WarbandNexus:CreateBackup()
    if not self.db or not self.db.global then
        return false
    end
    
    local success = pcall(function()
        if not self.db.global.backups then
            self.db.global.backups = {}
        end
        
        -- Compress current state
        local dataToBackup = self.db.global.characters or {}
        local serialized = LibSerialize:Serialize(dataToBackup)
        local compressed = LibDeflate:CompressDeflate(serialized, {level = 5})
        local encoded = LibDeflate:EncodeForPrint(compressed)
        
        -- Store backup with timestamp
        local timestamp = time()
        self.db.global.backups[timestamp] = {
            data = encoded,
            timestamp = timestamp,
            characterCount = self:GetTableSize(dataToBackup)
        }
        
        -- Clean old backups
        self:CleanOldBackups()
    end)
    
    return success
end

--[[
    Restore database from most recent backup
    @return success boolean
]]
function WarbandNexus:RestoreFromBackup()
    if not self.db.global.backups or not next(self.db.global.backups) then
        return false
    end
    
    -- Find most recent backup
    local latestTimestamp = 0
    for timestamp, _ in pairs(self.db.global.backups) do
        if timestamp > latestTimestamp then
            latestTimestamp = timestamp
        end
    end
    
    if latestTimestamp == 0 then
        return false
    end
    
    local backup = self.db.global.backups[latestTimestamp]
    
    local success, characters = pcall(function()
        local compressed = LibDeflate:DecodeForPrint(backup.data)
        local serialized = LibDeflate:DecompressDeflate(compressed)
        local deserializeSuccess, data = AceSerializer:Deserialize(serialized)
        
        if not deserializeSuccess then
            error("Failed to deserialize backup")
        end
        
        return data
    end)
    
    if success then
        self.db.global.characters = characters
        self:Print("|cff00ff00Database restored from backup|r")
        return true
    end
    
    return false
end

--[[
    Clean backups older than retention period
]]
function WarbandNexus:CleanOldBackups()
    if not self.db.global.backups then
        return
    end
    
    local cutoffTime = time() - (BACKUP_RETENTION_DAYS * 86400)
    local removed = 0
    
    for timestamp, _ in pairs(self.db.global.backups) do
        if timestamp < cutoffTime then
            self.db.global.backups[timestamp] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        self:Debug("Cleaned " .. removed .. " old backups")
    end
end

--[[
    Auto-archive inactive characters
    @return archived number - Count of archived characters
]]
function WarbandNexus:AutoArchiveInactiveCharacters()
    if not self.db.global.characters then
        return 0
    end
    
    local archived = 0
    local currentTime = time()
    
    for charKey, charData in pairs(self.db.global.characters) do
        local lastLogin = charData.lastLogin or 0
        local daysSinceLogin = (currentTime - lastLogin) / 86400
        
        if daysSinceLogin >= ARCHIVE_THRESHOLD_DAYS then
            if self:ArchiveCharacter(charKey) then
                archived = archived + 1
            end
        end
    end
    
    return archived
end

--[[
    Get compression statistics
    @return table - Stats about compression
]]
function WarbandNexus:GetCompressionStats()
    local stats = {
        isCompressed = self.db.global.compressedData ~= nil,
        characterCount = 0,
        archivedCount = 0,
        backupCount = 0,
        originalSize = 0,
        compressedSize = 0,
        ratio = 0
    }
    
    if self.db.global.characters then
        stats.characterCount = self:GetTableSize(self.db.global.characters)
    end
    
    if self.db.global.archivedCharacters then
        stats.archivedCount = self:GetTableSize(self.db.global.archivedCharacters)
    end
    
    if self.db.global.backups then
        stats.backupCount = self:GetTableSize(self.db.global.backups)
    end
    
    if self.db.global.compressionStats then
        local cs = self.db.global.compressionStats
        stats.originalSize = cs.originalSize or 0
        stats.compressedSize = cs.compressedSize or 0
        stats.ratio = cs.ratio or 0
        stats.lastCompression = cs.timestamp or 0
    end
    
    return stats
end

--[[
    Helper: Get table size (number of keys)
]]
function WarbandNexus:GetTableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--[[
    Manual compression trigger (for UI button)
]]
function WarbandNexus:ManualCompress()
    -- Create backup first
    if not self:CreateBackup() then
        self:Print("|cffff6600Warning: Could not create backup before compression|r")
    end
    
    -- Pack database
    local success, message = self:PackDatabase()
    
    if success then
        self:Print("|cff00ff00Compression successful:|r " .. message)
        
        -- Immediately unpack for continued use
        self:UnpackDatabase()
    else
        self:Print("|cffff0000Compression failed:|r " .. message)
    end
end

--[[
    Initialize compression system
]]
function WarbandNexus:InitializeCompression()
    -- Unpack on login
    local success, message = self:UnpackDatabase()
    if success then
        self:Debug("Database unpacked: " .. message)
    else
        self:Print("|cffff0000Database initialization failed:|r " .. message)
    end
    
    -- Register logout handler
    self:RegisterEvent("PLAYER_LOGOUT", function()
        -- Create backup before packing
        self:CreateBackup()
        
        -- Pack database
        local packSuccess, packMessage = self:PackDatabase()
        if packSuccess then
            self:Debug("Database packed for logout: " .. packMessage)
        else
            self:Debug("Database packing failed: " .. packMessage)
        end
    end)
    
    -- Auto-archive inactive characters (daily check)
    C_Timer.NewTicker(86400, function() -- 24 hours
        local archived = self:AutoArchiveInactiveCharacters()
        if archived > 0 then
            self:Debug("Auto-archived " .. archived .. " inactive characters")
        end
    end)
end

