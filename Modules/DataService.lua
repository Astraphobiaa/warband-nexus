--[[
    Warband Nexus - Data Service Module
    Centralized data collection, processing, and retrieval
    
    REFACTOR STATUS (Phase 2):
    ==========================
    This module is being refactored to delegate to specialized cache services:
    - PvE data → PvECacheService.lua
    - Items/Bank → ItemsCacheService.lua
    - Currency → CurrencyCacheService.lua
    - Reputation → ReputationCacheService.lua
    
    Current Responsibilities:
    - Character orchestration (gold, level, class, profession)
    - Cross-character aggregation queries
    - Legacy function wrappers (will be removed in Phase 3)
    
    DEPRECATED FUNCTIONS (Use cache services directly):
    - CollectPvEData() → PvECacheService:GetPvEData()
    - UpdatePvEDataV2() → PvECacheService:UpdatePvEData()
    - GetPvEDataV2() → PvECacheService:GetPvEData()
    - ScanBagV2() → ItemsCacheService:ScanInventoryBags()
    - GetPersonalBankV2() → ItemsCacheService:GetItemsData()
    - GetWarbandBankV2() → ItemsCacheService:GetWarbandBankData()
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants

-- Get library references
local LibSerialize = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- ============================================================================
-- PLAYED TIME TRACKING
-- ============================================================================
--[[
    Track cumulative /played time per character using RequestTimePlayed() API.
    TIME_PLAYED_MSG fires asynchronously with (totalTimePlayed, timePlayedThisLevel).
    Chat message is suppressed via ChatFrame_DisplayTimePlayed hook.
]]

local suppressTimePlayedChat = false
local origChatFrameDisplayTimePlayed = nil

--- Request played time from server (suppresses chat output)
function WarbandNexus:RequestPlayedTime()
    -- Hook ChatFrame_DisplayTimePlayed to suppress "/played" chat message
    if not suppressTimePlayedChat then
        suppressTimePlayedChat = true
        origChatFrameDisplayTimePlayed = ChatFrame_DisplayTimePlayed
        ChatFrame_DisplayTimePlayed = function() end
    end
    RequestTimePlayed()
end

--- Handle TIME_PLAYED_MSG event
--- @param totalTimePlayed number Total seconds played on this character
--- @param timePlayedThisLevel number Seconds played at current level
function WarbandNexus:OnTimePlayedReceived(event, totalTimePlayed, timePlayedThisLevel)
    -- Restore chat handler
    if suppressTimePlayedChat and origChatFrameDisplayTimePlayed then
        ChatFrame_DisplayTimePlayed = origChatFrameDisplayTimePlayed
        origChatFrameDisplayTimePlayed = nil
        suppressTimePlayedChat = false
    end

    if not totalTimePlayed or totalTimePlayed <= 0 then return end
    if not self.db or not self.db.global or not self.db.global.characters then return end

    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = self.db.global.characters[charKey]
    if not charData then return end

    charData.timePlayed = totalTimePlayed
    DebugPrint("|cff9370DB[WN DataService]|r Played time stored for " .. charKey .. ": " .. totalTimePlayed .. "s")

    -- Fire event so UI refreshes
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = charKey,
    })
end

-- ============================================================================
-- PVE LOADING STATE MANAGEMENT
-- ============================================================================
--[[
    PvE Loading State System
    Tracks data collection progress and provides visual feedback
    
    Purpose:
    - Track loading progress (0-100%)
    - Prevent multiple simultaneous collections
    - Provide cancellation mechanism
    - Update UI automatically during collection
]]

-- Global loading state (accessible from UI modules)
ns.PvELoadingState = {
    isLoading = false,           -- Currently collecting data
    loadingProgress = 0,         -- 0-100 progress percentage
    lastAttempt = 0,            -- Timestamp of last collection attempt
    attempts = 0,               -- Current retry attempt (1-3)
    error = nil,                -- Error message if failed
    currentStage = nil,         -- Current stage name (e.g., "Great Vault")
    cancelled = false,          -- User cancelled collection
}

-- Active coroutines for async collection
local activeCoroutines = {}

-- Tooltip item count cache: avoid full cross-character scan on every item hover. Invalidated on bag/bank changes.
local itemCountCache = {}
local ITEM_COUNT_CACHE_TTL = 30

-- ============================================================================
-- SESSION CACHE SYSTEM
-- ============================================================================
--[[
    Session Cache System - Runtime memory cache for collection data
    
    Purpose:
    - Minimize disk I/O by keeping frequently accessed data in memory
    - Compress saved data using LibDeflate + AceSerialize
    - Provide O(1) lookups for collection status checks
    
    Data Flow:
    LOAD:  SavedVariables → DecodeForPrint → DecompressDeflate → Deserialize → SessionCache
    SAVE:  SessionCache → Serialize → CompressDeflate → EncodeForPrint → SavedVariables
]]

-- Session cache storage (cleared on logout/reload)
local sessionCache = {}

--[[
    Initialize session cache
    Called on addon load (OnInitialize)
]]
function WarbandNexus:InitializeSessionCache()
    sessionCache = {
        collections = {},  -- Collection status cache
        plans = {},        -- Plan data cache
        characters = {},   -- Character data cache (NEW: gold, level, class, etc.)
        timestamp = time(),
    }
end

--[[
    Get data from session cache
    @param cacheKey string - Cache key
    @return any - Cached value or nil
]]
function WarbandNexus:GetFromSessionCache(cacheKey)
    if not cacheKey then return nil end
    return sessionCache[cacheKey]
end

--[[
    Set data in session cache
    @param cacheKey string - Cache key
    @param value any - Value to cache
]]
function WarbandNexus:SetInSessionCache(cacheKey, value)
    if not cacheKey then return end
    sessionCache[cacheKey] = value
end

--[[
    Invalidate session cache entry
    @param cacheKey string - Cache key to invalidate (nil = invalidate all)
]]
function WarbandNexus:InvalidateSessionCache(cacheKey)
    if cacheKey then
        sessionCache[cacheKey] = nil
    else
        -- Clear all except structure
        sessionCache = {
            collections = {},
            plans = {},
            characters = {},
            timestamp = time(),
        }
    end
end

-- ============================================================================
-- CHARACTER DATA CACHE (Session-based, Event-driven)
-- ============================================================================
--[[
    Character Data Cache System
    
    Purpose:
    - Cache frequently accessed character data (gold, level, class, etc.)
    - Event-driven updates (PLAYER_MONEY, PLAYER_LEVEL_UP, etc.)
    - Reduce redundant API calls
    - Provide fast O(1) lookups for UI modules
    
    Cached Data:
    - Gold (copper)
    - Level, MaxLevel
    - Class (localized + English)
    - Race (localized + English)
    - Faction (Horde/Alliance)
    - Gender (localized)
    - Specialization (name + icon)
    - Item Level (average)
    - Resting XP state
    - Zone location
]]

-- NO CHARACTER LIST CACHE - Always read fresh from DB (API > DB > UI pattern)

---Get comprehensive character data from DB
---DIRECT DB READ - No sessionCache (API > DB > UI pattern)
---@param forceRefresh boolean|nil Deprecated (kept for compatibility)
---@return table Character data from db.global.characters
function WarbandNexus:GetCharacterData(forceRefresh)
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
    if not charKey then return {} end
    
    -- DIRECT DB ACCESS
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return {}  -- Character not tracked
    end
    
    return self.db.global.characters[charKey]
end

---Update character data in DB (called by event handlers)
---DIRECT DB WRITE - No sessionCache (API > DB > UI pattern)
---@param dataType string Specific data type to update ("gold", "level", "spec", "itemLevel", etc.)
function WarbandNexus:UpdateCharacterCache(dataType)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    
    -- DIRECT DB ACCESS - No sessionCache
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return  -- Character not tracked
    end
    
    local charData = self.db.global.characters[charKey]
    
    -- Update specific data type in DB
    if dataType == "gold" then
        local totalCopper = math.floor(GetMoney())
        local gold = math.floor(totalCopper / 10000)
        local silver = math.floor((totalCopper % 10000) / 100)
        local copper = math.floor(totalCopper % 100)
        
        charData.gold = gold
        charData.silver = silver
        charData.copper = copper
        
    elseif dataType == "level" then
        charData.level = UnitLevel("player")
        
    elseif dataType == "spec" then
        local specID = GetSpecialization()
        if specID then
            local _, specName, _, specIcon = GetSpecializationInfo(specID)
            charData.specID = specID
            charData.specName = specName
            charData.specIcon = specIcon
        end
        
    elseif dataType == "itemLevel" then
        local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
        local newItemLevel = math.floor(avgItemLevelEquipped or 0)
        
        charData.itemLevel = newItemLevel
        
    elseif dataType == "resting" then
        charData.isResting = IsResting()
        
    elseif dataType == "zone" then
        charData.zoneName = GetZoneText()
        charData.subZoneName = GetSubZoneText()
    end
    
    -- Update lastSeen timestamp
    charData.lastSeen = time()
    
    -- Fire event for UI refresh (DB-First pattern)
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = charKey,
        dataType = dataType
    })
end

---Register character data cache events
function WarbandNexus:RegisterCharacterCacheEvents()
    -- EventManager is self (WarbandNexus) with AceEvent mixed in
    if not self.RegisterEvent then
        return
    end
    
    -- PLAYER_MONEY: owned by Core.lua → EventManager (OnMoneyChanged)
    -- DataService listens to WN_MONEY_UPDATED message instead
    self:RegisterMessage("WN_MONEY_UPDATED", function()
        self:UpdateCharacterCache("gold")
    end)
    
    -- Level changes
    self:RegisterEvent("PLAYER_LEVEL_UP", function(event)
        ns.DebugPrint("|cff9370DB[DataService]|r [Character Event] PLAYER_LEVEL_UP triggered")
        self:UpdateCharacterCache("level")
    end)
    
    -- Specialization changes
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(event)
        ns.DebugPrint("|cff9370DB[DataService]|r [Character Event] PLAYER_SPECIALIZATION_CHANGED triggered")
        self:UpdateCharacterCache("spec")
    end)
    
    -- PLAYER_EQUIPMENT_CHANGED: owned by EventManager (OnItemLevelChanged, throttled)
    -- DataService listens to WN_CHARACTER_UPDATED message instead
    self:RegisterMessage("WN_CHARACTER_UPDATED", function(event, data)
    end)
    
    -- Resting state changes
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function(event)
        ns.DebugPrint("|cff9370DB[DataService]|r [Character Event] PLAYER_UPDATE_RESTING triggered")
        self:UpdateCharacterCache("resting")
    end)
    
    -- Zone changes (debounced 2s — ZONE_CHANGED fires frequently during flight paths)
    local zoneUpdatePending = false
    local function DebouncedZoneUpdate()
        if zoneUpdatePending then return end
        zoneUpdatePending = true
        C_Timer.After(2, function()
            zoneUpdatePending = false
            self:UpdateCharacterCache("zone")
        end)
    end
    
    self:RegisterEvent("ZONE_CHANGED", function(event)
        ns.DebugPrint("|cff9370DB[DataService]|r [Zone Event] ZONE_CHANGED triggered")
        DebouncedZoneUpdate()
    end)
    
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function(event)
        ns.DebugPrint("|cff9370DB[DataService]|r [Zone Event] ZONE_CHANGED_NEW_AREA triggered")
        DebouncedZoneUpdate()
    end)
    
    -- SKILL_LINES_CHANGED: owned by EventManager (OnSkillLinesChanged, throttled)

    -- Invalidate tooltip item count cache when bags/bank change
    -- Listen to internal messages (ItemsCacheService is the single owner of WoW events)
    self:RegisterMessage("WN_BAGS_UPDATED", function()
        if self.InvalidateItemCountCache then self:InvalidateItemCountCache() end
        if self.InvalidateItemSummary then
            local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
            self:InvalidateItemSummary(charKey)
        end
    end)
    self:RegisterMessage("WN_ITEMS_UPDATED", function()
        if self.InvalidateItemCountCache then self:InvalidateItemCountCache() end
        if self.InvalidateItemSummary then
            local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
            self:InvalidateItemSummary(charKey)
        end
    end)
    
    -- Character cache event handlers registered (verbose logging removed)
end

---Clear tooltip item count cache (call when bags/bank change so next hover gets fresh data).
function WarbandNexus:InvalidateItemCountCache()
    for k in pairs(itemCountCache) do itemCountCache[k] = nil end
end

-- ============================================================================
-- COLLECTION CACHE COMPRESSION (For CollectionService)
-- ============================================================================

--[[
    Compress collection data for storage
    @param data table - Collection cache data
    @return string - Compressed and encoded string
]]
function WarbandNexus:CompressCollectionData(data)
    if not LibSerialize or not LibDeflate then
        self:Debug("LibSerialize or LibDeflate not available")
        return nil
    end
    
    if not data or type(data) ~= "table" then
        return nil
    end
    
    -- Serialize
    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        self:Debug("Failed to serialize collection data")
        return nil
    end
    
    -- Compress
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        self:Debug("Failed to compress collection data")
        return nil
    end
    
    -- Encode for storage
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        self:Debug("Failed to encode collection data")
        return nil
    end
    
    return encoded
end

--[[
    Decompress collection data from storage
    @param compressed string - Compressed and encoded string
    @return table - Decompressed collection cache data
]]
function WarbandNexus:DecompressCollectionData(compressed)
    if not LibSerialize or not LibDeflate then
        self:Debug("LibSerialize or LibDeflate not available")
        return nil
    end
    
    if not compressed or type(compressed) ~= "string" then
        return nil
    end
    
    -- Decode
    local decoded = LibDeflate:DecodeForPrint(compressed)
    if not decoded then
        self:Debug("Failed to decode collection data")
        return nil
    end
    
    -- Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        self:Debug("Failed to decompress collection data")
        return nil
    end
    
    -- Deserialize
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success or type(data) ~= "table" then
        return nil
    end
    
    return data
end

--[[
    Generic table decompression (wrapper for DecompressCollectionData)
    @param compressed string - Compressed and encoded string
    @return table - Decompressed data or nil
]]
function WarbandNexus:DecompressTable(compressed)
    return self:DecompressCollectionData(compressed)
end

--[[
    Generic table compression (wrapper for CompressCollectionData)
    @param data table - Data to compress
    @return string - Compressed and encoded string or nil
]]
function WarbandNexus:CompressTable(data)
    return self:CompressCollectionData(data)
end

--[[
    Get current cache version for validation
    @return string - Game version (build number)
]]
function WarbandNexus:GetCacheVersion()
    return select(4, GetBuildInfo())
end

--[[
    Check if cached data is valid for current game version
    @param savedVersion string - Saved cache version
    @return boolean - True if valid
]]
function WarbandNexus:IsCacheValid(savedVersion)
    local currentVersion = self:GetCacheVersion()
    return savedVersion == currentVersion
end

--[[
    Compress and save session cache to SavedVariables
    Called on PLAYER_LOGOUT
    @return boolean - Success status
]]
function WarbandNexus:CompressAndSave()
    if not LibSerialize or not LibDeflate then
        return false
    end
    
    -- Only compress if there's data to save
    if not sessionCache or type(sessionCache) ~= "table" or not next(sessionCache) then
        return true
    end
    
    local success, err = pcall(function()
        -- Serialize the cache
        local serialized = LibSerialize:Serialize(sessionCache)
        if not serialized then
            return false
        end
        
        -- Compress using LibDeflate
        local compressed = LibDeflate:CompressDeflate(serialized)
        if not compressed then
            return false
        end
        
        -- Encode for storage (ASCII safe)
        local encoded = LibDeflate:EncodeForPrint(compressed)
        if not encoded then
            return false
        end
        
        -- Store in SavedVariables
        self.db.global.sessionCache = {
            version = 1,
            data = encoded,
            timestamp = time(),
        }
        
        return true
    end)
    
    if not success then
        if self.db.profile.debugMode then
            self:Print("|cffff0000SessionCache save error:|r " .. tostring(err))
        end
        return false
    end
    
    return true
end

