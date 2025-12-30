--[[
    Warband Nexus - Search Indexer Module
    Implements reverse index for O(1) item lookups
    Dramatically improves search performance for large databases
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Search index structure
local searchIndex = {}
local indexTimestamp = 0
local INDEX_REBUILD_INTERVAL = 300 -- Rebuild every 5 minutes if needed

--[[
    Build or rebuild the search index
    @param force boolean - Force rebuild even if recent
    @return boolean - Success
]]
function WarbandNexus:RebuildSearchIndex(force)
    if not force and (time() - indexTimestamp) < INDEX_REBUILD_INTERVAL then
        return true -- Index is recent enough
    end
    
    local startTime = debugprofilestop()
    
    -- Clear existing index
    table.wipe(searchIndex)
    
    local itemCount = 0
    
    -- Index Warband Bank items
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        for tabIndex, tab in pairs(self.db.global.warbandBank.items) do
            for slotID, item in pairs(tab) do
                if item and item.id then
                    self:AddToSearchIndex(item.id, {
                        charKey = "@warband",
                        location = "warbandBank",
                        tab = tabIndex,
                        slot = slotID,
                        count = item.count or 1
                    })
                    itemCount = itemCount + 1
                end
            end
        end
    end
    
    -- Index character items (bags and bank)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            -- Index bags
            if charData.bags then
                for bagIndex, bag in pairs(charData.bags) do
                    if bag.items then
                        for slot, item in pairs(bag.items) do
                            if item and item.id then
                                self:AddToSearchIndex(item.id, {
                                    charKey = charKey,
                                    location = "bags",
                                    bag = bagIndex,
                                    slot = slot,
                                    count = item.count or 1
                                })
                                itemCount = itemCount + 1
                            end
                        end
                    end
                end
            end
            
            -- Index bank
            if charData.bank then
                for slot, item in pairs(charData.bank) do
                    if item and item.id then
                        self:AddToSearchIndex(item.id, {
                            charKey = charKey,
                            location = "bank",
                            slot = slot,
                            count = item.count or 1
                        })
                        itemCount = itemCount + 1
                    end
                end
            end
        end
    end
    
    indexTimestamp = time()
    local elapsed = debugprofilestop() - startTime
    
    self:Debug(string.format("Search index rebuilt: %d items in %.0f ms", itemCount, elapsed))
    
    return true
end

--[[
    Add an item to the search index
    @param itemID number - Item ID
    @param location table - Location data
]]
function WarbandNexus:AddToSearchIndex(itemID, location)
    if not searchIndex[itemID] then
        searchIndex[itemID] = {}
    end
    
    table.insert(searchIndex[itemID], location)
end

--[[
    Remove an item from the search index
    @param itemID number - Item ID
    @param charKey string - Character key
    @param location string - Location type
    @param slot number - Slot number
]]
function WarbandNexus:RemoveFromSearchIndex(itemID, charKey, location, slot)
    if not searchIndex[itemID] then
        return
    end
    
    for i = #searchIndex[itemID], 1, -1 do
        local loc = searchIndex[itemID][i]
        if loc.charKey == charKey and loc.location == location and loc.slot == slot then
            table.remove(searchIndex[itemID], i)
            break
        end
    end
    
    -- Remove itemID entry if no locations left
    if #searchIndex[itemID] == 0 then
        searchIndex[itemID] = nil
    end
end

--[[
    Search for items by ID (O(1) lookup)
    @param itemID number - Item ID to search for
    @return table - Array of locations where item is found
]]
function WarbandNexus:SearchByItemID(itemID)
    -- Rebuild index if stale
    if (time() - indexTimestamp) > INDEX_REBUILD_INTERVAL then
        self:RebuildSearchIndex(false)
    end
    
    return searchIndex[itemID] or {}
end

--[[
    Search for items by name (requires item info lookup)
    @param searchTerm string - Item name or partial name
    @param maxResults number - Maximum results to return (default 100)
    @return table - Array of search results
]]
function WarbandNexus:SearchByItemName(searchTerm, maxResults)
    maxResults = maxResults or 100
    
    if not searchTerm or searchTerm == "" then
        return {}
    end
    
    searchTerm = searchTerm:lower()
    local results = {}
    local resultCount = 0
    
    -- Rebuild index if needed
    if (time() - indexTimestamp) > INDEX_REBUILD_INTERVAL then
        self:RebuildSearchIndex(false)
    end
    
    -- Search through indexed items
    for itemID, locations in pairs(searchIndex) do
        if resultCount >= maxResults then
            break
        end
        
        -- Get item name
        local itemName = C_Item.GetItemNameByID(itemID)
        if itemName and itemName:lower():find(searchTerm, 1, true) then
            -- Add all locations for this item
            for _, location in ipairs(locations) do
                table.insert(results, {
                    itemID = itemID,
                    itemName = itemName,
                    location = location
                })
                resultCount = resultCount + 1
                
                if resultCount >= maxResults then
                    break
                end
            end
        end
    end
    
    return results
end

--[[
    Get total count of an item across all characters
    @param itemID number - Item ID
    @return number - Total count
]]
function WarbandNexus:GetItemTotalCount(itemID)
    local locations = self:SearchByItemID(itemID)
    local total = 0
    
    for _, location in ipairs(locations) do
        total = total + (location.count or 1)
    end
    
    return total
end

--[[
    Get all characters that have a specific item
    @param itemID number - Item ID
    @return table - Array of character keys
]]
function WarbandNexus:GetCharactersWithItem(itemID)
    local locations = self:SearchByItemID(itemID)
    local characters = {}
    local seen = {}
    
    for _, location in ipairs(locations) do
        local charKey = location.charKey
        if charKey and charKey ~= "@warband" and not seen[charKey] then
            table.insert(characters, charKey)
            seen[charKey] = true
        end
    end
    
    return characters
end

--[[
    Incremental index update (add item)
    @param itemID number - Item ID
    @param charKey string - Character key
    @param location string - Location type
    @param slot number - Slot number
    @param count number - Stack count
]]
function WarbandNexus:IndexAddItem(itemID, charKey, location, slot, count)
    self:AddToSearchIndex(itemID, {
        charKey = charKey,
        location = location,
        slot = slot,
        count = count or 1
    })
end

--[[
    Incremental index update (remove item)
    @param itemID number - Item ID
    @param charKey string - Character key
    @param location string - Location type
    @param slot number - Slot number
]]
function WarbandNexus:IndexRemoveItem(itemID, charKey, location, slot)
    self:RemoveFromSearchIndex(itemID, charKey, location, slot)
end

--[[
    Get search index statistics
    @return table - Index statistics
]]
function WarbandNexus:GetSearchIndexStats()
    local uniqueItems = 0
    local totalLocations = 0
    
    for itemID, locations in pairs(searchIndex) do
        uniqueItems = uniqueItems + 1
        totalLocations = totalLocations + #locations
    end
    
    return {
        uniqueItems = uniqueItems,
        totalLocations = totalLocations,
        lastRebuild = indexTimestamp,
        age = time() - indexTimestamp,
        isStale = (time() - indexTimestamp) > INDEX_REBUILD_INTERVAL
    }
end

--[[
    Clear the search index
]]
function WarbandNexus:ClearSearchIndex()
    table.wipe(searchIndex)
    indexTimestamp = 0
    self:Debug("Search index cleared")
end

--[[
    Initialize search indexer
]]
function WarbandNexus:InitializeSearchIndexer()
    -- Build initial index
    self:RebuildSearchIndex(true)
    
    -- Register events for incremental updates
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        -- Rebuild index after bag changes
        C_Timer.After(2, function()
            self:RebuildSearchIndex(false)
        end)
    end)
    
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        -- Rebuild index after bank interaction
        C_Timer.After(1, function()
            self:RebuildSearchIndex(false)
        end)
    end)
    
    -- Periodic rebuild (every 5 minutes)
    C_Timer.NewTicker(INDEX_REBUILD_INTERVAL, function()
        local stats = self:GetSearchIndexStats()
        if stats.isStale then
            self:RebuildSearchIndex(false)
        end
    end)
    
    self:Debug("Search indexer initialized")
