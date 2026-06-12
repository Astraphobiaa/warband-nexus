--[[
    Warband Nexus - Data Service Module
    Character orchestration, cross-character aggregation, and legacy cache wrappers.
    Domain caches: PvECacheService, ItemsCacheService, CurrencyCacheService, ReputationCacheService.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS

-- Midnight 12.0+: currency list link / names may be secret in some contexts.
local issecretvalue = issecretvalue
local Utilities = ns.Utilities
local function CmpCharName(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
end

-- Unique AceEvent handler identity for DataService
-- Prevents overwriting other modules' handlers for the same message.
local DataServiceEvents = {}

-- Roster helpers: DataService_RosterHelpers.lua (ns.DataServiceRoster)
local Roster = ns.DataServiceRoster
local _allCharsRosterCache = Roster and Roster.cache or { sig = nil, list = nil }
local ComputeCharactersRosterSig = Roster and Roster.ComputeCharactersRosterSig
local InvalidateGetAllCharactersCache = Roster and Roster.InvalidateGetAllCharactersCache
local SafeGetMoneyCopperFromEntry = Roster and Roster.SafeGetMoneyCopperFromEntry
local RelocateLegacyCharacterSlot = Roster and Roster.RelocateLegacyCharacterSlot
local tableToItemArrayForStorage = Roster and Roster.tableToItemArrayForStorage

-- Debug print helper
-- Rested XP accumulation constants (Blizzard behavior in resting areas).
-- Pandaren "Inner Peace" racial doubles both the cap and accumulation rate.
local RESTED_XP_GAIN_PER_8H = 0.05
local SECONDS_PER_8H = 8 * 60 * 60
local CollectRestedData

local function GetRestedCapMultiplier(raceFile)
    return (raceFile == "Pandaren") and 3.0 or 1.5
end

local function GetRestedAccumulationMultiplier(raceFile)
    return (raceFile == "Pandaren") and 2 or 1
end

-- PLAYED TIME TRACKING
--[[
    Track cumulative /played time per character using RequestTimePlayed() API.
    TIME_PLAYED_MSG fires asynchronously with (totalTimePlayed, timePlayedThisLevel).
    Chat lines: ChatFrameUtil.DisplayTimePlayed wrap (Mainline), legacy globals,
    CHAT_MSG_SYSTEM backup, and Chattynator.API.FilterTimePlayed when Chattynator
    is loaded (its Messages frame has its own TIME_PLAYED_MSG listener).
    See notifications.hidePlayedTimeInChat (default: hide).
]]

--- Request played time from server (for internal DB; chat lines controlled by profile filter).
function WarbandNexus:RequestPlayedTime()
    RequestTimePlayed()
end

--- Handle TIME_PLAYED_MSG event.
function WarbandNexus:OnTimePlayedReceived(event, totalTimePlayed, timePlayedThisLevel)
    if totalTimePlayed == nil then return end
    if issecretvalue and issecretvalue(totalTimePlayed) then return end
    local played = tonumber(totalTimePlayed)
    if not played or played <= 0 then return end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end
    if not self.db or not self.db.global or not self.db.global.characters then return end

    local rawKey = ns.Utilities:GetCharacterKey()
    if not rawKey then return end

    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then tableKey = resolved end
    end

    local charData = self.db.global.characters[tableKey]
    if not charData then return end

    charData.timePlayed = played

    local msgKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)) or rawKey
    -- Fire event so UI refreshes
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = msgKey,
    })
end

-- PVE LOADING STATE MANAGEMENT
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



-- CHARACTER DATA CACHE (Session-based, Event-driven)
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

--- Invalidate cached roster array from GetAllCharacters (character DB changed).
function WarbandNexus:InvalidateGetAllCharactersCache()
    InvalidateGetAllCharactersCache()
end

--- Trustworthy age since last roster row update; nil when lastSeen is missing or invalid (never treat as infinitely stale).
function WarbandNexus:GetCharacterLastSeenAge(char, currentTime)
    if type(char) ~= "table" then return nil end
    local lastSeen = char.lastSeen
    if type(lastSeen) ~= "number" or lastSeen <= 0 then
        return nil
    end
    local age = (currentTime or time()) - lastSeen
    if age < 0 then return nil end
    return age
end

--- Auto-prune only explicit untracked roster rows (`isTracked == false`) with valid lastSeen past threshold.
--- Tracked rows (`isTracked` nil/true) and unknown-age rows are never removed here.
function WarbandNexus:IsCharacterEligibleForStaleRemoval(char, thresholdSeconds, currentTime)
    if type(char) ~= "table" then return false end
    if not thresholdSeconds or thresholdSeconds <= 0 then return false end
    if char.isTracked ~= false then return false end
    local age = self:GetCharacterLastSeenAge(char, currentTime)
    if not age then return false end
    return age > thresholdSeconds
end

--- Repair missing name/realm/class display fields from legacy Name-Realm storage keys.
function WarbandNexus:RepairCharacterRowFromKey(charKey, charData)
    if type(charData) ~= "table" then return false end
    local repaired = false
    local U = ns.Utilities
    if U and U.SplitCharacterKey and charKey and type(charKey) == "string" then
        if not (issecretvalue and issecretvalue(charKey)) then
            if (not charData.name or charData.name == "") or (not charData.realm or charData.realm == "") then
                local n, r = U:SplitCharacterKey(charKey)
                if n and n ~= "" and (not charData.name or charData.name == "") then
                    charData.name = n
                    repaired = true
                end
                if r and r ~= "" and (not charData.realm or charData.realm == "") then
                    charData.realm = r
                    repaired = true
                end
            end
        end
    end
    if (not charData.class or charData.class == "") and charData.classFile and charData.classFile ~= "" then
        if not (issecretvalue and issecretvalue(charData.classFile)) then
            charData.class = charData.classFile
            repaired = true
        end
    end
    return repaired
end

--- Row lacks minimum identity for roster display after optional repair.
function WarbandNexus:IsCharacterRowStructurallyInvalid(charKey, charData)
    if type(charData) ~= "table" then return true end
    self:RepairCharacterRowFromKey(charKey, charData)
    local name, realm = charData.name, charData.realm
    if issecretvalue then
        if name and issecretvalue(name) then name = nil end
        if realm and issecretvalue(realm) then realm = nil end
    end
    local hasNameRealm = name and name ~= "" and realm and realm ~= ""
    local g = charData.guid
    local hasGuid = type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g))
    if not hasNameRealm and not hasGuid then return true end
    local cls, clsFile = charData.class, charData.classFile
    if issecretvalue then
        if cls and issecretvalue(cls) then cls = nil end
        if clsFile and issecretvalue(clsFile) then clsFile = nil end
    end
    if (not cls or cls == "") and (not clsFile or clsFile == "") then
        return not hasGuid
    end
    return false
end

---Get comprehensive character data from DB
---DIRECT DB READ - No sessionCache (API > DB > UI pattern)
---@param forceRefresh boolean|nil Deprecated (kept for compatibility)
---@return table Character data from db.global.characters
function WarbandNexus:GetCharacterData(forceRefresh)
    local rawKey = ns.Utilities:GetCharacterKey()
    if not rawKey then return {} end
    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then tableKey = resolved end
    end
    if not self.db.global.characters or not self.db.global.characters[tableKey] then
        return {}
    end
    return self.db.global.characters[tableKey]
end

