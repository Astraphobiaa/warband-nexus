--[[
    Warband Nexus - Transmog Manager Module
    Handles transmog collection tracking with async data loading and performance optimization
    
    Features:
    - C_TransmogCollection API integration
    - Coroutine-based frame budgeting (50ms/frame)
    - ItemMixin async data loading
    - Hybrid source text parsing (Drops API + TooltipInfo)
    - Warbands-compatible (account-wide collection)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS AND CONFIGURATION
-- ============================================================================

local FRAME_BUDGET_MS = 16  -- Maximum processing time per frame (16ms = ~60 FPS)
local BATCH_SIZE = 10       -- Number of items to process before checking frame budget (reduced for more frequent yields)
local MAX_RESULTS_PER_CATEGORY = 50  -- Limit results per category to prevent freezing (user can search for more)

-- Transmog Category Mappings (from Enum.TransmogCollectionType)
-- https://wowpedia.fandom.com/wiki/Enum.TransmogCollectionType
local function BuildTransmogCategories()
    local L = ns.L
    return {
        {id = 1, key = "head", name = (L and L["SLOT_HEAD"]) or INVTYPE_HEAD or "Head", slot = "HeadSlot", icon = "Interface\\Icons\\INV_Helmet_01"},
        {id = 2, key = "shoulder", name = (L and L["SLOT_SHOULDER"]) or INVTYPE_SHOULDER or "Shoulder", slot = "ShoulderSlot", icon = "Interface\\Icons\\INV_Shoulder_02"},
        {id = 3, key = "back", name = (L and L["SLOT_BACK"]) or INVTYPE_CLOAK or "Back", slot = "BackSlot", icon = "Interface\\Icons\\INV_Misc_Cape_01"},
        {id = 4, key = "chest", name = (L and L["SLOT_CHEST"]) or INVTYPE_CHEST or "Chest", slot = "ChestSlot", icon = "Interface\\Icons\\INV_Chest_Cloth_17"},
        {id = 5, key = "shirt", name = (L and L["SLOT_SHIRT"]) or INVTYPE_BODY or "Shirt", slot = "ShirtSlot", icon = "Interface\\Icons\\INV_Shirt_01"},
        {id = 6, key = "tabard", name = (L and L["SLOT_TABARD"]) or INVTYPE_TABARD or "Tabard", slot = "TabardSlot", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01"},
        {id = 7, key = "wrist", name = (L and L["SLOT_WRIST"]) or INVTYPE_WRIST or "Wrist", slot = "WristSlot", icon = "Interface\\Icons\\INV_Bracer_02"},
        {id = 8, key = "hands", name = (L and L["SLOT_HANDS"]) or INVTYPE_HAND or "Hands", slot = "HandsSlot", icon = "Interface\\Icons\\INV_Gauntlets_01"},
        {id = 9, key = "waist", name = (L and L["SLOT_WAIST"]) or INVTYPE_WAIST or "Waist", slot = "WaistSlot", icon = "Interface\\Icons\\INV_Belt_01"},
        {id = 10, key = "legs", name = (L and L["SLOT_LEGS"]) or INVTYPE_LEGS or "Legs", slot = "LegsSlot", icon = "Interface\\Icons\\INV_Pants_01"},
        {id = 11, key = "feet", name = (L and L["SLOT_FEET"]) or INVTYPE_FEET or "Feet", slot = "FeetSlot", icon = "Interface\\Icons\\INV_Boots_01"},
        {id = 12, key = "mainhand", name = (L and L["SLOT_MAINHAND"]) or INVTYPE_WEAPONMAINHAND or "Main Hand", slot = "MainHandSlot", icon = "Interface\\Icons\\INV_Sword_27"},
        {id = 13, key = "offhand", name = (L and L["SLOT_OFFHAND"]) or INVTYPE_WEAPONOFFHAND or "Off Hand", slot = "SecondaryHandSlot", icon = "Interface\\Icons\\INV_Shield_06"},
    }
end

local TRANSMOG_CATEGORIES -- Lazy-initialized (locale must be loaded first)

local function GetTransmogCategories()
    if not TRANSMOG_CATEGORIES then
        TRANSMOG_CATEGORIES = BuildTransmogCategories()
        ns.TRANSMOG_CATEGORIES = TRANSMOG_CATEGORIES
    end
    return TRANSMOG_CATEGORIES
end

ns.GetTransmogCategories = GetTransmogCategories
ns.TRANSMOG_CATEGORIES = nil -- Will be set on first access

-- ============================================================================
-- API AVAILABILITY CHECK
-- ============================================================================

local function CheckTransmogAPIs()
    if not C_TransmogCollection then
        return false, "C_TransmogCollection API not available"
    end
    
    if not C_TooltipInfo then
        return false, "C_TooltipInfo API not available"
    end
    
    if not Item then
        return false, "ItemMixin not available"
    end
    
    return true
end

-- ============================================================================
-- CATEGORY MANAGEMENT
-- ============================================================================

--[[
    Get list of all transmog categories
    @return table - Array of category definitions
]]
function WarbandNexus:GetTransmogCategories()
    return GetTransmogCategories()
end

--[[
    Get category definition by key
    @param categoryKey string - Category key (e.g., "head", "shoulder")
    @return table|nil - Category definition or nil
]]
function WarbandNexus:GetTransmogCategoryByKey(categoryKey)
    for _, category in ipairs(GetTransmogCategories()) do
        if category.key == categoryKey then
            return category
        end
    end
    return nil
end

--[[
    Get category definition by ID
    @param categoryID number - Category ID
    @return table|nil - Category definition or nil
]]
function WarbandNexus:GetTransmogCategoryByID(categoryID)
    for _, category in ipairs(GetTransmogCategories()) do
        if category.id == categoryID then
            return category
        end
    end
    return nil
end

-- ============================================================================
-- COROUTINE-BASED TRANSMOG FETCHING
-- ============================================================================

--[[
    Process transmog items with frame budgeting to prevent FPS drops
    Uses coroutine to yield every 50ms to maintain smooth gameplay
    
    @param categoryID number - Transmog category ID
    @param callback function - Called with results table when complete
    @param progressCallback function (optional) - Called with progress updates
]]
function WarbandNexus:ProcessTransmogCoroutine(categoryID, callback, progressCallback)
    -- API availability check
    local available, errorMsg = CheckTransmogAPIs()
    if not available then
        self:Print("|cffff0000Error:|r " .. errorMsg)
        callback({})
        return
    end
    
    local co = coroutine.create(function()
        local startTimeTotal = debugprofilestop()
        
        -- Get all appearances for category
        local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID)
        if not appearances or #appearances == 0 then
            self:Debug("No appearances found for category " .. categoryID)
            callback({})
            return
        end
        
        local results = {}
        local totalCount = #appearances
        local processedCount = 0
        local startTime = debugprofilestop()
        
        -- #region agent log
        local countUncollected = 0
        local countWithSources = 0
        local countValidSourceID = 0
        local countSuccessSourceInfo = 0
        local countAdded = 0
        local reachedLimit = false  -- Flag for early exit
        -- #endregion
        
        self:Debug("Processing " .. totalCount .. " transmog items for category " .. categoryID)
        
        for i, appearanceInfo in ipairs(appearances) do
            -- Early exit if we've hit the limit
            if reachedLimit then
                break
            end
            -- Skip collected items (Warband-compatible filtering)
            if not appearanceInfo.isCollected then
                -- #region agent log
                countUncollected = countUncollected + 1
                
                -- Get sources for this appearance
                local sources = C_TransmogCollection.GetAppearanceSources(appearanceInfo.visualID)
                
                if sources and #sources > 0 then
                    countWithSources = countWithSources + 1
                    
                    -- Process ALL sources for this appearance (multiple items can have same visual)
                    for _, sourceData in ipairs(sources) do
                        local sourceID = sourceData.sourceID  -- sources is array of {sourceID=X, ...}
                        
                        -- Validate sourceID is a valid number
                        if type(sourceID) == "number" and sourceID > 0 then
                            -- #region agent log
                            countValidSourceID = countValidSourceID + 1
                            -- #endregion
                            
                            -- Get source info (with protected call to catch errors)
                            local success, sourceInfo = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
                            
                            if success and sourceInfo then
                            -- #region agent log
                            countSuccessSourceInfo = countSuccessSourceInfo + 1
                            -- #endregion
                            
                            -- TWW 11.0 compatibility: canDisplayOnPlayer (backward compatible)
                            local canDisplayOnPlayer = appearanceInfo.canDisplayOnPlayer
                            if canDisplayOnPlayer == nil then
                                -- Fallback to isUsable for pre-11.0
                                canDisplayOnPlayer = appearanceInfo.isUsable
                            end
                            
                            -- TWW 11.0: playerCanCollect field
                            local playerCanCollect = appearanceInfo.playerCanCollect
                            if playerCanCollect == nil then
                                -- Assume true if field doesn't exist (backward compatibility)
                                playerCanCollect = true
                            end
                            
                            table.insert(results, {
                                visualID = appearanceInfo.visualID,
                                sourceID = sourceID,
                                itemID = sourceInfo.itemID,
                                isUsable = appearanceInfo.isUsable,  -- Keep for compatibility
                                canDisplayOnPlayer = canDisplayOnPlayer,  -- TWW 11.0+
                                playerCanCollect = playerCanCollect,      -- TWW 11.0+
                                exclusions = appearanceInfo.exclusions,   -- TWW 11.0+ (bitfield)
                                isHideVisual = appearanceInfo.isHideVisual,
                                uiOrder = appearanceInfo.uiOrder,
                                categoryID = sourceInfo.categoryID,
                                -- Data will be enriched asynchronously
                                name = nil,
                                icon = nil,
                                quality = nil,
                                sourceText = nil,
                            })
                            
                            -- #region agent log
                            countAdded = countAdded + 1
                            
                            -- Stop if we've hit the limit (prevent freezing with huge datasets)
                            if #results >= MAX_RESULTS_PER_CATEGORY then
                                reachedLimit = true
                                break  -- Break out of sources loop
                            end
                        end  -- End of if success and sourceInfo
                    end  -- End of if type(sourceID) == "number"
                    end  -- End of for sources loop
                end  -- End of if sources and #sources > 0
            end  -- End of if not appearanceInfo.isCollected
            
            processedCount = processedCount + 1
            
            -- Update progress
            if progressCallback and processedCount % BATCH_SIZE == 0 then
                progressCallback(processedCount, totalCount)
            end
            
            -- Check frame budget every batch
            if i % BATCH_SIZE == 0 then
                local elapsed = debugprofilestop() - startTime
                if elapsed > FRAME_BUDGET_MS then
                    coroutine.yield()  -- Pause and resume next frame
                    startTime = debugprofilestop()
                end
            end
        end
        
        local totalElapsed = debugprofilestop() - startTimeTotal
        self:Debug(string.format("Transmog processing complete: %d items in %.2fms", #results, totalElapsed))
        
        -- Final progress update
        if progressCallback then
            progressCallback(totalCount, totalCount)
        end
        
        callback(results)
    end)
    
    -- Resume coroutine every frame until complete
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local status = coroutine.status(co)
        
        if status == "dead" then
            ticker:Cancel()
        else
            local success, errorMsg = coroutine.resume(co)
            if not success then
                self:Print("|cffff0000Transmog Coroutine Error:|r " .. tostring(errorMsg))
                ticker:Cancel()
                callback({})
            end
        end
    end)
end

-- ============================================================================
-- ASYNCHRONOUS ITEM DATA LOADING (ItemMixin)
-- ============================================================================

--[[
    Load transmog item data asynchronously using ItemMixin
    Prevents nil errors by waiting for item data to load
    
    @param sourceID number - Transmog source ID
    @param callback function - Called with item data when loaded
]]
function WarbandNexus:LoadTransmogItemAsync(sourceID, callback)
    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
    if not sourceInfo or not sourceInfo.itemID then
        callback(nil)
        return
    end
    
    local itemID = sourceInfo.itemID
    
    -- Create ItemMixin object
    local item = Item:CreateFromItemID(itemID)
    if not item then
        callback(nil)
        return
    end
    
    -- Wait for item data to load
    item:ContinueOnItemLoad(function()
        local itemName = item:GetItemName()
        local itemLink = item:GetItemLink()
        local itemQuality = item:GetItemQuality()
        local icon = item:GetItemIcon()
        
        -- All data loaded successfully
        callback({
            itemID = itemID,
            name = itemName,
            link = itemLink,
            quality = itemQuality,
            icon = icon,
            sourceID = sourceID,
        })
    end)
end

--[[
    Batch load multiple transmog items asynchronously
    @param transmogItems table - Array of transmog items with sourceID
    @param onItemLoaded function - Called for each item as it loads
    @param onComplete function - Called when all items are loaded
]]
function WarbandNexus:LoadTransmogItemsBatch(transmogItems, onItemLoaded, onComplete)
    if not transmogItems or #transmogItems == 0 then
        if onComplete then
            onComplete()
        end
        return
    end
    
    local totalItems = #transmogItems
    local loadedCount = 0
    
    for i, item in ipairs(transmogItems) do
        self:LoadTransmogItemAsync(item.sourceID, function(itemData)
            loadedCount = loadedCount + 1
            
            -- Update item with loaded data
            if itemData then
                item.name = itemData.name
                item.icon = itemData.icon
                item.quality = itemData.quality
                item.link = itemData.link
            end
            
            -- Call per-item callback
            if onItemLoaded then
                onItemLoaded(item, loadedCount, totalItems)
            end
            
            -- Check if all items loaded
            if loadedCount >= totalItems and onComplete then
                onComplete()
            end
        end)
    end
end

-- ============================================================================
-- SOURCE TEXT PARSING (Hybrid Approach)
-- ============================================================================

--[[
    Get source text from boss drops API (fastest method)
    @param sourceID number - Transmog source ID
    @return string|nil - Source text or nil
]]
function WarbandNexus:GetSourceFromDrops(sourceID)
    if not C_TransmogCollection.GetAppearanceSourceDrops then
        return nil
    end
    
    local drops = C_TransmogCollection.GetAppearanceSourceDrops(sourceID)
    if not drops or #drops == 0 then
        return nil
    end
    
    local drop = drops[1]
    if drop.encounter and drop.instance then
        return string.format("Drop: %s (%s)", drop.encounter, drop.instance)
    elseif drop.encounter then
        return string.format("Drop: %s", drop.encounter)
    elseif drop.instance then
        return string.format("Drop: %s", drop.instance)
    end
    
    return nil
end

--[[
    Get source text from tooltip parsing (fallback method)
    @param sourceID number - Transmog source ID
    @return string|nil - Source text or nil
]]
function WarbandNexus:GetSourceFromTooltip(sourceID)
    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
    if not sourceInfo or not sourceInfo.itemID then
        return nil
    end
    
    -- Use C_TooltipInfo API (modern method)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then
        return nil
    end
    
    -- FIX: GetTransmogrifyItem expects transmogLocation, use GetItemByID for itemID
    local tooltipData = C_TooltipInfo.GetItemByID(sourceInfo.itemID)
    if not tooltipData or not tooltipData.lines then
        return nil
    end
    
    -- Source keywords to look for
    local sourceKeywords = {
        "Drop:", "Vendor:", "Quest:", "Achievement:", "Profession:",
        "Crafted:", "World Event:", "Holiday:", "PvP:", "Arena:",
        "Battleground:", "Dungeon:", "Raid:", "Trading Post:",
        "Treasure:", "Reputation:", "Garrison:", "Covenant:"
    }
    
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local text = line.leftText
            
            -- Check if line contains source keywords
            for _, keyword in ipairs(sourceKeywords) do
                if text:find(keyword, 1, true) then
                    -- Clean escape sequences
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")  -- Color codes
                    text = text:gsub("|r", "")  -- Reset
                    text = text:gsub("|T.-|t", "")  -- Textures
                    text = text:gsub("|H.-|h", "")  -- Hyperlinks
                    text = text:gsub("|h", "")
                    
                    return text:trim()
                end
            end
        end
    end
    
    return nil
end

--[[
    Get transmog source text using hybrid approach
    Tries drops API first, then falls back to tooltip parsing
    
    @param sourceID number - Transmog source ID
    @return string - Source text (never nil, returns "Unknown source" if not found)
]]
function WarbandNexus:GetTransmogSourceText(sourceID)
    -- Method 1: Boss drops API (fastest)
    local dropSource = self:GetSourceFromDrops(sourceID)
    if dropSource then
        return dropSource
    end
    
    -- Method 2: Tooltip parsing (fallback)
    local tooltipSource = self:GetSourceFromTooltip(sourceID)
    if tooltipSource then
        return tooltipSource
    end
    
    -- Method 3: Default
    return "Unknown source"
end

--[[
    Batch process source text for multiple transmog items
    @param transmogItems table - Array of transmog items with sourceID
    @param onComplete function - Called when all sources are processed
]]
function WarbandNexus:ProcessTransmogSources(transmogItems, onComplete)
    if not transmogItems or #transmogItems == 0 then
        if onComplete then
            onComplete()
        end
        return
    end
    
    -- Process sources synchronously (source text parsing is fast)
    for _, item in ipairs(transmogItems) do
        if item.sourceID then
            item.sourceText = self:GetTransmogSourceText(item.sourceID)
        end
    end
    
    if onComplete then
        onComplete()
    end
end

-- ============================================================================
-- HIGH-LEVEL API FUNCTIONS
-- ============================================================================

--[[
    Get uncollected transmog items for a category
    This is the main function to call from UI code
    
    @param categoryKey string - Category key (e.g., "head", "shoulder", or "all")
    @param callback function - Called with array of transmog items when complete
    @param progressCallback function (optional) - Called with progress updates
]]
function WarbandNexus:GetUncollectedTransmog(categoryKey, callback, progressCallback)
    -- Handle "all" category - Get mixed results from all categories (5 from each)
    if categoryKey == "all" then
        self:GetMixedUncollectedTransmog(callback, progressCallback)
        return
    end
    
    -- Get category definition
    local category = self:GetTransmogCategoryByKey(categoryKey)
    if not category then
        self:Print("|cffff0000Error:|r Invalid transmog category: " .. tostring(categoryKey))
        callback({})
        return
    end
    
    -- Start coroutine processing
    self:ProcessTransmogCoroutine(category.id, function(results)
        
        -- Enrich data with item info and source text
        self:LoadTransmogItemsBatch(results, function(item, loaded, total)
            -- Progress update per item
            if progressCallback then
                progressCallback(loaded, total, "Loading item data...")
            end
        end, function()
            -- All items loaded, now process source text
            self:ProcessTransmogSources(results, function()
                -- All done
                callback(results)
            end)
        end)
    end, progressCallback)
end

--[[
    Get uncollected transmog items from all categories (mixed sample)
    Fetches 5 items from each category for a total of ~40 items
    @param callback function - Called with array of transmog items when complete
    @param progressCallback function (optional) - Called with progress updates
]]
function WarbandNexus:GetMixedUncollectedTransmog(callback, progressCallback)
    local allResults = {}
    local categoriesProcessed = 0
    local categories = GetTransmogCategories()
    local totalCategories = #categories
    local ITEMS_PER_CATEGORY = 5  -- Small sample from each category
    
    -- Temporarily reduce MAX_RESULTS_PER_CATEGORY for this fetch
    local originalMax = MAX_RESULTS_PER_CATEGORY
    MAX_RESULTS_PER_CATEGORY = ITEMS_PER_CATEGORY
    
    for _, category in ipairs(categories) do
        self:ProcessTransmogCoroutine(category.id, function(results)
            -- Add category results to all results (limited to ITEMS_PER_CATEGORY)
            for i = 1, math.min(#results, ITEMS_PER_CATEGORY) do
                table.insert(allResults, results[i])
            end
            
            categoriesProcessed = categoriesProcessed + 1
            
            if progressCallback then
                progressCallback(categoriesProcessed, totalCategories, "Processing categories...")
            end
            
            -- All categories processed
            if categoriesProcessed >= totalCategories then
                -- Restore original max
                MAX_RESULTS_PER_CATEGORY = originalMax
                
                -- Enrich data
                self:LoadTransmogItemsBatch(allResults, nil, function()
                    self:ProcessTransmogSources(allResults, function()
                        callback(allResults)
                    end)
                end)
            end
        end)
    end
end

--[[
    Get uncollected transmog items from all categories
    @param callback function - Called with array of transmog items when complete
    @param progressCallback function (optional) - Called with progress updates
]]
function WarbandNexus:GetAllUncollectedTransmog(callback, progressCallback)
    local allResults = {}
    local categoriesProcessed = 0
    local categories = GetTransmogCategories()
    local totalCategories = #categories
    
    for _, category in ipairs(categories) do
        self:ProcessTransmogCoroutine(category.id, function(results)
            -- Add category results to all results
            for _, item in ipairs(results) do
                table.insert(allResults, item)
            end
            
            categoriesProcessed = categoriesProcessed + 1
            
            if progressCallback then
                progressCallback(categoriesProcessed, totalCategories, "Processing categories...")
            end
            
            -- All categories processed
            if categoriesProcessed >= totalCategories then
                
                -- Enrich data
                self:LoadTransmogItemsBatch(allResults, nil, function()
                    self:ProcessTransmogSources(allResults, function()
                        callback(allResults)
                    end)
                end)
            end
        end)
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--[[
    Check if a specific transmog source is collected
    @param sourceID number - Transmog source ID
    @return boolean - True if collected
]]
function WarbandNexus:IsTransmogCollected(sourceID)
    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
    if not sourceInfo then
        return false
    end
    
    return sourceInfo.isCollected or false
end

--[[
    Check if transmog system is available
    @return boolean - True if APIs are available
]]
function WarbandNexus:IsTransmogAvailable()
    local available, _ = CheckTransmogAPIs()
    return available
end

--[[
    Search uncollected transmog items by text query
    Uses WoW's native search API for optimal performance
    
    @param categoryKey string - Category key (e.g., "head", "shoulder")
    @param searchText string - Search query
    @param callback function - Called with array of transmog items when complete
    @param progressCallback function (optional) - Called with progress updates
]]
function WarbandNexus:SearchUncollectedTransmog(categoryKey, searchText, callback, progressCallback)
    if not searchText or searchText == "" then
        -- No search text, just get regular uncollected items
        self:GetUncollectedTransmog(categoryKey, callback, progressCallback)
        return
    end
    
    -- Handle "all" category for search - use first category (Head) as search applies across all
    if categoryKey == "all" then
        categoryKey = "head"  -- Search API works across all categories anyway
    end
    
    -- Get category definition
    local category = self:GetTransmogCategoryByKey(categoryKey)
    if not category then
        self:Print("|cffff0000Error:|r Invalid transmog category: " .. tostring(categoryKey))
        callback({})
        return
    end
    
    -- SIMPLIFIED APPROACH: Just filter results by name (client-side search)
    -- WoW's search API is unreliable, so we'll do simple filtering instead
    
    self:GetUncollectedTransmog(categoryKey, function(results)
        -- Filter results by search text
        local filtered = {}
        local searchLower = string.lower(searchText)
        
        for _, item in ipairs(results) do
            if item.name and string.find(string.lower(item.name), searchLower, 1, true) then
                table.insert(filtered, item)
            end
        end
        
        callback(filtered)
    end, progressCallback)
end

-- String trim utility
if not string.trim then
    function string.trim(s)
        return s:match("^%s*(.-)%s*$")
    end
end

