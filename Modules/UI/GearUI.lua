--[[
    Warband Nexus - Gear Management Tab
    Paperdoll with Midnight Dawncrests and upgrade analysis.

    Layout:
    ┌────────────────────────────────────────────────────────────────────────────┐
    │ [Header: Title / subtitle (left)                    Character ▼ (right)]    │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Paperdoll — Slot icons (left/right/bottom) + portrait (center) + crests    │
    └────────────────────────────────────────────────────────────────────────────┘
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants    = ns.Constants
local FontManager   = ns.FontManager

--- Tek merkez: Modules/FontManager.lua → FONT_ROLE
local function GFR(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local issecretvalue = issecretvalue

-- Services / helpers
local COLORS              = ns.UI_COLORS
local CreateCard          = ns.UI_CreateCard
local ApplyVisuals        = ns.UI_ApplyVisuals
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetQualityHex       = ns.UI_GetQualityHex
local CreateThemedButton  = ns.UI_CreateThemedButton
local FormatGold          = ns.UI_FormatGold
local FormatNumber        = ns.UI_FormatNumber
local DrawEmptyState      = ns.UI_DrawEmptyState
local CreateHeaderIcon    = ns.UI_CreateHeaderIcon
local GetTabIcon          = ns.UI_GetTabIcon
local ShowTooltip         = ns.UI_ShowTooltip
local HideTooltip         = ns.UI_HideTooltip
local ApplyProfessionCraftingQualityAtlasToTexture = ns.UI_ApplyProfessionCraftingQualityAtlasToTexture
local GetEnchantmentCraftingQualityTierFromItemLink = ns.UI_GetEnchantmentCraftingQualityTierFromItemLink

-- Slot definitions from GearService
local GEAR_SLOTS         = ns.GEAR_SLOTS
local SLOT_BY_ID         = ns.SLOT_BY_ID
local EQUIP_LOC_TO_SLOTS = ns.EQUIP_LOC_TO_SLOTS

local format = string.format

local WEAPON_ENCHANT_EQUIP_LOCS = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON = true,
}

---Midnight primary-enchant expectation by slot + equip location.
---@param slotID number
---@param slotData table|nil
---@return boolean
local function IsPrimaryEnchantExpected(slotID, slotData)
    local enchantableSlots = Constants and Constants.GEAR_ENCHANTABLE_SLOTS
    if not (enchantableSlots and enchantableSlots[slotID]) then
        return false
    end
    if slotID == 16 or slotID == 17 then
        local equipLoc = slotData and slotData.equipLoc or ""
        return WEAPON_ENCHANT_EQUIP_LOCS[equipLoc] == true
    end
    return true
end

--- English track names from Blizzard tooltip/API → locale (e.g. zhCN PVE_CREST_*).
local function LocalizeUpgradeTrackName(name)
    if not name or name == "" then return name end
    if issecretvalue and issecretvalue(name) then return name end
    local L = ns.L
    if not L then return name end
    local trimmed = name:match("^%s*(.-)%s*$") or name
    local key = ({
        Adventurer = "PVE_CREST_ADV",
        Veteran = "PVE_CREST_VET",
        Champion = "PVE_CREST_CHAMP",
        Hero = "PVE_CREST_HERO",
        Myth = "PVE_CREST_MYTH",
        Explorer = "PVE_CREST_EXPLORER",
        Crafted = "GEAR_TRACK_CRAFTED_FALLBACK",
    })[trimmed]
    if key and L[key] then return L[key] end
    return name
end

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

--- Color-code upgrade-track tiers like item quality: Adventurer→common, Veteran→uncommon,
--- Champion→rare, Hero→epic, Myth→legendary. Returns hex (no #) or nil for unknown tiers.
local UPGRADE_TRACK_TIER_HEX = {
    Adventurer = "9d9d9d",
    Explorer   = "9d9d9d",
    Veteran    = "1eff00",
    Champion   = "0070dd",
    Hero       = "a335ee",
    Myth       = "ff8000",
}
local function GetUpgradeTrackHex(englishName)
    if not englishName or englishName == "" then return nil end
    local trimmed = englishName:match("^%s*(.-)%s*$") or englishName
    return UPGRADE_TRACK_TIER_HEX[trimmed]
end

local function FormatFloat2(value)
    if not value then return nil end
    local n = tonumber(value)
    if not n then return nil end
    return format("%.2f", n)
end

-- ============================================================================
-- CONSTANTS / LAYOUT  (addon theme: ns.UI_LAYOUT when available)
-- ============================================================================

local function GetLayout() return ns.UI_LAYOUT or {} end
local UI_LAYOUT      = ns.UI_LAYOUT or {}
local SIDE_MARGIN    = UI_LAYOUT.SIDE_MARGIN or 16
local TOP_MARGIN     = UI_LAYOUT.TOP_MARGIN or 12
local HEADER_H       = UI_LAYOUT.HEADER_HEIGHT or 32
-- Character strip + dropdown: match header controls elsewhere (SharedWidgets sort dropdown = 32px row, 26px menu entries).
local GEAR_CHAR_SELECTOR_WIDTH = 292
local GEAR_CHAR_SELECTOR_HEIGHT = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or HEADER_H or 32
local GEAR_CHAR_DROPDOWN_ENTRY_H = 26
local GEAR_HIDE_FILTER_BUTTON_W = 84

-- Paper doll: sol panel | orta panel | sağ panel | alt panel (fixed widths); %10 büyütme
local PAPERDOLL_SCALE = 1.10
local function P(n) return math.floor(n * PAPERDOLL_SCALE + 0.5) end
local SLOT_SIZE      = P(38)
local SLOT_GAP       = P(5)
local DOLL_PAD       = P(12)
local SLOT_TO_ARROW_GAP = P(4)   -- slot ile upgrade ikonu arası
local ARROW_TO_TEXT_GAP = P(6)   -- ok ile yazı arası boşluk (artık yaslamalı olduğu için pozitif olmalı)
local TRACK_TEXT_W   = P(136)  -- Track metin taşmasını engellemek için genişletildi
local UPGRADE_ARROW_W = P(16)
local CURRENCY_PANEL_W = 248
local GEAR_STAT_PANEL_W = 292
local CENTER_GAP     = P(10)
local CURRENCY_PAPERDOLL_GAP = 14  -- boşluk crest paneli ile paperdoll arası

-- Fixed panel widths: sol = yazı + ikon + slot, sağ = slot + ikon + yazı
local LEFT_PANEL_W   = TRACK_TEXT_W + ARROW_TO_TEXT_GAP + UPGRADE_ARROW_W + SLOT_TO_ARROW_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_ARROW_GAP + UPGRADE_ARROW_W + 2 + ARROW_TO_TEXT_GAP + TRACK_TEXT_W
local MODEL_W       = P(248)
-- Neutral center fill: Blizzard tooltip tile (FrameXML Backdrop — see warcraft.wiki.gg UIOBJECT Frame / Backdrop).
-- Avoids a flat ColorTexture “void” without class-specific art.
local GEAR_MODEL_PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    tile = true,
    tileSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
-- Paperdoll blok genişliği (sol kolon + model + sağ kolon) — kart içinde ortalanır
local PAPERDOLL_BLOCK_W = LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP + RIGHT_PANEL_W

-- Gear tab: paperdoll column | narrow info column (stats then currencies) | recommendations.
local GEAR_PANEL_GAP = 10
local MIN_GEAR_PANEL_W = PAPERDOLL_BLOCK_W
local GEAR_REC_COL_MIN_W = 218
local GEAR_MID_COL_MIN_W = 228
local GEAR_MID_COL_PREF_W = 340
local GEAR_PAPER_COL_W = PAPERDOLL_BLOCK_W + 8
local MIN_CARD_INNER_W = GEAR_PAPER_COL_W + GEAR_PANEL_GAP + GEAR_MID_COL_MIN_W + GEAR_PANEL_GAP + GEAR_REC_COL_MIN_W
-- Minimum scrollChild width: daraldığında yatay scroll, elementler üst üste binmesin
local MIN_GEAR_CARD_W = 2 * (SIDE_MARGIN or 16) + 2 * 12 + MIN_CARD_INNER_W  -- 12 = CARD_PAD
ns.MIN_GEAR_CARD_W = MIN_GEAR_CARD_W  -- used by UI.lua for scrollChild width on gear tab

-- Ortadan çizgi hizalama: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ)
local SLOT_HALF      = SLOT_SIZE / 2
local ARROW_HALF     = UPGRADE_ARROW_W / 2
local TEXT_HALF_W   = TRACK_TEXT_W / 2
-- Slot merkezinden ok merkezine uzaklık (px) — ikon eski yerinde
local ARROW_OFFSET_FROM_SLOT_CENTER = SLOT_HALF + SLOT_TO_ARROW_GAP + ARROW_HALF
-- Slot merkezinden yazı bloğu merkezine uzaklık (px) — sadece yazı ikona yakın
local TEXT_OFFSET_FROM_SLOT_CENTER  = ARROW_OFFSET_FROM_SLOT_CENTER + ARROW_HALF + ARROW_TO_TEXT_GAP + TEXT_HALF_W

-- Empty slot textures (standard WoW interface art)
local EMPTY_SLOT_TEXTURE = {
    [1]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Head",
    [2]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Neck",
    [3]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Shoulder",
    [5]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest",
    [6]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Waist",
    [7]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Legs",
    [8]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Feet",
    [9]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Wrist",
    [10] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Hands",
    [11] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    [12] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    [13] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    [14] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    [15] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Back",
    [16] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-MainHand",
    [17] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-SecondaryHand",
}

local SLOT_FALLBACK_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Bag"

-- ============================================================================
-- SESSION STATE  (selected character; persists within session)
-- ============================================================================

local selectedCharKey = nil  -- nil = auto-select current player

local function GetSelectedCharKey()
    if selectedCharKey then return selectedCharKey end
    return ns.Utilities and ns.Utilities:GetCharacterKey()
end

local function GetLowLevelHideThreshold(profile)
    if not profile then return 0 end
    local threshold = tonumber(profile.hideLowLevelThreshold) or 0
    if threshold >= 90 then return 90 end
    if threshold >= 80 then return 80 end
    -- Backward compatibility for older boolean setting.
    if profile.hideLowLevelCharacters == true then
        return 80
    end
    return 0
end

local function GetLowLevelHideCycleNext(current)
    if current == 0 then return 80 end
    if current == 80 then return 90 end
    return 0
end

local function GetLowLevelHideLabel(threshold)
    if threshold == 90 then return GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") end
    if threshold == 80 then return GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

local function ApplyLowLevelHideThreshold(threshold)
    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not profile then return end
    local nextThreshold = tonumber(threshold) or 0
    if nextThreshold ~= 80 and nextThreshold ~= 90 then
        nextThreshold = 0
    end
    profile.hideLowLevelThreshold = nextThreshold
    profile.hideLowLevelCharacters = (nextThreshold >= 80)
    local events = Constants and Constants.EVENTS
    if WarbandNexus and WarbandNexus.SendMessage and events and events.CHARACTER_TRACKING_CHANGED then
        WarbandNexus:SendMessage(events.CHARACTER_TRACKING_CHANGED, {
            source = "HideFilter",
            threshold = nextThreshold,
        })
    end
end

-- Gear event refresh is centralized in UI.lua SchedulePopulateContent
-- (WN_GEAR_UPDATED, WN_ITEMS_UPDATED, WN_CHARACTER_UPDATED, WN_CURRENCY_UPDATED).

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Get tracked characters honoring user prefs:
---   * `db.profile.hideLowLevelThreshold` filters out chars below level 80/90.
---   * `db.profile.characterOrder` (favorites + regular arrays) drives manual order;
---     unranked chars fall back to lastSeen DESC. Mirrors PvE/Characters tab order.
local function GetTrackedCharacters()
    local chars = {}
    local db = WarbandNexus.db and WarbandNexus.db.global
    if not db or not db.characters then return chars end
    local profile = WarbandNexus.db and WarbandNexus.db.profile or {}
    local minLevel = GetLowLevelHideThreshold(profile)
    for charKey, data in pairs(db.characters) do
        local lvl = tonumber(data.level) or 0
        if data.isTracked and (minLevel == 0 or lvl >= minLevel) then
            chars[#chars + 1] = { key = charKey, data = data }
        end
    end

    -- Manual order index from db.profile.characterOrder.{favorites, regular}.
    local rankOf, nextRank = {}, 1
    local order = profile.characterOrder
    if order then
        for _, list in ipairs({ order.favorites or {}, order.regular or {} }) do
            for _, k in ipairs(list) do
                if rankOf[k] == nil then
                    rankOf[k] = nextRank
                    nextRank = nextRank + 1
                end
            end
        end
    end

    table.sort(chars, function(a, b)
        local ra, rb = rankOf[a.key], rankOf[b.key]
        if ra and rb then return ra < rb end
        if ra and not rb then return true end
        if rb and not ra then return false end
        return (a.data.lastSeen or 0) > (b.data.lastSeen or 0)
    end)
    return chars
end

--- Format item level with quality color (real data only; empty slot = empty string).
local function ColoredIlvl(ilvl, quality)
    if not ilvl or ilvl == 0 then return "" end
    local hex = GetQualityHex and GetQualityHex(quality or 0) or "ffffff"
    return format("|cff%s%d|r", hex, ilvl)
end

---@param linkOrId string|number itemLink or itemID
---@return number|string|nil texture (fileID or path)
local function GetItemIconSafe(linkOrId)
    if not linkOrId then return nil end
    local ok, result = pcall(function()
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(linkOrId)
            if icon and icon ~= 0 and icon ~= "" then return icon end
        end
        local itemId = type(linkOrId) == "number" and linkOrId or nil
        if not itemId and type(linkOrId) == "string" then
            if issecretvalue and issecretvalue(linkOrId) then
                itemId = nil
            else
                itemId = tonumber(linkOrId:match("item:(%d+)"))
            end
        end
        if not itemId then return nil end
        -- GetItemInfoInstant returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        if icon and icon ~= 0 and icon ~= "" then return icon end
        return nil
    end)
    return (ok and result) or nil
end

-- ============================================================================
-- CRAFTED ITEM RECRAFT RANGE
-- ============================================================================

--- Calculate achievable ilvl range for a crafted item based on player's crest inventory.
--- Crafted items can be recrafted with crests to jump to higher ilvl tiers.
--- Each tier has its own crest type and cost (e.g. Myth = 80 crests, Hero = 60).
--- Also returns the next unaffordable tier info so UI can show what's needed.
---@param upInfo table slot upgrade info with isCrafted=true
---@param currencyAmounts table map currencyID → amount
---@return table|nil { minIlvl, maxIlvl, bestCrestName, bestCrestCost, nextTierName, nextTierCost, nextTierHave, nextTierMaxIlvl } or nil if no crests
local function GetCraftedIlvlRange(upInfo, currencyAmounts)
    if not upInfo or not upInfo.isCrafted then return nil end
    local currentIlvl = upInfo.currentIlvl or 0
    local tiers = ns.CRAFTED_CREST_TIERS
    if not tiers or not currencyAmounts then return nil end

    local bestMaxIlvl = currentIlvl
    local bestCrestName = nil
    local bestCrestCost = 0
    local nextTierName, nextTierCost, nextTierHave, nextTierMaxIlvl = nil, nil, nil, nil

    for i = 1, #tiers do
        local tier = tiers[i]
        local have = currencyAmounts[tier.crestID] or 0
        if have >= tier.cost and tier.maxIlvl > currentIlvl then
            bestMaxIlvl = tier.maxIlvl
            bestCrestName = tier.name
            bestCrestCost = tier.cost
            break
        elseif tier.maxIlvl > currentIlvl and not nextTierName then
            nextTierName = tier.name
            nextTierCost = tier.cost
            nextTierHave = have
            nextTierMaxIlvl = tier.maxIlvl
        end
    end

    if bestMaxIlvl <= currentIlvl then return nil end

    return {
        minIlvl = currentIlvl,
        maxIlvl = bestMaxIlvl,
        bestCrestName = bestCrestName,
        bestCrestCost = bestCrestCost,
        nextTierName = nextTierName,
        nextTierCost = nextTierCost,
        nextTierHave = nextTierHave,
        nextTierMaxIlvl = nextTierMaxIlvl,
    }
end

--- Hesaplama matematiği (upgrade affordability):
--- - Her tier 20 crest + gold. Watermark: o slotta daha önce ulaşılan max ilvl; o ilvl'e kadar tier'lar "gold only".
--- - Döngü: currTier+1 .. maxTier. Her adımda: ilvl <= watermark ise sadece gold düş; değilse 20 crest + gold düş.
--- - haveCrests / 20 = en fazla crest'li upgrade sayısı değil; tier-by-tier düşüyoruz (3/6→4/6 bir crest, 4/6→5/6 bir crest).
--- - Sonuç: totalAffordable = kaç tier atlanabiliyor, goldOnlyCount = bunlardan kaçı crest gerektirmiyor.
---
--- Calculate affordable upgrades tier-by-tier, accounting for watermark (gold-only) levels.
---@param upInfo table slot upgrade info from GetPersistedUpgradeInfo
---@param currencyAmounts table map currencyID → amount (0 = gold in gold units)
---@return number totalAffordable how many upgrades the player can afford
---@return number goldOnlyCount how many of those are gold-only (below watermark)
local function CalculateAffordableUpgrades(upInfo, currencyAmounts)
    if not upInfo or not upInfo.canUpgrade then return 0, 0 end

    local currTier = upInfo.currUpgrade or 0
    local maxTier = upInfo.maxUpgrade or 0
    if currTier >= maxTier then return 0, 0 end

    local trackName = upInfo.trackName
    local TRACK_ILVLS = ns.TRACK_ILVLS
    local tiers = TRACK_ILVLS and TRACK_ILVLS[trackName]
    if not tiers then return 0, 0 end

    local wmIlvl = upInfo.watermarkIlvl or 0
    local goldPerUpgrade = upInfo.moneyCost or (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000)
    local crestPerUpgrade = upInfo.crestCost or (ns.UPGRADE_CREST_PER_LEVEL or 20)
    local currencyID = upInfo.currencyID or 0

    local haveGoldCopper = ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
    local haveCrests = (currencyAmounts and currencyAmounts[currencyID]) or 0

    local totalAffordable = 0
    local goldOnlyCount = 0

    for nextTier = currTier + 1, maxTier do
        local nextIlvl = tiers[nextTier]
        if not nextIlvl then break end

        local isGoldOnly = (nextIlvl <= wmIlvl)

        if haveGoldCopper < goldPerUpgrade then break end

        if not isGoldOnly then
            if haveCrests < crestPerUpgrade then break end
            haveCrests = haveCrests - crestPerUpgrade
        end

        haveGoldCopper = haveGoldCopper - goldPerUpgrade
        totalAffordable = totalAffordable + 1
        if isGoldOnly then
            goldOnlyCount = goldOnlyCount + 1
        end
    end

    return totalAffordable, goldOnlyCount
end

--- Check if the player can afford at least one upgrade for this slot.
---@param upInfo table slot upgrade info from GetPersistedUpgradeInfo
---@param currencyAmounts table map currencyID → amount
---@return boolean
local function CanAffordNextUpgrade(upInfo, currencyAmounts)
    if not upInfo or not upInfo.canUpgrade then return false end
    if upInfo.isCrafted then
        local range = GetCraftedIlvlRange(upInfo, currencyAmounts)
        return range and range.maxIlvl > (upInfo.currentIlvl or 0)
    end
    local count = CalculateAffordableUpgrades(upInfo, currencyAmounts)
    return count > 0
end

--- Get the class color hex for a classFile string (e.g. "SHAMAN").
local function GetClassHex(classFile)
    if not classFile then return "ffffff" end
    local classColors = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if classColors then
        return format("%02x%02x%02x",
            math.floor(classColors.r * 255),
            math.floor(classColors.g * 255),
            math.floor(classColors.b * 255))
    end
    -- Fallback from Constants
    local Constants = ns.Constants
    if Constants and Constants.CLASS_COLORS and Constants.CLASS_COLORS[classFile] then
        local s = Constants.CLASS_COLORS[classFile]
        return s:gsub("|cff", "")
    end
    return "ffffff"
end

--- Tooltip spec: prefer saved specID; else first spec for class (offline / stale DB still get correct primary stat).
local function GetGearTabTooltipSpecID(charData)
    if not charData then return nil end
    local sid = tonumber(charData.specID)
    if sid and sid > 0 then return sid end
    local cid = tonumber(charData.classID)
    if not cid or cid < 1 then
        local cf = charData.classFile
        if type(cf) == "string" and cf ~= "" then
            local uc = strupper or string.upper
            local map = Constants and Constants.CLASS_FILE_TO_CLASS_ID
            cid = map and map[uc(cf)]
        end
    end
    if cid and cid > 0 and GetSpecializationInfoForClassID then
        local specID = select(1, GetSpecializationInfoForClassID(cid, 1))
        specID = tonumber(specID)
        if specID and specID > 0 then return specID end
    end
    return nil
end

--- { level, specID } for TooltipService when showing Gear tab items for this character.
local function BuildGearTabItemTooltipContext(charData)
    if not charData then return nil end
    local lvl = tonumber(charData.level)
    if not lvl or lvl < 1 then return nil end
    local specID = GetGearTabTooltipSpecID(charData)
    if not specID or specID < 1 then return nil end
    return { level = lvl, specID = specID }
end

-- Enchant quality glyph: same anchor band as missing-enchant/gem alert (arrow ±9), profession atlases from SharedWidgets.
local GEAR_ENCHANT_QUALITY_SZ = 18

--- True if item hyperlink encodes a non-zero enchant id in the standard payload field.
local function ItemLinkHasEnchantment(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return false end
    if issecretvalue and issecretvalue(itemLink) then return false end
    local segment = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:[^|]+)|h") or itemLink
    local body = segment:match("^item:(.+)$") or segment
    local _, enc = body:match("^(%d+):([^:]*):")
    if not _ then
        _, enc = body:match("^(%d+):([^:]*)$")
    end
    if enc and enc ~= "" then
        local e = tonumber(enc)
        if e and e > 0 then return true end
    end
    return false
end

--- Permanent enchant row tier from C_TooltipInfo (same source as Blizzard “Enchanted:” glyph).
--- Item:GetCraftingQuality() is the base item’s craft tier — wrong when enchant rank differs (e.g. R2 enchant on R1 item).
---@param itemLink string|nil
---@return number|nil 1–3 for display, or nil if unknown
local function GetGearSlotEnchantQualityTier(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if not GetEnchantmentCraftingQualityTierFromItemLink then return nil end
    local q = GetEnchantmentCraftingQualityTierFromItemLink(itemLink)
    q = tonumber(q)
    if q and q >= 1 then return q end
    return nil
end

--- Apply profession crafting-quality atlas or engraving fallback.
local function SetupGearSlotEnchantQualityTexture(tex, tierIdx)
    if not tex then return false end
    local tier = tonumber(tierIdx) or 1
    if tier < 1 then tier = 1 end
    if ApplyProfessionCraftingQualityAtlasToTexture and ApplyProfessionCraftingQualityAtlasToTexture(tex, tier, GEAR_ENCHANT_QUALITY_SZ) then
        return true
    end
    tex:SetTexture("Interface\\Icons\\Trade_Engraving")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(0.82, 0.76, 1.0, 0.92)
    tex:SetSize(GEAR_ENCHANT_QUALITY_SZ, GEAR_ENCHANT_QUALITY_SZ)
    tex:Show()
    return true
end

--- Stack offset below upgrade arrow when warn + quality both visible (px).
local GEAR_AUX_STACK_STEP = 18

--- Missing gem/enchant alert + enchant-quality glyph share this anchor band (below upgrade arrow when present).
local function PlaceGearAuxSlotIcon(btn, tex, side, arrowAnchor, upgradeArrowPresent, stackIndex)
    local si = stackIndex or 1
    local yOff = 0
    if upgradeArrowPresent then
        yOff = -9 - GEAR_AUX_STACK_STEP * (si - 1)
    elseif si > 1 then
        yOff = -GEAR_AUX_STACK_STEP * (si - 1)
    end
    if side == "left" then
        tex:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, yOff)
    elseif side == "right" then
        tex:SetPoint("CENTER", btn, "CENTER", ARROW_OFFSET_FROM_SLOT_CENTER, yOff)
    else
        if arrowAnchor then
            tex:SetPoint("CENTER", arrowAnchor, "CENTER", 0, yOff)
        else
            tex:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, yOff)
        end
    end
end

-- ============================================================================
-- SLOT ICON BUTTON
-- ============================================================================

--- Create a single equipment slot icon button.
---@param parent Frame
---@param slotID number
---@param slotData table|nil  { itemLink, itemLevel, quality, name, ... }
---@param x number x offset from parent TOPLEFT
---@param y number y offset (negative = downward) from parent TOPLEFT
---@param isUpgradable boolean|nil if true, show green arrow overlay
---@param statusText string|nil e.g. "Veteran 6/6", "Champion 4/8", or nil to show ilvl/"—"
---@param textSide string|nil "right" | "left" | "top" — where to place status text relative to icon
---@param isNotUpgradeable boolean|nil if true, show a lock icon overlay (item confirmed not upgradeable)
---@param centerTextOnIcon boolean|nil if true, center slot name + track text relative to slot icon (weapon row)
---@param upgradeInfo table|nil optional; when set, tooltip shows next upgrade tier and cost for this slot
---@param currencyAmounts table|nil optional; map currencyID -> amount (for "you have X" in tooltip if needed)
---@param itemTooltipContext table|nil optional { level, specID } — rewrite item link for C_TooltipInfo primary-stat lines (Gear tab / viewed character)
---@return Frame btn
local function CreateSlotButton(parent, slotID, slotData, x, y, isUpgradable, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon, upgradeInfo, currencyAmounts, itemTooltipContext)
    -- Slot her zaman aynı boyutta; ikon görünmese bile boşluk rezerve (empty texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    btn:SetPoint("TOPLEFT", x, y)

    -- Outer border frame (quality color rim)
    local borderFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    borderFrame:SetAllPoints()
    borderFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn.borderFrame = borderFrame

    -- Dark background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.9)

    -- Item / empty slot texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.iconTex = tex

    -- ilvl label (bottom-right overlay); font must be set before any SetText (WoW requirement)
    local ilvlLabel = btn:CreateFontString(nil, "OVERLAY")
    ilvlLabel:SetPoint("BOTTOMRIGHT", -2, 2)
    ilvlLabel:SetFontObject(SystemFont_Tiny)  -- ensure font set before Populate() ever calls SetText
    if FontManager and FontManager.CreateFontString then
        local fs = FontManager:CreateFontString(btn, GFR("gearSlotIlvl"), "OVERLAY")
        if fs and fs.SetFontObject then
            fs:SetPoint("BOTTOMRIGHT", -2, 2)
            fs:SetJustifyH("RIGHT")
            if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
            btn.ilvlLabel = fs
            ilvlLabel:SetAlpha(0)
        else
            btn.ilvlLabel = ilvlLabel
        end
    else
        btn.ilvlLabel = ilvlLabel
        if ilvlLabel.SetDrawLayer then ilvlLabel:SetDrawLayer("OVERLAY", 7) end
    end

    -- Populate with item or empty slot art
    local function Populate(data)
        if data and data.itemLink then
            local icon = GetItemIconSafe(data.itemLink)
            if icon then
                tex:SetTexture(icon)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                tex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
                tex:SetTexCoord(0, 1, 0, 1)
            end

            -- Quality border color
            local q = data.quality or 0
            local r, g, b = GetItemQualityColor(q)
            borderFrame:SetBackdropBorderColor(r or 0.4, g or 0.4, b or 0.4, 1)

            -- ilvl label (only when slot has an item link and valid ilvl)
            if btn.ilvlLabel and data.itemLink and data.itemLevel and data.itemLevel > 0 then
                btn.ilvlLabel:SetText(data.itemLevel)
                btn.ilvlLabel:SetTextColor(1, 1, 1)
                btn.ilvlLabel:SetShadowOffset(1, -1)
                btn.ilvlLabel:SetShadowColor(0, 0, 0, 1)
                btn.ilvlLabel:Show()
            elseif btn.ilvlLabel then
                btn.ilvlLabel:Hide()
            end
        else
            -- Empty slot
            tex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
            tex:SetTexCoord(0, 1, 0, 1)
            local accent = COLORS and COLORS.accent or { 0.5, 0.3, 0.8 }
            borderFrame:SetBackdropBorderColor(accent[1] * 0.4, accent[2] * 0.4, accent[3] * 0.4, 0.5)
            if btn.ilvlLabel then btn.ilvlLabel:Hide() end
        end
    end

    Populate(slotData)

    local side = textSide or "right"
    local upgradeArrow = nil
    local arrowAnchor = nil  -- bottom: her zaman ikon boyutu kadar boşluk rezerve

    -- Alt (weapon): yazı + ok ikonun YANINDA (aynı satır). Main Hand = solda, Off Hand = sağda
    local isBottomLeft  = (side == "bottom" or side == "bottom_left")
    local isBottomRight = (side == "bottom_right")
    if isBottomLeft or isBottomRight then
        arrowAnchor = CreateFrame("Frame", nil, btn)
        arrowAnchor:SetSize(UPGRADE_ARROW_W, UPGRADE_ARROW_W)
        -- Ok ikonu slotla aynı dikey hizada, Main Hand'ta slotun solunda, Off Hand'ta sağında
        if isBottomLeft then
            arrowAnchor:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        else
            arrowAnchor:SetPoint("CENTER", btn, "CENTER", ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        end
    end

    -- Ortadan çizgi: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ/alt)
    local upSlot = upgradeInfo and upgradeInfo[slotID]
    local isCraftedSlot = upSlot and upSlot.isCrafted
    if isUpgradable then
        upgradeArrow = btn:CreateTexture(nil, "OVERLAY")
        upgradeArrow:SetSize(UPGRADE_ARROW_W, UPGRADE_ARROW_W)
        if isCraftedSlot and upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("Professions-Crafting-Orders-Icon", false)
        elseif upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("loottoast-arrow-green", false)
        else
            upgradeArrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            upgradeArrow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            upgradeArrow:SetVertexColor(0.2, 1, 0.25)
        end
        if side == "left" then
            upgradeArrow:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        elseif (side == "bottom" or side == "bottom_left" or side == "bottom_right") and arrowAnchor then
            upgradeArrow:SetPoint("CENTER", arrowAnchor, "CENTER", 0, 0)
        else
            upgradeArrow:SetPoint("CENTER", btn, "CENTER", ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        end
    elseif isNotUpgradeable and slotData and slotData.itemLink then
        local lockIcon = btn:CreateTexture(nil, "OVERLAY")
        lockIcon:SetSize(12, 12)
        if (side == "bottom" or side == "bottom_left" or side == "bottom_right") and arrowAnchor then
            lockIcon:SetPoint("CENTER", arrowAnchor, "CENTER", 0, 0)
        elseif side == "left" then
            lockIcon:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        else
            lockIcon:SetPoint("CENTER", btn, "CENTER", ARROW_OFFSET_FROM_SLOT_CENTER, 0)
        end
        lockIcon:SetTexture("Interface\\Common\\LockIcon")
        lockIcon:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    end

    -- Tooltip: item link + simplified upgrade info (custom tooltip service)
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    
    -- Dynamically evaluate enchant and gem status from itemLink so it works for offline characters
    local hasEnchant = false
    local isMissingGem = false
    local isEnchantable = false
    local craftingQualityTier = nil

    if slotData and slotData.itemLink then
        local link = slotData.itemLink
        if not (issecretvalue and issecretvalue(link)) then
            hasEnchant = ItemLinkHasEnchantment(link)

            local stats = GetItemStats and GetItemStats(link) or {}
            for k, v in pairs(stats) do
                if type(k) == "string" and not (issecretvalue and issecretvalue(k)) and string.find(k, "EMPTY_SOCKET_") then
                    isMissingGem = true
                    break
                end
            end

            isEnchantable = IsPrimaryEnchantExpected(slotID, slotData)
            craftingQualityTier = GetGearSlotEnchantQualityTier(link)
        end
    end

    local showWarn = slotData and slotData.itemLink and (isMissingGem or (isEnchantable and not hasEnchant))
    local showEnchantQuality = slotData and slotData.itemLink and hasEnchant
    local enchantDisplayTier = tonumber(craftingQualityTier) or 1
    if enchantDisplayTier < 1 then enchantDisplayTier = 1 end

    local upArrow = upgradeArrow ~= nil
    if upArrow and (showWarn or showEnchantQuality) then
        upgradeArrow:ClearAllPoints()
        if side == "left" then
            upgradeArrow:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, 9)
        elseif side == "right" then
            upgradeArrow:SetPoint("CENTER", btn, "CENTER", ARROW_OFFSET_FROM_SLOT_CENTER, 9)
        else
            if arrowAnchor then
                upgradeArrow:SetPoint("CENTER", arrowAnchor, "CENTER", 0, 9)
            else
                upgradeArrow:SetPoint("CENTER", btn, "CENTER", -ARROW_OFFSET_FROM_SLOT_CENTER, 9)
            end
        end
    end

    local auxStack = 1
    if showWarn then
        local warnIcon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        warnIcon:SetSize(18, 18)
        warnIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        PlaceGearAuxSlotIcon(btn, warnIcon, side, arrowAnchor, upArrow, auxStack)
        auxStack = auxStack + 1
        btn.warnIcon = warnIcon
    end
    if showEnchantQuality then
        local eqTex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        eqTex:SetSize(GEAR_ENCHANT_QUALITY_SZ, GEAR_ENCHANT_QUALITY_SZ)
        SetupGearSlotEnchantQualityTexture(eqTex, enchantDisplayTier)
        PlaceGearAuxSlotIcon(btn, eqTex, side, arrowAnchor, upArrow, auxStack)
        btn.enchantQualityIcon = eqTex
    end
    
    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            local up = upgradeInfo and upgradeInfo[slotID]
            local additionalLines = {}
            local underTitleLines
            
            -- Missing Enchant/Gem warnings at the top of additional lines
            if isEnchantable and not hasEnchant then
                additionalLines[#additionalLines + 1] = {
                    text = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14|t |cffff3333" .. ((ns.L and ns.L["GEAR_MISSING_ENCHANT"]) or "Missing Enchant") .. "|r",
                    color = {1, 0.2, 0.2}
                }
            end
            if isMissingGem then
                additionalLines[#additionalLines + 1] = {
                    text = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14|t |cffff3333" .. ((ns.L and ns.L["GEAR_MISSING_GEM"]) or "Missing Gem") .. "|r",
                    color = {1, 0.2, 0.2}
                }
            end
            
            if up and up.isCrafted then
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                local tierLabel = LocalizeUpgradeTrackName(up.craftedTierName or "Crafted")
                if not up.canUpgrade then
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_CRAFTED_MAX_ILVL_LINE"]) or "%s (max ilvl %d)", tierLabel, up.currentIlvl or 0),
                        color = { 0.6, 0.6, 0.6 }
                    }
                else
                    local range = GetCraftedIlvlRange(up, currencyAmounts)
                    if range then
                        local bestName = LocalizeUpgradeTrackName(range.bestCrestName or "")
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_CRAFTED_RECAST_TO_LINE"]) or "Recraft to %s (ilvl %d)", bestName, range.maxIlvl),
                            color = { 0.4, 1, 0.4 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_CRAFTED_COST_DAWNCREST"]) or "Cost: %d %s Dawncrest", range.bestCrestCost or 0, bestName),
                            color = { 0.6, 0.9, 0.6 }
                        }
                        if range.nextTierName and range.nextTierCost and range.nextTierHave then
                            local needed = range.nextTierCost - range.nextTierHave
                            if needed > 0 then
                                additionalLines[#additionalLines + 1] = {
                                    text = format((ns.L and ns.L["GEAR_CRAFTED_NEXT_TIER_CRESTS"]) or "%s (ilvl %d): %d/%d crests (%d more needed)", LocalizeUpgradeTrackName(range.nextTierName), range.nextTierMaxIlvl or 0, range.nextTierHave, range.nextTierCost, needed),
                                    color = { 0.7, 0.7, 0.7 }
                                }
                            end
                        end
                    else
                        additionalLines[#additionalLines + 1] = {
                            text = (ns.L and ns.L["GEAR_CRAFTED_NO_CRESTS"]) or "No crests available for recraft",
                            color = { 0.8, 0.5, 0.2 }
                        }
                    end
                end
            elseif up and up.canUpgrade then
                local affordable, goldOnly = CalculateAffordableUpgrades(up, currencyAmounts)
                if affordable > 0 then
                    additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                    -- Show achievable target only (e.g. 2/6 when 20 crests and 1/6 — not 6/6).
                    local targetTier = (up.currUpgrade or 0) + affordable
                    local TRACK_ILVLS = ns.TRACK_ILVLS
                    local targetIlvl = TRACK_ILVLS and TRACK_ILVLS[up.trackName] and TRACK_ILVLS[up.trackName][targetTier]
                    local ilvlStr = targetIlvl and format(" (%d)", targetIlvl) or ""
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_UPGRADE_AVAILABLE_FORMAT"]) or "Available upgrade to %s %d/%d%s", LocalizeUpgradeTrackName(up.trackName or ""), targetTier, up.maxUpgrade or 0, ilvlStr),
                        color = { 0.4, 1, 0.4 }
                    }
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"]) or "%d upgrade(s) with current currency", affordable),
                        color = { 0.6, 0.9, 0.6 }
                    }
                    if goldOnly > 0 then
                        if goldOnly >= affordable then
                            additionalLines[#additionalLines + 1] = {
                                text = (ns.L and ns.L["GEAR_CRESTS_GOLD_ONLY"]) or "Crests needed: 0 (gold only — previously reached)",
                                color = { 1, 0.85, 0.4 }
                            }
                        else
                            additionalLines[#additionalLines + 1] = {
                                text = format((ns.L and ns.L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"]) or "%d upgrade(s) gold only (previously reached)", goldOnly),
                                color = { 1, 0.85, 0.4 }
                            }
                        end
                    end
                else
                    underTitleLines = {
                        {
                            text = format((ns.L and ns.L["GEAR_NEED_MORE_CRESTS_FORMAT"]) or "%s %d/%d — need more crests", LocalizeUpgradeTrackName(up.trackName or ""), up.currUpgrade or 0, up.maxUpgrade or 0),
                            color = { 0.8, 0.5, 0.2 }
                        }
                    }
                end
            end
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    underTitleLines = underTitleLines,
                    anchor = "ANCHOR_RIGHT",
                    itemTooltipContext = itemTooltipContext,
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    underTitleLines = underTitleLines,
                    anchor = "ANCHOR_RIGHT",
                    itemTooltipContext = itemTooltipContext,
                })
            end
        else
            local title = (slotDef and slotDef.label) or "Empty"
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = (ns.L and ns.L["GEAR_NO_ITEM_EQUIPPED"]) or "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                    anchor = "ANCHOR_RIGHT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = (ns.L and ns.L["GEAR_NO_ITEM_EQUIPPED"]) or "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                    anchor = "ANCHOR_RIGHT",
                })
            end
        end
    end)
    btn:SetScript("OnLeave", function()
        if HideTooltip then
            HideTooltip()
        elseif ns.TooltipService then
            ns.TooltipService:Hide()
        end
    end)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.12)

    -- Slot adı (Head, Trinket 1, Main Hand vb.) — Veteran/Champion yazısının üstünde
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    local slotName = (slotDef and slotDef.label) and slotDef.label or ""
    if slotID == 11 then slotName = (ns.L and ns.L["GEAR_SLOT_RING1"]) or "Ring 1"
    elseif slotID == 12 then slotName = (ns.L and ns.L["GEAR_SLOT_RING2"]) or "Ring 2"
    elseif slotID == 13 then slotName = (ns.L and ns.L["GEAR_SLOT_TRINKET1"]) or "Trinket 1"
    elseif slotID == 14 then slotName = (ns.L and ns.L["GEAR_SLOT_TRINKET2"]) or "Trinket 2"
    end
    local slotNameLabel
    if slotName ~= "" then
        slotNameLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, GFR("gearSlotName"), "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotNameLabel:SetText("|cffffffff" .. slotName .. "|r")
        slotNameLabel:SetNonSpaceWrap(false)
        if slotNameLabel.SetWordWrap then slotNameLabel:SetWordWrap(false) end
    end

    -- Status label ve text layout
    local trackText = (statusText and statusText ~= "") and statusText or nil
    local trackLabel = nil
    local w = textWidth or TRACK_TEXT_W
    
    local currentTextOffset = TEXT_OFFSET_FROM_SLOT_CENTER
    -- Dikey hizalama yapıldığı için artık +20 yatay itme yapmaya gerek yok

    if trackText and side ~= "top" then
        trackLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, GFR("gearTrackLabel"), "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trackLabel:SetText(trackText)
        trackLabel:SetNonSpaceWrap(false)
        if trackLabel.SetWordWrap then trackLabel:SetWordWrap(false) end
        trackLabel:SetWidth(w)

        if side == "left" or side == "right" or isBottomLeft or isBottomRight then
            local textCenterX
            if side == "left" or isBottomLeft then
                textCenterX = -currentTextOffset
            else
                textCenterX = currentTextOffset
            end
            local textContainer = CreateFrame("Frame", nil, parent)
            textContainer:SetSize(textWidth or TRACK_TEXT_W, P(42))
            textContainer:SetPoint("CENTER", btn, "CENTER", textCenterX, 0)
            
            local blockCenterOffset = 8
            trackLabel:SetParent(textContainer)
            trackLabel:ClearAllPoints()
            trackLabel:SetWidth(textWidth or TRACK_TEXT_W)
            trackLabel:SetPoint("CENTER", textContainer, "CENTER", 0, -blockCenterOffset)
            
            -- Set justification based on side to fix the huge gap
            if side == "left" or isBottomLeft then
                trackLabel:SetJustifyH("RIGHT")
            elseif side == "right" or isBottomRight then
                trackLabel:SetJustifyH("LEFT")
            else
                trackLabel:SetJustifyH("CENTER")
            end
            
            if slotNameLabel then
                slotNameLabel:SetParent(textContainer)
                slotNameLabel:ClearAllPoints()
                slotNameLabel:SetPoint("BOTTOM", trackLabel, "TOP", 0, 2)
                slotNameLabel:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
                slotNameLabel:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
                if side == "left" or isBottomLeft then
                    slotNameLabel:SetJustifyH("RIGHT")
                elseif side == "right" or isBottomRight then
                    slotNameLabel:SetJustifyH("LEFT")
                else
                    slotNameLabel:SetJustifyH("CENTER")
                end
            end
        end
    elseif slotNameLabel then
        if side == "left" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", -currentTextOffset, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("RIGHT")
        elseif side == "right" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", currentTextOffset, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("LEFT")
        else
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", (side == "bottom_right") and currentTextOffset or -currentTextOffset, 0)
            slotNameLabel:SetWidth(textWidth or TRACK_TEXT_W)
            slotNameLabel:SetJustifyH((side == "bottom_right") and "LEFT" or "RIGHT")
        end
    end

    return btn
