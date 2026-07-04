--[[
    Warband Nexus - PvP pipeline self-test (/wn pvp test).
    Probes API -> DB write -> GetSummary -> filter parity used by PvPUI Recent Matches.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local PvPService = ns.PvPService
local format = string.format

assert(WarbandNexus and PvPService, "PvPService_SelfTest: load PvPService.lua first")

local PASS = "|cff00ff00PASS|r"
local FAIL = "|cffff0000FAIL|r"
local WARN = "|cffff9900WARN|r"

local function probe(label, fn)
    local ok, err = pcall(fn)
    if ok then
        WarbandNexus:Print("[WN-PvP-Test] " .. PASS .. " " .. label)
        return true
    end
    WarbandNexus:Print("[WN-PvP-Test] " .. FAIL .. " " .. label .. " — " .. tostring(err))
    return false
end

function WarbandNexus:RunPvPSelfTest()
    local passed, failed = 0, 0
    local function tally(ok)
        if ok then passed = passed + 1 else failed = failed + 1 end
    end

    WarbandNexus:Print("|cff00ccff[WN-PvP-Test]|r API -> DB -> UI pipeline smoke test")

    tally(probe("PvPService table loaded", function()
        assert(PvPService.RATED_BRACKETS and #PvPService.RATED_BRACKETS >= 5)
    end))

    tally(probe("PVP_UPDATED message constant", function()
        assert(ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.PVP_UPDATED == "WN_PVP_UPDATED")
    end))

    tally(probe("RECENT_FILTER_DEFS parity (6 filters)", function()
        assert(PvPService.RECENT_FILTER_DEFS and #PvPService.RECENT_FILTER_DEFS == 6)
    end))

    local charKey
    tally(probe("Resolve character storage key", function()
        local U = ns.Utilities
        assert(U and U.GetCharacterStorageKey)
        local ok, key = pcall(U.GetCharacterStorageKey, U, WarbandNexus)
        assert(ok and key and not (issecretvalue and issecretvalue(key)))
        charKey = key
    end))

    tally(probe("GetSummary returns progress + matches tables", function()
        assert(charKey)
        local progress, matches = PvPService:GetSummary(charKey)
        assert(type(progress) == "table" or progress == nil)
        assert(type(matches) == "table" or matches == nil)
        if matches then
            assert(type(matches.recent) == "table")
            assert(type(matches.session) == "table")
            assert(type(matches.lifetime) == "table")
        end
    end))

    tally(probe("GetPersonalRatedInfo API (bracket 1)", function()
        assert(GetPersonalRatedInfo)
        local ok = pcall(GetPersonalRatedInfo, 1)
        assert(ok)
    end))

    tally(probe("SnapshotRatedInfo writes DB (skipEmit)", function()
        assert(charKey)
        PvPService:SnapshotRatedInfo(true)
        local progress = PvPService:GetSummary(charKey)
        assert(progress and progress.brackets)
    end))

    tally(probe("GetWarbandOverview returns roster rows", function()
        local rows, seasonNumber = PvPService:GetWarbandOverview()
        assert(type(rows) == "table")
        assert(seasonNumber == nil or type(seasonNumber) == "number")
        for i = 1, #rows do
            local r = rows[i]
            assert(type(r.charKey) == "string")
            assert(r.bestRating == nil or type(r.bestRating) == "number")
        end
    end))

    tally(probe("GetActiveBrawl no-throw (nil or sanitized table)", function()
        local brawl = PvPService:GetActiveBrawl()
        assert(brawl == nil or (type(brawl) == "table" and type(brawl.name) == "string"))
    end))

    tally(probe("GetTierLabel nil/0/bogus args", function()
        assert(PvPService:GetTierLabel(nil) == nil)
        assert(PvPService:GetTierLabel(0) == nil)
        local label = PvPService:GetTierLabel(999999)
        assert(label == nil or type(label) == "string")
    end))

    tally(probe("InjectSelfTestMatch -> DB recent[1]", function()
        assert(charKey)
        PvPService:ClearSelfTestMatches(true)
        local beforeN = 0
        do
            local _, before = PvPService:GetSummary(charKey)
            beforeN = (before and before.recent and #before.recent) or 0
        end
        local entry = PvPService:InjectSelfTestMatch({
            mode = "2v2",
            outcome = "win",
            ratingChange = 24,
            mapName = "WN Self-Test Arena",
        })
        assert(entry)
        local _, matches = PvPService:GetSummary(charKey)
        assert(matches and matches.recent and matches.recent[1])
        assert(matches.recent[1]._wnPvPSelfTest)
        assert(matches.recent[1].mode == "2v2")
        assert(#matches.recent == beforeN + 1)
    end))

    tally(probe("Injected match carries score block (tooltip data)", function()
        local _, matches = PvPService:GetSummary(charKey)
        local m = matches and matches.recent and matches.recent[1]
        assert(m and type(m.score) == "table")
        assert(type(m.score.killingBlows) == "number")
        assert(type(m.score.prematchMMR) == "number")
    end))

    tally(probe("FilterRecentMatches (2v2) includes injected row", function()
        local _, matches = PvPService:GetSummary(charKey)
        local filtered = PvPService:FilterRecentMatches(matches.recent, "2v2")
        assert(#filtered >= 1)
        assert(filtered[1]._wnPvPSelfTest)
    end))

    tally(probe("SumMatchScope session/lifetime bumped", function()
        local _, matches = PvPService:GetSummary(charKey)
        local sw, sp = PvPService:SumMatchScope(matches.session, "2v2")
        local lw, lp = PvPService:SumMatchScope(matches.lifetime, "2v2")
        assert(sp >= 1 and lp >= 1)
        assert(sw >= 1 and lw >= 1)
    end))

    tally(probe("ClearSelfTestMatches restores injected row", function()
        local n = PvPService:ClearSelfTestMatches(true)
        assert(n >= 1)
        local _, matches = PvPService:GetSummary(charKey)
        for i = 1, #(matches.recent or {}) do
            assert(not matches.recent[i]._wnPvPSelfTest)
        end
    end))

    tally(probe("OnMatchComplete nil winner (no throw)", function()
        PvPService:OnMatchComplete(nil, nil)
    end))

    tally(probe("ResetMatchStats session scope (no throw)", function()
        assert(charKey)
        PvPService:ResetMatchStats(charKey, "session")
    end))

    if not PvPService._initialized then
        WarbandNexus:Print("[WN-PvP-Test] " .. WARN .. " PvPService not initialized — live PVP_MATCH_COMPLETE hook inactive until login")
    end

    PvPService:ClearSelfTestMatches(false)

    WarbandNexus:Print(format("|cff00ccff[WN-PvP-Test]|r Done: %d passed, %d failed", passed, failed))
    if failed == 0 then
        WarbandNexus:Print("|cff00ccff[WN-PvP-Test]|r Run |cff00ccff/wn pvp status|r for live API/DB snapshot.")
    end
end
