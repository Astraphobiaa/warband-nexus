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
local PlanCardFactory = ns.UI_PlanCardFactory
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
local DETAIL_ICON_SIZE = LAYOUT.DETAIL_ICON_SIZE or 64  -- Detail panel icon (Pets/Mounts/Toy/Achievement)
local STATUS_ICON_SIZE = LAYOUT.STATUS_ICON_SIZE or 16
local SCROLL_CONTENT_TOP_PADDING = LAYOUT.SCROLL_CONTENT_TOP_PADDING or 12
-- Symmetric layout: all panels use same inset; no magic numbers.
local CONTENT_INSET = LAYOUT.CONTENT_INSET or LAYOUT.CARD_GAP or 8
local CONTAINER_INSET = LAYOUT.CONTAINER_INSET or 2
local TEXT_GAP = AFTER_ELEMENT
local SEARCH_ROW_HEIGHT = 32  -- Plans ile birebir aynı
-- Header kartı: sadece başlık; search bar sekmelerin altında. Plans ile aynı: header sonrası GetLayout().afterHeader (75)
local COLLECTIONS_HEADER_CARD_HEIGHT = 70
local AFTER_HEADER = LAYOUT.afterHeader or 75
local SUBTAB_BAR_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
local HEADER_ICON_TEXT_GAP = 12
local PROGRESS_ROW_HEIGHT = 28
local BAR_INSET = 2  -- Bar 2px each side = total 4px inside border

-- ============================================================================
-- MOUNT SOURCE CLASSIFICATION
-- ============================================================================