end

-- ============================================================================
-- PAPERDOLL CARD  (full width; doll centered like Characters screen)
-- ============================================================================

local CURRENCY_ROW_H = 26
local ROW_H = 34
local CARD_PAD = 12

--- Build track/tier string from upgradeInfo[slotID], e.g. "Veteran 2/6".
--- For crafted items, shows tier name + ilvl (e.g. "Myth 285") or upgrade arrow (e.g. "Hero → Myth 285").
local function GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)
    local up = upgradeInfo and upgradeInfo[slotID]
    if not up then return nil end
    local fallbackHex = GetQualityHex and GetQualityHex(quality or 0) or "ffffff"

    -- Crafted items: show current tier + achievable recraft target
    if up.isCrafted then
        local currentEnglish = up.craftedTierName or "Crafted"
        local currentHex = GetUpgradeTrackHex(currentEnglish) or fallbackHex
        local currentTier = LocalizeUpgradeTrackName(currentEnglish)
        local range = currencyAmounts and GetCraftedIlvlRange(up, currencyAmounts) or nil
        if range and range.maxIlvl > (up.currentIlvl or 0) then
            local bestEnglish = range.bestCrestName or ""
            local bestHex = GetUpgradeTrackHex(bestEnglish) or fallbackHex
            return format("|cff%s%s|r → |cff%s%s %d|r",
                currentHex, currentTier, bestHex, LocalizeUpgradeTrackName(bestEnglish), range.maxIlvl)
        end
        return format("|cff%s%s %d|r", currentHex, currentTier, up.currentIlvl or 0)
    end

    local englishTrack = up.trackName
    local track = (englishTrack and englishTrack ~= "") and LocalizeUpgradeTrackName(englishTrack) or nil
    local hex = GetUpgradeTrackHex(englishTrack) or fallbackHex
    local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
    if maxT and maxT > 0 and track then
        return format("|cff%s%s %d/%d|r", hex, track, curT, maxT)
    end
    if track and track ~= "" then return "|cff" .. hex .. track .. "|r" end
    return nil
