--[[
    Minimal WoW 12.1 API stub: enough surface to LOAD THE REAL ADDON FILES and drive
    event-level scenarios under lua5.1.

    Why this exists: the other test_*.lua scripts here re-implement the logic they check,
    so the shipped file can regress while its test still passes. Tests built on this stub
    load Modules/*.lua verbatim and fire real events at them, so a regression in the
    shipped code fails the gate.

    Test-visible surface:
      M.Advance(seconds)      run every timer due in that window (fake clock, no sleeping)
      M.Fire(event, ...)      dispatch a WoW event to every frame that registered it
      M.chat                  array of lines the addon printed
      M.errors                array of errors raised inside timers / event handlers
      M.world                 mutable world state (map, loot slots, loot sources, API flags)
      M.Reset()               clear chat + errors between phases
]]
local M = {}

local env = _G

-- ---------- clock / timers ----------
local clock = { now = 1000.0 }
local timers = {}   -- { at, fn, cancelled }
env.GetTime = function() return clock.now end

local C_Timer = {}
function C_Timer.After(delay, fn)
    timers[#timers + 1] = { at = clock.now + (tonumber(delay) or 0), fn = fn }
end
function C_Timer.NewTimer(delay, fn)
    local t = { at = clock.now + (tonumber(delay) or 0), fn = fn }
    timers[#timers + 1] = t
    t.Cancel = function(self) (self or t).cancelled = true end
    return t
end
function C_Timer.NewTicker(delay, fn)
    local t = { at = clock.now + (tonumber(delay) or 0), fn = fn, ticker = true, interval = delay }
    timers[#timers + 1] = t
    t.Cancel = function(self) (self or t).cancelled = true end
    return t
end
env.C_Timer = C_Timer

--- Advance the fake clock and run every timer due at or before the new time.
function M.Advance(seconds)
    local target = clock.now + (seconds or 0)
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 10000 then error("timer storm") end
        local nextIdx, nextAt
        for i = 1, #timers do
            local t = timers[i]
            if not t.cancelled and not t.done and t.at <= target then
                if not nextAt or t.at < nextAt then nextAt, nextIdx = t.at, i end
            end
        end
        if not nextIdx then break end
        local t = timers[nextIdx]
        t.done = true
        clock.now = t.at
        local ok, err = pcall(t.fn)
        if not ok then M.errors[#M.errors + 1] = tostring(err) end
    end
    clock.now = target
end
M.errors = {}

-- ---------- frames ----------
local frameProto = {}
frameProto.__index = frameProto
function frameProto:RegisterEvent(ev) self._events[ev] = true end
function frameProto:RegisterUnitEvent(ev) self._events[ev] = true end
function frameProto:UnregisterEvent(ev) self._events[ev] = nil end
function frameProto:UnregisterAllEvents() self._events = {} end
function frameProto:SetScript(name, fn) self._scripts[name] = fn end
function frameProto:GetScript(name) return self._scripts[name] end
function frameProto:Show() self._shown = true end
function frameProto:Hide() self._shown = false end
function frameProto:IsShown() return self._shown end
function frameProto:SetSize() end
function frameProto:SetPoint() end
function frameProto:SetAllPoints() end
function frameProto:AddMessage(msg) M.chat[#M.chat + 1] = msg end

local frames = {}
env.CreateFrame = function()
    local f = setmetatable({ _events = {}, _scripts = {}, _shown = true }, frameProto)
    frames[#frames + 1] = f
    return f
end

--- Fire a WoW event into every frame that registered it.
function M.Fire(event, ...)
    for i = 1, #frames do
        local f = frames[i]
        if f._events[event] and f._scripts.OnEvent then
            local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
            if not ok then M.errors[#M.errors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

-- ---------- chat ----------
M.chat = {}
local chatFrame = { AddMessage = function(_, msg) M.chat[#M.chat + 1] = msg end }
env.DEFAULT_CHAT_FRAME = chatFrame
env.SELECTED_CHAT_FRAME = chatFrame
env.ChatFrame1 = chatFrame
env.NUM_CHAT_WINDOWS = 1
env.GetNumChatWindows = function() return 1 end
env.GetChatWindowMessages = function() return "LOOT" end
env.AddChatWindowMessages = function() end
env.RemoveChatWindowMessages = function() end
env.ChatTypeGroup = {}
env.hooksecurefunc = function() end
env.FCF_GetSelectedChatFrame = function() return chatFrame end

-- ---------- world state (test-controlled) ----------
M.world = {
    mapID = 2405,          -- Voidstorm (Midnight fishing zone)
    inInstance = false,
    instanceType = "none",
    isFishingLoot = false,
    lootSlots = {},        -- { { link = "|Hitem:268730:...|h[x]|h", hasItem = true } }
    lootSources = {},      -- per-slot array of GUIDs
    playerGUID = "Player-1-00000001",
    playerName = "Tester",
    ownedMounts = {},
    ownedPets = {},
    ownedToys = {},
    bagCounts = {},        -- [itemID] = count, backs C_Item.GetItemCount
    itemClass = {},        -- [itemID] = { classID, subClassID }, backs GetItemInfoInstant
    -- Encounter Journal, backing the EJ_* block below:
    --   journal.order     = { { instanceID, isRaid }, ... } in EJ_GetInstanceByIndex order
    --   journal.instances = { [instanceID] = {
    --       diffs      = { difficultyID, ... }   what InstanceHasDifficultyID reports
    --       encounters = { { jid = journalEncounterID, did = dungeonEncounterID }, ... }
    --       loot       = { [difficultyID] = { itemID, ... } or "STALE" }
    --   } }
    journal = { order = {}, instances = {} },
}

env.IsInInstance = function() return M.world.inInstance, M.world.instanceType end
env.GetInstanceInfo = function()
    return "Test", M.world.instanceType, 0, "", 0, 0, false, 0, 0, 0
end
env.IsFishingLoot = function() return M.world.isFishingLoot end
env.GetNumLootItems = function() return #M.world.lootSlots end
env.LootSlotHasItem = function(i)
    local s = M.world.lootSlots[i]; return s and s.hasItem or false
end
env.GetLootSlotLink = function(i)
    local s = M.world.lootSlots[i]; return s and s.link or nil
end
env.GetLootSourceInfo = function(i)
    local src = M.world.lootSources[i]
    if not src then return end
    return unpack(src)
end
env.UnitGUID = function(unit)
    if unit == "player" then return M.world.playerGUID end
    return nil
end
env.UnitName = function() return M.world.playerName end
env.UnitExists = function() return false end
env.InCombatLockdown = function() return false end
env.IsInGroup = function() return false end
env.IsInRaid = function() return false end
env.GetRealmName = function() return "TestRealm" end
-- GetStatistic(category[, index]) returns the value as a STRING ("Wrapping the returned value with
-- tonumber() is necessary" -- warcraft.wiki.gg/wiki/API_GetStatistic), or nil when unknown. Tests
-- populate M.statistics[statID]; anything unset reads as nil, which is the "no value" case.
-- A stub that returned nil unconditionally left the whole statistics seed/reseed path inert: zero
-- GetStatistic calls across every suite, while 57 statistic-backed counter buckets existed.
M.statistics = {}
M.statCalls = 0
function M.SetStatistic(statID, value)
    -- Stored as a string on purpose, so the product's own tostring/gsub/tonumber handling is exercised.
    M.statistics[statID] = value ~= nil and tostring(value) or nil
end
function M.ClearStatistics() M.statistics = {}; M.statCalls = 0 end
env.GetStatistic = function(category)
    M.statCalls = M.statCalls + 1
    return M.statistics[category]
end

-- Midnight 12.0 secret values. Tests opt specific values in with M.MarkSecret(v); everything else
-- reads as non-secret. A stub that always answered false left every issecretvalue guard in the
-- addon (200+ of them) permanently on its happy path, so the defensive branches were never run.
M.secrets = setmetatable({}, { __mode = "k" })
function M.MarkSecret(v) M.secrets[v] = true; return v end
function M.ClearSecrets() for k in pairs(M.secrets) do M.secrets[k] = nil end end
env.issecretvalue = function(v) return M.secrets[v] == true end

-- Real UiMap.db2 parent chain for the Midnight maps, build 12.1.0.69299 (wago.tools).
-- 2537 is the Quel'Thalas region map and carries no fishing entry, which is exactly why
-- 2424 / 2541 have to be listed explicitly in CollectibleSourceDB.
M.uiMapParents = {
    [2393] = 2395,   -- Silvermoon City   -> Eversong Woods
    [2395] = 2537,   -- Eversong Woods    -> Quel'Thalas
    [2405] = 2537,   -- Voidstorm         -> Quel'Thalas
    [2413] = 2537,   -- Harandar          -> Quel'Thalas
    [2424] = 2537,   -- Isle of Quel'Danas-> Quel'Thalas  (NOT Eversong)
    [2437] = 2537,   -- Zul'Aman          -> Quel'Thalas
    [2444] = 2405,   -- Slayer's Rise     -> Voidstorm
    [2509] = 2512,   -- Vaults of Atal'Utek -> The Coiled Isle
    [2512] = 2537,   -- The Coiled Isle   -> Quel'Thalas
    [2536] = 2437,   -- Atal'Aman         -> Zul'Aman
    [2541] = 2537,   -- Arcantina         -> Quel'Thalas  (NOT Voidstorm)
    [2576] = 2413,   -- The Den           -> Harandar
}

env.C_Map = {
    GetBestMapForUnit = function() return M.world.mapID end,
    GetMapInfo = function(id)
        return { mapID = id, name = "Map" .. tostring(id), parentMapID = M.uiMapParents[id] }
    end,
}
env.C_QuestLog = {
    IsQuestFlaggedCompleted = function(qid)
        return M.world.completedQuests and M.world.completedQuests[qid] == true or false
    end
}
function M.SetQuestCompleted(qid, completed)
    if not M.world.completedQuests then M.world.completedQuests = {} end
    M.world.completedQuests[qid] = (completed ~= false)
end
env.C_MountJournal = {
    GetMountInfoByID = function(id) return "Mount" .. tostring(id) end,
    GetMountFromItem = function() return nil end,
    GetMountIDs = function() return {} end,
    GetMountInfoExtraByID = function() return nil end,
}
env.C_PetJournal = {
    GetPetInfoBySpeciesID = function(id) return "Pet" .. tostring(id) end,
    GetNumCollectedInfo = function() return 0, 0 end,
    GetPetInfoByPetID = function() return nil end,
}
env.C_ToyBox = { GetToyInfo = function() return nil end }
env.PlayerHasToy = function(id) return M.world.ownedToys[id] == true end
env.C_TransmogCollection = { PlayerHasTransmogByItemInfo = function() return false end }
env.C_Item = {
    GetItemInfo = function(id) return "Item" .. tostring(id), "|Hitem:" .. tostring(id) .. "::::::::::::::::|h[Item" .. tostring(id) .. "]|h" end,
    -- Real returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID.
    -- world.itemClass lets a test declare a collectible (Miscellaneous 15: mount 5, pet 2).
    GetItemInfoInstant = function(id)
        local c = M.world.itemClass and M.world.itemClass[id]
        if not c then return id end
        return id, nil, nil, nil, nil, c[1], c[2]
    end,
    -- (itemInfo, includeBank, includeUses, includeReagentBank, includeAccountBank).
    -- The stub ignores the scope flags: bagCounts models "the player holds it somewhere".
    GetItemCount = function(id) return M.world.bagCounts[id] or 0 end,
    RequestLoadItemDataByID = function() end,
    DoesItemExistByID = function() return true end,
}
env.GetItemInfo = env.C_Item.GetItemInfo
env.GetItemInfoInstant = env.C_Item.GetItemInfoInstant
env.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
}
-- ---------- Encounter Journal ----------
-- Enough surface for TryCounterService_JournalScan to walk tier -> instance -> difficulty ->
-- encounter -> loot for real. The loot list is keyed by difficulty because that is the behaviour
-- the scan depends on: the journal shows what drops at the difficulty currently selected.
env.DifficultyUtil = { ID = {
    DungeonNormal = 1, DungeonHeroic = 2, DungeonMythic = 23, DungeonChallenge = 8,
    DungeonTimewalker = 24, RaidLFR = 7, Raid10Normal = 3, Raid10Heroic = 5,
    Raid25Normal = 4, Raid25Heroic = 6, RaidWorld = 172, PrimaryRaidLFR = 17,
    PrimaryRaidNormal = 14, PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16,
    RaidTimewalker = 33, Raid40 = 9,
} }

local ej = { tier = 1, instanceID = nil, difficulty = 14, encounter = nil, filterClass = 0,
             filterSpec = 0, slotFilter = 0 }
M.ej = ej   -- test-visible: ej.visits records every (instance, difficulty, encounter) read
ej.visits = {}

local function ejInstance() return M.world.journal.instances[ej.instanceID] end

--- The raw loot entry for the selected encounter at the selected difficulty. Either a plain
--- array of itemIDs, the string "STALE" (never arrives), or { staleFor = n, items = {...} }
--- which reports out-of-date for the next n checks and then delivers -- the real client's
--- behaviour when a difficulty change sends the list back to the server.
local function ejRaw()
    local inst = ejInstance()
    if not inst or not ej.encounter then return nil end
    return inst.loot and inst.loot[ej.difficulty]
end
local function ejItems()
    local raw = ejRaw()
    if type(raw) ~= "table" then return nil end
    if raw.items then return raw.items end
    return raw
end

env.EJ_GetNumTiers = function() return 1 end
env.EJ_SelectTier = function(t) ej.tier = t return true end
env.EJ_GetCurrentTier = function() return ej.tier end
env.EJ_GetDifficulty = function() return ej.difficulty end
env.EJ_SetDifficulty = function(d) ej.difficulty = d end
env.EJ_GetLootFilter = function() return ej.filterClass, ej.filterSpec end
env.EJ_SetLootFilter = function(c, sp) ej.filterClass, ej.filterSpec = c, sp end
env.EJ_IsValidInstanceDifficulty = function() return true end
env.EJ_IsLootListOutOfDate = function()
    local raw = ejRaw()
    if raw == "STALE" then return true end
    if type(raw) == "table" and (raw.staleFor or 0) > 0 then
        raw.staleFor = raw.staleFor - 1
        return true
    end
    return false
end

env.EJ_GetInstanceByIndex = function(index, isRaid)
    local order = M.world.journal.order
    local n = 0
    for i = 1, #order do
        if order[i][2] == isRaid then
            n = n + 1
            if n == index then return order[i][1] end
        end
    end
    return nil
end
env.EJ_SelectInstance = function(id) ej.instanceID = id; ej.encounter = nil end
env.EJ_GetEncounterInfoByIndex = function(index, instanceID)
    local inst = M.world.journal.instances[instanceID]
    local e = inst and inst.encounters and inst.encounters[index]
    if not e then return nil end
    -- name, description, journalEncounterID(3), rootSectionID, link, journalInstanceID,
    -- dungeonEncounterID(7), instanceID
    return "Boss", "", e.jid, 0, nil, instanceID, e.did, instanceID
end
env.EJ_SelectEncounter = function(jid) ej.encounter = jid return true end
env.EJ_GetNumLoot = function()
    local l = ejItems()
    if type(l) ~= "table" then return 0 end
    ej.visits[#ej.visits + 1] = tostring(ej.instanceID) .. "@" .. tostring(ej.difficulty)
        .. ":" .. tostring(ej.encounter)
    return #l
end

env.C_EncounterJournal = {
    GetLootInfoByIndex = function(i)
        local l = ejItems()
        if type(l) ~= "table" then return nil end
        return { itemID = l[i] }
    end,
    InstanceHasDifficultyID = function(d)
        local inst = ejInstance()
        if not inst or not inst.diffs then return false end
        for i = 1, #inst.diffs do if inst.diffs[i] == d then return true end end
        return false
    end,
    GetSlotFilter = function() return ej.slotFilter end,
    SetSlotFilter = function(f) ej.slotFilter = f end,
    ResetSlotFilter = function() ej.slotFilter = 0 end,
}

env.C_AchievementInfo = {}
env.C_DelvesUI = { GetCurrentDelvesSeasonNumber = function() return 2 end }
env.C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
env.C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function() return nil end }
env.IsAddOnLoaded = function() return false end
env.Enum = { ItemClass = {}, PlayerInteractionType = {} }
env.Constants = {}
env.LE_ITEM_QUALITY_EPIC = 4
env.Item = {
    CreateFromItemID = function(id)
        return { ContinueOnItemLoad = function(_, cb) if cb then cb() end end, GetItemID = function() return id end }
    end,
}

-- ---------- lua-side WoW globals ----------
-- Milliseconds since client start; the addon uses it to time-budget batched work. Driven by the
-- fake clock so a test that advances time also advances the budget, and a batch loop that expects
-- to yield actually yields instead of spinning.
env.debugprofilestop = function() return clock.now * 1000 end

env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.strsplit = function(sep, str)
    local out = {}
    local pattern = "([^" .. sep .. "]*)"
    for piece in string.gmatch(str, pattern .. sep .. "?") do out[#out + 1] = piece end
    -- gmatch above emits a trailing empty capture; drop it
    if out[#out] == "" then out[#out] = nil end
    return unpack(out)
end
env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
env.format = string.format
env.tinsert = table.insert
env.tremove = table.remove
env.sort = table.sort
env.date = os.date
env.time = os.time
env.print = print
env.securecall = function(fn, ...) return fn(...) end
env.geterrorhandler = function() return function(e) M.errors[#M.errors + 1] = tostring(e) end end

-- Blizzard GlobalStrings (SAVE, CLOSE, SEARCH, ...): locale files use them as `X or "fallback"`.
-- Return the key name so the `or` fallback is never taken and nothing blows up on concat.
setmetatable(env, {
    __index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z][A-Z0-9_]+$") then return k end
        return nil
    end,
})

function M.Reset()
    M.chat = {}
    M.errors = {}
end

return M
