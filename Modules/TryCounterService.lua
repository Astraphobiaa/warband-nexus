--[[
    Warband Nexus - Try Counter Service
    Rarity-style try counter: manual set/get and optional LOOT_OPENED auto-increment.
    DB: db.global.tryCounts[type][id] = count
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true }

---Ensure DB structure exists
local function EnsureDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return false
    end
    if not WarbandNexus.db.global.tryCounts then
        WarbandNexus.db.global.tryCounts = {
            mount = {}, pet = {}, toy = {}, illusion = {},
        }
    end
    for t in pairs(VALID_TYPES) do
        if not WarbandNexus.db.global.tryCounts[t] then
            WarbandNexus.db.global.tryCounts[t] = {}
        end
    end
    return true
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number count
function WarbandNexus:GetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not EnsureDB() then return 0 end
    local count = WarbandNexus.db.global.tryCounts[collectibleType][id]
    return type(count) == "number" and count or 0
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@param count number
function WarbandNexus:SetTryCount(collectibleType, id, count)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not EnsureDB() then return end
    count = tonumber(count)
    if not count or count < 0 then count = 0 end
    WarbandNexus.db.global.tryCounts[collectibleType][id] = count
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number newCount
function WarbandNexus:IncrementTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not EnsureDB() then return 0 end
    local current = WarbandNexus:GetTryCount(collectibleType, id)
    local newCount = current + 1
    WarbandNexus.db.global.tryCounts[collectibleType][id] = newCount
    return newCount
end

---Initialize: ensure DB and register LOOT_OPENED (auto-increment when loot table mapping exists; currently empty)
function WarbandNexus:InitializeTryCounter()
    EnsureDB()
    if not self.RegisterEvent then return end
    self:RegisterEvent("LOOT_OPENED", "OnTryCounterLootOpened")
end

---LOOT_OPENED handler. Loot table mapping empty by design; future: match loot to collectible and increment.
function WarbandNexus:OnTryCounterLootOpened()
    ns.DebugPrint("|cff9370DB[TryCounter]|r [Loot Event] LOOT_OPENED triggered")
end

ns.TryCounterService = {
    GetTryCount = function(_, ct, id) return WarbandNexus:GetTryCount(ct, id) end,
    SetTryCount = function(_, ct, id, c) return WarbandNexus:SetTryCount(ct, id, c) end,
    IncrementTryCount = function(_, ct, id) return WarbandNexus:IncrementTryCount(ct, id) end,
}
