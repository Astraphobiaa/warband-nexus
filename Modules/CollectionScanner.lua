--[[
    Warband Nexus - Unified Collection Scanner Module
    
    Provides consistent coroutine-based background scanning for ALL collection types:
    - Mounts, Pets, Toys, Achievements, Illusions, Titles
    
    Design Philosophy: ONE pattern for ALL collections
    - Same coroutine architecture
    - Same cache structure
    - Same invalidation rules
    - Same UI feedback
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local FRAME_BUDGET_MS = 5   -- 5ms per frame (~1/3 of 60 FPS budget, leaves room for game)
local BATCH_SIZE = 10       -- Yield every 10 items
local CACHE_VERSION = "1.4.0"  -- Restored: Comprehensive toy source extraction with 3 fallbacks

-- ============================================================================
-- COLLECTION CONFIGURATIONS
-- ============================================================================
-- ONE configuration pattern for ALL collection types

local COLLECTION_CONFIGS = {
    mount = {
        name = "Mounts",
        iterator = function()
            if not C_MountJournal then return {} end
            return C_MountJournal.GetMountIDs() or {}
        end,
        extract = function(mountID)
            local name, spellID, icon, _, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not name then return nil end
            
            local _, description, source = C_MountJournal.GetMountInfoExtraByID(mountID)
            
            return {
                id = mountID,
                name = name,
                icon = icon,
                spellID = spellID,
                source = source or "Unknown",
                sourceType = sourceType,
                description = description,
                collected = isCollected,
                faction = faction,
                isFactionSpecific = isFactionSpecific,
                shouldHideOnChar = shouldHideOnChar,  -- Needed for filter
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            -- Filter: Faction-specific mounts for wrong faction
            if data.shouldHideOnChar then return false end
            
            -- Filter: Use centralized unobtainable filter
            if WarbandNexus.UnobtainableFilters and WarbandNexus.UnobtainableFilters:IsUnobtainableMount(data) then
                return false
            end
            
            return true
        end
    },
    
    pet = {
        name = "Pets",
        iterator = function()
            if not C_PetJournal then return {} end
            
            -- Save and clear filters
            local numPets = C_PetJournal.GetNumPets()
            local pets = {}
            for i = 1, numPets do
                table.insert(pets, i)
            end
            return pets
        end,
        extract = function(index)
            local petID, speciesID, owned, customName, level, favorite, isRevoked, speciesName, icon, petType, companionID, tooltip, description, isWild, canBattle, isTradeable, isUnique, obtainable = C_PetJournal.GetPetInfoByIndex(index)
            
            if not speciesName then return nil end
            
            -- Get source
            local sourceText = nil
            if C_PetJournal.GetPetInfoBySpeciesID then
                local _, _, _, _, source = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                sourceText = source
            end
            
            -- Use user-friendly default if API doesn't provide source
            if not sourceText or sourceText == "" then
                sourceText = "Pet Collection"
            end
            
            return {
                id = speciesID,
                name = speciesName,
                icon = icon,
                source = sourceText,
                description = description,
                collected = owned,
                petType = petType,
                canBattle = canBattle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            -- Filter: Use centralized unobtainable filter
            if WarbandNexus.UnobtainableFilters and WarbandNexus.UnobtainableFilters:IsUnobtainablePet(data) then
                return false
            end
            
            return true
        end
    },
    
    toy = {
        name = "Toys",
        iterator = function()
            if not C_ToyBox then return {} end
            
            local numToys = C_ToyBox.GetNumToys() or 0
            local toys = {}
            for i = 1, numToys do
                table.insert(toys, i)
            end
            return toys
        end,
        extract = function(index)
            local itemID = C_ToyBox.GetToyFromIndex(index)
            if not itemID then return nil end
            
            local _, name, icon = C_ToyBox.GetToyInfo(itemID)
            if not name then return nil end
            
            local isFavorite = C_ToyBox.GetIsFavorite(itemID)
            local hasToy = PlayerHasToy(itemID)
            
            -- Get toy source using comprehensive fallback approach (restored from old system)
            local sourceText = nil
            
            -- Source keywords to detect (comprehensive list)
            local sourceKeywords = {
                "Vendor:", "Sold by:", "Drop:", "Quest:", "Achievement:", "Profession:",
                "Crafted:", "World Event:", "Holiday:", "PvP:", "Arena:", "Battleground:",
                "Dungeon:", "Raid:", "Trading Post:", "Treasure:", "Reputation:", "Faction:",
                "Garrison:", "Garrison Building:", "Pet Battle:", "Zone:", "Store:",
                "Order Hall:", "Covenant:", "Renown:", "Friendship:", "Paragon:",
                "Mission:", "Expansion:", "Scenario:", "Class Hall:", "Campaign:",
                "Event:", "Promotion:", "Special:", "Brawler's Guild:", "Challenge Mode:",
                "Mythic+:", "Timewalking:", "Island Expedition:", "Warfront:", "Torghast:",
                "Discovery:", "Contained in:", "Rare:", "World Boss:"
            }
            
            local function hasSourceKeyword(text)
                if not text then return false end
                for _, keyword in ipairs(sourceKeywords) do
                    if text:find(keyword, 1, true) then
                        return true
                    end
                end
                return false
            end
            
            -- FALLBACK 1: C_TooltipInfo.GetToyByItemID (structured tooltip data)
            if C_TooltipInfo and C_TooltipInfo.GetToyByItemID then
                local tooltipData = C_TooltipInfo.GetToyByItemID(itemID)
                if tooltipData and tooltipData.lines then
                    for _, line in ipairs(tooltipData.lines) do
                        if line.leftText then
                            local text = line.leftText
                            if hasSourceKeyword(text) and not text:match("^Use:") and not text:match("^Cost:") and text ~= name then
                                if not sourceText then
                                    sourceText = text
                                elseif not sourceText:find(text, 1, true) then
                                    sourceText = sourceText .. "\n" .. text
                                end
                            end
                        end
                    end
                end
            end
            
            -- FALLBACK 2: C_TooltipInfo.GetItemByID (item tooltip instead of toy tooltip)
            if not sourceText or sourceText == "" then
                if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                    local itemTooltipData = C_TooltipInfo.GetItemByID(itemID)
                    if itemTooltipData and itemTooltipData.lines then
                        for _, line in ipairs(itemTooltipData.lines) do
                            if line.leftText then
                                local text = line.leftText
                                if hasSourceKeyword(text) and not text:match("^Use:") and not text:match("^Cost:") and text ~= name then
                                    if not sourceText then
                                        sourceText = text
                                    elseif not sourceText:find(text, 1, true) then
                                        sourceText = sourceText .. "\n" .. text
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            -- Use user-friendly default if no source found
            if not sourceText or sourceText == "" then
                sourceText = "Toy Collection"
            end
            
            return {
                id = itemID,
                name = name,
                icon = icon,
                source = sourceText,
                collected = hasToy,
                isFavorite = isFavorite,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            -- Filter: Use centralized unobtainable filter
            if WarbandNexus.UnobtainableFilters and WarbandNexus.UnobtainableFilters:IsUnobtainableToy(data) then
                return false
            end
            
            return true
        end
    },
    
    achievement = {
        name = "Achievements",
        iterator = function()
            -- Return achievement categories
            return GetCategoryList() or {}
        end,
        extract = function(categoryID)
            -- This is special: returns multiple achievements per category
            local achievements = {}
            local total, completed, incompleted = GetCategoryNumAchievements(categoryID)
            
            if total and total > 0 then
                for i = 1, total do
                    local achievementID, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy = GetAchievementInfo(categoryID, i)
                    
                    if achievementID and name then
                        -- Get criteria info
                        local numCriteria = GetAchievementNumCriteria(achievementID)
                        local source = description or ""
                        
                        if numCriteria and numCriteria > 0 then
                            local completedCriteria = 0
                            for criteriaIndex = 1, numCriteria do
                                local _, _, criteriaCompleted = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                                if criteriaCompleted then
                                    completedCriteria = completedCriteria + 1
                                end
                            end
                            source = string.format("Progress: %d/%d criteria", completedCriteria, numCriteria)
                            if description and description ~= "" then
                                source = description .. "\n" .. source
                            end
                        end
                        
                        table.insert(achievements, {
                            id = achievementID,
                            name = name,
                            icon = icon,
                            points = points or 0,
                            description = description or "",
                            source = source,
                            rewardText = rewardText,
                            categoryID = categoryID,
                            collected = completed,
                            isGuild = isGuild,
                            numCriteria = numCriteria,
                            flags = flags,
                        })
                    end
                end
            end
            
            return achievements
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            if data.isGuild then return false end
            -- All uncompleted achievements will be collected (including Feats of Strength)
            return true
        end
    },
    
    illusion = {
        name = "Illusions",
        iterator = function()
            if not C_TransmogCollection then return {} end
            return C_TransmogCollection.GetIllusions() or {}
        end,
        extract = function(illusionInfo)
            if not illusionInfo then return nil end
            
            local visualID = illusionInfo.visualID
            local icon = illusionInfo.icon
            local sourceID = illusionInfo.sourceID
            local isCollected = illusionInfo.isCollected
            
            -- Get detailed info
            local name, hyperlink, sourceText = C_TransmogCollection.GetIllusionStrings(sourceID)
            
            return {
                id = sourceID,
                visualID = visualID,
                name = name or "Unknown",
                icon = icon,
                source = sourceText or "Illusion",
                collected = isCollected,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            -- Filter: Use centralized unobtainable filter
            if WarbandNexus.UnobtainableFilters and WarbandNexus.UnobtainableFilters:IsUnobtainableIllusion(data) then
                return false
            end
            
            return true
        end
    },
    
    title = {
        name = "Titles",
        iterator = function()
            local numTitles = GetNumTitles() or 0
            local titles = {}
            for i = 1, numTitles do
                table.insert(titles, i)
            end
            return titles
        end,
        extract = function(titleID)
            local name = GetTitleName(titleID)
            if not name then return nil end
            
            local isKnown = IsTitleKnown(titleID)
            
            -- Clean up title name (remove %s placeholder)
            local displayName = name:gsub("%%s", ""):trim()
            
            return {
                id = titleID,
                name = displayName,
                icon = "Interface\\Icons\\INV_Misc_Book_11",  -- Scroll/Book icon for titles
                source = "Character Title",
                collected = isKnown,
            }
        end,
        shouldInclude = function(data)
            -- Titles generally don't have unobtainable issues, just check collected
            return data and not data.collected
        end
    },
}

-- ============================================================================
-- MODULE STATE
-- ============================================================================

-- Create scanner directly on WarbandNexus (NO local reference)
if not WarbandNexus.CollectionScanner then
    WarbandNexus.CollectionScanner = {
        cache = {},           -- In-memory cache
        isReady = false,      -- Scanner ready flag
        isScanning = false,   -- Currently scanning flag
        progress = {},        -- Progress per collection type
        coroutines = {},      -- Active coroutines
    }
end

-- Define all methods on WarbandNexus.CollectionScanner directly
local CS = WarbandNexus.CollectionScanner  -- Short alias for readability

-- ============================================================================
-- CORE SCANNING FUNCTIONS
-- ============================================================================

--[[
    Generic collection scanner (ONE function for ALL types)
    @param collectionType string - Type to scan
    @param callback function - Called when complete
]]
function CS:ScanCollection(collectionType, callback)
    local config = COLLECTION_CONFIGS[collectionType]
    if not config then
        WarbandNexus:Print("|cffff0000Error:|r Unknown collection type: " .. tostring(collectionType))
        if callback then callback({}) end
        return
    end
    
    -- Create coroutine for this collection
    local co = coroutine.create(function()
        local results = {}
        local processed = 0
        local startTime = debugprofilestop()
        
        -- Deduplication map for achievements (prevents same achievement appearing in multiple categories)
        local seenIDs = {}
        
        WarbandNexus:Debug(string.format("Scanning %s...", config.name))
        
        -- Get items to iterate
        local items = config.iterator()
        local totalItems = #items
        
        for index, item in ipairs(items) do
            -- Extract data (may return single item or array for achievements)
            local extracted = config.extract(item)
            
            if extracted then
                -- Handle single item or array
                if type(extracted) == "table" and #extracted > 0 and extracted[1].id then
                    -- Array of items (achievements) - DEDUPLICATE HERE
                    for _, itemData in ipairs(extracted) do
                        if not seenIDs[itemData.id] then  -- Only add if not seen before
                            seenIDs[itemData.id] = true
                            if config.shouldInclude(itemData) then
                                table.insert(results, itemData)
                            end
                        end
                    end
                else
                    -- Single item
                    if config.shouldInclude(extracted) then
                        table.insert(results, extracted)
                    end
                end
            end
            
            processed = processed + 1
            
            -- Update progress
            CS.progress[collectionType] = {
                current = processed,
                total = totalItems,
                percent = math.floor((processed / totalItems) * 100)
            }
            
            -- Frame budget: yield every BATCH_SIZE or if time exceeded
            if processed % BATCH_SIZE == 0 then
                local elapsed = debugprofilestop() - startTime
                if elapsed > FRAME_BUDGET_MS then
                    coroutine.yield()
                    startTime = debugprofilestop()
                end
            end
        end
        
        local totalElapsed = debugprofilestop() - startTime
        WarbandNexus:Debug(string.format("%s scan complete: %d items in %.2fms", config.name, #results, totalElapsed))
        
        -- Yield results instead of return (so status becomes "dead" after this yield, not before)
        coroutine.yield(results)
    end)
    
    -- Store coroutine
    CS.coroutines[collectionType] = co
    
    -- Resume coroutine with ticker
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local status = coroutine.status(co)
        
        if status == "dead" then
            ticker:Cancel()
            
            -- Coroutine is dead, don't resume again - just cleanup
            CS.coroutines[collectionType] = nil
        elseif status == "suspended" then
            local success, results = coroutine.resume(co)
            
            if not success then
                WarbandNexus:Print("|cffff0000Error:|r Failed to scan " .. collectionType)
                if callback then callback({}) end
                ticker:Cancel()
                CS.coroutines[collectionType] = nil
            elseif results and type(results) == "table" then
                -- Results received (last yield before dead)
                CS.cache[collectionType] = {
                    timestamp = time(),
                    data = results
                }
                
                if callback then callback(results) end
            end
        end
    end)
end

--[[
    Scan all collection types
    @param onComplete function - Called when all scans complete
]]
function CS:ScanAllCollections(onComplete)
    CS.isScanning = true
    CS.isReady = false
    
    local types = {"mount", "pet", "toy", "achievement", "illusion", "title"}
    local completed = 0
    
    local function onTypeComplete()
        completed = completed + 1
        
        if completed >= #types then
            CS.isScanning = false
            CS.isReady = true
            
            -- Save to disk
            CS:SaveCache()
            
            WarbandNexus:Print("|cff00ff00Collection scan complete!|r All collections cached.")
            
            if onComplete then onComplete() end
        end
    end
    
    -- Scan each type
    for _, collectionType in ipairs(types) do
        CS:ScanCollection(collectionType, onTypeComplete)
    end
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

--[[
    Save cache to SavedVariables
]]
function CS:SaveCache()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    
    local cacheData = {
        version = CACHE_VERSION,
        gameVersion = (select(4, GetBuildInfo())),
        timestamp = time(),
        collections = self.cache
    }
    
    -- Compress and save
    local compressed = WarbandNexus:CompressCollectionData(cacheData)
    if compressed then
        WarbandNexus.db.global.collectionCache = compressed
    end
end

--[[
    Load cache from SavedVariables
    @return boolean - Success
]]
function CS:LoadCache()
    if not WarbandNexus.db or not WarbandNexus.db.global then
        return false
    end
    
    local compressed = WarbandNexus.db.global.collectionCache
    
    if not compressed then
        return false
    end
    
    -- Decompress and load
    local cacheData = WarbandNexus:DecompressCollectionData(compressed)
    
    if not cacheData then return false end
    
    -- Version check
    if cacheData.version ~= CACHE_VERSION then
        WarbandNexus:Debug(string.format(
            "CollectionScanner:LoadCache() - Cache version mismatch (Cache: %s, Required: %s) - Invalidating",
            tostring(cacheData.version), tostring(CACHE_VERSION)
        ))
        return false
    end
    
    -- Game version check
    local currentVersion = select(4, GetBuildInfo())
    if cacheData.gameVersion ~= currentVersion then
        WarbandNexus:Debug(string.format(
            "CollectionScanner:LoadCache() - Game version changed (Cache: %s, Current: %s) - Invalidating",
            tostring(cacheData.gameVersion), tostring(currentVersion)
        ))
        return false
    end
    
    -- Load cache
    self.cache = cacheData.collections or {}
    self.isReady = true
    
    -- MIGRATION CHECK: If cache is empty, force fresh scan
    local mountCount = (self.cache.mount and self.cache.mount.data and #self.cache.mount.data) or 0
    local petCount = (self.cache.pet and self.cache.pet.data and #self.cache.pet.data) or 0
    
    if mountCount == 0 and petCount == 0 then
        WarbandNexus:Debug("CollectionScanner:LoadCache() - Cache is empty, forcing fresh scan")
        self.cache = {}
        self.isReady = false
        return false  -- Trigger fresh scan
    end
    
    WarbandNexus:Debug(string.format(
        "CollectionScanner:LoadCache() - Successfully loaded cache (Version: %s, Collections: M:%d P:%d)",
        CACHE_VERSION, mountCount, petCount
    ))
    
    return true
end

--[[
    Invalidate cache for specific type
    @param collectionType string - Type to invalidate
]]
function CS:InvalidateCache(collectionType)
    if self.cache[collectionType] then
        self.cache[collectionType] = nil
        WarbandNexus:Debug("Invalidated cache: " .. collectionType)
        
        -- Re-scan this type
        self:ScanCollection(collectionType, function()
            self:SaveCache()
        end)
    end
end

--[[
    Clear all cache
]]
function CS:ClearCache()
    self.cache = {}
    self.isReady = false
    if WarbandNexus.db and WarbandNexus.db.global then
        WarbandNexus.db.global.collectionCache = nil
    end
    WarbandNexus:Debug("All cache cleared")
end

-- ============================================================================
-- QUERY FUNCTIONS
-- ============================================================================

--[[
    Get collection data (with search filtering)
    @param collectionType string - Type to query
    @param searchText string - Search filter (optional)
    @param limit number - Max results (optional)
    @return table - Filtered results
]]
function CS:GetCollectionData(collectionType, searchText, limit)
    local cached = self.cache[collectionType]
    
    if not cached or not cached.data then
        return {}  -- No data yet
    end
    
    local results = {}
    limit = limit or 50
    
    -- Filter by search text
    local searchLower = searchText and searchText:lower() or nil
    
    for _, item in ipairs(cached.data) do
        if #results >= limit then break end
        
        -- Apply search filter
        if not searchLower or (item.name and item.name:lower():find(searchLower, 1, true)) then
            
            -- Add isPlanned flag using correct function for each type
            local plannedSuccess = false
            if collectionType == "mount" then
                local ok, result = pcall(function() return WarbandNexus:IsMountPlanned(item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            elseif collectionType == "pet" then
                local ok, result = pcall(function() return WarbandNexus:IsPetPlanned(item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            elseif collectionType == "toy" then
                local ok, result = pcall(function() return WarbandNexus:IsItemPlanned(PLAN_TYPES.TOY, item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            elseif collectionType == "achievement" then
                local ok, result = pcall(function() return WarbandNexus:IsAchievementPlanned(item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            elseif collectionType == "illusion" then
                local ok, result = pcall(function() return WarbandNexus:IsIllusionPlanned(item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            elseif collectionType == "title" then
                local ok, result = pcall(function() return WarbandNexus:IsTitlePlanned(item.id) end)
                item.isPlanned = ok and result or false
                plannedSuccess = ok
            else
                item.isPlanned = false
                plannedSuccess = true
            end
            
            table.insert(results, item)
        end
    end
    
    return results
end

--[[
    Check if scanner is ready
    @return boolean
]]
function CS:IsReady()
    return self.isReady
end

--[[
    Check if currently scanning
    @return boolean
]]
function CS:IsScanning()
    return self.isScanning
end

--[[
    Get scan progress
    @return table - Progress info {overall, types}
]]
function CS:GetProgress()
    local total = 0
    local completed = 0
    
    for _, progress in pairs(self.progress) do
        total = total + progress.total
        completed = completed + progress.current
    end
    
    local percent = total > 0 and math.floor((completed / total) * 100) or 0
    
    return {
        percent = percent,
        types = self.progress
    }
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize scanner on addon load
]]
function CS:Initialize()
    -- ONE-TIME: Clear old cache to force fresh scan with new unified system
    -- Check if we have old cache format (non-unified)
    if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.collectionCache then
        local compressed = WarbandNexus.db.global.collectionCache
        local cacheData = WarbandNexus:DecompressCollectionData(compressed)
        
        -- If cache exists but collections are empty, clear it
        if cacheData and cacheData.collections then
            local mountCount = (cacheData.collections.mount and cacheData.collections.mount.data and #cacheData.collections.mount.data) or 0
            if mountCount == 0 then
                WarbandNexus.db.global.collectionCache = nil
            end
        end
    end
    
    -- Try to load cache
    local loaded = CS:LoadCache()
    
    -- Check if Plans module is enabled
    local plansEnabled = WarbandNexus.db and WarbandNexus.db.profile and 
                        WarbandNexus.db.profile.modulesEnabled and 
                        WarbandNexus.db.profile.modulesEnabled.plans ~= false
    
    if not loaded and plansEnabled then
        -- No valid cache and plans enabled, start background scan
        WarbandNexus:Debug("No valid cache found, starting background scan...")
        C_Timer.After(2, function()  -- Delay 2s after login
            CS:ScanAllCollections(function()
                -- Callback when scan completes - refresh UI if Plans tab is open
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
        end)
    end
end

--[[
    Enable CollectionScanner - Start scanning if no cache exists
]]
function CS:Enable()
    WarbandNexus:Debug("CollectionScanner:Enable() - Plans module enabled")
    
    -- Check if we have valid cache
    if CS:IsReady() then
        -- Count cached items for debug
        local mountCount = (CS.cache.mount and CS.cache.mount.data and #CS.cache.mount.data) or 0
        local petCount = (CS.cache.pet and CS.cache.pet.data and #CS.cache.pet.data) or 0
        local toyCount = (CS.cache.toy and CS.cache.toy.data and #CS.cache.toy.data) or 0
        local achievementCount = (CS.cache.achievement and CS.cache.achievement.data and #CS.cache.achievement.data) or 0
        
        WarbandNexus:Debug(string.format(
            "CollectionScanner:Enable() - Valid cache found (M:%d P:%d T:%d A:%d), using cached data",
            mountCount, petCount, toyCount, achievementCount
        ))
        
        if WarbandNexus.RefreshUI then
            WarbandNexus:RefreshUI()
        end
        return
    end
    
    -- No cache, start scanning
    WarbandNexus:Debug("CollectionScanner:Enable() - No cache found, starting background scan...")
    C_Timer.After(0.5, function()
        CS:ScanAllCollections(function()
            WarbandNexus:Debug("CollectionScanner:Enable() - Background scan completed")
            if WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end)
    end)
end

--[[
    Disable CollectionScanner - Stop any ongoing scans
]]
function CS:Disable()
    WarbandNexus:Debug("CollectionScanner:Disable() - Stopping collection scan")
    
    -- Stop all coroutines
    for collectionType, _ in pairs(COLLECTION_CONFIGS) do
        if CS.coroutines and CS.coroutines[collectionType] then
            CS.coroutines[collectionType] = nil
        end
    end
    
    -- Reset scanning state
    CS.isScanning = false
    
    -- Clear progress for all collection types
    CS.progress = {}
    
    -- Refresh UI to show disabled state
    if WarbandNexus.RefreshUI then
        WarbandNexus:RefreshUI()
    end
end

-- Export to namespace (already done at module start, CS is WarbandNexus.CollectionScanner)
ns.CollectionScanner = WarbandNexus.CollectionScanner

