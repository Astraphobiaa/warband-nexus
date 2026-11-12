--[[
    Warband Nexus - API surface snapshot (`/wn caps api`).

    The wiki's Forever API diff lists names with no signatures and no event arguments, and a
    namespace existing in Forever says nothing about the system behind it. So instead of reading
    a page, ask the running client: walk every C_* namespace for the functions it really has, and
    settle each event with C_EventUtils.IsEventValid (10.0.0+, callable from addon code).

    The result goes to db.global.apiSnapshot rather than chat -- a few thousand names do not fit
    in the frame, and SavedVariables can be read off disk after a /reload.
    Diagnostic only: nothing on the login path calls this.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local USED_EVENTS = {
    "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED",
    "ACCOUNT_MONEY",
    "ACHIEVEMENT_EARNED",
    "ADDON_ACTION_FORBIDDEN",
    "ADDON_LOADED",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "BANKFRAME_CLOSED",
    "BANKFRAME_OPENED",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_KEYSTONE_SLOTTED",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "CHAT_MSG_LOOT",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "CRAFTINGORDERS_UPDATE_ORDER_COUNT",
    "CRITERIA_EARNED",
    "CRITERIA_UPDATE",
    "CURRENCY_DISPLAY_UPDATE",
    "DELVES_ACCOUNT_DATA_ELEMENT_CHANGED",
    "DISPLAY_SIZE_CHANGED",
    "ENCOUNTER_END",
    "GET_ITEM_INFO_RECEIVED",
    "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_UPDATE_TABS",
    "ITEM_UPGRADE_MASTER_UPDATE",
    "MAIL_CLOSED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "MODIFIER_STATE_CHANGED",
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
    "MYTHIC_PLUS_NEW_WEEKLY_RECORD",
    "NEW_MOUNT_ADDED",
    "NEW_PET_ADDED",
    "NEW_RECIPE_LEARNED",
    "NEW_TOY_ADDED",
    "PERKS_ACTIVITY_COMPLETED",
    "PET_JOURNAL_LIST_UPDATE",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    "PLAYER_DIFFICULTY_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_GUILD_UPDATE",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_LEVEL_CHANGED",
    "PLAYER_LEVEL_UP",
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "PLAYER_MONEY",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_XP_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN",
    "RAID_INSTANCE_WELCOME",
    "SKILL_LINES_CHANGED",
    "TIME_PLAYED_MSG",
    "TOKEN_MARKET_PRICE_UPDATED",
    "TOOLTIP_DATA_UPDATE",
    "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_SHOW",
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_NODE_CHANGED",
    "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "TRANSMOG_COLLECTION_UPDATED",
    "UI_SCALE_CHANGED",
    "UPDATE_EXHAUSTION",
    "UPDATE_FACTION",
    "UPDATE_INSTANCE_INFO",
    "UPDATE_PENDING_MAIL",
    "WEEKLY_REWARDS_ITEM_CHANGED",
    "WEEKLY_REWARDS_UPDATE",
    "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
}

local FOREVER_NEW_EVENTS = {
    "ALERT_AGE_VERIFICATION_RESTRICTED",
    "BC_26_COLD_SWAP_FEATURE_ENABLED_CHANGED",
    "BC_26_EXPERIENCE_CHANGED",
    "CHAT_MSG_COLLECTED_APPEARANCE",
    "DIEL_CYCLE_CHANGED",
    "GAME_PAD_ALLOW_HOVER_EVENTS_WITH_FREE_LOOK_CHANGED",
    "GAME_RULES_CHANGED",
    "GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED",
    "GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED",
    "GLOBAL_REGION_MOUSE_DOWN",
    "GLOBAL_REGION_MOUSE_UP",
    "GUILD_PREFERRED_PLAY_SETTINGS_UPDATED",
    "INPUT_DEVICE_INTERFACE_TRANSITION",
    "LFG_LIST_ROLE_UPDATE",
    "LFG_LIST_SHOW_SEARCH",
    "PET_STATS_UPDATE",
    "PET_SPELL_POWER_UPDATE",
    "PLAYER_PVP_FLAG_CHANGED",
    "PLAYER_SWING",
    "PLAYER_SWING_RANGE_UPDATE",
    "SHARD_TRANSFER",
    "SHARD_TRANSFER_IMMINENT",
    "SOCIAL_UI_RAID_LIST_SYSTEM_STATUS_UPDATED",
    "UNIT_HAPPINESS",
    "UNIT_PET_TRAINING_POINTS",
    "VIEWED_TRANSMOG_OUTFIT_SLOT_OPTION_CHANGED",
    "VIEWED_TRANSMOG_OUTFIT_SLOT_WEAPON_OPTION_CHANGED",
}

local function SortedKeys(tbl, wantType)
    local out = {}
    for k, v in pairs(tbl) do
        if type(k) == "string" and (not wantType or type(v) == wantType) then
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return out
end

--- Every C_* namespace in _G and the function names it really exposes.
local function SnapshotNamespaces()
    local out, count = {}, 0
    for name, tbl in pairs(_G) do
        if type(name) == "string" and type(tbl) == "table" and name:sub(1, 2) == "C_" then
            local fns = SortedKeys(tbl, "function")
            out[name] = fns
            count = count + #fns
        end
    end
    return out, count
end

--- IsEventValid is the only safe answer: registering a bad name raises instead of returning nil.
local function TestEvents(list, out)
    local valid, invalid = 0, 0
    local fn = C_EventUtils and C_EventUtils.IsEventValid
    for i = 1, #list do
        local name = list[i]
        local ok, res
        if fn then ok, res = pcall(fn, name) end
        if not fn or not ok then
            out[name] = "unknown"
        elseif res then
            out[name] = true
            valid = valid + 1
        else
            out[name] = false
            invalid = invalid + 1
        end
    end
    return valid, invalid
end

--- Enum tables carry the shape of a system, not just its entry points. C_GameRules turned out to
--- be the Forever-specific surface (GetForeverExperiencePreset, IsGameRuleActive, ...), so the
--- matching Enum.GameRule / Enum.GameMode values are what actually name the rules in play.
local function SnapshotEnums()
    local out, count = {}, 0
    if type(Enum) ~= "table" then return out, count end
    for name, tbl in pairs(Enum) do
        if type(name) == "string" and type(tbl) == "table" then
            local vals = {}
            for k, v in pairs(tbl) do
                if type(k) == "string" and type(v) == "number" then vals[k] = v end
            end
            out[name] = vals
            count = count + 1
        end
    end
    return out, count
end

--- Direct readout of the game-mode API: this is the authoritative flavor answer, not a guess.
local function SnapshotGameRules()
    local out = {}
    local function try(label, fn)
        local ok, v = pcall(fn)
        out[label] = ok and (v == nil and "nil" or v) or "error"
    end
    if type(C_GameRules) ~= "table" then return out end
    try("activeGameMode", function() return C_GameRules.GetActiveGameMode() end)
    try("isStandard", function() return C_GameRules.IsStandard() end)
    try("isHardcore", function() return C_GameRules.IsHardcoreActive() end)
    try("isSelfFound", function() return C_GameRules.IsSelfFoundAllowed() end)
    try("isPlunderstorm", function() return C_GameRules.IsPlunderstorm() end)
    try("foreverXpPreset", function() return C_GameRules.GetForeverExperiencePreset() end)
    try("gameModeRecordID", function() return C_GameRules.GetCurrentGameModeRecordID() end)
    -- Every Enum.GameRule value, asked one by one: which rules this client actually has active.
    if type(Enum) == "table" and type(Enum.GameRule) == "table"
        and type(C_GameRules.IsGameRuleActive) == "function" then
        local rules = {}
        for name, value in pairs(Enum.GameRule) do
            if type(name) == "string" and type(value) == "number" then
                local ok, active = pcall(C_GameRules.IsGameRuleActive, value)
                rules[name] = ok and (active and true or false) or "error"
            end
        end
        out.activeRules = rules
    end
    return out
end

--- Plain globals matter as much as the C_ namespaces: the achievement surface Forever's Legacy
--- System would most likely reuse (GetAchievementInfo, GetAchievementCriteriaInfo, ...) lives in
--- _G, not under a C_ table, so the first snapshot could not have seen it.
local function SnapshotGlobalFunctions()
    local out = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "function" and name:sub(1, 2) ~= "C_" then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

--[[
    Legacy System sweep.

    Forever has no C_Legacy namespace, but _G carries ToggleLegacySystemUI, ToggleLegacyChallenges
    and ShowLegacyChallenge next to the full achievement API, so the Legacy System is the
    achievement surface wearing a different UI. That matters for one question in particular: the
    achievement API reports criteria and rewards for entries that are NOT finished, so a reward
    tier can be read before it unlocks.

    Walks the category tree once and records what each achievement declares. Bounded and
    pcall-guarded; diagnostic only.
]]
local MAX_ACHIEVEMENTS = 600
local function SnapshotLegacy()
    local out = { categories = {}, achievements = {}, truncated = false }
    if type(GetCategoryList) ~= "function" then return out end
    local okList, cats = pcall(GetCategoryList)
    if not okList or type(cats) ~= "table" then return out end
    local seen = 0
    for ci = 1, #cats do
        local id = cats[ci]
        local okName, name, parent = pcall(GetCategoryInfo, id)
        out.categories[#out.categories + 1] = {
            id = id,
            name = okName and tostring(name) or nil,
            parent = okName and parent or nil,
        }
        local okNum, num = pcall(GetCategoryNumAchievements, id)
        if okNum and type(num) == "number" then
            for ai = 1, num do
                if seen >= MAX_ACHIEVEMENTS then out.truncated = true break end
                local ok, aid, aname, points, completed = pcall(GetAchievementInfo, id, ai)
                if ok and aid then
                    local entry = {
                        id = aid,
                        name = tostring(aname),
                        points = points,
                        completed = completed and true or false,
                        category = id,
                    }
                    local okC, nCrit = pcall(GetAchievementNumCriteria, aid)
                    if okC and type(nCrit) == "number" and nCrit > 0 then
                        entry.criteria = {}
                        for k = 1, nCrit do
                            local okK, cname, _, done, qty, req = pcall(GetAchievementCriteriaInfo, aid, k)
                            if okK then
                                entry.criteria[k] = {
                                    name = tostring(cname),
                                    done = done and true or false,
                                    have = qty, need = req,
                                }
                            end
                        end
                    end
                    local okR, nRew = pcall(GetAchievementNumRewards, aid)
                    if okR and type(nRew) == "number" and nRew > 0 then
                        entry.rewards = {}
                        for k = 1, nRew do
                            local okRR, rew = pcall(GetAchievementReward, aid, k)
                            entry.rewards[k] = okRR and tostring(rew) or nil
                        end
                    end
                    out.achievements[#out.achievements + 1] = entry
                    seen = seen + 1
                end
            end
        end
        if out.truncated then break end
    end
    local okPts, pts = pcall(GetTotalAchievementPoints)
    out.totalPoints = okPts and pts or nil
    return out
end

--- Forever shows two-word player names ("Elementalist Vhorzen") but the addon stores only the
--- first word, and nothing in the addon splits on a space. So the question is which of the
--- name APIs returns which half -- ask all of them rather than guess.
local function SnapshotPlayerName()
    local out = {}
    local function try(label, fn)
        local ok, a, b = pcall(fn)
        if not ok then out[label] = "error"
        elseif a == nil then out[label] = "nil"
        else out[label] = tostring(a) .. (b ~= nil and (" | " .. tostring(b)) or "") end
    end
    try("UnitName", function() return UnitName("player") end)
    try("UnitFullName", function() return UnitFullName("player") end)
    try("GetUnitName_true", function() return GetUnitName("player", true) end)
    try("UnitPVPName", function() return UnitPVPName("player") end)
    try("GetTitleName_cur", function() return GetTitleName(GetCurrentTitle()) end)
    try("UnitNameUnmodified", function() return UnitNameUnmodified("player") end)
    try("GetRealmName", function() return GetRealmName() end)
    try("normalizedRealm", function() return GetNormalizedRealmName() end)
    try("playerGUID", function() return UnitGUID("player") end)
    return out
end

--[[
    Paragon sweep.

    C_Reputation.GetFactionParagonInfo and friends exist on Forever, but so did C_WeeklyRewards
    and C_MythicPlus for systems that are not there. Paragon is "keep earning past Exalted for a
    reward bag", which has no obvious place in a vanilla reputation ladder -- so walk the real
    faction list and ask each one instead of reading the namespace.
]]
local function SnapshotParagon(out)
    local res = { checked = 0, paragon = {} }
    if type(C_Reputation) ~= "table" or type(C_Reputation.IsFactionParagon) ~= "function" then
        res.available = false
        return res
    end
    res.available = true
    local okN, num = pcall(C_Reputation.GetNumFactions)
    if not okN or type(num) ~= "number" then return res end
    for i = 1, num do
        local okD, data = pcall(C_Reputation.GetFactionDataByIndex, i)
        if okD and type(data) == "table" and data.factionID then
            res.checked = res.checked + 1
            local okP, isPara = pcall(C_Reputation.IsFactionParagon, data.factionID)
            if okP and isPara then
                local okI, value, threshold, rewardQuestID, hasRewardPending =
                    pcall(C_Reputation.GetFactionParagonInfo, data.factionID)
                res.paragon[#res.paragon + 1] = {
                    factionID = data.factionID,
                    name = tostring(data.name),
                    value = okI and value or nil,
                    threshold = okI and threshold or nil,
                    rewardQuestID = okI and rewardQuestID or nil,
                    hasRewardPending = okI and hasRewardPending or nil,
                }
            end
        end
    end
    return res
end

--[[
    Renown tracks.

    Forever exposes two major factions: 2800 "PvP Rank Points" and 2802 "Legacy Track". So the
    Legacy System is a renown track, not an achievement category -- which is the answer to
    whether locked reward tiers can be read in advance: GetRenownLevels reports every level with
    its locked flag, and GetRenownRewardsForLevel returns that level's rewards whether or not it
    is reached. Enum.RenownRewardsFlags even marks Milestone / Capstone tiers.
]]
local MAX_RENOWN_LEVELS = 120
local function SnapshotRenownTracks()
    local out = {}
    if type(C_MajorFactions) ~= "table" then return out end
    local okIDs, ids = pcall(C_MajorFactions.GetMajorFactionIDs)
    if not okIDs or type(ids) ~= "table" then return out end
    for n = 1, #ids do
        local fid = ids[n]
        local track = { id = fid, levels = {} }
        local okD, data = pcall(C_MajorFactions.GetMajorFactionData, fid)
        if okD and type(data) == "table" then
            track.name = tostring(data.name)
            track.renownLevel = data.renownLevel
            track.maxLevel = data.renownLevelThreshold
        end
        local okL, levels = pcall(C_MajorFactions.GetRenownLevels, fid)
        if okL and type(levels) == "table" then
            for k = 1, math.min(#levels, MAX_RENOWN_LEVELS) do
                local entry = levels[k]
                local lvl = (type(entry) == "table" and entry.level) or entry
                local row = {
                    level = lvl,
                    locked = (type(entry) == "table") and (entry.locked and true or false) or nil,
                    rewards = nil,
                }
                local okR, rewards = pcall(C_MajorFactions.GetRenownRewardsForLevel, fid, lvl)
                if okR and type(rewards) == "table" and #rewards > 0 then
                    row.rewards = {}
                    for r = 1, #rewards do
                        local rw = rewards[r]
                        row.rewards[r] = {
                            name = tostring(rw.name),
                            type = rw.renownRewardType,
                            flags = rw.flags,
                            itemID = rw.itemID,
                            icon = rw.icon,
                        }
                    end
                end
                track.levels[#track.levels + 1] = row
            end
        end
        out[#out + 1] = track
    end
    return out
end

--[[
    Collection journal sizes as the client answers them, next to what the addon has stored. Settles
    "the API returns nothing here" vs "our scan never ran / never finished" without guessing -- the
    Forever store showed 0 toys and 0 illusions with no illusion completion stamp.
    Each call is pcall'd and recorded as a value, "nil", "error" or "ABSENT".
]]
local function SnapshotCollectionCounts()
    local out = { api = {}, store = {} }
    local function call(label, ns_, fnName, ...)
        if type(ns_) ~= "table" or type(ns_[fnName]) ~= "function" then out.api[label] = "ABSENT" return nil end
        local ok, a = pcall(ns_[fnName], ...)
        if not ok then out.api[label] = "error" return nil end
        if a == nil then out.api[label] = "nil" return nil end
        out.api[label] = (type(a) == "table") and ("table(" .. #a .. ")") or tostring(a)
        return a
    end
    call("ToyBox.GetNumToys", C_ToyBox, "GetNumToys")
    call("ToyBox.GetNumTotalDisplayedToys", C_ToyBox, "GetNumTotalDisplayedToys")
    call("ToyBox.GetNumLearnedDisplayedToys", C_ToyBox, "GetNumLearnedDisplayedToys")
    call("ToyBox.GetNumFilteredToys", C_ToyBox, "GetNumFilteredToys")
    -- Same counts the way the journal scan reads them: Blizzard_Collections loaded and every toy
    -- filter opened (shared helper), then the player's filters restored. Out of combat only.
    local Mat = ns.CollectionMaterialize
    local RT = ns.CollectionServiceRT
    if not (InCombatLockdown and InCombatLockdown()) and RT and RT.OpenAllToyBoxFilters and RT.RestoreToyBoxFilters then
        if Mat and Mat.EnsureBlizzardCollectionsLoaded then pcall(Mat.EnsureBlizzardCollectionsLoaded) end
        local saved = RT.OpenAllToyBoxFilters()
        call("ToyBox.open.GetNumFilteredToys", C_ToyBox, "GetNumFilteredToys")
        call("ToyBox.open.GetNumTotalDisplayedToys", C_ToyBox, "GetNumTotalDisplayedToys")
        call("ToyBox.open.GetToyFromIndex1", C_ToyBox, "GetToyFromIndex", 1)
        -- Did the setters stick, and what does the filter space look like on this client?
        call("ToyBox.open.GetCollectedShown", C_ToyBox, "GetCollectedShown")
        call("ToyBox.open.GetUncollectedShown", C_ToyBox, "GetUncollectedShown")
        call("ToyBox.open.GetUnusableShown", C_ToyBox, "GetUnusableShown")
        call("ToyBoxInfo.IsUsingDefaultFilters", C_ToyBoxInfo, "IsUsingDefaultFilters")
        call("ToyBoxInfo.HasAnyToy", C_ToyBoxInfo, "HasAnyToy")
        out.api["GetNumExpansions"] = tostring(GetNumExpansions and GetNumExpansions() or "ABSENT")
        --[[
            The client may rebuild the filtered list asynchronously (Blizzard's ToyBox redraws on
            TOYS_UPDATED). Re-read once that fires, or after 3s, then restore the player's filters.
            Lands in apiSnapshot.collections.api["ToyBox.later.*"]; /reload to flush it to disk.
        ]]
        local addon = WarbandNexus
        local done = false
        local function later()
            if done then return end
            done = true
            pcall(addon.UnregisterEvent, addon, "TOYS_UPDATED")
            local snap = addon.db and addon.db.global and addon.db.global.apiSnapshot
            local api = snap and snap.collections and snap.collections.api
            if type(api) == "table" then
                local function put(label, fnName, ...)
                    local fn = C_ToyBox and C_ToyBox[fnName]
                    if type(fn) ~= "function" then api[label] = "ABSENT" return nil end
                    local ok, v = pcall(fn, ...)
                    api[label] = ok and tostring(v) or "error"
                    return ok and v or nil
                end
                local n = put("ToyBox.later.GetNumFilteredToys", "GetNumFilteredToys")
                put("ToyBox.later.GetNumTotalDisplayedToys", "GetNumTotalDisplayedToys")
                put("ToyBox.later.GetNumLearnedDisplayedToys", "GetNumLearnedDisplayedToys")
                local ids = {}
                n = (type(n) == "number" and not (issecretvalue and issecretvalue(n))) and n or 0
                for i = 1, math.min(n, 40) do
                    local ok, id = pcall(C_ToyBox.GetToyFromIndex, i)
                    if ok and type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
                        local has = PlayerHasToy and PlayerHasToy(id)
                        ids[#ids + 1] = id .. ((has == true) and "+" or "")
                    end
                end
                api["ToyBox.later.ids"] = table.concat(ids, ",")
            end
            RT.RestoreToyBoxFilters(saved)
        end
        pcall(addon.RegisterEvent, addon, "TOYS_UPDATED", later)
        C_Timer.After(3, later)
    end
    local illusions = call("TransmogCollection.GetIllusions", C_TransmogCollection, "GetIllusions")
    if type(illusions) == "table" then
        local collected, hidden = 0, 0
        for i = 1, #illusions do
            local info = illusions[i]
            if type(info) == "table" then
                if info.isCollected == true then collected = collected + 1 end
                if info.isHideVisual == true then hidden = hidden + 1 end
            end
        end
        out.api["TransmogCollection.GetIllusions.collected"] = collected
        out.api["TransmogCollection.GetIllusions.hideVisual"] = hidden
    end
    local store = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.collectionStore
    if type(store) == "table" then
        for _, cat in ipairs({ "mount", "pet", "toy", "achievement", "title", "illusion" }) do
            local n = 0
            for _ in pairs(store[cat] or {}) do n = n + 1 end
            out.store[cat] = n
        end
        out.store.scanCompleted = store.scanCompleted
        out.store.achievementScanTotal = store.achievementScanTotal
    end
    return out
end

function WarbandNexus:WriteApiSnapshot()
    if not self.db or not self.db.global then return nil end
    local namespaces, fnCount = SnapshotNamespaces()
    local events = {}
    local okUsed, badUsed = TestEvents(USED_EVENTS, events)
    local okNew, badNew = TestEvents(FOREVER_NEW_EVENTS, events)
    local globals = SnapshotGlobalFunctions()
    local legacy = SnapshotLegacy()
    local playerName = SnapshotPlayerName()
    local renownTracks = SnapshotRenownTracks()
    local paragon = SnapshotParagon()
    local enums, enumCount = SnapshotEnums()
    local gameRules = SnapshotGameRules()
    local version, build, _, interface = GetBuildInfo()
    self.db.global.apiSnapshot = {
        takenAt = time(),
        version = tostring(version),
        build = tostring(build),
        interface = interface,
        isForever = (ns.Capabilities and ns.Capabilities.IsForeverClient
            and ns.Capabilities.IsForeverClient()) or false,
        namespaces = namespaces,
        events = events,
        enums = enums,
        gameRules = gameRules,
        globals = globals,
        legacy = legacy,
        playerName = playerName,
        renownTracks = renownTracks,
        paragon = paragon,
        collections = SnapshotCollectionCounts(),
    }
    return self.db.global.apiSnapshot, fnCount, okUsed, badUsed, okNew, badNew, enumCount
end

--[[
    Full API documentation dump (`/wn apidoc`).

    The snapshot above collects NAMES only, because Lua cannot introspect a C function's signature.
    The client ships the signatures anyway: Blizzard_APIDocumentation is an on-demand addon whose
    APIDocumentation.systems table carries every function with its arguments and returns, and every
    event with its payload. Loading it is the only way to get argument names and types, and it is
    generated from this exact build -- so it also answers which systems this game type really has.

    Written compactly (one string per entry) because the full tree would be several megabytes of
    SavedVariables. Diagnostic only; nothing on the login path loads the documentation addon.
]]
local function DescribeFields(list)
    if type(list) ~= "table" or #list == 0 then return "" end
    local parts = {}
    for i = 1, #list do
        local f = list[i]
        local name = tostring(f.Name or "?")
        local ftype = tostring(f.Type or "?")
        if f.Nilable then ftype = ftype .. "?" end
        parts[#parts + 1] = name .. ":" .. ftype
    end
    return table.concat(parts, ", ")
end

function WarbandNexus:WriteApiDocumentation()
    if not self.db or not self.db.global then return nil, "db" end
    -- The viewer addon and the DATA addon are different: Blizzard_APIDocumentation is the UI,
    -- Blizzard_APIDocumentationGenerated is what fills APIDocumentation.systems. Loading only
    -- the first one leaves systems empty, which is what happened on the first attempt.
    local tried = {}
    for _, name in ipairs({ "Blizzard_APIDocumentationGenerated", "Blizzard_APIDocumentation" }) do
        local loaded = false
        if C_AddOns and C_AddOns.LoadAddOn then
            local ok, res = pcall(C_AddOns.LoadAddOn, name)
            loaded = ok and res and true or false
        end
        tried[#tried + 1] = name .. "=" .. tostring(loaded)
    end
    if not APIDocumentation and APIDocumentation_LoadUI then
        pcall(APIDocumentation_LoadUI)
    end
    local systems = APIDocumentation and APIDocumentation.systems
    if type(systems) ~= "table" or #systems == 0 then
        return nil, "no systems (" .. table.concat(tried, ", ") .. ")"
    end
    if type(systems) ~= "table" then return nil, "APIDocumentation unavailable" end

    local out = { functions = {}, events = {}, systems = {} }
    for i = 1, #systems do
        local sys = systems[i]
        local sysName = tostring(sys.Name or sys.Namespace or "?")
        out.systems[#out.systems + 1] = sysName
        local fns = sys.Functions
        if type(fns) == "table" then
            for k = 1, #fns do
                local fn = fns[k]
                local owner = sys.Namespace and (sys.Namespace .. ".") or ""
                out.functions[#out.functions + 1] = string.format("%s%s(%s) -> %s",
                    owner, tostring(fn.Name),
                    DescribeFields(fn.Arguments), DescribeFields(fn.Returns))
            end
        end
        local evs = sys.Events
        if type(evs) == "table" then
            for k = 1, #evs do
                local ev = evs[k]
                out.events[#out.events + 1] = string.format("%s(%s)",
                    tostring(ev.LiteralName or ev.Name), DescribeFields(ev.Payload))
            end
        end
    end
    table.sort(out.functions)
    table.sort(out.events)
    table.sort(out.systems)
    local _, build, _, interface = GetBuildInfo()
    out.build = tostring(build)
    out.interface = interface
    self.db.global.apiDocumentation = out
    return out
end
