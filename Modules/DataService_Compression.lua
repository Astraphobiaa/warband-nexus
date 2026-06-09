--[[
    Warband Nexus - LibSerialize/LibDeflate collection + session cache compression helpers.
    Split from DataService.lua (Lua 5.1 local limit).
    Loaded before Modules/DataService.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local LibSerialize = LibStub and LibStub("LibSerialize-1.0", true)
local LibDeflate = LibStub and LibStub("LibDeflate", true)
function WarbandNexus:CompressCollectionData(data)
    if not LibSerialize or not LibDeflate then
        self:Debug("LibSerialize or LibDeflate not available")
        return nil
    end
    
    if not data or type(data) ~= "table" then
        return nil
    end
    
    -- Serialize
    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        self:Debug("Failed to serialize collection data")
        return nil
    end
    
    -- Compress
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        self:Debug("Failed to compress collection data")
        return nil
    end
    
    -- Encode for storage
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        self:Debug("Failed to encode collection data")
        return nil
    end
    
    return encoded
end

--[[
    Decompress collection data from storage
    @param compressed string - Compressed and encoded string
    @return table - Decompressed collection cache data
]]
function WarbandNexus:DecompressCollectionData(compressed)
    if not LibSerialize or not LibDeflate then
        self:Debug("LibSerialize or LibDeflate not available")
        return nil
    end
    
    if not compressed or type(compressed) ~= "string" then
        return nil
    end
    
    -- Decode
    local decoded = LibDeflate:DecodeForPrint(compressed)
    if not decoded then
        self:Debug("Failed to decode collection data")
        return nil
    end
    
    -- Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        self:Debug("Failed to decompress collection data")
        return nil
    end
    
    -- Deserialize
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success or type(data) ~= "table" then
        return nil
    end
    
    return data
end

--[[
    Generic table decompression (wrapper for DecompressCollectionData)
    @param compressed string - Compressed and encoded string
    @return table - Decompressed data or nil
]]
function WarbandNexus:DecompressTable(compressed)
    return self:DecompressCollectionData(compressed)
end

--[[
    Generic table compression (wrapper for CompressCollectionData)
    @param data table - Data to compress
    @return string - Compressed and encoded string or nil
]]
function WarbandNexus:CompressTable(data)
    return self:CompressCollectionData(data)
end

--[[
    Get current cache version for validation
    @return string - Game version (build number)
]]
function WarbandNexus:GetCacheVersion()
    return select(4, GetBuildInfo())
end

--[[
    Check if cached data is valid for current game version
    @param savedVersion string - Saved cache version
    @return boolean - True if valid
]]
function WarbandNexus:IsCacheValid(savedVersion)
    local currentVersion = self:GetCacheVersion()
    return savedVersion == currentVersion
end
