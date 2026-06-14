--[[
    Warband Nexus - Gear storage upgrade finder (ops-032 slice)
    FindGearStorageUpgrades, cache APIs, yielded scan, /wn gearstash diagnostic.
    Loaded after Modules/GearService.lua (deps on ns.GearService._storageFindDeps).
    See WN-CODE-gear-storage-recommendations.mdc for product rules.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local issecretvalue = issecretvalue
local wipe = table.wipe
local debugprofilestop = debugprofilestop

local M = ns.GearStorageFind or {}
ns.GearStorageFind = M

local function D(name)
    local deps = ns.GearService and ns.GearService._storageFindDeps
    assert(deps, "GearService_StorageFind: bind _storageFindDeps in GearService.lua before load")
    local v = deps[name]
    assert(v ~= nil, "GearService_StorageFind: missing dep " .. tostring(name))
    return v
end

local GEAR_STORAGE_PUMP_BUDGET_MS = 12
local GEAR_STORAGE_PUMP_MAX_RESUMES = 48
local GEAR_STORAGE_EVAL_ITEMS_PER_YIELD = 14
local GEAR_STORAGE_WARBANK_ITEMS_PER_YIELD = 24
local GEAR_STORAGE_CHAR_LOOP_EVERY = 3

local GEAR_SLOTS = D("GEAR_SLOTS")
local EQUIP_LOC_TO_SLOTS = D("EQUIP_LOC_TO_SLOTS")
local GetEffectiveIlvl = D("GetEffectiveIlvl")
local GetEquipLoc = D("GetEquipLoc")
local GetItemQuality = D("GetItemQuality")
local GetRawItemBindType = D("GetRawItemBindType")
local CategoryFromRawBind = D("CategoryFromRawBind")
local GetItemMinLevelFromItemInfo = D("GetItemMinLevelFromItemInfo")
local IsArmorCompatible = D("IsArmorCompatible")
local IsWeaponCompatible = D("IsWeaponCompatible")
local MatchGetItemStatsPrimariesToExpected = D("MatchGetItemStatsPrimariesToExpected")
local ResolveExpectedPrimaryStatFromCharacter = D("ResolveExpectedPrimaryStatFromCharacter")
local ResolveGearStorageKey = D("ResolveGearStorageKey")
local RequestGearStorageRedraw = D("RequestGearStorageRedraw")

local function ScanTooltipForWarbandBind(itemLink, itemID)
    if not C_TooltipInfo then return nil end
    local tipData = nil
    if itemLink and not (issecretvalue and issecretvalue(itemLink)) and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and data and data.lines then tipData = data end
    end
    if not tipData and itemID and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and data and data.lines then tipData = data end
    end
    if not tipData or not tipData.lines then return nil end

    local strWuE = _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP or "Warbound until equipped"
    local strWB1 = _G.ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net Account"
    local strWB2 = _G.ITEM_BIND_TO_ACCOUNT or "Binds to Account"
    local strWB3 = _G.ITEM_BIND_TO_WARBAND or "Binds to Warband"
    local strWB4 = "Warbound"

    for li = 1, #tipData.lines do
        local lt = tipData.lines[li] and tipData.lines[li].leftText
        if lt and not (issecretvalue and issecretvalue(lt)) and type(lt) == "string" then
            if lt:find(strWuE, 1, true) or lt:find("until equipped", 1, true) then
                return "warbound_until_equipped"
            end
            if lt:find(strWB3, 1, true) or lt:find(strWB1, 1, true) or lt:find(strWB2, 1, true) or lt:find(strWB4, 1, true) then
                return "warbound"
            end
        end
    end
    return nil
end

local function GetBindingType(item)
    if not item then return nil end
    local link = item.itemLink or item.link
    local tipCat = ScanTooltipForWarbandBind(link, item.itemID)
    if tipCat then return tipCat end
    return CategoryFromRawBind(GetRawItemBindType(item))
end

local function IsCosmeticGearCandidate(itemID, itemLink)
    if not itemID or not C_Item or not C_Item.IsCosmeticItem then return false end
    local ok, isCosmetic = pcall(function()
        if itemLink and type(itemLink) == "string" and itemLink ~= "" and not (issecretvalue and issecretvalue(itemLink)) then
            return C_Item.IsCosmeticItem(itemLink)
        end
        return C_Item.IsCosmeticItem(itemID)
    end)
    return ok and isCosmetic == true
end

local GEAR_STORAGE_FINDINGS_LOGIC_VER = 10

local function GearStorageFindingsCount(findings)
    if not findings or type(findings) ~= "table" then return 0, 0 end
    local slots, cand = 0, 0
    for _, list in pairs(findings) do
        slots = slots + 1
        if type(list) == "table" then
            cand = cand + #list
        end
    end
    return slots, cand
end

local function IsAllowedStorageRecommendationBindLabel(sourceType)
    if sourceType == "self_bag" or sourceType == "self_bank" then
        return true
    end
    if sourceType == "boe" or sourceType == "warbound" or sourceType == "warbound_until_equipped" then
        return true
    end
    return false
end

local function IsViewingLivePlayerGear(charKey)
    if not charKey then return false end
    local U = ns.Utilities
    local function canon(k)
        if not k or k == "" then return "" end
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    local view = canon(charKey)
    if view == "" then return false end
    if WarbandNexus.IsGearTabCharacterLoggedInPlayer
        and WarbandNexus:IsGearTabCharacterLoggedInPlayer(charKey) then
        return true
    end
    if U and U.GetCharacterStorageKey then
        local live = U:GetCharacterStorageKey(WarbandNexus)
        if live and canon(live) == view then return true end
    end
    if UnitGUID then
        local pg = UnitGUID("player")
        if pg and not (issecretvalue and issecretvalue(pg)) and canon(pg) == view then
            return true
        end
    end
    return false
end

local function IsSelectedCharacterOwnStorage(sourceCharKey, selectedCharKey, storageType, getCanonicalKey, forceOwn)
    if storageType ~= "bag" and storageType ~= "bank" then return false end
    if forceOwn == true then return true end
    if not sourceCharKey or not selectedCharKey then return false end
    local src = getCanonicalKey(sourceCharKey) or sourceCharKey
    local sel = getCanonicalKey(selectedCharKey) or selectedCharKey
    if src ~= "" and sel ~= "" and src == sel then return true end
    return false
end

local function OwnStorageSourceLabels(storageType)
    if storageType == "bank" then
        return "Your Bank", "self_bank"
    end
    return "Your Bag", "self_bag"
end
-- STORAGE UPGRADE FINDER  (Cross-character — reads persisted item data)

local function ResolveEquippedIlvlForComparison(charKey, slotID, equippedMap)
    -- Logged-in player: live inventory wins over stale db.global.gearData (unequip-to-bag must clear slot).
    if IsViewingLivePlayerGear(charKey) and GetInventoryItemLink then
        local link = GetInventoryItemLink("player", slotID)
        if not link or link == "" or (issecretvalue and issecretvalue(link)) then
            return 0
        end
        local liveIl = GetEffectiveIlvl(link) or 0
        if liveIl > 0 then return liveIl end
        return 0
    end

    local il = equippedMap and equippedMap[slotID] or nil
    if il and il > 0 then return il end

    local gearData = WarbandNexus:GetEquippedGear(charKey)
    local slotData = gearData and gearData.slots and gearData.slots[slotID]
    if slotData then
        il = tonumber(slotData.itemLevel) or 0
        if il > 0 then return il end
        if slotData.itemLink then
            il = GetEffectiveIlvl(slotData.itemLink) or 0
            if il > 0 then return il end
        end
    end

    return 0
end

local function BuildEquippedIlvlMap(charKey)
    local map = {}
    local slotList = GEAR_SLOTS
    if slotList then
        for si = 1, #slotList do
            local sid = slotList[si].id
            map[sid] = ResolveEquippedIlvlForComparison(charKey, sid, nil)
        end
        return map
    end
    local gearData = WarbandNexus:GetEquippedGear(charKey)
    if not gearData or not gearData.slots then return map end
    for slotID, _ in pairs(gearData.slots) do
        map[slotID] = ResolveEquippedIlvlForComparison(charKey, slotID, nil)
    end
    return map
end

local GEAR_STORAGE_EMPTY_SLOT_FLOOR_MARGIN = 40

local function BuildGearStorageComparisonFloor(charKey, slotID, equippedMap, charData)
    local equipped = ResolveEquippedIlvlForComparison(charKey, slotID, equippedMap)
    if equipped > 0 then return equipped end

    local sum, count = 0, 0
    local gearData = WarbandNexus:GetEquippedGear(charKey)
    if gearData and gearData.slots then
        for sid, _ in pairs(gearData.slots) do
            if sid ~= slotID then
                local il = ResolveEquippedIlvlForComparison(charKey, sid, equippedMap)
                if il > 0 then
                    sum = sum + il
                    count = count + 1
                end
            end
        end
    end
    if count > 0 then
        return math.max(0, math.floor(sum / count + 0.5) - GEAR_STORAGE_EMPTY_SLOT_FLOOR_MARGIN)
    end
    local rosterIlvl = charData and tonumber(charData.itemLevel)
    if rosterIlvl and rosterIlvl > 0 then
        return math.max(0, rosterIlvl - GEAR_STORAGE_EMPTY_SLOT_FLOOR_MARGIN)
    end
    return 0
end

local function GearItemEvalSeenKey(item)
    if not item then return "nil" end
    local bagID = item.actualBagID or item.bagID
    local slotIdx = item.slotIndex or item.slot
    if bagID ~= nil and slotIdx ~= nil then
        return "c:" .. tostring(bagID) .. ":" .. tostring(slotIdx)
    end
    local lk = item.itemLink or item.link
    if lk and type(lk) == "string" and not (issecretvalue and issecretvalue(lk)) then
        return "l:" .. lk
    end
    return "i:" .. tostring(item.itemID or 0)
end

-- Fixed slot order for FindGearStorageUpgrades cache keys (pairs() on slots is undefined order).
local GEAR_STORAGE_SIG_SLOTS = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}
local gearStorageFindingsCache = { canonKey = nil, invEpoch = nil, equipSig = nil, findings = nil, logicVer = nil }

-- Narrow refresh (ITEM_METADATA / GET_ITEM_INFO) used to Invalidate+ScheduleResolve immediately after a
-- yielded Find commit, producing duplicate full scans with identical Reject/add lines. We record the last
-- yield completion time per canon and let UI.lua skip soft-invalidate when cache is still strict-valid.
ns._gearStorageLastYieldCompleteAt = ns._gearStorageLastYieldCompleteAt or {}
local GEAR_STORAGE_NARROW_RESCAN_COOLDOWN = 0.72

local function BuildGearStorageScanCacheSignature(selectedCharKey, equippedMap)
    local gear = WarbandNexus:GetEquippedGear(selectedCharKey)
    local sl = gear and gear.slots
    local parts = {}
    for i = 1, #GEAR_STORAGE_SIG_SLOTS do
        local sid = GEAR_STORAGE_SIG_SLOTS[i]
        local sd = sl and sl[sid]
        local ilv = (equippedMap and equippedMap[sid]) or 0
        local iid = 0
        if sd and sd.itemID then
            iid = tonumber(sd.itemID) or 0
        end
        parts[i] = tostring(ilv) .. ":" .. tostring(iid)
    end
    return table.concat(parts, ";")
end

local function ResolveStorageItemIlvl(item)
    if not item or not item.itemID then return 0 end

    local storedIlvl = tonumber(item.itemLevel) or tonumber(item.ilvl)
    if storedIlvl and storedIlvl > 0 then return storedIlvl end

    local bagID = item.actualBagID or item.bagID
    local slotIdx = item.slotIndex or item.slot
    if bagID and slotIdx and ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.GetCurrentItemLevel then
        local okLoc, ilFromLoc = pcall(function()
            local loc = ItemLocation:CreateFromBagAndSlot(bagID, slotIdx)
            if loc and loc.IsValid and loc:IsValid() then
                local v = C_Item.GetCurrentItemLevel(loc)
                if type(v) == "number" and v > 0 then return v end
            end
            return 0
        end)
        if okLoc and ilFromLoc and ilFromLoc > 0 then return ilFromLoc end
    end

    local link = item.itemLink or item.link
    if link then
        -- Prefer link-based ilvl first so storage row matches tooltip when cache is warm.
        local ilvl = GetEffectiveIlvl(link)
        if ilvl > 0 then return ilvl end
        local ok, _, _, level = pcall(C_Item.GetItemInfo, link)
        if ok and level and type(level) == "number" and level > 0 then
            return level
        end
        -- Link present but client cache still cold: try ID-based APIs (often warm before hyperlink resolves).
        local detFromId = 0
        pcall(function()
            if C_Item and C_Item.GetDetailedItemLevelInfo then
                local v = select(1, C_Item.GetDetailedItemLevelInfo(item.itemID))
                if type(v) == "number" and v > 0 then detFromId = v end
            end
        end)
        if detFromId > 0 then return detFromId end
        local ilvlId = GetEffectiveIlvl(item.itemID)
        if ilvlId > 0 then return ilvlId end
        local ok3, _, _, level3 = pcall(C_Item.GetItemInfo, item.itemID)
        if ok3 and level3 and type(level3) == "number" and level3 > 0 then
            return level3
        end
        -- Still unknown: EvaluateItem already requested load by ID; next ITEM_METADATA / items scan can fill in.
        return 0
    end
    local ilvlId = GetEffectiveIlvl(item.itemID)
    if ilvlId > 0 then return ilvlId end
    local ok2, _, _, level2 = pcall(C_Item.GetItemInfo, item.itemID)
    if ok2 and level2 and type(level2) == "number" and level2 > 0 then
        return level2
    end

    return 0
end

local function ResolveStorageItemIlvlWarm(item)
    if not item then return 0 end
    local ilvl = ResolveStorageItemIlvl(item)
    if ilvl > 0 then return ilvl end
    if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, item.itemID)
        ilvl = ResolveStorageItemIlvl(item)
    end
    return ilvl or 0