-- Anlamca eşleşen, projede kullanıldığı bilinen Blizzard atlas'ları (kategori ile doğrudan ilişkili)
local L = ns.L
local SOURCE_CATEGORIES = {
    { key = "drop",        label = (L and L["SOURCE_TYPE_DROP"]) or "Drop",              iconAtlas = "ParagonReputation_Bag" },
    { key = "vendor",      label = (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor",          iconAtlas = "coin-gold" },
    { key = "quest",       label = (L and L["SOURCE_TYPE_QUEST"]) or "Quest",            iconAtlas = "quest-legendary-turnin" },
    { key = "achievement", label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement", iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "profession",  label = (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession",  iconAtlas = "poi-workorders" },
    { key = "reputation",  label = (L and L["PARSE_REPUTATION"]) or "Reputation",        iconAtlas = "MajorFactions_MapIcons_Centaur64" },
    { key = "pvp",         label = (L and L["SOURCE_TYPE_PVP"]) or "PvP",                iconAtlas = "honorsystem-icon-prestige-9" },
    { key = "worldevent",  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event", iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion",    iconAtlas = "Bonus-Objective-Star" },
    { key = "tradingpost", label = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post", iconAtlas = "Auctioneer" },
    { key = "treasure",    label = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",      iconAtlas = "VignetteLoot" },
    { key = "unknown",     label = (L and L["SOURCE_OTHER"]) or "Other",                 iconAtlas = "poi-town" },
}

local SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(SOURCE_CATEGORIES) do
    SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- Pet-specific categories: Pet Battle, Puzzle added; Pet Battle is its own category (not achievement).
local PET_SOURCE_CATEGORIES = {
    { key = "petbattle",   label = (ns.L and ns.L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle", iconAtlas = "WildBattlePetCapturable" },
    { key = "drop",        label = (L and L["SOURCE_TYPE_DROP"]) or "Drop",              iconAtlas = "ParagonReputation_Bag" },
    { key = "vendor",      label = (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor",          iconAtlas = "coin-gold" },
    { key = "quest",       label = (L and L["SOURCE_TYPE_QUEST"]) or "Quest",            iconAtlas = "quest-legendary-turnin" },
    { key = "achievement", label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement", iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "profession",  label = (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession",  iconAtlas = "poi-workorders" },
    { key = "reputation",  label = (L and L["PARSE_REPUTATION"]) or "Reputation",        iconAtlas = "MajorFactions_MapIcons_Centaur64" },
    { key = "pvp",         label = (L and L["SOURCE_TYPE_PVP"]) or "PvP",                iconAtlas = "honorsystem-icon-prestige-9" },
    { key = "worldevent",  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event", iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   label = (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion",    iconAtlas = "Bonus-Objective-Star" },
    { key = "tradingpost", label = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post", iconAtlas = "Auctioneer" },
    { key = "treasure",    label = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",      iconAtlas = "VignetteLoot" },
    { key = "puzzle",      label = (L and L["SOURCE_TYPE_PUZZLE"]) or "Puzzle",          iconAtlas = "UpgradeItem-32x32" },
    { key = "unknown",     label = (L and L["SOURCE_OTHER"]) or "Other",                 iconAtlas = "poi-town" },
}

local PET_SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(PET_SOURCE_CATEGORIES) do
    PET_SOURCE_CATEGORY_ORDER[cat.key] = i
end

-- Toy-specific categories: mapped from C_ToyBox source type filter indices (BattlePetSources DBC enum, 1-indexed in Lua)
local TOY_SOURCE_CATEGORIES = {
    { key = "drop",        sourceIndex = 1,  label = (L and L["SOURCE_TYPE_DROP"]) or "Drop",                iconAtlas = "ParagonReputation_Bag" },
    { key = "quest",       sourceIndex = 2,  label = (L and L["SOURCE_TYPE_QUEST"]) or "Quest",              iconAtlas = "quest-legendary-turnin" },
    { key = "vendor",      sourceIndex = 3,  label = (L and L["SOURCE_TYPE_VENDOR"]) or "Vendor",            iconAtlas = "coin-gold" },
    { key = "profession",  sourceIndex = 4,  label = (L and L["SOURCE_TYPE_PROFESSION"]) or "Profession",    iconAtlas = "poi-workorders" },
    { key = "achievement", sourceIndex = 6,  label = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement",  iconAtlas = "UI-Achievement-Shield-NoPoints" },
    { key = "worldevent",  sourceIndex = 7,  label = (L and L["SOURCE_TYPE_WORLD_EVENT"]) or "World Event",  iconAtlas = "characterupdate_clock-icon" },
    { key = "promotion",   sourceIndex = 8,  label = (L and L["SOURCE_TYPE_PROMOTION"]) or "Promotion",      iconAtlas = "Bonus-Objective-Star" },
    { key = "tcg",         sourceIndex = 9,  label = (L and L["SOURCE_TYPE_TRADING_CARD"]) or "Trading Card", iconAtlas = "Auctioneer" },
    { key = "petstore",    sourceIndex = 10, label = (L and L["SOURCE_TYPE_IN_GAME_SHOP"]) or "In-Game Shop", iconAtlas = "coin-gold" },
    { key = "tradingpost", sourceIndex = 11, label = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post", iconAtlas = "Auctioneer" },
    { key = "unknown",     sourceIndex = 0,  label = (L and L["SOURCE_OTHER"]) or "Other",                   iconAtlas = "poi-town" },
}

local TOY_SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(TOY_SOURCE_CATEGORIES) do
    TOY_SOURCE_CATEGORY_ORDER[cat.key] = i
end

local SOURCE_INDEX_TO_TOY_CAT = {
    [1] = "drop", [2] = "quest", [3] = "vendor", [4] = "profession",
    [5] = "petbattle", [6] = "achievement", [7] = "worldevent",
    [8] = "promotion", [9] = "tcg", [10] = "petstore", [11] = "tradingpost",
}

-- Single parse system: ParseSourceText (PlansUI) → category key. Used for mount, pet, toy.
local PARSE_SOURCE_TYPE_TO_CATEGORY = {
    ["Vendor"] = "vendor",
    ["Drop"] = "drop",
    ["Quest"] = "quest",
    ["Achievement"] = "achievement",
    ["Crafted"] = "profession",
    ["Promotion"] = "promotion",
    ["Trading Post"] = "tradingpost",
    ["Pet Battle"] = "achievement",
    ["World Event"] = "worldevent",
    ["Treasure"] = "treasure",
    ["Reputation"] = "reputation",
    ["PvP"] = "pvp",
    ["Puzzle"] = "unknown",
}
local PARSE_SOURCE_TYPE_TO_PET_CATEGORY = {
    ["Vendor"] = "vendor",
    ["Drop"] = "drop",
    ["Quest"] = "quest",
    ["Achievement"] = "achievement",
    ["Crafted"] = "profession",
    ["Promotion"] = "promotion",
    ["Trading Post"] = "tradingpost",
    ["Pet Battle"] = "petbattle",
    ["World Event"] = "worldevent",
    ["Treasure"] = "treasure",
    ["Reputation"] = "reputation",
    ["PvP"] = "pvp",
    ["Puzzle"] = "puzzle",
}

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

-- Single parse system: WarbandNexus:ParseSourceText (PlansUI) + mapping. kind = "mount" | "pet" | "toy".
local function ClassifySource(cache, sourceText, kind)
    kind = kind or "mount"
    local key = (sourceText or "") .. "\0" .. kind
    local c = cache[key]
    if c ~= nil then return c end
    local parts = WarbandNexus.ParseSourceText and WarbandNexus:ParseSourceText(sourceText or "") or {}
    local st = parts and parts.sourceType
    local map = (kind == "pet") and PARSE_SOURCE_TYPE_TO_PET_CATEGORY or PARSE_SOURCE_TYPE_TO_CATEGORY
    c = (st and map[st]) or "unknown"
    if c == "unknown" and sourceText and type(sourceText) == "string" and sourceText ~= "" then
        local trimmed = sourceText:gsub("|n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed ~= "Unknown" then
            c = "drop"
        end
    end
    cache[key] = c
    return c
end
local function ClassifyMountSourceCached(cache, sourceText)
    return ClassifySource(cache, sourceText, "mount")
end
local function ClassifyPetSourceCached(cache, sourceText)
    return ClassifySource(cache, sourceText, "pet")
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
-- Single source: bar/button sizes and column width so Mounts/Pets/Toys/Achievements look identical
local SCROLLBAR_GAP = (ns.UI_LAYOUT and ns.UI_LAYOUT.SCROLLBAR_COLUMN_WIDTH) or 22
local SCROLLBAR_SIDE_GAP = 5  -- Equal gap between list <-> scrollbar and scrollbar <-> details
-- Match Plans: defer sub-tab draw and heavy work by 0.05s for smooth switching.
local COLLECTION_HEAVY_DELAY = 0.05
-- Process this many mounts/pets per frame to avoid 1s freeze (spread over multiple frames).
local RUN_CHUNK_SIZE = 100
-- Same row/header dimensions for all three sub-tabs (Mounts, Pets, Achievements); matches SharedWidgets/UI_SPACING
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 26
local HEADER_HEIGHT = LAYOUT.HEADER_HEIGHT or 32

-- Detail container border: SharedWidgets 4-texture border system (accent)
local function ApplyDetailAccentVisuals(frame)
    if ns.UI_ApplyDetailContainerVisuals then
        ns.UI_ApplyDetailContainerVisuals(frame)
    elseif frame and ApplyVisuals then
        ApplyVisuals(frame, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
end

local function ScrollFrameByMouseWheel(scrollFrame, delta)
    if not scrollFrame then return end
    local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
    local cur = scrollFrame:GetVerticalScroll()
    local maxS = scrollFrame:GetVerticalScrollRange()
    local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
    scrollFrame:SetVerticalScroll(newScroll)
    if scrollFrame.ScrollBar and scrollFrame.ScrollBar.SetValue then
        scrollFrame.ScrollBar:SetValue(newScroll)
    end
end

local function EnableStandardScrollWheel(scrollFrame)
    if not scrollFrame then return end
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        ScrollFrameByMouseWheel(self, delta)
    end)
end

local function CreateStandardScrollChild(scrollFrame, width, height)
    if not scrollFrame or not Factory or not Factory.CreateContainer then return nil end
    local scrollChild = Factory:CreateContainer(scrollFrame, width or 1, height or 1, false)
    if width then
        scrollChild:SetWidth(width)
    end
    if height then
        scrollChild:SetHeight(height)
    end
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:EnableMouseWheel(true)
    scrollChild:SetScript("OnMouseWheel", function(_, delta)
        ScrollFrameByMouseWheel(scrollFrame, delta)
    end)
    return scrollChild
end

local function EnsureListScrollBarContainer(existingContainer, parent, anchorFrame, columnWidth, height, sideGap)
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, height, false)
    end
    container:SetSize(columnWidth, height)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", sideGap or 0, 0)
    container:SetFrameLevel((anchorFrame and anchorFrame:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- Details scrollbar: üst/alt boşluk (küçük = scrollbar daha uzun, aşağı/yukarı uzar)
local DETAIL_SCROLLBAR_VERTICAL_INSET = 4

local function EnsureDetailScrollBarContainer(existingContainer, parent, columnWidth, inset, verticalInset)
    verticalInset = verticalInset or DETAIL_SCROLLBAR_VERTICAL_INSET
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, 1, false)
    end
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -verticalInset)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, verticalInset)
    container:SetWidth(columnWidth)
    container:SetFrameLevel((parent and parent:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- ============================================================================
-- DETAILS WINDOW DIFFERENCES: Mounts vs ToyBox vs Achievement
-- ============================================================================
-- Mounts: viewerContainer (CreateContainer) → mountDetailEmptyOverlay + modelViewer (CreateModelViewer).
--   Single panel: icon, name, source, description, 3D model. No scroll; content fixed in one panel.
-- ToyBox: toyDetailContainer (CreateContainer) → toyDetailEmptyOverlay + _toyDetailScroll (ScrollFrame).
--   ScrollChild has: headerRow (icon, name), collectedBadge, sourceLabel. Scroll-based; no 3D model.
-- Achievement: achievementDetailContainer (CreateContainer) → achDetailEmptyOverlay + achievementDetailPanel.
--   achievementDetailPanel = CreateAchievementDetailPanel (Frame + inner ScrollFrame, dynamic content:
--   description, achievement series list, criteria). Panel has its own border/ApplyVisuals and scroll.
-- All three use CreateDetailEmptyOverlay(container, typeKey) for empty state; same overlay styling.
-- ============================================================================

-- Empty detail state: single centered line "Select a X to see details." (all 4 collection tabs)
-- Neutral grey background, no border. Inset by 1px so parent's accent border stays visible.
local BORDER_INSET = 1
local function CreateDetailEmptyOverlay(parent, typeKey)
    if not parent then return nil end
    local w = parent:GetWidth() or 200
    local h = parent:GetHeight() or 200
    local overlay = Factory:CreateContainer(parent, w, h, false)
    if not overlay then return nil end
    overlay:SetPoint("TOPLEFT", parent, "TOPLEFT", BORDER_INSET, -BORDER_INSET)
    overlay:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
    overlay:EnableMouse(false)
    if ApplyVisuals then ApplyVisuals(overlay, {0.08, 0.08, 0.10, 0.98}, {0, 0, 0, 0}) end
    local fmt = (ns.L and ns.L["SELECT_TO_SEE_DETAILS"]) or "Select a %s to see details."
    if fmt == "SELECT_TO_SEE_DETAILS" then fmt = "Select a %s to see details." end
    local typeName = (typeKey == "mount" and ((ns.L and ns.L["TYPE_MOUNT"]) or "mount"))
        or (typeKey == "pet" and ((ns.L and ns.L["TYPE_PET"]) or "pet"))
        or (typeKey == "toy" and ((ns.L and ns.L["TYPE_TOY"]) or "toy"))
        or (typeKey == "achievement" and ((ns.L and ns.L["ACHIEVEMENT"]) or "achievement"))
        or typeKey
    if typeName == "TYPE_MOUNT" then typeName = "mount" end
    if typeName == "TYPE_PET" then typeName = "pet" end
    if typeName == "TYPE_TOY" then typeName = "toy" end
    if typeName == "ACHIEVEMENT" then typeName = "achievement" end
    local text = string.format(fmt, typeName)
    local fs = FontManager:CreateFontString(overlay, "body", "OVERLAY")
    fs:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText("|cff888888" .. text .. "|r")
    fs:SetWordWrap(true)
    overlay.text = fs
    overlay:Hide()
    return overlay
end

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
    toyListContainer = nil,
    toyListScrollFrame = nil,
    toyListScrollChild = nil,
    toyListScrollBarContainer = nil,
    toyDetailContainer = nil,
    toyDetailScrollBarContainer = nil,
    collapsedHeadersToys = {},
    selectedToyID = nil,
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

---categoriesOverride: optional list of { key, label } for toys (C_ToyBox source type). If nil, uses SOURCE_CATEGORIES.
local function BuildFlatToyList(groupedData, collapsedHeaders, categoriesOverride)
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
    local categories = (categoriesOverride and #categoriesOverride > 0) and categoriesOverride or SOURCE_CATEGORIES
    local nCats = #categories
    for ci = 1, nCats do
        local catInfo = categories[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            local labelText = (catInfo.label and catInfo.label ~= "") and catInfo.label or key
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. labelText .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
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
                    flat[#flat + 1] = { type = "row", toy = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Toys: flat list only (no categories). items = array of { id, name, icon, collected }.
local function BuildFlatToyListOnly(items)
    local flat = {}
    local yOffset = 0
    for i = 1, #items do
        flat[#flat + 1] = { type = "row", toy = items[i], rowIndex = i, yOffset = yOffset, height = ROW_HEIGHT }
        yOffset = yOffset + ROW_HEIGHT
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
local DEFAULT_ICON_TOY = "Interface\\Icons\\INV_Misc_Toy_07"
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

local function AcquireToyRow(scrollChild, listWidth, item, selectedToyID, onSelectToy, redraw, cf)
    local toy = item.toy
    local nameColor = (toy.isCollected or toy.collected) and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (toy.name or "") .. "|r"
    return AcquireCollectionRow(scrollChild, item, 0, toy.icon or DEFAULT_ICON_TOY, labelText, (toy.isCollected == true) or (toy.collected == true), selectedToyID, toy.id, function()
        if onSelectToy then
            onSelectToy(toy.id, toy.name, toy.icon, toy.source, toy.description, (toy.isCollected == true) or (toy.collected == true), toy.sourceTypeName)
        end
    end, function()
        if collectionsState._toyFlatList and collectionsState.toyListScrollFrame then
            collectionsState._toyListSelectedID = toy.id
            local r = collectionsState._toyListRefreshVisible
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
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
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
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
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

local _populateToyListBusy = false
local _toyScrollUpdateScheduled = false

local function UpdateToyListVisibleRange()
    local state = collectionsState
    local flatList = state._toyFlatList
    local scrollFrame = state.toyListScrollFrame
    local scrollChild = state.toyListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._toyVisibleRowFrames
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
    state._toyVisibleRowFrames = {}
    local redraw = state._toyListRedrawFn
    local cf = state._toyListContentFrame
    local selectedToyID = state._toyListSelectedID or state.selectedToyID
    local onSelectToy = state._toyListOnSelectToy
    local listWidth = state._toyListWidth or scrollChild:GetWidth()
    local n = #flatList
    local startIdx, endIdx = 1, n
    for i = 1, n do
        local it = flatList[i]
        if startIdx == 1 and it.yOffset + it.height > scrollTop then startIdx = i end
        if it.yOffset < bottom then endIdx = i else break end
    end
    for i = startIdx, endIdx do
        local it = flatList[i]
        if it.type == "row" then
            local frame = AcquireToyRow(scrollChild, listWidth, it, selectedToyID, onSelectToy, nil, cf)
            state._toyVisibleRowFrames[#state._toyVisibleRowFrames + 1] = { frame = frame, flatIndex = i }
        end
    end
end

local function PopulateToyList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populateToyListBusy then return end
    _populateToyListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    local visible = collectionsState._toyVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._toyVisibleRowFrames = {}
    end

    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatToyList(groupedData, collapsedHeaders, TOY_SOURCE_CATEGORIES)
    scrollChild:SetHeight(totalHeight)

    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local function onToggle(expanded)
                collapsedHeaders[key] = not expanded
                local cached = collectionsState._lastGroupedToyData
                local sch = collectionsState.toyListScrollChild
                if cached and sch and cf and cf:IsVisible() then
                    PopulateToyList(sch, listWidth, cached, collapsedHeaders, selectedToyID, onSelectToy, cf, redraw)
                    if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                        Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
                    end
                elseif redraw and cf and cf:IsVisible() then
                    redraw(cf)
                end
            end
            local header = CreateCollapsibleHeader(scrollChild, it.label, key, not it.isCollapsed, onToggle, GetToyCategoryIcon(key), true, 0)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -it.yOffset)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)
        end
    end

    collectionsState._toyFlatList = flatList
    collectionsState._toyFlatListTotalHeight = totalHeight
    collectionsState._toyListWidth = listWidth
    collectionsState._toyListSelectedID = selectedToyID
    collectionsState._toyListOnSelectToy = onSelectToy
    collectionsState._toyListRedrawFn = redraw
    collectionsState._toyListContentFrame = cf
    collectionsState._toyListRefreshVisible = UpdateToyListVisibleRange

    local scrollFrame = collectionsState.toyListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            if _toyScrollUpdateScheduled then return end
            _toyScrollUpdateScheduled = true
            C_Timer.After(0, function()
                _toyScrollUpdateScheduled = false
                UpdateToyListVisibleRange()
            end)
        end)
    end
    C_Timer.After(0, UpdateToyListVisibleRange)
    _populateToyListBusy = false
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
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
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
    local panel = Factory:CreateContainer(parent, width, height, false)
    if not panel then return nil end
    panel:SetSize(width, height)
    ApplyDetailAccentVisuals(panel)

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
                local camDist = FIXED_CAM_DISTANCE * panel.zoomMultiplier * panel.modelScale
                local ok = pcall(model.SetCameraDistance, model, math.max(0.1, camDist))
                if not ok and model.SetCamDistanceScale then
                    model:SetCamDistanceScale(panel.camScale)
                end
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

    local DETAIL_HEADER_GAP = 10
    -- Detail icon with border (Factory CreateContainer + accent override)
    local iconBorder = Factory:CreateContainer(textOverlay, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
    iconBorder:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    if ApplyVisuals then
        ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
    end
    panel.detailIconBorder = iconBorder
    local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.detailIconTexture = iconTex

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local whiteR, whiteG, whiteB = 1, 1, 1

    -- Sağ üst Add container (nameText bunun soluna dayanacak)
    local addContainer = CreateFrame("Frame", nil, textOverlay)
    addContainer:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    addContainer:SetSize(80, 28)
    addContainer:Hide()
    panel._addContainer = addContainer
    if PlanCardFactory then
        panel._addBtn = PlanCardFactory.CreateAddButton(addContainer, {
            buttonType = "row",
            anchorPoint = "RIGHT",
            x = 0,
            y = 0,
        })
        if panel._addBtn then panel._addBtn:ClearAllPoints(); panel._addBtn:SetPoint("TOPRIGHT", addContainer, "TOPRIGHT", 0, 0) end
        panel._addedIndicator = PlanCardFactory.CreateAddedIndicator(addContainer, {
            buttonType = "row",
            label = (ns.L and ns.L["ADDED"]) or "Added",
            fontCategory = "body",
            anchorPoint = "RIGHT",
            x = 0,
            y = 0,
        })
        if panel._addedIndicator then
            panel._addedIndicator:ClearAllPoints()
            panel._addedIndicator:SetPoint("TOPRIGHT", addContainer, "TOPRIGHT", 0, 0)
            panel._addedIndicator:Hide()
        end
    end

    local nameText = FontManager:CreateFontString(textOverlay, "header", "OVERLAY")
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
    nameText:SetPoint("TOPRIGHT", addContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    nameText:SetTextColor(whiteR, whiteG, whiteB)
    panel.nameText = nameText

    local headerRowBottom = CreateFrame("Frame", nil, textOverlay)
    headerRowBottom:SetPoint("TOPLEFT", iconBorder, "BOTTOMLEFT", 0, 0)
    headerRowBottom:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, 0)
    headerRowBottom:SetHeight(1)
    panel.headerRowBottom = headerRowBottom

    local sourceContainer = CreateFrame("Frame", nil, textOverlay)
    sourceContainer:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceContainer:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceContainer:SetHeight(1)
    panel.sourceContainer = sourceContainer
    panel.sourceLines = {}

    -- Source label: gold color (consistent with Toy and all collection detail panels)
    local sourceLabel = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    sourceLabel:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceLabel:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetWordWrap(true)
    sourceLabel:SetNonSpaceWrap(false)
    sourceLabel:SetTextColor(goldR, goldG, goldB)
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
            -- İlk frame zoom-in olmasın: başta normalizedRadius=true, modelScale=1 ile sabit kamera kullan; radius gelince güncelle.
            panel.normalizedRadius = true
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
            panel.normalizedRadius = true
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

    local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
    local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"

    function panel:SetMountInfo(mountID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not mountID then
            local placeholder = (ns.L and ns.L["SELECT_MOUNT_FROM_LIST"]) or "Select a mount from the list"
            if placeholder == "" or placeholder == "SELECT_MOUNT_FROM_LIST" then placeholder = "Select a mount from the list" end
            nameText:SetText("|cff888888" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_MOUNT)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            for _, line in ipairs(panel.sourceLines) do
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn and panel._addedIndicator then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsMountPlanned and WarbandNexus:IsMountPlanned(mountID)
            local collected = isCollectedFromCache
            if collected then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(0.45)
            elseif planned then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(1)
            else
                panel._addedIndicator:Hide()
                panel._addBtn:Show()
                panel._addBtn:SetScript("OnClick", function()
                    if WarbandNexus and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = "mount",
                            mountID = mountID,
                            name = name,
                            icon = icon,
                            source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                        })
                        if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                    end
                end)
            end
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_MOUNT)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
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
        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    function panel:SetPetInfo(speciesID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not speciesID then
            local placeholder = (ns.L and ns.L["SELECT_PET_FROM_LIST"]) or "Select a pet from the list"
            if placeholder == "" or placeholder == "SELECT_PET_FROM_LIST" then placeholder = "Select a pet from the list" end
            nameText:SetText("|cff888888" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_PET)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            for _, line in ipairs(panel.sourceLines) do
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn and panel._addedIndicator then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsPetPlanned and WarbandNexus:IsPetPlanned(speciesID)
            local collected = isCollectedFromCache
            if collected then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(0.45)
            elseif planned then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(1)
            else
                panel._addedIndicator:Hide()
                panel._addBtn:Show()
                panel._addBtn:SetScript("OnClick", function()
                    if WarbandNexus and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = "pet",
                            speciesID = speciesID,
                            name = name,
                            icon = icon,
                            source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                        })
                        if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                    end
                end)
            end
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_PET)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
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
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    function panel:SetMountInfo() end
    return panel
end

-- ============================================================================
-- LOADING STATE PANEL
-- ============================================================================

local function GetOrCreateLoadingPanel(parent)
    local UI_CreateLoadingStatePanel = ns.UI_CreateLoadingStatePanel
    if UI_CreateLoadingStatePanel then
        return UI_CreateLoadingStatePanel(parent)
    end
    local fallback = CreateFrame("Frame", nil, parent)
    fallback:SetAllPoints(parent)
    function fallback:ShowLoading() self:Show() end
    function fallback:HideLoading() self:Hide() end
    return fallback
end

-- ============================================================================
-- ACHIEVEMENT DETAIL PANEL — Parent/Children, Description, Criteria (replaces model viewer)
-- ============================================================================
-- Plans-style row button sizes (match PlanCardFactory row + Track 52x20)
local ACH_ROW_ADD_WIDTH = 70
local ACH_ROW_ADD_HEIGHT = 28
local ACH_TRACK_WIDTH = 52
local ACH_TRACK_HEIGHT = 20
local ACH_ACTION_GAP = 6

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

local function IsAchievementTracked(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.IsAchievementTracked then
        return WarbandNexus:IsAchievementTracked(achievementID)
    end
    return false
end

local function ToggleAchievementTracking(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.ToggleAchievementTracking then
        return WarbandNexus:ToggleAchievementTracking(achievementID)
    end
    return false
end

local function CreateAchievementDetailPanel(parent, width, height, onSelectAchievement)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyDetailAccentVisuals(panel)

    panel._scrollBarContainer = EnsureDetailScrollBarContainer(panel._scrollBarContainer, panel, SCROLLBAR_GAP, CONTAINER_INSET)
    local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
    scroll:SetPoint("BOTTOMRIGHT", panel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
    EnableStandardScrollWheel(scroll)
    panel.scrollFrame = scroll

    local child = CreateStandardScrollChild(scroll, width - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
    if scroll.ScrollBar then
        Factory:PositionScrollBarInContainer(scroll.ScrollBar, panel._scrollBarContainer, CONTAINER_INSET)
    end

    local content = child
    local lastAnchor = content
    local lastPoint = "TOPLEFT"
    local lastY = 0
    local TEXT_GAP_LINE = TEXT_GAP

    panel._detailElements = {}

    local function clearDetailElements()
        local bin = ns.UI_RecycleBin
        for _, el in ipairs(panel._detailElements) do
            el:Hide()
            if bin then el:SetParent(bin) else el:SetParent(nil) end
        end
        panel._detailElements = {}
    end

    local function addDetailElement(el)
        if el then
            panel._detailElements[#panel._detailElements + 1] = el
        end
    end

    -- Achievement details: sola hizalı (tüm içerik CONTENT_INSET’ten başlar)
    local SECTION_GAP = 4       -- gap between section title and body
    local SECTION_HEADER_GAP = 10  -- gap between section blocks (Description / Series / Criteria)
    local ICON_LEFT_INSET = 2  -- icons 2px right from row edge
    local CONTENT_COLUMN_LEFT = CONTENT_INSET  -- section titles, description, criteria (sola hizalı)
    local ROW_TEXT_LEFT = CONTENT_INSET + ICON_LEFT_INSET + ROW_ICON_SIZE + (CONTENT_INSET / 2)  -- series row name (after icon; completed/not icon kaldırıldı)

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0

    local function addSection(title, fn)
        local titleFs = FontManager:CreateFontString(content, "body", "OVERLAY")
        titleFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
        titleFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
        titleFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(true)
        titleFs:SetTextColor(goldR, goldG, goldB)
        titleFs:SetText(title or "")
        addDetailElement(titleFs)
        lastAnchor = titleFs
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP
        fn(titleFs)
    end

    local function addAchievementRow(ach, label, currentAchievementID)
        if not ach or not ach.id then return end
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOP", lastAnchor, lastPoint, 0, lastY)
        row:SetPoint("LEFT", content, "LEFT", CONTENT_INSET, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        local isCurrent = (currentAchievementID and ach.id == currentAchievementID)
        if ApplyVisuals then
            if isCurrent then
                ApplyVisuals(row, {0.1, 0.08, 0.05, 0.9}, {goldR, goldG, goldB, 0.85})
            else
                ApplyVisuals(row, {0.06, 0.06, 0.08, 0.5}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4})
            end
        end
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        icon:SetTexture(ach.icon or "Interface\\Icons\\Achievement_General")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local nameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
        nameFs:SetPoint("LEFT", row, "LEFT", ROW_TEXT_LEFT, 0)
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
        lastY = -SECTION_GAP
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

        -- Header: same hierarchy as Mounts/Pets (CONTENT_INSET from edges, icon then name)
        local headerRow = CreateFrame("Frame", nil, content)
        headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(math.max(ROW_HEIGHT + SECTION_GAP, DETAIL_ICON_SIZE + SECTION_GAP))
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if ApplyVisuals then
            ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
        end
        local headerIcon = iconBorder:CreateTexture(nil, "OVERLAY")
        headerIcon:SetAllPoints()
        headerIcon:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_General")
        headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local DETAIL_HEADER_GAP = 10
        local goldR = (COLORS.gold and COLORS.gold[1]) or 1
        local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local goldB = (COLORS.gold and COLORS.gold[3]) or 0
        -- Sağ üst: Add + Track (mount/pet/toy ile birebir aynı: PlanCardFactory row + Track 52x20, Plans ile aynı görsel)
        local addContainer = CreateFrame("Frame", nil, headerRow)
        addContainer:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        addContainer:SetSize(ACH_ROW_ADD_WIDTH + ACH_ACTION_GAP + ACH_TRACK_WIDTH, ACH_ROW_ADD_HEIGHT)

        -- Track: Add ile aynı köşesiz stil (border/background yok, sadece metin)
        local trackBtn = Factory:CreateButton(addContainer, ACH_TRACK_WIDTH, ACH_TRACK_HEIGHT, true)
        trackBtn:SetPoint("TOPRIGHT", addContainer, "TOPRIGHT", 0, 0)
        trackBtn:SetFrameLevel(headerRow:GetFrameLevel() + 10)
        trackBtn:SetScript("OnMouseDown", function() end)
        trackBtn:RegisterForClicks("AnyUp")
        local trackLabel = FontManager:CreateFontString(trackBtn, "body", "OVERLAY")
        trackLabel:SetPoint("CENTER")
        local trackedText = "|cff44ff44" .. ((ns.L and ns.L["TRACKED"]) or "Tracked") .. "|r"
        local trackText = "|cffffcc00" .. ((ns.L and ns.L["TRACK"]) or "Track") .. "|r"
        local function UpdateTrackButton()
            if achievement.isCollected then
                trackLabel:SetText("|cff888888" .. ((ns.L and ns.L["TRACK"]) or "Track") .. "|r")
                trackBtn:SetAlpha(0.45)
                trackBtn:EnableMouse(false)
            else
                trackLabel:SetText(IsAchievementTracked(achievement.id) and trackedText or trackText)
                trackBtn:SetAlpha(1)
                trackBtn:EnableMouse(true)
            end
        end
        trackBtn:SetScript("OnClick", function()
            if achievement.id then
                ToggleAchievementTracking(achievement.id)
                UpdateTrackButton()
            end
        end)
        trackBtn:SetScript("OnEnter", function()
            if trackBtn:IsMouseEnabled() then
                if trackLabel then trackLabel:SetTextColor(0.6, 0.9, 1, 1) end
                GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
                GameTooltip:SetText((ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
                GameTooltip:Show()
            end
        end)
        trackBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if trackLabel then
                trackLabel:SetText(IsAchievementTracked(achievement.id) and trackedText or trackText)
            end
        end)

        local addLabelText = (ns.L and ns.L["ADD_PLAN"]) or "+ Add"
        local addedLabelText = (ns.L and ns.L["ADDED"]) or "Added"
        local isPlanned = WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievement.id)
        local addBtn, addedIndicator
        if achievement.isCollected then
            addedIndicator = PlanCardFactory and PlanCardFactory.CreateAddedIndicator(addContainer, {
                buttonType = "row",
                label = addedLabelText,
                fontCategory = "body",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if addedIndicator then
                addedIndicator:ClearAllPoints()
                addedIndicator:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
                addedIndicator:SetAlpha(0.45)
            end
        elseif isPlanned then
            addedIndicator = PlanCardFactory and PlanCardFactory.CreateAddedIndicator(addContainer, {
                buttonType = "row",
                label = addedLabelText,
                fontCategory = "body",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if addedIndicator then
                addedIndicator:ClearAllPoints()
                addedIndicator:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
            end
        else
            addBtn = PlanCardFactory and PlanCardFactory.CreateAddButton(addContainer, {
                buttonType = "row",
                label = addLabelText,
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
                onClick = function()
                    if not achievement.id or not WarbandNexus or not WarbandNexus.AddPlan then return end
                    local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
                    local rewardText = rewardInfo and (rewardInfo.title or rewardInfo.itemName) or nil
                    WarbandNexus:AddPlan({
                        type = "achievement",
                        achievementID = achievement.id,
                        name = achievement.name,
                        icon = achievement.icon,
                        points = achievement.points,
                        source = achievement.source,
                        rewardText = rewardText,
                    })
                end,
            })
            if addBtn then
                addBtn:ClearAllPoints()
                addBtn:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
            end
        end

        UpdateTrackButton()

        local headerName = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        headerName:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        headerName:SetPoint("TOPRIGHT", addContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        headerName:SetJustifyH("LEFT")
        headerName:SetWordWrap(true)
        headerName:SetTextColor(goldR, goldG, goldB)
        headerName:SetText((achievement.name or "") .. (achievement.points and achievement.points > 0 and (" (" .. achievement.points .. " pts)") or ""))

        addDetailElement(headerRow)
        lastAnchor = headerRow
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP

        -- Description: tek satır "Description: metin" — sadece baş harf büyük, etiket sarı
        if achievement.description and achievement.description ~= "" then
            local rawLabel = (ns.L and ns.L["DESCRIPTION"]) or "Description"
            local descLabel = (rawLabel and rawLabel ~= "" and (string.upper(string.sub(rawLabel, 1, 1)) .. string.lower(string.sub(rawLabel, 2)))) or "Description"
            local goldHex = string.format("|cff%02x%02x%02x", goldR * 255, goldG * 255, goldB * 255)
            local descFs = FontManager:CreateFontString(content, "body", "OVERLAY")
            descFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
            descFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
            descFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
            descFs:SetJustifyH("LEFT")
            descFs:SetWordWrap(true)
            descFs:SetText(goldHex .. descLabel .. ":|r " .. (achievement.description or ""))
            addDetailElement(descFs)
            lastAnchor = descFs
            lastPoint = "BOTTOMLEFT"
            lastY = -SECTION_GAP
        end

        -- Achievement series (e.g. Level 10, 20, 30... 80): all tiers with check/cross; current achievement highlighted
        local seriesIds = BuildAchievementSeries(achievement.id)
        if seriesIds and #seriesIds > 1 then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["ACHIEVEMENT_SERIES"]) or "Achievement Series", function()
                for i = 1, #seriesIds do
                    local achID = seriesIds[i]
                    -- GetAchievementInfo: id, name, points, completed, month, day, year, description, flags, icon, ...
                    local ok, _, aName, aPoints, aCompleted, _, _, _, aDesc, _, aIcon = pcall(GetAchievementInfo, achID)
                    if ok and aName then
                        addAchievementRow({ id = achID, name = aName, icon = aIcon, points = aPoints, isCollected = aCompleted, description = aDesc }, nil, achievement.id)
                    end
                end
            end)
        end

        local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
        if rewardInfo and (rewardInfo.title or rewardInfo.itemName) then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["REWARD_LABEL"]) or "Reward", function(anchor)
                local rewardFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                rewardFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
                rewardFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, 0)
                rewardFs:SetJustifyH("LEFT")
                rewardFs:SetWordWrap(true)
                local txt = rewardInfo.title or rewardInfo.itemName or ""
                rewardFs:SetText("|cff00ff00" .. txt .. "|r")
                addDetailElement(rewardFs)
                lastAnchor = rewardFs
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end)
        end

        local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(achievement.id) or 0
        if numCriteria > 0 then
            lastY = lastY - SECTION_HEADER_GAP
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
                        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, lastY)
                        row:SetHeight(CRITERIA_LINE_HEIGHT)
                        -- Criteria satırı başlıkla aynı hizada: X ve metin CONTENT_COLUMN_LEFT’ten başlar
                        local critFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                        critFs:SetPoint("LEFT", row, "LEFT", CONTENT_COLUMN_LEFT + ICON_LEFT_INSET, 0)
                        critFs:SetPoint("RIGHT", row, "RIGHT", -CONTENT_INSET, 0)
                        critFs:SetJustifyH("LEFT")
                        critFs:SetWordWrap(true)
                        critFs:SetText(color .. (criteriaName or "") .. progressStr .. "|r")
                        addDetailElement(row)
                        lastAnchor = row
                        lastPoint = "BOTTOMLEFT"
                        lastY = -SECTION_GAP
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
    { key = "toys", label = (ns.L and ns.L["CATEGORY_TOYS"]) or (TOY_BOX or "Toys"), icon = "Interface\\Icons\\INV_Misc_Toy_07" },
    { key = "achievements", label = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
}

-- Plans category bar ile birebir aynı (catBtnHeight=40, catBtnSpacing=8, DEFAULT_CAT_BTN_WIDTH=150)
local SUBTAB_BTN_HEIGHT = 40
local SUBTAB_BTN_SPACING = 8
local SUBTAB_ICON_SIZE = 28
local SUBTAB_ICON_LEFT = 10
local SUBTAB_ICON_TEXT_GAP = 8
local SUBTAB_TEXT_RIGHT = 10
local SUBTAB_DEFAULT_WIDTH = 150

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

    local accentColor = COLORS.accent
    for i, tabInfo in ipairs(SUB_TABS) do
        local btnWidth = btnWidths[i]
        local btn = ns.UI.Factory:CreateButton(bar, btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
        end
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        -- Active indicator bar (main window tab ile aynı: alt çizgi vurgusu)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

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
                UpdateBorderColor(self, {accentColor[1] * 1.2, accentColor[2] * 1.2, accentColor[3] * 1.2, 0.9})
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                UpdateBorderColor(self, {accentColor[1], accentColor[2], accentColor[3], 0.6})
            end)
        else
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.10, 0.10, 0.12, 0.95) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.12, 0.12, 0.15, 1) end
            end)
        end

        buttons[tabInfo.key] = btn
        xPos = xPos + btnWidths[i] + spacing
    end

    bar.buttons = buttons

    function bar:SetActiveTab(key)
        local acc = COLORS.accent
        for k, btn in pairs(buttons) do
            if k == key then
                btn._active = true
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1}, {acc[1], acc[2], acc[3], 1})
                end
                if btn._text then
                    btn._text:SetTextColor(1, 1, 1)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "OUTLINE") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1], acc[2], acc[3], 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1) end
            else
                btn._active = false
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1})
                end
                if btn._text then
                    btn._text:SetTextColor(0.7, 0.7, 0.7)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 1) end
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
            elseif d.shouldHideOnChar then
                -- skip hidden/unobtainable mount
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
            -- Skip hidden mounts (10th return value from GetMountInfoByID)
            local shouldHide = false
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, _, _, _, _, _, _, _, _, sh = C_MountJournal.GetMountInfoByID(mountID)
                shouldHide = sh
            end
            if not shouldHide then
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
            if d and d.id and not d.shouldHideOnChar then
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

-- Toys: grouped by C_ToyBox source type. Returns { [catKey] = items[] } filtered by search and owned/missing.
local function GetFilteredToysGrouped(searchText, showCollected, showUncollected)
    local sourceGrouped = (WarbandNexus.GetToysDataGroupedBySourceType and WarbandNexus:GetToysDataGroupedBySourceType()) or {}
    local grouped = {}
    local query = (searchText or ""):lower()
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    for sourceIndex, group in pairs(sourceGrouped) do
        local catKey = SOURCE_INDEX_TO_TOY_CAT[sourceIndex] or "unknown"
        if not grouped[catKey] then grouped[catKey] = {} end
        local items = group.items or {}
        for i = 1, #items do
            local item = items[i]
            if item and item.id then
                local isCollected = (item.collected == true) or (item.isCollected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    local name = item.name or tostring(item.id)
                    if query == "" or (name:lower():find(query, 1, true)) then
                        grouped[catKey][#grouped[catKey] + 1] = item
                    end
                end
            end
        end
    end
    return grouped
end

local function BuildGroupedToyData(searchText, showCollected, showUncollected, optionalToys)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for _, cat in ipairs(SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src)
        return ClassifySource(classifyCache, src, "toy")
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allToys = (optionalToys and #optionalToys > 0) and optionalToys or (WarbandNexus.GetAllToysData and WarbandNexus:GetAllToysData()) or {}
    local query = (searchText or ""):lower()
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local function isReliableToySource(src)
        return WarbandNexus.IsReliableToySource and WarbandNexus:IsReliableToySource(src) or (src and src ~= "")
    end

    for i = 1, #allToys do
        local d = allToys[i]
        if d and d.id then
            local name = d.name or tostring(d.id)
            local isCollected = (d.isCollected == true) or (d.collected == true)
            if (showC and isCollected) or (showU and not isCollected) then
                if query == "" or (name and name:lower():find(query, 1, true)) then
                    local sourceText = d.source or ""
                    if not isReliableToySource(sourceText) then
                        local meta = WarbandNexus.ResolveCollectionMetadata and WarbandNexus:ResolveCollectionMetadata("toy", d.id)
                        if meta and isReliableToySource(meta.source) then
                            sourceText = meta.source
                        end
                    end
                    local catKey = classify(sourceText)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = d.id,
                            name = name,
                            icon = d.icon or DEFAULT_ICON_TOY,
                            source = sourceText,
                            description = d.description or "",
                            isCollected = isCollected,
                            collected = isCollected,
                        })
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    end
    return grouped
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
        collectionsState.modelViewer:SetMountInfo(nil)
        collectionsState.modelViewer:SetPetInfo(nil)
        collectionsState.modelViewer:Hide()
    end
    if collectionsState.petListContainer then collectionsState.petListContainer:Hide() end
    if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Hide() end
    if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
    if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
    if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
    if collectionsState.toyListContainer then collectionsState.toyListContainer:Hide() end
    if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Hide() end
    if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Hide() end
    if collectionsState.toyDetailScrollBarContainer then collectionsState.toyDetailScrollBarContainer:Hide() end
end

local function SetCollectionProgress(current, total)
    local bar = collectionsState.collectionProgressBar
    local lbl = collectionsState.collectionProgressLabel
    if bar then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue((total and total > 0 and current) and (current / total) or 0)
    end
    if lbl then
        lbl:SetText((current ~= nil and total ~= nil) and (tostring(current) .. " / " .. tostring(total)) or "— / —")
    end
end

local function EnsureCollectionProgressBar(rightCol)
    if collectionsState.collectionProgressFrame or not rightCol then return end
    local pr = CreateFrame("Frame", nil, rightCol)
    pr:SetHeight(PROGRESS_ROW_HEIGHT)
    pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
    local barWidth = (rightCol:GetWidth() and (rightCol:GetWidth() - 4)) or 200
    local barHeight = 22
    local barWrapper = CreateFrame("Frame", nil, pr, "BackdropTemplate")
    barWrapper:SetAllPoints(pr)
    if ApplyVisuals then
        ApplyVisuals(barWrapper, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
    end
    local innerW = math.max(1, barWidth - (BAR_INSET * 2))
    local innerH = math.max(1, barHeight - (BAR_INSET * 2))
    local statusBar = ns.UI_CreateStatusBar and ns.UI_CreateStatusBar(barWrapper, innerW, innerH, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5}, true)
    if statusBar then
        statusBar:ClearAllPoints()
        statusBar:SetPoint("TOPLEFT", barWrapper, "TOPLEFT", BAR_INSET, -BAR_INSET)
        statusBar:SetPoint("BOTTOMRIGHT", barWrapper, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
        statusBar:SetMinMaxValues(0, 1)
        statusBar:SetValue(0)
        local barTexture = statusBar:GetStatusBarTexture()
        if barTexture then barTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85) end
    end
    collectionsState.collectionProgressBar = statusBar
    local progressFs = FontManager:CreateFontString(pr, "body", "OVERLAY")
    if progressFs then
        if statusBar then
            progressFs:SetParent(statusBar)
            progressFs:SetDrawLayer("OVERLAY", 7)
            progressFs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
        else
            progressFs:SetPoint("CENTER", pr, "CENTER", 0, 0)
        end
        progressFs:SetJustifyH("CENTER")
        progressFs:SetJustifyV("MIDDLE")
        progressFs:SetTextColor(1, 1, 1)
        progressFs:SetText("— / —")
    end
    collectionsState.collectionProgressLabel = progressFs
    collectionsState.collectionProgressFrame = pr
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

    -- Layout: LEFT = list, gap, scrollbar, gap, RIGHT = 3D viewer (equal SCROLLBAR_SIDE_GAP each side of scrollbar).
    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()

    -- LEFT CONTAINER: List only (scroll frame fills it; scrollbar ayrı sütunda)
    if not collectionsState.mountListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, false)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.mountListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.mountListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.mountListScrollChild = scrollChild

        -- SCROLLBAR REZERVE: Liste ile 3D view arasında görünür (eşit boşluk).
        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, ch, SCROLLBAR_SIDE_GAP)
        collectionsState.mountListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.mountListContainer:SetSize(listContentWidth, ch)
        collectionsState.mountListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.mountListScrollBarContainer,
            contentFrame,
            collectionsState.mountListContainer,
            scrollBarColumnWidth,
            ch,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.mountListScrollFrame and collectionsState.mountListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.mountListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.mountListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = CreateFrame("Frame", nil, contentFrame)
        rightCol:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
        rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, ch - detailTop)

    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer
        ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(viewerContainer, "mount")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            collectionsState.mountDetailEmptyOverlay = emptyOverlay
        end
        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
        if not collectionsState.selectedMountID then
            mv:Hide()
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
        end
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetParent(rightCol)
            collectionsState.viewerContainer:ClearAllPoints()
            if pr then
                collectionsState.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            ApplyDetailAccentVisuals(collectionsState.viewerContainer)
            if not collectionsState.mountDetailEmptyOverlay then
                local emptyOverlay = CreateDetailEmptyOverlay(collectionsState.viewerContainer, "mount")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(collectionsState.viewerContainer:GetFrameLevel() + 5)
                    collectionsState.mountDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectMount(mountID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedMountID = mountID
        if collectionsState.mountDetailEmptyOverlay then
            collectionsState.mountDetailEmptyOverlay:SetShown(not mountID)
        end
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetShown(mountID ~= nil)
            if mountID then
                collectionsState.modelViewer:SetMount(mountID, creatureDisplayID)
                collectionsState.modelViewer:SetMountInfo(mountID, name, icon, source, description, isCollected)
            else
                collectionsState.modelViewer:SetMount(nil)
                collectionsState.modelViewer:SetMountInfo(nil)
            end
        end
    end
    if collectionsState.modelViewer and not collectionsState.selectedMountID then
        if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
        collectionsState.modelViewer:Hide()
    else
        if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
    end
    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Mounts show only mount or empty, never previous pet.
    if collectionsState.modelViewer then
        if collectionsState.selectedMountID then
            local mid = collectionsState.selectedMountID
            local md
            local am = collectionsState._cachedMountsData
            if am then
                for i = 1, #am do
                    if am[i].id == mid then md = am[i]; break end
                end
            end
            if md then
                collectionsState.modelViewer:SetMount(mid, md.creatureDisplayID)
                collectionsState.modelViewer:SetMountInfo(mid, md.name, md.icon, md.source, md.description, md.isCollected)
            else
                collectionsState.modelViewer:SetMount(mid, nil)
                collectionsState.modelViewer:SetMountInfo(mid, nil, nil, nil, nil, nil)
            end
        else
            collectionsState.modelViewer:SetMount(nil)
            collectionsState.modelViewer:SetPet(nil)
            collectionsState.modelViewer:SetMountInfo(nil)
            collectionsState.modelViewer:SetPetInfo(nil)
        end
    end

    -- Loading only when a scan is in progress or we have not yet completed initial fetch (no cache).
    -- Cache is set even when list is empty so we don't show loading forever for 0 mounts.
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allMounts = collectionsState._cachedMountsData
    local dataReady = (allMounts ~= nil)
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
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
                collectionsState._cachedMountsData = am
                if #am == 0 and WarbandNexus.EnsureCollectionData then
                    WarbandNexus:EnsureCollectionData()
                end
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
                local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
                SetCollectionProgress(collected, total)
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
                if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if not collectionsState.selectedMountID then
                    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
                else
                    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                end
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
        if not collectionsState.selectedMountID then
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
        else
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.mountListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
        local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
        SetCollectionProgress(collected, total)
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
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()

    -- LEFT CONTAINER: Pet list
    if not collectionsState.petListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, false)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.petListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.petListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.petListScrollChild = scrollChild

        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, ch, SCROLLBAR_SIDE_GAP)
        collectionsState.petListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.petListContainer:SetSize(listContentWidth, ch)
        collectionsState.petListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.petListScrollBarContainer,
            contentFrame,
            collectionsState.petListContainer,
            scrollBarColumnWidth,
            ch,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.petListScrollFrame and collectionsState.petListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.petListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.petListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = CreateFrame("Frame", nil, contentFrame)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.petListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, ch - detailTop)

    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer
        ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(viewerContainer, "pet")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            collectionsState.petDetailEmptyOverlay = emptyOverlay
        end
        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
        if not collectionsState.selectedPetID then
            mv:Hide()
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
        end
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetParent(rightCol)
            collectionsState.viewerContainer:ClearAllPoints()
            if pr then
                collectionsState.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            ApplyDetailAccentVisuals(collectionsState.viewerContainer)
            if not collectionsState.petDetailEmptyOverlay then
                local emptyOverlay = CreateDetailEmptyOverlay(collectionsState.viewerContainer, "pet")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(collectionsState.viewerContainer:GetFrameLevel() + 5)
                    collectionsState.petDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectPet(speciesID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedPetID = speciesID
        if collectionsState.petDetailEmptyOverlay then
            collectionsState.petDetailEmptyOverlay:SetShown(not speciesID)
        end
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetShown(speciesID ~= nil)
            if speciesID then
                collectionsState.modelViewer:SetPet(speciesID, creatureDisplayID)
                collectionsState.modelViewer:SetPetInfo(speciesID, name, icon, source, description, isCollected)
            else
                collectionsState.modelViewer:SetPet(nil)
                collectionsState.modelViewer:SetPetInfo(nil)
            end
        end
    end
    if collectionsState.modelViewer and not collectionsState.selectedPetID then
        if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
        collectionsState.modelViewer:Hide()
    else
        if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
    end
    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Pets show only pet or empty, never previous mount.
    if collectionsState.modelViewer then
        if collectionsState.selectedPetID then
            local sid = collectionsState.selectedPetID
            local pd
            local ap = collectionsState._cachedPetsData
            if ap then
                for i = 1, #ap do
                    if ap[i].id == sid then pd = ap[i]; break end
                end
            end
            if pd then
                collectionsState.modelViewer:SetPet(sid, pd.creatureDisplayID)
                collectionsState.modelViewer:SetPetInfo(sid, pd.name, pd.icon, pd.source, pd.description, pd.isCollected)
            else
                collectionsState.modelViewer:SetPet(sid, nil)
                collectionsState.modelViewer:SetPetInfo(sid, nil, nil, nil, nil, nil)
            end
        else
            collectionsState.modelViewer:SetMount(nil)
            collectionsState.modelViewer:SetPet(nil)
            collectionsState.modelViewer:SetMountInfo(nil)
            collectionsState.modelViewer:SetPetInfo(nil)
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
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
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
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
                local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
                SetCollectionProgress(collected, total)
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.petListContainer then collectionsState.petListContainer:Show() end
                if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if not collectionsState.selectedPetID then
                    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
                else
                    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                end
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
        if not collectionsState.selectedPetID then
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
        else
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.petListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
        local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
        SetCollectionProgress(collected, total)
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

-- DrawToysContent: list left (grouped by source), toy detail panel right (icon, name, source, description). No 3D viewer.
local function DrawToysContent(contentFrame)
    if collectionsState._drawToysContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawToysContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawToysContentBusy = true
    collectionsState._toysDrawGen = (collectionsState._toysDrawGen or 0) + 1
    local drawGen = collectionsState._toysDrawGen
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
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()

    -- LEFT: Toy list container + scroll
    if not collectionsState.toyListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, false)
        listContainer:SetPoint("TOPLEFT", 0, 0)
        listContainer:Show()
        collectionsState.toyListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.toyListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.toyListScrollChild = scrollChild

        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, ch, SCROLLBAR_SIDE_GAP)
        collectionsState.toyListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.toyListContainer:SetSize(listContentWidth, ch)
        collectionsState.toyListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.toyListScrollBarContainer,
            contentFrame,
            collectionsState.toyListContainer,
            scrollBarColumnWidth,
            ch,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.toyListScrollFrame and collectionsState.toyListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.toyListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.toyListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + toy detail panel (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = CreateFrame("Frame", nil, contentFrame)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.toyListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, ch - detailTop)

    -- RIGHT: Toy detail panel — anchored below progress so they never overlap
    local SECTION_BODY_INDENT = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 12
    local TEXT_GAP_LINE = TEXT_GAP or 8
    if not collectionsState.toyDetailContainer then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        collectionsState.toyDetailContainer = detailContainer
        ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(detailContainer, "toy")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            collectionsState.toyDetailEmptyOverlay = emptyOverlay
        end

        collectionsState.toyDetailScrollBarContainer = EnsureDetailScrollBarContainer(
            collectionsState.toyDetailScrollBarContainer,
            detailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        local scroll = Factory:CreateScrollFrame(detailContainer, "UIPanelScrollFrameTemplate", true)
        scroll:SetPoint("TOPLEFT", detailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
        scroll:SetPoint("BOTTOMRIGHT", collectionsState.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
        EnableStandardScrollWheel(scroll)
        collectionsState._toyDetailScroll = scroll

        local scrollChild = CreateStandardScrollChild(scroll, detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
        collectionsState._toyDetailScrollChild = scrollChild
        if scroll.ScrollBar then
            Factory:PositionScrollBarInContainer(scroll.ScrollBar, collectionsState.toyDetailScrollBarContainer, CONTAINER_INSET)
        end

        -- Header row: same hierarchy as Mounts/Pets (CONTENT_INSET from edges, icon then name)
        local headerRow = CreateFrame("Frame", nil, scrollChild)
        headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(math.max(ROW_HEIGHT + TEXT_GAP_LINE, DETAIL_ICON_SIZE + TEXT_GAP_LINE))
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if ApplyVisuals then
            ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
        end
        local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
        iconTex:SetAllPoints()
        iconTex:SetTexture(DEFAULT_ICON_TOY)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        collectionsState._toyDetailIcon = iconTex
        collectionsState._toyDetailIconBorder = iconBorder

        local DETAIL_HEADER_GAP = 10
        local goldR = (COLORS.gold and COLORS.gold[1]) or 1
        local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local goldB = (COLORS.gold and COLORS.gold[3]) or 0
        local nameFs = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        nameFs:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        nameFs:SetNonSpaceWrap(true)
        nameFs:SetTextColor(goldR, goldG, goldB)
        nameFs:SetText("")
        collectionsState._toyDetailName = nameFs
        collectionsState._toyDetailHeaderRow = headerRow

        -- Sağ üst: + Add / Added (PlanCardFactory row, toy için)
        local toyAddContainer = CreateFrame("Frame", nil, headerRow)
        toyAddContainer:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        toyAddContainer:SetSize(80, 28)
        toyAddContainer:Hide()
        collectionsState._toyDetailAddContainer = toyAddContainer
        if PlanCardFactory then
            collectionsState._toyDetailAddBtn = PlanCardFactory.CreateAddButton(toyAddContainer, {
                buttonType = "row",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if collectionsState._toyDetailAddBtn then
                collectionsState._toyDetailAddBtn:ClearAllPoints()
                collectionsState._toyDetailAddBtn:SetPoint("TOPRIGHT", toyAddContainer, "TOPRIGHT", 0, 0)
            end
            collectionsState._toyDetailAddedIndicator = PlanCardFactory.CreateAddedIndicator(toyAddContainer, {
                buttonType = "row",
                label = (ns.L and ns.L["ADDED"]) or "Added",
                fontCategory = "body",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if collectionsState._toyDetailAddedIndicator then
                collectionsState._toyDetailAddedIndicator:ClearAllPoints()
                collectionsState._toyDetailAddedIndicator:SetPoint("TOPRIGHT", toyAddContainer, "TOPRIGHT", 0, 0)
                collectionsState._toyDetailAddedIndicator:Hide()
            end
        end
        -- İsim Add butonunun solunda kalsın
        if nameFs and toyAddContainer then
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
            nameFs:SetPoint("TOPRIGHT", toyAddContainer, "TOPLEFT", -8, 0)
        end

        local collectedBadge = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        collectedBadge:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetJustifyH("LEFT")
        collectedBadge:SetWordWrap(true)
        collectedBadge:SetText("")
        collectedBadge:Hide()
        collectionsState._toyDetailCollectedBadge = collectedBadge

        local sourceLabel = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        sourceLabel:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetJustifyH("LEFT")
        sourceLabel:SetWordWrap(true)
        sourceLabel:SetText("")
        collectionsState._toyDetailSourceLabel = sourceLabel
    else
        collectionsState.toyDetailContainer:SetParent(rightCol)
        collectionsState.toyDetailContainer:SetSize(detailWidth, detailH)
        collectionsState.toyDetailContainer:ClearAllPoints()
        if pr then
            collectionsState.toyDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            collectionsState.toyDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        collectionsState.toyDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        ApplyDetailAccentVisuals(collectionsState.toyDetailContainer)
        collectionsState.toyDetailScrollBarContainer = EnsureDetailScrollBarContainer(
            collectionsState.toyDetailScrollBarContainer,
            collectionsState.toyDetailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        if collectionsState._toyDetailScroll then
            collectionsState._toyDetailScroll:ClearAllPoints()
            collectionsState._toyDetailScroll:SetPoint("TOPLEFT", collectionsState.toyDetailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
            collectionsState._toyDetailScroll:SetPoint("BOTTOMRIGHT", collectionsState.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if collectionsState._toyDetailScroll.ScrollBar then
                Factory:PositionScrollBarInContainer(collectionsState._toyDetailScroll.ScrollBar, collectionsState.toyDetailScrollBarContainer, CONTAINER_INSET)
            end
        end
        if collectionsState._toyDetailScrollChild then
            collectionsState._toyDetailScrollChild:SetWidth(detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end

    local function UpdateToyDetailPanel(itemID, name, icon, isCollected, sourceTypeName)
        if collectionsState._toyDetailAddContainer then
            if not itemID then
                collectionsState._toyDetailAddContainer:Hide()
            else
                collectionsState._toyDetailAddContainer:Show()
                local addBtn = collectionsState._toyDetailAddBtn
                local addedIndicator = collectionsState._toyDetailAddedIndicator
                if addBtn and addedIndicator and WarbandNexus then
                    local planned = WarbandNexus.IsItemPlanned and WarbandNexus:IsItemPlanned("toy", itemID)
                    if isCollected then
                        addBtn:Hide()
                        addedIndicator:Show()
                        addedIndicator:SetAlpha(0.45)
                    elseif planned then
                        addBtn:Hide()
                        addedIndicator:Show()
                        addedIndicator:SetAlpha(1)
                    else
                        addedIndicator:Hide()
                        addBtn:Show()
                        addBtn:SetScript("OnClick", function()
                            if WarbandNexus and WarbandNexus.AddPlan then
                                WarbandNexus:AddPlan({
                                    type = "toy",
                                    itemID = itemID,
                                    name = name,
                                    icon = icon,
                                    source = sourceTypeName or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                                })
                                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                            end
                        end)
                    end
                end
            end
        end
        -- Resolve display name: avoid showing raw ID when API didn't return name
        local displayName = name and name ~= "" and name or ""
        if (displayName == "" or (itemID and displayName == tostring(itemID))) and itemID and WarbandNexus.ResolveCollectionMetadata then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", itemID)
            if meta and meta.name and meta.name ~= "" and meta.name ~= tostring(itemID) then
                displayName = meta.name
            elseif itemID and C_Item and C_Item.GetItemInfo then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName and type(itemName) == "string" and itemName ~= "" then
                    displayName = itemName
                end
            end
        end
        if displayName == "" and itemID then displayName = tostring(itemID) end
        if collectionsState._toyDetailIcon then
            collectionsState._toyDetailIcon:SetTexture(icon or DEFAULT_ICON_TOY)
            collectionsState._toyDetailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if collectionsState._toyDetailName then
            local gR = (COLORS.gold and COLORS.gold[1]) or 1
            local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
            local gB = (COLORS.gold and COLORS.gold[3]) or 0
            collectionsState._toyDetailName:SetText(displayName)
            collectionsState._toyDetailName:SetTextColor(gR, gG, gB)
        end
        if collectionsState._toyDetailCollectedBadge then
            collectionsState._toyDetailCollectedBadge:Hide()
        end
        if collectionsState._toyDetailSourceLabel then
            local srcLabel = collectionsState._toyDetailSourceLabel
            local srcText = (sourceTypeName and sourceTypeName ~= "") and sourceTypeName or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
            if srcText == "SOURCE_UNKNOWN" then srcText = "Unknown" end
            local sourceTitle = (ns.L and ns.L["SOURCE"]) or "Source"
            if sourceTitle == "SOURCE" then sourceTitle = "Source" end
            local gR = (COLORS.gold and COLORS.gold[1]) or 1
            local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
            local gB = (COLORS.gold and COLORS.gold[3]) or 0
            local goldHex = string.format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
            srcLabel:SetText(goldHex .. sourceTitle .. ":|r |cffffffff" .. srcText .. "|r")
        end
        if collectionsState._toyDetailScrollChild and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local child = collectionsState._toyDetailScrollChild
                if not child then return end
                local lastEl = collectionsState._toyDetailSourceLabel or collectionsState._toyDetailCollectedBadge
                if lastEl and lastEl.GetBottom and child.GetTop then
                    local top = child:GetTop()
                    local bot = lastEl:GetBottom()
                    if top and bot then
                        child:SetHeight(math.max(1, top - bot + PADDING))
                    end
                end
            end)
        end
    end

    local function onSelectToy(itemID, name, icon, _source, _description, isCollected, sourceTypeName)
        collectionsState.selectedToyID = itemID
        if collectionsState.toyDetailEmptyOverlay then
            collectionsState.toyDetailEmptyOverlay:SetShown(not itemID)
        end
        if collectionsState._toyDetailScroll then
            collectionsState._toyDetailScroll:SetShown(itemID ~= nil)
        end
        UpdateToyDetailPanel(itemID, name or "", icon or DEFAULT_ICON_TOY, isCollected, sourceTypeName)
    end

    -- Toys: list from C_ToyBox source type API; no flat cache required
    local dataReady = true
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    if not dataReady and not isLoading then
        isLoading = true
    end

    if isLoading and not dataReady then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if collectionsState.toyListContainer then collectionsState.toyListContainer:Hide() end
        if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Hide() end
        if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Hide() end
        C_Timer.After(COLLECTION_HEAVY_DELAY, function()
            if collectionsState._toysDrawGen ~= drawGen or collectionsState.currentSubTab ~= "toys" then return end
            if not contentFrame or not contentFrame:IsVisible() then return end
            if WarbandNexus.EnsureCollectionData then WarbandNexus:EnsureCollectionData() end
            local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
            local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
            local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
            SetCollectionProgress(collected, total)
            if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
            if collectionsState.toyListContainer then collectionsState.toyListContainer:Show() end
            if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Show() end
            if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Show() end
            if not collectionsState.selectedToyID then
                if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Show() end
                if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Hide() end
            else
                if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Hide() end
                if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Show() end
            end
            local listW = listContentWidth - (CONTAINER_INSET * 2)
            local sch = collectionsState.toyListScrollChild
            local grouped = GetFilteredToysGrouped(collectionsState.searchText or "", collectionsState.showCollected, collectionsState.showUncollected)
            if collectionsState._toysDrawGen == drawGen and collectionsState.currentSubTab == "toys" and sch and sch:GetParent() and contentFrame:IsVisible() then
                collectionsState._lastGroupedToyData = grouped
                PopulateToyList(sch, listW, grouped, collectionsState.collapsedHeadersToys, collectionsState.selectedToyID, onSelectToy, contentFrame, DrawToysContent)
                if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                    Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
                end
            end
        end)
    else
        if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
        if collectionsState.toyListContainer then collectionsState.toyListContainer:Show() end
        if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Show() end
        if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Show() end
        if not collectionsState.selectedToyID then
            if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Show() end
            if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Hide() end
        else
            if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Hide() end
            if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.toyListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
        local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
        SetCollectionProgress(collected, total)
        local searchUnchanged = (collectionsState._toyLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._toyLastShowCollected == collectionsState.showCollected)
            and (collectionsState._toyLastShowUncollected == collectionsState.showUncollected)
        if sch and collectionsState._toyFlatList and collectionsState._lastGroupedToyData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
            end
            if collectionsState._toyListRefreshVisible then
                collectionsState._toyListRefreshVisible()
            end
        else
            C_Timer.After(0, function()
                if collectionsState._toysDrawGen ~= drawGen or collectionsState.currentSubTab ~= "toys" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                local grouped = GetFilteredToysGrouped(collectionsState.searchText or "", collectionsState.showCollected, collectionsState.showUncollected)
                if collectionsState._toysDrawGen == drawGen and collectionsState.currentSubTab == "toys" and sch:GetParent() and contentFrame:IsVisible() then
                    collectionsState._toyLastSearchText = collectionsState.searchText or ""
                    collectionsState._toyLastShowCollected = collectionsState.showCollected
                    collectionsState._toyLastShowUncollected = collectionsState.showUncollected
                    collectionsState._lastGroupedToyData = grouped
                    PopulateToyList(sch, listW, grouped, collectionsState.collapsedHeadersToys, collectionsState.selectedToyID, onSelectToy, contentFrame, DrawToysContent)
                    if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                        Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
                    end
                end
            end)
        end
    end
    collectionsState._drawToysContentBusy = nil
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
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()

    -- Achievements: list container | scrollbar column | detail (same pattern as Mounts/Pets/Toys)
    local achListContainer = collectionsState.achievementListContainer
    if not achListContainer then
        achListContainer = Factory:CreateContainer(contentFrame, listContentWidth, ch, false)
        achListContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
        collectionsState.achievementListContainer = achListContainer
        local scrollFrame = Factory:CreateScrollFrame(achListContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", achListContainer, "BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.achievementListScrollFrame = scrollFrame
        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.achievementListScrollChild = scrollChild
        collectionsState.achievementListScrollBarContainer = EnsureListScrollBarContainer(
            nil, contentFrame, achListContainer, scrollBarColumnWidth, ch, SCROLLBAR_SIDE_GAP
        )
    end
    achListContainer = collectionsState.achievementListContainer
    achListContainer:SetSize(listContentWidth, ch)
    achListContainer:Show()
    -- Liste etrafında border yok
    collectionsState.achievementListScrollBarContainer = EnsureListScrollBarContainer(
        collectionsState.achievementListScrollBarContainer,
        contentFrame,
        achListContainer,
        scrollBarColumnWidth,
        ch,
        SCROLLBAR_SIDE_GAP
    )
    collectionsState.achievementListScrollBarContainer:Show()
    local achScrollBar = collectionsState.achievementListScrollFrame and collectionsState.achievementListScrollFrame.ScrollBar
    if achScrollBar and collectionsState.achievementListScrollBarContainer then
        Factory:PositionScrollBarInContainer(achScrollBar, collectionsState.achievementListScrollBarContainer, CONTAINER_INSET)
        achScrollBar:Show()
        if achScrollBar.ScrollUpBtn then achScrollBar.ScrollUpBtn:Show() end
        if achScrollBar.ScrollDownBtn then achScrollBar.ScrollDownBtn:Show() end
    end
    collectionsState.achievementListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + achievement detail panel (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = CreateFrame("Frame", nil, contentFrame)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.achievementListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, ch - detailTop)

    if collectionsState.achievementDetailContainer then
        collectionsState.achievementDetailContainer:Show()
    end

    local function onSelectAchievement(ach)
        collectionsState.selectedAchievementID = ach and ach.id
        if collectionsState.achDetailEmptyOverlay then
            collectionsState.achDetailEmptyOverlay:SetShown(not (ach and ach.id))
        end
        if collectionsState.achievementDetailPanel then
            collectionsState.achievementDetailPanel:SetShown(ach and ach.id ~= nil)
            collectionsState.achievementDetailPanel:SetAchievement(ach)
        end
    end

    if not collectionsState.achievementDetailPanel then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        collectionsState.achievementDetailContainer = detailContainer
        ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(detailContainer, "achievement")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            collectionsState.achDetailEmptyOverlay = emptyOverlay
        end
        collectionsState.achievementDetailPanel = CreateAchievementDetailPanel(detailContainer, detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2), onSelectAchievement)
        collectionsState.achievementDetailPanel:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
    else
        if collectionsState.achievementDetailContainer then
            collectionsState.achievementDetailContainer:SetParent(rightCol)
            collectionsState.achievementDetailContainer:SetSize(detailWidth, detailH)
            collectionsState.achievementDetailContainer:ClearAllPoints()
            if pr then
                collectionsState.achievementDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.achievementDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.achievementDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        end
        ApplyDetailAccentVisuals(collectionsState.achievementDetailContainer)
        collectionsState.achievementDetailPanel:SetSize(detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        if collectionsState.achievementDetailPanel._scrollBarContainer then
            collectionsState.achievementDetailPanel._scrollBarContainer = EnsureDetailScrollBarContainer(
                collectionsState.achievementDetailPanel._scrollBarContainer,
                collectionsState.achievementDetailPanel,
                SCROLLBAR_GAP,
                CONTAINER_INSET
            )
        end
        if collectionsState.achievementDetailPanel.scrollFrame and collectionsState.achievementDetailPanel._scrollBarContainer then
            collectionsState.achievementDetailPanel.scrollFrame:ClearAllPoints()
            collectionsState.achievementDetailPanel.scrollFrame:SetPoint("TOPLEFT", collectionsState.achievementDetailPanel, "TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
            collectionsState.achievementDetailPanel.scrollFrame:SetPoint("BOTTOMRIGHT", collectionsState.achievementDetailPanel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if collectionsState.achievementDetailPanel.scrollFrame.ScrollBar then
                Factory:PositionScrollBarInContainer(collectionsState.achievementDetailPanel.scrollFrame.ScrollBar, collectionsState.achievementDetailPanel._scrollBarContainer, CONTAINER_INSET)
            end
        end
        local achChild = collectionsState.achievementDetailPanel.scrollFrame and collectionsState.achievementDetailPanel.scrollFrame:GetScrollChild()
        if achChild then
            achChild:SetWidth((detailWidth - (CONTAINER_INSET * 2)) - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end
    if not collectionsState.selectedAchievementID then
        if collectionsState.achDetailEmptyOverlay then collectionsState.achDetailEmptyOverlay:Show() end
        if collectionsState.achievementDetailPanel then collectionsState.achievementDetailPanel:Hide() end
    else
        if collectionsState.achDetailEmptyOverlay then collectionsState.achDetailEmptyOverlay:Hide() end
        if collectionsState.achievementDetailPanel then collectionsState.achievementDetailPanel:Show() end
    end

    local loadingState = ns.PlansLoadingState and ns.PlansLoadingState.achievement
    local collLoading = ns.CollectionLoadingState
    -- Loading only when a scan/load is actually in progress; not when filters result in empty list (e.g. both Owned and Missing unchecked)
    local isLoading = (loadingState and loadingState.isLoading) or (collLoading and collLoading.isLoading and collLoading.currentCategory == "achievement")
    local categoryData, rootCategories, totalCount = BuildGroupedAchievementData(
        collectionsState.searchText or "",
        collectionsState.showCollected,
        collectionsState.showUncollected
    )

    if isLoading then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or (collLoading and collLoading.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or (collLoading and collLoading.currentStage) or ((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...", progress, stage)
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
    else
        if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Show() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Show() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Show() end

        local allAchsForProgress = WarbandNexus.GetAllAchievementsData and WarbandNexus:GetAllAchievementsData() or {}
        local achTotal = #allAchsForProgress
        local achCollected = 0
        for i = 1, achTotal do
            if allAchsForProgress[i] and (allAchsForProgress[i].isCollected or allAchsForProgress[i].completed) then achCollected = achCollected + 1 end
        end
        SetCollectionProgress(achCollected, achTotal)

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
    local sideMargin = (LAYOUT.SIDE_MARGIN or 10)
    local width = (parent:GetWidth() or 680) - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = (LAYOUT.TOP_MARGIN or 8)

    HideEmptyStateCard(parent, "collections")

    -- ===== CHROME CACHING: reuse header/search/filter/subtab frames across tab switches =====
    local chrome = collectionsState._chrome

    if chrome and chrome.titleCard then
        chrome.titleCard:SetParent(headerParent)
        chrome.titleCard:ClearAllPoints()
        chrome.titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        chrome.titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        chrome.titleCard:Show()

        headerYOffset = headerYOffset + (GetLayout().afterHeader or AFTER_HEADER)

        chrome.subTabBar:SetParent(headerParent)
        chrome.subTabBar:ClearAllPoints()
        chrome.subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        chrome.subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        chrome.subTabBar:SetActiveTab(collectionsState.currentSubTab)
        chrome.subTabBar:Show()
        collectionsState.subTabBar = chrome.subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        chrome.searchRow:SetParent(headerParent)
        chrome.searchRow:ClearAllPoints()
        chrome.searchRow:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        chrome.searchRow:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        chrome.searchRow:Show()

        chrome.filterRow:SetParent(chrome.searchRow)
        chrome.filterRow:ClearAllPoints()
        chrome.filterRow:SetPoint("TOPRIGHT", chrome.searchRow, "TOPRIGHT", 0, 0)
        chrome.filterRow:Show()

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    else
        -- First-time creation of chrome elements
        chrome = {}
        collectionsState._chrome = chrome

        -- ===== HEADER CARD (in fixedHeader - non-scrolling) =====
        local titleCard = CreateCard(headerParent, COLLECTIONS_HEADER_CARD_HEIGHT)
        titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
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

        titleCard:Show()
        headerYOffset = headerYOffset + (GetLayout().afterHeader or AFTER_HEADER)

        -- ===== SUB-TAB BAR (in fixedHeader - non-scrolling) =====
        local subTabBar = CreateSubTabBar(headerParent, function(tabKey)
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
            collectionsState.searchText = ""
            if collectionsState.searchBox then
                collectionsState.searchBox:SetText("")
            end
            HideAllCollectionsResultFrames()
            C_Timer.After(0, function()
                local cf = collectionsState.contentFrame
                if not cf or not cf:GetParent() then return end
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(cf)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(cf)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(cf)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(cf)
                end
            end)
        end)
        subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        subTabBar:SetActiveTab(collectionsState.currentSubTab)
        chrome.subTabBar = subTabBar
        collectionsState.subTabBar = subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        -- ===== SEARCH ROW (in fixedHeader - non-scrolling) =====
        local searchRow = CreateFrame("Frame", nil, headerParent)
        searchRow:SetHeight(SEARCH_ROW_HEIGHT)
        searchRow:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        searchRow:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        chrome.searchRow = searchRow

        local FILTER_BLOCK_WIDTH = 200
        local filterRow = CreateFrame("Frame", nil, searchRow)
        filterRow:SetSize(FILTER_BLOCK_WIDTH, SEARCH_ROW_HEIGHT)
        filterRow:SetPoint("TOPRIGHT", searchRow, "TOPRIGHT", 0, 0)
        chrome.filterRow = filterRow

        local searchBar = Factory:CreateContainer(searchRow, nil, 32, false)
        searchBar:SetPoint("TOPLEFT", searchRow, "TOPLEFT", 0, 0)
        searchBar:SetPoint("TOPRIGHT", filterRow, "TOPLEFT", -8, 0)
        if ApplyVisuals then
            ApplyVisuals(searchBar, { 0.06, 0.06, 0.08, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        end

        local searchIcon = searchBar:CreateTexture(nil, "OVERLAY")
        searchIcon:SetSize(14, 14)
        searchIcon:SetPoint("LEFT", 8, 0)
        searchIcon:SetAtlas("common-search-magnifyingglass")
        searchIcon:SetVertexColor(0.6, 0.6, 0.6)

        local searchBox = Factory:CreateEditBox(searchBar)
        searchBox:SetSize(1, 26)
        searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 6, 0)
        searchBox:SetPoint("RIGHT", searchBar, "RIGHT", -8, 0)
        searchBox:SetFontObject(ChatFontNormal)
        searchBox:SetTextColor(1, 1, 1, 1)
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(50)
        searchBox.Instructions = searchBox:CreateFontString(nil, "ARTWORK")
        searchBox.Instructions:SetFontObject(ChatFontNormal)
        searchBox.Instructions:SetPoint("LEFT", 0, 0)
        searchBox.Instructions:SetPoint("RIGHT", 0, 0)
        searchBox.Instructions:SetJustifyH("LEFT")
        searchBox.Instructions:SetTextColor(0.5, 0.5, 0.5, 0.8)
        searchBox.Instructions:SetText((ns.L and ns.L["SEARCH_PLACEHOLDER"]) or "Search...")
        searchBox:SetText(collectionsState.searchText or "")
        if (collectionsState.searchText or "") ~= "" then searchBox.Instructions:Hide() end

        searchBox:SetScript("OnTextChanged", function(self, userInput)
            local text = self:GetText() or ""
            collectionsState.searchText = text
            if self.Instructions then
                if text ~= "" then self.Instructions:Hide() else self.Instructions:Show() end
            end
            if not userInput then return end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            collectionsState.searchText = ""
            if self.Instructions then self.Instructions:Show() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)
        searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        searchBar:EnableMouse(true)
        searchBar:SetScript("OnMouseDown", function() searchBox:SetFocus() end)
        collectionsState.searchBox = searchBox

        -- ===== FILTERS (right side of search row: Owned | Missing) =====
        local lblOwned = (ns.L and (ns.L["FILTER_SHOW_OWNED"] or ns.L["FILTER_COLLECTED"])) or "Owned"
        local lblMissing = (ns.L and (ns.L["FILTER_SHOW_MISSING"] or ns.L["FILTER_UNCOLLECTED"])) or "Missing"

        local cbCollected = CreateThemedCheckbox(filterRow, collectionsState.showCollected)
        cbCollected:SetPoint("LEFT", filterRow, "LEFT", CONTENT_INSET, 0)
        local lblCollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblCollected:SetPoint("LEFT", cbCollected, "RIGHT", 4, 0)
        lblCollected:SetText(lblOwned)
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
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        local cbUncollected = CreateThemedCheckbox(filterRow, collectionsState.showUncollected)
        cbUncollected:SetPoint("LEFT", lblCollected, "RIGHT", CONTENT_INSET * 2, 0)
        local lblUncollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblUncollected:SetPoint("LEFT", cbUncollected, "RIGHT", 4, 0)
        lblUncollected:SetText(lblMissing)
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
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
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

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    end

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

    -- ===== CONTENT AREA =====
    local scrollFrame = parent:GetParent()
    local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
    local bottomPad = 0
    local contentHeight = math.max(250, viewHeight - yOffset - bottomPad)
    local parentWidth = parent:GetWidth() or 680
    local contentWidth = math.max(1, parentWidth - (sideMargin * 2))

    local contentFrame = collectionsState.contentFrame
    if contentFrame then
        contentFrame:SetParent(parent)
        contentFrame:ClearAllPoints()
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        collectionsState.contentFrame = contentFrame
    else
        contentFrame = CreateFrame("Frame", nil, parent)
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
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
        collectionsState.toyListContainer = nil
        collectionsState.toyListScrollFrame = nil
        collectionsState.toyListScrollChild = nil
        collectionsState.toyListScrollBarContainer = nil
        collectionsState.toyDetailContainer = nil
        collectionsState.toyDetailScrollBarContainer = nil
        collectionsState.collectionRightColumn = nil
        collectionsState.collectionProgressFrame = nil
        collectionsState.collectionProgressBar = nil
        collectionsState.collectionProgressLabel = nil
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
    elseif collectionsState.currentSubTab == "toys" then
        DrawToysContent(contentFrame)
    elseif collectionsState.currentSubTab == "achievements" then
        DrawAchievementsContent(contentFrame)
    end

    yOffset = yOffset + contentHeight + bottomPad

    -- Event-driven updates (same events as Plans): all sub-tabs (Mounts, Pets, Achievements) refresh when these fire.
    -- CRITICAL: Use a dedicated listener key (CUIListeners) instead of WarbandNexus as self.
    -- AceEvent allows only ONE handler per (event, self) pair — using WarbandNexus would
    -- overwrite CollectionService's handlers for the same events (e.g. RemoveFromUncollected).
    if not collectionsState._messageRegistered then
        collectionsState._messageRegistered = true
        local CUIListeners = {}
        collectionsState._listeners = CUIListeners

        local function InvalidateAllCollectionCaches()
            collectionsState._cachedMountsData = nil
            collectionsState._cachedPetsData = nil
            collectionsState._cachedToysData = nil
            collectionsState._lastGroupedMountData = nil
            collectionsState._mountFlatList = nil
            collectionsState._lastGroupedPetData = nil
            collectionsState._petFlatList = nil
            collectionsState._lastGroupedToyData = nil
            collectionsState._toyFlatList = nil
        end

        local eventName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_PROGRESS) or "WN_COLLECTION_SCAN_PROGRESS"
        WarbandNexus.RegisterMessage(CUIListeners, eventName, function()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" and collectionsState.contentFrame then
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        local completeName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE) or "WN_COLLECTION_SCAN_COMPLETE"
        WarbandNexus.RegisterMessage(CUIListeners, completeName, function()
            InvalidateAllCollectionCaches()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end
        end)

        local updatedName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED) or "WN_COLLECTION_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, updatedName, function(_, updatedType)
            if updatedType ~= "mount" and updatedType ~= "pet" and updatedType ~= "toy" and updatedType ~= "achievement" then return end
            InvalidateAllCollectionCaches()
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end)
        end)

        local plansUpdatedName = (Constants and Constants.EVENTS and Constants.EVENTS.PLANS_UPDATED) or "WN_PLANS_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, plansUpdatedName, function()
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if not collectionsState.contentFrame then return end
                if collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end)
        end)

        local trackingUpdatedName = (Constants and Constants.EVENTS and Constants.EVENTS.ACHIEVEMENT_TRACKING_UPDATED) or "WN_ACHIEVEMENT_TRACKING_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, trackingUpdatedName, function(_, payload)
            if not payload or not payload.achievementID then return end
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if collectionsState.currentSubTab ~= "achievements" then return end
                if not collectionsState.contentFrame then return end
                DrawAchievementsContent(collectionsState.contentFrame)
            end)
        end)

        local obtainedName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTIBLE_OBTAINED) or "WN_COLLECTIBLE_OBTAINED"
        WarbandNexus.RegisterMessage(CUIListeners, obtainedName, function(_, data)
            if not data or not data.type then return end
            if data.type ~= "mount" and data.type ~= "pet" and data.type ~= "toy" and data.type ~= "achievement" then return end
            InvalidateAllCollectionCaches()
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end)
        end)
    end

    return yOffset
end
