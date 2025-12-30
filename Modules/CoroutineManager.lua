--[[
    Warband Nexus - Coroutine Manager Module
    Manages long-running operations using coroutines to prevent UI freezing
    Spreads heavy computations across multiple frames
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Active coroutines
local activeCoroutines = {}
local coroutineFrame = nil
local ITEMS_PER_FRAME = 50 -- Process 50 items per frame

--[[
    Initialize coroutine manager
]]
function WarbandNexus:InitializeCoroutineManager()
    -- Create frame for OnUpdate
    if not coroutineFrame then
        coroutineFrame = CreateFrame("Frame")
        coroutineFrame:SetScript("OnUpdate", function()
            self:ProcessCoroutines()
        end)
    end
    
    self:Debug("Coroutine manager initialized")
end

--[[
    Process all active coroutines
]]
function WarbandNexus:ProcessCoroutines()
    for i = #activeCoroutines, 1, -1 do
        local coData = activeCoroutines[i]
        
        if coData and coData.co then
            local success, result = coroutine.resume(coData.co)
            
            if not success then
                -- Coroutine error
                self:Print("|cffff0000Coroutine error:|r " .. tostring(result))
                table.remove(activeCoroutines, i)
                
                if coData.onError then
                    coData.onError(result)
                end
                
            elseif coroutine.status(coData.co) == "dead" then
                -- Coroutine finished
                table.remove(activeCoroutines, i)
                
                if coData.onComplete then
                    coData.onComplete(result)
                end
            end
        else
            -- Invalid coroutine data
            table.remove(activeCoroutines, i)
        end
    end
end

--[[
    Run a function as a coroutine
    @param func function - Function to run
    @param onComplete function - Callback when complete
    @param onError function - Callback on error
    @return number - Coroutine ID
]]
function WarbandNexus:RunCoroutine(func, onComplete, onError)
    local co = coroutine.create(func)
    
    local coData = {
        co = co,
        onComplete = onComplete,
        onError = onError,
        startTime = debugprofilestop()
    }
    
    table.insert(activeCoroutines, coData)
    
    return #activeCoroutines
end

--[[
    Cancel a running coroutine
    @param coID number - Coroutine ID
]]
function WarbandNexus:CancelCoroutine(coID)
    if coID and activeCoroutines[coID] then
        table.remove(activeCoroutines, coID)
    end
end

--[[
    Cancel all running coroutines
]]
function WarbandNexus:CancelAllCoroutines()
    table.wipe(activeCoroutines)
end

--[[
    Get number of active coroutines
    @return number - Count
]]
function WarbandNexus:GetActiveCoroutineCount()
    return #activeCoroutines
end

-- ============================================================================
-- PRE-BUILT COROUTINE OPERATIONS
-- ============================================================================

--[[
    Database unpacking as coroutine (spread over multiple frames)
    @param onComplete function - Callback when complete
]]
function WarbandNexus:UnpackDatabaseAsync(onComplete)
    self:RunCoroutine(function()
        local startTime = debugprofilestop()
        
        -- Check if data is compressed
        if not self.db.global.compressedData then
            if onComplete then
                onComplete(true, "Database already uncompressed")
            end
            return
        end
        
        -- Decode
        local compressed = LibDeflate:DecodeForPrint(self.db.global.compressedData)
        coroutine.yield()
        
        -- Decompress
        local serialized = LibDeflate:DecompressDeflate(compressed)
        coroutine.yield()
        
        -- Deserialize
        local deserializeSuccess, characters = LibSerialize:Deserialize(serialized)
        coroutine.yield()
        
        if deserializeSuccess then
            self.db.global.characters = characters
            local elapsed = debugprofilestop() - startTime
            return string.format("Decompressed in %.0f ms", elapsed)
        else
            error("Deserialization failed")
        end
    end, onComplete, function(err)
        self:Print("|cffff0000Database unpacking failed:|r " .. tostring(err))
    end)
end

--[[
    Search index rebuild as coroutine
    @param onComplete function - Callback when complete
]]
function WarbandNexus:RebuildSearchIndexAsync(onComplete)
    self:RunCoroutine(function()
        local startTime = debugprofilestop()
        local itemCount = 0
        local processedItems = 0
        
        -- Clear existing index
        self:ClearSearchIndex()
        coroutine.yield()
        
        -- Index Warband Bank
        if self.db.global.warbandBank and self.db.global.warbandBank.items then
            for tabIndex, tab in pairs(self.db.global.warbandBank.items) do
                for slotID, item in pairs(tab) do
                    if item and item.id then
                        self:IndexAddItem(item.id, "@warband", "warbandBank", slotID, item.count)
                        itemCount = itemCount + 1
                        processedItems = processedItems + 1
                        
                        -- Yield every ITEMS_PER_FRAME items
                        if processedItems >= ITEMS_PER_FRAME then
                            processedItems = 0
                            coroutine.yield()
                        end
                    end
                end
            end
        end
        
        -- Index character items
        if self.db.global.characters then
            for charKey, charData in pairs(self.db.global.characters) do
                -- Bags
                if charData.bags then
                    for bagIndex, bag in pairs(charData.bags) do
                        if bag.items then
                            for slot, item in pairs(bag.items) do
                                if item and item.id then
                                    self:IndexAddItem(item.id, charKey, "bags", slot, item.count)
                                    itemCount = itemCount + 1
                                    processedItems = processedItems + 1
                                    
                                    if processedItems >= ITEMS_PER_FRAME then
                                        processedItems = 0
                                        coroutine.yield()
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Bank
                if charData.bank then
                    for slot, item in pairs(charData.bank) do
                        if item and item.id then
                            self:IndexAddItem(item.id, charKey, "bank", slot, item.count)
                            itemCount = itemCount + 1
                            processedItems = processedItems + 1
                            
                            if processedItems >= ITEMS_PER_FRAME then
                                processedItems = 0
                                coroutine.yield()
                            end
                        end
                    end
                end
            end
        end
        
        local elapsed = debugprofilestop() - startTime
        return string.format("Indexed %d items in %.0f ms", itemCount, elapsed)
    end, onComplete, function(err)
        self:Print("|cffff0000Index rebuild failed:|r " .. tostring(err))
    end)
end

--[[
    Archive inactive characters as coroutine
    @param onComplete function - Callback when complete
]]
function WarbandNexus:ArchiveInactiveCharactersAsync(onComplete)
    self:RunCoroutine(function()
        local archived = 0
        local processed = 0
        local currentTime = time()
        
        if not self.db.global.characters then
            return "No characters to archive"
        end
        
        for charKey, charData in pairs(self.db.global.characters) do
            local lastLogin = charData.lastLogin or 0
            local daysSinceLogin = (currentTime - lastLogin) / 86400
            
            if daysSinceLogin >= 7 then -- 7 days threshold
                if self:ArchiveCharacter(charKey) then
                    archived = archived + 1
                end
            end
            
            processed = processed + 1
            
            -- Yield every 10 characters
            if processed % 10 == 0 then
                coroutine.yield()
            end
        end
        
        return string.format("Archived %d inactive characters", archived)
    end, onComplete, function(err)
        self:Print("|cffff0000Archival failed:|r " .. tostring(err))
    end)
end

--[[
    Full database compression as coroutine
    @param onComplete function - Callback when complete
]]
function WarbandNexus:CompressDatabaseAsync(onComplete)
    self:RunCoroutine(function()
        local startTime = debugprofilestop()
        
        if not self.db.global.characters or not next(self.db.global.characters) then
            return "No data to compress"
        end
        
        -- Serialize
        local serialized = LibSerialize:Serialize(self.db.global.characters)
        coroutine.yield()
        
        -- Compress
        local compressed = LibDeflate:CompressDeflate(serialized, {level = 5})
        coroutine.yield()
        
        -- Encode
        local encoded = LibDeflate:EncodeForPrint(compressed)
        coroutine.yield()
        
        -- Store
        self.db.global.compressedData = encoded
        self.db.global.compressionStats = {
            originalSize = #serialized,
            compressedSize = #encoded,
            ratio = (1 - #encoded / #serialized) * 100,
            timestamp = time(),
            version = 1
        }
        
        -- Clear uncompressed data
        self.db.global.characters = nil
        
        local elapsed = debugprofilestop() - startTime
        local stats = self.db.global.compressionStats
        
        return string.format("Compressed %.2f KB → %.2f KB (%.1f%%) in %.0f ms",
            stats.originalSize / 1024, stats.compressedSize / 1024, stats.ratio, elapsed)
    end, onComplete, function(err)
        self:Print("|cffff0000Compression failed:|r " .. tostring(err))
    end)
end

--[[
    Universal search as coroutine (fallback if index unavailable)
    @param searchTerm string - Search term
    @param onComplete function - Callback with results
]]
function WarbandNexus:SearchItemsAsync(searchTerm, onComplete)
    self:RunCoroutine(function()
        local results = {}
        local processed = 0
        
        searchTerm = searchTerm:lower()
        
        -- Search Warband Bank
        if self.db.global.warbandBank and self.db.global.warbandBank.items then
            for tabIndex, tab in pairs(self.db.global.warbandBank.items) do
                for slotID, item in pairs(tab) do
                    if item and item.id then
                        local itemName = C_Item.GetItemNameByID(item.id)
                        if itemName and itemName:lower():find(searchTerm, 1, true) then
                            table.insert(results, {
                                itemID = item.id,
                                itemName = itemName,
                                location = {
                                    charKey = "@warband",
                                    location = "warbandBank",
                                    tab = tabIndex,
                                    slot = slotID,
                                    count = item.count or 1
                                }
                            })
                        end
                        
                        processed = processed + 1
                        if processed % ITEMS_PER_FRAME == 0 then
                            coroutine.yield()
                        end
                    end
                end
            end
        end
        
        -- Search character items
        if self.db.global.characters then
            for charKey, charData in pairs(self.db.global.characters) do
                -- Bags
                if charData.bags then
                    for bagIndex, bag in pairs(charData.bags) do
                        if bag.items then
                            for slot, item in pairs(bag.items) do
                                if item and item.id then
                                    local itemName = C_Item.GetItemNameByID(item.id)
                                    if itemName and itemName:lower():find(searchTerm, 1, true) then
                                        table.insert(results, {
                                            itemID = item.id,
                                            itemName = itemName,
                                            location = {
                                                charKey = charKey,
                                                location = "bags",
                                                bag = bagIndex,
                                                slot = slot,
                                                count = item.count or 1
                                            }
                                        })
                                    end
                                    
                                    processed = processed + 1
                                    if processed % ITEMS_PER_FRAME == 0 then
                                        coroutine.yield()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        return results
    end, onComplete, function(err)
        self:Print("|cffff0000Search failed:|r " .. tostring(err))
    end)
end

--[[
    Get coroutine manager statistics
    @return table - Statistics
]]
function WarbandNexus:GetCoroutineStats()
    return {
        activeCoroutines = #activeCoroutines,
        isProcessing = #activeCoroutines > 0
    }
end

