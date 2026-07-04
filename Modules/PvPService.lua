--[[
    Warband Nexus - PvP Service
    Rated bracket snapshots, honor progress, and match history recording.
    Data → db.global.pvpProgress / db.global.pvpMatches → SendMessage(WN_PVP_UPDATED) → PvPUI.

    API notes (verified on warcraft.wiki.gg + Blizzard live FrameXML, 2026-07-03):
    - GetPersonalRatedInfo(bracketIndex) is a GLOBAL (15 returns in Midnight,
      mirroring PVPPersonalRatedInfo: rating, seasonBest, weeklyBest, seasonPlayed,
      seasonWon, weeklyPlayed, weeklyWon, lastWeeksBest, hasWonToday, tier, ranking,
      roundsSeasonPlayed, roundsSeasonWon, roundsWeeklyPlayed, roundsWeeklyWon).
      Brackets: 1=2v2, 2=3v3, 4=RBG, 7=Solo Shuffle, 9=Battleground Blitz.
    - RequestRatedInfo() asks the server for fresh rated stats and triggers
      PVP_RATED_STATS_UPDATE on reply (wiki: API_RequestRatedInfo).
    - PVP_MATCH_COMPLETE(winner, duration); scoreboard (C_PvP.GetScoreInfo*) is
      SecretInActivePvPMatch in 12.x — read it only at match completion and
      issecretvalue-guard every field regardless. PVPScoreInfo fields consumed:
      killingBlows, deaths, damageDone, healingDone, honorGained, ratingChange,
      prematchMMR, mmrChange, postmatchMMR, talentSpec (wiki: GetScoreInfoByPlayerGuid).
    - GetActiveMatchWinner()/GetBattlefieldArenaFaction() numeric mapping is not
      wiki-documented; outcome falls back to "unknown" when unresolvable.
    - Season number: GetCurrentArenaSeason() global (wiki verified; 0 = no season).
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

-- Secret-safe string: nil unless a plain, non-secret string.
local function SafeStr(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "string" then return v end
    return nil
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

local WEEK_SECONDS = 7 * 24 * 60 * 60

-- Epoch of the current weekly reset period's start (wiki: API_C_DateAndTime.GetSecondsUntilWeeklyReset).
-- nil when the API is unavailable (callers then skip staleness checks).
local function GetWeekStart()
    if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then return nil end
    local ok, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    secs = ok and SafeNum(secs) or nil
    if not secs or secs <= 0 or secs > WEEK_SECONDS then return nil end
    return time() + secs - WEEK_SECONDS
end

---True when a store's rated snapshot predates the current weekly reset:
---its weekly W/P values belong to a previous week and must display as 0.
function PvPService:IsRatedWeeklyStale(store)
    if type(store) ~= "table" then return false end
    local weekStart = GetWeekStart()
    if not weekStart then return false end
    local ts = SafeNum(store.ratedUpdated) or SafeNum(store.lastUpdated)
    if not ts then return false end
    return ts < weekStart
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
                weeklyPlayed, weeklyWon, _lastWeeksBest, _hasWonToday, tier, _ranking,
                roundsSeasonPlayed, roundsSeasonWon, roundsWeeklyPlayed, roundsWeeklyWon
                = pcall(GetPersonalRatedInfo, b.index)
            if ok then
                local row = store.brackets[b.key] or {}
                row.rating = SafeNum(rating) or row.rating or 0
                row.seasonBest = SafeNum(seasonBest) or row.seasonBest or 0
                row.weeklyBest = SafeNum(weeklyBest) or row.weeklyBest or 0
                row.seasonPlayed = SafeNum(seasonPlayed) or row.seasonPlayed or 0
                row.seasonWon = SafeNum(seasonWon) or row.seasonWon or 0
                row.weeklyPlayed = SafeNum(weeklyPlayed) or row.weeklyPlayed or 0
                row.weeklyWon = SafeNum(weeklyWon) or row.weeklyWon or 0
                -- Midnight extras (nil-safe on older return shapes)
                row.tier = SafeNum(tier) or row.tier
                row.roundsSeasonPlayed = SafeNum(roundsSeasonPlayed) or row.roundsSeasonPlayed
                row.roundsSeasonWon = SafeNum(roundsSeasonWon) or row.roundsSeasonWon
                row.roundsWeeklyPlayed = SafeNum(roundsWeeklyPlayed) or row.roundsWeeklyPlayed
                row.roundsWeeklyWon = SafeNum(roundsWeeklyWon) or row.roundsWeeklyWon
                store.brackets[b.key] = row
                changed = true
            end
        end
    end
    -- Season number (GetCurrentArenaSeason: 0 = no active season)
    if GetCurrentArenaSeason then
        local okS, season = pcall(GetCurrentArenaSeason)
        if okS then
            local n = SafeNum(season)
            if n and n > 0 then
                store.seasonNumber = n
                changed = true
            end
        end
    end
    if changed then
        store.lastUpdated = time()
        store.ratedUpdated = time() -- weekly-reset staleness stamp (IsRatedWeeklyStale)
        if not skipEmit then EmitUpdated() end
    end
end

-- Ask the server for fresh rated stats; reply lands as PVP_RATED_STATS_UPDATE.
function PvPService:RequestRatedRefresh()
    if RequestRatedInfo then
        pcall(RequestRatedInfo)
    end
end

-- Active brawl for the logged-in character (wiki: C_PvP.GetActiveBrawlInfo, 8.1.5+).
-- Live read, no persist; nil when no brawl or when it cannot be queued.
function PvPService:GetActiveBrawl()
    if not (C_PvP and C_PvP.GetActiveBrawlInfo) then return nil end
    local ok, info = pcall(C_PvP.GetActiveBrawlInfo)
    if not ok or type(info) ~= "table" then return nil end
    if not SafeBool(info.canQueue) then return nil end
    local name = SafeStr(info.name)
    if not name then return nil end
    return {
        name = name,
        shortDescription = SafeStr(info.shortDescription),
        timeLeft = SafeNum(info.timeLeftUntilNextChange),
    }
end

-- Tier name for a bracket's tierID (wiki: C_PvP.GetPvpTierInfo -> PvpTierInfo.name).
-- Cached per session; returns nil when unresolvable.
local tierNameCache = {}
function PvPService:GetTierLabel(tierID)
    tierID = SafeNum(tierID)
    if not tierID or tierID <= 0 then return nil end
    if tierNameCache[tierID] ~= nil then
        return tierNameCache[tierID] or nil
    end
    local label
    if C_PvP and C_PvP.GetPvpTierInfo then
        local ok, info = pcall(C_PvP.GetPvpTierInfo, tierID)
        if ok and type(info) == "table" then
            label = SafeStr(info.name)
        end
    end
    tierNameCache[tierID] = label or false
    return label
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

    -- Guard: a completely unresolvable match outside a PvP instance is noise
    -- (self-test probes, spurious events in the open world) — do not record a "?" row.
    if modeKey == "unknown" and IsInInstance then
        local okI, _, instType = pcall(IsInInstance)
        local t = (okI and type(instType) == "string"
            and not (issecretvalue and issecretvalue(instType))) and instType or nil
        if t ~= "pvp" and t ~= "arena" then
            return
        end
    end

    local myTeam = GetOwnTeamIndex()

    local outcome = "unknown"
    if winner == 255 then
        outcome = "draw"
    elseif winner ~= nil and myTeam ~= nil then
        outcome = (winner == myTeam) and "win" or "loss"
    end

    -- Own scoreboard row: safe only at match completion (SecretInActivePvPMatch).
    local ratingChange, score
    local row = ReadOwnScoreRow()
    if row then
        ratingChange = SafeNum(row.ratingChange)
        score = {
            killingBlows = SafeNum(row.killingBlows),
            deaths = SafeNum(row.deaths),
            damageDone = SafeNum(row.damageDone),
            healingDone = SafeNum(row.healingDone),
            honorGained = SafeNum(row.honorGained),
            prematchMMR = SafeNum(row.prematchMMR),
            mmrChange = SafeNum(row.mmrChange),
            postmatchMMR = SafeNum(row.postmatchMMR),
            talentSpec = SafeStr(row.talentSpec),
        }
        local hasAny = false
        for _ in pairs(score) do hasAny = true break end
        if not hasAny then score = nil end
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
        score = score,
    })
    for i = #matches.recent, RECENT_MATCH_CAP + 1, -1 do
        table.remove(matches.recent, i)
    end

    EmitUpdated()

    -- Ask the server for fresh rated numbers; PVP_RATED_STATS_UPDATE listener
    -- snapshots on reply. Blind 2s timer stays as fallback for missed replies.
    self:RequestRatedRefresh()
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

-- Canonical pvpProgress key for a roster character row (GUID-first; mirrors
-- PvEUI.GetCanonicalKeyForChar so DB lookups match service writes).
local function ResolveRosterCharKey(char)
    if type(char) ~= "table" then return nil end
    local U = ns.Utilities
    if U and U.ResolveCharacterRowKey then
        local ok, rk = pcall(U.ResolveCharacterRowKey, U, char)
        if ok and type(rk) == "string" and not (issecretvalue and issecretvalue(rk)) then
            if U.GetCanonicalCharacterKey then
                local ok2, ck = pcall(U.GetCanonicalCharacterKey, U, rk)
                if ok2 and type(ck) == "string" then return ck end
            end
            return rk
        end
    end
    local raw = char._key
    if type(raw) == "string" and not (issecretvalue and issecretvalue(raw)) then
        if U and U.GetCanonicalCharacterKey then
            local ok2, ck = pcall(U.GetCanonicalCharacterKey, U, raw)
            if ok2 and type(ck) == "string" then return ck end
        end
        return raw
    end
    return nil
end

---Aggregated PvP view over all tracked characters (Warband roster card).
---Returns array of rows sorted by best rating desc, plus season number (or nil).
---Row: { charKey, name, realm, class, classFile, level, isCurrent,
---       honorLevel, brackets, lastUpdated }
function PvPService:GetWarbandOverview()
    local rows = {}
    local db = WarbandNexus and WarbandNexus.db
    if not db or not db.global then return rows, nil end
    local progress = db.global.pvpProgress or {}
    local characters = (WarbandNexus.GetAllCharacters and WarbandNexus:GetAllCharacters()) or {}
    local currentKey = GetCharKey()
    local seasonNumber
    local seen = {} -- legacy Name-Realm + GUID roster rows can canonicalize to the same key

    for i = 1, #characters do
        local char = characters[i]
        local charKey = ResolveRosterCharKey(char)
        local store = charKey and progress[charKey] or nil
        if charKey and not seen[charKey] then
            seen[charKey] = true
            local honor = store and store.honor or nil
            local brackets = store and store.brackets or nil
            if store and SafeNum(store.seasonNumber) then
                local sn = SafeNum(store.seasonNumber)
                if not seasonNumber or sn > seasonNumber then seasonNumber = sn end
            end
            -- Best rating across brackets (roster sort + gold highlight in UI)
            local bestRating = 0
            if brackets then
                for _, b in pairs(brackets) do
                    local r = SafeNum(b.rating) or 0
                    if r > bestRating then bestRating = r end
                end
            end
            rows[#rows + 1] = {
                charKey = charKey,
                name = char.name,
                realm = char.realm,
                class = char.class,
                classFile = char.classFile,
                level = char.level,
                isCurrent = (charKey == currentKey),
                honorLevel = honor and SafeNum(honor.level) or nil,
                brackets = brackets,
                bestRating = bestRating,
                lastUpdated = store and store.lastUpdated or nil,
                -- Snapshot taken before this week's reset: weekly W/P shows 0 in UI
                weeklyStale = self:IsRatedWeeklyStale(store),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.bestRating ~= b.bestRating then return a.bestRating > b.bestRating end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return rows, seasonNumber
end

-- RECENT MATCH FILTERS (shared with PvPUI + self-test; labels stay in UI/locale)
local RECENT_FILTER_DEFS = {
    { key = "all", matches = function() return true end },
    { key = "shuffle", matches = function(m) return m.mode == "shuffle" end },
    { key = "blitz", matches = function(m) return m.mode == "blitz" end },
    { key = "2v2", matches = function(m) return m.mode == "2v2" end },
    { key = "3v3", matches = function(m) return m.mode == "3v3" end },
    { key = "bg", matches = function(m) return m.mode == "bg" or m.mode == "rbg" end },
}
PvPService.RECENT_FILTER_DEFS = RECENT_FILTER_DEFS

function PvPService:GetRecentFilterDef(filterKey)
    for i = 1, #RECENT_FILTER_DEFS do
        local def = RECENT_FILTER_DEFS[i]
        if def.key == filterKey then return def end
    end
    return RECENT_FILTER_DEFS[1]
end

function PvPService:FilterRecentMatches(recent, filterKey)
    recent = recent or {}
    local def = self:GetRecentFilterDef(filterKey)
    local out = {}
    for i = 1, #recent do
        local m = recent[i]
        if m and def.matches(m) then
            out[#out + 1] = m
        end
    end
    return out
end

function PvPService:SumMatchScope(bucket, filterKey)
    local played, won = 0, 0
    if not bucket then return won, played end
    local def = self:GetRecentFilterDef(filterKey)
    for modeKey, agg in pairs(bucket) do
        local probe = { mode = modeKey }
        if def.matches(probe) or filterKey == "all" then
            played = played + (agg.played or 0)
            won = won + (agg.won or 0)
        end
    end
    return won, played
end

local SELF_TEST_MATCH_TAG = "_wnPvPSelfTest"

---Insert a tagged synthetic recent match (self-test / QA only).
function PvPService:InjectSelfTestMatch(opts)
    opts = opts or {}
    local charKey = GetCharKey()
    if not charKey then return nil, "no_char_key" end
    local matches = GetMatchStore(charKey)
    if not matches then return nil, "no_match_store" end

    local modeKey = opts.mode or "2v2"
    local outcome = opts.outcome or "win"
    local won = (outcome == "win")
    local entry = {
        mode = modeKey,
        rated = opts.rated,
        outcome = outcome,
        duration = opts.duration or 615,
        ratingChange = opts.ratingChange or 12,
        mapName = opts.mapName or "WN Self-Test Arena",
        endedAt = opts.endedAt or time(),
        -- Synthetic scoreboard block so the Recent Matches hover tooltip is testable
        score = opts.score or {
            killingBlows = 4,
            deaths = 1,
            damageDone = 12345678,
            healingDone = 2345678,
            honorGained = 250,
            prematchMMR = 1900,
            mmrChange = 18,
            postmatchMMR = 1918,
        },
        [SELF_TEST_MATCH_TAG] = true,
    }
    BumpAggregate(matches.lifetime, modeKey, won)
    BumpAggregate(matches.session, modeKey, won)
    table.insert(matches.recent, 1, entry)
    for i = #matches.recent, RECENT_MATCH_CAP + 1, -1 do
        table.remove(matches.recent, i)
    end
    EmitUpdated()
    return entry
end

---Remove self-test rows and roll back their session/lifetime aggregate bumps.
function PvPService:ClearSelfTestMatches(skipEmit)
    local charKey = GetCharKey()
    if not charKey then return 0 end
    local matches = GetMatchStore(charKey)
    if not matches then return 0 end

    local removed = 0
    for i = #matches.recent, 1, -1 do
        local m = matches.recent[i]
        if m and m[SELF_TEST_MATCH_TAG] then
            local won = (m.outcome == "win")
            local modeKey = m.mode or "unknown"
            local function dec(bucket)
                local agg = bucket[modeKey]
                if not agg then return end
                agg.played = math.max(0, (agg.played or 0) - 1)
                if won then agg.won = math.max(0, (agg.won or 0) - 1) end
                bucket[modeKey] = agg
            end
            dec(matches.lifetime)
            dec(matches.session)
            table.remove(matches.recent, i)
            removed = removed + 1
        end
    end
    if removed > 0 and not skipEmit then EmitUpdated() end
    return removed
end

---Chat diagnostics: API snapshot + DB rows for current character.
function PvPService:PrintDiagnostics(addon)
    addon = addon or WarbandNexus
    if not addon or not addon.Print then return end
    local charKey = GetCharKey()
    addon:Print("|cff00ccff[WN-PvP]|r Diagnostics (API -> DB -> UI read path)")
    if not charKey then
        addon:Print("  |cffff6600FAIL|r charKey unavailable (not logged in?)")
        return
    end
    addon:Print("  charKey: " .. tostring(charKey))

    if not self._initialized then
        addon:Print("  |cffff9900WARN|r PvPService not initialized yet")
    else
        addon:Print("  |cff00ff00OK|r PvPService initialized")
    end

    if GetPersonalRatedInfo then
        for i = 1, #RATED_BRACKETS do
            local b = RATED_BRACKETS[i]
            local ok, rating = pcall(GetPersonalRatedInfo, b.index)
            local apiRating = (ok and SafeNum(rating)) or "?"
            local progress = self:GetSummary(charKey)
            local dbRow = progress and progress.brackets and progress.brackets[b.key]
            local dbRating = dbRow and dbRow.rating or "?"
            addon:Print(string.format("  API/DB %s rating: %s / %s", b.key, tostring(apiRating), tostring(dbRating)))
        end
    end

    local _, matches = self:GetSummary(charKey)
    local recentN = (matches and matches.recent and #matches.recent) or 0
    addon:Print(string.format("  DB recent matches: %d", recentN))
    if recentN > 0 and matches.recent[1] then
        local m = matches.recent[1]
        addon:Print(string.format("  latest: %s %s %s %s",
            tostring(m.mode), tostring(m.outcome),
            ((m.ratingChange or 0) >= 0 and "+" or "") .. tostring(m.ratingChange or 0),
            tostring(m.mapName or "")))
    end

    for _, fk in ipairs({ "all", "2v2", "shuffle" }) do
        local sw, sp = self:SumMatchScope(matches and matches.session, fk)
        local lw, lp = self:SumMatchScope(matches and matches.lifetime, fk)
        local filtN = #self:FilterRecentMatches(matches and matches.recent, fk)
        addon:Print(string.format("  filter %-7s UI rows:%2d  session:%d/%d  lifetime:%d/%d",
            fk, filtN, sw, sp, lw, lp))
    end

    local rosterRows, seasonNumber = self:GetWarbandOverview()
    addon:Print(string.format("  warband roster rows: %d  season: %s",
        #rosterRows, tostring(seasonNumber or "?")))
    local brawl = self:GetActiveBrawl()
    if brawl then
        addon:Print(string.format("  active brawl: %s (%ss left)",
            tostring(brawl.name), tostring(brawl.timeLeft or "?")))
    else
        addon:Print("  active brawl: none / not queueable")
    end
end

-- INIT / EVENTS (registered at PLAYER_LOGIN; db is ready by then)

local sessionStarted = false

-- One-time hygiene: older builds recorded "?" rows (mode/outcome unknown, e.g.
-- from self-test probes outside PvP) into recent + lifetime aggregates.
local function PurgeUnknownMatchNoise(matches)
    if not matches or matches._unknownPurgedV1 then return end
    matches._unknownPurgedV1 = true
    for i = #matches.recent, 1, -1 do
        local m = matches.recent[i]
        if type(m) == "table" and m.mode == "unknown" and (m.outcome == "unknown" or m.outcome == nil) then
            table.remove(matches.recent, i)
        end
    end
    matches.lifetime.unknown = nil
    matches.session.unknown = nil
end

local function OnLogin()
    local charKey = GetCharKey()
    if charKey and not sessionStarted then
        sessionStarted = true
        local matches = GetMatchStore(charKey)
        if matches then
            -- "Session" is per login session.
            wipe(matches.session)
            PurgeUnknownMatchNoise(matches)
        end
    end
    -- Ask the server for rated stats; PVP_RATED_STATS_UPDATE snapshots on reply.
    PvPService:RequestRatedRefresh()
    -- Seed snapshots shortly after login as fallback; rated info needs warm server data.
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
    -- Server replies to RequestRatedInfo() land here (wiki: API_RequestRatedInfo).
    WarbandNexus.RegisterEvent(PvPEvents, "PVP_RATED_STATS_UPDATE", function()
        PvPService:SnapshotRatedInfo()
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
