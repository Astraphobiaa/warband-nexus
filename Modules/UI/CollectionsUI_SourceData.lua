--[[
    Warband Nexus - Collections tab source/category tables and FormatSourceMultiline.
    Split from CollectionsUI.lua to stay under Lua 5.1 chunk local limit (~200).
    Loaded from WarbandNexus.toc immediately before Modules/UI/CollectionsUI.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue

-- ============================================================================
-- MOUNT / PET / TOY SOURCE CLASSIFICATION (Pure API)
-- ============================================================================
--[[
    Categorization is driven exclusively by Blizzard's API source type integer.
    No string parsing, no keyword heuristics.

    - Mount: C_MountJournal.GetMountInfoByID(id) → 6th return `sourceType`
        Enum (0-based) per Wowpedia:
            0 Other, 1 Drop, 2 Quest, 3 Vendor, 4 Profession, 5 PetBattle,
            6 Achievement, 7 WorldEvent, 8 Promotion, 9 TCG, 10 Shop, 11 Discovery
    - Pet:   C_PetJournal source filter index (BattlePetSources):
            1 Drop, 2 Quest, 3 Vendor, 4 Profession, 5 PetBattle, 6 Achievement,
            7 WorldEvent, 8 Promotion, 9 TCG, 10 Shop, 11 TradingPost, 12 PvP
    - Toy:   C_ToyBox source filter index (BattlePetSources, same as pet above).
]]

local L = ns.L
local format = string.format

-- Mount categories (Blizzard mount-source enum order; "other" = sourceType 0).
local SOURCE_CATEGORIES = {
    { key = "drop",        label = (L and L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop",                  iconAtlas = "ParagonReputation_Bag" },
    { key = "quest",       label = (L and L["SOURCE_TYPE_QUEST"]) or BATTLE_PET_SOURCE_2 or "Quest",                iconAtlas = "quest-legendary-turnin" },
    { key = "vendor",      label = (L and L["SOURCE_TYPE_VENDOR"]) or BATTLE_PET_SOURCE_3 or "Vendor",              iconAtlas = "coin-gold" },
    { key = "profession",  label = (L and L["SOURCE_TYPE_PROFESSION"]) or BATTLE_PET_SOURCE_4 or "Profession",      iconAtlas = "poi-workorders" },
    { key = "petbattle",   label = (L and L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle",      iconAtlas = "WildBattlePetCapturable" },
    { key = "achievement", label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement",    iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "worldevent",  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or BATTLE_PET_SOURCE_7 or "World Event",    iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = (L and L["SOURCE_TYPE_PROMOTION"]) or BATTLE_PET_SOURCE_8 or "Promotion",        iconAtlas = "Bonus-Objective-Star" },
    { key = "tcg",         label = (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card Game",                    iconAtlas = "Auctioneer" },
    { key = "shop",        label = (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or BATTLE_PET_SOURCE_10 or "In-Game Shop", iconAtlas = "coin-gold" },
    { key = "discovery",   label = (L and L["PARSE_DISCOVERY"]) or "Discovery",                                     iconAtlas = "VignetteLoot" },
    { key = "unknown",     label = (L and L["SOURCE_OTHER"]) or "Other",                                            iconAtlas = "poi-town" },
}

local SOURCE_CATEGORY_ORDER = {}
for i = 1, #SOURCE_CATEGORIES do
    local cat = SOURCE_CATEGORIES[i]
    SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- Pet categories (Blizzard battle-pet source filter order, 1-indexed).
local PET_SOURCE_CATEGORIES = {
    { key = "drop",        label = (L and L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop",                  iconAtlas = "ParagonReputation_Bag" },
    { key = "quest",       label = (L and L["SOURCE_TYPE_QUEST"]) or BATTLE_PET_SOURCE_2 or "Quest",                iconAtlas = "quest-legendary-turnin" },
    { key = "vendor",      label = (L and L["SOURCE_TYPE_VENDOR"]) or BATTLE_PET_SOURCE_3 or "Vendor",              iconAtlas = "coin-gold" },
    { key = "profession",  label = (L and L["SOURCE_TYPE_PROFESSION"]) or BATTLE_PET_SOURCE_4 or "Profession",      iconAtlas = "poi-workorders" },
    { key = "petbattle",   label = (L and L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle",      iconAtlas = "WildBattlePetCapturable" },
    { key = "achievement", label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement",    iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "worldevent",  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or BATTLE_PET_SOURCE_7 or "World Event",    iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = (L and L["SOURCE_TYPE_PROMOTION"]) or BATTLE_PET_SOURCE_8 or "Promotion",        iconAtlas = "Bonus-Objective-Star" },
    { key = "tcg",         label = (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card Game",                    iconAtlas = "Auctioneer" },
    { key = "shop",        label = (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or BATTLE_PET_SOURCE_10 or "In-Game Shop", iconAtlas = "coin-gold" },
    { key = "tradingpost", label = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",                         iconAtlas = "Auctioneer" },
    { key = "pvp",         label = (L and L["SOURCE_TYPE_PVP"]) or "PvP",                                           iconAtlas = "honorsystem-icon-prestige-9" },
    { key = "unknown",     label = (L and L["SOURCE_OTHER"]) or "Other",                                            iconAtlas = "poi-town" },
}

local PET_SOURCE_CATEGORY_ORDER = {}
for i = 1, #PET_SOURCE_CATEGORIES do
    local cat = PET_SOURCE_CATEGORIES[i]
    PET_SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- Toy categories (Blizzard ToyBox source filter, BattlePetSources, 1-indexed).
local TOY_SOURCE_CATEGORIES = {
    { key = "drop",        sourceIndex = 1,  label = (L and L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop",                  iconAtlas = "ParagonReputation_Bag" },
    { key = "quest",       sourceIndex = 2,  label = (L and L["SOURCE_TYPE_QUEST"]) or BATTLE_PET_SOURCE_2 or "Quest",                iconAtlas = "quest-legendary-turnin" },
    { key = "vendor",      sourceIndex = 3,  label = (L and L["SOURCE_TYPE_VENDOR"]) or BATTLE_PET_SOURCE_3 or "Vendor",              iconAtlas = "coin-gold" },
    { key = "profession",  sourceIndex = 4,  label = (L and L["SOURCE_TYPE_PROFESSION"]) or BATTLE_PET_SOURCE_4 or "Profession",      iconAtlas = "poi-workorders" },
    { key = "petbattle",   sourceIndex = 5,  label = (L and L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle",      iconAtlas = "WildBattlePetCapturable" },
    { key = "achievement", sourceIndex = 6,  label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement",    iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "worldevent",  sourceIndex = 7,  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or BATTLE_PET_SOURCE_7 or "World Event",    iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   sourceIndex = 8,  label = (L and L["SOURCE_TYPE_PROMOTION"]) or BATTLE_PET_SOURCE_8 or "Promotion",        iconAtlas = "Bonus-Objective-Star" },
    { key = "tcg",         sourceIndex = 9,  label = (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card Game",                    iconAtlas = "Auctioneer" },
    { key = "shop",        sourceIndex = 10, label = (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or BATTLE_PET_SOURCE_10 or "In-Game Shop", iconAtlas = "coin-gold" },
    { key = "tradingpost", sourceIndex = 11, label = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",                         iconAtlas = "Auctioneer" },
    { key = "unknown",     sourceIndex = 0,  label = (L and L["SOURCE_OTHER"]) or "Other",                                            iconAtlas = "poi-town" },
}

local TOY_SOURCE_CATEGORY_ORDER = {}
for i = 1, #TOY_SOURCE_CATEGORIES do
    local cat = TOY_SOURCE_CATEGORIES[i]
    TOY_SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- API integer → category key tables.
-- Mount uses the C_MountJournal sourceType enum (0..11 per Wowpedia).
local MOUNT_SOURCETYPE_TO_CATEGORY = {
    [0]  = "unknown",
    [1]  = "drop",
    [2]  = "quest",
    [3]  = "vendor",
    [4]  = "profession",
    [5]  = "petbattle",
    [6]  = "achievement",
    [7]  = "worldevent",
    [8]  = "promotion",
    [9]  = "tcg",
    [10] = "shop",
    [11] = "discovery",
}
-- Pets/toys use the C_PetJournal / C_ToyBox source filter index (BattlePetSources, 1-indexed).
local BATTLEPET_SOURCETYPE_TO_CATEGORY = {
    [1]  = "drop",
    [2]  = "quest",
    [3]  = "vendor",
    [4]  = "profession",
    [5]  = "petbattle",
    [6]  = "achievement",
    [7]  = "worldevent",
    [8]  = "promotion",
    [9]  = "tcg",
    [10] = "shop",
    [11] = "tradingpost",
    [12] = "pvp",
}
local SOURCE_INDEX_TO_TOY_CAT = BATTLEPET_SOURCETYPE_TO_CATEGORY

-- Category icon by key (atlas only; CreateCollapsibleHeader isAtlas=true)
local DEFAULT_CATEGORY_ATLAS = "icons_64x64_important"
local function GetMountCategoryIcon(catKey)
    for i = 1, #SOURCE_CATEGORIES do
        if SOURCE_CATEGORIES[i].key == catKey then
            local a = SOURCE_CATEGORIES[i].iconAtlas
            return (a and a ~= "") and a or DEFAULT_CATEGORY_ATLAS
        end
    end
    return DEFAULT_CATEGORY_ATLAS
end
local function GetPetCategoryIcon(catKey)
    for i = 1, #PET_SOURCE_CATEGORIES do
        if PET_SOURCE_CATEGORIES[i].key == catKey then
            local a = PET_SOURCE_CATEGORIES[i].iconAtlas
            return (a and a ~= "") and a or DEFAULT_CATEGORY_ATLAS
        end
    end
    return DEFAULT_CATEGORY_ATLAS
end
local function GetToyCategoryIcon(catKey)
    for i = 1, #TOY_SOURCE_CATEGORIES do
        if TOY_SOURCE_CATEGORIES[i].key == catKey then
            local a = TOY_SOURCE_CATEGORIES[i].iconAtlas
            return (a and a ~= "") and a or DEFAULT_CATEGORY_ATLAS
        end
    end
    return DEFAULT_CATEGORY_ATLAS
end

-- Pure-API classifier: takes the API source-type integer; returns a stable category key.
-- Backwards compat: still accepts a `cache` table arg (legacy callsites pass it) but
-- caching is unnecessary for an O(1) integer lookup, so the table is simply ignored.
local function ClassifyMountByAPI(_cache, sourceTypeInt)
    if not sourceTypeInt then return "unknown" end
    if issecretvalue and issecretvalue(sourceTypeInt) then return "unknown" end
    return MOUNT_SOURCETYPE_TO_CATEGORY[sourceTypeInt] or "unknown"
end
local function ClassifyBattlePetByAPI(_cache, sourceTypeIndex)
    if not sourceTypeIndex then return "unknown" end
    if issecretvalue and issecretvalue(sourceTypeIndex) then return "unknown" end
    return BATTLEPET_SOURCETYPE_TO_CATEGORY[sourceTypeIndex] or "unknown"
end
-- Aliases preserve existing function names used throughout the file.
local ClassifyMountSourceCached = ClassifyMountByAPI
local ClassifyPetSourceCached = ClassifyBattlePetByAPI
local function ClassifySource(_cache, sourceTypeInt, kind)
    if kind == "mount" then return ClassifyMountByAPI(nil, sourceTypeInt) end
    return ClassifyBattlePetByAPI(nil, sourceTypeInt)
end

local function FormatMountPetToyListTrySuffix(collectibleType, id)
    if not id or not WarbandNexus or not WarbandNexus.ShouldShowTryCountInUI or not WarbandNexus:ShouldShowTryCountInUI(collectibleType, id) then return "" end
    local c = WarbandNexus:GetTryCount(collectibleType, id) or 0
    local fmt = (ns.L and ns.L["COLLECTION_LIST_ATTEMPTS_FMT"]) or "%d Attempts"
    return " |cff888888(" .. format(fmt, c) .. ")|r"
end

-- Para birimi ikonu: cost/amount satırlarında fiyat yanında gösterilir.
-- Default gold icon (fallback when currency cannot be identified)
local CURRENCY_ICON_GOLD = "|TInterface\\Icons\\INV_Misc_Coin_01:14:14:0:0:64:64:4:60:4:60|t"

-- Smart currency icon resolver: parse cost text to identify actual currency and return correct icon.
-- Uses C_CurrencyInfo API for dynamic lookup; caches results to avoid repeated API calls.
local _currencyIconCache = {}
local function MakeCurrencyIconString(iconPath)
    if not iconPath or iconPath == "" then return CURRENCY_ICON_GOLD end
    return "|T" .. tostring(iconPath) .. ":14:14:0:0:64:64:4:60:4:60|t"
end

-- Known currency name → currencyID mappings (covers most common vendor currencies).
-- These are stable IDs that don't change between patches.
local KNOWN_CURRENCY_IDS = {
    ["honor"] = 1792,
    ["conquest"] = 1602,
    ["timewarped badge"] = 1166,
    ["timewarped badges"] = 1166,
    ["mark of honor"] = 1901, -- technically an item, but treated as currency in UI
    ["polished pet charm"] = 2032, -- item-based but common
    ["shiny pet charm"] = 2032,
    ["trader's tender"] = 2032, -- Trading Post currency
    ["dragon isles supplies"] = 2003,
    ["elemental overflow"] = 2118,
    ["bloody tokens"] = 2123,
    ["trophy of strife"] = 2123,
    ["valor"] = 1191,
    ["anima"] = 1813,
    ["reservoir anima"] = 1813,
    ["stygia"] = 1767,
    ["cataloged research"] = 1931,
    ["cosmic flux"] = 2009,
    ["storm sigil"] = 2122,
    ["flightstones"] = 2245,
    ["paracausal flakes"] = 2594,
    ["resonance crystals"] = 2815,
    ["restored coffer key"] = 2803,
    ["weathered harbinger crest"] = 2806,
    ["carved harbinger crest"] = 2807,
    ["runed harbinger crest"] = 2809,
    ["gilded harbinger crest"] = 2812,
    ["undercoin"] = 2803,
}

local function ResolveCurrencyIconFromText(costText)
    if not costText or costText == "" then return CURRENCY_ICON_GOLD end
    -- Strip WoW format codes and normalize
    local clean = costText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return CURRENCY_ICON_GOLD end

    -- Check cache first
    local cacheKey = clean:lower()
    if _currencyIconCache[cacheKey] then return _currencyIconCache[cacheKey] end

    -- Pure gold amount (e.g. "50 Gold", "1,500 Gold", just a number)
    if clean:match("^[%d%.,]+%s*[Gg]old") or clean:match("^[%d%.,]+$") then
        _currencyIconCache[cacheKey] = CURRENCY_ICON_GOLD
        return CURRENCY_ICON_GOLD
    end

    -- Try to extract currency name: "123 Currency Name" or "Currency Name x123"
    local currencyName = clean:match("^%d[%d%.,]*%s+(.+)$") or clean:match("^(.+)%s+x%d+$") or clean
    if currencyName then
        currencyName = currencyName:gsub("^%s+", ""):gsub("%s+$", "")
        local lowerName = currencyName:lower()

        -- Check known currency table
        local knownID = KNOWN_CURRENCY_IDS[lowerName]
        if knownID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(knownID)
            if info and info.iconFileID then
                local icon = MakeCurrencyIconString(info.iconFileID)
                _currencyIconCache[cacheKey] = icon
                return icon
            end
        end

        -- Dynamic lookup: search through active currencies
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            -- Try common currency ID ranges
            local CURRENCY_TEST_IDS = {1792, 1602, 1166, 1901, 2032, 2003, 2118, 2122, 2123, 1191, 1813, 1767, 1931, 2009, 2245, 2594, 2815, 2803, 2806, 2807, 2809, 2812}
            for ti = 1, #CURRENCY_TEST_IDS do
                local testID = CURRENCY_TEST_IDS[ti]
                local info = C_CurrencyInfo.GetCurrencyInfo(testID)
                if info and info.name and info.name:lower() == lowerName and info.iconFileID then
                    local icon = MakeCurrencyIconString(info.iconFileID)
                    _currencyIconCache[cacheKey] = icon
                    return icon
                end
            end
        end
    end

    -- Fallback: gold icon
    _currencyIconCache[cacheKey] = CURRENCY_ICON_GOLD
    return CURRENCY_ICON_GOLD
end

-- Resolve currency icon for a cost/amount line value (text after "Cost: " or "Amount: ")
local function GetCurrencyIconForCostLine(costValue)
    if not costValue or costValue == "" then return CURRENCY_ICON_GOLD end
    return ResolveCurrencyIconFromText(costValue)
end

-- WoW format kodlarını metinden kaldır (renk, reset, newline vb.). Görünen "cFFFFD200", "r", "n" gibi artıkları önler.
local function StripWoWFormatCodes(text)
    if not text or text == "" then return "" end
    local s = text
    s = s:gsub("|n", "\n")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|c%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H.-|h", "")
    s = s:gsub("|h", "")
    s = s:gsub("|%a", "")
    return s
end

-- Source metnini satır satır göster: her kaynak tipi (Drop, Location, Vendor, vb.) ayrı satır.
-- Format: Sarı "Label : " Beyaz "Value". Cost/Amount yanında currency icon.
local function FormatSourceMultiline(rawSource, goldHex, whiteHex)
    if not rawSource or rawSource == "" then return "" end
    rawSource = StripWoWFormatCodes(rawSource)
    if rawSource == "" then return "" end
    local L = ns.L
    local dropKey = BATTLE_PET_SOURCE_1 or (L and L["SOURCE_TYPE_DROP"]) or "Drop"
    local vendorKey = BATTLE_PET_SOURCE_3 or (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor"
    local questKey = BATTLE_PET_SOURCE_2 or (L and L["SOURCE_TYPE_QUEST"]) or "Quest"
    local achievementKey = BATTLE_PET_SOURCE_6 or (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement"
    local professionKey = BATTLE_PET_SOURCE_4 or (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession"
    local worldEventKey = BATTLE_PET_SOURCE_7 or (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event"
    local promotionKey = BATTLE_PET_SOURCE_8 or (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion"
    local tradingPostKey = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post"
    local treasureKey = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure"
    local renownKey = (L and L["SOURCE_TYPE_RENOWN"]) or REPUTATION or "Renown"
    local pvpKey = (L and L["SOURCE_TYPE_PVP"]) or PVP or "PvP"
    local locationKey = (L and L["PARSE_LOCATION"]) or (L and L["LOCATION_LABEL"] and L["LOCATION_LABEL"]:gsub(":%s*$", "")) or "Location"
    local zoneKey = (L and L["PARSE_ZONE"]) or ZONE or "Zone"
    local costKey = (L and L["PARSE_COST"]) or "Cost"
    local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
    local factionKey = FACTION or (L and L["PARSE_FACTION"]) or "Faction"
    local reputationKey = REPUTATION or (L and L["PARSE_REPUTATION"]) or "Reputation"
    local soldByKey = (L and L["PARSE_SOLD_BY"]) or "Sold by"
    local containedInKey = (L and L["PARSE_CONTAINED_IN"]) or "Contained in"
    local discoveryKey = (L and L["PARSE_DISCOVERY"]) or "Discovery"

    -- Tüm kaynak etiketleri: satır kırma ve blok başlangıcı için (her biri ayrı veri = ayrı satır)
    local lineStartKeys = {
        dropKey, vendorKey, questKey, achievementKey, professionKey, worldEventKey, promotionKey,
        tradingPostKey, treasureKey, renownKey, pvpKey, locationKey, zoneKey, costKey, amountKey,
        factionKey, reputationKey, soldByKey, containedInKey, discoveryKey,
    }
    -- Ön adım: " Key:" veya " Key :" geçen her yerde satır kır (API formatına bağlı kalmadan)
    for ki = 1, #lineStartKeys do
        local key = lineStartKeys[ki]
        if key and key ~= "" and type(key) == "string" then
            local needle = " " .. key
            local pos = 1
            while true do
                local idx = rawSource:find(needle, pos, true)
                if not idx then break end
                local afterKey = idx + 1 + #key
                local rest = rawSource:sub(afterKey)
                local skip = 0
                while skip < #rest and rest:sub(skip + 1, skip + 1) == " " do skip = skip + 1 end
                if rest:sub(skip + 1, skip + 1) == ":" then
                    local valueStart = afterKey + skip + 1
                    local value = rawSource:sub(valueStart):gsub("^%s+", "")
                    rawSource = rawSource:sub(1, idx - 1) .. "|n" .. key .. ": " .. value
                    pos = 1
                else
                    pos = idx + 1
                end
            end
        end
    end
    -- |n'ı \n yap ki aşağıdaki parçalama çalışsın
    rawSource = rawSource:gsub("|n", "\n")

    local blockStartPrefixes = {}
    for ki = 1, #lineStartKeys do
        local key = lineStartKeys[ki]
        if key and key ~= "" and type(key) == "string" then
            blockStartPrefixes[#blockStartPrefixes + 1] = key .. ":"
        end
    end

    local function startsNewBlock(text)
        for pi = 1, #blockStartPrefixes do
            local prefix = blockStartPrefixes[pi]
            if text:sub(1, #prefix) == prefix then return true end
        end
        return false
    end

    -- " | " ve " . " ile parçalara böl; her "Type: value" kendi blokunda
    local parts = {}
    for p in (rawSource:gsub("|%s*", "\n"):gsub("%.%s+", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        p = p:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then parts[#parts + 1] = p end
    end
    if #parts == 0 then parts[#parts + 1] = rawSource:gsub("^%s+", ""):gsub("%s+$", "") end

    local blocks = {}
    local current = {}
    for i = 1, #parts do
        local p = parts[i]
        if startsNewBlock(p) and #current > 0 then
            blocks[#blocks + 1] = table.concat(current, " ")
            current = { p }
        else
            current[#current + 1] = p
        end
    end
    if #current > 0 then blocks[#blocks + 1] = table.concat(current, " ") end
    if #blocks == 0 then blocks[#blocks + 1] = rawSource:gsub("^%s+", ""):gsub("%s+$", "") end

    -- Her "Label:" veya "Label :" geçişinde satır kır (API bazen boşluklu "Location :" döner).
    local function splitBlockIntoLines(s)
        for ki = 1, #lineStartKeys do
            local key = lineStartKeys[ki]
            if not key or key == "" or type(key) ~= "string" then
                -- skip
            else
                local needle = " " .. key
                local pos = 1
                while true do
                    local startIdx = s:find(needle, pos, true)
                    if not startIdx then break end
                    local afterKey = startIdx + 1 + #key
                    local colonIdx = s:find(":", afterKey - 1, true)
                    if colonIdx and colonIdx <= afterKey + 2 then
                        local valueStart = colonIdx + 1
                        local value = s:sub(valueStart):gsub("^%s+", "")
                        s = s:sub(1, startIdx - 1) .. "\n" .. key .. ": " .. value
                        pos = 1
                    else
                        pos = startIdx + 1
                    end
                end
                -- Satır başında olmayan "Key:" (örn. "X Location: Y")
                pos = 1
                local needle2 = key .. ":"
                while true do
                    local idx = s:find(needle2, pos, true)
                    if not idx or idx <= 1 then break end
                    local prev = s:sub(idx - 1, idx - 1)
                    if prev == " " then
                        local valueStart = idx + #needle2
                        local value = s:sub(valueStart):gsub("^%s+", "")
                        s = s:sub(1, idx - 2) .. "\n" .. key .. ": " .. value
                        pos = 1
                    elseif prev ~= "\n" then
                        local valueStart = idx + #needle2
                        local value = s:sub(valueStart):gsub("^%s+", "")
                        s = s:sub(1, idx - 1) .. "\n" .. key .. ": " .. value
                        pos = 1
                    else
                        pos = idx + 1
                    end
                end
            end
        end
        return s
    end

    local function formatLine(label, value, isCostOrAmount)
        local suffix = (isCostOrAmount and value ~= "") and (" " .. GetCurrencyIconForCostLine(value)) or ""
        return goldHex .. label .. " : |r" .. whiteHex .. (value or "") .. "|r" .. suffix
    end

    local allBlocksOut = {}
    for b = 1, #blocks do
        local s = splitBlockIntoLines(blocks[b])
        local lines = {}
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colon = line:find(":", 1, true)
                if colon and colon > 1 then
                    local label = line:sub(1, colon - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colon + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local isCostOrAmount = (label == costKey or label == amountKey)
                    lines[#lines + 1] = formatLine(label, value, isCostOrAmount)
                else
                    lines[#lines + 1] = whiteHex .. line .. "|r"
                end
            end
        end
        if #lines > 0 then
            allBlocksOut[#allBlocksOut + 1] = table.concat(lines, "|n")
        end
    end
    local result = table.concat(allBlocksOut, "|n")
    -- WoW'da satır kırma: |n kullan (FontString bazen \n'i tek satır gösterebiliyor)
    return result
end


ns.CollectionsUI_SourceData = {
    SOURCE_CATEGORIES = SOURCE_CATEGORIES,
    SOURCE_CATEGORY_ORDER = SOURCE_CATEGORY_ORDER,
    PET_SOURCE_CATEGORIES = PET_SOURCE_CATEGORIES,
    PET_SOURCE_CATEGORY_ORDER = PET_SOURCE_CATEGORY_ORDER,
    TOY_SOURCE_CATEGORIES = TOY_SOURCE_CATEGORIES,
    TOY_SOURCE_CATEGORY_ORDER = TOY_SOURCE_CATEGORY_ORDER,
    MOUNT_SOURCETYPE_TO_CATEGORY = MOUNT_SOURCETYPE_TO_CATEGORY,
    BATTLEPET_SOURCETYPE_TO_CATEGORY = BATTLEPET_SOURCETYPE_TO_CATEGORY,
    SOURCE_INDEX_TO_TOY_CAT = SOURCE_INDEX_TO_TOY_CAT,
    DEFAULT_CATEGORY_ATLAS = DEFAULT_CATEGORY_ATLAS,
    GetMountCategoryIcon = GetMountCategoryIcon,
    GetPetCategoryIcon = GetPetCategoryIcon,
    GetToyCategoryIcon = GetToyCategoryIcon,
    ClassifyMountByAPI = ClassifyMountByAPI,
    ClassifyBattlePetByAPI = ClassifyBattlePetByAPI,
    ClassifyMountSourceCached = ClassifyMountSourceCached,
    ClassifyPetSourceCached = ClassifyPetSourceCached,
    ClassifySource = ClassifySource,
    FormatMountPetToyListTrySuffix = FormatMountPetToyListTrySuffix,
    CURRENCY_ICON_GOLD = CURRENCY_ICON_GOLD,
    MakeCurrencyIconString = MakeCurrencyIconString,
    KNOWN_CURRENCY_IDS = KNOWN_CURRENCY_IDS,
    ResolveCurrencyIconFromText = ResolveCurrencyIconFromText,
    GetCurrencyIconForCostLine = GetCurrencyIconForCostLine,
    StripWoWFormatCodes = StripWoWFormatCodes,
    FormatSourceMultiline = FormatSourceMultiline,
}
