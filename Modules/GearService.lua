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
    Storage upgrade findings are cached per (character, equipped signature, inventory epoch);
    see FindGearStorageUpgrades, GetGearStorageFindingsIfCached (UI fast path), and ns._gearStorageInvGen bumps
    (real bag/bank/warband persistence edits in ItemsCacheService Save* paths; UI.lua CHARACTER_TRACKING_CHANGED;
    GET_ITEM_INFO when no cache to Invalidate). ITEM_METADATA_READY does not bump invGen (coalesced Invalidate on Gear).
    GET_ITEM_INFO coalesced batches prefer InvalidateGearStorageFindingsCacheForCanon (gear tab) over a blind invGen bump so strict cache is not dirtied without a storage edit.
    Post-yield redraw may use ns._gearStorageAllowEquipSigInvBypass (one frame) when invGen drifts
    without a real bag change (see GearUI applyStorageScanUI). Find commits cache with invEpoch
    refreshed to the current ns._gearStorageInvGen so item-info bumps during a yielded scan do not
    force a second synchronous Find. ns._gearStorageYieldFindCanon marks an in-flight yielded scan.
    Soft invalidate (InvalidateGearStorageFindingsCacheForCanon) bumps ns._gearStorageFindingsDirtyToken;
    Find commit sets ns._gearStorageFindingsCleanToken so GearUI can coalesce duplicate FULLFIND in
    the same GetTime() tick when dirty==clean, equipSig matches cache, and ns._gearStorageSameFrameFullFind matches.
    While ns._gearStorageYieldCo runs, invalidate/equip events defer to ns._gearStorageDeferInvalidateCanon /
    ns._gearStorageDeferEquipRefreshCanon and flush via OnGearStorageYieldedScanComplete (no mid-scan dirty abort).

    0-crest (gold-only) detection: C_ItemUpgrade cost APIs only return real costs when the
    Item Upgrade NPC window is open. We detect gold-only upgrades offline via persisted
    watermarks (per-slot max ilvl this character has ever had). Upgrades to ilvl <= watermark
    are treated as gold-only; no API cost query needed.

    WN_NONUI_UI: Transient DressUp/model preview frames constructed in this module are helpers only; Gear tab visuals live in Modules/UI/GearUI.lua.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local issecretvalue = issecretvalue
local wipe = table.wipe

local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter("|cff00BFFF[GearService]|r"))
    or ns.DebugPrint
    or function() end

--- Session-only traces (not persisted; default OFF): `SetGearStorageTrace` = yielded/cache pipeline;
--- `SetGearStoragePanelDebug` = verbose stash UI + Find outcome (Profiler trace only, not chat).
--- Not persisted; default OFF.
function WarbandNexus:SetGearStorageTrace(enabled)
    if enabled then
        ns.WN_GEAR_STORAGE_TRACE = true
    else
        ns.WN_GEAR_STORAGE_TRACE = nil
    end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN GearStorage] session trace " .. (enabled and "ON" or "OFF")
            .. " — lines go to |cff00ccff/wn profiler trace|r (not chat).")
    end
end

function WarbandNexus:GearStorageTrace(msg)
    if not ns.WN_GEAR_STORAGE_TRACE then return end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN GearStorage] " .. tostring(msg))
    end
end

--- Session-only: `/run WarbandNexus:SetGearStoragePanelDebug(true)` — stash panel + scan verbose (trace only).
--- Default OFF. Pair with `SetGearStorageTrace(true)` for full yielded-scan stepping.
function WarbandNexus:SetGearStoragePanelDebug(enabled)
    if enabled then
        ns.WN_GEAR_STORAGE_PANEL_DEBUG = true
    else
        ns.WN_GEAR_STORAGE_PANEL_DEBUG = nil
    end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN StashRec] panel debug " .. (enabled and "ON" or "OFF")
            .. " — use |cff00ccff/wn profiler trace|r to view.")
    end
end

--- Verbose stash-rec panel logging (controlled by `SetGearStoragePanelDebug`). Trace only.
---@param msg string|any
function WarbandNexus:GearStoragePanelDebug(msg)
    if not ns.WN_GEAR_STORAGE_PANEL_DEBUG then return end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN StashRec] " .. tostring(msg))
    end
end

--- Always visible (not gated by debugMode): coroutine / storage pipeline failures.
---@param err any
---@param context string|nil
function WarbandNexus:ReportGearStorageError(err, context)
    local ctx = (context and context ~= "") and context or "error"
    local msg = "Gear storage " .. ctx .. ": " .. tostring(err)
    print("|cffff4444[Warband Nexus]|r " .. msg)
    if geterrorhandler then
        geterrorhandler()(msg)
    end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN ERROR GearStorage] " .. msg)
    end
end

---@param canonKey string|nil
---@return boolean
function WarbandNexus:IsGearStorageScanInFlightForCanon(canonKey)
    if not canonKey or not ns._gearStorageYieldCo then return false end
    local flightCanon = ns._gearStorageYieldFindCanon
    if not flightCanon then return true end
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        canonKey = U:GetCanonicalCharacterKey(canonKey) or canonKey
        flightCanon = U:GetCanonicalCharacterKey(flightCanon) or flightCanon
    end
    return flightCanon == canonKey
end

--- Equip-only: refresh cache equipSig; never invalidate mid-yielded-scan (avoids dirty mid-scan commit drop).
---@param canonKey string|nil
function WarbandNexus:NotifyGearStorageEquipChanged(canonKey)
    if not canonKey then return end
    if WarbandNexus.IsGearStorageRecommendationsEnabled
        and not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        return
    end
    if self:IsGearStorageScanInFlightForCanon(canonKey) then
        ns._gearStorageDeferEquipRefreshCanon = canonKey
        WarbandNexus:GearStorageTrace("Equip refresh deferred (scan in flight) canon=" .. tostring(canonKey))
        return
    end
    if self.RefreshGearStorageCacheEquipSigForCanon then
        self:RefreshGearStorageCacheEquipSigForCanon(canonKey)
    end
end

--- Bag / item-info invalidation: defer while yielded Find runs for the same character.
---@param canonKey string|nil
---@return string|nil "rescan" when a follow-up yielded find was scheduled; nil otherwise
function WarbandNexus:ProcessDeferredGearStorageUpdates(canonKey)
    if not canonKey then return nil end
    local U = ns.Utilities
    local function norm(k)
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    local want = norm(canonKey)
    local deferInv = ns._gearStorageDeferInvalidateCanon
    local deferEquip = ns._gearStorageDeferEquipRefreshCanon
    ns._gearStorageDeferInvalidateCanon = nil
    ns._gearStorageDeferEquipRefreshCanon = nil
    if deferInv and norm(deferInv) ~= want then
        ns._gearStorageDeferInvalidateCanon = deferInv
    end
    if deferEquip and norm(deferEquip) ~= want then
        ns._gearStorageDeferEquipRefreshCanon = deferEquip
    end
    if deferInv and norm(deferInv) == want then
        self:InvalidateGearStorageFindingsCacheImmediate(want)
        return "rescan"
    end
    if deferEquip and norm(deferEquip) == want then
        if self.RefreshGearStorageCacheEquipSigForCanon then
            self:RefreshGearStorageCacheEquipSigForCanon(want)
        end
        return "equip_redraw"
    end
    return nil
end

--- After yielded Find completes: apply deferred equip/inventory work, optionally chain one rescan.
---@param canonKey string
---@param paintGen number
---@param afterFn function|nil
function WarbandNexus:OnGearStorageYieldedScanComplete(canonKey, paintGen, afterFn)
    local action = self:ProcessDeferredGearStorageUpdates(canonKey)
    local function runTail()
        if action == "equip_redraw" and self.RedrawGearStorageRecommendationsOnly then
            if paintGen == (ns._gearTabDrawGen or 0)
                and WarbandNexus.IsStillOnTab and WarbandNexus:IsStillOnTab("gear") then
                ns._gearStorageAllowEquipSigInvBypass = true
                self:RedrawGearStorageRecommendationsOnly(canonKey, paintGen, false)
                ns._gearStorageAllowEquipSigInvBypass = false
            end
        end
        if type(afterFn) == "function" then
            afterFn()
        end
    end
    if action == "rescan" and self.ScheduleGearStorageFindingsResolve then
        self:ScheduleGearStorageFindingsResolve(canonKey, paintGen, runTail)
    else
        runTail()
    end
end

local gearScanTimer = nil
local currencyGearScanTimer = nil
local gearWarmSnapshotSessionGen = 0

-- Session-only: hyperlink -> crafted probe result (avoids C_TooltipInfo.GetHyperlink every Gear draw).
local gearCraftedProbeCache = {}
local gearCraftedProbeCacheSize = 0
local GEAR_CRAFTED_PROBE_CACHE_CAP = 512

