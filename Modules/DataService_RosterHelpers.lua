--[[
    Warband Nexus - Character roster cache sig + safe money + storage row helpers.
    Split from DataService.lua (Lua 5.1 local limit).
    Loaded before Modules/DataService.lua.
]]

local _, ns = ...
local issecretvalue = issecretvalue

local MERGE_GUID_PREFIX = "\001g\001"
local MERGE_NAME_PREFIX = "\001n\001"

local _allCharsRosterCache = { sig = nil, list = nil }

local function ComputeCharactersRosterSig(chars)
    if not chars then return "0:0" end
    local n, acc = 0, 0
    for _, row in pairs(chars) do
        if type(row) == "table" then
            n = n + 1
            acc = acc + (tonumber(row.lastSeen) or 0)
            acc = acc + ((tonumber(row.level) or 0) * 1315423911)
        end
    end
    return tostring(n) .. ":" .. tostring(acc)
end

local function InvalidateGetAllCharactersCache()
    _allCharsRosterCache.sig = nil
    _allCharsRosterCache.list = nil
end

--- GetMoney() may return a secret value (Midnight+); math.floor/tonumber on it throws.
--- When secret, fall back to last saved gold/silver/copper from existingEntry if present.
local function SafeGetMoneyCopperFromEntry(existingEntry)
    local m = GetMoney()
    if m == nil then return 0 end
    if issecretvalue and issecretvalue(m) then
        if existingEntry and type(existingEntry.gold) == "number" then
            return math.floor((existingEntry.gold or 0) * 10000 + (existingEntry.silver or 0) * 100 + (existingEntry.copper or 0))
        end
        return 0
    end
    local n = tonumber(m)
    if not n then return 0 end
    return math.floor(n)
end

--- Fill missing name/realm on a roster row from its table index when possible.
local function EnsureCharNameRealm(data, key)
    if type(data) ~= "table" then return nil, nil end
    local name, realm = data.name, data.realm
    if (not name or name == "") or (not realm or realm == "") then
        local U = ns.Utilities
        if key and type(key) == "string" and U and U.SplitCharacterKey then
            local n, r = U:SplitCharacterKey(key)
            if n and r then
                name, realm = n, r
                data.name = name
                data.realm = realm
            end
        end
    end
    if name and realm and name ~= "" and realm ~= "" then
        return name, realm
    end
    return nil, nil
end

--- Index Name-Realm -> guid for rows that already store guid (cross-link legacy duplicates).
local function BuildGuidByNameRealmIndex(charsTbl)
    local guidByNameRealm = {}
    if type(charsTbl) ~= "table" then return guidByNameRealm end
    local U = ns.Utilities
    for key, data in pairs(charsTbl) do
        if type(data) == "table" then
            local name, realm = EnsureCharNameRealm(data, key)
            if name and realm and U and U.GetCharacterKey then
                local g = data.guid
                if type(g) ~= "string" or g == "" or (issecretvalue and issecretvalue(g)) then
                    if type(key) == "string" and not (issecretvalue and issecretvalue(key))
                        and key:sub(1, 7) == "Player-" then
                        g = key
                    end
                end
                if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                    local normalizedKey = U:GetCharacterKey(name, realm)
                    if normalizedKey then
                        guidByNameRealm[normalizedKey] = g
                    end
                end
            end
        end
    end
    -- Legacy rows without guid: link to a guid-shaped sibling with the same name+realm.
    for key, data in pairs(charsTbl) do
        if type(data) == "table" then
            local name, realm = EnsureCharNameRealm(data, key)
            if name and realm and U and U.GetCharacterKey then
                local normalizedKey = U:GetCharacterKey(name, realm)
                if normalizedKey and not guidByNameRealm[normalizedKey] then
                    for k2, d2 in pairs(charsTbl) do
                        if type(d2) == "table" then
                            local n2, r2 = EnsureCharNameRealm(d2, k2)
                            if n2 == name and r2 == realm then
                                local g2 = d2.guid
                                if (type(g2) ~= "string" or g2 == "" or (issecretvalue and issecretvalue(g2)))
                                    and type(k2) == "string" and not (issecretvalue and issecretvalue(k2))
                                    and k2:sub(1, 7) == "Player-" then
                                    g2 = k2
                                end
                                if type(g2) == "string" and g2 ~= ""
                                    and not (issecretvalue and issecretvalue(g2)) then
                                    guidByNameRealm[normalizedKey] = g2
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return guidByNameRealm
end

