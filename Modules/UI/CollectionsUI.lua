--[[
    Warband Nexus - Collections Tab
    Sub-tab system: Mounts, Pets, Toys, etc.
    Mounts tab: Virtual scroll list grouped by Source, Model Viewer, Description panel.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local COLORS = ns.UI_COLORS
local CreateHeaderIcon = ns.UI_CreateHeaderIcon
local GetTabIcon = ns.UI_GetTabIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor

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

local SOURCE_CATEGORIES = {
    { key = "drop",        label = "Drop",         icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
    { key = "vendor",      label = "Vendor",        icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { key = "quest",       label = "Quest",         icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "achievement", label = "Achievement",   icon = "Interface\\Icons\\Achievement_Quests_Completed_08" },
    { key = "profession",  label = "Profession",    icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "reputation",  label = "Reputation",    icon = "Interface\\Icons\\INV_Misc_Note_02" },
    { key = "pvp",         label = "PvP",           icon = "Interface\\Icons\\Achievement_PVP_P_01" },
    { key = "worldevent",  label = "World Event",   icon = "Interface\\Icons\\INV_Misc_Celebrations" },
    { key = "promotion",   label = "Promotion",     icon = "Interface\\Icons\\INV_Misc_Gift_05" },
    { key = "tradingpost", label = "Trading Post",  icon = "Interface\\Icons\\INV_Misc_Coin_17" },
    { key = "treasure",    label = "Treasure",      icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "unknown",     label = "Other",         icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

local SOURCE_CATEGORY_ORDER = {}
for i, cat in ipairs(SOURCE_CATEGORIES) do
    SOURCE_CATEGORY_ORDER[cat.key] = i
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
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 30
local HEADER_HEIGHT = LAYOUT.HEADER_HEIGHT or 32

-- State for Collections tab (must be defined before PopulateMountList/UpdateMountListVisibleRange/DrawMountsContent)
local collectionsState = {
    currentSubTab = "mounts",
    mountListContainer = nil,
    mountListScrollFrame = nil,
    mountListScrollChild = nil,
    modelViewer = nil,
    descriptionPanel = nil,
    loadingPanel = nil,
    searchBox = nil,
    contentFrame = nil,
    subTabBar = nil,
    showCollected = true,
    showUncollected = true,
    collapsedHeaders = {},
    selectedMountID = nil,
    initialized = false,
}

local _populateMountListBusy = false

-- Build flat list for virtual scrolling: [{ type = "header", ... } | { type = "row", ... }], totalHeight
-- Sayılar (Drop 669, Quest 87, vb.) grouped[key] uzunluğundan gelir; liste ile tutarlıdır.
local function BuildFlatMountList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    for _, catInfo in ipairs(SOURCE_CATEGORIES) do
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            local isCollapsed = collapsedHeaders[key]
            local rD, gD, bD = (COLORS.textDim[1] or 0.55), (COLORS.textDim[2] or 0.55), (COLORS.textDim[3] or 0.55)
            local countColor = string.format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
            local rB, gB, bB = (COLORS.textBright[1] or 1), (COLORS.textBright[2] or 1), (COLORS.textBright[3] or 1)
            local titleColor = string.format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. catInfo.label .. "|r " .. countColor .. "(" .. #items .. ")|r",
                rightStr = countColor .. #items .. "|r",
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = HEADER_HEIGHT,
            }
            yOffset = yOffset + HEADER_HEIGHT
            if not isCollapsed then
                for _, mount in ipairs(items) do
                    rowCounter = rowCounter + 1
                    flat[#flat + 1] = { type = "row", mount = mount, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

local MountRowPool = {}
local STATUS_ICON_SIZE = 16
local ICON_CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- Collected text color: match Plans tab green (0.2, 0.9, 0.2)
local COLLECTED_COLOR = "|cff33e533"

-- Acquire or create a mount row frame and configure it for one flat item (virtual scroll).
local function AcquireMountRow(scrollChild, listWidth, item, selectedMountID, onSelectMount, redraw, cf)
    local f = table.remove(MountRowPool)
    if not f then
        f = Factory:CreateDataRow(scrollChild, 0, 1, ROW_HEIGHT)
        f:ClearAllPoints()
        f:EnableMouse(true)
        -- Status icon (check/cross) at left
        local statusIcon = f:CreateTexture(nil, "ARTWORK")
        statusIcon:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
        statusIcon:SetPoint("LEFT", PADDING, 0)
        f.statusIcon = statusIcon
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        icon:SetPoint("LEFT", statusIcon, "RIGHT", CONTENT_INSET / 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.mountIcon = icon
        f.mountLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        f.mountLabel:SetPoint("LEFT", icon, "RIGHT", CONTENT_INSET, 0)
        f.mountLabel:SetPoint("RIGHT", f, "RIGHT", -PADDING, 0)
        f.mountLabel:SetJustifyH("LEFT")
        f.mountLabel:SetWordWrap(false)
    end
    f:SetParent(scrollChild)
    f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -item.yOffset)
    f:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    f:SetHeight(ROW_HEIGHT)
    -- Alternating row background (dark/light)
    Factory:ApplyRowBackground(f, item.rowIndex)
    local mount = item.mount
    f.statusIcon:SetTexture(mount.isCollected and ICON_CHECK or ICON_CROSS)
    f.statusIcon:Show()
    f.mountIcon:SetTexture(mount.icon or "Interface\\Icons\\Ability_Mount_RidingHorse")
    local nameColor = mount.isCollected and COLLECTED_COLOR or "|cffffffff"
    f.mountLabel:SetText(nameColor .. (mount.name or "") .. "|r")
    f:SetScript("OnMouseDown", function()
        if onSelectMount then
            onSelectMount(mount.id, mount.name, mount.icon, mount.source, mount.creatureDisplayID, mount.description, mount.isCollected)
        end
        -- Sadece seçim vurgusunu güncelle; tam yeniden çizim (BuildGroupedMountData) FPS düşürür.
        if collectionsState._mountFlatList and collectionsState.mountListScrollFrame then
            collectionsState._mountListSelectedID = mount.id
            local refresh = collectionsState._mountListRefreshVisible
            if refresh then refresh() end
        end
    end)
    if f.selBg then f.selBg:Hide() end
    if selectedMountID == mount.id then
        if not f.selBg then
            f.selBg = f:CreateTexture(nil, "BORDER")
            f.selBg:SetAllPoints()
        end
        f.selBg:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.25)
        f.selBg:Show()
    end
    f:Show()
    return f
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
                MountRowPool[#MountRowPool + 1] = v.frame
            end
        end
    end
    state._mountVisibleRowFrames = {}
    local redraw = state._mountListRedrawFn
    local cf = state._mountListContentFrame
    local selectedMountID = state._mountListSelectedID or state.selectedMountID
    local onSelectMount = state._mountListOnSelectMount
    local listWidth = state._mountListWidth or scrollChild:GetWidth()
    local startIdx, endIdx = 1, #flatList
    for i = 1, #flatList do
        local it = flatList[i]
        if it.yOffset + it.height > scrollTop and startIdx == 1 then startIdx = i end
        if it.yOffset < bottom then endIdx = i end
    end
    for i = startIdx, endIdx do
        local it = flatList[i]
        if it.type == "row" then
            local frame = AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
            state._mountVisibleRowFrames[#state._mountVisibleRowFrames + 1] = { frame = frame, flatIndex = i }
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
                MountRowPool[#MountRowPool + 1] = v.frame
            end
        end
        collectionsState._mountVisibleRowFrames = {}
    end

    -- Clear existing children (headers from previous run)
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        children[i]:ClearAllPoints()
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatMountList(groupedData, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    -- Create only section headers (fixed); rows are virtualized in UpdateMountListVisibleRange
        for i = 1, #flatList do
            local it = flatList[i]
            if it.type == "header" then
                local function Toggle()
                    collapsedHeaders[it.key] = not collapsedHeaders[it.key]
                    local cached = collectionsState._lastGroupedMountData
                    if cached and collectionsState.mountListScrollChild and cf and cf:IsVisible() then
                        PopulateMountList(scrollChild, listWidth, cached, collapsedHeaders, selectedMountID, onSelectMount, cf, redraw)
                    elseif C_Timer and C_Timer.After and cf and cf:IsVisible() and redraw then
                        C_Timer.After(0, function() redraw(cf) end)
                    end
                end
                Factory:CreateSectionHeader(scrollChild, it.yOffset, it.isCollapsed, it.label, it.rightStr, Toggle, it.height)
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
            UpdateMountListVisibleRange()
        end)
    end
    UpdateMountListVisibleRange()
    _populateMountListBusy = false
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

local function CreateModelViewer(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})

    local model = CreateFrame("PlayerModel", nil, panel)
    model:SetModelDrawLayer("ARTWORK")
    model:EnableMouse(true)
    model:EnableMouseWheel(true)

    -- 1:1 kare çerçeve: panel boyutuna göre min(genişlik, yükseklik) ile kare, ortada (freeform canvas yerine sabit oran).
    local function UpdateModelFrameSize()
        local w = panel:GetWidth()
        local h = panel:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        local side = math.min(w, h) - (CONTENT_INSET * 2)
        if side < 1 then side = 1 end
        model:SetSize(side, side)
        model:ClearAllPoints()
        model:SetPoint("CENTER", panel, "CENTER", 0, 0)
    end
    panel.UpdateModelFrameSize = UpdateModelFrameSize
    panel:SetScript("OnSizeChanged", UpdateModelFrameSize)
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
                model:SetCameraDistance(math.max(0.1, FIXED_CAM_DISTANCE * panel.zoomMultiplier))
            end
        else
            if model.SetCamDistanceScale then model:SetCamDistanceScale(panel.camScale) end
        end
        if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
    end

    -- Sağ tık: döndür
    model:SetScript("OnMouseDown", function(_, button)
        if button ~= "RightButton" then return end
        local x = GetCursorPosition()
        local s = model:GetEffectiveScale()
        if s and s > 0 then x = x / s end
        panel._dragCursorX = x
        panel._dragRotation = panel.modelRotation
    end)
    model:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then panel._dragCursorX = nil end
    end)
    model:SetScript("OnUpdate", function()
        if panel._dragCursorX == nil then return end
        if not IsMouseButtonDown("RightButton") then
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

    -- Text: symmetric insets from panel (CONTENT_INSET); vertical gap TEXT_GAP.
    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local whiteR, whiteG, whiteB = 1, 1, 1

    local nameText = FontManager:CreateFontString(panel, "title", "OVERLAY")
    nameText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    nameText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    nameText:SetTextColor(whiteR, whiteG, whiteB)
    panel.nameText = nameText

    local sourceContainer = CreateFrame("Frame", nil, panel)
    sourceContainer:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceContainer:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceContainer:SetHeight(1)
    panel.sourceContainer = sourceContainer
    panel.sourceLines = {}

    local sourceLabel = FontManager:CreateFontString(panel, "body", "OVERLAY")
    sourceLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceLabel:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetWordWrap(true)
    sourceLabel:SetNonSpaceWrap(false)
    sourceLabel:SetTextColor(whiteR, whiteG, whiteB)
    panel.sourceLabel = sourceLabel

    local descText = FontManager:CreateFontString(panel, "body", "OVERLAY")
    descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
    descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(whiteR, whiteG, whiteB)
    panel.descText = descText

    local collectedBadge = FontManager:CreateFontString(panel, "body", "OVERLAY")
    collectedBadge:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET)
    collectedBadge:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_INSET, 0)
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
-- SUB-TAB BUTTONS
-- ============================================================================

local SUB_TABS = {
    { key = "mounts", label = "Mounts", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    -- Future: pets, toys, transmog, etc.
}

local function CreateSubTabBar(parent, onTabSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(SUBTAB_BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)

    local buttons = {}
    local xPos = 0
    local btnWidth = 100
    local btnHeight = SUBTAB_BAR_HEIGHT - (CONTAINER_INSET * 2)
    local spacing = CARD_GAP

    for i, tabInfo in ipairs(SUB_TABS) do
        local btn = ns.UI.Factory:CreateButton(bar, btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xPos, -CONTAINER_INSET)
        btn._tabKey = tabInfo.key

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        btnIcon:SetSize(ROW_ICON_SIZE - 2, ROW_ICON_SIZE - 2)
        btnIcon:SetPoint("LEFT", CONTENT_INSET, 0)
        btnIcon:SetTexture(tabInfo.icon)
        btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", btnIcon, "RIGHT", CONTENT_INSET, 0)
        btnText:SetText(tabInfo.label)
        btnText:SetJustifyH("LEFT")
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
        xPos = xPos + btnWidth + spacing
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
    for _, cat in ipairs(SOURCE_CATEGORIES) do
        grouped[cat.key] = {}
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name or not grouped[catKey] then return false end
        local n = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        for j = 1, #grouped[catKey] do
            if (grouped[catKey][j].name or ""):gsub("^%s+", ""):gsub("%s+$", "") == n then
                return true
            end
        end
        return false
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name or not grouped[catKey] then return end
        local n = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        for j = 1, #grouped[catKey] do
            if (grouped[catKey][j].name or ""):gsub("^%s+", ""):gsub("%s+$", "") == n then
                grouped[catKey][j].isCollected = true
                return
            end
        end
    end

    -- Use optionalMounts when provided and non-empty to avoid repeated DB/API calls
    local allMounts
    if optionalMounts and #optionalMounts > 0 then
        allMounts = optionalMounts
    else
        allMounts = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
    end
    local useCache = #allMounts > 0

    -- Cache'den gelen mount'ları sadece şu an journal'da olanlarla sınırla (DB eski/patch ile kaldırılan kayıtları göstermesin).
    local currentMountIDSet
    if useCache and C_MountJournal and C_MountJournal.GetMountIDs then
        currentMountIDSet = {}
        local ids = C_MountJournal.GetMountIDs()
        if ids then
            for j = 1, #ids do currentMountIDSet[ids[j]] = true end
        end
    end

    local query = (searchText or ""):lower()
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allMounts do
            local d = allMounts[i]
            if not d or not d.id then
                -- skip
            elseif currentMountIDSet and not currentMountIDSet[d.id] then
                -- Journal'da artık yok (patch ile kaldırılmış veya eski DB); gösterme.
            else
                local name = d.name or tostring(d.id)
                if MOUNT_NAME_BLACKLIST[name] then
                    -- skip (yetenek/placeholder)
                else
                    -- Collected durumu her zaman canlı API'den; cache eski kalabiliyor.
                    local isCollected = SafeGetMountCollected(d.id)
                    if (showC and isCollected) or (showU and not isCollected) then
                        if query == "" or (name and name:lower():find(query, 1, true)) then
                            local sourceText = d.source or ""
                            local catKey = ClassifyMountSource(sourceText)
                            if not grouped[catKey] then grouped[catKey] = {} end
                            if not nameAlreadyInCategory(catKey, name) then
                                grouped[catKey][#grouped[catKey] + 1] = {
                                    id = d.id,
                                    name = name,
                                    icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                    source = sourceText,
                                    description = d.description,
                                    creatureDisplayID = d.creatureDisplayID,
                                    isCollected = isCollected,
                                }
                                totalCount = totalCount + 1
                            else
                                if isCollected then
                                    updateCollectedInCategory(catKey, name, true)
                                end
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
                    local catKey = ClassifyMountSource(sourceText)
                    if not grouped[catKey] then grouped[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        grouped[catKey][#grouped[catKey] + 1] = {
                            id = mountID,
                            name = name,
                            icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                            source = sourceText,
                            description = (meta and meta.description) or description or "",
                            creatureDisplayID = creatureDisplayID,
                            isCollected = isCollected,
                        }
                        totalCount = totalCount + 1
                    else
                        if isCollected then
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
    -- When data exists, use cache to avoid repeated GetAllMountsData() every draw
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allMounts
    if collectionsState._cachedMountsData and #collectionsState._cachedMountsData > 0 then
        allMounts = collectionsState._cachedMountsData
    else
        allMounts = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
        if #allMounts > 0 then
            collectionsState._cachedMountsData = allMounts
        end
    end
    local dataReady = #allMounts > 0
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
    else
        if collectionsState.loadingPanel then
            collectionsState.loadingPanel:Hide()
        end
        if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
        if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end

        local searchText = collectionsState.searchText or ""
        local grouped = BuildGroupedMountData(
            searchText,
            collectionsState.showCollected,
            collectionsState.showUncollected,
            allMounts
        )
        collectionsState._lastGroupedMountData = grouped
        PopulateMountList(
            collectionsState.mountListScrollChild,
            listContentWidth - (CONTAINER_INSET * 2),
            grouped,
            collectionsState.collapsedHeaders,
            collectionsState.selectedMountID,
            onSelectMount,
            contentFrame,
            DrawMountsContent
        )
        if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
            Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
        end
    end
    collectionsState._drawMountsContentBusy = nil
end

-- ============================================================================
-- DRAW COLLECTIONS TAB (Main Entry)
-- ============================================================================

function WarbandNexus:DrawCollectionsTab(parent)
    local yOffset = TOP_MARGIN
    HideEmptyStateCard(parent, "collections")

    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

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

    -- Sync state indicator in header
    local syncText = FontManager:CreateFontString(titleCard, "small", "OVERLAY")
    syncText:SetPoint("RIGHT", titleCard, "RIGHT", -SIDE_MARGIN, 0)
    syncText:SetJustifyH("RIGHT")

    local loadingState = ns.CollectionLoadingState
    if loadingState and loadingState.isLoading then
        local pct = loadingState.loadingProgress or 0
        local stage = loadingState.currentStage or ""
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
    yOffset = yOffset + 70 + CARD_GAP

    -- ===== SEARCH BOX =====
    local searchRow = CreateFrame("Frame", nil, parent)
    searchRow:SetHeight(SEARCH_ROW_HEIGHT)
    searchRow:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchRow:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

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
    placeholder:SetText((ns.L and ns.L["SEARCH_PLACEHOLDER"]) or "Search mounts...")
    if (collectionsState.searchText or "") ~= "" then placeholder:Hide() end

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        collectionsState.searchText = text
        if text == "" then placeholder:Show() else placeholder:Hide() end
        if collectionsState.currentSubTab == "mounts" and collectionsState.contentFrame then
            DrawMountsContent(collectionsState.contentFrame)
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    collectionsState.searchBox = searchBox

    yOffset = yOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT

    -- ===== FILTER ROW: Collected / Uncollected checkboxes =====
    local filterRow = CreateFrame("Frame", nil, parent)
    filterRow:SetHeight(FILTER_ROW_HEIGHT)
    filterRow:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    filterRow:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

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
        if collectionsState.currentSubTab == "mounts" and collectionsState.contentFrame then
            DrawMountsContent(collectionsState.contentFrame)
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
        if collectionsState.currentSubTab == "mounts" and collectionsState.contentFrame then
            DrawMountsContent(collectionsState.contentFrame)
        end
    end)

    -- Ensure at least one filter is on
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
        collectionsState.currentSubTab = tabKey
        if collectionsState.subTabBar then
            collectionsState.subTabBar:SetActiveTab(tabKey)
        end
        if tabKey == "mounts" and collectionsState.contentFrame then
            DrawMountsContent(collectionsState.contentFrame)
        end
    end)
    subTabBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    subTabBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    subTabBar:SetActiveTab(collectionsState.currentSubTab)
    collectionsState.subTabBar = subTabBar

    yOffset = yOffset + SUBTAB_BAR_HEIGHT + CONTAINER_INSET

    -- ===== CONTENT AREA (fills remaining viewport) =====
    local scrollFrame = parent:GetParent()
    local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
    local bottomPad = LAYOUT.MIN_BOTTOM_SPACING or 12
    local contentHeight = math.max(250, viewHeight - yOffset - bottomPad)
    local parentWidth = parent:GetWidth() or 680
    local contentWidth = math.max(1, parentWidth - (SIDE_MARGIN * 2))

    local contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetSize(contentWidth, contentHeight)
    contentFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    contentFrame:Show()
    collectionsState.contentFrame = contentFrame

    -- Clear panel refs so DrawMountsContent creates new panels parented to this contentFrame.
    collectionsState.viewerContainer = nil
    collectionsState.mountListContainer = nil
    collectionsState.mountListScrollFrame = nil
    collectionsState.mountListScrollChild = nil
    collectionsState.modelViewer = nil
    collectionsState.loadingPanel = nil

    -- Draw current sub-tab content
    if collectionsState.currentSubTab == "mounts" then
        DrawMountsContent(contentFrame)
    end

    yOffset = yOffset + contentHeight + bottomPad

    -- Register message for loading updates to refresh UI
    if not collectionsState._messageRegistered then
        collectionsState._messageRegistered = true

        WarbandNexus:RegisterMessage("WN_COLLECTION_SCAN_PROGRESS", function()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                if collectionsState.contentFrame and collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                end
            end
        end)

        WarbandNexus:RegisterMessage("WN_COLLECTION_SCAN_COMPLETE", function()
            collectionsState._cachedMountsData = nil
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                if collectionsState.contentFrame and collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                end
            end
        end)
    end

    return yOffset
end