end

--- Offline character center panel: class-accent top rule + bottom bar with badge (3D/2D preview only).
---@param centerRef Frame
---@param classFile string|nil
local function ApplyGearOfflineCenterChrome(centerRef, classFile)
    if not centerRef then return end
    local chrome = ns._gearOfflineCenterChrome
    if not chrome then
        chrome = CreateFrame("Frame", nil, centerRef)
        chrome:SetAllPoints()
        chrome:EnableMouse(false)
        chrome:EnableMouseWheel(false)
        chrome.isPersistentRowElement = true
        local topLine = chrome:CreateTexture(nil, "ARTWORK", nil, 2)
        topLine:SetHeight(2)
        topLine:SetPoint("TOPLEFT", chrome, "TOPLEFT", 0, -1)
        topLine:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", 0, -1)
        chrome._topLine = topLine
        local bar = CreateFrame("Frame", nil, chrome)
        bar:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", 0, 0)
        bar:SetHeight(36)
        chrome._bar = bar
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0, 0, 0, 0.5)
        chrome._barBg = barBg
        local barClassLine = bar:CreateTexture(nil, "BORDER", nil, 1)
        barClassLine:SetHeight(2)
        barClassLine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        barClassLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        chrome._barClassLine = barClassLine
        local label = FontManager:CreateFontString(chrome, GFR("gearChromeHint"), "OVERLAY")
        label:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 10, 7)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.93, 0.94, 0.96, 0.95)
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(0, 0, 0, 0.9)
        chrome._label = label
        ns._gearOfflineCenterChrome = chrome
    end
    if chrome:GetParent() ~= centerRef then
        chrome:SetParent(centerRef)
    end
    chrome:ClearAllPoints()
    chrome:SetAllPoints()
    -- Above model (0) and interaction layer (~20), below nothing that matters; mouse passes through to drag layer.
    chrome:SetFrameLevel(25)
    local c = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or { r = 0.55, g = 0.5, b = 0.75 }
    if chrome._topLine then
        chrome._topLine:SetColorTexture(c.r, c.g, c.b, 0.55)
    end
    if chrome._barClassLine then
        chrome._barClassLine:SetColorTexture(c.r, c.g, c.b, 0.9)
    end
    if chrome._label then
        chrome._label:SetText((ns.L and ns.L["GEAR_OFFLINE_BADGE"]) or "Offline")
    end
    chrome:Show()
end

