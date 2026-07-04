--[[ CollectionService NEW_* handlers (ops split) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS
local RT = assert(ns.CollectionServiceRT, 'CollectionService_Events: load CollectionService.lua first')
local DebugPrint = RT.DebugPrint
local issecretvalue = issecretvalue
local C_Timer = C_Timer
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local C_ToyBox = C_ToyBox
local Notify = ns.CollectionNotify
local CSListeners = RT.CSListeners
local InvalidateCollectionCountsCache = RT.InvalidateCollectionCountsCache
local WipeUncollectedResultsCacheAndMergedAchievements = RT.WipeUncollectedResultsCacheAndMergedAchievements

-- REAL-TIME EVENT HANDLERS (NEW_MOUNT_ADDED, NEW_PET_ADDED, NEW_TOY_ADDED)
--
-- The three handlers below share a skeleton (retry → owned/store update → dedup
-- gates → toast → COLLECTION_UPDATED) but are DELIBERATELY kept as parallel flat
-- functions, not a shared core: the dedup chains differ in both content and ORDER
-- (pets check fanfare/wrapped state and duplicate-species count before the common
-- layers, mounts add the grind chat line, toys invalidate their source caches),
-- and a callback-config abstraction here would obscure exactly the part that has
-- to be auditable. Keep edits synchronized across all three by hand.

---Handle NEW_MOUNT_ADDED event
---Fires when player learns a new mount
function WarbandNexus:OnNewMount(event, mountID, retryCount)
    if not mountID then return end
    retryCount = retryCount or 0

    local name, _, icon, _, _, sourceType = C_MountJournal.GetMountInfoByID(mountID)
    if issecretvalue then
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
        if sourceType and issecretvalue(sourceType) then sourceType = nil end
    end
    if not name then
        if retryCount < 3 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewMount: Data not ready for mountID=" .. mountID .. ", retry " .. (retryCount + 1) .. "/3")
            C_Timer.After(0.5, function()
                self:OnNewMount(event, mountID, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewMount: Data unavailable after 3 retries for mountID=" .. mountID)
        end
        return
    end

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    RT.collectionCache.owned.mounts[mountID] = true
    self:RemoveFromUncollected("mount", mountID)

    if not RT.collectionStore.mount then RT.collectionStore.mount = {} end
    local m = RT.collectionStore.mount[mountID]
    local storeChanged = false
    if not m then
        local sourceText = ""
        if C_MountJournal.GetMountInfoExtraByID then
            local _, description, src = C_MountJournal.GetMountInfoExtraByID(mountID)
            if src and not (issecretvalue and issecretvalue(src)) then sourceText = src end
        end
        RT.collectionStore.mount[mountID] = {
            id = mountID, name = name, icon = icon, source = sourceText, sourceType = sourceType, description = "",
            creatureDisplayID = nil, collected = true,
        }
        storeChanged = true
    else
        if m.collected ~= true then
            m.collected = true
            storeChanged = true
        end
        -- Backfill sourceType if missing (DB migration from pre-3.0 store entries)
        if sourceType and m.sourceType ~= sourceType then
            m.sourceType = sourceType
            storeChanged = true
        end
    end
    if storeChanged then
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local skipNotification = false
    -- Repeatable (farmable) affects try-counter / drop DB only — never bypass permanent toast dedup
    -- or the same mount can notify again on every journal/login refresh.
    if Notify.WasAlreadyNotified("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: mount " .. mountID .. " (already notified)")
    elseif Notify.WasRecentlyShownByName(name) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
    elseif Notify.WasDetectedInBag("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (detected in bag before; 2h bag-detect window)")
    elseif Notify.WasRecentlyNotified("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (notified within 5s)")
    end

    if not skipNotification then
        Notify.MarkAsNotified("mount", mountID)
        Notify.MarkAsShownByName(name)

        -- "What a grind" chat line when cumulative drop probability > 70%.
        -- Honors hideTryCounterChat; gracefully no-ops when rate/itemID unknown.
        if ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetCumulativeProbability
            and C_MountJournal and C_MountJournal.GetMountItemID then
            local okItem, mountItemID = pcall(C_MountJournal.GetMountItemID, mountID)
            if okItem and mountItemID and type(mountItemID) == "number" and mountItemID > 0 then
                local tries = (self.GetTryCount and self:GetTryCount("mount", mountID)) or 0
                local total = (tonumber(tries) or 0) + 1
                local cumP = ns.CollectibleSourceDB.GetCumulativeProbability(mountItemID, total)
                if cumP and cumP > 0.70 then
                    local hideChat = self.db and self.db.profile and self.db.profile.notifications
                        and self.db.profile.notifications.hideTryCounterChat
                    if not hideChat then
                        local itemLink
                        if GetItemInfo then
                            local _, link = GetItemInfo(mountItemID)
                            if link and link ~= "" and not (issecretvalue and issecretvalue(link)) then itemLink = link end
                        end
                        if not itemLink then
                            itemLink = (ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. "[" .. (name or "Mount") .. "]|r"
                        end
                        local L = ns.L
                        local fmt = (L and L["TRYCOUNTER_WHAT_A_GRIND"])
                            or "What a grind! %d attempts (expected ~%d%% to have it by now) for %s"
                        local pct = math.floor(cumP * 100 + 0.5)
                        local msg = "|cffff8800[WN-Grind]|r " .. string.format(fmt, total, pct, itemLink)
                        if ns.ChatOutput and ns.ChatOutput.SendTryCounterMessage then
                            ns.ChatOutput.SendTryCounterMessage(msg)
                        elseif self.Print then
                            self:Print(msg)
                        end
                    end
                end
            end
        end

        self:SendMessage(E.COLLECTIBLE_OBTAINED, {
            type = "mount",
            id = mountID,
            name = name,
            icon = icon,
            obtainedBy = Notify.CollectiblePayloadObtainedBy(),
        })
    end

    -- Fire data-update event so UI refreshes (even when notification is deduped).
    -- NOTE: Do NOT call InvalidateCollectionCache here — the incremental updates above
    -- (RemoveFromUncollected + direct store write) are correct and sufficient.
    -- InvalidateCollectionCache would clear RT.collectionCache.owned.mounts={}, undoing
    -- the owned cache set we just did. WN_COLLECTION_UPDATED triggers the UI to
    -- invalidate its own display caches and refresh.
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "mount")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW MOUNT: " .. name .. (skipNotification and " (notification deduped)" or ""))
end

---Handle NEW_PET_ADDED event
---Fires when player learns a new battle pet
function WarbandNexus:OnNewPet(event, petGUID, retryCount)
    if not petGUID then return end
    retryCount = retryCount or 0

    local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon = C_PetJournal.GetPetInfoByPetID(petGUID)
    if issecretvalue then
        if speciesID and issecretvalue(speciesID) then speciesID = nil end
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
    end

    if not speciesID or not name then
        -- Pet journal may not be ready immediately when NEW_PET_ADDED fires; retry with backoff (up to 5 tries, 0.8s apart)
        if retryCount < 5 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewPet: Data not ready for petGUID=" .. tostring(petGUID) .. ", retry " .. (retryCount + 1) .. "/5")
            C_Timer.After(0.8, function()
                self:OnNewPet(event, petGUID, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewPet: Data unavailable after 5 retries for petGUID=" .. tostring(petGUID))
        end
        return
    end

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    RT.collectionCache.owned.pets[speciesID] = true
    self:RemoveFromUncollected("pet", speciesID)

    if not RT.collectionStore.pet then RT.collectionStore.pet = {} end
    local p = RT.collectionStore.pet[speciesID]
    local storeChanged = false
    -- Existing sourceTypeIndex from prior scan; backfilled if a fresh scan ran (rare on real-time path).
    local sourceTypeIndex = ns._petSpeciesToSourceIndex and ns._petSpeciesToSourceIndex[speciesID] or (p and p.sourceTypeIndex)
    if not p then
        local sourceText = ""
        if C_PetJournal.GetPetInfoBySpeciesID then
            local _, _, _, _, src = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            if src and not (issecretvalue and issecretvalue(src)) then sourceText = src end
        end
        RT.collectionStore.pet[speciesID] = {
            id = speciesID, name = name, icon = icon, source = sourceText, sourceTypeIndex = sourceTypeIndex, description = "",
            creatureDisplayID = displayID, collected = true,
        }
        storeChanged = true
    else
        if p.collected ~= true then
            p.collected = true
            storeChanged = true
        end
        if sourceTypeIndex and p.sourceTypeIndex ~= sourceTypeIndex then
            p.sourceTypeIndex = sourceTypeIndex
            storeChanged = true
        end
    end
    if storeChanged then
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local skipNotification = false

    -- Wrapped journal pets: NEW_PET_ADDED can fire before unwrap — skip toast spam until unwrapped.
    if C_PetJournal.PetNeedsFanfare and petGUID and C_PetJournal.PetNeedsFanfare(petGUID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r SKIP: pet needs fanfare (wrapped) petGUID=" .. tostring(petGUID))
    end

    -- Prefer species name for display (stable); journal row name can be wrong during async journal loads.
    local notifyPetName = name
    if speciesID and C_PetJournal.GetPetInfoBySpeciesID then
        local sName = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        if sName and sName ~= "" and not (issecretvalue and issecretvalue(sName)) then
            notifyPetName = sName
        end
    end

    -- Duplicate pet species (2/3, 3/3 etc.) — skip notification but data is already updated
    local numOwned, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
    if issecretvalue and numOwned and issecretvalue(numOwned) then numOwned = nil end
    if not skipNotification and numOwned and numOwned > 1 then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r SKIP: " .. notifyPetName .. " (" .. numOwned .. "/" .. (limit or 3) .. " owned) - not first acquisition")
    elseif not skipNotification and Notify.WasAlreadyNotified("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: pet " .. notifyPetName .. " (already notified)")
    elseif not skipNotification and Notify.WasRecentlyShownByName(notifyPetName) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. notifyPetName)
    elseif not skipNotification and Notify.WasDetectedInBag("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. notifyPetName .. " (detected in bag before; 2h bag-detect window)")
    elseif not skipNotification and Notify.IsPetNameBagCooldownActive(notifyPetName) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. notifyPetName .. " (item-based bag detection)")
    elseif not skipNotification and Notify.WasRecentlyNotified("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. notifyPetName .. " (notified within 5s)")
    end

    if not skipNotification then
        Notify.MarkAsNotified("pet", speciesID)
        Notify.MarkAsShownByName(notifyPetName)

        self:SendMessage(E.COLLECTIBLE_OBTAINED, {
            obtainedBy = Notify.CollectiblePayloadObtainedBy(),
            type = "pet",
            id = speciesID,
            name = notifyPetName,
            icon = icon
        })
    end

    -- Fire data-update event so UI refreshes (even when notification is deduped).
    -- NOTE: Do NOT call InvalidateCollectionCache here — incremental updates are sufficient.
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "pet")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW PET: " .. notifyPetName .. " (speciesID: " .. speciesID .. ")" .. (skipNotification and " (notification deduped)" or ""))
end

---Handle NEW_TOY_ADDED event
---Fires when player learns a new toy
function WarbandNexus:OnNewToy(event, itemID, _isFavorite, _retryCount)
    if not itemID then return end
    local retryCount = (type(_retryCount) == "number") and _retryCount or 0

    local success, name = pcall(GetItemInfo, itemID)
    if not success or not name then
        if retryCount < 3 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewToy: Data not ready for itemID=" .. itemID .. ", retry " .. (retryCount + 1) .. "/3")
            C_Timer.After(0.5, function()
                self:OnNewToy(event, itemID, nil, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewToy: Data unavailable after 3 retries for itemID=" .. itemID)
        end
        return
    end

    local icon = GetItemIcon(itemID)

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    RT.collectionCache.owned.toys[itemID] = true
    self:RemoveFromUncollected("toy", itemID)

    if not RT.collectionStore.toy then RT.collectionStore.toy = {} end
    local t = RT.collectionStore.toy[itemID]
    if not t then
        RT.collectionStore.toy[itemID] = { id = itemID, name = name }
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local skipNotification = false
    if Notify.WasAlreadyNotified("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: toy " .. itemID .. " (already notified)")
    elseif Notify.WasDetectedInBag("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. name .. " (detected in bag before; 2h bag-detect window)")
    elseif Notify.WasRecentlyNotified("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. name .. " (notified within 5s)")
    elseif Notify.WasRecentlyShownByName(name) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
    end

    if not skipNotification then
        Notify.MarkAsNotified("toy", itemID)
        Notify.MarkAsShownByName(name)

        self:SendMessage(E.COLLECTIBLE_OBTAINED, {
            type = "toy",
            id = itemID,
            name = name,
            icon = icon,
            obtainedBy = Notify.CollectiblePayloadObtainedBy(),
        })
    end

    -- Fire data-update event so UI refreshes (even when notification is deduped).
    -- NOTE: Do NOT call InvalidateCollectionCache here — incremental updates are sufficient.
    -- The fast-path map (_toyGroupedFromMapValid gate) must drop too; clearing only the
    -- fallback cache kept serving a source index that lacked the new toy.
    if ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache.map = nil end
    ns._toyGroupedFromMapValid = false
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "toy")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY: " .. name .. (skipNotification and " (notification deduped)" or ""))
end

---Handle TRANSMOG_COLLECTION_UPDATED event
---Fires when transmog collection changes (including illusions)
---We need to detect which illusion was added by comparing before/after
function WarbandNexus:OnTransmogCollectionUpdated(event)
    if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then return end
    
    -- Throttle checks to avoid spam (illusions are rare)
    if self._lastIllusionCheck and (GetTime() - self._lastIllusionCheck) < 2 then
        return
    end
    self._lastIllusionCheck = GetTime()
    
    -- Get current illusion state
    local illusions = C_TransmogCollection.GetIllusions()
    if not illusions then return end
    
    -- Build current collected set
    local currentCollected = {}
    for i = 1, #illusions do
        local illusionInfo = illusions[i]
        if illusionInfo and illusionInfo.visualID and illusionInfo.isCollected then
            currentCollected[illusionInfo.visualID] = illusionInfo
        end
    end
    
    -- Initialize previous state if not exists
    if not self._previousIllusionState then
        self._previousIllusionState = currentCollected
        return
    end
    
    -- Compare and find newly collected illusions
    local newIllusionLearned = false
    for visualID, illusionInfo in pairs(currentCollected) do
        if not self._previousIllusionState[visualID] then
            newIllusionLearned = true
            -- NEW ILLUSION COLLECTED!
            local name = illusionInfo.name
            
            -- Try spell name if no name
            if (not name or name == "") and illusionInfo.spellID then
                local spellName = C_Spell and C_Spell.GetSpellName(illusionInfo.spellID)
                if spellName and spellName ~= "" then
                    name = spellName
                end
            end
            
            -- Fallback to visualID
            if not name or name == "" then
                name = ((ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion") .. " " .. visualID
            end
            
            local icon = illusionInfo.icon or 134400
            
            -- Remove from uncollected cache if present
            self:RemoveFromUncollected("illusion", visualID)

            -- Fire notification event
            self:SendMessage(E.COLLECTIBLE_OBTAINED, {
                type = "illusion",
                id = visualID,
                name = name,
                icon = icon,
                obtainedBy = Notify.CollectiblePayloadObtainedBy(),
            })
            
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW ILLUSION: " .. name .. " (ID: " .. visualID .. ")")
        end
    end

    if newIllusionLearned and ns.InvalidateIllusionLookupCache then
        ns.InvalidateIllusionLookupCache()
    end

    -- Update previous state
    self._previousIllusionState = currentCollected
end

---Remove Collections → Recent entries older than Constants.COLLECTIONS_RECENT_RETENTION_SEC (newest-first list).
function WarbandNexus:PruneCollectionsRecentObtained()
    if not self.db or not self.db.global then return end
    local list = self.db.global.collectionsRecentObtained
    if type(list) ~= "table" then return end
    local retention = (Constants and Constants.COLLECTIONS_RECENT_RETENTION_SEC) or 604800
    local cutoff = time() - retention
    for i = #list, 1, -1 do
        local e = list[i]
        local et = e and e.t
        if type(et) ~= "number" or et < cutoff then
            table.remove(list, i)
        end
    end
end

---Remove all Collections → Recent rows for one collectible type (Recent tab per-card reset).
function WarbandNexus:ClearCollectionsRecentObtainedForType(collectibleType)
    if not collectibleType or not self.db or not self.db.global then return end
    local list = self.db.global.collectionsRecentObtained
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        local e = list[i]
        if e and e.type == collectibleType then
            table.remove(list, i)
        end
    end
end

---Persist newest collectible acquisitions for the Collections tab "Recently obtained" strip.
function WarbandNexus:AppendCollectionsRecentObtained(data)
    if not data or type(data) ~= "table" or not data.type then return end
    local allowed = {
        mount = true, pet = true, toy = true, achievement = true, title = true, illusion = true,
    }
    if not allowed[data.type] then return end
    if data.id == nil then return end
    if not self.db or not self.db.global then return end
    local list = self.db.global.collectionsRecentObtained
    if type(list) ~= "table" then
        list = {}
        self.db.global.collectionsRecentObtained = list
    end
    local displayName = data.name
    if (not displayName or displayName == "") and data.type == "achievement" then
        displayName = (ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement"
    end
    if not displayName or displayName == "" then return end
    -- Achievements: only first account completion belongs in Recent (alt re-earn / prior store completion).
    if data.type == "achievement" and data.accountFirstEarn == false then
        return
    end
    -- One Recent row per type+id (account-wide collectibles; stops relog/alt duplicate lines).
    local priorTs = self:GetCollectionsAcquiredAt(data.type, data.id)
    if priorTs ~= nil then
        return
    end
    for i = 1, #list do
        local e = list[i]
        if e and e.type == data.type and e.id == data.id then
            return
        end
    end
    local now = time()
    local first = list[1]
    if first and first.type == data.type and first.id == data.id and (now - (first.t or 0)) < 5 then
        return
    end
    local accountFirstEarn = true
    if data.type == "achievement" then
        accountFirstEarn = (data.accountFirstEarn ~= false)
    end
    table.insert(list, 1, {
        t = now,
        type = data.type,
        id = data.id,
        name = displayName,
        obtainedBy = data.obtainedBy,
        accountFirstEarn = accountFirstEarn,
    })
    self:PruneCollectionsRecentObtained()

    local lastRoot = self.db.global.collectionsLastObtained
    if type(lastRoot) ~= "table" then
        lastRoot = {}
        self.db.global.collectionsLastObtained = lastRoot
    end
    local bucket = lastRoot[data.type]
    if type(bucket) ~= "table" then
        bucket = {}
        lastRoot[data.type] = bucket
    end
    bucket[data.id] = now
end

---Unix time when the addon last recorded this collectible as obtained (WN_COLLECTIBLE_OBTAINED), or nil.
---@return number|nil
function WarbandNexus:GetCollectionsAcquiredAt(collectibleType, id)
    if not collectibleType or id == nil then return nil end
    if not self.db or not self.db.global then return nil end
    local root = self.db.global.collectionsLastObtained
    if type(root) ~= "table" then return nil end
    local b = root[collectibleType]
    if type(b) ~= "table" then return nil end
    local t = b[id]
    if type(t) ~= "number" or t <= 0 then return nil end
    return t
end

-- Invalidate API counts cache so Statistics and Collections show same numbers after any collection change.
-- COLLECTION_UPDATED sends (message, collectionType string). COLLECTIBLE_OBTAINED passes payload table { type = ... }.
-- Must be declared before WN_COLLECTIBLE_OBTAINED RegisterMessage below: Lua 5.1 local function scope starts after this `end`.
local function InvalidateCollectionCountsCache(_, arg)
    -- Table arg = COLLECTIBLE_OBTAINED payload (a confirmed +1); string arg =
    -- COLLECTION_UPDATED (journal refresh, counts may not have changed) → full wipe.
    local ctype = arg
    local isObtain = false
    if type(arg) == "table" then
        ctype = arg.type
        isObtain = true
    end
    if WarbandNexus.InvalidateCollectionCountsAPICache then
        WarbandNexus:InvalidateCollectionCountsAPICache(isObtain and ctype or nil)
    end
    WipeUncollectedResultsCacheAndMergedAchievements()
    -- Toy source lazy cache (GetToySourceTypeIndexForItem) must rebuild after collection changes
    ns._toyItemIDToSourceIndexCache = nil
    ns._toyGroupedFromMapValid = false
    ns._mountGroupedFromMapValid = false
    ns._mountIDToSourceIndex = nil
    -- Pet journal source classification: clear on full invalidation or pet-specific updates (P1 staleness)
    if ctype == nil or ctype == "pet" then
        ns._petSpeciesToSourceIndex = nil
    end
    if ctype == nil or ctype == "mount" then
        ns._mountGroupedFromMapValid = false
        ns._mountIDToSourceIndex = nil
    end
end

-- Single WN_COLLECTIBLE_OBTAINED handler
-- (AceEvent table is keyed by self). Order: uncollected prune -> API/uncollected caches -> recent ring -> UI broadcast.
if E and E.COLLECTIBLE_OBTAINED then
    WarbandNexus.RegisterMessage(CSListeners, E.COLLECTIBLE_OBTAINED, function(_, data)
        if not data or not data.type then return end
        local t = data.type
        local id = data.id
        if id and (t == "mount" or t == "pet" or t == "toy") then
            WarbandNexus:RemoveFromUncollected(t, id)
            if data.fromTryCounter then
                Notify.MarkAsNotified(t, id)
                if data.name then Notify.MarkAsShownByName(data.name) end
            end
        end
        InvalidateCollectionCountsCache(_, data)
        WarbandNexus:AppendCollectionsRecentObtained(data)
        if id and (t == "mount" or t == "pet" or t == "toy") and E.COLLECTION_UPDATED then
            WarbandNexus:SendMessage(E.COLLECTION_UPDATED, t)
        end
    end)
end

-- Register real-time collection events
-- Bag scan handles ALL collectible detection (mount/pet/toy)
-- Real-time collection events: fire when mount/pet/toy is learned (from quests, drops, vendors, etc.)
-- Duplicate prevention: Multi-layer debounce (name, ID, bag-detection) prevents double notifications.
WarbandNexus:RegisterEvent("NEW_MOUNT_ADDED", "OnNewMount")
WarbandNexus:RegisterEvent("NEW_PET_ADDED", "OnNewPet")
WarbandNexus:RegisterEvent("NEW_TOY_ADDED", "OnNewToy")

WarbandNexus.RegisterMessage(CSListeners, Constants.EVENTS.COLLECTION_UPDATED, InvalidateCollectionCountsCache)
WarbandNexus.RegisterMessage(CSListeners, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
    WipeUncollectedResultsCacheAndMergedAchievements()
    InvalidateCollectionCountsCache(nil, nil)
    WarbandNexus:SendMessage(Constants.EVENTS.ACHIEVEMENT_CATEGORY_CACHE_INVALIDATED)
end)
