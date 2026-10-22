--[[
    Warband Nexus - Try Counter loot session capture (split from TryCounterService.lua, 2026-10-22)
    Spellcast hooks (fishing / pickpocket / gathering context), safe GUID helpers, container open
    attempts, fishing-zone lookups, loot session snapshot / classify / route and loot source GUIDs.
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
    DB tables are reassigned by LoadRuntimeSourceTables, so they are read as RT.* at the use site.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V and RT.lootReady, "TryCounterService_LootSession: load TryCounterService.lua first")
assert(TC.FISHING_BOBBER_NPC_IDS and TC.FISHING_BOBBER_OBJECT_IDS,
    "TryCounterService_LootSession: load TryCounterService_Process.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local lootReady = RT.lootReady
-- Learned bobber ids: the same tables TryCounterService.lua mutates (TryCounterService_Process.lua).
local FISHING_BOBBER_NPC_IDS = TC.FISHING_BOBBER_NPC_IDS
local FISHING_BOBBER_OBJECT_IDS = TC.FISHING_BOBBER_OBJECT_IDS

local UnitGUID = UnitGUID
local GetNumLootItems = GetNumLootItems
local GetLootSlotLink = GetLootSlotLink
local LootSlotHasItem = LootSlotHasItem
local GetTime = GetTime
local C_Map = C_Map
local C_Timer = C_Timer
local C_Container = C_Container
local IsInInstance = IsInInstance
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

local FISHING_SPELLS = TC.FISHING_SPELLS or {}

local FISHING_SPELL_ICON_IDS = TC.FISHING_SPELL_ICON_IDS or { [4620674] = true, [136245] = true }
local probedNonFishingSpells = TC.probedNonFishingSpells or {}
TC.probedNonFishingSpells = probedNonFishingSpells

-- Pickpocket spell IDs (Rogue): opens loot window on a mob WITHOUT killing it.
-- LOOT_OPENED fires with isFromItem=false, fishingCtx.active=false → would fall through to
-- ProcessNPCLoot → sourceGUID matches a tracked NPC → false try counter increment.
-- Detection: set V.isPickpocketing flag on spell cast, skip ProcessNPCLoot, clear on LOOT_CLOSED.
local PICKPOCKET_SPELLS = {
    [921] = true,     -- Pick Pocket
}

-- Profession/gathering spell IDs that open a loot window on a corpse/node WITHOUT killing it.
-- These spells fire LOOT_OPENED, and the sourceGUID may be a tracked NPC (e.g., skinning a rare
-- corpse, mining a node near a boss chest). Without this guard, ProcessNPCLoot would run and
-- potentially match the sourceGUID against npcDropDB, causing a false try count increment.
-- Defense-in-depth: filters out profession-sourced loot events that share NPC GUIDs.
-- Flag set on UNIT_SPELLCAST_SENT, cleared on LOOT_CLOSED.
local PROFESSION_LOOT_SPELLS = {
    -- Skinning
    [8613] = true,      -- Skinning (generic)
    [194174] = true,    -- Skinning (Legion variant)
    [195125] = true,    -- Skinning (BfA variant)
    [265856] = true,    -- Skinning (BfA Kul Tiran)
    [265858] = true,    -- Skinning (BfA Zandalari)
    [324801] = true,    -- Skinning (Shadowlands)
    [366262] = true,    -- Skinning (Dragonflight)
    [423344] = true,    -- Skinning (TWW)
    [471014] = true,    -- Skinning (Midnight 12.0)
    -- Mining (these open loot on mining nodes, not corpses, but guard just in case)
    [2575] = true,      -- Mining (generic)
    [195122] = true,    -- Mining (BfA variant)
    [265854] = true,    -- Mining (BfA Kul Tiran)
    [265846] = true,    -- Mining (BfA Zandalari)
    [324802] = true,    -- Mining (Shadowlands)
    [366260] = true,    -- Mining (Dragonflight)
    [423343] = true,    -- Mining (TWW)
    [471013] = true,    -- Mining (Midnight 12.0)
    -- Herbalism
    [2366] = true,      -- Herb Gathering (generic)
    [195114] = true,    -- Herbalism (BfA variant)
    [265852] = true,    -- Herbalism (BfA Kul Tiran)
    [265842] = true,    -- Herbalism (BfA Zandalari)
    [324804] = true,    -- Herbalism (Shadowlands)
    [366261] = true,    -- Herbalism (Dragonflight)
    [423342] = true,    -- Herbalism (TWW)
    [471022] = true,    -- Herbalism (Midnight 12.0)
    -- Disenchanting
    [13262] = true,     -- Disenchant
    -- Prospecting
    [31252] = true,     -- Prospecting
    -- Milling
    [51005] = true,     -- Milling
    -- Salvaging (Garrison / Profession)
    [168065] = true,    -- Salvage (WoD Salvage Yard)
    [382984] = true,    -- Salvaging (DF variant)
    -- Milling / Prospecting new IDs (DF/TWW)
    [390396] = true,    -- Mass Milling (DF)
    [389191] = true,    -- Mass Prospecting (DF)
}

local lastGatherCastName = nil
local lastGatherCastTime = 0
local lastSafeMapID = nil  -- cached last known good mapID for fallback when API returns nil/secret

function Fns.ClearTryCounterGatherCastGuard()
    lastGatherCastTime = 0
    lastGatherCastName = nil
end

---Begin fishing context when a known Fishing spell starts (shared by SENT + CHANNEL_START).
---@param spellID number|nil
function WarbandNexus:TryCounterBeginFishingContext(spellID)
    if spellID then
        if issecretvalue and issecretvalue(spellID) then return end
        if not FISHING_SPELLS[spellID] then return end
    end
    RT.fishingCtx.active = true
    RT.fishingCtx.castTime = GetTime()
    -- Safety: if the bite never completes and LOOT_CLOSED never fires, clear context so chests/mobs
    -- are not misclassified. Match FISHING_CAST_CONTEXT_TTL so long channels still count.
    if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel() end
    RT.fishingCtx.resetTimer = C_Timer.NewTimer(RT.FISHING_CAST_CONTEXT_TTL, function()
        RT.fishingCtx.active = false
        RT.fishingCtx.castTime = 0
        RT.fishingCtx.resetTimer = nil
    end)
end

--- One-shot GetSpellInfo probe for unknown player casts; caches confirmed non-fishing ids.
local function ResolveTryCounterFishingSpell(spellID)
    if not spellID then return false end
    if FISHING_SPELLS[spellID] then return true end
    if probedNonFishingSpells[spellID] then return false end
    if not C_Spell or not C_Spell.GetSpellInfo then
        return false
    end
    local ok, spellInfo = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or not spellInfo then
        probedNonFishingSpells[spellID] = true
        return false
    end
    local iconID = spellInfo.iconID
    if iconID and not (issecretvalue and issecretvalue(iconID)) and FISHING_SPELL_ICON_IDS[iconID] then
        FISHING_SPELLS[spellID] = true
        return true
    end
    probedNonFishingSpells[spellID] = true
    return false
end

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if not Fns.IsTryCounterModuleEnabled() then return end
    -- Midnight 12.0: target/spellID can be secret values during instanced combat
    if issecretvalue and target and issecretvalue(target) then target = nil end
    if issecretvalue and spellID and issecretvalue(spellID) then
        -- We cannot read the spellID. If it's fishing, we might be able to read the channel texture.
        -- UNIT_SPELLCAST_SENT fires slightly before the channel starts, so we might not have it yet.
        -- But we can rely on UNIT_SPELLCAST_CHANNEL_START to catch it.
        return
    end
    if target then
        lastGatherCastName = target
        lastGatherCastTime = GetTime()
    end

    -- Overflowing Dumpster and other objectDropDB nodes: target is often nil on UNIT_SPELLCAST_SENT;
    -- mouseover/target GUID is reliable for attributing currency-only opens (no LOOT_OPENED).
    do
        local goGUID = Fns.SafeGetMouseoverGUID() or Fns.SafeGetTargetGUID()
        local oid = goGUID and Fns.GetObjectIDFromGUID(goGUID)
        if oid and RT.objectDropDB[oid] then
            V.lastTrackedObjectInteractID = oid
            V.lastTrackedObjectInteractGUID = goGUID
            V.lastTrackedObjectInteractTime = GetTime()
        end
    end

    if spellID and PICKPOCKET_SPELLS[spellID] then
        V.isPickpocketing = true
        V.lootSpellFlagTime = GetTime()
        return
    end
    if spellID and PROFESSION_LOOT_SPELLS[spellID] then
        V.isProfessionLooting = true
        V.lootSpellFlagTime = GetTime()
        return
    end

    if ResolveTryCounterFishingSpell(spellID) then
        self:TryCounterBeginFishingContext(spellID)
    end
end

---UNIT_SPELLCAST_CHANNEL_START — some fishing variants channel without a separate SENT we map.
---Args: unitTarget, castGUID, spellID
function WarbandNexus:OnTryCounterSpellcastChannelStart(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not Fns.IsTryCounterModuleEnabled() then return end

    local isFishing = false
    local validSpellID = spellID

    if issecretvalue and spellID and issecretvalue(spellID) then
        validSpellID = nil
        -- Secret value during instanced combat. We can't read spellID.
        -- Try to detect via UnitChannelInfo texture.
        if UnitChannelInfo then
            local _, _, texture = UnitChannelInfo("player")
            if texture and not (issecretvalue and issecretvalue(texture)) and texture == 136245 then
                isFishing = true
            end
        end
        if not isFishing then return end
    else
        isFishing = ResolveTryCounterFishingSpell(spellID)
    end

    if isFishing then
        self:TryCounterBeginFishingContext(validSpellID)
    end
end

---UNIT_SPELLCAST_INTERRUPTED / UNIT_SPELLCAST_FAILED_QUIET handler.
---Clears fishing context immediately when the initial cast fails (player moved, interrupted).
---Without this, fishingCtx.active stays true for up to 20s (safety timer), during which
---unrelated loot events (chests, untracked mobs) could be misclassified as fishing.
---Args: (unit, castGUID, spellID) — note: no target param unlike UNIT_SPELLCAST_SENT.
---@param event string
---@param unit string
---@param castGUID string
---@param spellID number
function WarbandNexus:OnTryCounterSpellcastFailed(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if issecretvalue and spellID and issecretvalue(spellID) then return end
    -- A pickpocket / gathering cast that fails opens no loot window, so LOOT_CLOSED never clears its
    -- skip flag and the next kill, catch or container would be dropped as profession loot.
    if spellID and not RT.lootSession.opened then
        if PICKPOCKET_SPELLS[spellID] then V.isPickpocketing = false end
        if PROFESSION_LOOT_SPELLS[spellID] then V.isProfessionLooting = false end
    end
    if not FISHING_SPELLS[spellID] then return end
    
    -- Clicking the bobber interrupts the fishing channel.
    -- If we clear the context instantly, LOOT_READY fires 0.1s later with NO fishing context.
    -- We delay the clearing by 1.5s to ensure the loot window can capture the context.
    local captureTime = RT.fishingCtx.castTime
    C_Timer.After(1.5, function()
        if RT.fishingCtx.active and RT.fishingCtx.castTime == captureTime and not RT.fishingCtx.lootWasFishing then
            RT.fishingCtx.active = false
            RT.fishingCtx.castTime = 0
            if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel() RT.fishingCtx.resetTimer = nil end
        end
    end)
end

-- SAFE GUID HELPERS (must be defined before event handlers)

Fns.SafeGetUnitGUID = function(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not guid then return nil end
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

Fns.SafeGetTargetGUID = function()
    return Fns.SafeGetUnitGUID("target")
end

Fns.SafeGetMouseoverGUID = function()
    return Fns.SafeGetUnitGUID("mouseover")
end

---GUID of a unit as a loot source: a living Creature/Vehicle is never what the window looted, only
---what the player happens to have selected (a rare targeted while opening a chest, node or bag).
---UnitIsDead(unit) -> isDead (warcraft.wiki.gg API_UnitIsDead, checked 2026-10-09).
Fns.SafeGetLootedUnitGUID = function(unit)
    local guid = Fns.SafeGetUnitGUID(unit)
    if not guid or not UnitIsDead then return guid end
    if not (guid:match("^Creature") or guid:match("^Vehicle")) then return guid end
    local ok, dead = pcall(UnitIsDead, unit)
    if not ok or (issecretvalue and issecretvalue(dead)) then return nil end
    return dead == true and guid or nil
end

Fns.SafeGuardGUID = function(rawGUID)
    if not rawGUID then return nil end
    if type(rawGUID) ~= "string" then return nil end
    if issecretvalue and issecretvalue(rawGUID) then return nil end
    return rawGUID
end

function Fns.SafeIsFishingLoot()
    if not IsFishingLoot then return false end
    local ok, v = pcall(IsFishingLoot)
    if not ok or v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return not not v
end

function Fns.IsFishingSourceCompatible(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return true end
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if type(srcGUID) == "string" and not (issecretvalue and issecretvalue(srcGUID)) then
            local typeStr = srcGUID:match("^(%a+)")
            local npcID = Fns.GetNPCIDFromGUID(srcGUID)
            if npcID and RT.npcDropDB[npcID] then return false end
            local objectID = Fns.GetObjectIDFromGUID(srcGUID)
            if objectID and RT.objectDropDB[objectID] then return false end
        end
    end
    return true
end

-- LOOT / CHAT_MSG_LOOT handlers: Modules/TryCounterService_Handlers.lua

---CHAT_MSG_CURRENCY / CHAT_MSG_MONEY fallback for tracked world objects (Overflowing Dumpster).
---When loot is currency-only, LOOT_OPENED may not fire; attribute a miss once per interact.
function Fns.TryProcessTrackedObjectCurrencyFallback(self)
    if not self or not Fns.IsAutoTryCounterEnabled() then return end
    if RT.pendingLootSessionFinalize or RT.lootSession.opened then return end

    local now = GetTime()
    local objectID, sourceGUID = Fns.GetTrackedObjectIDFromSourceGUIDs(RT.lootReady.sourceGUIDs)
    if not objectID and V.lastTrackedObjectInteractID
        and (now - (V.lastTrackedObjectInteractTime or 0)) < 12 then
        objectID = V.lastTrackedObjectInteractID
        sourceGUID = V.lastTrackedObjectInteractGUID
    end
    if not objectID then return end

    local dedupKey = Fns.BuildTryCountSourceKey(nil, nil, objectID, sourceGUID)
    if dedupKey and V.lastTryCountSourceKey == dedupKey
        and (now - V.lastTryCountSourceTime) < RT.CHAT_LOOT_DEBOUNCE then
        return
    end

    local drops = RT.objectDropDB and RT.objectDropDB[objectID]
    if not drops then return end
    local trackable = {}
    for i = 1, #drops do
        local drop = drops[i]
        if drop and (drop.repeatable or not Fns.IsCollectibleCollected(drop)) then
            trackable[#trackable + 1] = drop
        end
    end
    if #trackable == 0 then return end

    local allObtained = true
    for i = 1, #trackable do
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(trackable[i])
        if not tryKey or not Fns.IsObtainOutcomeApplied(tcType, tryKey, trackable[i]) then
            allObtained = false
            break
        end
    end
    if allObtained then return end

    Fns.ApplyNpcLootOutcomes(self, {
        trackable = trackable,
        found = {},
        lastMatchedObjectID = objectID,
        dedupGUID = sourceGUID,
        baselineTryCounts = Fns.CaptureTryCountBaselines(trackable),
    })
end

---Bag count of a container item (carried bags only; C_Item.GetItemCount defaults exclude banks).
---C_Item.GetItemCount(itemInfo [, includeBank ...]) -> count (warcraft.wiki.gg, checked 2026-10-09).
function Fns.GetCarriedContainerCount(itemID)
    if not (C_Item and C_Item.GetItemCount) then return nil end
    local ok, count = pcall(C_Item.GetItemCount, itemID)
    if not ok or type(count) ~= "number" or (issecretvalue and issecretvalue(count)) then return nil end
    return count
end

function Fns.ScheduleContainerOpenAttempt(cItemID, bagID, slotID)
    if not cItemID or not RT.containerDropDB[cItemID] then return end
    -- Merchant / bank / mail / trade: a right-click or drag there sells, stores or hands the cache over.
    if V.isBlockingInteractionOpen then return end
    local now = GetTime()
    V.lastContainerItemID = cItemID
    V.lastContainerItemTime = now
    V.lastObservedContainerItemID = cItemID
    V.lastObservedContainerItemTime = now

    -- One check per action. A drag or a use fires ITEM_LOCK_CHANGED for the lock and again for the
    -- unlock (and for both slots of a move); the later events must not replace the baseline count,
    -- which is taken while the item is still in the bags (hooks and the lock event run before the
    -- server consumes it).
    local pending = V.pendingContainerCheck
    if pending and pending.itemID == cItemID and (now - pending.time) < 0.75 then return end
    local baseline = Fns.GetCarriedContainerCount(cItemID)
    pending = { itemID = cItemID, time = now }
    V.pendingContainerCheck = pending

    -- Safety fallback timer: if no LOOT_OPENED, CHAT_MSG_LOOT, or CHAT_MSG_CURRENCY fired
    -- within 0.75s (e.g. silent unpack or slow client event dispatch), commit the attempt if the
    -- container was really consumed. "Consumed" is the carried count dropping: a slot that merely
    -- changed is a move, sort or bag swap, not an open.
    C_Timer.After(0.75, function()
        if V.pendingContainerCheck == pending then V.pendingContainerCheck = nil end
        local consumed
        local nowCount = baseline and Fns.GetCarriedContainerCount(cItemID)
        if baseline and nowCount then
            consumed = baseline - nowCount
        elseif bagID and slotID and C_Container and C_Container.GetContainerItemID then
            consumed = (C_Container.GetContainerItemID(bagID, slotID) == cItemID) and 0 or 1
        else
            consumed = 0   -- no evidence either way (UseItemByName / GUID with no count API)
        end
        if consumed <= 0 then
            -- Not an open: stop the CHAT_MSG_* container paths from claiming the next loot for it.
            if V.lastContainerItemID == cItemID then
                V.lastContainerItemID = nil
                V.lastContainerItemTime = 0
            end
            if V.lastObservedContainerItemID == cItemID then V.lastObservedContainerItemID = nil end
            return
        end
        if V.lastContainerItemID == cItemID and (GetTime() - (V.lastContainerItemTime or 0)) <= 3.0 then
            local nowTimer = GetTime()
            local containerSourceKey = "container_" .. tostring(cItemID)
            if V.lastTryCountSourceKey ~= containerSourceKey or (nowTimer - (V.lastTryCountSourceTime or 0)) >= RT.CHAT_LOOT_DEBOUNCE then
                V.lastContainerItemID = nil
                V.lastContainerItemTime = 0
                V.lastObservedContainerItemID = nil
                V.lastTryCountSourceKey = containerSourceKey
                V.lastTryCountSourceTime = nowTimer
                local cData = RT.containerDropDB[cItemID]
                local cDrops = cData and (cData.drops or cData)
                if cDrops and type(cDrops) == "table" and #cDrops > 0 then
                    local trackable = {}
                    for i = 1, #cDrops do
                        local d = cDrops[i]
                        if d.repeatable or not Fns.IsCollectibleCollected(d) then
                            trackable[#trackable + 1] = d
                        end
                    end
                    if #trackable > 0 then
                        Fns.TryCounterLootDebugDropLines(WarbandNexus, "Container-Direct-Fallback", trackable)
                        Fns.ProcessMissedDrops(trackable, nil, { sync = true, attemptTimes = consumed })
                    end
                end
            end
        end
    end)
end

---CHAT_MSG_CURRENCY / CHAT_MSG_MONEY fallback logic.
---In WoW, when opening containers (like Keg-Shaped Treasure Chest for Brewfest Prize Tokens)
---or gathering objects (like Overflowing Dumpster) that ONLY drop currency/money.
---@param event string
---@param message string
function WarbandNexus:OnTryCounterChatMsgCurrency(event, message)
    if not Fns.IsAutoTryCounterEnabled() then return end
    local now = GetTime()
    if V.lastContainerItemID and RT.containerDropDB[V.lastContainerItemID]
        and (now - (V.lastContainerItemTime or 0)) < 15 then
        local cItemID = V.lastContainerItemID
        local cData = RT.containerDropDB[cItemID]
        local cDrops = cData and (cData.drops or cData)
        if cDrops and type(cDrops) == "table" and #cDrops > 0 then
            local trackable = {}
            for i = 1, #cDrops do
                local d = cDrops[i]
                if d.repeatable or not Fns.IsCollectibleCollected(d) then
                    trackable[#trackable + 1] = d
                end
            end
            local containerSourceKey = "container_" .. tostring(cItemID)
            if V.lastTryCountSourceKey ~= containerSourceKey or (now - (V.lastTryCountSourceTime or 0)) >= RT.CHAT_LOOT_DEBOUNCE then
                V.lastContainerItemID = nil
                V.lastContainerItemTime = 0
                V.lastObservedContainerItemID = nil
                V.lastTryCountSourceKey = containerSourceKey
                V.lastTryCountSourceTime = now
                if #trackable > 0 then
                    Fns.TryCounterLootDebugDropLines(self, "Chat-Container-Currency", trackable)
                    Fns.ProcessMissedDrops(trackable, nil, { sync = true })
                end
                return
            end
        end
    end
    Fns.TryProcessTrackedObjectCurrencyFallback(self)
end

---ITEM_LOCK_CHANGED handler (detect container item usage for try count tracking)
---When a container item from our DB changes lock state, record its itemID so
---ProcessContainerLoot() knows which container was opened.
---@param event string
---@param bagID number Bag index (0-4 for bags, -1 for bank, etc.)
---@param slotID number|nil Slot index within the bag. nil = equipment slot change.
function WarbandNexus:OnTryCounterItemLockChanged(event, bagID, slotID)
    if not bagID or not slotID then return end
    if issecretvalue and (issecretvalue(bagID) or issecretvalue(slotID)) then return end
    local maxCarriedBagID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    if bagID < 0 or bagID > maxCarriedBagID then return end
    if not C_Container or not C_Container.GetContainerItemID then return end

    local slotKey = bagID * 100 + slotID
    local itemID = C_Container.GetContainerItemID(bagID, slotID)
    if itemID and not (issecretvalue and issecretvalue(itemID)) then
        V.bagSlotItemCache[slotKey] = itemID
    else
        itemID = V.bagSlotItemCache[slotKey]
        V.bagSlotItemCache[slotKey] = nil
    end
    if not itemID then return end
    if issecretvalue and issecretvalue(itemID) then return end
    if not RT.containerDropDB[itemID] then return end

    Fns.ScheduleContainerOpenAttempt(itemID, bagID, slotID)
end

Fns.GetSafeMapID = function()
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and not (issecretvalue and issecretvalue(rawMapID))) and rawMapID or nil
    if mapID then
        lastSafeMapID = mapID
    else
        mapID = lastSafeMapID
    end
    return mapID
end

function Fns.CollectFishingDropsForZone()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return {}, true end
    local mapID = Fns.GetSafeMapID()
    local drops = {}
    local seen = {}  -- dedup: same drop registered at child + parent map would double-count
    -- Do not auto-merge fishingDropDB[0] (global pool) into every map.
    -- Global entries (e.g. Sea Turtle) would make every zone look like a fishing
    -- try-counter zone and cause wrong attribution in Midnight maps.
    local currentMapID = mapID
    local depthGuard = 0
    while currentMapID and currentMapID > 0 do
        depthGuard = depthGuard + 1
        if depthGuard > 20 then break end  -- WoW map hierarchy is never deeper than ~5 levels
        if RT.fishingDropDB[currentMapID] then
            local mapDrops = RT.fishingDropDB[currentMapID]
            for i = 1, #mapDrops do
                local d = mapDrops[i]
                if d and d.itemID then
                    local key = (d.type or "item") .. "\0" .. tostring(d.itemID)
                    if not seen[key] then
                        seen[key] = true
                        drops[#drops + 1] = d
                    end
                end
            end
        end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(currentMapID)
        local nextID = mapInfo and mapInfo.parentMapID
        currentMapID = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
    end
    return drops, false
end

Fns.GetFishingTrackableForCurrentZone = function()
    local drops, inInstance = Fns.CollectFishingDropsForZone()
    if inInstance then return {} end
    local trackable = {}
    for i = 1, #drops do
        local d = drops[i]
        if d.repeatable or not Fns.IsCollectibleCollected(d) then trackable[#trackable + 1] = d end
    end
    return trackable
end

Fns.GetFishingDropItemIDsForCurrentZone = function()
    local drops, inInstance = Fns.CollectFishingDropsForZone()
    if inInstance or #drops == 0 then return nil end
    local set = {}
    for i = 1, #drops do
        local id = drops[i] and drops[i].itemID
        if id then set[id] = true end
    end
    return set
end

Fns.IsInTrackableFishingZone = function()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return false end
    local mapID = Fns.GetSafeMapID()
    if not mapID then return false end
    local current = mapID
    local depthGuard = 0
    while current and current > 0 do
        depthGuard = depthGuard + 1
        if depthGuard > 20 then break end  -- WoW map hierarchy is never deeper than ~5 levels
        if RT.fishingDropDB[current] then return true end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(current)
        local nextID = mapInfo and mapInfo.parentMapID
        current = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
    end
    return false
end

-- LOOT SESSION HELPERS (shared by LOOT_READY, LOOT_OPENED, LOOT_CLOSED)

function Fns.UnitGuidLooksLikeMobCorpse(guid)
    if type(guid) ~= "string" then return false end
    if issecretvalue and issecretvalue(guid) then return false end
    return guid:match("^Creature") ~= nil or guid:match("^Vehicle") ~= nil
end

function Fns.LootSessionHasAnyMobCorpseSources(sourceGUIDs)
    for i = 1, #(sourceGUIDs or {}) do
        local g = sourceGUIDs[i]
        if Fns.UnitGuidLooksLikeMobCorpse(g) then
            local nid = Fns.GetNPCIDFromGUID(g)
            if not Fns.IsFishingBobberNpcId(nid) then
                return true
            end
        end
    end
    return false
end

function Fns.LootEligibleNpcFromGuid(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local nid = Fns.GetNPCIDFromGUID(guid)
    if nid and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then return nid end
    return nil
end

function Fns.CurrentUnitsHaveEligibleNpcContext()
    local mo = Fns.SafeGetMouseoverGUID()
    local tg = Fns.SafeGetTargetGUID()
    local npc = Fns.SafeGetUnitGUID("npc")
    return Fns.LootEligibleNpcFromGuid(mo) or Fns.LootEligibleNpcFromGuid(tg) or Fns.LootEligibleNpcFromGuid(npc)
end

local function IsBlockingMobCorpseGuid(guid)
    if not guid or not Fns.UnitGuidLooksLikeMobCorpse(guid) then return false end
    local nid = Fns.GetNPCIDFromGUID(guid)
    return not Fns.IsFishingBobberNpcId(nid)
end

function Fns.LootSessionHasMobLootContext()
    return IsBlockingMobCorpseGuid(RT.lootSession.mouseoverGUID)
        or IsBlockingMobCorpseGuid(RT.lootSession.targetGUID)
        or IsBlockingMobCorpseGuid(RT.lootSession.npcGUID)
end

function Fns.LootReadySnapshotHasMobLootContext(mouseoverGUID, targetGUID, npcGUID)
    return IsBlockingMobCorpseGuid(mouseoverGUID)
        or IsBlockingMobCorpseGuid(targetGUID)
        or IsBlockingMobCorpseGuid(npcGUID)
end

Fns.CurrentUnitsHaveMobLootContext = function()
    local mo = Fns.SafeGetMouseoverGUID()
    local tg = Fns.SafeGetTargetGUID()
    local npc = Fns.SafeGetUnitGUID("npc")
    return IsBlockingMobCorpseGuid(mo) or IsBlockingMobCorpseGuid(tg) or IsBlockingMobCorpseGuid(npc)
end

Fns.ResetLootSession = function()
    RT.lootSession.numLoot = 0
    RT.lootSession.sourceGUIDs = {}
    wipe(RT.lootSession.slotData)
    RT.lootSession.mouseoverGUID = nil
    RT.lootSession.targetGUID = nil
    RT.lootSession.npcGUID = nil
    RT.lootSession.opened = false
end

local function CopyArray(src)
    local out = {}
    if src then
        for i = 1, #src do
            out[i] = src[i]
        end
    end
    return out
end

local function CopyLootSlotData(src)
    local out = {}
    if src then
        for i = 1, #src do
            local slot = src[i]
            if slot then
                out[i] = {
                    hasItem = slot.hasItem,
                    link = slot.link,
                }
            end
        end
    end
    return out
end

Fns.SnapshotLootSessionState = function()
    return {
        numLoot = RT.lootSession.numLoot or 0,
        sourceGUIDs = CopyArray(RT.lootSession.sourceGUIDs),
        slotData = CopyLootSlotData(RT.lootSession.slotData),
        mouseoverGUID = RT.lootSession.mouseoverGUID,
        targetGUID = RT.lootSession.targetGUID,
        npcGUID = RT.lootSession.npcGUID,
        opened = RT.lootSession.opened == true,
    }
end

Fns.ApplyLootSessionState = function(snapshot)
    snapshot = snapshot or {}
    RT.lootSession.numLoot = snapshot.numLoot or 0
    RT.lootSession.sourceGUIDs = CopyArray(snapshot.sourceGUIDs)
    wipe(RT.lootSession.slotData)
    local slots = snapshot.slotData
    if slots then
        for i = 1, #slots do
            local slot = slots[i]
            if slot then
                RT.lootSession.slotData[i] = {
                    hasItem = slot.hasItem,
                    link = slot.link,
                }
            end
        end
    end
    RT.lootSession.mouseoverGUID = snapshot.mouseoverGUID
    RT.lootSession.targetGUID = snapshot.targetGUID
    RT.lootSession.npcGUID = snapshot.npcGUID
    RT.lootSession.opened = snapshot.opened == true
end

local function ApplyLootReadySnapshotToSession(numLoot)
    local readyGuids = lootReady.sourceGUIDs
    for i = 1, #readyGuids do
        RT.lootSession.sourceGUIDs[i] = readyGuids[i]
    end
    for i = 1, numLoot do
        local slot = lootReady.slotData[i]
        if slot then
            RT.lootSession.slotData[i] = { hasItem = slot.hasItem, link = slot.link }
        end
    end
end

Fns.CaptureLootSessionState = function()
    Fns.ResetLootSession()
    RT.lootSession.mouseoverGUID = Fns.SafeGetLootedUnitGUID("mouseover")
    RT.lootSession.targetGUID = Fns.SafeGetLootedUnitGUID("target")
    RT.lootSession.npcGUID = Fns.SafeGetUnitGUID("npc")
    RT.lootSession.numLoot = (GetNumLootItems and GetNumLootItems()) or 0

    local now = GetTime()
    local reuseReady = lootReady.time > 0
        and (now - lootReady.time) <= RT.LOOT_READY_STATE_TTL
        and lootReady.numLoot == RT.lootSession.numLoot

    if reuseReady then
        ApplyLootReadySnapshotToSession(RT.lootSession.numLoot)
    else
        RT.lootSession.sourceGUIDs = Fns.GetAllLootSourceGUIDs() or {}
        wipe(RT.lootSession.slotData)
        for i = 1, RT.lootSession.numLoot do
            local hasItem = LootSlotHasItem and LootSlotHasItem(i)
            local link = GetLootSlotLink and GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
            RT.lootSession.slotData[i] = { hasItem = not not hasItem, link = link }
        end
    end
end

Fns.PromoteLootReadyToSession = function()
    Fns.ResetLootSession()
    if lootReady.time > 0 and (GetTime() - lootReady.time) <= RT.LOOT_READY_STATE_TTL then
        RT.lootSession.mouseoverGUID = lootReady.mouseoverGUID
        RT.lootSession.targetGUID = lootReady.targetGUID
        RT.lootSession.npcGUID = lootReady.npcGUID
        RT.lootSession.sourceGUIDs = lootReady.sourceGUIDs
        RT.lootSession.numLoot = lootReady.numLoot
        for i = 1, #lootReady.slotData do RT.lootSession.slotData[i] = lootReady.slotData[i] end
    end
end

-- CLASSIFY-LOCK-PROCESS ROUTER
-- Determines exactly ONE route per loot session. Once classified, no
-- other source type can run. Each classification is based on hard
-- signals (API flags, exact GUID types, spell context) — never heuristic
-- fallthrough from one source type to another.
--
-- Priority (first match wins, all others locked out):
--   1. SKIP       — pickpocket / blocking vendor UI / profession loot
--   2. CONTAINER  — isFromItem flag OR recent tracked container use
--   3. FISHING    — IsFishingLoot() API OR structural bobber/pool sources in fishable zone;
--                   never from cast timer + empty sources alone.
--   4. NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)

---Backstop for pickpocket / gathering casts that fail without UNIT_SPELLCAST_INTERRUPTED or
---FAILED_QUIET (e.g. "no pockets to pick" is a plain FAILED, not registered): their loot window
---opens right after the cast, so a flag older than this with no window open is stale.
function Fns.ExpireStaleLootSpellFlags()
    if not (V.isPickpocketing or V.isProfessionLooting) then return end
    if RT.lootSession.opened then return end
    if GetTime() - (V.lootSpellFlagTime or 0) <= 10 then return end
    V.isPickpocketing = false
    V.isProfessionLooting = false
end

Fns.ClassifyLootSession = function(source, isFromItem)
    -- 1. SKIP: non-combat loot sources
    Fns.ExpireStaleLootSpellFlags()
    if V.isPickpocketing then return "skip" end
    if V.isBlockingInteractionOpen then return "skip" end
    if V.isProfessionLooting then return "skip" end

    -- Gathering cast + only GameObject sources (herb/ore node) → skip
    local now = GetTime()
    -- Slightly wide window: slow clients / double LOOT_READY can exceed 5s; still only GO+no mob context.
    if lastGatherCastTime and (now - lastGatherCastTime) < 12 then
        local anyGameObject, anyMob = false, false
        for i = 1, #RT.lootSession.sourceGUIDs do
            local guid = RT.lootSession.sourceGUIDs[i]
            if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
                if guid:match("^GameObject") then anyGameObject = true end
                if guid:match("^Creature") or guid:match("^Vehicle") then anyMob = true end
            end
        end
        if anyGameObject and not anyMob and not Fns.LootSessionHasMobLootContext() then
            if not Fns.LootSessionHasTrackedObjectSource(RT.lootSession.sourceGUIDs) then
                return "skip"
            end
        end
    end

    -- GameObject-only loot (herb/ore) in open-world maps that have fishing DB entries is not fishing
    -- unless API or structural bobber/pool says so (prevents false ProcessFishingLoot on Thorncap etc.).
    -- Tracked objectDropDB sources (Overflowing Dumpster, raid chests) always use NPC/object path.
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if not inInstance and Fns.LootSessionSourcesAreOnlyGameObjects(RT.lootSession.sourceGUIDs) and Fns.IsInTrackableFishingZone() then
        if not Fns.LootSessionHasTrackedObjectSource(RT.lootSession.sourceGUIDs) then
            local structFish = Fns.LootSourcesLookLikeFishingOnly(RT.lootSession.sourceGUIDs)
            local apiOpen = (source == "opened" and Fns.SafeIsFishingLoot() and not V.isProfessionLooting)
            local closedFish = (source == "closed" and lootReady.wasFishing)
            if not structFish and not apiOpen and not closedFish then
                return "skip"
            end
        end
    end

    -- 2. CONTAINER: isFromItem flag (Blizzard API) or recent tracked container use
    local safeIsFromItem = isFromItem
    if issecretvalue and safeIsFromItem and issecretvalue(safeIsFromItem) then safeIsFromItem = nil end
    if not safeIsFromItem then
        safeIsFromItem = V.lastContainerItemID and RT.containerDropDB[V.lastContainerItemID] and (now - V.lastContainerItemTime) < 15
    end
    if safeIsFromItem then return "container" end

    -- 3. FISHING: IsFishingLoot() API, LOOT_READY snapshot, or structural bobber/pool sources in zone.
    --    Removed: "fishable zone + cast TTL + empty sources" — that misclassified normal kills after fishing.
    local fishingFromSourcesOnly = Fns.LootSourcesLookLikeFishingOnly(RT.lootSession.sourceGUIDs)
        and Fns.IsInTrackableFishingZone()
    local fishingLootAPI = false
    if source == "opened" then
        fishingLootAPI = Fns.SafeIsFishingLoot() and not V.isProfessionLooting
    elseif source == "closed" then
        -- LOOT_OPENED is often skipped by auto-loot; use LOOT_READY snapshot and API while still valid.
        if lootReady.wasFishing then
            fishingLootAPI = true
        else
            fishingLootAPI = Fns.SafeIsFishingLoot() and not V.isProfessionLooting
        end
    end
    
    local fishingContextFresh = RT.fishingCtx.active and (now - RT.fishingCtx.castTime) <= RT.FISHING_CAST_CONTEXT_TTL
    local sourceCompatible = fishingContextFresh and Fns.IsFishingSourceCompatible(RT.lootSession.sourceGUIDs)

    -- Third trigger: a fresh fishing cast in a trackable fishing zone when the session reports NO
    -- loot sources at all. Deliberately narrow. With sources present the two triggers above already
    -- decide (learned fishing-node GameObject / IsFishingLoot), and a mob corpse must keep winning —
    -- an earlier version of this rule counted normal kills as fishing, which is why it was removed
    -- once before. Restricting it to the empty-source case covers the only gap the others cannot see
    -- (secret or absent GetLootSourceInfo data) without reintroducing that false positive.
    local fishingFromCastContext = sourceCompatible
        and #RT.lootSession.sourceGUIDs == 0
        and Fns.IsInTrackableFishingZone()

    if fishingLootAPI or fishingFromSourcesOnly or fishingFromCastContext then
        local corpseInSources = Fns.LootSessionHasBlockingMobCorpseForFishing(RT.lootSession.sourceGUIDs)
        local corpseFromUnits = Fns.LootSessionHasMobLootContext()
        -- When the client reports fishing loot (API or LOOT_READY snapshot), trust it over unit
        -- frames — target/mouseover often stays on a nearby corpse while reeling in.
        local corpsePresent = fishingLootAPI and corpseInSources
            or (not fishingLootAPI and (corpseInSources or corpseFromUnits))
        if not corpsePresent then
            if fishingLootAPI then Fns.LearnFishingBobbersFromSources(RT.lootSession.sourceGUIDs) end
            return "fishing"
        end
    end
    -- Clear stale fishing context when source GUIDs point to a tracked NPC/object
    if fishingContextFresh and not sourceCompatible then
        RT.fishingCtx.active = false
        RT.fishingCtx.castTime = 0
        if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel(); RT.fishingCtx.resetTimer = nil end
    end

    -- 4. NPC / Object / Zone / Encounter
    return "npc"
end

---Learn bobber ids from a session already routed to fishing with IsFishingLoot() confirmation.
---Runs only after the corpse guard: learning first let a mob that shared the session be persisted as
---a "bobber", after which every kill of it read as fishing loot. A Creature is learned only when it
---is the lone Creature source (toy / oversized bobbers); GameObjects are the normal bobber shape.
function Fns.LearnFishingBobbersFromSources(sourceGUIDs)
    if not sourceGUIDs then return end
    local creatureCount = 0
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g:match("^Creature") then
            creatureCount = creatureCount + 1
        end
    end
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            if g:match("^Creature") then
                local nid = Fns.GetNPCIDFromGUID(g)
                if creatureCount == 1 and nid and not FISHING_BOBBER_NPC_IDS[nid] then
                    Fns.RememberFishingBobberNpcId(nid)
                end
            elseif g:match("^GameObject") then
                -- The live bobber is a GameObject, so this is the branch that actually fires
                -- while fishing. Scanning only "^Creature" here is why nothing was ever learned
                -- and the structural route stayed permanently dead.
                local oid = Fns.GetObjectIDFromGUID(g)
                if oid and not FISHING_BOBBER_OBJECT_IDS[oid] then
                    Fns.RememberFishingBobberObjectId(oid)
                end
            end
        end
    end
end

local function ScheduleLootRouteProcessor(addon, route, source)
    local sessionSnapshot = Fns.SnapshotLootSessionState()
    local containerItemIDSnapshot = V.lastContainerItemID
    local containerItemTimeSnapshot = V.lastContainerItemTime
    local professionLootingSnapshot = V.isProfessionLooting
    local lootOpenSerialSnapshot = RT.lootOpenSerial or 0

    C_Timer.After(0, function()
        if not addon or not Fns.IsAutoTryCounterEnabled() then return end

        local liveSession = Fns.SnapshotLootSessionState()
        local liveContainerItemID = V.lastContainerItemID
        local liveContainerItemTime = V.lastContainerItemTime
        local liveProfessionLooting = V.isProfessionLooting

        Fns.ApplyLootSessionState(sessionSnapshot)
        V.lastContainerItemID = containerItemIDSnapshot
        V.lastContainerItemTime = containerItemTimeSnapshot
        V.isProfessionLooting = professionLootingSnapshot

        -- Fast auto-loot can fire LOOT_CLOSED in the SAME frame that LOOT_OPENED scheduled this
        -- processor. Deferring the outcome then strands the staged session: no LOOT_CLOSED is left to
        -- finalize it, so the attempt line sits in the queue until the NEXT loot closes -- which is
        -- why a fishing attempt appeared seconds late, on the following catch.
        local prevWindowClosed = V.lootRouteWindowAlreadyClosed
        V.lootRouteWindowAlreadyClosed =
            not (RT.lootOpenSerial == lootOpenSerialSnapshot and RT.lootWindowOpen == true)

        local ok, err
        local P = ns.Profiler
        local routeFn
        if route == "container" then
            routeFn = function() addon:ProcessContainerLoot(source) end
        elseif route == "fishing" then
            routeFn = function() addon:ProcessFishingLoot(source) end
        elseif route == "npc" then
            routeFn = function() addon:ProcessNPCLoot(source) end
        end
        if routeFn and P and P.enabled and P.RunSlice then
            ok, err = pcall(P.RunSlice, P, P.CAT.SVC, "TC_LootRoute_" .. route, routeFn)
        elseif routeFn then
            ok, err = pcall(routeFn)
        else
            ok = true
        end

        Fns.ApplyLootSessionState(liveSession)
        -- A container route that consumed the container id must not get it back: restoring it kept the
        -- container "active", and CHAT_MSG_LOOT / CHAT_MSG_MONEY during the open window counted it again.
        local containerConsumed = route == "container" and containerItemIDSnapshot ~= nil
            and V.lastContainerItemID == nil and liveContainerItemID == containerItemIDSnapshot
        if containerConsumed then
            V.lastContainerItemID = nil
            V.lastContainerItemTime = 0
        else
            V.lastContainerItemID = liveContainerItemID
            V.lastContainerItemTime = liveContainerItemTime
        end
        V.isProfessionLooting = liveProfessionLooting
        V.lootRouteWindowAlreadyClosed = prevWindowClosed

        if route == "fishing" and ok and (source == "closed" or not liveSession.opened) then
            RT.fishingCtx.active = false
            RT.fishingCtx.castTime = 0
            RT.fishingCtx.lootWasFishing = false
            if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel() RT.fishingCtx.resetTimer = nil end
        end

        if not ok then error(err) end
    end)
end

Fns.RouteLootSession = function(self, source, isFromItem)
    if not Fns.IsAutoTryCounterEnabled() then return end

    local route = Fns.ClassifyLootSession(source, isFromItem)

    if route == "skip" then return end
    if route == "container" then
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
    if route == "fishing" then
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
    if route == "npc" then
        -- Instance boss: slot-link outcome when GUIDs are secret (Midnight).
        if Fns.TryInstanceBossSlotOutcomeFirst(self, source) then return end
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
end

-- LOOT EVENT HANDLERS

---LOOT_OPENED handler (warcraft.wiki.gg/wiki/LOOT_OPENED).
---Fires AFTER LOOT_READY, but ONLY when the loot frame is actually rendered.
---Fast auto-loot or third-party auto-loot addons may skip this entirely.
---When it does fire, it provides the best-quality data: fresh unit GUIDs + isFromItem flag.
---@param event string
---@param autoLoot boolean
---@param isFromItem boolean Added in 8.3.0, true if loot is from opening a container item
function WarbandNexus:OnTryCounterLootOpened(event, autoLoot, isFromItem)
    Fns.CaptureLootSessionState()
    RT.lootSession.opened = true
    -- Live window state for the next-frame route processor. lootSession.opened cannot answer this:
    -- LOOT_CLOSED resets it and ScheduleLootRouteProcessor restores its snapshot value, so inside the
    -- processor it always reads "open". The serial distinguishes "still this window" from "a new one".
    RT.lootOpenSerial = (RT.lootOpenSerial or 0) + 1
    RT.lootWindowOpen = true
    -- Auto-loot may close before OPENED; closed route already incremented (e.g. HK-8 Mythic).
    if Fns.ShouldSkipLateLootOpenedRoute(isFromItem) then
        return
    end
    Fns.RouteLootSession(self, "opened", isFromItem)
end

-- PROCESSING PATHS

Fns.GetAllLootSourceGUIDs = function()
    local uniqueGUIDs = {}
    local seen = {}
    local slotCreatureCount = 0

    local inRaidForGo = false
    do
        local okII, inI, instType = pcall(IsInInstance)
        if okII and inI and not (issecretvalue and issecretvalue(inI)) and inI
            and instType and not (issecretvalue and issecretvalue(instType)) and instType == "raid" then
            inRaidForGo = true
        end
    end

    -- Method 1: GetLootSourceInfo per slot — unpack ALL guid,qty pairs per slot
    if GetLootSourceInfo then
        local numItems = GetNumLootItems()
        for i = 1, numItems or 0 do
            local ok, packed = pcall(function(slot)
                return { GetLootSourceInfo(slot) }
            end, i)
            if ok and packed then
                for k = 1, #packed, 2 do
                    local sourceGUID = packed[k]
                    local safeGUID = Fns.SafeGuardGUID(sourceGUID)
                    if safeGUID and not seen[safeGUID] then
                        seen[safeGUID] = true
                        uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                        local pfx = safeGUID:match("^(%a+)")
                        if pfx == "Creature" or pfx == "Vehicle" then
                            slotCreatureCount = slotCreatureCount + 1
                        end
                    end
                end
            end
        end
    end

    -- Method 2: UnitGUID when slots are empty (instant autoloot) or GetLootSourceInfo missed a source.
    -- When Method 1 reported ANY source, do NOT add mouseover/target: Method 1 is what was looted.
    -- A rare on target while looting trash, a chest, a node, a bag item or a fishing bobber would
    -- otherwise join this list, P1 MatchGuidExact would attribute the loot to that NPC, and a fishing
    -- catch would be read as mob loot. Unit "npc" is still included (corpse interact token).
    local unitTokens
    if #uniqueGUIDs > 0 then
        unitTokens = { "npc" }
    else
        unitTokens = { "npc", "mouseover", "target" }
    end
    for u = 1, #unitTokens do
        local safeGUID = Fns.SafeGetLootedUnitGUID(unitTokens[u])
        if safeGUID and not seen[safeGUID] then
            local pfx = safeGUID:match("^(%a+)")
            if pfx == "Creature" or pfx == "Vehicle" or Fns.GetNPCIDFromGUID(safeGUID) then
                seen[safeGUID] = true
                uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
            elseif pfx == "GameObject" and RT.objectDropDB then
                local oid = Fns.GetObjectIDFromGUID(safeGUID)
                if oid and (RT.objectDropDB[oid] or inRaidForGo) then
                    seen[safeGUID] = true
                    uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                end
            end
        end
    end

    return uniqueGUIDs
end

-- SOURCE RESOLVERS (P1-P4) — each populates ctx when a match is found.
-- ProcessNPCLoot calls them in strict sequence; first match wins.
-- Every match requires EXACT ID equality (npcID in npcDropDB, objectID
-- in objectDropDB, etc.). No heuristic guessing.

function Fns.MatchGuidExact(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local npcID = Fns.GetNPCIDFromGUID(guid)
    if npcID and RT.tryCounterNpcEligible[npcID] and RT.npcDropDB[npcID] then
        return RT.npcDropDB[npcID], npcID, nil
    end
    local objectID = Fns.GetObjectIDFromGUID(guid)
    if objectID and RT.objectDropDB[objectID] then
        return RT.objectDropDB[objectID], nil, objectID
    end
    return nil
end

function Fns.CountCorpsesSharingDropTable(allSourceGUIDs, dropsTable)
    if not dropsTable or not allSourceGUIDs or #allSourceGUIDs == 0 then return 1 end
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            if not g:match("^GameObject") and not seen[g] then
                seen[g] = true
                local d2 = Fns.MatchGuidExact(g)
                if d2 == dropsTable then
                    n = n + 1
                end
            end
        end
    end
    return math.max(1, n)
end

function Fns.CountUniqueLootSourcesForNpcID(allSourceGUIDs, npcID)
    if not npcID or not allSourceGUIDs or #allSourceGUIDs == 0 then return 0 end
    local needle = "-" .. tostring(npcID) .. "-"
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and not seen[g] then
            seen[g] = true
            if not g:match("^GameObject") then
                local nid = Fns.GetNPCIDFromGUID(g)
                if nid == npcID then
                    n = n + 1
                elseif not nid and (g:match("^Creature") or g:match("^Vehicle")) and g:find(needle, 1, true) then
                    -- unparsed GUID only: on a parsed one the needle can hit server/instance/zone fields
                    n = n + 1
                end
            end
        end
    end
    return n
end