---Update character data in DB (called by event handlers)
---DIRECT DB WRITE - No sessionCache (API > DB > UI pattern)
---@param dataType string Specific data type to update ("gold", "level", "spec", "itemLevel", etc.)
function WarbandNexus:UpdateCharacterCache(dataType)
    local rawKey = ns.Utilities:GetCharacterKey()
    if not rawKey then return end
    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then tableKey = resolved end
    end
    if not self.db.global.characters or not self.db.global.characters[tableKey] then
        return
    end
    -- GUARD: Only tracked characters get full updates (gold, level, spec, etc.)
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    local charData = self.db.global.characters[tableKey]
    
    -- Update specific data type in DB
    if dataType == "gold" then
        local totalCopper = SafeGetMoneyCopperFromEntry(charData)
        local gold = math.floor(totalCopper / 10000)
        local silver = math.floor((totalCopper % 10000) / 100)
        local copper = math.floor(totalCopper % 100)
        
        charData.gold = gold
        charData.silver = silver
        charData.copper = copper
        
    elseif dataType == "level" then
        local lv = UnitLevel("player")
        if issecretvalue and lv and issecretvalue(lv) then return end
        charData.level = lv
        
    elseif dataType == "spec" then
        local specIndex = GetSpecialization()
        if specIndex and GetSpecializationInfo then
            local specID, specName, _, specIcon = GetSpecializationInfo(specIndex)
            charData.specID = specID
            charData.specName = specName
            charData.specIcon = specIcon
        end
        -- Hero Talent (Midnight 12.0+): active hero spec subclass name
        if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
            local heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
            if heroSpecID and not (issecretvalue and issecretvalue(heroSpecID)) then
                charData.heroSpecID = heroSpecID
                if C_ClassTalents.GetHeroTalentSpecInfo then
                    local heroInfo = C_ClassTalents.GetHeroTalentSpecInfo(heroSpecID)
                    if heroInfo then
                        charData.heroSpecName = heroInfo.name
                    end
                end
            end
        end
        
    elseif dataType == "itemLevel" then
        local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
        if issecretvalue and avgItemLevelEquipped and issecretvalue(avgItemLevelEquipped) then return end
        local newItemLevel = math.floor(avgItemLevelEquipped or 0)
        
        charData.itemLevel = newItemLevel
        
    elseif dataType == "guild" then
        local gn = IsInGuild() and GetGuildInfo("player") or nil
        if gn and issecretvalue and issecretvalue(gn) then gn = nil end
        charData.guildName = gn

    elseif dataType == "zone" then
        charData.zoneName = GetZoneText()
        charData.subZoneName = GetSubZoneText()
    elseif dataType == "rested" then
        local newRested = CollectRestedData()
        local existingRested = charData.rested
        -- Preserve maxXP when API returned nil so we don't overwrite good DB value
        if newRested and (newRested.maxXP == nil or newRested.maxXP == 0) and type(existingRested) == "table" and type(existingRested.maxXP) == "number" and existingRested.maxXP > 0 then
            newRested.maxXP = existingRested.maxXP
            local capMul = GetRestedCapMultiplier(charData.raceFile)
            newRested.restedCapXP = math.floor(existingRested.maxXP * capMul)
        end
        charData.rested = newRested
    end
    
    -- Update lastSeen timestamp
    charData.lastSeen = time()
    
    local msgKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)) or rawKey
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
    end
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = msgKey,
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
    local DataServiceMsgListeners = ns._dataServiceMsgListeners or {}
    ns._dataServiceMsgListeners = DataServiceMsgListeners
    WarbandNexus.RegisterMessage(DataServiceMsgListeners, E.MONEY_UPDATED, function()
        self:UpdateCharacterCache("gold")
    end)
    
    -- Level changes
    self:RegisterEvent("PLAYER_LEVEL_UP", function(event)
        self:UpdateCharacterCache("level")
        self:UpdateCharacterCache("rested")
    end)
    
    -- Specialization changes
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(event)
        self:UpdateCharacterCache("spec")
    end)
    
    -- PLAYER_EQUIPMENT_CHANGED: owned by EventManager (OnItemLevelChanged, throttled)
    -- NOTE: WN_CHARACTER_UPDATED empty handler REMOVED — it was a no-op that overwrote
    -- real handlers in other modules (AceEvent allows only one handler per event per self).
    
    -- NOTE: PLAYER_ENTERING_WORLD is NOT registered here.
    -- It fires at T+0s but RegisterCharacterCacheEvents runs at T+2s (too late).
    -- Also, AceEvent allows only one handler per event per self — registering here
    -- would overwrite Core.lua's OnPlayerEnteringWorld handler.
    -- Character save on login is handled by Core.lua raw frame handler (SaveCharacter)
    -- and Core.lua OnEnable (SaveMinimalCharacterData for untracked characters).

    -- Guild membership/name changed (join/leave/switch)
    self:RegisterEvent("PLAYER_GUILD_UPDATE", function(event)
        self:UpdateCharacterCache("guild")
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
        DebouncedZoneUpdate()
    end)
    
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function(event)
        DebouncedZoneUpdate()
    end)

    -- Rested state updates are event-driven from game APIs.
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function(event)
        self:UpdateCharacterCache("rested")
    end)
    self:RegisterEvent("UPDATE_EXHAUSTION", function(event)
        self:UpdateCharacterCache("rested")
    end)
    self:RegisterEvent("PLAYER_XP_UPDATE", function(event, unit)
        if unit and unit ~= "player" then return end
        self:UpdateCharacterCache("rested")
    end)
    
    -- SKILL_LINES_CHANGED: owned by EventManager (OnSkillLinesChanged, throttled)

    -- Invalidate tooltip item count cache when bags/bank change
    -- Listen to internal messages (ItemsCacheService is the single owner of WoW events)
    -- NOTE: Uses DataServiceEvents as 'self' key to avoid overwriting other modules' handlers.
    WarbandNexus.RegisterMessage(DataServiceEvents, E.BAGS_UPDATED, function()
        if WarbandNexus.InvalidateItemSummary then
            local charKey = ns.Utilities:GetCharacterKey()
            WarbandNexus:InvalidateItemSummary(charKey)
        end
    end)
    WarbandNexus.RegisterMessage(DataServiceEvents, E.ITEMS_UPDATED, function()
        if WarbandNexus.InvalidateItemSummary then
            local charKey = ns.Utilities:GetCharacterKey()
            WarbandNexus:InvalidateItemSummary(charKey)
        end
    end)

    WarbandNexus.RegisterMessage(DataServiceEvents, E.CHARACTER_UPDATED, function()
        InvalidateGetAllCharactersCache()
    end)
    WarbandNexus.RegisterMessage(DataServiceEvents, E.CHARACTER_TRACKING_CHANGED, function()
        InvalidateGetAllCharactersCache()
    end)
    
    -- Character cache event handlers registered (verbose logging removed)
end


-- Collection compression helpers: DataService_Compression.lua


-- CHARACTER DATA COLLECTION

--- Collect basic profession data.
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