end

local function ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
    local allCharsDB = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    local charData = allCharsDB and allCharsDB[sourceCharKey]
    local charName = (charData and charData.name) or sourceCharKey

    if storageType == "warband" then
        -- Warband Bank: storage is account-wide, but recommendations stay BoE / warband-bound only.
        local rawWB = GetRawItemBindType(item)
        if rawWB == LE_ITEM_BIND_ON_ACQUIRE or rawWB == 1 or rawWB == LE_ITEM_BIND_QUEST or rawWB == 4 then
            return nil, nil
        end
        if rawWB == ITEM_BIND_ON_USE then
            return nil, nil
        end
        local wbCat = GetBindingType(item)
        if not wbCat then
            wbCat = CategoryFromRawBind(rawWB)
        end
        if not wbCat then
            wbCat = "warbound"
        end
        return "Warband Bank", wbCat
    end

    if storageType == "guild" then
        local rawG = GetRawItemBindType(item)
        if rawG == LE_ITEM_BIND_ON_ACQUIRE or rawG == 1 or rawG == LE_ITEM_BIND_QUEST or rawG == 4 then
            return nil, nil
        end
        if rawG == ITEM_BIND_ON_USE then
            return nil, nil
        end
        local gCat = GetBindingType(item)
        if not gCat then
            gCat = CategoryFromRawBind(rawG)
        end
        if not gCat then
            gCat = "warbound"
        end
        local label = "Guild Bank"
        local tnm = item.tabName
        if type(tnm) == "string" and tnm ~= "" and not (issecretvalue and issecretvalue(tnm)) then
            label = "Guild Bank (" .. tnm .. ")"
        end
        return label, gCat
    end

    local function canonical(k)
        if not k or k == "" then return "" end
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    local sourceNorm = canonical(sourceCharKey)
    local selectedNorm = canonical(selectedCharKey)
    local isSameChar = (sourceNorm ~= "" and selectedNorm ~= "" and sourceNorm == selectedNorm)

    if isSameChar and (storageType == "bag" or storageType == "bank") then
        return OwnStorageSourceLabels(storageType)
    end

    -- Cross-character: prefer tooltip scan (catches WuE items reported as bindType=2 by
    -- GetItemInfo). If tooltip says Warbound or Warbound-until-equipped, item is transferable.
    local tipCat = ScanTooltipForWarbandBind(item.itemLink or item.link, item.itemID)

    -- A BoE *template* item that has been equipped/right-clicked becomes Soulbound to the
    -- source character. The bag snapshot records this via item.isBound=true. Such items are
    -- NOT transferable to another alt — only the warband-binding categories survive equip.
    -- Reject any cross-character entry that is flagged isBound and not warband-bound.
    if item.isBound == true and tipCat == nil then
        return nil, nil
    end

    if tipCat then
        local suffix = (storageType == "bank") and " (Bank)" or " (Bag)"
        return charName .. suffix, tipCat
    end

    -- No tooltip-derived warband flag → fall back to template bindType for BoE detection.
    local rawBind = GetRawItemBindType(item)
    if rawBind == LE_ITEM_BIND_ON_ACQUIRE or rawBind == 1 then
        return nil, nil
    end
    if rawBind == LE_ITEM_BIND_QUEST or rawBind == 4 then
        return nil, nil
    end

    local bindCategory = CategoryFromRawBind(rawBind)
    if not bindCategory then
        return nil, nil
    end

    local suffix = (storageType == "bank") and " (Bank)" or " (Bag)"
    return charName .. suffix, bindCategory