-- Session-only: canonical gear row key -> { lastScan = number, upgrades = table } for GetPersistedUpgradeInfo.
local persistedUpgradeInfoSessionCache = {}

-- Session-only: offline-view canonical key -> currency array from GetGearUpgradeCurrenciesFromDB (amounts follow Currency UI snapshot).
local gearUpgradeCurrencyOfflineCache = {}

--- Clears session caches used by Gear offline currency strip and upgrade reconstruction.
--- Keys are per canonical character; wiping on WN_CURRENCY_UPDATED / WN_CHARACTER_UPDATED avoids
--- stale amounts and keeps persisted upgrade inference aligned after scans (lastScan validation still applies).
local function InvalidateGearUpgradeCurrencyCaches()
    wipe(gearUpgradeCurrencyOfflineCache)
    wipe(persistedUpgradeInfoSessionCache)
end

-- Session-only: itemLink -> { hasStr, hasAgi, hasInt } or false (probed, no primary lines).
local gearPrimaryStatProbeCache = {}
local gearPrimaryStatProbeCacheSize = 0
local GEAR_PRIMARY_STAT_PROBE_CACHE_CAP = 768

local function CacheGearCraftedProbeResult(link, isCrafted)
    if not link or link == "" then return end
    if issecretvalue and issecretvalue(link) then return end
    if gearCraftedProbeCache[link] == nil then
        gearCraftedProbeCacheSize = gearCraftedProbeCacheSize + 1
    end
    gearCraftedProbeCache[link] = isCrafted and true or false
    if gearCraftedProbeCacheSize > GEAR_CRAFTED_PROBE_CACHE_CAP then
        wipe(gearCraftedProbeCache)
        gearCraftedProbeCacheSize = 0
        gearCraftedProbeCache[link] = isCrafted and true or false
        gearCraftedProbeCacheSize = 1
    end
end

-- ============================================================================
-- SLOT DEFINITIONS
-- ============================================================================

-- Left column, right column, bottom row — mirrors Blizzard paper doll order.
local GEAR_SLOTS = {
    { id = 1,  key = "head",      label = INVTYPE_HEAD,      col = "left"   },
    { id = 2,  key = "neck",      label = INVTYPE_NECK,      col = "left"   },
    { id = 3,  key = "shoulder",  label = INVTYPE_SHOULDER,  col = "left"   },
    { id = 15, key = "back",      label = INVTYPE_CLOAK,      col = "left"   },
    { id = 5,  key = "chest",     label = INVTYPE_CHEST,     col = "left"   },
    { id = 9,  key = "wrist",     label = INVTYPE_WRIST,     col = "left"   },
    { id = 10, key = "hands",     label = INVTYPE_HAND,     col = "right"  },
    { id = 6,  key = "waist",     label = INVTYPE_WAIST,     col = "right"  },
    { id = 7,  key = "legs",      label = INVTYPE_LEGS,      col = "right"  },
    { id = 8,  key = "feet",      label = INVTYPE_FEET,      col = "right"  },
    { id = 11, key = "ring1",     label = "Ring",      col = "right"  },
    { id = 12, key = "ring2",     label = "Ring",      col = "right"  },
    { id = 13, key = "trinket1",  label = "Trinket",   col = "bottom" },
    { id = 14, key = "trinket2",  label = "Trinket",   col = "bottom" },
    { id = 16, key = "mainhand",  label = INVTYPE_WEAPONMAINHAND, col = "bottom" },
    { id = 17, key = "offhand",   label = INVTYPE_WEAPONOFFHAND,  col = "bottom" },
}

local ITEM_CLASS_WEAPON = LE_ITEM_CLASS_WEAPON or 2
local ITEM_CLASS_ARMOR = LE_ITEM_CLASS_ARMOR or 4

-- Reverse map: slotID -> slot def (O(1) lookup)
local SLOT_BY_ID = {}
for i = 1, #GEAR_SLOTS do
    local s = GEAR_SLOTS[i]
    SLOT_BY_ID[s.id] = s
end

-- WoW uses shared "item redundancy" for rings, trinkets, and weapons: one watermark per group.
-- Ring 1/2, Trinket 1/2, and Main Hand/Off Hand all share their respective high watermark slot.
-- For paired slots, gold-only affordability must be capped by THIS item's ilvl — otherwise the
-- pair's higher ilvl makes upgrades look free when the upgrade NPC actually charges crests
-- (e.g. Off Hand at 285 falsely marks Main Hand 282→285 as gold-only).
local SLOT_PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }

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

-- Global specialization ID → primary stat for gear filtering (Midnight 12.x).
-- Storage-upgrade matching: ResolveExpectedPrimaryStatFromCharacter → expected STR/AGI/INT,
-- then compare to C_Item.GetItemStats / GetItemStats primary flags on the item link.
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
    -- Demon Hunter (Midnight): Devourer uses Intellect; Havoc/Vengeance remain Agility (TooltipService SPEC_ID_PRIMARY_KIND parity).
    [577] = "AGI", [581] = "AGI", [1456] = "AGI",
    [1480] = "INT", -- Devourer
}

local CLASS_FILE_TO_ID = Constants.CLASS_FILE_TO_CLASS_ID

--- Blizzard primaryStat / GetSpecPrimaryStat: 1=Str, 2=Agi, 4=Int (Stamina=3 is never a spec primary).
local function PrimaryStatEnumToMainStatCode(enum)
    if enum == nil or type(enum) ~= "number" then return nil end
    if enum == 1 then return "STR" end
    if enum == 2 then return "AGI" end
    if enum == 4 then return "INT" end
    if LE_UNIT_STAT_STRENGTH and enum == LE_UNIT_STAT_STRENGTH then return "STR" end
    if LE_UNIT_STAT_AGILITY and enum == LE_UNIT_STAT_AGILITY then return "AGI" end
    if LE_UNIT_STAT_INTELLECT and enum == LE_UNIT_STAT_INTELLECT then return "INT" end
    return nil
end

--- Prefer static SPEC_MAIN_STAT, then client API for unknown / new Midnight spec IDs.
local function ResolveMainStatFromSpecID(specID)
    if not specID or type(specID) ~= "number" then return nil end
    if SPEC_MAIN_STAT[specID] then
        return SPEC_MAIN_STAT[specID]
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecPrimaryStat then
        local ok, code = pcall(C_SpecializationInfo.GetSpecPrimaryStat, C_SpecializationInfo, specID)
        if not ok or code == nil then
            ok, code = pcall(C_SpecializationInfo.GetSpecPrimaryStat, specID)
        end
        if ok and code ~= nil then
            return PrimaryStatEnumToMainStatCode(code)
        end
    end
    return nil
end

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
                if resolvedSpecID then
                    local m = ResolveMainStatFromSpecID(resolvedSpecID)
                    if m then return m end
                end
            end
        end
        local m = ResolveMainStatFromSpecID(specID)
        if m then return m end
        -- Have a global spec ID but resolution failed (e.g. unknown API): do NOT substitute first class spec
        -- — that mislabels Midnight specs (e.g. DH Devourer 1480 vs Havoc 577).
        return nil
    end
    -- Legacy DB rows with no global spec ID: infer from the class's first specialization (e.g. Mage → Arcane → INT).
    if charData.classFile and GetSpecializationInfoForClassID then
        local classID = CLASS_FILE_TO_ID[charData.classFile]
        if classID then
            local firstSpecID = GetSpecializationInfoForClassID(classID, 1)
            if firstSpecID then
                local m = ResolveMainStatFromSpecID(firstSpecID)
                if m then return m end
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
    -- Midnight+: GetSpecializationInfo slot indices for "primary stat enum" drift across patches.
    -- Prefer global specID → SPEC_MAIN_STAT / C_SpecializationInfo.GetSpecPrimaryStat (same as offline GetCharacterMainStat).
    local specID = select(1, GetSpecializationInfo(specIndex))
    if specID and type(specID) == "number" and specID > 0 then
        local m = ResolveMainStatFromSpecID(specID)
        if m then return m end
    end
    local _, _, _, _, _, r6, r7 = GetSpecializationInfo(specIndex)
    return PrimaryStatEnumToMainStatCode(r6) or PrimaryStatEnumToMainStatCode(r7)
end

