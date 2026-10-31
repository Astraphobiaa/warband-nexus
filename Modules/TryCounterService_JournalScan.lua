--[[
    Warband Nexus - Encounter Journal source discovery.

    Walks the Encounter Journal (tier -> instance -> encounter -> loot) and records which MOUNTS,
    PETS and TOYS each boss can drop, for every expansion the client knows about. Output lands in
    db.global.trackDB.journal.encounters, keyed by DungeonEncounterID -- the id ENCOUNTER_END
    delivers -- because EJ_GetCreatureInfo cannot give a creature/NPC id (it returns
    JournalEncounterCreature.ID and CreatureDisplayID, neither of which matches a GUID). The
    encounter lane in TryCounterService consumes it; MergeTrackDB strips anything the shipped npc
    rows already cover, so the two lanes can never charge the same drop twice.

    Each instance is walked once per difficulty it offers, because the journal's loot list is what
    the player sees on the selected difficulty -- that is the only way to learn a mount is
    Mythic-only. A drop that did not appear at every difficulty gets a `difficultyIDs` whitelist,
    which ProcessEncounterKeyedMiss runs through the same Fns.FilterDropsByDifficulty the npc lane
    uses. A whitelist is written ONLY when every difficulty was read cleanly: an unread loot list
    and "this boss does not drop it here" are indistinguishable, so an incomplete scan deliberately
    produces unrestricted rows rather than a wrong restriction.

    The walk is staged: tiers x instances x difficulties x encounters x loot is thousands of API
    calls, so it runs in bounded slices via C_Timer.After and carries a generation id so a restart
    cancels the previous run.

    EJ state is global and the player's open journal reads it back, so the scan snapshots tier /
    difficulty / loot filter / slot filter and restores them, and refuses to run while the journal
    is open or while in combat.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter
assert(TC and TC.Fns and TC.Runtime, "TryCounterService_JournalScan: TryCounterService must load first")
local Fns = TC.Fns
local RT = TC.Runtime
local issecretvalue = issecretvalue

local SLICE_BUDGET_MS = 8
-- A difficulty change refetches the loot list from the server (it lands on
-- EJ_LOOT_DATA_RECIEVED), so the walk has to let a frame or two pass before reading. The first
-- pass yields briefly and queues whatever still came back stale; the retry pass waits longer,
-- which is affordable because it only revisits what actually failed.
local DIFFICULTY_SETTLE_SEC = 0.05
local RETRY_SETTLE_SEC = 0.20
local RETRY_MAX = 600
local DebugPrint = ns.DebugPrint or function() end

local Scan = {
    running = false,
    generation = 0,
    snapshot = nil,
    found = nil,
    stats = nil,
    -- Per-encounter record of WHICH difficulties were read cleanly. An encounter whose loot list
    -- was still loading at any difficulty gets no difficulty whitelist at all, because "item not
    -- seen on Mythic" and "Mythic list never arrived" are indistinguishable from the drop list.
    encMeta = nil,
    retry = nil,
}
TC.JournalScan = Scan

-- ── helpers ──────────────────────────────────────────────────────────────────

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function SafeNumber(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

---Mount / pet / toy, or nil for anything else. The journal has no such flag: EncounterJournalItemInfo
---carries no mount/pet/toy field, so classification is by itemID.
---@return string|nil "mount"|"pet"|"toy"
local function ClassifyCollectibleItem(itemID)
    itemID = SafeNumber(itemID)
    if not itemID or itemID <= 0 then return nil end

    local GII = C_Item and C_Item.GetItemInfoInstant
    if GII then
        -- returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
        local ok, _, _, _, _, _, classID, subClassID = pcall(GII, itemID)
        if ok then
            classID, subClassID = SafeNumber(classID), SafeNumber(subClassID)
            -- Miscellaneous (15): Mount = subclass 5, Companion Pet = subclass 2.
            if classID == 15 then
                if subClassID == 5 then return "mount" end
                if subClassID == 2 then return "pet" end
            end
        end
    end

    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, toyID = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok and SafeNumber(toyID) then return "toy" end
    end
    return nil
end

---The difficulties the journal itself offers, mirroring EJ_DIFFICULTIES in Blizzard's own
---Blizzard_EncounterJournal.lua. DifficultyUtil.ID is the canonical source; the literals are the
---documented ids (warcraft.wiki.gg/wiki/DifficultyID) for a client that does not expose it.
local function BuildEJDifficultyIDs()
    local D = DifficultyUtil and DifficultyUtil.ID or nil
    local function pick(name, fallback)
        local v = D and D[name]
        return SafeNumber(v) or fallback
    end
    return {
        pick("DungeonNormal", 1), pick("DungeonHeroic", 2), pick("DungeonMythic", 23),
        pick("DungeonChallenge", 8), pick("DungeonTimewalker", 24),
        pick("RaidLFR", 7), pick("Raid10Normal", 3), pick("Raid10Heroic", 5),
        pick("Raid25Normal", 4), pick("Raid25Heroic", 6), pick("RaidWorld", 172),
        pick("PrimaryRaidLFR", 17), pick("PrimaryRaidNormal", 14),
        pick("PrimaryRaidHeroic", 15), pick("PrimaryRaidMythic", 16),
        pick("RaidTimewalker", 33), pick("Raid40", 9),
    }
end

local EJ_DIFFICULTY_IDS = nil

---Which of those the CURRENTLY SELECTED instance actually offers.
---Blizzard's own difficulty dropdown notes that EJ_IsValidInstanceDifficulty is not sufficient on
---its own ("new difficulties have IDs above the mask limit (64) that it checks"), so
---InstanceHasDifficultyID wins where the client has it.
---@return table list of difficultyIDs; { 0 } when none could be determined
local function InstanceDifficulties()
    EJ_DIFFICULTY_IDS = EJ_DIFFICULTY_IDS or BuildEJDifficultyIDs()
    local hasFn = C_EncounterJournal and C_EncounterJournal.InstanceHasDifficultyID
    local out = {}
    for i = 1, #EJ_DIFFICULTY_IDS do
        local id = EJ_DIFFICULTY_IDS[i]
        local valid = nil
        if hasFn then
            local ok, has = pcall(hasFn, id)
            if ok then valid = (has == true) end
        end
        if valid == nil and EJ_IsValidInstanceDifficulty then
            local ok2, v = pcall(EJ_IsValidInstanceDifficulty, id)
            if ok2 then valid = (v == true) end
        end
        if valid then out[#out + 1] = id end
    end
    -- 0 means "difficulty unknown": scan once at whatever the journal is already on and record no
    -- difficulty, which leaves the rows exactly as unrestricted as they were before this lane
    -- learned about difficulties at all.
    if #out == 0 then out[1] = 0 end
    return out
end

local function SnapshotEJState()
    local snap = {}
    local ok, v
    ok, v = SafeCall(EJ_GetCurrentTier); if ok then snap.tier = SafeNumber(v) end
    ok, v = SafeCall(EJ_GetDifficulty); if ok then snap.difficulty = SafeNumber(v) end
    if EJ_GetLootFilter then
        local ok2, c, sp = pcall(EJ_GetLootFilter)
        if ok2 then snap.filterClass, snap.filterSpec = SafeNumber(c), SafeNumber(sp) end
    end
    if C_EncounterJournal and C_EncounterJournal.GetSlotFilter then
        local ok3, f = pcall(C_EncounterJournal.GetSlotFilter)
        if ok3 then snap.slotFilter = SafeNumber(f) end
    end
    return snap
end

local function RestoreEJState(snap)
    if not snap then return end
    if snap.filterClass ~= nil and EJ_SetLootFilter then
        SafeCall(EJ_SetLootFilter, snap.filterClass, snap.filterSpec or 0)
    end
    if snap.slotFilter ~= nil and C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
        SafeCall(C_EncounterJournal.SetSlotFilter, snap.slotFilter)
    end
    if snap.difficulty and EJ_SetDifficulty then SafeCall(EJ_SetDifficulty, snap.difficulty) end
    if snap.tier and EJ_SelectTier then SafeCall(EJ_SelectTier, snap.tier) end
end

---@return string|nil reason when the scan must not run
local function BlockedReason()
    if InCombatLockdown and InCombatLockdown() then return "in combat" end
    local frame = _G and _G.EncounterJournal
    if frame and frame.IsShown then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and shown == true then return "the Encounter Journal is open" end
    end
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex
        or not EJ_SelectInstance or not EJ_GetEncounterInfoByIndex or not EJ_GetNumLoot then
        return "Encounter Journal API unavailable"
    end
    if not (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) then
        return "C_EncounterJournal.GetLootInfoByIndex unavailable"
    end
    return nil
end

-- ── the walk ─────────────────────────────────────────────────────────────────

---Read the loot of the currently selected encounter into Scan.found.
---@param dungeonEncID number
---@param difficultyID number 0 when the difficulty could not be determined
---@return number added, boolean incomplete
local function ReadSelectedEncounterLoot(dungeonEncID, difficultyID)
    local ok, numLoot = SafeCall(EJ_GetNumLoot)
    numLoot = (ok and SafeNumber(numLoot)) or 0

    -- Loot arrives asynchronously (EJ_LOOT_DATA_RECIEVED). An empty or stale list is not proof the
    -- boss drops nothing, so it is queued for a second pass rather than recorded as "none".
    local stale = false
    if EJ_IsLootListOutOfDate then
        local ok2, outOfDate = pcall(EJ_IsLootListOutOfDate)
        if ok2 and outOfDate == true then stale = true end
    end
    if numLoot == 0 or stale then return 0, true end

    local meta = Scan.encMeta[dungeonEncID]
    if not meta then meta = { read = {}, nRead = 0, pending = 0 }; Scan.encMeta[dungeonEncID] = meta end
    if difficultyID and difficultyID > 0 and not meta.read[difficultyID] then
        meta.read[difficultyID] = true
        meta.nRead = meta.nRead + 1
    end

    local added = 0
    for i = 1, numLoot do
        local ok3, info = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
        if ok3 and type(info) == "table" then
            local itemID = SafeNumber(info.itemID)
            local kind = itemID and ClassifyCollectibleItem(itemID)
            if kind then
                local bucket = Scan.found[dungeonEncID]
                if not bucket then bucket = {}; Scan.found[dungeonEncID] = bucket end
                local row = bucket[itemID]
                if not row then
                    row = { kind = kind, diffs = {}, nDiffs = 0 }
                    bucket[itemID] = row
                    added = added + 1
                    Scan.stats[kind] = (Scan.stats[kind] or 0) + 1
                end
                if difficultyID and difficultyID > 0 and not row.diffs[difficultyID] then
                    row.diffs[difficultyID] = true
                    row.nDiffs = row.nDiffs + 1
                end
            end
        end
    end
    return added, false
end

---Build the flat work list of {tier, isRaid, instanceID} to visit.
local function BuildInstanceWorkList()
    local work = {}
    local ok, numTiers = SafeCall(EJ_GetNumTiers)
    numTiers = (ok and SafeNumber(numTiers)) or 0
    for tier = 1, numTiers do
        if not SafeCall(EJ_SelectTier, tier) then break end
        for _, isRaid in ipairs({ false, true }) do
            local index = 1
            while true do
                local ok2, instanceID = pcall(EJ_GetInstanceByIndex, index, isRaid)
                instanceID = ok2 and SafeNumber(instanceID) or nil
                if not instanceID then break end
                work[#work + 1] = { tier = tier, isRaid = isRaid, instanceID = instanceID }
                index = index + 1
                if index > 200 then break end -- defensive: never spin on a misbehaving client
            end
        end
    end
    return work
end

local function FinishScan(generation, aborted, reason)
    if generation ~= Scan.generation then return end
    RestoreEJState(Scan.snapshot)
    Scan.running = false
    Scan.snapshot = nil

    local WN = WarbandNexus
    if aborted then
        if WN and WN.Print then
            WN:Print("|cffff6600[WN-TC-Scan]|r Stopped: " .. tostring(reason))
        end
        Scan.found, Scan.stats, Scan.encMeta, Scan.retry = nil, nil, nil, nil
        return
    end

    -- Persist: DungeonEncounterID -> drop rows, in the journal namespace.
    if Fns.EnsureDB and Fns.EnsureDB() then
        local g = WarbandNexus.db.global
        g.trackDB = g.trackDB or {}
        g.trackDB.journal = g.trackDB.journal or {}
        local out = {}
        local encounters, rows = 0, 0
        for encID, items in pairs(Scan.found or {}) do
            local list = {}
            local meta = Scan.encMeta and Scan.encMeta[encID]
            -- Only trust a whitelist when every difficulty this encounter offers was read, and
            -- there was more than one of them. Otherwise an unread list would look like "this
            -- mount does not drop here" and the lane would stop counting a real attempt.
            -- pending counts loot lists still unread after the retry pass.
            local trustDiffs = meta and (meta.pending or 0) == 0 and (meta.nRead or 0) > 1
            for itemID, row in pairs(items) do
                local entry = { type = row.kind, itemID = itemID }
                -- Present at every difficulty = no restriction worth storing.
                if trustDiffs and row.nDiffs > 0 and row.nDiffs < meta.nRead then
                    local ids = {}
                    for diffID in pairs(row.diffs) do ids[#ids + 1] = diffID end
                    table.sort(ids)
                    entry.difficultyIDs = ids
                end
                list[#list + 1] = entry
                rows = rows + 1
            end
            if #list > 0 then
                out[encID] = list
                encounters = encounters + 1
            end
        end
        g.trackDB.journal.encounters = out
        g.trackDB.journal.scannedAt = time()

        if Fns.MergeTrackDB then Fns.MergeTrackDB() end
        if WN and WN.Print then
            WN:Print(string.format(
                "|cff00ff00[WN-TC-Scan]|r Done: %d bosses, %d drops (%d mount / %d pet / %d toy).",
                encounters, rows, Scan.stats.mount or 0, Scan.stats.pet or 0, Scan.stats.toy or 0))
            local stillMissing = 0
            for _, m in pairs(Scan.encMeta or {}) do
                if (m.pending or 0) > 0 then stillMissing = stillMissing + 1 end
            end
            if (Scan.stats.recovered or 0) > 0 then
                WN:Print(string.format(
                    "|cff9370DB[WN-TC-Scan]|r Second pass recovered %d loot list(s).",
                    Scan.stats.recovered))
            end
            if stillMissing > 0 then
                -- Deliberately does NOT tell the player to rescan: the result is deterministic.
                -- These are encounters that report an empty loot list at one or more of their
                -- difficulties, which this scan cannot tell apart from "not loaded yet", so they
                -- keep the unrestricted behaviour they had before difficulties were read at all.
                WN:Print(string.format(
                    "|cffffcc00[WN-TC-Scan]|r %d bosses reported no loot at one or more"
                    .. " difficulties; their drops stay unrestricted.", stillMissing))
            end
        end
    end
    Scan.found, Scan.stats, Scan.encMeta, Scan.retry = nil, nil, nil, nil
end

---Second pass over the (instance, difficulty, encounter) triples whose loot list was still
---loading the first time. Serial and unhurried on purpose: this is a short list, and a boss with
---even one unread difficulty produces no whitelist at all, so recovering one read can be what
---makes the whole encounter usable.
local function RunRetry(generation, state)
    if generation ~= Scan.generation then return end
    local blocked = BlockedReason()
    if blocked then return FinishScan(generation, true, blocked) end

    local item = Scan.retry[state.r]
    if not item then return FinishScan(generation, false) end
    state.r = state.r + 1

    SafeCall(EJ_SelectTier, item.tier)
    if item.difficultyID > 0 and EJ_SetDifficulty then
        SafeCall(EJ_SetDifficulty, item.difficultyID)
    end
    SafeCall(EJ_SelectInstance, item.instanceID)
    SafeCall(EJ_SelectEncounter, item.jid)

    C_Timer.After(RETRY_SETTLE_SEC, function()
        if generation ~= Scan.generation then return end
        local _, stillStale = ReadSelectedEncounterLoot(item.did, item.difficultyID)
        if not stillStale then
            local meta = Scan.encMeta[item.did]
            if meta and meta.pending and meta.pending > 0 then
                meta.pending = meta.pending - 1
            end
            Scan.stats.recovered = (Scan.stats.recovered or 0) + 1
        end
        RunRetry(generation, state)
    end)
end

local function RunSlice(generation, state)
    if generation ~= Scan.generation then return end
    local blocked = BlockedReason()
    if blocked then return FinishScan(generation, true, blocked) end

    local t0 = debugprofilestop()
    while state.i <= #state.work do
        local item = state.work[state.i]

        if not state.instanceOpened then
            SafeCall(EJ_SelectTier, item.tier)
            -- Documented prerequisite: EJ_GetEncounterInfoByIndex(index, instanceID) returns nil
            -- until EJ_SelectInstance has been called at least once this session.
            SafeCall(EJ_SelectInstance, item.instanceID)
            state.instanceOpened = true
            state.diffs = InstanceDifficulties()
            state.d = 0
            state.diffApplied = false
            state.e = 1
        end

        -- Walk this instance once per difficulty: the journal's loot list is what the player sees
        -- on the selected difficulty, which is the only way to learn that a mount is Mythic-only.
        -- diffApplied, not an index comparison: this block yields a frame and RunSlice re-enters
        -- with state.e still 1, so a guard based on state.d alone advances twice and reads only
        -- the last difficulty of every instance.
        if not state.diffApplied then
            state.d = state.d + 1
            state.diffApplied = true
            local diffID = state.diffs[state.d] or 0
            if diffID > 0 and EJ_SetDifficulty then
                SafeCall(EJ_SetDifficulty, diffID)
                SafeCall(EJ_SelectInstance, item.instanceID)
                -- The loot list is refetched from the server on a difficulty change and arrives on
                -- EJ_LOOT_DATA_RECIEVED, so hand the client a frame before reading anything.
                C_Timer.After(DIFFICULTY_SETTLE_SEC, function() RunSlice(generation, state) end)
                return
            end
        end

        local ok, _, _, journalEncID, _, _, _, dungeonEncID =
            pcall(EJ_GetEncounterInfoByIndex, state.e, item.instanceID)
        journalEncID = ok and SafeNumber(journalEncID) or nil
        dungeonEncID = ok and SafeNumber(dungeonEncID) or nil

        if not journalEncID then
            -- End of this instance's encounter list: next difficulty, or next instance.
            if state.d < #state.diffs then
                state.e = 1
                state.diffApplied = false
            else
                state.i = state.i + 1
                state.instanceOpened = false
                state.diffApplied = false
                state.e = 1
            end
        else
            if dungeonEncID and EJ_SelectEncounter then
                if SafeCall(EJ_SelectEncounter, journalEncID) then
                    local diffID = state.diffs[state.d] or 0
                    local _, incomplete = ReadSelectedEncounterLoot(dungeonEncID, diffID)
                    if incomplete then
                        -- Mark the encounter itself, not just a counter: a single unread
                        -- difficulty makes every whitelist for this boss untrustworthy.
                        local meta = Scan.encMeta[dungeonEncID]
                        if not meta then
                            meta = { read = {}, nRead = 0, pending = 0 }
                            Scan.encMeta[dungeonEncID] = meta
                        end
                        meta.pending = (meta.pending or 0) + 1
                        if #Scan.retry < RETRY_MAX then
                            Scan.retry[#Scan.retry + 1] = {
                                tier = item.tier, instanceID = item.instanceID,
                                difficultyID = diffID, jid = journalEncID, did = dungeonEncID,
                            }
                        end
                    end
                end
            end
            state.e = state.e + 1
        end

        state.visited = state.visited + 1
        if (debugprofilestop() - t0) > SLICE_BUDGET_MS then
            C_Timer.After(0, function() RunSlice(generation, state) end)
            return
        end
    end

    if #Scan.retry > 0 and not state.retrying then
        state.retrying = true
        state.r = 1
        return RunRetry(generation, state)
    end
    FinishScan(generation, false)
end

-- ── entry point ──────────────────────────────────────────────────────────────

function WarbandNexus:ScanEncounterJournalSources()
    local blocked = BlockedReason()
    if blocked then
        if self.Print then
            self:Print("|cffff6600[WN-TC-Scan]|r Cannot scan right now: " .. blocked .. ".")
        end
        return
    end
    if Scan.running then
        if self.Print then self:Print("|cffffcc00[WN-TC-Scan]|r Already running.") end
        return
    end

    Scan.generation = Scan.generation + 1
    local generation = Scan.generation
    Scan.running = true
    Scan.found, Scan.stats, Scan.encMeta, Scan.retry = {}, {}, {}, {}
    Scan.snapshot = SnapshotEJState()

    -- Clear the class/spec and slot filters or the loot lists come back filtered to the player's
    -- own spec. (0, 0) as "no filter" is not documented; it is wrapped so a refusal cannot abort
    -- the scan, and the snapshot above puts the player's own filter back afterwards.
    SafeCall(EJ_SetLootFilter, 0, 0)
    if C_EncounterJournal and C_EncounterJournal.ResetSlotFilter then
        SafeCall(C_EncounterJournal.ResetSlotFilter)
    end

    if self.Print then
        self:Print("|cff9370DB[WN-TC-Scan]|r Walking the Encounter Journal for mount/pet/toy drops...")
    end

    local work = BuildInstanceWorkList()
    DebugPrint("|cff9370DB[WN-TC-Scan]|r instances queued: " .. #work)
    if #work == 0 then
        return FinishScan(generation, true, "no instances returned by the journal")
    end

    RunSlice(generation, {
        work = work, i = 1, e = 1, d = 0, diffs = {}, diffApplied = false,
        visited = 0, instanceOpened = false,
    })
end

---Stop a running scan and put the player's journal state back.
function WarbandNexus:StopEncounterJournalScan()
    if not Scan.running then return end
    Scan.generation = Scan.generation + 1
    RestoreEJState(Scan.snapshot)
    Scan.running = false
    Scan.snapshot, Scan.found, Scan.stats, Scan.encMeta, Scan.retry = nil, nil, nil, nil, nil
    if self.Print then self:Print("|cffff6600[WN-TC-Scan]|r Stopped.") end
end