--- Draw paperdoll: sol panel (yazı-ikon-slot) | orta (model) | sağ panel (slot-ikon-yazı) | alt panel.
--- baseX: paperdoll bloğunun sol kenarı (kart içinde ana kolonda ortalanmış).
--- paperOriginY: kart TOPLEFT'e göre kağıt bezi bandının üstü (dikey hizalama için).
local function DrawPaperDollInCard(card, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar, baseX, charKey, paperOriginY, paperdollNaturalH, paperBandH)
    baseX = baseX or CARD_PAD
    local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
    -- Sol panel: fixed width; slot sağda (yazı - ikon - slot)
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local leftColRight = baseX + LEFT_PANEL_W
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP

    local slots = gearData and gearData.slots or {}
    local function GetSlotData(slotID) return slots[slotID] end
    local function IsUpgradable(slotID)
        local up = upgradeInfo and upgradeInfo[slotID]
        return up and up.canUpgrade and CanAffordNextUpgrade(up, currencyAmounts)
    end
    local function IsNotUpgradeable(slotID)
        local slot = slots[slotID]
        if slot and slot.notUpgradeable then return true end
        local up = upgradeInfo and upgradeInfo[slotID]
        if up and up.notUpgradeable then return true end
        return false
    end

    local rowStep = SLOT_SIZE + SLOT_GAP
    local vertCenterPad = 0
    if type(paperBandH) == "number" and type(paperdollNaturalH) == "number" and paperBandH > paperdollNaturalH then
        vertCenterPad = math.floor((paperBandH - paperdollNaturalH) / 2 + 0.5)
    end
    local anchorY = paperOriginY
    if anchorY == nil then
        anchorY = -(CARD_PAD + 24)
    end
    local startY = anchorY - vertCenterPad

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i, slotID in ipairs(leftSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), leftX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext)
    end

    -- Right column: 6 armor + 2 trinkets — slot | ikon | yazı
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i, slotID in ipairs(rightSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), rightX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext)
    end

    -- Alt panel: slot üstte, altında ikon + yazı (yazılar aşağı); silahlar birbirine yakın
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local WEAPON_TEXT_W = TRACK_TEXT_W
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (MODEL_W + CENTER_GAP - weaponRowW) / 2
    local maxRows = math.max(#leftSlots, #rightSlots)
    local bottomY = startY - maxRows * rowStep - 8
    for i, slotID in ipairs(weaponSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        local weaponSide = (i == 1) and "bottom_left" or "bottom_right"  -- Main Hand solunda, Off Hand sağında
        CreateSlotButton(card, slotID, GetSlotData(slotID), wx, bottomY, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext)
    end

    -- Orta panel: model frame alt ucu trinket satırının altına denk gelecek şekilde uzatıldı
    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- trinket altına kadar
    local classFile = charData and charData.classFile
    local accent    = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }
    local modelX    = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY

    -- scrollChild is the stable parent — portrait panel is parented here once and NEVER
    -- re-parented (same pattern as the old PlayerModel paperdoll).
    local scrollParent = card:GetParent()

    --- Resolve creature display ID for portrait: saved gear snapshot, or live for logged-in char.
    local function ResolveGearPaperdollDisplayID()
        local snap = gearData and gearData.modelSnapshot
        local id = snap and snap.displayID
        if type(id) == "string" then id = tonumber(id) end
        if id and issecretvalue and issecretvalue(id) then id = nil end
        if id and type(id) == "number" and id > 0 then return math.floor(id) end
        if isCurrentChar == true then
            if UnitCreatureDisplayID then
                local ok, d = pcall(UnitCreatureDisplayID, "player")
                if ok and d and type(d) == "number" and d > 0
                    and not (issecretvalue and issecretvalue(d)) then
                    return math.floor(d)
                end
            end
            if C_PlayerInfo and C_PlayerInfo.GetDisplayID then
                local ok, d = pcall(C_PlayerInfo.GetDisplayID)
                if ok and d and type(d) == "number" and d > 0
                    and not (issecretvalue and issecretvalue(d)) then
                    return math.floor(d)
                end
            end
        end
        return nil
    end

    local function AcquireGearPortraitPanel()
        local pan = ns._gearPortraitPanel
        if not pan then
            pan = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
            local tex = pan:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", pan, "TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", pan, "BOTTOMRIGHT", -2, 2)
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            pan._tex = tex
            pan.isPersistentRowElement = true
            ns._gearPortraitPanel = pan
        end
        if not pan._wnGearTooltipPanelBg then
            pan:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
            pan._wnGearTooltipPanelBg = true
        end
        pan:SetBackdropColor(0.1, 0.1, 0.12, 0.92)
        return pan
    end

    -- Hide until we know which center widget to show; legacy PlayerModel (unused)
    if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
    if ns._gearDressModel then ns._gearDressModel:Hide() end
    if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
    if ns._gearOfflineCenterChrome then ns._gearOfflineCenterChrome:Hide() end
    if ns._gearPlayerModel then
        ns._gearPlayerModel:Hide()
        ns._gearPlayerModel._unitSet = false
        ns._gearPlayerModel._displaySet = false
    end

    -- 2D portrait: fallback (SetPortraitTexture*). Shown when 3D (DressUpModel) cannot be built.
    -- TexCoord crop = extra zoom on the bust.
    local GEAR_PORTRAIT_CROP = { 0.09, 0.91, 0.06, 0.94 }

    -- Primary: DressUpModel — current character SetUnit+Dress; alts: snapshot+TryOn. modelView in SavedVariables.
    local GEAR_REFERENCE_RADIUS = 0.96
    local GEAR_FIXED_CAM_DISTANCE = 2.72
    local GEAR_CAM_FIT_PADDING = 1.06
    local GEAR_FIXED_CAM_SCALE = 2.05
    local GEAR_MODEL_SCALE_MIN = 0.15
    local GEAR_MODEL_SCALE_MAX = 6.0
    local GEAR_ZOOM_MIN = 0.5
    local GEAR_ZOOM_MAX = 2.0
    local GEAR_ROTATE_SENSITIVITY = 0.02

    local centerRef = nil

-- Two distinct widgets so SetUnit/Dress state on the online widget can never
    -- bleed into the offline widget (DressUpModel + SetUnit + later SetDisplayInfo
    -- = white-mannequin: dressing layer keeps a stale slot list whose item textures
    -- aren't in the local cache for alts). PlayerModel has no dressing layer, so
    -- SetDisplayInfo renders the displayID's baked race/sex/customizations directly.
    local function BuildModelClip(widgetType)
        -- Clip frame: holds background + 3D model + interaction layer. SetClipsChildren
        -- prevents the model from drawing over neighbouring cards/scroll edges.
        local clip = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
        if clip.SetClipsChildren then clip:SetClipsChildren(true) end
        clip:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
        clip:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        clip.isPersistentRowElement = true

        -- Class-tinted vertical gradient drawn behind the 3D model. Same look as the
        -- offline character card so online and offline panels share a consistent feel.
        local grad = clip:CreateTexture(nil, "BACKGROUND", nil, 1)
        grad:SetPoint("TOPLEFT", clip, "TOPLEFT", 1, -1)
        grad:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -1, 1)
        grad:SetColorTexture(1, 1, 1, 1)
        clip._gradient = grad
        clip._SetClassTint = function(self, classFile)
            local cc = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
                or { r = 0.55, g = 0.5, b = 0.75 }
            local tR, tG, tB = cc.r * 0.50, cc.g * 0.50, cc.b * 0.50
            if grad.SetGradient and CreateColor then
                pcall(grad.SetGradient, grad, "VERTICAL",
                    CreateColor(tR, tG, tB, 0.90),
                    CreateColor(0.04, 0.04, 0.05, 0.95))
            else
                grad:SetColorTexture(tR, tG, tB, 0.90)
            end
        end

        local m = CreateFrame(widgetType, nil, clip)
        m:SetAllPoints(clip)
        m:SetModelDrawLayer("ARTWORK")
        m:EnableMouse(false)
        m:EnableMouseWheel(false)
        m._clip = clip
        clip._model = m

        m._rotation = 0
        m._zoom = 1.0
        m._scale = 1.0
        m._normalized = false

        local function ApplyTransform()
            pcall(function()
                m:SetPosition(0, 0, 0)
                if m.UseModelCenterToTransform then m:UseModelCenterToTransform(true) end
                if m.SetPitch then m:SetPitch(0) end
                m:SetFacing(m._rotation)
                if m.SetPortraitZoom then m:SetPortraitZoom(0) end
                if m._normalized and m.SetModelScale and m.SetCameraDistance then
                    m:SetModelScale(m._scale)
                    local vw, vh = clip:GetWidth() or 1, clip:GetHeight() or 1
                    local aspectPad = (vh > 1 and (vw / vh) > 1.12) and 1.09 or 1.0
                    local camDist = GEAR_FIXED_CAM_DISTANCE
                        * GEAR_CAM_FIT_PADDING
                        * aspectPad
                        * m._zoom
                        * m._scale
                    m:SetCameraDistance(math.max(0.1, camDist))
                elseif m.SetCamDistanceScale then
                    m:SetCamDistanceScale(GEAR_FIXED_CAM_SCALE * m._zoom)
                end
                if m.SetViewTranslation then m:SetViewTranslation(0, 0) end
            end)
        end
        clip._ApplyTransform = ApplyTransform

        local function NormalizeRadius()
            if not m.GetModelRadius or not m.SetModelScale or not m.SetCameraDistance then return false end
            local ok, r = pcall(m.GetModelRadius, m)
            if not ok or not r or r <= 0 then return false end
            local s = (GEAR_REFERENCE_RADIUS / r) * 0.94 * 1.05
            if s < GEAR_MODEL_SCALE_MIN then s = GEAR_MODEL_SCALE_MIN
            elseif s > GEAR_MODEL_SCALE_MAX then s = GEAR_MODEL_SCALE_MAX end
            m._normalized = true
            m._scale = s
            ApplyTransform()
            return true
        end
        clip._Normalize = NormalizeRadius

        m:SetScript("OnModelLoaded", function()
            if m.SetAnimation then
                pcall(m.SetAnimation, m, 0)
            end
            if m.ClearFog then
                pcall(m.ClearFog, m)
            end
            NormalizeRadius()
            ApplyTransform()
        end)

        -- Interaction layer: rotation drag (left/right button) + wheel zoom.
        local il = CreateFrame("Frame", nil, clip)
        il:SetAllPoints()
        il:SetFrameLevel(m:GetFrameLevel() + 20)
        il:EnableMouse(true)
        il:EnableMouseWheel(true)
        clip._il = il

        local function SchedulePersistView()
            if not clip._viewCharKey or not (WarbandNexus and WarbandNexus.SaveGearModelViewState) then return end
            if ns._gearViewSaveTimer then
                ns._gearViewSaveTimer:Cancel()
                ns._gearViewSaveTimer = nil
            end
            ns._gearViewSaveTimer = C_Timer.NewTimer(0.35, function()
                ns._gearViewSaveTimer = nil
                if not clip or not clip._viewCharKey or not clip._model then return end
                WarbandNexus:SaveGearModelViewState(clip._viewCharKey, clip._model._rotation, clip._model._zoom)
            end)
        end

        local function ScaleX()
            local s = il:GetEffectiveScale() or 1
            return (s > 0) and s or 1
        end

        local function dragOnUpdate()
            if m._dragX == nil or not m._dragBtn then il:SetScript("OnUpdate", nil); return end
            if not IsMouseButtonDown(m._dragBtn) then
                m._dragX, m._dragBtn = nil, nil
                il:SetScript("OnUpdate", nil)
                return
            end
            local x = GetCursorPosition() / ScaleX()
            local dx = x - m._dragX
            m._dragX = x
            m._rotation = (m._dragRot or 0) - dx * GEAR_ROTATE_SENSITIVITY
            m._dragRot = m._rotation
            m:SetFacing(m._rotation)
        end
        il:SetScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" and btn ~= "RightButton" then return end
            m._dragX = GetCursorPosition() / ScaleX()
            m._dragRot = m._rotation
            m._dragBtn = btn
            il:SetScript("OnUpdate", dragOnUpdate)
        end)
        il:SetScript("OnMouseUp", function(_, btn)
            if btn == m._dragBtn then m._dragX, m._dragBtn = nil, nil end
            il:SetScript("OnUpdate", nil)
            SchedulePersistView()
        end)
        il:SetScript("OnHide", function()
            m._dragX, m._dragBtn = nil, nil
            il:SetScript("OnUpdate", nil)
        end)
        il:SetScript("OnMouseWheel", function(_, delta)
            local z = m._zoom * ((delta > 0) and 0.9 or 1.1)
            if z < GEAR_ZOOM_MIN then z = GEAR_ZOOM_MIN
            elseif z > GEAR_ZOOM_MAX then z = GEAR_ZOOM_MAX end
            m._zoom = z
            ApplyTransform()
            SchedulePersistView()
        end)

        return clip
    end

    local function AcquireGearDressModel()
        if not ns._gearDressModel then
            ns._gearDressModel = BuildModelClip("DressUpModel")
        end
        return ns._gearDressModel
    end

    -- Offline-alt rendering: a SECOND DressUpModel widget that NEVER calls SetUnit.
    -- The widget is reset with SetCustomRace (race base mesh — ships with client, always
    -- rendered with textures) and then SetItemTransmogInfoList replays the saved per-slot
    -- transmog list (Wowpedia: UIOBJECT_DressUpModel). White-mannequin only happens when
    -- a player displayID's appearance bundle isn't cached — this path avoids displayIDs
    -- entirely. Customisations (skin/face/hair) fall back to race defaults; no public API
    -- exposes them outside the barber shop.
    local function AcquireGearOfflineModel()
        if not ns._gearOfflineModel then
            ns._gearOfflineModel = BuildModelClip("DressUpModel")
        end
        return ns._gearOfflineModel
    end

    local function ApplyOfflineModelSnapshot(m, snap)
        if not snap or not m then return false end
        local raceID = snap.raceID
        local sex = snap.dressGender
        if sex ~= 0 and sex ~= 1 then sex = (snap.sex == 3) and 1 or 0 end
        if not raceID then return false end

        -- One pcall: if ItemTransmogInfo build fails, still get base race body on screen.
        local ok = pcall(function()
            if m.ClearModel then m:ClearModel() end
            if m.SetCustomRace then m:SetCustomRace(raceID, sex) end
            if m.SetUseTransmogSkin then m:SetUseTransmogSkin(false) end
            if snap.transmogList and m.SetItemTransmogInfoList and ItemUtil and ItemUtil.CreateItemTransmogInfo then
                local list = {}
                for i = 1, #snap.transmogList do
                    local e = snap.transmogList[i]
                    if type(e) == "table" then
                        list[#list + 1] = ItemUtil.CreateItemTransmogInfo(e.app or 0, e.sec or 0, e.ill or 0)
                    end
                end
                if #list > 0 then
                    pcall(m.SetItemTransmogInfoList, m, list)
                end
            end
            if m.SetSheathed then m:SetSheathed(true) end
            if m.SetAnimation then
                pcall(m.SetAnimation, m, 0)
            end
        end)
        return ok
    end

    if not centerRef and isCurrentChar == true then
        local clip = AcquireGearDressModel()
        if not clip._wnGearTooltipPanelBg then
            clip:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
            clip._wnGearTooltipPanelBg = true
        end
        clip:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        if clip._SetClassTint then clip:_SetClassTint(classFile) end
        clip._viewCharKey = charKey
        local m = clip._model
        if clip:GetParent() ~= scrollParent then clip:SetParent(scrollParent) end
        clip:ClearAllPoints()
        clip:SetSize(MODEL_W, MODEL_H)
        clip:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        clip:SetFrameLevel(card:GetFrameLevel() + 5)

        -- Reset framing state on character swap so radius normalize re-runs cleanly.
        m._normalized = false
        m._scale = 1.0
        m._zoom = 0.58
        m._rotation = 0
        do
            local mv = gearData and gearData.modelView
            if type(mv) == "table" then
                if mv.rotation ~= nil then
                    m._rotation = tonumber(mv.rotation) or 0
                end
                if mv.zoom ~= nil then
                    m._zoom = tonumber(mv.zoom) or m._zoom
                end
            end
        end
        if m._zoom < GEAR_ZOOM_MIN then m._zoom = GEAR_ZOOM_MIN
        elseif m._zoom > GEAR_ZOOM_MAX then m._zoom = GEAR_ZOOM_MAX end
        m._dragRot = m._rotation

        local ok = pcall(function()
            m:SetUnit("player")
            if m.Dress then m:Dress() end
            if m.RefreshUnit then m:RefreshUnit() end
        end)

        if ok then
            if m.ClearFog then
                pcall(m.ClearFog, m)
            end
            if m.SetAnimation then
                pcall(m.SetAnimation, m, 0)
            end
            if clip._Normalize then clip._Normalize() end
            if clip._ApplyTransform then clip._ApplyTransform() end
            if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
            clip:Show()
            m:Show()
            centerRef = clip
        else
            clip:Hide()
        end
    end

    -- Offline alts: skip every 3D / 2D rendering attempt and go directly to the
    -- modern character card below. The DressUpModel snapshot path
    -- (SetCustomRace + SetItemTransmogInfoList) and the SetPortraitTextureFromCreatureDisplayID
    -- 2D fallback are both unreliable for alts — Blizzard's player displayIDs are
    -- session-bound runtime handles, so replaying them in a different session
    -- produces a white mannequin or broken portrait. The class-themed card is
    -- consistent, readable, and never breaks.
    if not centerRef and isCurrentChar ~= true then
        if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
        if ns._gearDressModel then ns._gearDressModel:Hide() end
        local pan = ns._gearPortraitPanel
        if pan then pan:Hide() end
    end

    -- Online (current character) 2D portrait fallback: only when the live DressUpModel
    -- failed AND we're on the player. SetPortraitTexture("player") is reliable; we never
    -- run SetPortraitTextureFromCreatureDisplayID for offline alts here.
    if not centerRef and isCurrentChar == true then
        local pan = AcquireGearPortraitPanel()
        if pan:GetParent() ~= scrollParent then pan:SetParent(scrollParent) end
        pan:ClearAllPoints()
        pan:SetSize(MODEL_W, MODEL_H)
        pan:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        pan:SetFrameLevel(card:GetFrameLevel() + 5)
        local tex = pan._tex
        local ok2d = false
        if tex and SetPortraitTexture then
            if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
            ok2d = pcall(function() SetPortraitTexture(tex, "player") end)
        end
        if ok2d then
            if tex and tex.SetTexCoord then
                local c = GEAR_PORTRAIT_CROP
                tex:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            pan:Show()
            if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
            if ns._gearDressModel then ns._gearDressModel:Hide() end
            if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
            centerRef = pan
        end
    end

    -- Fallback: modern offline character card.
    -- Layout: class-colored vertical gradient → large class icon → character name
    -- (class-colored) → "Lv N · Race" line → item-level pill → soft hint at bottom.
    -- All elements pulled from charData; gracefully degrades when fields are missing.
    if not centerRef then
        local portrait = ns._gearNoPreviewFrame
        if not portrait then
            portrait = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
            portrait.isPersistentRowElement = true
            ns._gearNoPreviewFrame = portrait

            -- Class-tinted vertical gradient (top → bottom: dim → black).
            local grad = portrait:CreateTexture(nil, "BACKGROUND", nil, 1)
            grad:SetPoint("TOPLEFT", portrait, "TOPLEFT", 1, -1)
            grad:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 1)
            grad:SetColorTexture(1, 1, 1, 1)
            portrait._gradient = grad

            -- Large class icon — modern transparent atlas (classicon-<class>) instead of
            -- the legacy WORLDSTATEFRAME sheet which left a coloured square outline.
            local icon = portrait:CreateTexture(nil, "ARTWORK")
            icon:SetSize(80, 80)
            icon:SetPoint("CENTER", portrait, "CENTER", 0, 22)
            portrait._classIcon = icon

            -- Soft circular halo behind icon (atlas if available, else dim disc).
            local ring = portrait:CreateTexture(nil, "ARTWORK", nil, -1)
            ring:SetSize(108, 108)
            ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
            if ring.SetAtlas then
                local ok = pcall(ring.SetAtlas, ring, "communities-create-avatar-bg-glow", true)
                if not ok then ring:SetColorTexture(0, 0, 0, 0.0) end
            end
            ring:SetVertexColor(1, 1, 1, 0.35)
            portrait._iconRing = ring

            -- Character name (class-colored).
            local name = FontManager:CreateFontString(portrait, GFR("gearPortraitLine"), "OVERLAY")
            name:SetPoint("TOP", icon, "BOTTOM", 0, -10)
            name:SetWidth(MODEL_W - 16)
            name:SetJustifyH("CENTER")
            name:SetShadowOffset(1, -1)
            name:SetShadowColor(0, 0, 0, 0.95)
            portrait._name = name

            -- "Lv N · Race" meta line.
            local meta = FontManager:CreateFontString(portrait, GFR("gearPortraitMeta"), "OVERLAY")
            meta:SetPoint("TOP", name, "BOTTOM", 0, -2)
            meta:SetWidth(MODEL_W - 16)
            meta:SetJustifyH("CENTER")
            meta:SetTextColor(0.78, 0.8, 0.88, 1)
            meta:SetShadowOffset(1, -1)
            meta:SetShadowColor(0, 0, 0, 0.85)
            portrait._meta = meta

            -- Item level pill: small framed bg with bold ilvl text.
            local pill = CreateFrame("Frame", nil, portrait, "BackdropTemplate")
            pill:SetSize(78, 22)
            pill:SetPoint("TOP", meta, "BOTTOM", 0, -10)
            pill:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            pill:SetBackdropColor(0, 0, 0, 0.55)
            portrait._pill = pill
            local pillLabel = FontManager:CreateFontString(pill, GFR("gearPortraitMeta"), "OVERLAY")
            pillLabel:SetPoint("CENTER", pill, "CENTER", 0, 0)
            pillLabel:SetTextColor(1, 0.82, 0.0, 1)
            pillLabel:SetShadowOffset(1, -1)
            pillLabel:SetShadowColor(0, 0, 0, 0.9)
            portrait._pillLabel = pillLabel
        end

        if portrait:GetParent() ~= scrollParent then
            portrait:SetParent(scrollParent)
        end
        portrait:ClearAllPoints()
        portrait:SetSize(MODEL_W, MODEL_H)
        portrait:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        portrait:SetFrameLevel(card:GetFrameLevel() + 5)
        portrait:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
        portrait:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        portrait:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)

        local cc = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
            or { r = 0.55, g = 0.5, b = 0.75 }
        if portrait._gradient and portrait._gradient.SetGradient then
            -- Top: dim class tint; bottom: near-black.
            local topR, topG, topB = cc.r * 0.32, cc.g * 0.32, cc.b * 0.32
            local createColor = (CreateColor or ColorMixin) and CreateColor or nil
            if createColor then
                pcall(portrait._gradient.SetGradient, portrait._gradient, "VERTICAL",
                    CreateColor(topR, topG, topB, 0.85),
                    CreateColor(0.04, 0.04, 0.05, 0.95))
            else
                portrait._gradient:SetColorTexture(topR, topG, topB, 0.85)
            end
        end

        if portrait._classIcon then
            local applied = false
            if classFile and portrait._classIcon.SetAtlas then
                local atlas = "classicon-" .. string.lower(classFile)
                applied = pcall(portrait._classIcon.SetAtlas, portrait._classIcon, atlas)
            end
            if applied then
                -- Reset TexCoord so a previous WORLDSTATEFRAME crop doesn't clip the atlas.
                portrait._classIcon:SetTexCoord(0, 1, 0, 1)
            else
                -- Legacy fallback: WORLDSTATEFRAME sheet with TCoords.
                -- Inset the TexCoords by ~6 % on each edge to crop the coloured square
                -- border that surrounds each class icon cell in the sprite sheet.
                portrait._classIcon:SetTexture("Interface\\WORLDSTATEFRAME\\Icons-Classes")
                local coords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
                if coords then
                    local INSET = 0.02
                    portrait._classIcon:SetTexCoord(
                        coords[1] + INSET, coords[2] - INSET,
                        coords[3] + INSET, coords[4] - INSET)
                end
            end
            portrait._classIcon:SetVertexColor(1, 1, 1, 1)
            portrait._classIcon:Show()
        end

        if portrait._iconRing then
            portrait._iconRing:SetVertexColor(cc.r, cc.g, cc.b, 0.45)
        end

        local pnDisplayName = (charData and charData.name) or ""
        local pnFallback = ((ns.L and ns.L["GEAR_NO_PREVIEW"]) or "No Preview")
        if portrait._name then
            if pnDisplayName ~= "" then
                portrait._name:Hide()
            else
                portrait._name:SetText(pnFallback)
                portrait._name:SetTextColor(cc.r, cc.g, cc.b, 1)
                portrait._name:Show()
            end
        end

        if portrait._meta then
            local lvl = charData and tonumber(charData.level) or nil
            local race = (charData and (charData.raceName or charData.race)) or nil
            local parts = {}
            if lvl and lvl > 0 then parts[#parts + 1] = "Lv " .. lvl end
            if race and race ~= "" then parts[#parts + 1] = race end
            portrait._meta:SetText(#parts > 0 and table.concat(parts, "  ·  ") or ((ns.L and ns.L["GEAR_NO_PREVIEW_HINT"]) or "Log in on this character to refresh the appearance preview."))
        end

        -- iLvl pill removed — the equipped ilvl is already visible in the header.
        if portrait._pill then portrait._pill:Hide() end

        portrait:Show()
        centerRef = portrait
    end

    do
        local isNoPreview = (centerRef == ns._gearNoPreviewFrame)
        if isCurrentChar == true or isNoPreview or not centerRef then
            if ns._gearOfflineCenterChrome then
                ns._gearOfflineCenterChrome:Hide()
            end
        else
            ApplyGearOfflineCenterChrome(centerRef, classFile)
        end
    end

    -- Border around model/portrait (singleton — reused across refreshes)
    local modelBorder = ns._gearModelBorder
    if not modelBorder then
        modelBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
        modelBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        modelBorder.isPersistentRowElement = true
        ns._gearModelBorder = modelBorder
    end
    modelBorder:SetParent(card)
    modelBorder:ClearAllPoints()
    modelBorder:SetPoint("TOPLEFT",     centerRef, "TOPLEFT",      -1,  1)
    modelBorder:SetPoint("BOTTOMRIGHT", centerRef, "BOTTOMRIGHT",   1, -1)
    modelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)
    modelBorder:SetFrameLevel(centerRef:GetFrameLevel() + 6)
    modelBorder:Show()

    -- Character name + average item level: stacked inside model/portrait panel (top).
    local avgIlvl = charData and charData.itemLevel or 0
    local ilvlFrame = ns._gearIlvlFrame
    if not ilvlFrame then
        ilvlFrame = CreateFrame("Frame", nil, card)
        ilvlFrame:SetSize(120, 22)
        local ilvlOverlay = FontManager:CreateFontString(ilvlFrame, GFR("gearIlvlBadge"), "OVERLAY")
        ilvlOverlay:SetPoint("CENTER", 0, 0)
        ilvlOverlay:SetJustifyH("CENTER")
        ilvlOverlay:SetShadowOffset(1, -1)
        ilvlOverlay:SetShadowColor(0, 0, 0, 1)
        ilvlFrame._label = ilvlOverlay
        ilvlFrame.isPersistentRowElement = true
        ns._gearIlvlFrame = ilvlFrame
    end

    local displayName = (charData and charData.name) or ""
    local nameWrapper = ns._gearNameWrapper
    if not nameWrapper then
        nameWrapper = CreateFrame("Frame", nil, card)
        local nameLabel = FontManager:CreateFontString(nameWrapper, GFR("gearCharacterName"), "OVERLAY")
        nameLabel:SetJustifyH("CENTER")
        nameLabel:SetShadowOffset(1, -1)
        nameLabel:SetShadowColor(0, 0, 0, 1)
        nameWrapper._label = nameLabel
        nameWrapper.isPersistentRowElement = true
        ns._gearNameWrapper = nameWrapper
    end

    local textBase = 40
    if centerRef._il and centerRef._il.GetFrameLevel then
        textBase = centerRef._il:GetFrameLevel() + 2
    elseif centerRef._model and centerRef._model.GetFrameLevel then
        textBase = centerRef._model:GetFrameLevel() + 22
    end

    if displayName ~= "" then
        nameWrapper:SetParent(centerRef)
        nameWrapper:ClearAllPoints()
        nameWrapper:SetPoint("TOPLEFT", centerRef, "TOPLEFT", 6, -8)
        nameWrapper:SetPoint("TOPRIGHT", centerRef, "TOPRIGHT", -6, -8)
        nameWrapper:SetHeight(20)
        if nameWrapper.SetFrameLevel then
            nameWrapper:SetFrameLevel(textBase)
        end
        local nameLabel = nameWrapper._label
        nameLabel:ClearAllPoints()
        nameLabel:SetPoint("TOPLEFT", nameWrapper, "TOPLEFT", 0, 0)
        nameLabel:SetPoint("TOPRIGHT", nameWrapper, "TOPRIGHT", 0, 0)
        local classHex = GetClassHex(classFile)
        nameLabel:SetText("|cff" .. classHex .. displayName .. "|r")
        nameWrapper:Show()

        if avgIlvl > 0 then
            ilvlFrame:SetParent(centerRef)
            ilvlFrame:ClearAllPoints()
            ilvlFrame:SetPoint("TOP", nameWrapper, "BOTTOM", 0, 0)
            if ilvlFrame.SetFrameLevel then
                ilvlFrame:SetFrameLevel(textBase + 1)
            end
            ilvlFrame._label:SetTextColor(1, 0.9, 0)
            ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
            ilvlFrame:Show()
        else
            ilvlFrame:Hide()
        end
    else
        nameWrapper:Hide()
        if avgIlvl > 0 then
            ilvlFrame:SetParent(centerRef)
            ilvlFrame:ClearAllPoints()
            ilvlFrame:SetPoint("TOP", centerRef, "TOP", 0, -8)
            if ilvlFrame.SetFrameLevel then
                ilvlFrame:SetFrameLevel(textBase + 1)
            end
            ilvlFrame._label:SetTextColor(1, 0.9, 0)
            ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
            ilvlFrame:Show()
        else
            ilvlFrame:Hide()
        end
    end
end

-- ── Stat helpers (live API for current char) ────────────────────────────────
local STAT_IDS = {
    { id = 1, label = (ns.L and ns.L["STAT_STRENGTH"]) or SPELL_STAT1_NAME or "Strength",    icon = "Interface\\Icons\\spell_nature_strength" },
    { id = 2, label = (ns.L and ns.L["STAT_AGILITY"]) or SPELL_STAT2_NAME or "Agility",      icon = "Interface\\Icons\\ability_backstab" },
    { id = 3, label = (ns.L and ns.L["STAT_STAMINA"]) or SPELL_STAT3_NAME or "Stamina",      icon = "Interface\\Icons\\spell_holy_wordfortitude" },
    { id = 4, label = (ns.L and ns.L["STAT_INTELLECT"]) or SPELL_STAT4_NAME or "Intellect",  icon = "Interface\\Icons\\spell_holy_magicalsentry" },
}
local SECONDARY_STATS = {
    { label = (ns.L and ns.L["STAT_CRITICAL_STRIKE"]) or "Critical Strike", fn = function() return GetCombatRating and GetCombatRating(9) or 0 end,  pctFn = function() return GetCritChance and GetCritChance() or 0 end },
    { label = (ns.L and ns.L["STAT_HASTE"]) or "Haste",                     fn = function() return GetCombatRating and GetCombatRating(18) or 0 end, pctFn = function() return GetHaste and GetHaste() or 0 end },
    { label = (ns.L and ns.L["STAT_MASTERY"]) or "Mastery",                 fn = function() return GetCombatRating and GetCombatRating(26) or 0 end, pctFn = function() return GetMasteryEffect and select(1, GetMasteryEffect()) or 0 end },
    { label = (ns.L and ns.L["STAT_VERSATILITY"]) or "Versatility",         fn = function() return GetCombatRating and GetCombatRating(29) or 0 end, pctFn = function() return GetCombatRatingBonus and GetCombatRatingBonus(29) or 0 end },
}

-- Offline snapshot: sıra veya etiket ile eşleştir (eski SV uyumu)
local function MergeOfflineSecondaryForGear(savedSec)
    local out = {}
    for i = 1, #SECONDARY_STATS do
        local def = SECONDARY_STATS[i]
        local rating, pct = 0, 0
        local s = savedSec and savedSec[i]
        if s and type(s.rating) == "number" then
            rating = math.floor(s.rating)
            pct = (type(s.pct) == "number") and s.pct or 0
        elseif savedSec then
            for j = 1, #savedSec do
                local ent = savedSec[j]
                if ent and ent.label == def.label then
                    rating = tonumber(ent.rating) or 0
                    pct = (type(ent.pct) == "number") and ent.pct or 0
                    break
                end
            end
        end
        out[#out + 1] = { label = def.label, rating = rating, pct = pct }
    end
    return out
end

--- Equipped gear card: paperdoll (left) | stacked stats + currencies (middle) | upgrade recommendations (right).
--- charKey: key from dropdown (used for currency/gold lookup).
--- isCurrentChar: true if selected character is the logged-in one (live portrait fallback).
--- currencies: array from GetGearUpgradeCurrenciesFromDB (passed to avoid duplicate API calls).
local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar, currencies, storageFindings)
    local rowStep = SLOT_SIZE + SLOT_GAP
    -- Content height: section + slot columns + gap + weapon row (Main/Off Hand) + bottom pad so card border is below weapons
    local contentTop = CARD_PAD + 24
    local weaponBottom = 8 * rowStep + 8 + SLOT_SIZE
    local paperdollH = contentTop + weaponBottom + CARD_PAD
    currencies = currencies or {}
    -- Middle column subpanels: stats + currencies — padding + stat column gaps (uses midColW).
    local GEAR_SUBPANEL_PAD = 10
    local GEAR_SUBPANEL_HDR = 36   -- Bumped from 26: visible breathing room between title and first row.
    local GEAR_STAT_COL_GAP = 8
    local cardH = CARD_PAD + 24 + paperdollH + CARD_PAD

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, yOffset)

    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }

    -- ── Crest / gold block heights (drawn under character stats in main column) ──
    local crestCurrencies = {}
    local goldCurrency = nil
    for _, cur in ipairs(currencies) do
        if cur.isGold then goldCurrency = cur else crestCurrencies[#crestCurrencies + 1] = cur end
    end

    -- Currency panel height: header + crest rows + divider + gold + footer hint + bottom pad
    local CREST_ROW_H = 36
    local FOOTER_HINT_H = 14
    local currenciesH = GEAR_SUBPANEL_HDR + #crestCurrencies * CREST_ROW_H + 12 + 28 + FOOTER_HINT_H + 8

    local parentW = (card and card.GetWidth) and card:GetWidth() or ((parent and parent.GetWidth) and parent:GetWidth() or 0)
    local CARD_PAD_X = 12
    local cardInnerW = 0
    if parentW and parentW > (SIDE_MARGIN * 2) then
        cardInnerW = parentW - (SIDE_MARGIN * 2) - (CARD_PAD_X * 2)
    end
    if cardInnerW <= 0 and card and card.GetWidth then
        cardInnerW = card:GetWidth() - CARD_PAD_X * 2
    end
    cardInnerW = math.max(cardInnerW or 0, MIN_CARD_INNER_W)
    local PANEL_GAP = GEAR_PANEL_GAP
    local paperColW = GEAR_PAPER_COL_W
    -- Mid column targets prefer width (so stat/currency labels never truncate); storage takes all leftover (right edge).
    local afterPaper = cardInnerW - paperColW - PANEL_GAP * 2
    local midColW = GEAR_MID_COL_PREF_W
    if midColW > afterPaper - GEAR_REC_COL_MIN_W then
        midColW = math.max(GEAR_MID_COL_MIN_W, afterPaper - GEAR_REC_COL_MIN_W)
    end
    local storageW = math.max(GEAR_REC_COL_MIN_W, afterPaper - midColW)
    local paperLeft = CARD_PAD
    local midLeft = CARD_PAD + paperColW + PANEL_GAP

    local panelTopY = -CARD_PAD - 22
    local SECTION_GAP = 12

    local paperdollBaseX = paperLeft + math.max(0, math.floor((paperColW - PAPERDOLL_BLOCK_W) / 2))

    local STAT_ROW_H = 28
    local primaryRows = {}
    local secondaryRows = {}
    if isCurrentChar and UnitStat then
        local mainStat = (WarbandNexus.GetCurrentCharacterMainStat and WarbandNexus:GetCurrentCharacterMainStat()) or nil
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        for i = 1, #STAT_IDS do
            local stat = STAT_IDS[i]
            if stat.id == 3 then
                -- Stamina always
            elseif mainStatId and stat.id ~= mainStatId then
                stat = nil
            end
            if stat then
                local ok, _, total = pcall(UnitStat, "player", stat.id)
                if ok and type(total) == "number" then
                    primaryRows[#primaryRows + 1] = {
                        label = stat.label,
                        value = FormatNumber and FormatNumber(math.floor(total)) or tostring(math.floor(total)),
                    }
                end
            end
        end
        for i = 1, #SECONDARY_STATS do
            local stat = SECONDARY_STATS[i]
            local okR, rating = pcall(stat.fn)
            local okP, pct = pcall(stat.pctFn)
            local rNum = (okR and type(rating) == "number") and rating or 0
            local pNum = (okP and type(pct) == "number") and pct or 0
            secondaryRows[#secondaryRows + 1] = {
                label = stat.label,
                pctStr = format("%.1f%%", pNum),
                ratingStr = FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum)),
            }
        end
    elseif not isCurrentChar and charData and charData.stats then
        local mainStat = nil
        local mc = charData.stats.mainStatCode
        if mc == "STR" or mc == "AGI" or mc == "INT" then
            mainStat = mc
        end
        if not mainStat and WarbandNexus.GetCharacterMainStat then
            mainStat = WarbandNexus:GetCharacterMainStat(charData)
        end
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        local prim = charData.stats.primary
        if prim and next(prim) then
            for idx = 1, #STAT_IDS do
                local stat = STAT_IDS[idx]
                if stat.id == 3 then
                    -- Stamina always
                elseif mainStatId and stat.id ~= mainStatId then
                    stat = nil
                end
                if stat then
                    local raw = prim[stat.id]
                    if raw == nil then raw = 0 end
                    if type(raw) == "number" then
                        primaryRows[#primaryRows + 1] = {
                            label = stat.label,
                            value = FormatNumber and FormatNumber(math.floor(raw)) or tostring(math.floor(raw)),
                        }
                    end
                end
            end
        end
        local mergedSec = MergeOfflineSecondaryForGear(charData.stats.secondary)
        for j = 1, #mergedSec do
            local s = mergedSec[j]
            if s then
                local pNum = (type(s.pct) == "number") and s.pct or 0
                local rNum = (type(s.rating) == "number") and s.rating or 0
                secondaryRows[#secondaryRows + 1] = {
                    label = s.label,
                    pctStr = format("%.1f%%", pNum),
                    ratingStr = FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum)),
                }
            end
        end
    end
    local hasDivider = (#primaryRows > 0 and #secondaryRows > 0)
    local statContentRows = #primaryRows + #secondaryRows
    local statContentH = GEAR_SUBPANEL_HDR + (statContentRows * STAT_ROW_H) + (hasDivider and 10 or 0) + 14
    if statContentRows == 0 then
        statContentH = GEAR_SUBPANEL_HDR + 70
    end
    local statPanelH = statContentH
    local middleStackNatural = statPanelH + SECTION_GAP + currenciesH
    local naturalMainH = math.max(paperdollH, middleStackNatural)
    -- Card sized to content; do NOT expand to viewport (was leaving a huge dead band below sparse content).
    local panelH = naturalMainH
    local currencyBlockH = math.max(currenciesH, panelH - statPanelH - SECTION_GAP)

    local yPaperBandTop = panelTopY

    local paperChrome = CreateFrame("Frame", nil, card, "BackdropTemplate")
    paperChrome:SetPoint("TOPLEFT", card, "TOPLEFT", paperLeft, yPaperBandTop)
    paperChrome:SetSize(paperColW, paperdollH)
    paperChrome:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    paperChrome:SetBackdropColor(0.05, 0.05, 0.07, 0.38)
    paperChrome:SetBackdropBorderColor(accent[1] * 0.22, accent[2] * 0.22, accent[3] * 0.32, 0.30)
    paperChrome:EnableMouse(false)
    if paperChrome.SetFrameLevel and card.GetFrameLevel then
        paperChrome:SetFrameLevel((card:GetFrameLevel() or 2) + 1)
    end

    -- Plain layout frames (no nested border): avoids “box inside box” next to the gear card chrome.
    local statPanel = CreateFrame("Frame", nil, card)
    statPanel:SetSize(midColW, statPanelH)
    statPanel:SetPoint("TOPLEFT", card, "TOPLEFT", midLeft, panelTopY)
    statPanel:EnableMouse(false)
    if statPanel.SetFrameLevel then
        statPanel:SetFrameLevel((paperChrome:GetFrameLevel() or 3) + 2)
    end

    local currencyPanel = CreateFrame("Frame", nil, card)
    currencyPanel:SetSize(midColW, currencyBlockH)
    currencyPanel:SetPoint("TOPLEFT", statPanel, "BOTTOMLEFT", 0, -SECTION_GAP)
    currencyPanel:EnableMouse(false)
    if currencyPanel.SetClipsChildren then
        currencyPanel:SetClipsChildren(true)
    end
    if currencyPanel.SetFrameLevel then
        currencyPanel:SetFrameLevel(statPanel:GetFrameLevel() or 5)
    end

    local statPad = GEAR_SUBPANEL_PAD
    local statInnerW = math.max(1, midColW - statPad * 2)
    local valColW = 56
    local pctColW = 52
    local labelColW = statInnerW - pctColW - valColW - GEAR_STAT_COL_GAP * 2
    while labelColW < 34 do
        if pctColW > 40 then
            pctColW = pctColW - 2
        elseif valColW > 46 then
            valColW = valColW - 2
        else
            break
        end
        labelColW = statInnerW - pctColW - valColW - GEAR_STAT_COL_GAP * 2
    end
    local currPad = GEAR_SUBPANEL_PAD
    -- 3-value crest format ("362 \194\183 540 / 1000") needs more room than 2-value: bump reserve.
    local currAmtReserve = math.min(176, math.max(110, math.floor((midColW - currPad * 2) * 0.55)))

    -- Middle column: Character Stats, then Upgrade Currencies (reference: classic gear + side info strip).
    local statTitle = FontManager:CreateFontString(statPanel, GFR("gearSectionTitle"), "OVERLAY")
    statTitle:SetPoint("TOPLEFT", statPanel, "TOPLEFT", statPad, -8)
    statTitle:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, -8)
    statTitle:SetJustifyH("CENTER")
    statTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. ((ns.L and ns.L["GEAR_CHARACTER_STATS"]) or "Character Stats") .. "|r")
    statTitle:SetShadowOffset(1, -1)
    statTitle:SetShadowColor(0, 0, 0, 1)

    local statY = -GEAR_SUBPANEL_HDR

    if #primaryRows > 0 or #secondaryRows > 0 then
        for i = 1, #primaryRows do
            local stat = primaryRows[i]
            local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
            row:SetPoint("TOPLEFT", statPad, statY)
            row:SetWidth(labelColW)
            row:SetWordWrap(false)
            row:SetJustifyH("LEFT")
            row:SetTextColor(1, 1, 1)
            row:SetText(stat.label)
            row:SetShadowOffset(1, -1)
            row:SetShadowColor(0, 0, 0, 0.8)

            local mid = FontManager:CreateFontString(statPanel, GFR("gearPrimaryMid"), "OVERLAY")
            mid:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad - valColW - GEAR_STAT_COL_GAP, statY)
            mid:SetWidth(pctColW)
            mid:SetJustifyH("RIGHT")
            mid:SetText("")
            mid:SetTextColor(1, 1, 1)
            mid:SetShadowOffset(1, -1)
            mid:SetShadowColor(0, 0, 0, 0.8)

            local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
            val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
            val:SetWidth(valColW)
            val:SetJustifyH("RIGHT")
            val:SetTextColor(1, 1, 1)
            val:SetText(stat.value)
            val:SetShadowOffset(1, -1)
            val:SetShadowColor(0, 0, 0, 0.8)

            statY = statY - STAT_ROW_H
        end

        if hasDivider then
            local statDiv = statPanel:CreateTexture(nil, "ARTWORK")
            statDiv:SetPoint("TOPLEFT", statPad, statY - 2)
            statDiv:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY - 2)
            statDiv:SetHeight(1)
            statDiv:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)
            statY = statY - 10
        end

        for i = 1, #secondaryRows do
            local stat = secondaryRows[i]
            local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
            row:SetPoint("TOPLEFT", statPad, statY)
            row:SetWidth(labelColW)
            row:SetWordWrap(false)
            row:SetJustifyH("LEFT")
            row:SetTextColor(1, 1, 1)
            row:SetText(stat.label)
            row:SetShadowOffset(1, -1)
            row:SetShadowColor(0, 0, 0, 0.8)

            local pctFs = FontManager:CreateFontString(statPanel, GFR("gearStatPct"), "OVERLAY")
            pctFs:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad - valColW - GEAR_STAT_COL_GAP, statY)
            pctFs:SetWidth(pctColW)
            pctFs:SetJustifyH("RIGHT")
            pctFs:SetTextColor(1, 1, 1)
            pctFs:SetText(stat.pctStr or "0.0%")
            pctFs:SetShadowOffset(1, -1)
            pctFs:SetShadowColor(0, 0, 0, 0.8)

            local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
            val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
            val:SetWidth(valColW)
            val:SetJustifyH("RIGHT")
            val:SetTextColor(1, 1, 1)
            val:SetText(stat.ratingStr or "0")
            val:SetShadowOffset(1, -1)
            val:SetShadowColor(0, 0, 0, 0.8)

            statY = statY - STAT_ROW_H
        end
    else
        local noStats = FontManager:CreateFontString(statPanel, GFR("gearEmptyStatsHint"), "OVERLAY")
        noStats:SetPoint("TOPLEFT", statPad, statY)
        noStats:SetWidth(statInnerW)
        noStats:SetJustifyH("CENTER")
        noStats:SetTextColor(0.45, 0.45, 0.45)
        noStats:SetText((ns.L and ns.L["GEAR_STATS_CURRENT_ONLY"]) or "Stats available for\ncurrent character only")
        noStats:SetShadowOffset(1, -1)
        noStats:SetShadowColor(0, 0, 0, 0.8)
    end

    -- Panel header (ortalanmış)
    local panelTitle = FontManager:CreateFontString(currencyPanel, GFR("gearPanelTitle"), "OVERLAY")
    panelTitle:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, -8)
    panelTitle:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, -8)
    panelTitle:SetJustifyH("CENTER")
    panelTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. ((ns.L and ns.L["GEAR_UPGRADE_CURRENCIES"]) or "Upgrade Currencies") .. "|r")
    panelTitle:SetShadowOffset(1, -1)
    panelTitle:SetShadowColor(0, 0, 0, 1)

    -- Crest rows: icon | name (clipped) | fixed-width amount column (symmetric insets with stats panel).
    local curY = -GEAR_SUBPANEL_HDR
    local iconSize = 24
    for _, cur in ipairs(crestCurrencies) do
        -- Alternating row bg
        local rowBg = currencyPanel:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
        rowBg:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
        rowBg:SetHeight(CREST_ROW_H)
        rowBg:SetColorTexture(1, 1, 1, (_ % 2 == 0) and 0.03 or 0)

        local ico = currencyPanel:CreateTexture(nil, "ARTWORK")
        ico:SetSize(iconSize, iconSize)
        ico:SetPoint("TOPLEFT", currPad, curY - (CREST_ROW_H - iconSize) / 2)
        ico:SetTexture(cur.icon or "Interface\\Icons\\INV_Misc_Coin_01")
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local crestHit = CreateFrame("Frame", nil, currencyPanel)
        crestHit:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
        crestHit:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
        crestHit:SetHeight(CREST_ROW_H)
        crestHit:EnableMouse(true)
        crestHit:SetScript("OnEnter", function(self)
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "currency",
                    currencyID = cur.currencyID,
                    charKey = charKey,
                    anchor = "ANCHOR_RIGHT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "currency",
                    currencyID = cur.currencyID,
                    charKey = charKey,
                    anchor = "ANCHOR_RIGHT",
                })
            end
        end)
        crestHit:SetScript("OnLeave", function()
            if HideTooltip then
                HideTooltip()
            elseif ns.TooltipService then
                ns.TooltipService:Hide()
            end
        end)

        -- Name (left aligned; reserve currAmtReserve for amount column — symmetric rows)
        local nameText = FontManager:CreateFontString(currencyPanel, GFR("gearCurrencyLabel"), "OVERLAY")
        nameText:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        nameText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad - currAmtReserve, 0)
        nameText:SetPoint("TOP", ico, "TOP", 0, 0)
        nameText:SetPoint("BOTTOM", ico, "BOTTOM", 0, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetTextColor(0.85, 0.85, 0.85)
        -- Always use the first word (e.g. Adventurer/Veteran) to keep labels crisp without truncation.
        local rawCrestName = cur.name or ""
        local displayCrestName = rawCrestName
        if rawCrestName and not (issecretvalue and issecretvalue(rawCrestName)) and rawCrestName ~= "" then
            local firstWord = rawCrestName:match("^(%S+)")
            firstWord = firstWord or rawCrestName
            local tierHex = GetUpgradeTrackHex(firstWord)
            if tierHex then
                displayCrestName = "|cff" .. tierHex .. firstWord .. "|r"
            else
                displayCrestName = firstWord
            end
        end
        nameText:SetText(displayCrestName)
        nameText:SetShadowOffset(1, -1)
        nameText:SetShadowColor(0, 0, 0, 0.8)

        -- Amount / cap: GetCurrencyData (same source as PvE + Currency tab) — season earned/max or weekly qty/cap + green/red
        local cd = WarbandNexus.GetCurrencyData and WarbandNexus:GetCurrencyData(cur.currencyID, charKey) or nil
        if not cd then
            local mq = (type(cur.maxQuantity) == "number" and cur.maxQuantity > 0) and cur.maxQuantity or 0
            cd = {
                currencyID = cur.currencyID,
                name = cur.name,
                quantity = cur.amount or 0,
                maxQuantity = mq,
                totalEarned = nil,
                seasonMax = nil,
            }
        end
        local amountText = FontManager:CreateFontString(currencyPanel, GFR("gearCurrencyAmount"), "OVERLAY")
        amountText:SetWidth(currAmtReserve - 4)
        amountText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad, 0)
        amountText:SetPoint("TOP", ico, "TOP", 0, 0)
        amountText:SetPoint("BOTTOM", ico, "BOTTOM", 0, 0)
        amountText:SetJustifyH("RIGHT")
        amountText:SetShadowOffset(1, -1)
        amountText:SetShadowColor(0, 0, 0, 0.8)
        if ns.UI_BindSeasonProgressAmount then
            ns.UI_BindSeasonProgressAmount(amountText, cd)
        elseif ns.UI_FormatSeasonProgressCurrencyLine then
            amountText:SetText(ns.UI_FormatSeasonProgressCurrencyLine(cd) or "")
        end

        curY = curY - CREST_ROW_H
    end

    -- Divider line
    local divider = currencyPanel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY - 4)
    divider:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY - 4)
    divider:SetHeight(1)
    divider:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)

    -- Gold row
    if goldCurrency then
        curY = curY - 14
        local goldIco = currencyPanel:CreateTexture(nil, "ARTWORK")
        goldIco:SetSize(iconSize, iconSize)
        goldIco:SetPoint("TOPLEFT", currPad, curY)
        goldIco:SetTexture(goldCurrency.icon or 133784)
        goldIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local goldText = FontManager:CreateFontString(currencyPanel, GFR("gearGoldLabel"), "OVERLAY")
        goldText:SetPoint("LEFT", goldIco, "RIGHT", 6, 0)
        goldText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad - currAmtReserve, 0)
        goldText:SetJustifyH("LEFT")
        goldText:SetWordWrap(false)
        goldText:SetTextColor(1, 0.82, 0)
        goldText:SetText((ns.L and ns.L["GOLD_LABEL"]) or "Gold")
        goldText:SetShadowOffset(1, -1)
        goldText:SetShadowColor(0, 0, 0, 0.8)

        local goldAmt = FontManager:CreateFontString(currencyPanel, GFR("gearGoldAmount"), "OVERLAY")
        goldAmt:SetWidth(currAmtReserve - 4)
        goldAmt:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad, 0)
        goldAmt:SetPoint("TOP", goldIco, "TOP", 0, 0)
        goldAmt:SetPoint("BOTTOM", goldIco, "BOTTOM", 0, 0)
        goldAmt:SetJustifyH("RIGHT")
        goldAmt:SetShadowOffset(1, -1)
        goldAmt:SetShadowColor(0, 0, 0, 0.8)
        local copper = (goldCurrency.amount or 0) * 10000 + (goldCurrency.silver or 0) * 100 + (goldCurrency.copper or 0)
        goldAmt:SetText("|cffffff00" .. (FormatGold and FormatGold(copper) or (tostring(goldCurrency.amount or 0) .. "g")) .. "|r")
    end

    -- Footer hint: Shift info belongs to panel footer, not title region.
    local shiftHint = FontManager:CreateFontString(currencyPanel, "small", "OVERLAY")
    shiftHint:SetPoint("BOTTOMLEFT", currencyPanel, "BOTTOMLEFT", currPad, 4)
    shiftHint:SetPoint("BOTTOMRIGHT", currencyPanel, "BOTTOMRIGHT", -currPad, 4)
    shiftHint:SetJustifyH("RIGHT")
    shiftHint:SetText("|cff777777" .. GetLocalizedText("SHIFT_HINT_SEASON_PROGRESS_SHORT", "Shift: Season progress") .. "|r")
    shiftHint:SetShadowOffset(1, -1)
    shiftHint:SetShadowColor(0, 0, 0, 0.8)

    -- ── RIGHT PANEL: Item Upgrade Recommendations (scrollable, bordered) ───────
    local storagePanel = CreateFrame("Frame", nil, card, "BackdropTemplate")
    local storagePanelH = panelH
    storagePanel:SetWidth(storageW)
    storagePanel:SetHeight(storagePanelH)
    storagePanel:SetPoint("TOPLEFT", card, "TOPLEFT", midLeft + midColW + PANEL_GAP, panelTopY)
    storagePanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    storagePanel:SetBackdropColor(0.06, 0.06, 0.08, 0.86)
    storagePanel:SetBackdropBorderColor(accent[1] * 0.36, accent[2] * 0.36, accent[3] * 0.46, 0.52)
    local storageTitle = FontManager:CreateFontString(storagePanel, GFR("gearStorageCardTitle"), "OVERLAY")
    storageTitle:SetPoint("TOPLEFT", 12, -8)
    storageTitle:SetPoint("TOPRIGHT", -12, -8)
    storageTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1] * 255), math.floor(accent[2] * 255), math.floor(accent[3] * 255))
        .. GetLocalizedText("GEAR_ITEM_UPGRADE_RECOMMENDATIONS_TITLE", "Item Upgrade Recommendations") .. "|r")

    -- Subtitle removed to declutter; scrollable rows alone communicate "transferable upgrades from Storage".

    local storageRows = {}
    do
        local equippedSlots = gearData and gearData.slots or {}
        local seenItemLink = {}
        if storageFindings then
            for slotID, candidates in pairs(storageFindings) do
                local best = candidates and candidates[1]
                if best then
                    local current = (equippedSlots[slotID] and equippedSlots[slotID].itemLevel) or 0
                    local target = best.itemLevel or 0
                    if target > current then
                        local linkKey = best.itemLink or ("id:" .. tostring(best.itemID or 0))
                        if not seenItemLink[linkKey] then
                            seenItemLink[linkKey] = true
                            local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
                            storageRows[#storageRows + 1] = {
                                slotID = slotID,
                                slotName = (slotDef and slotDef.label) or GetLocalizedText("GEAR_SLOT_FALLBACK_FORMAT", "Slot %d"):format(tonumber(slotID) or 0),
                                currentIlvl = current,
                                targetIlvl = target,
                                itemLink = best.itemLink,
                                itemID = best.itemID,
                                source = best.source or "",
                                sourceType = best.sourceType or "",
                                sourceClassFile = best.sourceClassFile,
                                delta = target - current,
                            }
                        end
                    end
                end
            end
        end
        table.sort(storageRows, function(a, b)
            if a.delta ~= b.delta then return a.delta > b.delta end
            return a.slotID < b.slotID
        end)
    end

    local storagePad = 8
    local storageHeaderH = 32  -- Reduced (subtitle removed): just the title band.
    local storageBarW = 22
    local rowH = 32
    local viewportH = storagePanelH - storageHeaderH - storagePad - 10
    local recScroll, recContent
    local scroll = ns.UI.Factory and ns.UI.Factory.CreateScrollFrame and ns.UI.Factory:CreateScrollFrame(storagePanel, "UIPanelScrollFrameTemplate", true)
    local sbCol
    -- Pre-compute overflow so we can decide whether to reserve space for the scrollbar column at all.
    local rowsOverflow = (#storageRows * rowH) > viewportH
    if scroll then
        if scroll.SetFrameLevel and storagePanel.GetFrameLevel then
            scroll:SetFrameLevel(storagePanel:GetFrameLevel() + 2)
        end
        sbCol = ns.UI.Factory and ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory:CreateScrollBarColumn(storagePanel, storageBarW, storagePad, storagePad)
        if sbCol and scroll.ScrollBar and ns.UI.Factory and ns.UI.Factory.PositionScrollBarInContainer then
            ns.UI.Factory:PositionScrollBarInContainer(scroll.ScrollBar, sbCol, 0)
        end
        scroll:SetPoint("TOPLEFT", storagePad, -storageHeaderH)
        -- Hide the scrollbar column entirely when no overflow, and let scroll area reclaim its width.
        if rowsOverflow then
            scroll:SetPoint("BOTTOMRIGHT", -storageBarW, storagePad)
            if sbCol and sbCol.Show then sbCol:Show() end
        else
            scroll:SetPoint("BOTTOMRIGHT", -storagePad, storagePad)
            if sbCol and sbCol.Hide then sbCol:Hide() end
        end
        local content = CreateFrame("Frame", nil, scroll)
        recScroll = scroll
        recContent = content
        local contentW = rowsOverflow
            and math.max(120, storageW - storagePad * 2 - storageBarW)
            or  math.max(120, storageW - storagePad * 2)
        content:SetWidth(contentW)
        content:SetHeight(math.max(#storageRows * rowH, viewportH))
        scroll:SetScrollChild(content)

        if #storageRows == 0 then
            local empty = FontManager:CreateFontString(content, GFR("gearStorageEmpty"), "OVERLAY")
            empty:SetAllPoints()
            empty:SetJustifyH("CENTER")
            empty:SetJustifyV("MIDDLE")
            empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY_NO_BOE_WOE", "Can't find any BoE or WoE to upgrade on item slots."))
            empty:SetTextColor(0.55, 0.55, 0.6)
        else
            local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
            for i = 1, #storageRows do
                local row = storageRows[i]
                local line = ns.UI.Factory and ns.UI.Factory.CreateContainer and ns.UI.Factory:CreateContainer(content, contentW, rowH - 2, true)
                if line then
                    line:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                    if ns.UI.Factory and ns.UI.Factory.ApplyRowBackground then
                        ns.UI.Factory:ApplyRowBackground(line, i)
                    end
                    line:EnableMouse(true)
                    local delta = (row.targetIlvl or 0) - (row.currentIlvl or 0)
                    local txt = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
                    txt:SetPoint("LEFT", 8, 0)
                    txt:SetPoint("RIGHT", -8, 0)
                    txt:SetJustifyH("LEFT")
                    txt:SetWordWrap(false)
                    -- Compact format: slot · cur → tgt (+delta) · source. Color emphasis on delta only.
                    local deltaTxt = (delta > 0) and ("|cff80ff80+" .. delta .. "|r") or ""
                    local src = row.source or ""
                    if src ~= "" then src = " |cff888888\194\183|r |cffb0b6c4" .. src .. "|r" end
                    txt:SetText(string.format("|cffd6dae6%s|r  %d \194\160\226\134\146\194\160 %d  %s%s",
                        row.slotName or "Slot",
                        row.currentIlvl or 0,
                        row.targetIlvl or 0,
                        deltaTxt,
                        src))
                    txt:SetTextColor(0.9, 0.92, 1)
                    line:SetScript("OnEnter", function(self)
                        if ShowTooltip then
                            ShowTooltip(self, {
                                type = "item",
                                itemID = row.itemID,
                                itemLink = row.itemLink,
                                anchor = "ANCHOR_LEFT",
                                itemTooltipContext = itemTooltipContext,
                            })
                        end
                    end)
                    line:SetScript("OnLeave", function()
                        if HideTooltip then HideTooltip() end
                    end)
                end
            end
        end
        if ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(scroll)
        end
    end

    -- Paperdoll last so slot icons / ilvl / track labels paint above the recommendations panel (same parent).
    DrawPaperDollInCard(card, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true, paperdollBaseX, charKey, yPaperBandTop, paperdollH, paperdollH)

    cardH = CARD_PAD + 24 + panelH + CARD_PAD
    if recContent then
        local newViewportH = panelH - storageHeaderH - storagePad - 10
        recContent:SetHeight(math.max(#storageRows * rowH, math.max(newViewportH, 40)))
        if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
        end
    end

    card:SetHeight(cardH)

    card:Show()
    return yOffset - cardH - 12, cardH
end

-- (Equipment Status card removed per user request)

local function BuildStorageRecommendationRows(findings, gearData)
    local rows = {}
    if not findings then return rows end
    local equippedSlots = gearData and gearData.slots or {}
    local seenItemLink = {}

    for slotID, candidates in pairs(findings) do
        local best = candidates and candidates[1]
        if best then
            local current = (equippedSlots[slotID] and equippedSlots[slotID].itemLevel) or 0
            local target = best.itemLevel or 0
            if target > current then
                local linkKey = best.itemLink or ("id:" .. tostring(best.itemID or 0))
                if seenItemLink[linkKey] then
                    -- Same item already shown (e.g. trinket for slot 13 and 14) — show once
                else
                    seenItemLink[linkKey] = true
                    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
                    rows[#rows + 1] = {
                        slotID = slotID,
                        slotName = (slotDef and slotDef.label) or GetLocalizedText("GEAR_SLOT_FALLBACK_FORMAT", "Slot %d"):format(tonumber(slotID) or 0),
                        currentIlvl = current,
                        targetIlvl = target,
                        itemLink = best.itemLink,
                        itemID = best.itemID,
                        source = best.source or "",
                        sourceType = best.sourceType or "",
                        sourceClassFile = best.sourceClassFile,
                        delta = target - current,
                        requiredLevel = best.requiredLevel,
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.delta ~= b.delta then
            return a.delta > b.delta
        end
        return a.slotID < b.slotID
    end)
    return rows
end

--- Color character name in storage source line; warband stays plain.
local function ColoredStorageSourceName(classFile, name)
    if not name or name == "" then return name end
    return "|cff" .. GetClassHex(classFile) .. name .. "|r"
end

local function FormatStorageSourceDisplay(source, sourceClassFile, viewerClassFile)
    if not source then return "" end
    if source == "Warband Bank" then
        return source
    end
    if source == "Your Bag" or source == "Your Bank" then
        return ColoredStorageSourceName(viewerClassFile, source)
    end
    local paren = source:find(" %(")
    if paren and paren > 1 then
        local namePart = source:sub(1, paren - 1)
        local rest = source:sub(paren)
        return ColoredStorageSourceName(sourceClassFile, namePart) .. rest
    end
    return ColoredStorageSourceName(sourceClassFile, source)
end

local function DrawStorageRecommendationsCard(parent, yOffset, gearData, storageFindings, charData, layout)
    local rows = BuildStorageRecommendationRows(storageFindings, gearData)
    local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
    local title = (ns.L and ns.L["GEAR_STORAGE_TITLE"]) or "Storage Upgrade Recommendations"
    local subtitle = (ns.L and ns.L["GEAR_STORAGE_SUBTITLE"]) or "Transferable items only (BoE / Warbound)"
    local rowH = 36
    local headerH = 56
    local titleToContentGap = 12
    local cardH = headerH + titleToContentGap + (math.max(#rows, 1) * rowH) + 10

    local card = CreateCard(parent, cardH)
    local leftInset = (layout and layout.leftInset) or SIDE_MARGIN
    local fixedWidth = layout and layout.width
    if fixedWidth and fixedWidth > 0 then
        card:SetWidth(fixedWidth)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", leftInset, yOffset)
    else
        card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
        card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, yOffset)
    end

    local accent = (COLORS and COLORS.accent) or { 0.6, 0.6, 1.0 }
    local hexAcc = format("%02x%02x%02x", math.floor(accent[1] * 255), math.floor(accent[2] * 255), math.floor(accent[3] * 255))

    local titleText = FontManager:CreateFontString(card, GFR("gearStorageCardTitle"), "OVERLAY")
    titleText:SetPoint("TOPLEFT", 14, -12)
    titleText:SetText("|cff" .. hexAcc .. title .. "|r")

    local subtitleText = FontManager:CreateFontString(card, GFR("gearStorageSubtitle"), "OVERLAY")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    subtitleText:SetText(subtitle)
    subtitleText:SetTextColor(0.6, 0.6, 0.7)

    local startY = -headerH - titleToContentGap
    if #rows == 0 then
        local empty = FontManager:CreateFontString(card, GFR("gearStorageEmpty"), "OVERLAY")
        empty:SetPoint("TOPLEFT", 14, startY)
        empty:SetPoint("TOPRIGHT", -14, startY)
        empty:SetJustifyH("LEFT")
        empty:SetText((ns.L and ns.L["GEAR_STORAGE_EMPTY"]) or "No better BoE / Warbound upgrades found for this character.")
        empty:SetTextColor(0.55, 0.55, 0.6)
        card:Show()
        return yOffset - cardH - 12, cardH
    end

    for i = 1, #rows do
        local row = rows[i]
        local container = ns.UI.Factory:CreateContainer(card, 10, rowH - 2)
        container:SetPoint("TOPLEFT", 10, startY - (i - 1) * rowH)
        container:SetPoint("TOPRIGHT", -10, startY - (i - 1) * rowH)
        container:EnableMouse(true)
        if ns.UI.Factory and ns.UI.Factory.ApplyRowBackground then
            ns.UI.Factory:ApplyRowBackground(container, i)
        end

        -- Column 1: Gear slot (fixed width, with spacing)
        local slotText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        slotText:SetPoint("LEFT", 10, 0)
        slotText:SetWidth(80)
        slotText:SetJustifyH("LEFT")
        slotText:SetText(row.slotName)
        slotText:SetTextColor(0.95, 0.95, 1.0)
        slotText:SetWordWrap(false)
        slotText:SetNonSpaceWrap(false)

        -- Column 2: current ilvl [atlas] target ilvl + increase (wider so 3-digit ilvls don't truncate)
        local currIlvlText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        currIlvlText:SetPoint("LEFT", slotText, "RIGHT", 10, 0)
        currIlvlText:SetWidth(40)
        currIlvlText:SetJustifyH("RIGHT")
        currIlvlText:SetText(tostring(row.currentIlvl or 0))
        currIlvlText:SetTextColor(0.75, 0.75, 0.8)
        currIlvlText:SetWordWrap(false)

        local arrowTex = container:CreateTexture(nil, "ARTWORK")
        arrowTex:SetSize(14, 14)
        arrowTex:SetPoint("LEFT", currIlvlText, "RIGHT", 6, 0)
        if arrowTex.SetAtlas then
            arrowTex:SetAtlas("common-dropdown-icon-play", true)
        else
            arrowTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            arrowTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            arrowTex:SetVertexColor(0.3, 1, 0.4)
        end

        local targetIlvlText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        targetIlvlText:SetPoint("LEFT", arrowTex, "RIGHT", 6, 0)
        targetIlvlText:SetWidth(40)
        targetIlvlText:SetJustifyH("LEFT")
        targetIlvlText:SetText(tostring(row.targetIlvl or 0))
        targetIlvlText:SetTextColor(0.4, 1, 0.5)
        targetIlvlText:SetWordWrap(false)

        local delta = (row.targetIlvl and row.currentIlvl) and (row.targetIlvl - row.currentIlvl) or 0
        local increaseText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        increaseText:SetPoint("LEFT", targetIlvlText, "RIGHT", 8, 0)
        increaseText:SetWidth(44)
        increaseText:SetJustifyH("LEFT")
        increaseText:SetText(delta > 0 and ("+" .. tostring(delta)) or "")
        increaseText:SetTextColor(0.35, 0.9, 0.45)
        increaseText:SetWordWrap(false)

        -- Column 3: Level (optional, white) then item icon
        local levelPrefix = ""
        if row.requiredLevel and row.requiredLevel > 0 then
            levelPrefix = "Lv" .. tostring(row.requiredLevel) .. " "
        end
        local levelText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        levelText:SetPoint("LEFT", increaseText, "RIGHT", 10, 0)
        levelText:SetText(levelPrefix)
        levelText:SetTextColor(1, 1, 1)
        levelText:SetWordWrap(false)

        local itemIcon = container:CreateTexture(nil, "ARTWORK")
        itemIcon:SetSize(22, 22)
        itemIcon:SetPoint("LEFT", levelText, "RIGHT", 4, 0)
        local icon = row.itemLink and GetItemIconSafe(row.itemLink) or GetItemIconSafe(row.itemID)
        itemIcon:SetTexture(icon or 134400)
        itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Source (right): no fixed width — grows left so item name can use remaining space (no huge gap).
        local sourceText = FontManager:CreateFontString(container, GFR("gearStorageSource"), "OVERLAY")
        sourceText:SetPoint("RIGHT", container, "RIGHT", -10, 0)
        sourceText:SetJustifyH("RIGHT")
        local bindLabel = ""
        if row.sourceType == "warbound" then
            bindLabel = "WB"
        elseif row.sourceType == "warbound_until_equipped" then
            bindLabel = "WuE"
        elseif row.sourceType == "boe" then
            bindLabel = "BoE"
        end
        local sourceBody = FormatStorageSourceDisplay(row.source, row.sourceClassFile, charData and charData.classFile)
        if bindLabel ~= "" then
            sourceText:SetText(sourceBody .. "  |cff888888(" .. bindLabel .. ")|r")
        else
            sourceText:SetText(sourceBody)
        end
        sourceText:SetTextColor(1, 1, 1)
        sourceText:SetWordWrap(false)
        sourceText:SetNonSpaceWrap(false)

        -- Item name: fills space between icon and source column
        local itemText = FontManager:CreateFontString(container, GFR("gearStorageRow"), "OVERLAY")
        itemText:SetPoint("LEFT", itemIcon, "RIGHT", 8, 0)
        itemText:SetPoint("RIGHT", sourceText, "LEFT", -8, 0)
        itemText:SetJustifyH("LEFT")
        local displayItem = row.itemLink or ("item:" .. tostring(row.itemID or 0))
        itemText:SetText(displayItem)
        itemText:SetTextColor(0.75, 0.85, 1.0)
        itemText:SetWordWrap(false)
        itemText:SetNonSpaceWrap(false)

        -- Tooltip: item only (no extra Slot/iLvl/From lines)
        container:SetScript("OnEnter", function(self)
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "item",
                    itemID = row.itemID,
                    itemLink = row.itemLink,
                    anchor = "ANCHOR_LEFT",
                    itemTooltipContext = itemTooltipContext,
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = row.itemID,
                    itemLink = row.itemLink,
                    anchor = "ANCHOR_LEFT",
                    itemTooltipContext = itemTooltipContext,
                })
            end
        end)
        container:SetScript("OnLeave", function()
            if HideTooltip then
                HideTooltip()
            elseif ns.TooltipService then
                ns.TooltipService:Hide()
            end
        end)
    end

    card:Show()
    return yOffset - cardH - 12, cardH
end

-- ============================================================================
-- CHARACTER SELECTOR  (dropdown button)
-- ============================================================================

-- Singleton dropdown frames (reused to avoid frame buildup)
local gearCharDropdownMenu = nil
local gearCharDropdownBg   = nil
local gearCharSelectorBtn  = nil
local gearHideFilterBtn    = nil
local gearCharDropdownEntryPool = {}

local GEAR_CHAR_SEP = "|cff888888 | |r"

--- Max pixel width of colored character names (for aligned name column).
local function MeasureGearCharNameColumnWidth(chars, measureFs)
    local maxW = 0
    for i = 1, #chars do
        local c = chars[i].data
        local hex = GetClassHex(c.classFile)
        local nm = c.name or chars[i].key or ""
        measureFs:SetText("|cff" .. hex .. nm .. "|r")
        maxW = math.max(maxW, measureFs:GetStringWidth())
    end
    return maxW
end

--- Name column width: wide enough for longest name, capped so realm keeps a readable minimum width.
local function ComputeGearCharNameColW(chars, measureFs, textBudget)
    if textBudget < 56 then
        return math.max(36, math.floor(textBudget * 0.38))
    end
    local raw = MeasureGearCharNameColumnWidth(chars, measureFs) + 6
    local minRealm = 102
    local sepReserve = 22
    local capByRealm = textBudget - minRealm - sepReserve
    local capByRatio = math.floor(textBudget * 0.48)
    local cap = math.min(capByRatio, math.max(52, capByRealm))
    return math.min(math.max(raw, 48), cap)
end

--- Two fontstrings: fixed-width name column, then separator, then realm (remaining width).
local function LayoutGearCharNameRealmColumns(parent, nameColW, leftPad, arrowReserve)
    local nm = parent._nameLabel
    local sp = parent._sepLabel
    local rm = parent._realmLabel
    if not nm or not sp or not rm then return end
    nm:ClearAllPoints()
    sp:ClearAllPoints()
    rm:ClearAllPoints()
    nm:SetWidth(nameColW)
    nm:SetJustifyH("LEFT")
    nm:SetWordWrap(false)
    nm:SetPoint("LEFT", parent, "LEFT", leftPad, 0)
    nm:SetPoint("TOP", parent, "TOP", 0, 0)
    nm:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    sp:SetText(GEAR_CHAR_SEP)
    sp:SetWidth(20)
    sp:SetJustifyH("CENTER")
    sp:SetPoint("LEFT", nm, "RIGHT", 0, 0)
    sp:SetPoint("TOP", parent, "TOP", 0, 0)
    sp:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    rm:SetJustifyH("LEFT")
    rm:SetWordWrap(false)
    rm:SetPoint("LEFT", sp, "RIGHT", 2, 0)
    rm:SetPoint("RIGHT", parent, "RIGHT", -arrowReserve, 0)
    rm:SetPoint("TOP", parent, "TOP", 0, 0)
    rm:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
end

local function EnsureGearSelectorColumnLabels(btn)
    if btn._nameLabel then return end
    if btn._label then
        btn._label:Hide()
        btn._label = nil
    end
    btn._nameLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._sepLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._realmLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._measureFs = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "ARTWORK")
    btn._measureFs:SetAlpha(0)
    btn._measureFs:SetPoint("TOPLEFT", btn, "TOPLEFT", -4000, 0)
end

local function EnsureGearEntryColumnLabels(entryBtn)
    if entryBtn._nameLabel then return end
    if entryBtn._label then
        entryBtn._label:Hide()
        entryBtn._label = nil
    end
    entryBtn._nameLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
    entryBtn._sepLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
    entryBtn._realmLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
end

--- Close Gear character picker when main addon frame hides (menu is parented to UIParent).
function ns.HideGearCharacterDropdown()
    if gearCharDropdownMenu then gearCharDropdownMenu:Hide() end
    if gearCharDropdownBg then gearCharDropdownBg:Hide() end
end

local function CreateCharacterSelector(parent, currentCharKey, yOffset)
    local chars  = GetTrackedCharacters()
    if #chars == 0 then return nil, yOffset end

    local COLORS = ns.UI_COLORS
    local accent = COLORS.accent
    local layout = ns.UI_LAYOUT or {}
    local SCROLL_COL_EST = layout.SCROLLBAR_COLUMN_WIDTH or 22
    local MENU_EDGE_EST = 4

    local btn = gearCharSelectorBtn
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetHeight(GEAR_CHAR_SELECTOR_HEIGHT)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })

        EnsureGearSelectorColumnLabels(btn)

        local arrow = btn:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT", -5, 0)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

        local hi = btn:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.08)

        btn.isPersistentRowElement = true
        gearCharSelectorBtn = btn
    end

    EnsureGearSelectorColumnLabels(btn)

    btn:SetParent(parent)
    btn:ClearAllPoints()
    btn:SetHeight(GEAR_CHAR_SELECTOR_HEIGHT)
    btn:SetWidth(GEAR_CHAR_SELECTOR_WIDTH)
    -- Vertically centered like Characters/Storage/PvE header sort controls (RIGHT, -20, 0).
    btn:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    btn:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
    btn:SetBackdropBorderColor(accent[1]*0.6, accent[2]*0.6, accent[3]*0.6, 0.8)

    local function SetLabelToChar(charKey)
        local db    = WarbandNexus.db and WarbandNexus.db.global
        local cData = db and db.characters and db.characters[charKey]
        local nm = btn._nameLabel
        local rm = btn._realmLabel
        if not nm then return end
        if cData and (cData.name and cData.name ~= "") then
            local hex   = GetClassHex(cData.classFile)
            local namePart = "|cff" .. hex .. (cData.name or "") .. "|r"
            nm:SetText(namePart)
            nm:SetTextColor(1, 1, 1)
            local realm = cData.realm and cData.realm ~= "" and cData.realm or nil
            if realm and rm then
                local realmShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(realm)) or realm
                rm:SetText("|cffffffff" .. realmShown .. "|r")
            elseif rm then
                rm:SetText("")
            end
        elseif charKey and charKey ~= "" then
            nm:SetText(charKey)
            nm:SetTextColor(1, 1, 1)
            if rm then rm:SetText("") end
        else
            nm:SetText("")
            if rm then rm:SetText("") end
        end
    end

    -- Shared text budget: selector row and list rows use the same inner width as the scroll child
    -- (outer width minus left/right menu edges, scrollbar column, gap, and entry horizontal padding).
    local function RefreshSelectorColumns(charList)
        local list = charList or GetTrackedCharacters()
        if #list == 0 or not btn._measureFs then return end
        local btnW = math.max(1, btn:GetWidth())
        local scrollFrameW = btnW - 2 * MENU_EDGE_EST - SCROLL_COL_EST - 2
        local entryHPad = 12
        local rowTextBudget = math.max(56, scrollFrameW - entryHPad)
        local selectorLeftPad = 8
        local selectorArrowReserve = 22
        local selectorTextBudget = math.max(56, btnW - selectorLeftPad - selectorArrowReserve)
        local textBudget = math.max(56, math.min(rowTextBudget, selectorTextBudget))
        local nameColW = ComputeGearCharNameColW(list, btn._measureFs, textBudget)
        LayoutGearCharNameRealmColumns(btn, nameColW, selectorLeftPad, selectorArrowReserve)
        for i = 1, #gearCharDropdownEntryPool do
            local eb = gearCharDropdownEntryPool[i]
            if eb and eb._nameLabel then
                LayoutGearCharNameRealmColumns(eb, nameColW, 6, 6)
            end
        end
    end

    RefreshSelectorColumns(chars)
    SetLabelToChar(currentCharKey)

    -- Dropdown: reuse singleton menu and bg to avoid frame buildup
    btn:SetScript("OnClick", function(self)
        local list = GetTrackedCharacters()
        if #list == 0 then return end

        local menu = gearCharDropdownMenu
        local bg   = gearCharDropdownBg

        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(500)
            menu:SetWidth(GEAR_CHAR_SELECTOR_WIDTH)
            menu:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
            menu:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.9)

            -- Factory scroll + dedicated scrollbar column (matches main window / Collections)
            local Factory = ns.UI and ns.UI.Factory
            local layoutLocal = ns.UI_LAYOUT or {}
            local SCROLL_COL = layoutLocal.SCROLLBAR_COLUMN_WIDTH or 22
            local MENU_EDGE = 4

            if Factory and Factory.CreateScrollFrame and Factory.CreateScrollBarColumn and Factory.PositionScrollBarInContainer then
                menu._barColumn = Factory:CreateScrollBarColumn(menu, SCROLL_COL, MENU_EDGE, MENU_EDGE)
                local sf = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
                sf:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_EDGE, -MENU_EDGE)
                sf:SetPoint("BOTTOMRIGHT", menu._barColumn, "BOTTOMLEFT", -2, MENU_EDGE)
                if sf.SetClipsChildren then
                    sf:SetClipsChildren(true)
                end
                local sc = CreateFrame("Frame", nil, sf)
                sf:SetScrollChild(sc)
                menu._charScroll = sf
                menu._charScrollChild = sc
                if sf.ScrollBar then
                    Factory:PositionScrollBarInContainer(sf.ScrollBar, menu._barColumn, 0)
                end
                sf:SetScript("OnSizeChanged", function(frame, w)
                    if sc and w and w > 0 then
                        sc:SetWidth(w)
                    end
                end)
            else
                local sf = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
                sf:SetPoint("TOPLEFT", 4, -4)
                sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 4)
                if sf.SetClipsChildren then
                    sf:SetClipsChildren(true)
                end
                local sc = CreateFrame("Frame", nil, sf)
                sf:SetScrollChild(sc)
                menu._charScroll = sf
                menu._charScrollChild = sc
                menu._barColumn = nil
                sf:SetScript("OnSizeChanged", function(frame, w)
                    if sc and w and w > 0 then
                        sc:SetWidth(w)
                    end
                end)
            end
            gearCharDropdownMenu = menu
        end
        if not bg then
            bg = CreateFrame("Button", nil, UIParent)
            bg:SetAllPoints()
            bg:SetFrameStrata("FULLSCREEN_DIALOG")
            bg:SetFrameLevel(499)
            bg:SetScript("OnClick", function()
                menu:Hide()
                bg:Hide()
                if WarbandNexus and WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "gear", skipCooldown = true })
                end
            end)
            gearCharDropdownBg = bg
        end

        local ENTRY_H = GEAR_CHAR_DROPDOWN_ENTRY_H
        local contentH = #list * ENTRY_H + 8
        local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 800
        local maxMenuH = math.max(ENTRY_H + 8, math.floor(screenH * 0.52))
        local menuH = math.min(contentH, maxMenuH)
        menu:SetHeight(menuH)
        menu:ClearAllPoints()
        -- Same outer width and horizontal alignment as header selector (full card strip).
        local btnW = math.max(1, math.floor(self:GetWidth() + 0.5))
        menu:SetWidth(btnW)
        menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)

        local scroll = menu._charScroll
        local scrollChild = menu._charScrollChild
        if scroll and scrollChild then
            scrollChild:SetHeight(math.max(contentH, 1))
            scroll:SetVerticalScroll(0)
            local sw = scroll:GetWidth()
            if sw and sw > 0 then
                scrollChild:SetWidth(sw)
            end
        end

        local selKey = selectedCharKey or GetSelectedCharKey()

        -- Hide excess pooled entries, reuse or create as needed
        for pi = #list + 1, #gearCharDropdownEntryPool do
            local poolBtn = gearCharDropdownEntryPool[pi]
            if poolBtn then poolBtn:Hide() end
        end

        local entryParent = scrollChild or menu
        local entryY = -4
        for i = 1, #list do
            local charEntry = list[i]
            local entryBtn = gearCharDropdownEntryPool[i]
            if not entryBtn then
                entryBtn = CreateFrame("Button", nil, entryParent)
                EnsureGearEntryColumnLabels(entryBtn)
                local entryHi = entryBtn:CreateTexture(nil, "HIGHLIGHT")
                entryHi:SetAllPoints()
                entryHi:SetColorTexture(1, 1, 1, 0.1)
                gearCharDropdownEntryPool[i] = entryBtn
            end
            EnsureGearEntryColumnLabels(entryBtn)
            entryBtn:SetHeight(ENTRY_H)

            entryBtn:EnableMouseWheel(true)
            entryBtn:SetScript("OnMouseWheel", function(entry, delta)
                if ns.UI_ForwardMouseWheelToScrollAncestor then
                    ns.UI_ForwardMouseWheelToScrollAncestor(entry, delta)
                end
            end)

            entryBtn:SetParent(entryParent)
            entryBtn:ClearAllPoints()
            entryBtn:SetPoint("TOPLEFT",  6, entryY)
            entryBtn:SetPoint("TOPRIGHT", -6, entryY)

            if entryBtn.SetClippingChildren then
                entryBtn:SetClippingChildren(true)
            end
            local cKey   = charEntry.key
            local cData  = charEntry.data
            local hex    = GetClassHex(cData.classFile)
            local namePart = "|cff" .. hex .. (cData.name or cKey) .. "|r"
            local r = cData.realm and cData.realm ~= "" and cData.realm or ""
            entryBtn._nameLabel:SetText(namePart)
            entryBtn._nameLabel:SetTextColor(1, 1, 1)
            if r ~= "" then
                local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(r)) or r
                entryBtn._realmLabel:SetText("|cffffffff" .. rShown .. "|r")
            else
                entryBtn._realmLabel:SetText("")
            end

            if cKey == selKey then
                entryBtn._realmLabel:SetTextColor(accent[1] + 0.2, accent[2] + 0.2, accent[3] + 0.2)
            else
                entryBtn._realmLabel:SetTextColor(1, 1, 1)
            end

            entryBtn:SetScript("OnClick", function()
                selectedCharKey = cKey
                SetLabelToChar(cKey)
                menu:Hide()
                bg:Hide()
                if WarbandNexus and WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "gear", skipCooldown = true })
                end
            end)

            entryBtn:Show()
            entryY = entryY - ENTRY_H
        end

        local Factory = ns.UI and ns.UI.Factory
        local function SyncDropdownScroll()
            if not menu or not menu:IsShown() or not scroll or not scrollChild then return end
            local sw = scroll:GetWidth()
            if sw and sw > 0 then
                scrollChild:SetWidth(sw)
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(scroll)
            elseif scroll.UpdateScrollBarVisibility then
                scroll:UpdateScrollBarVisibility()
            end
        end

        local function RelayoutColumnsAfterSize()
            SyncDropdownScroll()
            RefreshSelectorColumns(list)
            SetLabelToChar(selKey)
        end

        bg:Show()
        menu:Show()
        RelayoutColumnsAfterSize()
        C_Timer.After(0, RelayoutColumnsAfterSize)
    end)

    btn:SetScript("OnEnter", function(self)
        local a = (ns.UI_COLORS or {}).accent or {0.5, 0.3, 0.8}
        self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        local a = (ns.UI_COLORS or {}).accent or {0.5, 0.3, 0.8}
        self:SetBackdropBorderColor(a[1]*0.6, a[2]*0.6, a[3]*0.6, 0.8)
    end)

    btn._refreshGearCharColumns = function()
        local cl = GetTrackedCharacters()
        if #cl == 0 then return end
        RefreshSelectorColumns(cl)
        SetLabelToChar(selectedCharKey or GetSelectedCharKey())
    end

    return btn, yOffset