--- Expected primary stat for the *selected* character in Gear storage scan.
--- Uses SPEC_MAIN_STAT: live specialization when the selected row is the logged-in player (accurate respec),
--- otherwise saved charData.specID (with index→global ID resolution) or first spec for the class.
---@param charData table|nil db.global.characters[key]
---@param selectedIsLoggedInPlayer boolean
---@return string|nil "STR"|"AGI"|"INT"
---@return string source debug label
local function ResolveExpectedPrimaryStatFromCharacter(charData, selectedIsLoggedInPlayer)
    if selectedIsLoggedInPlayer and GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = select(1, GetSpecializationInfo(specIndex))
            local m = (specID and ResolveMainStatFromSpecID(specID)) or nil
            if not m then
                local _, _, _, _, _, r6, r7 = GetSpecializationInfo(specIndex)
                m = PrimaryStatEnumToMainStatCode(r6) or PrimaryStatEnumToMainStatCode(r7)
            end
            if m then
                return m, "live(specID=" .. tostring(specID) .. ")"
            end
        end
    end
    local fromDb = GetCharacterMainStat(charData)
    if fromDb then
        return fromDb, "db(specID=" .. tostring(charData and charData.specID) .. ")"
    end
    return nil, "none"
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

--- Tooltip line mentions a localized primary stat (not Requires/Use meta).
---@param lineText string
---@param statLabel string
---@return boolean
local function TooltipLineMentionsPrimaryStat(lineText, statLabel)
    if not lineText or statLabel == "" then return false end
    if issecretvalue and issecretvalue(lineText) then return false end
    if not lineText:find(statLabel, 1, true) then return false end
    if lineText:find("Requires", 1, true) then return false end
    if lineText:find("Durability", 1, true) then return false end
    if lineText:find("Use:", 1, true) or lineText:find("Equip:", 1, true) then return false end
    return true
end

--- Fallback when C_Item.GetItemStats / GetItemStats has no primary keys (cold SV links).
--- Wiki: https://warcraft.wiki.gg/wiki/API_C_TooltipInfo.GetHyperlink
---@param itemLink string|nil
---@param itemID number|nil
---@return boolean hasStr
---@return boolean hasAgi
---@return boolean hasInt
local function ProbeItemPrimaryStatsFromTooltip(itemLink, itemID)
    if not C_TooltipInfo then return false, false, false end
    local cacheKey = itemLink
    if cacheKey and not (issecretvalue and issecretvalue(cacheKey)) then
        local cached = gearPrimaryStatProbeCache[cacheKey]
        if cached == false then
            return false, false, false
        end
        if type(cached) == "table" then
            return cached[1], cached[2], cached[3]
        end
    end

    local tipData = nil
    if itemLink and not (issecretvalue and issecretvalue(itemLink)) and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and data and data.lines then tipData = data end
    end
    if not tipData and itemID and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and data and data.lines then tipData = data end
    end

    local strName = SPELL_STAT1_NAME or "Strength"
    local agiName = SPELL_STAT2_NAME or "Agility"
    local intName = SPELL_STAT4_NAME or "Intellect"
    local hasStr, hasAgi, hasInt = false, false, false

    if tipData and tipData.lines then
        for li = 1, #tipData.lines do
            local lt = tipData.lines[li] and tipData.lines[li].leftText
            if TooltipLineMentionsPrimaryStat(lt, strName) then hasStr = true end
            if TooltipLineMentionsPrimaryStat(lt, agiName) then hasAgi = true end
            if TooltipLineMentionsPrimaryStat(lt, intName) then hasInt = true end
        end
    end

    if cacheKey and not (issecretvalue and issecretvalue(cacheKey)) then
        if gearPrimaryStatProbeCache[cacheKey] == nil then
            gearPrimaryStatProbeCacheSize = gearPrimaryStatProbeCacheSize + 1
        end
        if not hasStr and not hasAgi and not hasInt then
            gearPrimaryStatProbeCache[cacheKey] = false
        else
            gearPrimaryStatProbeCache[cacheKey] = { hasStr, hasAgi, hasInt }
        end
        if gearPrimaryStatProbeCacheSize > GEAR_PRIMARY_STAT_PROBE_CACHE_CAP then
            wipe(gearPrimaryStatProbeCache)
            gearPrimaryStatProbeCacheSize = 0
            if not hasStr and not hasAgi and not hasInt then
                gearPrimaryStatProbeCache[cacheKey] = false
                gearPrimaryStatProbeCacheSize = 1
            else
                gearPrimaryStatProbeCache[cacheKey] = { hasStr, hasAgi, hasInt }
                gearPrimaryStatProbeCacheSize = 1
            end
        end
    end

    return hasStr, hasAgi, hasInt
end

--- C_Item.GetItemStats first; tooltip probe when stat table is missing or has no primary keys.
---@param itemLink string|nil
---@param itemID number|nil
---@return boolean hasStr
---@return boolean hasAgi
---@return boolean hasInt
local function ResolveItemPrimaryStatFlags(itemLink, itemID)
    local statTable = GetItemStatTableForLink(itemLink)
    if statTable then
        local hasStr, hasAgi, hasInt = TableHasPrimaryStats(statTable)
        if hasStr or hasAgi or hasInt then
            return hasStr, hasAgi, hasInt
        end
    end
    return ProbeItemPrimaryStatsFromTooltip(itemLink, itemID)
end

--- Match item primary stats to expectedMainStat for storage-upgrade filtering.
--- Wiki: API_C_Item.GetItemStats, API_C_TooltipInfo.GetHyperlink (see WN-VERSION-wiki-browser.mdc).
---@param expectedMainStat string|nil "STR"|"AGI"|"INT"
---@param selectedIsLoggedInPlayer boolean|nil
---@param itemID number|nil optional for tooltip fallback
local function MatchGetItemStatsPrimariesToExpected(itemLink, expectedMainStat, slotID, selectedIsLoggedInPlayer, itemID)
    if selectedIsLoggedInPlayer == nil then
        selectedIsLoggedInPlayer = true
    end
    if not itemLink and not itemID then return true end

    -- Offline roster: GetItemStats / tooltip can reflect the logged-in viewer, not the alt.
    if not selectedIsLoggedInPlayer then
        return true
    end

    local hasStr, hasAgi, hasInt = ResolveItemPrimaryStatFlags(itemLink, itemID)

    if hasStr and hasAgi and hasInt then
        return true
    end

    if not hasStr and not hasAgi and not hasInt then
        return true
    end

    if not expectedMainStat then
        return true
    end

    if expectedMainStat == "STR" then return hasStr end
    if expectedMainStat == "AGI" then return hasAgi end
    if expectedMainStat == "INT" then return hasInt end

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

--- Enum.ItemBind / LE_ITEM_BIND: "Bind to Warband" (TWW+). Not the same as legacy BNET/BOA.
---@type number
local ITEM_BIND_WARBAND = (type(LE_ITEM_BIND_WARBAND) == "number" and LE_ITEM_BIND_WARBAND)
    or (Enum and Enum.ItemBind and type(Enum.ItemBind.Warband) == "number" and Enum.ItemBind.Warband)
    or 8

--- 9 = ToBnetAccountUntilEquipped — "Warbound until equipped".
---@type number
local ITEM_BIND_BNET_UNTIL_EQUIPPED = (Enum and Enum.ItemBind and type(Enum.ItemBind.ToBnetAccountUntilEquipped) == "number" and Enum.ItemBind.ToBnetAccountUntilEquipped) or 9

--- 7 = ToWoWAccount (legacy bind-to-account); still transferable within account/warband scope for recommendations.
---@type number
local ITEM_BIND_TO_WOW_ACCOUNT = (Enum and Enum.ItemBind and type(Enum.ItemBind.ToWoWAccount) == "number" and Enum.ItemBind.ToWoWAccount) or 7

---@type number
local ITEM_BIND_ON_USE = (Enum and Enum.ItemBind and type(Enum.ItemBind.OnUse) == "number" and Enum.ItemBind.OnUse)
    or (type(LE_ITEM_BIND_ON_USE) == "number" and LE_ITEM_BIND_ON_USE)
    or 3

--- Read bindType (14th return) without relying on a long pcall multi-assign (pcall failure can mis-align locals).
---@param itemInfo number|string|nil itemID, link, or name
---@return number|nil bindType Enum.ItemBind numeric, or nil if not cached / error
local function GetRawItemBindTypeFromGetItemInfo(itemInfo)
    if not itemInfo or not C_Item or not C_Item.GetItemInfo then return nil end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14 = pcall(C_Item.GetItemInfo, itemInfo)
    if not ok or not r1 then return nil end
    if type(r14) ~= "number" then return nil end
    return r14
end

---@param item table|nil
---@return number|nil
local function GetRawItemBindType(item)
    if not item then return nil end
    local linkOrID = item.itemLink or item.link or item.itemID
    if not linkOrID then return nil end
    local bind = GetRawItemBindTypeFromGetItemInfo(linkOrID)
    if bind == nil and item.itemID and item.itemID ~= linkOrID then
        bind = GetRawItemBindTypeFromGetItemInfo(item.itemID)
    end
    if bind == nil and GetItemInfo then
        local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14 = pcall(GetItemInfo, linkOrID)
        if ok and r1 and type(r14) == "number" then
            bind = r14
        end
    end
    return bind