--[[
    Decompress and load session cache from SavedVariables
    Called on ADDON_LOADED
    @return boolean - Success status
]]
function WarbandNexus:DecompressAndLoad()
    if not LibSerialize or not LibDeflate then
        -- Initialize empty cache if libraries not available
        self:InitializeSessionCache()
        return false
    end
    
    -- Check if saved cache exists
    if not self.db.global.sessionCache or not self.db.global.sessionCache.data then
        -- Initialize empty cache
        self:InitializeSessionCache()
        return true
    end
    
    local success, err = pcall(function()
        local stored = self.db.global.sessionCache
        
        -- Decode from ASCII
        local decoded = LibDeflate:DecodeForPrint(stored.data)
        if not decoded then
            return false
        end
        
        -- Decompress
        local decompressed = LibDeflate:DecompressDeflate(decoded)
        if not decompressed then
            return false
        end
        
        -- Deserialize
        local success2, deserialized = LibSerialize:Deserialize(decompressed)
        if not success2 then
            return false
        end
        
        -- Load into session cache
        sessionCache = deserialized
        
        return true
    end)
    
    if not success then
        if self.db.profile.debugMode then
            self:Print("|cffff0000SessionCache load error:|r " .. tostring(err))
        end
        -- Initialize empty cache on error
        self:InitializeSessionCache()
        return false
    end
    
    return true
end

-- ============================================================================
-- CHARACTER DATA COLLECTION
-- ============================================================================

--[[
    Collect basic profession data
    @return table - Profession data
]]
function WarbandNexus:CollectProfessionData()
    -- GUARD: Only collect if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return nil
    end
    
    local success, result = pcall(function()
        local professions = {}
        
        -- GetProfessions returns indices for the profession UI
        local prof1, prof2, _arch, fish, cook = GetProfessions()
        
        local function getProfData(index)
            if not index then return nil end
            -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specializationIndex, specializationOffset
            local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            
            if not name then return nil end
            
            return {
                name = name,
                icon = icon,
                rank = rank,
                maxRank = maxRank,
                skill = rank,
                maxSkill = maxRank,
                skillLine = skillLine,
                index = index
            }
        end

        if prof1 then professions[1] = getProfData(prof1) end
        if prof2 then professions[2] = getProfData(prof2) end
        if cook then professions.cooking = getProfData(cook) end
        if fish then professions.fishing = getProfData(fish) end
        -- Archaeology removed: deprecated since Dragonflight, no longer relevant
        
        return professions
    end)
    
    if not success then
        return {}
    end
    
    return result
end


--[[
    Save minimal character data for UNTRACKED characters
    Only collects: name, realm, class, race, faction, level, ilvl, gold
    NO items, reputation, currency, pve, professions, etc.
    @return boolean - Success status
]]
function WarbandNexus:SaveMinimalCharacterData()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()
    
    if not name or name == "" or not realm or realm == "" then
        return false
    end
    
    local key = name .. "-" .. realm
    local Constants = ns.Constants
    
    -- Get basic character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    local totalCopper = math.floor(GetMoney())
    local faction = UnitFactionGroup("player")
    local race, raceFile = UnitRace("player")
    
    -- Get gender
    local gender = UnitSex("player")
    local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
    if raceInfo and raceInfo.gender ~= nil then
        gender = (raceInfo.gender == 1) and 3 or 2
    end
    if not gender or gender == 0 or gender == 1 then
        gender = 2
    end
    
    -- Get item level
    local _, avgItemLevelEquipped = GetAverageItemLevel()
    local itemLevel = avgItemLevelEquipped or 0
    
    -- Validate critical data
    if not classFile or not level or level == 0 then
        return false
    end
    
    -- Initialize characters table
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    -- Convert totalCopper to gold/silver/copper (for compatibility)
    local gold = math.floor(totalCopper / 10000)
    local remainingCopper = totalCopper % 10000
    local silver = math.floor(remainingCopper / 100)
    local copper = remainingCopper % 100
    
    -- CRITICAL: Preserve existing tracking flags from the character entry.
    -- SaveMinimalCharacterData can run BEFORE the tracking confirmation popup
    -- is shown (race condition: SaveCharacter at 2s vs popup at 2.5s).
    -- If we overwrite trackingConfirmed here, the popup will never appear.
    local existingEntry = self.db.global.characters[key]
    local preserveTracked = existingEntry and existingEntry.isTracked
    local preserveConfirmed = existingEntry and existingEntry.trackingConfirmed
    local preserveTimePlayed = existingEntry and existingEntry.timePlayed
    local preserveMythicKey = existingEntry and existingEntry.mythicKey  -- Preserve keystone data for CharactersUI display
    
    -- Preserve profession service data (collected separately by ProfessionService)
    local preserveProfessions          = existingEntry and existingEntry.professions  -- CRITICAL FIX: Don't lose profession data on untracked save
    local preserveConcentration       = existingEntry and existingEntry.concentration
    local preserveRecipes             = existingEntry and existingEntry.recipes
    local preserveProfExpansions      = existingEntry and existingEntry.professionExpansions
    local preserveDiscoveredSkillLines = existingEntry and existingEntry.discoveredSkillLines
    local preserveKnowledgeData       = existingEntry and existingEntry.knowledgeData
    
    -- Store MINIMAL data only
    self.db.global.characters[key] = {
        name = name,
        realm = realm,
        class = className,
        classFile = classFile,
        classID = classID,
        level = level,
        gold = gold,
        silver = silver,
        copper = copper,
        faction = faction,
        race = race,
        raceFile = raceFile,
        gender = gender,
        itemLevel = itemLevel,
        isTracked = preserveTracked or false,  -- Preserve existing tracking choice
        trackingConfirmed = preserveConfirmed or false,  -- ONLY true if user actually made a choice
        lastSeen = time(),
        mythicKey = preserveMythicKey,  -- Preserve keystone data for CharactersUI display
        timePlayed = preserveTimePlayed,  -- Preserve played time (updated separately by TIME_PLAYED_MSG)
        -- Preserve profession service data (CRITICAL: include professions to prevent data loss)
        professions          = preserveProfessions,  -- Profession names, icons, skill levels
        concentration        = preserveConcentration,
        recipes              = preserveRecipes,
        professionExpansions = preserveProfExpansions,
        discoveredSkillLines = preserveDiscoveredSkillLines,
        knowledgeData        = preserveKnowledgeData,
    }
    
    -- Fire event for UI refresh
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = key,
        isTracked = false
    })
    
    return true
end

--[[
    Save complete character data
    Called on login/reload and when significant changes occur
    v2: No longer stores currencies/reputations per character (stored globally)
    @return boolean - Success status
]]
function WarbandNexus:SaveCurrentCharacterData()
    -- Check tracking status
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    
    -- If NOT tracked, save minimal data only
    if not isTracked then
        return self:SaveMinimalCharacterData()
    end
    
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()  -- CRITICAL: Get realm name
    
    -- Safety check
    if not name or name == "" or name == "Unknown" then
        return false
    end
    if not realm or realm == "" then
        return false
    end
    
    local key = name .. "-" .. realm
    
    -- Get character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    
    -- CRITICAL: Store as single totalCopper (Lua number = 64-bit)
    -- Per documentation: GetMoney() returns copper directly
    -- FLOOR to ensure integer (prevent float overflow in texture rendering)
    local totalCopper = math.floor(GetMoney())
    
    
    local faction = UnitFactionGroup("player")
    local race, raceFile = UnitRace("player")  -- race = localized name, raceFile = English ID
    
    -- Get gender with C_PlayerInfo fallback (more reliable in TWW)
    local gender = UnitSex("player")  -- 2 = male, 3 = female, 1 = neutral/unknown
    
    -- CRITICAL FIX: Use C_PlayerInfo if available (more reliable)
    local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
    if raceInfo and raceInfo.gender ~= nil then
        -- C_PlayerInfo returns: 0 = male, 1 = female
        -- Convert to UnitSex format: 2 = male, 3 = female
        gender = (raceInfo.gender == 1) and 3 or 2
    end
    
    -- Fallback to male if still unknown
    if not gender or gender == 0 or gender == 1 then
        gender = 2  -- Default to male
    end
    
    -- Validate we have critical info
    if not classFile or not level or level == 0 then
        self:Print(string.format("|cffff0000[SaveChar] FAILED: Missing critical data (class=%s, level=%s)|r", 
            tostring(classFile or "nil"), 
            tostring(level or "0")))
        return false
    end
    
    -- Initialize characters table if needed
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    -- Check if new character
    local isNew = (self.db.global.characters[key] == nil)
    
    -- Collect PvE data (Great Vault, Lockouts, M+)
    local pveData = self:CollectPvEData()
    
    -- Collect Profession data (only if new character or professions don't exist)
    local professionData = nil
    if isNew or not self.db.global.characters[key] or not self.db.global.characters[key].professions then
        professionData = self:CollectProfessionData()
    else
        -- Preserve existing profession data (will be updated by SKILL_LINES_CHANGED event if needed)
        professionData = self.db.global.characters[key].professions
    end
    
    -- Get character's average item level (ALWAYS fresh from API)
    local _, avgItemLevelEquipped = GetAverageItemLevel()
    local itemLevel = avgItemLevelEquipped or 0
    
    -- Scan for Mythic Keystone (always scan on login to check if key exists)
    local keystoneData = nil
    if self.ScanMythicKeystone then
        keystoneData = self:ScanMythicKeystone()
    end
    
    -- Copy personal bank data to global (for cross-character search and storage browser)
    local personalBank = nil
    if self.db.char.personalBank and self.db.char.personalBank.items then
        personalBank = {}
        for bagIndex, bagData in pairs(self.db.char.personalBank.items) do
            personalBank[bagIndex] = {}
            for slotID, item in pairs(bagData) do
                -- Deep copy all item fields
                personalBank[bagIndex][slotID] = {
                    itemID = item.itemID,
                    itemLink = item.itemLink,
                    stackCount = item.stackCount,
                    quality = item.quality,
                    iconFileID = item.iconFileID,
                    name = item.name,
                    itemLevel = item.itemLevel,
                    itemType = item.itemType,
                    itemSubType = item.itemSubType,
                    classID = item.classID,
                    subclassID = item.subclassID,
                    actualBagID = item.actualBagID,  -- Store bag ID for location display
                }
            end
        end
    end
    
    -- Copy character bags data to global (for tooltip and storage browser)
    local bagsData = nil
    if self.db.char.bags and self.db.char.bags.items then
        bagsData = {}
        for bagIndex, bagData in pairs(self.db.char.bags.items) do
            bagsData[bagIndex] = {}
            for slotID, item in pairs(bagData) do
                -- Deep copy all item fields
                bagsData[bagIndex][slotID] = {
                    itemID = item.itemID,
                    itemLink = item.itemLink,
                    stackCount = item.stackCount,
                    quality = item.quality,
                    iconFileID = item.iconFileID,
                    name = item.name,
                    itemLevel = item.itemLevel,
                    itemType = item.itemType,
                    itemSubType = item.itemSubType,
                    classID = item.classID,
                    subclassID = item.subclassID,
                    actualBagID = item.actualBagID,  -- Store bag ID for location display
                }
            end
        end
    end
    
    -- CRITICAL: WoW SavedVariables uses 32-bit integers (max: 2,147,483,647)
    -- totalCopper can exceed this for high-gold characters (>214k gold)
    -- Solution: Store as gold/silver/copper breakdown (smaller numbers)
    local gold = math.floor(totalCopper / 10000)
    local silver = math.floor((totalCopper % 10000) / 100)
    local copper = math.floor(totalCopper % 100)
    
    -- CRITICAL: Preserve trackingConfirmed flag from existing entry.
    -- This flag is set by ConfirmCharacterTracking() when user makes a choice.
    -- Without preserving it, every save would lose the user's tracking confirmation.
    local existingEntry = self.db.global.characters[key]
    local preserveConfirmed = existingEntry and existingEntry.trackingConfirmed
    local preserveTimePlayed = existingEntry and existingEntry.timePlayed
    
    -- Preserve profession service data (collected separately by ProfessionService)
    local preserveConcentration       = existingEntry and existingEntry.concentration
    local preserveRecipes             = existingEntry and existingEntry.recipes
    local preserveProfExpansions      = existingEntry and existingEntry.professionExpansions
    local preserveDiscoveredSkillLines = existingEntry and existingEntry.discoveredSkillLines
    local preserveKnowledgeData       = existingEntry and existingEntry.knowledgeData
    
    self.db.global.characters[key] = {
        name = name,
        realm = realm,
        class = className,
        classFile = classFile,
        classID = classID,
        level = level,
        gold = gold,          -- Stored separately to avoid 32-bit overflow
        silver = silver,
        copper = copper,
        faction = faction,
        race = race,
        raceFile = raceFile,
        gender = gender,
        itemLevel = itemLevel,
        mythicKey = keystoneData,
        isTracked = true,     -- Track this character (API calls, data updates enabled)
        trackingConfirmed = preserveConfirmed or true,  -- Preserve existing, default true for tracked chars
        lastSeen = time(),
        professions = professionData,
        bags = bagsData,      -- Character inventory bags (for Storage tab and tooltip)
        timePlayed = preserveTimePlayed,  -- Preserve played time (updated separately by TIME_PLAYED_MSG)
        -- Preserve profession service data
        concentration        = preserveConcentration,
        recipes              = preserveRecipes,
        professionExpansions = preserveProfExpansions,
        discoveredSkillLines = preserveDiscoveredSkillLines,
        knowledgeData        = preserveKnowledgeData,
    }
    
    
    -- ========== V2: Store PvE data globally ==========
    self:UpdatePvEDataV2(key, pveData)
    
    -- ========== V2: Store Personal Bank globally (compressed) ==========
    self:UpdatePersonalBankV2(key, personalBank)
    
    -- Update currencies to global storage (v2)
    self:UpdateCurrencyData()
    
    -- Fire event for UI refresh (DB-First pattern)
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = key,
        isNew = isNew
    })
    
    return true
end

--[[
    Update only profession data (lightweight — names, icons, skill levels)
]]
function WarbandNexus:UpdateProfessionData()
    local success, err = pcall(function()
        local key = ns.Utilities:GetCharacterKey()
        if not self.db.global.characters or not self.db.global.characters[key] then return end

        local newData = self:CollectProfessionData()

        -- Guard: Don't overwrite saved DB data with empty results.
        -- GetProfessions() can return nil on login before the profession system is
        -- fully loaded, which would destroy the previous session's saved data.
        -- Only overwrite if new data has at least one profession entry.
        if not newData or not next(newData) then return end

        self.db.global.characters[key].professions = newData
        self.db.global.characters[key].lastSeen = time()

        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = key,
            dataType = "professions"
        })
    end)
end

--[[
    Update only gold for current character (lightweight, called on PLAYER_MONEY)
    Works for BOTH tracked and untracked characters (gold is part of minimal data)
    @return boolean - Success status
]]
function WarbandNexus:UpdateCharacterGold()
    -- No tracking guard here - gold updates for both tracked and untracked characters
    
    local key = ns.Utilities:GetCharacterKey()
    
    if self.db.global.characters and self.db.global.characters[key] then
        local totalCopper = math.floor(GetMoney())
        
        -- Store as breakdown to avoid SavedVariables 32-bit overflow
        local gold = math.floor(totalCopper / 10000)
        local silver = math.floor((totalCopper % 10000) / 100)
        local copper = math.floor(totalCopper % 100)
        
        self.db.global.characters[key].gold = gold
        self.db.global.characters[key].silver = silver
        self.db.global.characters[key].copper = copper
        
        self.db.global.characters[key].lastSeen = time()
        
        -- Fire event for UI refresh (DB-First pattern)
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = key,
            dataType = "gold"
        })
        
        return true
    end
    
    return false
end

