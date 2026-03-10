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

-- Reverse map: slotID -> slot def (O(1) lookup)
local SLOT_BY_ID = {}
for _, s in ipairs(GEAR_SLOTS) do
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
local EQUIP_LOC_TO_SLOTS = {
    INVTYPE_HEAD           = { 1  },
    INVTYPE_NECK           = { 2  },
    INVTYPE_SHOULDER       = { 3  },
    INVTYPE_BACK           = { 15 },
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

local GEAR_DATA_VERSION = "1.0.0"

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
for _, trackName in ipairs(TRACK_ORDER) do
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
--- Falls back through C_Item.GetDetailedItemLevelInfo → GetItemInfo.
---@param itemLink string Item hyperlink
---@return number ilvl (0 if unknown)
local function GetEffectiveIlvl(itemLink)
    if not itemLink then return 0 end
    local ilvl = 0

    -- Primary: C_Item.GetDetailedItemLevelInfo (uses bonus IDs from link)
    local ok = pcall(function()
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local val = C_Item.GetDetailedItemLevelInfo(itemLink)
            if val and val > 0 then ilvl = val end
        end
    end)

    -- Fallback: C_Item.GetItemInfo (returns base ilvl; may be nil if not cached)
    if ilvl == 0 then
        pcall(function()
            if C_Item and C_Item.GetItemInfo then
                local _, _, _, level = C_Item.GetItemInfo(itemLink)
                if level and level > 0 then ilvl = level end
            end
        end)
    end

    return ilvl
end

--- Get the equip location string for an item link ("INVTYPE_HEAD" etc.)
---@param itemLink string
---@return string equipLoc (empty string if unknown/non-equip)
local function GetEquipLoc(itemLink)
    if not itemLink then return "" end
    local loc = ""
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            -- GetItemInfoInstant: itemID, itemType, itemSubType, stackCount, itemEquipLoc, icon, classID, subclassID
            local _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
            loc = itemEquipLoc or ""
        end
    end)
    return loc
end

