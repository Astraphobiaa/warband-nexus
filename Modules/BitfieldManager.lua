--[[
    Warband Nexus - Bitfield Manager Module
    Efficient storage of boolean data (learned recipes, completed quests, etc.)
    using bit arrays instead of table entries
    
    Example: 1000 recipes stored as ~125 bytes instead of 1000+ table entries
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Local references for performance
local floor = math.floor
local strchar = string.char
local strbyte = string.byte
local strfind = string.find
local strsub = string.sub
local tinsert = table.insert
local tconcat = table.concat

-- Bitfield constants
local BITS_PER_BYTE = 8
local MAX_ID = 1000000 -- Maximum ID we can store (adjustable)

--[[
    Create a new empty bitfield
    @param maxSize number - Maximum number of IDs to support
    @return string - Empty bitfield
]]
function WarbandNexus:CreateBitfield(maxSize)
    maxSize = maxSize or MAX_ID
    local byteCount = floor((maxSize + BITS_PER_BYTE - 1) / BITS_PER_BYTE)
    return string.rep("\0", byteCount)
end

--[[
    Set a bit in the bitfield (mark ID as present)
    @param bitfield string - The bitfield
    @param id number - The ID to set
    @return string - Updated bitfield
]]
function WarbandNexus:SetBit(bitfield, id)
    if not bitfield or not id or id < 0 then
        return bitfield
    end
    
    local byteIndex = floor(id / BITS_PER_BYTE) + 1
    local bitIndex = id % BITS_PER_BYTE
    
    -- Extend bitfield if necessary
    local currentLength = #bitfield
    if byteIndex > currentLength then
        bitfield = bitfield .. string.rep("\0", byteIndex - currentLength)
    end
    
    -- Get current byte
    local currentByte = strbyte(bitfield, byteIndex) or 0
    
    -- Set the bit
    local newByte = bit.bor(currentByte, bit.lshift(1, bitIndex))
    
    -- Replace byte in string
    local before = byteIndex > 1 and strsub(bitfield, 1, byteIndex - 1) or ""
    local after = byteIndex < #bitfield and strsub(bitfield, byteIndex + 1) or ""
    
    return before .. strchar(newByte) .. after
end

--[[
    Clear a bit in the bitfield (mark ID as absent)
    @param bitfield string - The bitfield
    @param id number - The ID to clear
    @return string - Updated bitfield
]]
function WarbandNexus:ClearBit(bitfield, id)
    if not bitfield or not id or id < 0 then
        return bitfield
    end
    
    local byteIndex = floor(id / BITS_PER_BYTE) + 1
    local bitIndex = id % BITS_PER_BYTE
    
    if byteIndex > #bitfield then
        return bitfield -- Bit is already 0 (not set)
    end
    
    -- Get current byte
    local currentByte = strbyte(bitfield, byteIndex) or 0
    
    -- Clear the bit
    local newByte = bit.band(currentByte, bit.bnot(bit.lshift(1, bitIndex)))
    
    -- Replace byte in string
    local before = byteIndex > 1 and strsub(bitfield, 1, byteIndex - 1) or ""
    local after = byteIndex < #bitfield and strsub(bitfield, byteIndex + 1) or ""
    
    return before .. strchar(newByte) .. after
end

--[[
    Test if a bit is set in the bitfield
    @param bitfield string - The bitfield
    @param id number - The ID to test
    @return boolean - True if bit is set
]]
function WarbandNexus:TestBit(bitfield, id)
    if not bitfield or not id or id < 0 then
        return false
    end
    
    local byteIndex = floor(id / BITS_PER_BYTE) + 1
    local bitIndex = id % BITS_PER_BYTE
    
    if byteIndex > #bitfield then
        return false -- Bit is not set
    end
    
    local currentByte = strbyte(bitfield, byteIndex) or 0
    local mask = bit.lshift(1, bitIndex)
    
    return bit.band(currentByte, mask) ~= 0
end

--[[
    Set multiple bits from an array of IDs
    @param bitfield string - The bitfield
    @param ids table - Array of IDs to set
    @return string - Updated bitfield
]]
function WarbandNexus:SetBits(bitfield, ids)
    if not ids or type(ids) ~= "table" then
        return bitfield
    end
    
    for _, id in ipairs(ids) do
        bitfield = self:SetBit(bitfield, id)
    end
    
    return bitfield
end

--[[
    Get all set bits as an array of IDs
    @param bitfield string - The bitfield
    @param maxID number - Maximum ID to check (optional)
    @return table - Array of IDs that are set
]]
function WarbandNexus:GetSetBits(bitfield, maxID)
    if not bitfield or #bitfield == 0 then
        return {}
    end
    
    local result = {}
    maxID = maxID or (#bitfield * BITS_PER_BYTE)
    
    for id = 0, maxID - 1 do
        if self:TestBit(bitfield, id) then
            tinsert(result, id)
        end
    end
    
    return result
end

--[[
    Count the number of set bits
    @param bitfield string - The bitfield
    @return number - Count of set bits
]]
function WarbandNexus:CountSetBits(bitfield)
    if not bitfield or #bitfield == 0 then
        return 0
    end
    
    local count = 0
    
    for i = 1, #bitfield do
        local byte = strbyte(bitfield, i)
        
        -- Count bits in byte using Brian Kernighan's algorithm
        while byte ~= 0 do
            byte = bit.band(byte, byte - 1)
            count = count + 1
        end
    end
    
    return count
end

--[[
    Compress bitfield (remove trailing zeros)
    @param bitfield string - The bitfield
    @return string - Compressed bitfield
]]
function WarbandNexus:CompressBitfield(bitfield)
    if not bitfield or #bitfield == 0 then
        return ""
    end
    
    -- Find last non-zero byte
    local lastNonZero = 0
    for i = #bitfield, 1, -1 do
        if strbyte(bitfield, i) ~= 0 then
            lastNonZero = i
            break
        end
    end
    
    if lastNonZero == 0 then
        return "" -- All zeros
    end
    
    return strsub(bitfield, 1, lastNonZero)
end

--[[
    Merge two bitfields (OR operation)
    @param bitfield1 string - First bitfield
    @param bitfield2 string - Second bitfield
    @return string - Merged bitfield
]]
function WarbandNexus:MergeBitfields(bitfield1, bitfield2)
    if not bitfield1 then return bitfield2 or "" end
    if not bitfield2 then return bitfield1 end
    
    local maxLen = math.max(#bitfield1, #bitfield2)
    local result = {}
    
    for i = 1, maxLen do
        local byte1 = strbyte(bitfield1, i) or 0
        local byte2 = strbyte(bitfield2, i) or 0
        tinsert(result, strchar(bit.bor(byte1, byte2)))
    end
    
    return tconcat(result)
end

--[[
    Get difference between two bitfields (XOR operation)
    @param bitfield1 string - First bitfield
    @param bitfield2 string - Second bitfield
    @return string - Difference bitfield
]]
function WarbandNexus:DiffBitfields(bitfield1, bitfield2)
    if not bitfield1 then return bitfield2 or "" end
    if not bitfield2 then return bitfield1 end
    
    local maxLen = math.max(#bitfield1, #bitfield2)
    local result = {}
    
    for i = 1, maxLen do
        local byte1 = strbyte(bitfield1, i) or 0
        local byte2 = strbyte(bitfield2, i) or 0
        tinsert(result, strchar(bit.bxor(byte1, byte2)))
    end
    
    return tconcat(result)
end

--[[
    Recipe-specific: Set learned recipes for a profession
    @param professionID number - Profession ID
    @param recipeIDs table - Array of recipe IDs
    @return string - Bitfield of learned recipes
]]
function WarbandNexus:SetLearnedRecipes(professionID, recipeIDs)
    if not recipeIDs or type(recipeIDs) ~= "table" then
        return ""
    end
    
    -- Create empty bitfield
    local bitfield = self:CreateBitfield(100000) -- Support up to 100k recipe IDs
    
    -- Set bits for each learned recipe
    bitfield = self:SetBits(bitfield, recipeIDs)
    
    -- Compress to remove trailing zeros
    bitfield = self:CompressBitfield(bitfield)
    
    return bitfield
end

--[[
    Recipe-specific: Get learned recipes from bitfield
    @param bitfield string - Recipe bitfield
    @return table - Array of learned recipe IDs
]]
function WarbandNexus:GetLearnedRecipes(bitfield)
    if not bitfield or #bitfield == 0 then
        return {}
    end
    
    return self:GetSetBits(bitfield, 100000)
end

--[[
    Recipe-specific: Check if a recipe is learned
    @param bitfield string - Recipe bitfield
    @param recipeID number - Recipe ID to check
    @return boolean - True if learned
]]
function WarbandNexus:IsRecipeLearned(bitfield, recipeID)
    return self:TestBit(bitfield, recipeID)
end

--[[
    Quest-specific: Set completed quests
    @param questIDs table - Array of quest IDs
    @return string - Bitfield of completed quests
]]
function WarbandNexus:SetCompletedQuests(questIDs)
    if not questIDs or type(questIDs) ~= "table" then
        return ""
    end
    
    local bitfield = self:CreateBitfield(100000) -- Support up to 100k quest IDs
    bitfield = self:SetBits(bitfield, questIDs)
    bitfield = self:CompressBitfield(bitfield)
    
    return bitfield
end

--[[
    Quest-specific: Check if a quest is completed
    @param bitfield string - Quest bitfield
    @param questID number - Quest ID to check
    @return boolean - True if completed
]]
function WarbandNexus:IsQuestCompleted(bitfield, questID)
    return self:TestBit(bitfield, questID)
end

--[[
    Get bitfield statistics
    @param bitfield string - The bitfield
    @return table - Statistics
]]
function WarbandNexus:GetBitfieldStats(bitfield)
    if not bitfield then
        return {
            size = 0,
            setBits = 0,
            capacity = 0,
            efficiency = 0
        }
    end
    
    local size = #bitfield
    local setBits = self:CountSetBits(bitfield)
    local capacity = size * BITS_PER_BYTE
    local efficiency = capacity > 0 and (setBits / capacity * 100) or 0
    
    return {
        size = size,
        setBits = setBits,
        capacity = capacity,
        efficiency = efficiency
    }
end

--[[
    Convert bitfield to hex string for display/debugging
    @param bitfield string - The bitfield
    @return string - Hex representation
]]
function WarbandNexus:BitfieldToHex(bitfield)
    if not bitfield or #bitfield == 0 then
        return ""
    end
    
    local hex = {}
    for i = 1, math.min(#bitfield, 32) do -- Limit to first 32 bytes for display
        tinsert(hex, string.format("%02X", strbyte(bitfield, i)))
    end
    
    if #bitfield > 32 then
        tinsert(hex, "...")
    end
    
    return tconcat(hex, " ")
end

--[[
    Example usage and testing
]]
function WarbandNexus:TestBitfield()
    self:Print("=== Bitfield Manager Test ===")
    
    -- Test recipe storage
    local recipeIDs = {100, 250, 500, 1000, 5000, 10000}
    local bitfield = self:SetLearnedRecipes(0, recipeIDs)
    
    self:Print("Stored " .. #recipeIDs .. " recipes in " .. #bitfield .. " bytes")
    self:Print("Hex: " .. self:BitfieldToHex(bitfield))
    
    -- Test retrieval
    for _, id in ipairs(recipeIDs) do
        local learned = self:IsRecipeLearned(bitfield, id)
        self:Print("Recipe " .. id .. ": " .. tostring(learned))
    end
    
    -- Test non-existent recipe
    self:Print("Recipe 999: " .. tostring(self:IsRecipeLearned(bitfield, 999)))
    
    -- Show stats
    local stats = self:GetBitfieldStats(bitfield)
    self:Print(string.format("Stats: %d bytes, %d bits set, %.2f%% efficiency",
        stats.size, stats.setBits, stats.efficiency))
    
    -- Compare with table storage
    local tableSize = #recipeIDs * 8 -- Approximate: each entry ~8 bytes minimum
    local savings = (1 - #bitfield / tableSize) * 100
    self:Print(string.format("Savings vs table: %.1f%% (%d bytes → %d bytes)",
        savings, tableSize, #bitfield))
end