end

--- C_Item.GetItemInfo: 5th return is itemMinLevel (required character level).
---@param itemInfo number|string|nil
---@return number|nil
local function GetItemMinLevelFromItemInfo(itemInfo)
    if not itemInfo or not C_Item or not C_Item.GetItemInfo then return nil end
    local ok, _, _, _, minLvl = pcall(C_Item.GetItemInfo, itemInfo)
    if not ok or minLvl == nil then return nil end
    if issecretvalue and issecretvalue(minLvl) then return nil end
    if type(minLvl) ~= "number" or minLvl <= 0 then return nil end
    return minLvl
end

--- Map numeric Enum.ItemBind to storage-upgrade category (nil = not transferable template).
--- BoE = bind-on-equip only (not Bind on Use). Warbound-until-equipped is its own UI label.
---@param bindType number|nil
---@return string|nil "boe"|"warbound"|"warbound_until_equipped"
local function CategoryFromRawBind(bindType)
    if bindType == nil then return nil end
    if bindType == LE_ITEM_BIND_ON_EQUIP or bindType == 2 then
        return "boe"
    end
    if bindType == ITEM_BIND_BNET_UNTIL_EQUIPPED or bindType == 9 then
        return "warbound_until_equipped"
    end
    if bindType == LE_ITEM_BIND_TO_BNETACCOUNT or bindType == LE_ITEM_BIND_TO_ACCOUNT
        or bindType == ITEM_BIND_WARBAND or bindType == ITEM_BIND_TO_WOW_ACCOUNT then
        return "warbound"
    end
    return nil
end

--- Tooltip-based override for warband binding. In TWW Midnight, GetItemInfo's 14th
--- return ("bindType") reports WuE items as 2 (OnEquip) — the Warbound-until-Equipped
--- aspect lives on a separate item flag surfaced only in the tooltip text. Without
--- this scan, every WuE item is mislabelled "BoE" in the recommendation list.
---@param itemLink string|nil
---@param itemID number|nil
---@return string|nil "warbound_until_equipped"|"warbound"|nil
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

--- Returns the TEMPLATE bind type of an item (what the item *is*), not whether it's currently bound.
--- BoE items show "boe" even if isBound=true in a character's bag (they were bound on pickup/equip).
--- Tooltip scan takes precedence: WuE items report bindType=2 (OnEquip) via GetItemInfo,
--- so we must read the tooltip text to distinguish "BoE" from "Warbound until Equipped".
local function GetBindingType(item)
    if not item then return nil end
    local link = item.itemLink or item.link
    local tipCat = ScanTooltipForWarbandBind(link, item.itemID)
    if tipCat then return tipCat end
    return CategoryFromRawBind(GetRawItemBindType(item))
end

--- Transmog/cosmetic gear has valid equip slots + ilvl but is not an upgrade target here.
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

--- Item Upgrade / storage recommendations only surface own bags+bank or transferable BoE / warband binds.
local function IsAllowedStorageRecommendationBindLabel(sourceType)
    if sourceType == "self_bag" or sourceType == "self_bank" then
        return true
    end
    if sourceType == "boe" or sourceType == "warbound" or sourceType == "warbound_until_equipped" then
        return true
    end
    return false
end

local GEAR_DATA_VERSION = "1.1.0"

-- Login cold prefetch phase-2 (InitializationService): staged gear persist across C_Timer.After ticks.
local GEAR_WARM_SNAPSHOT_SLOTS_PER_TICK = 3
local GEAR_WARM_SNAPSHOT_MS_BUDGET = 6
local GEAR_WARM_SNAPSHOT_TICK_DELAY = 0.04

local WEAPON_ENCHANT_EQUIP_LOCS = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON = true,
}

---Midnight primary-enchant expectation by slot + equip location.
---@param slotID number
---@param equipLoc string|nil
---@return boolean
local function IsPrimaryEnchantExpected(slotID, equipLoc)
    local enchantableSlots = Constants and Constants.GEAR_ENCHANTABLE_SLOTS
    if not (enchantableSlots and enchantableSlots[slotID]) then
        return false
    end
    if slotID == 16 or slotID == 17 then
        return WEAPON_ENCHANT_EQUIP_LOCS[equipLoc or ""] == true
    end
    return true
end

--- UnitSex: 1 unknown, 2 male, 3 female. DressUpModel:SetCustomRace (when used) expects 0 = male, 1 = female.
---@param unitSex number|nil
---@return number 0|1
local function UnitSexToDressGender0Or1(unitSex)
    if unitSex == 3 then return 1 end
    return 0
end

---Capture a model snapshot for offline rendering.
---Player displayIDs are runtime handles into the active character's appearance bundle —
---they cannot be cached and replayed for an offline alt (replay → white mannequin, the
---bundle is gone after logout). Wowpedia: UIOBJECT_PlayerModel / API_C_PlayerInfo.GetDisplayID.
---
---Reliable replay path: capture race + sex + a serialised transmog list (per-slot
---ItemTransmogInfo). Offline render uses Actor:SetCustomRace + Actor:SetItemTransmogInfoList,
---which reproduces race body + equipped transmog (face/hair/skin customisations are not
---available outside the barber shop API, so those fall back to race defaults — accepted).
---@return table
local function BuildCharacterModelSnapshot()
    local uSex = UnitSex and UnitSex("player") or nil
    local snap = {
        lastUpdate = time(),
        raceID = UnitRace and select(3, UnitRace("player")) or nil,
        sex = uSex, -- raw UnitSex (2/3) for debugging/compat
        dressGender = UnitSexToDressGender0Or1(uSex),
    }

    -- Capture transmog list via a hidden DressUpModel: SetUnit + Dress reads the
    -- live worn appearance, GetItemTransmogInfoList returns 19 ItemTransmogInfo
    -- entries (per-slot appearanceID/secondaryAppearanceID/illusionID). We serialise
    -- raw fields because the mixin metatable can't survive SavedVariables.
    local ok, list = pcall(function()
        local m = CreateFrame("DressUpModel")
        m:SetUnit("player")
        if m.Dress then m:Dress() end
        if m.SetUseTransmogChoices then m:SetUseTransmogChoices(true) end
        if m.SetUseTransmogSkin then m:SetUseTransmogSkin(false) end
        local l = m.GetItemTransmogInfoList and m:GetItemTransmogInfoList() or nil
        m:Hide()
        m:SetParent(nil)
        return l
    end)
    if ok and type(list) == "table" then
        local serialised = {}
        for i = 1, #list do
            local t = list[i]
            if type(t) == "table" then
                serialised[i] = {
                    app = t.appearanceID or 0,
                    sec = t.secondaryAppearanceID or 0,
                    ill = t.illusionID or 0,
                }
            end
        end
        snap.transmogList = serialised
    end

    return snap
end

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

--- Same storage key as db.global.characters / GearUI GetSelectedCharKey (guid when available).
---@return string|nil
local function ResolveGearStorageKey()
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local k = ns.CharacterService:ResolveCharactersTableKey(WarbandNexus)
        if k and k ~= "" then return k end
    end
    local U = ns.Utilities
    if U and U.GetCharacterStorageKey then
        local k = U:GetCharacterStorageKey(WarbandNexus)
        if k and k ~= "" then return k end
    end
    return U and U:GetCharacterKey()
end

--- Logged-in player's gearData bucket (canonical storage key).
---@return string|nil
function WarbandNexus:GetCurrentGearStorageKey()
    return ResolveGearStorageKey()
end

--- Move pre-guid scans (Name-Realm) into the canonical bucket once.
---@param db table gearData root
---@param storageKey string
local function MigrateLegacyGearDataKey(db, storageKey)
    if not db or not storageKey then return end
    local U = ns.Utilities
    if not U or not U.GetCharacterKey then return end
    local legacy = U:GetCharacterKey()
    if not legacy or legacy == "" or legacy == storageKey or not db[legacy] then return end
    if not db[storageKey] then
        db[storageKey] = db[legacy]
    end
    db[legacy] = nil
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
        if trackName and issecretvalue and issecretvalue(trackName) then
            trackName = nil
        end
        if not trackName and info.customUpgradeString and info.customUpgradeString ~= "" then
            trackName = info.customUpgradeString
            if trackName and issecretvalue and issecretvalue(trackName) then
                trackName = nil
            end
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