end

--- Fast path for Gear tab staged paint: returns cached findings when inventory epoch,
--- character, and equipped signature match (same gates as FindGearStorageUpgrades).
--- Does not run the cross-character scan.
---@param selectedCharKey string
---@return table|nil findings
---@return boolean cached True when findings came from gearStorageFindingsCache
function WarbandNexus:GetGearStorageFindingsIfCached(selectedCharKey)
    if not selectedCharKey then return nil, false end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k)
    end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey
    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)
    local invEpoch = ns._gearStorageInvGen or 0
    local equipSig = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMap)
    local c = gearStorageFindingsCache
    if c.canonKey == canonKey and c.invEpoch == invEpoch and c.equipSig == equipSig and c.findings
        and (c.logicVer or 0) == GEAR_STORAGE_FINDINGS_LOGIC_VER then
        local _, fc = GearStorageFindingsCount(c.findings)
        if fc > 0 then
            return c.findings, true
        end
        -- Empty findings must not block a rescan (bag/equip change may have added candidates).
    end
    return nil, false
end

--- Findings from the last committed scan for this character (ignores invEpoch; UI post-yield paint).
---@param selectedCharKey string
---@return table|nil findings
---@return boolean ok
function WarbandNexus:GetGearStorageFindingsCommitted(selectedCharKey)
    if not selectedCharKey then return nil, false end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k)
    end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey
    local c = gearStorageFindingsCache
    if c.canonKey == canonKey and c.findings and (c.logicVer or 0) == GEAR_STORAGE_FINDINGS_LOGIC_VER then
        return c.findings, true
    end
    return nil, false
end

--- Equip-only change (ring/trinket swap): bag findings unchanged — update equipSig so UI can redraw without FindGearStorageUpgrades.
---@param selectedCharKey string
---@return boolean ok
function WarbandNexus:RefreshGearStorageCacheEquipSigForCanon(selectedCharKey)
    if not selectedCharKey then return false end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k)
    end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey
    local c = gearStorageFindingsCache
    if c.canonKey ~= canonKey or not c.findings then
        return false
    end
    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)
    c.equipSig = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMap)
    return true
end

--- Like GetGearStorageFindingsIfCached but matches canon + equipSig only; invEpoch must match
--- unless `ns._gearStorageAllowEquipSigInvBypass` is true (GearUI arms this for one redraw tick
--- after a yielded Find) so post-scan item-info bumps do not force a second full scan.
---@param selectedCharKey string
---@return table|nil findings
---@return boolean ok
function WarbandNexus:GetGearStorageFindingsIfEquipSigMatch(selectedCharKey)
    if not selectedCharKey then return nil, false end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k)
    end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey
    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)
    local equipSig = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMap)
    local c = gearStorageFindingsCache
    if c.canonKey ~= canonKey or c.equipSig ~= equipSig or not c.findings
        or (c.logicVer or 0) ~= GEAR_STORAGE_FINDINGS_LOGIC_VER then
        return nil, false
    end
    local invEpoch = ns._gearStorageInvGen or 0
    if c.invEpoch == invEpoch then
        return c.findings, true
    end
    if ns._gearStorageAllowEquipSigInvBypass then
        return c.findings, true
    end
    return nil, false
end

--- After a committed stash scan, suppress TryRunGearTabInventoryNarrowRefresh Invalidate+Resolve when the
--- client fires metadata/item-info bursts that do not change invGen or equipped sig (avoids 2-3x full Find).
---@param canonKey string
---@return boolean
function WarbandNexus:ShouldSkipGearStorageNarrowInvalidateForRapidRescan(canonKey)
    if not canonKey then return false end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k) or k
    end or function(k) return k end
    local canon = getCanonicalKey(canonKey) or canonKey
    local c = gearStorageFindingsCache
    if not c or c.canonKey ~= canon or not c.findings then return false end
    local invNow = ns._gearStorageInvGen or 0
    if c.invEpoch == nil or c.invEpoch ~= invNow then return false end
    local tDone = ns._gearStorageLastYieldCompleteAt and ns._gearStorageLastYieldCompleteAt[canon]
    if not tDone or (GetTime() - tDone) >= GEAR_STORAGE_NARROW_RESCAN_COOLDOWN then return false end
    return true
end

--- Client item cache warmed (GET_ITEM_INFO) for links already in SV: findings must re-run,
--- but a global `ns._gearStorageInvGen` bump falsely invalidates strict cache vs real bag edits.
--- When the gear tab's populate canon matches cached scan canon, drop only `invEpoch` so the
--- next `FindGearStorageUpgrades` runs while leaving `ns._gearStorageInvGen` unchanged.
---@param canonKey string canonical character key
---@return boolean invalidated True when cache was cleared or invalidate was queued for after scan
function WarbandNexus:InvalidateGearStorageFindingsCacheForCanon(canonKey)
    if not canonKey then return false end
    if self:IsGearStorageScanInFlightForCanon(canonKey) then
        ns._gearStorageDeferInvalidateCanon = canonKey
        WarbandNexus:GearStorageTrace("Invalidate deferred (scan in flight) canon=" .. tostring(canonKey))
        return true
    end
    return self:InvalidateGearStorageFindingsCacheImmediate(canonKey)
end

--- Soft invalidate without deferral (internal; callers must not use during active yielded scan).
---@param canonKey string
---@return boolean
function WarbandNexus:InvalidateGearStorageFindingsCacheImmediate(canonKey)
    if not canonKey then return false end
    local c = gearStorageFindingsCache
    if c then
        if c.canonKey == canonKey or not c.canonKey then
            c.canonKey = nil
            c.invEpoch = nil
            c.equipSig = nil
            c.findings = nil
            c.logicVer = nil
        end
    end
    ns._gearStorageFindingsDirtyToken = (ns._gearStorageFindingsDirtyToken or 0) + 1
    WarbandNexus:GearStorageTrace("Invalidate full clear canon=" .. tostring(canonKey)
        .. " dirtyTok=" .. tostring(ns._gearStorageFindingsDirtyToken or 0))
    return true
end

--- When dirty==clean, equipSig matches cache, and we already ran a FULLFIND this GetTime() for this canon,
--- skip a second synchronous Find (duplicate TryGear + applyStorageScanUI / equipSig flicker same tick).
---@param selectedCharKey string canonical character key
---@return table|nil findings
function WarbandNexus:TryCoalesceGearStorageFullFind(selectedCharKey)
    if not selectedCharKey then return nil end
    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k)
        return ns.Utilities:GetCanonicalCharacterKey(k)
    end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey

    local dt = ns._gearStorageFindingsDirtyToken or 0
    local ct = ns._gearStorageFindingsCleanToken or 0
    if dt ~= ct then return nil end

    local equippedMap = BuildEquippedIlvlMap(canonKey)
    local equipSig = BuildGearStorageScanCacheSignature(canonKey, equippedMap)
    local c = gearStorageFindingsCache
    if not c or c.canonKey ~= canonKey or not c.findings or c.equipSig ~= equipSig then return nil end

    local tNow = GetTime()
    local sff = ns._gearStorageSameFrameFullFind
    if not sff or sff.canon ~= canonKey or sff.t ~= tNow then return nil end

    return c.findings
end

-- Reused by GetGearStorageFindingsDedupeToken (hot path via GetGearPopulateSignature); not re-entrant.
local _gearStorageDedupeTokenBuf = {}