end

local function CreateGearHeaderHideButton(parent)
    local btn = gearHideFilterBtn
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(GEAR_HIDE_FILTER_BUTTON_W, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or GEAR_CHAR_SELECTOR_HEIGHT or 32)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        local txt = FontManager:CreateFontString(btn, "body", "OVERLAY")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetJustifyH("CENTER")
        txt:SetTextColor(0.9, 0.9, 0.9)
        btn._text = txt
        gearHideFilterBtn = btn
    end

    btn:SetParent(parent)
    btn:ClearAllPoints()
    btn:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
    btn:SetBackdropBorderColor(0.45, 0.45, 0.55, 0.8)

    btn._text:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"))

    local function HideMenuClose()
        if btn._menu and btn._menu:IsShown() then btn._menu:Hide() end
        if btn._catcher and btn._catcher:IsShown() then btn._catcher:Hide() end
    end
    local function HideMenuApply(threshold, keepMenuOpen)
        ApplyLowLevelHideThreshold(threshold)
        if not keepMenuOpen then
            HideMenuClose()
        end
    end
    local function HideMenuBuild()
        local menu = btn._menu
        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(5200)
            menu:SetSize(132, 66)
            menu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
            local accent = (COLORS and COLORS.accent) or ((ns.UI_COLORS or {}).accent) or { 0.40, 0.20, 0.58 }
            menu:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
            btn._menu = menu
        end
        local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        local options = {
            { value = 80, label = GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") },
            { value = 90, label = GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") },
        }
        local children = { menu:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #children do
            children[i]:Hide()
            if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
        end
        local rowH = 30
        for i = 1, #options do
            local opt = options[i]
            local row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * rowH)
            row:SetHeight(rowH - 2)
            row:RegisterForClicks("LeftButtonUp")
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor((opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.20 or 0.10, 1)
            local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, opt.value == cur)
            if not cb then return menu end
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", row, "LEFT", 6, 0)
            cb:EnableMouse(false)
            local fs = FontManager:CreateFontString(row, "body", "OVERLAY")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(opt.label)
            fs:SetTextColor(1, 1, 1)
            row:SetScript("OnClick", function()
                local active = GetLowLevelHideThreshold(WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile)
                local nextThreshold = (active == opt.value) and 0 or opt.value
                HideMenuApply(nextThreshold, true)
                HideMenuBuild()
            end)
        end
        return menu
    end

    btn:SetScript("OnClick", function(self)
        local menu = btn._menu
        if menu and menu:IsShown() then
            HideMenuClose()
            return
        end
        if ns.HideGearCharacterDropdown then
            ns.HideGearCharacterDropdown()
        end
        menu = HideMenuBuild()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        menu:Show()
        local catcher = btn._catcher
        if not catcher then
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetFrameLevel(5199)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function(_, button)
                if menu and menu:IsShown() and not menu:IsMouseOver() and not btn:IsMouseOver() then
                    HideMenuClose()
                end
            end)
            btn._catcher = catcher
        end
        catcher:Show()
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.7, 0.7, 0.85, 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"), 1, 1, 1)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_TOGGLE", "Toggle filters: Level 80 / Level 90"), 0.8, 0.8, 0.8)
        local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_CURRENT", "Current: %s"):format(GetLowLevelHideLabel(cur)), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.45, 0.45, 0.55, 0.8)
        if GameTooltip then GameTooltip:Hide() end
    end)

    btn:Show()
    return btn
