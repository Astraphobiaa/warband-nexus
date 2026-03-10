--[[
    Warband Nexus - Gear Management Tab
    Professional WoW-style layout: paperdoll, Midnight crests, equipped items + upgrade status.

    Layout (full-width cards, like Characters tab):
    ┌────────────────────────────────────────────────────────────────────────────┐
    │ [Header: Title + Character Selector ▼]                                      │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Paperdoll — Full width; portrait + slots centered (Characters-style)       │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Upgrade currencies — Gold + Midnight Dawncrests (Adventurer → Myth)         │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Equipment — Slot | Item (icon, name, ilvl) | Status (track X/Y, upgradable)│
    ├────────────────────────────────────────────────────────────────────────────┤
    │ ▼ Storage upgrades (collapsible)                                            │
    └────────────────────────────────────────────────────────────────────────────┘
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager   = ns.FontManager

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
local ShowTooltip         = ns.UI_ShowTooltip
local HideTooltip         = ns.UI_HideTooltip
local CreateHeaderIcon    = ns.UI_CreateHeaderIcon
local GetTabIcon          = ns.UI_GetTabIcon
local CreateEmptyStateCard  = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard    = ns.UI_HideEmptyStateCard

-- Slot definitions from GearService
local GEAR_SLOTS         = ns.GEAR_SLOTS
local SLOT_BY_ID         = ns.SLOT_BY_ID
local EQUIP_LOC_TO_SLOTS = ns.EQUIP_LOC_TO_SLOTS

local format = string.format

local function FormatFloat2(value)
    if not value then return nil end
    local n = tonumber(value)
    if not n then return nil end
    return format("%.2f", n)
end

-- ============================================================================
-- CONSTANTS / LAYOUT  (addon theme: ns.UI_LAYOUT when available)
-- ============================================================================

local UI_LAYOUT      = ns.UI_LAYOUT or {}
local SIDE_MARGIN    = UI_LAYOUT.SIDE_MARGIN or 16
local TOP_MARGIN     = UI_LAYOUT.TOP_MARGIN or 12
local HEADER_H       = UI_LAYOUT.HEADER_HEIGHT or 32

-- Paper doll: sol panel | orta panel | sağ panel | alt panel (fixed widths); %10 büyütme
local PAPERDOLL_SCALE = 1.10
local function P(n) return math.floor(n * PAPERDOLL_SCALE + 0.5) end
local SLOT_SIZE      = P(38)
local SLOT_GAP       = P(5)
local DOLL_PAD       = P(12)
local SLOT_TO_TEXT_GAP = P(4)  -- yazı ile ok/slot arası daha sıkı
local TRACK_TEXT_W   = P(136)  -- Track metin taşmasını engellemek için genişletildi
local UPGRADE_ARROW_W = P(16)
local CURRENCY_RESERVE = P(312)
local CURRENCY_PANEL_W = 280
local CENTER_GAP     = P(10)

-- Fixed panel widths: sol = yazı + ikon + slot, sağ = slot + ikon + yazı
local LEFT_PANEL_W   = TRACK_TEXT_W + SLOT_TO_TEXT_GAP + UPGRADE_ARROW_W + SLOT_TO_TEXT_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_TEXT_GAP + UPGRADE_ARROW_W + 2 + TRACK_TEXT_W
local MODEL_W       = P(228)

-- Ortadan çizgi hizalama: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ)
local SLOT_HALF      = SLOT_SIZE / 2
local ARROW_HALF     = UPGRADE_ARROW_W / 2
local TEXT_HALF_W   = TRACK_TEXT_W / 2
-- Slot merkezinden ok merkezine uzaklık (px)
local ARROW_OFFSET_FROM_SLOT_CENTER = SLOT_HALF + SLOT_TO_TEXT_GAP + ARROW_HALF  -- 19+6+8 = 33
-- Slot merkezinden yazı bloğu merkezine uzaklık (px)
local TEXT_OFFSET_FROM_SLOT_CENTER  = ARROW_OFFSET_FROM_SLOT_CENTER + ARROW_HALF + SLOT_TO_TEXT_GAP + TEXT_HALF_W  -- 33+8+6+49 = 96

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

-- Source type labels + colors
local SOURCE_TYPE_COLOR = {
    warband   = { 0.4, 0.8, 1.0 },   -- cyan-blue
    char_bag  = { 0.6, 1.0, 0.6 },   -- green
    char_bank = { 0.9, 0.8, 0.5 },   -- gold-ish
    self_bag  = { 0.7, 0.7, 0.7 },   -- grey
    self_bank = { 0.7, 0.7, 0.7 },   -- grey
    boe       = { 1.0, 0.5, 0.1 },   -- orange
}

-- ============================================================================
-- SESSION STATE  (selected character; persists within session)
-- ============================================================================

local selectedCharKey = nil  -- nil = auto-select current player

local function GetSelectedCharKey()
    if selectedCharKey then return selectedCharKey end
    -- Default: current player
    return ns.Utilities and ns.Utilities:GetCharacterKey()
end

-- Expand/collapse state per section
local sectionExpanded = {
    upgrades = true,
    storage  = true,
}

-- ============================================================================
-- EVENT REFRESH REGISTRATION
-- ============================================================================

local _gearEventsRegistered = false

local function RegisterGearEvents()
    if _gearEventsRegistered then return end
    _gearEventsRegistered = true

    -- Event-driven refresh is handled centrally by UI.lua's SchedulePopulateContent.
    -- No additional listeners needed here; UI.lua already routes
    -- WN_GEAR_UPDATED, WN_ITEMS_UPDATED, WN_CHARACTER_UPDATED,
    -- WN_CURRENCY_UPDATED, WARBAND_CURRENCIES_UPDATED to PopulateContent
    -- when the gear tab is active.
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Get all tracked characters sorted by last seen descending.
local function GetTrackedCharacters()
    local chars = {}
    local db = WarbandNexus.db and WarbandNexus.db.global
    if not db or not db.characters then return chars end
    for charKey, data in pairs(db.characters) do
        if data.isTracked then
            chars[#chars + 1] = { key = charKey, data = data }
        end
    end
    table.sort(chars, function(a, b)
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
            itemId = tonumber(linkOrId:match("item:(%d+)"))
        end
        if not itemId then return nil end
        -- GetItemInfoInstant returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        if icon and icon ~= 0 and icon ~= "" then return icon end
        return nil
    end)
    return (ok and result) or nil
end

local function BuildCurrencyAmountMap(charKey)
    local map = {}
    local currencies = (WarbandNexus.GetGearUpgradeCurrenciesFromDB and WarbandNexus:GetGearUpgradeCurrenciesFromDB(charKey)) or {}
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur and cur.currencyID ~= nil then
            map[cur.currencyID] = (cur.amount ~= nil) and cur.amount or 0
        end
    end
    return map
end

local function CanAffordUpgrade(costs, currencyAmounts)
    if not costs or #costs == 0 then return true end
    if not currencyAmounts then return false end
    for i = 1, #costs do
        local cost = costs[i]
        local have = currencyAmounts[cost.currencyID] or 0
        if have < (cost.amount or 0) then
            return false
        end
    end
    return true
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
---@return Frame btn
local function CreateSlotButton(parent, slotID, slotData, x, y, isUpgradable, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon)
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
        local fs = FontManager:CreateFontString(btn, "tiny", "OVERLAY")
        if fs and fs.SetFontObject then
            fs:SetPoint("BOTTOMRIGHT", -2, 2)
            fs:SetJustifyH("RIGHT")
            btn.ilvlLabel = fs
            ilvlLabel:SetAlpha(0)
        else
            btn.ilvlLabel = ilvlLabel
        end
    else
        btn.ilvlLabel = ilvlLabel
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
    if isUpgradable then
        upgradeArrow = btn:CreateTexture(nil, "OVERLAY")
        upgradeArrow:SetSize(UPGRADE_ARROW_W, UPGRADE_ARROW_W)
        if upgradeArrow.SetAtlas then
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

    -- Tooltip
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(slotData.itemLink)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((slotDef and slotDef.label) or "Empty", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.12)

    -- Slot adı (Head, Trinket 1, Main Hand vb.) — Veteran/Champion yazısının üstünde
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    local slotName = (slotDef and slotDef.label) and slotDef.label or ""
    if slotID == 11 then slotName = "Ring 1"
    elseif slotID == 12 then slotName = "Ring 2"
    elseif slotID == 13 then slotName = "Trinket 1"
    elseif slotID == 14 then slotName = "Trinket 2"
    end
    local slotNameLabel
    if slotName ~= "" then
        slotNameLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, "tiny", "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotNameLabel:SetText("|cffffffff" .. slotName .. "|r")
        slotNameLabel:SetNonSpaceWrap(false)
        if slotNameLabel.SetWordWrap then slotNameLabel:SetWordWrap(false) end
    end

    -- Status label: ortadan çizgi — yazı/ikon/slot merkezleri aynı hizada
    local trackText = (statusText and statusText ~= "") and statusText or nil
    local trackLabel = nil
    local w = textWidth or TRACK_TEXT_W

    if trackText and side ~= "top" then
        trackLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, "tiny", "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trackLabel:SetText(trackText)
        trackLabel:SetNonSpaceWrap(false)
        if trackLabel.SetWordWrap then trackLabel:SetWordWrap(false) end
        trackLabel:SetWidth(w)

        if side == "left" or side == "right" or isBottomLeft or isBottomRight then
            -- Sol/sağ/silah: yazı bloğu ikonun YANINDA, aynı satırda dikey ortalanır
            local textCenterX
            if side == "left" or isBottomLeft then
                textCenterX = -TEXT_OFFSET_FROM_SLOT_CENTER
            else
                textCenterX = TEXT_OFFSET_FROM_SLOT_CENTER
            end
            local textContainer = CreateFrame("Frame", nil, parent)
            textContainer:SetSize(textWidth or TRACK_TEXT_W, P(36))
            textContainer:SetPoint("CENTER", btn, "CENTER", textCenterX, 0)
            -- Sol/sağ/silah: iki satırlık yazı bloğu ikonla dikey hizalı olsun (diğerleri gibi)
            local blockCenterOffset = 8
            trackLabel:SetParent(textContainer)
            trackLabel:ClearAllPoints()
            trackLabel:SetWidth(textWidth or TRACK_TEXT_W)
            trackLabel:SetPoint("CENTER", textContainer, "CENTER", 0, -blockCenterOffset)
            trackLabel:SetJustifyH("CENTER")
            if slotNameLabel then
                slotNameLabel:SetParent(textContainer)
                slotNameLabel:ClearAllPoints()
                slotNameLabel:SetPoint("BOTTOM", trackLabel, "TOP", 0, 2)
                slotNameLabel:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
                slotNameLabel:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
                slotNameLabel:SetJustifyH("CENTER")
            end
        end
    elseif slotNameLabel then
        -- Track yoksa: slot adı yine merkez hizada (sol/sağ/alt)
        if side == "left" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", -TEXT_OFFSET_FROM_SLOT_CENTER, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("CENTER")
        elseif side == "right" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", TEXT_OFFSET_FROM_SLOT_CENTER, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("CENTER")
        else
            -- bottom_left/bottom_right: slot adı ikonun yanında (aynı satır)
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", (side == "bottom_right") and TEXT_OFFSET_FROM_SLOT_CENTER or -TEXT_OFFSET_FROM_SLOT_CENTER, 0)
            slotNameLabel:SetWidth(textWidth or TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("CENTER")
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

--- Build track/tier string from upgradeInfo[slotID], e.g. "Veteran 6/6", "Champion 4/8".
--- Rarity rengi kullanır (Champion/Adventurer/Veteran); slot adları ayrıca beyaz tutulur.
local function GetSlotTrackText(upgradeInfo, slotID, quality)
    local up = upgradeInfo and upgradeInfo[slotID]
    if not up then return nil end
    local track = (up.trackName and up.trackName ~= "") and up.trackName or nil
    local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
    local hex = GetQualityHex and GetQualityHex(quality or 0) or "ffffff"
    if maxT and maxT > 0 and track then
        return format("|cff%s%s %d/%d|r", hex, track, curT, maxT)
    end
    if track and track ~= "" then return "|cff" .. hex .. track .. "|r" end
    return nil
end

--- Draw paperdoll: sol panel (yazı-ikon-slot) | orta (model) | sağ panel (slot-ikon-yazı) | alt panel.
local function DrawPaperDollInCard(card, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar)
    local cardW = card:GetWidth()
    local contentRight = cardW - math.max(CURRENCY_RESERVE, CURRENCY_PANEL_W + (CARD_PAD * 2))

    -- Sol panel: fixed width; slot sağda (yazı - ikon - slot)
    local leftX = CARD_PAD + LEFT_PANEL_W - SLOT_SIZE
    local leftColRight = leftX + SLOT_SIZE
    -- Yan yana hizalı: sol | gap | orta | gap | sağ; sağ panel taşmasın diye clamp
    local rightXPreferred = leftColRight + CENTER_GAP + MODEL_W + CENTER_GAP
    local rightX = math.min(rightXPreferred, contentRight - CARD_PAD - RIGHT_PANEL_W)

    local slots = gearData and gearData.slots or {}
    local function GetSlotData(slotID) return slots[slotID] end
    local function IsUpgradable(slotID)
        local up = upgradeInfo and upgradeInfo[slotID]
        return up and up.canUpgrade and CanAffordUpgrade(up.costs, currencyAmounts)
    end
    local function IsNotUpgradeable(slotID)
        local slot = slots[slotID]
        if slot and slot.notUpgradeable then return true end
        local up = upgradeInfo and upgradeInfo[slotID]
        if up and up.notUpgradeable then return true end
        return false
    end

    local startY = -(CARD_PAD + 24)
    local rowStep = SLOT_SIZE + SLOT_GAP

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i, slotID in ipairs(leftSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), leftX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W)
    end

    -- Right column: 6 armor + 2 trinkets — slot | ikon | yazı
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i, slotID in ipairs(rightSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), rightX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W)
    end

    -- Alt panel: slot üstte, altında ikon + yazı (yazılar aşağı); silahlar birbirine yakın
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local WEAPON_TEXT_W = TRACK_TEXT_W
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = leftColRight + (rightX - leftColRight - weaponRowW) / 2
    local maxRows = math.max(#leftSlots, #rightSlots)
    local bottomY = startY - maxRows * rowStep - 8
    for i, slotID in ipairs(weaponSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        local weaponSide = (i == 1) and "bottom_left" or "bottom_right"  -- Main Hand solunda, Off Hand sağında
        CreateSlotButton(card, slotID, GetSlotData(slotID), wx, bottomY, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W)
    end

    -- Orta panel: model frame alt ucu trinket satırının altına denk gelecek şekilde uzatıldı
    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- trinket altına kadar
    local classFile = charData and charData.classFile
    local accent    = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }
    local modelX    = leftColRight + CENTER_GAP
    local modelTopY = startY

    local centerRef = nil
    if isCurrentChar == true then
        local ok, m = pcall(function()
            local f = CreateFrame("PlayerModel", nil, card)
            f:SetSize(MODEL_W, MODEL_H)
            f:SetPoint("TOPLEFT", modelX, modelTopY)
            f:SetUnit("player")
            f:SetCamDistanceScale(0.92)
            f:SetPortraitZoom(0.42)
            return f
        end)
        if ok and m then centerRef = m end
    end

    -- Fallback: large class icon
    if not centerRef then
        local portrait = CreateFrame("Frame", nil, card, "BackdropTemplate")
        portrait:SetSize(MODEL_W, MODEL_H)
        portrait:SetPoint("TOPLEFT", modelX, modelTopY)
        portrait:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        portrait:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        portrait:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)
        local portraitTex = portrait:CreateTexture(nil, "ARTWORK")
        portraitTex:SetPoint("TOPLEFT", 4, -4)
        portraitTex:SetPoint("BOTTOMRIGHT", -4, 4)
        local classCoords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if classCoords then
            portraitTex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            portraitTex:SetTexCoord(unpack(classCoords))
        else
            portraitTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            portraitTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        centerRef = portrait
    end

    -- Border around model/portrait
    local modelBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
    modelBorder:SetPoint("TOPLEFT",     centerRef, "TOPLEFT",      -1,  1)
    modelBorder:SetPoint("BOTTOMRIGHT", centerRef, "BOTTOMRIGHT",   1, -1)
    modelBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    modelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)

    -- Item level overlaid at top of portrait (wrapper frame so we can SetFrameLevel; FontString has no SetFrameLevel)
    local avgIlvl = charData and charData.itemLevel or 0
    if avgIlvl > 0 then
        local ilvlFrame = CreateFrame("Frame", nil, card)
        ilvlFrame:SetPoint("TOP", centerRef, "TOP", 0, -6)
        ilvlFrame:SetSize(120, 24)
        if ilvlFrame.SetFrameLevel and centerRef.GetFrameLevel then
            ilvlFrame:SetFrameLevel(centerRef:GetFrameLevel() + 10)
        end
        local ilvlOverlay = ilvlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        ilvlOverlay:SetPoint("CENTER", 0, 0)
        ilvlOverlay:SetJustifyH("CENTER")
        ilvlOverlay:SetTextColor(1, 0.9, 0)
        ilvlOverlay:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " iLvl")
        ilvlOverlay:SetShadowOffset(1, -1)
        ilvlOverlay:SetShadowColor(0, 0, 0, 1)
    end

    -- Karakter adı model alanının içinde, altta modelin üzerinde
    local displayName = (charData and charData.name) or ""
    if displayName ~= "" then
        local nameFrame = CreateFrame("Frame", nil, card)
        nameFrame:SetPoint("BOTTOM", centerRef, "BOTTOM", 0, 8)
        nameFrame:SetSize(MODEL_W, P(28))
        if nameFrame.SetFrameLevel and centerRef.GetFrameLevel then
            nameFrame:SetFrameLevel(centerRef:GetFrameLevel() + 10)
        end
        local nameLabel = FontManager:CreateFontString(nameFrame, "header", "OVERLAY")
        nameLabel:SetPoint("CENTER", 0, 0)
        nameLabel:SetJustifyH("CENTER")
        local classHex = GetClassHex(classFile)
        nameLabel:SetText("|cff" .. classHex .. displayName .. "|r")
        nameLabel:SetShadowOffset(1, -1)
        nameLabel:SetShadowColor(0, 0, 0, 1)
    end