--[[
    Get all characters (tracked AND untracked) (DB-First pattern)
    Direct DB access, no RAM cache
    Returns both tracked and untracked characters - UI modules should filter as needed
    @return table - Array of character data sorted by level then name
]]
function WarbandNexus:GetAllCharacters()
    local characters = {}
    
    if not self.db.global.characters then
        return characters
    end
    
    -- CRITICAL: Deduplicate characters (keep newest by lastSeen)
    local seen = {}  -- [normalizedKey] = {charData, originalKey}
    
    for key, data in pairs(self.db.global.characters) do
        -- Filter: Skip invalid entries only (no name/realm)
        -- Include BOTH tracked AND untracked characters (UI will separate them)
        if data.name and data.realm and data.name ~= "" and data.realm ~= "" then
            -- Normalize key for duplicate detection (remove spaces, lowercase)
            local normalizedName = (data.name or ""):gsub("%s+", ""):lower()
            local normalizedRealm = (data.realm or ""):gsub("%s+", ""):lower()
            local normalizedKey = normalizedName .. "-" .. normalizedRealm
            
            if seen[normalizedKey] then
                -- Duplicate found! Keep the one with newest lastSeen
                local existingData = seen[normalizedKey]
                local existingTime = existingData.lastSeen or 0
                local newTime = data.lastSeen or 0
                
                if newTime > existingTime then
                    -- Current one is newer, replace
                    data._key = key
                    seen[normalizedKey] = data
                end
                -- else: existing one is newer, keep it
            else
                -- First occurrence of this character
                data._key = key
                seen[normalizedKey] = data
            end
        end
    end
    
    -- Convert seen map to array
    for _, data in pairs(seen) do
        table.insert(characters, data)
    end
    
    -- Sort by level (highest first), then by name
    table.sort(characters, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then
            return (a.level or 0) > (b.level or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    
    return characters
end

-- REMOVED: GetCachedCharacters (DB-First pattern - no cache, use GetAllCharacters directly)
-- REMOVED: InvalidateCharacterCache (DB-First pattern - no cache to invalidate)

--[[
    Get characters logged in within the last X days
    Used for Weekly Planner feature
    @param days number - Number of days to look back (default 3)
    @return table - Array of recently active characters
]]
function WarbandNexus:GetRecentCharacters(days)
    days = days or 3
    local cutoff = time() - (days * 86400)
    local recent = {}
    
    if not self.db.global.characters then
        return recent
    end
    
    for key, char in pairs(self.db.global.characters) do
        -- Filter: Skip untracked characters (only show explicitly tracked)
        if char.isTracked == true and char.lastSeen and char.lastSeen >= cutoff then
            char._key = key  -- Include key for reference
            table.insert(recent, char)
        end
    end
    
    -- Sort by lastSeen (most recent first)
    table.sort(recent, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    
    return recent
end

--[[
    Generate weekly planner alerts for recently active characters
    Checks: Great Vault, Knowledge Points, Reputation Milestones, M+ Keys
    @return table - Array of alert objects sorted by priority
]]
function WarbandNexus:GenerateWeeklyAlerts()
    local alerts = {}
    local days = (self.db and self.db.profile and self.db.profile.weeklyPlannerDays) or 3
    local recentChars = self:GetRecentCharacters(days)
    
    if not recentChars then return alerts end
    
    for _, char in ipairs(recentChars) do
        local charKey = char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
        local charName = char.name or "Unknown"
        
        -- Safely get class color
        local classColor = { r = 1, g = 1, b = 1 }
        if char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile] then
            classColor = RAID_CLASS_COLORS[char.classFile]
        end
        local coloredName = string.format("|cff%02x%02x%02x%s|r", 
            (classColor.r or 1) * 255, (classColor.g or 1) * 255, (classColor.b or 1) * 255, charName)
        
        -- ===== CHECK GREAT VAULT =====
        local pveData = self.GetCachedPvEData and self:GetCachedPvEData(charKey)
        if pveData and pveData.greatVault then
            local filledSlots = 0
            local totalSlots = 0
            
            for _, activity in ipairs(pveData.greatVault) do
                if activity.progress then
                    for _, slot in ipairs(activity.progress) do
                        totalSlots = totalSlots + 1
                        if slot.progress and slot.threshold and slot.progress >= slot.threshold then
                            filledSlots = filledSlots + 1
                        end
                    end
                end
            end
            
            -- Alert if less than 3 slots filled (assuming 3 per row, 9 total)
            local slotsToFill = math.max(0, 3 - filledSlots)
            if slotsToFill > 0 and filledSlots < 9 then
                table.insert(alerts, {
                    type = "vault",
                    icon = "Interface\\Icons\\Achievement_Dungeon_GlsoDungeon_Heroic",
                    character = coloredName,
                    charKey = charKey,
                    message = slotsToFill .. " Great Vault slot" .. (slotsToFill > 1 and "s" or "") .. " to fill",
                    priority = 1,
                })
            end
        end
        
        -- ===== CHECK REPUTATION MILESTONES (within 500 of next level) =====
        local reps = self.db.global.reputations
        if reps then
            for factionID, repData in pairs(reps) do
                if repData.chars and repData.chars[charKey] then
                    local charRep = repData.chars[charKey]
                    local repToNext = 0
                    local nextLevel = nil
                    
                    -- Check renown progress
                    if charRep.renownLevel and charRep.renownProgress and charRep.renownThreshold then
                        repToNext = (charRep.renownThreshold or 0) - (charRep.renownProgress or 0)
                        if repToNext > 0 and repToNext <= 500 then
                            nextLevel = "Renown " .. ((charRep.renownLevel or 0) + 1)
                        end
                    end
                    
                    -- Check classic reputation progress
                    if not nextLevel and charRep.currentRep and charRep.nextThreshold then
                        repToNext = (charRep.nextThreshold or 0) - (charRep.currentRep or 0)
                        if repToNext > 0 and repToNext <= 500 then
                            -- Get next standing name
                            local standings = {"Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"}
                            local currentStanding = charRep.standingID or 4
                            if currentStanding < 8 then
                                nextLevel = standings[currentStanding + 1]
                            end
                        end
                    end
                    
                    if nextLevel and repToNext > 0 then
                        table.insert(alerts, {
                            type = "reputation",
                            icon = repData.icon or "Interface\\Icons\\Achievement_Reputation_01",
                            character = coloredName,
                            charKey = charKey,
                            message = repToNext .. " rep to " .. nextLevel .. " (" .. (repData.name or "Faction") .. ")",
                            priority = 3,
                        })
                    end
                end
            end
        end
        
        -- ===== CHECK M+ KEYSTONE =====
        if pveData and pveData.mythicPlus and pveData.mythicPlus.keystone then
            local ks = pveData.mythicPlus.keystone
            if ks.mapID and ks.level then
                -- Has a key - could add logic to check if run this week
                -- For now, just note they have a key available
                -- We'll skip this alert to avoid noise, but structure is here for future
            end
        end
    end
    
    -- Sort by priority (lower = more important)
    if #alerts > 0 then
        table.sort(alerts, function(a, b)
            if (a.priority or 99) ~= (b.priority or 99) then
                return (a.priority or 99) < (b.priority or 99)
            end
            return (a.character or "") < (b.character or "")
        end)
    end
    
    return alerts
end

-- ============================================================================
-- PVE LOADING STATE HELPERS
-- ============================================================================

--[[
    Update PvE loading state and refresh UI
    @param state table - State updates {isLoading, loadingProgress, attempts, etc.}
]]
function WarbandNexus:UpdatePvELoadingState(state)
    if not state then return end
    
    -- Update state fields
    for k, v in pairs(state) do
        ns.PvELoadingState[k] = v
    end
    
    -- Fire event for UI update
    if self.SendMessage then
        self:SendMessage("WARBAND_PVE_UPDATED")
    end
end

--[[
    Cancel ongoing PvE data collection
    Called when user switches tabs or logs out
]]
function WarbandNexus:CancelPvECollection()
    ns.PvELoadingState.cancelled = true
    
    -- Cancel all active coroutines
    for _, co in pairs(activeCoroutines) do
        if coroutine.status(co) ~= "dead" then
            -- Coroutines will check cancelled flag on next yield
        end
    end
    wipe(activeCoroutines)
    
    -- Update loading state
    self:UpdatePvELoadingState({
        isLoading = false,
        attempts = 0,
        loadingProgress = 0,
        currentStage = nil,
    })
end

--[[
    Execute coroutine across multiple frames to prevent FPS drops
    Yields between expensive operations
    @param co coroutine - Coroutine to execute
    @param callback function - Callback when complete (receives result)
    @param errorCallback function - Callback on error
]]
function WarbandNexus:ExecuteCoroutineAsync(co, callback, errorCallback)
    local function resume()
        -- Check if cancelled
        if ns.PvELoadingState.cancelled then
            if errorCallback then
                errorCallback("Collection cancelled by user")
            end
            return
        end
        
        -- Check if coroutine finished
        if coroutine.status(co) == "dead" then
            return
        end
        
        -- Resume coroutine
        local success, result = coroutine.resume(co)
        
        if not success then
            -- Error occurred
            if errorCallback then
                errorCallback(result)
            else
                -- Coroutine error logged silently
            end
            return
        end
        
        -- Check if coroutine returned (finished)
        if coroutine.status(co) == "dead" then
            if callback then
                callback(result)
            end
            return
        end
        
        -- Schedule next frame (0 delay = next frame)
        C_Timer.After(0, resume)
    end
    
    -- Start execution
    resume()
end

-- ============================================================================
-- PVE DATA VALIDATION
-- ============================================================================

--[[
    Validate PvE data completeness
    Checks if critical fields are missing (indicates API not ready)
    @param pve table - PvE data to validate
    @return boolean - True if complete, false if missing data
]]
local function ValidatePvEDataCompleteness(pve)
    if not pve then
        return false
    end
    
    local hasMissingData = false
    
    -- Validate Great Vault data
    if pve.greatVault and #pve.greatVault > 0 then
        for _, activity in ipairs(pve.greatVault) do
            -- Check completed slots
            if activity.progress and activity.threshold and activity.progress >= activity.threshold then
                -- Completed slot should have reward ilvl
                if not activity.rewardItemLevel or activity.rewardItemLevel == 0 then
                    hasMissingData = true
                    break
                end
                
                -- Non-max slots should have upgrade info (unless at max already)
                local level = activity.level or 0
                local isAtMax = false
                
                -- Determine if at max based on activity type
                if activity.type == 1 then -- M+
                    isAtMax = (level >= 10)
                elseif activity.type == 6 then -- World/Delves
                    isAtMax = (level >= 8)
                elseif activity.type == 3 then -- Raid
                    isAtMax = (level >= 16) -- Mythic
                end
                
                -- If not at max, should have upgrade info
                if not isAtMax then
                    if not activity.nextLevelIlvl or not activity.maxIlvl then
                        hasMissingData = true
                        break
                    end
                end
            end
        end
    end
    
    -- Validate M+ scores (if there are dungeons, should have overall score)
    if pve.mythicPlus then
        local overallScore = pve.mythicPlus.overallScore or 0
        local dungeonCount = pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons or 0
        
        -- If we have dungeon data but no overall score, data is incomplete
        if dungeonCount > 0 and overallScore == 0 then
            hasMissingData = true
        end
    end
    
    return not hasMissingData
end

-- ============================================================================
-- PVE DATA COLLECTION
-- ============================================================================

--[[
    Collect comprehensive PvE data (Great Vault, Lockouts, M+)
    @return table - PvE data structure
]]
---Collect PvE data (Phase 2: DEPRECATED - Routes to PvECacheService)
---@return table|nil PvE data
function WarbandNexus:CollectPvEData()
    -- GUARD: Only collect if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return nil
    end
    
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("pve") then
        return nil
    end
    
    -- Phase 2: Route to PvECacheService (preferred)
    if self.UpdatePvEData and self.GetPvEData then
        self:UpdatePvEData()
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        return self:GetPvEData(charKey)
    end
    
    -- Legacy fallback (Phase 3: will be removed)
    local success, result = pcall(function()
    local pve = {
        greatVault = {},
        lockouts = {},
        mythicPlus = {},
    }
    
    -- ===== GREAT VAULT PROGRESS =====
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        if activities then
            for _, activity in ipairs(activities) do
                local activityData = {
                    type = activity.type,
                    index = activity.index,
                    progress = activity.progress,
                    threshold = activity.threshold,
                    level = activity.level,
                }
                
                -- Method 1: Check activity.rewards array (most direct)
                if activity.rewards and #activity.rewards > 0 then
                    local reward = activity.rewards[1]
                    if reward then
                        -- Check for itemLevel field
                        if reward.itemLevel and reward.itemLevel > 0 then
                            activityData.rewardItemLevel = reward.itemLevel
                        end
                        -- Check for itemDBID to get hyperlink
                        if not activityData.rewardItemLevel and reward.itemDBID and C_WeeklyRewards.GetItemHyperlink then
                            local hyperlink = C_WeeklyRewards.GetItemHyperlink(reward.itemDBID)
                            if hyperlink and GetDetailedItemLevelInfo then
                                local ilvl = GetDetailedItemLevelInfo(hyperlink)
                                if ilvl and ilvl > 0 then
                                    activityData.rewardItemLevel = ilvl
                                end
                            end
                        end
                    end
                end
                
                -- Method 2: Use GetExampleRewardItemHyperlinks(id) - id is activity.id
                if activity.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                    local hyperlink, upgradeHyperlink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                    
                    -- Get current reward item level from hyperlink
                    if hyperlink and not activityData.rewardItemLevel then
                        if GetDetailedItemLevelInfo then
                            local ilvl = GetDetailedItemLevelInfo(hyperlink)
                            if ilvl and ilvl > 0 then
                                activityData.rewardItemLevel = ilvl
                            end
                        end
                    end
                    
                    -- Get UPGRADE reward item level from upgradeHyperlink
                    if upgradeHyperlink then
                        if GetDetailedItemLevelInfo then
                            local upgradeIlvl = GetDetailedItemLevelInfo(upgradeHyperlink)
                            if upgradeIlvl and upgradeIlvl > 0 then
                                activityData.upgradeItemLevel = upgradeIlvl
                            end
                        end
                    end
                end
                
                -- Determine activity type name
                local activityTypeName = nil
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                        activityTypeName = "M+"
                    elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                        activityTypeName = "World"
                    elseif activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                        activityTypeName = "Raid"
                    end
                else
                    if activity.type == 1 then activityTypeName = "M+"
                    elseif activity.type == 6 then activityTypeName = "World"
                    elseif activity.type == 3 then activityTypeName = "Raid"
                    end
                end
                
                local currentLevel = activity.level or 0
                
                -- M+: Use GetNextMythicPlusIncrease
                if activityTypeName == "M+" and C_WeeklyRewards.GetNextMythicPlusIncrease then
                    local hasData, nextLevel, nextIlvl = C_WeeklyRewards.GetNextMythicPlusIncrease(currentLevel)
                    if hasData and nextLevel then
                        activityData.nextLevel = nextLevel
                        activityData.nextLevelIlvl = nextIlvl
                    end
                    -- Get max M+ info (level 10)
                    local hasMax, maxLevel, maxIlvl = C_WeeklyRewards.GetNextMythicPlusIncrease(9)
                    if hasMax then
                        activityData.maxLevel = 10
                        activityData.maxIlvl = maxIlvl
                    end
                end
                
                -- World/Delves: Use GetNextActivitiesIncrease with activity.id as activityTierID
                if activityTypeName == "World" then
                    -- Set next level (current + 1)
                    activityData.nextLevel = currentLevel + 1
                    activityData.maxLevel = 8 -- Tier 8 is max
                    
                    -- Fallback for rewardItemLevel if not obtained from API
                    -- TWW Season 1: Tier 1 = ~584, each tier adds ~3 iLvL
                    if not activityData.rewardItemLevel and currentLevel > 0 then
                        local baseIlvl = 584  -- Tier 1 base item level
                        activityData.rewardItemLevel = baseIlvl + ((currentLevel - 1) * 3)
                    end
                    
                    -- Try API first
                    if C_WeeklyRewards.GetNextActivitiesIncrease and activity.id then
                        local hasData, nextTierID, nextLevel, nextIlvl = C_WeeklyRewards.GetNextActivitiesIncrease(activity.id, currentLevel)
                        if hasData and nextIlvl then
                            activityData.nextLevelIlvl = nextIlvl
                        end
                        -- Get max World info (Tier 8)
                        local hasMax, maxTierID, maxLevel, maxIlvl = C_WeeklyRewards.GetNextActivitiesIncrease(activity.id, 7)
                        if hasMax and maxIlvl then
                            activityData.maxIlvl = maxIlvl
                        end
                    end
                    
                    -- Fallback for next tier: Use upgradeItemLevel from hyperlink
                    if not activityData.nextLevelIlvl and activityData.upgradeItemLevel then
                        activityData.nextLevelIlvl = activityData.upgradeItemLevel
                    end
                    
                    -- Fallback: Calculate nextLevelIlvl from current + 3
                    if not activityData.nextLevelIlvl and activityData.rewardItemLevel then
                        activityData.nextLevelIlvl = activityData.rewardItemLevel + 3
                    end
                    
                    -- Fallback for max tier: Calculate from current + tier difference
                    -- Each Delve tier adds approximately 3 item levels
                    if not activityData.maxIlvl and activityData.rewardItemLevel then
                        local tierDiff = 8 - currentLevel
                        activityData.maxIlvl = activityData.rewardItemLevel + (tierDiff * 3)
                    end
                end
                
                -- Raid: Difficulty progression
                if activityTypeName == "Raid" then
                    local difficultyOrder = { 17, 14, 15, 16 } -- LFR → Normal → Heroic → Mythic
                    for i, diff in ipairs(difficultyOrder) do
                        if diff == currentLevel and i < #difficultyOrder then
                            activityData.nextLevel = difficultyOrder[i + 1]
                            break
                        end
                    end
                    activityData.maxLevel = 16 -- Mythic
                    
                    -- Get item levels from hyperlinks or use available data
                    if not activityData.nextLevelIlvl and activityData.upgradeItemLevel then
                        activityData.nextLevelIlvl = activityData.upgradeItemLevel
                    end
                    if not activityData.maxIlvl then
                        activityData.maxIlvl = activityData.upgradeItemLevel or activityData.rewardItemLevel
                    end
                end
                
                table.insert(pve.greatVault, activityData)
            end
        end
    end
    
    -- ===== CHECK FOR UNCLAIMED VAULT REWARDS =====
    -- This checks if the player has rewards waiting from LAST week (not current progress)
    -- NOTE: This data is only accurate when you're logged in as that character
    -- The indicator will update automatically when you claim vault rewards (via WEEKLY_REWARDS_UPDATE event)
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        pve.hasUnclaimedRewards = C_WeeklyRewards.HasAvailableRewards()
    else
        pve.hasUnclaimedRewards = false
    end
    
    -- ===== RAID/INSTANCE LOCKOUTS =====
    if GetNumSavedInstances then
        local numSaved = GetNumSavedInstances()
        for i = 1, numSaved do
            local instanceName, lockoutID, resetTime, difficultyID, locked, extended, 
                  instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, 
                  encounterProgress, extendDisabled, instanceID = GetSavedInstanceInfo(i)
            
            if locked or extended then
                table.insert(pve.lockouts, {
                    name = instanceName,
                    id = lockoutID,
                    reset = resetTime,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    isRaid = isRaid,
                    maxPlayers = maxPlayers,
                    progress = encounterProgress,
                    total = numEncounters,
                    extended = extended,
                })
            end
        end
    end
    
    -- ===== MYTHIC+ DATA =====
    if C_MythicPlus then
        -- Current keystone - scan player's bags for keystone item
        local keystoneMapID, keystoneLevel, keystoneName
        for bagID = 0, NUM_BAG_SLOTS do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        -- Keystone items have ID 180653 (Mythic Keystone base)
                        -- But actual keystones have different IDs per dungeon
                        local itemName, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemInfo.itemID)
                        if itemName and itemName:find("Keystone") then
                            -- Get keystone level from item link
                            local itemLink = itemInfo.hyperlink
                            if itemLink then
                                -- Extract level from link (format: [Keystone: Dungeon Name +15])
                                keystoneLevel = itemLink:match("%+(%d+)")
                                if keystoneLevel then
                                    keystoneLevel = tonumber(keystoneLevel)
                                    keystoneName = itemName:match("Keystone:%s*(.+)") or itemName
                                    keystoneMapID = itemInfo.itemID
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if keystoneMapID and keystoneLevel then
            pve.mythicPlus.keystone = {
                mapID = keystoneMapID,
                name = keystoneName,
                level = keystoneLevel,
            }
        end
        
        -- Run history this week
        if C_MythicPlus.GetRunHistory then
            local includeIncomplete = false
            local includePreviousWeeks = false
            local runs = C_MythicPlus.GetRunHistory(includeIncomplete, includePreviousWeeks)
            if runs then
                pve.mythicPlus.runsThisWeek = #runs
                -- Get highest run level for weekly best
                local bestLevel = 0
                for _, run in ipairs(runs) do
                    if run.level and run.level > bestLevel then
                        bestLevel = run.level
                    end
                end
                if bestLevel > 0 then
                    pve.mythicPlus.weeklyBest = bestLevel
                end
            else
                pve.mythicPlus.runsThisWeek = 0
            end
        end
        
        -- ===== MYTHIC+ DUNGEON PROGRESS =====
        if C_ChallengeMode then
            pve.mythicPlus.dungeons = {}
            local overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
            pve.mythicPlus.overallScore = overallScore
            
            -- Get all map scores (returns indexed table with mapChallengeModeID keys)
            local allScores = C_ChallengeMode.GetMapScoreInfo() or {}
            
            -- Create lookup table by mapChallengeModeID
            local scoresByMapID = {}
            for _, scoreData in ipairs(allScores) do
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            local mapTable = C_ChallengeMode.GetMapTable()
            if mapTable then
                for _, mapID in ipairs(mapTable) do
                    local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if name then
                        local bestLevel = 0
                        local bestScore = 0
                        local isCompleted = false
                        
                        -- Lookup score data for this mapID
                        local scoreData = scoresByMapID[mapID]
                        if scoreData then
                            bestLevel = scoreData.level or 0
                            bestScore = scoreData.dungeonScore or 0
                            isCompleted = (scoreData.completedInTime == 1) or false
                        end
                        
                        -- Insert dungeon regardless of completion status
                        table.insert(pve.mythicPlus.dungeons, {
                            mapID = mapID,
                            name = name,
                            texture = texture,
                            bestLevel = bestLevel,
                            score = bestScore,
                            completed = isCompleted,
                        })
                    end
                end
            end
        end
    end
    
    return pve
    end)
    
    if not success then
        return {
            greatVault = {},
            lockouts = {},
            mythicPlus = {},
        }
    end
    
    return result
end

--[[
    Collect PvE data with retry logic and loading state updates
    Automatically retries up to 3 times if data is incomplete
    Updates loading state for UI feedback
    @param charKey string - Character key (name-realm)
    @param attempt number - Current attempt number (1-3)
]]
function WarbandNexus:CollectPvEDataWithRetry(charKey, attempt)
    attempt = attempt or 1
    
    -- Check if already loading
    if ns.PvELoadingState.isLoading and attempt == 1 then
        return false
    end
    
    -- Reset cancelled flag on first attempt
    if attempt == 1 then
        ns.PvELoadingState.cancelled = false
    end
    
    -- Check if cancelled
    if ns.PvELoadingState.cancelled then
        return false
    end
    
    -- Update loading state (AUTOMATIC - no user action)
    self:UpdatePvELoadingState({
        isLoading = true,
        attempts = attempt,
        loadingProgress = (attempt - 1) * 33, -- 0%, 33%, 66%
        lastAttempt = time(),
        currentStage = "Collecting PvE data",
    })
    
    -- Collect data
    local pve = self:CollectPvEData()
    
    -- Validate data completeness
    local isComplete = ValidatePvEDataCompleteness(pve)
    
    if isComplete then
        -- SUCCESS - data complete
        self:UpdatePvEDataV2(charKey, pve)
        self:UpdatePvELoadingState({
            isLoading = false,
            loadingProgress = 100,
            attempts = 0,
            error = nil,
            currentStage = nil,
        })
        return true
    elseif attempt < 3 then
        -- RETRY - schedule next attempt (AUTOMATIC)
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.CollectPvEDataWithRetry then
                WarbandNexus:CollectPvEDataWithRetry(charKey, attempt + 1)
            end
        end)
        return false
    else
        -- FAILED - store incomplete data and clear loading
        self:UpdatePvEDataV2(charKey, pve)
        self:UpdatePvELoadingState({
            isLoading = false,
            loadingProgress = 100,
            attempts = 0,
            error = "Some data may be incomplete. Try refreshing later.",
            currentStage = nil,
        })
        return false
    end
