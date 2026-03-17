--[[
    Warband Nexus - Gear Management Tab
    Paperdoll with Midnight Dawncrests and upgrade analysis.

    Layout:
    ┌────────────────────────────────────────────────────────────────────────────┐
    │ [Header: Title + Character Selector ▼]                                      │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Paperdoll — Slot icons (left/right/bottom) + portrait (center) + crests    │
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
local CreateHeaderIcon    = ns.UI_CreateHeaderIcon
local GetTabIcon          = ns.UI_GetTabIcon
local ShowTooltip         = ns.UI_ShowTooltip
local HideTooltip         = ns.UI_HideTooltip

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

local function GetLayout() return ns.UI_LAYOUT or {} end
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
-- Slot–ok arası eski konum; ok–yazı arası: daha negatif = yazı daha içeri (ikona yakın)
local SLOT_TO_ARROW_GAP = P(4)   -- slot ile upgrade ikonu arası (eski değer)
local ARROW_TO_TEXT_GAP = -8     -- yazılar içeri kaydırıldı (sol: sağa, sağ: sola)
local TRACK_TEXT_W   = P(136)  -- Track metin taşmasını engellemek için genişletildi
local UPGRADE_ARROW_W = P(16)
local CURRENCY_PANEL_W = 240
local CENTER_GAP     = P(10)
local CURRENCY_PAPERDOLL_GAP = 14  -- boşluk crest paneli ile paperdoll arası

-- Fixed panel widths: sol = yazı + ikon + slot, sağ = slot + ikon + yazı
local LEFT_PANEL_W   = TRACK_TEXT_W + ARROW_TO_TEXT_GAP + UPGRADE_ARROW_W + SLOT_TO_ARROW_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_ARROW_GAP + UPGRADE_ARROW_W + 2 + ARROW_TO_TEXT_GAP + TRACK_TEXT_W
local MODEL_W       = P(228)
-- Paperdoll blok genişliği (sol kolon + model + sağ kolon) — kart içinde ortalanır
local PAPERDOLL_BLOCK_W = LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP + RIGHT_PANEL_W

-- Minimum card inner width (currency + gaps + paperdoll block + stats) — layout bu genişliğin altına inmez
local MIN_CARD_INNER_W = CURRENCY_PANEL_W + CURRENCY_PAPERDOLL_GAP * 2 + PAPERDOLL_BLOCK_W + 260
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
---@return Frame btn
local function CreateSlotButton(parent, slotID, slotData, x, y, isUpgradable, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon, upgradeInfo, currencyAmounts)
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

    -- Tooltip: item link + simplified upgrade info (custom tooltip service)
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            local up = upgradeInfo and upgradeInfo[slotID]
            local additionalLines = {}
            if up and up.canUpgrade then
                local affordable, goldOnly = CalculateAffordableUpgrades(up, currencyAmounts)
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                if affordable > 0 then
                    -- Show achievable target only (e.g. 2/6 when 20 crests and 1/6 — not 6/6).
                    local targetTier = (up.currUpgrade or 0) + affordable
                    local TRACK_ILVLS = ns.TRACK_ILVLS
                    local targetIlvl = TRACK_ILVLS and TRACK_ILVLS[up.trackName] and TRACK_ILVLS[up.trackName][targetTier]
                    local ilvlStr = targetIlvl and format(" (%d)", targetIlvl) or ""
                    additionalLines[#additionalLines + 1] = {
                        text = format("Available upgrade to %s %d/%d%s", up.trackName or "", targetTier, up.maxUpgrade or 0, ilvlStr),
                        color = { 0.4, 1, 0.4 }
                    }
                    additionalLines[#additionalLines + 1] = {
                        text = format("%d upgrade(s) with current currency", affordable),
                        color = { 0.6, 0.9, 0.6 }
                    }
                    if goldOnly > 0 then
                        if goldOnly >= affordable then
                            additionalLines[#additionalLines + 1] = {
                                text = "Crests needed: 0 (gold only — previously reached)",
                                color = { 1, 0.85, 0.4 }
                            }
                        else
                            additionalLines[#additionalLines + 1] = {
                                text = format("%d upgrade(s) gold only (previously reached)", goldOnly),
                                color = { 1, 0.85, 0.4 }
                            }
                        end
                    end
                else
                    additionalLines[#additionalLines + 1] = {
                        text = format("%s %d/%d — need more crests", up.trackName or "", up.currUpgrade or 0, up.maxUpgrade or 0),
                        color = { 0.8, 0.5, 0.2 }
                    }
                end
            end
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    anchor = "ANCHOR_RIGHT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    anchor = "ANCHOR_RIGHT",
                })
            end
        else
            local title = (slotDef and slotDef.label) or "Empty"
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                    anchor = "ANCHOR_RIGHT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
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

