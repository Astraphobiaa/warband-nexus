--[[
    Warband Nexus - Memory Optimizer for UI
    Implements table recycling and string concatenation optimization
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Table pool for recycling
local tablePool = {}
local MAX_POOL_SIZE = 100

-- String builder for efficient concatenation
local stringBuilderPool = {}

-- ============================================================================
-- TABLE RECYCLING
-- ============================================================================

--[[
    Get a table from the pool (or create new)
    @return table - Recycled or new table
]]
function WarbandNexus:GetTable()
    local tbl = table.remove(tablePool)
    if not tbl then
        tbl = {}
    end
    return tbl
end

--[[
    Recycle a table back to the pool
    @param tbl table - Table to recycle
]]
function WarbandNexus:RecycleTable(tbl)
    if not tbl then return end
    
    -- Wipe the table
    table.wipe(tbl)
    
    -- Add back to pool if not full
    if #tablePool < MAX_POOL_SIZE then
        table.insert(tablePool, tbl)
    end
end

--[[
    Recycle multiple tables at once
    @param ... tables - Tables to recycle
]]
function WarbandNexus:RecycleTables(...)
    for i = 1, select("#", ...) do
        local tbl = select(i, ...)
        self:RecycleTable(tbl)
    end
end

--[[
    Clear the table pool
]]
function WarbandNexus:ClearTablePool()
    table.wipe(tablePool)
end

-- ============================================================================
-- STRING BUILDER (Efficient Concatenation)
-- ============================================================================

--[[
    Create a new string builder
    @return table - String builder
]]
function WarbandNexus:CreateStringBuilder()
    local builder = table.remove(stringBuilderPool)
    if not builder then
        builder = {}
    end
    return builder
end

--[[
    Append to string builder
    @param builder table - String builder
    @param str string - String to append
]]
function WarbandNexus:AppendString(builder, str)
    table.insert(builder, str)
end

--[[
    Append multiple strings
    @param builder table - String builder
    @param ... strings - Strings to append
]]
function WarbandNexus:AppendStrings(builder, ...)
    for i = 1, select("#", ...) do
        local str = select(i, ...)
        table.insert(builder, str)
    end
end

--[[
    Append with separator
    @param builder table - String builder
    @param separator string - Separator
    @param str string - String to append
]]
function WarbandNexus:AppendWithSeparator(builder, separator, str)
    if #builder > 0 then
        table.insert(builder, separator)
    end
    table.insert(builder, str)
end

--[[
    Build final string and recycle builder
    @param builder table - String builder
    @param separator string - Optional separator (default: "")
    @return string - Final concatenated string
]]
function WarbandNexus:BuildString(builder, separator)
    local result = table.concat(builder, separator or "")
    
    -- Recycle builder
    table.wipe(builder)
    if #stringBuilderPool < MAX_POOL_SIZE then
        table.insert(stringBuilderPool, builder)
    end
    
    return result
end

-- ============================================================================
-- FRAME RECYCLING
-- ============================================================================

-- Frame pools by type
local framePools = {
    Frame = {},
    Button = {},
    FontString = {},
    Texture = {}
}

--[[
    Get a frame from pool or create new
    @param frameType string - Frame type
    @param parent frame - Parent frame
    @param template string - Optional template
    @return frame - Recycled or new frame
]]
function WarbandNexus:GetFrame(frameType, parent, template)
    local pool = framePools[frameType]
    if not pool then
        pool = {}
        framePools[frameType] = pool
    end
    
    -- Try to get from pool
    local frame = table.remove(pool)
    
    if frame then
        -- Reuse existing frame
        frame:SetParent(parent)
        frame:ClearAllPoints()
        frame:Show()
        return frame
    else
        -- Create new frame
        if frameType == "FontString" then
            return parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
        elseif frameType == "Texture" then
            return parent:CreateTexture(nil, "ARTWORK")
        else
            return CreateFrame(frameType, nil, parent, template)
        end
    end
end

--[[
    Recycle a frame back to pool
    @param frame frame - Frame to recycle
    @param frameType string - Frame type
]]
function WarbandNexus:RecycleFrame(frame, frameType)
    if not frame or not frameType then return end
    
    local pool = framePools[frameType]
    if not pool then return end
    
    -- Hide and clear
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    
    -- Clear scripts
    if frame.SetScript then
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
        frame:SetScript("OnClick", nil)
        frame:SetScript("OnUpdate", nil)
    end
    
    -- Add to pool if not full
    if #pool < MAX_POOL_SIZE then
        table.insert(pool, frame)
    end
end

--[[
    Recycle all child frames of a parent
    @param parent frame - Parent frame
]]
function WarbandNexus:RecycleChildFrames(parent)
    if not parent then return end
    
    local children = {parent:GetChildren()}
    for _, child in ipairs(children) do
        local frameType = child:GetObjectType()
        self:RecycleFrame(child, frameType)
    end
end

-- ============================================================================
-- SCROLL FRAME OPTIMIZATION
-- ============================================================================

-- Row pools for scroll frames
local scrollRowPools = {}

--[[
    Create a scroll row pool for a specific scroll frame
    @param scrollFrameName string - Unique name for this scroll frame
    @param createFunc function - Function to create a new row
    @return table - Row pool
]]
function WarbandNexus:CreateScrollRowPool(scrollFrameName, createFunc)
    if not scrollRowPools[scrollFrameName] then
        scrollRowPools[scrollFrameName] = {
            active = {},
            inactive = {},
            createFunc = createFunc
        }
    end
    
    return scrollRowPools[scrollFrameName]
end

--[[
    Get a row from scroll pool
    @param poolName string - Pool name
    @param parent frame - Parent frame
    @return frame - Row frame
]]
function WarbandNexus:GetScrollRow(poolName, parent)
    local pool = scrollRowPools[poolName]
    if not pool then return nil end
    
    -- Try to reuse inactive row
    local row = table.remove(pool.inactive)
    
    if not row then
        -- Create new row
        row = pool.createFunc(parent)
    end
    
    -- Mark as active
    table.insert(pool.active, row)
    row:Show()
    
    return row
end

--[[
    Recycle all active rows in a scroll pool
    @param poolName string - Pool name
]]
function WarbandNexus:RecycleScrollRows(poolName)
    local pool = scrollRowPools[poolName]
    if not pool then return end
    
    -- Move all active rows to inactive
    for _, row in ipairs(pool.active) do
        row:Hide()
        row:ClearAllPoints()
        table.insert(pool.inactive, row)
    end
    
    -- Clear active list
    table.wipe(pool.active)
end

--[[
    Clear a scroll row pool
    @param poolName string - Pool name
]]
function WarbandNexus:ClearScrollRowPool(poolName)
    scrollRowPools[poolName] = nil
end

-- ============================================================================
-- MEMORY STATISTICS
-- ============================================================================

--[[
    Get memory optimization statistics
    @return table - Statistics
]]
function WarbandNexus:GetMemoryStats()
    local stats = {
        tablePool = #tablePool,
        stringBuilderPool = #stringBuilderPool,
        framePools = {},
        scrollRowPools = {},
        totalPooledObjects = #tablePool + #stringBuilderPool
    }
    
    -- Count frames in pools
    for frameType, pool in pairs(framePools) do
        stats.framePools[frameType] = #pool
        stats.totalPooledObjects = stats.totalPooledObjects + #pool
    end
    
    -- Count scroll rows
    for poolName, pool in pairs(scrollRowPools) do
        stats.scrollRowPools[poolName] = {
            active = #pool.active,
            inactive = #pool.inactive
        }
        stats.totalPooledObjects = stats.totalPooledObjects + #pool.inactive
    end
    
    return stats
end

--[[
    Clear all memory pools
]]
function WarbandNexus:ClearAllMemoryPools()
    table.wipe(tablePool)
    table.wipe(stringBuilderPool)
    
    for _, pool in pairs(framePools) do
        table.wipe(pool)
    end
    
    for _, pool in pairs(scrollRowPools) do
        table.wipe(pool.active)
        table.wipe(pool.inactive)
    end
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Format large numbers with separators
    @param number number - Number to format
    @return string - Formatted number
]]
function WarbandNexus:FormatNumber(number)
    if not number then return "0" end
    
    local builder = self:CreateStringBuilder()
    local str = tostring(math.floor(number))
    local len = #str
    
    for i = 1, len do
        local digit = str:sub(i, i)
        self:AppendString(builder, digit)
        
        -- Add separator every 3 digits from the right
        local remaining = len - i
        if remaining > 0 and remaining % 3 == 0 then
            self:AppendString(builder, ",")
        end
    end
    
    return self:BuildString(builder)
end

--[[
    Format bytes to human-readable size
    @param bytes number - Bytes
    @return string - Formatted size
]]
function WarbandNexus:FormatBytes(bytes)
    if not bytes or bytes < 1024 then
        return string.format("%d B", bytes or 0)
    elseif bytes < 1048576 then
        return string.format("%.2f KB", bytes / 1024)
    elseif bytes < 1073741824 then
        return string.format("%.2f MB", bytes / 1048576)
    else
        return string.format("%.2f GB", bytes / 1073741824)
    end
end

-- Export to namespace
ns.MemoryOptimizer = {
    GetTable = function(...) return WarbandNexus:GetTable(...) end,
    RecycleTable = function(...) return WarbandNexus:RecycleTable(...) end,
    CreateStringBuilder = function(...) return WarbandNexus:CreateStringBuilder(...) end,
    AppendString = function(...) return WarbandNexus:AppendString(...) end,
    BuildString = function(...) return WarbandNexus:BuildString(...) end,
    GetFrame = function(...) return WarbandNexus:GetFrame(...) end,
    RecycleFrame = function(...) return WarbandNexus:RecycleFrame(...) end,
}