end

--[[
    Collect PvE data with staggered approach (performance optimized)
    Spreads collection across 3 stages to prevent FPS drops
    Stage 1 (3s):  Great Vault (priority 1) → 33% progress
    Stage 2 (5s):  M+ Scores (priority 2) → 66% progress
    Stage 3 (7s):  Lockouts (priority 3) → 100% progress
    @param charKey string - Character key (name-realm)
]]
function WarbandNexus:CollectPvEDataStaggered(charKey)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("pve") then
        return
    end
    
    -- Reset cancelled flag
    ns.PvELoadingState.cancelled = false
    
    -- Initialize partial data structure
    local pve = {
        greatVault = {},
        lockouts = {},
        mythicPlus = {},
        hasUnclaimedRewards = false,
    }
    
    -- Update loading state
    self:UpdatePvELoadingState({
        isLoading = true,
        attempts = 1,
        loadingProgress = 0,
        lastAttempt = time(),
        currentStage = "Preparing",
    })
    
    -- Stage 1: Great Vault (most important, show first)
    C_Timer.After(3, function()
        if ns.PvELoadingState.cancelled then return end
        
        self:UpdatePvELoadingState({
            currentStage = "Great Vault",
            loadingProgress = 10,
        })
        
        -- Collect Great Vault data
        if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities then
                for _, activity in ipairs(activities) do
                    local activityData = {
                        type = activity.type,
                        index = activity.index,
                        progress = activity.progress,
                        threshold = activity.threshold,
                        level = activity.level,
                    }
                    
                    -- Get reward item levels
                    if activity.rewards and #activity.rewards > 0 then
                        local reward = activity.rewards[1]
                        if reward and reward.itemLevel and reward.itemLevel > 0 then
                            activityData.rewardItemLevel = reward.itemLevel
                        end
                    end
                    
                    table.insert(pve.greatVault, activityData)
                end
            end
        end
        
        -- Check for unclaimed rewards
        if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
            pve.hasUnclaimedRewards = C_WeeklyRewards.HasAvailableRewards()
        end
        
        -- Update progress
        self:UpdatePvELoadingState({loadingProgress = 33})
        self:UpdatePvEDataV2(charKey, pve) -- Partial update
    end)
    
    -- Stage 2: M+ Scores (medium priority)
    C_Timer.After(5, function()
        if ns.PvELoadingState.cancelled then return end
        
        self:UpdatePvELoadingState({
            currentStage = "Mythic+ Scores",
            loadingProgress = 40,
        })
        
        -- Collect M+ data
        if C_ChallengeMode then
            pve.mythicPlus.dungeons = {}
            local overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
            pve.mythicPlus.overallScore = overallScore
            
            -- Get map scores
            local allScores = C_ChallengeMode.GetMapScoreInfo() or {}
            local scoresByMapID = {}
            for _, scoreData in ipairs(allScores) do
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            -- Get dungeon details
            local mapTable = C_ChallengeMode.GetMapTable()
            if mapTable then
                for _, mapID in ipairs(mapTable) do
                    local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if name then
                        local scoreData = scoresByMapID[mapID]
                        table.insert(pve.mythicPlus.dungeons, {
                            mapID = mapID,
                            name = name,
                            texture = texture,
                            bestLevel = scoreData and scoreData.level or 0,
                            score = scoreData and scoreData.dungeonScore or 0,
                        })
                    end
                end
            end
        end
        
        -- Update progress
        self:UpdatePvELoadingState({loadingProgress = 66})
        self:UpdatePvEDataV2(charKey, pve) -- Partial update
    end)
    
    -- Stage 3: Lockouts (low priority)
    C_Timer.After(7, function()
        if ns.PvELoadingState.cancelled then return end
        
        self:UpdatePvELoadingState({
            currentStage = "Raid Lockouts",
            loadingProgress = 80,
        })
        
        -- Collect lockouts
        if GetNumSavedInstances then
            local numSaved = GetNumSavedInstances()
            for i = 1, numSaved do
                local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                if name and isRaid then
                    table.insert(pve.lockouts, {
                        name = name,
                        id = id,
                        reset = reset,
                        difficulty = difficulty,
                        difficultyName = difficultyName,
                        progress = encounterProgress or 0,
                        total = numEncounters or 0,
                        extended = extended,
                    })
                end
            end
        end
        
        -- Final update - complete!
        self:UpdatePvELoadingState({
            loadingProgress = 100,
            isLoading = false,
            attempts = 0,
            currentStage = nil,
        })
        self:UpdatePvEDataV2(charKey, pve) -- Final update
    end)
end

-- ============================================================================
-- ITEM SEARCH & AGGREGATION
-- ============================================================================

