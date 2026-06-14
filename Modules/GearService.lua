--[[
    Warband Nexus - Gear Service
    Scans/persists equipped gear (db.global.gearData[charKey]); ilvl-based upgrade analysis and cross-character storage finder.

    Storage-findings cache keys on equip signature + inventory epoch; yielded Find defers invalidation mid-scan.
    Gold-only (0-crest) upgrades use per-slot ilvl watermarks when the upgrade NPC window is closed.

    WN_NONUI_UI: Transient DressUp/model preview frames constructed in this module are helpers only; Gear tab visuals live in Modules/UI/GearUI.lua.
    LuaLS: retain ---@ on WarbandNexus: export surface only; local helpers stay comment-only.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local issecretvalue = issecretvalue
local wipe = table.wipe
local debugprofilestop = debugprofilestop

local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter("|cff00BFFF[GearService]|r"))
    or ns.DebugPrint
    or function() end

local function RequestGearStorageRedraw(canonKey, paintGen, trustEquipSig)
    if not canonKey or canonKey == "" then return end
    local ev = Constants and Constants.EVENTS and Constants.EVENTS.GEAR_STORAGE_REDRAW_REQUESTED
    if ev and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(ev, {
            canonKey = canonKey,
            paintGen = paintGen,
            trustEquipSig = trustEquipSig == true,
        })
    end
end

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
    self:Print("|cff00ccff[WN]|r Stash-rec panel debug " .. (enabled and "ON" or "OFF")
        .. " — trace in |cff00ccff/wn profiler trace|r; chat dump: |cff00ccff/wn gearstash|r")
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN StashRec] panel debug " .. (enabled and "ON" or "OFF"))
    end
end

--- Verbose stash-rec panel logging (controlled by `SetGearStoragePanelDebug`). Trace only.
function WarbandNexus:GearStoragePanelDebug(msg)
    if not ns.WN_GEAR_STORAGE_PANEL_DEBUG then return end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine("[WN StashRec] " .. tostring(msg))
    end
end

--- Always visible (not gated by debugMode): coroutine / storage pipeline failures.
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
        -- GET_ITEM_INFO can queue invalidate mid-yield; after commit the cache is still strict-valid.
        if self.ShouldSkipGearStorageNarrowInvalidateForRapidRescan
            and self:ShouldSkipGearStorageNarrowInvalidateForRapidRescan(want) then
            if self.RefreshGearStorageCacheEquipSigForCanon then
                self:RefreshGearStorageCacheEquipSigForCanon(want)
            end
            return "equip_redraw"
        end
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
function WarbandNexus:OnGearStorageYieldedScanComplete(canonKey, paintGen, afterFn)
    local action = self:ProcessDeferredGearStorageUpdates(canonKey)
    local function runTail()
        if action == "equip_redraw" then
            if paintGen == (ns._gearTabDrawGen or 0)
                and WarbandNexus.IsStillOnTab and WarbandNexus:IsStillOnTab("gear") then
                RequestGearStorageRedraw(canonKey, paintGen, false)
            end
        end
        if type(afterFn) == "function" then
            afterFn()
        end
    end
    if action == "rescan" and self.ScheduleGearStorageFindingsResolve then
        -- Never chain a second full Find in the same frame as scan completion (avoids 30–80ms doubles).
        C_Timer.After(0.04, function()
            if paintGen ~= (ns._gearTabDrawGen or 0) then return end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
            self:ScheduleGearStorageFindingsResolve(canonKey, paintGen, runTail)
        end)
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
local PERSISTED_UPGRADE_INFO_LOGIC_VER = 16

-- Session-only: offline-view canonical key -> currency array from GetGearUpgradeCurrenciesFromDB (amounts follow Currency UI snapshot).
local gearUpgradeCurrencyOfflineCache = {}

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

local function GearLinkIsCrafted(link)
    if not link or link == "" then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    local cached = gearCraftedProbeCache[link]
    if cached ~= nil then return cached end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo) then return nil end
    local ok, quality = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, link)
    if not ok then return nil end
    local isCrafted = type(quality) == "number" and quality > 0
    CacheGearCraftedProbeResult(link, isCrafted)
    return isCrafted
end

-- SLOT DEFINITIONS (GearService_Slots.lua)
local Slots = ns.GearServiceSlots
local GEAR_SLOTS = Slots.GEAR_SLOTS
local SLOT_BY_ID = Slots.SLOT_BY_ID
local EQUIP_LOC_TO_SLOTS = Slots.EQUIP_LOC_TO_SLOTS
local SLOT_PAIRS = Slots.SLOT_PAIRS
local ARMOR_SLOT_IDS = Slots.ARMOR_SLOT_IDS

local ITEM_CLASS_WEAPON = LE_ITEM_CLASS_WEAPON or 2
local ITEM_CLASS_ARMOR = LE_ITEM_CLASS_ARMOR or 4

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

local function TooltipLineMentionsPrimaryStat(lineText, statLabel)
    if not lineText or statLabel == "" then return false end
    if issecretvalue and issecretvalue(lineText) then return false end
    if not lineText:find(statLabel, 1, true) then return false end
    if lineText:find("Requires", 1, true) then return false end
    if lineText:find("Durability", 1, true) then return false end
    if lineText:find("Use:", 1, true) or lineText:find("Equip:", 1, true) then return false end
    return true
end

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

local ITEM_BIND_WARBAND = (type(LE_ITEM_BIND_WARBAND) == "number" and LE_ITEM_BIND_WARBAND)
    or (Enum and Enum.ItemBind and type(Enum.ItemBind.Warband) == "number" and Enum.ItemBind.Warband)
    or 8

local ITEM_BIND_BNET_UNTIL_EQUIPPED = (Enum and Enum.ItemBind and type(Enum.ItemBind.ToBnetAccountUntilEquipped) == "number" and Enum.ItemBind.ToBnetAccountUntilEquipped) or 9

local ITEM_BIND_TO_WOW_ACCOUNT = (Enum and Enum.ItemBind and type(Enum.ItemBind.ToWoWAccount) == "number" and Enum.ItemBind.ToWoWAccount) or 7

local ITEM_BIND_ON_USE = (Enum and Enum.ItemBind and type(Enum.ItemBind.OnUse) == "number" and Enum.ItemBind.OnUse)
    or (type(LE_ITEM_BIND_ON_USE) == "number" and LE_ITEM_BIND_ON_USE)
    or 3

local function GetRawItemBindTypeFromGetItemInfo(itemInfo)
    if not itemInfo or not C_Item or not C_Item.GetItemInfo then return nil end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14 = pcall(C_Item.GetItemInfo, itemInfo)
    if not ok or not r1 then return nil end
    if type(r14) ~= "number" then return nil end
    return r14
end

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

local function GetItemMinLevelFromItemInfo(itemInfo)
    if not itemInfo or not C_Item or not C_Item.GetItemInfo then return nil end
    local ok, _, _, _, minLvl = pcall(C_Item.GetItemInfo, itemInfo)
    if not ok or minLvl == nil then return nil end
    if issecretvalue and issecretvalue(minLvl) then return nil end
    if type(minLvl) ~= "number" or minLvl <= 0 then return nil end
    return minLvl
end

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

local function UnitSexToDressGender0Or1(unitSex)
    if unitSex == 3 then return 1 end
    return 0