--- Get quality (rarity) integer for an item link.
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

    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            -- Matches "Upgrade Level: Adventurer 6/6" (English client)
            local track, cur, max = text:match("Upgrade Level: (%a[%a ]*) (%d+)/(%d+)")
            if track and cur and max then
                -- Trim trailing space from track name
                track = track:match("^(.-)%s*$")
                return {
                    trackName   = track,
                    currUpgrade = tonumber(cur),
                    maxUpgrade  = tonumber(max),
                }
            end
        end
    end
    return nil
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

        -- Persist next-level costs so UI can show "affordable" badge offline
        local hasNext = (currUpgrade < maxUpgrade)
        if hasNext then
            local levelInfos = info.upgradeLevelInfos or {}
            local nextInfo   = levelInfos[currUpgrade + 1]
            if nextInfo and nextInfo.currencyCostsToUpgrade then
                local costs = {}
                for _, entry in ipairs(nextInfo.currencyCostsToUpgrade) do
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
                for _, entry in ipairs(rawCosts) do
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

    for _, slotDef in ipairs(GEAR_SLOTS) do
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

    DebugPrint("Gear scan complete for", charKey, "—", (function()
        local n = 0
        for _ in pairs(slots) do n = n + 1 end
        return n
    end)(), "slots equipped")

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

        if slot.notUpgradeable then
            upgrades[slotID] = {
                canUpgrade = false, notUpgradeable = true,
                currentIlvl = itemLevel, nextIlvl = itemLevel, maxIlvl = 0,
                currUpgrade = 0, maxUpgrade = 0, trackName = "",
                currencyID = 0, crestCost = 0, moneyCost = 0,
                watermarkIlvl = watermarks[slotID] or 0,
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

--- Debug: print upgrade info and affordability per slot (current character only). Use /wn gearupgradedebug
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
    for _, c in ipairs(currencies) do
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
    for _, slotDef in ipairs(GEAR_SLOTS) do
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
--- Uses the stored itemLink (contains bonus IDs), with itemID fallback.
---@param item table Hydrated item from ItemsCacheService
---@return number ilvl (0 if unknown)
local function ResolveStorageItemIlvl(item)
    if not item then return 0 end

    -- Prefer stored itemLevel if already non-zero
    if item.itemLevel and item.itemLevel > 0 then return item.itemLevel end

    -- Try via itemLink (bonus IDs give accurate ilvl)
    local link = item.itemLink or item.link
    if link then
        local ilvl = GetEffectiveIlvl(link)
        if ilvl > 0 then return ilvl end
    end

    return 0
end

--- Determine the binding/availability label for a storage item.
---@param item table Hydrated item
---@param sourceCharKey string The character that owns this item
---@param selectedCharKey string The character we're gearing
---@return string label  e.g. "Warband Bank", "Shaman Foo (Bag)", "Your Bag"
---@return string type   "warband" | "self_bag" | "self_bank" | "char_bag" | "char_bank" | "boe"
local function ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
    local charData = WarbandNexus.db and WarbandNexus.db.global
                     and WarbandNexus.db.global.characters
                     and WarbandNexus.db.global.characters[sourceCharKey]
    local charName = (charData and charData.name) or sourceCharKey

    if storageType == "warband" then
        return "Warband Bank", "warband"
    elseif sourceCharKey == selectedCharKey then
        if storageType == "bank" then return "Your Bank", "self_bank" end
        return "Your Bag", "self_bag"
    else
        -- Another character's item: only show BoE (unbound) items
        if item.isBound then return nil, nil end  -- Bound to other char; skip
        local suffix = (storageType == "bank") and " (Bank)" or " (Bag)"
        local sourceType = (storageType == "bank") and "char_bank" or "char_bag"
        return charName .. suffix, sourceType
    end
end

--- Find items in storage (all chars' bags/bank + warband bank) that would
--- upgrade any equipped slot for the selected character.
---@param selectedCharKey string
---@return table findings { [slotID] = { {itemID, itemLink, itemLevel, quality, source, sourceType, isBound}, ... } }
function WarbandNexus:FindGearStorageUpgrades(selectedCharKey)
    local findings = {}
    if not selectedCharKey then return findings end

    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)

    -- Helper: record a potential upgrade candidate for a given slot
    local function AddCandidate(slotID, candidate)
        if not findings[slotID] then findings[slotID] = {} end
        -- Deduplicate by itemLink + source
        for _, ex in ipairs(findings[slotID]) do
            if ex.itemLink == candidate.itemLink and ex.source == candidate.source then return end
        end
        findings[slotID][#findings[slotID] + 1] = candidate
    end

    -- Helper: evaluate a single storage item against all equipment slots
    local function EvaluateItem(item, sourceCharKey, storageType)
        if not item or not item.itemID then return end

        local equipLoc = ""
        pcall(function()
            -- GetItemInfoInstant: id, type, subtype, stackCount, equipLoc, icon, classID, subclassID
            local _, _, _, _, loc = C_Item.GetItemInfoInstant(item.itemID)
            equipLoc = loc or ""
        end)

        if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then return end

        local targetSlots = EQUIP_LOC_TO_SLOTS[equipLoc]
        if not targetSlots then return end

        local ilvl = ResolveStorageItemIlvl(item)
        if ilvl == 0 then return end  -- Can't determine ilvl; skip

        for _, slotID in ipairs(targetSlots) do
            local currentIlvl = equippedMap[slotID] or 0
            if ilvl > currentIlvl then
                local source, sourceType = ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
                if source then  -- nil means item is bound to another char; skip
                    AddCandidate(slotID, {
                        itemID     = item.itemID,
                        itemLink   = item.itemLink or item.link,
                        itemLevel  = ilvl,
                        quality    = item.quality or 0,
                        source     = source,
                        sourceType = sourceType,
                        isBound    = item.isBound,
                    })
                end
            end
        end
    end

    -- ── Warband Bank ──────────────────────────────────────────────────────────
    local wbData = (WarbandNexus.GetWarbandBankData and WarbandNexus:GetWarbandBankData()) or nil
    if wbData and wbData.items then
        for _, item in ipairs(wbData.items) do
            EvaluateItem(item, nil, "warband")
        end
    end

    -- ── All Tracked Characters ────────────────────────────────────────────────
    local allChars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    if allChars then
        for charKey, charData in pairs(allChars) do
            if charData.isTracked then
                local itemsData = (WarbandNexus.GetItemsData and WarbandNexus:GetItemsData(charKey)) or nil
                if itemsData then
                    -- Bags
                    for _, item in ipairs(itemsData.bags or {}) do
                        EvaluateItem(item, charKey, "bag")
                    end
                    -- Personal Bank
                    for _, item in ipairs(itemsData.bank or {}) do
                        EvaluateItem(item, charKey, "bank")
                    end
                end
            end
        end
    end

    -- Sort each slot's candidates by ilvl descending; keep top 5
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

--- Crest + gold for Gear tab.
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

    for _, currencyID in ipairs(UPGRADE_CURRENCY_IDS) do
        local amount = 0
        local cName = UPGRADE_CURRENCY_NAMES[currencyID]
        local cIcon = nil

        if isCurrentChar and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            -- LIVE API: exact same normalization as FetchCurrencyFromAPI in CurrencyCacheService
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if ok and info then
                if info.name and info.name ~= "" then cName = info.name end
                if info.iconFileID then cIcon = info.iconFileID end
                amount = info.quantity or 0
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
                end
            end
        end

        result[#result + 1] = {
            currencyID = currencyID,
            amount     = tonumber(amount) or 0,
            name       = cName,
            icon       = cIcon,
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