function WarbandNexus:GetGearStorageFindingsDedupeToken()
    local c = gearStorageFindingsCache
    if not c or not c.findings then return "0" end
    local buf = _gearStorageDedupeTokenBuf
    wipe(buf)
    local n = 0
    for slotID = 1, 19 do
        local list = c.findings[slotID]
        if list and list[1] then
            local top = list[1]
            local iid = tonumber(top.itemID) or 0
            local il = math.floor(tonumber(top.itemLevel) or 0)
            buf[#buf + 1] = tostring(slotID) .. ":" .. tostring(iid) .. ":" .. tostring(il)
            n = n + 1
        end
    end
    return tostring(n) .. ";" .. table.concat(buf, ",")
end

local LIVE_INVENTORY_BAGS = ns.INVENTORY_BAGS or { 0, 1, 2, 3, 4, 5 }
local LIVE_BANK_BAGS = ns.PERSONAL_BANK_BAGS or { -1, 6, 7, 8, 9, 10, 11 }

local function IsGearLiveBagIgnored(bagID)
    local prof = WarbandNexus.db and WarbandNexus.db.profile
    return prof and prof.ignoredInventoryBags and prof.ignoredInventoryBags[bagID] == true
end

local function AppendLiveContainerBagItems(out, bagID)
    if not out or not bagID or IsGearLiveBagIgnored(bagID) then return end
    if not C_Container or not C_Container.GetContainerItemInfo then return end
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        if itemInfo and itemInfo.hyperlink then
            local hl = itemInfo.hyperlink
            if not (issecretvalue and issecretvalue(hl)) then
                local itemID = itemInfo.itemID
                if not itemID and C_Item and C_Item.GetItemInfoInstant then
                    itemID = C_Item.GetItemInfoInstant(hl)
                end
                if itemID then
                    local snapIlvl = 0
                    if ItemLocation and ItemLocation.CreateFromBagAndSlot
                        and C_Item and C_Item.GetCurrentItemLevel then
                        pcall(function()
                            local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                            if loc and loc.IsValid and loc:IsValid() then
                                local v = C_Item.GetCurrentItemLevel(loc)
                                if type(v) == "number" and v > 0
                                    and not (issecretvalue and issecretvalue(v)) then
                                    snapIlvl = v
                                end
                            end
                        end)
                    end
                    if snapIlvl == 0 and C_Item and C_Item.GetDetailedItemLevelInfo then
                        pcall(function()
                            local v = C_Item.GetDetailedItemLevelInfo(hl)
                            if type(v) == "number" and v > 0 then snapIlvl = v end
                        end)
                    end
                    out[#out + 1] = {
                        itemID = itemID,
                        itemLink = hl,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality,
                        isBound = itemInfo.isBound or false,
                        actualBagID = bagID,
                        bagID = bagID,
                        slotIndex = slot,
                        slot = slot,
                        itemLevel = (snapIlvl > 0) and snapIlvl or nil,
                    }
                end
            end
        end
    end
end

local function CollectLivePlayerContainerItemsForGearScan()
    local bagItems = {}
    local bankItems = {}
    for i = 1, #LIVE_INVENTORY_BAGS do
        if ns._gearStorageYieldCo and i > 1 and (i % 2 == 0) then
            coroutine.yield()
        end
        AppendLiveContainerBagItems(bagItems, LIVE_INVENTORY_BAGS[i])
    end
    if WarbandNexus.bankIsOpen then
        for i = 1, #LIVE_BANK_BAGS do
            if ns._gearStorageYieldCo and (i % 2 == 0) then
                coroutine.yield()
            end
            AppendLiveContainerBagItems(bankItems, LIVE_BANK_BAGS[i])
        end
    end
    return bagItems, bankItems
end

--- Chat-visible storage-rec diagnostic + forced rescan (always prints; does not require debug mode).
--- Usage: |cff00ccff/wn gearstash|r  or  |cff00ccff/wn gearstash 193707|r
---@param charKey string|nil canonical or storage key; defaults to gear tab selection / logged-in player
---@param probeItemID number|nil optional itemID to search in bags (e.g. Final Grade)
function WarbandNexus:DiagnoseGearStorageRecToChat(charKey, probeItemID)
    local U = ns.Utilities
    local function canon(k)
        if not k or k == "" then return nil end
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    if not charKey then
        if ns.GearUI and type(ns.GearUI) == "table" then
            -- GearUI keeps selection in closure; use storage key for logged-in player.
        end
        charKey = (self.GetCurrentGearStorageKey and self:GetCurrentGearStorageKey())
            or (U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(self))
    end
    if not charKey then
        self:Print("|cffff6600[WN gearstash]|r No character key (not logged in?).")
        return
    end
    local selCanon = canon(charKey) or charKey
    local loggedIn = IsViewingLivePlayerGear(selCanon)

    self:Print("|cff00ccff[WN gearstash]|r canon=" .. tostring(selCanon) .. " loggedIn=" .. tostring(loggedIn))
    local mhFloor = BuildGearStorageComparisonFloor(selCanon, 16, BuildEquippedIlvlMap(selCanon), nil)
    self:Print(string.format("  MH comparison floor ilvl=%s (empty MH uses avg equipped - %d)",
        tostring(mhFloor), GEAR_STORAGE_EMPTY_SLOT_FLOOR_MARGIN))

    local bagN, bankN, liveN, liveBankN = 0, 0, 0, 0
    local probeHits = 0
    if self.GetItemsData then
        local data = self:GetItemsData(selCanon)
        if data then
            bagN = data.bags and #data.bags or 0
            bankN = data.bank and #data.bank or 0
        end
    end
    if loggedIn then
        local liveBags, liveBank = CollectLivePlayerContainerItemsForGearScan()
        liveN = liveBags and #liveBags or 0
        liveBankN = liveBank and #liveBank or 0
        if probeItemID and liveBags then
            for i = 1, #liveBags do
                local it = liveBags[i]
                if it and tonumber(it.itemID) == tonumber(probeItemID) then
                    probeHits = probeHits + 1
                    local il = ResolveStorageItemIlvlWarm(it)
                    self:Print(string.format("  live bag: id=%s ilvl=%s link=%s",
                        tostring(it.itemID), tostring(il), tostring(it.itemLink and "yes" or "no")))
                end
            end
        end
        if probeItemID and bagN > 0 and self.GetItemsData then
            local data = self:GetItemsData(selCanon)
            for i = 1, #(data.bags or {}) do
                local it = data.bags[i]
                if it and tonumber(it.itemID) == tonumber(probeItemID) then
                    probeHits = probeHits + 1
                    local il = ResolveStorageItemIlvlWarm(it)
                    self:Print(string.format("  saved bag: id=%s ilvl=%s", tostring(it.itemID), tostring(il)))
                end
            end
        end
    end
    self:Print(string.format("  items: savedBags=%d savedBank=%d liveBags=%d liveBank=%d probeId=%s hits=%d",
        bagN, bankN, liveN, liveBankN, tostring(probeItemID), probeHits))

    self:InvalidateGearStorageFindingsCacheImmediate(selCanon)
    local findings = (self.FindGearStorageUpgrades and self:FindGearStorageUpgrades(selCanon)) or {}
    local slots, cands = GearStorageFindingsCount(findings)
    self:Print(string.format("  scan: slots=%d candidates=%d logicVer=%s",
        slots, cands, tostring(GEAR_STORAGE_FINDINGS_LOGIC_VER)))

    local sum = ns._gearStorageLastFindSummary
    if sum then
        self:Print(string.format("  rejects: stat=%s lvlRace=%s boeSoul=%s bindLbl=%s bind=%s added=%s",
            tostring(sum.stat), tostring(sum.lvlRace), tostring(sum.boeSoul),
            tostring(sum.bindLabel), tostring(sum.bind), tostring(sum.added)))
    end

    for si = 1, #GEAR_SLOTS do
        local slotDef = GEAR_SLOTS[si]
        local sid = slotDef.id
        local list = findings[sid]
        local best = list and list[1]
        if best then
            self:Print(string.format("  slot %s: %s -> ilvl %s (%s)",
                tostring(slotDef.label),
                tostring(best.equippedIlvlAtFind or "?"),
                tostring(best.itemLevel or 0),
                tostring(best.source or "?")))
        end
    end

    if WarbandNexus.IsStillOnTab and WarbandNexus:IsStillOnTab("gear") then
        RequestGearStorageRedraw(selCanon, ns._gearTabDrawGen or 0, true)
        self:Print("  UI redraw requested (gear tab visible).")
    else
        self:Print("  Open Gear tab after /wn gearstash to refresh the recommendations panel.")
    end
end

--- True when `charKey` is the logged-in player (live bag APIs are player-scoped).
---@param charKey string|nil
---@return boolean
function WarbandNexus:IsGearTabCharacterLoggedInPlayer(charKey)
    if not charKey then return false end
    local U = ns.Utilities
    local function canon(k)
        if not k or k == "" then return "" end
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    local sel = canon(charKey)
    if sel == "" then return false end
    local cur = ResolveGearStorageKey()
    if not cur and U and U.GetCharacterStorageKey then
        cur = U:GetCharacterStorageKey(WarbandNexus)
    end
    if not cur then return false end
    return sel == canon(cur)
end

--- Find items in storage (all chars' bags/bank, warband bank, guild bank cache, plus other chars' equipped warbound)
--- upgrade any equipped slot for the selected character.
---@param selectedCharKey string
---@return table findings { [slotID] = { {itemID, itemLink, itemLevel, quality, source, sourceType, isBound}, ... } }
function WarbandNexus:FindGearStorageUpgrades(selectedCharKey)
    local findings = {}
    if WarbandNexus.IsGearStorageRecommendationsEnabled
        and not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        WarbandNexus:GearStoragePanelDebug("Find skip (stash recommendations disabled)")
        return findings
    end
    if not selectedCharKey then
        WarbandNexus:GearStoragePanelDebug("Find skip (no selectedCharKey)")
        return findings
    end

    local function dbg(msg)
        WarbandNexus:GearStorageTrace(msg)
    end

    local getCanonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and function(k) return ns.Utilities:GetCanonicalCharacterKey(k) end or function(k) return k end
    local canonKey = getCanonicalKey(selectedCharKey) or selectedCharKey
    local equippedMap = BuildEquippedIlvlMap(selectedCharKey)
    local invEpoch = ns._gearStorageInvGen or 0
    local equipSig = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMap)
    do
        local c = gearStorageFindingsCache
        if c.canonKey == canonKey and c.invEpoch == invEpoch and c.equipSig == equipSig and c.findings
            and (c.logicVer or 0) == GEAR_STORAGE_FINDINGS_LOGIC_VER then
            local fs, fc = GearStorageFindingsCount(c.findings)
            WarbandNexus:GearStoragePanelDebug(("Find CACHE HIT canon=%s invEpoch=%s findingsSlots=%d candidates=%d (no full scan)")
                :format(tostring(canonKey), tostring(invEpoch), fs, fc))
            WarbandNexus:GearStorageTrace("Find cache hit canon=" .. tostring(canonKey)
                .. " invEpoch=" .. tostring(invEpoch))
            return c.findings
        end
    end

    local findingsScanDirtyStart = ns._gearStorageFindingsDirtyToken or 0
    WarbandNexus:GearStorageTrace("Find full scan start canon=" .. tostring(canonKey)
        .. " invEpoch=" .. tostring(invEpoch) .. " dirtyTok=" .. tostring(findingsScanDirtyStart))
    do
        local nEq = 0
        for _ in pairs(equippedMap) do nEq = nEq + 1 end
        local esl = (type(equipSig) == "string") and #equipSig or 0
        WarbandNexus:GearStoragePanelDebug(("Find SCAN START canon=%s invEpoch=%s equippedIlvlSlots=%d equipSigLen=%d dirtyTok=%s")
            :format(tostring(canonKey), tostring(invEpoch), nEq, esl, tostring(findingsScanDirtyStart)))
    end

    -- Build itemID lookup for paired slots (rings 11/12, trinkets 13/14) so we can
    -- suppress duplicate-equip recommendations: if the same itemID is already worn
    -- in the partner slot, recommending it for the other slot would either be a
    -- false positive (same instance) or a unique-equip conflict (most trinkets and
    -- legendary-style rings carry the unique flag).
    local equippedItemIDBySlot = {}
    do
        local pairedSlots = { 11, 12, 13, 14 }
        for si = 1, #pairedSlots do
            local slotID = pairedSlots[si]
            local iid = nil
            if selectedIsLoggedInPlayer and GetInventoryItemLink then
                local link = GetInventoryItemLink("player", slotID)
                if link and not (issecretvalue and issecretvalue(link)) then
                    pcall(function()
                        if C_Item and C_Item.GetItemInfoInstant then
                            iid = C_Item.GetItemInfoInstant(link)
                        end
                    end)
                    if not iid and type(link) == "string" then
                        local idFromLink = link:match("item:(%d+)")
                        iid = idFromLink and tonumber(idFromLink) or nil
                    end
                end
            else
                local equippedGear = self:GetEquippedGear(selectedCharKey)
                local s = equippedGear and equippedGear.slots and equippedGear.slots[slotID]
                if s and s.itemID then
                    iid = tonumber(s.itemID)
                end
            end
            if iid then
                equippedItemIDBySlot[slotID] = iid
            end
        end
    end
    local PARTNER_SLOT = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

    -- If the main hand currently holds a two-handed weapon, the off-hand slot
    -- is logically occupied (cannot equip an off-hand without dropping the 2H).
    -- Suppress any off-hand recommendations so we don't surface a low-ilvl
    -- "upgrade" against an empty slot 17.
    local mainHandIs2H = false
    do
        local mhEquipLoc = ""
        if selectedIsLoggedInPlayer and GetInventoryItemLink then
            local mhLink = GetInventoryItemLink("player", 16)
            if mhLink and not (issecretvalue and issecretvalue(mhLink)) then
                mhEquipLoc = GetEquipLoc(mhLink) or ""
            end
        else
            local equippedGear = self:GetEquippedGear(selectedCharKey)
            local mh = equippedGear and equippedGear.slots and equippedGear.slots[16]
            mhEquipLoc = mh and mh.equipLoc or ""
            if mhEquipLoc == "" and mh and mh.itemLink then
                local ok, loc = pcall(GetEquipLoc, mh.itemLink)
                if ok then mhEquipLoc = loc or "" end
            end
        end
        if mhEquipLoc == "INVTYPE_2HWEAPON" or mhEquipLoc == "INVTYPE_RANGED" or mhEquipLoc == "INVTYPE_RANGEDRIGHT" then
            mainHandIs2H = true
        end
    end

    local allChars = self.db and self.db.global and self.db.global.characters
    -- Resolve DB row by canonical key: `characters` may be keyed by GUID or Name-Realm while callers pass the other form.
    local selCanon = getCanonicalKey(selectedCharKey) or selectedCharKey
    local charData = allChars and (allChars[selectedCharKey] or allChars[selCanon])
    if not charData and allChars then
        for k, data in pairs(allChars) do
            if (getCanonicalKey(k) or k) == selCanon then
                charData = data
                break
            end
        end
    end

    local currentKey = ResolveGearStorageKey()
    if not currentKey and ns.Utilities and ns.Utilities.GetCharacterStorageKey then
        currentKey = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    end
    local selectedIsLoggedInPlayer = IsViewingLivePlayerGear(selectedCharKey)

    local mainStat, mainStatSource = ResolveExpectedPrimaryStatFromCharacter(charData, selectedIsLoggedInPlayer)

    dbg(string.format(
        "=== Scan %s | class=%s spec=%s | mainStat=%s (%s) | loggedIn=%s ===",
        tostring(selectedCharKey),
        tostring(charData and charData.classFile),
        tostring(charData and charData.specID),
        tostring(mainStat),
        tostring(mainStatSource),
        tostring(selectedIsLoggedInPlayer)
    ))

    local addedCount = 0
    local rejectCounts = { stat = 0, lvlRace = 0, boeSoul = 0, bindLabel = 0, bind = 0 }

    local function ResolveSourceClassFile(ownerKey)
        if not ownerKey or not allChars then return nil end
        local d = allChars[ownerKey]
        if d and d.classFile then return d.classFile end
        local want = getCanonicalKey(ownerKey) or ownerKey
        for k, v in pairs(allChars) do
            if v and v.classFile then
                local nk = getCanonicalKey(k) or k
                if nk == want then return v.classFile end
            end
        end
        return nil
    end

    local function SelectedCharacterMeetsItemRequirements(itemLink, itemID, ownStorage)
        if ownStorage and selectedIsLoggedInPlayer then
            return true
        end
        local minLvl = GetItemMinLevelFromItemInfo(itemLink) or GetItemMinLevelFromItemInfo(itemID)
        local charLvl = charData and tonumber(charData.level)
        if selectedIsLoggedInPlayer and UnitLevel then
            local liveLvl = UnitLevel("player")
            if type(liveLvl) == "number" and liveLvl > 0 then
                charLvl = liveLvl
            end
        end
        if selectedIsLoggedInPlayer and minLvl and charLvl and charLvl < minLvl then
            return false
        end
        if selectedIsLoggedInPlayer and itemLink and type(itemLink) == "string"
            and not (issecretvalue and issecretvalue(itemLink)) then
            if C_Item and C_Item.IsDressableItemByRace then
                local okR, dress = pcall(C_Item.IsDressableItemByRace, itemLink)
                if okR and dress == false then return false end
            end
            if C_Item and C_Item.IsDressableItemByClass then
                local okC, dressC = pcall(C_Item.IsDressableItemByClass, itemLink)
                if okC and dressC == false then return false end
            end
        end
        return true
    end

    local function AddCandidate(slotID, candidate)
        if not findings[slotID] then findings[slotID] = {} end
        local link = candidate.itemLink or candidate.link
        local warmIlvl = tonumber(candidate.itemLevel) or 0
        if link then
            candidate.itemLevel = ResolveStorageItemIlvl({
                itemID = candidate.itemID,
                itemLink = link,
                link = link,
                actualBagID = candidate.actualBagID,
                bagID = candidate.bagID,
                slotIndex = candidate.slotIndex,
                slot = candidate.slot,
            }) or warmIlvl
            if (candidate.itemLevel or 0) == 0 and warmIlvl > 0 then
                candidate.itemLevel = warmIlvl
            end
            local minL = GetItemMinLevelFromItemInfo(link) or GetItemMinLevelFromItemInfo(candidate.itemID)
            if minL then candidate.requiredLevel = minL end
        end
        if (candidate.itemLevel or 0) == 0 then return end
        -- Snapshot for UI row filter: Find can run against slightly older gearData than RedrawGearStorageRecommendationsOnly.
        candidate.equippedIlvlAtFind = BuildGearStorageComparisonFloor(selectedCharKey, slotID, equippedMap, charData)
        for i = 1, #findings[slotID] do
            local ex = findings[slotID][i]
            if ex.itemLink == candidate.itemLink and ex.source == candidate.source then return end
        end
        findings[slotID][#findings[slotID] + 1] = candidate
        addedCount = addedCount + 1
    end

    local function EvaluateItem(item, sourceCharKey, storageType, evalOpts)
        evalOpts = evalOpts or {}
        if not item or not item.itemID then return false end
        local anyAdded = false
        -- When RunFindGearStorageUpgradesYielded drives this scan, yield so one frame never evaluates thousands of items.
        if ns._gearStorageYieldCo then
            ns._gearStorageYieldCounter = (ns._gearStorageYieldCounter or 0) + 1
            if ns._gearStorageYieldCounter >= GEAR_STORAGE_EVAL_ITEMS_PER_YIELD then
                ns._gearStorageYieldCounter = 0
                coroutine.yield()
            end
        end

        local linkEarly = item.itemLink or item.link
        if IsCosmeticGearCandidate(item.itemID, linkEarly) then return false end

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
        if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then return false end

        local targetSlots = EQUIP_LOC_TO_SLOTS[equipLoc]
        if not targetSlots then return false end

        local ilvl = ResolveStorageItemIlvlWarm(item)
        if ilvl == 0 then return false end

        -- Only Uncommon (2) and above; hide Poor (0) and Common (1)
        local quality = item.quality
        if quality == nil or quality == 0 then
            local q = (item.itemLink or item.link) and GetItemQuality(item.itemLink or item.link) or nil
            quality = (q ~= nil) and q or 0
        end
        if (quality or 0) < 2 then return false end

        local link = item.itemLink or item.link

        for i = 1, #targetSlots do
            local slotID = targetSlots[i]
            local partner = PARTNER_SLOT[slotID]
            local sameItemInPartner = partner and equippedItemIDBySlot[partner] == tonumber(item.itemID)
            if slotID == 17 and mainHandIs2H then
                -- Off-hand suppressed because main hand holds a two-handed weapon.
            elseif sameItemInPartner then
                -- Partner slot already wears this exact itemID (rings/trinkets pair) —
                -- recommending it for the other slot would be a duplicate / unique-equip
                -- conflict. Skip silently for this slot only; the candidate may still be
                -- valid for the partner slot itself (handled in another iteration).
            else
            local isArmorOK = IsArmorCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc)
            local isWeaponOK = IsWeaponCompatible(charData, slotID, itemClassID, itemSubclassID, equipLoc, mainStat)
            local ownStorage = IsSelectedCharacterOwnStorage(
                sourceCharKey, selectedCharKey, storageType, getCanonicalKey, evalOpts.forceOwnStorage == true)
            local isStatOK = MatchGetItemStatsPrimariesToExpected(link, mainStat, slotID, selectedIsLoggedInPlayer, item.itemID)
            if ownStorage then
                isStatOK = true
            end

            if not isArmorOK then
                -- silent
            elseif not isWeaponOK then
                -- silent
            elseif not isStatOK then
                rejectCounts.stat = rejectCounts.stat + 1
            elseif not SelectedCharacterMeetsItemRequirements(link, item.itemID, ownStorage) then
                rejectCounts.lvlRace = rejectCounts.lvlRace + 1
            else
                local currentIlvl = BuildGearStorageComparisonFloor(selectedCharKey, slotID, equippedMap, charData)
                if ilvl > currentIlvl then
                    if ownStorage then
                        local ownLabel, ownType = OwnStorageSourceLabels(storageType)
                        AddCandidate(slotID, {
                            itemID     = item.itemID,
                            itemLink   = link,
                            itemLevel  = ilvl,
                            quality    = item.quality or 0,
                            source     = ownLabel,
                            sourceType = ownType,
                            isBound    = item.isBound,
                            equipLoc   = equipLoc,
                            sourceClassFile = ResolveSourceClassFile(sourceCharKey),
                            actualBagID = item.actualBagID or item.bagID,
                            bagID = item.bagID,
                            slotIndex = item.slotIndex or item.slot,
                            slot = item.slot,
                        })
                        anyAdded = true
                    else
                        local source, sourceType = ResolveSourceLabel(item, sourceCharKey, selectedCharKey, storageType)
                        if source and sourceType == "boe" and item.isBound == true then
                            rejectCounts.boeSoul = rejectCounts.boeSoul + 1
                        elseif source and not IsAllowedStorageRecommendationBindLabel(sourceType) then
                            rejectCounts.bindLabel = rejectCounts.bindLabel + 1
                        elseif source then
                            AddCandidate(slotID, {
                                itemID     = item.itemID,
                                itemLink   = link,
                                itemLevel  = ilvl,
                                quality    = item.quality or 0,
                                source     = source,
                                sourceType = sourceType,
                                isBound    = item.isBound,
                                equipLoc   = equipLoc,
                                sourceClassFile = ResolveSourceClassFile(sourceCharKey),
                                actualBagID = item.actualBagID or item.bagID,
                                bagID = item.bagID,
                                slotIndex = item.slotIndex or item.slot,
                                slot = item.slot,
                            })
                            anyAdded = true
                        else
                            rejectCounts.bind = rejectCounts.bind + 1
                        end
                    end
                end
            end
            end
        end
        return anyAdded
    end

    local function EvaluateItemList(items, ownerKey, storageType, seen, evalOpts)
        if not items then return end
        for j = 1, #items do
            if ns._gearStorageYieldCo and (j % GEAR_STORAGE_EVAL_ITEMS_PER_YIELD == 0) then
                coroutine.yield()
            end
            local it = items[j]
            if not it then
                -- skip
            else
                local dk = GearItemEvalSeenKey(it)
                if seen and seen[dk] then
                    -- skip duplicate (same bag slot or same link already evaluated with known ilvl)
                else
                    local added = EvaluateItem(it, ownerKey, storageType, evalOpts)
                    if seen and added then
                        seen[dk] = true
                    end
                end
            end
        end
    end

    -- ── Warband Bank ──────────────────────────────────────────────────────────
    local wbData = (WarbandNexus.GetWarbandBankData and WarbandNexus:GetWarbandBankData()) or nil
    if wbData and wbData.items then
        for i = 1, #wbData.items do
            if ns._gearStorageYieldCo and (i % GEAR_STORAGE_WARBANK_ITEMS_PER_YIELD == 0) then
                coroutine.yield()
            end
            local item = wbData.items[i]
            EvaluateItem(item, nil, "warband")
        end
    end

    -- ── All characters + every itemStorage key (bags + bank) ──────────────────
    -- Include orphan keys: bag data can exist under a key not present in `characters` (legacy/realm).
    do
        local itemStorage = self.db and self.db.global and self.db.global.itemStorage or nil
        local repKeyByCanon = {}
        local scanOrder = {}

        if allChars then
            for charKey, _ in pairs(allChars) do
                local c = getCanonicalKey(charKey) or charKey
                if c and not repKeyByCanon[c] then
                    repKeyByCanon[c] = charKey
                    scanOrder[#scanOrder + 1] = c
                end
            end
        end
        if itemStorage then
            for storageKey, _ in pairs(itemStorage) do
                if storageKey ~= "warbandBank" then
                    local c = getCanonicalKey(storageKey) or storageKey
                    if c and not repKeyByCanon[c] then
                        repKeyByCanon[c] = storageKey
                        scanOrder[#scanOrder + 1] = c
                    end
                end
            end
        end

        local function getItemsForCharacter(canonicalChar, charKey)
            local data = (WarbandNexus.GetItemsData and WarbandNexus:GetItemsData(canonicalChar)) or nil
            if data and ((data.bags and #data.bags > 0) or (data.bank and #data.bank > 0)) then
                return data
            end
            if charKey and charKey ~= canonicalChar then
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

        local selCanonScan = getCanonicalKey(selectedCharKey) or selectedCharKey
        local ownEvalOpts = { forceOwnStorage = true }
        local seenOwnGlobal = {}

        -- Phase A: selected character own bags/bank FIRST (soulbound/BoE/warbound — never cross-char bind rules).
        do
            local repKeySel = repKeyByCanon[selCanonScan] or selCanonScan
            local itemsDataSel = getItemsForCharacter(selCanonScan, repKeySel)
            if selectedIsLoggedInPlayer then
                if itemsDataSel and itemsDataSel.bags and #itemsDataSel.bags > 0 then
                    EvaluateItemList(itemsDataSel.bags, selCanonScan, "bag", seenOwnGlobal, ownEvalOpts)
                end
                if itemsDataSel and not WarbandNexus.bankIsOpen and itemsDataSel.bank and #itemsDataSel.bank > 0 then
                    EvaluateItemList(itemsDataSel.bank, selCanonScan, "bank", seenOwnGlobal, ownEvalOpts)
                end
                local liveBags, liveBank = CollectLivePlayerContainerItemsForGearScan()
                EvaluateItemList(liveBags, selCanonScan, "bag", seenOwnGlobal, ownEvalOpts)
                EvaluateItemList(liveBank, selCanonScan, "bank", seenOwnGlobal, ownEvalOpts)
                dbg(string.format(
                    "Containers(own): persistedBags=%d liveBags=%d liveBank=%d loggedIn=%s",
                    itemsDataSel and itemsDataSel.bags and #itemsDataSel.bags or 0,
                    #liveBags,
                    #liveBank,
                    tostring(selectedIsLoggedInPlayer)
                ))
            elseif itemsDataSel then
                if itemsDataSel.bags and #itemsDataSel.bags > 0 then
                    EvaluateItemList(itemsDataSel.bags, selCanonScan, "bag", seenOwnGlobal, ownEvalOpts)
                end
                if itemsDataSel.bank and #itemsDataSel.bank > 0 then
                    EvaluateItemList(itemsDataSel.bank, selCanonScan, "bank", seenOwnGlobal, ownEvalOpts)
                end
            end
        end

        for i = 1, #scanOrder do
            if ns._gearStorageYieldCo and (i % 2 == 0) then
                coroutine.yield()
            end
            local canonicalChar = scanOrder[i]
            if canonicalChar == selCanonScan then
                -- Own storage already handled in Phase A.
            else
                local charKey = repKeyByCanon[canonicalChar] or canonicalChar
                local itemsData = getItemsForCharacter(canonicalChar, charKey)
                if itemsData then
                    local ownerKey = charKey
                    local bags = itemsData.bags or {}
                    for j = 1, #bags do
                        EvaluateItem(bags[j], ownerKey, "bag")
                    end
                    local bank = itemsData.bank or {}
                    for j = 1, #bank do
                        EvaluateItem(bank[j], ownerKey, "bank")
                    end
                end
            end
        end

        local guildItems = (WarbandNexus.GetGuildBankItems and WarbandNexus:GetGuildBankItems()) or {}
        for gi = 1, #guildItems do
            if ns._gearStorageYieldCo and (gi % GEAR_STORAGE_WARBANK_ITEMS_PER_YIELD == 0) then
                coroutine.yield()
            end
            EvaluateItem(guildItems[gi], selectedCharKey, "guild")
        end

        -- Logged-in player: re-touch bag rows that were skipped at ilvl 0 (cold client cache during long scans).
        if selectedIsLoggedInPlayer then
            local repKey = repKeyByCanon[selCanonScan] or selCanonScan
            local itemsDataRetry = getItemsForCharacter(selCanonScan, repKey)
            local function retryOwnStorageList(list, storageType)
                if not list then return end
                for j = 1, #list do
                    if ns._gearStorageYieldCo and (j % GEAR_STORAGE_EVAL_ITEMS_PER_YIELD == 0) then
                        coroutine.yield()
                    end
                    local it = list[j]
                    if it and it.itemID then
                        local il = tonumber(it.itemLevel) or ResolveStorageItemIlvlWarm(it)
                        if il == 0 then
                            if C_Item and C_Item.RequestLoadItemDataByID then
                                pcall(C_Item.RequestLoadItemDataByID, it.itemID)
                            end
                            il = ResolveStorageItemIlvlWarm(it)
                        end
                        if il > 0 then
                            EvaluateItem(it, selCanonScan, storageType, { forceOwnStorage = true })
                        end
                    end
                end
            end
            if itemsDataRetry then
                retryOwnStorageList(itemsDataRetry.bags, "bag")
                if not WarbandNexus.bankIsOpen then
                    retryOwnStorageList(itemsDataRetry.bank, "bank")
                end
            end
            local liveBagsRetry, liveBankRetry = CollectLivePlayerContainerItemsForGearScan()
            retryOwnStorageList(liveBagsRetry, "bag")
            retryOwnStorageList(liveBankRetry, "bank")
        end
    end

    -- ── Other characters' EQUIPPED gear (BoE/Warbound only — transferable) ─────
    -- So we show e.g. "Superluminal (equipped): 220 head" when viewing Astralumina.
    local selectedNorm = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(selectedCharKey) or selectedCharKey
    if allChars and selectedNorm and (WarbandNexus.GetEquippedGear) then
        local _equippedOtherYield = 0
        for otherCharKey, otherCharData in pairs(allChars) do
            if ns._gearStorageYieldCo then
                _equippedOtherYield = _equippedOtherYield + 1
                if _equippedOtherYield % GEAR_STORAGE_CHAR_LOOP_EVERY == 0 then
                    coroutine.yield()
                end
            end
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
                local _partner = PARTNER_SLOT[slotID]
                local _sameInPartner = slotData and slotData.itemID and _partner and equippedItemIDBySlot[_partner] == tonumber(slotData.itemID)
                if slotID == 17 and mainHandIs2H then
                    -- Off-hand suppressed (selected character wields a 2H weapon).
                elseif _sameInPartner then
                    -- Same itemID already equipped in the paired slot on the selected character.
                elseif slotData and slotData.itemID and (slotData.itemLink or slotData.itemLevel) then
                    if IsCosmeticGearCandidate(slotData.itemID, slotData.itemLink) then
                        -- skip cosmetic appearances worn by another character
                    else
                    local currentIlvl = ResolveEquippedIlvlForComparison(selectedCharKey, slotID, equippedMap)
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
                                -- Equipped items: BoE templates are now soulbound (cannot transfer)
                                -- and WuE templates have been "spent" by equipping (also locked).
                                -- Only persistent warband-bound items are still transferable.
                                if bindType == "warbound" then
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
                                        if not MatchGetItemStatsPrimariesToExpected(slotData.itemLink, mainStat, sid, selectedIsLoggedInPlayer, slotData.itemID) then ok = false break end
                                    end
                                    if ok and SelectedCharacterMeetsItemRequirements(slotData.itemLink, slotData.itemID) then
                                        AddCandidate(slotID, {
                                            itemID     = slotData.itemID,
                                            itemLink   = slotData.itemLink,
                                            itemLevel  = itemLevel,
                                            quality    = slotData.quality or 0,
                                            source     = otherName .. " (equipped)",
                                            sourceType = bindType,
                                            isBound    = true,
                                            equipLoc   = equipLoc,
                                            sourceClassFile = otherCharData and otherCharData.classFile or nil,
                                            requiredLevel = GetItemMinLevelFromItemInfo(slotData.itemLink)
                                                or GetItemMinLevelFromItemInfo(slotData.itemID),
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
    end

    local rSum = rejectCounts.stat + rejectCounts.lvlRace + rejectCounts.boeSoul + rejectCounts.bindLabel + rejectCounts.bind
    ns._gearStorageLastFindSummary = {
        stat = rejectCounts.stat,
        lvlRace = rejectCounts.lvlRace,
        boeSoul = rejectCounts.boeSoul,
        bindLabel = rejectCounts.bindLabel,
        bind = rejectCounts.bind,
        added = addedCount,
        canonKey = canonKey,
    }
    dbg(string.format(
        "  Reject/add: stat=%d lvlRace=%d boeSoul=%d bindLbl=%d bind=%d | added=%d",
        rejectCounts.stat,
        rejectCounts.lvlRace,
        rejectCounts.boeSoul,
        rejectCounts.bindLabel,
        rejectCounts.bind,
        addedCount
    ))

    local equippedMapCommit = BuildEquippedIlvlMap(selectedCharKey)
    for slotID, candidates in pairs(findings) do
        local floorIlvl = BuildGearStorageComparisonFloor(selectedCharKey, slotID, equippedMapCommit, charData)
        local i = 1
        while i <= #candidates do
            local cand = candidates[i]
            if (cand.itemLevel or 0) <= floorIlvl then
                table.remove(candidates, i)
            else
                cand.equippedIlvlAtFind = floorIlvl
                i = i + 1
            end
        end
        if #candidates == 0 then
            findings[slotID] = nil
        else
            table.sort(candidates, function(a, b) return (a.itemLevel or 0) > (b.itemLevel or 0) end)
            while #candidates > 5 do table.remove(candidates) end
        end
    end

    -- Recompute equipped signature at commit: yielded scans can span many frames while
    -- GetItemInfo warms equipped ilvls; a start-of-scan equipSig would mismatch the UI's
    -- post-scan GetGearStorageFindingsIfCached gate and force a redundant FULLFIND.
    if (ns._gearStorageFindingsDirtyToken or 0) ~= findingsScanDirtyStart then
        dbg("  Scan results not committed: storage cache invalidated mid-scan (equip/bag change).")
        WarbandNexus:GearStorageTrace("Find commit skipped (dirty mid-scan) canon=" .. tostring(canonKey)
            .. " dirtyStart=" .. tostring(findingsScanDirtyStart) .. " dirtyNow=" .. tostring(ns._gearStorageFindingsDirtyToken or 0))
        do
            local fs, fc = GearStorageFindingsCount(findings)
            WarbandNexus:GearStoragePanelDebug(("Find COMMIT SKIPPED (dirty mid-scan) canon=%s findingsSlots=%d candidates=%d added=%d")
                :format(tostring(canonKey), fs, fc, addedCount))
        end
        ns._gearStorageDeferInvalidateCanon = canonKey
        if gearStorageFindingsCache.canonKey == canonKey then
            gearStorageFindingsCache.findings = nil
            gearStorageFindingsCache.invEpoch = nil
        end
        return findings
    end
    local equipSigCommit = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMapCommit)
    gearStorageFindingsCache.canonKey = canonKey
    gearStorageFindingsCache.equipSig = equipSigCommit
    gearStorageFindingsCache.findings = findings
    gearStorageFindingsCache.logicVer = GEAR_STORAGE_FINDINGS_LOGIC_VER
    -- Align cache epoch to the latest scan generation. Item-info batches and metadata
    -- hooks can bump `ns._gearStorageInvGen` while a yielded Find runs; using only the
    -- epoch captured at scan start forces redundant FULLFIND in RedrawGearStorageRecommendationsOnly.
    gearStorageFindingsCache.invEpoch = ns._gearStorageInvGen or 0
    ns._gearStorageFindingsCleanToken = ns._gearStorageFindingsDirtyToken or 0

    WarbandNexus:GearStorageTrace("Find committed canon=" .. tostring(canonKey)
        .. " candidatesAdded=" .. tostring(addedCount) .. " invEpoch=" .. tostring(gearStorageFindingsCache.invEpoch))
    do
        local fs, fc = GearStorageFindingsCount(findings)
        WarbandNexus:GearStoragePanelDebug(("Find COMMIT OK canon=%s findingsSlots=%d candidates=%d added=%d rejectTotal=%d invEpoch=%s")
            :format(tostring(canonKey), fs, fc, addedCount, rSum, tostring(gearStorageFindingsCache.invEpoch)))
    end

    return findings
end

--- Run FindGearStorageUpgrades across multiple frames (coroutine + yields inside EvaluateItem / equipped loop).
--- @param canonicalKey string
--- @param paintGen number DrawGearTab generation; abort if stale.
--- @param onDone function Called when scan finished or aborted (still on gear / same gen).
function WarbandNexus:RunFindGearStorageUpgradesYielded(canonicalKey, paintGen, onDone)
    if WarbandNexus.IsGearStorageRecommendationsEnabled
        and not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        if type(onDone) == "function" then
            onDone()
        end
        return
    end
    if not canonicalKey or type(onDone) ~= "function" then
        if type(onDone) == "function" then
            onDone()
        end
        return
    end
    ns._gearStorageYieldFindCanon = canonicalKey
    WarbandNexus:GearStorageTrace("RunYield start canon=" .. tostring(canonicalKey) .. " paintGen=" .. tostring(paintGen))
    local co = coroutine.create(function()
        if WarbandNexus.FindGearStorageUpgrades then
            WarbandNexus:FindGearStorageUpgrades(canonicalKey)
        end
    end)
    ns._gearStorageYieldCo = co
    ns._gearStorageYieldCounter = 0

    local function abortYieldedFind(reason)
        -- A newer RunFindGearStorageUpgradesYielded may have replaced `_gearStorageYieldCo`; do not
        -- clear defer / findings state for the active scan (would orphan "Scanning storage…").
        if ns._gearStorageYieldCo ~= co then
            return
        end
        WarbandNexus:GearStorageTrace("RunYield abort: " .. tostring(reason))
        WarbandNexus:GearStoragePanelDebug("RunYield ABORT reason=" .. tostring(reason) .. " canon=" .. tostring(canonicalKey))
        -- `ScheduleGearStorageFindingsResolve` can append follow-up callbacks while this scan runs;
        -- the primary `onDone` is intentionally skipped on abort, so drain the queue here.
        local qlAbort = ns._gearStorageResolveQueuedDones
        if qlAbort and #qlAbort > 0 then
            ns._gearStorageResolveQueuedDones = nil
            for ai = 1, #qlAbort do
                local fnA = qlAbort[ai]
                if type(fnA) == "function" then
                    fnA()
                end
            end
        end
        local yieldCanon = ns._gearStorageYieldFindCanon
        ns._gearStorageYieldCo = nil
        ns._gearStorageYieldFindCanon = nil
        -- Stale scan must not leave UI.lua PopulateContent blocked on gear tab.
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        -- RedrawGearStorageRecommendationsOnly can set this and never clear it if the coroutine aborts mid-scan.
        if yieldCanon and ns._gearStorageRecFindPending then
            ns._gearStorageRecFindPending[yieldCanon] = nil
        end
        -- Stale scan: repaint storage panel only (full PopulateContent caused a visible "double refresh"
        -- after char switch + instant populate).
        local snapGen = paintGen
        local snapCanon = yieldCanon
        C_Timer.After(0, function()
            if snapGen ~= (ns._gearTabDrawGen or 0) then return end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
            if snapCanon then
                RequestGearStorageRedraw(snapCanon, snapGen, true)
            end
            if Constants and Constants.EVENTS and Constants.EVENTS.GEAR_TAB_VEIL_DISMISS then
                WarbandNexus:SendMessage(Constants.EVENTS.GEAR_TAB_VEIL_DISMISS, {
                    snapGen = snapGen,
                    clearDeferChain = true,
                })
            end
        end)
    end

    local P = ns.Profiler
    local _gearPumpProfOn = P and P.enabled and P.StartSlice and P.StopSlice

    local function pump()
        if paintGen ~= (ns._gearTabDrawGen or 0) then
            abortYieldedFind("stale paintGen")
            return
        end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
            abortYieldedFind("left gear tab")
            return
        end
        if ns._gearStorageYieldCo ~= co then
            return
        end
        if _gearPumpProfOn then P:StartSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
        local sliceStart = debugprofilestop()
        local resumes = 0
        while coroutine.status(co) ~= "dead" do
            if ns._gearStorageYieldCo ~= co then
                if _gearPumpProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
                return
            end
            resumes = resumes + 1
            if resumes > GEAR_STORAGE_PUMP_MAX_RESUMES then
                if _gearPumpProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
                C_Timer.After(0, pump)
                return
            end
            local ok, err = coroutine.resume(co)
            if not ok then
                if _gearPumpProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
                if ns._gearStorageYieldCo ~= co then
                    return
                end
                WarbandNexus:ReportGearStorageError(err, "yielded scan")
                abortYieldedFind("coroutine error")
                return
            end
            if (debugprofilestop() - sliceStart) >= GEAR_STORAGE_PUMP_BUDGET_MS then
                if _gearPumpProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
                C_Timer.After(0, pump)
                return
            end
        end
        if _gearPumpProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_pump") end
        if ns._gearStorageYieldCo ~= co then
            return
        end
        ns._gearStorageYieldCo = nil
        ns._gearStorageYieldFindCanon = nil
        do
            local U = ns.Utilities
            local ck = (U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(canonicalKey)) or canonicalKey
            ns._gearStorageLastYieldCompleteAt = ns._gearStorageLastYieldCompleteAt or {}
            ns._gearStorageLastYieldCompleteAt[ck] = GetTime()
        end
        WarbandNexus:GearStorageTrace("RunYield complete canon=" .. tostring(canonicalKey))
        WarbandNexus:GearStoragePanelDebug("RunYield COMPLETE canon=" .. tostring(canonicalKey) .. " paintGen=" .. tostring(paintGen))
        onDone()
    end

    C_Timer.After(0, pump)
end