--- Stable merge bucket for duplicate roster rows (guid + legacy Name-Realm).
local function ComputeCharacterMergeKey(data, key, guidByNameRealm)
    if type(data) ~= "table" then return nil end
    local U = ns.Utilities
    local g = data.guid
    if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
        return MERGE_GUID_PREFIX .. g
    end
    if type(key) == "string" and not (issecretvalue and issecretvalue(key))
        and key:sub(1, 7) == "Player-" then
        return MERGE_GUID_PREFIX .. key
    end
    local name, realm = EnsureCharNameRealm(data, key)
    if not name or not realm then return nil end
    local normalizedKey = (U and U.GetCharacterKey and U:GetCharacterKey(name, realm)) or key
    if normalizedKey and guidByNameRealm and guidByNameRealm[normalizedKey] then
        return MERGE_GUID_PREFIX .. guidByNameRealm[normalizedKey]
    end
    local rowStorageKey = U and U.ResolveCharacterRowKey and U:ResolveCharacterRowKey(data)
    return MERGE_NAME_PREFIX .. (rowStorageKey or normalizedKey or key)
end

--- Resolve rename chains (A->B, B->C => A->C).
local function ResolveRenameChains(renames)
    if type(renames) ~= "table" then return end
    for loserKey, survivorKey in pairs(renames) do
        local visited = { [loserKey] = true }
        while renames[survivorKey] and not visited[survivorKey] do
            visited[survivorKey] = true
            survivorKey = renames[survivorKey]
        end
        renames[loserKey] = survivorKey
    end
end

--- Display roster: mergeKey -> char row (mutates winner rows in-place for gold merge).
---@return table mergeKey -> charData
local function BuildMergedCharacterRosterView(charsTbl)
    local seen = {}
    if type(charsTbl) ~= "table" then return seen end
    local guidByNameRealm = BuildGuidByNameRealmIndex(charsTbl)
    local MS = ns.MigrationService
    local MergeRows = MS and MS.MergeCharacterRowPreserveWinner

    for key, data in pairs(charsTbl) do
        if type(data) == "table" then
            local mergeKey = ComputeCharacterMergeKey(data, key, guidByNameRealm)
            if mergeKey then
                if seen[mergeKey] then
                    local existingData = seen[mergeKey]
                    local existingTime = existingData.lastSeen or 0
                    local newTime = data.lastSeen or 0
                    if MergeRows then
                        if newTime >= existingTime then
                            MergeRows(data, existingData)
                            data._key = key
                            seen[mergeKey] = data
                        else
                            MergeRows(existingData, data)
                        end
                    elseif newTime > existingTime then
                        data._key = key
                        seen[mergeKey] = data
                    end
                else
                    data._key = key
                    seen[mergeKey] = data
                end
            end
        end
    end
    return seen
end

--- DB cleanup: find duplicate roster indices and produce rename/remove maps.
---@return table renames oldKey -> survivorKey
---@return table toRemove loser keys
---@return number duplicateCount
local function CollectCharacterDuplicateRenames(charsTbl)
    local renames = {}
    local toRemove = {}
    local duplicateCount = 0
    if type(charsTbl) ~= "table" then return renames, toRemove, duplicateCount end

    local guidByNameRealm = BuildGuidByNameRealmIndex(charsTbl)
    local seen = {} -- mergeKey -> survivor table key

    for charKey, charData in pairs(charsTbl) do
        if type(charData) == "table" then
            local mergeKey = ComputeCharacterMergeKey(charData, charKey, guidByNameRealm)
            if mergeKey then
                if seen[mergeKey] then
                    local existingKey = seen[mergeKey]
                    local existingData = charsTbl[existingKey]
                    local existingTime = existingData and existingData.lastSeen or 0
                    local newTime = charData.lastSeen or 0
                    duplicateCount = duplicateCount + 1
                    if newTime > existingTime then
                        renames[existingKey] = charKey
                        toRemove[existingKey] = true
                        seen[mergeKey] = charKey
                    else
                        renames[charKey] = existingKey
                        toRemove[charKey] = true
                    end
                else
                    seen[mergeKey] = charKey
                end
            end
        end
    end

    ResolveRenameChains(renames)
    return renames, toRemove, duplicateCount
