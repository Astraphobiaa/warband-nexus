--[[
    Warband Nexus - Midnight upgrade track ilvl tables + Dawncrest currency map.
    Split from GearService.lua (Lua 5.1 local limit).
    Loaded before Modules/GearService.lua.
]]

local _, ns = ...
-- Midnight Season 1: complete ilvl progression per upgrade track (tier 1-6).
-- Each track has 6 tiers. Adjacent tracks overlap by 2 tiers.
-- Increment pattern per track: +4, +3, +3, +3, +4
local TRACK_ILVLS = {
    Adventurer = { 220, 224, 227, 230, 233, 237 },
    Veteran    = { 233, 237, 240, 243, 246, 250 },
    Champion   = { 246, 250, 253, 256, 259, 263 },
    Hero       = { 259, 263, 266, 269, 272, 276 },
    Myth       = { 272, 276, 279, 282, 285, 289 },
}
local TRACK_ORDER = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- Reverse map: ilvl -> { trackName, tier, maxTier } (higher tracks win overlaps).
local ILVL_TO_UPGRADE = {}
for i = 1, #TRACK_ORDER do
    local trackName = TRACK_ORDER[i]
    local tiers = TRACK_ILVLS[trackName]
    for tier = 1, #tiers do
        ILVL_TO_UPGRADE[tiers[tier]] = { trackName, tier, #tiers }
    end
end

-- Flat cost per upgrade level: 20 Dawncrests + gold (Midnight Season 1)
ns.UPGRADE_CREST_PER_LEVEL = 20
ns.UPGRADE_GOLD_PER_LEVEL_COPPER = 10 * 10000

local TRACK_NAME_TO_CURRENCY_ID = {
    Adventurer = 3383,
    Veteran    = 3341,
    Champion   = 3343,
    Hero       = 3345,
    Myth       = 3347,
}

local UPGRADE_CURRENCY_ID_SET_EARLY = {}
local CURRENCY_ID_TO_TRACK = {}
for track, cid in pairs(TRACK_NAME_TO_CURRENCY_ID) do
    UPGRADE_CURRENCY_ID_SET_EARLY[cid] = true
    CURRENCY_ID_TO_TRACK[cid] = track
end

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