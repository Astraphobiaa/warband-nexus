--[[
    Warband Nexus - Unobtainable Filters Module
    
    Centralized filter system to exclude genuinely unobtainable items from Plans UI.
    Research-backed blocklists and keyword detection for mounts, pets, toys, etc.
    
    Categories of Unobtainable Items:
    1. PvP Season Rewards (past Gladiator/Elite mounts)
    2. TCG Items (Trading Card Game discontinued 2013)
    3. Promotions (time-limited BlizzCon, Collector's Edition)
    4. Challenge Mode (MoP/WoD/Legion - currency removed)
    5. Retired Events (AQ Opening 2006, special one-time events)
    6. Unknown Source (no valid source information)
]]

local addonName, ns = ...
local WarbandNexus = LibStub("AceAddon-3.0"):GetAddon(addonName)

local UnobtainableFilters = {}
WarbandNexus.UnobtainableFilters = UnobtainableFilters

-- ============================================================================
-- MOUNT BLOCKLISTS (Research-Based)
-- ============================================================================

--[[
    Arena Season Mounts - All past PvP season rewards
    These were limited-time rewards for top-ranking arena players
    Source: WoWHead, WarcraftWiki, WarcraftMounts.com
]]
local ARENA_MOUNT_NAMES = {
    -- TBC Arena Seasons (Nether Drakes)
    ["Swift Nether Drake"] = true,           -- Season 1
    ["Merciless Nether Drake"] = true,       -- Season 2
    ["Vengeful Nether Drake"] = true,        -- Season 3
    ["Brutal Nether Drake"] = true,          -- Season 4
    
    -- WotLK Arena Seasons (Frost Wyrms)
    ["Deadly Gladiator's Frost Wyrm"] = true,    -- Season 5
    ["Furious Gladiator's Frost Wyrm"] = true,   -- Season 6
    ["Relentless Gladiator's Frost Wyrm"] = true,-- Season 7
    ["Wrathful Gladiator's Frost Wyrm"] = true,  -- Season 8
    
    -- Cataclysm Arena Seasons (Drakes)
    ["Vicious Gladiator's Twilight Drake"] = true,  -- Season 9
    ["Ruthless Gladiator's Twilight Drake"] = true, -- Season 10
    ["Cataclysmic Gladiator's Twilight Drake"] = true, -- Season 11
    
    -- MoP Arena Seasons (Cloud Serpents)
    ["Tyrannical Gladiator's Cloud Serpent"] = true,  -- Season 12
    ["Grievous Gladiator's Cloud Serpent"] = true,    -- Season 13
    ["Prideful Gladiator's Cloud Serpent"] = true,    -- Season 14
    
    -- WoD Arena Seasons (Wolves)
    ["Primal Gladiator's Felblood Gronnling"] = true, -- Season 15
    ["Wild Gladiator's Felblood Gronnling"] = true,   -- Season 16
    ["Warmongering Gladiator's Felblood Gronnling"] = true, -- Season 17
    
    -- Legion Arena Seasons (Storm Dragons)
    ["Vindictive Gladiator's Storm Dragon"] = true,  -- Season 18
    ["Fearless Gladiator's Storm Dragon"] = true,    -- Season 19
    ["Cruel Gladiator's Storm Dragon"] = true,       -- Season 20
    ["Ferocious Gladiator's Storm Dragon"] = true,   -- Season 21
    
    -- BFA Arena Seasons (Drakes)
    ["Dread Gladiator's Proto-Drake"] = true,       -- Season 22
    ["Sinister Gladiator's Proto-Drake"] = true,    -- Season 23
    ["Notorious Gladiator's Proto-Drake"] = true,   -- Season 24
    ["Corrupted Gladiator's Proto-Drake"] = true,   -- Season 25
    
    -- Shadowlands Arena Seasons (Soul Eaters)
    ["Sinful Gladiator's Soul Eater"] = true,       -- Season 26
    ["Unchained Gladiator's Soul Eater"] = true,    -- Season 27
    ["Cosmic Gladiator's Soul Eater"] = true,       -- Season 28
    ["Eternal Gladiator's Soul Eater"] = true,      -- Season 29
}

--[[
    Challenge Mode Mounts - Removed content
    Challenge Mode currencies are no longer obtainable
]]
local CHALLENGE_MODE_MOUNTS = {
    -- MoP Challenge Mode (Ancestral Phoenix Egg currency removed)
    ["Ashen Pandaren Phoenix"] = true,
    ["Crimson Pandaren Phoenix"] = true,
    ["Emerald Pandaren Phoenix"] = true,
    ["Violet Pandaren Phoenix"] = true,
    
    -- WoD Challenge Mode (Challenge Conqueror requirement removed)
    ["Ironside Warwolf"] = true,
    ["Challenger's War Yeti"] = true,
}

--[[
    Special Event Mounts - One-time events that will never return
]]
local EVENT_EXCLUSIVE_MOUNTS = {
    -- AQ Opening Event (January 2006 - one-time server event)
    ["Black Qiraji Battle Tank"] = true,
    ["Black Qiraji Resonating Crystal"] = true,
}

--[[
    Generic/Placeholder Mounts - Never properly implemented
]]
local PLACEHOLDER_MOUNTS = {
    ["Tiger"] = true,                              -- Generic placeholder
    ["White Stallion"] = true,                     -- Removed
    ["Palomino"] = true,                           -- Removed
    ["Fluorescent Green Mechanostrider"] = true,   -- Never implemented
    ["Unpainted Mechanostrider"] = true,           -- Never implemented
}

-- ============================================================================
-- SOURCE TEXT KEYWORD PATTERNS
-- ============================================================================

--[[
    Keywords that indicate unobtainable content when found in source text
    Checked case-insensitively
]]
local UNOBTAINABLE_SOURCE_KEYWORDS = {
    -- PvP Season Rewards
    "GLADIATOR",
    "ELITE",
    "SEASON %d",        -- "Season 1", "Season 2", etc.
    "ARENA SEASON",
    "RATED",
    
    -- TCG and Promotions
    "TCG",
    "TRADING CARD",
    "LOOT CARD",
    "BLIZZCON",
    "COLLECTOR'S EDITION",
    "COLLECTOR EDITION",
    "PROMOTION",
    "PROMOTIONAL",
    
    -- Challenge Mode
    "CHALLENGE MODE",
    "CHALLENGE CONQUEROR",
    "ANCESTRAL PHOENIX EGG",
    
    -- Explicit removal/retirement
    "NO LONGER OBTAINABLE",
    "NO LONGER AVAILABLE",
    "RETIRED",
    "REMOVED",
    "UNOBTAINABLE",
    "LEGACY",  -- Many mount sources are marked as "Legacy"
}

-- ============================================================================
-- API SOURCE TYPE ENUM VALUES
-- ============================================================================

--[[
    WoW API sourceType enum values from C_MountJournal.GetMountInfoByID()
    
    1 = Drop (boss drops, mob drops) - OBTAINABLE
    2 = Quest (quest rewards) - OBTAINABLE
    3 = Vendor (purchased from vendor) - OBTAINABLE
    4 = Profession (crafted) - OBTAINABLE
    5 = Instance (dungeon/raid specific) - OBTAINABLE
    6 = Promotion (BlizzCon, Collector's Edition) - NOT OBTAINABLE
    7 = Achievement (achievement rewards) - OBTAINABLE (mostly)
    8 = World Event (seasonal events) - OBTAINABLE
    9 = TCG (Trading Card Game) - NOT OBTAINABLE (discontinued)
    10 = Store (Blizzard Shop) - OBTAINABLE
]]
local UNOBTAINABLE_SOURCE_TYPES = {
    [6] = true,  -- Promotion (time-limited, mostly expired)
    [9] = true,  -- TCG (discontinued 2013)
}

-- ============================================================================
-- FILTER FUNCTIONS
-- ============================================================================

--[[
    Check if source text contains unobtainable keywords
    @param source string - Source text from item data
    @return boolean - True if source indicates unobtainable
]]
local function HasUnobtainableKeyword(source)
    if not source or source == "" then return false end
    
    local sourceUpper = source:upper()
    
    for _, keyword in ipairs(UNOBTAINABLE_SOURCE_KEYWORDS) do
        if sourceUpper:find(keyword) then
            return true
        end
    end
    
    return false
end

--[[
    Check if a mount is unobtainable
    @param data table - Mount data with fields: name, source, sourceType
    @return boolean - True if mount is unobtainable
]]
function UnobtainableFilters:IsUnobtainableMount(data)
    if not data then return true end
    
    -- Check: Name-based blocklists (most reliable)
    if ARENA_MOUNT_NAMES[data.name] then return true end
    if CHALLENGE_MODE_MOUNTS[data.name] then return true end
    if EVENT_EXCLUSIVE_MOUNTS[data.name] then return true end
    if PLACEHOLDER_MOUNTS[data.name] then return true end
    
    -- Check: SourceType enum (TCG, Promotion)
    if data.sourceType and UNOBTAINABLE_SOURCE_TYPES[data.sourceType] then
        return true
    end
    
    -- Check: Source text keywords (Gladiator, Arena, Season, TCG, etc.)
    if data.source and HasUnobtainableKeyword(data.source) then
        return true
    end
    
    -- NOTE: We DON'T filter by "Unknown" source because many obtainable mounts
    -- have missing source text in the API (vendor mounts, legacy content, etc.)
    
    return false
end

--[[
    Check if a pet is unobtainable
    @param data table - Pet data with fields: name, source
    @return boolean - True if pet is unobtainable
]]
function UnobtainableFilters:IsUnobtainablePet(data)
    if not data then return true end
    
    -- NOTE: Many pets have "Unknown" source in API, so we DON'T filter by Unknown
    -- Only filter by explicit unobtainable keywords
    
    -- Check: Source text keywords (TCG, Promotion, etc.)
    if data.source and HasUnobtainableKeyword(data.source) then
        return true
    end
    
    return false
end

--[[
    Check if a toy is unobtainable
    @param data table - Toy data with fields: name, source
    @return boolean - True if toy is unobtainable
]]
function UnobtainableFilters:IsUnobtainableToy(data)
    if not data then return true end
    
    -- NOTE: Many toys have "Unknown" source in API, so we DON'T filter by Unknown
    -- Only filter by explicit unobtainable keywords
    
    -- Check: Source text keywords (TCG, Promotion, etc.)
    if data.source and HasUnobtainableKeyword(data.source) then
        return true
    end
    
    return false
end

--[[
    Check if an illusion is unobtainable
    @param data table - Illusion data with fields: name, source
    @return boolean - True if illusion is unobtainable
]]
function UnobtainableFilters:IsUnobtainableIllusion(data)
    if not data then return true end
    
    -- NOTE: Many illusions have "Unknown" source in API, so we DON'T filter by Unknown
    -- Only filter by explicit unobtainable keywords
    
    -- Check: Source text keywords
    if data.source and HasUnobtainableKeyword(data.source) then
        return true
    end
    
    return false
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Module is exported via WarbandNexus.UnobtainableFilters (line 20)