--- Collect current player stats for persistence (Gear tab offline display).
local function CollectPlayerStats()
    local primary = {}
    for id = 1, 4 do
        local ok, _, total = pcall(UnitStat, "player", id)
        if ok and total and type(total) == "number" then primary[id] = math.floor(total) end
    end
    if not next(primary) then primary = nil end
    -- Snapshot main stat code for Gear tab offline — matches live panel (hero specs / Midnight IDs).
    local mainStatCode = nil
    if WarbandNexus and WarbandNexus.GetCurrentCharacterMainStat then
        mainStatCode = WarbandNexus:GetCurrentCharacterMainStat()
    end
    local L = ns.L
    local secondary = {}
    local secondFns = {
        { label = (L and L["STAT_CRITICAL_STRIKE"]) or "Critical Strike", rating = 9,  pctFn = function() return GetCritChance and GetCritChance() or 0 end },
        { label = (L and L["STAT_HASTE"]) or "Haste",                     rating = 18, pctFn = function() return GetHaste and GetHaste() or 0 end },
        { label = (L and L["STAT_MASTERY"]) or "Mastery",                 rating = 26, pctFn = function() return GetMasteryEffect and select(1, GetMasteryEffect()) or 0 end },
        { label = (L and L["STAT_VERSATILITY"]) or "Versatility",         rating = 29, pctFn = function() return GetCombatRatingBonus and GetCombatRatingBonus(29) or 0 end },
    }
    for i = 1, #secondFns do
        local s = secondFns[i]
        local okR, rating = pcall(GetCombatRating, s.rating)
        local okP, pct = pcall(s.pctFn)
        local rVal = 0
        if okR and type(rating) == "number" then rVal = math.floor(rating) end
        local pVal = (okP and pct and type(pct) == "number") and pct or 0
        secondary[#secondary + 1] = {
            label = s.label,
            rating = rVal,
            pct = pVal,
        }
    end
    if not next(primary) and not next(secondary) then return nil end
    return { primary = primary, secondary = secondary, mainStatCode = mainStatCode }
end

--- Collect rested XP snapshot from API for DB persistence (API > DB > UI).
CollectRestedData = function()
    local exhaustionID, restStateName, restStateFactor = nil, nil, nil
    if GetRestState then
        exhaustionID, restStateName, restStateFactor = GetRestState()
        if issecretvalue and exhaustionID and issecretvalue(exhaustionID) then exhaustionID = nil end
        if issecretvalue and restStateFactor and issecretvalue(restStateFactor) then restStateFactor = nil end
    end

    local rawRestedXP = (GetXPExhaustion and GetXPExhaustion()) or 0
    if issecretvalue and rawRestedXP and issecretvalue(rawRestedXP) then rawRestedXP = 0 end
    local currentRestedXP = rawRestedXP
    local currentXP = UnitXP("player") or 0
    if issecretvalue and issecretvalue(currentXP) then currentXP = 0 end
    if type(currentXP) ~= "number" then currentXP = 0 end
    local maxXPApi = UnitXPMax("player")
    if issecretvalue and issecretvalue(maxXPApi) then maxXPApi = nil end
    local maxXP = (type(maxXPApi) == "number") and maxXPApi or nil
    local _, playerRaceFile = UnitRace("player")
    local capMultiplier = GetRestedCapMultiplier(playerRaceFile)
    local restedCapXP = (maxXP and maxXP > 0) and math.floor(maxXP * capMultiplier) or 0

    return {
        exhaustionID = exhaustionID,
        restStateName = restStateName,
        restStateFactor = restStateFactor,
        isRestingArea = IsResting() and true or false,
        currentRestedXP = math.floor(currentRestedXP),
        currentXP = math.floor(currentXP),
        maxXP = maxXP,
        restedCapXP = restedCapXP,
        updatedAt = time(),
    }
end

--- Save minimal character data for untracked characters (identity + gold/level only).
function WarbandNexus:SaveMinimalCharacterData()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()
    if name and issecretvalue and issecretvalue(name) then return false end
    if realm and issecretvalue and issecretvalue(realm) then return false end
    
    if not name or name == "" or not realm or realm == "" then
        return false
    end
    
    local legacyKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(name, realm)
    local key = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)
        or legacyKey
    if not key then return false end
    local Constants = ns.Constants

    -- Initialize characters table (needed for SafeGetMoneyCopperFromEntry fallback)
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    local chars = self.db.global.characters
    local existingEntry = (chars[key] or (legacyKey and chars[legacyKey])) or nil
    
    -- Get basic character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    if issecretvalue and level and issecretvalue(level) then return false end
    local totalCopper = SafeGetMoneyCopperFromEntry(existingEntry)
    local faction = UnitFactionGroup("player")
    local race, raceFile = UnitRace("player")
    local guildName = IsInGuild() and GetGuildInfo("player") or nil
    if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
    -- Get gender
    local gender = UnitSex("player")
    local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
    if raceInfo and raceInfo.gender ~= nil then
        gender = (raceInfo.gender == 1) and 3 or 2
    end
    if not gender or gender == 0 or gender == 1 then
        gender = 2
    end
    
    -- Validate critical data
    if not classFile or not level or level == 0 then
        return false
    end
    
    -- Convert totalCopper to gold/silver/copper (for compatibility)
    local gold = math.floor(totalCopper / 10000)
    local remainingCopper = totalCopper % 10000
    local silver = math.floor(remainingCopper / 100)
    local copper = remainingCopper % 100
    
    -- Preserve existing tracking flags from the character entry.
    -- SaveMinimalCharacterData can run BEFORE the tracking confirmation popup
    -- is shown (race condition: SaveCharacter at 2s vs popup at 2.5s).
    -- If we overwrite trackingConfirmed here, the popup will never appear.
    local preserveTracked = existingEntry and existingEntry.isTracked
    -- Never coerce nil → false: false is treated like "unconfirmed" by old popups and breaks (not false)==true.
    local preserveConfirmed = existingEntry and existingEntry.trackingConfirmed

    -- Store MINIMAL data only (untracked: strip profession/gear/PvE-style fields; do not call extra collectors)
    chars[key] = {
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
        guildName = guildName,
        race = race,
        raceFile = raceFile,
        gender = gender,
        itemLevel = 0,
        isTracked = preserveTracked or false,
        trackingConfirmed = preserveConfirmed,
        lastSeen = time(),
        mythicKey = nil,
        timePlayed = nil,
        professions = nil,
        concentration = nil,
        recipes = nil,
        professionExpansions = nil,
        discoveredSkillLines = nil,
        knowledgeData = nil,
        professionCooldowns = nil,
        professionEquipment = nil,
        cooldownRecipeIDs = nil,
        craftingOrders = nil,
        professionData = nil,
        rested = nil,
        -- GUID: never call UnitGUID here (untracked / minimal row). Preserve existing SV guid only;
        -- fresh capture happens when the user enables tracking (CharacterService:ConfirmCharacterTracking).
        guid = (function()
            local g = existingEntry and existingEntry.guid
            if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                return g
            end
            return nil
        end)(),
        stats = nil,
        specID = nil,
        specName = nil,
        specIcon = nil,
        heroSpecID = nil,
        heroSpecName = nil,
    }
    RelocateLegacyCharacterSlot(self.db, key, legacyKey)
    -- Fire event for UI refresh
    self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
        charKey = key,
        isTracked = false
    })
    
    return true
end

