--[[
    Warband Nexus - Item Data Normalizer
    Normalizes item storage by removing static data that can be fetched at runtime
    Reduces database size by ~90% for item data
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Cache for item info to reduce API calls
local itemInfoCache = {}
local CACHE_DURATION = 300 -- 5 minutes

--[[
    Normalize item data (remove static fields)
    @param itemData table - Full item data
    @return table - Normalized item data (id, count, slot only)
]]
function WarbandNexus:NormalizeItemData(itemData)
    if not itemData or not itemData.itemID then
        return nil
    end
    
    return {
        id = itemData.itemID,
        count = itemData.stackCount or 1,
        link = itemData.itemLink, -- Keep link for tooltip/quality
        classID = itemData.classID -- Keep classID for grouping/filtering
    }
end

--[[
    Expand normalized item data (fetch static fields at runtime)
    @param normalizedData table - Normalized item data
    @return table - Full item data with static fields
]]
function WarbandNexus:ExpandItemData(normalizedData)
    if not normalizedData or not normalizedData.id then
        return nil
    end
    
    -- Check cache first
    local cacheKey = normalizedData.id
    local cached = itemInfoCache[cacheKey]
    if cached and (time() - cached.timestamp) < CACHE_DURATION then
        return self:MergeItemData(normalizedData, cached.data)
    end
    
    -- Fetch from API (use global GetItemInfo for compatibility)
    local itemID = normalizedData.id
    local name, link, quality, _, _, _, itemSubType, _, _, icon, _, classID, subclassID = GetItemInfo(itemID)
    
    if not name then
        -- Item not in cache yet, return minimal data
        return {
            itemID = itemID,
            stackCount = normalizedData.count,
            itemLink = normalizedData.link,
            quality = 0,
            iconFileID = 134400, -- Question mark icon
            name = "Item #" .. itemID,
            loading = true
        }
    end
    
    -- Cache the static data
    local staticData = {
        name = name,
        quality = quality,
        iconFileID = icon,
        itemType = itemSubType,
        classID = classID,
        subclassID = subclassID
    }
    
    itemInfoCache[cacheKey] = {
        data = staticData,
        timestamp = time()
    }
    
    return self:MergeItemData(normalizedData, staticData)
end

--[[
    Merge normalized data with static data
    @param normalized table - Normalized item data
    @param static table - Static item data
    @return table - Merged data
]]
function WarbandNexus:MergeItemData(normalized, static)
    return {
        itemID = normalized.id,
        itemLink = normalized.link,
        stackCount = normalized.count,
        quality = static.quality,
        iconFileID = static.iconFileID,
        name = static.name,
        itemType = static.itemType,
        classID = static.classID,
        subclassID = static.subclassID
    }
end

--[[
    Clear item info cache
]]
function WarbandNexus:ClearItemCache()
    table.wipe(itemInfoCache)
end

--[[
    Preload item data for a list of item IDs
    @param itemIDs table - Array of item IDs
]]
function WarbandNexus:PreloadItemData(itemIDs)
    if not itemIDs then return end
    
    for _, itemID in ipairs(itemIDs) do
        -- Use C_Item if available, otherwise just call GetItemInfo to trigger load
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        else
            GetItemInfo(itemID) -- This triggers item load as fallback
        end
    end
end

--[[
    Get cache statistics
    @return table - Cache stats
]]
function WarbandNexus:GetItemCacheStats()
    local count = 0
    local oldEntries = 0
    local currentTime = time()
    
    for _, cached in pairs(itemInfoCache) do
        count = count + 1
        if (currentTime - cached.timestamp) > CACHE_DURATION then
            oldEntries = oldEntries + 1
        end
    end
    
    return {
        totalEntries = count,
        staleEntries = oldEntries,
        freshEntries = count - oldEntries
    }
end

