--[[
    Warband Nexus - Plans browse source text parser (mount/pet/toy tooltips).
    Split from PlansUI.lua (Lua 5.1 local limit).
    Loaded before Modules/UI/PlansUI.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
-- SOURCE TEXT PARSER

--[[
    Parse source text into structured parts
    @param source string - Raw source text from API
    @return table - Parsed parts { sourceType, zone, npc, cost, renown, scenario, raw }
]]
function WarbandNexus:ParseSourceText(source)
    local parts = {
        sourceType = nil,
        zone = nil,
        npc = nil,
        cost = nil,
        renown = nil,
        scenario = nil,
        raw = source,
        isVendor = false,
        isDrop = false,
        isPetBattle = false,
        isQuest = false,
    }
    
    if not source then return parts end
    if type(source) ~= "string" then return parts end
    if issecretvalue and issecretvalue(source) then return parts end
    
    -- Clean escape sequences from source text before parsing
    local cleanSource = source
    if self.CleanSourceText then
        cleanSource = self:CleanSourceText(source)
    else
        -- Fallback inline cleanup if CleanSourceText not available
        cleanSource = source:gsub("|T.-|t", "")  -- Remove texture tags
        cleanSource = cleanSource:gsub("|c%x%x%x%x%x%x%x%x", "")  -- Remove color codes
        cleanSource = cleanSource:gsub("|r", "")  -- Remove color reset
        cleanSource = cleanSource:gsub("|H.-|h", "")  -- Remove hyperlinks
        cleanSource = cleanSource:gsub("|h", "")  -- Remove closing hyperlink tags
    end
    if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
        return parts
    end
    
    -- Determine source type using Blizzard's localized BATTLE_PET_SOURCE_* globals
    -- These globals are auto-localized by WoW client (Drop, Quest, Vendor, etc.)
    local L = ns.L
    -- Single parse system for mount/pet/toy/plans. Order: more specific first.
    local sourcePatterns = {
        { pattern = BATTLE_PET_SOURCE_3 or "Vendor",                         type = "Vendor",      flagKey = "isVendor" },
        { pattern = (L and L["PARSE_SOLD_BY"]) or "Sold by",                 type = "Vendor",      flagKey = "isVendor" },
        { pattern = BATTLE_PET_SOURCE_1 or "Drop",                           type = "Drop",        flagKey = "isDrop" },
        { pattern = BATTLE_PET_SOURCE_5 or "Pet Battle",                     type = "Pet Battle",  flagKey = "isPetBattle" },
        { pattern = (L and L["SOURCE_TYPE_PUZZLE"]) or "Puzzle",             type = "Puzzle" },
        { pattern = BATTLE_PET_SOURCE_2 or "Quest",                          type = "Quest",       flagKey = "isQuest" },
        { pattern = BATTLE_PET_SOURCE_6 or "Achievement",                    type = "Achievement" },
        { pattern = (L and L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement", type = "Achievement" },
        { pattern = BATTLE_PET_SOURCE_4 or "Profession",                     type = "Crafted" },
        { pattern = (L and L["PARSE_CRAFTED"]) or "Crafted",                 type = "Crafted" },
        { pattern = BATTLE_PET_SOURCE_8 or "Promotion",                      type = "Promotion" },
        { pattern = BATTLE_PET_SOURCE_10 or "In-Game Shop",                  type = "Promotion" },
        { pattern = BATTLE_PET_SOURCE_9 or "Trading Card",                   type = "Promotion" },
        { pattern = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post", type = "Trading Post" },
        { pattern = BATTLE_PET_SOURCE_7 or "World Event",                     type = "World Event" },
        { pattern = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",          type = "Treasure" },
        { pattern = (L and L["PARSE_DISCOVERY"]) or "Discovery",             type = "Treasure" },
        { pattern = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown",             type = "Reputation" },
        { pattern = (L and L["PARSE_PARAGON"]) or "Paragon",                type = "Reputation" },
        { pattern = (L and L["PARSE_COVENANT"]) or "Covenant",               type = "Reputation" },
        { pattern = REPUTATION or "Reputation",                              type = "Reputation" },
        { pattern = (L and L["SOURCE_TYPE_PVP"]) or PVP or "PvP",            type = "PvP" },
        { pattern = (L and L["PARSE_GARRISON"]) or "Garrison",               type = "Quest" },
        { pattern = (L and L["PARSE_MISSION"]) or "Mission",                type = "Quest" },
        { pattern = (L and L["PARSE_LOCATION"]) or (L and L["LOCATION_LABEL"] and L["LOCATION_LABEL"]:gsub(":%s*$", "")) or "Location", type = "Drop" },
        { pattern = ZONE or "Zone",                                          type = "Drop" },
    }
    
    for ei = 1, #sourcePatterns do
        local entry = sourcePatterns[ei]
        if entry.pattern and cleanSource:find(entry.pattern, 1, true) then
            parts.sourceType = entry.type
            if entry.flagKey then
                parts[entry.flagKey] = true
            end
            break
        end
    end
    
    -- Extract vendor/NPC name (use cleaned source)
    local vendor = cleanSource:match("Vendor:%s*([^\n]+)") or cleanSource:match("Sold by:%s*([^\n]+)")
    if vendor then
        parts.npc = vendor:gsub("%s*$", "")  -- Trim trailing whitespace
    end
    
    -- Extract zone (use cleaned source)
    local zone = cleanSource:match("Zone:%s*([^\n]+)")
    if zone then
        parts.zone = zone:gsub("%s*$", "")
    end
    
    -- Extract cost (gold) - use cleaned source
    local goldCost = cleanSource:match("Cost:%s*([%d,]+)%s*[gG]old") or cleanSource:match("([%d,]+)%s*[gG]old")
    if goldCost then
        parts.cost = goldCost .. " " .. ((ns.L and ns.L["GOLD_LABEL"]) or "Gold")
    end
    
    -- Extract cost (other currencies) - use cleaned source
    local currencyCost = cleanSource:match("Cost:%s*([%d,]+)%s*([^\n]+)")
    if currencyCost and not goldCost then
        parts.cost = currencyCost
    end
    
    -- Extract renown requirement - use cleaned source
    local renown = cleanSource:match("Renown%s*(%d+)") or cleanSource:match("Renown:%s*(%d+)")
    if renown then
        parts.renown = ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown") .. " " .. renown
    end
    
    -- Extract scenario - use cleaned source
    local scenario = cleanSource:match("Scenario:%s*([^\n]+)")
    if scenario then
        parts.scenario = scenario:gsub("%s*$", "")
    end
    
    -- Pet Battle location - use cleaned source
    local petBattleZone = cleanSource:match("Pet Battle:%s*([^\n]+)")
    if petBattleZone then
        parts.zone = petBattleZone:gsub("%s*$", "")
    end
    
    -- Drop source - use cleaned source
    local dropSource = cleanSource:match("Drop:%s*([^\n]+)")
    if dropSource then
        parts.npc = dropSource:gsub("%s*$", "")
    end
    
    return parts
end
