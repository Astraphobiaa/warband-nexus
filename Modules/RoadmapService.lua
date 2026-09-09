--[[
    Warband Nexus - Roadmap Service
    Consolidated data aggregator for weekly character progression (PvE, PvP, Professions).
    Target: Midnight 12.1.0 (## Interface: 120100).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants and Constants.EVENTS

local RoadmapService = {}
ns.RoadmapService = RoadmapService

local issecretvalue = issecretvalue
local tinsert = table.insert
local twipe = table.wipe

local MIDNIGHT_DELVE_MAPS = {
    { mapID = 2395, name = "Eversong Woods" },
    { mapID = 2405, name = "Voidstorm" },
    { mapID = 2413, name = "Harandar" },
    { mapID = 2437, name = "Zul'Aman" },
    { mapID = 2444, name = "Slayer's Rise" },
    { mapID = 2512, name = "The Coiled Isle" },
}

--- Safe check for secret values before string or numeric ops
local function IsSafeVal(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

--- Get seconds remaining until weekly reset
function RoadmapService:GetWeeklyResetTimeRemaining()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, sec = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(sec) == "number" and sec > 0 then
            return sec
        end
    end
    if WarbandNexus and WarbandNexus.GetWeeklyResetTime then
        local ok, resetTime = pcall(WarbandNexus.GetWeeklyResetTime, WarbandNexus)
        if ok and type(resetTime) == "number" then
            local diff = resetTime - GetServerTime()
            if diff > 0 then return diff end
        end
    end
    return 0
end

--- Query active daily Bountiful Delves across Midnight zones
--- @return table array of { mapID, name, description, position, isNemesis, poiID }
function RoadmapService:GetBountifulDelves()
    local results = {}
    if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIForMap or not C_AreaPoiInfo.GetAreaPOIInfo then
        return results
    end

    for mi = 1, #MIDNIGHT_DELVE_MAPS do
        local mapEntry = MIDNIGHT_DELVE_MAPS[mi]
        local mapID = mapEntry.mapID
        local ok, poiIDs = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
        if ok and type(poiIDs) == "table" then
            for pi = 1, #poiIDs do
                local poiID = poiIDs[pi]
                local poiOk, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
                if poiOk and info and info.atlasName then
                    local atlas = tostring(info.atlasName):lower()
                    if atlas:find("bountiful") then
                        local delveName = IsSafeVal(info.name) and info.name or "Bountiful Delve"
                        local desc = IsSafeVal(info.description) and info.description or ""
                        local isNemesis = (delveName:find("Venomfall") ~= nil) or (desc:find("Nemesis") ~= nil)
                        results[#results + 1] = {
                            poiID = poiID,
                            mapID = mapID,
                            zoneName = mapEntry.name,
                            name = delveName,
                            description = desc,
                            position = info.position,
                            isNemesis = isNemesis,
                        }
                    end
                end
            end
        end
    end

    return results
end

--- Set one-click waypoint to a Delve entrance
--- @param mapID number
--- @param position table Vector2D
--- @return boolean
function RoadmapService:SetDelveWaypoint(mapID, position)
    if not mapID or not position or not C_Map or not UiMapPoint or not UiMapPoint.CreateFromVector2D then
        return false
    end
    local ok, point = pcall(UiMapPoint.CreateFromVector2D, mapID, position)
    if ok and point and C_Map.SetUserWaypoint then
        pcall(C_Map.SetUserWaypoint, point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        return true
    end
    return false
end

--- Collect comprehensive PvE roadmap for a given character key
--- @param charKey string|nil canonical character storage key
--- @return table
function RoadmapService:GetCharacterPvERoadmap(charKey)
    local isCurrentChar = false
    local resolvedKey = charKey
    if not resolvedKey then
        if ns.Utilities and ns.Utilities.GetCharacterStorageKey then
            resolvedKey = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        end
        isCurrentChar = true
    else
        local curKey = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        isCurrentChar = (curKey ~= nil and resolvedKey == curKey)
    end

    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local charData = (db and db.characters and resolvedKey and db.characters[resolvedKey]) or {}
    local pveCache = db and db.pveCache

    local roadmap = {
        charKey = resolvedKey,
        isCurrentChar = isCurrentChar,
        characterName = charData.name or (isCurrentChar and UnitName("player")) or "Unknown",
        characterClass = charData.class or (isCurrentChar and select(2, UnitClass("player"))) or "WARRIOR",
        characterLevel = charData.level or (isCurrentChar and UnitLevel("player")) or 80,
        resetSeconds = self:GetWeeklyResetTimeRemaining(),
        vault = {
            hasAvailableRewards = false,
            raid = { slots = {}, completedCount = 0, totalSlots = 3 },
            dungeon = { slots = {}, completedCount = 0, totalSlots = 3, topLevel = 0 },
            world = { slots = {}, completedCount = 0, totalSlots = 3, topTier = 0 },
        },
        weeklies = {},
        delves = {
            activeBountiful = self:GetBountifulDelves(),
            cofferKeys = 0,
            bountifulCompletedToday = false,
            gildedStashes = 0,
            gildedStashesMax = 3,
        },
        seasonalPower = {
            manafluxHeld = 0,
            manafluxMax = 0,
            manafluxSeasonEarned = 0,
            manafluxName = (ns.VaultButton and ns.VaultButton.GetManafluxName and ns.VaultButton.GetManafluxName()) or "Venomblight Manaflux",
            sparkDustHeld = 0,
            keystoneMap = nil,
            keystoneLevel = 0,
            topRunLevel = 0,
            deadRunFloor = 0,
        },
        raidLockouts = {},
    }

    -- 1. Great Vault
    if isCurrentChar and C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local okRew, hasRew = pcall(C_WeeklyRewards.HasAvailableRewards)
        if okRew then roadmap.vault.hasAvailableRewards = (hasRew == true) end

        local typeEnum = Enum and Enum.WeeklyRewardChestThresholdType
        local raidType = (typeEnum and typeEnum.Raid) or 1
        local dungType = (typeEnum and typeEnum.MythicPlus) or 2
        local worldType = (typeEnum and typeEnum.World) or 3

        local function ParseActivities(actType)
            local ok, acts = pcall(C_WeeklyRewards.GetActivities, actType)
            local slots = {}
            local completed = 0
            if ok and type(acts) == "table" then
                for i = 1, #acts do
                    local act = acts[i]
                    local thresh = act.threshold or 0
                    local prog = act.progress or 0
                    local isDone = (prog >= thresh) and (thresh > 0)
                    if isDone then completed = completed + 1 end
                    slots[#slots + 1] = {
                        threshold = thresh,
                        progress = prog,
                        completed = isDone,
                        level = act.level or 0,
                        itemLevel = act.itemLevel or 0,
                    }
                end
            end
            return slots, completed
        end

        roadmap.vault.raid.slots, roadmap.vault.raid.completedCount = ParseActivities(raidType)
        roadmap.vault.dungeon.slots, roadmap.vault.dungeon.completedCount = ParseActivities(dungType)
        roadmap.vault.world.slots, roadmap.vault.world.completedCount = ParseActivities(worldType)
    elseif pveCache and pveCache.greatVault then
        -- Read cached vault activities for alts
        local gvActs = (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.greatVault.activities, resolvedKey))
            or (pveCache.greatVault.activities and resolvedKey and pveCache.greatVault.activities[resolvedKey])
        if gvActs then
            local function ReadCachedSection(secKey, fallbackKey)
                local slots = {}
                local completed = 0
                local sec = gvActs[secKey] or (fallbackKey and gvActs[fallbackKey])
                if type(sec) == "table" then
                    for i = 1, #sec do
                        local act = sec[i]
                        local thresh = act.threshold or 0
                        local prog = act.progress or 0
                        local isDone = (prog >= thresh) and (thresh > 0)
                        if isDone then completed = completed + 1 end
                        slots[#slots + 1] = {
                            threshold = thresh,
                            progress = prog,
                            completed = isDone,
                            level = act.level or 0,
                            itemLevel = act.rewardItemLevel or act.itemLevel or 0,
                        }
                    end
                end
                return slots, completed
            end
            roadmap.vault.raid.slots, roadmap.vault.raid.completedCount = ReadCachedSection("raids", "raid")
            roadmap.vault.dungeon.slots, roadmap.vault.dungeon.completedCount = ReadCachedSection("mythicPlus", "dungeon")
            roadmap.vault.world.slots, roadmap.vault.world.completedCount = ReadCachedSection("world")
        end

        local gvRews = (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.greatVault.rewards, resolvedKey))
            or (pveCache.greatVault.rewards and resolvedKey and pveCache.greatVault.rewards[resolvedKey])
        if gvRews then
            roadmap.vault.hasAvailableRewards = (gvRews.hasAvailableRewards == true)
        end
    end

    -- 2. Core Weeklies (Midnight S2)
    local CORE_WEEKLIES = {
        { key = "spark", questID = 93942, catalogKey = "spark_tides", title = "Spark of Tides", icon = "Interface\\Icons\\INV_10_Jewelcrafting_Gem3Primal_Fire_Cut_Blue", desc = "Weekly Spark craft currency" },
        { key = "world_boss", questID = 93913, title = "Midnight: World Boss", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", desc = "Quel'Thalas weekly world boss" },
        { key = "world_quests", questID = 93766, title = "Midnight: World Quests", icon = "Interface\\Icons\\worldquest-icon", desc = "Complete 6 World Quests" },
        { key = "soiree", questID = 93889, title = "Saltheril's Soiree", icon = "Interface\\Icons\\INV_Misc_Food_164_Fish_Seadog", desc = "Eversong Woods event" },
        { key = "abundance", questID = 93890, title = "Abundance", icon = "Interface\\Icons\\INV_Misc_Herb_AncientLichen", desc = "Zul'Aman treasure cave event" },
        { key = "haranir", questID = 93891, title = "Legends of the Haranir", icon = "Interface\\Icons\\INV_Misc_Book_09", desc = "Harandar relic event" },
        { key = "stormarion", questID = 93892, title = "Stormarion Assault", icon = "Interface\\Icons\\Ability_Warrior_Charge", desc = "Voidstorm Singularity event" },
        { key = "nightmare", questID = 94446, title = "A Nightmarish Task", icon = "Interface\\Icons\\Spell_Shadow_Nightmare", desc = "Prey hunts (Trovehunter's Bounty)" },
        { key = "purging", questID = 95520, title = "Purging the Vaults", icon = "Interface\\Icons\\INV_Misc_Idol_03", desc = "Vaults of Atal'Utek (Trovehunter's Bounty)" },
    }

    local nowServer = (GetServerTime and GetServerTime()) or time()
    local resetSec = self:GetWeeklyResetTimeRemaining()
    local cachedQuests = nil
    if pveCache and pveCache.weeklyQuests then
        local cq = (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.weeklyQuests, resolvedKey))
            or (resolvedKey and pveCache.weeklyQuests[resolvedKey])
        if cq and (not cq.resetAt or cq.resetAt > nowServer) then
            cachedQuests = cq.quests or cq
        end
    end

    local liveQuestsToSave = nil
    if isCurrentChar and pveCache and resolvedKey then
        pveCache.weeklyQuests = pveCache.weeklyQuests or {}
        pveCache.weeklyQuests[resolvedKey] = {
            quests = {},
            resetAt = nowServer + (resetSec > 0 and resetSec or 604800),
            lastUpdate = nowServer,
        }
        liveQuestsToSave = pveCache.weeklyQuests[resolvedKey].quests
    end

    local delveChar = pveCache and pveCache.delves and pveCache.delves.characters and resolvedKey and (
        (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.delves.characters, resolvedKey))
        or pveCache.delves.characters[resolvedKey]
    )

    for wi = 1, #CORE_WEEKLIES do
        local w = CORE_WEEKLIES[wi]
        local isDone = false
        if isCurrentChar and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
            local ok, qDone = pcall(C_QuestLog.IsQuestFlaggedCompleted, w.questID)
            if ok then isDone = (qDone == true) end
            if liveQuestsToSave then
                liveQuestsToSave[w.questID] = isDone
            end
        elseif cachedQuests and cachedQuests[w.questID] ~= nil then
            isDone = (cachedQuests[w.questID] == true)
        elseif delveChar then
            if w.key == "nightmare" and delveChar.nightmareTaskComplete ~= nil then
                isDone = (delveChar.nightmareTaskComplete == true)
            elseif w.key == "purging" and delveChar.purgingVaultsComplete ~= nil then
                isDone = (delveChar.purgingVaultsComplete == true)
            end
        end

        roadmap.weeklies[#roadmap.weeklies + 1] = {
            key = w.key,
            questID = w.questID,
            title = w.title,
            icon = w.icon,
            description = w.desc,
            completed = isDone,
        }
    end

    -- 3. Delve metrics & Coffer keys
    if delveChar then
        roadmap.delves.bountifulCompletedToday = (delveChar.bountifulComplete == true)
        roadmap.delves.gildedStashes = tonumber(delveChar.gildedStashes) or 0
        roadmap.delves.gildedStashesMax = tonumber(delveChar.gildedStashesMax) or 3
    end

    -- Helper to resolve offline currency amounts across AceDB and CurrencyCacheService
    local function GetOfflineCurrency(currID)
        if charData and charData.currencies and charData.currencies[currID] then
            local c = charData.currencies[currID]
            local q = type(c) == "table" and c.quantity or c
            if tonumber(q) then return tonumber(q) end
        end
        if WarbandNexus and WarbandNexus.GetCurrenciesForUI then
            local ok, allCur = pcall(WarbandNexus.GetCurrenciesForUI, WarbandNexus)
            if ok and allCur and allCur[currID] and allCur[currID].chars then
                local chMap = allCur[currID].chars
                local val = chMap[resolvedKey] or (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and chMap[ns.Utilities:GetCanonicalCharacterKey(resolvedKey)])
                if type(val) == "table" then return tonumber(val.quantity) or 0 end
                if tonumber(val) then return tonumber(val) end
            end
        end
        local cdb = db and db.currencyData and db.currencyData.currencies
        if cdb and resolvedKey and cdb[resolvedKey] and cdb[resolvedKey][currID] then
            local val = cdb[resolvedKey][currID]
            if type(val) == "table" then return tonumber(val.quantity) or 0 end
            if tonumber(val) then return tonumber(val) end
        end
        return 0
    end

    -- Coffer Keys currency (3089)
    if isCurrentChar and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, cinfo = pcall(C_CurrencyInfo.GetCurrencyInfo, 3089)
        if ok and cinfo then roadmap.delves.cofferKeys = cinfo.quantity or 0 end
    else
        roadmap.delves.cofferKeys = GetOfflineCurrency(3089)
    end

    -- 4. Seasonal Power (Catalyst 3465, Spark 3509, Keystones)
    local manafluxID = (ns.VaultButton and ns.VaultButton.GetManafluxID and ns.VaultButton.GetManafluxID()) or 3465
    if isCurrentChar and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, cinfo = pcall(C_CurrencyInfo.GetCurrencyInfo, manafluxID)
        if ok and cinfo then
            roadmap.seasonalPower.manafluxHeld = cinfo.quantity or 0
            roadmap.seasonalPower.manafluxMax = cinfo.maxQuantity or cinfo.seasonMax or 0
            roadmap.seasonalPower.manafluxSeasonEarned = cinfo.totalEarned or cinfo.quantity or 0
        end
        local okSpark, spInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, 3509)
        if okSpark and spInfo then
            roadmap.seasonalPower.sparkDustHeld = spInfo.quantity or 0
        end
    else
        roadmap.seasonalPower.manafluxHeld = GetOfflineCurrency(manafluxID)
        roadmap.seasonalPower.sparkDustHeld = GetOfflineCurrency(3509)
        if charData.currencies and charData.currencies[manafluxID] then
            local cd = charData.currencies[manafluxID]
            roadmap.seasonalPower.manafluxMax = tonumber(cd.maxQuantity or cd.seasonMax) or 0
            roadmap.seasonalPower.manafluxSeasonEarned = tonumber(cd.totalEarned or cd.quantity) or 0
        end
    end

    -- Keystone info
    local ksChar = pveCache and pveCache.keystones and pveCache.keystones.characters and resolvedKey and (
        (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.keystones.characters, resolvedKey))
        or pveCache.keystones.characters[resolvedKey]
    )
    if ksChar then
        roadmap.seasonalPower.keystoneLevel = tonumber(ksChar.level) or 0
        roadmap.seasonalPower.keystoneMap = ksChar.challengeMapID
    elseif isCurrentChar and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
        local okLvl, klvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
        if okLvl and klvl then roadmap.seasonalPower.keystoneLevel = klvl end
        local okMap, kmap = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
        if okMap and kmap then roadmap.seasonalPower.keystoneMap = kmap end
    end

    -- 5. Raid Lockouts
    if isCurrentChar and GetNumSavedInstances then
        local okNum, num = pcall(GetNumSavedInstances)
        if okNum and type(num) == "number" then
            for i = 1, num do
                local name, id, reset, difficulty, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                if IsSafeVal(name) and (locked == true or locked == 1 or extended == true or extended == 1 or (encounterProgress and encounterProgress > 0)) and (isRaid == true or isRaid == 1) then
                    roadmap.raidLockouts[#roadmap.raidLockouts + 1] = {
                        name = name,
                        difficultyName = IsSafeVal(difficultyName) and difficultyName or "Raid",
                        numEncounters = tonumber(numEncounters) or 0,
                        encounterProgress = tonumber(encounterProgress) or 0,
                        locked = (locked == true or locked == 1),
                        extended = (extended == true or extended == 1),
                    }
                end
            end
        end
    end
    if #roadmap.raidLockouts == 0 and pveCache and pveCache.lockouts and pveCache.lockouts.raids and resolvedKey then
        local charRaids = (ns.LookupPvECacheSubtable and ns.LookupPvECacheSubtable(pveCache.lockouts.raids, resolvedKey))
            or pveCache.lockouts.raids[resolvedKey]
        if charRaids then
            for _, row in pairs(charRaids) do
                if row and row.name then
                    roadmap.raidLockouts[#roadmap.raidLockouts + 1] = {
                        name = row.name,
                        difficultyName = row.difficultyName or "Raid",
                        numEncounters = tonumber(row.numEncounters) or 0,
                        encounterProgress = tonumber(row.encounterProgress) or 0,
                        locked = (row.locked == true or row.locked == 1),
                        extended = (row.extended == true or row.extended == 1),
                    }
                end
            end
        end
    end

    return roadmap
end

--- Centralized event initialization to notify UI of weekly progression updates
--- @param addon table AceAddon instance
function RoadmapService:Initialize(addon)
    if self._initialized then return end
    self._initialized = true
    local target = addon or WarbandNexus
    if not target then return end

    local function OnRoadmapEvent()
        if target.SendMessage and E and E.ROADMAP_UPDATED then
            target:SendMessage(E.ROADMAP_UPDATED)
        end
    end

    if target.RegisterBucketEvent then
        target:RegisterBucketEvent({
            "WEEKLY_REWARDS_UPDATE",
            "CHALLENGE_MODE_COMPLETED",
            "UPDATE_INSTANCE_INFO",
            "BOSS_KILL",
            "QUEST_LOG_UPDATE",
            "CURRENCY_DISPLAY_UPDATE",
        }, 1.0, OnRoadmapEvent)
    end
end

