--[[
    Warband Nexus - Cache Manager Module
    Smart caching system for frequently accessed data
    
    Features:
    - Memory-efficient caching with size limits
    - Automatic cache invalidation on data changes
    - Cache hit/miss statistics
    - TTL (Time-To-Live) support
    - Granular cache clearing by category
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CACHE CONFIGURATION
-- ============================================================================

local CACHE_CONFIG = {
    -- Max memory per cache category (in KB, approximate)
    MAX_SIZE_PER_CATEGORY = 1024, -- 1MB per category
    
    -- TTL (seconds) for different cache types
    TTL = {
        CHARACTERS = 300,      -- 5 minutes (changes infrequently)
        ITEMS = 30,            -- 30 seconds (changes frequently during bank operations)
        PVE = 600,             -- 10 minutes (changes weekly)
        COLLECTIONS = 1800,    -- 30 minutes (changes rarely)
        SEARCH = 60,           -- 1 minute (user-driven)
        PROFESSIONS = 3600,    -- 60 minutes (changes rarely, only when player trains)
    },
    
    -- Enable/disable cache categories
    ENABLED = {
        CHARACTERS = true,
        ITEMS = true,
        PVE = true,
        COLLECTIONS = true,
        SEARCH = true,
        PROFESSIONS = true,
    },
}

-- ============================================================================
-- CACHE STORAGE
-- ============================================================================

-- Cache structure: { data = {}, timestamp = number, hits = number }
local cache = {
    characters = {},       -- Cached character list
    items = {},            -- Cached item data by location
    pve = {},              -- Cached PvE data by character
    collections = {},      -- Cached collection stats
    search = {},           -- Cached search results by query
    professions = {},      -- Cached profession data by character
}

-- Statistics
local stats = {
    hits = 0,
    misses = 0,
    invalidations = 0,
    memoryEvictions = 0,
}

-- ============================================================================
-- CORE CACHE OPERATIONS
-- ============================================================================

--[[
    Set cache entry
    @param category string - Cache category (characters, items, pve, etc.)
    @param key string - Unique key for this entry
    @param data any - Data to cache
    @param ttl number - Optional TTL override (seconds)
]]
local function SetCache(category, key, data, ttl)
    if not CACHE_CONFIG.ENABLED[category:upper()] then
        return
    end
    
    if not cache[category] then
        cache[category] = {}
    end
    
    -- Use category-specific TTL or override
    local categoryTTL = CACHE_CONFIG.TTL[category:upper()] or 300
    local finalTTL = ttl or categoryTTL
    
    cache[category][key] = {
        data = data,
        timestamp = time(),
        ttl = finalTTL,
        hits = 0,
    }
end

--[[
    Get cache entry
    @param category string - Cache category
    @param key string - Unique key
    @return any, boolean - Cached data and cache hit status (true=hit, false=miss)
]]
local function GetCache(category, key)
    if not CACHE_CONFIG.ENABLED[category:upper()] then
        return nil, false
    end
    
    if not cache[category] or not cache[category][key] then
        stats.misses = stats.misses + 1
        return nil, false
    end
    
    local entry = cache[category][key]
    local age = time() - entry.timestamp
    
    -- Check TTL expiration
    if age > entry.ttl then
        cache[category][key] = nil
        stats.misses = stats.misses + 1
        return nil, false
    end
    
    -- Cache hit!
    entry.hits = entry.hits + 1
    stats.hits = stats.hits + 1
    return entry.data, true
end

--[[
    Invalidate cache entry or entire category
    @param category string - Cache category
    @param key string - Optional specific key (if nil, clears entire category)
]]
local function InvalidateCache(category, key)
    if key then
        -- Invalidate specific key
        if cache[category] and cache[category][key] then
            cache[category][key] = nil
            stats.invalidations = stats.invalidations + 1
        end
    else
        -- Invalidate entire category
        if cache[category] then
            for k in pairs(cache[category]) do
                cache[category][k] = nil
                stats.invalidations = stats.invalidations + 1
            end
        end
    end
end

--[[
    Clear all caches
]]
local function ClearAllCaches()
    for category in pairs(cache) do
        InvalidateCache(category, nil)
    end
end

-- ============================================================================
-- PUBLIC API (WarbandNexus methods)
-- ============================================================================

--[[
    Get cached character list (or fetch and cache)
    @return table - Array of characters
]]
function WarbandNexus:GetCachedCharacters()
    local cached, hit = GetCache("characters", "list")
    if hit then
        return cached
    end
    
    -- Cache miss - fetch fresh data
    local characters = self:GetAllCharacters()
    SetCache("characters", "list", characters)
    return characters
end

--[[
    Get cached PvE data for a character
    @param characterKey string - Character key (name-realm)
    @return table - PvE data structure
]]
function WarbandNexus:GetCachedPvEData(characterKey)
    local cached, hit = GetCache("pve", characterKey)
    if hit then
        return cached
    end
    
    -- Cache miss - fetch from saved data
    if self.db.global.characters and self.db.global.characters[characterKey] then
        local pveData = self.db.global.characters[characterKey].pve
        if pveData then
            SetCache("pve", characterKey, pveData)
            return pveData
        end
    end
    
    return nil
end

--[[
    Get cached item search results
    @param searchTerm string - Search query
    @return table - Search results
]]
function WarbandNexus:GetCachedSearchResults(searchTerm)
    local searchKey = searchTerm:lower()
    local cached, hit = GetCache("search", searchKey)
    if hit then
        return cached
    end
    
    -- Cache miss - perform search
    local results = self:PerformItemSearch(searchTerm)
    SetCache("search", searchKey, results)
    return results
end

--[[
    Get cached collection stats for current character
    @return table - Collection statistics
]]
function WarbandNexus:GetCachedCollectionStats()
    local playerKey = UnitName("player") .. "-" .. GetRealmName()
    local cached, hit = GetCache("collections", playerKey)
    if hit then
        return cached
    end
    
    -- Cache miss - fetch fresh data
    local stats = self:GetCollectionStats()
    SetCache("collections", playerKey, stats)
    return stats
end

--[[
    Get cached profession data for a character
    @param characterKey string - Character key (name-realm)
    @return table - Profession data structure
]]
function WarbandNexus:GetCachedProfessionData(characterKey)
    local cached, hit = GetCache("professions", characterKey)
    if hit then
        return cached
    end
    
    -- Cache miss - fetch from saved data
    if self.db.global.characters and self.db.global.characters[characterKey] then
        local professionData = self.db.global.characters[characterKey].professions
        if professionData then
            SetCache("professions", characterKey, professionData)
            return professionData
        end
    end
    
    return nil
end

--[[
    Invalidate character cache (call after character data changes)
]]
function WarbandNexus:InvalidateCharacterCache()
    InvalidateCache("characters", "list")
end

--[[
    Invalidate item caches (call after bag/bank changes)
]]
function WarbandNexus:InvalidateItemCache()
    InvalidateCache("items", nil) -- Clear all item caches
    InvalidateCache("search", nil) -- Clear all search caches (items changed)
end

--[[
    Invalidate PvE cache for a specific character
    @param characterKey string - Optional character key (if nil, clears all)
]]
function WarbandNexus:InvalidatePvECache(characterKey)
    if characterKey then
        InvalidateCache("pve", characterKey)
    else
        InvalidateCache("pve", nil)
    end
end

--[[
    Invalidate collection cache for current character
]]
function WarbandNexus:InvalidateCollectionCache()
    local playerKey = UnitName("player") .. "-" .. GetRealmName()
    InvalidateCache("collections", playerKey)
end

--[[
    Invalidate profession cache for a specific character
    @param characterKey string - Optional character key (if nil, clears all)
]]
function WarbandNexus:InvalidateProfessionCache(characterKey)
    if characterKey then
        InvalidateCache("professions", characterKey)
    else
        InvalidateCache("professions", nil)
    end
end

--[[
    Clear all caches (useful for debugging or major data refresh)
]]
function WarbandNexus:ClearAllCaches()
    ClearAllCaches()
end

--[[
    Get cache statistics
    @return table - Cache hit/miss stats
]]
function WarbandNexus:GetCacheStats()
    local totalRequests = stats.hits + stats.misses
    local hitRate = totalRequests > 0 and (stats.hits / totalRequests * 100) or 0
    
    -- Count cache entries per category
    local entryCounts = {}
    for category, entries in pairs(cache) do
        local count = 0
        for _ in pairs(entries) do
            count = count + 1
        end
        entryCounts[category] = count
    end
    
    return {
        hits = stats.hits,
        misses = stats.misses,
        hitRate = string.format("%.1f%%", hitRate),
        invalidations = stats.invalidations,
        memoryEvictions = stats.memoryEvictions,
        entries = entryCounts,
    }
end

--[[
    Print cache statistics to chat
]]
function WarbandNexus:PrintCacheStats()
    local cacheStats = self:GetCacheStats()
    
    self:Print("===== Cache Statistics =====")
    self:Print(string.format("Hit Rate: %s (%d hits, %d misses)", 
        cacheStats.hitRate, cacheStats.hits, cacheStats.misses))
    self:Print(string.format("Invalidations: %d | Memory Evictions: %d", 
        cacheStats.invalidations, cacheStats.memoryEvictions))
    
    self:Print("Cached Entries:")
    for category, count in pairs(cacheStats.entries) do
        self:Print(string.format("  %s: %d", category, count))
    end
end

-- ============================================================================
-- AUTOMATIC CACHE MANAGEMENT
-- ============================================================================

--[[
    Periodic cache cleanup (remove expired entries)
    Called by timer (every 60 seconds)
]]
local function CleanupExpiredCaches()
    local currentTime = time()
    local removed = 0
    
    for category, entries in pairs(cache) do
        for key, entry in pairs(entries) do
            local age = currentTime - entry.timestamp
            if age > entry.ttl then
                cache[category][key] = nil
                removed = removed + 1
            end
        end
    end
    
    if removed > 0 and WarbandNexus then
    end
end

-- Start cleanup timer (every 60 seconds)
if WarbandNexus then
    WarbandNexus:ScheduleRepeatingTimer(CleanupExpiredCaches, 60)
end

-- ============================================================================
-- CACHE WARMUP (Preload frequently used data)
-- ============================================================================

--[[
    Warm up caches on addon load
    Preloads frequently accessed data to improve first-access performance
]]
function WarbandNexus:WarmupCaches()
    -- Preload character list
    self:GetCachedCharacters()
    
    -- Preload current character's PvE data
    local playerKey = UnitName("player") .. "-" .. GetRealmName()
    self:GetCachedPvEData(playerKey)
    
    -- Preload collection stats
    self:GetCachedCollectionStats()
    
end

-- ============================================================================
-- EVENT INTEGRATION (Auto-invalidation on data changes)
-- ============================================================================

--[[
    Hook into existing event handlers to auto-invalidate caches
    Called during OnEnable
]]
function WarbandNexus:InitializeCacheInvalidation()
    -- Character data changed
    self:RegisterMessage("WARBAND_CHARACTER_UPDATED", function()
        self:InvalidateCharacterCache()
    end)
    
    -- Items changed (bags/bank)
    self:RegisterMessage("WARBAND_ITEMS_UPDATED", function()
        self:InvalidateItemCache()
    end)
    
    -- PvE data changed
    self:RegisterMessage("WARBAND_PVE_UPDATED", function()
        self:InvalidatePvECache()
    end)
    
    -- Collections changed
    self:RegisterMessage("WARBAND_COLLECTIONS_UPDATED", function()
        self:InvalidateCollectionCache()
    end)
    
    -- Professions changed
    self:RegisterMessage("WARBAND_PROFESSIONS_UPDATED", function()
        self:InvalidateProfessionCache()
    end)
    
end

-- Export stats for debugging
ns.CacheStats = stats