end

-- Shared icon paths (used by equipment card)
local UPGRADE_ICON = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local LOCK_ICON    = "Interface\\Common\\LockIcon"

--- Full-width Equipped gear card: paperdoll left/center, crests on the right. Returns new yOffset.
--- charKey: key from dropdown (used for currency/gold lookup; GetGearUpgradeCurrenciesFromDB tries canonical + this).
--- isCurrentChar: true if selected character is the logged-in one (model vs class portrait).
local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar)
    local rowStep = SLOT_SIZE + SLOT_GAP
    local numRightRows = 8
    local MODEL_H_DEFAULT = (numRightRows - 1) * rowStep + SLOT_SIZE
    local leftH = DOLL_PAD + 8 * rowStep + SLOT_SIZE + 8 + MODEL_H_DEFAULT + 40
    local currencies = (WarbandNexus.GetGearUpgradeCurrenciesFromDB and WarbandNexus:GetGearUpgradeCurrenciesFromDB(charKey)) or {}
    local currencyIconSize = 22
    local rowH = 26
    local currenciesH = 16 + #currencies * rowH
    local cardH = CARD_PAD + math.max(leftH, currenciesH) + CARD_PAD

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", -SIDE_MARGIN, yOffset)

    local sectionLabel = FontManager:CreateFontString(card, "small", "OVERLAY")
    sectionLabel:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    sectionLabel:SetText("|cffcccccc" .. "Equipped Gear" .. "|r")

    DrawPaperDollInCard(card, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true)

    -- Sağ: crest/gold ikon + isim + miktar (DB'den, API yok)
    local currencyPanelW = 240
    local rightPanel = CreateFrame("Frame", nil, card)
    rightPanel:SetWidth(currencyPanelW)
    rightPanel:SetHeight(currenciesH)
    rightPanel:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_PAD - 2)

    local curY = -2
    for _, cur in ipairs(currencies) do
        local ico = rightPanel:CreateTexture(nil, "ARTWORK")
        ico:SetSize(currencyIconSize, currencyIconSize)
        ico:SetPoint("TOPLEFT", 0, curY)
        ico:SetTexture(cur.icon or "Interface\\Icons\\INV_Misc_Coin_01")
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local nameStr = (cur.name and cur.name ~= "") and cur.name or (cur.isGold and "Gold" or "")
        local textW = currencyPanelW - currencyIconSize - 14
        local nameText = FontManager:CreateFontString(rightPanel, "small", "OVERLAY")
        nameText:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        nameText:SetWidth(textW)
        nameText:SetJustifyH("LEFT")
        nameText:SetNonSpaceWrap(false)
        nameText:SetText("|cffb0b0b0" .. (nameStr or "") .. "|r")

        local amountText = FontManager:CreateFontString(rightPanel, "small", "OVERLAY")
        amountText:SetPoint("LEFT", ico, "RIGHT", 6, -12)
        amountText:SetWidth(textW)
        amountText:SetJustifyH("LEFT")
        if cur.isGold then
            local copper = (cur.amount or 0) * 10000 + (cur.silver or 0) * 100 + (cur.copper or 0)
            amountText:SetText(FormatGold and FormatGold(copper) or (tostring(cur.amount or 0) .. "g"))
            amountText:SetTextColor(1, 0.85, 0.4)
        else
            local amt = cur.amount or 0
            amountText:SetText("|cffffd700" .. (FormatNumber and FormatNumber(amt) or tostring(amt)) .. "|r")
        end
        curY = curY - rowH
    end

    card:Show()
    return yOffset - cardH - 12
