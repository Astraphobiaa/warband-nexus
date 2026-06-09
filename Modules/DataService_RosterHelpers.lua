--[[
    Warband Nexus - Character roster cache sig + safe money + storage row helpers.
    Split from DataService.lua (Lua 5.1 local limit).
    Loaded before Modules/DataService.lua.
]]

local _, ns = ...
local issecretvalue = issecretvalue

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

--- After `characters` row moves from legacy Name-Realm index to guid-shaped key, remap subsidiary tables once.
local function RelocateLegacyCharacterSlot(db, newKey, legacyKey)
    if not db or not db.global or not db.global.characters then return end
    if not newKey or not legacyKey or newKey == legacyKey then return end
    if not db.global.characters[legacyKey] then return end
    local MS = ns.MigrationService
    if MS and MS.ApplyCharacterKeyedStorageRenames then
        MS:ApplyCharacterKeyedStorageRenames(db, { [legacyKey] = newKey })
    end
    db.global.characters[legacyKey] = nil
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
}