--- Merge one equipped slot into working tables (live inventory). Mutates slots / watermarks / changedSlotIDs.
---@param slotID number
---@param baselineGearData table|nil Snapshot at scan start (reuse-fast-path + change detection).
local function ApplyEquippedGearSlotScan(slotID, baselineGearData, slots, watermarks, changedSlotIDs)
    local itemLink = GetInventoryItemLink("player", slotID)
    if itemLink and (issecretvalue and issecretvalue(itemLink)) then
        itemLink = nil
    end

    if itemLink then
        local itemID = nil
        pcall(function()
            if C_Item and C_Item.GetItemInfoInstant then
                itemID = C_Item.GetItemInfoInstant(itemLink)
            end
        end)
        if not itemID and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
            local idFromLink = itemLink:match("item:(%d+)")
            itemID = idFromLink and tonumber(idFromLink) or nil
        end

        if itemID or itemLink then
            -- Ring/trinket/weapon swaps only change 2 slots; the rest still ran GetItemStats +
            -- C_TooltipInfo.GetInventoryItem per slot (~15× heavy API in one frame → 200–400ms spikes).
            -- When the hyperlink is unchanged, reuse persisted slot analysis and only refresh ilvl/quality/name.
            local prevSlot = baselineGearData and baselineGearData.slots and baselineGearData.slots[slotID]
            local prevLinkSafe = prevSlot and prevSlot.itemLink
            local canReuseSlot = false
            if prevSlot and prevLinkSafe and itemLink
                and not (issecretvalue and issecretvalue(prevLinkSafe))
                and not (issecretvalue and issecretvalue(itemLink))
                and prevLinkSafe == itemLink
                and (prevSlot.upgradeTrack or prevSlot.notUpgradeable or prevSlot.isCrafted) then
                local idOk = (not itemID or not prevSlot.itemID or prevSlot.itemID == itemID)
                if idOk then
                    canReuseSlot = true
                end
            end

            if canReuseSlot then
                local slotEntry = {}
                for k, v in pairs(prevSlot) do
                    slotEntry[k] = v
                end
                local ilvl = GetEffectiveIlvl(itemLink) or slotEntry.itemLevel or 0
                slotEntry.itemLink = itemLink
                slotEntry.itemID = itemID or slotEntry.itemID
                slotEntry.itemLevel = ilvl
                slotEntry.quality = GetItemQuality(itemLink) or slotEntry.quality
                pcall(function()
                    if C_Item and C_Item.GetItemInfo then
                        local nm = C_Item.GetItemInfo(itemLink)
                        if nm then slotEntry.name = nm end
                    end
                end)
                slots[slotID] = slotEntry
                local prevWM = watermarks[slotID] or 0
                if ilvl > prevWM then
                    watermarks[slotID] = ilvl
                end
                pcall(function()
                    if C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkSlotForItem then
                        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
                        if location and location:IsValid() then
                            local hwSlot = C_ItemUpgrade.GetHighWatermarkSlotForItem(location)
                            if hwSlot and C_ItemUpgrade.GetHighWatermarkForSlot then
                                local charHW = C_ItemUpgrade.GetHighWatermarkForSlot(hwSlot)
                                local apiWM = (type(charHW) == "number") and charHW or 0
                                if not SLOT_PAIRS[slotID] and apiWM > (watermarks[slotID] or 0) then
                                    watermarks[slotID] = apiWM
                                end
                            end
                        end
                    end
                end)
            else
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

                local hasEnchant = false
                if type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
                    local enchantStr = string.match(itemLink, "item:%d+:(%d*)")
                    if enchantStr and enchantStr ~= "" and enchantStr ~= "0" then
                        hasEnchant = true
                    end
                end

                local isMissingGem = false
                local stats = GetItemStats and GetItemStats(itemLink) or {}
                for k, v in pairs(stats) do
                    if type(k) == "string" and string.find(k, "EMPTY_SOCKET_") then
                        isMissingGem = true
                        break
                    end
                end

                slotEntry.hasEnchant = hasEnchant
                slotEntry.isMissingGem = isMissingGem
                slotEntry.isEnchantable = IsPrimaryEnchantExpected(slotID, equipLoc)

                local tooltipInfo = ScanUpgradeFromTooltip(slotID)
                if tooltipInfo then
                    slotEntry.upgradeTrack = tooltipInfo.trackName
                    slotEntry.currUpgrade  = tooltipInfo.currUpgrade
                    slotEntry.maxUpgrade   = tooltipInfo.maxUpgrade
                    if tooltipInfo.isCrafted then
                        slotEntry.isCrafted = true
                    end
                end

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

                local prevWM = watermarks[slotID] or 0
                if ilvl > prevWM then
                    watermarks[slotID] = ilvl
                end

                pcall(function()
                    if C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkSlotForItem then
                        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
                        if location and location:IsValid() then
                            local hwSlot = C_ItemUpgrade.GetHighWatermarkSlotForItem(location)
                            if hwSlot and C_ItemUpgrade.GetHighWatermarkForSlot then
                                local charHW = C_ItemUpgrade.GetHighWatermarkForSlot(hwSlot)
                                local apiWM = (type(charHW) == "number") and charHW or 0
                                if not SLOT_PAIRS[slotID] and apiWM > (watermarks[slotID] or 0) then
                                    watermarks[slotID] = apiWM
                                end
                            end
                        end
                    end
                end)

                slots[slotID] = slotEntry
                local prev = baselineGearData and baselineGearData.slots and baselineGearData.slots[slotID]
                local prevLink = prev and prev.itemLink
                if prevLink ~= itemLink then
                    changedSlotIDs[#changedSlotIDs + 1] = slotID
                end
            end
        end
    else
        slots[slotID] = nil
        local prev = baselineGearData and baselineGearData.slots and baselineGearData.slots[slotID]
        if prev and prev.itemLink then
            changedSlotIDs[#changedSlotIDs + 1] = slotID
        end
    end
end

--- Persist scanned gear tables and optionally notify listeners.
---@param silent boolean|nil When true, skip GEAR_UPDATED (cold prefetch / background prime).
local function FinalizeEquippedGearPersist(charKey, slots, watermarks, baselineGearData, triggerSlotID, changedSlotIDs, silent)
    local preservedModelView = baselineGearData and baselineGearData.modelView
    local db = GetDB()
    if not db then return end

    db[charKey] = {
        version       = GEAR_DATA_VERSION,
        lastScan      = time(),
        slots         = slots,
        watermarks    = watermarks,
        modelSnapshot = BuildCharacterModelSnapshot(),
    }
    if type(preservedModelView) == "table" then
        db[charKey].modelView = preservedModelView
    end

    if silent then return end

    if Constants and Constants.EVENTS and Constants.EVENTS.GEAR_UPDATED then
        local expanded = {}
        local seen = {}
        local function addSid(sid)
            if not sid or type(sid) ~= "number" then return end
            sid = math.floor(sid)
            if sid < 1 or sid > 17 then return end
            if seen[sid] then return end
            seen[sid] = true
            expanded[#expanded + 1] = sid
            local partner = SLOT_PAIRS[sid]
            if partner and not seen[partner] then
                seen[partner] = true
                expanded[#expanded + 1] = partner
            end
        end
        for si = 1, #changedSlotIDs do
            addSid(changedSlotIDs[si])
        end
        if triggerSlotID and type(triggerSlotID) == "number" then
            addSid(triggerSlotID)
        end
        WarbandNexus:SendMessage(Constants.EVENTS.GEAR_UPDATED, { charKey = charKey, slotIDs = expanded })
    end
end

--- Scan all equipped item slots for the current player and persist to DB.
--- Called from SaveCurrentCharacterData and on PLAYER_EQUIPMENT_CHANGED.
---@param triggerSlotID number|nil PLAYER_EQUIPMENT_CHANGED slot (1-17); forwarded to UI for single-slot refresh.
---@param opts table|nil `{ silent = boolean }` — silent skips GEAR_UPDATED message.
function WarbandNexus:ScanEquippedGear(triggerSlotID, opts)
    opts = opts or {}
    local silent = opts.silent == true

    local db = GetDB()
    if not db then return end

    local charKey = ResolveGearStorageKey()
    if not charKey then return end
    MigrateLegacyGearDataKey(db, charKey)

    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end

    local baselineGearData = db[charKey]
    local slots = {}
    local watermarks = {}
    if baselineGearData and baselineGearData.watermarks then
        for k, v in pairs(baselineGearData.watermarks) do
            watermarks[k] = v
        end
    end
    local changedSlotIDs = {}

    for i = 1, #GEAR_SLOTS do
        local slotDef = GEAR_SLOTS[i]
        ApplyEquippedGearSlotScan(slotDef.id, baselineGearData, slots, watermarks, changedSlotIDs)
    end

    FinalizeEquippedGearPersist(charKey, slots, watermarks, baselineGearData, triggerSlotID, changedSlotIDs, silent)
end

--- Bounded staged persist prime after equipped metadata prefetch (login/reload).
--- Populates db.global.gearData for the logged-in character so GetPersistedUpgradeInfo / Gear first-open avoids a cold full-frame ScanEquippedGear.
--- Does not emit GEAR_UPDATED; aborts when PEW prefetch generation changes, session bumps, or another ScanEquippedGear refreshes gearData.
---@param coldPrefetchGen number InitializationService coldPrefetchGeneration captured at schedule time.
function WarbandNexus:WarmGearUpgradeSnapshotForSession(coldPrefetchGen)
    local InitSvc = ns.InitializationService
    if not InitSvc or not InitSvc.GetColdPrefetchGeneration then return end

    local mods = self.db and self.db.profile and self.db.profile.modulesEnabled
    if mods then
        if mods.items == false and mods.gear == false and mods.storage == false then
            return
        end
    end

    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end

    gearWarmSnapshotSessionGen = gearWarmSnapshotSessionGen + 1
    local warmSession = gearWarmSnapshotSessionGen

    local db = GetDB()
    if not db then return end

    local charKey = ResolveGearStorageKey()
    if not charKey then return end
    MigrateLegacyGearDataKey(db, charKey)

    local baselineGearData = db[charKey]
    local baselineLastScan = baselineGearData and baselineGearData.lastScan

    local slots = {}
    if baselineGearData and baselineGearData.slots then
        for sid, entry in pairs(baselineGearData.slots) do
            if type(entry) == "table" then
                local c = {}
                for k, v in pairs(entry) do
                    c[k] = v
                end
                slots[sid] = c
            end
        end
    end

    local watermarks = {}
    if baselineGearData and baselineGearData.watermarks then
        for k, v in pairs(baselineGearData.watermarks) do
            watermarks[k] = v
        end
    end

    local changedSlotIDs = {}
    local nextIdx = 1

    local function gearWarmStillBaseline()
        local live = db[charKey]
        local cur = live and live.lastScan
        return cur == baselineLastScan
    end

    local function tick()
        if warmSession ~= gearWarmSnapshotSessionGen then return end
        if coldPrefetchGen ~= InitSvc:GetColdPrefetchGeneration() then return end
        if not WarbandNexus.db or not WarbandNexus.db.global then return end
        if not gearWarmStillBaseline() then return end

        local t0 = debugprofilestop()
        local processedSlots = 0

        while nextIdx <= #GEAR_SLOTS do
            ApplyEquippedGearSlotScan(GEAR_SLOTS[nextIdx].id, baselineGearData, slots, watermarks, changedSlotIDs)
            nextIdx = nextIdx + 1
            processedSlots = processedSlots + 1

            if processedSlots >= GEAR_WARM_SNAPSHOT_SLOTS_PER_TICK then
                break
            end
            if (debugprofilestop() - t0) >= GEAR_WARM_SNAPSHOT_MS_BUDGET then
                break
            end
        end

        if warmSession ~= gearWarmSnapshotSessionGen then return end
        if coldPrefetchGen ~= InitSvc:GetColdPrefetchGeneration() then return end

        if nextIdx <= #GEAR_SLOTS then
            C_Timer.After(GEAR_WARM_SNAPSHOT_TICK_DELAY, tick)
            return
        end

        if not gearWarmStillBaseline() then return end

        FinalizeEquippedGearPersist(charKey, slots, watermarks, baselineGearData, nil, changedSlotIDs, true)
    end

    C_Timer.After(0, tick)
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
    -- Gear tab: refresh paperdoll icons from live inventory immediately; API links can lag one frame
    -- behind this event, so GearUI also retries on next ticks. Persisted scan stays debounced below.
    if WarbandNexus.TryRefreshGearEquipSlotsImmediate then
        WarbandNexus:TryRefreshGearEquipSlotsImmediate(slotID)
    end
    if gearScanTimer then
        gearScanTimer:Cancel()
    end
    local capSlot = slotID
    gearScanTimer = C_Timer.NewTimer(0.12, function()
        gearScanTimer = nil
        WarbandNexus:ScanEquippedGear(capSlot)
    end)
end

--- Get stored equipped gear for a tracked character.
--- Caller must pass canonical key (Utilities:GetCanonicalCharacterKey / GetCharacterKey).
---@param charKey string Canonical character key ("Name-Realm", normalized)
---@return table|nil { version, lastScan, slots = { [slotID] = { itemID, itemLink, itemLevel, quality, equipLoc, name } } }
function WarbandNexus:GetEquippedGear(charKey)
    local db = GetDB()
    if not db or not charKey then return nil end
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        charKey = U:GetCanonicalCharacterKey(charKey) or charKey
    end
    MigrateLegacyGearDataKey(db, charKey)
    if db[charKey] then return db[charKey] end
    -- Legacy: older builds wrote under Name-Realm while UI reads guid storage key.
    if U and U.GetCharacterKey then
        local legacy = U:GetCharacterKey()
        if legacy and legacy ~= charKey and db[legacy] then
            local canonLegacy = (U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(legacy)) or legacy
            if canonLegacy == charKey then
                return db[legacy]
            end
        end
    end
    return nil
end

--- Gear tab 3D paperdoll: persist rotation + zoom in SavedVariables (per character, with gearData).
---@param charKey string
---@param rotation number|nil facing radians (DressUpModel)
---@param zoom number|nil user zoom factor (same as m._zoom in GearUI)
function WarbandNexus:SaveGearModelViewState(charKey, rotation, zoom)
    if not charKey then return end
    if self.db and self.db.global and not self.db.global.gearData then
        self.db.global.gearData = {}
    end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    end
    local db = GetDB()
    if not db then return end
    local entry = db[charKey]
    if not entry then return end
    if not entry.modelView then entry.modelView = {} end
    entry.modelView.rotation = rotation
    entry.modelView.zoom = zoom
    entry.modelView.lastUpdate = time()
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
    local U = ns.Utilities
    local canon = charKey
    if U and U.GetCanonicalCharacterKey then
        canon = U:GetCanonicalCharacterKey(charKey) or charKey
    end

    local gearData = self:GetEquippedGear(canon)
    if not gearData or not gearData.slots then return upgrades end

    local ls = tonumber(gearData.lastScan) or 0
    local upCache = persistedUpgradeInfoSessionCache[canon]
    if upCache and upCache.lastScan == ls and upCache.upgrades then
        return upCache.upgrades
    end

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
        -- Scans the stored itemLink tooltip for "Crafted" quality text (once per link per session + cache).
        if not slot.isCrafted and trackName ~= "Crafted" and slot.itemLink then
            local link = slot.itemLink
            if issecretvalue and issecretvalue(link) then
                -- Cannot safely inspect; skip probe.
            else
                local cachedCrafted = gearCraftedProbeCache[link]
                if cachedCrafted == true then
                    slot.isCrafted = true
                elseif cachedCrafted == false then
                    slot.isCrafted = false
                else
                    local foundCrafted = false
                    local tipOk, tipData
                    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                        tipOk, tipData = pcall(C_TooltipInfo.GetHyperlink, link)
                    end
                    if tipOk and tipData and tipData.lines then
                        for li = 1, #tipData.lines do
                            local lt = tipData.lines[li] and tipData.lines[li].leftText
                            if lt and not (issecretvalue and issecretvalue(lt)) and lt:find("Crafted") then
                                slot.isCrafted = true
                                foundCrafted = true
                                break
                            end
                        end
                    end
                    if not foundCrafted then
                        slot.isCrafted = false
                    end
                    CacheGearCraftedProbeResult(link, foundCrafted)
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

    persistedUpgradeInfoSessionCache[canon] = { lastScan = ls, upgrades = upgrades }
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

local function CountCrestStepsRemaining(upInfo)
    if not upInfo or upInfo.isCrafted then return 0 end
    local curr = upInfo.currUpgrade or 0
    local maxT = upInfo.maxUpgrade or 0
    local wm = upInfo.watermarkIlvl or 0
    local tiers = TRACK_ILVLS and TRACK_ILVLS[upInfo.trackName]
    if not tiers then return 0 end
    local count = 0
    for nextTier = curr + 1, maxT do
        local nIlvl = tiers[nextTier]
        if not nIlvl then break end
        if nIlvl > wm then
            count = count + 1
        end
    end
    return count
end

local function SumRemainingCrestCosts(upInfo)
    return CountCrestStepsRemaining(upInfo) * (upInfo.crestCost or ns.UPGRADE_CREST_PER_LEVEL or 20)
end

local function GetEffectiveNextStepCrestCost(upInfo)
    if not upInfo or upInfo.isCrafted then return nil end
    if not upInfo.canUpgrade then return nil end
    local currTier = upInfo.currUpgrade or 0
    local maxTier = upInfo.maxUpgrade or 0
    if currTier >= maxTier then return nil end
    local tiers = TRACK_ILVLS and TRACK_ILVLS[upInfo.trackName]
    if not tiers then return nil end
    local wmIlvl = upInfo.watermarkIlvl or 0
    local nextIlvl = tiers[currTier + 1]
    if not nextIlvl then return nil end
    if nextIlvl <= wmIlvl then return 0 end
    return upInfo.crestCost or ns.UPGRADE_CREST_PER_LEVEL or 20
end

--- Gear tab item hover: Dawncrest + Sources blocks removed (no vendor playbook in tooltip).
---@return table lines always empty; upgrade row stays on paperdoll only.
function WarbandNexus:GetGearItemUpgradeTooltipAppend(itemLink, slotContext)
    return {}
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
        self:Print("|cffff6600[WN GearStorageDebug]|r " .. ((ns.L and ns.L["GEAR_NO_TRACKED_CHARACTERS_TITLE"]) or "No tracked characters.") )
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

-- Fixed slot order for FindGearStorageUpgrades cache keys (pairs() on slots is undefined order).
local GEAR_STORAGE_SIG_SLOTS = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}
local gearStorageFindingsCache = { canonKey = nil, invEpoch = nil, equipSig = nil, findings = nil }

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

--- Try to resolve the effective ilvl of an item from bag storage.
--- Prefers link-based ilvl so the UI row matches the tooltip (same item link).
---@param item table Hydrated item from ItemsCacheService
---@return number ilvl (0 if unknown)
local function ResolveStorageItemIlvl(item)
    if not item or not item.itemID then return 0 end

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

--- Determine the binding/availability label for a storage item.
---@param item table Hydrated item
---@param sourceCharKey string The character that owns this item
---@param selectedCharKey string The character we're gearing
---@return string label  e.g. "Warband Bank", "Shaman Foo (Bag)", "Your Bag"
---@return string type   "warband" | "self_bag" | "self_bank" | "char_bag" | "char_bank" | "boe" | "warbound" | "warbound_until_equipped"
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
        return (k:gsub("%s+", ""))
    end
    local sourceNorm = canonical(sourceCharKey)
    local selectedNorm = canonical(selectedCharKey)
    local isSameChar = (sourceNorm ~= "" and selectedNorm ~= "" and sourceNorm == selectedNorm)

    if isSameChar then
        if storageType == "bank" then return "Your Bank", "self_bank" end
        return "Your Bag", "self_bag"
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
    if c.canonKey == canonKey and c.invEpoch == invEpoch and c.equipSig == equipSig and c.findings then
        return c.findings, true
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
    if c.canonKey == canonKey and c.findings then
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
    if c.canonKey ~= canonKey or c.equipSig ~= equipSig or not c.findings then
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
    if not c or c.canonKey ~= canonKey or not c.findings then
        return false
    end
    c.invEpoch = nil
    ns._gearStorageFindingsDirtyToken = (ns._gearStorageFindingsDirtyToken or 0) + 1
    WarbandNexus:GearStorageTrace("Invalidate invEpoch cleared canon=" .. tostring(canonKey)
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

--- Compact fingerprint of `gearStorageFindingsCache` for PopulateContent dedupe.
--- When async scan fills findings without bumping `ns._gearStorageInvGen`, this still
--- changes so same-tab repaints are not misclassified as gearSigEcho while stale UI remains.
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

--- Count slot buckets and total candidate rows in a findings table (debug / diagnostics).
---@param findings table|nil
---@return number slots
---@return number candidates
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
        if c.canonKey == canonKey and c.invEpoch == invEpoch and c.equipSig == equipSig and c.findings then
            local fs, fc = GearStorageFindingsCount(c.findings)
            WarbandNexus:GearStoragePanelDebug(("Find CACHE HIT canon=%s invEpoch=%s findingsSlots=%d candidates=%d (no full scan)")
                :format(tostring(canonKey), tostring(invEpoch), fs, fc))
            WarbandNexus:GearStorageTrace("Find cache hit canon=" .. tostring(canonKey)
                .. " invEpoch=" .. tostring(invEpoch))
            return c.findings
        end
    end

    local P = ns.Profiler
    local _gearFindProfOn = P and P.enabled and P.StartSlice and P.StopSlice
    if _gearFindProfOn then P:StartSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_scan") end
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
        local equippedGear = self:GetEquippedGear(selectedCharKey)
        local slots = equippedGear and equippedGear.slots or {}
        local pairedSlots = { 11, 12, 13, 14 }
        for si = 1, #pairedSlots do
            local slotID = pairedSlots[si]
            local s = slots[slotID]
            if s and s.itemID then
                equippedItemIDBySlot[slotID] = tonumber(s.itemID)
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
        local equippedGear = self:GetEquippedGear(selectedCharKey)
        local mh = equippedGear and equippedGear.slots and equippedGear.slots[16]
        local mhEquipLoc = mh and mh.equipLoc or ""
        if mhEquipLoc == "" and mh and mh.itemLink then
            local ok, loc = pcall(GetEquipLoc, mh.itemLink)
            if ok then mhEquipLoc = loc or "" end
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
    local curCanon = currentKey
    local selectedIsLoggedInPlayer = (selCanon and curCanon and selCanon == curCanon)

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

    --- Class file for storage row coloring (nil = neutral: warband / unknown).
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

    --- Level + race/class (only when the selected tab character is the logged-in player — API is player-scoped).
    local function SelectedCharacterMeetsItemRequirements(itemLink, itemID)
        local minLvl = GetItemMinLevelFromItemInfo(itemLink) or GetItemMinLevelFromItemInfo(itemID)
        local charLvl = charData and tonumber(charData.level)
        -- charData.level is a stale snapshot from the last time this character was online —
        -- it can lag behind the current real level (e.g. char dinged 90 but DB still shows 89,
        -- so a "Requires Level 90" recommendation gets rejected). When previewing an alt, we
        -- can't fetch live level from the API; trust storage availability + class/armor filter
        -- instead of a brittle stale-level check.
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
        if link then
            candidate.itemLevel = ResolveStorageItemIlvl({ itemID = candidate.itemID, itemLink = link, link = link })
            local minL = GetItemMinLevelFromItemInfo(link) or GetItemMinLevelFromItemInfo(candidate.itemID)
            if minL then candidate.requiredLevel = minL end
        end
        if (candidate.itemLevel or 0) == 0 then return end
        -- Snapshot for UI row filter: Find can run against slightly older gearData than RedrawGearStorageRecommendationsOnly.
        candidate.equippedIlvlAtFind = equippedMap[slotID] or 0
        for i = 1, #findings[slotID] do
            local ex = findings[slotID][i]
            if ex.itemLink == candidate.itemLink and ex.source == candidate.source then return end
        end
        findings[slotID][#findings[slotID] + 1] = candidate
        addedCount = addedCount + 1
    end

    local function EvaluateItem(item, sourceCharKey, storageType)
        if not item or not item.itemID then return end
        -- When RunFindGearStorageUpgradesYielded drives this scan, yield so one frame never evaluates thousands of items.
        if ns._gearStorageYieldCo then
            ns._gearStorageYieldCounter = (ns._gearStorageYieldCounter or 0) + 1
            if ns._gearStorageYieldCounter >= 28 then
                ns._gearStorageYieldCounter = 0
                coroutine.yield()
            end
        end

        local linkEarly = item.itemLink or item.link
        if IsCosmeticGearCandidate(item.itemID, linkEarly) then return end

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

        if C_Item and C_Item.RequestLoadItemDataByID and item.itemID then
            pcall(C_Item.RequestLoadItemDataByID, item.itemID)
        end

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
            local isStatOK = MatchGetItemStatsPrimariesToExpected(link, mainStat, slotID, selectedIsLoggedInPlayer, item.itemID)

            if not isArmorOK then
                -- silent
            elseif not isWeaponOK then
                -- silent
            elseif not isStatOK then
                rejectCounts.stat = rejectCounts.stat + 1
            elseif not SelectedCharacterMeetsItemRequirements(link, item.itemID) then
                rejectCounts.lvlRace = rejectCounts.lvlRace + 1
            else
                local currentIlvl = equippedMap[slotID] or 0
                if ilvl > currentIlvl then
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
                        })
                    else
                        rejectCounts.bind = rejectCounts.bind + 1
                    end
                end
            end
            end
        end
    end

    -- ── Warband Bank ──────────────────────────────────────────────────────────
    local wbData = (WarbandNexus.GetWarbandBankData and WarbandNexus:GetWarbandBankData()) or nil
    if wbData and wbData.items then
        for i = 1, #wbData.items do
            if ns._gearStorageYieldCo and (i % 40 == 0) then
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

        for i = 1, #scanOrder do
            local canonicalChar = scanOrder[i]
            local charKey = repKeyByCanon[canonicalChar] or canonicalChar
            local itemsData = getItemsForCharacter(canonicalChar, charKey)
            if itemsData then
                local bags = itemsData.bags or {}
                for j = 1, #bags do
                    EvaluateItem(bags[j], charKey, "bag")
                end
                local bank = itemsData.bank or {}
                for j = 1, #bank do
                    EvaluateItem(bank[j], charKey, "bank")
                end
            end
        end

        local guildItems = (WarbandNexus.GetGuildBankItems and WarbandNexus:GetGuildBankItems()) or {}
        for gi = 1, #guildItems do
            if ns._gearStorageYieldCo and (gi % 40 == 0) then
                coroutine.yield()
            end
            EvaluateItem(guildItems[gi], selectedCharKey, "guild")
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
                if _equippedOtherYield % 4 == 0 then
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
    dbg(string.format(
        "  Reject/add: stat=%d lvlRace=%d boeSoul=%d bindLbl=%d bind=%d | added=%d",
        rejectCounts.stat,
        rejectCounts.lvlRace,
        rejectCounts.boeSoul,
        rejectCounts.bindLabel,
        rejectCounts.bind,
        addedCount
    ))

    for slotID, candidates in pairs(findings) do
        table.sort(candidates, function(a, b) return (a.itemLevel or 0) > (b.itemLevel or 0) end)
        while #candidates > 5 do table.remove(candidates) end
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
        if _gearFindProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_scan") end
        return findings
    end
    local equippedMapCommit = BuildEquippedIlvlMap(selectedCharKey)
    local equipSigCommit = BuildGearStorageScanCacheSignature(selectedCharKey, equippedMapCommit)
    gearStorageFindingsCache.canonKey = canonKey
    gearStorageFindingsCache.equipSig = equipSigCommit
    gearStorageFindingsCache.findings = findings
    -- Align cache epoch to the latest scan generation. Item-info batches and metadata
    -- hooks can bump `ns._gearStorageInvGen` while a yielded Find runs; using only the
    -- epoch captured at scan start forces redundant FULLFIND in RedrawGearStorageRecommendationsOnly.
    gearStorageFindingsCache.invEpoch = ns._gearStorageInvGen or 0
    ns._gearStorageFindingsCleanToken = ns._gearStorageFindingsDirtyToken or 0

    if _gearFindProfOn then P:StopSlice(P.CAT.SVC, "Gear_FindStorageUpgrades_scan") end

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
        local mfAb = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mfAb then
            mfAb._gearDeferChainActive = false
        end
        -- RedrawGearStorageRecommendationsOnly can set this and never clear it if the coroutine aborts mid-scan.
        if yieldCanon and ns._gearStorageRecFindPending then
            ns._gearStorageRecFindPending[yieldCanon] = nil
        end
        -- Stale scan: repaint storage panel only (full PopulateContent caused a visible "double refresh"
        -- after char switch + instant populate).
        local snapGen = paintGen
        C_Timer.After(0, function()
            if snapGen ~= (ns._gearTabDrawGen or 0) then return end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            local canon = (mf and mf._gearPopulateCanonKey) or yieldCanon
            if canon and WarbandNexus.RedrawGearStorageRecommendationsOnly then
                ns._gearStorageAllowEquipSigInvBypass = true
                WarbandNexus:RedrawGearStorageRecommendationsOnly(canon, snapGen, true)
                ns._gearStorageAllowEquipSigInvBypass = false
            end
            if ns.UI_TryDismissGearTabLoadingVeil and mf then
                ns.UI_TryDismissGearTabLoadingVeil(mf, snapGen)
            end
        end)
    end

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
        local sliceStart = GetTime()
        while coroutine.status(co) ~= "dead" do
            if ns._gearStorageYieldCo ~= co then
                return
            end
            local ok, err = coroutine.resume(co)
            if not ok then
                if ns._gearStorageYieldCo ~= co then
                    return
                end
                WarbandNexus:ReportGearStorageError(err, "yielded scan")
                abortYieldedFind("coroutine error")
                return
            end
            if (GetTime() - sliceStart) > 0.010 then
                C_Timer.After(0, pump)
                return
            end
        end
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

-- ============================================================================
-- CURRENCY SNAPSHOT  (Resources available for upgrading)
-- ============================================================================

-- Currency IDs for item upgrades (Dawncrest column order — UI only; see Constants.DAWNCREST_UI)
local UPGRADE_CURRENCY_IDS = (Constants.DAWNCREST_UI and Constants.DAWNCREST_UI.COLUMN_IDS)
    or { 3383, 3341, 3343, 3345, 3347 }

local UPGRADE_CURRENCY_NAMES = (Constants.DAWNCREST_UI and Constants.DAWNCREST_UI.DISPLAY_NAMES) or {
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

--- Match CurrencyCacheService: progress-style currencies from API (no hardcoded ID list).
local function IsGearSeasonSplitCurrency(currencyID, info)
    if not info then return false end
    if info.isHeader then return false end
    if info.useTotalEarnedForMaxQty == true then return true end
    if not info.name then return false end
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
--- Offline char: merged snapshot from GetCurrenciesForUI (CurrencyCacheService).
---@param charKey string Character key from UI (dropdown).
---@return table list { { currencyID, amount, name, icon }, ... }, gold last
function WarbandNexus:GetGearUpgradeCurrenciesFromDB(charKey)
    local result = {}
    if not charKey then return result end

    local canonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(charKey)) or charKey
    local currentKey = ResolveGearStorageKey()
    local isCurrentChar = (canonicalKey and currentKey and canonicalKey == currentKey)
    if not isCurrentChar then
        local oc = gearUpgradeCurrencyOfflineCache[canonicalKey]
        if oc then
            return oc
        end
    end
    local function norm(k)
        if not k or k == "" then return "" end
        if issecretvalue and issecretvalue(k) then return "" end
        return (tostring(k):gsub("%s+", ""))
    end

    local upgradeIds = {}
    for i = 1, #UPGRADE_CURRENCY_IDS do
        upgradeIds[#upgradeIds + 1] = UPGRADE_CURRENCY_IDS[i]
    end
    do
        local allCur = self:GetCurrenciesForUI()
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
            -- OFFLINE: quantities from merged currency snapshot (same table as Currency tab).
            local currencyData = self:GetCurrenciesForUI()
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
    if isCurrentChar and ns.Utilities and ns.Utilities.GetLiveCharacterMoneyCopper then
        gold = ns.Utilities:GetLiveCharacterMoneyCopper(gold)
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
    if not isCurrentChar then
        gearUpgradeCurrencyOfflineCache[canonicalKey] = result
    end
    return result
end

--- Get the player's current quantities of upgrade-relevant currencies.
--- DB only: same as GetGearUpgradeCurrenciesFromDB (CurrencyCacheService + characters gold). No API calls.
---@param charKey string
---@return table currencies Array of { currencyID, amount, name, icon, isGold? }
function WarbandNexus:GetGearUpgradeCurrencies(charKey)
    return self:GetGearUpgradeCurrenciesFromDB(charKey)
end

-- ============================================================================
-- GEAR UPGRADE PLAYBOOK (removed from Gear tab UI; GetGearUpgradePlaybookText is a no-op stub)
-- ============================================================================

local function LocalizeDawncrestTierShortName(englishFirstWord)
    if not englishFirstWord or englishFirstWord == "" then return englishFirstWord end
    local L = ns.L
    if not L then return englishFirstWord end
    local key = ({
        Adventurer = "PVE_CREST_ADV",
        Veteran = "PVE_CREST_VET",
        Champion = "PVE_CREST_CHAMP",
        Hero = "PVE_CREST_HERO",
        Myth = "PVE_CREST_MYTH",
        Explorer = "PVE_CREST_EXPLORER",
    })[englishFirstWord]
    if key and L[key] then return L[key] end
    return englishFirstWord
end

--- Playbook-style Dawncrest tooltip removed from Gear tab (UI no longer calls this for display).
---@return string summary
---@return table|nil tooltipPayload
function WarbandNexus:GetGearUpgradePlaybookText(charKey)
    return "", nil
end

-- After currency changes (e.g. crests spent on upgrade), re-scan gear so item ilvl/tier and watermarks stay in sync.
WarbandNexus:RegisterMessage(Constants.EVENTS.CURRENCY_UPDATED, function()
    InvalidateGearUpgradeCurrencyCaches()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
    if currencyGearScanTimer then currencyGearScanTimer:Cancel() end
    currencyGearScanTimer = C_Timer.NewTimer(0.4, function()
        currencyGearScanTimer = nil
        WarbandNexus:ScanEquippedGear()
    end)
end)

WarbandNexus:RegisterMessage(Constants.EVENTS.CHARACTER_UPDATED, function()
    InvalidateGearUpgradeCurrencyCaches()
end)
