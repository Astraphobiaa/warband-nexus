--[[
    Warband Nexus - Upgrade track ilvl tables + crest currency map for the ACTIVE season.
    Split from GearService.lua (Lua 5.1 local limit).
    Loaded after Modules\Data\SeasonData.lua, before Modules\GearService.lua.

    Every table below is created once and refilled in place on a season change, because
    GearService / GearUI capture them as chunk-level locals at load time.
]]

local _, ns = ...

local TRACK_ILVLS = {}
local TRACK_ORDER = {}
-- Reverse map: ilvl -> { trackName, tier, maxTier } (higher tracks win overlaps).
local ILVL_TO_UPGRADE = {}
local TRACK_NAME_TO_CURRENCY_ID = {}
local UPGRADE_CURRENCY_ID_SET_EARLY = {}
local CURRENCY_ID_TO_TRACK = {}

ns.GearUpgradeTracks = {
    TRACK_ILVLS = TRACK_ILVLS,
    TRACK_ORDER = TRACK_ORDER,
    ILVL_TO_UPGRADE = ILVL_TO_UPGRADE,
    TRACK_NAME_TO_CURRENCY_ID = TRACK_NAME_TO_CURRENCY_ID,
    UPGRADE_CURRENCY_ID_SET_EARLY = UPGRADE_CURRENCY_ID_SET_EARLY,
    CURRENCY_ID_TO_TRACK = CURRENCY_ID_TO_TRACK,
}
ns.TRACK_ILVLS = TRACK_ILVLS
ns.TRACK_ORDER = TRACK_ORDER
ns.TRACK_NAME_TO_CURRENCY_ID = TRACK_NAME_TO_CURRENCY_ID

local SeasonData = ns.SeasonData
assert(SeasonData, "GearService_UpgradeTracks: ns.SeasonData missing - check TOC order (Modules\\Data\\SeasonData.lua must load first)")

SeasonData:RegisterRebuild(function(season)
    table.wipe(TRACK_ILVLS)
    table.wipe(TRACK_ORDER)
    table.wipe(ILVL_TO_UPGRADE)
    table.wipe(TRACK_NAME_TO_CURRENCY_ID)
    table.wipe(UPGRADE_CURRENCY_ID_SET_EARLY)
    table.wipe(CURRENCY_ID_TO_TRACK)

    -- Track order is the canonical low -> high list, filtered to tracks this season defines.
    local canonical = SeasonData.TRACK_ORDER
    for i = 1, #canonical do
        local trackName = canonical[i]
        local tiers = season.trackIlvls[trackName]
        if tiers then
            TRACK_ORDER[#TRACK_ORDER + 1] = trackName
            TRACK_ILVLS[trackName] = tiers
        end
    end

    -- Low -> high so a higher track overwrites the shared ilvls in the overlap region.
    for i = 1, #TRACK_ORDER do
        local trackName = TRACK_ORDER[i]
        local tiers = TRACK_ILVLS[trackName]
        for tier = 1, #tiers do
            ILVL_TO_UPGRADE[tiers[tier]] = { trackName, tier, #tiers }
        end
    end

    for trackName, currencyID in pairs(season.crestIDs) do
        TRACK_NAME_TO_CURRENCY_ID[trackName] = currencyID
        UPGRADE_CURRENCY_ID_SET_EARLY[currencyID] = true
        CURRENCY_ID_TO_TRACK[currencyID] = trackName
    end

    -- Flat cost per upgrade level: N crests + gold.
    ns.UPGRADE_CREST_PER_LEVEL = season.crestPerLevel or 20
    ns.UPGRADE_GOLD_PER_LEVEL_COPPER = season.goldPerLevelCopper or (10 * 10000)
end)