--- Save complete character data (login/reload and significant changes).
function WarbandNexus:SaveCurrentCharacterData()
    -- Check tracking status
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    
    -- If NOT tracked, save minimal data only
    if not isTracked then
        return self:SaveMinimalCharacterData()
    end
    
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()  -- Get realm name
    if name and issecretvalue and issecretvalue(name) then return false end
    if realm and issecretvalue and issecretvalue(realm) then return false end
    
    -- Safety check
    if not name or name == "" or name == "Unknown" then
        return false
    end
    if not realm or realm == "" then
        return false
    end
    
    local legacyKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(name, realm)
    local key = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)
        or legacyKey
    if not key then return false end

    -- Get character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    if issecretvalue and level and issecretvalue(level) then return false end
    local guildName = IsInGuild() and GetGuildInfo("player") or nil
    if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
    
    -- Store as single totalCopper (Lua number = 64-bit)
    -- GetMoney() may be a secret value in some contexts — use SafeGetMoneyCopperFromEntry
    local chars = self.db.global.characters
    local existingSnapshot = (chars[key] or (legacyKey and chars[legacyKey])) or nil
    local totalCopper = SafeGetMoneyCopperFromEntry(existingSnapshot)

    local faction = UnitFactionGroup("player")
    local race, raceFile = UnitRace("player")  -- race = localized name, raceFile = English ID
    -- Get gender with C_PlayerInfo fallback (more reliable in TWW)
    local gender = UnitSex("player")  -- 2 = male, 3 = female, 1 = neutral/unknown
    
    -- Use C_PlayerInfo if available (more reliable)
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
    local isNew = (existingSnapshot == nil)
    
    -- Collect PvE data (Great Vault, Lockouts, M+)
    local pveData = self:CollectPvEData()
    
    -- Collect Profession data (only if new character or professions don't exist)
    local professionData = nil
    if isNew or not existingSnapshot or not existingSnapshot.professions then
        professionData = self:CollectProfessionData()
        if professionData and next(professionData) then
            ns._professionDataReady = true
        end
    else
        -- Preserve existing profession data (will be updated by SKILL_LINES_CHANGED event if needed)
        professionData = existingSnapshot.professions
        if professionData and next(professionData) then
            ns._professionDataReady = true
        end
    end
    
    -- Get character's average item level (ALWAYS fresh from API)
    local _, avgItemLevelEquipped = GetAverageItemLevel()
    if issecretvalue and avgItemLevelEquipped and issecretvalue(avgItemLevelEquipped) then avgItemLevelEquipped = nil end
    local itemLevel = avgItemLevelEquipped or 0
    
    -- Spec (for offline main stat in Gear tab)
    local specID, specName, specIcon = nil, nil, nil
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx then specID, specName, _, specIcon = GetSpecializationInfo(idx) end
    end
    
    -- Hero Talent (Midnight 12.0+)
    local heroSpecID, heroSpecName = nil, nil
    if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
        heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
        if heroSpecID and not (issecretvalue and issecretvalue(heroSpecID)) then
            if C_ClassTalents.GetHeroTalentSpecInfo then
                local heroInfo = C_ClassTalents.GetHeroTalentSpecInfo(heroSpecID)
                if heroInfo then heroSpecName = heroInfo.name end
            end
        else
            heroSpecID = nil
        end
    end
    
    -- Scan for Mythic Keystone (always scan on login to check if key exists)
    local keystoneData = nil
    if self.ScanMythicKeystone then
        keystoneData = self:ScanMythicKeystone()
    end
    
    local bagsArray = (self.db.char.bags and self.db.char.bags.items) and tableToItemArrayForStorage(self.db.char.bags.items) or nil
    local bankArray = (self.db.char.personalBank and self.db.char.personalBank.items) and tableToItemArrayForStorage(self.db.char.personalBank.items) or nil
    if self.SaveItemsCompressed and key then
        if bagsArray then self:SaveItemsCompressed(key, "bags", bagsArray) end
        if bankArray then self:SaveItemsCompressed(key, "bank", bankArray) end
    end

    -- WoW SavedVariables uses 32-bit integers (max: 2,147,483,647)
    -- totalCopper can exceed this for high-gold characters (>214k gold)
    -- Solution: Store as gold/silver/copper breakdown (smaller numbers)
    local gold = math.floor(totalCopper / 10000)
    local silver = math.floor((totalCopper % 10000) / 100)
    local copper = math.floor(totalCopper % 100)
    
    -- Preserve trackingConfirmed flag from existing entry.
    -- This flag is set by ConfirmCharacterTracking() when user makes a choice.
    -- Without preserving it, every save would lose the user's tracking confirmation.
    local existingEntry = existingSnapshot
    local preserveConfirmed = existingEntry and existingEntry.trackingConfirmed
    local preserveTimePlayed = existingEntry and existingEntry.timePlayed
    -- Preserve profession service data (collected separately by ProfessionService)
    local preserveConcentration       = existingEntry and existingEntry.concentration
    local preserveRecipes             = existingEntry and existingEntry.recipes
    local preserveProfExpansions      = existingEntry and existingEntry.professionExpansions
    local preserveDiscoveredSkillLines = existingEntry and existingEntry.discoveredSkillLines
    local preserveKnowledgeData       = existingEntry and existingEntry.knowledgeData
    local preserveProfessionCooldowns = existingEntry and existingEntry.professionCooldowns
    local preserveProfessionEquipment = existingEntry and existingEntry.professionEquipment
    local preserveCooldownRecipeIDs   = existingEntry and existingEntry.cooldownRecipeIDs
    local preserveCraftingOrders      = existingEntry and existingEntry.craftingOrders
    local preserveProfessionData      = existingEntry and existingEntry.professionData
    local preserveRested              = existingEntry and existingEntry.rested
    local restedData                  = CollectRestedData() or preserveRested
    -- Preserve maxXP when API returned nil so we don't overwrite good DB value with nil/0
    if restedData and (restedData.maxXP == nil or restedData.maxXP == 0) and preserveRested and type(preserveRested.maxXP) == "number" and preserveRested.maxXP > 0 then
        restedData.maxXP = preserveRested.maxXP
        if not restedData.restedCapXP or restedData.restedCapXP == 0 then
            local capMul = GetRestedCapMultiplier(raceFile)
            restedData.restedCapXP = math.floor(preserveRested.maxXP * capMul)
        end
    end

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
        guildName = guildName,
        race = race,
        raceFile = raceFile,
        gender = gender,
        itemLevel = itemLevel,
        mythicKey = keystoneData,
        isTracked = true,     -- Track this character (API calls, data updates enabled)
        -- Preserve the user's explicit choice (false must survive a save or the
        -- tracking popup gets skipped); default true only when no choice exists yet.
        trackingConfirmed = preserveConfirmed == nil and true or preserveConfirmed,
        lastSeen = time(),
        professions = professionData,
        timePlayed = preserveTimePlayed,  -- Preserve played time (updated separately by TIME_PLAYED_MSG)
        -- Preserve profession service data
        concentration        = preserveConcentration,
        recipes              = preserveRecipes,
        professionExpansions = preserveProfExpansions,
        discoveredSkillLines = preserveDiscoveredSkillLines,
        knowledgeData        = preserveKnowledgeData,
        professionCooldowns  = preserveProfessionCooldowns,
        professionEquipment  = preserveProfessionEquipment,
        cooldownRecipeIDs    = preserveCooldownRecipeIDs,
        craftingOrders       = preserveCraftingOrders,
        professionData       = preserveProfessionData,
        rested               = restedData,
        -- GUID: persist stable value; only call SafeGuid when row has no usable guid yet (post-tracking first save).
        guid                 = (function()
            local g = existingEntry and existingEntry.guid
            if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                return g
            end
            if ns.Utilities and ns.Utilities.SafeGuid then
                return ns.Utilities:SafeGuid("player")
            end
            return nil
        end)(),
        stats                = CollectPlayerStats(),  -- For Gear tab offline Character Stats
        specID               = specID,
        specName             = specName,
        specIcon             = specIcon,
        heroSpecID           = heroSpecID,
        heroSpecName         = heroSpecName,
        hasMail              = HasNewMail() and true or false,
    }

    -- After a rename, a stale row may remain under the old character key with the same player GUID.
    if ns.MigrationService and ns.MigrationService.ApplyCharacterKeyedStorageRenames then
        local pg = self.db.global.characters[key] and self.db.global.characters[key].guid
        if type(pg) == "string" and pg ~= "" and not (issecretvalue and issecretvalue(pg)) then
            local renames = {}
            for otherKey, other in pairs(self.db.global.characters) do
                if otherKey ~= key and type(other) == "table" then
                    local og = other.guid
                    if type(og) == "string" and og ~= "" and not (issecretvalue and issecretvalue(og)) and og == pg then
                        renames[otherKey] = key
                    end
                end
            end
            if next(renames) then
                local winnerRow = self.db.global.characters[key]
                for oldKey in pairs(renames) do
                    local loserRow = self.db.global.characters[oldKey]
                    if winnerRow and loserRow and ns.MigrationService.MergeCharacterRowPreserveWinner then
                        ns.MigrationService:MergeCharacterRowPreserveWinner(winnerRow, loserRow)
                    end
                end
                ns.MigrationService:ApplyCharacterKeyedStorageRenames(self.db, renames)
                for oldKey in pairs(renames) do
                    self.db.global.characters[oldKey] = nil
                end
            end
        end
    end

    RelocateLegacyCharacterSlot(self.db, key, legacyKey)

    -- Store PvE data globally (v2 path)
    self:UpdatePvEDataV2(key, pveData)
    
    -- Bags/bank stored via SaveItemsCompressed above (itemStorage); no duplicate in character record or personalBanks from this path
    -- Update currencies to global storage (v2)
    self:UpdateCurrencyData()

    -- Keep equipped-gear cache fresh for Gear tab.
    if self.ScanEquippedGear then
        self:ScanEquippedGear()
    end
    
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
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end
    local success, err = pcall(function()
        local key = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(self)
        if not key and ns.Utilities and ns.Utilities.GetCharacterStorageKey then
            key = ns.Utilities:GetCharacterStorageKey(self)
        end
        if not key and ns.Utilities and ns.Utilities.GetCharacterKey then
            key = ns.Utilities:GetCharacterKey()
        end
        if not key or not self.db.global.characters or not self.db.global.characters[key] then return end

        local newData = self:CollectProfessionData()

        -- Guard: Don't overwrite saved DB data with empty results on login.
        -- GetProfessions() can return nil on login before the profession system is
        -- fully loaded, which would destroy the previous session's saved data.
        -- After the first successful collection, trust empty results (user may have
        -- unlearned all professions).
        if not newData then return end
        if not next(newData) then
            if not ns._professionDataReady then return end
        else
            ns._professionDataReady = true
        end

        self.db.global.characters[key].professions = newData
        self.db.global.characters[key].lastSeen = time()

        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = key,
            dataType = "professions"
        })
    end)
