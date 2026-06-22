--[[
    Warband Nexus - Transmog Manager Module
    C_TransmogCollection scans with coroutine frame budgeting and async item loads.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- CONSTANTS AND CONFIGURATION

local FRAME_BUDGET_MS = 16  -- Maximum processing time per frame (16ms = ~60 FPS)
local BATCH_SIZE = 10       -- Number of items to process before checking frame budget (reduced for more frequent yields)
local MAX_RESULTS_PER_CATEGORY = 50  -- Limit results per category to prevent freezing (user can search for more)
local TRANSMOG_BROWSE_CACHE_VERSION = 5
ns.TRANSMOG_BROWSE_CACHE_VERSION = TRANSMOG_BROWSE_CACHE_VERSION

local function TrimString(text)
    if not text then return "" end
    return (text:gsub("^%s*(.-)%s*$", "%1"))
end

-- Transmog Category Mappings (Enum.TransmogCollectionType — warcraft.wiki.gg)
local MAINHAND_COLLECTION_TYPES = { 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29 }
local OFFHAND_COLLECTION_TYPES = { 18, 19, 13, 14, 15, 16, 17, 12 }

local function BuildTransmogCategories()
    local L = ns.L
    return {
        { id = 1, key = "head", name = (L and L["SLOT_HEAD"]) or INVTYPE_HEAD or "Head", slot = "HeadSlot", icon = "Interface\\Icons\\INV_Helmet_01", enumIds = { 1 } },
        { id = 2, key = "shoulder", name = (L and L["SLOT_SHOULDER"]) or INVTYPE_SHOULDER or "Shoulder", slot = "ShoulderSlot", icon = "Interface\\Icons\\INV_Shoulder_02", enumIds = { 2 } },
        { id = 3, key = "back", name = (L and L["SLOT_BACK"]) or INVTYPE_CLOAK or "Back", slot = "BackSlot", icon = "Interface\\Icons\\INV_Misc_Cape_01", enumIds = { 3 } },
        { id = 4, key = "chest", name = (L and L["SLOT_CHEST"]) or INVTYPE_CHEST or "Chest", slot = "ChestSlot", icon = "Interface\\Icons\\INV_Chest_Cloth_17", enumIds = { 4 } },
        { id = 5, key = "shirt", name = (L and L["SLOT_SHIRT"]) or INVTYPE_BODY or "Shirt", slot = "ShirtSlot", icon = "Interface\\Icons\\INV_Shirt_01", enumIds = { 5 } },
        { id = 6, key = "tabard", name = (L and L["SLOT_TABARD"]) or INVTYPE_TABARD or "Tabard", slot = "TabardSlot", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", enumIds = { 6 } },
        { id = 7, key = "wrist", name = (L and L["SLOT_WRIST"]) or INVTYPE_WRIST or "Wrist", slot = "WristSlot", icon = "Interface\\Icons\\INV_Bracer_02", enumIds = { 7 } },
        { id = 8, key = "hands", name = (L and L["SLOT_HANDS"]) or INVTYPE_HAND or "Hands", slot = "HandsSlot", icon = "Interface\\Icons\\INV_Gauntlets_01", enumIds = { 8 } },
        { id = 9, key = "waist", name = (L and L["SLOT_WAIST"]) or INVTYPE_WAIST or "Waist", slot = "WaistSlot", icon = "Interface\\Icons\\INV_Belt_01", enumIds = { 9 } },
        { id = 10, key = "legs", name = (L and L["SLOT_LEGS"]) or INVTYPE_LEGS or "Legs", slot = "LegsSlot", icon = "Interface\\Icons\\INV_Pants_01", enumIds = { 10 } },
        { id = 11, key = "feet", name = (L and L["SLOT_FEET"]) or INVTYPE_FEET or "Feet", slot = "FeetSlot", icon = "Interface\\Icons\\INV_Boots_01", enumIds = { 11 } },
        { id = 12, key = "mainhand", name = (L and L["SLOT_MAINHAND"]) or INVTYPE_WEAPONMAINHAND or "Main Hand", slot = "MainHandSlot", icon = "Interface\\Icons\\INV_Sword_27", enumIds = MAINHAND_COLLECTION_TYPES },
        { id = 18, key = "offhand", name = (L and L["SLOT_OFFHAND"]) or INVTYPE_WEAPONOFFHAND or "Off Hand", slot = "SecondaryHandSlot", icon = "Interface\\Icons\\INV_Shield_06", enumIds = OFFHAND_COLLECTION_TYPES },
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

-- API AVAILABILITY CHECK

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

local function CheckTransmogBrowseAPIs()
    if not C_TransmogCollection then
        return false, "C_TransmogCollection API not available"
    end
    if not C_TransmogCollection.GetCategoryAppearances then
        return false, "C_TransmogCollection.GetCategoryAppearances not available"
    end
    return true
end

-- CATEGORY MANAGEMENT

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
    local cats = GetTransmogCategories()
    for ci = 1, #cats do
        local category = cats[ci]
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
    local cats = GetTransmogCategories()
    for ci = 1, #cats do
        local category = cats[ci]
        if category.id == categoryID then
            return category
        end
    end
    return nil
end

-- COROUTINE-BASED TRANSMOG FETCHING

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
        
        local reachedLimit = false  -- Flag for early exit
        
        self:Debug("Processing " .. totalCount .. " transmog items for category " .. categoryID)
        
        for i = 1, #appearances do
            local appearanceInfo = appearances[i]
            -- Early exit if we've hit the limit
            if reachedLimit then
                break
            end
            -- Skip collected items (Warband-compatible filtering)
            if not appearanceInfo.isCollected then
                -- Get sources for this appearance
                local sources = C_TransmogCollection.GetAppearanceSources(appearanceInfo.visualID)
                
                if sources and #sources > 0 then
                    -- Process ALL sources for this appearance (multiple items can have same visual)
                    for sourceIndex = 1, #sources do
                        local sourceData = sources[sourceIndex]
                        local sourceID = sourceData.sourceID  -- sources is array of {sourceID=X, ...}
                        
                        -- Validate sourceID is a valid number
                        if type(sourceID) == "number" and sourceID > 0 then
                            -- Get source info (with protected call to catch errors)
                            local success, sourceInfo = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
                            
                            if success and sourceInfo then
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
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            self:Debug(string.format("Transmog processing complete: %d items in %.2fms", #results, totalElapsed))
        end
        
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

-- ASYNCHRONOUS ITEM DATA LOADING (ItemMixin)

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
    
    for ii = 1, #transmogItems do
        local item = transmogItems[ii]
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

-- SOURCE TEXT PARSING (Hybrid Approach)

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
    local itemID
    local itemLink
    if C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
        local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
        if ok and info then
            if info.itemLink and not (issecretvalue and issecretvalue(info.itemLink)) then
                itemLink = info.itemLink
            end
        end
    end
    local sourceInfo = C_TransmogCollection and C_TransmogCollection.GetSourceInfo and C_TransmogCollection.GetSourceInfo(sourceID)
    if sourceInfo and sourceInfo.itemID then
        itemID = sourceInfo.itemID
    end
    if not itemID and not itemLink then
        return nil
    end
    if not C_TooltipInfo then
        return nil
    end

    local tooltipData
    if itemLink and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok then tooltipData = data end
    end
    if not tooltipData and itemID and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok then tooltipData = data end
    end
    if not tooltipData or not tooltipData.lines then
        return nil
    end
    local sourceKeywords = {
        "Drop:", "Vendor:", "Quest:", "Achievement:", "Profession:",
        "Crafted:", "World Event:", "Holiday:", "PvP:", "Arena:",
        "Battleground:", "Dungeon:", "Raid:", "Trading Post:",
        "Treasure:", "Reputation:", "Garrison:", "Covenant:"
    }
    
    local tooltipLines = tooltipData.lines
    for li = 1, #tooltipLines do
        local line = tooltipLines[li]
        if line.leftText then
            local text = line.leftText
            if issecretvalue and issecretvalue(text) then
                text = nil
            end
            if text then
            
            -- Check if line contains source keywords
            for ki = 1, #sourceKeywords do
                local keyword = sourceKeywords[ki]
                if text:find(keyword, 1, true) then
                    -- Clean escape sequences
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")  -- Color codes
                    text = text:gsub("|r", "")  -- Reset
                    text = text:gsub("|T.-|t", "")  -- Textures
                    text = text:gsub("|H.-|h", "")  -- Hyperlinks
                    text = text:gsub("|h", "")
                    
                    return TrimString(text)
                end
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
    for ii = 1, #transmogItems do
        local item = transmogItems[ii]
        if item.sourceID then
            item.sourceText = self:GetTransmogSourceText(item.sourceID)
        end
    end
    
    if onComplete then
        onComplete()
    end
end

-- HIGH-LEVEL API FUNCTIONS

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
    
    for ci = 1, #categories do
        local category = categories[ci]
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
    
    for ci = 1, #categories do
        local category = categories[ci]
        self:ProcessTransmogCoroutine(category.id, function(results)
            -- Add category results to all results
            for ri = 1, #results do
                table.insert(allResults, results[ri])
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

-- UTILITY FUNCTIONS

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

local function ItemNameFromTooltip(itemID, itemLink)
    if not C_TooltipInfo then return nil end
    local tooltipData
    if itemLink and itemLink ~= "" and not (issecretvalue and issecretvalue(itemLink)) and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok then tooltipData = data end
    elseif itemID and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok then tooltipData = data end
    end
    if not tooltipData or not tooltipData.lines then return nil end
    local line = tooltipData.lines[1]
    if not line or not line.leftText then return nil end
    local text = line.leftText
    if not text or text == "" or (issecretvalue and issecretvalue(text)) then return nil end
    local Utilities = ns.Utilities
    if Utilities and Utilities.StripFormattingCodes then
        return Utilities:StripFormattingCodes(text)
    end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s*(.-)%s*$", "%1")
end

local function SafeTransmogBool(val, defaultWhenSecret)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return defaultWhenSecret == true end
    return val == true
end

local function SafeTransmogOptionalBool(val)
    if val == nil then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    if val == true then return true end
    if val == false then return false end
    return nil
end

local function SafeTransmogString(val)
    if not val or val == "" then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    if type(val) ~= "string" then return nil end
    return val
end

--- Merge GetCategoryAppearances across one or more Enum.TransmogCollectionType values.
local function FetchCategoryAppearances(category)
    local enumIds = category.enumIds or { category.id }
    local merged = {}
    for ei = 1, #enumIds do
        local enumId = enumIds[ei]
        local ok, apps = pcall(C_TransmogCollection.GetCategoryAppearances, enumId)
        if ok and apps then
            for ai = 1, #apps do
                merged[#merged + 1] = {
                    appearanceInfo = apps[ai],
                    categoryTypeID = enumId,
                }
            end
        end
    end
    return merged
end

local function EnrichTransmogBrowseRow(row)
    if not row then return end
    local sourceID = row.sourceID
    local itemID = row.itemID

    if sourceID and C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
        local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
        if ok and info then
            if type(info.icon) == "number" and info.icon > 0
                and not (issecretvalue and issecretvalue(info.icon)) then
                row.icon = info.icon
            end
            if info.itemLink and info.itemLink ~= ""
                and not (issecretvalue and issecretvalue(info.itemLink)) then
                row.link = info.itemLink
            end
        end
    end

    if itemID and C_Item and C_Item.GetItemIconByID
        and (type(row.icon) ~= "number" or row.icon <= 0) then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and type(icon) == "number" and icon > 0
            and not (issecretvalue and issecretvalue(icon)) then
            row.icon = icon
        end
    end

    local name
    if row.link and C_Item and C_Item.GetItemInfo then
        local ok, itemName = pcall(C_Item.GetItemInfo, row.link)
        if ok and type(itemName) == "string" and itemName ~= ""
            and not (issecretvalue and issecretvalue(itemName)) then
            name = itemName
        end
    end
    if (not name or name == "") and itemID and C_Item and C_Item.GetItemInfo then
        local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(itemName) == "string" and itemName ~= ""
            and not (issecretvalue and issecretvalue(itemName)) then
            name = itemName
        end
    end
    if (not name or name == "") and itemID and GetItemInfo then
        local ok, itemName = pcall(GetItemInfo, itemID)
        if ok and type(itemName) == "string" and itemName ~= ""
            and not (issecretvalue and issecretvalue(itemName)) then
            name = itemName
        end
    end
    if not name or name == "" then
        name = ItemNameFromTooltip(itemID, row.link)
    end
    if type(name) == "string" and name ~= "" then
        row.name = name
    elseif itemID then
        row.name = string.format("Item %d", itemID)
        row._namePending = true
    end
    row.icon = nil
end

local function BuildTransmogSourceEntry(sourceData, categoryTypeID)
    if not sourceData then return nil end
    local sourceID = sourceData.sourceID
    if type(sourceID) ~= "number" or sourceID <= 0 then return nil end
    if issecretvalue and issecretvalue(sourceID) then return nil end

    local itemID = sourceData.itemID
    if itemID and issecretvalue and issecretvalue(itemID) then
        itemID = nil
    end
    if not itemID then
        local okInfo, sourceInfo = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
        if okInfo and sourceInfo and sourceInfo.itemID then
            itemID = sourceInfo.itemID
            if itemID and issecretvalue and issecretvalue(itemID) then
                itemID = nil
            end
        end
    end

    local entry = {
        sourceID = sourceID,
        itemID = itemID,
        name = SafeTransmogString(sourceData.name),
        categoryID = sourceData.categoryID or categoryTypeID,
        quality = sourceData.quality,
        link = nil,
        sourceText = nil,
        isCollected = SafeTransmogOptionalBool(sourceData.isCollected),
    }
    if sourceID and C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
        local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
        if ok and info and info.itemLink and info.itemLink ~= ""
            and not (issecretvalue and issecretvalue(info.itemLink)) then
            entry.link = info.itemLink
        end
        if entry.isCollected == nil and info then
            entry.isCollected = SafeTransmogOptionalBool(info.isCollected)
        end
    end
    return entry
end

local function PickPrimaryTransmogSource(sources)
    for i = 1, #sources do
        if sources[i].isCollected then return sources[i] end
    end
    return sources[1]
end

local function MergeTransmogSourcesIntoRow(row, sourceList, categoryTypeID)
    row.sources = row.sources or {}
    row._sourceIDSet = row._sourceIDSet or {}
    for i = 1, #sourceList do
        local entry = BuildTransmogSourceEntry(sourceList[i], categoryTypeID)
        if entry and not row._sourceIDSet[entry.sourceID] then
            row._sourceIDSet[entry.sourceID] = true
            row.sources[#row.sources + 1] = entry
        end
    end
end

local function FinalizeTransmogBrowseRow(row, category)
    if not row or not row.sources or #row.sources == 0 then return end
    local primary = PickPrimaryTransmogSource(row.sources)
    row.sourceID = primary.sourceID
    row.itemID = primary.itemID
    row.categoryID = primary.categoryID or row.categoryID
    row.quality = primary.quality
    row.link = primary.link
    if not row.name or row.name == "" then
        row.name = primary.name
    end
    if not row.name or row.name == "" then
        EnrichTransmogBrowseRow(row)
    else
        row.icon = nil
    end
    if row.sourceText == nil and row.sourceID and WarbandNexus and WarbandNexus.GetTransmogSourceText then
        row.sourceText = WarbandNexus:GetTransmogSourceText(row.sourceID)
    end
    for i = 1, #row.sources do
        local src = row.sources[i]
        if (not src.sourceText or src.sourceText == "") and src.sourceID
            and WarbandNexus and WarbandNexus.GetTransmogSourceText then
            src.sourceText = WarbandNexus:GetTransmogSourceText(src.sourceID)
        end
    end
end

local function AppendTransmogAppearanceRow(category, wrapped, showCollected, showUncollected, results, visualByID)
    if not wrapped or not category then return end
    local appearanceInfo = wrapped.appearanceInfo or wrapped
    local categoryTypeID = wrapped.categoryTypeID or category.id
    if not appearanceInfo or not appearanceInfo.visualID then return end

    local isCollected = SafeTransmogBool(appearanceInfo.isCollected, false)
    if not ((isCollected and showCollected) or (not isCollected and showUncollected)) then
        return
    end

    local canDisplay = SafeTransmogOptionalBool(appearanceInfo.canDisplayOnPlayer)
    if canDisplay == nil then
        canDisplay = SafeTransmogOptionalBool(appearanceInfo.isUsable)
    end
    if canDisplay == false then return end

    local visualID = appearanceInfo.visualID
    if issecretvalue and issecretvalue(visualID) then return end

    local okSources, sources = pcall(C_TransmogCollection.GetAppearanceSources, visualID, categoryTypeID)
    if not okSources or not sources or #sources == 0 then return end

    local builtSources = {}
    for si = 1, #sources do
        local entry = BuildTransmogSourceEntry(sources[si], categoryTypeID)
        if entry then builtSources[#builtSources + 1] = entry end
    end
    if #builtSources == 0 then return end

    visualByID = visualByID or {}
    local existing = visualByID[visualID]
    if existing then
        MergeTransmogSourcesIntoRow(existing, sources, categoryTypeID)
        if isCollected then
            existing.isCollected = true
            existing.collected = true
        end
        FinalizeTransmogBrowseRow(existing, category)
        return
    end

    local primary = PickPrimaryTransmogSource(builtSources)
    local row = {
        visualID = visualID,
        sourceID = primary.sourceID,
        itemID = primary.itemID,
        sources = builtSources,
        _sourceIDSet = {},
        categoryID = primary.categoryID or categoryTypeID or category.id,
        categoryKey = category.key,
        categoryName = category.name,
        isCollected = isCollected,
        collected = isCollected,
        name = SafeTransmogString(primary.name),
        icon = category.icon,
        quality = primary.quality,
        link = primary.link,
        sourceText = nil,
    }
    for i = 1, #builtSources do
        row._sourceIDSet[builtSources[i].sourceID] = true
    end
    FinalizeTransmogBrowseRow(row, category)
    visualByID[visualID] = row
    results[#results + 1] = row
end

--[[
    Load one equipment-slot category for Collections Transmog sub-tabs.
    @param categoryKey string - e.g. "head", "chest"
    @param callback function(table) - flat rows for that slot
]]
function WarbandNexus:LoadTransmogCategoryData(categoryKey, callback, progressCallback, opts)
    if not callback then return end
    opts = opts or {}
    local showCollected = (opts.showCollected ~= false)
    local showUncollected = (opts.showUncollected ~= false)
    local forceRefresh = (opts.forceRefresh == true)

    local available, errorMsg = CheckTransmogBrowseAPIs()
    if not available then
        if self.Print then
            self:Print("|cffff0000Error:|r " .. tostring(errorMsg))
        end
        callback({})
        return
    end

    local category = self:GetTransmogCategoryByKey(categoryKey)
    if not category then
        callback({})
        return
    end

    self._transmogCategoryCache = self._transmogCategoryCache or {}
    local bucket = self._transmogCategoryCache[categoryKey]
    if not forceRefresh and bucket and bucket.version == TRANSMOG_BROWSE_CACHE_VERSION then
        callback(bucket.rows or {})
        return
    end

    if self._transmogCategoryLoadTicker then
        self._transmogCategoryLoadTicker:Cancel()
        self._transmogCategoryLoadTicker = nil
    end

    local results = {}
    local visualByID = {}
    local appearances = FetchCategoryAppearances(category)
    local appIdx = 1
    local totalApps = #appearances

    if progressCallback then
        progressCallback(0, totalApps, category.name or category.key or "")
    end

    if totalApps == 0 then
        callback(results)
        return
    end

    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local budgetStart = debugprofilestop()
        while appIdx <= totalApps and (debugprofilestop() - budgetStart) < FRAME_BUDGET_MS do
            AppendTransmogAppearanceRow(category, appearances[appIdx], showCollected, showUncollected, results, visualByID)
            appIdx = appIdx + 1
            if progressCallback and (appIdx % BATCH_SIZE == 0 or appIdx > totalApps) then
                progressCallback(appIdx, totalApps, category.name or category.key or "")
            end
        end

        if appIdx > totalApps then
            ticker:Cancel()
            self._transmogCategoryLoadTicker = nil
            if totalApps > 0 then
                self._transmogCategoryCache[categoryKey] = {
                    rows = results,
                    version = TRANSMOG_BROWSE_CACHE_VERSION,
                }
            end
            callback(results)
        end
    end)
    self._transmogCategoryLoadTicker = ticker
end

--[[
    Build a browse list for Collections UI (collected + uncollected, all slot categories).
    Results are session-cached on WarbandNexus._transmogBrowseCache until TRANSMOG_COLLECTION_UPDATED.
    @param callback function(table) - flat array of transmog row entries
    @param progressCallback function|nil - (current, total, message)
    @param opts table|nil - { showCollected=true, showUncollected=true, forceRefresh=false }
]]
function WarbandNexus:LoadTransmogBrowseData(callback, progressCallback, opts)
    if not callback then return end
    opts = opts or {}
    local showCollected = (opts.showCollected ~= false)
    local showUncollected = (opts.showUncollected ~= false)
    local forceRefresh = (opts.forceRefresh == true)
    local partialCallback = opts.partialCallback

    local available, errorMsg = CheckTransmogBrowseAPIs()
    if not available then
        if self.Print then
            self:Print("|cffff0000Error:|r " .. tostring(errorMsg))
        end
        callback({})
        return
    end

    if not forceRefresh and self._transmogBrowseCache
        and self._transmogBrowseCacheVersion == TRANSMOG_BROWSE_CACHE_VERSION then
        callback(self._transmogBrowseCache)
        return
    end

    if self._transmogBrowseLoadTicker then
        self._transmogBrowseLoadTicker:Cancel()
        self._transmogBrowseLoadTicker = nil
    end

    local results = {}
    local visualByID = {}
    local categories = GetTransmogCategories()
    local totalCats = #categories
    local catIdx = 1
    local appearances = nil
    local appIdx = 1

    local function finishBrowseLoad()
        self._transmogBrowseLoadTicker = nil
        self._transmogBrowseCache = results
        self._transmogBrowseCacheVersion = TRANSMOG_BROWSE_CACHE_VERSION
        callback(results)
    end

    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local budgetStart = debugprofilestop()
        while (debugprofilestop() - budgetStart) < FRAME_BUDGET_MS do
            if catIdx > totalCats then
                ticker:Cancel()
                finishBrowseLoad()
                return
            end

            local category = categories[catIdx]
            if not appearances then
                appearances = FetchCategoryAppearances(category)
                appIdx = 1
                if progressCallback then
                    progressCallback(catIdx, totalCats, category.name or category.key or "")
                end
            end

            if appIdx > #appearances then
                if partialCallback then
                    partialCallback(results, category.key, catIdx, totalCats)
                end
                catIdx = catIdx + 1
                appearances = nil
                if catIdx > totalCats then
                    ticker:Cancel()
                    finishBrowseLoad()
                end
                break
            end

            AppendTransmogAppearanceRow(category, appearances[appIdx], showCollected, showUncollected, results, visualByID)
            appIdx = appIdx + 1
        end
    end)
    self._transmogBrowseLoadTicker = ticker
end

function WarbandNexus:InvalidateTransmogBrowseCache()
    self._transmogBrowseCache = nil
    self._transmogBrowseCacheVersion = nil
    self._transmogCategoryCache = nil
    if self._transmogBrowseLoadTicker then
        self._transmogBrowseLoadTicker:Cancel()
        self._transmogBrowseLoadTicker = nil
    end
    if self._transmogCategoryLoadTicker then
        self._transmogCategoryLoadTicker:Cancel()
        self._transmogCategoryLoadTicker = nil
    end
    local cui = ns.CollectionsUI
    if cui and cui.state then
        cui.state._cachedTransmogBrowse = nil
        cui.state._lastGroupedTransmogData = nil
        cui.state._transmogCategoryRows = nil
        cui.state._transmogFlatList = nil
        cui.state._transmogRowByVisualID = nil
        if cui.state.currentSubTab == "transmog" and cui.state.contentFrame and cui.DrawTransmogContent then
            cui.state._transmogFlatList = nil
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if cui.state.currentSubTab == "transmog" and cui.state.contentFrame then
                        cui.DrawTransmogContent(cui.state.contentFrame)
                    end
                end)
            else
                cui.DrawTransmogContent(cui.state.contentFrame)
            end
        end
    end
end

function WarbandNexus:SearchUncollectedTransmog(categoryKey, searchText, callback, progressCallback)
    if not searchText or type(searchText) ~= "string" then
        self:GetUncollectedTransmog(categoryKey, callback, progressCallback)
        return
    end
    if issecretvalue and issecretvalue(searchText) then
        self:GetUncollectedTransmog(categoryKey, callback, progressCallback)
        return
    end
    if searchText == "" then
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
        
        for ri = 1, #results do
            local item = results[ri]
            local itemName = item and item.name
            if itemName and not (issecretvalue and issecretvalue(itemName))
                and string.find(string.lower(itemName), searchLower, 1, true) then
                table.insert(filtered, item)
            end
        end
        
        callback(filtered)
    end, progressCallback)
end