--- Build track/tier string from upgradeInfo[slotID], e.g. "Veteran 2/6".
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
--- baseX: paperdoll bloğunun sol kenarı (kart içinde crest panelinden sonra ortalanmış alan).
local function DrawPaperDollInCard(card, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar, baseX)
    baseX = baseX or CARD_PAD
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

    local startY = -(CARD_PAD + 24)
    local rowStep = SLOT_SIZE + SLOT_GAP

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i, slotID in ipairs(leftSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), leftX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts)
    end

    -- Right column: 6 armor + 2 trinkets — slot | ikon | yazı
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i, slotID in ipairs(rightSlots) do
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), rightX, startY - (i - 1) * rowStep, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts)
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
        CreateSlotButton(card, slotID, GetSlotData(slotID), wx, bottomY, IsUpgradable(slotID), GetSlotTrackText(upgradeInfo, slotID, quality), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W, nil, upgradeInfo, currencyAmounts)
    end

    -- Orta panel: model frame alt ucu trinket satırının altına denk gelecek şekilde uzatıldı
    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- trinket altına kadar
    local classFile = charData and charData.classFile
    local accent    = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }
    local modelX    = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY

    -- scrollChild is the stable parent — model is parented here once and NEVER
    -- re-parented. Re-parenting a PlayerModel resets WoW's internal renderer
    -- causing the "slide up from bottom" animation on every refresh.
    -- The model is positioned by anchoring to the card (which is recreated each
    -- refresh) — anchor changes don't trigger animation restarts.
    local scrollParent = card:GetParent()

    local centerRef = nil
    if isCurrentChar == true then
        local model = ns._gearPlayerModel
        if not model then
            local ok, m = pcall(function()
                local f = CreateFrame("PlayerModel", nil, scrollParent)
                if f.SetKeepModelOnHide then f:SetKeepModelOnHide(true) end
                return f
            end)
            if ok and m then
                model = m
                model.isPersistentRowElement = true
                ns._gearPlayerModel = model
            end
        end
        if model then
            -- Ensure stable parent (scrollChild) — NEVER re-parent to card
            if model:GetParent() ~= scrollParent then
                model:SetParent(scrollParent)
            end
            model:ClearAllPoints()
            model:SetSize(MODEL_W, MODEL_H)
            -- Anchor TO the card so model scrolls with it, without being its child
            model:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
            model:SetFrameLevel(card:GetFrameLevel() + 5)
            model:SetCamDistanceScale(0.92)
            model:SetPortraitZoom(0.42)
            if not model._unitSet then
                model:SetUnit("player")
                model._unitSet = true
            end
            model:Show()
            centerRef = model
        end
    else
        if ns._gearPlayerModel then
            ns._gearPlayerModel:Hide()
            ns._gearPlayerModel._unitSet = false
        end
    end

    -- Fallback: No Preview (same stable-parent pattern)
    if not centerRef then
        local portrait = ns._gearNoPreviewFrame
        if not portrait then
            portrait = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
            local noPreview = FontManager:CreateFontString(portrait, "header", "OVERLAY")
            noPreview:SetPoint("CENTER", portrait, "CENTER", 0, 0)
            noPreview:SetJustifyH("CENTER")
            noPreview:SetTextColor(0.5, 0.5, 0.55, 1)
            noPreview:SetText("No Preview")
            noPreview:SetShadowOffset(1, -1)
            noPreview:SetShadowColor(0, 0, 0, 0.8)
            portrait.isPersistentRowElement = true
            ns._gearNoPreviewFrame = portrait
        end
        if portrait:GetParent() ~= scrollParent then
            portrait:SetParent(scrollParent)
        end
        portrait:ClearAllPoints()
        portrait:SetSize(MODEL_W, MODEL_H)
        portrait:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        portrait:SetFrameLevel(card:GetFrameLevel() + 5)
        portrait:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        portrait:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        portrait:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)
        portrait:Show()
        centerRef = portrait
    end

    -- Border around model/portrait (parented to card — recycled automatically)
    local modelBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
    modelBorder:SetPoint("TOPLEFT",     centerRef, "TOPLEFT",      -1,  1)
    modelBorder:SetPoint("BOTTOMRIGHT", centerRef, "BOTTOMRIGHT",   1, -1)
    modelBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    modelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)
    modelBorder:SetFrameLevel(centerRef:GetFrameLevel() + 6)

    -- Item level overlaid at top of portrait
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

    -- Karakter adı: container border ile 3D model border arası bandta, yukarıda (kart border'a yakın)
    local displayName = (charData and charData.name) or ""
    if displayName ~= "" then
        local nameWrapper = CreateFrame("Frame", nil, card)
        nameWrapper:SetPoint("TOP", card, "TOP", 0, -CARD_PAD)
        nameWrapper:SetPoint("BOTTOM", centerRef, "TOP", 0, 0)
        nameWrapper:SetPoint("LEFT", centerRef, "LEFT", 0, 0)
        nameWrapper:SetPoint("RIGHT", centerRef, "RIGHT", 0, 0)
        if nameWrapper.SetFrameLevel and card.GetFrameLevel then
            nameWrapper:SetFrameLevel(card:GetFrameLevel() + 100)
        end
        local nameLabel = FontManager:CreateFontString(nameWrapper, "header", "OVERLAY")
        nameLabel:SetPoint("CENTER", nameWrapper, "CENTER", 0, 10)
        nameLabel:SetPoint("LEFT", nameWrapper, "LEFT", 0, 0)
        nameLabel:SetPoint("RIGHT", nameWrapper, "RIGHT", 0, 0)
        nameLabel:SetJustifyH("CENTER")
        local classHex = GetClassHex(classFile)
        nameLabel:SetText("|cff" .. classHex .. displayName .. "|r")
        nameLabel:SetShadowOffset(1, -1)
        nameLabel:SetShadowColor(0, 0, 0, 1)
    end
end

-- ── Stat helpers (live API for current char) ────────────────────────────────
local STAT_IDS = {
    { id = 1, label = "Strength",    icon = "Interface\\Icons\\spell_nature_strength" },
    { id = 2, label = "Agility",     icon = "Interface\\Icons\\ability_backstab" },
    { id = 3, label = "Stamina",     icon = "Interface\\Icons\\spell_holy_wordfortitude" },
    { id = 4, label = "Intellect",   icon = "Interface\\Icons\\spell_holy_magicalsentry" },
}
local SECONDARY_STATS = {
    { label = "Critical Strike", fn = function() return GetCombatRating and GetCombatRating(9) or 0 end,  pctFn = function() return GetCritChance and GetCritChance() or 0 end },
    { label = "Haste",           fn = function() return GetCombatRating and GetCombatRating(18) or 0 end, pctFn = function() return GetHaste and GetHaste() or 0 end },
    { label = "Mastery",         fn = function() return GetCombatRating and GetCombatRating(26) or 0 end, pctFn = function() return GetMasteryEffect and select(1, GetMasteryEffect()) or 0 end },
    { label = "Versatility",     fn = function() return GetCombatRating and GetCombatRating(29) or 0 end, pctFn = function() return GetCombatRatingBonus and GetCombatRatingBonus(29) or 0 end },
}

--- Equipped gear card: 3-panel layout — Currency (left) | Paperdoll (center) | Stats (right).
--- charKey: key from dropdown (used for currency/gold lookup).
--- isCurrentChar: true if selected character is the logged-in one (model vs class portrait).
--- currencies: array from GetGearUpgradeCurrenciesFromDB (passed to avoid duplicate API calls).
local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar, currencies)
    local rowStep = SLOT_SIZE + SLOT_GAP
    local numRightRows = 8
    local MODEL_H_DEFAULT = (numRightRows - 1) * rowStep + SLOT_SIZE
    -- Content height: section + slot columns + gap + weapon row (Main/Off Hand) + bottom pad so card border is below weapons
    local contentTop = CARD_PAD + 24
    local weaponBottom = 8 * rowStep + 8 + SLOT_SIZE
    local paperdollH = contentTop + weaponBottom + CARD_PAD
    currencies = currencies or {}
    local STAT_PANEL_W = 260
    local contentH = paperdollH
    local cardH = CARD_PAD + 24 + contentH + CARD_PAD

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, yOffset)

    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }

    -- ── LEFT PANEL: Upgrade Currencies ──────────────────────────────────────
    local currencyPanelW = CURRENCY_PANEL_W
    local crestCurrencies = {}
    local goldCurrency = nil
    for _, cur in ipairs(currencies) do
        if cur.isGold then goldCurrency = cur else crestCurrencies[#crestCurrencies + 1] = cur end
    end

    -- Currency panel height: header(20) + crests(rows) + divider(12) + gold(24) + pad(8)
    local CREST_ROW_H = 28
    local currenciesH = 24 + #crestCurrencies * CREST_ROW_H + 12 + 28 + 8

    local parentW = (parent and parent.GetWidth) and parent:GetWidth() or 0
    local CARD_PAD_X = 12
    local cardInnerW = 0
    if parentW and parentW > (SIDE_MARGIN * 2) then
        cardInnerW = parentW - (SIDE_MARGIN * 2) - (CARD_PAD_X * 2)
    end
    if cardInnerW <= 0 and card and card.GetWidth then
        cardInnerW = card:GetWidth() - CARD_PAD_X * 2
    end
    -- Layout hiç bu minimumun altına inmesin; dar pencerede içerik taşar, yatay scroll ile görünür
    cardInnerW = math.max(cardInnerW or 0, MIN_CARD_INNER_W)

    local leftPanel = CreateFrame("Frame", nil, card, "BackdropTemplate")
    leftPanel:SetWidth(currencyPanelW)
    leftPanel:SetHeight(currenciesH)
    leftPanel:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD - 22)
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    leftPanel:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
    leftPanel:SetBackdropBorderColor(accent[1] * 0.5, accent[2] * 0.5, accent[3] * 0.5, 0.6)

    -- Panel header (ortalanmış)
    local panelTitle = FontManager:CreateFontString(leftPanel, "header", "OVERLAY")
    panelTitle:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 10, -8)
    panelTitle:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -10, -8)
    panelTitle:SetJustifyH("CENTER")
    panelTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. "Upgrade Currencies|r")
    panelTitle:SetShadowOffset(1, -1)
    panelTitle:SetShadowColor(0, 0, 0, 1)

    -- Crest rows: icon | name ............ amount / cap
    local curY = -28
    local curPad = 10
    local iconSize = 22
    for _, cur in ipairs(crestCurrencies) do
        -- Alternating row bg
        local rowBg = leftPanel:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", 2, curY + 1)
        rowBg:SetPoint("TOPRIGHT", -2, curY + 1)
        rowBg:SetHeight(CREST_ROW_H)
        rowBg:SetColorTexture(1, 1, 1, (_ % 2 == 0) and 0.03 or 0)

        local ico = leftPanel:CreateTexture(nil, "ARTWORK")
        ico:SetSize(iconSize, iconSize)
        ico:SetPoint("TOPLEFT", curPad, curY - (CREST_ROW_H - iconSize) / 2)
        ico:SetTexture(cur.icon or "Interface\\Icons\\INV_Misc_Coin_01")
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Name (left aligned)
        local nameText = FontManager:CreateFontString(leftPanel, "tiny", "OVERLAY")
        nameText:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        nameText:SetTextColor(0.85, 0.85, 0.85)
        -- Shorten name: "Adventurer Dawncrest" → "Adventurer"
        local shortName = (cur.name or ""):match("^(%S+)") or cur.name or ""
        nameText:SetText(shortName)
        nameText:SetShadowOffset(1, -1)
        nameText:SetShadowColor(0, 0, 0, 0.8)

        -- Amount / cap (right aligned); cap from C_CurrencyInfo API (maxWeeklyQuantity/maxQuantity)
        local amt = cur.amount or 0
        local cap = (type(cur.maxQuantity) == "number" and cur.maxQuantity > 0) and cur.maxQuantity or 200
        local amountText = FontManager:CreateFontString(leftPanel, "tiny", "OVERLAY")
        amountText:SetPoint("RIGHT", leftPanel, "RIGHT", -curPad, 0)
        amountText:SetPoint("TOP", ico, "TOP", 0, 0)
        amountText:SetPoint("BOTTOM", ico, "BOTTOM", 0, 0)
        amountText:SetJustifyH("RIGHT")
        amountText:SetShadowOffset(1, -1)
        amountText:SetShadowColor(0, 0, 0, 0.8)
        local capStr = (FormatNumber and FormatNumber(cap) or tostring(cap))
        if amt > 0 then
            amountText:SetText("|cffffffff" .. (FormatNumber and FormatNumber(amt) or tostring(amt)) .. "|r |cff666666/ " .. capStr .. "|r")
        else
            amountText:SetText("|cff555555" .. "0" .. "|r |cff444444/ " .. capStr .. "|r")
        end

        curY = curY - CREST_ROW_H
    end

    -- Divider line
    local divider = leftPanel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", curPad, curY - 4)
    divider:SetPoint("RIGHT", leftPanel, "RIGHT", -curPad, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)

    -- Gold row
    if goldCurrency then
        curY = curY - 14
        local goldIco = leftPanel:CreateTexture(nil, "ARTWORK")
        goldIco:SetSize(iconSize, iconSize)
        goldIco:SetPoint("TOPLEFT", curPad, curY)
        goldIco:SetTexture(goldCurrency.icon or 133784)
        goldIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local goldText = FontManager:CreateFontString(leftPanel, "tiny", "OVERLAY")
        goldText:SetPoint("LEFT", goldIco, "RIGHT", 6, 0)
        goldText:SetTextColor(1, 0.82, 0)
        goldText:SetText("Gold")
        goldText:SetShadowOffset(1, -1)
        goldText:SetShadowColor(0, 0, 0, 0.8)

        local goldAmt = FontManager:CreateFontString(leftPanel, "tiny", "OVERLAY")
        goldAmt:SetPoint("RIGHT", leftPanel, "RIGHT", -curPad, 0)
        goldAmt:SetPoint("TOP", goldIco, "TOP", 0, 0)
        goldAmt:SetPoint("BOTTOM", goldIco, "BOTTOM", 0, 0)
        goldAmt:SetJustifyH("RIGHT")
        goldAmt:SetShadowOffset(1, -1)
        goldAmt:SetShadowColor(0, 0, 0, 0.8)
        local copper = (goldCurrency.amount or 0) * 10000 + (goldCurrency.silver or 0) * 100 + (goldCurrency.copper or 0)
        goldAmt:SetText("|cffffff00" .. (FormatGold and FormatGold(copper) or (tostring(goldCurrency.amount or 0) .. "g")) .. "|r")
    end

    -- ── CENTER: Paperdoll ───────────────────────────────────────────────────
    local middleW = cardInnerW - CURRENCY_PANEL_W - STAT_PANEL_W - (CURRENCY_PAPERDOLL_GAP * 2)
    local middlePad = math.max(0, (middleW - PAPERDOLL_BLOCK_W) / 2)
    local paperdollBaseX = CARD_PAD + CURRENCY_PANEL_W + CURRENCY_PAPERDOLL_GAP + middlePad
    DrawPaperDollInCard(card, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true, paperdollBaseX)

    -- ── RIGHT PANEL: Character Stats ────────────────────────────────────────
    local STAT_ROW_H = 24
    local primaryRows = {}
    local secondaryRows = {}
    if isCurrentChar and UnitStat then
        local mainStat = (WarbandNexus.GetCurrentCharacterMainStat and WarbandNexus:GetCurrentCharacterMainStat()) or nil
        -- Show only main stat (STR/AGI/INT per spec) + Stamina; hide other primary stats
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        for i = 1, #STAT_IDS do
            local stat = STAT_IDS[i]
            if stat.id == 3 then
                -- Always show Stamina
            elseif mainStatId and stat.id ~= mainStatId then
                -- Skip non-main primary (e.g. STR/AGI for Intellect spec)
                stat = nil
            end
            if stat then
                local ok, _, total = pcall(UnitStat, "player", stat.id)
                if ok and total and total > 0 then
                    primaryRows[#primaryRows + 1] = {
                        label = stat.label,
                        value = FormatNumber and FormatNumber(math.floor(total)) or tostring(math.floor(total)),
                    }
                end
            end
        end
        for i = 1, #SECONDARY_STATS do
            local stat = SECONDARY_STATS[i]
            local ok, rating = pcall(stat.fn)
            local ok2, pct = pcall(stat.pctFn)
            if ok and rating and rating > 0 then
                local pctStr = (ok2 and pct) and format("%.1f%%", pct) or ""
                secondaryRows[#secondaryRows + 1] = {
                    label = stat.label,
                    value = pctStr .. "  |cffffffff" .. (FormatNumber and FormatNumber(math.floor(rating)) or tostring(math.floor(rating))) .. "|r",
                }
            end
        end
    elseif not isCurrentChar and charData and charData.stats then
        -- Offline: show persisted stats (saved when character was last online)
        local mainStat = (WarbandNexus.GetCharacterMainStat and WarbandNexus:GetCharacterMainStat(charData)) or nil
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        local prim = charData.stats.primary
        if prim and next(prim) then
            for i = 1, #STAT_IDS do
                local stat = STAT_IDS[i]
                if stat.id == 3 then
                    -- Stamina always
                elseif mainStatId and stat.id ~= mainStatId then
                    stat = nil
                end
                if stat and prim[stat.id] and prim[stat.id] > 0 then
                    primaryRows[#primaryRows + 1] = {
                        label = stat.label,
                        value = FormatNumber and FormatNumber(prim[stat.id]) or tostring(prim[stat.id]),
                    }
                end
            end
        end
        local sec = charData.stats.secondary
        if sec and #sec > 0 then
            for j = 1, #sec do
                local s = sec[j]
                if s and s.label and s.rating and s.rating > 0 then
                    local pctStr = (s.pct and type(s.pct) == "number") and format("%.1f%%", s.pct) or ""
                    secondaryRows[#secondaryRows + 1] = {
                        label = s.label,
                        value = pctStr .. "  |cffffffff" .. (FormatNumber and FormatNumber(s.rating) or tostring(s.rating)) .. "|r",
                    }
                end
            end
        end
    end
    local hasDivider = (#primaryRows > 0 and #secondaryRows > 0)
    local statContentRows = #primaryRows + #secondaryRows
    local statContentH = 32 + (statContentRows * STAT_ROW_H) + (hasDivider and 10 or 0) + 14
    if statContentRows == 0 then
        statContentH = 96
    end
    local statPanelH = math.max(currenciesH, statContentH)

    local statPanel = CreateFrame("Frame", nil, card, "BackdropTemplate")
    statPanel:SetWidth(STAT_PANEL_W)
    statPanel:SetHeight(statPanelH)
    statPanel:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD - 22)
    statPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    statPanel:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
    statPanel:SetBackdropBorderColor(accent[1] * 0.5, accent[2] * 0.5, accent[3] * 0.5, 0.6)

    -- Panel header (ortalanmış)
    local statTitle = FontManager:CreateFontString(statPanel, "header", "OVERLAY")
    statTitle:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 10, -8)
    statTitle:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -10, -8)
    statTitle:SetJustifyH("CENTER")
    statTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. "Character Stats|r")
    statTitle:SetShadowOffset(1, -1)
    statTitle:SetShadowColor(0, 0, 0, 1)

    local statY = -32
    local statPad = 12

    if #primaryRows > 0 or #secondaryRows > 0 then
        for i = 1, #primaryRows do
            local stat = primaryRows[i]
            local row = FontManager:CreateFontString(statPanel, "tiny", "OVERLAY")
            row:SetPoint("TOPLEFT", statPad, statY)
            row:SetWidth(118)
            row:SetWordWrap(false)
            row:SetJustifyH("LEFT")
            row:SetTextColor(0.75, 0.8, 0.9)
            row:SetText(stat.label)
            row:SetShadowOffset(1, -1)
            row:SetShadowColor(0, 0, 0, 0.8)

            local val = FontManager:CreateFontString(statPanel, "tiny", "OVERLAY")
            val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
            val:SetPoint("LEFT", row, "RIGHT", 6, 0)
            val:SetJustifyH("RIGHT")
            val:SetTextColor(0.4, 0.9, 0.5)
            val:SetText(stat.value)
            val:SetShadowOffset(1, -1)
            val:SetShadowColor(0, 0, 0, 0.8)

            statY = statY - STAT_ROW_H
        end

        if hasDivider then
            local statDiv = statPanel:CreateTexture(nil, "ARTWORK")
            statDiv:SetPoint("TOPLEFT", statPad, statY - 2)
            statDiv:SetPoint("RIGHT", statPanel, "RIGHT", -statPad, 0)
            statDiv:SetHeight(1)
            statDiv:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)
            statY = statY - 10
        end

        for i = 1, #secondaryRows do
            local stat = secondaryRows[i]
            local row = FontManager:CreateFontString(statPanel, "tiny", "OVERLAY")
            row:SetPoint("TOPLEFT", statPad, statY)
            row:SetWidth(118)
            row:SetWordWrap(false)
            row:SetJustifyH("LEFT")
            row:SetTextColor(0.75, 0.8, 0.9)
            row:SetText(stat.label)
            row:SetShadowOffset(1, -1)
            row:SetShadowColor(0, 0, 0, 0.8)

            local val = FontManager:CreateFontString(statPanel, "tiny", "OVERLAY")
            val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
            val:SetPoint("LEFT", row, "RIGHT", 6, 0)
            val:SetJustifyH("RIGHT")
            val:SetTextColor(0.55, 0.85, 0.95)
            val:SetText(stat.value)
            val:SetShadowOffset(1, -1)
            val:SetShadowColor(0, 0, 0, 0.8)

            statY = statY - STAT_ROW_H
        end
    else
        -- Offline character: no stats available
        local noStats = FontManager:CreateFontString(statPanel, "tiny", "OVERLAY")
        noStats:SetPoint("TOPLEFT", statPad, statY)
        noStats:SetTextColor(0.45, 0.45, 0.45)
        noStats:SetText("Stats available for\ncurrent character only")
        noStats:SetShadowOffset(1, -1)
        noStats:SetShadowColor(0, 0, 0, 0.8)
    end

    card:Show()
    return yOffset - cardH - 12
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
                        slotName = (slotDef and slotDef.label) or ("Slot " .. tostring(slotID)),
                        currentIlvl = current,
                        targetIlvl = target,
                        itemLink = best.itemLink,
                        itemID = best.itemID,
                        source = best.source or "",
                        sourceType = best.sourceType or "",
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