end

-- ============================================================================
-- EQUIPMENT CARD  (item icon | slot name | item name | ilvl | upgrade status)
-- ============================================================================

local SLOT_ROW_H = 28
local ICON_SIZE  = 20   -- item icon in each row

-- Column right-edge offsets (from card TOPRIGHT, negative = inward)
local COL_STATUS_RIGHT = -8    -- status text right edge
local COL_ILVL_RIGHT   = -208  -- ilvl label right edge
local COL_NAME_RIGHT   = -265  -- item name right edge (leaves room for ilvl+status)

local function DrawEquipmentCard(parent, yOffset, gearData, charKey, upgradeInfo, currencyAmounts)
    local slotCount  = GEAR_SLOTS and #GEAR_SLOTS or 16
    -- column header row (20px) + separator (1px) + slot rows
    local contentH   = 20 + 4 + slotCount * (SLOT_ROW_H + 2) + 8
    local cardH      = CARD_PAD + 22 + contentH + CARD_PAD

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT",  SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", -SIDE_MARGIN, yOffset)

    -- Section header
    local sectionLabel = FontManager:CreateFontString(card, "small", "OVERLAY")
    sectionLabel:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    sectionLabel:SetText("|cffcccccc" .. "Equipment Status" .. "|r")

    -- Column headers
    local colY = -CARD_PAD - 18
    local colHdr = CreateFrame("Frame", nil, card)
    colHdr:SetHeight(16)
    colHdr:SetPoint("TOPLEFT",  CARD_PAD, colY)
    colHdr:SetPoint("TOPRIGHT", -CARD_PAD, colY)

    local hdrSlot = FontManager:CreateFontString(colHdr, "tiny", "OVERLAY")
    hdrSlot:SetPoint("LEFT", ICON_SIZE + 4, 0)
    hdrSlot:SetText("|cff999999SLOT|r")

    local hdrItem = FontManager:CreateFontString(colHdr, "tiny", "OVERLAY")
    hdrItem:SetPoint("LEFT", ICON_SIZE + 68, 0)
    hdrItem:SetText("|cff999999ITEM|r")

    local hdrIlvl = FontManager:CreateFontString(colHdr, "tiny", "OVERLAY")
    hdrIlvl:SetPoint("RIGHT", COL_ILVL_RIGHT + 10, 0)
    hdrIlvl:SetJustifyH("RIGHT")
    hdrIlvl:SetText("|cff999999iLVL|r")

    local hdrStatus = FontManager:CreateFontString(colHdr, "tiny", "OVERLAY")
    hdrStatus:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
    hdrStatus:SetJustifyH("RIGHT")
    hdrStatus:SetText("|cff999999STATUS|r")

    -- Separator line
    local sep = card:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  CARD_PAD, colY - 18)
    sep:SetPoint("TOPRIGHT", -CARD_PAD, colY - 18)
    sep:SetColorTexture(0.25, 0.25, 0.30, 0.6)

    local slots  = gearData and gearData.slots or {}
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }

    local y = colY - 22   -- below column headers + separator
    for _, slotDef in ipairs(GEAR_SLOTS or {}) do
        local slotID   = slotDef.id
        local slotData = slots[slotID]
        local upInfo   = upgradeInfo and upgradeInfo[slotID]

        local canUpgradeThis  = upInfo and upInfo.canUpgrade
        local notUpgradeable  = (slotData and slotData.notUpgradeable) or (upInfo and upInfo.notUpgradeable)
        local isAtMax         = upInfo and not upInfo.canUpgrade and (upInfo.maxUpgrade or 0) > 0
        local canAfford       = canUpgradeThis and CanAffordUpgrade(upInfo.costs, currencyAmounts) or false

        local row = CreateFrame("Button", nil, card, "BackdropTemplate")
        row:SetHeight(SLOT_ROW_H)
        row:SetPoint("TOPLEFT",  CARD_PAD, y)
        row:SetPoint("TOPRIGHT", -CARD_PAD, y)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

        if canUpgradeThis then
            -- Upgradable: green tint when affordable, orange when can't afford
            if canAfford then
                row:SetBackdropColor(0.04, 0.09, 0.05, 0.6)
                row:SetBackdropBorderColor(0.15, 0.45, 0.18, 0.7)
            else
                row:SetBackdropColor(0.09, 0.07, 0.03, 0.6)
                row:SetBackdropBorderColor(0.45, 0.32, 0.10, 0.7)
            end
        elseif isAtMax then
            -- At max upgrade: subtle blue-green
            row:SetBackdropColor(0.03, 0.07, 0.09, 0.6)
            row:SetBackdropBorderColor(0.10, 0.35, 0.45, 0.7)
        else
            row:SetBackdropColor(0.04, 0.04, 0.06, 0.5)
            row:SetBackdropBorderColor(accent[1]*0.15, accent[2]*0.15, accent[3]*0.15, 0.45)
        end

        -- ── Item icon ──────────────────────────────────────────────────────
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_SIZE, ICON_SIZE)
        iconTex:SetPoint("LEFT", 2, 0)
        if slotData and slotData.itemLink then
            local icon = GetItemIconSafe(slotData.itemLink)
            if icon then
                iconTex:SetTexture(icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                iconTex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
                iconTex:SetTexCoord(0, 1, 0, 1)
            end
        else
            iconTex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
            iconTex:SetTexCoord(0, 1, 0, 1)
            iconTex:SetVertexColor(0.4, 0.4, 0.4)
        end

        -- ── Slot label (e.g. "Head", "Main Hand") ──────────────────────────
        local slotLabel = FontManager:CreateFontString(row, "small", "OVERLAY")
        slotLabel:SetPoint("LEFT", ICON_SIZE + 4, 0)
        slotLabel:SetWidth(60)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetText("|cffffffff" .. (slotDef.label or "") .. "|r")

        -- ── Item name (quality colored) ────────────────────────────────────
        local nameLabel = FontManager:CreateFontString(row, "small", "OVERLAY")
        nameLabel:SetPoint("LEFT",  ICON_SIZE + 68, 0)
        nameLabel:SetPoint("RIGHT", COL_NAME_RIGHT,  0)
        nameLabel:SetJustifyH("LEFT")
        nameLabel:SetNonSpaceWrap(false)
        if slotData and slotData.itemLink then
            local itemName = (slotData.name and slotData.name ~= "") and slotData.name or "Unknown"
            local hex = GetQualityHex and GetQualityHex(slotData.quality or 0) or "ffffff"
            nameLabel:SetText("|cff" .. hex .. itemName .. "|r")
        else
            nameLabel:SetText("|cff555555— empty —|r")
        end

        -- ── iLvl ──────────────────────────────────────────────────────────
        local ilvlLabel = FontManager:CreateFontString(row, "small", "OVERLAY")
        ilvlLabel:SetPoint("RIGHT", COL_ILVL_RIGHT, 0)
        ilvlLabel:SetJustifyH("RIGHT")
        ilvlLabel:SetWidth(40)
        local ilvl = slotData and slotData.itemLevel or 0
        if ilvl > 0 then
            ilvlLabel:SetText(ColoredIlvl(ilvl, slotData and slotData.quality or 0))
        else
            ilvlLabel:SetText("")
        end

        -- ── Status (right-aligned): track X/Y | MAX | lock | — ────────────
        local statusText = FontManager:CreateFontString(row, "small", "OVERLAY")
        statusText:SetJustifyH("RIGHT")
        statusText:SetWidth(150)
        statusText:SetNonSpaceWrap(false)

        if canUpgradeThis then
            local track  = (upInfo.trackName and upInfo.trackName ~= "") and upInfo.trackName or ""
            local curT   = upInfo.currUpgrade or 0
            local maxT   = upInfo.maxUpgrade  or 0
            if canAfford then
                -- Affordable: bright green + vault upgrade icon
                statusText:SetPoint("RIGHT", COL_STATUS_RIGHT - 18, 0)
                statusText:SetText(format("|cff33dd55%s %d/%d|r", track, curT, maxT))
                local arrow = row:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(14, 14)
                arrow:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
                if arrow.SetAtlas then
                    arrow:SetAtlas("loottoast-arrow-green", false)
                else
                    arrow:SetTexture(UPGRADE_ICON)
                    arrow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    arrow:SetVertexColor(0.2, 1, 0.25)
                end
            else
                -- Can upgrade but can't afford: yellow
                statusText:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
                statusText:SetText(format("|cffddaa33%s %d/%d|r", track, curT, maxT))
            end
        elseif isAtMax then
            -- Fully upgraded: green "MAX" badge
            local track = (upInfo.trackName and upInfo.trackName ~= "") and upInfo.trackName or ""
            local maxT  = upInfo.maxUpgrade or 0
            statusText:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
            statusText:SetText(format("|cff00ff88%s %d/%d|r", track, maxT, maxT))
        elseif notUpgradeable and slotData and slotData.itemLink then
            -- Confirmed not part of upgrade system: lock icon + label
            statusText:SetPoint("RIGHT", COL_STATUS_RIGHT - 16, 0)
            statusText:SetText("|cff888888Not upgradeable|r")
            local lockTex = row:CreateTexture(nil, "OVERLAY")
            lockTex:SetSize(12, 12)
            lockTex:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
            lockTex:SetTexture(LOCK_ICON)
            lockTex:SetVertexColor(0.5, 0.5, 0.5, 0.9)
        else
            -- No data (alt char not yet scanned, or empty slot)
            statusText:SetPoint("RIGHT", COL_STATUS_RIGHT, 0)
            statusText:SetText(slotData and slotData.itemLink and "|cff777777—|r" or "")
        end

        -- Tooltip
        local itemLink = slotData and slotData.itemLink
        row:SetScript("OnEnter", function(self)
            if itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Hover
        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.06)

        y = y - (SLOT_ROW_H + 2)
    end

    card:Show()
    return yOffset - cardH - 12
end

-- ============================================================================
-- STORAGE UPGRADES SECTION
-- ============================================================================

local function DrawStorageSection(parent, yOffset, storageFinds, gearData)
    local COLORS = ns.UI_COLORS
    local accent = COLORS.accent

    -- Collapsible header
    local headerHeight = HEADER_H
    local header = CreateCollapsibleHeader(
        parent,
        (ns.L and ns.L["GEAR_SECTION_STORAGE"]) or "Storage Upgrades",
        "gear_storage",
        sectionExpanded.storage,
        function(expanded)
            sectionExpanded.storage = expanded
            if WarbandNexus and WarbandNexus.PopulateContent then
                WarbandNexus:PopulateContent()
            end
        end
    )
    header:SetPoint("TOPLEFT",  SIDE_MARGIN, yOffset)
    header:SetPoint("TOPRIGHT", -SIDE_MARGIN, yOffset)
    yOffset = yOffset - headerHeight - 6

    if not sectionExpanded.storage then return yOffset end

    local slots = gearData and gearData.slots or {}
    local hasAny = false

    -- Iterate slots in display order
    for _, slotDef in ipairs(GEAR_SLOTS) do
        local slotID      = slotDef.id
        local candidates  = storageFinds[slotID]
        if candidates and #candidates > 0 then
            hasAny = true

            -- Slot header row
            local slotHeaderRow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            slotHeaderRow:SetHeight(32)
            slotHeaderRow:SetPoint("TOPLEFT",  SIDE_MARGIN + 12, yOffset)
            slotHeaderRow:SetPoint("TOPRIGHT", -SIDE_MARGIN - 12, yOffset)
            slotHeaderRow:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            slotHeaderRow:SetBackdropColor(accent[1]*0.12, accent[2]*0.12, accent[3]*0.12, 0.8)
            slotHeaderRow:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.6)

            -- Slot name + currently equipped ilvl (clear "Change gear" context)
            local equippedData = slots[slotID]
            local currentIlvl  = equippedData and equippedData.itemLevel or 0

            local slotTitle = FontManager:CreateFontString(slotHeaderRow, "body", "OVERLAY")
            slotTitle:SetPoint("LEFT", 8, 0)
            local equippedStr = currentIlvl > 0
                and ("|cffaaaaaa" .. currentIlvl .. " equipped|r")
                or  "|cff666666empty|r"
            slotTitle:SetText(
                "|cff" .. ((COLORS.accent and format("%02x%02x%02x",
                    math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255))) or "aaaaff")
                .. slotDef.label .. "|r  " .. equippedStr
            )

            yOffset = yOffset - 34 - 4

            -- Candidate rows (first = best by ilvl; show Warbound/BoE badges)
            for candidateIdx, candidate in ipairs(candidates) do
                local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
                row:SetHeight(32)
                row:SetPoint("TOPLEFT",  SIDE_MARGIN + 16, yOffset)
                row:SetPoint("TOPRIGHT", -SIDE_MARGIN - 12, yOffset)
                row:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                local isBest = (candidateIdx == 1)
                if isBest then
                    row:SetBackdropColor(accent[1]*0.08, accent[2]*0.08, accent[3]*0.08, 0.75)
                    row:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.6)
                else
                    row:SetBackdropColor(0.04, 0.04, 0.06, 0.6)
                    row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.4)
                end

                local icon = GetItemIconSafe(candidate.itemID or candidate.itemLink)
                local iconTex = row:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(22, 22)
                iconTex:SetPoint("LEFT", 4, 0)
                if icon then
                    iconTex:SetTexture(icon)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                -- Equipped → candidate ilvl in one clear line (e.g. "230 → 240")
                local upgradeLineStr
                if currentIlvl > 0 then
                    upgradeLineStr = format("|cff888888%d|r → %s", currentIlvl, ColoredIlvl(candidate.itemLevel, candidate.quality))
                else
                    upgradeLineStr = ColoredIlvl(candidate.itemLevel, candidate.quality)
                end
                local ilvlLabel = FontManager:CreateFontString(row, "body", "OVERLAY")
                ilvlLabel:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                ilvlLabel:SetText(upgradeLineStr)

                -- Delta (e.g. "+10") next to the arrow
                local delta = candidate.itemLevel - currentIlvl
                if delta > 0 and currentIlvl > 0 then
                    local deltaLabel = FontManager:CreateFontString(row, "small", "OVERLAY")
                    deltaLabel:SetPoint("LEFT", ilvlLabel, "RIGHT", 4, 0)
                    deltaLabel:SetText("|cff00ff00(+" .. delta .. ")|r")
                end

                -- Right side: Best badge (slot best), Warbound/BoE badge, then source
                local sourceColor = SOURCE_TYPE_COLOR[candidate.sourceType] or { 0.7, 0.7, 0.7 }
                local sourceLabel = FontManager:CreateFontString(row, "small", "OVERLAY")
                sourceLabel:SetPoint("RIGHT", -6, 0)
                sourceLabel:SetText(format("|cff%s%s|r",
                    format("%02x%02x%02x", math.floor(sourceColor[1]*255), math.floor(sourceColor[2]*255), math.floor(sourceColor[3]*255)),
                    candidate.source or ""))
                local sourceW = sourceLabel:GetStringWidth() or 60
                local rightX = -6 - sourceW - 6

                -- Warbound / BoE badge (small pill)
                local badgeText = nil
                local badgeR, badgeG, badgeB = 0.7, 0.7, 0.7
                if candidate.sourceType == "warband" then
                    badgeText = (ns.L and ns.L["GEAR_STORAGE_WARBOUND"]) or "Warbound"
                    badgeR, badgeG, badgeB = 0.35, 0.75, 1.0
                elseif candidate.sourceType == "char_bag" or candidate.sourceType == "char_bank" then
                    badgeText = (ns.L and ns.L["GEAR_STORAGE_BOE"]) or "BoE"
                    badgeR, badgeG, badgeB = 1.0, 0.55, 0.2
                end
                if badgeText then
                    local badge = FontManager:CreateFontString(row, "tiny", "OVERLAY")
                    badge:SetPoint("RIGHT", rightX, 0)
                    badge:SetText(format("|cff%02x%02x%02x[%s]|r", math.floor(badgeR*255), math.floor(badgeG*255), math.floor(badgeB*255), badgeText))
                    rightX = rightX - (badge:GetStringWidth() or 40) - 4
                end

                -- Best candidate badge (first in slot)
                if isBest then
                    local bestLabel = FontManager:CreateFontString(row, "tiny", "OVERLAY")
                    bestLabel:SetPoint("RIGHT", rightX, 0)
                    bestLabel:SetText(format("|cff%02x%02x%02x%s|r", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255), (ns.L and ns.L["GEAR_STORAGE_BEST"]) or "Best"))
                end

                -- Tooltip
                local itemLink = candidate.itemLink
                row:SetScript("OnEnter", function(self)
                    if itemLink then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(itemLink)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Hover highlight
                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints()
                hi:SetColorTexture(1, 1, 1, 0.07)

                yOffset = yOffset - 34 - 4
            end

            yOffset = yOffset - 8
        end
    end

    yOffset = yOffset - 8
    return yOffset
end

-- ============================================================================
-- CHARACTER SELECTOR  (dropdown button)
-- ============================================================================

local function CreateCharacterSelector(parent, currentCharKey, yOffset)
    local chars  = GetTrackedCharacters()
    if #chars == 0 then return nil, yOffset end

    local COLORS = ns.UI_COLORS
    local accent = COLORS.accent
    local PAD    = 8

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(36)
    btn:SetWidth(260)
    btn:SetPoint("RIGHT", parent, "RIGHT", -SIDE_MARGIN - PAD, 0)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
    btn:SetBackdropBorderColor(accent[1]*0.6, accent[2]*0.6, accent[3]*0.6, 0.8)

    local label = FontManager:CreateFontString(btn, "small", "OVERLAY")
    label:SetPoint("LEFT",  6, 0)
    label:SetPoint("RIGHT", -20, 0)
    label:SetJustifyH("LEFT")

    -- Arrow icon
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    local function SetLabelToChar(charKey)
        local db    = WarbandNexus.db and WarbandNexus.db.global
        local cData = db and db.characters and db.characters[charKey]
        if cData and (cData.name and cData.name ~= "") then
            local hex   = GetClassHex(cData.classFile)
            local text  = "|cff" .. hex .. cData.name .. "|r"
            local realm = cData.realm
            if realm and realm ~= "" then text = text .. " |cff555555(" .. realm .. ")|r" end
            label:SetText(text)
        elseif charKey and charKey ~= "" then
            label:SetText(charKey)
        else
            label:SetText("")
        end
    end

    SetLabelToChar(currentCharKey)

    -- Dropdown menu (parent UIParent so not clipped by scroll; position from button)
    btn:SetScript("OnClick", function(self)
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(500)
        menu:SetWidth(220)
        menu:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        menu:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
        menu:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.9)

        -- Close on outside click
        local bg = CreateFrame("Button", nil, UIParent)
        bg:SetAllPoints()
        bg:SetFrameStrata("FULLSCREEN_DIALOG")
        bg:SetFrameLevel(499)
        bg:SetScript("OnClick", function()
            menu:Hide()
            bg:Hide()
            if WarbandNexus and WarbandNexus.PopulateContent then
                WarbandNexus:PopulateContent()
            end
        end)
        bg:Show()

        local menuH = #chars * 26 + 8
        menu:SetHeight(menuH)
        menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)

        local entryY = -4
        for _, charEntry in ipairs(chars) do
            local entryBtn = CreateFrame("Button", nil, menu)
            entryBtn:SetHeight(24)
            entryBtn:SetPoint("TOPLEFT",  4, entryY)
            entryBtn:SetPoint("TOPRIGHT", -4, entryY)

            local entryLabel = FontManager:CreateFontString(entryBtn, "small", "OVERLAY")
            entryLabel:SetPoint("LEFT", 4, 0)
            entryLabel:SetPoint("RIGHT", -4, 0)
            entryLabel:SetJustifyH("LEFT")

            local cKey   = charEntry.key
            local cData  = charEntry.data
            local hex    = GetClassHex(cData.classFile)
            entryLabel:SetText("|cff" .. hex .. (cData.name or cKey) .. "|r"
                .. " |cff444444" .. (cData.realm or "") .. "|r")

            -- Highlight current selection
            if cKey == currentCharKey then
                entryLabel:SetTextColor(accent[1] + 0.2, accent[2] + 0.2, accent[3] + 0.2)
            end

            local entryHi = entryBtn:CreateTexture(nil, "HIGHLIGHT")
            entryHi:SetAllPoints()
            entryHi:SetColorTexture(1, 1, 1, 0.1)

            entryBtn:SetScript("OnClick", function()
                -- #region agent log
                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
                    print("|cff00ff00[WN Gear]|r selector click cKey=" .. tostring(cKey) .. " len=" .. tostring(cKey and #cKey or 0))
                end
                -- #endregion
                selectedCharKey = cKey
                SetLabelToChar(cKey)
                menu:Hide()
                bg:Hide()
                if WarbandNexus then
                    WarbandNexus:RefreshUI()
                    if WarbandNexus.PopulateContent then
                        WarbandNexus:PopulateContent()
                    end
                end
            end)

            entryY = entryY - 26
        end

        menu:Show()
    end)

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(accent[1]*0.6, accent[2]*0.6, accent[3]*0.6, 0.8)
    end)

    return btn, yOffset
