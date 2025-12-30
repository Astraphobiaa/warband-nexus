--[[
    Warband Nexus - Deep Optimizer
    Normalizes ALL existing data for maximum performance
    This runs a deep scan through all database structures
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--[[
    Deep normalize all existing data
    @return itemsNormalized, charactersProcessed
]]
function WarbandNexus:DeepNormalizeAllData()
    local startTime = debugprofilestop()
    
    local stats = {
        itemsNormalized = 0,
        charactersProcessed = 0,
        banksProcessed = 0,
        warbandBankNormalized = false
    }
    
    self:Print("|cff00ff00Starting deep normalization...|r")
    
    -- 1. Normalize Warband Bank
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        self:Print("Normalizing Warband Bank...")
        for tabIndex, tab in pairs(self.db.global.warbandBank.items) do
            for slotID, item in pairs(tab) do
                if item and not self:IsItemNormalized(item) then
                    -- Normalize this item
                    local normalized = self:NormalizeItemData({
                        itemID = item.itemID or item.id,
                        itemLink = item.itemLink or item.link,
                        stackCount = item.stackCount or item.count or 1
                    })
                    
                    if normalized then
                        self.db.global.warbandBank.items[tabIndex][slotID] = normalized
                        stats.itemsNormalized = stats.itemsNormalized + 1
                    end
                end
            end
        end
        stats.warbandBankNormalized = true
    end
    
    -- 2. Normalize all characters' personal banks (db.char structure)
    -- Note: We can't access other characters' db.char, but we can normalize current character
    if self.db.char.personalBank and self.db.char.personalBank.items then
        self:Print("Normalizing personal bank...")
        for bagIndex, bag in pairs(self.db.char.personalBank.items) do
            for slotID, item in pairs(bag) do
                if item and not self:IsItemNormalized(item) then
                    local normalized = self:NormalizeItemData({
                        itemID = item.itemID or item.id,
                        itemLink = item.itemLink or item.link,
                        stackCount = item.stackCount or item.count or 1
                    })
                    
                    if normalized then
                        self.db.char.personalBank.items[bagIndex][slotID] = normalized
                        stats.itemsNormalized = stats.itemsNormalized + 1
                    end
                end
            end
        end
        stats.banksProcessed = stats.banksProcessed + 1
    end
    
    -- 3. Normalize all characters in global database
    if self.db.global.characters then
        self:Print("Normalizing character data...")
        for charKey, charData in pairs(self.db.global.characters) do
            stats.charactersProcessed = stats.charactersProcessed + 1
            
            -- Normalize bags
            if charData.bags then
                for bagIndex, bag in pairs(charData.bags) do
                    if type(bag) == "table" and bag.items then
                        for slotID, item in pairs(bag.items) do
                            if item and not self:IsItemNormalized(item) then
                                local normalized = self:NormalizeItemData({
                                    itemID = item.itemID or item.id,
                                    itemLink = item.itemLink or item.link,
                                    stackCount = item.stackCount or item.count or 1
                                })
                                
                                if normalized then
                                    bag.items[slotID] = normalized
                                    stats.itemsNormalized = stats.itemsNormalized + 1
                                end
                            end
                        end
                    end
                end
            end
            
            -- Normalize bank
            if charData.bank then
                for slotID, item in pairs(charData.bank) do
                    if item and not self:IsItemNormalized(item) then
                        local normalized = self:NormalizeItemData({
                            itemID = item.itemID or item.id,
                            itemLink = item.itemLink or item.link,
                            stackCount = item.stackCount or item.count or 1
                        })
                        
                        if normalized then
                            charData.bank[slotID] = normalized
                            stats.itemsNormalized = stats.itemsNormalized + 1
                        end
                    end
                end
            end
        end
    end
    
    local elapsed = debugprofilestop() - startTime
    
    -- Invalidate caches
    self:InvalidateCharacterCache()
    
    -- Rebuild search index with new data
    if self.RebuildSearchIndex then
        self:RebuildSearchIndex(true)
    end
    
    -- Print results
    self:Print("|cff00ff00Deep normalization complete!|r")
    self:Print(string.format("Items normalized: |cff00ff00%d|r", stats.itemsNormalized))
    self:Print(string.format("Characters processed: |cff00ff00%d|r", stats.charactersProcessed))
    self:Print(string.format("Banks processed: |cff00ff00%d|r", stats.banksProcessed))
    self:Print(string.format("Time: |cff00ff00%.0f ms|r", elapsed))
    
    return stats.itemsNormalized, stats.charactersProcessed
end

--[[
    Check if an item is already normalized
    @param item table - Item data
    @return boolean - True if normalized
]]
function WarbandNexus:IsItemNormalized(item)
    if not item then return false end
    
    -- Normalized items have:
    -- 1. "id" field (not "itemID")
    -- 2. "count" field (not "stackCount")
    -- 3. "link" field (not "itemLink")
    -- 4. NO extra fields (name, icon, quality, etc.)
    
    -- Check if it has the normalized structure
    local hasId = item.id ~= nil
    local hasCount = item.count ~= nil
    local hasLink = item.link ~= nil
    
    -- Check if it has old structure fields
    local hasItemID = item.itemID ~= nil
    local hasStackCount = item.stackCount ~= nil
    local hasName = item.name ~= nil
    local hasIcon = item.iconFileID ~= nil or item.icon ~= nil
    local hasQuality = item.quality ~= nil
    
    -- If it has old fields, it's not normalized
    if hasItemID or hasStackCount or hasName or hasIcon or hasQuality then
        return false
    end
    
    -- If it has normalized fields, it's normalized
    return hasId and hasCount
end

--[[
    Optimize everything - Full optimization pass
]]
function WarbandNexus:FullOptimization()
    self:Print("|cffff9900Starting FULL optimization...|r")
    self:Print("This may take a few moments...")
    
    -- Step 1: Deep normalize
    self:Print("\n|cffffcc00Step 1/4:|r Deep normalization")
    local itemsNormalized, charsProcessed = self:DeepNormalizeAllData()
    
    -- Step 2: Rebuild search index
    self:Print("\n|cffffcc00Step 2/4:|r Rebuilding search index")
    if self.RebuildSearchIndex then
        self:RebuildSearchIndex(true)
        self:Print("|cff00ff00Search index rebuilt!|r")
    end
    
    -- Step 3: Archive old characters
    self:Print("\n|cffffcc00Step 3/4:|r Archiving inactive characters")
    if self.AutoArchiveInactiveCharacters then
        local archived = self:AutoArchiveInactiveCharacters()
        if archived > 0 then
            self:Print(string.format("|cff00ff00Archived %d inactive characters|r", archived))
        else
            self:Print("|cffffcc00No inactive characters to archive|r")
        end
    end
    
    -- Step 4: Compress database
    self:Print("\n|cffffcc00Step 4/4:|r Testing compression")
    if self.db.global.characters and next(self.db.global.characters) then
        self:Print("|cffffcc00Compression will activate on logout|r")
    end
    
    -- Final report
    self:Print("\n|cff00ff00=== Full Optimization Complete! ===|r")
    
    -- Get statistics
    local compressionStats = self:GetCompressionStats()
    local searchStats = self:GetSearchIndexStats()
    
    self:Print(string.format("Characters: |cff00ff00%d active|r, |cffffcc00%d archived|r", 
        compressionStats.characterCount, compressionStats.archivedCount))
    self:Print(string.format("Search Index: |cff00ff00%d items|r", searchStats.uniqueItems))
    
    -- Get current memory usage
    UpdateAddOnMemoryUsage()
    local memoryUsage = GetAddOnMemoryUsage("WarbandNexus")
    self:Print(string.format("Memory: |cff00ff00%.2f MB|r", memoryUsage / 1024))
    
    self:Print("\n|cff00ff00Reload recommended: /reload|r")
end

--[[
    Slash command handler for optimization
]]
function WarbandNexus:SlashOptimize(args)
    if not args or args == "" then
        self:Print("Optimization commands:")
        self:Print("/wn optimize normalize - Normalize all existing data")
        self:Print("/wn optimize full - Full optimization (normalize + archive + index)")
        self:Print("/wn optimize compress - Test compression")
        self:Print("/wn optimize index - Rebuild search index")
        return
    end
    
    args = args:lower()
    
    if args == "normalize" then
        self:DeepNormalizeAllData()
        self:Print("|cff00ff00Recommendation: /reload to see effects|r")
        
    elseif args == "full" then
        self:FullOptimization()
        
    elseif args == "compress" then
        if self.ManualCompress then
            self:ManualCompress()
        else
            self:Print("|cffff6600Compression system not available|r")
        end
        
    elseif args == "index" then
        if self.RebuildSearchIndex then
            self:RebuildSearchIndex(true)
            self:Print("|cff00ff00Search index rebuilt!|r")
        else
            self:Print("|cffff6600Search indexer not available|r")
        end
        
    else
        self:Print("|cffff6600Unknown optimize command. Use: /wn optimize|r")
    end
end