end

function WarbandNexus:UpdateMailStatus()
    local rawKey = ns.Utilities:GetCharacterKey()
    if not rawKey then return end
    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then tableKey = resolved end
    end
    if self.db.global.characters and self.db.global.characters[tableKey] then
        self.db.global.characters[tableKey].hasMail = HasNewMail() and true or false
        local msgKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)) or rawKey
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
        end
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, { charKey = msgKey, dataType = "mail" })
    end
end

--- Update only gold for current character (PLAYER_MONEY; tracked and untracked).
function WarbandNexus:UpdateCharacterGold()
    -- No tracking guard here - gold updates for both tracked and untracked characters
    local rawKey = ns.Utilities:GetCharacterKey()
    if not rawKey then return false end
    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then tableKey = resolved end
    end
    if self.db.global.characters and self.db.global.characters[tableKey] then
        local totalCopper = SafeGetMoneyCopperFromEntry(self.db.global.characters[tableKey])
        local gold = math.floor(totalCopper / 10000)
        local silver = math.floor((totalCopper % 10000) / 100)
        local copper = math.floor(totalCopper % 100)
        self.db.global.characters[tableKey].gold = gold
        self.db.global.characters[tableKey].silver = silver
        self.db.global.characters[tableKey].copper = copper
        self.db.global.characters[tableKey].lastSeen = time()
        local msgKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)) or rawKey
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
        end
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, {
            charKey = msgKey,
            dataType = "gold"
        })
        return true
    end
    return false
end

--- Get all characters (tracked and untracked), sorted by level then name.
function WarbandNexus:GetAllCharacters()
    local characters = {}
    
    if not self.db.global.characters then
        return characters
    end

    local charsTbl = self.db.global.characters
    local rosterSig = ComputeCharactersRosterSig(charsTbl)
    if _allCharsRosterCache.sig == rosterSig and _allCharsRosterCache.list then
        local cached = _allCharsRosterCache.list
        local n = #cached
        if n == 0 then
            return cached
        end
        -- Fresh array so callers cannot mutate sort order of the cached roster (e.g. table.sort).
        local out = {}
        for i = 1, n do
            out[i] = cached[i]
        end
        return out
    end
    
    -- Deduplicate characters (keep newest by lastSeen). Prefer player GUID when present (post-rename duplicates).
    local seen = {}  -- [mergeKey] = charData
    
    for key, data in pairs(charsTbl) do
        if type(data) ~= "table" then
            -- skip
        else
            local name, realm = data.name, data.realm
            if (not name or name == "") or (not realm or realm == "") then
                if key and type(key) == "string" and ns.Utilities and ns.Utilities.SplitCharacterKey then
                    local n, r = ns.Utilities:SplitCharacterKey(key)
                    if n and r then
                        name, realm = n, r
                        data.name = name
                        data.realm = realm
                    end
                end
            end
            if name and realm and name ~= "" and realm ~= "" then
                local normalizedKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(name, realm)
                if not normalizedKey then normalizedKey = key end
                -- Same player can appear under two keys after a rename; `guid` merges them (name+realm alone does not).
                local mergeKey
                local g = data.guid
                if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                    mergeKey = "\001g\001" .. g
                else
                    local rowStorageKey = ns.Utilities.ResolveCharacterRowKey and ns.Utilities:ResolveCharacterRowKey(data)
                    mergeKey = "\001n\001" .. (rowStorageKey or normalizedKey or key)
                end
                if seen[mergeKey] then
                    local existingData = seen[mergeKey]
                    local existingTime = existingData.lastSeen or 0
                    local newTime = data.lastSeen or 0
                    if newTime > existingTime then
                        data._key = key
                        seen[mergeKey] = data
                    else
                        -- Keep existing
                    end
                else
                    data._key = key
                    seen[mergeKey] = data
                end
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
        return CmpCharName(a, b)
    end)
    
    _allCharsRosterCache.sig = rosterSig
    _allCharsRosterCache.list = characters
    local n = #characters
    if n == 0 then
        return characters
    end
    local out = {}
    for i = 1, n do
        out[i] = characters[i]
    end
    return out
end

