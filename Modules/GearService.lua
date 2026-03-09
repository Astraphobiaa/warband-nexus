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

    Upgrade data is session-only (requires C_ItemUpgrade API, current char only).
    Storage upgrade findings are recomputed on each tab open.
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

-- Export slot definitions for use by GearUI
ns.GEAR_SLOTS        = GEAR_SLOTS
ns.SLOT_BY_ID        = SLOT_BY_ID
ns.EQUIP_LOC_TO_SLOTS = EQUIP_LOC_TO_SLOTS

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
                    if entry.currencyID and entry.cost then
                        costs[#costs + 1] = { currencyID = entry.currencyID, amount = entry.cost }
                    end
                end
                if #costs > 0 then
                    slotEntry.nextUpgradeCosts = costs
                end
            end
            if not slotEntry.nextUpgradeCosts and C_ItemUpgrade.GetItemUpgradeCost then
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

    -- Only scan for tracked characters
    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end

    local slots = {}

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

                -- Persist upgrade track data (C_ItemUpgrade, current char only)
                ScanSlotUpgradeData(slotEntry, slotID)

                slots[slotID] = slotEntry
            end
        end
    end

    db[charKey] = {
        version  = GEAR_DATA_VERSION,
        lastScan = time(),
        slots    = slots,
    }

    DebugPrint("Gear scan complete for", charKey, "—", (function()
        local n = 0
        for _ in pairs(slots) do n = n + 1 end
        return n
    end)(), "slots equipped")

    -- Notify UI modules
    if Constants and Constants.EVENTS and Constants.EVENTS.GEAR_UPDATED then
        WarbandNexus:SendMessage(Constants.EVENTS.GEAR_UPDATED, { charKey = charKey })
    end
end

--- Register event listener for PLAYER_EQUIPMENT_CHANGED to keep gear data fresh.
function WarbandNexus:RegisterGearCacheEvents()
    -- PLAYER_EQUIPMENT_CHANGED is owned by EventManager.
    -- This method is kept for backward compatibility.
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

--- Get stored equipped gear for any tracked character.
---@param charKey string Character key ("Name-Realm")
---@return table|nil { version, lastScan, slots = { [slotID] = { itemID, itemLink, itemLevel, quality, equipLoc, name } } }
function WarbandNexus:GetEquippedGear(charKey)
    local db = GetDB()
    if not db or not charKey then return nil end
    return db[charKey]
end

-- ============================================================================
-- UPGRADE ANALYSIS  (Session-only — requires C_ItemUpgrade API, current char)
-- ============================================================================

--- Scan upgrade opportunities for every equipped slot using C_ItemUpgrade.
--- Returns session-only data (not persisted; only valid while character is online).
---@return table upgrades { [slotID] = { canUpgrade, currentIlvl, nextIlvl, maxIlvl, trackName, costs } }
function WarbandNexus:GetGearUpgradeInfo()
    local upgrades = {}

    -- C_ItemUpgrade may not be available in all expansion builds
    if not C_ItemUpgrade then return upgrades end
    if not ItemLocation then return upgrades end

    for _, slotDef in ipairs(GEAR_SLOTS) do
        local slotID = slotDef.id
        local ok, result = pcall(function()
            local location = ItemLocation:CreateFromEquipmentSlot(slotID)
            if not location or not location:IsValid() then return nil end

            -- API returns: currUpgrade, maxUpgrade, minItemLevel, maxItemLevel, upgradeLevelInfos[], itemUpgradeable
            local info = (C_ItemUpgrade.GetItemUpgradeItemInfo and C_ItemUpgrade.GetItemUpgradeItemInfo(location)) or {}
            if not info or (info.itemUpgradeable == false and info.currUpgrade == nil and info.maxUpgrade == nil) then return nil end

            local currUpgrade = info.currUpgrade or 0
            local maxUpgrade  = info.maxUpgrade or 0

            -- If the API returned 0/0 with no useful data, check for not-upgradeable or
            -- fall back to tooltip parsing.
            if currUpgrade == 0 and maxUpgrade == 0 then
                if info.itemUpgradeable == false then
                    -- API explicitly says not upgradeable
                    local hasItem = false
                    pcall(function()
                        if C_Item and C_Item.DoesItemExist then
                            hasItem = C_Item.DoesItemExist(location)
                        end
                    end)
                    if hasItem then
                        return { canUpgrade = false, notUpgradeable = true, currentIlvl = 0, nextIlvl = 0, maxIlvl = 0, currUpgrade = 0, maxUpgrade = 0, trackName = "", costs = {} }
                    end
                    return nil
                end
                -- API returned nothing useful — try tooltip fallback for track info
                local tipInfo = ScanUpgradeFromTooltip(slotDef.id)
                if tipInfo then
                    local cur = tipInfo.currUpgrade or 0
                    local max = tipInfo.maxUpgrade  or 0
                    if max > 0 then
                        local currentIlvl = 0
                        pcall(function()
                            if C_Item and C_Item.GetCurrentItemLevel then
                                local v = C_Item.GetCurrentItemLevel(location)
                                if v and type(v) == "number" and v > 0 then currentIlvl = v end
                            end
                        end)
                        return {
                            canUpgrade  = (cur < max),
                            currentIlvl = currentIlvl,
                            nextIlvl    = currentIlvl,
                            maxIlvl     = 0,
                            currUpgrade = cur,
                            maxUpgrade  = max,
                            trackName   = tipInfo.trackName,
                            costs       = {},
                        }
                    end
                end
                return nil
            end

            local hasNextStep = (currUpgrade < maxUpgrade)
            -- Include slot even when at max, so UI can show "X iLvl (Max)" from API; canUpgrade = has next tier

            local minIlvl     = info.minItemLevel or 0
            local maxIlvl     = info.maxItemLevel or 0
            local levelInfos  = info.upgradeLevelInfos or {}

            -- Current ilvl: prefer C_Item.GetCurrentItemLevel (accurate); fallback to min + increments
            local currentIlvl = minIlvl
            for i = 1, currUpgrade do
                local linfo = levelInfos[i]
                if linfo and linfo.itemLevelIncrement then
                    currentIlvl = currentIlvl + linfo.itemLevelIncrement
                end
            end
            if C_Item and C_Item.GetCurrentItemLevel then
                local okGet, apiIlvl = pcall(function() return C_Item.GetCurrentItemLevel(location) end)
                if okGet and apiIlvl and type(apiIlvl) == "number" and apiIlvl > 0 then
                    currentIlvl = apiIlvl
                end
            end

            local nextLevelInfo = hasNextStep and levelInfos[currUpgrade + 1] or nil
            local nextIlvl = currentIlvl
            if nextLevelInfo and nextLevelInfo.itemLevelIncrement then
                nextIlvl = currentIlvl + nextLevelInfo.itemLevelIncrement
            elseif maxIlvl and maxIlvl > currentIlvl then
                nextIlvl = maxIlvl
            end

            -- Costs only when there is a next upgrade step
            local costs = {}
            if nextLevelInfo and nextLevelInfo.currencyCostsToUpgrade then
                for _, entry in ipairs(nextLevelInfo.currencyCostsToUpgrade) do
                    if entry.currencyID and entry.cost then
                        costs[#costs + 1] = { currencyID = entry.currencyID, amount = entry.cost }
                    end
                end
            end
            -- Fallback: legacy GetItemUpgradeCost(location, level)
            if #costs == 0 and C_ItemUpgrade.GetItemUpgradeCost then
                local rawCosts = C_ItemUpgrade.GetItemUpgradeCost(location, currUpgrade + 1) or {}
                for _, entry in ipairs(rawCosts) do
                    if entry.currencyID and (entry.amount or entry.cost) then
                        costs[#costs + 1] = {
                            currencyID = entry.currencyID,
                            amount     = entry.amount or entry.cost,
                        }
                    end
                end
            end

            -- Only include slots that have real item data (avoid empty-slot noise)
            if currentIlvl == 0 and maxIlvl == 0 then return nil end

            local trackName = (info.name and info.name ~= "") and info.name or ""
            if trackName == "" and info.customUpgradeString and info.customUpgradeString ~= "" then
                trackName = info.customUpgradeString
            end
            return {
                canUpgrade  = hasNextStep,
                currentIlvl = currentIlvl,
                nextIlvl    = nextIlvl,
                maxIlvl     = maxIlvl,
                currUpgrade = currUpgrade,
                maxUpgrade  = maxUpgrade,
                trackName   = trackName,
                costs       = costs,
            }
        end)

        if ok and result then
            upgrades[slotID] = result
        end
    end

    return upgrades
end

--- Reconstruct upgradeInfo table from persisted slot data.
--- Returns the same shape as GetGearUpgradeInfo() so GearUI needs no branching.
---@param charKey string
---@return table upgrades { [slotID] = { canUpgrade, currentIlvl, nextIlvl, maxIlvl, trackName, currUpgrade, maxUpgrade, costs } }
function WarbandNexus:GetPersistedUpgradeInfo(charKey)
    local upgrades = {}
    local gearData = self:GetEquippedGear(charKey)
    if not gearData or not gearData.slots then return upgrades end

    for slotID, slot in pairs(gearData.slots) do
        if slot.currUpgrade and slot.maxUpgrade and slot.maxUpgrade > 0 then
            local hasNext = (slot.currUpgrade < slot.maxUpgrade)
            upgrades[slotID] = {
                canUpgrade  = hasNext,
                currentIlvl = slot.itemLevel or 0,
                nextIlvl    = slot.itemLevel or 0,
                maxIlvl     = slot.maxIlvl or 0,
                currUpgrade = slot.currUpgrade,
                maxUpgrade  = slot.maxUpgrade,
                trackName   = slot.upgradeTrack or "",
                costs       = hasNext and slot.nextUpgradeCosts or {},
            }
        elseif slot.notUpgradeable and slot.itemLink then
            -- Item is equipped but confirmed not part of any upgrade track
            upgrades[slotID] = {
                canUpgrade     = false,
                notUpgradeable = true,
                currentIlvl    = slot.itemLevel or 0,
                nextIlvl       = slot.itemLevel or 0,
                maxIlvl        = 0,
                currUpgrade    = 0,
                maxUpgrade     = 0,
                trackName      = "",
                costs          = {},
            }
        end
    end

    return upgrades
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
    3391,  -- Adventurer Dawncrest (ilvl 224–237)
    3342,  -- Veteran Dawncrest (ilvl 237–250)
    3343,  -- Champion Dawncrest (ilvl 250–263)
    3345,  -- Hero Dawncrest (ilvl 263–276)
    3347,  -- Myth Dawncrest (ilvl 276–289)
}

-- Fallback names for Dawncrests (when API not ready)
local UPGRADE_CURRENCY_NAMES = {
    [3391] = "Adventurer Dawncrest",
    [3342] = "Veteran Dawncrest",
    [3343] = "Champion Dawncrest",
    [3345] = "Hero Dawncrest",
    [3347] = "Myth Dawncrest",
}

--- Get the player's current quantities of upgrade-relevant currencies.
--- For current character uses C_CurrencyInfo live API so amounts are always real.
---@param charKey string
---@return table currencies Array of { currencyID, amount, name, icon, isGold? }
function WarbandNexus:GetGearUpgradeCurrencies(charKey)
    local result = {}
    if not charKey then return result end

    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
    local isCurrentChar = (charKey == currentKey)

    for _, currencyID in ipairs(UPGRADE_CURRENCY_IDS) do
        local amount, name, icon = 0, UPGRADE_CURRENCY_NAMES[currencyID] or ("Currency " .. currencyID), nil

        if isCurrentChar and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if ok and info then
                amount = (info.quantity ~= nil) and info.quantity or 0
                if info.name and info.name ~= "" then name = info.name end
                icon = info.iconFileID or info.icon
            end
        end

        if not isCurrentChar or not icon then
            local entry = self.GetCurrencyData and self:GetCurrencyData(currencyID, charKey) or nil
            if entry then
                if amount == 0 and entry.quantity ~= nil then amount = entry.quantity end
                if (not name or name == "") and entry.name and entry.name ~= "" then name = entry.name end
                if not icon then icon = entry.iconFileID or entry.icon end
            end
        end

        result[#result + 1] = {
            currencyID = currencyID,
            amount     = amount,
            name       = name,
            icon       = icon,
        }
    end

    -- Gold: live for current char, else from DB
    local db = WarbandNexus.db and WarbandNexus.db.global
    if db and db.characters and db.characters[charKey] then
        local charData = db.characters[charKey]
        local gold = charData.gold or 0
        if isCurrentChar and GetMoney then
            gold = GetMoney() or 0
        end
        result[#result + 1] = {
            currencyID = 0,
            amount     = math.floor(gold / 10000),
            name       = "Gold",
            icon       = 133784,
            isGold     = true,
            silver     = math.floor((gold % 10000) / 100),
            copper     = gold % 100,
        }
    end

    return result
end
