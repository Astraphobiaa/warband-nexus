--[[
    Warband Nexus - Gear Service
    Scans and persists equipped gear per character.
    Provides upgrade analysis and cross-character storage upgrade finder.

    Data stored in db.global.gearData[charKey]:
    {
        version  = "1.0.0",
        lastScan = timestamp,
        slots    = {
            [slotID] = {
                itemID    = number,
                itemLink  = string,   -- hyperlink with bonus IDs
                itemLevel = number,
                quality   = number,
                equipLoc  = string,   -- e.g. "INVTYPE_HEAD"
                name      = string,
            }
        }
    }

    Upgrade data is ilvl-based from persisted gear (no C_ItemUpgrade API); works offline.
    Storage upgrade findings are recomputed on each tab open.

    0-crest (gold-only) detection: C_ItemUpgrade cost APIs only return real costs when the
    Item Upgrade NPC window is open. We detect gold-only upgrades offline via persisted
    watermarks (per-slot max ilvl this character has ever had). Upgrades to ilvl <= watermark
    are treated as gold-only; no API cost query needed.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants

local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print("|cff00BFFF[GearService]|r", ...)
    end
end

local gearScanTimer = nil
local currencyGearScanTimer = nil

-- ============================================================================
-- SLOT DEFINITIONS
-- ============================================================================

-- Left column, right column, bottom row — mirrors Blizzard paper doll order.
local GEAR_SLOTS = {
    { id = 1,  key = "head",      label = "Head",      col = "left"   },
    { id = 2,  key = "neck",      label = "Neck",      col = "left"   },
    { id = 3,  key = "shoulder",  label = "Shoulder",  col = "left"   },
    { id = 15, key = "back",      label = "Back",      col = "left"   },
    { id = 5,  key = "chest",     label = "Chest",     col = "left"   },
    { id = 9,  key = "wrist",     label = "Wrist",     col = "left"   },
    { id = 10, key = "hands",     label = "Hands",     col = "right"  },
    { id = 6,  key = "waist",     label = "Waist",     col = "right"  },
    { id = 7,  key = "legs",      label = "Legs",      col = "right"  },
    { id = 8,  key = "feet",      label = "Feet",      col = "right"  },
    { id = 11, key = "ring1",     label = "Ring",      col = "right"  },
    { id = 12, key = "ring2",     label = "Ring",      col = "right"  },
    { id = 13, key = "trinket1",  label = "Trinket",   col = "bottom" },
    { id = 14, key = "trinket2",  label = "Trinket",   col = "bottom" },
    { id = 16, key = "mainhand",  label = "Main Hand", col = "bottom" },
    { id = 17, key = "offhand",   label = "Off Hand",  col = "bottom" },
}

local ITEM_CLASS_WEAPON = LE_ITEM_CLASS_WEAPON or 2
local ITEM_CLASS_ARMOR = LE_ITEM_CLASS_ARMOR or 4

-- Reverse map: slotID -> slot def (O(1) lookup)
local SLOT_BY_ID = {}
for i = 1, #GEAR_SLOTS do
    local s = GEAR_SLOTS[i]
    SLOT_BY_ID[s.id] = s
end

-- WoW uses shared "item redundancy" for rings and trinkets: one watermark per pair.
-- So Ring 1 and Ring 2 share the same high watermark; Trinket 1 and Trinket 2 share the same.
local SLOT_PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

--- Effective watermark for a slot: max of this slot and its pair (for rings/trinkets).
--- Used only for display/consistency; gold-only affordability uses per-slot watermark (this slot's max only).
---@param watermarks table [slotID] = ilvl
---@param slotID number
---@return number
local function GetEffectiveWatermark(watermarks, slotID)
    if not watermarks then return 0 end
    local a = watermarks[slotID] or 0
    local pair = SLOT_PAIRS[slotID]
    if not pair then return a end
    local b = watermarks[pair] or 0
    return (a > b) and a or b
end

-- Maps INVTYPE_ equip location -> which slot IDs that item can fill
-- C_Item.GetItemInfoInstant returns 4th value = itemEquipLoc (string, e.g. "INVTYPE_SHOULDER")
local EQUIP_LOC_TO_SLOTS = {
    INVTYPE_HEAD           = { 1  },
    INVTYPE_NECK           = { 2  },
    INVTYPE_SHOULDER       = { 3  },
    INVTYPE_BACK           = { 15 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_CHEST          = { 5  },
    INVTYPE_ROBE           = { 5  },
    INVTYPE_WRIST          = { 9  },
    INVTYPE_HAND           = { 10 },
    INVTYPE_WAIST          = { 6  },
    INVTYPE_LEGS           = { 7  },
    INVTYPE_FEET           = { 8  },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_WEAPON         = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_RANGED         = { 16 },
    INVTYPE_RANGEDRIGHT    = { 16 },
}

local ARMOR_SLOT_IDS = {
    [1] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true,
}

local SPEC_MAIN_STAT = {
    [62] = "INT", [63] = "INT", [64] = "INT",
    [65] = "INT", [66] = "STR", [70] = "STR",
    [71] = "STR", [72] = "STR", [73] = "STR",
    [102] = "INT", [103] = "AGI", [104] = "AGI", [105] = "INT",
    [1467] = "INT", [1468] = "INT", [1473] = "INT",
    [250] = "STR", [251] = "STR", [252] = "STR",
    [253] = "AGI", [254] = "AGI", [255] = "AGI",
    [256] = "INT", [257] = "INT", [258] = "INT",
    [259] = "AGI", [260] = "AGI", [261] = "AGI",
    [262] = "INT", [263] = "AGI", [264] = "INT",
    [265] = "INT", [266] = "INT", [267] = "INT",
    [268] = "AGI", [269] = "AGI", [270] = "INT",
    [577] = "AGI", [581] = "AGI",
}

local CLASS_FILE_TO_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
    DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

local CLASS_ARMOR_SUBCLASS = {
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

local function SetFromList(list)
    local out = {}
    for i = 1, #list do
        out[list[i]] = true
    end
    return out
end

local CLASS_WEAPON_SUBCLASS = {
    WARRIOR = SetFromList({ 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 }),
    PALADIN = SetFromList({ 0, 1, 4, 5, 6, 7, 8 }),
    DEATHKNIGHT = SetFromList({ 0, 1, 4, 5, 6, 7, 8 }),
    HUNTER = SetFromList({ 0, 1, 2, 3, 6, 7, 8, 10, 18 }),
    SHAMAN = SetFromList({ 0, 1, 4, 5, 10, 13, 15 }),
    EVOKER = SetFromList({ 0, 4, 7, 10, 13, 15 }),
    ROGUE = SetFromList({ 0, 4, 7, 13, 15 }),
    DRUID = SetFromList({ 4, 5, 6, 10, 13, 15 }),
    MONK = SetFromList({ 0, 4, 6, 7, 10, 13 }),
    DEMONHUNTER = SetFromList({ 0, 7, 9, 13 }),
    MAGE = SetFromList({ 7, 10, 15, 19 }),
    PRIEST = SetFromList({ 4, 10, 15, 19 }),
    WARLOCK = SetFromList({ 7, 10, 15, 19 }),
}

local function GetCharacterMainStat(charData)
    if not charData then return nil end
    local specID = tonumber(charData.specID)
    if specID then
        -- Legacy DB could contain spec index (1-4) instead of global specID.
        if specID > 0 and specID <= 4 and GetSpecializationInfoForClassID then
            local classFile = charData.classFile
            local classID = classFile and CLASS_FILE_TO_ID[classFile] or nil
            if classID then
                local resolvedSpecID = GetSpecializationInfoForClassID(classID, specID)
                if resolvedSpecID and SPEC_MAIN_STAT[resolvedSpecID] then
                    return SPEC_MAIN_STAT[resolvedSpecID]
                end
            end
        end
        if SPEC_MAIN_STAT[specID] then
            return SPEC_MAIN_STAT[specID]
        end
    end
    -- No spec in DB: infer from the class's first specialization (e.g. Mage → Arcane → INT).
    if charData.classFile and GetSpecializationInfoForClassID then
        local classID = CLASS_FILE_TO_ID[charData.classFile]
        if classID then
            local firstSpecID = GetSpecializationInfoForClassID(classID, 1)
            if firstSpecID and SPEC_MAIN_STAT[firstSpecID] then
                return SPEC_MAIN_STAT[firstSpecID]
            end
        end
    end
    return nil
end

--- Returns the main stat for a character from DB (for offline Character Stats panel).
---@param charData table Character entry from db.global.characters
---@return string|nil "STR" | "AGI" | "INT" or nil
function WarbandNexus:GetCharacterMainStat(charData)
    return GetCharacterMainStat(charData)
end

--- Returns the main stat for the current player from live spec (for UI: Character Stats panel, etc.).
---@return string|nil "STR" | "AGI" | "INT" or nil
function WarbandNexus:GetCurrentCharacterMainStat()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or not GetSpecializationInfo then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return (specID and SPEC_MAIN_STAT[specID]) or nil
end

--- Resolve item stat table (prefer C_Item API; fallback to legacy GetItemStats).
local function GetItemStatTableForLink(itemLink)
    if not itemLink then return nil end
    if C_Item and C_Item.GetItemStats then
        local ok, t = pcall(C_Item.GetItemStats, itemLink)
        if ok and t and next(t) then
            return t
        end
    end
    if GetItemStats then
        local statTable = {}
        local ok = pcall(GetItemStats, itemLink, statTable)
        if ok and statTable and next(statTable) then
            return statTable
        end
    end
    return nil
end

local function TableHasPrimaryStats(statTable)
    if not statTable then return false, false, false end
    local s = (statTable.ITEM_MOD_STRENGTH_SHORT or statTable.ITEM_MOD_STRENGTH or 0)
    local a = (statTable.ITEM_MOD_AGILITY_SHORT or statTable.ITEM_MOD_AGILITY or 0)
    local it = (statTable.ITEM_MOD_INTELLECT_SHORT or statTable.ITEM_MOD_INTELLECT or 0)
    local hasStr = s > 0
    local hasAgi = a > 0
    local hasInt = it > 0
    if not hasStr and not hasAgi and not hasInt then
        for k, v in pairs(statTable) do
            if type(v) == "number" and v > 0 and type(k) == "string" then
                if k:find("STRENGTH", 1, true) then hasStr = true end
                if k:find("AGILITY", 1, true) then hasAgi = true end
                if k:find("INTELLECT", 1, true) then hasInt = true end
            end
        end
    end
    return hasStr, hasAgi, hasInt
end

local function SlotExpectsPrimaryStatForFilter(slotID)
    if slotID == 13 or slotID == 14 then
        return false
    end
    if slotID == 2 or slotID == 11 or slotID == 12 then
        return false
    end
    if slotID == 15 then
        return false
    end
    if slotID == 16 or slotID == 17 then
        return true
    end
    return ARMOR_SLOT_IDS[slotID] == true
end

local function IsMainStatCompatible(itemLink, mainStat, slotID)
    if not itemLink then return true end
    local isTrinket = (slotID == 13 or slotID == 14)

    local statTable = GetItemStatTableForLink(itemLink)
    if not statTable then
        if mainStat and SlotExpectsPrimaryStatForFilter(slotID) and not isTrinket then
            return false
        end
        return true
    end

    local hasStr, hasAgi, hasInt = TableHasPrimaryStats(statTable)

    if not hasStr and not hasAgi and not hasInt then
        return true
    end

    if mainStat then
        if mainStat == "STR" then return hasStr end
        if mainStat == "AGI" then return hasAgi end
        if mainStat == "INT" then return hasInt end
    end

    if isTrinket then
        return false
    end

    return true
end

local function IsArmorCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc)
    if not ARMOR_SLOT_IDS[slotID] then
        return true
    end
    if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_BACK" then
        return true
    end
    if itemClassID and itemClassID ~= ITEM_CLASS_ARMOR then
        return false
    end
    local classFile = charData and charData.classFile
    local requiredSubclass = classFile and CLASS_ARMOR_SUBCLASS[classFile]
    if not requiredSubclass then
        return true
    end
    if not itemSubclassID then
        return true
    end
    return itemSubclassID == requiredSubclass
end

local function IsWeaponCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc, mainStat)
    if slotID ~= 16 and slotID ~= 17 then
        return true
    end
    if equipLoc == "INVTYPE_SHIELD" then
        local classFile = charData and charData.classFile
        return classFile == "WARRIOR" or classFile == "PALADIN" or classFile == "SHAMAN"
    end
    if equipLoc == "INVTYPE_HOLDABLE" then
        return mainStat == "INT"
    end
    if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
        local classFile = charData and charData.classFile
        return classFile == "HUNTER"
    end
    if itemClassID and itemClassID ~= ITEM_CLASS_WEAPON then
        return false
    end
    local classFile = charData and charData.classFile
    local allowedByClass = classFile and CLASS_WEAPON_SUBCLASS[classFile]
    if not allowedByClass then
        return true
    end
    if not itemSubclassID then
        return true
    end
    return allowedByClass[itemSubclassID] == true
end

--- Returns the TEMPLATE bind type of an item (what the item *is*), not whether it's currently bound.
--- BoE items show "boe" even if isBound=true in a character's bag (they were bound on pickup/equip).
--- Uses itemID for lookup since link-based GetItemInfo may not be cached for other characters.
local function GetBindingType(item)
    if not item then return nil end
    if not C_Item or not C_Item.GetItemInfo then return nil end

    -- Try link first (most accurate), then itemID
    local linkOrID = item.itemLink or item.link or item.itemID
    if not linkOrID then return nil end

    local ok, _, _, _, _, _, _, _, _, _, _, _, _, bindType = pcall(C_Item.GetItemInfo, linkOrID)

    -- If link failed, retry with itemID (template data is always available by ID)
    if (not ok or not bindType) and item.itemID and item.itemID ~= linkOrID then
        ok, _, _, _, _, _, _, _, _, _, _, _, _, bindType = pcall(C_Item.GetItemInfo, item.itemID)
    end

    if not ok or not bindType then return nil end

    if bindType == LE_ITEM_BIND_ON_EQUIP or bindType == LE_ITEM_BIND_ON_USE then
        return "boe"
    end
    if bindType == LE_ITEM_BIND_TO_BNETACCOUNT or bindType == LE_ITEM_BIND_TO_ACCOUNT then
        return "warbound"
    end
    return nil
end

local GEAR_DATA_VERSION = "1.1.0"

-- ============================================================================
-- UPGRADE ANALYSIS  (No API — ilvl-based inference from DB only, works offline)
-- ============================================================================

-- Midnight Season 1: complete ilvl progression per upgrade track (tier 1-6).
-- Each track has 6 tiers. Adjacent tracks overlap by 2 tiers.
-- Increment pattern per track: +4, +3, +3, +3, +4
local TRACK_ILVLS = {
    Adventurer = { 220, 224, 227, 230, 233, 237 },
    Veteran    = { 233, 237, 240, 243, 246, 250 },
    Champion   = { 246, 250, 253, 256, 259, 263 },
    Hero       = { 259, 263, 266, 269, 272, 276 },
    Myth       = { 272, 276, 279, 282, 285, 289 },
}
local TRACK_ORDER = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- Reverse map: ilvl → { trackName, tier, maxTier }.
-- Overlapping ilvls: higher tracks overwrite lower, so 233 → Veteran 1/6 (not Adventurer 5/6).
local ILVL_TO_UPGRADE = {}
for i = 1, #TRACK_ORDER do
    local trackName = TRACK_ORDER[i]
    local tiers = TRACK_ILVLS[trackName]
    for tier = 1, #tiers do
        ILVL_TO_UPGRADE[tiers[tier]] = { trackName, tier, #tiers }
    end
end

--- Infer upgrade track and level from item level only (no API). Returns nil if not in Midnight upgrade range.
--- NOTE: unreliable for overlapping ilvls (233, 237, 246, 250, 259, 263, 272, 276).
---@param itemLevel number
---@return string|nil trackName
---@return number|nil currUpgrade 1-6
---@return number|nil maxUpgrade 6
local function InferUpgradeFromIlvl(itemLevel)
    local ilvl = tonumber(itemLevel)
    if not ilvl or ilvl < 220 or ilvl > 289 then return nil, nil, nil end
    local entry = ILVL_TO_UPGRADE[ilvl]
    if entry then return entry[1], entry[2], entry[3] end
    local best, bestDiff = nil, 999
    for k, v in pairs(ILVL_TO_UPGRADE) do
        local d = math.abs(k - ilvl)
        if d < bestDiff then bestDiff = d; best = v end
    end
    if best then return best[1], best[2], best[3] end
    return nil, nil, nil
end

--- Get the ilvl for a given track and tier.
---@param trackName string
---@param tier number 1-6
---@return number|nil ilvl
local function GetIlvlForTier(trackName, tier)
    local tiers = TRACK_ILVLS[trackName]
    if not tiers or tier < 1 or tier > #tiers then return nil end
    return tiers[tier]
end

-- Flat cost per upgrade level: 20 Dawncrests + gold (Midnight Season 1)
ns.UPGRADE_CREST_PER_LEVEL = 20
ns.UPGRADE_GOLD_PER_LEVEL_COPPER = 10 * 10000

local TRACK_NAME_TO_CURRENCY_ID = {
    Adventurer = 3383,
    Veteran    = 3341,
    Champion   = 3343,
    Hero       = 3345,
    Myth       = 3347,
}

-- Crafted items: recraft with crests to reach higher ilvl tiers.
-- Crafted gear caps at 5/6 (285 for Myth, 272 for Hero) — NOT 6/6 like dropped gear.
-- Hero/Myth crafted ilvls are offset: Hero 259-272 (not 263-276), Myth 272-285 (not 276-289).
-- Recraft is a single operation: player picks target tier, pays that tier's crest cost.
-- Ordered highest → lowest so UI picks the best affordable tier first.
local CRAFTED_CREST_TIERS = {
    { crestID = 3347, name = "Myth",       maxIlvl = 285, cost = 80 },
    { crestID = 3345, name = "Hero",       maxIlvl = 272, cost = 60 },
    { crestID = 3343, name = "Champion",   maxIlvl = 263, cost = 60 },
    { crestID = 3341, name = "Veteran",    maxIlvl = 250, cost = 45 },
    { crestID = 3383, name = "Adventurer", maxIlvl = 237, cost = 30 },
}
ns.CRAFTED_CREST_TIERS = CRAFTED_CREST_TIERS

-- Export slot definitions and upgrade tables for use by GearUI
ns.GEAR_SLOTS              = GEAR_SLOTS
ns.SLOT_BY_ID              = SLOT_BY_ID
ns.EQUIP_LOC_TO_SLOTS      = EQUIP_LOC_TO_SLOTS
ns.TRACK_ILVLS             = TRACK_ILVLS
ns.TRACK_ORDER             = TRACK_ORDER
ns.TRACK_NAME_TO_CURRENCY_ID = TRACK_NAME_TO_CURRENCY_ID

-- ============================================================================
-- DB HELPERS
-- ============================================================================

local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    if not WarbandNexus.db.global.gearData then
        WarbandNexus.db.global.gearData = {}
    end
    return WarbandNexus.db.global.gearData
end

-- ============================================================================
-- ITEM LEVEL RESOLUTION
-- ============================================================================

--- Get the effective (bonus-ID-aware) item level from an item link.
--- Uses dual-API approach: compares GetDetailedItemLevelInfo (bonus-ID inflated)
--- vs GetItemInfo (may be base). Takes the lower when they disagree significantly
--- (e.g. Heart of Azeroth link returning 371 vs real ilvl 74).
---@param itemLink string Item hyperlink
---@return number ilvl (0 if unknown)
local function GetEffectiveIlvl(itemLink)
    if not itemLink then return 0 end
    local detailedIlvl = 0
    local infoIlvl = 0

    pcall(function()
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local val = C_Item.GetDetailedItemLevelInfo(itemLink)
            if val and val > 0 then detailedIlvl = val end
        end
    end)

    pcall(function()
        if C_Item and C_Item.GetItemInfo then
            local _, _, _, level = C_Item.GetItemInfo(itemLink)
            if level and level > 0 then infoIlvl = level end
        end
    end)

    if detailedIlvl > 0 and infoIlvl > 0 then
        if detailedIlvl > infoIlvl * 2 then
            return infoIlvl
        end
        return detailedIlvl
    end

    if detailedIlvl > 0 then return detailedIlvl end
    return infoIlvl
end

--- Get the equip location string for an item link ("INVTYPE_HEAD" etc.)
---@param itemLink string
---@return string equipLoc (empty string if unknown/non-equip)
local function GetEquipLoc(itemLink)
    if not itemLink then return "" end
    local loc = ""
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            -- GetItemInfoInstant: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID (4th = equipLoc)
            local _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
            loc = itemEquipLoc or ""
        end
    end)
    return loc
end

--- Get item quality tier integer for an item link.
---@param itemLink string
---@return number quality (0 = Poor, 2 = Uncommon, 3 = Rare, 4 = Epic, ...)
local function GetItemQuality(itemLink)
    if not itemLink then return 0 end
    local quality = 0
    pcall(function()
        if C_Item and C_Item.GetItemInfo then
            local _, _, q = C_Item.GetItemInfo(itemLink)
            if q then quality = q end
        end
    end)
    return quality
end

-- ============================================================================
-- TOOLTIP UPGRADE SCAN  (Fallback when C_ItemUpgrade API is unavailable/empty)
-- ============================================================================

--- Parse upgrade track info from the item tooltip of an equipped slot.
--- Reads "Upgrade Level: TrackName X/Y" line from C_TooltipInfo.GetInventoryItem.
--- Returns { trackName, currUpgrade, maxUpgrade } or nil if not found.
---@param slotID number Equipment slot ID (1-17)
---@return table|nil { trackName, currUpgrade, maxUpgrade }
local function ScanUpgradeFromTooltip(slotID)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
    if not ok or not data or not data.lines then return nil end

    local result = nil
    local isCrafted = false

    for i = 1, #data.lines do
        local line = data.lines[i]
        local text = line.leftText
        if text then
            if issecretvalue and issecretvalue(text) then
                -- skip secret lines
            else
                if not result then
                    local track, cur, max = text:match("Upgrade Level: (%a[%a ]*) (%d+)/(%d+)")
                    if track and cur and max then
                        track = track:match("^(.-)%s*$")
                        result = {
                            trackName   = track,
                            currUpgrade = tonumber(cur),
                            maxUpgrade  = tonumber(max),
                        }
                    end
                end
                if not isCrafted and text:find("Crafted") then
                    isCrafted = true
                end
            end
        end
    end

    if result then
        result.isCrafted = isCrafted or (result.trackName == "Crafted")
    end
    return result
end

-- ============================================================================
-- UPGRADE DATA PERSISTENCE  (Captures C_ItemUpgrade state during gear scan)
-- ============================================================================

--- Read C_ItemUpgrade data for a single equipped slot and write it into the
--- slot entry table so the info survives across sessions / characters.
---@param slotEntry table  The slot record being built (mutated in place)
---@param slotID number    Equipment slot ID (1-17)
local function ScanSlotUpgradeData(slotEntry, slotID)
    if not C_ItemUpgrade or not ItemLocation then return end

    pcall(function()
        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
        if not location or not location:IsValid() then return end

        local info = C_ItemUpgrade.GetItemUpgradeItemInfo
                     and C_ItemUpgrade.GetItemUpgradeItemInfo(location)
        if not info then return end

        local currUpgrade = info.currUpgrade or 0
        local maxUpgrade  = info.maxUpgrade or 0
        if currUpgrade == 0 and maxUpgrade == 0 then
            -- API returned data but no track info.
            if info.itemUpgradeable == false then
                -- Explicitly marked as not upgradeable by API
                slotEntry.notUpgradeable = true
                return
            end
            -- API simply hasn't populated the slot yet — try tooltip fallback
            local tooltipInfo = ScanUpgradeFromTooltip(slotID)
            if tooltipInfo then
                slotEntry.upgradeTrack = tooltipInfo.trackName
                slotEntry.currUpgrade  = tooltipInfo.currUpgrade
                slotEntry.maxUpgrade   = tooltipInfo.maxUpgrade
                if tooltipInfo.isCrafted then
                    slotEntry.isCrafted = true
                end
            end
            return
        end

        -- Track name: name (e.g. Veteran, Champion); fallback customUpgradeString (10.1.0+)
        local trackName = (info.name and info.name ~= "") and info.name or nil
        if not trackName and info.customUpgradeString and info.customUpgradeString ~= "" then
            trackName = info.customUpgradeString
        end
        slotEntry.upgradeTrack = trackName
        slotEntry.currUpgrade  = currUpgrade
        slotEntry.maxUpgrade   = maxUpgrade
        slotEntry.maxIlvl      = info.maxItemLevel or 0
        -- Mark crafted items: check track name AND tooltip for "Crafted" quality line.
        -- Midnight crafted items show "Myth 5/6" as track, not "Crafted", so tooltip scan is needed.
        if trackName == "Crafted" then
            slotEntry.isCrafted = true
        elseif not slotEntry.isCrafted then
            local tooltipInfo = ScanUpgradeFromTooltip(slotID)
            if tooltipInfo and tooltipInfo.isCrafted then
                slotEntry.isCrafted = true
            end
        end

        -- Persist next-level costs so UI can show "affordable" badge offline
        local hasNext = (currUpgrade < maxUpgrade)
        if hasNext then
            local levelInfos = info.upgradeLevelInfos or {}
            local nextInfo   = levelInfos[currUpgrade + 1]
            if nextInfo and nextInfo.currencyCostsToUpgrade then
                local costs = {}
                for i = 1, #nextInfo.currencyCostsToUpgrade do
                    local entry = nextInfo.currencyCostsToUpgrade[i]
                    if entry.currencyID and (entry.cost or entry.amount) then
                        costs[#costs + 1] = { currencyID = entry.currencyID, amount = entry.cost or entry.amount }
                    end
                end
                if #costs > 0 then
                    slotEntry.nextUpgradeCosts = costs
                end
            end
            if not slotEntry.nextUpgradeCosts and C_ItemUpgrade.GetItemUpgradeCost then -- legacy; not in current API list
                local rawCosts = C_ItemUpgrade.GetItemUpgradeCost(location, currUpgrade + 1) or {}
                local costs = {}
                for i = 1, #rawCosts do
                    local entry = rawCosts[i]
                    if entry.currencyID and (entry.amount or entry.cost) then
                        costs[#costs + 1] = {
                            currencyID = entry.currencyID,
                            amount     = entry.amount or entry.cost,
                        }
                    end
                end
                if #costs > 0 then
                    slotEntry.nextUpgradeCosts = costs
                end
            end
        end
    end)
end

-- ============================================================================
-- GEAR SCANNING  (Current character only — requires live API)
-- ============================================================================

--- Scan all equipped item slots for the current player and persist to DB.
--- Called from SaveCurrentCharacterData and on PLAYER_EQUIPMENT_CHANGED.
function WarbandNexus:ScanEquippedGear()
    local db = GetDB()
    if not db then return end

    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end

    local slots = {}
    local existingData = db[charKey]
    local watermarks = (existingData and existingData.watermarks) or {}

    for i = 1, #GEAR_SLOTS do
        local slotDef = GEAR_SLOTS[i]
        local slotID = slotDef.id
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            local itemID = nil
            pcall(function()
                if C_Item and C_Item.GetItemInfoInstant then
                    itemID = C_Item.GetItemInfoInstant(itemLink)
                end
            end)

            if itemID then
                local equipLoc  = GetEquipLoc(itemLink)
                local ilvl      = GetEffectiveIlvl(itemLink)
                local quality   = GetItemQuality(itemLink)
                local name      = nil
                pcall(function()
                    if C_Item and C_Item.GetItemInfo then
                        name = C_Item.GetItemInfo(itemLink)
                    end
                end)

                local slotEntry = {
                    itemID    = itemID,
                    itemLink  = itemLink,
                    itemLevel = ilvl,
                    quality   = quality,
                    equipLoc  = equipLoc,
                    name      = name,
                }

                -- Priority 1: Tooltip scan for exact track/tier (always available for equipped items)
                local tooltipInfo = ScanUpgradeFromTooltip(slotID)
                if tooltipInfo then
                    slotEntry.upgradeTrack = tooltipInfo.trackName
                    slotEntry.currUpgrade  = tooltipInfo.currUpgrade
                    slotEntry.maxUpgrade   = tooltipInfo.maxUpgrade
                    if tooltipInfo.isCrafted then
                        slotEntry.isCrafted = true
                    end
                end

                -- Priority 2: ilvl inference fallback
                if not slotEntry.upgradeTrack then
                    local trackName, curUp, maxUp = InferUpgradeFromIlvl(ilvl)
                    if trackName and curUp and maxUp then
                        slotEntry.upgradeTrack = trackName
                        slotEntry.currUpgrade  = curUp
                        slotEntry.maxUpgrade   = maxUp
                    elseif ilvl > 0 and (ilvl < 220 or ilvl > 289) then
                        slotEntry.notUpgradeable = true
                    end
                end

                -- Update watermark: highest ilvl ever seen in this slot for this character
                local prevWM = watermarks[slotID] or 0
                if ilvl > prevWM then
                    watermarks[slotID] = ilvl
                end

                -- Try to read API high watermark (character-only; account watermark would make
                -- other chars' progress count as "gold only" on this char, but crests are per-char)
                pcall(function()
                    if C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkSlotForItem then
                        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
                        if location and location:IsValid() then
                            local hwSlot = C_ItemUpgrade.GetHighWatermarkSlotForItem(location)
                            if hwSlot and C_ItemUpgrade.GetHighWatermarkForSlot then
                                local charHW = C_ItemUpgrade.GetHighWatermarkForSlot(hwSlot)
                                -- Use character watermark only (not account); affordability uses this char's crests
                                local apiWM = (type(charHW) == "number") and charHW or 0
                                -- Paired slots (rings/trinkets): API returns group max; do NOT write to this slot
                                -- or we'd mark Ring 1 as 237 from Ring 2 — gold-only must be per-slot (this item's max).
                                if not SLOT_PAIRS[slotID] and apiWM > (watermarks[slotID] or 0) then
                                    watermarks[slotID] = apiWM
                                end
                            end
                        end
                    end
                end)

                slots[slotID] = slotEntry
            end
        end
    end

    db[charKey] = {
        version    = GEAR_DATA_VERSION,
        lastScan   = time(),
        slots      = slots,
        watermarks = watermarks,
    }

    do
        local n = 0
        for _ in pairs(slots) do n = n + 1 end
        DebugPrint("Gear scan: " .. tostring(charKey) .. " — " .. tostring(n) .. " slots")
    end

    if Constants and Constants.EVENTS and Constants.EVENTS.GEAR_UPDATED then
        WarbandNexus:SendMessage(Constants.EVENTS.GEAR_UPDATED, { charKey = charKey })
    end
end

--- Register event listener for PLAYER_EQUIPMENT_CHANGED to keep gear data fresh.
function WarbandNexus:RegisterGearCacheEvents()
    -- PLAYER_EQUIPMENT_CHANGED is owned by EventManager.
    self._gearEventsRegistered = true
end

--- EventManager hook for PLAYER_EQUIPMENT_CHANGED.
--- Debounces rapid swaps and scans only gear slots (1-17).
---@param slotID number
function WarbandNexus:OnGearEquipmentChanged(slotID)
    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end
    if slotID and (slotID < 1 or slotID > 17) then return end
    if gearScanTimer then
        gearScanTimer:Cancel()
    end
    gearScanTimer = C_Timer.NewTimer(0.35, function()
        gearScanTimer = nil
        WarbandNexus:ScanEquippedGear()
    end)
end

--- Get stored equipped gear for a tracked character.
--- Caller must pass canonical key (Utilities:GetCanonicalCharacterKey / GetCharacterKey).
---@param charKey string Canonical character key ("Name-Realm", normalized)
---@return table|nil { version, lastScan, slots = { [slotID] = { itemID, itemLink, itemLevel, quality, equipLoc, name } } }
function WarbandNexus:GetEquippedGear(charKey)
    local db = GetDB()
    if not db or not charKey then return nil end
    return db[charKey]
end

-- ============================================================================
-- UPGRADE ANALYSIS  (No API — ilvl-based inference from DB only, works offline)
-- ============================================================================

--- Reconstruct upgrade info from persisted gear only. No API; works offline.
--- Uses slot.upgradeTrack/currUpgrade when present; else infers from slot.itemLevel.
--- Returns per-slot info with ilvl progression, currency IDs, costs, and watermark data.
---@param charKey string
---@return table upgrades { [slotID] = upgradeSlotInfo }
function WarbandNexus:GetPersistedUpgradeInfo(charKey)
    local upgrades = {}
    local gearData = self:GetEquippedGear(charKey)
    if not gearData or not gearData.slots then return upgrades end

    local watermarks = gearData.watermarks or {}

    for slotID, slot in pairs(gearData.slots) do
        local itemLevel = tonumber(slot.itemLevel) or 0
        local trackName = slot.upgradeTrack
        local currUpgrade = slot.currUpgrade
        local maxUpgrade = slot.maxUpgrade

        if not trackName or not currUpgrade or not maxUpgrade or maxUpgrade == 0 then
            trackName, currUpgrade, maxUpgrade = InferUpgradeFromIlvl(itemLevel)
        end

        -- Runtime crafted detection for old persisted data missing isCrafted flag.
        -- Scans the stored itemLink tooltip for "Crafted" quality text.
        if not slot.isCrafted and trackName ~= "Crafted" and slot.itemLink then
            local tipOk, tipData
            if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                tipOk, tipData = pcall(C_TooltipInfo.GetHyperlink, slot.itemLink)
            end
            if tipOk and tipData and tipData.lines then
                for li = 1, #tipData.lines do
                    local lt = tipData.lines[li] and tipData.lines[li].leftText
                    if lt and not (issecretvalue and issecretvalue(lt)) and lt:find("Crafted") then
                        slot.isCrafted = true
                        break
                    end
                end
            end
        end

        if slot.notUpgradeable then
            upgrades[slotID] = {
                canUpgrade = false, notUpgradeable = true,
                currentIlvl = itemLevel, nextIlvl = itemLevel, maxIlvl = 0,
                currUpgrade = 0, maxUpgrade = 0, trackName = "",
                currencyID = 0, crestCost = 0, moneyCost = 0,
                watermarkIlvl = watermarks[slotID] or 0,
            }
        elseif slot.isCrafted or trackName == "Crafted" then
            -- Crafted items: recraft with crests to reach higher ilvl.
            -- Crafted gear caps at 285 (Myth), not 289 like dropped gear.
            -- Determine current tier name from ilvl (table is highest → lowest; scan 1→N to match highest first).
            local craftedTierName = "Crafted"
            for ci = 1, #CRAFTED_CREST_TIERS do
                if itemLevel >= CRAFTED_CREST_TIERS[ci].maxIlvl then
                    craftedTierName = CRAFTED_CREST_TIERS[ci].name
                    break
                end
            end
            local canUpgrade = (itemLevel < CRAFTED_CREST_TIERS[1].maxIlvl)
            upgrades[slotID] = {
                canUpgrade      = canUpgrade,
                isCrafted       = true,
                currentIlvl     = itemLevel,
                nextIlvl        = itemLevel,
                maxIlvl         = 285,
                currUpgrade     = currUpgrade or 0,
                maxUpgrade      = maxUpgrade or 0,
                trackName       = "Crafted",
                craftedTierName = craftedTierName,
                currencyID      = 0,
                crestCost       = 0,
                moneyCost       = 0,
                watermarkIlvl   = watermarks[slotID] or 0,
            }
        elseif trackName and currUpgrade and maxUpgrade and maxUpgrade > 0 then
            local hasNext = (currUpgrade < maxUpgrade)
            local tiers = TRACK_ILVLS[trackName]

            local nextIlvl = itemLevel
            if hasNext and tiers and tiers[currUpgrade + 1] then
                nextIlvl = tiers[currUpgrade + 1]
            end

            local maxIlvl = itemLevel
            if tiers and tiers[maxUpgrade] then
                maxIlvl = tiers[maxUpgrade]
            end

            local currencyID = TRACK_NAME_TO_CURRENCY_ID[trackName] or 0
            local crestCost = hasNext and (ns.UPGRADE_CREST_PER_LEVEL or 20) or 0
            local moneyCost = hasNext and (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000) or 0

            -- Gold-only = upgrades to ilvl this slot has already reached. Use per-slot watermark only;
            -- for paired slots (rings/trinkets), cap by this item's current ilvl so we don't use the pair's max
            -- (e.g. Ring 1 at 3/6 only gets gold-only up to 227, not Ring 2's 237).
            local rawWm = watermarks[slotID] or 0
            local perSlotWm = SLOT_PAIRS[slotID] and (itemLevel < rawWm and itemLevel or rawWm) or rawWm
            upgrades[slotID] = {
                canUpgrade    = hasNext,
                currentIlvl   = itemLevel,
                nextIlvl      = nextIlvl,
                maxIlvl       = maxIlvl,
                currUpgrade   = currUpgrade,
                maxUpgrade    = maxUpgrade,
                trackName     = trackName,
                currencyID    = currencyID,
                crestCost     = crestCost,
                moneyCost     = moneyCost,
                watermarkIlvl = perSlotWm,
            }
        end
    end

    return upgrades
end

--- Same logic as GearUI: tier-by-tier affordable count and whether next step needs crests (20) or gold-only (0).
---@param upInfo table from GetPersistedUpgradeInfo
---@param currencyAmounts table map currencyID -> amount (0 = gold in gold units)
---@return number totalAffordable
---@return number effectiveCrestNeedForNextStep 0 if next step is gold-only or maxed, else 20
local function GetAffordableCountAndNextCrestNeed(upInfo, currencyAmounts)
    if not upInfo then return 0, 0 end
    if not upInfo.canUpgrade then
        return 0, 0  -- maxed or not upgradeable -> show crest need 0
    end
    local currTier = upInfo.currUpgrade or 0
    local maxTier = upInfo.maxUpgrade or 0
    if currTier >= maxTier then return 0, 0 end

    local tiers = TRACK_ILVLS and TRACK_ILVLS[upInfo.trackName]
    if not tiers or not tiers[currTier + 1] then return 0, (upInfo.crestCost or 20) end

    local wmIlvl = upInfo.watermarkIlvl or 0
    local nextIlvl = tiers[currTier + 1]
    local effectiveCrestNeed = (nextIlvl <= wmIlvl) and 0 or (upInfo.crestCost or 20)

    local goldPerUpgrade = upInfo.moneyCost or 100000
    local crestPerUpgrade = upInfo.crestCost or 20
    local cid = upInfo.currencyID or 0
    local haveGoldCopper = ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
    local haveCrests = (currencyAmounts and currencyAmounts[cid]) or 0

    local totalAffordable = 0
    for nextTier = currTier + 1, maxTier do
        local nIlvl = tiers[nextTier]
        if not nIlvl then break end
        local isGoldOnly = (nIlvl <= wmIlvl)
        if haveGoldCopper < goldPerUpgrade then break end
        if not isGoldOnly then
            if haveCrests < crestPerUpgrade then break end
            haveCrests = haveCrests - crestPerUpgrade
        end
        haveGoldCopper = haveGoldCopper - goldPerUpgrade
        totalAffordable = totalAffordable + 1
    end
    return totalAffordable, effectiveCrestNeed
end

--- Internal diagnostic: upgrade info per slot (current character). No slash — dev: /run WarbandNexus:GearUpgradeDebugReport()
--- Uses same currency source as Gear tab (FromDB, normalized). Crest need = 20 or 0 (gold-only/maxed).
function WarbandNexus:GearUpgradeDebugReport()
    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
    if not currentKey then
        self:Print("|cffff6600[WN GearUpgradeDebug]|r No current character.")
        return
    end
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(currentKey)) or {}
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(currentKey)) or {}
    local currencyAmounts = {}
    for i = 1, #currencies do
        local c = currencies[i]
        if c and c.currencyID ~= nil then
            currencyAmounts[c.currencyID] = (c.amount ~= nil) and c.amount or 0
        end
    end
    local function currencyName(cid)
        if cid == 0 then return "Gold" end
        return UPGRADE_CURRENCY_NAMES[cid] or ("Currency " .. tostring(cid))
    end
    self:Print("|cff00ccff[WN GearUpgradeDebug]|r Current char: " .. tostring(currentKey))
    self:Print("|cff888888Your currency:|r")
    for id, amt in pairs(currencyAmounts) do
        local nameStr = currencyName(id)
        if type(nameStr) == "table" then nameStr = (nameStr.name or tostring(id)) end
        self:Print("  " .. tostring(id) .. " " .. tostring(nameStr) .. " = " .. tostring(amt))
    end
    self:Print("|cff888888Slots: crest=have/need (need 20 or 0=gold-only/max), afford:|r")
    for i = 1, #GEAR_SLOTS do
        local slotDef = GEAR_SLOTS[i]
        local slotID = slotDef.id
        local up = upgradeInfo[slotID]
        if up then
            local label = slotDef.label or ("Slot " .. tostring(slotID))
            local tier = string.format("%d/%d", up.currUpgrade or 0, up.maxUpgrade or 0)
            local cid = up.currencyID or 0
            local crestHave = currencyAmounts[cid] or 0
            local totalAffordable, effectiveCrestNeed = GetAffordableCountAndNextCrestNeed(up, currencyAmounts)
            local goldHave = (currencyAmounts[0] or 0) * 10000
            local goldNeed = up.moneyCost or 0
            local wmIlvl = up.watermarkIlvl or 0
            local canAfford = (totalAffordable > 0)
            self:Print(string.format("  |cff%s%s|r %s %s ilvl=%d wm=%d | crest=%d/%d gold=%d/%d | afford=%s",
                (canAfford and "00ff00") or (up.canUpgrade and "ffaa00") or "888888",
                label, tier, up.trackName or "", up.currentIlvl or 0, wmIlvl,
                crestHave, effectiveCrestNeed, math.floor(goldHave/10000), math.floor(goldNeed/10000),
                tostring(canAfford)))
        end
    end
end

--- Internal diagnostic: storage-upgrade summary for all tracked characters. No slash — dev: /run WarbandNexus:GearStorageUpgradeDebugReportAll()
function WarbandNexus:GearStorageUpgradeDebugReportAll()
    local chars = self.db and self.db.global and self.db.global.characters
    if not chars then
        self:Print("|cffff6600[WN GearStorageDebug]|r No character database.")
        return
    end

    local tracked = {}
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey)
        and function(k) return ns.Utilities:GetCanonicalCharacterKey(k) end
        or function(k) return k end
    for key, data in pairs(chars) do
        if data and data.isTracked then
            tracked[#tracked + 1] = { key = key, data = data, canonical = getCanonicalKey(key) or key }
        end
    end
    if #tracked == 0 then
        self:Print("|cffff6600[WN GearStorageDebug]|r No tracked characters.")
        return
    end

    table.sort(tracked, function(a, b)
        return (a.data.lastSeen or 0) > (b.data.lastSeen or 0)
    end)

    self:Print("|cff00ccff[WN GearStorageDebug]|r Scanning storage upgrades for |cffffff00" .. tostring(#tracked) .. "|r tracked character(s)")
    for i = 1, #tracked do
        local entry = tracked[i]
        local charName = (entry.data and entry.data.name) or entry.key
        local findings = (self.FindGearStorageUpgrades and self:FindGearStorageUpgrades(entry.canonical)) or {}
        local equippedMap = BuildEquippedIlvlMap(entry.canonical)

        local totalSlotsWithUpgrade = 0
        for _ in pairs(findings) do totalSlotsWithUpgrade = totalSlotsWithUpgrade + 1 end
        self:Print(string.format("|cff88ccff- %s|r (%s): |cff00ff00%d slot(s)|r with upgrade candidates",
            tostring(charName), tostring(entry.canonical), totalSlotsWithUpgrade))

        if totalSlotsWithUpgrade > 0 then
            for ii = 1, #GEAR_SLOTS do
                local slotDef = GEAR_SLOTS[ii]
                local slotID = slotDef.id
                local cands = findings[slotID]
                local best = cands and cands[1]
                if best then
                    local current = equippedMap[slotID] or 0
                    self:Print(string.format("   %s: %d -> %d (%s)", tostring(slotDef.label), current, best.itemLevel or 0, tostring(best.source or "?")))
                end
            end
        end
    end
end

-- ============================================================================
-- STORAGE UPGRADE FINDER  (Cross-character — reads persisted item data)
-- ============================================================================

--- Build a map: slotID -> currently equipped ilvl for the given character.
---@param charKey string
---@return table { [slotID] = ilvl }
local function BuildEquippedIlvlMap(charKey)
    local gearData = WarbandNexus:GetEquippedGear(charKey)
    if not gearData or not gearData.slots then return {} end
    local map = {}
    for slotID, slotData in pairs(gearData.slots) do
        map[slotID] = slotData.itemLevel or 0
    end
    return map
end

--- Try to resolve the effective ilvl of an item from bag storage.
--- Prefers link-based ilvl so the UI row matches the tooltip (same item link).
---@param item table Hydrated item from ItemsCacheService
---@return number ilvl (0 if unknown)
local function ResolveStorageItemIlvl(item)
    if not item or not item.itemID then return 0 end

    local link = item.itemLink or item.link
    if not link then
        -- Strict mode for recommendation accuracy: if no link, we cannot guarantee tooltip-matching ilvl.
        return 0
    end
    -- Prefer link-based ilvl first so storage row matches tooltip (avoids cache vs link mismatch)
    local ilvl = GetEffectiveIlvl(link)
    if ilvl > 0 then return ilvl end
    local ok, _, _, level = pcall(C_Item.GetItemInfo, link)
    if ok and level and type(level) == "number" and level > 0 then
        return level
    end

    -- Link present but ilvl unknown (cache miss). Skip instead of using stale/cache-only numbers.
    return 0
end

--- Determine the binding/availability label for a storage item.
---@param item table Hydrated item
---@param sourceCharKey string The character that owns this item
---@param selectedCharKey string The character we're gearing
---@return string label  e.g. "Warband Bank", "Shaman Foo (Bag)", "Your Bag"
---@return string type   "warband" | "self_bag" | "self_bank" | "char_bag" | "char_bank" | "boe"
local function ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
    local allCharsDB = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    local charData = allCharsDB and allCharsDB[sourceCharKey]
    local charName = (charData and charData.name) or sourceCharKey

    if storageType == "warband" then
        return "Warband Bank", "warbound"
    end

    local function canonical(k)
        if not k or k == "" then return "" end
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(k) or k
        end
        return (k:gsub("%s+", ""))
    end
    local sourceNorm = canonical(sourceCharKey)
    local selectedNorm = canonical(selectedCharKey)
    local isSameChar = (sourceNorm ~= "" and selectedNorm ~= "" and sourceNorm == selectedNorm)

    local bindType = GetBindingType(item)
    -- bindType: "boe" (BoE/BoU), "warbound" (Warbound/Account), nil (soulbound or API not cached)
    -- Rule: only show BoE and Warbound items. Reject confirmed soulbound.
    -- If bindType is nil (API cache miss), check isBound field:
    --   isBound=false → item isn't bound yet, likely BoE/Warbound → show it
    --   isBound=true + bindType=nil → likely soulbound (BoP) → reject
    local isSoulbound = (bindType == nil and item.isBound == true)
    if isSoulbound then
        return nil, nil
    end

    local effectiveType = bindType or "boe"

    if isSameChar then
        if storageType == "bank" then return "Your Bank", "self_bank" end
        return "Your Bag", "self_bag"
    end

    local suffix = (storageType == "bank") and " (Bank)" or " (Bag)"
    return charName .. suffix, effectiveType
end

--- Find items in storage (all chars' bags/bank + warband bank) that would
--- upgrade any equipped slot for the selected character.
---@param selectedCharKey string
---@return table findings { [slotID] = { {itemID, itemLink, itemLevel, quality, source, sourceType, isBound}, ... } }
function WarbandNexus:FindGearStorageUpgrades(selectedCharKey)
    local findings = {}
    if not selectedCharKey then return findings end

    local isDebug = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode
    local function dbg(msg)
        if isDebug then _G.print("|cff00BFFF[StorageUpgrade]|r " .. msg) end
    end

    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)
    local allChars = self.db and self.db.global and self.db.global.characters
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k) return ns.Utilities:GetCanonicalCharacterKey(k) end or function(k) return k end
    local charData = allChars and allChars[selectedCharKey]
    if not charData and allChars then
        for k, data in pairs(allChars) do
            if (getCanonicalKey(k) or k) == selectedCharKey then
                charData = data
                break
            end
        end
    end

    -- Main stat: always prefer live spec for current player
    local mainStat = nil
    local mainStatSource = "none"
    do
        local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey) and ns.Utilities:GetCharacterKey() or nil
        local selCanon = getCanonicalKey(selectedCharKey) or selectedCharKey
        local curCanon = (currentKey and getCanonicalKey(currentKey)) or currentKey
        local isCurrentPlayer = (selCanon and curCanon and selCanon == curCanon)

        if isCurrentPlayer and GetSpecialization and GetSpecializationInfo then
            local specIndex = GetSpecialization()
            if specIndex then
                local specID = GetSpecializationInfo(specIndex)
                if specID and SPEC_MAIN_STAT[specID] then
                    mainStat = SPEC_MAIN_STAT[specID]
                    mainStatSource = "live(specID=" .. tostring(specID) .. ")"
                end
            end
        end

        if not mainStat then
            mainStat = GetCharacterMainStat(charData)
            if mainStat then
                mainStatSource = "db(specID=" .. tostring(charData and charData.specID) .. ")"
            end
        end
    end

    dbg("=== Scan for: " .. tostring(selectedCharKey) .. " ===")
    dbg("  classFile=" .. tostring(charData and charData.classFile) .. " specID(db)=" .. tostring(charData and charData.specID) .. " mainStat=" .. tostring(mainStat) .. " (" .. mainStatSource .. ")")

    local addedCount = 0

    local function AddCandidate(slotID, candidate)
        if not findings[slotID] then findings[slotID] = {} end
        local link = candidate.itemLink or candidate.link
        if link then
            candidate.itemLevel = ResolveStorageItemIlvl({ itemID = candidate.itemID, itemLink = link, link = link })
            -- C_Item.GetItemInfo returns: name, link, quality, itemLevel, reqLevel, ...
            -- With pcall: ok, name, link, quality, itemLevel, reqLevel
            local rok, _, _, _, _, reqLevel = pcall(C_Item.GetItemInfo, link)
            if rok and reqLevel and type(reqLevel) == "number" and reqLevel > 0 then
                candidate.requiredLevel = reqLevel
            end
        end
        if (candidate.itemLevel or 0) == 0 then return end
        for i = 1, #findings[slotID] do
            local ex = findings[slotID][i]
            if ex.itemLink == candidate.itemLink and ex.source == candidate.source then return end
        end
        findings[slotID][#findings[slotID] + 1] = candidate
        addedCount = addedCount + 1

        local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
        local slotLabel = (slotDef and slotDef.label) or tostring(slotID)
        local itemName = link and link:match("%[(.-)%]") or tostring(candidate.itemID)
        dbg("  +++ " .. slotLabel .. ": " .. itemName .. " ilvl=" .. tostring(candidate.itemLevel) .. " from=" .. tostring(candidate.source))
    end

    local function EvaluateItem(item, sourceCharKey, storageType)
        if not item or not item.itemID then return end

        local equipLoc = ""
        local itemClassID = item.classID
        local itemSubclassID = item.subclassID
        pcall(function()
            local _, _, _, loc, _, classID, subclassID = C_Item.GetItemInfoInstant(item.itemID)
            equipLoc = loc or ""
            if not itemClassID then itemClassID = classID end
            if not itemSubclassID then itemSubclassID = subclassID end
        end)
        if (equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP") and (item.itemLink or item.link) then
            equipLoc = GetEquipLoc(item.itemLink or item.link)
        end
        if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then return end

        local targetSlots = EQUIP_LOC_TO_SLOTS[equipLoc]
        if not targetSlots then return end

        local ilvl = ResolveStorageItemIlvl(item)
        if ilvl == 0 then return end

        -- Only Uncommon (2) and above; hide Poor (0) and Common (1)
        local quality = item.quality
        if quality == nil or quality == 0 then
            local q = (item.itemLink or item.link) and GetItemQuality(item.itemLink or item.link) or nil
            quality = (q ~= nil) and q or 0
        end
        if (quality or 0) < 2 then return end

        local link = item.itemLink or item.link
        local itemName = link and link:match("%[(.-)%]") or tostring(item.itemID)

        for i = 1, #targetSlots do
            local slotID = targetSlots[i]
            local isArmorOK = IsArmorCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc)
            local isWeaponOK = IsWeaponCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc, mainStat)
            local isStatOK = IsMainStatCompatible(link, mainStat, slotID)

            if not isArmorOK or not isWeaponOK then
                -- skip silently
            elseif not isStatOK then
                dbg("  --- REJECTED(stat): " .. itemName .. " slot=" .. tostring(slotID) .. " mainStat=" .. tostring(mainStat))
            else
                local currentIlvl = equippedMap[slotID] or 0
                if ilvl > currentIlvl then
                    local source, sourceType = ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
                    if source then
                        AddCandidate(slotID, {
                            itemID     = item.itemID,
                            itemLink   = link,
                            itemLevel  = ilvl,
                            quality    = item.quality or 0,
                            source     = source,
                            sourceType = sourceType,
                            isBound    = item.isBound,
                            equipLoc   = equipLoc,
                        })
                    else
                        local bt = GetBindingType(item)
                        dbg("  --- REJECTED(bind): " .. itemName .. " ilvl=" .. tostring(ilvl) .. " bindType=" .. tostring(bt) .. " isBound=" .. tostring(item.isBound) .. " src=" .. tostring(sourceCharKey) .. "/" .. tostring(storageType))
                    end
                end
            end
        end
    end

    -- ── Warband Bank ──────────────────────────────────────────────────────────
    local wbData = (WarbandNexus.GetWarbandBankData and WarbandNexus:GetWarbandBankData()) or nil
    if wbData and wbData.items then
        for i = 1, #wbData.items do
            local item = wbData.items[i]
            EvaluateItem(item, nil, "warband")
        end
    end

    -- ── All Characters (bags + bank) ─────────────────────────────────────────
    -- Resolve items using every key variant so we don't miss (itemStorage may be keyed differently than allChars).
    if allChars then
        local itemStorage = self.db and self.db.global and self.db.global.itemStorage or nil
        for charKey, _ in pairs(allChars) do
            local canonicalChar = getCanonicalKey(charKey) or charKey
            local function getItemsForChar()
                local data = (WarbandNexus.GetItemsData and WarbandNexus:GetItemsData(canonicalChar)) or nil
                if data and ((data.bags and #data.bags > 0) or (data.bank and #data.bank > 0)) then
                    return data
                end
                if charKey ~= canonicalChar then
                    data = (WarbandNexus.GetItemsData and WarbandNexus:GetItemsData(charKey)) or nil
                    if data and ((data.bags and #data.bags > 0) or (data.bank and #data.bank > 0)) then
                        return data
                    end
                end
                if itemStorage then
                    for storageKey, _ in pairs(itemStorage) do
                        if storageKey ~= "warbandBank" and (getCanonicalKey(storageKey) or storageKey) == canonicalChar then
                            data = (WarbandNexus.GetItemsData and WarbandNexus:GetItemsData(storageKey)) or nil
                            if data and ((data.bags and #data.bags > 0) or (data.bank and #data.bank > 0)) then
                                return data
                            end
                        end
                    end
                end
                return nil
            end
            local itemsData = getItemsForChar()
            if itemsData then
                local bags = itemsData.bags or {}
                for i = 1, #bags do
                    local item = bags[i]
                    EvaluateItem(item, charKey, "bag")
                end
                local bank = itemsData.bank or {}
                for i = 1, #bank do
                    local item = bank[i]
                    EvaluateItem(item, charKey, "bank")
                end
            end
        end
    end

    -- ── Other characters' EQUIPPED gear (BoE/Warbound only — transferable) ─────
    -- So we show e.g. "Superluminal (equipped): 220 head" when viewing Astralumina.
    local selectedNorm = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(selectedCharKey) or selectedCharKey
    if allChars and selectedNorm and (WarbandNexus.GetEquippedGear) then
        for otherCharKey, otherCharData in pairs(allChars) do
            if not otherCharData.isTracked then
                -- skip
            elseif (getCanonicalKey(otherCharKey) or otherCharKey) == selectedNorm then
                -- skip selected character
            else
            local otherNorm = getCanonicalKey(otherCharKey) or otherCharKey
            local otherGear = WarbandNexus:GetEquippedGear(otherNorm) or WarbandNexus:GetEquippedGear(otherCharKey)
            if otherGear and otherGear.slots then
            local otherName = (otherCharData and otherCharData.name) or otherCharKey
            for slotID, slotData in pairs(otherGear.slots) do
                if slotData and slotData.itemID and (slotData.itemLink or slotData.itemLevel) then
                    local currentIlvl = equippedMap[slotID] or 0
                    local itemLevel = ResolveStorageItemIlvl(slotData)
                    if itemLevel > currentIlvl then
                        local slotQuality = slotData.quality
                        if slotQuality == nil and slotData.itemLink then
                            slotQuality = GetItemQuality(slotData.itemLink)
                        end
                        if (slotQuality or 0) < 2 then
                            -- skip Poor/Common
                        else
                        local fakeItem = {
                            itemID = slotData.itemID,
                            itemLink = slotData.itemLink,
                            link = slotData.itemLink,
                            quality = slotData.quality or 0,
                            equipLoc = slotData.equipLoc or "",
                            classID = slotData.classID,
                            subclassID = slotData.subclassID,
                            isBound = true,
                        }
                        local equipLoc = slotData.equipLoc or ""
                        if equipLoc == "" and slotData.itemLink then
                            equipLoc = GetEquipLoc(slotData.itemLink)
                        end
                        if equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
                            local targetSlots = EQUIP_LOC_TO_SLOTS[equipLoc]
                            if targetSlots then
                                local bindType = GetBindingType(fakeItem)
                                if bindType == "boe" or bindType == "warbound" then
                                    local itemClassID = slotData.classID
                                    local itemSubclassID = slotData.subclassID
                                    if not itemClassID or not itemSubclassID then
                                        pcall(function()
                                            local _, _, _, _, _, cid, sid = C_Item.GetItemInfoInstant(slotData.itemID)
                                            if not itemClassID then itemClassID = cid end
                                            if not itemSubclassID then itemSubclassID = sid end
                                        end)
                                    end
                                    local ok = true
                                    for i = 1, #targetSlots do
                                        local sid = targetSlots[i]
                                        if not IsArmorCompatible(charData, sid, itemClassID, itemSubclassID, equipLoc) then ok = false break end
                                        if not IsWeaponCompatible(charData, sid, itemClassID, itemSubclassID, equipLoc, mainStat) then ok = false break end
                                        if not IsMainStatCompatible(slotData.itemLink, mainStat, sid) then ok = false break end
                                    end
                                    if ok then
                                        AddCandidate(slotID, {
                                            itemID     = slotData.itemID,
                                            itemLink   = slotData.itemLink,
                                            itemLevel  = itemLevel,
                                            quality    = slotData.quality or 0,
                                            source     = otherName .. " (equipped)",
                                            sourceType = bindType,
                                            isBound    = true,
                                            equipLoc   = equipLoc,
                                            requiredLevel = (function()
                                                if not slotData.itemLink then return nil end
                                                local ok2, _, _, _, _, reqLvl = pcall(C_Item.GetItemInfo, slotData.itemLink)
                                                return (ok2 and reqLvl and type(reqLvl) == "number" and reqLvl > 0) and reqLvl or nil
                                            end)(),
                                        })
                                    end
                                end
                            end
                        end
                        end
                    end
                end
            end
            end
            end
        end
    end

    dbg("  Total candidates added: " .. tostring(addedCount))

    for slotID, candidates in pairs(findings) do
        table.sort(candidates, function(a, b) return (a.itemLevel or 0) > (b.itemLevel or 0) end)
        while #candidates > 5 do table.remove(candidates) end
    end

    return findings
end

-- ============================================================================
-- CURRENCY SNAPSHOT  (Resources available for upgrading)
-- ============================================================================

-- Currency IDs for item upgrades (Midnight 12.0.1 — Dawncrests only; Valorstone removed)
-- Must match IDs used in PvEUI / CurrencyCacheService. Order: Adventurer → Myth.
local UPGRADE_CURRENCY_IDS = {
    3383,  -- Adventurer Dawncrest (Wowhead: currency=3383)
    3341,  -- Veteran Dawncrest    (Wowhead: currency=3341)
    3343,  -- Champion Dawncrest
    3345,  -- Hero Dawncrest
    3347,  -- Myth Dawncrest
}

-- Fallback names for Dawncrests (when API not ready)
local UPGRADE_CURRENCY_NAMES = {
    [3383] = "Adventurer Dawncrest",
    [3341] = "Veteran Dawncrest",
    [3343] = "Champion Dawncrest",
    [3345] = "Hero Dawncrest",
    [3347] = "Myth Dawncrest",
}

local UPGRADE_CURRENCY_ID_SET = {}
for i = 1, #UPGRADE_CURRENCY_IDS do
    UPGRADE_CURRENCY_ID_SET[UPGRADE_CURRENCY_IDS[i]] = true
end

--- Match CurrencyCacheService: weekly display cap + season max from API (Dawncrest IDs + Coffer Key Shards by name).
local function IsGearSeasonSplitCurrency(currencyID, info)
    if UPGRADE_CURRENCY_ID_SET[currencyID] then return true end
    if not info or not info.name then return false end
    local nm = info.name
    if issecretvalue and issecretvalue(nm) then return false end
    local n = string.lower(tostring(nm))
    return n:find("coffer", 1, true) ~= nil and n:find("shard", 1, true) ~= nil
end

--- Effective maxQuantity for Gear panel fallback (weekly cap when season-split, else API caps).
local function DisplayMaxQuantityFromCurrencyInfo(currencyID, info)
    if not info then return nil end
    local maxQ = info.maxQuantity or 0
    local maxWeekly = info.maxWeeklyQuantity or 0
    if IsGearSeasonSplitCurrency(currencyID, info) and maxWeekly > 0 then
        return maxWeekly
    end
    if maxQ > 0 then return maxQ end
    if maxWeekly > 0 then return maxWeekly end
    return nil
end

--- Dawncrests + Coffer Key Shards (name-resolved ID) + gold for Gear tab.
--- Current char: live C_CurrencyInfo API (same source as Currency tab scan).
--- Offline char: DB fallback via GetCurrenciesForUI.
---@param charKey string Character key from UI (dropdown).
---@return table list { { currencyID, amount, name, icon }, ... }, gold last
function WarbandNexus:GetGearUpgradeCurrenciesFromDB(charKey)
    local result = {}
    if not charKey then return result end

    local canonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(charKey)) or charKey
    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
    local function norm(k) return (k and k:gsub("%s+", "")) or "" end
    local isCurrentChar = (norm(canonicalKey) == norm(currentKey) or norm(charKey) == norm(currentKey))

    local upgradeIds = {}
    for i = 1, #UPGRADE_CURRENCY_IDS do
        upgradeIds[#upgradeIds + 1] = UPGRADE_CURRENCY_IDS[i]
    end
    do
        local allCur = self.GetCurrenciesForUI and self:GetCurrenciesForUI() or {}
        for cid, entry in pairs(allCur) do
            local lowerName = entry and entry.name and string.lower(tostring(entry.name)) or ""
            if lowerName ~= "" and lowerName:find("coffer", 1, true) and lowerName:find("shard", 1, true) then
                upgradeIds[#upgradeIds + 1] = cid
                break
            end
        end
    end

    for i = 1, #upgradeIds do
        local currencyID = upgradeIds[i]
        local amount = 0
        local cName = UPGRADE_CURRENCY_NAMES[currencyID]
        local cIcon = nil
        local maxQuantity = nil  -- Weekly/total cap from API; nil = use fallback in UI

        if isCurrentChar then
            -- Prefer GetCurrencyData: same normalization as Currency tab (Dawncrests + Coffer Key Shards).
            local cd = self.GetCurrencyData and self:GetCurrencyData(currencyID, canonicalKey)
            if cd and cd.quantity ~= nil then
                amount = cd.quantity
                if cd.name and cd.name ~= "" then cName = cd.name end
                if cd.icon or cd.iconFileID then cIcon = cd.icon or cd.iconFileID end
                maxQuantity = cd.maxQuantity
            elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                if ok and info then
                    if info.name and info.name ~= "" then cName = info.name end
                    if info.iconFileID then cIcon = info.iconFileID end
                    amount = info.quantity or 0
                    maxQuantity = DisplayMaxQuantityFromCurrencyInfo(currencyID, info)
                end
            end
        else
            -- OFFLINE: read from DB via GetCurrenciesForUI (aggregated per-char data)
            local currencyData = self.GetCurrenciesForUI and self:GetCurrenciesForUI() or {}
            local L = currencyData[currencyID]
            if L then
                if L.name and L.name ~= "" then cName = L.name end
                if L.icon or L.iconFileID then cIcon = L.icon or L.iconFileID end
                if L.chars then
                    amount = L.chars[canonicalKey] or L.chars[charKey] or 0
                    if type(amount) == "table" then amount = amount.quantity or 0 end
                    -- Fallback: key format may differ (e.g. "Name - Realm" vs "Name-Realm"); match by normalized key
                    if (amount == nil or amount == 0) and next(L.chars) then
                        local nCanon = norm(canonicalKey)
                        local nChar = norm(charKey)
                        for k, v in pairs(L.chars) do
                            if k and (norm(k) == nCanon or norm(k) == nChar) then
                                local q = type(v) == "table" and (v.quantity or v.amount) or v
                                if type(q) == "number" and q > 0 then amount = q break end
                            end
                        end
                    end
                    amount = tonumber(amount) or 0
                end
            end
        end

        -- Cap from API (max is global per currency type, works for both current and offline char)
        if not maxQuantity and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if ok and info then
                maxQuantity = DisplayMaxQuantityFromCurrencyInfo(currencyID, info)
            end
        end

        result[#result + 1] = {
            currencyID = currencyID,
            amount     = tonumber(amount) or 0,
            name       = cName,
            icon       = cIcon,
            maxQuantity = maxQuantity,
        }
    end

    local db = self.db and self.db.global
    local gold = 0
    if db and db.characters then
        local charEntry = db.characters[canonicalKey] or db.characters[charKey]
        if charEntry and (charEntry.gold or charEntry.silver or charEntry.copper) then
            gold = (charEntry.gold or 0) * 10000 + (charEntry.silver or 0) * 100 + (charEntry.copper or 0)
        end
    end
    if isCurrentChar and GetMoney then gold = GetMoney() or 0 end
    result[#result + 1] = {
        currencyID = 0,
        amount     = math.floor(gold / 10000),
        name       = "Gold",
        icon       = 133784,
        isGold     = true,
        silver     = math.floor((gold % 10000) / 100),
        copper     = gold % 100,
    }
    return result
end

--- Get the player's current quantities of upgrade-relevant currencies.
--- DB only: same as GetGearUpgradeCurrenciesFromDB (CurrencyCacheService + characters gold). No API calls.
---@param charKey string
---@return table currencies Array of { currencyID, amount, name, icon, isGold? }
function WarbandNexus:GetGearUpgradeCurrencies(charKey)
    return self:GetGearUpgradeCurrenciesFromDB(charKey)
end

-- After currency changes (e.g. crests spent on upgrade), re-scan gear so item ilvl/tier and watermarks stay in sync.
WarbandNexus:RegisterMessage("WN_CURRENCY_UPDATED", function()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
    if currencyGearScanTimer then currencyGearScanTimer:Cancel() end
    currencyGearScanTimer = C_Timer.NewTimer(0.4, function()
        currencyGearScanTimer = nil
        WarbandNexus:ScanEquippedGear()
    end)
end)