end

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
        -- Singleton probe model: frames are never garbage collected, and this used
        -- to create-and-abandon a full DressUpModel on every transmog snapshot.
        local m = ns._wnTransmogSnapshotModel
        if not m then
            m = CreateFrame("DressUpModel")
            m:Hide()
            ns._wnTransmogSnapshotModel = m
        end
        m:SetUnit("player")
        if m.Dress then m:Dress() end
        if m.SetUseTransmogChoices then m:SetUseTransmogChoices(true) end
        if m.SetUseTransmogSkin then m:SetUseTransmogSkin(false) end
        local l = m.GetItemTransmogInfoList and m:GetItemTransmogInfoList() or nil
        m:Hide()
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

-- UPGRADE ANALYSIS  (No API — ilvl-based inference from DB only, works offline)

local GT = ns.GearUpgradeTracks
local TRACK_ILVLS = GT.TRACK_ILVLS
local TRACK_ORDER = GT.TRACK_ORDER
local ILVL_TO_UPGRADE = GT.ILVL_TO_UPGRADE
local TRACK_NAME_TO_CURRENCY_ID = GT.TRACK_NAME_TO_CURRENCY_ID
local UPGRADE_CURRENCY_ID_SET_EARLY = GT.UPGRADE_CURRENCY_ID_SET_EARLY
local CURRENCY_ID_TO_TRACK = GT.CURRENCY_ID_TO_TRACK

local function NormalizeUpgradeTrackName(raw)
    if not raw or raw == "" then return nil end
    if issecretvalue and issecretvalue(raw) then return nil end
    if TRACK_ILVLS[raw] then return raw end
    local firstWord = raw:match("^([%a]+)")
    if firstWord and TRACK_ILVLS[firstWord] then return firstWord end
    for ti = 1, #TRACK_ORDER do
        local eng = TRACK_ORDER[ti]
        if raw:find(eng, 1, true) then return eng end
    end
    local L = ns.L
    local labelKeys = Constants and Constants.DAWNCREST_UI and Constants.DAWNCREST_UI.PVE_LABEL_KEYS
    if L and labelKeys then
        for eng, key in pairs(labelKeys) do
            local loc = L[key]
            if loc and loc ~= "" and (raw == loc or raw:find(loc, 1, true)) then
                return eng
            end
        end
    end
    return nil
end
local function InferTierWithinTrack(trackName, itemLevel)
    local tiers = TRACK_ILVLS[trackName]
    if not tiers then return nil, nil end
    local ilvl = tonumber(itemLevel)
    if not ilvl then return nil, nil end
    for t = 1, #tiers do
        if tiers[t] == ilvl then
            return t, #tiers
        end
    end
    local best = 1
    for t = 1, #tiers do
        if ilvl >= tiers[t] then
            best = t
        end
    end
    return best, #tiers
end

local function ReconcileUpgradeTierForSlot(trackName, itemLevel, apiCurr, apiMax)
    local tiers = TRACK_ILVLS[trackName]
    if not tiers then
        return apiCurr, apiMax
    end
    local ilvl = tonumber(itemLevel) or 0
    local maxT = #tiers
    local inferCur, inferMax = InferTierWithinTrack(trackName, ilvl)
    if not inferCur or not inferMax then
        return apiCurr, apiMax
    end
    if not (apiCurr and apiMax and apiMax > 0) then
        return inferCur, inferMax
    end
    local cur = math.floor(tonumber(apiCurr) or 0)
    local maxU = math.floor(tonumber(apiMax) or 0)
    if maxU > maxT then maxU = maxT end
    if cur > 0 and cur <= maxU then
        local tierIlvl = tiers[cur]
        if ilvl > 0 and tierIlvl and tierIlvl == ilvl then
            return cur, maxU
        end
        if cur >= maxU and ilvl > 0 and ilvl >= (tiers[maxU] or ilvl) then
            return maxU, maxU
        end
        -- Equipped ilvl disagrees with API tier step (e.g. Myth 3/6 on 289 ilvl) — trust ilvl.
        if ilvl > 0 and (not tierIlvl or tierIlvl ~= ilvl) then
            return inferCur, inferMax
        end
        if inferCur > cur then
            return inferCur, inferMax
        end
        return cur, maxU
    end
    return inferCur, inferMax
end

local function InferUpgradeFromIlvl(itemLevel)
    local ilvl = tonumber(itemLevel)
    if not ilvl or ilvl < 220 or ilvl > 289 then return nil, nil, nil end

    local bestTrack, bestTier, bestMax = nil, -1, 6
    for ti = 1, #TRACK_ORDER do
        local trackName = TRACK_ORDER[ti]
        local tiers = TRACK_ILVLS[trackName]
        if tiers then
            for tier = 1, #tiers do
                if tiers[tier] == ilvl and tier > bestTier then
                    bestTier = tier
                    bestTrack = trackName
                    bestMax = #tiers
                end
            end
        end
    end
    if bestTrack then
        return bestTrack, bestTier, bestMax
    end

    local entry = ILVL_TO_UPGRADE[ilvl]
    if entry then return entry[1], entry[2], entry[3] end
    local nearest, bestDiff = nil, 999
    for k, v in pairs(ILVL_TO_UPGRADE) do
        local d = math.abs(k - ilvl)
        if d < bestDiff then
            bestDiff = d
            nearest = v
        end
    end
    if nearest then return nearest[1], nearest[2], nearest[3] end
    return nil, nil, nil
end

local function GetTierIlvlForTrack(trackName, tier)
    local tiers = TRACK_ILVLS[trackName]
    if not tiers or not tier or tier < 1 or tier > #tiers then return nil end
    return tiers[math.floor(tier)]
end

local function GetIlvlForTier(trackName, tier)
    local tiers = TRACK_ILVLS[trackName]
    if not tiers or tier < 1 or tier > #tiers then return nil end
    return tiers[tier]
end
local function TrackNameFromUpgradeCurrencyID(currencyID)
    if not currencyID then return nil end
    return CURRENCY_ID_TO_TRACK[currencyID]
end

local function NormalizeUpgradeCurrencyCostEntry(entry)
    if not entry or not entry.currencyID then return nil end
    local amt = entry.cost or entry.amount
    if amt == nil then return nil end
    local di = entry.discountInfo
    local isDiscounted = (di and di.isDiscounted == true) or false
    return {
        currencyID = entry.currencyID,
        amount = amt,
        isDiscounted = isDiscounted,
    }
end

local function ResolveTrackFromPersistedCosts(slot)
    local costs = slot and slot.nextUpgradeCosts
    if not costs then return nil end
    for i = 1, #costs do
        local norm = NormalizeUpgradeCurrencyCostEntry(costs[i])
        if norm and norm.currencyID then
            local track = TrackNameFromUpgradeCurrencyID(norm.currencyID)
            if track and TRACK_ILVLS[track] then
                return track
            end
        end
    end
    return nil
end

local function ParseUpgradeLabelString(raw)
    if not raw or raw == "" then return nil, nil, nil end
    if issecretvalue and issecretvalue(raw) then return nil, nil, nil end
    local trackPart, curS, maxS = raw:match("^([%a]+)%s+(%d+)/(%d+)")
    if trackPart then
        local track = NormalizeUpgradeTrackName(trackPart)
        if track and TRACK_ILVLS[track] then
            return track, tonumber(curS), tonumber(maxS)
        end
    end
    local track = NormalizeUpgradeTrackName(raw)
    if track and TRACK_ILVLS[track] then
        return track, nil, nil
    end
    return nil, nil, nil
end

local function ResolveTrackFromSlotLabels(slot)
    if not slot then return nil, nil, nil end
    local track, cur, max = ParseUpgradeLabelString(slot.customUpgradeString)
    if track then return track, cur, max end
    track = NormalizeUpgradeTrackName(slot.upgradeTrack)
    if track and TRACK_ILVLS[track] then
        return track, tonumber(slot.currUpgrade), tonumber(slot.maxUpgrade)
    end
    return nil, nil, nil