end

--[[
    Export search index for debugging
    @return string - Formatted index info
]]
function WarbandNexus:ExportSearchIndexInfo()
    local stats = self:GetSearchIndexStats()
    local lines = {}
    
    table.insert(lines, "=== Search Index Statistics ===")
    table.insert(lines, "Unique Items: " .. stats.uniqueItems)
    table.insert(lines, "Total Locations: " .. stats.totalLocations)
    table.insert(lines, "Index Age: " .. stats.age .. " seconds")
    table.insert(lines, "Status: " .. (stats.isStale and "STALE" or "FRESH"))
    
    if stats.lastRebuild > 0 then
        table.insert(lines, "Last Rebuild: " .. date("%Y-%m-%d %H:%M:%S", stats.lastRebuild))
    end
    
    -- Show top 10 most common items
    local itemCounts = {}
    for itemID, locations in pairs(searchIndex) do
        table.insert(itemCounts, {itemID = itemID, count = #locations})
    end
    
    table.sort(itemCounts, function(a, b) return a.count > b.count end)
    
    table.insert(lines, "\nTop 10 Most Common Items:")
    for i = 1, math.min(10, #itemCounts) do
        local item = itemCounts[i]
        local itemName = C_Item.GetItemNameByID(item.itemID) or ("Item #" .. item.itemID)
        table.insert(lines, string.format("  %d. %s (%d locations)", i, itemName, item.count))
    end
    
    return table.concat(lines, "\n")
end