end

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================

function WarbandNexus:DrawGearTab(parent)
    -- Lazy-load FontManager if needed
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then return 0 end
    end

    -- Re-bind shared helpers (may not have been loaded at file parse time)
    if not COLORS then COLORS = ns.UI_COLORS end
    if not CreateCard then CreateCard = ns.UI_CreateCard end
    if not ApplyVisuals then ApplyVisuals = ns.UI_ApplyVisuals end
    if not CreateCollapsibleHeader then CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader end
    if not GetQualityHex then GetQualityHex = ns.UI_GetQualityHex end
    if not FormatGold then FormatGold = ns.UI_FormatGold end
    if not FormatNumber then FormatNumber = ns.UI_FormatNumber end
    if not GEAR_SLOTS then GEAR_SLOTS = ns.GEAR_SLOTS end
    if not SLOT_BY_ID then SLOT_BY_ID = ns.SLOT_BY_ID end

    if not COLORS or not CreateCard or not FontManager then return 0 end

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = TOP_MARGIN
    local accent     = COLORS.accent

    -- ── Character selection ───────────────────────────────────────────────────
    local charKey = GetSelectedCharKey()

    -- Auto-validate: selected char might no longer be tracked
    if selectedCharKey then
        local db = self.db and self.db.global
        if not (db and db.characters and db.characters[selectedCharKey] and db.characters[selectedCharKey].isTracked) then
            selectedCharKey = nil
            charKey = GetSelectedCharKey()
        end
    end

    -- Standard: use canonical key (normalized) for all DB/service calls so currency, gear, gold match.
    local canonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey

    local allChars = GetTrackedCharacters()
    if #allChars == 0 then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local height = DrawEmptyState and DrawEmptyState(
            parent,
            (ns.L and ns.L["GEAR_NO_TRACKED_CHARACTERS_TITLE"]) or "No tracked characters",
            (ns.L and ns.L["GEAR_NO_TRACKED_CHARACTERS_DESC"]) or "Log in to a character to start tracking gear."
        ) or 200
        return height
    end

    -- ── Header Card (in fixedHeader - non-scrolling) — Characters-tab layout + room for char selector ─────
    local r, g, b = accent[1], accent[2], accent[3]
    local hexAcc  = format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local titleTextContent = "|cff" .. hexAcc .. ((ns.L and ns.L["GEAR_TAB_TITLE"]) or "Gear Management") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["GEAR_TAB_DESC"]) or "Equipped gear, upgrade analysis, and crest tracking"
    -- Reserve space for [Hide filter][Character ▼] aligned with other tabs' -20 right inset + 8px gap between controls.
    local gearHeaderRightReserve = GEAR_CHAR_SELECTOR_WIDTH + GEAR_HIDE_FILTER_BUTTON_W + 8 + 20 + 4

    local headerCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "gear",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = gearHeaderRightReserve,
    }))
    headerCard:SetPoint("TOPLEFT",  SIDE_MARGIN, -headerYOffset)
    headerCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)

    local gearCharSel = CreateCharacterSelector(headerCard, charKey, 0)
    local hideBtn = CreateGearHeaderHideButton(headerCard)
    if hideBtn and gearCharSel then
        hideBtn:SetPoint("RIGHT", gearCharSel, "LEFT", -8, 0)
    elseif hideBtn then
        hideBtn:SetPoint("RIGHT", headerCard, "RIGHT", -20, 0)
    end
    headerCard:Show()
    if gearCharSel and gearCharSel._refreshGearCharColumns then
        C_Timer.After(0, function()
            if gearCharSel.GetParent and gearCharSel:GetParent() then
                gearCharSel._refreshGearCharColumns()
            end
        end)
    end

    -- Use shared header spacing so Gear matches the global tab header rhythm.
    headerYOffset = headerYOffset + (GetLayout().afterHeader or 75)

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = -TOP_MARGIN

    -- ── Data retrieval (all by canonical key) ──────────────────────────────────
    local db        = self.db and self.db.global
    local charData  = db and (db.characters[canonicalKey] or db.characters[charKey])
    local gearData  = (self.GetEquippedGear and self:GetEquippedGear(canonicalKey)) or nil

    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canonicalKey)) or {}

    -- Fetch currencies once; reuse for both affordability map and display panel
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(canonicalKey)) or {}
    local currencyAmounts = {}
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur and cur.currencyID ~= nil then
            local id = (type(cur.currencyID) == "number") and cur.currencyID or tonumber(cur.currencyID)
            local amt = (type(cur.amount) == "number") and cur.amount or tonumber(cur.amount)
            if id then currencyAmounts[id] = (amt and amt >= 0) and amt or 0 end
        end
    end

    local storageFindings = (self.FindGearStorageUpgrades and self:FindGearStorageUpgrades(canonicalKey)) or {}
    yOffset = DrawPaperDollCard(
        parent, yOffset, charData, gearData, upgradeInfo, canonicalKey, currencyAmounts,
        canonicalKey == currentKey, currencies, storageFindings
    )
    return math.abs(yOffset) + TOP_MARGIN
end