end

local function ResolveNextUpgradeCosts(slot, trackName, hasNext)
    local currencyID = 0
    local crestCost = hasNext and (ns.UPGRADE_CREST_PER_LEVEL or 20) or 0
    local moneyCost = hasNext and (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000) or 0
    local isDiscounted = false
    if not hasNext or not slot then
        return currencyID, crestCost, moneyCost, isDiscounted
    end
    local costs = slot.nextUpgradeCosts
    if costs then
        for i = 1, #costs do
            local norm = NormalizeUpgradeCurrencyCostEntry(costs[i])
            if norm and norm.currencyID and UPGRADE_CURRENCY_ID_SET_EARLY[norm.currencyID] then
                currencyID = norm.currencyID
                crestCost = norm.amount
                if norm.isDiscounted then
                    isDiscounted = true
                end
            end
        end
    end
    if currencyID == 0 and trackName and TRACK_ILVLS[trackName] then
        currencyID = TRACK_NAME_TO_CURRENCY_ID[trackName] or 0
    end
    if currencyID ~= 0 and trackName and TRACK_ILVLS[trackName] then
        local costTrack = TrackNameFromUpgradeCurrencyID(currencyID)
        if costTrack and costTrack ~= trackName then
            currencyID = TRACK_NAME_TO_CURRENCY_ID[trackName] or 0
            crestCost = hasNext and (ns.UPGRADE_CREST_PER_LEVEL or 20) or 0
            isDiscounted = false
        end
    end
    if slot.nextUpgradeMoneyCost and slot.nextUpgradeMoneyCost > 0 then
        moneyCost = slot.nextUpgradeMoneyCost
    end
    if slot.nextUpgradeIsDiscounted then
        isDiscounted = true
    end
    return currencyID, crestCost, moneyCost, isDiscounted
end

local function ResolveSlotUpgradeTrackAndTier(slot)
    if not slot then return nil, nil, nil end
    local ilvl = tonumber(slot.itemLevel) or 0
    if ilvl <= 0 then return nil, nil, nil end

    local labelTrack, labelCur, labelMax = ResolveTrackFromSlotLabels(slot)
    local track = labelTrack or NormalizeUpgradeTrackName(slot.upgradeTrack)
    if track and not TRACK_ILVLS[track] then
        track = nil
    end

    local apiCur = tonumber(slot.currUpgrade)
    local apiMax = tonumber(slot.maxUpgrade)
    if labelCur and labelMax and labelMax > 0 then
        apiCur = apiCur or labelCur
        apiMax = apiMax or labelMax
    end

    if track then
        if apiCur and apiMax and apiMax > 0 then
            local tCur, tMax = ReconcileUpgradeTierForSlot(track, ilvl, apiCur, apiMax)
            if tCur and tMax then
                return track, tCur, tMax
            end
            return track, math.floor(apiCur), math.min(math.floor(apiMax), #TRACK_ILVLS[track])
        end
        local tCur, tMax = InferTierWithinTrack(track, ilvl)
        if tCur and tMax then
            return track, tCur, tMax
        end
    end

    return InferUpgradeFromIlvl(ilvl)
end

ns.Gear_ResolveSlotUpgradeTrackAndTier = ResolveSlotUpgradeTrackAndTier

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

local function InferSlotIsCraftedGear(slot, trackName, itemLevel)
    if slot and slot.isCrafted then return true end
    if trackName == "Crafted" then return true end
    return false
end

-- DB HELPERS

local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    if not WarbandNexus.db.global.gearData then
        WarbandNexus.db.global.gearData = {}
    end
    return WarbandNexus.db.global.gearData
end

local function ResolveGearStorageKey()
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k and k ~= "" then return k end
    end
    if CS and CS.ResolveCharactersTableKey then
        local k = CS:ResolveCharactersTableKey(WarbandNexus)
        if k and k ~= "" then return k end
    end
    local U = ns.Utilities
    if U and U.GetCharacterStorageKey then
        local k = U:GetCharacterStorageKey(WarbandNexus)
        if k and k ~= "" then return k end
    end
    return U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus) or nil
end

--- Logged-in player's gearData bucket (canonical storage key).
---@return string|nil
function WarbandNexus:GetCurrentGearStorageKey()
    return ResolveGearStorageKey()
end

local function GearDataSlotHasPayload(slot)
    if type(slot) ~= "table" then return false end
    if slot.itemLink or slot.itemID or slot.name then return true end
    return (tonumber(slot.itemLevel) or 0) > 0
end

local function CountGearDataPayloadSlots(entry)
    local slots = type(entry) == "table" and entry.slots
    if type(slots) ~= "table" then return 0 end
    local count = 0
    for _, slot in pairs(slots) do
        if GearDataSlotHasPayload(slot) then count = count + 1 end
    end
    return count
end

--- Older SavedVariables stored slots/watermarks by paperdoll row index (1..16), not Blizzard slot id.
--- Keys 6-16 collide (array[6]=wrist vs slot id 6=waist) so naive slot-id reads show the wrong character's layout.
local function GearSlotsUseSequentialPaperdollIndex(slots)
    if type(slots) ~= "table" then return false end
    for sid, slot in pairs(slots) do
        if type(sid) == "number" and sid > #GEAR_SLOTS and GearDataSlotHasPayload(slot) then
            return false
        end
    end
    for i = 1, #GEAR_SLOTS do
        local defId = GEAR_SLOTS[i].id
        if i ~= defId and GearDataSlotHasPayload(slots[i]) and not GearDataSlotHasPayload(slots[defId]) then
            return true
        end
    end
    return false
end

local function AverageGearPayloadIlvl(entry)
    local slots = entry and entry.slots
    if type(slots) ~= "table" then return 0 end
    local sum, count = 0, 0
    for _, slot in pairs(slots) do
        if GearDataSlotHasPayload(slot) then
            local il = tonumber(slot.itemLevel) or 0
            if il > 0 then
                sum = sum + il
                count = count + 1
            end
        end
    end
    if count == 0 then return 0 end
    return sum / count
end

local SPEC_RANGE_BY_CLASS_ID = {
    [1]  = { 71, 73 },     -- Warrior
    [2]  = { 65, 70 },     -- Paladin
    [3]  = { 253, 255 },   -- Hunter
    [4]  = { 259, 261 },   -- Rogue
    [5]  = { 256, 258 },   -- Priest
    [6]  = { 250, 252 },   -- Death Knight
    [7]  = { 262, 264 },   -- Shaman
    [8]  = { 62, 64 },     -- Mage
    [9]  = { 265, 267 },   -- Warlock
    [10] = { 268, 270 },   -- Monk
    [11] = { 102, 105 },   -- Druid
    [12] = { 577, 581 },   -- Demon Hunter
    [13] = { 1467, 1473 }, -- Evoker
}

