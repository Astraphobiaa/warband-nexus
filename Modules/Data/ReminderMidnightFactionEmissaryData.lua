--[[
    Midnight faction Emissary world quests (NOT in warcraft.wiki.gg Category:Midnight_world_quests).
    Blizzard pins them on every regional map via C_TaskQuest; zone assignment is by faction, not scan mapID.

    Sources (May 2026):
    - Four factions / zones: Midnight World Tour (95245) + MidnightQuestCatalog eventGroup zones
    - Silvermoon Court -> Eversong (2395): https://warcraft.wiki.gg (Saltheril's Soiree / Caeris Fairdawn, Eversong)
    - Amani Tribe -> Zul'Aman (2437): Midnight: Abundance (93890) in MidnightQuestCatalog
    - Hara'ti -> Harandar (2413): Midnight: Legends of the Haranir (93891)
    - Singularity -> Voidstorm (2405): Midnight: Stormarion Assault (93892)
    - Quest IDs: in-game Set Alert scan / quest log (user report 94478, 94058, 92547, 93514)
]]

local ADDON_NAME, ns = ...

local ZONE_INDEX = {
    silvermoon = 1,
    eversong = 2,
    isle = 3,
    harandar = 4,
    zulaman = 5,
    voidstorm = 6,
}

local ENTRIES = {
    {
        questID = 94478,
        title = "Emissary of Silvermoon Court",
        zoneKey = "eversong",
        mapID = 2395,
        faction = "Silvermoon Court",
        sourceNote = "Faction WQ; Eversong Woods (not Category:Midnight_world_quests)",
    },
    {
        questID = 94058,
        title = "Emissary of the Amani Tribe",
        zoneKey = "zulaman",
        mapID = 2437,
        faction = "Amani Tribe",
        sourceNote = "Faction WQ; Zul'Aman",
    },
    {
        questID = 92547,
        title = "Emissary of the Hara'ti",
        zoneKey = "harandar",
        mapID = 2413,
        faction = "Hara'ti",
        sourceNote = "Faction WQ; Harandar",
    },
    {
        questID = 93514,
        title = "Emissary of the Singularity",
        zoneKey = "voidstorm",
        mapID = 2405,
        faction = "Singularity / Stormarion",
        sourceNote = "Faction WQ; Voidstorm",
    },
}

local BY_QUEST_ID = {}
for i = 1, #ENTRIES do
    local e = ENTRIES[i]
    BY_QUEST_ID[e.questID] = e
end

ns.ReminderMidnightFactionEmissaryData = {
    ENTRIES = ENTRIES,
    BUILD_COUNT = #ENTRIES,

    ---@param questID number
    ---@return table|nil
    GetEntry = function(questID)
        return BY_QUEST_ID[tonumber(questID)]
    end,

    ---@param questID number
    ---@return number|nil zone index (ReminderWorldQuestIndex.ZONES)
    GetZoneIndexForQuest = function(questID)
        local e = BY_QUEST_ID[tonumber(questID)]
        if not e or not e.zoneKey then return nil end
        return ZONE_INDEX[e.zoneKey]
    end,

    ---@param questID number
    ---@return string|nil
    GetZoneKeyForQuest = function(questID)
        local e = BY_QUEST_ID[tonumber(questID)]
        return e and e.zoneKey
    end,

    ---@param title string|nil
    ---@return boolean
    IsEmissaryTitle = function(title)
        if title == nil or title == "" then return false end
        if issecretvalue and issecretvalue(title) then return false end
        return title:lower():find("emissary of ", 1, true) ~= nil
    end,
}