--- Get rested state from DB for UI rendering.
--- Offline estimate applies only when character logged out in resting area.
---@param charData table
---@param nowTs number|nil
---@return table|nil
function WarbandNexus:GetCharacterRestedState(charData, nowTs)
    if type(charData) ~= "table" then return nil end
    local rested = charData.rested
    local capMultiplier = GetRestedCapMultiplier(charData.raceFile)
    -- Support flat format (restedXP, xpMax, restedUpdatedAt, isResting) when char.rested is missing (e.g. from CaptureLogoutCharacterState)
    if type(rested) ~= "table" then
        local flatRested = tonumber(charData.restedXP)
        local flatMax = tonumber(charData.xpMax)
        if flatRested == nil and flatMax == nil then return nil end
        rested = {
            currentRestedXP = flatRested or 0,
            maxXP = flatMax or 0,
            restedCapXP = (flatMax and flatMax > 0) and math.floor(flatMax * capMultiplier) or 0,
            updatedAt = tonumber(charData.restedUpdatedAt) or tonumber(charData.lastSeen) or 0,
            isRestingArea = charData.isResting == true,
        }
    end

    local baseRestedXP = tonumber(rested.currentRestedXP) or 0
    local maxXP = tonumber(rested.maxXP) or 0
    local restedCapXP = tonumber(rested.restedCapXP) or ((maxXP > 0) and (maxXP * capMultiplier) or 0)
    local updatedAt = tonumber(rested.updatedAt) or tonumber(charData.lastSeen) or 0

    local estimatedRestedXP = baseRestedXP
    if rested.isRestingArea and maxXP > 0 and updatedAt > 0 then
        local currentTime = nowTs or time()
        if currentTime > updatedAt then
            local elapsed = currentTime - updatedAt
            local accelMultiplier = GetRestedAccumulationMultiplier(charData.raceFile)
            local gainPerSecond = (maxXP * RESTED_XP_GAIN_PER_8H * accelMultiplier) / SECONDS_PER_8H
            estimatedRestedXP = estimatedRestedXP + (elapsed * gainPerSecond)
        end
    end

    if restedCapXP > 0 then
        estimatedRestedXP = math.min(estimatedRestedXP, restedCapXP)
    end
    estimatedRestedXP = math.max(0, estimatedRestedXP)

    local restedPercentOfLevel = 0
    if maxXP > 0 then
        restedPercentOfLevel = (estimatedRestedXP / maxXP) * 100
    end

    local restedPercentOfCap = 0
    if restedCapXP > 0 then
        restedPercentOfCap = (estimatedRestedXP / restedCapXP) * 100
    end

    return {
        hasRestedXP = estimatedRestedXP > 0,
        isRestingArea = rested.isRestingArea == true,
        restedXP = math.floor(estimatedRestedXP),
        restedCapXP = math.floor(restedCapXP),
        currentXP = tonumber(rested.currentXP) or 0,
        maxXP = maxXP,
        exhaustionID = rested.exhaustionID,
        restStateName = rested.restStateName,
        restStateFactor = rested.restStateFactor,
        updatedAt = updatedAt,
        restedPercentOfLevel = restedPercentOfLevel,
        restedPercentOfCap = restedPercentOfCap,
    }
end

-- REMOVED: GetCachedCharacters (DB-First pattern - no cache, use GetAllCharacters directly)
-- REMOVED: InvalidateCharacterCache (DB-First pattern - no cache to invalidate)

-- PVE LOADING STATE HELPERS

--- Update PvE loading state and refresh UI.
function WarbandNexus:UpdatePvELoadingState(state)
    if not state then return end
    
    -- Update state fields
    for k, v in pairs(state) do
        ns.PvELoadingState[k] = v
    end
    
    -- Fire event for UI update (keystone + loading overlay; listeners use WN_PVE_UPDATED)
    if self.SendMessage then
        local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
        self:SendMessage(Constants.EVENTS.PVE_UPDATED, charKey)
    end
end

-- PVE DATA COLLECTION

--- Collect PvE data (deprecated; routes to PvECacheService).
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
        local charKey = ns.Utilities:GetCharacterKey()
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
            for i = 1, #activities do
                local activity = activities[i]
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
                    for ii = 1, #difficultyOrder do
                        local diff = difficultyOrder[ii]
                        if diff == currentLevel and ii < #difficultyOrder then
                            activityData.nextLevel = difficultyOrder[ii + 1]
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
    if ns.WeeklyVaultHasPendingRewards then
        pve.hasUnclaimedRewards = ns.WeeklyVaultHasPendingRewards()
    elseif C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        local has = C_WeeklyRewards.HasAvailableRewards()
        if has and C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and not C_WeeklyRewards.AreRewardsForCurrentRewardPeriod() then
            has = false
        end
        pve.hasUnclaimedRewards = has
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
            if issecretvalue and instanceName and issecretvalue(instanceName) then instanceName = nil end
            if issecretvalue and difficultyName and issecretvalue(difficultyName) then difficultyName = nil end
            
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
        -- Current keystone: C_MythicPlus (challenge map ID) — NOT bag itemID (legacy bug broke PvE cache).
        if self.ScanMythicKeystone then
            local ks = self:ScanMythicKeystone()
            if ks and ks.level and ks.level > 0 and ks.mapID then
                pve.mythicPlus.keystone = {
                    mapID = ks.mapID,
                    name = ks.dungeonName or "Unknown Dungeon",
                    level = ks.level,
                    lastUpdate = ks.scanTime or time(),
                }
            end
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
                for i = 1, #runs do
                    local run = runs[i]
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
            for i = 1, #allScores do
                local scoreData = allScores[i]
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            local mapTable = C_ChallengeMode.GetMapTable()
            if mapTable then
                for i = 1, #mapTable do
                    local mapID = mapTable[i]
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

