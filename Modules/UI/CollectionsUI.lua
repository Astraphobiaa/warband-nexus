--[[
    Warband Nexus - Collections Tab
    Sub-tab system: Mounts, Pets, Toys, etc.
    Mounts tab: Virtual scroll list grouped by Source, Model Viewer, Description panel.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local Constants = ns.Constants

local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local COLORS = ns.UI_COLORS
local CreateHeaderIcon = ns.UI_CreateHeaderIcon
local GetTabIcon = ns.UI_GetTabIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader

-- Single source for layout (matches CurrencyUI, PlansUI, SharedWidgets)
local function GetLayout()
    return ns.UI_LAYOUT or ns.UI_SPACING or {}
end
local LAYOUT = GetLayout()
local SIDE_MARGIN = LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = LAYOUT.TOP_MARGIN or 8
local CARD_GAP = LAYOUT.CARD_GAP or 8
local AFTER_ELEMENT = LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8
local ROW_ICON_SIZE = LAYOUT.ROW_ICON_SIZE or 20
local STATUS_ICON_SIZE = LAYOUT.STATUS_ICON_SIZE or 16
local SCROLL_CONTENT_TOP_PADDING = LAYOUT.SCROLL_CONTENT_TOP_PADDING or 12
-- Symmetric layout: all panels use same inset; no magic numbers.
local CONTENT_INSET = LAYOUT.CONTENT_INSET or LAYOUT.CARD_GAP or 8
local CONTAINER_INSET = LAYOUT.CONTAINER_INSET or 2
local TEXT_GAP = AFTER_ELEMENT
local BAR_EXTEND_H = 60
local SEARCH_ROW_HEIGHT = 28
local FILTER_ROW_HEIGHT = 24
local SUBTAB_BAR_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
local HEADER_ICON_TEXT_GAP = 12

-- ============================================================================
-- MOUNT SOURCE CLASSIFICATION
-- ============================================================================

-- Anlamca eşleşen, projede kullanıldığı bilinen Blizzard atlas'ları (kategori ile doğrudan ilişkili)
local SOURCE_CATEGORIES = {
    { key = "drop",        label = "Drop",         iconAtlas = "ParagonReputation_Bag" },       -- torba (loot)
    { key = "vendor",      label = "Vendor",        iconAtlas = "coin-gold" },
    { key = "quest",       label = "Quest",         iconAtlas = "quest-legendary-turnin" },
    { key = "achievement", label = "Achievement",   iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "profession",  label = "Profession",    iconAtlas = "poi-workorders" },
    { key = "reputation",  label = "Reputation",    iconAtlas = "MajorFactions_MapIcons_Centaur64" }, -- faction/renown
    { key = "pvp",         label = "PvP",           iconAtlas = "honorsystem-icon-prestige-9" },
    { key = "worldevent",  label = "World Event",   iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = "Promotion",     iconAtlas = "Bonus-Objective-Star" },        -- ödül / yükselme
    { key = "tradingpost", label = "Trading Post",   iconAtlas = "Auctioneer" },
    { key = "treasure",    label = "Treasure",      iconAtlas = "VignetteLoot" },
    { key = "unknown",     label = "Other",         iconAtlas = "poi-town" },                     -- nötr / diğer
}

local SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(SOURCE_CATEGORIES) do
    SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- Pet-specific categories: Pet Battle, Puzzle added; Pet Battle is its own category (not achievement).
local PET_SOURCE_CATEGORIES = {
    { key = "petbattle",   label = (ns.L and ns.L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle", iconAtlas = "WildBattlePetCapturable" },
    { key = "drop",        label = "Drop",         iconAtlas = "ParagonReputation_Bag" },
    { key = "vendor",      label = "Vendor",        iconAtlas = "coin-gold" },
    { key = "quest",       label = "Quest",         iconAtlas = "quest-legendary-turnin" },
    { key = "achievement", label = "Achievement",   iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "profession",  label = "Profession",    iconAtlas = "poi-workorders" },
    { key = "reputation",  label = "Reputation",    iconAtlas = "MajorFactions_MapIcons_Centaur64" },
    { key = "pvp",         label = "PvP",           iconAtlas = "honorsystem-icon-prestige-9" },
    { key = "worldevent",  label = "World Event",   iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = "Promotion",     iconAtlas = "Bonus-Objective-Star" },
    { key = "tradingpost", label = "Trading Post",  iconAtlas = "Auctioneer" },
    { key = "treasure",    label = "Treasure",      iconAtlas = "VignetteLoot" },
    { key = "puzzle",      label = (ns.L and ns.L["SOURCE_TYPE_PUZZLE"]) or "Puzzle", iconAtlas = "UpgradeItem-32x32" },
    { key = "unknown",     label = "Other",         iconAtlas = "poi-town" },
}

local PET_SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(PET_SOURCE_CATEGORIES) do
    PET_SOURCE_CATEGORY_ORDER[cat.key] = i
end

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

-- Classify mount source into exactly one category. Uses Blizzard "Type: detail" format and
-- localized BATTLE_PET_SOURCE_* / L[] so Vendor→Vendor, Drop→Drop with no cross-category leaks.
local function ClassifyMountSource(sourceText)
    if not sourceText or type(sourceText) ~= "string" then return "unknown" end
    local trimmed = sourceText:gsub("|n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return "unknown" end
    -- İlk satır kategoriyi belirler (API "Drop: X|nLocation: Y" dönebilir)
    local firstLine = trimmed:match("^([^\n]+)") or trimmed
    local lower = firstLine:lower()
    local fullLower = trimmed:lower()
    local L = ns.L

    local function startsWith(token)
        if not token or token == "" then return false end
        local t = token:lower()
        return lower:sub(1, #t) == t
    end

    local function contains(token)
        if not token or token == "" then return false end
        return fullLower:find(token:lower(), 1, true) and true or false
    end

    -- 1) Explicit type prefix (Blizzard "Type: Detail")
    local dropLabel = BATTLE_PET_SOURCE_1 or (L and L["SOURCE_TYPE_DROP"]) or "Drop"
    local vendorLabel = BATTLE_PET_SOURCE_3 or (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor"
    local questLabel = BATTLE_PET_SOURCE_2 or (L and L["SOURCE_TYPE_QUEST"]) or "Quest"
    local achievementLabel = BATTLE_PET_SOURCE_6 or (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement"
    local professionLabel = BATTLE_PET_SOURCE_4 or (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession"
    local worldEventLabel = BATTLE_PET_SOURCE_7 or (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event"
    local promotionLabel = BATTLE_PET_SOURCE_8 or (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion"
    local tradingPostLabel = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post"
    local treasureLabel = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure"
    local renownLabel = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown"
    local pvpLabel = (L and L["SOURCE_TYPE_PVP"]) or PVP or "PvP"
    local soldByLabel = (L and L["PARSE_SOLD_BY"]) or "Sold by"
    local locationLabel = (L and L["PARSE_LOCATION"]) or (L and L["LOCATION_LABEL"] and (L["LOCATION_LABEL"]:gsub(":%s*$", ""))) or "Location"
    local zoneLabel = (L and L["PARSE_ZONE"]) or ZONE or "Zone"
    local inGameShopLabel = (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or "In-Game Shop"
    local tradingCardLabel = (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card"
    local petBattleLabel = (L and L["SOURCE_TYPE_PET_BATTLE"]) or "Pet Battle"
    local garrisonLabel = (L and L["PARSE_GARRISON"]) or "Garrison"
    local discoveryLabel = (L and L["PARSE_DISCOVERY"]) or "Discovery"
    local missionLabel = (L and L["PARSE_MISSION"]) or "Mission"
    local paragonLabel = (L and L["PARSE_PARAGON"]) or "Paragon"
    local covenantLabel = (L and L["PARSE_COVENANT"]) or "Covenant"
    local fromAchievementLabel = (L and L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement"

    if startsWith(tradingPostLabel) then return "tradingpost" end
    if startsWith(treasureLabel) then return "treasure" end
    if startsWith(vendorLabel) then return "vendor" end
    if startsWith(questLabel) then return "quest" end
    if startsWith(achievementLabel) or startsWith(fromAchievementLabel) then return "achievement" end
    if startsWith(professionLabel) or contains("crafted") or (L and L["PARSE_CRAFTED"] and contains(L["PARSE_CRAFTED"])) then return "profession" end
    if startsWith(renownLabel) or startsWith(REPUTATION or "Reputation") or contains("reputation") or contains("renown") or contains("faction:") or startsWith(paragonLabel) or startsWith(covenantLabel) then return "reputation" end
    if startsWith(pvpLabel) or contains("pvp") or contains("arena") or contains("rated") or contains("battleground") then return "pvp" end
    if startsWith(worldEventLabel) or contains("world event") or contains("holiday") then return "worldevent" end
    if startsWith(promotionLabel) or startsWith(inGameShopLabel) or startsWith(tradingCardLabel) or contains("promotion") or contains("blizzard shop") or contains("store") then return "promotion" end
    if startsWith(dropLabel) then return "drop" end
    if startsWith(locationLabel) or startsWith(zoneLabel) then return "drop" end
    if startsWith(garrisonLabel) or startsWith(missionLabel) then return "quest" end
    if startsWith(discoveryLabel) then return "treasure" end
    if startsWith(petBattleLabel) then return "achievement" end

    -- 2) Phrase fallbacks
    if contains(soldByLabel) then return "vendor" end
    if contains("dropped by") or contains("contained in") or contains("drop:") then return "drop" end
    if contains("trading post") then return "tradingpost" end
    if contains("treasure") then return "treasure" end
    if contains("quest") then return "quest" end
    if contains("achievement") or contains("from achievement") then return "achievement" end
    if contains("profession") or contains("crafted") then return "profession" end
    if contains("reputation") or contains("renown") or contains("paragon") or contains("covenant") then return "reputation" end
    if contains("pvp") or contains("arena") or contains("battleground") then return "pvp" end
    if contains("world event") or contains("holiday") then return "worldevent" end
    if contains("promotion") or (contains("blizzard") and contains("shop")) or contains("in-game shop") or contains("trading card") then return "promotion" end
    if contains("garrison") or contains("mission") then return "quest" end
    if contains("discovery") then return "treasure" end
    if contains("dungeon") or contains("raid") or contains("world boss") or contains("rare") then return "drop" end

    -- 3) İçerik varsa drop (çoğu sınıflandırılmamış mount drop); sadece boş/Unknown → Other
    if trimmed ~= "" and trimmed ~= "Unknown" then return "drop" end
    return "unknown"
end

-- Classify pet source: Pet Battle, Puzzle as own categories; uses BATTLE_PET_SOURCE_* (Blizzard pet journal).
local function ClassifyPetSource(sourceText)
    if not sourceText or type(sourceText) ~= "string" then return "unknown" end
    local trimmed = sourceText:gsub("|n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return "unknown" end
    local firstLine = trimmed:match("^([^\n]+)") or trimmed
    local lower = firstLine:lower()
    local fullLower = trimmed:lower()
    local L = ns.L

    local function startsWith(token)
        if not token or token == "" then return false end
        local t = token:lower()
        return lower:sub(1, #t) == t
    end

    local function contains(token)
        if not token or token == "" then return false end
        return fullLower:find(token:lower(), 1, true) and true or false
    end

    -- Blizzard BATTLE_PET_SOURCE_* (1=Drop, 2=Quest, 3=Vendor, 4=Profession, 5=Pet Battle, 6=Achievement, 7=World Event, 8=Promotion, 9=Trading Card, 10=In-Game Shop)
    local dropLabel = BATTLE_PET_SOURCE_1 or (L and L["SOURCE_TYPE_DROP"]) or "Drop"
    local questLabel = BATTLE_PET_SOURCE_2 or (L and L["SOURCE_TYPE_QUEST"]) or "Quest"
    local vendorLabel = BATTLE_PET_SOURCE_3 or (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor"
    local professionLabel = BATTLE_PET_SOURCE_4 or (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession"
    local petBattleLabel = BATTLE_PET_SOURCE_5 or (L and L["SOURCE_TYPE_PET_BATTLE"]) or "Pet Battle"
    local achievementLabel = BATTLE_PET_SOURCE_6 or (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement"
    local worldEventLabel = BATTLE_PET_SOURCE_7 or (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event"
    local promotionLabel = BATTLE_PET_SOURCE_8 or (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion"
    local tradingCardLabel = BATTLE_PET_SOURCE_9 or (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card Game"
    local inGameShopLabel = BATTLE_PET_SOURCE_10 or (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or "In-Game Shop"
    local puzzleLabel = (L and L["SOURCE_TYPE_PUZZLE"]) or "Puzzle"
    local tradingPostLabel = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post"
    local treasureLabel = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure"
    local renownLabel = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown"
    local pvpLabel = (L and L["SOURCE_TYPE_PVP"]) or PVP or "PvP"
    local soldByLabel = (L and L["PARSE_SOLD_BY"]) or "Sold by"
    local locationLabel = (L and L["PARSE_LOCATION"]) or (L and L["LOCATION_LABEL"] and (L["LOCATION_LABEL"]:gsub(":%s*$", ""))) or "Location"
    local zoneLabel = (L and L["PARSE_ZONE"]) or ZONE or "Zone"
    local fromAchievementLabel = (L and L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement"
    local paragonLabel = (L and L["PARSE_PARAGON"]) or "Paragon"
    local covenantLabel = (L and L["PARSE_COVENANT"]) or "Covenant"
    local garrisonLabel = (L and L["PARSE_GARRISON"]) or "Garrison"
    local missionLabel = (L and L["PARSE_MISSION"]) or "Mission"
    local discoveryLabel = (L and L["PARSE_DISCOVERY"]) or "Discovery"

    -- 1) Explicit type prefix — Pet Battle FIRST (common for pets)
    if startsWith(petBattleLabel) then return "petbattle" end
    if startsWith(puzzleLabel) then return "puzzle" end
    if startsWith(tradingPostLabel) then return "tradingpost" end
    if startsWith(treasureLabel) then return "treasure" end
    if startsWith(vendorLabel) then return "vendor" end
    if startsWith(questLabel) then return "quest" end
    if startsWith(achievementLabel) or startsWith(fromAchievementLabel) then return "achievement" end
    if startsWith(professionLabel) or contains("crafted") or (L and L["PARSE_CRAFTED"] and contains(L["PARSE_CRAFTED"])) then return "profession" end
    if startsWith(renownLabel) or startsWith(REPUTATION or "Reputation") or contains("reputation") or contains("renown") or contains("faction:") or startsWith(paragonLabel) or startsWith(covenantLabel) then return "reputation" end
    if startsWith(pvpLabel) or contains("pvp") or contains("arena") or contains("rated") or contains("battleground") then return "pvp" end
    if startsWith(worldEventLabel) or contains("world event") or contains("holiday") then return "worldevent" end
    if startsWith(promotionLabel) or startsWith(inGameShopLabel) or startsWith(tradingCardLabel) or contains("promotion") or contains("blizzard shop") or contains("store") then return "promotion" end
    if startsWith(dropLabel) then return "drop" end
    if startsWith(locationLabel) or startsWith(zoneLabel) then return "drop" end
    if startsWith(garrisonLabel) or startsWith(missionLabel) then return "quest" end
    if startsWith(discoveryLabel) then return "treasure" end

    -- 2) Phrase fallbacks — Pet Battle variants (wild, captured, battle pet)
    if contains(petBattleLabel) or contains("pet battle") or contains("wild pet") or contains("captured") or contains("battle pet") or contains("pet battle:") then return "petbattle" end
    if contains(puzzleLabel) then return "puzzle" end
    if contains(soldByLabel) then return "vendor" end
    if contains("dropped by") or contains("contained in") or contains("drop:") then return "drop" end
    if contains("trading post") then return "tradingpost" end
    if contains("treasure") then return "treasure" end
    if contains("quest") then return "quest" end
    if contains("achievement") or contains("from achievement") then return "achievement" end
    if contains("profession") or contains("crafted") then return "profession" end
    if contains("reputation") or contains("renown") or contains("paragon") or contains("covenant") then return "reputation" end
    if contains("pvp") or contains("arena") or contains("battleground") then return "pvp" end
    if contains("world event") or contains("holiday") then return "worldevent" end
    if contains("promotion") or (contains("blizzard") and contains("shop")) or contains("in-game shop") or contains("trading card") then return "promotion" end
    if contains("garrison") or contains("mission") then return "quest" end
    if contains("discovery") then return "treasure" end
    if contains("dungeon") or contains("raid") or contains("world boss") or contains("rare") then return "drop" end

    -- 3) Content exists but unknown → drop (item drops, containers)
    if trimmed ~= "" and trimmed ~= "Unknown" then return "drop" end
    return "unknown"
end

-- Cache for source classification (same source string → same category). Defined after Classify* so they are in scope.
-- Key = sourceText, value = catKey. Cuts ~1000 ClassifyMountSource calls down to ~50–100.
local function ClassifyMountSourceCached(cache, sourceText)
    if not sourceText or type(sourceText) ~= "string" then return "unknown" end
    local c = cache[sourceText]
    if c ~= nil then return c end
    c = ClassifyMountSource(sourceText)
    cache[sourceText] = c
    return c
end
local function ClassifyPetSourceCached(cache, sourceText)
    if not sourceText or type(sourceText) ~= "string" then return "unknown" end
    local c = cache[sourceText]
    if c ~= nil then return c end
    c = ClassifyPetSource(sourceText)
    cache[sourceText] = c
    return c
end

-- Para birimi ikonu (altın); Cost/Amount satırlarında fiyat yanında gösterilir.
local CURRENCY_ICON_GOLD = "|TInterface\\Icons\\INV_Misc_Coin_01:14:14:0:0:64:64:4:60:4:60|t"

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
    for _, key in ipairs(lineStartKeys) do
        if key and key ~= "" and type(key) == "string" then
            blockStartPrefixes[#blockStartPrefixes + 1] = key .. ":"
        end
    end

    local function startsNewBlock(text)
        for _, prefix in ipairs(blockStartPrefixes) do
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
        for _, key in ipairs(lineStartKeys) do
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
        local suffix = (isCostOrAmount and value ~= "") and (" " .. CURRENCY_ICON_GOLD) or ""
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

-- ============================================================================
-- MOUNT LIST (Factory layout: ScrollFrame + SectionHeader + DataRow)
-- ============================================================================

local Factory = ns.UI.Factory
local PADDING = SIDE_MARGIN
local SCROLLBAR_GAP = 22
-- Match Plans: defer sub-tab draw and heavy work by 0.05s for smooth switching.
local COLLECTION_HEAVY_DELAY = 0.05
-- Process this many mounts/pets per frame to avoid 1s freeze (spread over multiple frames).
local RUN_CHUNK_SIZE = 100
-- Same row/header dimensions for all three sub-tabs (Mounts, Pets, Achievements); matches SharedWidgets/UI_SPACING
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 26
local HEADER_HEIGHT = LAYOUT.HEADER_HEIGHT or 32

-- State for Collections tab (must be defined before PopulateMountList/UpdateMountListVisibleRange/DrawMountsContent)
local collectionsState = {
    currentSubTab = "mounts",
    mountListContainer = nil,
    mountListScrollFrame = nil,
    mountListScrollChild = nil,
    petListContainer = nil,
    petListScrollFrame = nil,
    petListScrollChild = nil,
    modelViewer = nil,
    descriptionPanel = nil,
    loadingPanel = nil,
    searchBox = nil,
    contentFrame = nil,
    subTabBar = nil,
    showCollected = true,
    showUncollected = true,
    collapsedHeaders = {},
    collapsedHeadersMounts = {},
    collapsedHeadersPets = {},
    selectedMountID = nil,
    selectedPetID = nil,
    selectedAchievementID = nil,
    achievementListContainer = nil,
    achievementListScrollFrame = nil,
    achievementListScrollChild = nil,
    achievementListScrollBarContainer = nil,
    achievementDetailPanel = nil,
    initialized = false,
}

local _populateMountListBusy = false
local _mountScrollUpdateScheduled = false
local _petScrollUpdateScheduled = false

-- Build flat list for virtual scrolling: [{ type = "header", ... } | { type = "row", ... }], totalHeight
-- Sayılar (Drop 669, Quest 87, vb.) grouped[key] uzunluğundan gelir; liste ile tutarlıdır.
local function BuildFlatMountList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD = COLORS.textDim[1] or 0.55
    local gD = COLORS.textDim[2] or 0.55
    local bD = COLORS.textDim[3] or 0.55
    local countColor = string.format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB = COLORS.textBright[1] or 1
    local gB = COLORS.textBright[2] or 1
    local bB = COLORS.textBright[3] or 1
    local titleColor = string.format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
    local sectionGap = (LAYOUT.betweenSections or LAYOUT.SECTION_SPACING or 8)
    local nCats = #SOURCE_CATEGORIES
    for ci = 1, nCats do
        local catInfo = SOURCE_CATEGORIES[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. catInfo.label .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
                rightStr = countColor .. itemCount .. "|r",
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = HEADER_HEIGHT,
            }
            yOffset = yOffset + HEADER_HEIGHT
            if not isCollapsed then
                local nItems = #items
                for ji = 1, nItems do
                    rowCounter = rowCounter + 1
                    flat[#flat + 1] = { type = "row", mount = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

local function BuildFlatPetList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD = COLORS.textDim[1] or 0.55
    local gD = COLORS.textDim[2] or 0.55
    local bD = COLORS.textDim[3] or 0.55
    local countColor = string.format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB = COLORS.textBright[1] or 1
    local gB = COLORS.textBright[2] or 1
    local bB = COLORS.textBright[3] or 1
    local titleColor = string.format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
    local sectionGap = (LAYOUT.betweenSections or LAYOUT.SECTION_SPACING or 8)
    local nCats = #PET_SOURCE_CATEGORIES
    for ci = 1, nCats do
        local catInfo = PET_SOURCE_CATEGORIES[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. catInfo.label .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
                rightStr = countColor .. itemCount .. "|r",
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = HEADER_HEIGHT,
            }
            yOffset = yOffset + HEADER_HEIGHT
            if not isCollapsed then
                local nItems = #items
                for ji = 1, nItems do
                    rowCounter = rowCounter + 1
                    flat[#flat + 1] = { type = "row", pet = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Achievement grouping: API category hierarchy (GetCategoryList, GetCategoryInfo) — same as Plans.
local function BuildGroupedAchievementData(searchText, showCollected, showUncollected)
    local allCategoryIDs = GetCategoryList and GetCategoryList() or {}
    if #allCategoryIDs == 0 then return {}, {}, 0 end

    local categoryData = {}
    local rootCategories = {}

    for index, categoryID in ipairs(allCategoryIDs) do
        local categoryName, parentCategoryID = GetCategoryInfo(categoryID)
        categoryData[categoryID] = {
            id = categoryID,
            name = categoryName or ((ns.L and ns.L["UNKNOWN_CATEGORY"]) or "Unknown Category"),
            parentID = parentCategoryID,
            children = {},
            achievements = {},
            order = index,
        }
    end

    for _, categoryID in ipairs(allCategoryIDs) do
        local data = categoryData[categoryID]
        if data then
            if data.parentID and data.parentID > 0 then
                if categoryData[data.parentID] then
                    table.insert(categoryData[data.parentID].children, categoryID)
                end
            else
                table.insert(rootCategories, categoryID)
            end
        end
    end

    local allAchievements = (WarbandNexus.GetAllAchievementsData and WarbandNexus:GetAllAchievementsData()) or {}
    local query = (searchText or ""):lower()
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local totalCount = 0

    for i = 1, #allAchievements do
        local a = allAchievements[i]
        if not a or not a.id then
        elseif not ((showC and a.isCollected) or (showU and not a.isCollected)) then
        elseif query ~= "" and (not a.name or not a.name:lower():find(query, 1, true)) then
        else
            local categoryID = a.categoryID
            if not categoryID and GetAchievementCategory then
                categoryID = GetAchievementCategory(a.id)
            end
            if categoryID and categoryData[categoryID] then
                table.insert(categoryData[categoryID].achievements, a)
                totalCount = totalCount + 1
            end
        end
    end

    return categoryData, rootCategories, totalCount
end

-- Build flat list from category hierarchy — birebir Plans DrawAchievementsTable yapısı (max 3 seviye: root > child > grandchild).
-- Child sadece root'un achievement'ı VE child'ı varsa; grandchild sadece child'ın achievement'ı VE child'ı varsa.
local BASE_INDENT = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 15
local SECTION_SPACING = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_SPACING) or (ns.UI_LAYOUT and ns.UI_LAYOUT.betweenSections) or 8
local MINI_SPACING = 4
local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end

local function BuildFlatAchievementList(categoryData, rootCategories, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD, gD, bD = (COLORS.textDim[1] or 0.55), (COLORS.textDim[2] or 0.55), (COLORS.textDim[3] or 0.55)
    local countColor = string.format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB, gB, bB = (COLORS.textBright[1] or 1), (COLORS.textBright[2] or 1), (COLORS.textBright[3] or 1)
    local titleColor = string.format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)

    for _, rootID in ipairs(rootCategories) do
        local rootCat = categoryData[rootID]
        if rootCat then
        local totalAchievements = #rootCat.achievements
        for _, childID in ipairs(rootCat.children or {}) do
            local childCat = categoryData[childID]
            if childCat then
                totalAchievements = totalAchievements + #childCat.achievements
                for _, grandchildID in ipairs(childCat.children or {}) do
                    local gcCat = categoryData[grandchildID]
                    if gcCat then totalAchievements = totalAchievements + #gcCat.achievements end
                end
            end
        end
        if totalAchievements > 0 then
        local rootKey = "achievement_cat_" .. rootID
        -- Default collapsed when first opened (nil -> not expanded)
        local rootExpanded = (collapsedHeaders[rootKey] == false)
        flat[#flat + 1] = {
            type = "header",
            key = rootKey,
            label = titleColor .. (rootCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(totalAchievements) .. ")|r",
            rightStr = countColor .. FormatNumber(totalAchievements) .. "|r",
            isCollapsed = not rootExpanded,
            yOffset = yOffset,
            height = HEADER_HEIGHT,
            indent = 0,
        }
        yOffset = yOffset + HEADER_HEIGHT

        if rootExpanded then
            yOffset = yOffset + MINI_SPACING
            for _, ach in ipairs(rootCat.achievements) do
                rowCounter = rowCounter + 1
                flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT }
                yOffset = yOffset + ROW_HEIGHT
            end
            if #(rootCat.children or {}) > 0 and #rootCat.achievements > 0 then
                yOffset = yOffset + SECTION_SPACING
            end

            for childIdx, childID in ipairs(rootCat.children or {}) do
                local childCat = categoryData[childID]
                if childCat then
                local childAchievementCount = #childCat.achievements
                for _, grandchildID in ipairs(childCat.children or {}) do
                    local gcCat = categoryData[grandchildID]
                    if gcCat then childAchievementCount = childAchievementCount + #gcCat.achievements end
                end
                if childAchievementCount > 0 then
                local childKey = "achievement_cat_" .. childID
                local childExpanded = (collapsedHeaders[childKey] == false)
                flat[#flat + 1] = {
                    type = "header",
                    key = childKey,
                    label = titleColor .. (childCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(childAchievementCount) .. ")|r",
                    rightStr = countColor .. FormatNumber(childAchievementCount) .. "|r",
                    isCollapsed = not childExpanded,
                    yOffset = yOffset,
                    height = HEADER_HEIGHT,
                    indent = BASE_INDENT,
                }
                yOffset = yOffset + HEADER_HEIGHT

                if childExpanded then
                    yOffset = yOffset + MINI_SPACING
                    for _, ach in ipairs(childCat.achievements) do
                        rowCounter = rowCounter + 1
                        flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT * 2 }
                        yOffset = yOffset + ROW_HEIGHT
                    end
                    if #(childCat.children or {}) > 0 and #childCat.achievements > 0 then
                        yOffset = yOffset + SECTION_SPACING
                    end

                    for grandchildIdx, grandchildID in ipairs(childCat.children or {}) do
                        local grandchildCat = categoryData[grandchildID]
                        if grandchildCat and #grandchildCat.achievements > 0 then
                        local gcKey = "achievement_cat_" .. grandchildID
                        local gcExpanded = (collapsedHeaders[gcKey] == false)
                        flat[#flat + 1] = {
                            type = "header",
                            key = gcKey,
                            label = titleColor .. (grandchildCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(#grandchildCat.achievements) .. ")|r",
                            rightStr = countColor .. FormatNumber(#grandchildCat.achievements) .. "|r",
                            isCollapsed = not gcExpanded,
                            yOffset = yOffset,
                            height = HEADER_HEIGHT,
                            indent = BASE_INDENT * 2,
                        }
                        yOffset = yOffset + HEADER_HEIGHT

                        if gcExpanded then
                            yOffset = yOffset + MINI_SPACING
                            for _, ach in ipairs(grandchildCat.achievements) do
                                rowCounter = rowCounter + 1
                                flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT * 3 }
                                yOffset = yOffset + ROW_HEIGHT
                            end
                        end
                        if grandchildIdx < #(childCat.children or {}) then
                            yOffset = yOffset + SECTION_SPACING
                        end
                        end
                    end
                end
                if childIdx < #(rootCat.children or {}) then
                    yOffset = yOffset + SECTION_SPACING
                end
                end
                end
            end
        end
        yOffset = yOffset + SECTION_SPACING
        end
        end
    end

    return flat, math.max(yOffset + PADDING, 1)
end

-- Shared row pool for all three collection lists (Mounts, Pets, Achievements). Row structure from SharedWidgets.
local CollectionRowPool = {}
local COLLECTED_COLOR = "|cff33e533"
local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"
local DEFAULT_ICON_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

-- Acquire a collection list row (SharedWidgets layout: status icon + icon + label). Used by Mounts, Pets, Achievements.
local function AcquireCollectionRow(scrollChild, item, leftIndent, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn)
    local f = table.remove(CollectionRowPool)
    if not f then
        f = Factory:CreateCollectionListRow(scrollChild, ROW_HEIGHT)
        f:ClearAllPoints()
    end
    f:SetParent(scrollChild)
    f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", leftIndent or 0, -(item.yOffset or 0))
    f:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    f:SetHeight(ROW_HEIGHT)
    local onClick
    if onSelect or refreshFn then
        onClick = function()
            if onSelect then onSelect() end
            if refreshFn then refreshFn() end
        end
    end
    Factory:ApplyCollectionListRowContent(f, item.rowIndex, iconPath, labelText, isCollected, (selectedID == itemID), onClick)
    f:Show()
    return f
end

local function AcquireMountRow(scrollChild, listWidth, item, selectedMountID, onSelectMount, redraw, cf)
    local mount = item.mount
    local nameColor = mount.isCollected and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (mount.name or "") .. "|r"
    return AcquireCollectionRow(scrollChild, item, 0, mount.icon or DEFAULT_ICON_MOUNT, labelText, mount.isCollected, selectedMountID, mount.id, function()
        if onSelectMount then
            onSelectMount(mount.id, mount.name, mount.icon, mount.source, mount.creatureDisplayID, mount.description, mount.isCollected)
        end
    end, function()
        if collectionsState._mountFlatList and collectionsState.mountListScrollFrame then
            collectionsState._mountListSelectedID = mount.id
            local r = collectionsState._mountListRefreshVisible
            if r then r() end
        end
    end)
end

local function AcquirePetRow(scrollChild, listWidth, item, selectedPetID, onSelectPet, redraw, cf)
    local pet = item.pet
    local nameColor = pet.isCollected and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (pet.name or "") .. "|r"
    return AcquireCollectionRow(scrollChild, item, 0, pet.icon or DEFAULT_ICON_PET, labelText, pet.isCollected, selectedPetID, pet.id, function()
        if onSelectPet then
            onSelectPet(pet.id, pet.name, pet.icon, pet.source, pet.creatureDisplayID, pet.description, pet.isCollected)
        end
    end, function()
        if collectionsState._petFlatList and collectionsState.petListScrollFrame then
            collectionsState._petListSelectedID = pet.id
            local r = collectionsState._petListRefreshVisible
            if r then r() end
        end
    end)
end

local function AcquireAchievementRow(scrollChild, listWidth, item, selectedAchievementID, onSelectAchievement, redraw, cf)
    local ach = item.achievement
    local nameColor = ach.isCollected and COLLECTED_COLOR or "|cffffffff"
    local pointsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
    local labelText = nameColor .. (ach.name or "") .. "|r" .. pointsStr
    local indent = item.indent or 0
    return AcquireCollectionRow(scrollChild, item, indent, ach.icon or DEFAULT_ICON_ACHIEVEMENT, labelText, ach.isCollected, selectedAchievementID, ach.id, function()
        if onSelectAchievement then onSelectAchievement(ach) end
    end, function()
        if collectionsState._achFlatList and collectionsState.achievementListScrollFrame then
            collectionsState._achListSelectedID = ach.id
            local r = collectionsState._achListRefreshVisible
            if r then r() end
        end
    end)
end

-- Update visible row frames only (virtual scroll). Headers are created in PopulateMountList.
local function UpdateMountListVisibleRange()
    local state = collectionsState
    local flatList = state._mountFlatList
    local scrollFrame = state.mountListScrollFrame
    local scrollChild = state.mountListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._mountVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._mountVisibleRowFrames = {}
    local redraw = state._mountListRedrawFn
    local cf = state._mountListContentFrame
    local selectedMountID = state._mountListSelectedID or state.selectedMountID
    local onSelectMount = state._mountListOnSelectMount
    local listWidth = state._mountListWidth or scrollChild:GetWidth()
    local n = #flatList
    local startIdx, endIdx = 1, n
    for i = 1, n do
        local it = flatList[i]
        if startIdx == 1 and it.yOffset + it.height > scrollTop then startIdx = i end
        if it.yOffset < bottom then endIdx = i else break end
    end
    local tinsert = table.insert
    for i = startIdx, endIdx do
        local it = flatList[i]
        if it.type == "row" then
            local frame = AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
            tinsert(state._mountVisibleRowFrames, { frame = frame, flatIndex = i })
        end
    end
end

-- Populate scrollChild: build flat list, create headers only, set height; visible rows updated by UpdateMountListVisibleRange (virtual scroll).
-- contentFrameForRefresh, redrawFn: redrawFn(contentFrame) is called on next frame for refresh; pass same DrawMountsContent from caller so closure sees it.
local function PopulateMountList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populateMountListBusy then return end
    _populateMountListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    -- Release any visible row frames back to pool before clearing
    local visible = collectionsState._mountVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._mountVisibleRowFrames = {}
    end

    -- Clear existing children (headers from previous run); unparent to avoid accumulating on re-populate
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatMountList(groupedData, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    -- Create collapsible headers (Plans-style factory); rows are virtualized in UpdateMountListVisibleRange
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local function onToggle(expanded)
                collapsedHeaders[key] = not expanded
                local cached = collectionsState._lastGroupedMountData
                local sch = collectionsState.mountListScrollChild
                if cached and sch and cf and cf:IsVisible() then
                    PopulateMountList(sch, listWidth, cached, collapsedHeaders, selectedMountID, onSelectMount, cf, redraw)
                    if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                        Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
                    end
                elseif redraw and cf and cf:IsVisible() then
                    redraw(cf)
                end
            end
            local header = CreateCollapsibleHeader(scrollChild, it.label, key, not it.isCollapsed, onToggle, GetMountCategoryIcon(key), true, 0)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -it.yOffset)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)
        end
    end

    -- Store state for virtual scroll callback (refreshVisible: row tıklanınca sadece seçim vurgusunu günceller)
    collectionsState._mountFlatList = flatList
    collectionsState._mountFlatListTotalHeight = totalHeight
    collectionsState._mountListWidth = listWidth
    collectionsState._mountListSelectedID = selectedMountID
    collectionsState._mountListOnSelectMount = onSelectMount
    collectionsState._mountListCollapsedHeaders = collapsedHeaders
    collectionsState._mountListRedrawFn = redraw
    collectionsState._mountListContentFrame = cf
    collectionsState._mountListRefreshVisible = UpdateMountListVisibleRange

    local scrollFrame = collectionsState.mountListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            if _mountScrollUpdateScheduled then return end
            _mountScrollUpdateScheduled = true
            C_Timer.After(0, function()
                _mountScrollUpdateScheduled = false
                UpdateMountListVisibleRange()
            end)
        end)
    end
    -- Defer row creation to next frame to reduce FPS spike when switching to Mounts
    C_Timer.After(0, UpdateMountListVisibleRange)
    _populateMountListBusy = false
end

local _populatePetListBusy = false

local function UpdatePetListVisibleRange()
    local state = collectionsState
    local flatList = state._petFlatList
    local scrollFrame = state.petListScrollFrame
    local scrollChild = state.petListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._petVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._petVisibleRowFrames = {}
    local redraw = state._petListRedrawFn
    local cf = state._petListContentFrame
    local selectedPetID = state._petListSelectedID or state.selectedPetID
    local onSelectPet = state._petListOnSelectPet
    local listWidth = state._petListWidth or scrollChild:GetWidth()
    local n = #flatList
    local startIdx, endIdx = 1, n
    for i = 1, n do
        local it = flatList[i]
        if startIdx == 1 and it.yOffset + it.height > scrollTop then startIdx = i end
        if it.yOffset < bottom then endIdx = i else break end
    end
    local tinsert = table.insert
    for i = startIdx, endIdx do
        local it = flatList[i]
        if it.type == "row" then
            local frame = AcquirePetRow(scrollChild, listWidth, it, selectedPetID, onSelectPet, redraw, cf)
            tinsert(state._petVisibleRowFrames, { frame = frame, flatIndex = i })
        end
    end
end

local function PopulatePetList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populatePetListBusy then return end
    _populatePetListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    local visible = collectionsState._petVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._petVisibleRowFrames = {}
    end

    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatPetList(groupedData, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    -- Create collapsible headers (Plans-style factory)
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local function onToggle(expanded)
                collapsedHeaders[key] = not expanded
                local cached = collectionsState._lastGroupedPetData
                local sch = collectionsState.petListScrollChild
                if cached and sch and cf and cf:IsVisible() then
                    PopulatePetList(sch, listWidth, cached, collapsedHeaders, selectedPetID, onSelectPet, cf, redraw)
                    if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                        Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
                    end
                elseif redraw and cf and cf:IsVisible() then
                    redraw(cf)
                end
            end
            local header = CreateCollapsibleHeader(scrollChild, it.label, key, not it.isCollapsed, onToggle, GetPetCategoryIcon(key), true, 0)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -it.yOffset)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)
        end
    end

    collectionsState._petFlatList = flatList
    collectionsState._petFlatListTotalHeight = totalHeight
    collectionsState._petListWidth = listWidth
    collectionsState._petListSelectedID = selectedPetID
    collectionsState._petListOnSelectPet = onSelectPet
    collectionsState._petListCollapsedHeaders = collapsedHeaders
    collectionsState._petListRedrawFn = redraw
    collectionsState._petListContentFrame = cf
    collectionsState._petListRefreshVisible = UpdatePetListVisibleRange

    local scrollFrame = collectionsState.petListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            if _petScrollUpdateScheduled then return end
            _petScrollUpdateScheduled = true
            C_Timer.After(0, function()
                _petScrollUpdateScheduled = false
                UpdatePetListVisibleRange()
            end)
        end)
    end
    -- Defer row creation to next frame to reduce FPS spike when switching to Pets
    C_Timer.After(0, UpdatePetListVisibleRange)
    _populatePetListBusy = false
end

local _populateAchievementListBusy = false

local function UpdateAchievementListVisibleRange()
    local state = collectionsState
    local flatList = state._achFlatList
    local scrollFrame = state.achievementListScrollFrame
    local scrollChild = state.achievementListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._achVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._achVisibleRowFrames = {}
    local cf = state._achListContentFrame
    local selectedID = state._achListSelectedID or state.selectedAchievementID
    local onSelect = state._achListOnSelect
    local listWidth = state._achListWidth or scrollChild:GetWidth()
    local startIdx, endIdx = 1, #flatList
    for i = 1, #flatList do
        local it = flatList[i]
        if it.yOffset + it.height > scrollTop and startIdx == 1 then startIdx = i end
        if it.yOffset < bottom then endIdx = i end
    end
    for i = startIdx, endIdx do
        local it = flatList[i]
        if it.type == "row" then
            local frame = AcquireAchievementRow(scrollChild, listWidth, it, selectedID, onSelect, nil, cf)
            state._achVisibleRowFrames[#state._achVisibleRowFrames + 1] = { frame = frame, flatIndex = i }
        end
    end
end

local function PopulateAchievementList(scrollChild, listWidth, categoryData, rootCategories, collapsedHeaders, selectedAchievementID, onSelectAchievement, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populateAchievementListBusy then return end
    _populateAchievementListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    local visible = collectionsState._achVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._achVisibleRowFrames = {}
    end

    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatAchievementList(categoryData, rootCategories, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    -- Create collapsible headers (Plans-style factory; indent for hierarchy)
    local achBaseIndent = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 15
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local indentPx = it.indent or 0
            local indentLevel = (indentPx > 0 and math.floor(indentPx / achBaseIndent)) or 0
            local function onToggle(expanded)
                collapsedHeaders[key] = not expanded
                local cachedCat = collectionsState._lastAchievementCategoryData
                local cachedRoot = collectionsState._lastAchievementRootCategories
                local achScrollChild = collectionsState.achievementListScrollChild
                if cachedCat and cachedRoot and achScrollChild and cf and cf:IsVisible() then
                    PopulateAchievementList(achScrollChild, listWidth, cachedCat, cachedRoot, collapsedHeaders, selectedAchievementID, onSelectAchievement, cf, redraw)
                elseif redraw and cf and cf:IsVisible() then
                    redraw(cf)
                end
            end
            local header = CreateCollapsibleHeader(scrollChild, it.label, key, not it.isCollapsed, onToggle, "UI-Achievement-Shield-NoPoints", true, indentLevel)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indentPx, -it.yOffset)
            header:SetWidth(listWidth - indentPx)
            header:SetHeight(it.height)
        end
    end

    collectionsState._achFlatList = flatList
    collectionsState._achFlatListTotalHeight = totalHeight
    collectionsState._achListWidth = listWidth
    collectionsState._achListSelectedID = selectedAchievementID
    collectionsState._achListOnSelect = onSelectAchievement
    collectionsState._achListCollapsedHeaders = collapsedHeaders
    collectionsState._achListContentFrame = cf
    collectionsState._achListRefreshVisible = UpdateAchievementListVisibleRange

    local scrollFrame = collectionsState.achievementListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            UpdateAchievementListVisibleRange()
        end)
    end
    -- Defer row creation to next frame to reduce FPS spike when opening Achievements list
    C_Timer.After(0, UpdateAchievementListVisibleRange)
    _populateAchievementListBusy = false
end

-- ============================================================================
-- MODEL VIEWER PANEL — Sabit, merkezde, Mount Journal gibi. Tek kural: hep ortada, sabit uzaklık.
-- ============================================================================

local FIXED_CAM_SCALE = 1.8
local CAM_SCALE_MIN = 0.6
local CAM_SCALE_MAX = 6
local ZOOM_STEP = 0.1
local ROTATE_SENSITIVITY = 0.02
-- Tüm modeller aynı boyut/pozisyon: modeli REFERENCE_RADIUS'a scale ediyoruz, tek sabit kamera mesafesi.
local REFERENCE_RADIUS = 1.0
local FIXED_CAM_DISTANCE = 2.8
local MODEL_SCALE_MIN = 0.15
local MODEL_SCALE_MAX = 6.0
local ZOOM_MULTIPLIER_MIN = 0.5
local ZOOM_MULTIPLIER_MAX = 2.0
local RADIUS_POLL_MAX_TIME = 1.0
local RADIUS_POLL_INTERVAL = 0.05

-- Model yüklendikten sonra geçerli yarıçap döner; bazen async yüklemede gecikme olur, pcall ile güvenli.
local function GetModelRadiusSafe(m)
    if not m or not m.GetModelRadius then return nil end
    local ok, r = pcall(m.GetModelRadius, m)
    if not ok or type(r) ~= "number" or r <= 0 then return nil end
    return r
end

-- Mount API helpers — CreateModelViewer closure'ları bunlara ihtiyaç duyduğu için burada tanımlı.
local function SafeGetMountCollected(mountID)
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return false end
    local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    if issecretvalue and collected and issecretvalue(collected) then
        return false
    end
    return collected == true
end

local function SafeGetMountInfoExtra(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then
        return nil, "", "", nil
    end
    local displayID, description, source, _, _, uiModelSceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
    if issecretvalue and displayID and issecretvalue(displayID) then displayID = nil end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and uiModelSceneID and issecretvalue(uiModelSceneID) then uiModelSceneID = nil end
    return displayID, description or "", source or "", uiModelSceneID
end

-- Pet API helpers — same pattern as mounts.
local function SafeGetPetCollected(speciesID)
    if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return false end
    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
    if issecretvalue and numCollected and issecretvalue(numCollected) then
        return false
    end
    return numCollected and numCollected > 0
end

local function SafeGetPetInfoExtra(speciesID)
    if not speciesID or not C_PetJournal then return nil, "", "" end
    local creatureDisplayID = nil
    if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
        local numDisplays = C_PetJournal.GetNumDisplays(speciesID) or 0
        if numDisplays > 0 then
            creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
        end
    end
    if issecretvalue and creatureDisplayID and issecretvalue(creatureDisplayID) then creatureDisplayID = nil end
    local name, icon, _, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    return creatureDisplayID, description or "", source or ""
end

local function CreateModelViewer(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})

    local model = CreateFrame("PlayerModel", nil, panel)
    model:SetModelDrawLayer("ARTWORK")
    model:SetFrameLevel(panel:GetFrameLevel())
    model:EnableMouse(true)
    model:EnableMouseWheel(true)

    -- Model area starts directly below the text block (panel.descText); re-run after text set or resize.
    local MODEL_FALLBACK_TOP_RATIO = 0.42
    local function UpdateModelFrameSize()
        local w = panel:GetWidth()
        local h = panel:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        model:ClearAllPoints()
        local descBottom = nil
        if panel.descText and panel.descText.GetBottom then
            descBottom = panel.descText:GetBottom()
        end
        local panelTop = panel:GetTop()
        if descBottom and panelTop and panel:IsVisible() then
            local offsetY = descBottom - panelTop
            if offsetY < -20 then
                model:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_INSET, offsetY - TEXT_GAP)
                model:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CONTENT_INSET, offsetY - TEXT_GAP)
                model:SetPoint("BOTTOM", panel, "BOTTOM", 0, CONTENT_INSET)
            else
                model:SetPoint("TOP", panel, "TOP", 0, -h * MODEL_FALLBACK_TOP_RATIO - TEXT_GAP)
                model:SetPoint("BOTTOM", panel, "BOTTOM", 0, CONTENT_INSET)
                model:SetPoint("LEFT", panel, "LEFT", CONTENT_INSET, 0)
                model:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_INSET, 0)
            end
        else
            model:SetPoint("TOP", panel, "TOP", 0, -h * MODEL_FALLBACK_TOP_RATIO - TEXT_GAP)
            model:SetPoint("BOTTOM", panel, "BOTTOM", 0, CONTENT_INSET)
            model:SetPoint("LEFT", panel, "LEFT", CONTENT_INSET, 0)
            model:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_INSET, 0)
        end
    end
    panel.UpdateModelFrameSize = UpdateModelFrameSize
    panel:SetScript("OnSizeChanged", function()
        UpdateModelFrameSize()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UpdateModelFrameSize() end)
        end
    end)
    UpdateModelFrameSize()

    panel.modelRotation = 0
    panel.camScale = FIXED_CAM_SCALE
    panel.normalizedRadius = false
    panel.modelScale = 1.0
    panel.zoomMultiplier = 1.0

    -- Tek kural: merkez (0,0,0), UseModelCenterToTransform. Model boyutu SetModelScale ile normalize edildiyse sabit kamera mesafesi.
    local function ApplyTransform()
        model:SetPosition(0, 0, 0)
        if model.UseModelCenterToTransform then model:UseModelCenterToTransform(true) end
        model:SetFacing(panel.modelRotation)
        if model.SetPortraitZoom then model:SetPortraitZoom(0) end
        if panel.normalizedRadius then
            if model.SetModelScale then model:SetModelScale(panel.modelScale) end
            if model.SetCameraDistance then
                -- Scale camera with model so large-scale models (e.g. Ashes of Belo'ren) are not zoomed in.
                local camDist = FIXED_CAM_DISTANCE * panel.zoomMultiplier * panel.modelScale
                model:SetCameraDistance(math.max(0.1, camDist))
            end
        else
            if model.SetCamDistanceScale then model:SetCamDistanceScale(panel.camScale) end
        end
        if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
    end

    -- Sol tık basılı tutunca: döndür
    model:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local x = GetCursorPosition()
        local s = model:GetEffectiveScale()
        if s and s > 0 then x = x / s end
        panel._dragCursorX = x
        panel._dragRotation = panel.modelRotation
    end)
    model:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then panel._dragCursorX = nil end
    end)
    model:SetScript("OnUpdate", function()
        if panel._dragCursorX == nil then return end
        if not IsMouseButtonDown("LeftButton") then
            panel._dragCursorX = nil
            return
        end
        local x = GetCursorPosition()
        local s = model:GetEffectiveScale()
        if s and s > 0 then x = x / s end
        local dx = x - panel._dragCursorX
        panel._dragCursorX = x
        panel.modelRotation = (panel._dragRotation or 0) - dx * ROTATE_SENSITIVITY
        panel._dragRotation = panel.modelRotation
        model:SetFacing(panel.modelRotation)
        model:SetPosition(0, 0, 0)
    end)
    -- Tekerlek: zoom (normalize modunda zoomMultiplier, yoksa camScale)
    model:SetScript("OnMouseWheel", function(_, delta)
        if panel.normalizedRadius then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
        else
            local v = panel.camScale + (delta > 0 and -ZOOM_STEP or ZOOM_STEP)
            if v < CAM_SCALE_MIN then v = CAM_SCALE_MIN elseif v > CAM_SCALE_MAX then v = CAM_SCALE_MAX end
            panel.camScale = v
        end
        ApplyTransform()
    end)

    -- Text on top of model: overlay frame with higher frame level so text is always in front.
    local textOverlay = CreateFrame("Frame", nil, panel)
    textOverlay:SetFrameLevel(panel:GetFrameLevel() + 10)
    textOverlay:SetAllPoints(panel)
    textOverlay:EnableMouse(false)
    panel.textOverlay = textOverlay

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local whiteR, whiteG, whiteB = 1, 1, 1

    local nameText = FontManager:CreateFontString(textOverlay, "title", "OVERLAY")
    nameText:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    nameText:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    nameText:SetTextColor(whiteR, whiteG, whiteB)
    panel.nameText = nameText

    local sourceContainer = CreateFrame("Frame", nil, textOverlay)
    sourceContainer:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceContainer:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceContainer:SetHeight(1)
    panel.sourceContainer = sourceContainer
    panel.sourceLines = {}

    local sourceLabel = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    sourceLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceLabel:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetWordWrap(true)
    sourceLabel:SetNonSpaceWrap(false)
    sourceLabel:SetTextColor(whiteR, whiteG, whiteB)
    panel.sourceLabel = sourceLabel

    local descText = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
    descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(whiteR, whiteG, whiteB)
    panel.descText = descText

    local collectedBadge = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    collectedBadge:SetPoint("BOTTOMLEFT", textOverlay, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET)
    collectedBadge:SetPoint("RIGHT", textOverlay, "RIGHT", -CONTENT_INSET, 0)
    collectedBadge:SetJustifyH("LEFT")
    collectedBadge:Hide()
    panel.collectedBadge = collectedBadge

    panel.model = model

    panel:SetScript("OnShow", function()
        local cid = panel._lastCreatureDisplayID
        if cid and cid > 0 and model.SetDisplayInfo then
            model:ClearModel()
            model:SetDisplayInfo(cid)
            ApplyTransform()
        end
    end)

    function panel:SetMount(mountID, creatureDisplayIDFromCache)
        if not mountID then
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            return
        end
        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = SafeGetMountInfoExtra(mountID)
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = false
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            -- Modeli REFERENCE_RADIUS'a scale et → tek sabit kamera; tüm mount'lar aynı boyut/pozisyon. GetModelRadius geç dönebilir, 1 sn boyunca aralıklı dene.
            local function tryApplyRadiusNormalize()
                if panel._lastCreatureDisplayID ~= creatureDisplayID then return end
                local r = GetModelRadiusSafe(model)
                if not r or r <= 0 or not model.SetModelScale or not model.SetCameraDistance then return end
                local scale = REFERENCE_RADIUS / r
                if scale < MODEL_SCALE_MIN then scale = MODEL_SCALE_MIN elseif scale > MODEL_SCALE_MAX then scale = MODEL_SCALE_MAX end
                panel.normalizedRadius = true
                panel.modelScale = scale
                panel.zoomMultiplier = 1.0
                ApplyTransform()
            end
            local t = 0
            while t <= RADIUS_POLL_MAX_TIME do
                C_Timer.After(t, tryApplyRadiusNormalize)
                t = t + RADIUS_POLL_INTERVAL
            end
        else
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            panel.normalizedRadius = false
        end
    end

    function panel:SetPet(speciesID, creatureDisplayIDFromCache)
        if not speciesID then
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            return
        end
        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = select(1, SafeGetPetInfoExtra(speciesID))
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastPetID = speciesID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = false
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            local function tryApplyRadiusNormalize()
                if panel._lastCreatureDisplayID ~= creatureDisplayID then return end
                local r = GetModelRadiusSafe(model)
                if not r or r <= 0 or not model.SetModelScale or not model.SetCameraDistance then return end
                local scale = REFERENCE_RADIUS / r
                if scale < MODEL_SCALE_MIN then scale = MODEL_SCALE_MIN elseif scale > MODEL_SCALE_MAX then scale = MODEL_SCALE_MAX end
                panel.normalizedRadius = true
                panel.modelScale = scale
                panel.zoomMultiplier = 1.0
                ApplyTransform()
            end
            local t = 0
            while t <= RADIUS_POLL_MAX_TIME do
                C_Timer.After(t, tryApplyRadiusNormalize)
                t = t + RADIUS_POLL_INTERVAL
            end
        else
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            panel.normalizedRadius = false
        end
    end

    function panel:SetMountInfo(mountID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not mountID then
            nameText:SetText("")
            sourceLabel:SetText("")
            for _, line in ipairs(panel.sourceLines) do
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            return
        end
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = string.format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r")
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = SafeGetMountInfoExtra(mountID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = StripWoWFormatCodes(source)
            description = StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        -- Cost/Amount satırlarına para birimi ikonu (satın alma)
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        -- API satırları: "Label: Value" ise etiket (Drop, Zone, Location vb.) sarı, değer beyaz
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. CURRENCY_ICON_GOLD) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. CURRENCY_ICON_GOLD) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
        descText:SetPoint("TOPRIGHT", lastAnchor, "BOTTOMRIGHT", 0, lastY)

        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        -- API'den gelen description olduğu gibi, beyaz
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")
        local isCollected = isCollectedFromCache
        if isCollected == nil and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
            if issecretvalue and collected and issecretvalue(collected) then
                isCollected = false
            else
                isCollected = collected == true
            end
        end
        if isCollected then
            local s = (ns.L and ns.L["STATUS_COLLECTED"]) or "Collected"
            if s == "STATUS_COLLECTED" then s = "Collected" end
            collectedBadge:SetText("|cff00ff00" .. s .. "|r")
        else
            local s = (ns.L and ns.L["STATUS_NOT_COLLECTED"]) or "Not Collected"
            if s == "STATUS_NOT_COLLECTED" then s = "Not Collected" end
            collectedBadge:SetText("|cffff4444" .. s .. "|r")
        end
        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    function panel:SetPetInfo(speciesID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not speciesID then
            nameText:SetText("")
            sourceLabel:SetText("")
            for _, line in ipairs(panel.sourceLines) do
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            return
        end
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = string.format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r")
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = SafeGetPetInfoExtra(speciesID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = StripWoWFormatCodes(source)
            description = StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. CURRENCY_ICON_GOLD) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. CURRENCY_ICON_GOLD) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
        descText:SetPoint("TOPRIGHT", lastAnchor, "BOTTOMRIGHT", 0, lastY)
        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")
        local isCollected = isCollectedFromCache
        if isCollected == nil then
            isCollected = SafeGetPetCollected(speciesID)
        end
        if isCollected then
            local s = (ns.L and ns.L["STATUS_COLLECTED"]) or "Collected"
            if s == "STATUS_COLLECTED" then s = "Collected" end
            collectedBadge:SetText("|cff00ff00" .. s .. "|r")
        else
            local s = (ns.L and ns.L["STATUS_NOT_COLLECTED"]) or "Not Collected"
            if s == "STATUS_NOT_COLLECTED" then s = "Not Collected" end
            collectedBadge:SetText("|cffff4444" .. s .. "|r")
        end
        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    return panel
end

-- ============================================================================
-- DESCRIPTION PANEL (standalone; used only if we need separate panel elsewhere)
-- ============================================================================

local function CreateDescriptionPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    function panel:SetMountInfo() end
    return panel
end

-- ============================================================================
-- LOADING STATE PANEL
-- ============================================================================

local function CreateLoadingPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)

    local spinner = FontManager:CreateFontString(panel, "header", "OVERLAY")
    spinner:SetPoint("CENTER", 0, CONTENT_INSET)
    spinner:SetText("|cff9370DB" .. ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...") .. "|r")

    local progressText = FontManager:CreateFontString(panel, "body", "OVERLAY")
    progressText:SetPoint("CENTER", 0, -CONTENT_INSET)
    progressText:SetTextColor(0.7, 0.7, 0.7)
    panel.progressText = progressText

    local barBg = panel:CreateTexture(nil, "ARTWORK")
    barBg:SetHeight(4)
    barBg:SetPoint("TOPLEFT", progressText, "BOTTOMLEFT", -BAR_EXTEND_H, -CONTENT_INSET)
    barBg:SetPoint("TOPRIGHT", progressText, "BOTTOMRIGHT", BAR_EXTEND_H, -CONTENT_INSET)
    barBg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local barFill = panel:CreateTexture(nil, "OVERLAY")
    barFill:SetHeight(4)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetWidth(1)
    barFill:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    panel.barFill = barFill
    panel.barBg = barBg

    function panel:UpdateProgress(progress, stage)
        local pct = math.min(100, math.max(0, progress or 0))
        progressText:SetText(string.format("%d%% - %s", pct, stage or ""))
        local barWidth = barBg:GetWidth()
        if barWidth and barWidth > 0 then
            barFill:SetWidth(math.max(1, barWidth * (pct / 100)))
        end
    end

    return panel
end

-- ============================================================================
-- ACHIEVEMENT DETAIL PANEL — Parent/Children, Description, Criteria (replaces model viewer)
-- ============================================================================
-- Same status icons as Plans/PlansTracker: green tick and red cross for all achievement UIs
local ACHIEVEMENT_ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ACHIEVEMENT_ICON_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

-- Build full achievement series (e.g. Level 10, 20, 30... 80): walk to root via GetPreviousAchievement, then collect all via GetSupercedingAchievements.
-- Returns ordered array of achievement IDs from first tier to last; length >= 1 when achievement is part of a chain.
local function BuildAchievementSeries(achievementID)
    if not achievementID or achievementID <= 0 then return {} end
    local GetPrev = GetPreviousAchievement
    local GetSuperceding = (C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements) or function() return {} end
    if not GetPrev then return { achievementID } end
    local id = achievementID
    while true do
        local prev = GetPrev(id)
        if not prev or prev <= 0 then break end
        id = prev
    end
    local series = { id }
    local idx = 1
    while true do
        local nextIds = GetSuperceding(series[idx])
        if not nextIds or #nextIds == 0 then break end
        series[idx + 1] = nextIds[1]
        idx = idx + 1
    end
    return series
end

local function CreateAchievementDetailPanel(parent, width, height, onSelectAchievement)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
    scroll:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(width - (CONTAINER_INSET * 2) - 24)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local content = child
    local lastAnchor = content
    local lastPoint = "TOPLEFT"
    local lastY = 0
    local TEXT_GAP_LINE = TEXT_GAP

    panel._detailElements = {}

    local function clearDetailElements()
        for _, el in ipairs(panel._detailElements) do
            el:Hide()
            el:SetParent(nil)
        end
        panel._detailElements = {}
    end

    local function addDetailElement(el)
        if el then
            panel._detailElements[#panel._detailElements + 1] = el
        end
    end

    -- Satır başı boşluğu (Plans sekmesi ile uyumlu)
    local SECTION_BODY_INDENT = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 12
    local CRITERIA_TEXT_INDENT = SECTION_BODY_INDENT

    local function addSection(title, fn)
        local titleFs = FontManager:CreateFontString(content, "title", "OVERLAY")
        titleFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
        titleFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, lastY)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(true)
        titleFs:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        titleFs:SetText(title or "")
        addDetailElement(titleFs)
        lastAnchor = titleFs
        lastPoint = "BOTTOMLEFT"
        lastY = -TEXT_GAP_LINE
        fn(titleFs)
    end

    local function addAchievementRow(ach, label)
        if not ach or not ach.id then return end
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, lastY)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        if ApplyVisuals then
            ApplyVisuals(row, {0.06, 0.06, 0.08, 0.5}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
        end
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        icon:SetPoint("LEFT", PADDING, 0)
        icon:SetTexture(ach.icon or "Interface\\Icons\\Achievement_General")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local statusIcon = row:CreateTexture(nil, "ARTWORK")
        statusIcon:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
        statusIcon:SetPoint("LEFT", icon, "RIGHT", CONTENT_INSET / 2, 0)
        statusIcon:SetTexture(ach.isCollected and ACHIEVEMENT_ICON_READY or ACHIEVEMENT_ICON_NOT_READY)
        local nameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
        nameFs:SetPoint("LEFT", statusIcon, "RIGHT", CONTENT_INSET, 0)
        nameFs:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        local ptsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
        nameFs:SetText((ach.name or "") .. ptsStr)
        row:SetScript("OnMouseDown", function()
            if onSelectAchievement then onSelectAchievement(ach) end
            if ach.id and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, ach.id)
            end
        end)
        addDetailElement(row)
        lastAnchor = row
        lastPoint = "BOTTOMLEFT"
        lastY = -TEXT_GAP_LINE
    end

    function panel:SetAchievement(achievement)
        clearDetailElements()
        lastAnchor = content
        lastPoint = "TOPLEFT"
        lastY = 0

        if not achievement or not achievement.id then
            child:SetHeight(1)
            return
        end

        -- Header: icon + status + title (Plans kartları ile aynı stil: title font, accent renk)
        local headerRow = CreateFrame("Frame", nil, content)
        headerRow:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
        headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, lastY)
        headerRow:SetHeight(ROW_HEIGHT + TEXT_GAP_LINE)
        local headerIcon = headerRow:CreateTexture(nil, "ARTWORK")
        headerIcon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        headerIcon:SetPoint("LEFT", PADDING, 0)
        headerIcon:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_General")
        headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local headerStatus = headerRow:CreateTexture(nil, "ARTWORK")
        headerStatus:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
        headerStatus:SetPoint("LEFT", headerIcon, "RIGHT", CONTENT_INSET / 2, 0)
        headerStatus:SetTexture(achievement.isCollected and ACHIEVEMENT_ICON_READY or ACHIEVEMENT_ICON_NOT_READY)
        local headerName = FontManager:CreateFontString(headerRow, "title", "OVERLAY")
        headerName:SetPoint("LEFT", headerStatus, "RIGHT", CONTENT_INSET, 0)
        headerName:SetPoint("RIGHT", headerRow, "RIGHT", -PADDING, 0)
        headerName:SetJustifyH("LEFT")
        headerName:SetWordWrap(true)
        headerName:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        headerName:SetText((achievement.name or "") .. (achievement.points and achievement.points > 0 and (" (" .. achievement.points .. " pts)") or ""))
        addDetailElement(headerRow)
        lastAnchor = headerRow
        lastPoint = "BOTTOMLEFT"
        lastY = -TEXT_GAP_LINE

        -- Show full achievement series (e.g. Level 10, 20, 30... 80): all tiers with check/cross; click selects and opens achievement.
        local seriesIds = BuildAchievementSeries(achievement.id)
        if seriesIds and #seriesIds > 1 then
            addSection((ns.L and ns.L["ACHIEVEMENT_SERIES"]) or "Achievement Series", function()
                for i = 1, #seriesIds do
                    local achID = seriesIds[i]
                    local ok, _, aName, aPoints, aCompleted, _, _, _, _, _, aIcon = pcall(GetAchievementInfo, achID)
                    if ok and aName then
                        addAchievementRow({ id = achID, name = aName, icon = aIcon, points = aPoints, isCollected = aCompleted }, nil)
                    end
                end
            end)
        end

        if achievement.description and achievement.description ~= "" then
            addSection((ns.L and ns.L["DESCRIPTION"]) or "Description", function(anchor)
                local descFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                descFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", SECTION_BODY_INDENT, -TEXT_GAP_LINE)
                descFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(true)
                descFs:SetText(achievement.description or "")
                addDetailElement(descFs)
                lastAnchor = descFs
                lastPoint = "BOTTOMLEFT"
                lastY = -TEXT_GAP_LINE
            end)
        end

        local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
        if rewardInfo and (rewardInfo.title or rewardInfo.itemName) then
            addSection((ns.L and ns.L["REWARD_LABEL"]) or "Reward", function(anchor)
                local rewardFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                rewardFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", SECTION_BODY_INDENT, -TEXT_GAP_LINE)
                rewardFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
                rewardFs:SetJustifyH("LEFT")
                rewardFs:SetWordWrap(true)
                local txt = rewardInfo.title or rewardInfo.itemName or ""
                rewardFs:SetText("|cff00ff00" .. txt .. "|r")
                addDetailElement(rewardFs)
                lastAnchor = rewardFs
                lastPoint = "BOTTOMLEFT"
                lastY = -TEXT_GAP_LINE
            end)
        end

        local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(achievement.id) or 0
        if numCriteria > 0 then
            addSection((ns.L and ns.L["CRITERIA"]) or "Criteria", function(anchor)
                local CRITERIA_LINE_HEIGHT = 16
                for i = 1, numCriteria do
                    local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievement.id, i)
                    if criteriaName and criteriaName ~= "" then
                        local progressStr = ""
                        if quantity and reqQuantity and reqQuantity > 1 then
                            local fmt = ns.UI_FormatNumber or tostring
                            progressStr = string.format(" (%s / %s)", fmt(quantity), fmt(reqQuantity))
                        end
                        local P = ns.PLAN_UI_COLORS or {}
                        local color = completed and (P.completed or "|cff44ff44") or (P.incomplete or "|cffffffff")
                        local row = CreateFrame("Frame", nil, content)
                        row:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, lastY)
                        row:SetHeight(CRITERIA_LINE_HEIGHT)
                        local checkTex = row:CreateTexture(nil, "ARTWORK")
                        checkTex:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
                        checkTex:SetPoint("LEFT", 0, 0)
                        checkTex:SetTexture(completed and ACHIEVEMENT_ICON_READY or ACHIEVEMENT_ICON_NOT_READY)
                        local critFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                        critFs:SetPoint("LEFT", checkTex, "RIGHT", CRITERIA_TEXT_INDENT, 0)
                        critFs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                        critFs:SetJustifyH("LEFT")
                        critFs:SetWordWrap(true)
                        critFs:SetText(color .. (criteriaName or "") .. progressStr .. "|r")
                        addDetailElement(row)
                        lastAnchor = row
                        lastPoint = "BOTTOMLEFT"
                        lastY = -TEXT_GAP_LINE
                    end
                end
            end)
        end

        local totalH = math.abs(lastY) + PADDING
        child:SetHeight(math.max(totalH, 1))
    end

    return panel
end

-- ============================================================================
-- SUB-TAB BUTTONS
-- ============================================================================

local SUB_TABS = {
    { key = "mounts", label = (ns.L and ns.L["CATEGORY_MOUNTS"]) or MOUNTS or "Mounts", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "pets", label = (ns.L and ns.L["CATEGORY_PETS"]) or PETS or "Pets", icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
    { key = "achievements", label = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
    -- Future: toys, transmog, etc.
}

-- Plans category bar ile birebir aynı (catBtnHeight=40, catBtnSpacing=8, dynamic width)
local SUBTAB_BTN_HEIGHT = 40
local SUBTAB_BTN_SPACING = 8
local SUBTAB_ICON_SIZE = 28
local SUBTAB_ICON_LEFT = 10
local SUBTAB_ICON_TEXT_GAP = 8
local SUBTAB_TEXT_RIGHT = 10
local SUBTAB_DEFAULT_WIDTH = 120

local function CreateSubTabBar(parent, onTabSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(SUBTAB_BTN_HEIGHT)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)

    -- Plans gibi metne göre buton genişliği hesapla
    local btnWidths = {}
    for i, tabInfo in ipairs(SUB_TABS) do
        local tempFs = FontManager:CreateFontString(bar, "body", "OVERLAY")
        tempFs:SetText(tabInfo.label)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = SUBTAB_ICON_LEFT + SUBTAB_ICON_SIZE + SUBTAB_ICON_TEXT_GAP + textW + SUBTAB_TEXT_RIGHT
        btnWidths[i] = math.max(needed, SUBTAB_DEFAULT_WIDTH)
    end

    local buttons = {}
    local xPos = 0
    local btnHeight = SUBTAB_BTN_HEIGHT
    local spacing = SUBTAB_BTN_SPACING

    for i, tabInfo in ipairs(SUB_TABS) do
        local btnWidth = btnWidths[i]
        local btn = ns.UI.Factory:CreateButton(bar, btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        btnIcon:SetSize(SUBTAB_ICON_SIZE - 2, SUBTAB_ICON_SIZE - 2)
        btnIcon:SetPoint("LEFT", SUBTAB_ICON_LEFT, 0)
        btnIcon:SetTexture(tabInfo.icon)
        btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", btnIcon, "RIGHT", SUBTAB_ICON_TEXT_GAP, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -SUBTAB_TEXT_RIGHT, 0)
        btnText:SetText(tabInfo.label)
        btnText:SetJustifyH("LEFT")
        btnText:SetWordWrap(false)
        btnText:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        btn._text = btnText

        btn:SetScript("OnClick", function()
            if onTabSelect then onTabSelect(tabInfo.key) end
        end)

        if UpdateBorderColor then
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                UpdateBorderColor(self, {COLORS.accent[1] * 1.2, COLORS.accent[2] * 1.2, COLORS.accent[3] * 1.2, 0.9})
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                UpdateBorderColor(self, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
            end)
        else
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.10, 0.10, 0.12, 0.95) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.08, 0.08, 0.10, 0.95) end
            end)
        end

        buttons[tabInfo.key] = btn
        xPos = xPos + btnWidths[i] + spacing
    end

    bar.buttons = buttons

    function bar:SetActiveTab(key)
        for k, btn in pairs(buttons) do
            if k == key then
                btn._active = true
                if ApplyVisuals then
                    ApplyVisuals(btn, {COLORS.accent[1] * 0.2, COLORS.accent[2] * 0.2, COLORS.accent[3] * 0.2, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85})
                end
                if btn._text then btn._text:SetTextColor(COLORS.textBright[1], COLORS.textBright[2], COLORS.textBright[3]) end
                if UpdateBorderColor then
                    UpdateBorderColor(btn, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85})
                end
            else
                btn._active = false
                if ApplyVisuals then
                    ApplyVisuals(btn, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
                end
                if btn._text then btn._text:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3]) end
                if UpdateBorderColor then
                    UpdateBorderColor(btn, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
                end
            end
        end
    end

    return bar
end

-- ============================================================================
-- MOUNT DATA BUILDER (Source Grouped) — From global collection data (DB); fallback to API
-- ============================================================================

-- API bazen yetenek/placeholder veya journal'da olmayan kayıt döndürür; liste dışı bırakıyoruz.
local MOUNT_NAME_BLACKLIST = {
    ["Soar"] = true,
    ["Unstable Rocket"] = true,
    ["Whelpling"] = true,
}

local function BuildGroupedMountData(searchText, showCollected, showUncollected, optionalMounts)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for _, cat in ipairs(SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return ClassifyMountSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    -- Use optionalMounts when provided and non-empty to avoid repeated DB/API calls
    local allMounts
    if optionalMounts and #optionalMounts > 0 then
        allMounts = optionalMounts
    else
        allMounts = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
    end
    local useCache = #allMounts > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma (FPS ve performans).
    local query = (searchText or ""):lower()
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allMounts do
            local d = allMounts[i]
            if not d or not d.id then
                -- skip
            else
                local name = d.name or tostring(d.id)
                if MOUNT_NAME_BLACKLIST[name] then
                    -- skip (yetenek/placeholder)
                else
                    -- Sadece DB/cache: isCollected cache'den (API çağrısı yok).
                    local isCollected = (d.isCollected == true) or (d.collected == true)
                    if (showC and isCollected) or (showU and not isCollected) then
                        if query == "" or (name and name:lower():find(query, 1, true)) then
                            local sourceText = d.source or ""
                            local catKey = classify(sourceText)
                            if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                            if not nameAlreadyInCategory(catKey, name) then
                                addToCategory(catKey, {
                                    id = d.id,
                                    name = name,
                                    icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                    source = sourceText,
                                    description = d.description,
                                    creatureDisplayID = d.creatureDisplayID,
                                    isCollected = isCollected,
                                })
                                totalCount = totalCount + 1
                            elseif isCollected then
                                updateCollectedInCategory(catKey, name, true)
                            end
                        end
                    end
                end
            end
        end
    else
        local mountIDs = (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountIDs()) or {}
        if #mountIDs == 0 then return grouped, 0 end
        for i = 1, #mountIDs do
            local mountID = mountIDs[i]
            local isCollected = SafeGetMountCollected(mountID)
            if (showC and isCollected) or (showU and not isCollected) then
                local meta = WarbandNexus:ResolveCollectionMetadata("mount", mountID)
                local name = (meta and meta.name) or ""
                if not name and C_MountJournal and C_MountJournal.GetMountInfoByID then
                    local n = C_MountJournal.GetMountInfoByID(mountID)
                    if n and not (issecretvalue and issecretvalue(n)) then name = n end
                end
                if not name then name = tostring(mountID) end
                if MOUNT_NAME_BLACKLIST[name] then
                    -- skip (yetenek/placeholder)
                elseif query == "" or name:lower():find(query, 1, true) then
                    local sourceText = meta and meta.source or ""
                    local creatureDisplayID, description, src = SafeGetMountInfoExtra(mountID)
                    if sourceText == "" then sourceText = src or "" end
                    local icon = (meta and meta.icon) or "Interface\\Icons\\Ability_Mount_RidingHorse"
                    if not icon and C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, ic = C_MountJournal.GetMountInfoByID(mountID)
                        if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                    end
                    local catKey = classify(sourceText)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = mountID,
                            name = name,
                            icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                            source = sourceText,
                            description = (meta and meta.description) or description or "",
                            creatureDisplayID = creatureDisplayID,
                            isCollected = isCollected,
                        })
                        totalCount = totalCount + 1
                    elseif isCollected then
                        updateCollectedInCategory(catKey, name, true)
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
    end

    return grouped, totalCount
end

-- Chunked build: process mounts in small chunks per frame so no single frame freezes for ~1s.
local function RunChunkedMountBuild(allMounts, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for _, cat in ipairs(SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return ClassifyMountSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = (searchText or ""):lower()
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allMounts

    local function processChunk()
        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allMounts[i]
            if d and d.id then
                local name = d.name or tostring(d.id)
                if not MOUNT_NAME_BLACKLIST[name] then
                    local isCollected = (d.isCollected == true) or (d.collected == true)
                    if (showC and isCollected) or (showU and not isCollected) then
                        if query == "" or (name and name:lower():find(query, 1, true)) then
                            local sourceText = d.source or ""
                            local catKey = classify(sourceText)
                            if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                            if not nameAlreadyInCategory(catKey, name) then
                                addToCategory(catKey, {
                                    id = d.id,
                                    name = name,
                                    icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                    source = sourceText,
                                    description = d.description,
                                    creatureDisplayID = d.creatureDisplayID,
                                    isCollected = isCollected,
                                })
                            elseif isCollected then
                                updateCollectedInCategory(catKey, name, true)
                            end
                        end
                    end
                end
            end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- Chunked build for pets (same idea as mounts).
local function RunChunkedPetBuild(allPets, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for _, cat in ipairs(PET_SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return ClassifyPetSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = (searchText or ""):lower()
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allPets

    local function processChunk()
        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allPets[i]
            if d and d.id then
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and name:lower():find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(sourceText)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- BuildGroupedPetData: same structure as mounts, uses C_PetJournal / GetAllPetsData. Pet-specific categories (petbattle, puzzle).
local function BuildGroupedPetData(searchText, showCollected, showUncollected, optionalPets)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for _, cat in ipairs(PET_SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return ClassifyPetSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allPets
    if optionalPets and #optionalPets > 0 then
        allPets = optionalPets
    else
        allPets = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
    end
    local useCache = #allPets > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma.
    local query = (searchText or ""):lower()
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allPets do
            local d = allPets[i]
            if not d or not d.id then
            else
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and name:lower():find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(sourceText)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    else
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
        if not InCombatLockdown() then
            pcall(function()
                if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                if C_PetJournal.SetFilterChecked then
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                end
            end)
        end
        local numPets = C_PetJournal.GetNumPets and C_PetJournal.GetNumPets() or 0
        if numPets == 0 then return grouped, 0 end
        for i = 1, numPets do
            local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
            if speciesID then
                local isCollected = SafeGetPetCollected(speciesID)
                if (showC and isCollected) or (showU and not isCollected) then
                    local meta = WarbandNexus:ResolveCollectionMetadata("pet", speciesID)
                    local name = (meta and meta.name) or ""
                    if not name and C_PetJournal.GetPetInfoBySpeciesID then
                        local n = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                        if n and not (issecretvalue and issecretvalue(n)) then name = n end
                    end
                    if not name then name = tostring(speciesID) end
                    if query == "" or name:lower():find(query, 1, true) then
                        local sourceText = meta and meta.source or ""
                        local creatureDisplayID, description, src = SafeGetPetInfoExtra(speciesID)
                        if sourceText == "" then sourceText = src or "" end
                        local icon = (meta and meta.icon) or "Interface\\Icons\\INV_Box_PetCarrier_01"
                        if not icon and C_PetJournal.GetPetInfoBySpeciesID then
                            local _, ic = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                            if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                        end
                        local catKey = classify(sourceText)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = speciesID,
                                name = name,
                                icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                description = (meta and meta.description) or description or "",
                                creatureDisplayID = creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
    end

    return grouped, totalCount
end

-- ============================================================================
-- DRAW MOUNTS CONTENT
-- Layout: LEFT = Header + Rows (scroll list), RIGHT = Model viewer (vertical, text inside same frame).
-- All in Factory containers; responsive width/height from window.
-- ============================================================================

local CONTENT_GAP = LAYOUT.CARD_GAP or 8

-- Result container: only one sub-tab's content is visible. Hide all result-area frames before drawing current tab.
local function HideAllCollectionsResultFrames()
    if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
    if collectionsState.mountListContainer then collectionsState.mountListContainer:Hide() end
    if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Hide() end
    if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
    if collectionsState.modelViewer then
        collectionsState.modelViewer:SetMount(nil)
        collectionsState.modelViewer:SetPet(nil)
        collectionsState.modelViewer:Hide()
    end
    if collectionsState.petListContainer then collectionsState.petListContainer:Hide() end
    if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Hide() end
    if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
    if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
    if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
end

local function DrawMountsContent(contentFrame)
    if collectionsState._drawMountsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawMountsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawMountsContentBusy = true
    collectionsState._mountsDrawGen = (collectionsState._mountsDrawGen or 0) + 1
    local drawGen = collectionsState._mountsDrawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    -- Layout: LEFT = list (header + rows), MIDDLE = scrollbar rezerve, RIGHT = 3D viewer.
    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth - CONTENT_GAP)

    HideAllCollectionsResultFrames()

    -- LEFT CONTAINER: List only (scroll frame fills it; scrollbar ayrı sütunda)
    if not collectionsState.mountListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, true)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.mountListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = self:GetVerticalScroll()
            local maxS = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            self:SetVerticalScroll(newScroll)
            if self.ScrollBar and self.ScrollBar.SetValue then
                self.ScrollBar:SetValue(newScroll)
            end
        end)
        collectionsState.mountListScrollFrame = scrollFrame

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
        scrollFrame:SetScrollChild(scrollChild)
        scrollChild:EnableMouseWheel(true)
        scrollChild:SetScript("OnMouseWheel", function(_, delta)
            local sf = collectionsState.mountListScrollFrame
            if not sf then return end
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = sf:GetVerticalScroll()
            local maxS = sf:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            sf:SetVerticalScroll(newScroll)
            if sf.ScrollBar and sf.ScrollBar.SetValue then
                sf.ScrollBar:SetValue(newScroll)
            end
        end)
        collectionsState.mountListScrollChild = scrollChild

        -- SCROLLBAR REZERVE: Liste ile 3D view arasında görünür; parent değiştirilmez (Blizzard script scroll frame arar).
        local scrollBarContainer = CreateFrame("Frame", nil, contentFrame)
        scrollBarContainer:SetSize(scrollBarColumnWidth, ch)
        scrollBarContainer:SetPoint("TOPLEFT", listContainer, "TOPRIGHT", 0, 0)
        scrollBarContainer:Show()
        collectionsState.mountListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, -CONTAINER_INSET)
            scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
            scrollBar:SetWidth(scrollBarColumnWidth - 4)
        end
    else
        collectionsState.mountListContainer:SetSize(listContentWidth, ch)
        if not collectionsState.mountListScrollBarContainer then
            local scrollBarContainer = CreateFrame("Frame", nil, contentFrame)
            scrollBarContainer:SetSize(scrollBarColumnWidth, ch)
            scrollBarContainer:SetPoint("TOPLEFT", collectionsState.mountListContainer, "TOPRIGHT", 0, 0)
            scrollBarContainer:Show()
            collectionsState.mountListScrollBarContainer = scrollBarContainer
            local scrollBar = collectionsState.mountListScrollFrame and collectionsState.mountListScrollFrame.ScrollBar
            if scrollBar then
                scrollBar:ClearAllPoints()
                scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, -CONTAINER_INSET)
                scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
                scrollBar:SetWidth(scrollBarColumnWidth - 4)
            end
        else
            collectionsState.mountListScrollBarContainer:SetSize(scrollBarColumnWidth, ch)
            collectionsState.mountListScrollBarContainer:SetPoint("TOPLEFT", collectionsState.mountListContainer, "TOPRIGHT", 0, 0)
            local scrollBar = collectionsState.mountListScrollFrame and collectionsState.mountListScrollFrame.ScrollBar
            if scrollBar then
                scrollBar:ClearAllPoints()
                scrollBar:SetPoint("TOP", collectionsState.mountListScrollBarContainer, "TOP", 0, -CONTAINER_INSET)
                scrollBar:SetPoint("BOTTOM", collectionsState.mountListScrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
                scrollBar:SetWidth(scrollBarColumnWidth - 4)
            end
        end
    end
    collectionsState.mountListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT CONTAINER: 3D viewer (scrollBarContainer'ın sağında)
    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(contentFrame, viewerWidth, ch, true)
        viewerContainer:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer

        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetSize(viewerWidth, ch)
            collectionsState.viewerContainer:ClearAllPoints()
            collectionsState.viewerContainer:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", 0, 0)
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2))
    end

    local function onSelectMount(mountID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedMountID = mountID
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetMount(mountID, creatureDisplayID)
            collectionsState.modelViewer:SetMountInfo(mountID, name, icon, source, description, isCollected)
        end
    end

    -- Loading: scan in progress (CollectionLoadingState) or mount data not yet in DB (GetAllMountsData empty)
    -- When data exists, use cache to avoid repeated GetAllMountsData() every draw.
    -- Never call GetAllMountsData() in the tab-click frame: defer to next frame to avoid 1s freeze.
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allMounts
    if collectionsState._cachedMountsData and #collectionsState._cachedMountsData > 0 then
        allMounts = collectionsState._cachedMountsData
    else
        -- Do not call GetAllMountsData() here; defer fetch to next frame when we show loading.
        allMounts = nil
    end
    local dataReady = allMounts and #allMounts > 0
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = CreateLoadingPanel(contentFrame, cw, ch)
            collectionsState.loadingPanel:SetPoint("TOPLEFT", 0, 0)
        end
        collectionsState.loadingPanel:Show()
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:UpdateProgress(progress, stage)
        if collectionsState.mountListContainer then collectionsState.mountListContainer:Hide() end
        if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Hide() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
        -- No cache and no scan in progress: fetch data after short delay so tab switch stays responsive.
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if collectionsState._mountsDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "mounts" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local am = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
                if #am > 0 then
                    collectionsState._cachedMountsData = am
                else
                    -- Empty store: ensure build runs so next refresh has data
                    if WarbandNexus.EnsureCollectionData then WarbandNexus:EnsureCollectionData() end
                end
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
                if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = collectionsState.mountListScrollChild
                -- Build and populate even when am is empty (show empty list; EnsureCollectionData may fill store later)
                RunChunkedMountBuild(
                    am,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedMountData = grouped
                        C_Timer.After(0, function()
                            if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulateMountList(sch, listW, grouped, collectionsState.collapsedHeadersMounts, collectionsState.selectedMountID, onSelectMount, contentFrame, DrawMountsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    else
        if collectionsState.loadingPanel then
            collectionsState.loadingPanel:Hide()
        end
        if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
        if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.mountListScrollChild
        local searchUnchanged = (collectionsState._mountLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._mountLastShowCollected == collectionsState.showCollected)
            and (collectionsState._mountLastShowUncollected == collectionsState.showUncollected)
        -- Tab switch back: list already populated and search/filter unchanged, only refresh visible range (no repopulate).
        if sch and collectionsState._mountFlatList and collectionsState._lastGroupedMountData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
            end
            if collectionsState._mountListRefreshVisible then
                collectionsState._mountListRefreshVisible()
            end
        else
            -- First time or list not built: chunked build then populate.
            C_Timer.After(0, function()
                if collectionsState._mountsDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "mounts" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                RunChunkedMountBuild(
                    allMounts,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedMountData = grouped
                        collectionsState._mountLastSearchText = collectionsState.searchText or ""
                        collectionsState._mountLastShowCollected = collectionsState.showCollected
                        collectionsState._mountLastShowUncollected = collectionsState.showUncollected
                        C_Timer.After(0, function()
                            if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulateMountList(sch, listW, grouped, collectionsState.collapsedHeadersMounts, collectionsState.selectedMountID, onSelectMount, contentFrame, DrawMountsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    end
    collectionsState._drawMountsContentBusy = nil
end

-- DrawPetsContent: same layout as mounts, uses pet API and list.
local function DrawPetsContent(contentFrame)
    if collectionsState._drawPetsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawPetsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawPetsContentBusy = true
    collectionsState._petDrawGen = (collectionsState._petDrawGen or 0) + 1
    local drawGen = collectionsState._petDrawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth - CONTENT_GAP)

    HideAllCollectionsResultFrames()

    -- LEFT CONTAINER: Pet list
    if not collectionsState.petListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, true)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.petListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = self:GetVerticalScroll()
            local maxS = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            self:SetVerticalScroll(newScroll)
            if self.ScrollBar and self.ScrollBar.SetValue then
                self.ScrollBar:SetValue(newScroll)
            end
        end)
        collectionsState.petListScrollFrame = scrollFrame

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
        scrollFrame:SetScrollChild(scrollChild)
        scrollChild:EnableMouseWheel(true)
        scrollChild:SetScript("OnMouseWheel", function(_, delta)
            local sf = collectionsState.petListScrollFrame
            if not sf then return end
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = sf:GetVerticalScroll()
            local maxS = sf:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            sf:SetVerticalScroll(newScroll)
            if sf.ScrollBar and sf.ScrollBar.SetValue then
                sf.ScrollBar:SetValue(newScroll)
            end
        end)
        collectionsState.petListScrollChild = scrollChild

        local scrollBarContainer = CreateFrame("Frame", nil, contentFrame)
        scrollBarContainer:SetSize(scrollBarColumnWidth, ch)
        scrollBarContainer:SetPoint("TOPLEFT", listContainer, "TOPRIGHT", 0, 0)
        scrollBarContainer:Show()
        collectionsState.petListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, -CONTAINER_INSET)
            scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
            scrollBar:SetWidth(scrollBarColumnWidth - 4)
        end
    else
        collectionsState.petListContainer:SetSize(listContentWidth, ch)
        collectionsState.petListScrollBarContainer:SetSize(scrollBarColumnWidth, ch)
        collectionsState.petListScrollBarContainer:SetPoint("TOPLEFT", collectionsState.petListContainer, "TOPRIGHT", 0, 0)
        local scrollBar = collectionsState.petListScrollFrame and collectionsState.petListScrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOP", collectionsState.petListScrollBarContainer, "TOP", 0, -CONTAINER_INSET)
            scrollBar:SetPoint("BOTTOM", collectionsState.petListScrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
            scrollBar:SetWidth(scrollBarColumnWidth - 4)
        end
    end
    collectionsState.petListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT CONTAINER: 3D viewer (shared with mounts)
    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(contentFrame, viewerWidth, ch, true)
        viewerContainer:SetPoint("TOPLEFT", collectionsState.petListScrollBarContainer, "TOPRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer

        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetSize(viewerWidth, ch)
            collectionsState.viewerContainer:ClearAllPoints()
            collectionsState.viewerContainer:SetPoint("TOPLEFT", collectionsState.petListScrollBarContainer, "TOPRIGHT", 0, 0)
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2))
    end

    local function onSelectPet(speciesID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedPetID = speciesID
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetPet(speciesID, creatureDisplayID)
            collectionsState.modelViewer:SetPetInfo(speciesID, name, icon, source, description, isCollected)
        end
    end

    -- Never call GetAllPetsData() in the tab-click frame: defer to next frame to avoid 1s freeze.
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allPets
    if collectionsState._cachedPetsData and #collectionsState._cachedPetsData > 0 then
        allPets = collectionsState._cachedPetsData
    else
        allPets = nil
    end
    local dataReady = allPets and #allPets > 0
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = CreateLoadingPanel(contentFrame, cw, ch)
            collectionsState.loadingPanel:SetPoint("TOPLEFT", 0, 0)
        end
        collectionsState.loadingPanel:Show()
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:UpdateProgress(progress, stage)
        if collectionsState.petListContainer then collectionsState.petListContainer:Hide() end
        if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Hide() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if collectionsState._petDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "pets" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local ap = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
                if #ap > 0 then
                    collectionsState._cachedPetsData = ap
                else
                    if WarbandNexus.EnsureCollectionData then WarbandNexus:EnsureCollectionData() end
                end
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.petListContainer then collectionsState.petListContainer:Show() end
                if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = collectionsState.petListScrollChild
                RunChunkedPetBuild(
                    ap,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedPetData = grouped
                        C_Timer.After(0, function()
                            if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulatePetList(sch, listW, grouped, collectionsState.collapsedHeadersPets, collectionsState.selectedPetID, onSelectPet, contentFrame, DrawPetsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    else
        if collectionsState.loadingPanel then
            collectionsState.loadingPanel:Hide()
        end
        if collectionsState.petListContainer then collectionsState.petListContainer:Show() end
        if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Show() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.petListScrollChild
        local searchUnchanged = (collectionsState._petLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._petLastShowCollected == collectionsState.showCollected)
            and (collectionsState._petLastShowUncollected == collectionsState.showUncollected)
        -- Tab switch back: list already populated and search/filter unchanged, only refresh visible range (no repopulate).
        if sch and collectionsState._petFlatList and collectionsState._lastGroupedPetData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
            end
            if collectionsState._petListRefreshVisible then
                collectionsState._petListRefreshVisible()
            end
        else
            -- First time or list not built: chunked build then populate.
            C_Timer.After(0, function()
                if collectionsState._petDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "pets" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                RunChunkedPetBuild(
                    allPets,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedPetData = grouped
                        collectionsState._petLastSearchText = collectionsState.searchText or ""
                        collectionsState._petLastShowCollected = collectionsState.showCollected
                        collectionsState._petLastShowUncollected = collectionsState.showUncollected
                        C_Timer.After(0, function()
                            if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulatePetList(sch, listW, grouped, collectionsState.collapsedHeadersPets, collectionsState.selectedPetID, onSelectPet, contentFrame, DrawPetsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    end
    collectionsState._drawPetsContentBusy = nil
end

-- DrawAchievementsContent: list left, achievement detail panel right (parent/children, criteria).
local function DrawAchievementsContent(contentFrame)
    if collectionsState._drawAchievementsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawAchievementsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawAchievementsContentBusy = true
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth - CONTENT_GAP)

    HideAllCollectionsResultFrames()

    if not collectionsState.achievementListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, true)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.achievementListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = self:GetVerticalScroll()
            local maxS = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            self:SetVerticalScroll(newScroll)
            if self.ScrollBar and self.ScrollBar.SetValue then self.ScrollBar:SetValue(newScroll) end
        end)
        collectionsState.achievementListScrollFrame = scrollFrame

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
        scrollFrame:SetScrollChild(scrollChild)
        scrollChild:EnableMouseWheel(true)
        scrollChild:SetScript("OnMouseWheel", function(_, delta)
            local sf = collectionsState.achievementListScrollFrame
            if not sf then return end
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
            local cur = sf:GetVerticalScroll()
            local maxS = sf:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
            sf:SetVerticalScroll(newScroll)
            if sf.ScrollBar and sf.ScrollBar.SetValue then sf.ScrollBar:SetValue(newScroll) end
        end)
        collectionsState.achievementListScrollChild = scrollChild

        local scrollBarContainer = CreateFrame("Frame", nil, contentFrame)
        scrollBarContainer:SetSize(scrollBarColumnWidth, ch)
        scrollBarContainer:SetPoint("TOPLEFT", listContainer, "TOPRIGHT", 0, 0)
        scrollBarContainer:Show()
        collectionsState.achievementListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, -CONTAINER_INSET)
            scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
            scrollBar:SetWidth(scrollBarColumnWidth - 4)
        end
    else
        collectionsState.achievementListContainer:SetSize(listContentWidth, ch)
        collectionsState.achievementListContainer:Show()
        collectionsState.achievementListScrollBarContainer:SetSize(scrollBarColumnWidth, ch)
        collectionsState.achievementListScrollBarContainer:SetPoint("TOPLEFT", collectionsState.achievementListContainer, "TOPRIGHT", 0, 0)
        collectionsState.achievementListScrollBarContainer:Show()
        local scrollBar = collectionsState.achievementListScrollFrame and collectionsState.achievementListScrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOP", collectionsState.achievementListScrollBarContainer, "TOP", 0, -CONTAINER_INSET)
            scrollBar:SetPoint("BOTTOM", collectionsState.achievementListScrollBarContainer, "BOTTOM", 0, CONTAINER_INSET)
            scrollBar:SetWidth(scrollBarColumnWidth - 4)
        end
    end
    collectionsState.achievementListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
    if collectionsState.achievementDetailContainer then
        collectionsState.achievementDetailContainer:Show()
    end

    local function onSelectAchievement(ach)
        collectionsState.selectedAchievementID = ach and ach.id
        if collectionsState.achievementDetailPanel then
            collectionsState.achievementDetailPanel:SetAchievement(ach)
        end
    end

    if not collectionsState.achievementDetailPanel then
        local detailContainer = Factory:CreateContainer(contentFrame, detailWidth, ch, true)
        detailContainer:SetPoint("TOPLEFT", collectionsState.achievementListScrollBarContainer, "TOPRIGHT", 0, 0)
        detailContainer:Show()
        collectionsState.achievementDetailContainer = detailContainer
        collectionsState.achievementDetailPanel = CreateAchievementDetailPanel(detailContainer, detailWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2), onSelectAchievement)
        collectionsState.achievementDetailPanel:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
    else
        if collectionsState.achievementDetailContainer then
            collectionsState.achievementDetailContainer:SetSize(detailWidth, ch)
            collectionsState.achievementDetailContainer:ClearAllPoints()
            collectionsState.achievementDetailContainer:SetPoint("TOPLEFT", collectionsState.achievementListScrollBarContainer, "TOPRIGHT", 0, 0)
        end
        collectionsState.achievementDetailPanel:SetSize(detailWidth - (CONTAINER_INSET * 2), ch - (CONTAINER_INSET * 2))
    end

    local loadingState = ns.PlansLoadingState and ns.PlansLoadingState.achievement
    local collLoading = ns.CollectionLoadingState
    local isLoading = (loadingState and loadingState.isLoading) or (collLoading and collLoading.isLoading and collLoading.currentCategory == "achievement")
    local categoryData, rootCategories, totalCount = BuildGroupedAchievementData(
        collectionsState.searchText or "",
        collectionsState.showCollected,
        collectionsState.showUncollected
    )
    local dataReady = totalCount > 0
    if not isLoading and not dataReady then
        isLoading = true
    end
    -- Re-check: BuildGroupedAchievementData/GetAllAchievementsData may have triggered ScanAchievementsAsync
    if not isLoading and loadingState and loadingState.isLoading then
        isLoading = true
    end

    if isLoading then
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = CreateLoadingPanel(contentFrame, cw, ch)
            collectionsState.loadingPanel:SetPoint("TOPLEFT", 0, 0)
        end
        collectionsState.loadingPanel:Show()
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or (collLoading and collLoading.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or (collLoading and collLoading.currentStage) or ((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...")
        collectionsState.loadingPanel:UpdateProgress(progress, stage)
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
    else
        if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Show() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Show() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Show() end

        collectionsState._lastAchievementCategoryData = categoryData
        collectionsState._lastAchievementRootCategories = rootCategories
        PopulateAchievementList(
            collectionsState.achievementListScrollChild,
            listContentWidth - (CONTAINER_INSET * 2),
            categoryData,
            rootCategories,
            collectionsState.collapsedHeaders,
            collectionsState.selectedAchievementID,
            onSelectAchievement,
            contentFrame,
            DrawAchievementsContent
        )
        if collectionsState.selectedAchievementID then
            local allAchs = WarbandNexus:GetAllAchievementsData()
            for i = 1, #allAchs do
                if allAchs[i].id == collectionsState.selectedAchievementID then
                    collectionsState.achievementDetailPanel:SetAchievement(allAchs[i])
                    break
                end
            end
        else
            collectionsState.achievementDetailPanel:SetAchievement(nil)
        end
        if Factory.UpdateScrollBarVisibility and collectionsState.achievementListScrollFrame then
            Factory:UpdateScrollBarVisibility(collectionsState.achievementListScrollFrame)
        end
    end
    collectionsState._drawAchievementsContentBusy = nil
end

-- ============================================================================
-- DRAW COLLECTIONS TAB (Main Entry)
-- ============================================================================

function WarbandNexus:DrawCollectionsTab(parent)
    local yOffset = (LAYOUT.TOP_MARGIN or 8)
    local sideMargin = (LAYOUT.SIDE_MARGIN or 10)
    local width = (parent:GetWidth() or 680) - 20
    HideEmptyStateCard(parent, "collections")

    -- ===== CHROME CACHING: reuse header/search/filter/subtab frames across tab switches =====
    local chrome = collectionsState._chrome

    if chrome and chrome.titleCard then
        -- Re-parent cached chrome into current scrollChild
        chrome.titleCard:SetParent(parent)
        chrome.titleCard:ClearAllPoints()
        chrome.titleCard:SetPoint("TOPLEFT", sideMargin, -yOffset)
        chrome.titleCard:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.titleCard:Show()

        -- Update sync state text (lightweight)
        local loadingState = ns.CollectionLoadingState
        local achLoading = ns.PlansLoadingState and ns.PlansLoadingState.achievement
        local activeLoading = (loadingState and loadingState.isLoading) or (achLoading and achLoading.isLoading)
        local activeState = (loadingState and loadingState.isLoading) and loadingState or achLoading
        if activeLoading and activeState then
            local pct = activeState.loadingProgress or 0
            local stage = activeState.currentStage or ""
            chrome.syncText:SetText("|cffffcc00" .. string.format("Syncing %s... %d%%", stage, pct) .. "|r")
        else
            local LT = ns.LoadingTracker
            if LT and LT:IsComplete() then
                chrome.syncText:SetText("|cff00ff00" .. ((ns.L and ns.L["SYNC_COMPLETE"]) or "Synced") .. "|r")
            else
                chrome.syncText:SetText("|cff888888" .. ((ns.L and ns.L["SYNC_WAITING"]) or "Waiting...") .. "|r")
            end
        end

        yOffset = yOffset + (LAYOUT.afterHeader or 75)

        chrome.searchRow:SetParent(parent)
        chrome.searchRow:ClearAllPoints()
        chrome.searchRow:SetPoint("TOPLEFT", sideMargin, -yOffset)
        chrome.searchRow:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.searchRow:Show()

        yOffset = yOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT

        chrome.filterRow:SetParent(parent)
        chrome.filterRow:ClearAllPoints()
        chrome.filterRow:SetPoint("TOPLEFT", sideMargin, -yOffset)
        chrome.filterRow:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.filterRow:Show()

        yOffset = yOffset + FILTER_ROW_HEIGHT

        chrome.subTabBar:SetParent(parent)
        chrome.subTabBar:ClearAllPoints()
        chrome.subTabBar:SetPoint("TOPLEFT", sideMargin, -yOffset)
        chrome.subTabBar:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.subTabBar:SetActiveTab(collectionsState.currentSubTab)
        chrome.subTabBar:Show()
        collectionsState.subTabBar = chrome.subTabBar

        yOffset = yOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)
    else
        -- First-time creation of chrome elements
        chrome = {}
        collectionsState._chrome = chrome

        -- ===== HEADER CARD =====
        local titleCard = CreateCard(parent, 70)
        titleCard:SetPoint("TOPLEFT", sideMargin, -yOffset)
        titleCard:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.titleCard = titleCard

        local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("collections"))
        local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
        local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections") .. "|r"
        local subtitleTextContent = (ns.L and ns.L["COLLECTIONS_SUBTITLE"]) or "Mounts, pets, toys, and transmog overview"

        local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
        local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
        titleText:SetText(titleTextContent)
        titleText:SetJustifyH("LEFT")
        local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
        subtitleText:SetText(subtitleTextContent)
        subtitleText:SetTextColor(1, 1, 1)
        subtitleText:SetJustifyH("LEFT")
        titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)
        titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -(CONTENT_INSET / 2))
        subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", HEADER_ICON_TEXT_GAP, 0)
        textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)

        local syncText = FontManager:CreateFontString(titleCard, "small", "OVERLAY")
        syncText:SetPoint("RIGHT", titleCard, "RIGHT", -sideMargin, 0)
        syncText:SetJustifyH("RIGHT")
        chrome.syncText = syncText

        local loadingState = ns.CollectionLoadingState
        local achLoading = ns.PlansLoadingState and ns.PlansLoadingState.achievement
        local activeLoading = (loadingState and loadingState.isLoading) or (achLoading and achLoading.isLoading)
        local activeState = (loadingState and loadingState.isLoading) and loadingState or achLoading
        if activeLoading and activeState then
            local pct = activeState.loadingProgress or 0
            local stage = activeState.currentStage or ""
            syncText:SetText("|cffffcc00" .. string.format("Syncing %s... %d%%", stage, pct) .. "|r")
        else
            local LT = ns.LoadingTracker
            if LT and LT:IsComplete() then
                syncText:SetText("|cff00ff00" .. ((ns.L and ns.L["SYNC_COMPLETE"]) or "Synced") .. "|r")
            else
                syncText:SetText("|cff888888" .. ((ns.L and ns.L["SYNC_WAITING"]) or "Waiting...") .. "|r")
            end
        end

        titleCard:Show()
        yOffset = yOffset + (LAYOUT.afterHeader or 75)

        -- ===== SEARCH BOX =====
        local searchRow = CreateFrame("Frame", nil, parent)
        searchRow:SetHeight(SEARCH_ROW_HEIGHT)
        searchRow:SetPoint("TOPLEFT", sideMargin, -yOffset)
        searchRow:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.searchRow = searchRow

        local searchBox = CreateFrame("EditBox", nil, searchRow, "BackdropTemplate")
        searchBox:SetHeight(24)
        searchBox:SetPoint("TOPLEFT", 0, 0)
        searchBox:SetPoint("TOPRIGHT", 0, 0)
        if ApplyVisuals then
            ApplyVisuals(searchBox, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        else
            searchBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            searchBox:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
            searchBox:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
        end
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(50)
        searchBox:SetFontObject(GameFontNormal)
        searchBox:SetTextInsets(CONTENT_INSET, CONTENT_INSET, CONTENT_INSET / 2, CONTENT_INSET / 2)
        searchBox:SetText(collectionsState.searchText or "")

        local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        placeholder:SetPoint("LEFT", CONTENT_INSET, 0)
        placeholder:SetText((ns.L and ns.L["SEARCH_PLACEHOLDER"]) or "Search...")
        if (collectionsState.searchText or "") ~= "" then placeholder:Hide() end

        searchBox:SetScript("OnTextChanged", function(self)
            local text = self:GetText()
            collectionsState.searchText = text
            if text == "" then placeholder:Show() else placeholder:Hide() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)
        searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        collectionsState.searchBox = searchBox

        yOffset = yOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT

        -- ===== FILTER ROW =====
        local filterRow = CreateFrame("Frame", nil, parent)
        filterRow:SetHeight(FILTER_ROW_HEIGHT)
        filterRow:SetPoint("TOPLEFT", sideMargin, -yOffset)
        filterRow:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        chrome.filterRow = filterRow

        local cbCollected = CreateThemedCheckbox(filterRow, collectionsState.showCollected)
        cbCollected:SetPoint("LEFT", 0, 0)
        local lblCollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblCollected:SetPoint("LEFT", cbCollected, "RIGHT", CONTENT_INSET, 0)
        lblCollected:SetText((ns.L and ns.L["FILTER_COLLECTED"]) or "Collected")
        lblCollected:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        lblCollected:SetJustifyH("LEFT")
        cbCollected:SetScript("OnClick", function(self)
            collectionsState.showCollected = self:GetChecked()
            if self:GetChecked() then cbCollected.checkTexture:Show() else cbCollected.checkTexture:Hide() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        local cbUncollected = CreateThemedCheckbox(filterRow, collectionsState.showUncollected)
        cbUncollected:SetPoint("LEFT", lblCollected, "RIGHT", CONTENT_INSET * 2, 0)
        local lblUncollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblUncollected:SetPoint("LEFT", cbUncollected, "RIGHT", CONTENT_INSET, 0)
        lblUncollected:SetText((ns.L and ns.L["FILTER_UNCOLLECTED"]) or "Uncollected")
        lblUncollected:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        lblUncollected:SetJustifyH("LEFT")
        cbUncollected:SetScript("OnClick", function(self)
            collectionsState.showUncollected = self:GetChecked()
            if self:GetChecked() then cbUncollected.checkTexture:Show() else cbUncollected.checkTexture:Hide() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        if not collectionsState.showCollected and not collectionsState.showUncollected then
            collectionsState.showCollected = true
            collectionsState.showUncollected = true
            cbCollected:SetChecked(true)
            cbCollected.checkTexture:Show()
            cbUncollected:SetChecked(true)
            cbUncollected.checkTexture:Show()
        end

        yOffset = yOffset + FILTER_ROW_HEIGHT

        -- ===== SUB-TAB BAR =====
        local subTabBar = CreateSubTabBar(parent, function(tabKey)
            if collectionsState.currentSubTab == tabKey then
                if collectionsState.subTabBar then
                    collectionsState.subTabBar:SetActiveTab(tabKey)
                end
                return
            end
            collectionsState.currentSubTab = tabKey
            if collectionsState.subTabBar then
                collectionsState.subTabBar:SetActiveTab(tabKey)
            end
            -- Clear search when switching sub-tabs so the new tab shows full list
            collectionsState.searchText = ""
            if collectionsState.searchBox then
                collectionsState.searchBox:SetText("")
            end
            -- Clear result area immediately so only the new tab's content appears (no overlap).
            HideAllCollectionsResultFrames()
            C_Timer.After(0, function()
                local cf = collectionsState.contentFrame
                if not cf or not cf:GetParent() then return end
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(cf)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(cf)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(cf)
                end
            end)
        end)
        subTabBar:SetPoint("TOPLEFT", sideMargin, -yOffset)
        subTabBar:SetPoint("TOPRIGHT", -sideMargin, -yOffset)
        subTabBar:SetActiveTab(collectionsState.currentSubTab)
        chrome.subTabBar = subTabBar
        collectionsState.subTabBar = subTabBar

        yOffset = yOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)
    end

    -- ===== CONTENT AREA (fills remaining viewport) =====
    local scrollFrame = parent:GetParent()
    local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
    local bottomPad = LAYOUT.MIN_BOTTOM_SPACING or 12
    local contentHeight = math.max(250, viewHeight - yOffset - bottomPad)
    local parentWidth = parent:GetWidth() or 680
    local contentWidth = math.max(1, parentWidth - (sideMargin * 2))

    local contentFrame = collectionsState.contentFrame
    if contentFrame then
        contentFrame:SetParent(parent)
        contentFrame:ClearAllPoints()
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        collectionsState.contentFrame = contentFrame
    else
        contentFrame = CreateFrame("Frame", nil, parent)
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        collectionsState.contentFrame = contentFrame
        collectionsState.viewerContainer = nil
        collectionsState.mountListContainer = nil
        collectionsState.mountListScrollFrame = nil
        collectionsState.mountListScrollChild = nil
        collectionsState.mountListScrollBarContainer = nil
        collectionsState.petListContainer = nil
        collectionsState.petListScrollFrame = nil
        collectionsState.petListScrollChild = nil
        collectionsState.petListScrollBarContainer = nil
        collectionsState.achievementListContainer = nil
        collectionsState.achievementListScrollFrame = nil
        collectionsState.achievementListScrollChild = nil
        collectionsState.achievementListScrollBarContainer = nil
        collectionsState.achievementDetailPanel = nil
        collectionsState.achievementDetailContainer = nil
        collectionsState.modelViewer = nil
        collectionsState.loadingPanel = nil
        collectionsState._achFlatList = nil
        collectionsState._achVisibleRowFrames = nil
        collectionsState._achListContentFrame = nil
    end

    -- Draw current sub-tab content
    if collectionsState.currentSubTab == "mounts" then
        DrawMountsContent(contentFrame)
    elseif collectionsState.currentSubTab == "pets" then
        DrawPetsContent(contentFrame)
    elseif collectionsState.currentSubTab == "achievements" then
        DrawAchievementsContent(contentFrame)
    end

    yOffset = yOffset + contentHeight + bottomPad

    -- Event-driven updates (same events as Plans): all sub-tabs (Mounts, Pets, Achievements) refresh when these fire.
    if not collectionsState._messageRegistered then
        collectionsState._messageRegistered = true

        local eventName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_PROGRESS) or "WN_COLLECTION_SCAN_PROGRESS"
        WarbandNexus:RegisterMessage(eventName, function()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" and collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        local completeName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE) or "WN_COLLECTION_SCAN_COMPLETE"
        WarbandNexus:RegisterMessage(completeName, function()
            collectionsState._cachedMountsData = nil
            collectionsState._cachedPetsData = nil
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end
        end)

        -- Real-time collection update (mount/pet/toy/achievement obtained) — defer refresh like Plans
        local updatedName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED) or "WN_COLLECTION_UPDATED"
        WarbandNexus:RegisterMessage(updatedName, function(_, updatedType)
            if updatedType ~= "mount" and updatedType ~= "pet" and updatedType ~= "toy" and updatedType ~= "achievement" then return end
            collectionsState._cachedMountsData = nil
            collectionsState._cachedPetsData = nil
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end)
        end)
    end

    return yOffset
end