--[[
    Perform item search across all characters and banks
    @param searchTerm string - Search query (item name or ID)
    @return table - Array of search results with location info
]]
function WarbandNexus:PerformItemSearch(searchTerm)
    if not searchTerm or searchTerm == "" then
        return {}
    end
    
    local results = {}
    local searchLower = searchTerm:lower()
    local searchID = tonumber(searchTerm)
    
    -- Search Warband Bank
    local warbandData = self:GetWarbandBankV2()
    if warbandData and warbandData.items then
        for bagID, bagData in pairs(warbandData.items) do
            for slotID, item in pairs(bagData) do
                local match = false
                
                -- Match by name
                if item.name and item.name:lower():find(searchLower) then
                    match = true
                end
                
                -- Match by ID
                if searchID and item.itemID == searchID then
                    match = true
                end
                
                if match then
                    table.insert(results, {
                        item = item,
                        location = "Warband Bank",
                        locationDetail = "Tab " .. (bagID - 12), -- Convert bagID to tab number
                        character = nil,
                    })
                end
            end
        end
    end
    
    -- Search Personal Banks (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            local personalBank = self:GetPersonalBankV2(charKey)
            if personalBank then
                for bagID, bagData in pairs(personalBank) do
                    for slotID, item in pairs(bagData) do
                        local match = false
                        
                        -- Match by name
                        if item.name and item.name:lower():find(searchLower) then
                            match = true
                        end
                        
                        -- Match by ID
                        if searchID and item.itemID == searchID then
                            match = true
                        end
                        
                        if match then
                            table.insert(results, {
                                item = item,
                                location = "Personal Bank",
                                locationDetail = charData.name .. " (" .. charData.realm .. ")",
                                character = charData.name,
                            })
                        end
                    end
                end
            end
        end
    end
    
    return results
end

-- ============================================================================
-- CURRENCY DATA
-- ============================================================================

--[[
    Important Currency IDs organized by expansion
]]
-- ============================================================================
-- CURRENCY COLLECTION (Direct from Blizzard API)
-- ============================================================================
-- NOTE: We no longer use a hardcoded currency list.
-- Instead, we collect ALL currencies from C_CurrencyInfo.GetCurrencyListSize()
-- This ensures we always match Blizzard's Currency UI exactly.
-- ============================================================================

--[[
    Collect all currency data for current character
    Collects ALL currencies directly from Blizzard API with their header structure
    @return table, table - currencies data, headers data
]]
function WarbandNexus:CollectCurrencyData()
    local currencies = {}
    local headers = {}
    
    local success, err = pcall(function()
        if not C_CurrencyInfo then
            return
        end
        
        -- FIRST: Expand all currency categories (CRITICAL!)
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and info.isHeader and not info.isHeaderExpanded then
                C_CurrencyInfo.ExpandCurrencyList(i, true)
            end
        end
        
        -- Wait a tiny bit for expansion (not ideal but necessary)
        -- In production, this would be done via event
        
        -- Get currency list size AFTER expansion
        local listSize = C_CurrencyInfo.GetCurrencyListSize()
        
        local currentHeader = nil
        local scannedCount = 0
        local currencyCount = 0
        
        for i = 1, listSize do
            local listInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
            
            if listInfo and listInfo.name and listInfo.name ~= "" then
                scannedCount = scannedCount + 1
                
                if listInfo.isHeader then
                    -- This is a HEADER
                    -- Store depth/level information if available
                    currentHeader = {
                        name = listInfo.name,
                        index = i,
                        currencies = {},
                        isHeaderExpanded = listInfo.isHeaderExpanded,
                        -- Capture ALL fields from API for debugging
                        isTypeUnused = listInfo.isTypeUnused,
                        -- Log what API provides
                        _debug_listInfo = {
                            name = listInfo.name,
                            isHeader = listInfo.isHeader,
                            isHeaderExpanded = listInfo.isHeaderExpanded,
                            isTypeUnused = listInfo.isTypeUnused,
                            -- Check if API provides depth or indent
                            depth = listInfo.depth,
                            level = listInfo.level,
                            indent = listInfo.indent,
                            parentIndex = listInfo.parentIndex,
                        }
                    }
                    table.insert(headers, currentHeader)
                else
                    -- This is a CURRENCY entry
                    -- Try multiple methods to get currency ID
                    local currencyID = nil
                    
                    -- Method 1: From link (most reliable if it exists)
                    local currencyLink = C_CurrencyInfo.GetCurrencyListLink(i)
                    if currencyLink then
                        currencyID = tonumber(currencyLink:match("currency:(%d+)"))
                    end
                    
                    -- Method 2: If listInfo has the ID directly (some versions)
                    if not currencyID then
                        currencyID = listInfo.currencyTypesID
                    end
                    
                    -- Method 3: Search by name (fallback, less reliable)
                    if not currencyID and listInfo.name then
                        -- We can't reliably get ID from name, skip this
                    end
                    
                    if currencyID and currencyID > 0 then
                        -- Get FULL currency info using the ID
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                        
                        if currencyInfo and currencyInfo.name then
                            currencyCount = currencyCount + 1
                            
                            -- Hidden criteria
                            local nameHidden = currencyInfo.name and 
                                              (currencyInfo.name:find("%(Hidden%)") or 
                                               currencyInfo.name:match("^%d+%.%d+%.%d+"))
                            
                            local isReallyHidden = nameHidden or false
                            
                            -- Store currency data
                            local currencyData = {
                                name = currencyInfo.name,
                                quantity = currencyInfo.quantity or 0,
                                maxQuantity = currencyInfo.maxQuantity or 0,
                                iconFileID = currencyInfo.iconFileID,
                                quality = currencyInfo.quality or 1,
                                useTotalEarnedForMaxQty = currencyInfo.useTotalEarnedForMaxQty,
                                canEarnPerWeek = currencyInfo.canEarnPerWeek,
                                quantityEarnedThisWeek = currencyInfo.quantityEarnedThisWeek or 0,
                                isCapped = (currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 and
                                           currencyInfo.quantity >= currencyInfo.maxQuantity),
                                isAccountWide = currencyInfo.isAccountWide or false,
                                isAccountTransferable = currencyInfo.isAccountTransferable or false,
                                discovered = currencyInfo.discovered or false,
                                isHidden = isReallyHidden,
                                headerName = currentHeader and currentHeader.name or "Other",
                                listIndex = i,
                            }
                            
                            -- Auto-assign expansion and category based on name patterns
                            local name = currencyData.name:lower()
                            local headerName = currencyData.headerName:lower()
                            
                            -- Expansion detection
                            if name:find("ethereal") or name:find("carved ethereal") or name:find("runed ethereal") or name:find("weathered ethereal") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Crest"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("undercoin") or name:find("restored coffer") or name:find("coffer key") or name:find("voidsplinter") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Currency"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("kej") or name:find("resonance") or name:find("valorstone") or name:find("flame%-blessed") or name:find("mereldar") or name:find("hellstone") or name:find("corrupted mementos") or name:find("kaja'cola") or name:find("finery") or name:find("residual memories") or name:find("untethered coin") or name:find("trader's tender") or name:find("bronze celebration") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = name:find("valorstone") and "Upgrade" or "Currency"
                            elseif name:find("drake") or name:find("whelp") or name:find("aspect") or name:find("dragon isles") or name:find("dragonf") then
                                currencyData.expansion = "Dragonflight"
                                currencyData.category = name:find("crest") and "Crest" or "Currency"
                            elseif name:find("soul") or name:find("cinders") or name:find("stygia") or name:find("shadowlands") or name:find("anima") or name:find("infused ruby") or name:find("reservoir anima") or name:find("grateful offering") then
                                currencyData.expansion = "Shadowlands"
                                currencyData.category = "Currency"
                            elseif name:find("war resource") or name:find("seafarer") or name:find("7th legion") or name:find("honorbound") or name:find("polished pet charm") or name:find("prismatic manapearl") or name:find("war supplies") then
                                currencyData.expansion = "Battle for Azeroth"
                                currencyData.category = "Currency"
                            elseif name:find("legion") or name:find("order resource") or name:find("nethershard") or name:find("curious coin") or name:find("legionfall") or name:find("wakening") or name:find("shadowy coin") or name:find("seal of broken fate") then
                                currencyData.expansion = "Legion"
                                currencyData.category = "Currency"
                            elseif name:find("apexis") or name:find("garrison") or name:find("primal spirit") or name:find("oil") or name:find("seal of tempered fate") or name:find("seal of inevitable fate") then
                                currencyData.expansion = "Warlords of Draenor"
                                currencyData.category = "Currency"
                            elseif name:find("timeless") or name:find("warforged") or name:find("bloody coin") or name:find("lesser charm") or name:find("elder charm") or name:find("mogu rune") or name:find("valor point") then
                                currencyData.expansion = "Mists of Pandaria"
                                currencyData.category = "Currency"
                            elseif name:find("mote") or name:find("sidereal") or name:find("essence of corrupted") or name:find("illustrious") or name:find("mark of the world tree") or name:find("tol barad") or name:find("conquest point") then
                                currencyData.expansion = "Cataclysm"
                                currencyData.category = "Currency"
                            elseif name:find("champion's seal") or name:find("emblem") or name:find("stone keeper") or name:find("defiler's") or name:find("wintergrasp") or name:find("shard of") or name:find("frozen orb") then
                                currencyData.expansion = "Wrath of the Lich King"
                                currencyData.category = "Currency"
                            elseif name:find("badge") or name:find("venture coin") or name:find("halaa") or name:find("spirit shard") or name:find("mark of honor hold") or name:find("mark of thrallmar") then
                                currencyData.expansion = "The Burning Crusade"
                                currencyData.category = "Currency"
                            elseif currencyData.isAccountWide then
                                currencyData.expansion = "Account-Wide"
                                currencyData.category = "Currency"
                            else
                                -- Use header name to determine expansion if still unknown
                                if headerName:find("war within") or headerName:find("tww") then
                                    currencyData.expansion = "The War Within"
                                elseif headerName:find("dragonflight") or headerName:find("df") then
                                    currencyData.expansion = "Dragonflight"
                                elseif headerName:find("shadowlands") or headerName:find("sl") then
                                    currencyData.expansion = "Shadowlands"
                                elseif headerName:find("battle for azeroth") or headerName:find("bfa") then
                                    currencyData.expansion = "Battle for Azeroth"
                                elseif headerName:find("legion") then
                                    currencyData.expansion = "Legion"
                                elseif headerName:find("warlords") or headerName:find("wod") then
                                    currencyData.expansion = "Warlords of Draenor"
                                elseif headerName:find("mists of pandaria") or headerName:find("mop") then
                                    currencyData.expansion = "Mists of Pandaria"
                                elseif headerName:find("cataclysm") then
                                    currencyData.expansion = "Cataclysm"
                                elseif headerName:find("wrath") or headerName:find("lich king") or headerName:find("wotlk") then
                                    currencyData.expansion = "Wrath of the Lich King"
                                elseif headerName:find("burning crusade") or headerName:find("tbc") or headerName:find("bc") then
                                    currencyData.expansion = "The Burning Crusade"
                                else
                                    currencyData.expansion = "Other"
                                end
                            end
                            
                            -- Category refinement and special handling
                            if not currencyData.category then
                                if name:find("crest") or name:find("fragment") then
                                    currencyData.category = "Crest"
                                elseif name:find("valorstone") or name:find("upgrade") then
                                    currencyData.category = "Upgrade"
                                elseif name:find("supplies") then
                                    currencyData.category = "Supplies"
                                elseif name:find("research") or name:find("knowledge") or name:find("artisan") then
                                    currencyData.category = "Profession"
                                elseif headerName:find("pvp") or name:find("honor") or name:find("conquest") or name:find("bloody token") or name:find("vicious") then
                                    currencyData.category = "PvP"
                                elseif headerName:find("event") or name:find("timewarped") or name:find("darkmoon") or name:find("love token") or name:find("tricky treat") or name:find("brewfest") or name:find("celebration token") or name:find("prize ticket") or name:find("epicurean") then
                                    currencyData.category = "Event"
                                elseif name:find("trophy") or name:find("tender") then
                                    currencyData.category = "Cosmetic"
                                else
                                    currencyData.category = "Currency"
                                end
                            end
                            
                            -- Special handling for PvP and Event currencies - assign to correct expansion
                            if currencyData.expansion == "Other" then
                                if currencyData.category == "PvP" then
                                    -- PvP currencies go to Account-Wide if account-wide
                                    if currencyData.isAccountWide or name:find("bloody") or name:find("vicious") or name:find("honor") or name:find("conquest") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Event" then
                                    -- Most event currencies are account-wide
                                    if currencyData.isAccountWide or name:find("timewarped") or name:find("darkmoon") or name:find("celebration") or name:find("epicurean") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Cosmetic" then
                                    -- Cosmetic currencies are usually account-wide
                                    if currencyData.isAccountWide or name:find("tender") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                end
                            end
                            
                            currencies[currencyID] = currencyData
                            
                            -- Add to current header's currency list
                            if currentHeader then
                                table.insert(currentHeader.currencies, currencyID)
                            end
                        end
                    end
                end
            end
        end
    end)
    
    if not success then
        return {}, {}
    end
    
    -- Infer depth from header sequence (Blizzard API may not provide depth)
    local function InferHeaderDepth(headerList)
        -- First, log what API provides
        if headerList[1] and headerList[1]._debug_listInfo then
            -- Check first header to see if API provides depth info
            local firstDebug = headerList[1]._debug_listInfo
            -- If API provides depth/level/indent, we should use it instead of inference
        end
        
        for i, header in ipairs(headerList) do
            local name = header.name
            
            -- Root level headers (depth 0)
            if name == "Dungeon and Raid" or 
               name == "Miscellaneous" or 
               name == "Player vs. Player" or 
               name == "Legacy" then
                header.depth = 0
            -- Legacy children (depth 1) - ALL expansions including Burning Crusade
            elseif name:find("War Within") or 
                   name:find("Dragonflight") or 
                   name:find("Shadowlands") or 
                   name:find("Battle for Azeroth") or 
                   name:find("Legion") or 
                   name:find("Warlords of Draenor") or 
                   name:find("Mists of Pandaria") or 
                   name:find("Cataclysm") or 
                   name:find("Wrath of the Lich King") or
                   name:find("Burning Crusade") or
                   name:find("Outland") then
                header.depth = 1
            -- Season 3 is child of War Within (depth 2)
            elseif name:find("Season") and (name:find("3") or name:find("Three")) then
                header.depth = 2
            else
                -- Default to depth 0 if unknown
                header.depth = 0
            end
        end
        
        return headerList
    end
    
    -- First infer depths
    headers = InferHeaderDepth(headers)
    
    -- Build header tree structure (parent-child relationships)
    local function BuildHeaderTree(headerList)
        -- Initialize children array and hasDescendants flag
        for i, header in ipairs(headerList) do
            header.children = {}
            header.hasDescendants = #header.currencies > 0
        end
        
        -- Link children to parents based on depth
        -- Process in reverse to propagate hasDescendants upward
        for i = #headerList, 1, -1 do
            local header = headerList[i]
            local depth = header.depth or 0
            
            -- Find parent (previous header with lower depth)
            for j = i - 1, 1, -1 do
                local potentialParent = headerList[j]
                local parentDepth = potentialParent.depth or 0
                
                if parentDepth < depth then
                    -- This is the parent
                    table.insert(potentialParent.children, 1, header)  -- Insert at beginning to maintain order
                    
                    -- Propagate hasDescendants flag to parent
                    if header.hasDescendants or #header.children > 0 then
                        potentialParent.hasDescendants = true
                    end
                    
                    break
                end
            end
        end
        
        return headerList
    end
    
    headers = BuildHeaderTree(headers)
    
    return currencies, headers
end

--[[
    Update currency data for current character
    DEPRECATED: Now handled by CurrencyCacheService (Direct DB architecture)
    This function is kept for backward compatibility but redirects to new system
]]
function WarbandNexus:UpdateCurrencyData()
    -- GUARD: Only update currency if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("currencies") then
        return
    end
    
    -- DEPRECATED: Redirect to new CurrencyCacheService
    -- Currency data is now managed by CurrencyCacheService via Direct DB
    -- No need to collect or write data here anymore
    
    if self.ScanCurrencies then
        -- Trigger scan via new system
        self:ScanCurrencies()
    end
    
    return
end


-- ============================================================================
-- V2: INCREMENTAL REPUTATION UPDATES
-- ============================================================================

-- MOVED: Build* reputation functions → ReputationCacheService.lua
-- These are now wrappers that delegate to ReputationCacheService
-- (Backwards compatibility maintained for DataService callers)

--[[
    Update a single reputation (incremental update)
    Detects rep type (Friendship, Renown, Classic) and updates only that faction
    @param factionID number - Faction ID to update
]]
function WarbandNexus:UpdateSingleReputation(factionID)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("reputations") then
        return
    end
    
    if not factionID then return end
    
    local charKey = ns.Utilities:GetCharacterKey()
    local repData = nil
    
    -- Initialize global structure if needed
    self.db.global.reputations = self.db.global.reputations or {}
    
    -- 1. Check if Friendship faction (highest priority for TWW)
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            repData = self:BuildFriendshipData(factionID, friendInfo)
            
            -- Update metadata
            if repData and not self.db.global.reputations[factionID] then
                local factionData = C_Reputation and C_Reputation.GetFactionDataByID(factionID)
                self.db.global.reputations[factionID] = {
                    name = friendInfo.name or (factionData and factionData.name) or ("Faction " .. factionID),
                    icon = friendInfo.texture,
                    isMajorFaction = true,
                    isRenown = true,
                }
            end
        end
    end
    
    -- 2. Check if Renown (Major Faction)
    if not repData and C_MajorFactions and C_MajorFactions.GetMajorFactionRenownInfo then
        local renownInfo = C_MajorFactions.GetMajorFactionRenownInfo(factionID)
        if renownInfo then
            repData = self:BuildRenownData(factionID, renownInfo)
            
            -- Update metadata (ALWAYS update, not just first time - Blizzard can change flags)
            local majorData = C_MajorFactions.GetMajorFactionData(factionID)
            self.db.global.reputations[factionID] = self.db.global.reputations[factionID] or {}
            self.db.global.reputations[factionID].name = majorData and majorData.name or ("Faction " .. factionID)
            self.db.global.reputations[factionID].icon = majorData and majorData.textureKit
            self.db.global.reputations[factionID].isMajorFaction = true
            self.db.global.reputations[factionID].isRenown = true
            -- CRITICAL: Always update isAccountWide from API
            self.db.global.reputations[factionID].isAccountWide = majorData and majorData.isAccountWide
            if self.db.global.reputations[factionID].isAccountWide == nil then
                self.db.global.reputations[factionID].isAccountWide = true  -- Major factions default to true
            end
        end
    end
    
    -- 3. Fall back to Classic reputation
    if not repData and C_Reputation and C_Reputation.GetFactionDataByID then
        local factionData = C_Reputation.GetFactionDataByID(factionID)
        if factionData and factionData.name then
            repData = self:BuildClassicRepData(factionID, factionData)
            
            -- Update metadata (ALWAYS update, not just first time)
            self.db.global.reputations[factionID] = self.db.global.reputations[factionID] or {}
            self.db.global.reputations[factionID].name = factionData.name
            self.db.global.reputations[factionID].icon = factionData.factionID and select(2, GetFactionInfoByID(factionData.factionID))
            self.db.global.reputations[factionID].isMajorFaction = false
            self.db.global.reputations[factionID].isRenown = false
            -- CRITICAL: Always update isAccountWide from API if available
            if factionData.isAccountWide ~= nil then
                self.db.global.reputations[factionID].isAccountWide = factionData.isAccountWide
            else
                -- If API doesn't provide the flag, default to false for classic reps
                self.db.global.reputations[factionID].isAccountWide = false
            end
        end
    end
    
    -- Update character progress
    if repData then
        self.db.global.reputations[factionID] = self.db.global.reputations[factionID] or {}
        self.db.global.reputations[factionID].chars = self.db.global.reputations[factionID].chars or {}
        self.db.global.reputations[factionID].chars[charKey] = repData
        
        -- Update timestamp
        self.db.global.reputationLastUpdate = time()
        
        -- Invalidate cache
        if self.InvalidateReputationCache then
            self:InvalidateReputationCache()
        end
    end
end


-- ============================================================================
-- V2: PVE DATA STORAGE (Global with Metadata Separation)
-- ============================================================================

--[[
    Update PvE data to global storage (v2)
    Separates metadata (dungeon names, textures) from progress data
    @param charKey string - Character key
    @param pveData table - PvE data from CollectPvEData
]]
---Update PvE data for character (Phase 2: Routes to PvECacheService)
---@param charKey string Character key
---@param pveData table PvE data
function WarbandNexus:UpdatePvEDataV2(charKey, pveData)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("pve") then
        return
    end
    
    -- Phase 2: Route to PvECacheService
    if self.UpdatePvEData then
        self:UpdatePvEData()
        return
    end
    
    -- Legacy fallback (Phase 3: will be removed)
    if not charKey or not pveData then return end
    
    -- Initialize global structures
    self.db.global.pveMetadata = self.db.global.pveMetadata or { dungeons = {}, raids = {}, lastUpdate = 0 }
    self.db.global.pveProgress = self.db.global.pveProgress or {}
    
    -- Extract and store dungeon metadata globally
    if pveData.mythicPlus and pveData.mythicPlus.dungeons then
        for _, dungeon in ipairs(pveData.mythicPlus.dungeons) do
            if dungeon.mapID and dungeon.name then
                self.db.global.pveMetadata.dungeons[dungeon.mapID] = {
                    name = dungeon.name,
                    texture = dungeon.texture,
                }
            end
        end
    end
    
    -- Extract and store raid metadata globally
    if pveData.lockouts then
        for _, lockout in ipairs(pveData.lockouts) do
            if lockout.instanceID and lockout.name then
                self.db.global.pveMetadata.raids[lockout.instanceID] = {
                    name = lockout.name,
                    difficulty = lockout.difficulty,
                }
            end
        end
    end
    
    self.db.global.pveMetadata.lastUpdate = time()
    
    -- Store character-specific progress (without redundant metadata)
    local progress = {
        -- Great Vault: only store essential progress data
        greatVault = {},
        hasUnclaimedRewards = pveData.hasUnclaimedRewards or false,
        
        -- Lockouts: only store progress data, reference metadata by ID
        lockouts = {},
        
        -- M+: store scores and references to dungeons by mapID
        mythicPlus = {
            overallScore = pveData.mythicPlus and pveData.mythicPlus.overallScore or 0,
            weeklyBest = pveData.mythicPlus and pveData.mythicPlus.weeklyBest or 0,
            runsThisWeek = pveData.mythicPlus and pveData.mythicPlus.runsThisWeek or 0,
            keystone = pveData.mythicPlus and pveData.mythicPlus.keystone,
            dungeonProgress = {},  -- { [mapID] = { score, bestLevel, affixes, ... } }
        },
        
        lastUpdate = time(),
    }
    
    -- Copy Great Vault data (minimal, no heavy metadata)
    if pveData.greatVault then
        for _, activity in ipairs(pveData.greatVault) do
            table.insert(progress.greatVault, {
                type = activity.type,
                index = activity.index,
                progress = activity.progress,
                threshold = activity.threshold,
                level = activity.level,
                rewardItemLevel = activity.rewardItemLevel,
                nextLevel = activity.nextLevel,
                nextLevelIlvl = activity.nextLevelIlvl,
                maxLevel = activity.maxLevel,
                maxIlvl = activity.maxIlvl,
                upgradeItemLevel = activity.upgradeItemLevel,
            })
        end
    end
    
    -- Copy Lockouts (reference by instanceID, not full metadata)
    if pveData.lockouts then
        for _, lockout in ipairs(pveData.lockouts) do
            table.insert(progress.lockouts, {
                instanceID = lockout.instanceID or lockout.id,
                name = lockout.name,  -- Keep name for display (small)
                reset = lockout.reset,
                difficulty = lockout.difficulty,
                progress = lockout.progress,
                total = lockout.total,
                isRaid = lockout.isRaid,
                extended = lockout.extended,
            })
        end
    end
    
    -- Copy M+ dungeon progress (reference by mapID)
    if pveData.mythicPlus and pveData.mythicPlus.dungeons then
        for _, dungeon in ipairs(pveData.mythicPlus.dungeons) do
            if dungeon.mapID then
                progress.mythicPlus.dungeonProgress[dungeon.mapID] = {
                    score = dungeon.score or 0,
                    bestLevel = dungeon.bestLevel or 0,
                    bestLevelAffixes = dungeon.bestLevelAffixes,
                    bestOverallAffixes = dungeon.bestOverallAffixes,
                }
            end
        end
    end
    
    -- Store progress (uncompressed for now, can add compression later if needed)
    self.db.global.pveProgress[charKey] = progress
end

--[[
    Get PvE data for a character (v2)
    Reconstructs full data from global metadata + progress
    @param charKey string - Character key
    @return table - Full PvE data structure
]]
---Get PvE data for character (Phase 2: Routes to PvECacheService)
---@param charKey string Character key
---@return table|nil PvE data
function WarbandNexus:GetPvEDataV2(charKey)
    -- Phase 2: Route to PvECacheService
    if self.GetPvEData then
        return self:GetPvEData(charKey)
    end
    
    -- Legacy fallback (Phase 3: will be removed)
    local progress = self.db.global.pveProgress and self.db.global.pveProgress[charKey]
    local metadata = self.db.global.pveMetadata or { dungeons = {}, raids = {} }
    
    -- Fallback to old per-character storage for migration
    if not progress then
        local charData = self.db.global.characters and self.db.global.characters[charKey]
        if charData and charData.pve then
            return charData.pve
        end
        return nil
    end
    
    -- Reconstruct full PvE data
    local pve = {
        greatVault = progress.greatVault or {},
        hasUnclaimedRewards = progress.hasUnclaimedRewards or false,
        lockouts = progress.lockouts or {},
        mythicPlus = {
            overallScore = progress.mythicPlus and progress.mythicPlus.overallScore or 0,
            weeklyBest = progress.mythicPlus and progress.mythicPlus.weeklyBest or 0,
            runsThisWeek = progress.mythicPlus and progress.mythicPlus.runsThisWeek or 0,
            keystone = progress.mythicPlus and progress.mythicPlus.keystone,
            dungeons = {},
        },
    }
    
    -- Reconstruct dungeon data with metadata
    if progress.mythicPlus and progress.mythicPlus.dungeonProgress then
        for mapID, dungeonProgress in pairs(progress.mythicPlus.dungeonProgress) do
            local dungeonMeta = metadata.dungeons[mapID] or {}
            table.insert(pve.mythicPlus.dungeons, {
                mapID = mapID,
                name = dungeonMeta.name or ("Dungeon " .. mapID),
                texture = dungeonMeta.texture,
                score = dungeonProgress.score or 0,
                bestLevel = dungeonProgress.bestLevel or 0,
                bestLevelAffixes = dungeonProgress.bestLevelAffixes,
                bestOverallAffixes = dungeonProgress.bestOverallAffixes,
            })
        end
        
        -- Sort by name
        table.sort(pve.mythicPlus.dungeons, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
    end
    
    return pve
end

-- ============================================================================
-- V2: PERSONAL BANK STORAGE (Global with Compression)
-- ============================================================================

-- Cache for decompressed data (in-memory only, per session)
local decompressedCache = {
    personalBanks = {},  -- [charKey] = decompressed data
    warbandBank = nil,   -- single warband bank
}

--[[
    Update personal bank to global storage (v2)
    DEPRECATED: This function redirects to ItemsCacheService for compatibility
    New code should use ItemsCacheService:SaveItemsCompressed() directly
    @param charKey string - Character key
    @param bankData table - Personal bank data (old bagID/slot format)
]]
function WarbandNexus:UpdatePersonalBankV2(charKey, bankData)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("items") then
        return
    end
    
    if not charKey then return end
    
    -- Initialize global structure
    self.db.global.personalBanks = self.db.global.personalBanks or {}
    
    if not bankData or not next(bankData) then
        -- No bank data, clear any existing
        self.db.global.personalBanks[charKey] = nil
        return
    end
    
    -- Try to compress the bank data
    local compressed = self:CompressTable(bankData)
    
    if compressed and type(compressed) == "string" then
        -- Store compressed data
        self.db.global.personalBanks[charKey] = {
            compressed = true,
            data = compressed,
            lastUpdate = time(),
        }
    else
        -- Fallback: store uncompressed
        self.db.global.personalBanks[charKey] = {
            compressed = false,
            data = bankData,
            lastUpdate = time(),
        }
    end
    
    self.db.global.personalBanksLastUpdate = time()
    
    -- Invalidate decompressed cache for this character
    if decompressedCache.personalBanks then
        decompressedCache.personalBanks[charKey] = nil
    end
end

--[[
    Get personal bank data for a character (v2)
    DEPRECATED: Redirects to ItemsCacheService:GetItemsData()
    @param charKey string - Character key
    @return table - Personal bank data
]]
function WarbandNexus:GetPersonalBankV2(charKey)
    -- Redirect to ItemsCacheService (unified storage)
    if self.GetItemsData then
        local itemsData = self:GetItemsData(charKey)
        if itemsData then
            -- Return combined bags + bank for legacy compatibility
            local combined = {}
            
            -- Add bags (convert array to bagID-indexed)
            if itemsData.bags then
                for _, item in ipairs(itemsData.bags) do
                    local bagID = item.bagID or 0
                    local slot = item.slot or 1
                    if not combined[bagID] then
                        combined[bagID] = {}
                    end
                    combined[bagID][slot] = item
                end
            end
            
            -- Add bank (convert array to bagID-indexed)
            if itemsData.bank then
                for _, item in ipairs(itemsData.bank) do
                    local bagID = item.bagID or -1
                    local slot = item.slot or 1
                    if not combined[bagID] then
                        combined[bagID] = {}
                    end
                    combined[bagID][slot] = item
                end
            end
            
            return combined
        end
    end
    
    return nil
end

--[[
    Get character's Personal Bank + Inventory Bags combined
    DEPRECATED: Use ItemsCacheService:GetItemsData(charKey) instead
    This function is kept for backward compatibility only
    @param charKey string - Character key (Name-Realm)
    @return table - Combined bank and bags data with unique keys
]]
function WarbandNexus:GetPersonalItemsV2(charKey)
    -- DEPRECATED: Redirect to ItemsCacheService
    if self.GetItemsData then
        local itemsData = self:GetItemsData(charKey)
        if itemsData then
            -- Convert array format to bagID-indexed format for legacy compatibility
            local combined = {}
            
            -- Add bags
            if itemsData.bags then
                for _, item in ipairs(itemsData.bags) do
                    local bagID = item.bagID or 0
                    local slot = item.slot or 1
                    if not combined[bagID] then
                        combined[bagID] = {}
                    end
                    combined[bagID][slot] = item
                end
            end
            
            -- Add bank
            if itemsData.bank then
                for _, item in ipairs(itemsData.bank) do
                    local bagID = item.bagID or -1
                    local slot = item.slot or 1
                    if not combined[bagID] then
                        combined[bagID] = {}
                    end
                    combined[bagID][slot] = item
                end
            end
            
            return combined
        end
    end
    
    return {}
end

-- ============================================================================
-- WARBAND BANK V2 STORAGE (COMPRESSED)
-- ============================================================================

--[[
    Update warband bank to global storage (v2)
    Uses LibDeflate compression to reduce file size
    @param bankData table - Warband bank data (items, gold, metadata)
]]
function WarbandNexus:UpdateWarbandBankV2(bankData)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("items") then
        return
    end
    
    -- Initialize global structure
    self.db.global.warbandBankV2 = self.db.global.warbandBankV2 or {}
    
    if not bankData then
        return
    end
    
    -- Separate metadata from items for efficient storage
    local metadata = {
        gold = bankData.gold or 0,
        lastScan = bankData.lastScan or time(),
        totalSlots = bankData.totalSlots or 0,
        usedSlots = bankData.usedSlots or 0,
    }
    
    -- Try to compress the items data
    local itemsCompressed = nil
    if bankData.items and next(bankData.items) then
        itemsCompressed = self:CompressTable(bankData.items)
    end
    
    if itemsCompressed and type(itemsCompressed) == "string" then
        -- Store compressed data
        self.db.global.warbandBankV2 = {
            compressed = true,
            items = itemsCompressed,
            metadata = metadata,
        }
    else
        -- Fallback: store uncompressed
        self.db.global.warbandBankV2 = {
            compressed = false,
            items = bankData.items or {},
            metadata = metadata,
        }
    end
    
    self.db.global.warbandBankLastUpdate = time()
    
    -- CRITICAL: Invalidate decompressed cache for warband bank
    -- Next GetWarbandBankV2() call will decompress fresh data
    if decompressedCache then
        decompressedCache.warbandBank = nil
    end
end

--[[
    Get warband bank data (v2)
    DEPRECATED: Redirects to ItemsCacheService:GetWarbandBankData()
    @return table - Full warband bank data structure
]]
function WarbandNexus:GetWarbandBankV2()
    -- Redirect to ItemsCacheService (unified storage)
    if self.GetWarbandBankData then
        local warbandData = self:GetWarbandBankData()
        if warbandData then
            -- Convert array format to bagID-indexed format for legacy compatibility
            local result = {
                items = {},
                gold = 0, -- Legacy field (not tracked by ItemsCacheService)
                lastScan = warbandData.lastUpdate or 0,
                totalSlots = 0, -- Legacy field
                usedSlots = 0, -- Legacy field
            }
            
            if warbandData.items then
                for _, item in ipairs(warbandData.items) do
                    local bagID = item.bagID or 13
                    local slot = item.slot or 1
                    if not result.items[bagID] then
                        result.items[bagID] = {}
                    end
                    result.items[bagID][slot] = item
                end
            end
            
            return result
        end
    end
    
    -- Fallback
    return { items = {}, gold = 0, lastScan = 0, totalSlots = 0, usedSlots = 0 }
end

--[[
    Helper: Count table entries
]]
function WarbandNexus:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- COLLECTION DATA
-- ============================================================================

--[[
    Get collection statistics for current character
    @return table - Collection stats (mounts, pets, toys, achievements)
]]
function WarbandNexus:GetCollectionStats()
    local success, result = pcall(function()
    local stats = {
        mounts = 0,
        pets = 0,
        toys = 0,
        achievements = 0,
    }
    
    -- Mounts
    if C_MountJournal and C_MountJournal.GetNumMounts then
        stats.mounts = C_MountJournal.GetNumMounts() or 0
    end
    
    -- Pets
    if C_PetJournal and C_PetJournal.GetNumPets then
        stats.pets = C_PetJournal.GetNumPets() or 0
    end
    
    -- Toys
    if C_ToyBox and C_ToyBox.GetNumToys then
        stats.toys = C_ToyBox.GetNumToys() or 0
    end
    
    -- Achievement Points
    if GetTotalAchievementPoints then
        stats.achievements = GetTotalAchievementPoints() or 0
    end
    
    return stats
    end)
    
    if not success then
        return {
            mounts = 0,
            pets = 0,
            toys = 0,
            achievements = 0,
        }
    end
    
    return result
end

--[[
    Export character data for external use (CSV/JSON compatible)
    @param characterKey string - Character key (name-realm)
    @return table - Simplified character data structure
]]
function WarbandNexus:ExportCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return nil
    end
    
    local char = self.db.global.characters[characterKey]
    -- v2: Get PvE data from global storage
    local pve = self:GetPvEDataV2(characterKey) or {}
    
    -- Create simplified export structure
    return {
        name = char.name,
        realm = char.realm,
        class = char.class,
        level = char.level,
        gold = char.gold or 0,
        silver = char.silver or 0,
        copper = char.copper or 0,
        faction = char.faction,
        race = char.race,
        lastSeen = char.lastSeen,
        pve = {
            greatVaultProgress = #(pve.greatVault or {}),
            lockoutCount = #(pve.lockouts or {}),
            mythicPlusWeeklyBest = (pve.mythicPlus and pve.mythicPlus.weeklyBest) or 0,
            mythicPlusRuns = (pve.mythicPlus and pve.mythicPlus.runsThisWeek) or 0,
        },
    }
end

-- ============================================================================
-- DATA VALIDATION & CLEANUP
-- ============================================================================

--[[
    Validate character data integrity
    @param characterKey string - Character key to validate
    @return boolean, string - Valid status and error message if invalid
]]
function WarbandNexus:ValidateCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return false, "Character not found"
    end
    
    local char = self.db.global.characters[characterKey]
    
    -- Check required fields
    local required = {"name", "realm", "class", "classFile", "level"}
    for _, field in ipairs(required) do
        if not char[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Check data types
    if type(char.level) ~= "number" or char.level < 1 or char.level > 80 then
        return false, "Invalid level: " .. tostring(char.level)
    end
    
    -- Check gold values (breakdown format)
    if char.gold and (type(char.gold) ~= "number" or char.gold < 0) then
        return false, "Invalid gold: " .. tostring(char.gold)
    end
    if char.silver and (type(char.silver) ~= "number" or char.silver < 0 or char.silver > 99) then
        return false, "Invalid silver: " .. tostring(char.silver)
    end
    if char.copper and (type(char.copper) ~= "number" or char.copper < 0 or char.copper > 99) then
        return false, "Invalid copper: " .. tostring(char.copper)
    end
    
    return true, nil
end

--[[
    Clean up stale character data (90+ days old)
    @param daysThreshold number - Days of inactivity before cleanup (default 90)
    @return number - Count of characters removed
]]
function WarbandNexus:CleanupStaleCharacters(daysThreshold)
    daysThreshold = daysThreshold or 90
    local currentTime = time()
    local threshold = daysThreshold * 24 * 60 * 60 -- Convert to seconds
    local removed = 0
    
    if not self.db.global.characters then
        return 0
    end
    
    for key, char in pairs(self.db.global.characters) do
        local lastSeen = char.lastSeen or 0
        local age = currentTime - lastSeen
        
        if age > threshold then
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        self:Print(string.format("Cleaned up %d stale character(s)", removed))
    end
    
    return removed
end

-- ============================================================================
-- BANK ITEMS HELPERS FOR ITEMS TAB
-- ============================================================================

--[[
    Check if weekly reset has occurred since last scan
    EU: Tuesday 07:00 UTC, US: Tuesday 15:00 UTC
    @param lastScanTime number - Unix timestamp of last scan
    @return boolean - True if reset occurred
]]
function WarbandNexus:HasWeeklyResetOccurred(lastScanTime)
    if not lastScanTime then return true end
    
    local now = time()
    
    -- Get region (EU or US)
    local region = GetCurrentRegion() -- 1=US, 2=KR, 3=EU, 4=TW, 5=CN
    
    -- Reset day: Tuesday (wday = 3, where 1=Sunday)
    local resetDay = 3
    local resetHour = (region == 3) and 7 or 15  -- EU: 07:00 UTC, US: 15:00 UTC
    
    -- Calculate last Tuesday reset time
    local function getLastResetTime(timestamp)
        local d = date("*t", timestamp)
        local daysSinceReset = (d.wday - resetDay + 7) % 7
        
        -- Go back to last Tuesday
        local resetTime = os.time({
            year = d.year,
            month = d.month,
            day = d.day - daysSinceReset,
            hour = resetHour,
            min = 0,
            sec = 0
        })
        
        -- If we're before reset hour on Tuesday, go back one more week
        if d.wday == resetDay and d.hour < resetHour then
            resetTime = resetTime - (7 * 24 * 60 * 60)
        end
        
        return resetTime
    end
    
    local lastResetTime = getLastResetTime(now)
    
    -- If last scan was before the most recent reset, reset has occurred
    return lastScanTime < lastResetTime
end

--[[
    Clear keystones for all characters if weekly reset occurred
]]
function WarbandNexus:ClearKeystonesAfterReset()
    if not self.db.global.characters then return end
    
    for charKey, charData in pairs(self.db.global.characters) do
        if charData.mythicKey and charData.mythicKey.scanTime then
            -- Check if reset occurred since last scan
            if self:HasWeeklyResetOccurred(charData.mythicKey.scanTime) then
                charData.mythicKey = nil
            end
        end
    end
end

--[[
    Query current character's Mythic Keystone via C_MythicPlus API
    API-first approach — no bag scanning needed (O(1) vs O(n*slots))
    @return table|nil - {level, dungeonID, dungeonName, scanTime} or nil if no keystone
]]
function WarbandNexus:ScanMythicKeystone()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return nil
    end
    
    -- C_MythicPlus API: server-side cached, zero-cost query
    if not C_MythicPlus then return nil end
    
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    
    if not mapID or not keystoneLevel or keystoneLevel == 0 then
        return nil -- No keystone owned
    end
    
    local mapName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo(mapID)
    
    return {
        level = keystoneLevel,
        dungeonID = mapID,
        dungeonName = mapName or "Unknown Dungeon",
        mapID = mapID,
        scanTime = time()
    }
end

--[[
    Get CURRENT character's Personal Items (Bank + Inventory) as flat list for Items tab
    CRITICAL: Only returns items for the logged-in character, not all characters
    @return table - Array of items with metadata
]]
function WarbandNexus:GetPersonalBankItems()
    local items = {}
    
    -- Get CURRENT character key
    local charKey = ns.Utilities:GetCharacterKey()
    
    -- CRITICAL: Use ItemsCacheService (new unified storage)
    if not self.GetItemsData then
        return items  -- ItemsCacheService not loaded yet
    end
    
    local itemsData = self:GetItemsData(charKey)
    if not itemsData then
        return items
    end
    
    -- ItemsCacheService returns: { bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0 }
    -- Merge bags + bank into a single flat array for UI
    
    -- Add inventory bags items
    if itemsData.bags then
        for _, item in ipairs(itemsData.bags) do
            if item.itemID then
                item.bagIndex = item.actualBagID or item.bagID
                item.slotID = item.slotIndex
                item.source = "bags"
                table.insert(items, item)
            end
        end
    end
    
    -- Add bank items
    if itemsData.bank then
        for _, item in ipairs(itemsData.bank) do
            if item.itemID then
                item.bagIndex = item.actualBagID or item.bagID
                item.slotID = item.slotIndex
                item.source = "personal_bank"
                table.insert(items, item)
            end
        end
    end
    
    return items
end

--[[
    Scan character's inventory bags (0-4 + Reagent)
    Stores data in db.char.bags (current character only)
    Called when bags open/close or BAG_UPDATE fires
]]
--[[
    Scan Character Bags/Inventory
    
    @param specificBagIDs table|nil - Optional: Specific bag IDs to scan
                                      nil = Full scan (all inventory bags)
                                      {0, 1} = Scan only backpack + bag 1
    @return boolean - Success status
]]
function WarbandNexus:ScanCharacterBags(specificBagIDs)
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("items") then
        return false
    end
    
    -- Check if INVENTORY_BAGS constant exists
    if not ns.INVENTORY_BAGS then
        return false
    end
    
    -- Initialize structure
    if not self.db.char.bags then
        self.db.char.bags = { items = {}, lastScan = 0 }
    end
    if not self.db.char.bags.items then
        self.db.char.bags.items = {}
    end
    
    -- Determine which bags to scan
    local bagsToScan
    local isFullScan = (specificBagIDs == nil)
    
    if isFullScan then
        -- Full scan: Clear cache
        wipe(self.db.char.bags.items)
        bagsToScan = ns.INVENTORY_BAGS -- All inventory bags
    else
        -- Incremental scan: Only specified bags
        bagsToScan = specificBagIDs
    end
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Scan specified bags
    for _, bagID in ipairs(bagsToScan) do
        -- Find bagIndex from bagID
        local bagIndex = nil
        for idx, invBagID in ipairs(ns.INVENTORY_BAGS) do
            if invBagID == bagID then
                bagIndex = idx
                break
            end
        end
        
        -- SKIP IGNORED BAGS (Settings UI integration)
        local shouldSkip = false
        if self.db.profile.ignoredInventoryBags and self.db.profile.ignoredInventoryBags[bagID] then
            shouldSkip = true
        end
        
        if not shouldSkip and bagIndex then
            -- Initialize bag if needed
            if not self.db.char.bags.items[bagIndex] then
                self.db.char.bags.items[bagIndex] = {}
            else
                -- Clear this bag's data (incremental update)
                wipe(self.db.char.bags.items[bagIndex])
            end
            
            -- Use API wrapper (TWW compatible)
            local numSlots = self:API_GetBagSize(bagID)
            totalSlots = totalSlots + numSlots
            
            for slotID = 1, numSlots do
                -- PERFORMANCE: Quick check first (skip empty slots)
                if C_Container.HasContainerItem(bagID, slotID) then
                    local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
                    
                    if itemInfo and itemInfo.itemID then
                        usedSlots = usedSlots + 1
                        totalItems = totalItems + (itemInfo.stackCount or 1)
                        
                        -- Store minimal data (performance optimization)
                        local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture, _, classID = self:API_GetItemInfo(itemInfo.itemID)
                        
                        -- CRITICAL: Check for NEW collectible ONLY for collectible classIDs
                        -- ClassID 15/subclass 2 (Companion Pets), 15/subclass 5 (Mount), 17 (Battle Pets)
                        -- Note: classID 15/subclass 0 includes toys but also junk - CheckNewCollectible handles filtering
                        if (classID == 17 or classID == 15) and self.CheckNewCollectible then
                            local newCollectible = self:CheckNewCollectible(itemInfo.itemID, itemInfo.hyperlink)
                            if newCollectible then
                                -- Fire notification event
                                if self.SendMessage then
                                    self:SendMessage("WN_COLLECTIBLE_OBTAINED", newCollectible)
                                end
                            end
                        end
                        
                        -- Special handling for Battle Pets (classID 17)
                        local displayName = itemName
                        local displayIcon = itemInfo.iconFileID or itemTexture
                        
                        if classID == 17 and itemInfo.hyperlink then
                            local petName = itemInfo.hyperlink:match("%[(.-)%]")
                            if petName and petName ~= "" and petName ~= "Pet Cage" then
                                displayName = petName
                            end
                        end
                        
                        self.db.char.bags.items[bagIndex][slotID] = {
                            itemID = itemInfo.itemID,
                            itemLink = itemInfo.hyperlink,
                            stackCount = itemInfo.stackCount or 1,
                            quality = itemInfo.quality or itemQuality or 0,
                            iconFileID = displayIcon,
                            name = displayName,
                            classID = classID,
                            actualBagID = bagID,
                        }
                    end
                end
            end
        end  -- End shouldSkip check
    end  -- End bag loop
    
    -- Update metadata (only on full scan)
    if isFullScan then
        self.db.char.bags.lastScan = time()
        self.db.char.bags.totalSlots = totalSlots
        self.db.char.bags.usedSlots = usedSlots
        
        -- Copy to global database for Storage tab
        if self.SaveCurrentCharacterData then
            self:SaveCurrentCharacterData()
        end
    end
    
    -- Fire event for UI refresh
    if self.SendMessage then
        self:SendMessage("WN_BAGS_UPDATED")
    end
    
    return true
end

--[[
    Get CURRENT character's inventory bag items as flat list for Items tab
    @return table - Array of items with metadata
]]
function WarbandNexus:GetCharacterBagItems()
    local items = {}
    
    -- Get current character's bags
    if not self.db.char.bags or not self.db.char.bags.items then
        return items
    end
    
    for bagIndex, bagData in pairs(self.db.char.bags.items) do
        for slotID, item in pairs(bagData) do
            if item.itemID then
                -- Add metadata for Items tab display
                item.bagIndex = bagIndex
                item.slotID = slotID
                table.insert(items, item)
            end
        end
    end
    
    return items
end

--[[
    Get item counts across all characters (for tooltip injection)
    Searches Warband Bank, Personal Banks, and Character Bags
    @param itemID number - Item ID to search for
    @return table - Array of {charName, classFile, count} sorted by count descending
]]
function WarbandNexus:GetItemCountsAcrossCharacters(itemID)
    local counts = {}
    local warbandTotal = 0
    
    -- Check Warband Bank (shared, count once)
    local warbandData = self:GetWarbandBankV2()
    if warbandData and warbandData.items then
        for bagID, bagData in pairs(warbandData.items) do
            for slotID, item in pairs(bagData) do
                if item.itemID == itemID then
                    warbandTotal = warbandTotal + (item.stackCount or 1)
                end
            end
        end
    end
    
    -- Add Warband Bank as first entry if items found
    if warbandTotal > 0 then
        table.insert(counts, {
            charName = "Warband Bank",
            classFile = nil,  -- No class color
            count = warbandTotal,
        })
    end
    
    -- Check each character's personal bank and bags
    for charKey, charData in pairs(self.db.global.characters or {}) do
        local charTotal = 0
        
        -- Check Personal Bank
        local personalBank = self:GetPersonalBankV2(charKey)
        if personalBank then
            for bagID, bagData in pairs(personalBank) do
                for slotID, item in pairs(bagData) do
                    if item.itemID == itemID then
                        charTotal = charTotal + (item.stackCount or 1)
                    end
                end
            end
        end
        
        -- Check Character Bags
        if charData.bags and charData.bags.items then
            for bagID, bagData in pairs(charData.bags.items) do
                for slotID, item in pairs(bagData) do
                    if item.itemID == itemID then
                        charTotal = charTotal + (item.stackCount or 1)
                    end
                end
            end
        end
        
        if charTotal > 0 then
            table.insert(counts, {
                charName = charKey:match("^([^-]+)"),  -- Extract name (before dash)
                classFile = charData.classFile or charData.class,
                count = charTotal,
            })
        end
    end
    
    -- Sort by count descending
    table.sort(counts, function(a, b) return a.count > b.count end)
    
    return counts
end

-- Enhanced version with separate warband bank, personal bank, and bag counts. Cached to avoid lag on every tooltip hover.
function WarbandNexus:GetDetailedItemCounts(itemID)
    if not itemID then return nil end
    local cacheKey = tostring(itemID)
    local ent = itemCountCache[cacheKey]
    if ent and (GetTime() - ent.ts) < ITEM_COUNT_CACHE_TTL then
        return ent.details
    end

    local result = {
        warbandBank = 0,
        personalBankTotal = 0,
        characters = {}  -- {charName, classFile, bagCount, bankCount}
    }
    
    -- Check Warband Bank (shared, count once)
    local warbandData = self:GetWarbandBankV2()
    if warbandData and warbandData.items then
        for bagID, bagData in pairs(warbandData.items) do
            for slotID, item in pairs(bagData) do
                if item.itemID == itemID then
                    result.warbandBank = result.warbandBank + (item.stackCount or 1)
                end
            end
        end
    end
    
    -- Get current character key for live scanning
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- Check each character's personal bank and bags separately
    for charKey, charData in pairs(self.db.global.characters or {}) do
        local bankCount = 0
        local bagCount = 0
        local isCurrentChar = (charKey == currentCharKey)
        
        -- Check Personal Bank
        local personalBank = self:GetPersonalBankV2(charKey)
        if personalBank then
            for bagID, bagData in pairs(personalBank) do
                for slotID, item in pairs(bagData) do
                    if item.itemID == itemID then
                        bankCount = bankCount + (item.stackCount or 1)
                    end
                end
            end
        end
        
        -- Check Character Bags
        if isCurrentChar then
            -- LIVE SCAN for current character (most accurate, includes items just picked up)
            if C_Container and C_Container.GetContainerNumSlots then
                -- Scan all bags: 0 (backpack), 1-4 (bags), 5 (reagent bag)
                for bagID = 0, 5 do
                    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
                    for slotID = 1, numSlots do
                        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                        if itemInfo and itemInfo.itemID == itemID then
                            bagCount = bagCount + (itemInfo.stackCount or 1)
                        end
                    end
                end
            end
        else
            -- Use cached data for other characters
            if charData.bags and charData.bags.items then
                for bagID, bagData in pairs(charData.bags.items) do
                    for slotID, item in pairs(bagData) do
                        if item.itemID == itemID then
                            bagCount = bagCount + (item.stackCount or 1)
                        end
                    end
                end
            end
        end
        
        if bankCount > 0 or bagCount > 0 then
            result.personalBankTotal = result.personalBankTotal + bankCount
            table.insert(result.characters, {
                charName = charKey:match("^([^-]+)"),  -- Extract name (before dash)
                classFile = charData.classFile or charData.class,
                bagCount = bagCount,
                bankCount = bankCount,
                total = bagCount + bankCount
            })
        end
    end
    
    -- Sort: Current character first, then by total count descending
    table.sort(result.characters, function(a, b)
        local aIsCurrent = (a.charName == currentPlayerName)
        local bIsCurrent = (b.charName == currentPlayerName)
        
        if aIsCurrent and not bIsCurrent then
            return true  -- Current character always first
        elseif bIsCurrent and not aIsCurrent then
            return false
        else
            return a.total > b.total  -- Otherwise sort by count
        end
    end)

    itemCountCache[cacheKey] = { details = result, ts = GetTime() }
    return result
end
--[[
============================================================================
BAG & BANK SCANNING ARCHITECTURE (Service Layer)
============================================================================

This module owns ALL bag and bank scanning logic:
- Warband Bank (ScanWarbandBank)
- Personal Bank (ScanPersonalBank)
- Character Bags/Inventory (ScanCharacterBags)

EVENT FLOW:
1. WoW fires: BAG_UPDATE, BAG_UPDATE_DELAYED, BANKFRAME_OPENED
2. Core.lua handles events (with throttling/debounce)
3. Core.lua calls DataService scan methods WITH SPECIFIC bagIDs
4. DataService performs INCREMENTAL scan (only changed bags)
5. DataService stores in db.char / db.global
6. DataService fires internal events: WN_BAGS_UPDATED, WN_BANK_UPDATED
7. UI modules subscribe to internal events, read from db

PERFORMANCE OPTIMIZATIONS:
- INCREMENTAL SCANNING: Only scan bags that changed (not all)
  Example: Bag 1 changes â†’ scan ONLY Bag 1 (not 0-5)
  Example: Warband Tab 2 changes â†’ scan ONLY Tab 2 (not all 5 tabs)
- Fingerprint system (GetBagFingerprint in Core.lua) detects changes
- Event throttling via AceBucket (0.15s for BAG_UPDATE)
- Debouncing for bulk operations (1s delay for BAG_UPDATE_DELAYED)
- C_Container.HasContainerItem() skips empty slots
- Merge updates into existing cache (don't wipe on partial scan)

BACKWARD COMPATIBILITY:
- nil specificBagIDs = Full scan (all bags)
- table specificBagIDs = Incremental scan (only specified bags)
============================================================================
]]

-- Local references for performance
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local time = time

--[[
    Scan Warband Bank (Account-wide storage)
    
    @param specificBagIDs table|nil - Optional: Specific bag IDs to scan
                                      nil = Full scan (all warband bags)
                                      {14, 15} = Scan only tabs 2 and 3
    @return boolean - Success status
]]
function WarbandNexus:ScanWarbandBank(specificBagIDs)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("items") then
        return false
    end
    
    -- Initialize structure if needed
    if not self.db.global.warbandBank then
        self.db.global.warbandBank = { items = {}, gold = 0, silver = 0, copper = 0, lastScan = 0 }
    end
    if not self.db.global.warbandBank.items then
        self.db.global.warbandBank.items = {}
    end
    
    -- Determine which bags to scan
    local bagsToScan
    local isFullScan = (specificBagIDs == nil)
    
    if isFullScan then
        -- Full scan: Verify bank is accessible
        local isOpen = ns.Utilities:IsWarbandBankOpen(self)
        if not isOpen then
            local firstBagID = Enum.BagIndex.AccountBankTab_1
            local numSlots = self:API_GetBagSize(firstBagID)
            if not numSlots or numSlots == 0 then
                return false
            end
        end
        
        -- Clear cache on full scan
        wipe(self.db.global.warbandBank.items)
        bagsToScan = ns.WARBAND_BAGS -- All warband bags
    else
        -- Incremental scan: Only specified bags
        -- DON'T wipe cache - we'll merge updates
        bagsToScan = specificBagIDs
    end
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Scan specified bags
    for _, bagID in ipairs(bagsToScan) do
        -- Find tabIndex from bagID
        local tabIndex = nil
        for idx, wbBagID in ipairs(ns.WARBAND_BAGS) do
            if wbBagID == bagID then
                tabIndex = idx
                break
            end
        end
        
        -- SKIP IGNORED TABS (Settings UI integration)
        local shouldSkip = false
        if tabIndex and self.db.profile.ignoredTabs and self.db.profile.ignoredTabs[tabIndex] then
            shouldSkip = true
        end
        
        if not shouldSkip and tabIndex then
            -- Initialize tab if needed
            if not self.db.global.warbandBank.items[tabIndex] then
                self.db.global.warbandBank.items[tabIndex] = {}
            else
                -- Clear this tab's data (incremental update)
                wipe(self.db.global.warbandBank.items[tabIndex])
            end
            
            -- Use API wrapper (TWW compatible)
            local numSlots = self:API_GetBagSize(bagID)
            totalSlots = totalSlots + numSlots
            
            for slotID = 1, numSlots do
                local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    -- Get extended item info
                    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                          _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemInfo.itemID)
                    
                    -- Special handling for Battle Pets (classID 17)
                    local displayName = itemName
                    local displayIcon = itemInfo.iconFileID or itemTexture
                    
                    if classID == 17 and itemInfo.hyperlink then
                        local petName = itemInfo.hyperlink:match("%[(.-)%]")
                        if petName and petName ~= "" and petName ~= "Pet Cage" then
                            displayName = petName
                            
                            local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                            if speciesID and C_PetJournal then
                                local _, petIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                                if petIcon then
                                    displayIcon = petIcon
                                end
                            end
                        end
                    end
                    
                    self.db.global.warbandBank.items[tabIndex][slotID] = {
                        itemID = itemInfo.itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality or itemQuality or 0,
                        iconFileID = displayIcon,
                        name = displayName,
                        itemLevel = itemLevel,
                        itemType = itemType,
                        itemSubType = itemSubType,
                        classID = classID,
                        subclassID = subclassID,
                    }
                end
            end
        end
    end
    
    -- Update metadata (only on full scan)
    if isFullScan then
        self.db.global.warbandBank.lastScan = time()
        self.db.global.warbandBank.totalSlots = totalSlots
        self.db.global.warbandBank.usedSlots = usedSlots
        
        -- Get Warband bank gold
        if C_Bank and C_Bank.FetchDepositedMoney then
            local totalCopper = math.floor(C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0)
            self.db.global.warbandBank.gold = math.floor(totalCopper / 10000)
            self.db.global.warbandBank.silver = math.floor((totalCopper % 10000) / 100)
            self.db.global.warbandBank.copper = math.floor(totalCopper % 100)
        end
        
        -- Update V2 storage
        if self.UpdateWarbandBankV2 then
            self:UpdateWarbandBankV2(self.db.global.warbandBank)
        end
    end
    
    -- Fire event for UI refresh
    if self.SendMessage then
        self:SendMessage("WN_BAGS_UPDATED")
    end
    
    return true
end

--[[
    Scan Personal Bank (Character-specific bank storage)
    
    @param specificBagIDs table|nil - Optional: Specific bag IDs to scan
                                      nil = Full scan (all bank bags)
                                      {-1, 6} = Scan only main bank + bag 1
    @return boolean - Success status
]]
function WarbandNexus:ScanPersonalBank(specificBagIDs)
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("items") then
        return false
    end
    
    -- Initialize structure
    if not self.db.char.personalBank then
        self.db.char.personalBank = { items = {}, lastScan = 0 }
    end
    if not self.db.char.personalBank.items then
        self.db.char.personalBank.items = {}
    end
    
    -- Determine which bags to scan
    local bagsToScan
    local isFullScan = (specificBagIDs == nil)
    
    if isFullScan then
        -- Full scan: Verify bank is accessible
        local mainBankSlots = self:API_GetBagSize(Enum.BagIndex.Bank or -1)
        if mainBankSlots == 0 and not self.bankIsOpen then
            return false
        end
        
        -- Clear cache on full scan
        wipe(self.db.char.personalBank.items)
        bagsToScan = ns.PERSONAL_BANK_BAGS -- All personal bank bags
    else
        -- Incremental scan: Only specified bags
        bagsToScan = specificBagIDs
    end
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Scan specified bags
    for _, bagID in ipairs(bagsToScan) do
        -- Find bagIndex from bagID
        local bagIndex = nil
        for idx, pbBagID in ipairs(ns.PERSONAL_BANK_BAGS) do
            if pbBagID == bagID then
                bagIndex = idx
                break
            end
        end
        
        -- SKIP IGNORED BAGS (Settings UI integration)
        local shouldSkip = false
        if self.db.profile.ignoredPersonalBankBags and self.db.profile.ignoredPersonalBankBags[bagID] then
            shouldSkip = true
        end
        
        if not shouldSkip and bagIndex then
            -- Initialize bag if needed
            if not self.db.char.personalBank.items[bagIndex] then
                self.db.char.personalBank.items[bagIndex] = {}
            else
                -- Clear this bag's data (incremental update)
                wipe(self.db.char.personalBank.items[bagIndex])
            end
            
            -- Use API wrapper (TWW compatible)
            local numSlots = self:API_GetBagSize(bagID)
            totalSlots = totalSlots + numSlots
            
            for slotID = 1, numSlots do
                local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    -- Get extended item info
                    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                          _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemInfo.itemID)
                    
                    -- Special handling for Battle Pets (classID 17)
                    local displayName = itemName
                    local displayIcon = itemInfo.iconFileID or itemTexture
                    
                    if classID == 17 and itemInfo.hyperlink then
                        local petName = itemInfo.hyperlink:match("%[(.-)%]")
                        if petName and petName ~= "" and petName ~= "Pet Cage" then
                            displayName = petName
                            
                            local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                            if speciesID and C_PetJournal then
                                local _, petIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                                if petIcon then
                                    displayIcon = petIcon
                                end
                            end
                        end
                    end
                    
                    self.db.char.personalBank.items[bagIndex][slotID] = {
                        itemID = itemInfo.itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality or itemQuality or 0,
                        iconFileID = displayIcon,
                        name = displayName,
                        itemLevel = itemLevel,
                        itemType = itemType,
                        itemSubType = itemSubType,
                        classID = classID,
                        subclassID = subclassID,
                        actualBagID = bagID, -- Store for item movement tracking
                    }
                end
            end
        end  -- End shouldSkip check
    end  -- End bag loop
    
    -- Update metadata (only on full scan)
    if isFullScan then
        self.db.char.personalBank.lastScan = time()
        self.db.char.personalBank.totalSlots = totalSlots
        self.db.char.personalBank.usedSlots = usedSlots
        
        -- Copy to global database for Storage tab
        if self.SaveCurrentCharacterData then
            self:SaveCurrentCharacterData()
        end
    end
    
    -- Fire event for UI refresh
    if self.SendMessage then
        self:SendMessage("WN_BAGS_UPDATED")
    end
    
    return true
end

--[[
    Get all Warband Bank items as a flat list
    
    @param groupByCategory boolean - If true, group items by category
    @return table - Array of items (or grouped categories)
]]
function WarbandNexus:GetWarbandBankItems(groupByCategory)
    local items = {}
    
    -- CRITICAL: Use ItemsCacheService (new unified storage)
    if not self.GetWarbandBankData then
        return items  -- ItemsCacheService not loaded yet
    end
    
    local warbandData = self:GetWarbandBankData()
    if not warbandData or not warbandData.items then
        return items
    end
    
    -- ItemsCacheService returns: { items = {}, lastUpdate = 0 }
    -- Add source metadata for UI
    for _, item in ipairs(warbandData.items) do
        if item.itemID then
            item.tabIndex = item.tabIndex
            item.slotID = item.slotIndex
            item.source = "warband"
            table.insert(items, item)
        end
    end
    
    -- Sort by quality (highest first), then name
    table.sort(items, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then
            return (a.quality or 0) > (b.quality or 0)
        end
        -- Extract name for sorting (handle missing names)
        local aName = a.name
        if not aName and a.link then
            aName = a.link:match("%[(.-)%]")
        end
        local bName = b.name
        if not bName and b.link then
            bName = b.link:match("%[(.-)%]")
        end
        return (aName or "") < (bName or "")
    end)
    
    if groupByCategory then
        return self:GroupItemsByCategory(items)
    end
    
    return items
end

--[[
    Search items in Warband bank by name
    
    @param searchTerm string - Search query
    @return table - Array of matching items
]]
function WarbandNexus:SearchWarbandItems(searchTerm)
    local allItems = self:GetWarbandBankItems()
    local results = {}
    
    if not searchTerm or searchTerm == "" then
        return allItems
    end
    
    searchTerm = searchTerm:lower()
    
    for _, item in ipairs(allItems) do
        if item.name and item.name:lower():find(searchTerm, 1, true) then
            tinsert(results, item)
        end
    end
    
    return results
end

--[[
    Get bank statistics (slots, items, gold)
    
    CRITICAL CONTRACT: This function MUST always return a valid stats table with ALL fields initialized.
    UI modules depend on these fields existing (even if 0) to prevent nil comparison errors.
    
    @return table - Statistics for warband, personal, and guild banks
        Structure: {
            warband = { totalSlots, usedSlots, freeSlots, itemCount, gold, lastScan },
            personal = { totalSlots, usedSlots, freeSlots, itemCount, lastScan },
            guild = { totalSlots, usedSlots, freeSlots, itemCount, lastScan }
        }
        All numeric fields default to 0 if data unavailable.
]]
function WarbandNexus:GetBankStatistics()
    -- Initialize with safe defaults (never return nil fields)
    local stats = {
        warband = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            gold = 0,
            lastScan = 0,
        },
        personal = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            lastScan = 0,
        },
        guild = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            lastScan = 0,
        },
    }
    
    -- ===== WARBAND BANK (from new ItemsCacheService compressed storage) =====
    local warbandData = self.GetWarbandBankData and self:GetWarbandBankData()
    if warbandData and warbandData.items and #warbandData.items > 0 then
        stats.warband.usedSlots = #warbandData.items
        for _, item in ipairs(warbandData.items) do
            stats.warband.itemCount = stats.warband.itemCount + (item.stackCount or 1)
        end
        stats.warband.lastScan = warbandData.lastUpdate or 0
    end
    -- Live API for total warband bank slots (works even when bank is closed in TWW)
    local WARBAND_BAGS = ns.WARBAND_BAGS or {13, 14, 15, 16, 17}
    for _, bagID in ipairs(WARBAND_BAGS) do
        stats.warband.totalSlots = stats.warband.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    -- If API returned 0 (no purchased tabs), use stored item count as minimum
    if stats.warband.totalSlots == 0 and stats.warband.usedSlots > 0 then
        stats.warband.totalSlots = stats.warband.usedSlots
    end
    stats.warband.freeSlots = math.max(0, stats.warband.totalSlots - stats.warband.usedSlots)
    
    -- ===== PERSONAL STORAGE (inventory bags + personal bank from ItemsCacheService) =====
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
        or (UnitName("player") .. "-" .. GetRealmName())
    local itemsData = self.GetItemsData and self:GetItemsData(charKey)
    if itemsData then
        -- Count occupied slots and item stacks from bags
        local bagSlots = itemsData.bags and #itemsData.bags or 0
        local bankSlots = itemsData.bank and #itemsData.bank or 0
        stats.personal.usedSlots = bagSlots + bankSlots
        
        for _, item in ipairs(itemsData.bags or {}) do
            stats.personal.itemCount = stats.personal.itemCount + (item.stackCount or 1)
        end
        for _, item in ipairs(itemsData.bank or {}) do
            stats.personal.itemCount = stats.personal.itemCount + (item.stackCount or 1)
        end
        
        stats.personal.lastScan = math.max(itemsData.bagsLastUpdate or 0, itemsData.bankLastUpdate or 0)
    end
    -- Live API for total personal slots (inventory bags always accessible)
    local INVENTORY_BAGS = ns.INVENTORY_BAGS or {0, 1, 2, 3, 4, 5}
    local BANK_BAGS = ns.PERSONAL_BANK_BAGS or {-1, 6, 7, 8, 9, 10, 11}
    for _, bagID in ipairs(INVENTORY_BAGS) do
        stats.personal.totalSlots = stats.personal.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    for _, bagID in ipairs(BANK_BAGS) do
        stats.personal.totalSlots = stats.personal.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    -- If API returned 0 for everything, use stored item count as minimum
    if stats.personal.totalSlots == 0 and stats.personal.usedSlots > 0 then
        stats.personal.totalSlots = stats.personal.usedSlots
    end
    stats.personal.freeSlots = math.max(0, stats.personal.totalSlots - stats.personal.usedSlots)
    
    -- ===== GUILD BANK (legacy format - scanned when guild bank is opened) =====
    local guildName = GetGuildInfo("player")
    if guildName and self.db.global.guildBank and self.db.global.guildBank[guildName] then
        local guildData = self.db.global.guildBank[guildName]
        stats.guild.totalSlots = guildData.totalSlots or 0
        stats.guild.usedSlots = guildData.usedSlots or 0
        stats.guild.freeSlots = stats.guild.totalSlots - stats.guild.usedSlots
        stats.guild.lastScan = guildData.lastScan or 0
        
        -- Count items from all tabs
        for _, tabData in pairs(guildData.tabs or {}) do
            for _, itemData in pairs(tabData.items or {}) do
                stats.guild.itemCount = stats.guild.itemCount + (itemData.stackCount or 1)
            end
        end
    end
    
    return stats
end

-- DataService.lua loaded successfully (Refactored 2026-01-27)
if WarbandNexus then
    WarbandNexus._dataServiceLoaded = true
    WarbandNexus._dataServiceVersion = "1.0.0"
end