end

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================

function WarbandNexus:DrawGearTab(parent)
    RegisterGearEvents()

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

    local yOffset    = -TOP_MARGIN
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
        local height = DrawEmptyState and DrawEmptyState(parent,
            "No tracked characters",
            "Log in to a character to start tracking gear.") or 200
        return height
    end

    -- ── Header Card ───────────────────────────────────────────────────────────
    local headerCard = CreateCard(parent, 80)
    headerCard:SetPoint("TOPLEFT",  SIDE_MARGIN, yOffset)
    headerCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, yOffset)

    local headerIcon = CreateHeaderIcon and CreateHeaderIcon(headerCard, GetTabIcon and GetTabIcon("gear") or nil)

    local r, g, b = accent[1], accent[2], accent[3]
    local hexAcc  = format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local titleText = FontManager:CreateFontString(headerCard, "header", "OVERLAY")
    titleText:SetText("|cff" .. hexAcc .. ((ns.L and ns.L["GEAR_TAB_TITLE"]) or "Gear Management") .. "|r")
    titleText:SetJustifyH("LEFT")
    if headerIcon then
        titleText:SetPoint("TOPLEFT", headerIcon.border, "TOPRIGHT", 10, -4)
    else
        titleText:SetPoint("TOPLEFT", 12, -12)
    end

    local subText = FontManager:CreateFontString(headerCard, "subtitle", "OVERLAY")
    subText:SetText((ns.L and ns.L["GEAR_TAB_DESC"]) or "Equipment viewer, upgrade analysis, and cross-character storage finder")
    subText:SetTextColor(0.6, 0.6, 0.6)
    subText:SetJustifyH("LEFT")
    subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -3)
    subText:SetPoint("RIGHT", headerCard, "RIGHT", -270, 0)

    -- Character selector: large, right-centered vertically in header
    CreateCharacterSelector(headerCard, charKey, 0)
    headerCard:Show()

    yOffset = yOffset - 88 - 12  -- card height + gap

    -- ── Data retrieval (all by canonical key) ──────────────────────────────────
    local db        = self.db and self.db.global
    local charData  = db and (db.characters[canonicalKey] or db.characters[charKey])
    local gearData  = (self.GetEquippedGear and self:GetEquippedGear(canonicalKey)) or nil
    -- #region agent log
    do
        local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or ""
        if self.db and self.db.profile and self.db.profile.debugMode then
            local hasChar = (charData ~= nil) and "yes" or "no"
            local keysMatch = (canonicalKey == currentKey) and "yes" or "no"
            print("|cff00ff00[WN Gear]|r charKey=[" .. tostring(charKey) .. "] canonicalKey=[" .. tostring(canonicalKey) .. "] hasCharData=" .. hasChar .. " exactMatch=" .. keysMatch)
        end
    end
    -- #endregion

    local currentKey = (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
    local upgradeInfo = {}
    if canonicalKey == currentKey then
        upgradeInfo = (self.GetGearUpgradeInfo and self:GetGearUpgradeInfo()) or {}
    else
        upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canonicalKey)) or {}
    end

    local currencyAmounts = BuildCurrencyAmountMap(charKey)

    yOffset = DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, canonicalKey == currentKey)
    yOffset = DrawEquipmentCard(parent, yOffset, gearData, canonicalKey, upgradeInfo, currencyAmounts)
    local storageFinds = (self.FindGearStorageUpgrades and self:FindGearStorageUpgrades(canonicalKey)) or {}
    yOffset = DrawStorageSection(parent, yOffset, storageFinds, gearData)

    yOffset = yOffset - 12
    return math.abs(yOffset) + TOP_MARGIN
end