local function ExtractLinkPlayerSpecId(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if issecretvalue and issecretvalue(itemLink) then return nil end
    local _, specId = itemLink:match("::::::::(%d+):(%d+):")
    return specId and tonumber(specId) or nil
end

local function LinkSpecMatchesCharacterRow(row, specId)
    if not row or not specId then return true end
    local rowSpec = tonumber(row.specID)
    if rowSpec and rowSpec > 0 and specId == rowSpec then return true end
    local classID = tonumber(row.classID)
    local band = classID and SPEC_RANGE_BY_CLASS_ID[classID]
    if not band then return true end
    return specId >= band[1] and specId <= band[2]
end

--- Resolve db.global.characters row for Gear tab (GUID canonical + legacy roster index).
---@param charKey string|nil UI / storage key
---@return table|nil row
---@return string|nil rosterKey Key under db.characters when found
local function ResolveGearRosterRow(charKey)
    local g = WarbandNexus.db and WarbandNexus.db.global
    local chars = g and g.characters
    if not chars or not charKey or charKey == "" then return nil, nil end
    if issecretvalue and issecretvalue(charKey) then return nil, nil end
    local U = ns.Utilities
    local canon = (U and U.GetCanonicalCharacterKey) and (U:GetCanonicalCharacterKey(charKey) or charKey) or charKey
    if chars[canon] then return chars[canon], canon end
    if charKey ~= canon and chars[charKey] then return chars[charKey], charKey end
    for rosterKey, row in pairs(chars) do
        if type(row) == "table" and U and U.GetCanonicalCharacterKey then
            local ck = U:GetCanonicalCharacterKey(rosterKey)
            if ck == canon then
                return row, rosterKey
            end
        end
    end
    if type(canon) == "string" then
        for rosterKey, row in pairs(chars) do
            if type(row) == "table" then
                local g = row.guid
                if type(g) == "string" and g ~= "" and g == canon
                    and not (issecretvalue and issecretvalue(g)) then
                    return row, rosterKey
                end
            end
        end
    end
    return nil, canon
end

local function GearPayloadSpecMatchesCharacter(charKey, gearEntry)
    local row = ResolveGearRosterRow(charKey)
    if not row or not gearEntry or not gearEntry.slots then return true end
    local checked, mismatched = 0, 0
    for _, slot in pairs(gearEntry.slots) do
        if GearDataSlotHasPayload(slot) and slot.itemLink then
            local specId = ExtractLinkPlayerSpecId(slot.itemLink)
            if specId then
                checked = checked + 1
                if not LinkSpecMatchesCharacterRow(row, specId) then
                    mismatched = mismatched + 1
                end
            end
        end
    end
    if checked == 0 then return true end
    return mismatched == 0
end

---@param entry table|nil gearData bucket
---@return table|nil
local function NormalizeLegacyGearDataBuckets(entry)
    if type(entry) ~= "table" then return entry end
    local slots = entry.slots
    if type(slots) ~= "table" or not GearSlotsUseSequentialPaperdollIndex(slots) then
        return entry
    end
    local normalized = {}
    for i = 1, #GEAR_SLOTS do
        local sid = GEAR_SLOTS[i].id
        local legacyRow = slots[i]
        local atId = slots[sid]
        if GearDataSlotHasPayload(legacyRow) and not GearDataSlotHasPayload(atId) then
            normalized[sid] = legacyRow
        elseif GearDataSlotHasPayload(atId) then
            normalized[sid] = atId
        end
    end
    entry.slots = normalized

    local marks = entry.watermarks
    if type(marks) == "table" then
        local wmNorm = {}
        for i = 1, #GEAR_SLOTS do
            local sid = GEAR_SLOTS[i].id
            if marks[sid] ~= nil then
                wmNorm[sid] = marks[sid]
            elseif marks[i] ~= nil then
                wmNorm[sid] = marks[i]
            end
        end
        entry.watermarks = wmNorm
    end
    return entry
end

local function LivePlayerHasAnyEquippedItem()
    if not GetInventoryItemLink then return false end
    for i = 1, #GEAR_SLOTS do
        local sid = GEAR_SLOTS[i].id
        local link = GetInventoryItemLink("player", sid)
        if link and link ~= "" and not (issecretvalue and issecretvalue(link)) then
            return true
        end
    end
    return false
end

--- Reject scans that would persist starter/foreign gear under a high-ilvl roster row.
local function GearPayloadPlausibleForCharacter(charKey, gearEntry)
    local row = ResolveGearRosterRow(charKey)
    if not row or not gearEntry then return true end
    if CountGearDataPayloadSlots(gearEntry) == 0 then return true end
    local rosterIlvl = tonumber(row.itemLevel) or 0
    local payloadIlvl = AverageGearPayloadIlvl(gearEntry)
    if rosterIlvl > 0 and payloadIlvl > 0 and payloadIlvl < rosterIlvl - 50 then
        return false
    end
    if not GearPayloadSpecMatchesCharacter(charKey, gearEntry) then
        return false
    end
    return true
end

--- Hide corrupt snapshots in the UI without mutating SavedVariables on browse.
local function SanitizeGearDataForView(charKey, entry)
    if not entry then return nil end
    NormalizeLegacyGearDataBuckets(entry)
    if GearPayloadPlausibleForCharacter(charKey, entry) then
        return entry
    end
    local view = {}
    for k, v in pairs(entry) do
        if k ~= "slots" and k ~= "watermarks" then
            view[k] = v
        end
    end
    view.slots = {}
    view.watermarks = {}
    return view
end

local function TryRecoverPlausibleGearEntry(charKey, entry, db)
    if not entry then return nil end
    NormalizeLegacyGearDataBuckets(entry)
    if GearPayloadPlausibleForCharacter(charKey, entry) then
        return entry
    end
    local row = ResolveGearRosterRow(charKey)
    local U = ns.Utilities
    if not row or not U or not U.GetCharacterKey then
        return entry
    end
    local legacyKey = U:GetCharacterKey(row.name, row.realm)
    if not legacyKey or legacyKey == charKey or not db[legacyKey] then
        return entry
    end
    local legacy = db[legacyKey]
    NormalizeLegacyGearDataBuckets(legacy)
    if GearPayloadPlausibleForCharacter(charKey, legacy) then
        return legacy
    end
    return entry
end

local function FinishGearDataRead(charKey, entry)
    if not entry then return nil end
    return SanitizeGearDataForView(charKey, entry)
end

local function GearStorageKeysMatch(storageKey, currentKey)
    if not storageKey or not currentKey then return false end
    if storageKey == currentKey then return true end
    local U = ns.Utilities
    if not U or not U.GetCanonicalCharacterKey then return false end
    local a = U:GetCanonicalCharacterKey(storageKey) or storageKey
    local b = U:GetCanonicalCharacterKey(currentKey) or currentKey
    return a ~= "" and a == b
end

---@param charKey string|nil
---@return table|nil
---@return string|nil
function WarbandNexus:ResolveGearRosterRow(charKey)
    return ResolveGearRosterRow(charKey)
end

local function PromoteLegacyGearDataBucket(db, canonKey, legacyKey)
    if not db or not canonKey or not legacyKey or canonKey == legacyKey or not db[legacyKey] then
        return nil
    end
    local legacy = db[legacyKey]
    local cur = db[canonKey]
    if cur and not ShouldUseLegacyGearDataBucket(cur, legacy) then
        return cur
    end
    if not db[canonKey] then
        db[canonKey] = {}
    end
    db[canonKey] = MergeGearDataBucket(db[canonKey], legacy)
    db[legacyKey] = nil
    WarbandNexus:InvalidatePersistedUpgradeInfoCacheForChar(canonKey)
    return db[canonKey]
end

local function ShouldUseLegacyGearDataBucket(current, legacy)
    local currentSlots = CountGearDataPayloadSlots(current)
    local legacySlots = CountGearDataPayloadSlots(legacy)
    if legacySlots ~= currentSlots then
        return legacySlots > currentSlots
    end
    return (tonumber(legacy.lastScan) or 0) > (tonumber(current.lastScan) or 0)
end

local function MergeMissingGearDataSlots(target, donor)
    local donorSlots = type(donor) == "table" and donor.slots
    if type(donorSlots) ~= "table" then return end
    local donorNorm = { slots = donorSlots }
    NormalizeLegacyGearDataBuckets(donorNorm)
    donorSlots = donorNorm.slots
    if type(target.slots) ~= "table" then
        target.slots = donorSlots
        return
    end
    for slotID, donorSlot in pairs(donorSlots) do
        local targetSlot = target.slots[slotID]
        if GearDataSlotHasPayload(donorSlot) and not GearDataSlotHasPayload(targetSlot) then
            target.slots[slotID] = donorSlot
        end
    end
end

local function MergeGearDataWatermarks(target, donor)
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

    local curNorm = { slots = current.slots, watermarks = current.watermarks }
    local legNorm = { slots = legacy.slots, watermarks = legacy.watermarks }
    NormalizeLegacyGearDataBuckets(curNorm)
    NormalizeLegacyGearDataBuckets(legNorm)
    if curNorm.slots then current.slots = curNorm.slots end
    if curNorm.watermarks then current.watermarks = curNorm.watermarks end
    if legNorm.slots then legacy.slots = legNorm.slots end
    if legNorm.watermarks then legacy.watermarks = legNorm.watermarks end

    local target = current
    local donor = legacy
    if ShouldUseLegacyGearDataBucket(current, legacy) then
        target = legacy
        donor = current
    end

    MergeMissingGearDataSlots(target, donor)
    MergeGearDataWatermarks(target, donor)

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

local function MigrateLegacyGearDataKey(db, storageKey)
    if not db or not storageKey then return end
    local U = ns.Utilities
    if not U or not U.GetCharacterKey then return end
    local legacy = U:GetCharacterKey()
    if not legacy or legacy == "" or legacy == storageKey or not db[legacy] then return end
    db[storageKey] = MergeGearDataBucket(db[storageKey], db[legacy])
    db[legacy] = nil
end

local function MaybeMigrateLegacyGearDataKey(db, storageKey)
    if ns.Utilities and ns.Utilities.IsGuidOnlySubsidiaryReads and ns.Utilities:IsGuidOnlySubsidiaryReads() then
        return
    end
    local currentKey = ResolveGearStorageKey()
    if not GearStorageKeysMatch(storageKey, currentKey) then
        return
    end
    MigrateLegacyGearDataKey(db, storageKey)
end

-- ITEM LEVEL RESOLUTION

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

ns.Gear_GetEffectiveIlvl = GetEffectiveIlvl

--- Drop session upgrade reconstruction for one character (after live ilvl overlay).
---@param charKey string|nil
function WarbandNexus:InvalidatePersistedUpgradeInfoCacheForChar(charKey)
    if not charKey then return end
    local canon = charKey
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        canon = U:GetCanonicalCharacterKey(charKey) or charKey
    end
    persistedUpgradeInfoSessionCache[canon] = nil
end

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

-- TOOLTIP UPGRADE SCAN  (Fallback when C_ItemUpgrade API is unavailable/empty)

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
                if not isCrafted then
                    local lower = string.lower(text)
                    if lower:find("crafted", 1, true) or lower:find("radiance crafted", 1, true) then
                        isCrafted = true
                    end
                end
            end
        end
    end

    if result then
        result.trackName = NormalizeUpgradeTrackName(result.trackName) or result.trackName
        result.isCrafted = isCrafted or (result.trackName == "Crafted")
    end
    return result
end

-- UPGRADE DATA PERSISTENCE  (Captures C_ItemUpgrade state during gear scan)

local function FindUpgradeLevelInfo(levelInfos, upgradeLevel)
    if not levelInfos or not upgradeLevel then return nil end
    for i = 1, #levelInfos do
        local row = levelInfos[i]
        if row and row.upgradeLevel == upgradeLevel then
            return row
        end
    end
    return levelInfos[upgradeLevel]
end

local function ScanSlotUpgradeData(slotEntry, slotID)
    if not C_ItemUpgrade or not ItemLocation then return end

    pcall(function()
        local tooltipInfo = ScanUpgradeFromTooltip(slotID)
        if tooltipInfo and tooltipInfo.trackName then
            slotEntry.upgradeTrack = tooltipInfo.trackName
            if tooltipInfo.currUpgrade then
                slotEntry.currUpgrade = tooltipInfo.currUpgrade
            end
            if tooltipInfo.maxUpgrade then
                slotEntry.maxUpgrade = tooltipInfo.maxUpgrade
            end
            if tooltipInfo.isCrafted then
                slotEntry.isCrafted = true
            end
        end

        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
        if not location or not location:IsValid() then return end

        local info = C_ItemUpgrade.GetItemUpgradeItemInfo
                     and C_ItemUpgrade.GetItemUpgradeItemInfo(location)
        if not info then return end

        local currUpgrade = info.currUpgrade or 0
        local maxUpgrade  = info.maxUpgrade or 0
        if info.itemUpgradeable == false then
            slotEntry.notUpgradeable = true
            slotEntry.itemUpgradeable = false
        elseif info.itemUpgradeable == true then
            slotEntry.itemUpgradeable = true
        end

        if currUpgrade == 0 and maxUpgrade == 0 then
            -- API returned data but no track info.
            if info.itemUpgradeable == false then
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

        if info.customUpgradeString and info.customUpgradeString ~= ""
            and not (issecretvalue and issecretvalue(info.customUpgradeString)) then
            slotEntry.customUpgradeString = info.customUpgradeString
        end

        -- Track label: customUpgradeString / tooltip only — info.name is the item name, not Hero/Myth.
        local trackName, labelCur, labelMax = ParseUpgradeLabelString(slotEntry.customUpgradeString)
        if not trackName then
            local tooltipInfo = ScanUpgradeFromTooltip(slotID)
            if tooltipInfo and tooltipInfo.trackName then
                trackName = NormalizeUpgradeTrackName(tooltipInfo.trackName)
                labelCur = tooltipInfo.currUpgrade
                labelMax = tooltipInfo.maxUpgrade
            end
        end
        slotEntry.currUpgrade = currUpgrade
        slotEntry.maxUpgrade = maxUpgrade
        if labelCur and labelMax and labelMax > 0 and (not currUpgrade or currUpgrade == 0) then
            slotEntry.currUpgrade = labelCur
            slotEntry.maxUpgrade = labelMax
        end
        slotEntry.maxIlvl      = info.maxItemLevel or 0
        if maxUpgrade > 0 and currUpgrade >= maxUpgrade then
            slotEntry.notUpgradeable = true
        end
        -- Mark crafted items: link probe is definitive (crafting quality on the link);
        -- Midnight crafted items show "Myth 5/6" as track, not "Crafted", and the
        -- tooltip-line fallback fails whenever the Upgrade Level line does not parse.
        if trackName == "Crafted" then
            slotEntry.isCrafted = true
        elseif not slotEntry.isCrafted then
            local probed = GearLinkIsCrafted(slotEntry.itemLink)
            if probed ~= nil then
                slotEntry.isCrafted = probed
            else
                local tooltipInfo = ScanUpgradeFromTooltip(slotID)
                if tooltipInfo and tooltipInfo.isCrafted then
                    slotEntry.isCrafted = true
                end
            end
        end

        -- Persist next-level costs so UI can show "affordable" badge offline
        local hasNext = (currUpgrade < maxUpgrade)
        if hasNext then
            local levelInfos = info.upgradeLevelInfos or {}
            local nextInfo = FindUpgradeLevelInfo(levelInfos, currUpgrade + 1)
            if nextInfo then
                local inc = tonumber(nextInfo.itemLevelIncrement)
                local baseIlvl = tonumber(slotEntry.itemLevel) or 0
                if inc and inc > 0 and baseIlvl > 0 then
                    slotEntry.nextStepIlvl = baseIlvl + inc
                end
                if nextInfo.moneyCost and nextInfo.moneyCost > 0 then
                    slotEntry.nextUpgradeMoneyCost = nextInfo.moneyCost
                end
                if nextInfo.currencyCostsToUpgrade then
                    local costs = {}
                    for i = 1, #nextInfo.currencyCostsToUpgrade do
                        local norm = NormalizeUpgradeCurrencyCostEntry(nextInfo.currencyCostsToUpgrade[i])
                        if norm then
                            costs[#costs + 1] = norm
                            if norm.isDiscounted then
                                slotEntry.nextUpgradeIsDiscounted = true
                            end
                        end
                    end
                    if #costs > 0 then
                        slotEntry.nextUpgradeCosts = costs
                    end
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

        local labelTrack = NormalizeUpgradeTrackName(slotEntry.upgradeTrack)
            or trackName
        local costTrack = ResolveTrackFromPersistedCosts(slotEntry)
        if costTrack and TRACK_ILVLS[costTrack] then
            if not labelTrack or costTrack == labelTrack then
                slotEntry.upgradeTrack = costTrack
            end
        elseif labelTrack and TRACK_ILVLS[labelTrack] then
            slotEntry.upgradeTrack = labelTrack
        elseif trackName and TRACK_ILVLS[trackName] then
            slotEntry.upgradeTrack = trackName
        end
    end)
end

--- Refresh equipped slot metadata from live inventory (ilvl, quality, C_ItemUpgrade track).
---@param gearData table|nil
---@return table|nil gearData same table, mutated in place
function WarbandNexus:OverlayLiveEquippedIlvlOnGearData(gearData)
    if not gearData then return gearData end
    if not gearData.slots then
        gearData.slots = {}
    end
    local slotDefs = ns.GEAR_SLOTS
    if not slotDefs then return gearData end
    for si = 1, #slotDefs do
        local slotID = slotDefs[si].id
        local itemLink = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
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
            local ilvl = GetEffectiveIlvl(itemLink) or 0
            local quality = GetItemQuality(itemLink) or 0
            local slot = gearData.slots[slotID]
            if not slot then
                slot = {}
                gearData.slots[slotID] = slot
            end
            slot.itemLink = itemLink
            slot.itemID = itemID or slot.itemID
            slot.itemLevel = ilvl
            if quality > 0 then
                slot.quality = quality
            end
            ScanSlotUpgradeData(slot, slotID)
            local tn = NormalizeUpgradeTrackName(slot.upgradeTrack)
            if tn and TRACK_ILVLS[tn] and slot.currUpgrade and slot.maxUpgrade then
                local tc, tm = ReconcileUpgradeTierForSlot(tn, ilvl, slot.currUpgrade, slot.maxUpgrade)
                slot.upgradeTrack = tn
                slot.currUpgrade = tc
                slot.maxUpgrade = tm
            end
        end
    end
    return gearData
end

-- GEAR SCANNING  (Current character only — requires live API)

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
                ScanSlotUpgradeData(slotEntry, slotID)
                local tn = NormalizeUpgradeTrackName(slotEntry.upgradeTrack)
                if tn and TRACK_ILVLS[tn] and slotEntry.currUpgrade and slotEntry.maxUpgrade then
                    local tc, tm = ReconcileUpgradeTierForSlot(tn, ilvl, slotEntry.currUpgrade, slotEntry.maxUpgrade)
                    slotEntry.upgradeTrack = tn
                    slotEntry.currUpgrade = tc
                    slotEntry.maxUpgrade = tm
                end
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
                ScanSlotUpgradeData(slotEntry, slotID)
                local tn = NormalizeUpgradeTrackName(slotEntry.upgradeTrack)
                if tn and TRACK_ILVLS[tn] and slotEntry.currUpgrade and slotEntry.maxUpgrade then
                    local tc, tm = ReconcileUpgradeTierForSlot(tn, ilvl, slotEntry.currUpgrade, slotEntry.maxUpgrade)
                    slotEntry.upgradeTrack = tn
                    slotEntry.currUpgrade = tc
                    slotEntry.maxUpgrade = tm
                elseif not slotEntry.upgradeTrack and ilvl > 0 and (ilvl < 220 or ilvl > 289) then
                    slotEntry.notUpgradeable = true
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

local function FinalizeEquippedGearPersist(charKey, slots, watermarks, baselineGearData, triggerSlotID, changedSlotIDs, silent)
    local preservedModelView = baselineGearData and baselineGearData.modelView
    local db = GetDB()
    if not db then return end

    local newPayload = CountGearDataPayloadSlots({ slots = slots })
    local baselinePayload = CountGearDataPayloadSlots(baselineGearData)
    if newPayload == 0 and baselinePayload > 0 then
        -- Logout / reload edge: inventory APIs can return nil while watermarks still copy forward.
        if WarbandNexus._gearSkipEmptyWipe or LivePlayerHasAnyEquippedItem() then
            return
        end
    end

    if not GearPayloadPlausibleForCharacter(charKey, { slots = slots }) then
        if baselinePayload > 0 or LivePlayerHasAnyEquippedItem() then
            return
        end
    end

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
    MaybeMigrateLegacyGearDataKey(db, charKey)

    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then return end

    local baselineGearData = db[charKey]
    if baselineGearData then
        NormalizeLegacyGearDataBuckets(baselineGearData)
    end
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
    MaybeMigrateLegacyGearDataKey(db, charKey)

    local baselineGearData = db[charKey]
    if baselineGearData then
        NormalizeLegacyGearDataBuckets(baselineGearData)
    end
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

---Cancel debounced gear scan and persist equipped gear on PLAYER_LOGOUT.
function WarbandNexus:FlushGearCacheOnLogout()
    if gearScanTimer then
        gearScanTimer:Cancel()
        gearScanTimer = nil
    end
    if ns.CharacterService and ns.CharacterService:IsCharacterTracked(self) then
        self._gearSkipEmptyWipe = true
        self:ScanEquippedGear()
        self._gearSkipEmptyWipe = nil
    end
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
    MaybeMigrateLegacyGearDataKey(db, charKey)
    if db[charKey] then
        local entry = TryRecoverPlausibleGearEntry(charKey, db[charKey], db)
        return FinishGearDataRead(charKey, entry)
    end

    -- Alt roster / post-GUID migration: gear may still live under that character's Name-Realm only.
    local gchars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    if U and U.GetCharacterKey and gchars then
        local row = gchars[charKey]
        if not row and type(charKey) == "string" then
            for _, v in pairs(gchars) do
                if type(v) == "table" then
                    local g = v.guid
                    if type(g) == "string" and g ~= "" and g == charKey
                        and not (issecretvalue and issecretvalue(g)) then
                        row = v
                        break
                    end
                end
            end
        end
        if type(row) == "table" and row.name then
            local legacyKey = U:GetCharacterKey(row.name, row.realm)
            if legacyKey and legacyKey ~= charKey and db[legacyKey] then
                local promoted = PromoteLegacyGearDataBucket(db, charKey, legacyKey)
                if promoted then
                    return FinishGearDataRead(charKey, promoted)
                end
                local legacy = db[legacyKey]
                local cur = db[charKey]
                if not cur or CountGearDataPayloadSlots(legacy) > CountGearDataPayloadSlots(cur) then
                    return FinishGearDataRead(charKey, legacy)
                end
            end
        end
    end

    -- Pre-migration only: logged-in player's own Name-Realm bucket while UI passes GUID key.
    if not (U and U.IsGuidOnlySubsidiaryReads and U:IsGuidOnlySubsidiaryReads()) and U and U.GetCharacterKey then
        local currentKey = ResolveGearStorageKey()
        if GearStorageKeysMatch(charKey, currentKey) then
            local legacy = U:GetCharacterKey()
            if legacy and legacy ~= charKey and db[legacy] then
                local canonLegacy = (U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(legacy)) or legacy
                if canonLegacy == charKey then
                    return FinishGearDataRead(charKey, db[legacy])
                end
            end
        end
    end
    return nil
end

--- Count equipped slots that have displayable item payload (link/id/ilvl).
---@param gearData table|nil
---@return number
function WarbandNexus:CountGearEquippedPayloadSlots(gearData)
    return CountGearDataPayloadSlots(gearData)
end

--- Load gear + live overlay for the Gear tab's selected character only.
---@param charKey string|nil UI / roster key
---@param canonicalKey string|nil Pre-resolved storage key (optional)
---@return table|nil gearData
---@return boolean isViewingLoggedInPlayer
function WarbandNexus:PrepareGearTabViewData(charKey, canonicalKey)
    local U = ns.Utilities
    local canon = canonicalKey
    if not canon and charKey and U and U.GetCanonicalCharacterKey then
        canon = U:GetCanonicalCharacterKey(charKey) or charKey
    elseif not canon then
        canon = charKey
    end

    local isLive = false
    if self.IsGearTabCharacterLoggedInPlayer then
        if charKey then
            isLive = self:IsGearTabCharacterLoggedInPlayer(charKey)
        end
        if not isLive and canon then
            isLive = self:IsGearTabCharacterLoggedInPlayer(canon)
        end
    end

    local gearData = (canon and self.GetEquippedGear and self:GetEquippedGear(canon)) or nil

    if isLive then
        gearData = gearData or { slots = {}, watermarks = {} }
        if self.OverlayLiveEquippedIlvlOnGearData then
            self:OverlayLiveEquippedIlvlOnGearData(gearData)
        end
        if CountGearDataPayloadSlots(gearData) > 0 and self.ScanEquippedGear then
            self:ScanEquippedGear(nil, { silent = true })
            local persisted = (canon and self.GetEquippedGear and self:GetEquippedGear(canon)) or nil
            if persisted and CountGearDataPayloadSlots(persisted) > 0 then
                gearData = persisted
                if self.OverlayLiveEquippedIlvlOnGearData then
                    self:OverlayLiveEquippedIlvlOnGearData(gearData)
                end
            end
        end
        if canon and self.InvalidatePersistedUpgradeInfoCacheForChar then
            self:InvalidatePersistedUpgradeInfoCacheForChar(canon)
        end
    end

    return gearData, isLive
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

-- UPGRADE ANALYSIS  (No API — ilvl-based inference from DB only, works offline)

local function SyncUpgradeEntryFromPersistedSlot(up, slot)
    if not up or not slot or up.isCrafted or up.notUpgradeable then return up end
    local ilvl = tonumber(slot.itemLevel) or 0
    if ilvl <= 0 then return up end
    local trackName = NormalizeUpgradeTrackName(slot.upgradeTrack) or up.trackName
    local tCur, tMax = slot.currUpgrade, slot.maxUpgrade
    if trackName and TRACK_ILVLS[trackName] and tCur and tMax and tMax > 0 then
        tCur, tMax = ReconcileUpgradeTierForSlot(trackName, ilvl, tCur, tMax)
    else
        trackName, tCur, tMax = ResolveSlotUpgradeTrackAndTier(slot)
    end
    if not trackName or not tCur or not tMax then return up end
    slot.upgradeTrack = trackName
    slot.currUpgrade = tCur
    slot.maxUpgrade = tMax
    up.trackName = trackName
    up.currUpgrade = tCur
    up.maxUpgrade = tMax
    up.currentIlvl = ilvl
    local tiers = TRACK_ILVLS[trackName]
    local hasNext = (tCur < tMax) and slot.itemUpgradeable ~= false
    up.canUpgrade = hasNext
    if tiers and tiers[tMax] then
        up.maxIlvl = tiers[tMax]
    end
    if hasNext then
        local stepIlvl = tonumber(slot.nextStepIlvl)
        if stepIlvl and stepIlvl > ilvl then
            up.nextIlvl = stepIlvl
        elseif tiers and tiers[tCur + 1] then
            up.nextIlvl = tiers[tCur + 1]
        end
        local currencyID, crestCost, moneyCost, isDiscounted = ResolveNextUpgradeCosts(slot, trackName, true)
        up.currencyID = currencyID
        up.crestCost = crestCost
        up.moneyCost = moneyCost
        up.nextUpgradeIsDiscounted = isDiscounted
    else
        up.nextIlvl = ilvl
        up.crestCost = 0
        up.nextUpgradeIsDiscounted = false
    end
    up.upgradeArrowDisplay = nil
    if ns.GearUI_EnsureUpgradeRowCurrencyMatchesTrack then
        ns.GearUI_EnsureUpgradeRowCurrencyMatchesTrack(up)
    end
    return up
end

ns.Gear_SyncUpgradeEntryFromSlot = SyncUpgradeEntryFromPersistedSlot

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
    if upCache and upCache.lastScan == ls and upCache.upgrades
        and upCache.logicVer == PERSISTED_UPGRADE_INFO_LOGIC_VER then
        return upCache.upgrades
    end

    local watermarks = gearData.watermarks or {}

    for slotID, slot in pairs(gearData.slots) do
        local itemLevel = tonumber(slot.itemLevel) or 0
        local trackName = NormalizeUpgradeTrackName(slot.upgradeTrack)
        if trackName and not TRACK_ILVLS[trackName] then
            trackName = nil
        end
        local currUpgrade = slot.currUpgrade
        local maxUpgrade = slot.maxUpgrade

        if not trackName or not currUpgrade or not maxUpgrade or maxUpgrade == 0 then
            trackName, currUpgrade, maxUpgrade = ResolveSlotUpgradeTrackAndTier(slot)
        elseif trackName and TRACK_ILVLS[trackName] and itemLevel > 0 then
            currUpgrade, maxUpgrade = ReconcileUpgradeTierForSlot(trackName, itemLevel, currUpgrade, maxUpgrade)
        end

        if slot.itemUpgradeable == false then
            slot.notUpgradeable = true
        end

        -- Crafted / not-upgradeable normally come from ScanSlotUpgradeData. For slots
        -- persisted by older scans (isCrafted never written) run the cheap link probe
        -- once and PERSIST the verdict — without this, a crafted 285 item fell into the
        -- dropped Myth track and advertised a 6/6 (289) crest upgrade it cannot take.
        -- (The expensive C_TooltipInfo.GetHyperlink probe stays out of this path.)
        if slot.isCrafted == nil and trackName == "Crafted" then
            slot.isCrafted = true
        end
        if slot.isCrafted == nil and slot.itemLink then
            local probed = GearLinkIsCrafted(slot.itemLink)
            if probed ~= nil then
                slot.isCrafted = probed
            end
        end
        if InferSlotIsCraftedGear(slot, trackName, itemLevel) then
            slot.isCrafted = true
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
            -- Crafted items: NO Hero/Myth crest-track upgrades — they recraft with
            -- crests to jump tiers (separate system). Caps at 285 (Myth), not 289.
            -- Tier name = the RANGE the ilvl falls in: above the next-lower tier's cap.
            -- (Comparing against the tier's own cap mislabeled e.g. 280 as Hero.)
            local craftedTierName = "Crafted"
            for ci = 1, #CRAFTED_CREST_TIERS do
                local lowerCap = CRAFTED_CREST_TIERS[ci + 1] and CRAFTED_CREST_TIERS[ci + 1].maxIlvl or 0
                if itemLevel > lowerCap then
                    craftedTierName = CRAFTED_CREST_TIERS[ci].name
                    break
                end
            end
            local canUpgrade = (itemLevel < CRAFTED_CREST_TIERS[1].maxIlvl)
            -- Crafted gear caps at tier 5/6 on EVERY track (285 Myth, 272 Hero, ...),
            -- not only on Myth; the Blizzard maxUpgrade=6 comes from the dropped track.
            local craftedMaxTier = maxUpgrade or 0
            if craftedMaxTier > 5 then
                craftedMaxTier = 5
                if currUpgrade and currUpgrade > 5 then
                    currUpgrade = 5
                end
            end
            upgrades[slotID] = {
                canUpgrade      = canUpgrade,
                isCrafted       = true,
                currentIlvl     = itemLevel,
                nextIlvl        = itemLevel,
                maxIlvl         = 285,
                currUpgrade     = currUpgrade or 0,
                maxUpgrade      = craftedMaxTier,
                trackName       = "Crafted",
                craftedTierName = craftedTierName,
                currencyID      = 0,
                crestCost       = 0,
                moneyCost       = 0,
                watermarkIlvl   = watermarks[slotID] or 0,
            }
        elseif trackName and currUpgrade and maxUpgrade and maxUpgrade > 0 then
            local hasNext = (currUpgrade < maxUpgrade) and slot.itemUpgradeable ~= false
            local tiers = TRACK_ILVLS[trackName]

            local nextIlvl = itemLevel
            if hasNext then
                local stepIlvl = tonumber(slot.nextStepIlvl)
                if stepIlvl and stepIlvl > itemLevel then
                    nextIlvl = stepIlvl
                elseif tiers and tiers[currUpgrade + 1] then
                    nextIlvl = tiers[currUpgrade + 1]
                end
            end

            local maxIlvl = itemLevel
            if tiers and tiers[maxUpgrade] then
                maxIlvl = tiers[maxUpgrade]
            end

            local currencyID, crestCost, moneyCost, isDiscounted = ResolveNextUpgradeCosts(slot, trackName, hasNext)

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
                nextUpgradeIsDiscounted = isDiscounted,
            }
        end
    end

    persistedUpgradeInfoSessionCache[canon] = {
        lastScan = ls,
        upgrades = upgrades,
        logicVer = PERSISTED_UPGRADE_INFO_LOGIC_VER,
    }
    return upgrades
end

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
    local haveGoldCopper = (currencyAmounts and currencyAmounts._goldCopper)
        or ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
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

-- NOTE: CountCrestStepsRemaining / SumRemainingCrestCosts / GetEffectiveNextStepCrestCost
-- were removed (zero callers). The LIVE affordability math is CalculateAffordableUpgrades
-- in GearUI.lua; GetAffordableCountAndNextCrestNeed above serves only the debug report.

--- Gear tab item hover: Dawncrest + Sources blocks removed (no vendor playbook in tooltip).
---@return table lines always empty; upgrade row stays on paperdoll only.
function WarbandNexus:GetGearItemUpgradeTooltipAppend(itemLink, slotContext)
    return {}
end

--- Internal diagnostic: upgrade info per slot (current character). No slash — dev: /run WarbandNexus:GearUpgradeDebugReport()
--- Uses same currency source as Gear tab (FromDB, normalized). Crest need = 20 or 0 (gold-only/maxed).
function WarbandNexus:GearUpgradeDebugReport()
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
    local currentKey = (self.GetCurrentGearStorageKey and self:GetCurrentGearStorageKey())
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self))
        or nil
    if not currentKey then
        self:Print("|cffff6600[WN GearUpgradeDebug]|r No current character.")
        return
    end
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(currentKey)) or {}
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(currentKey)) or {}
    local currencyAmounts = (ns.GearUI_BuildGearCurrencyAmounts and ns.GearUI_BuildGearCurrencyAmounts(currencies)) or {}
    if not ns.GearUI_BuildGearCurrencyAmounts then
        for i = 1, #currencies do
            local c = currencies[i]
            if c and c.currencyID ~= nil then
                if c.currencyID == 0 and c.isGold then
                    local copper = (c.amount or 0) * 10000 + (c.silver or 0) * 100 + (c.copper or 0)
                    currencyAmounts[0] = math.floor(copper / 10000)
                    currencyAmounts._goldCopper = copper
                else
                    currencyAmounts[c.currencyID] = (c.amount ~= nil) and c.amount or 0
                end
            end
        end
    end
    if ns.GearUI_EnrichUpgradeInfoWithAffordability then
        ns.GearUI_EnrichUpgradeInfoWithAffordability(upgradeInfo, currencyAmounts)
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
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
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
                    local current = best.equippedIlvlAtFind or 0
                    self:Print(string.format("   %s: %d -> %d (%s)", tostring(slotDef.label), current, best.itemLevel or 0, tostring(best.source or "?")))
                end
            end
        end
    end
