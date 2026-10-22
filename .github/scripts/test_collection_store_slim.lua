#!/usr/bin/env lua
--[[
    Regression test: db.global.collectionStore persists only what the client cannot give back.

    The store (~3.1 MB in a real SavedVariables) held every mount/pet/achievement/title row with
    its full display metadata (name, icon, source text, description, journal fields). All of it
    is re-read synchronously from the journal APIs for the entity id, so it was parsed on every
    login and written on every logout for nothing.

    Drives the shipped files under wow_stub.lua:
      1. MigrateSlimCollectionStoreV1 strips display fields, keeps collected/points/source indices,
         leaves toys + illusions alone, tolerates partial data and runs once (RunMigrations reaches it).
      2. Readers of a stripped row return the API's display values (and the "ID:<id>" placeholder
         when the API has nothing), not blanks.
      3. A fresh scan + save writes the slim shape, while the session keeps the scanned values hot.
      4. Serialized size of a synthetic store with realistic counts, before / after.
]]

local passed, failed = 0, 0
local function check(cond, msg, detail)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg .. (detail and (": " .. tostring(detail)) or ""))
    end
end
local function assert_eq(actual, expected, msg)
    check(actual == expected, msg, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    UnregisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
-- WoW's string library carries trim (title extract uses titleString:gsub(...):trim()).
string.trim = string.trim or strtrim

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.IsModuleEnabled = function() return true end
ns.Utilities.IsAnyModuleEnabled = function() return true end
ns.Utilities.GetCharacterStorageKey = function() return "Player-01" end
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/CollectionService_Materialize.lua")
LoadFile("Modules/CollectionService_NotifyDedup.lua")
LoadFile("Modules/CollectionService_Scan.lua")
LoadFile("Modules/CollectionService.lua")
LoadFile("Modules/CollectionService_Store.lua")
LoadFile("Modules/CollectionService_JournalScan.lua")
LoadFile("Modules/CollectionService_Metadata.lua")
LoadFile("Modules/CollectionService_Queries.lua")
LoadFile("Modules/CollectionService_Achievements.lua")

local RT = ns.CollectionServiceRT
local MS = ns.MigrationService
local CACHE_VERSION = RT.CACHE_VERSION

-- ---------- journal API stubs (shapes per Blizzard_APIDocumentationGenerated 12.1.5) ----------
local apiCalls = { mount = 0, pet = 0, achievement = 0, title = 0 }
local apiMissing = {}   -- id -> true: API returns nothing for it (journal not ready)

-- GetMountInfoByID -> name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
-- isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID, isSteadyFlight
C_MountJournal.GetMountInfoByID = function(id)
    apiCalls.mount = apiCalls.mount + 1
    if apiMissing[id] then return nil end
    return "Api Mount " .. id, 100000 + id, 200000 + id, false, true, 4, false, false, nil, false, (id % 2 == 0), id, false
end
-- GetMountInfoExtraByID -> creatureDisplayInfoID, description, source, ...
C_MountJournal.GetMountInfoExtraByID = function(id)
    return 300000 + id, "Api mount description " .. id, "Api mount source " .. id
end
C_MountJournal.GetMountIDs = function() return { 2001, 2002, 2003 } end
-- GetPetInfoBySpeciesID -> name, icon, petType, creatureID, sourceText, description, isWild,
-- canBattle, tradable, unique, obtainable, displayID
C_PetJournal.GetPetInfoBySpeciesID = function(id)
    apiCalls.pet = apiCalls.pet + 1
    if apiMissing[id] then return nil end
    return "Api Pet " .. id, 400000 + id, 3, 500000 + id, "Api pet source " .. id, "Api pet description " .. id,
        false, true, true, false, true, 600000 + id
end
C_PetJournal.GetNumCollectedInfo = function() return 1, 3 end
-- GetAchievementInfo -> id, name, points, completed, month, day, year, description, flags, icon,
-- rewardText, isGuild, wasEarnedByMe, earnedBy, isStatistic
_G.GetAchievementInfo = function(id)
    apiCalls.achievement = apiCalls.achievement + 1
    if apiMissing[id] then return nil end
    return id, "Api Achievement " .. id, 10, false, nil, nil, nil, "Api achievement description " .. id, 0,
        700000 + id, (id == 15 and "Reward: Api Title" or ""), false, false, nil, false
end
_G.GetAchievementCategory = function(id) return 92 end
_G.GetTitleName = function(id)
    apiCalls.title = apiCalls.title + 1
    if apiMissing[id] then return nil end
    return "Api Title " .. id .. " %s", false
end
_G.IsTitleKnown = function() return true end
_G.GetNumTitles = function() return 0 end

local function rawKeys(row)
    local keys = {}
    for k in pairs(row) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Rows as the shipped scans write them (COLLECTION_CONFIGS extract / ScanAchievementsAsync record).
local function FullMountRow(id, collected)
    return { id = id, name = "Saved Mount " .. id, icon = 1000 + id, spellID = 2000 + id, source = "Saved source " .. id,
        sourceType = 7, description = "Saved description " .. id, creatureDisplayID = 3000 + id, collected = collected,
        shouldHideOnChar = false, isFactionSpecific = false, faction = nil, isSteadyFlight = false }
end
local function FullPetRow(id, collected)
    return { id = id, name = "Saved Pet " .. id, icon = 1000 + id, source = "Saved pet source " .. id, sourceTypeIndex = 2,
        description = "Saved pet description " .. id, collected = collected, petType = 5, creatureDisplayID = 3000 + id,
        obtainable = true }
end
local function FullAchievementRow(id, collected)
    return { id = id, name = "Saved Achievement " .. id, icon = 1000 + id, points = 25, description = "Saved ach description " .. id,
        collected = collected, categoryID = 15000 + id, rewardItemID = nil, rewardTitle = nil }
end
local function FullTitleRow(id, collected)
    return { id = id, name = "Saved Title " .. id, titleString = "Saved Title " .. id .. " %s", playerTitle = false,
        collected = collected, iconAtlas = "poi-legendsoftheharanir", source = "Player Title", type = "title" }
end

-- ---------------------------------------------------------------------------------------------
print("Phase 1: MigrateSlimCollectionStoreV1 strips display fields from an existing store")
local db = WarbandNexus.db
do
    db.global.collectionStore = {
        version = CACHE_VERSION,
        lastBuilt = 1700000000,
        mount = { [6] = FullMountRow(6, true), [7] = FullMountRow(7, false), [8] = "corrupt" },
        pet = { [39] = FullPetRow(39, true) },
        toy = { [1973] = { id = 1973, name = "Orb of Deception" } },
        achievement = { [6] = FullAchievementRow(6, true), [15] = FullAchievementRow(15, false), [16] = { collected = true } },
        title = { [1] = FullTitleRow(1, true) },
        illusion = { [5000] = { id = 5000, name = "Illusion: Mongoose", icon = 1, source = "Enchanting", collected = true } },
        scanCompleted = { mount = 1700000000 },
    }
    -- Existing install: schema current, fast path stamped by the previous release.
    db.global._schemaVersion = 13
    db.global._wnMigrationFastPathRev = 5
    local ok, err = pcall(MS.RunMigrations, MS, db)
    check(ok, "RunMigrations completes on an existing install", err)
    assert_eq(db.global.collectionStoreSlimV1, true, "RunMigrations reached the slim migration (fast-path revision bumped)")

    local store = db.global.collectionStore
    assert_eq(rawKeys(store.mount[6]), "collected,id,sourceType", "mount row keeps id, collected, sourceType only")
    assert_eq(store.mount[6].collected, true, "mount collected flag kept")
    assert_eq(store.mount[6].sourceType, 7, "mount sourceType kept (filter-sweep fallback is not per-id)")
    assert_eq(store.mount[8], "corrupt", "non-table row left alone (partial data is safe)")
    assert_eq(rawKeys(store.pet[39]), "collected,id,sourceTypeIndex", "pet row keeps id, collected, sourceTypeIndex only")
    assert_eq(rawKeys(store.achievement[6]), "collected,id,points", "achievement row keeps id, collected, points only")
    assert_eq(store.achievement[6].points, 25, "achievement points kept")
    assert_eq(store.achievement[16].id, 16, "row saved without id gets its key as id")
    assert_eq(rawKeys(store.title[1]), "collected,id", "title row keeps id, collected only")
    assert_eq(store.toy[1973].name, "Orb of Deception", "toy rows untouched (name needs item data)")
    assert_eq(store.illusion[5000].source, "Enchanting", "illusion rows untouched")

    -- Runs once: a later full row (e.g. written by an older client) is not stripped again by the migration.
    store.mount[9] = FullMountRow(9, true)
    pcall(MS.MigrateSlimCollectionStoreV1, MS, db)
    assert_eq(store.mount[9].name, "Saved Mount 9", "flagged migration does not run a second time")
    store.mount[9] = nil
end

-- ---------------------------------------------------------------------------------------------
print("Phase 2: readers of stripped rows return the API display values")
do
    WarbandNexus:InitializeCollectionCache()
    local mount = WarbandNexus:GetMountData(6)
    assert_eq(mount and mount.name, "Api Mount 6", "GetMountData name comes from C_MountJournal")
    assert_eq(mount and mount.icon, 200006, "mount icon from C_MountJournal")
    assert_eq(mount and mount.source, "Api mount source 6", "mount source text from GetMountInfoExtraByID")
    assert_eq(mount and mount.creatureDisplayID, 300006, "mount creatureDisplayID from GetMountInfoExtraByID")
    assert_eq(mount and mount.collected, true, "mount collected still the persisted flag")
    assert_eq(mount and mount.sourceType, 7, "mount sourceType still the persisted value")

    local pets = WarbandNexus:GetAllPetsData()
    assert_eq(pets[1] and pets[1].name, "Api Pet 39", "GetAllPetsData name comes from C_PetJournal")
    assert_eq(pets[1] and pets[1].description, "Api pet description 39", "pet description from C_PetJournal")
    assert_eq(pets[1] and pets[1].sourceTypeIndex, 2, "pet sourceTypeIndex still the persisted value")

    local unc = WarbandNexus:GetUncollectedAchievements("", 100)
    local a15
    for i = 1, #unc do if unc[i].id == 15 then a15 = unc[i] end end
    assert_eq(a15 and a15.name, "Api Achievement 15", "uncollected achievement name from GetAchievementInfo")
    assert_eq(a15 and a15.description, "Api achievement description 15", "achievement description from GetAchievementInfo")
    assert_eq(a15 and a15.icon, 700015, "achievement icon from GetAchievementInfo (10th return)")
    assert_eq(a15 and a15.points, 25, "achievement points still the persisted value")
    assert_eq(a15 and a15.categoryID, 92, "achievement categoryID from GetAchievementCategory")
    assert_eq(a15 and a15.rewardTitle, "Reward: Api Title", "achievement reward text from GetAchievementInfo (11th return)")
    local searched = WarbandNexus:GetUncollectedAchievements("api achievement 15", 10)
    assert_eq(#searched, 1, "name search works on a stripped row")

    local title = RT.collectionStore.title[1]
    assert_eq(title and title.name, "Api Title 1", "title name from GetTitleName (placeholder stripped)")
    assert_eq(title and title.titleString, "Api Title 1 %s", "title format string from GetTitleName")

    -- Resolved once per id, then served from RAM.
    local before = apiCalls.mount
    local _ = mount.name, mount.description, mount.spellID
    assert_eq(apiCalls.mount, before, "second read of a resolved mount does not call the API again")

    -- API has nothing yet: same placeholder the list readers print, never a blank name.
    apiMissing[7] = true
    local m7 = WarbandNexus:GetMountData(7)
    assert_eq(m7 and m7.name, "ID:7", "unresolvable mount name reads as ID:<id>")
    apiMissing[7] = nil
    assert_eq(m7 and m7.name, "Api Mount 7", "name resolves once the API answers")

    -- SumAchievementJournalPointsMax probes isGuild on every row; that must not trigger the resolver.
    local callsBefore = apiCalls.achievement
    local probe = RT.collectionStore.achievement[6].isGuild
    assert_eq(probe, nil, "isGuild (never stored) still reads nil")
    assert_eq(apiCalls.achievement, callsBefore, "probing a non-display key does not hit the API")
end

-- ---------------------------------------------------------------------------------------------
print("Phase 3: a fresh scan writes the slim shape and keeps scanned values in RAM")
do
    local done = false
    RT.collectionCache.lastScan = 0   -- past the 5-minute "recent scan" skip
    WarbandNexus:ScanCollection("mount", nil, function() done = true end)
    stub.Advance(5)
    check(done, "mount scan completed")
    local saved = db.global.collectionStore.mount
    local row = saved and saved[2001]
    check(row ~= nil, "scanned mount persisted")
    if row then
        assert_eq(rawKeys(row), "collected,id,sourceType", "scanned mount persisted slim")
        assert_eq(row.name, "Api Mount 2001", "scanned mount name still readable in session")
    end
    local calls = apiCalls.mount
    local _ = row and row.description
    assert_eq(apiCalls.mount, calls, "scan values served from RAM after save (no re-resolve)")

    -- A writer that sets a display field on a persisted row keeps it out of SV.
    local m6 = RT.collectionStore.mount[2002]
    if m6 then m6.description = "Patched in session" end
    WarbandNexus:SaveCollectionStore()
    local r = db.global.collectionStore.mount[2002]
    assert_eq(r and rawget(r, "description"), nil, "display field set after save is not persisted")
    assert_eq(r and r.description, "Patched in session", "display field set after save is readable in session")

    -- Achievement earned for an id the store did not have: new row carries its id so it can resolve.
    WarbandNexus:OnAchievementEarned(nil, 77)
    local a77 = RT.collectionStore.achievement[77]
    assert_eq(a77 and a77.name, "Api Achievement 77", "earned-achievement row resolves its name")
end

-- ---------------------------------------------------------------------------------------------
print("Phase 3b: placeholder caching, fresh rows, display warm-up")
do
    -- Pet metadata while the journal has nothing yet must not pin the placeholder for the session.
    RT.collectionStore.pet[41] = { id = 41, collected = false, sourceTypeIndex = 1 }
    RT.SlimCollectionStoreRows("pet", RT.collectionStore.pet)
    apiMissing[41] = true
    local early = WarbandNexus:ResolveCollectionMetadata("pet", 41)
    assert_eq(early and early.name, "ID:41", "unresolved pet metadata reads the placeholder")
    apiMissing[41] = nil
    local later = WarbandNexus:ResolveCollectionMetadata("pet", 41)
    assert_eq(later and later.name, "Api Pet 41", "pet metadata resolves once the journal answers (placeholder not cached)")

    -- A rescan row replaces what RAM held for that id; fields it leaves out resolve again.
    RT.collectionStore.mount[2002] = { id = 2002, collected = true, sourceType = 4, name = "Rescanned 2002" }
    RT.SlimCollectionStoreRows("mount", RT.collectionStore.mount)
    local m = RT.collectionStore.mount[2002]
    assert_eq(m.name, "Rescanned 2002", "fresh row's own field wins")
    assert_eq(m.description, "Api mount description 2002", "field missing from the fresh row resolves again, not the stale session value")

    -- Store load schedules a warm-up: slim rows resolve ahead of the first list query.
    for id = 501, 520 do RT.collectionStore.achievement[id] = { id = id, collected = false, points = 5 } end
    RT.SlimCollectionStoreRows("achievement", RT.collectionStore.achievement)
    local callsBefore = apiCalls.achievement
    stub.Advance(10)
    check(apiCalls.achievement - callsBefore >= 20, "load-time warm-up resolved the unread achievement rows",
        apiCalls.achievement - callsBefore)
    local afterWarm = apiCalls.achievement
    local unc = WarbandNexus:GetUncollectedAchievements("", nil)
    check(#unc >= 20, "uncollected achievement list returned", #unc)
    assert_eq(apiCalls.achievement, afterWarm, "list query after warm-up makes no achievement API calls")

    -- Warm-up work is spread over frames by its time budget.
    for id = 601, 640 do RT.collectionStore.achievement[id] = { id = id, collected = false, points = 5 } end
    RT.SlimCollectionStoreRows("achievement", RT.collectionStore.achievement)
    local realProfile, realAfter = debugprofilestop, C_Timer.After
    local fakeMs, slices = 0, 0
    debugprofilestop = function() fakeMs = fakeMs + 1; return fakeMs end
    C_Timer.After = function(delay, fn) if delay == 0 then slices = slices + 1 end; return realAfter(delay, fn) end
    RT.WarmStoreRowDisplay({ "achievement" })
    stub.Advance(1)
    debugprofilestop, C_Timer.After = realProfile, realAfter
    check(slices > 5, "warm-up ran in several budgeted slices", slices)
    local calls = apiCalls.achievement
    local _ = RT.collectionStore.achievement[640].name
    assert_eq(apiCalls.achievement, calls, "every queued row resolved by the sliced warm-up")
end

-- ---------------------------------------------------------------------------------------------
print("Phase 4: serialized size on a synthetic store")
-- WoW SavedVariables layout: one `["key"] = value,` line per field, tab-indented.
local function Serialize(v, depth, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = string.format("%q", v)
    elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{\n"
        local pad = string.rep("\t", depth + 1)
        for k, val in next, v do
            out[#out + 1] = pad
            out[#out + 1] = type(k) == "string" and string.format("[%q] = ", k) or ("[" .. tostring(k) .. "] = ")
            Serialize(val, depth + 1, out)
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = string.rep("\t", depth) .. "}"
    else out[#out + 1] = "nil" end
    return out
end
local function SizeOf(tbl) return #table.concat(Serialize(tbl, 0, {})) end

local COUNTS = { mount = 1000, pet = 1500, toy = 800, achievement = 12000, title = 700, illusion = 150 }
local function Realistic(category, id)
    local collected = (id % 3 ~= 0)
    if category == "mount" then
        local r = FullMountRow(id, collected)
        r.name = "Reins of the Thundering Cobalt Cloud Serpent"
        r.source = "|cFFFFD200Drop:|r Huolon\n|cFFFFD200Zone:|r Isle of Thunder"
        r.description = "A cloud serpent bred in the storms of the Isle of Thunder; its scales crackle with lightning."
        r.icon = 4700000 + id
        return r
    elseif category == "pet" then
        local r = FullPetRow(id, collected)
        r.name = "Mechanical Squirrel"
        r.source = "|cFFFFD200Profession:|r Engineering\n|cFFFFD200Formula:|r Mechanical Squirrel Box"
        r.description = "Gnomish engineers built this tireless squirrel to gather nuts; it mostly gathers bolts."
        return r
    elseif category == "achievement" then
        local r = FullAchievementRow(id, collected)
        r.name = "Glory of the Midnight Raider"
        r.description = "Complete the Midnight raid achievements listed below."
        r.icon = 6000000 + id
        r.categoryID = 15400 + (id % 50)
        return r
    elseif category == "title" then
        return FullTitleRow(id, collected)
    elseif category == "toy" then
        return { id = id, name = "Toy Number " .. id }
    else
        return { id = id, name = "Illusion: Mongoose", icon = 135000 + id, sourceText = "Enchanting", source = "Enchanting",
            collected = collected, visualID = 100 + id, hyperlink = "|cff71d5ff|Htransmogillusion:" .. id .. "|h[Mongoose]|h|r" }
    end
end
do
    local full = { version = CACHE_VERSION, lastBuilt = 1700000000, scanCompleted = {} }
    for category, n in pairs(COUNTS) do
        local map = {}
        for i = 1, n do map[100000 + i] = Realistic(category, 100000 + i) end
        full[category] = map
    end
    local beforeBytes = SizeOf(full)

    -- Same rows in RAM, persisted through the shipped save path.
    for category in pairs(COUNTS) do RT.collectionStore[category] = full[category] end
    WarbandNexus:SaveCollectionStore()
    local afterBytes = SizeOf(db.global.collectionStore)
    print(string.format("  info synthetic store (%d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions)",
        COUNTS.mount, COUNTS.pet, COUNTS.toy, COUNTS.achievement, COUNTS.title, COUNTS.illusion))
    print(string.format("  info serialized before: %d bytes (%.2f MB) | after: %d bytes (%.2f MB) | %.0f%% smaller",
        beforeBytes, beforeBytes / 1048576, afterBytes, afterBytes / 1048576, 100 * (1 - afterBytes / beforeBytes)))
    check(afterBytes < beforeBytes * 0.5, "saved store is under half of the full-row size", afterBytes .. " vs " .. beforeBytes)
    local m = RT.collectionStore.mount[100001]
    assert_eq(m and m.name, "Reins of the Thundering Cobalt Cloud Serpent", "in-session reader keeps the scanned name after save")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    err: " .. stub.errors[i]) end end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Collection store slim suite failed with " .. failed .. " failure(s).")
end
print("Collection store slim suite: ALL TESTS PASSED.")