local function DrawStorageRecommendationsCard(parent, yOffset, gearData, storageFindings)
    local rows = BuildStorageRecommendationRows(storageFindings, gearData)
    local title = (ns.L and ns.L["GEAR_STORAGE_TITLE"]) or "Storage Upgrade Recommendations"
    local rowH = 26
    local titleToContentGap = 16
    local cardH = 52 + titleToContentGap + (math.max(#rows, 1) * rowH)

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, yOffset)

    local accent = (COLORS and COLORS.accent) or { 0.6, 0.6, 1.0 }
    local hexAcc = format("%02x%02x%02x", math.floor(accent[1] * 255), math.floor(accent[2] * 255), math.floor(accent[3] * 255))

    local titleText = FontManager:CreateFontString(card, "header", "OVERLAY")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetText("|cff" .. hexAcc .. title .. "|r")

    local startY = -38 - titleToContentGap
    if #rows == 0 then
        local empty = FontManager:CreateFontString(card, "small", "OVERLAY")
        empty:SetPoint("TOPLEFT", 14, startY)
        empty:SetPoint("TOPRIGHT", -14, startY)
        empty:SetJustifyH("LEFT")
        empty:SetText((ns.L and ns.L["GEAR_STORAGE_EMPTY"]) or "No better BoE / Warbound upgrades found for this character.")
        empty:SetTextColor(0.55, 0.55, 0.6)
        card:Show()
        return yOffset - cardH - 12
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
        local slotText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        slotText:SetPoint("LEFT", 12, 0)
        slotText:SetWidth(88)
        slotText:SetJustifyH("LEFT")
        slotText:SetText(row.slotName)
        slotText:SetTextColor(0.95, 0.95, 1.0)
        slotText:SetWordWrap(false)
        slotText:SetNonSpaceWrap(false)

        -- Column 2: current ilvl [atlas] target ilvl + increase (wider so 3-digit ilvls don't truncate)
        local currIlvlText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        currIlvlText:SetPoint("LEFT", slotText, "RIGHT", 14, 0)
        currIlvlText:SetWidth(40)
        currIlvlText:SetJustifyH("RIGHT")
        currIlvlText:SetText(tostring(row.currentIlvl or 0))
        currIlvlText:SetTextColor(0.75, 0.75, 0.8)
        currIlvlText:SetWordWrap(false)

        local arrowTex = container:CreateTexture(nil, "ARTWORK")
        arrowTex:SetSize(12, 12)
        arrowTex:SetPoint("LEFT", currIlvlText, "RIGHT", 8, 0)
        if arrowTex.SetAtlas then
            arrowTex:SetAtlas("common-dropdown-icon-play", true)
        else
            arrowTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            arrowTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            arrowTex:SetVertexColor(0.3, 1, 0.4)
        end

        local targetIlvlText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        targetIlvlText:SetPoint("LEFT", arrowTex, "RIGHT", 8, 0)
        targetIlvlText:SetWidth(40)
        targetIlvlText:SetJustifyH("LEFT")
        targetIlvlText:SetText(tostring(row.targetIlvl or 0))
        targetIlvlText:SetTextColor(0.4, 1, 0.5)
        targetIlvlText:SetWordWrap(false)

        local delta = (row.targetIlvl and row.currentIlvl) and (row.targetIlvl - row.currentIlvl) or 0
        local increaseText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        increaseText:SetPoint("LEFT", targetIlvlText, "RIGHT", 10, 0)
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
        local levelText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        levelText:SetPoint("LEFT", increaseText, "RIGHT", 16, 0)
        levelText:SetText(levelPrefix)
        levelText:SetTextColor(1, 1, 1)
        levelText:SetWordWrap(false)

        local itemIcon = container:CreateTexture(nil, "ARTWORK")
        itemIcon:SetSize(18, 18)
        itemIcon:SetPoint("LEFT", levelText, "RIGHT", 4, 0)
        local icon = row.itemLink and GetItemIconSafe(row.itemLink) or GetItemIconSafe(row.itemID)
        itemIcon:SetTexture(icon or 134400)
        itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Column 4: Item name (flex, between icon and source)
        local itemText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        itemText:SetPoint("LEFT", itemIcon, "RIGHT", 10, 0)
        itemText:SetPoint("RIGHT", container, "RIGHT", -168, 0)
        itemText:SetJustifyH("LEFT")
        local displayItem = row.itemLink or ("item:" .. tostring(row.itemID or 0))
        itemText:SetText(displayItem)
        itemText:SetTextColor(0.75, 0.85, 1.0)
        itemText:SetWordWrap(false)
        itemText:SetNonSpaceWrap(false)

        -- Column 5: Source (fixed width, right-aligned, with margin)
        local sourceText = FontManager:CreateFontString(container, "tiny", "OVERLAY")
        sourceText:SetPoint("RIGHT", -12, 0)
        sourceText:SetWidth(156)
        sourceText:SetJustifyH("RIGHT")
        local bindLabel = ""
        if row.sourceType == "warbound" then
            bindLabel = (ns.L and ns.L["GEAR_STORAGE_WARBOUND"]) or "Warbound"
        elseif row.sourceType == "boe" then
            bindLabel = (ns.L and ns.L["GEAR_STORAGE_BOE"]) or "BoE"
        end
        if bindLabel ~= "" then
            sourceText:SetText((row.source or "") .. "  |cff888888(" .. bindLabel .. ")|r")
        else
            sourceText:SetText(row.source or "")
        end
        sourceText:SetTextColor(0.8, 0.8, 0.85)
        sourceText:SetWordWrap(false)
        sourceText:SetNonSpaceWrap(false)

        -- Tooltip: item only (no extra Slot/iLvl/From lines)
        container:SetScript("OnEnter", function(self)
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "item",
                    itemID = row.itemID,
                    itemLink = row.itemLink,
                    anchor = "ANCHOR_LEFT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = row.itemID,
                    itemLink = row.itemLink,
                    anchor = "ANCHOR_LEFT",
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
    return yOffset - cardH - 12
end

-- ============================================================================
-- CHARACTER SELECTOR  (dropdown button)
-- ============================================================================

-- Singleton dropdown frames (reused to avoid frame buildup)
local gearCharDropdownMenu = nil
local gearCharDropdownBg   = nil

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

    local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
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
            local namePart = "|cff" .. hex .. (cData.name or "") .. "|r"
            local realm = cData.realm and cData.realm ~= "" and cData.realm or nil
            if realm then
                label:SetText(namePart .. "  |  |cffffffff" .. realm .. "|r")
            else
                label:SetText(namePart)
            end
        elseif charKey and charKey ~= "" then
            label:SetText(charKey)
        else
            label:SetText("")
        end
    end

    SetLabelToChar(currentCharKey)

    -- Dropdown: reuse singleton menu and bg to avoid frame buildup
    btn:SetScript("OnClick", function(self)
        local menu = gearCharDropdownMenu
        local bg   = gearCharDropdownBg

        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(500)
            menu:SetWidth(260)
            menu:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
            menu:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.9)
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
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
            gearCharDropdownBg = bg
        end

        -- Clear previous entries
        local bin = ns.UI_RecycleBin
        local children = { menu:GetChildren() }
        for i = 1, #children do
            children[i]:Hide()
            if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
        end

        local ENTRY_H = 28
        menu:SetHeight(#chars * ENTRY_H + 8)
        menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)

        local entryY = -4
        for i = 1, #chars do
            local charEntry = chars[i]
            local entryBtn = CreateFrame("Button", nil, menu)
            entryBtn:SetHeight(ENTRY_H)
            entryBtn:SetPoint("TOPLEFT",  4, entryY)
            entryBtn:SetPoint("TOPRIGHT", -4, entryY)

            local entryLabel = FontManager:CreateFontString(entryBtn, "body", "OVERLAY")
            entryLabel:SetPoint("LEFT", 4, 0)
            entryLabel:SetPoint("RIGHT", -4, 0)
            entryLabel:SetJustifyH("LEFT")

            local cKey   = charEntry.key
            local cData  = charEntry.data
            local hex    = GetClassHex(cData.classFile)
            local namePart = "|cff" .. hex .. (cData.name or cKey) .. "|r"
            local r = cData.realm and cData.realm ~= "" and cData.realm or ""
            if r ~= "" then
                entryLabel:SetText(namePart .. "  |  |cffffffff" .. r .. "|r")
            else
                entryLabel:SetText(namePart)
            end

            if cKey == currentCharKey then
                entryLabel:SetTextColor(accent[1] + 0.2, accent[2] + 0.2, accent[3] + 0.2)
            end

            local entryHi = entryBtn:CreateTexture(nil, "HIGHLIGHT")
            entryHi:SetAllPoints()
            entryHi:SetColorTexture(1, 1, 1, 0.1)

            entryBtn:SetScript("OnClick", function()
                selectedCharKey = cKey
                SetLabelToChar(cKey)
                menu:Hide()
                bg:Hide()
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)

            entryY = entryY - ENTRY_H
        end

        bg:Show()
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

    -- ── Header Card (standardized: same format as Currency, Storage, etc.) ─────
    local headerCard = CreateCard(parent, 70)
    headerCard:SetPoint("TOPLEFT",  SIDE_MARGIN, yOffset)
    headerCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, yOffset)

    local headerIcon = CreateHeaderIcon and CreateHeaderIcon(headerCard, GetTabIcon and GetTabIcon("gear") or nil)

    local r, g, b = accent[1], accent[2], accent[3]
    local hexAcc  = format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local titleTextContent = "|cff" .. hexAcc .. ((ns.L and ns.L["GEAR_TAB_TITLE"]) or "Gear Management") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["GEAR_TAB_DESC"]) or "Equipped gear, upgrade analysis, and crest tracking"

    local textContainer = ns.UI and ns.UI.Factory and ns.UI.Factory:CreateContainer(headerCard, 200, 40)
    if textContainer then
        local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
        titleText:SetText(titleTextContent)
        titleText:SetJustifyH("LEFT")
        titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)
        titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
        subtitleText:SetText(subtitleTextContent)
        subtitleText:SetTextColor(1, 1, 1)
        subtitleText:SetJustifyH("LEFT")
        subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)
        subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        textContainer:SetPoint("LEFT", headerIcon and headerIcon.border or headerCard, "RIGHT", headerIcon and 12 or 24, 0)
        textContainer:SetPoint("CENTER", headerCard, "CENTER", 0, 0)
    else
        local titleText = FontManager:CreateFontString(headerCard, "header", "OVERLAY")
        titleText:SetText(titleTextContent)
        titleText:SetJustifyH("LEFT")
        titleText:SetPoint("TOPLEFT", headerIcon and headerIcon.border or headerCard, "TOPRIGHT", headerIcon and 10 or 12, -4)
        local subtitleText = FontManager:CreateFontString(headerCard, "subtitle", "OVERLAY")
        subtitleText:SetText(subtitleTextContent)
        subtitleText:SetTextColor(0.6, 0.6, 0.6)
        subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -3)
        subtitleText:SetPoint("RIGHT", headerCard, "RIGHT", -270, 0)
    end

    CreateCharacterSelector(headerCard, charKey, 0)
    headerCard:Show()

    yOffset = yOffset - (GetLayout().afterHeader or 75)

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

    yOffset = DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, canonicalKey, currencyAmounts, canonicalKey == currentKey, currencies)

    local storageFindings = (self.FindGearStorageUpgrades and self:FindGearStorageUpgrades(canonicalKey)) or {}
    yOffset = DrawStorageRecommendationsCard(parent, yOffset, gearData, storageFindings)

    yOffset = yOffset - 12
    return math.abs(yOffset) + TOP_MARGIN
end