end


-- CURRENCY SNAPSHOT  (Resources available for upgrading)

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
    local charEntry = ResolveGearRosterRow(charKey)
    if not charEntry and db and db.characters then
        charEntry = db.characters[canonicalKey] or db.characters[charKey]
    end
    if charEntry and (charEntry.gold or charEntry.silver or charEntry.copper) then
        gold = (charEntry.gold or 0) * 10000 + (charEntry.silver or 0) * 100 + (charEntry.copper or 0)
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

-- GEAR UPGRADE PLAYBOOK (removed from Gear tab UI; GetGearUpgradePlaybookText is a no-op stub)

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


-- Bind storage-find satellite deps (GearService_StorageFind.lua loads after this file).
ns.GearService = ns.GearService or {}
local GearSlots = ns.GearServiceSlots or {}
ns.GearService._storageFindDeps = {
    GEAR_SLOTS = GearSlots.GEAR_SLOTS,
    EQUIP_LOC_TO_SLOTS = GearSlots.EQUIP_LOC_TO_SLOTS,
    GetEffectiveIlvl = GetEffectiveIlvl,
    GetEquipLoc = GetEquipLoc,
    GetItemQuality = GetItemQuality,
    GetRawItemBindType = GetRawItemBindType,
    CategoryFromRawBind = CategoryFromRawBind,
    GetItemMinLevelFromItemInfo = GetItemMinLevelFromItemInfo,
    IsArmorCompatible = IsArmorCompatible,
    IsWeaponCompatible = IsWeaponCompatible,
    MatchGetItemStatsPrimariesToExpected = MatchGetItemStatsPrimariesToExpected,
    ResolveExpectedPrimaryStatFromCharacter = ResolveExpectedPrimaryStatFromCharacter,
    ResolveGearStorageKey = ResolveGearStorageKey,
    RequestGearStorageRedraw = RequestGearStorageRedraw,
}

-- After currency changes (e.g. crests spent on upgrade), re-scan gear so item ilvl/tier and watermarks stay in sync.
local GearServiceMsgListeners = ns._gearServiceMsgListeners or {}
ns._gearServiceMsgListeners = GearServiceMsgListeners
WarbandNexus.RegisterMessage(GearServiceMsgListeners, Constants.EVENTS.CURRENCY_UPDATED, function()
    InvalidateGearUpgradeCurrencyCaches()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
    if currencyGearScanTimer then currencyGearScanTimer:Cancel() end
    currencyGearScanTimer = C_Timer.NewTimer(0.4, function()
        currencyGearScanTimer = nil
        WarbandNexus:ScanEquippedGear()
    end)
end)

WarbandNexus.RegisterMessage(GearServiceMsgListeners, Constants.EVENTS.CHARACTER_UPDATED, function()
    InvalidateGearUpgradeCurrencyCaches()
end)