--- Collect PvE data in three staggered stages (vault, M+, lockouts).
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
        currentStage = (ns.L and ns.L["PVE_PREPARING"]) or "Preparing",
    })
    
    -- Stage 1: Great Vault (most important, show first)
    C_Timer.After(3, function()
        if ns.PvELoadingState.cancelled then return end
        
        self:UpdatePvELoadingState({
            currentStage = (ns.L and ns.L["PVE_GREAT_VAULT"]) or "Great Vault",
            loadingProgress = 10,
        })
        
        -- Collect Great Vault data
        if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities then
                for i = 1, #activities do
                    local activity = activities[i]
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
        
        if ns.WeeklyVaultHasPendingRewards then
            pve.hasUnclaimedRewards = ns.WeeklyVaultHasPendingRewards()
        elseif C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
            local has = C_WeeklyRewards.HasAvailableRewards()
            if has and C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and not C_WeeklyRewards.AreRewardsForCurrentRewardPeriod() then
                has = false
            end
            pve.hasUnclaimedRewards = has
        end
        
        -- Update progress
        self:UpdatePvELoadingState({loadingProgress = 33})
        self:UpdatePvEDataV2(charKey, pve) -- Partial update
    end)
    
    -- Stage 2: M+ Scores (medium priority)
    C_Timer.After(5, function()
        if ns.PvELoadingState.cancelled then return end
        
        self:UpdatePvELoadingState({
            currentStage = (ns.L and ns.L["PVE_MYTHIC_SCORES"]) or "Mythic+ Scores",
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
            for i = 1, #allScores do
                local scoreData = allScores[i]
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            -- Get dungeon details
            local mapTable = C_ChallengeMode.GetMapTable()
            if mapTable then
                for i = 1, #mapTable do
                    local mapID = mapTable[i]
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
            currentStage = (ns.L and ns.L["PVE_RAID_LOCKOUTS"]) or "Raid Lockouts",
            loadingProgress = 80,
        })
        
        -- Collect lockouts (raids + dungeons; matches PvECacheService.UpdateRaidLockouts)
        if GetNumSavedInstances then
            local numSaved = GetNumSavedInstances()
            for i = 1, numSaved do
                local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                if issecretvalue and name and issecretvalue(name) then name = nil end
                if issecretvalue and difficultyName and issecretvalue(difficultyName) then difficultyName = nil end
                if name and locked then
                    table.insert(pve.lockouts, {
                        name = name,
                        id = id,
                        reset = reset,
                        difficulty = difficulty,
                        difficultyName = difficultyName,
                        progress = encounterProgress or 0,
                        total = numEncounters or 0,
                        extended = extended,
                        isRaid = (isRaid == true),
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


-- CURRENCY DATA

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


-- V2: PVE DATA STORAGE (Global with Metadata Separation)

--- Update PvE data (deprecated; routes to PvECacheService).
function WarbandNexus:UpdatePvEDataV2(charKey, pveData)
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("pve") then
        return
    end
    
    -- Phase 2: Route to PvECacheService
    if self.ImportLegacyPvEData then
        -- When called with explicit charKey + pveData (migration, event handler),
        -- import data for THAT specific character — do NOT collect fresh API data
        -- for the current character (which would ignore the passed charKey).
        if charKey and pveData then
            self:ImportLegacyPvEData(charKey, pveData)
        elseif self.UpdatePvEData then
            -- No data passed: collect fresh from WoW API for current character
            self:UpdatePvEData()
        end
        return
    end
    
    -- PvECacheService not loaded yet (should not happen after full init)
    if ns.DebugPrint then
        ns.DebugPrint("|cffff8000[DataService]|r UpdatePvEDataV2: ImportLegacyPvEData unavailable")
    end
end

--- Get PvE data for a character (deprecated; routes to PvECacheService).
function WarbandNexus:GetPvEDataV2(charKey)
    if self.GetPvEData then
        return self:GetPvEData(charKey)
    end
    return nil
end

-- V2: PERSONAL BANK STORAGE (Global with Compression)

--- Update personal bank (deprecated; prefer ItemsCacheService:SaveItemsCompressed).
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
    
end

-- NOTE: the GetPersonalBankV2 / UpdateWarbandBankV2 / GetWarbandBankV2 redirect
-- wrappers were removed (zero callers). ItemsCacheService owns item storage;
-- warbandBankV2 is deprecated and purged by DatabaseCleanup.

-- DATA VALIDATION & CLEANUP

--- Remove explicit untracked roster rows past daysThreshold (default 90); returns count removed.
function WarbandNexus:CleanupStaleCharacters(daysThreshold)
    daysThreshold = daysThreshold or 90
    local currentTime = time()
    local threshold = daysThreshold * 24 * 60 * 60 -- Convert to seconds
    local removed = 0
    
    if not self.db.global.characters then
        return 0
    end
    
    for key, char in pairs(self.db.global.characters) do
        if self:IsCharacterEligibleForStaleRemoval(char, threshold, currentTime) then
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        self:InvalidateGetAllCharactersCache()
        if self.SendMessage then
            self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, { dataType = "rosterPrune", removed = removed })
        end
    end
    
    return removed
end

-- BANK ITEMS HELPERS FOR ITEMS TAB

--- True when a weekly reset occurred since lastScanTime (EU Tue 07:00 / US Tue 15:00 UTC fallback).
function WarbandNexus:HasWeeklyResetOccurred(lastScanTime)
    if not lastScanTime then return true end
    
    local weekSecs = 7 * 24 * 60 * 60
    
    -- Prefer Blizzard API (no os.* — WoW sandbox has no standard os library)
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local secsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secsUntil ~= nil and secsUntil >= 0 then
            local now = GetServerTime()
            local nextReset = now + secsUntil
            local lastResetTime = nextReset - weekSecs
            return lastScanTime < lastResetTime
        end
    end
    
    -- Same helper as PlansManager:GetWeeklyResetTime fallback (uses global time(table), not os.time)
    if self.GetWeeklyResetTime then
        local nextReset = self:GetWeeklyResetTime()
        if nextReset and nextReset > 0 then
            return lastScanTime < (nextReset - weekSecs)
        end
    end
    
    local now = time()
    local region = GetCurrentRegion() -- 1=US, 2=KR, 3=EU, 4=TW, 5=CN
    local resetDay = 3
    local resetHour = (region == 3) and 7 or 15  -- EU: 07:00 UTC, US: 15:00 UTC
    
    local function getLastResetTime(timestamp)
        local d = date("*t", timestamp)
        local daysSinceReset = (d.wday - resetDay + 7) % 7
        local resetTs = time({
            year = d.year,
            month = d.month,
            day = d.day - daysSinceReset,
            hour = resetHour,
            min = 0,
            sec = 0,
        })
        if d.wday == resetDay and d.hour < resetHour then
            resetTs = resetTs - weekSecs
        end
        return resetTs
    end
    
    return lastScanTime < getLastResetTime(now)
end

--- Query current character's Mythic Keystone via C_MythicPlus API.
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
    if mapName and issecretvalue and issecretvalue(mapName) then
        mapName = nil
    end

    return {
        level = keystoneLevel,
        dungeonID = mapID,
        dungeonName = mapName or "Unknown Dungeon",
        mapID = mapID,
        scanTime = time()
    }
end

--- Get inventory items only (logged-in character bags 0-5).
function WarbandNexus:GetInventoryItems()
    local items = {}
    
    -- Same key as ItemsCacheService scans (GUID when available) — Name-Realm alone misses v2 itemStorage.
    local charKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
        and ns.CharacterService:ResolveCharactersTableKey(self)
    if not charKey and ns.Utilities.GetCharacterStorageKey then
        charKey = ns.Utilities:GetCharacterStorageKey(self)
    end
    if not charKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    -- Use ItemsCacheService (new unified storage)
    if not self.GetItemsData then
        return items  -- ItemsCacheService not loaded yet
    end
    
    local itemsData = self:GetItemsData(charKey)
    if not itemsData then
        return items
    end
    
    -- Add ONLY inventory bags items (bags field)
    if itemsData.bags then
        for i = 1, #itemsData.bags do
            local item = itemsData.bags[i]
            if item.itemID then
                item.bagIndex = item.actualBagID or item.bagID
                item.slotID = item.slotIndex
                item.source = "inventory"
                table.insert(items, item)
            end
        end
    end
    
    return items
end

--- Get personal bank items only (logged-in character).
function WarbandNexus:GetBankItems()
    local items = {}
    
    local charKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
        and ns.CharacterService:ResolveCharactersTableKey(self)
    if not charKey and ns.Utilities.GetCharacterStorageKey then
        charKey = ns.Utilities:GetCharacterStorageKey(self)
    end
    if not charKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    -- Use ItemsCacheService (new unified storage)
    if not self.GetItemsData then
        return items  -- ItemsCacheService not loaded yet
    end
    
    local itemsData = self:GetItemsData(charKey)
    if not itemsData then
        return items
    end
    
    -- Add ONLY bank items (bank field)
    if itemsData.bank then
        for i = 1, #itemsData.bank do
            local item = itemsData.bank[i]
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

-- Bag/bank scanning lives in ItemsCacheService; DataService retains personal-bank helpers below.

-- Local references for performance
local wipe = wipe
local pairs = pairs
local tinsert = table.insert
local time = time

-- NOTE: WarbandNexus:ScanWarbandBank() lives in Modules/ItemsCacheService.lua.
-- A legacy implementation previously existed here but was always overridden by
-- the ItemsCacheService version (which loads later per WarbandNexus.toc order).
-- Removed 2026-04 as dead code. See Core.lua delegate table for the canonical reference.

--- Scan personal bank; optional specificBagIDs limits which bags are read.
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
        local mainBankSlots = C_Container.GetContainerNumSlots(Enum.BagIndex.Bank or -1) or 0
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
    for i = 1, #bagsToScan do
        local bagID = bagsToScan[i]
        -- Find bagIndex from bagID
        local bagIndex = nil
        for j = 1, #ns.PERSONAL_BANK_BAGS do
            local pbBagID = ns.PERSONAL_BANK_BAGS[j]
            if pbBagID == bagID then
                bagIndex = j
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
            
            local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
            totalSlots = totalSlots + numSlots

            for slotID = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    -- Get extended item info
                    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                          _, _, itemTexture, _, classID, subclassID = C_Item.GetItemInfo(itemInfo.itemID)
                    
                    -- Special handling for Battle Pets (classID 17)
                    local displayName = itemName
                    local displayIcon = itemInfo.iconFileID or itemTexture
                    
                    if classID == 17 and itemInfo.hyperlink then
                        local hp = itemInfo.hyperlink
                        if type(hp) == "string" and not (issecretvalue and issecretvalue(hp)) then
                            local petName = hp:match("%[(.-)%]")
                            if petName and petName ~= "" and petName ~= "Pet Cage" then
                                displayName = petName
                            end
                            local speciesID = tonumber(hp:match("|Hbattlepet:(%d+):"))
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
        -- Persist to itemStorage only (no full character save from bank scan path).
        -- Resolve the same GUID-preferred key ItemsCacheService writes under; the legacy
        -- Name-Realm derivation parked a second bank blob the UI never read.
        local key = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(self))
            or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self))
            or ns.Utilities:GetCharacterKey()
        if key and self.SaveItemsCompressed then
            local arr = tableToItemArrayForStorage(self.db.char.personalBank and self.db.char.personalBank.items)
            if arr then self:SaveItemsCompressed(key, "bank", arr) end
        end
    end
    
    -- Fire event for UI refresh
    if self.SendMessage then
        self:SendMessage(E.BAGS_UPDATED)
    end
    
    return true