end

--- Merge duplicate roster rows in DB, remap subsidiary keys, delete losers. Idempotent.
---@param db table AceDB root
---@param migrationService table|nil MigrationService for merge/remap APIs
---@return number duplicateCount
local function ApplyCharacterRosterDeduplication(db, migrationService)
    if not db or not db.global or type(db.global.characters) ~= "table" then
        return 0
    end
    local MS = migrationService or ns.MigrationService
    local renames, toRemove, duplicateCount = CollectCharacterDuplicateRenames(db.global.characters)
    if duplicateCount <= 0 or not next(toRemove) then
        return 0
    end

    if MS and MS.ApplyCharacterKeyedStorageRenames and next(renames) then
        MS:ApplyCharacterKeyedStorageRenames(db, renames)
    end

    local chars = db.global.characters
    for loserKey in pairs(toRemove) do
        local survivorKey = renames[loserKey]
        local loserData = chars[loserKey]
        local survivorData = survivorKey and chars[survivorKey]
        if survivorData and loserData and MS and MS.MergeCharacterRowPreserveWinner then
            MS:MergeCharacterRowPreserveWinner(survivorData, loserData)
        end
        chars[loserKey] = nil
    end

    InvalidateGetAllCharactersCache()
    return duplicateCount
end

--- After `characters` row moves from legacy Name-Realm index to guid-shaped key, remap subsidiary tables once.
local function RelocateLegacyCharacterSlot(db, newKey, legacyKey)
    if not db or not db.global or not db.global.characters then return end
    if not newKey or not legacyKey or newKey == legacyKey then return end
    local legacyRow = db.global.characters[legacyKey]
    if not legacyRow then return end
    local newRow = db.global.characters[newKey]
    if type(newRow) ~= "table" then
        db.global.characters[newKey] = legacyRow
        newRow = legacyRow
    elseif type(legacyRow) == "table" then
        local MS = ns.MigrationService
        if MS and MS.MergeCharacterRowPreserveWinner then
            MS:MergeCharacterRowPreserveWinner(newRow, legacyRow)
        end
    end
    local MS = ns.MigrationService
    if MS and MS.ApplyCharacterKeyedStorageRenames then
        MS:ApplyCharacterKeyedStorageRenames(db, { [legacyKey] = newKey })
    end
    db.global.characters[legacyKey] = nil
    InvalidateGetAllCharactersCache()
end

--- Convert bag/bank table (bagIndex -> slotID -> item) to array for ItemsCacheService (avoids full character save from scan path).
local function tableToItemArrayForStorage(tbl)
    if not tbl or type(tbl) ~= "table" then return nil end
    local arr = {}
    for bagIndex, bagData in pairs(tbl) do
        if type(bagData) == "table" then
            for slotID, item in pairs(bagData) do
                if type(item) == "table" and item.itemID then
                    arr[#arr + 1] = {
                        actualBagID = item.actualBagID or bagIndex,
                        bagID = item.actualBagID or bagIndex,
                        slotIndex = slotID,
                        slot = slotID,
                        itemID = item.itemID,
                        itemLink = item.itemLink,
                        stackCount = item.stackCount or 1,
                        quality = item.quality,
                        isBound = item.isBound or false,
                    }
                end
            end
        end
    end
    return #arr > 0 and arr or nil
end

ns.DataServiceRoster = {
    cache = _allCharsRosterCache,
    ComputeCharactersRosterSig = ComputeCharactersRosterSig,
    InvalidateGetAllCharactersCache = InvalidateGetAllCharactersCache,
    SafeGetMoneyCopperFromEntry = SafeGetMoneyCopperFromEntry,
    RelocateLegacyCharacterSlot = RelocateLegacyCharacterSlot,
    tableToItemArrayForStorage = tableToItemArrayForStorage,
    BuildGuidByNameRealmIndex = BuildGuidByNameRealmIndex,
    ComputeCharacterMergeKey = ComputeCharacterMergeKey,
    BuildMergedCharacterRosterView = BuildMergedCharacterRosterView,
    CollectCharacterDuplicateRenames = CollectCharacterDuplicateRenames,
    ResolveRenameChains = ResolveRenameChains,
    ApplyCharacterRosterDeduplication = ApplyCharacterRosterDeduplication,
}
