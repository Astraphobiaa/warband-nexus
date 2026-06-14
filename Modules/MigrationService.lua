--[[
    WarbandNexus - Migration Service
    Handles database migrations and upgrades across versions
    
    Responsibilities:
    - One-time data migrations
    - Database schema upgrades
    - Backward compatibility fixes
    - Data format conversions
    - Version tracking and cache invalidation
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local DebugPrint = ns.DebugPrint

local function PrintUserMessage(message)
    if not message or message == "" then return end
    local addon = _G.WarbandNexus
    if addon and addon.Print then
        addon:Print(message)
    else
        _G.print(message)
    end
end

---@class MigrationService
local MigrationService = {}
ns.MigrationService = MigrationService

local function GearSlotHasPayload(slot)
    if type(slot) ~= "table" then return false end
    if slot.itemLink or slot.itemID or slot.name then return true end
    return (tonumber(slot.itemLevel) or 0) > 0
end

local function CountGearPayloadSlots(entry)
    local slots = type(entry) == "table" and entry.slots
    if type(slots) ~= "table" then return 0 end
    local count = 0
    for _, slot in pairs(slots) do
        if GearSlotHasPayload(slot) then count = count + 1 end
    end
    return count
end

local function ShouldUseLegacyGearBucket(current, legacy)
    local currentSlots = CountGearPayloadSlots(current)
    local legacySlots = CountGearPayloadSlots(legacy)
    if legacySlots ~= currentSlots then
        return legacySlots > currentSlots
    end
    return (tonumber(legacy.lastScan) or 0) > (tonumber(current.lastScan) or 0)
end

local function MergeMissingGearSlots(target, donor)
    local donorSlots = type(donor) == "table" and donor.slots
    if type(donorSlots) ~= "table" then return end
    if type(target.slots) ~= "table" then
        target.slots = donorSlots
        return
    end
    for slotID, donorSlot in pairs(donorSlots) do
        local targetSlot = target.slots[slotID]
        if GearSlotHasPayload(donorSlot) and not GearSlotHasPayload(targetSlot) then
            target.slots[slotID] = donorSlot
        end
    end
end

local function MergeGearWatermarks(target, donor)
    local donorMarks = type(donor) == "table" and donor.watermarks
    if type(donorMarks) ~= "table" then return end
    if type(target.watermarks) ~= "table" then
        target.watermarks = donorMarks
        return
    end
    for slotID, watermark in pairs(donorMarks) do
        local existing = target.watermarks[slotID]
        if existing == nil or (tonumber(watermark) or 0) > (tonumber(existing) or 0) then
            target.watermarks[slotID] = watermark
        end
    end
end

local function MergeGearDataBucket(current, legacy)
    if type(legacy) ~= "table" then return current end
    if type(current) ~= "table" then return legacy end

    local target = current
    local donor = legacy
    if ShouldUseLegacyGearBucket(current, legacy) then
        target = legacy
        donor = current
    end

    MergeMissingGearSlots(target, donor)
    MergeGearWatermarks(target, donor)

    if type(target.modelView) ~= "table" and type(donor.modelView) == "table" then
        target.modelView = donor.modelView
    elseif type(target.modelView) == "table" and type(donor.modelView) == "table" then
        local targetViewScan = tonumber(target.modelView.lastUpdate) or 0
        local donorViewScan = tonumber(donor.modelView.lastUpdate) or 0
        if donorViewScan > targetViewScan then
            target.modelView = donor.modelView
        end
    end
    if type(target.modelSnapshot) ~= "table" and type(donor.modelSnapshot) == "table" then
        target.modelSnapshot = donor.modelSnapshot
    end
    if target.version == nil and donor.version ~= nil then
        target.version = donor.version
    end
    if (tonumber(donor.lastScan) or 0) > (tonumber(target.lastScan) or 0) then
        target.lastScan = donor.lastScan
    end

    return target
end

--- Move/rename one top-level charKey bucket when roster keys change (GUID migration).
--- Callers must pass a transitively-resolved rename map (every loser points at the
--- final survivor — see CleanupDatabase). When the survivor already has a bucket it
--- wins and the loser's is discarded: bucket schemas differ per table, so a generic
--- merge isn't possible, and the survivor is always the most recently seen row.
---@param tbl table|nil
---@param renames table<string,string>
local function RemapCharKeyedBucket(tbl, renames)
    if type(tbl) ~= "table" then return end
    for oldKey, newKey in pairs(renames) do
        if oldKey ~= newKey then
            if tbl[oldKey] and not tbl[newKey] then
                tbl[newKey] = tbl[oldKey]
                tbl[oldKey] = nil
            elseif tbl[oldKey] then
                tbl[oldKey] = nil
            end
        end
    end
end

--- Union per-character reputation buckets; prefer newer lastScan on faction conflicts.
local function MergeReputationCharBucket(target, donor)
    if type(target) ~= "table" or type(donor) ~= "table" then return target end
    for factionID, entry in pairs(donor) do
        if type(entry) == "table" then
            local existing = target[factionID]
            if type(existing) ~= "table" then
                target[factionID] = entry
            else
                local eScan = tonumber(existing.lastScan) or 0
                local dScan = tonumber(entry.lastScan) or 0
                if dScan >= eScan then
                    target[factionID] = entry
                end
            end
        end
    end
    return target
end

local function RemapReputationCharBuckets(repData, renames)
    if type(repData) ~= "table" or type(renames) ~= "table" then return end
    local chars = repData.characters
    if type(chars) ~= "table" then return end
    for oldKey, newKey in pairs(renames) do
        if oldKey ~= newKey and chars[oldKey] then
            if not chars[newKey] then
                chars[newKey] = chars[oldKey]
            else
                MergeReputationCharBucket(chars[newKey], chars[oldKey])
            end
            chars[oldKey] = nil
        end
    end
end

--- Update money log entry.character fields when roster keys rename.
local function RemapCharacterBankMoneyLogEntries(logs, renames)
    if type(logs) ~= "table" or type(renames) ~= "table" then return end
    for i = 1, #logs do
        local e = logs[i]
        if type(e) == "table" and e.character then
            local nk = renames[e.character]
            if nk then
                e.character = nk
            end
        end
    end
end

--- Remap all per-character buckets in db.global.pveCache when roster keys move.
---@param pveCache table|nil
---@param renames table<string,string>
local function RemapPveCacheCharacterKeys(pveCache, renames)
    if type(pveCache) ~= "table" then return end
    local mp = pveCache.mythicPlus
    if mp then
        RemapCharKeyedBucket(mp.keystones, renames)
        RemapCharKeyedBucket(mp.bestRuns, renames)
        RemapCharKeyedBucket(mp.dungeonScores, renames)
        RemapCharKeyedBucket(mp.runHistory, renames)
    end
    local gv = pveCache.greatVault
    if gv then
        RemapCharKeyedBucket(gv.activities, renames)
        RemapCharKeyedBucket(gv.rewards, renames)
    end
    local lo = pveCache.lockouts
    if lo then
        RemapCharKeyedBucket(lo.raids, renames)
        RemapCharKeyedBucket(lo.dungeons, renames)
        RemapCharKeyedBucket(lo.worldBosses, renames)
    end
    local delves = pveCache.delves
    if delves and delves.characters then
        RemapCharKeyedBucket(delves.characters, renames)
    end
end

--[[
    Single-roof version check.

    Three independent version axes are tracked under db.global.versions:
      - addon: bumps on every release. NEVER triggers cache invalidation by itself.
      - game:  Blizzard build (select(4, GetBuildInfo())). When this changes the
               WoW API surface may have shifted — invalidate API-bound caches.
      - cache.<name>: per-cache schema versions from Constants.VERSIONS.CACHE.
               Bump these manually when a cache's stored shape becomes
               incompatible. Each is checked independently; only the cache
               whose version moved is invalidated.

    Invalidation is non-destructive (resets cache.version field, keeps data) and
    always backs up the prior table to db.global.cacheBackups[name] first, so a
    misfire can be reverted via /wn ... or InvalidateCache/RestoreCacheBackup.
]]
function MigrationService:CheckVersions(db, addon)
    local Constants = ns.Constants or {}
    local currentAddon  = Constants.ADDON_VERSION or "0.0.0"
    local currentGame   = (select(4, GetBuildInfo()))
    local currentCacheV = (Constants.VERSIONS and Constants.VERSIONS.CACHE) or {}

    db.global.versions = db.global.versions or {}
    local v = db.global.versions
    v.cache = v.cache or {}

    -- Migrate legacy single-key db.global.addonVersion into the unified registry
    -- so existing users do not get a phantom "version changed" on first run.
    if db.global.addonVersion and not v.addon then
        v.addon = db.global.addonVersion
    end
    db.global.addonVersion = nil

    -- 1. Addon version: track only, never invalidate caches.
    if v.addon ~= currentAddon then
        DebugPrint("|cff9370DB[WN Migration]|r addon " .. tostring(v.addon) .. " → " .. tostring(currentAddon) .. " (no cache action)")
        v.addon = currentAddon
    end

    -- 2. Game build: invalidate API-bound caches (reputation, collection) whose
    --    server-side data shape may have changed after a patch.
    if currentGame and v.game ~= currentGame then
        DebugPrint("|cff9370DB[WN Migration]|r game build " .. tostring(v.game) .. " → " .. tostring(currentGame) .. " (invalidating API caches)")
        if addon.InvalidateCache then
            addon:InvalidateCache("reputation", "game_build")
            addon:InvalidateCache("collection", "game_build")
        end
        v.game = currentGame
    end

    -- 3. Per-cache schema bump: invalidate only the cache whose schema integer
    --    in Constants.VERSIONS.CACHE was raised in this release.
    for name, version in pairs(currentCacheV) do
        if v.cache[name] ~= version then
            local prev = v.cache[name]
            DebugPrint("|cff9370DB[WN Migration]|r cache schema '" .. name .. "' " .. tostring(prev) .. " → " .. tostring(version) .. " (invalidating)")
            if prev ~= nil and addon.InvalidateCache then
                addon:InvalidateCache(name, "schema_bump")
            end
            v.cache[name] = version
        end
    end
end

-- Backwards-compat alias: old callers still invoke CheckAddonVersion.
function MigrationService:CheckAddonVersion(db, addon)
    return self:CheckVersions(db, addon)
end

-- Schema version: Increment on breaking DB changes to trigger full reset.
-- When incremented, ALL existing users get a one-time full SV wipe on next login (fresh start).
-- New users are unaffected (they start with empty DB + defaults).
local CURRENT_SCHEMA_VERSION = 13

---Run all database migrations. Returns true if a full schema reset was performed.
---@param db table AceDB instance
---@return boolean didReset
function MigrationService:RunMigrations(db)
    if not db then
        return false
    end

    -- Schema version check: full reset if outdated
    if self:CheckSchemaReset(db) then
        return true -- Everything was wiped; caller should re-apply defaults
    end

    self:MigrateThemeColors(db)
    self:MigrateThemeMode(db)
    self:MigrateReputationMetadata(db)
    self:MigrateReputationToV2(db)
    self:MigrateGenderField(db)
    self:MigrateTrackingField(db)
    self:MigrateTrackingConfirmed(db)
    self:MigrateGoldFormat(db)
    self:MigrateRealmSuffixRepairFromCharKey(db)
    self:MigrateCharacterKeyNormalize(db)
    self:MigrateGlobalCharactersToGuidStorageKeys(db)
    self:DeduplicateCharacterRoster(db)
    self:MigrateSubsidiaryOrphanKeys(db)
    self:MigrateSubsidiaryAliasBucketsV1(db)
    self:MigrateRestedDataReset(db)
    self:MigrateRarityMountSyncReseed(db)
    self:MigrateReminderToastAnchors(db)
    self:MigrateNotificationToastLaneDefaults(db)
    self:MigrateCustomSectionChangelogLog(db)
    self:MigrateReminderQuestCatalog(db)
    self:MigrateFontScalePreset(db)
    self:DropStaleLegacyGlobalCurrencies(db)
    self:DropStaleLegacyGlobalReputations(db)
    self:FinalizeGuidOnlySubsidiaryV1(db)
    return false
end

--- Enable GUID-only subsidiary reads after orphan + alias migrations complete.
---@param db table AceDB root
function MigrationService:FinalizeGuidOnlySubsidiaryV1(db)
    if not db or not db.global or db.global.guidOnlySubsidiaryV1 then return end
    if db.global.subsidiaryOrphanRemapV1 and db.global.subsidiaryAliasConsolidatedV1 then
        db.global.guidOnlySubsidiaryV1 = true
        if DebugPrint then
            DebugPrint("|cff9370DB[WN Migration]|r guidOnlySubsidiaryV1: subsidiary I/O is GUID-canonical")
        end
    end
end

--- Force subsidiary orphan/alias remap (slash `/wn guidmigrate`). Does not wipe roster rows.
---@param db table AceDB root
---@return number renameCount Keys remapped in the last alias pass
function MigrationService:RunGuidSubsidiaryRemap(db)
    if not db or not db.global then return 0 end
    db.global.subsidiaryOrphanRemapV1 = nil
    db.global.subsidiaryAliasConsolidatedV1 = nil
    db.global.guidOnlySubsidiaryV1 = nil
    local orphanRenames = BuildSubsidiaryOrphanRenames(db)
    local total = 0
    for _ in pairs(orphanRenames) do total = total + 1 end
    self:MigrateSubsidiaryOrphanKeys(db)
    local aliasRenames = BuildSubsidiaryAliasRenames(db)
    for _ in pairs(aliasRenames) do total = total + 1 end
    self:MigrateSubsidiaryAliasBucketsV1(db)
    self:FinalizeGuidOnlySubsidiaryV1(db)
    return total
end

--- Remove unused db.global.currencies table when currencyData is populated (no readers remain).
function MigrationService:DropStaleLegacyGlobalCurrencies(db)
    if not db or not db.global or db.global._legacyGlobalCurrenciesDropV1 then return end
    local legacy = db.global.currencies
    if type(legacy) ~= "table" then
        db.global._legacyGlobalCurrenciesDropV1 = true
        return
    end
    local cd = db.global.currencyData and db.global.currencyData.currencies
    if cd and next(cd) then
        db.global.currencies = nil
        if DebugPrint then
            DebugPrint("|cff9370DB[Migration]|r Dropped stale db.global.currencies (currencyData authoritative)")
        end
    end
    db.global._legacyGlobalCurrenciesDropV1 = true
end

--- Resolve legacy font scalePreset into scaleCustom + useCustomScale=true (Settings slider is authoritative).
function MigrationService:MigrateFontScalePreset(db)
    if not db or not db.profile or db.profile.fontScalePresetMigratedV1 then return end
    local fonts = db.profile.fonts
    if fonts and not fonts.useCustomScale then
        local preset = fonts.scalePreset or "normal"
        local multipliers = {
            tiny = 0.8,
            small = 0.9,
            normal = 1.0,
            large = 1.2,
            xlarge = 1.4,
        }
        fonts.scaleCustom = multipliers[preset] or 1.0
        fonts.useCustomScale = true
    end
    db.profile.fontScalePresetMigratedV1 = true
end

--- Seed maintained world-quest catalog (static + version bump).
function MigrationService:MigrateReminderQuestCatalog(db)
    if not db or not db.global then return end
    local WQC = ns.ReminderWorldQuestCatalog
    if not WQC or not WQC.SeedStaticIntoDatabase then return end
    local cat = db.global.reminderQuestCatalog
    local ver = WQC.CATALOG_VERSION or 1
    if cat and tonumber(cat.version) == ver then return end
    WQC.SeedStaticIntoDatabase()
    if ns.DebugPrint then
        ns.DebugPrint("|cff9370DB[Migration]|r Reminder quest catalog seeded (v" .. tostring(ver) .. ")")
    end
end

--- One-time chat log for Custom Section system updates (profile normalization lives in CharacterService:EnsureCustomCharacterSectionsProfile).
function MigrationService:MigrateCustomSectionChangelogLog(db)
    if not db or not db.global then return end
    if db.global._wnChangelogCustomSectionsV1 then return end
    db.global._wnChangelogCustomSectionsV1 = true
    local L = ns.L
    local body = (L and L["CHANGELOG_CUSTOM_SECTIONS_V1"])
        or "Custom sections: multiple gold-highlighted headers, favorites-first ordering, canonical assignment in roster/Characters list, and a simpler tab subtitle."
    PrintUserMessage("|cff6a0dad" .. ((L and L["ADDON_NAME"]) or "Warband Nexus") .. "|r: " .. body)
end

--[[
    Full SavedVariables reset when schema version is outdated.
    Wipes global/char/profile data so AceDB re-creates from defaults.
    @return boolean - true if reset was performed
]]
function MigrationService:CheckSchemaReset(db)
    local storedVersion = db.global._schemaVersion or 0
    if storedVersion >= CURRENT_SCHEMA_VERSION then
        return false
    end

    DebugPrint("|cff9370DB[WN Migration]|r [Migration Event] SCHEMA_RESET triggered (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. ")")
    PrintUserMessage("|cff6a0dad" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r: " .. ((ns.L and ns.L["DATABASE_UPDATED_MSG"]) or "Database updated to a new version.") .. " (v" .. storedVersion .. " → v" .. CURRENT_SCHEMA_VERSION .. ")")

    -- Wipe global (itemStorage, reputationData, characters, etc.)
    if db.global then wipe(db.global) end

    -- db.char is only the current character's slice. Wipe the raw SV char table
    -- so ALL characters (Y, Z, ...) are removed; otherwise other chars stay in SV.
    local raw = _G.WarbandNexusDB
    if raw and raw.char then
        wipe(raw.char)
    end
    if db.char then wipe(db.char) end

    -- Reset profile via AceDB API so defaults are properly re-applied
    if db.ResetProfile then
        db:ResetProfile(nil, true) -- silent reset, no callback fire
    elseif db.profile then
        wipe(db.profile)
    end

    -- Stamp current schema version (must be after wipe so it persists)
    db.global._schemaVersion = CURRENT_SCHEMA_VERSION

    PrintUserMessage("|cff6a0dad" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r: " .. ((ns.L and ns.L["MIGRATION_RESET_COMPLETE"]) or "Reset complete. All data will be rescanned automatically."))
    return true
end

--[[
    Migrate theme colors to new format with calculated variations
]]
function MigrationService:MigrateThemeColors(db)
    if not db.profile.themeColors then
        return
    end
    
    local colors = db.profile.themeColors
    
    -- If missing calculated variations, regenerate them
    if not colors.accentDark or not colors.tabHover then
        if ns.UI_CalculateThemeColors and colors.accent then
            local accent = colors.accent
            db.profile.themeColors = ns.UI_CalculateThemeColors(accent[1], accent[2], accent[3])
        end
    end
end

--- Collapse legacy lightMode / highContrast booleans into profile.themeMode ("dark" | "light").
function MigrationService:MigrateThemeMode(db)
    if not db or not db.profile or db.profile.themeModeMigratedV1 then
        return
    end

    local p = db.profile
    if p.themeMode ~= "light" and p.themeMode ~= "dark" then
        if p.lightMode == true then
            p.themeMode = "light"
        else
            p.themeMode = "dark"
        end
    end
    p.lightMode = nil
    p.highContrast = nil
    p.themeModeMigratedV1 = true
end

--[[
    Migrate reputation data to v2 with isAccountWide field
]]
function MigrationService:MigrateReputationMetadata(db)
    if not db.global.reputations or db.global.reputationMigrationV2 then
        return
    end
    
    local needsMigration = false
    for factionID, repData in pairs(db.global.reputations) do
        if repData and repData.isAccountWide == nil then
            needsMigration = true
            break
        end
    end
    
    if needsMigration then
        db.global.reputationMigrationV2 = true
        -- The actual update will happen on next ScanReputations() which runs on PLAYER_ENTERING_WORLD
    end
end

--[[
    Add gender field to existing characters
    Runs on every login until all characters are fixed
]]
function MigrationService:MigrateGenderField(db)
    if not db.global.characters then
        return
    end
    
    local U = ns.Utilities
    local currentKey = (U and U.GetCharacterStorageKey and U:GetCharacterStorageKey())
        or (U and U.GetCharacterKey and U:GetCharacterKey())
    if not currentKey then return end
    if not db.global.characters[currentKey] and U and U.GetCharacterKey then
        local leg = U:GetCharacterKey()
        if leg and db.global.characters[leg] then
            currentKey = leg
        end
    end
    -- Fix current character's gender on every login (in case it's wrong)
    if db.global.characters[currentKey] then
        local savedGender = db.global.characters[currentKey].gender
        
        -- Detect current gender using C_PlayerInfo (most reliable)
        local detectedGender = UnitSex("player")
        local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
        if raceInfo and raceInfo.gender ~= nil then
            detectedGender = (raceInfo.gender == 1) and 3 or 2
        end
        
        -- Update if different or missing
        if not savedGender or savedGender ~= detectedGender then
            db.global.characters[currentKey].gender = detectedGender
        end
    end
    
    -- ONE-TIME: Add default gender to characters that don't have it
    if not db.global.genderMigrationV1 then
        for charKey, charData in pairs(db.global.characters) do
            if charData and not charData.gender then
                -- Default to male (2) - will be corrected on next login
                charData.gender = 2
            end
        end
        -- Gender migration applied silently
        db.global.genderMigrationV1 = true
    end
end

--[[
    Add isTracked field to existing characters
]]
function MigrationService:MigrateTrackingField(db)
    if not db.global.characters or db.global.trackingMigrationV1 then
        return
    end
    
    for charKey, charData in pairs(db.global.characters) do
        if charData and charData.isTracked == nil then
            -- Existing characters automatically tracked (backward compatibility)
            charData.isTracked = true
        end
    end
    
    -- Tracking migration applied silently
    
    db.global.trackingMigrationV1 = true
end

--[[
    One-time: remove legacy rested XP fields from character records.
    Rested XP tracking was removed from the addon; keep DB schema clean.
]]
function MigrationService:MigrateRestedDataReset(db)
    if not db or not db.global or not db.global.characters then
        return
    end
    if db.global.restedDataRemovedV4 then
        return
    end

    for _, charData in pairs(db.global.characters) do
        if type(charData) == "table" then
            charData.restedXP = nil
            charData.xpMax = nil
            charData.xpCurrent = nil
            charData.isResting = nil
            charData.restedUpdatedAt = nil
        end
    end

    db.global.restedDataResetV1 = true
    db.global.restedDataResetV2 = true
    db.global.restedDataResetV3 = true
    db.global.restedDataRemovedV4 = true
end

--[[
    One-time per revision: clear informational legacyMountTrackerSeedComplete (preview / bookkeeping).
    SyncRarityMountAttemptsMax does NOT read this flag — merge already runs on a timer after login
    and after Statistics seed. Bump RARITY_MOUNT_SYNC_RESEED_REVISION after policy changes if you
    want users to see "seed done: false" once; for a manual re-merge run Rarity sync from Try Counter settings (Rarity enabled).
]]
local RARITY_MOUNT_SYNC_RESEED_REVISION = 1

--- Seed dedicated To-Do reminder toast anchors from legacy criteria-slot keys (one-time per profile).
function MigrationService:MigrateReminderToastAnchors(db)
    if not db or not db.profile or not db.profile.notifications then return end
    local n = db.profile.notifications
    if n.reminderToastAnchorMigratedV1 then return end
    local hasCritPos = (n.popupPointCompact and n.popupPointCompact ~= "")
        or n.popupXCompact ~= nil
        or n.popupYCompact ~= nil
    if hasCritPos then
        if not n.reminderToastPoint then n.reminderToastPoint = n.popupPointCompact or "TOPRIGHT" end
        if n.reminderToastX == nil then n.reminderToastX = n.popupXCompact end
        if n.reminderToastY == nil then n.reminderToastY = n.popupYCompact end
    end
    if n.reminderToastScale == nil then n.reminderToastScale = 1.0 end
    if n.reminderToastUseCriteriaLane == nil then n.reminderToastUseCriteriaLane = false end
    n.reminderToastAnchorMigratedV1 = true
end

--- Seed per-lane try-counter anchor + unified layout flag from legacy single-anchor keys.
function MigrationService:MigrateNotificationToastLaneDefaults(db)
    if not db or not db.profile or not db.profile.notifications then return end
    local n = db.profile.notifications
    if n._notificationToastLanesMigratedV1 then return end
    if n.unifiedToastLayout == nil then
        n.unifiedToastLayout = true
    end
    if not n.tryCounterToastPoint then
        n.tryCounterToastPoint = n.popupPoint or "TOP"
    end
    if n.tryCounterToastX == nil then
        n.tryCounterToastX = n.popupX or 0
    end
    if n.tryCounterToastY == nil then
        n.tryCounterToastY = n.popupY or -100
    end
    n._notificationToastLanesMigratedV1 = true
end

function MigrationService:MigrateRarityMountSyncReseed(db)
    if not db or not db.global then
        return
    end
    local doneRev = db.global._rarityMountSyncReseedRevision or 0
    if doneRev >= RARITY_MOUNT_SYNC_RESEED_REVISION then
        return
    end
    local tc = db.global.tryCounts
    if tc and type(tc) == "table" then
        tc.legacyMountTrackerSeedComplete = false
    end
    db.global._rarityMountSyncReseedRevision = RARITY_MOUNT_SYNC_RESEED_REVISION
    DebugPrint("|cff9370DB[WN Migration]|r Rarity mount max-sync reseed (revision "
        .. tostring(RARITY_MOUNT_SYNC_RESEED_REVISION) .. "): legacyMountTrackerSeedComplete cleared")
end

---Migrate reputation cache to v2.1.0 (per-character storage)
--- This migration only converts OLD reputationCache → NEW reputationData format.
---It MUST NOT wipe existing reputationData when the structure is already valid.
---The version field inside reputationData is managed by ReputationCacheService (may differ
---from Constants.REPUTATION_CACHE_VERSION after version bumps) — that's normal and expected.
function MigrationService:MigrateReputationToV2(db)
    if not db or not db.global then
        return
    end
    
    local oldCache = db.global.reputationCache
    local newCache = db.global.reputationData
    
    -- If new cache exists with valid STRUCTURE, no migration needed.
    -- Check structure (accountWide + characters tables exist), NOT version string.
    -- ReputationCacheService manages its own version field and may bump it independently.
    -- Matching on exact version here caused data wipe on every login when versions diverged.
    if newCache and type(newCache) == "table"
        and type(newCache.accountWide) == "table"
        and type(newCache.characters) == "table" then
        -- Structure is valid — clean up old cache if it still exists and return
        if oldCache then
            db.global.reputationCache = nil
        end
        return
    end
    
    -- No valid new cache exists — need to create one (fresh install or legacy migration)
    
    -- Clear old cache (any version)
    if oldCache then
        db.global.reputationCache = nil
    end
    
    -- Initialize new cache structure (v2.1: Per-character storage)
    -- Version set to "0" — ReputationCacheService will detect mismatch and trigger a rescan
    db.global.reputationData = {
        version = "0",
        lastScan = 0,
        accountWide = {},    -- Account-wide reputations
        characters = {},     -- Per-character reputations
        headers = {},
    }
    
end

--[[
    Add trackingConfirmed flag to legacy tracked characters
    Prevents tracking popup from appearing for existing tracked characters
]]
function MigrationService:MigrateTrackingConfirmed(db)
    if not db.global.characters then
        return
    end
    
    for charKey, charData in pairs(db.global.characters) do
        -- If character is tracked but doesn't have trackingConfirmed flag, add it
        if charData.isTracked == true and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
        end
        
        -- Also add flag to untracked characters with explicit isTracked=false
        if charData.isTracked == false and not charData.trackingConfirmed then
            charData.trackingConfirmed = true
        end
    end
    
    -- trackingConfirmed migration applied silently
end

function MigrationService:MigrateGoldFormat(db)
    if not db.global.characters then
        return
    end
    
    -- Migrate characters
    for charKey, charData in pairs(db.global.characters) do
        if charData then
            -- If old totalCopper exists, convert to breakdown
            if charData.totalCopper then
                local totalCopper = math.floor(tonumber(charData.totalCopper) or 0)
                charData.gold = math.floor(totalCopper / 10000)
                charData.silver = math.floor((totalCopper % 10000) / 100)
                charData.copper = math.floor(totalCopper % 100)
                -- DELETE old field to prevent overflow
                charData.totalCopper = nil
            end
            
            -- If very old format exists (gold/silver/copper as separate fields), ensure floored
            if charData.gold or charData.silver or charData.copper then
                charData.gold = math.floor(tonumber(charData.gold) or 0)
                charData.silver = math.floor(tonumber(charData.silver) or 0)
                charData.copper = math.floor(tonumber(charData.copper) or 0)
            end
            
            -- Delete ALL legacy fields that might cause overflow
            charData.goldAmount = nil
            charData.silverAmount = nil
            charData.copperAmount = nil
        end
    end
    
    -- Migrate warband bank
    if db.global.warbandBank then
        local wb = db.global.warbandBank
        
        -- If old totalCopper exists, convert to breakdown
        if wb.totalCopper then
            local totalCopper = math.floor(tonumber(wb.totalCopper) or 0)
            wb.gold = math.floor(totalCopper / 10000)
            wb.silver = math.floor((totalCopper % 10000) / 100)
            wb.copper = math.floor(totalCopper % 100)
            wb.totalCopper = nil  -- DELETE to prevent overflow
        end
        
        -- Ensure breakdown values are integers
        if wb.gold or wb.silver or wb.copper then
            wb.gold = math.floor(tonumber(wb.gold) or 0)
            wb.silver = math.floor(tonumber(wb.silver) or 0)
            wb.copper = math.floor(tonumber(wb.copper) or 0)
        end
        
        -- Delete legacy fields
        wb.goldAmount = nil
        wb.silverAmount = nil
        wb.copperAmount = nil
    end
    
    -- Gold format migration applied silently
end

---Fix charData.realm when it was truncated by greedy "Name-Realm" parsing (realm contains hyphens, e.g. Azjol-Nerub).
---Table key is authoritative: first hyphen separates name from full realm suffix.
function MigrationService:MigrateRealmSuffixRepairFromCharKey(db)
    if not db.global or db.global._realmSuffixRepairV1 then return end
    local Utilities = ns.Utilities
    if not Utilities or not Utilities.GetCharacterKey or not Utilities.SplitCharacterKey then
        return
    end
    local chars = db.global.characters
    if type(chars) ~= "table" then
        db.global._realmSuffixRepairV1 = true
        return
    end
    for charKey, charData in pairs(chars) do
        if type(charKey) == "string" and type(charData) == "table" and charData.name then
            local nKey, rKey = Utilities:SplitCharacterKey(charKey)
            if nKey and rKey then
                local nameNorm = tostring(charData.name):gsub("%s+", "")
                if nameNorm == nKey then
                    local splitCanon = Utilities:GetCharacterKey(nKey, rKey)
                    if splitCanon == charKey then
                        local rStored = charData.realm
                        local currentCanon = (type(rStored) == "string" and rStored ~= "")
                            and Utilities:GetCharacterKey(nameNorm, rStored) or nil
                        if currentCanon ~= charKey then
                            charData.realm = rKey
                        end
                    end
                end
            end
        end
    end
    db.global._realmSuffixRepairV1 = true
end

--- Remap character-keyed global/profile storage when `db.global.characters` rows move or merge.
--- Does not modify `db.global.characters` itself (callers own row moves/deletes).
---@param db table AceDB root (global + profile)
---@param renames table<string,string> oldKey -> newKey
function MigrationService:ApplyCharacterKeyedStorageRenames(db, renames)
    if not db or not db.global or type(renames) ~= "table" or not next(renames) then
        return
    end

    local remapCount = 0
    for _ in pairs(renames) do remapCount = remapCount + 1 end

    -- currencyData.currencies + totalEarned
    local cd = db.global.currencyData
    if cd then
        if cd.currencies then
            RemapCharKeyedBucket(cd.currencies, renames)
        end
        if cd.totalEarned then
            RemapCharKeyedBucket(cd.totalEarned, renames)
        end
    end

    -- gearData
    if db.global.gearData then
        for oldKey, newKey in pairs(renames) do
            if oldKey ~= newKey then
                if db.global.gearData[oldKey] then
                    db.global.gearData[newKey] = MergeGearDataBucket(db.global.gearData[newKey], db.global.gearData[oldKey])
                    db.global.gearData[oldKey] = nil
                end
            end
        end
    end

    -- pveProgress
    if db.global.pveProgress then
        RemapCharKeyedBucket(db.global.pveProgress, renames)
    end

    -- pveCache (active PvE storage)
    if db.global.pveCache then
        RemapPveCacheCharacterKeys(db.global.pveCache, renames)
    end

    -- statisticSnapshots
    if db.global.statisticSnapshots then
        for oldKey, newKey in pairs(renames) do
            if oldKey ~= newKey then
                if db.global.statisticSnapshots[oldKey] and not db.global.statisticSnapshots[newKey] then
                    db.global.statisticSnapshots[newKey] = db.global.statisticSnapshots[oldKey]
                    db.global.statisticSnapshots[oldKey] = nil
                elseif db.global.statisticSnapshots[oldKey] then
                    db.global.statisticSnapshots[oldKey] = nil
                end
            end
        end
    end

    -- personalBanks
    if db.global.personalBanks then
        for oldKey, newKey in pairs(renames) do
            if oldKey ~= newKey then
                if db.global.personalBanks[oldKey] and not db.global.personalBanks[newKey] then
                    db.global.personalBanks[newKey] = db.global.personalBanks[oldKey]
                    db.global.personalBanks[oldKey] = nil
                elseif db.global.personalBanks[oldKey] then
                    db.global.personalBanks[oldKey] = nil
                end
            end
        end
    end

    -- itemStorage (compressed bags/bank per character)
    if db.global.itemStorage then
        for oldKey, newKey in pairs(renames) do
            if oldKey ~= newKey then
                if db.global.itemStorage[oldKey] and not db.global.itemStorage[newKey] then
                    db.global.itemStorage[newKey] = db.global.itemStorage[oldKey]
                    db.global.itemStorage[oldKey] = nil
                elseif db.global.itemStorage[oldKey] then
                    db.global.itemStorage[oldKey] = nil
                end
            end
        end
    end

    -- reputationData.characters (per-character faction progress)
    if db.global.reputationData then
        RemapReputationCharBuckets(db.global.reputationData, renames)
    end

    -- characterBankMoneyLogs (entry.character field, not top-level bucket)
    if db.global.characterBankMoneyLogs then
        RemapCharacterBankMoneyLogEntries(db.global.characterBankMoneyLogs, renames)
    end

    -- favoriteCharacters (array): replace keys, then dedupe
    if db.global.favoriteCharacters and type(db.global.favoriteCharacters) == "table" then
        local seen = {}
        local favs = db.global.favoriteCharacters
        for i = 1, #favs do
            local key = favs[i]
            local canonical = renames[key] or key
            db.global.favoriteCharacters[i] = canonical
            seen[canonical] = true
        end
        local deduped = {}
        for i = 1, #db.global.favoriteCharacters do
            local k = db.global.favoriteCharacters[i]
            if seen[k] then
                deduped[#deduped + 1] = k
                seen[k] = nil
            end
        end
        db.global.favoriteCharacters = deduped
    end

    -- profile.characterGroupAssignments: map charKey -> groupId (keys follow character renames)
    if db.profile and db.profile.characterGroupAssignments and type(db.profile.characterGroupAssignments) == "table" then
        local assign = db.profile.characterGroupAssignments
        local newAssign = {}
        for oldKey, groupId in pairs(assign) do
            local nk = renames[oldKey] or oldKey
            newAssign[nk] = groupId
        end
        db.profile.characterGroupAssignments = newAssign
    end

    -- profile.characterOrder (favorites, regular, untracked, group_* custom sections)
    if db.profile and db.profile.characterOrder then
        for orderKey, arr in pairs(db.profile.characterOrder) do
            if type(arr) == "table" then
                for i = 1, #arr do
                    local key = arr[i]
                    arr[i] = renames[key] or key
                end
            end
        end
    end

    if remapCount > 0 and DebugPrint then
        DebugPrint(string.format("|cff9370DB[Migration]|r Character-keyed storage remapped: %d key(s)", remapCount))
    end
end

--- When collapsing duplicate `db.global.characters` rows (same player GUID), copy missing payloads from `loser` into `winner`.
--- Does not strip fields already populated on `winner` (live save/API wins); prefers richer gold when loser has higher copper.
---@param winner table
---@param loser table
function MigrationService:MergeCharacterRowPreserveWinner(winner, loser)
    if type(winner) ~= "table" or type(loser) ~= "table" then return end
    local U = ns.Utilities
    local function emptyTable(t)
        return not t or type(t) ~= "table" or not next(t)
    end
    local wCop = U and U.GetCharTotalCopper and U:GetCharTotalCopper(winner) or 0
    local lCop = U and U.GetCharTotalCopper and U:GetCharTotalCopper(loser) or 0
    if lCop > wCop then
        winner.gold = loser.gold
        winner.silver = loser.silver
        winner.copper = loser.copper
    end
    local wi = tonumber(winner.itemLevel) or 0
    local li = tonumber(loser.itemLevel) or 0
    if wi <= 0 and li > 0 then
        winner.itemLevel = loser.itemLevel
    end
    if emptyTable(winner.professions) and not emptyTable(loser.professions) then
        winner.professions = loser.professions
    end
    local nested = {
        "concentration", "recipes", "professionExpansions", "discoveredSkillLines",
        "knowledgeData", "professionCooldowns", "professionEquipment", "cooldownRecipeIDs",
        "craftingOrders", "professionData", "rested", "stats",
    }
    for i = 1, #nested do
        local k = nested[i]
        local wv = winner[k]
        if wv == nil or emptyTable(wv) then
            local lv = loser[k]
            if lv ~= nil then
                winner[k] = lv
            end
        end
    end
    if winner.mythicKey == nil and loser.mythicKey ~= nil then
        winner.mythicKey = loser.mythicKey
    end
    if winner.timePlayed == nil and loser.timePlayed ~= nil then
        winner.timePlayed = loser.timePlayed
    end
    if winner.specID == nil and loser.specID ~= nil then
        winner.specID = loser.specID
        winner.specName = winner.specName or loser.specName
        winner.specIcon = winner.specIcon or loser.specIcon
    end
    if winner.heroSpecID == nil and loser.heroSpecID ~= nil then
        winner.heroSpecID = loser.heroSpecID
        winner.heroSpecName = winner.heroSpecName or loser.heroSpecName
    end
end

--- Collapse duplicate `db.global.characters` rows (same GUID and/or legacy Name-Realm alias).
--- Uses shared roster merge key logic in DataService_RosterHelpers.
---@param db table AceDB root
---@return number duplicateCount
function MigrationService:DeduplicateCharacterRoster(db)
    local Roster = ns.DataServiceRoster
    if Roster and Roster.ApplyCharacterRosterDeduplication then
        return Roster.ApplyCharacterRosterDeduplication(db, self)
    end
    return 0
end

---Normalize character keys across all character-keyed tables to canonical form
---(Utilities:GetCharacterKey(name, realm)). Handles collision: keep newest by lastSeen, merge non-conflicting fields.
function MigrationService:MigrateCharacterKeyNormalize(db)
    if not db.global then return end
    if db.global.charactersKeyNormalized then return end
    local Utilities = ns.Utilities
    if not Utilities or not Utilities.GetCharacterKey then return end

    local renames = {} -- [oldKey] = newKey (only when newKey ~= oldKey)
    if db.global.characters then
        for charKey, charData in pairs(db.global.characters) do
            if type(charData) == "table" and charData.name and charData.realm then
                local newKey = Utilities:GetCharacterKey(charData.name, charData.realm)
                if newKey and newKey ~= charKey then
                    renames[charKey] = newKey
                end
            end
        end
    end

    if not next(renames) then
        db.global.charactersKeyNormalized = true
        return
    end

    local chars = db.global.characters
    for oldKey, newKey in pairs(renames) do
        if not chars[oldKey] then
            -- already moved or removed
        elseif not chars[newKey] then
            chars[newKey] = chars[oldKey]
            chars[oldKey] = nil
        else
            -- Collision: keep newest by lastSeen; absorb missing fields from the dropped row
            local oldData = chars[oldKey]
            local newData = chars[newKey]
            local oldSeen = (type(oldData.lastSeen) == "number") and oldData.lastSeen or 0
            local newSeen = (type(newData.lastSeen) == "number") and newData.lastSeen or 0
            if oldSeen > newSeen then
                self:MergeCharacterRowPreserveWinner(oldData, newData)
                chars[newKey] = oldData
            else
                self:MergeCharacterRowPreserveWinner(newData, oldData)
            end
            chars[oldKey] = nil
        end
    end

    self:ApplyCharacterKeyedStorageRenames(db, renames)

    db.global.charactersKeyNormalized = true
end

--- One-time: move `db.global.characters` rows to **player GUID** keys when `charData.guid` exists (stable across renames).
--- Subsidiary character-keyed globals/profile lists are remapped via `ApplyCharacterKeyedStorageRenames`.
--- Rows **without** guid stay on legacy Name-Realm keys until a login save stores guid (lazy relocate in DataService).
--- Collisions (multiple keys, same guid): keep single row at `chars[guid]` — winner prefers key == guid, else newest lastSeen.
---@param db table AceDB root
function MigrationService:MigrateGlobalCharactersToGuidStorageKeys(db)
    if not db or not db.global then return end
    if db.global.charactersGuidKeyedV1 then return end

    local chars = db.global.characters
    if type(chars) ~= "table" then
        db.global.charactersGuidKeyedV1 = true
        return
    end

    local issecretvalue = issecretvalue
    local byGuid = {}

    for charKey, charData in pairs(chars) do
        if type(charData) == "table" then
            local g = charData.guid
            if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                local lst = byGuid[g]
                if not lst then
                    lst = {}
                    byGuid[g] = lst
                end
                lst[#lst + 1] = {
                    k = charKey,
                    seen = (type(charData.lastSeen) == "number") and charData.lastSeen or 0,
                    data = charData,
                }
            end
        end
    end

    local renames = {}
    local renamedSlots = 0

    for g, lst in pairs(byGuid) do
        if type(lst) == "table" and #lst > 0 then
            local win = lst[1]
            for i = 2, #lst do
                local e = lst[i]
                local winAtG = (win.k == g)
                local eAtG = (e.k == g)
                if eAtG and not winAtG then
                    win = e
                elseif winAtG == eAtG then
                    if (e.seen or 0) > (win.seen or 0) then
                        win = e
                    end
                end
            end

            local winningTable = win.data
            for i = 1, #lst do
                local e = lst[i]
                if e and e.k and e.k ~= win.k and type(e.data) == "table" then
                    self:MergeCharacterRowPreserveWinner(winningTable, e.data)
                end
            end
            local keysInGroup = {}
            for i = 1, #lst do
                keysInGroup[lst[i].k] = true
            end

            for oldK in pairs(keysInGroup) do
                if oldK ~= g then
                    chars[oldK] = nil
                    renames[oldK] = g
                    renamedSlots = renamedSlots + 1
                end
            end
            chars[g] = winningTable
        end
    end

    if next(renames) then
        self:ApplyCharacterKeyedStorageRenames(db, renames)
    end

    DebugPrint("|cff9370DB[WN Migration]|r charactersGuidKeyedV1: guid storage keys applied; subsidiary remaps="
        .. tostring(renamedSlots))

    db.global.charactersGuidKeyedV1 = true
end

--- Merge currency quantity rows; prefer larger quantity when both buckets exist pre-rename.
local function MergeCurrencyCharBucket(target, donor)
    if type(donor) ~= "table" then return target end
    if type(target) ~= "table" then return donor end
    for currencyID, val in pairs(donor) do
        local dQty = (type(val) == "number") and val or (type(val) == "table" and tonumber(val.quantity)) or nil
        if dQty ~= nil then
            local tVal = target[currencyID]
            local tQty = (type(tVal) == "number") and tVal or (type(tVal) == "table" and tonumber(tVal.quantity)) or nil
            if tQty == nil or dQty > tQty then
                target[currencyID] = val
            end
        end
    end
    return target
end

--- Prefer the richer PvE per-character bucket (non-empty, newer lastUpdate).
local function PreferRicherPvECharBucket(target, donor)
    if type(donor) ~= "table" or not next(donor) then return target end
    if type(target) ~= "table" or not next(target) then return donor end
    local tLu = tonumber(target.lastUpdate) or 0
    local dLu = tonumber(donor.lastUpdate) or 0
    if dLu > tLu then return donor end
    if dLu < tLu then return target end
    return target
end

local function MergePvECharBucket(target, donor)
    return PreferRicherPvECharBucket(target, donor)
end

local function ForEachPveCharKeyedTable(pveCache, fn)
    if type(pveCache) ~= "table" or type(fn) ~= "function" then return end
    local mp = pveCache.mythicPlus
    if mp then
        if mp.keystones then fn(mp.keystones) end
        if mp.bestRuns then fn(mp.bestRuns) end
        if mp.dungeonScores then fn(mp.dungeonScores) end
        if mp.runHistory then fn(mp.runHistory) end
    end
    local gv = pveCache.greatVault
    if gv then
        if gv.activities then fn(gv.activities) end
        if gv.rewards then fn(gv.rewards) end
    end
    local lo = pveCache.lockouts
    if lo then
        if lo.raids then fn(lo.raids) end
        if lo.dungeons then fn(lo.dungeons) end
        if lo.worldBosses then fn(lo.worldBosses) end
    end
    if pveCache.delves and pveCache.delves.characters then
        fn(pveCache.delves.characters)
    end
end

--- Build oldKey -> canonical subsidiary key renames from roster + orphan subsidiary indices.
local function BuildSubsidiaryAliasRenames(db)
    local renames = {}
    local Utilities = ns.Utilities
    local issecretvalue = issecretvalue
    local chars = db.global.characters
    if type(chars) ~= "table" then return renames end

    local function noteRename(oldKey, newKey)
        if not oldKey or not newKey or oldKey == "" or newKey == "" or oldKey == newKey then return end
        if issecretvalue and (issecretvalue(oldKey) or issecretvalue(newKey)) then return end
        renames[oldKey] = newKey
    end

    for charKey, charData in pairs(chars) do
        if type(charData) == "table" then
            local target = charKey
            if Utilities and Utilities.ResolveCharacterRowKey then
                target = Utilities:ResolveCharacterRowKey(charData) or charKey
            end
            if Utilities and Utilities.GetCanonicalCharacterKey then
                target = Utilities:GetCanonicalCharacterKey(target) or target
            end
            noteRename(charKey, target)
            if charData.name and charData.realm and Utilities and Utilities.GetCharacterKey then
                local nk = Utilities:GetCharacterKey(charData.name, charData.realm)
                noteRename(nk, target)
            end
        end
    end

    local function noteFromSubsidiaryKey(subKey)
        if not subKey or subKey == "" then return end
        if issecretvalue and issecretvalue(subKey) then return end
        local canon = subKey
        if Utilities and Utilities.GetCanonicalCharacterKey then
            canon = Utilities:GetCanonicalCharacterKey(subKey) or subKey
        end
        noteRename(subKey, canon)
    end

    local cd = db.global.currencyData
    if cd then
        if cd.currencies then
            for subKey in pairs(cd.currencies) do noteFromSubsidiaryKey(subKey) end
        end
        if cd.totalEarned then
            for subKey in pairs(cd.totalEarned) do noteFromSubsidiaryKey(subKey) end
        end
    end

    if db.global.pveProgress then
        for subKey in pairs(db.global.pveProgress) do noteFromSubsidiaryKey(subKey) end
    end

    if db.global.pveCache then
        ForEachPveCharKeyedTable(db.global.pveCache, function(tbl)
            for subKey in pairs(tbl) do noteFromSubsidiaryKey(subKey) end
        end)
    end

    return renames
end

--- Union donor into target before RemapCharKeyedBucket drops the loser on collision.
local function MergeSubsidiaryBucketsBeforeRenames(db, renames)
    if type(renames) ~= "table" or not next(renames) then return end

    local cd = db.global.currencyData
    if cd then
        for oldKey, newKey in pairs(renames) do
            if oldKey ~= newKey then
                if cd.currencies and cd.currencies[oldKey] and cd.currencies[newKey] then
                    cd.currencies[newKey] = MergeCurrencyCharBucket(cd.currencies[newKey], cd.currencies[oldKey])
                end
                if cd.totalEarned and cd.totalEarned[oldKey] and cd.totalEarned[newKey] then
                    cd.totalEarned[newKey] = MergeCurrencyCharBucket(cd.totalEarned[newKey], cd.totalEarned[oldKey])
                end
            end
        end
    end

    if db.global.pveCache then
        ForEachPveCharKeyedTable(db.global.pveCache, function(tbl)
            for oldKey, newKey in pairs(renames) do
                if oldKey ~= newKey and tbl[oldKey] and tbl[newKey] then
                    tbl[newKey] = MergePvECharBucket(tbl[newKey], tbl[oldKey])
                end
            end
        end)
    end
end

--- One-time: fold Name-Realm (and other alias) subsidiary buckets into canonical GUID/storage keys.
--- Runs after roster GUID migration; merges data when both alias and target buckets exist.
---@param db table AceDB root
function MigrationService:MigrateSubsidiaryAliasBucketsV1(db)
    if not db or not db.global then return end
    if db.global.subsidiaryAliasConsolidatedV1 then return end
    if not db.global.charactersGuidKeyedV1 then return end

    local renames = BuildSubsidiaryAliasRenames(db)
    local renameCount = 0
    for _ in pairs(renames) do renameCount = renameCount + 1 end

    if next(renames) then
        MergeSubsidiaryBucketsBeforeRenames(db, renames)
        self:ApplyCharacterKeyedStorageRenames(db, renames)
    end

    DebugPrint("|cff9370DB[WN Migration]|r subsidiaryAliasConsolidatedV1: remapped "
        .. tostring(renameCount) .. " alias key(s)")

    db.global.subsidiaryAliasConsolidatedV1 = true
end

--- True when `key` has a non-empty payload in any character-keyed subsidiary global.
local function SubsidiaryBucketHasData(db, key)
    if not db or not db.global or not key or key == "" then return false end
    if issecretvalue and issecretvalue(key) then return false end

    local function bucketNonempty(tbl)
        if type(tbl) ~= "table" then return false end
        local entry = tbl[key]
        if entry == nil then return false end
        if type(entry) ~= "table" then return true end
        return next(entry) ~= nil
    end

    local g = db.global
    local cd = g.currencyData
    if cd then
        if bucketNonempty(cd.currencies) or bucketNonempty(cd.totalEarned) then return true end
    end
    if bucketNonempty(g.gearData) or bucketNonempty(g.pveProgress)
        or bucketNonempty(g.statisticSnapshots) or bucketNonempty(g.personalBanks)
        or bucketNonempty(g.itemStorage) then
        return true
    end
    local rd = g.reputationData
    if rd and bucketNonempty(rd.characters) then return true end

    local pc = g.pveCache
    if type(pc) == "table" then
        local mp = pc.mythicPlus
        if mp and (bucketNonempty(mp.keystones) or bucketNonempty(mp.bestRuns)
            or bucketNonempty(mp.dungeonScores) or bucketNonempty(mp.runHistory)) then
            return true
        end
        local gv = pc.greatVault
        if gv and (bucketNonempty(gv.activities) or bucketNonempty(gv.rewards)) then return true end
        local lo = pc.lockouts
        if lo and (bucketNonempty(lo.raids) or bucketNonempty(lo.dungeons) or bucketNonempty(lo.worldBosses)) then
            return true
        end
        if pc.delves and pc.delves.characters and bucketNonempty(pc.delves.characters) then return true end
    end
    return false
end

--- Remove `legacyKey` from subsidiary tables when `canonKey` already holds data (post-remap SV bloat guard).
local function PurgeLegacySubsidiaryKeyWhenCanonicalHasData(db, legacyKey, canonKey)
    if not db or not db.global or not legacyKey or not canonKey or legacyKey == canonKey then return 0 end
    if not SubsidiaryBucketHasData(db, canonKey) then return 0 end
    if SubsidiaryBucketHasData(db, legacyKey) then return 0 end

    local removed = 0
    local g = db.global

    local function nilKey(tbl)
        if type(tbl) ~= "table" or tbl[legacyKey] == nil then return end
        tbl[legacyKey] = nil
        removed = removed + 1
    end

    local cd = g.currencyData
    if cd then
        nilKey(cd.currencies)
        nilKey(cd.totalEarned)
    end
    nilKey(g.gearData)
    nilKey(g.pveProgress)
    nilKey(g.statisticSnapshots)
    nilKey(g.personalBanks)
    nilKey(g.itemStorage)
    if g.reputationData then nilKey(g.reputationData.characters) end

    local pc = g.pveCache
    if type(pc) == "table" then
        local mp = pc.mythicPlus
        if mp then
            nilKey(mp.keystones)
            nilKey(mp.bestRuns)
            nilKey(mp.dungeonScores)
            nilKey(mp.runHistory)
        end
        local gv = pc.greatVault
        if gv then
            nilKey(gv.activities)
            nilKey(gv.rewards)
        end
        local lo = pc.lockouts
        if lo then
            nilKey(lo.raids)
            nilKey(lo.dungeons)
            nilKey(lo.worldBosses)
        end
        if pc.delves and pc.delves.characters then nilKey(pc.delves.characters) end
    end
    return removed
end

--- After orphan remap: drop empty legacy subsidiary shells when canonical bucket has data.
---@param db table AceDB root
---@return number purged
function MigrationService:PruneLegacySubsidiaryDuplicates(db)
    if not db or not db.global or not db.global.characters then return 0 end
    local Utilities = ns.Utilities
    local purged = 0
    for _, charData in pairs(db.global.characters) do
        if type(charData) == "table" and charData.name and charData.realm and Utilities then
            local canonKey = Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(charData)
            if canonKey and Utilities.GetCanonicalCharacterKey then
                canonKey = Utilities:GetCanonicalCharacterKey(canonKey) or canonKey
            end
            local legacyKey = Utilities.GetCharacterKey and Utilities:GetCharacterKey(charData.name, charData.realm)
            if legacyKey and canonKey and legacyKey ~= canonKey then
                purged = purged + PurgeLegacySubsidiaryKeyWhenCanonicalHasData(db, legacyKey, canonKey)
            end
        end
    end
    return purged
end

local function RosterOwnsSubsidiaryKeyForMigration(db, subsidiaryKey)
    local addon = _G.WarbandNexus
    local CS = ns.CharacterService
    if CS and addon and addon.db == db and CS.CharacterOwnsSubsidiaryKey then
        return CS:CharacterOwnsSubsidiaryKey(addon, subsidiaryKey)
    end
    local chars = db.global.characters
    if type(chars) ~= "table" then return false end
    return chars[subsidiaryKey] ~= nil
end

--- Match orphan subsidiary key to roster storage key (name/realm/guid/VaultCharKeysMatch).
local function FindRosterTargetForOrphanKey(db, orphanKey)
    local chars = db.global.characters
    local Utilities = ns.Utilities
    if type(chars) ~= "table" or not orphanKey or orphanKey == "" then return nil end
    if issecretvalue and issecretvalue(orphanKey) then return nil end

    if chars[orphanKey] and Utilities and Utilities.ResolveCharacterRowKey then
        return Utilities:ResolveCharacterRowKey(chars[orphanKey]) or orphanKey
    end

    if Utilities and Utilities.GetCanonicalCharacterKey then
        local canon = Utilities:GetCanonicalCharacterKey(orphanKey)
        if canon and chars[canon] then
            return Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(chars[canon]) or canon
        end
    end

    for key, row in pairs(chars) do
        if type(row) == "table" then
            if key == orphanKey then
                return Utilities and Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(row) or key
            end
            if ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(key, orphanKey) then
                return Utilities and Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(row) or key
            end
            if row.guid and type(row.guid) == "string" and row.guid == orphanKey
                and not (issecretvalue and issecretvalue(row.guid)) then
                return Utilities and Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(row) or key
            end
            if row.name and row.realm and Utilities and Utilities.GetCharacterKey then
                local nk = Utilities:GetCharacterKey(row.name, row.realm)
                if nk == orphanKey or (ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(nk, orphanKey)) then
                    return Utilities.ResolveCharacterRowKey and Utilities:ResolveCharacterRowKey(row) or key
                end
            end
        end
    end
    return nil
end

--- Collect subsidiary keys from all char-keyed globals.
local function CollectSubsidiaryKeys(db, into)
    if type(into) ~= "table" then return end
    local function note(k)
        if k and k ~= "" and not (issecretvalue and issecretvalue(k)) then into[k] = true end
    end
    local g = db.global
    local cd = g.currencyData
    if cd then
        if cd.currencies then for k in pairs(cd.currencies) do note(k) end end
        if cd.totalEarned then for k in pairs(cd.totalEarned) do note(k) end end
    end
    if g.gearData then for k in pairs(g.gearData) do note(k) end end
    if g.pveProgress then for k in pairs(g.pveProgress) do note(k) end end
    if g.statisticSnapshots then for k in pairs(g.statisticSnapshots) do note(k) end end
    if g.personalBanks then for k in pairs(g.personalBanks) do note(k) end end
    if g.itemStorage then for k in pairs(g.itemStorage) do note(k) end end
    if g.reputationData and g.reputationData.characters then
        for k in pairs(g.reputationData.characters) do note(k) end
    end
    if g.pveCache then
        ForEachPveCharKeyedTable(g.pveCache, function(tbl)
            for k in pairs(tbl) do note(k) end
        end)
    end
end

--- Build orphan subsidiary renames (legacy Name-Realm buckets + unowned subsidiary keys).
local function BuildSubsidiaryOrphanRenames(db)
    local renames = {}
    local Utilities = ns.Utilities
    local chars = db.global.characters
    if type(chars) ~= "table" then return renames end

    local function noteRename(oldKey, newKey)
        if not oldKey or not newKey or oldKey == "" or newKey == "" or oldKey == newKey then return end
        if issecretvalue and (issecretvalue(oldKey) or issecretvalue(newKey)) then return end
        renames[oldKey] = newKey
    end

    for charKey, charData in pairs(chars) do
        if type(charData) == "table" then
            local target = charKey
            if Utilities and Utilities.ResolveCharacterRowKey then
                target = Utilities:ResolveCharacterRowKey(charData) or charKey
            end
            if Utilities and Utilities.GetCanonicalCharacterKey then
                target = Utilities:GetCanonicalCharacterKey(target) or target
            end
            noteRename(charKey, target)
            local guid = charData.guid
            if type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then
                noteRename(guid, target)
            end
            if charData.name and charData.realm and Utilities and Utilities.GetCharacterKey then
                local legacyKey = Utilities:GetCharacterKey(charData.name, charData.realm)
                if legacyKey and legacyKey ~= target then
                    if SubsidiaryBucketHasData(db, legacyKey) and not SubsidiaryBucketHasData(db, target) then
                        noteRename(legacyKey, target)
                    elseif SubsidiaryBucketHasData(db, legacyKey) then
                        noteRename(legacyKey, target)
                    end
                end
            end
        end
    end

    local orphanKeys = {}
    CollectSubsidiaryKeys(db, orphanKeys)
    for subKey in pairs(orphanKeys) do
        if not RosterOwnsSubsidiaryKeyForMigration(db, subKey) then
            local target = FindRosterTargetForOrphanKey(db, subKey)
            if target and target ~= subKey then
                noteRename(subKey, target)
            end
        end
    end

    return renames
end

--- One-time: remap orphan legacy subsidiary buckets (Name-Realm-only data, unowned keys) onto canonical GUID/storage keys.
--- Runs after roster dedup; idempotent via `subsidiaryOrphanRemapV1`.
---@param db table AceDB root
function MigrationService:MigrateSubsidiaryOrphanKeys(db)
    if not db or not db.global then return end
    if db.global.subsidiaryOrphanRemapV1 then return end

    local renames = BuildSubsidiaryOrphanRenames(db)
    local renameCount = 0
    for _ in pairs(renames) do renameCount = renameCount + 1 end

    if next(renames) then
        MergeSubsidiaryBucketsBeforeRenames(db, renames)
        self:ApplyCharacterKeyedStorageRenames(db, renames)
    end

    local purged = self:PruneLegacySubsidiaryDuplicates(db)

    if DebugPrint then
        DebugPrint("|cff9370DB[WN Migration]|r subsidiaryOrphanRemapV1: remapped "
            .. tostring(renameCount) .. " orphan key(s); pruned " .. tostring(purged) .. " empty legacy shell(s)")
    end

    db.global.subsidiaryOrphanRemapV1 = true
end

--- Remove unused `db.global.reputations` when `reputationData.characters` is authoritative.
function MigrationService:DropStaleLegacyGlobalReputations(db)
    if not db or not db.global or db.global._legacyReputationsDropV1 then return end
    local legacy = db.global.reputations
    if type(legacy) ~= "table" then
        db.global._legacyReputationsDropV1 = true
        return
    end
    local rd = db.global.reputationData and db.global.reputationData.characters
    if rd and next(rd) then
        db.global.reputations = nil
        if DebugPrint then
            DebugPrint("|cff9370DB[Migration]|r Dropped stale db.global.reputations (reputationData authoritative)")
        end
    end
    db.global._legacyReputationsDropV1 = true
end

return MigrationService