end

--- Flat list of Warband Bank items; optional groupByCategory buckets by category.
function WarbandNexus:GetWarbandBankItems(groupByCategory)
    local items = {}
    
    -- Use ItemsCacheService (new unified storage)
    if not self.GetWarbandBankData then
        return items  -- ItemsCacheService not loaded yet
    end
    
    local warbandData = self:GetWarbandBankData()
    if not warbandData or not warbandData.items then
        return items
    end
    
    -- ItemsCacheService returns: { items = {}, lastUpdate = 0 }
    -- Add source metadata for UI
    for i = 1, #warbandData.items do
        local item = warbandData.items[i]
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
        if not aName and a.link and type(a.link) == "string" and not (issecretvalue and issecretvalue(a.link)) then
            aName = a.link:match("%[(.-)%]")
        end
        local bName = b.name
        if not bName and b.link and type(b.link) == "string" and not (issecretvalue and issecretvalue(b.link)) then
            bName = b.link:match("%[(.-)%]")
        end
        return (aName or "") < (bName or "")
    end)
    
    if groupByCategory then
        return self:GroupItemsByCategory(items)
    end
    
    return items
end

--- Get bank statistics (warband, personal, guild). Always returns initialized numeric fields.
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
    local wbSlots, wbStacks, wbLast = 0, 0, 0
    if self.GetWarbandBankOccupiedSlotTally then
        wbSlots, wbStacks, wbLast = self:GetWarbandBankOccupiedSlotTally()
    else
        local warbandData = self.GetWarbandBankData and self:GetWarbandBankData()
        if warbandData and warbandData.items and #warbandData.items > 0 then
            wbSlots = #warbandData.items
            for i = 1, wbSlots do
                local item = warbandData.items[i]
                wbStacks = wbStacks + (item.stackCount or 1)
            end
            wbLast = warbandData.lastUpdate or 0
        end
    end
    stats.warband.usedSlots = wbSlots
    stats.warband.itemCount = wbStacks
    stats.warband.lastScan = wbLast
    -- Live API for total warband bank slots (works even when bank is closed in TWW)
    local WARBAND_BAGS = ns.WARBAND_BAGS or {13, 14, 15, 16, 17}
    for i = 1, #WARBAND_BAGS do
        local bagID = WARBAND_BAGS[i]
        stats.warband.totalSlots = stats.warband.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    -- If API returned 0 (no purchased tabs), use stored item count as minimum
    if stats.warband.totalSlots == 0 and stats.warband.usedSlots > 0 then
        stats.warband.totalSlots = stats.warband.usedSlots
    end
    stats.warband.freeSlots = math.max(0, stats.warband.totalSlots - stats.warband.usedSlots)
    
    -- ===== PERSONAL STORAGE (inventory bags + personal bank from ItemsCacheService) =====
    local charKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
        and ns.CharacterService:ResolveCharactersTableKey(self)
    if not charKey and ns.Utilities.GetCharacterStorageKey then
        charKey = ns.Utilities:GetCharacterStorageKey(self)
    end
    if not charKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    local itemsData = self.GetItemsData and self:GetItemsData(charKey)
    if itemsData then
        -- Count occupied slots and item stacks from bags
        local bagSlots = itemsData.bags and #itemsData.bags or 0
        local bankSlots = itemsData.bank and #itemsData.bank or 0
        stats.personal.usedSlots = bagSlots + bankSlots
        
        local _bags = itemsData.bags or {}
        for i = 1, #_bags do
            local item = _bags[i]
            stats.personal.itemCount = stats.personal.itemCount + (item.stackCount or 1)
        end
        local _bank = itemsData.bank or {}
        for i = 1, #_bank do
            local item = _bank[i]
            stats.personal.itemCount = stats.personal.itemCount + (item.stackCount or 1)
        end
        
        stats.personal.lastScan = math.max(itemsData.bagsLastUpdate or 0, itemsData.bankLastUpdate or 0)
    end
    -- Live API for total personal slots (inventory bags always accessible)
    local INVENTORY_BAGS = ns.INVENTORY_BAGS or {0, 1, 2, 3, 4, 5}
    local BANK_BAGS = ns.PERSONAL_BANK_BAGS or {-1, 6, 7, 8, 9, 10, 11}
    for i = 1, #INVENTORY_BAGS do
        local bagID = INVENTORY_BAGS[i]
        stats.personal.totalSlots = stats.personal.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    for i = 1, #BANK_BAGS do
        local bagID = BANK_BAGS[i]
        stats.personal.totalSlots = stats.personal.totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    -- If API returned 0 for everything, use stored item count as minimum
    if stats.personal.totalSlots == 0 and stats.personal.usedSlots > 0 then
        stats.personal.totalSlots = stats.personal.usedSlots
    end
    stats.personal.freeSlots = math.max(0, stats.personal.totalSlots - stats.personal.usedSlots)
    
    -- ===== GUILD BANK (legacy format - scanned when guild bank is opened) =====
    local guildName = GetGuildInfo("player")
    if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
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