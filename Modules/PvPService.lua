--[[
    Warband Nexus - PvP Service
    Rated bracket snapshots, honor progress, and match history recording.
    Data → db.global.pvpProgress / db.global.pvpMatches → SendMessage(WN_PVP_UPDATED) → PvPUI.

    API notes (verified on warcraft.wiki.gg + Blizzard live FrameXML, 2026-07-03):
    - GetPersonalRatedInfo(bracketIndex) is a GLOBAL (15 returns in Midnight).
      Brackets: 1=2v2, 2=3v3, 4=RBG, 7=Solo Shuffle, 9=Battleground Blitz.
    - PVP_MATCH_COMPLETE(winner, duration); scoreboard (C_PvP.GetScoreInfo*) is
      SecretInActivePvPMatch in 12.x — read it only at match completion and
      issecretvalue-guard every field regardless.
    - GetActiveMatchWinner()/GetBattlefieldArenaFaction() numeric mapping is not
      wiki-documented; outcome falls back to "unknown" when unresolvable.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local PvPService = {}
ns.PvPService = PvPService

local PvPEvents = {} -- AceEvent listener object (thin; never touches UI)

local RATED_BRACKETS = {
    { index = 1, key = "2v2" },
    { index = 2, key = "3v3" },
    { index = 4, key = "rbg" },
    { index = 7, key = "shuffle" },
    { index = 9, key = "blitz" },
}
PvPService.RATED_BRACKETS = RATED_BRACKETS

local RECENT_MATCH_CAP = 30

-- Secret-safe number: nil unless a plain, non-secret number(-like) value.
local function SafeNum(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
end

local function SafeBool(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v and true or false
end

local function GetCharKey()
    local U = ns.Utilities
    if U and U.GetCharacterStorageKey then
        local ok, key = pcall(U.GetCharacterStorageKey, U, WarbandNexus)
        if ok and key then return key end
    end
    return nil
end

local function GetProgressStore(charKey)
    local db = WarbandNexus and WarbandNexus.db
    if not db or not db.global then return nil end
    db.global.pvpProgress = db.global.pvpProgress or {}
    local store = db.global.pvpProgress[charKey]
    if not store then
        store = { brackets = {}, honor = {} }
        db.global.pvpProgress[charKey] = store
    end
    store.brackets = store.brackets or {}
    store.honor = store.honor or {}
    return store
end

local function GetMatchStore(charKey)
    local db = WarbandNexus and WarbandNexus.db
    if not db or not db.global then return nil end
    db.global.pvpMatches = db.global.pvpMatches or {}
    local store = db.global.pvpMatches[charKey]
    if not store then
        store = { lifetime = {}, session = {}, recent = {} }
        db.global.pvpMatches[charKey] = store
    end
    store.lifetime = store.lifetime or {}
    store.session = store.session or {}
    store.recent = store.recent or {}
    return store
end

local function EmitUpdated()
    if WarbandNexus and WarbandNexus.SendMessage and ns.Constants and ns.Constants.EVENTS then
        WarbandNexus:SendMessage(ns.Constants.EVENTS.PVP_UPDATED)
    end
end

-- SNAPSHOTS (rated brackets + honor) — persist, then emit.

function PvPService:SnapshotRatedInfo(skipEmit)
    local charKey = GetCharKey()
    if not charKey then return end
    local store = GetProgressStore(charKey)
    if not store then return end

    local changed = false
    for i = 1, #RATED_BRACKETS do
        local b = RATED_BRACKETS[i]
        if GetPersonalRatedInfo then
            local ok, rating, seasonBest, weeklyBest, seasonPlayed, seasonWon,
                weeklyPlayed, weeklyWon = pcall(GetPersonalRatedInfo, b.index)
            if ok then
                local row = store.brackets[b.key] or {}
                row.rating = SafeNum(rating) or row.rating or 0
                row.seasonBest = SafeNum(seasonBest) or row.seasonBest or 0
                row.weeklyBest = SafeNum(weeklyBest) or row.weeklyBest or 0
                row.seasonPlayed = SafeNum(seasonPlayed) or row.seasonPlayed or 0
                row.seasonWon = SafeNum(seasonWon) or row.seasonWon or 0
                row.weeklyPlayed = SafeNum(weeklyPlayed) or row.weeklyPlayed or 0
                row.weeklyWon = SafeNum(weeklyWon) or row.weeklyWon or 0
                store.brackets[b.key] = row
                changed = true
            end
        end
    end
    if changed then
        store.lastUpdated = time()
        if not skipEmit then EmitUpdated() end
    end
end

function PvPService:SnapshotHonor(skipEmit)
    local charKey = GetCharKey()
    if not charKey then return end
    local store = GetProgressStore(charKey)
    if not store then return end

    local okLvl, lvl = pcall(UnitHonorLevel, "player")
    local okCur, cur = pcall(UnitHonor, "player")
    local okMax, mx = pcall(UnitHonorMax, "player")
    store.honor.level = (okLvl and SafeNum(lvl)) or store.honor.level or 0
    store.honor.current = (okCur and SafeNum(cur)) or store.honor.current or 0
    store.honor.max = (okMax and SafeNum(mx)) or store.honor.max or 0
    store.lastUpdated = time()
    if not skipEmit then EmitUpdated() end
end

-- MATCH RECORDING

-- Resolve the mode of the active/completed match to a stable mode key.
local function ResolveMatchMode()
    local function ask(fnName)
        local fn = C_PvP and C_PvP[fnName]
        if not fn then return nil end
        local ok, v = pcall(fn)
        if not ok then return nil end
        return SafeBool(v)
    end
    if ask("IsRatedSoloShuffle") then return "shuffle", true end
    if ask("IsRatedSoloRBG") then return "blitz", true end
    if ask("IsRatedArena") then
        local bracket
        if C_PvP and C_PvP.GetActiveMatchBracket then
            local ok, v = pcall(C_PvP.GetActiveMatchBracket)
            if ok then bracket = SafeNum(v) end
        end
        if bracket == 2 then return "3v3", true end
        return "2v2", true
    end
    if ask("IsRatedBattleground") then return "rbg", true end
    if ask("IsSoloShuffle") then return "shuffle", false end
    if ask("IsArena") then return "arena", false end
    if ask("IsBattleground") then return "bg", false end
    return "unknown", false
end

-- Player team index for winner comparison. Mapping is not wiki-documented;
-- returns nil when unavailable so the outcome degrades to "unknown".
local function GetOwnTeamIndex()
    if GetBattlefieldArenaFaction then
        local ok, v = pcall(GetBattlefieldArenaFaction)
        if ok then return SafeNum(v) end
    end
    return nil
end

local function ReadOwnScoreRow()
    if not (C_PvP and C_PvP.GetScoreInfoByPlayerGuid and UnitGUID) then return nil end
    local okG, guid = pcall(UnitGUID, "player")
    if not okG or not guid then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    local okS, row = pcall(C_PvP.GetScoreInfoByPlayerGuid, guid)
    if not okS or type(row) ~= "table" then return nil end
    return row
end

local function BumpAggregate(bucket, modeKey, won)
    local agg = bucket[modeKey] or { played = 0, won = 0 }
    agg.played = (agg.played or 0) + 1
    if won then agg.won = (agg.won or 0) + 1 end
    bucket[modeKey] = agg
end

function PvPService:OnMatchComplete(winner, duration)
    local charKey = GetCharKey()
    if not charKey then return end
    local matches = GetMatchStore(charKey)
    if not matches then return end

    winner = SafeNum(winner)
    duration = SafeNum(duration)

    local modeKey, isRated = ResolveMatchMode()
    local myTeam = GetOwnTeamIndex()

    local outcome = "unknown"
    if winner == 255 then
        outcome = "draw"
    elseif winner ~= nil and myTeam ~= nil then
        outcome = (winner == myTeam) and "win" or "loss"
    end

    local ratingChange
    local row = ReadOwnScoreRow()
    if row then
        ratingChange = SafeNum(row.ratingChange)
    end

    local mapName
    if GetInstanceInfo then
        local okI, name = pcall(GetInstanceInfo)
        if okI and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
            mapName = name
        end
    end

    local won = (outcome == "win")
    BumpAggregate(matches.lifetime, modeKey, won)
    BumpAggregate(matches.session, modeKey, won)

    table.insert(matches.recent, 1, {
        mode = modeKey,
        rated = isRated or nil,
        outcome = outcome,
        duration = duration,
        ratingChange = ratingChange,
        mapName = mapName,
        endedAt = time(),
    })
    for i = #matches.recent, RECENT_MATCH_CAP + 1, -1 do
        table.remove(matches.recent, i)
    end

    EmitUpdated()

    -- Rated numbers can lag the completion event by a few frames; re-snapshot
    -- shortly after so the bracket table reflects the new rating.
    C_Timer.After(2, function()
        PvPService:SnapshotRatedInfo()
    end)
end

-- RESET / READ API (UI + external callers go through these; UI never writes db)

---Reset match statistics for a character. scope: "session" | "lifetime" | "all"
function PvPService:ResetMatchStats(charKey, scope)
    charKey = charKey or GetCharKey()
    if not charKey then return end
    local matches = GetMatchStore(charKey)
    if not matches then return end
    scope = scope or "all"
    if scope == "session" or scope == "all" then
        wipe(matches.session)
    end
    if scope == "lifetime" or scope == "all" then
        wipe(matches.lifetime)
        wipe(matches.recent)
        matches.resetAt = time()
    end
    EmitUpdated()
end

local HONOR_CURRENCY_ID = 1792
local CONQUEST_CURRENCY_ID = 1602

local function ReadCurrencyCaps(currencyID)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or type(info) ~= "table" then return nil end
    return {
        quantity = SafeNum(info.quantity) or 0,
        maxQuantity = SafeNum(info.maxQuantity) or 0,
        totalEarned = SafeNum(info.totalEarned) or 0,
        weeklyEarned = SafeNum(info.quantityEarnedThisWeek) or 0,
        weeklyMax = SafeNum(info.maxWeeklyQuantity) or 0,
        canEarnPerWeek = SafeBool(info.canEarnPerWeek) or false,
        -- Seasonal moving cap (Conquest): remaining = maxQuantity - totalEarned.
        useTotalEarnedForMaxQty = SafeBool(info.useTotalEarnedForMaxQty) or false,
    }
end

---Live Honor/Conquest quantities with weekly + seasonal cap fields (UI display).
---@return table|nil honor, table|nil conquest
function PvPService:GetCurrencyOverview()
    return ReadCurrencyCaps(HONOR_CURRENCY_ID), ReadCurrencyCaps(CONQUEST_CURRENCY_ID)
end

---Read-only snapshot for UI consumption.
function PvPService:GetSummary(charKey)
    charKey = charKey or GetCharKey()
    if not charKey then return nil end
    local db = WarbandNexus and WarbandNexus.db
    if not db or not db.global then return nil end
    return (db.global.pvpProgress or {})[charKey], (db.global.pvpMatches or {})[charKey]
end

-- INIT / EVENTS (registered at PLAYER_LOGIN; db is ready by then)

local sessionStarted = false

local function OnLogin()
    local charKey = GetCharKey()
    if charKey and not sessionStarted then
        sessionStarted = true
        local matches = GetMatchStore(charKey)
        if matches then
            -- "Session" is per login session.
            wipe(matches.session)
        end
    end
    -- Seed snapshots shortly after login; rated info needs the server data warm.
    C_Timer.After(5, function()
        PvPService:SnapshotRatedInfo(true)
        PvPService:SnapshotHonor(false)
    end)
end

function PvPService:Initialize()
    if self._initialized then return end
    if not (WarbandNexus and WarbandNexus.RegisterEvent) then return end
    self._initialized = true

    WarbandNexus.RegisterEvent(PvPEvents, "PVP_MATCH_COMPLETE", function(_, winner, duration)
        PvPService:OnMatchComplete(winner, duration)
    end)
    WarbandNexus.RegisterEvent(PvPEvents, "PVP_MATCH_ACTIVE", function()
        -- Pre-match snapshot so post-match deltas have a baseline.
        PvPService:SnapshotRatedInfo(true)
    end)
    WarbandNexus.RegisterEvent(PvPEvents, "HONOR_XP_UPDATE", function()
        PvPService:SnapshotHonor()
    end)
    WarbandNexus.RegisterEvent(PvPEvents, "HONOR_LEVEL_UPDATE", function()
        PvPService:SnapshotHonor()
    end)

    OnLogin()
end

-- Defer init to PLAYER_LOGIN so AceDB defaults exist. WarbandNexus (Core.lua)
-- loads before Modules per TOC, so AceEvent is available at file load.
if WarbandNexus and WarbandNexus.RegisterEvent then
    WarbandNexus.RegisterEvent(PvPEvents, "PLAYER_LOGIN", function()
        WarbandNexus.UnregisterEvent(PvPEvents, "PLAYER_LOGIN")
        PvPService:Initialize()
    end)
    if IsLoggedIn and IsLoggedIn() then
        WarbandNexus.UnregisterEvent(PvPEvents, "PLAYER_LOGIN")
        PvPService:Initialize()
    end
end
