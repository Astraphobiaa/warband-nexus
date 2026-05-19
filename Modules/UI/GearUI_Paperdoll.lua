--[[
    Warband Nexus - Gear tab paperdoll / slot / card draw chunk
    Split from GearUI.lua to stay under Lua 5.1's 200 locals-per-chunk limit.
]]

local _, ns = ...
local WarbandNexus, FontManager = ns.WarbandNexus, ns.FontManager

local function GFR(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local COLORS              = ns.UI_COLORS
local CreateCard          = ns.UI_CreateCard
local ApplyVisuals        = ns.UI_ApplyVisuals
local GetQualityHex       = ns.UI_GetQualityHex
local CreateThemedButton  = ns.UI_CreateThemedButton
local FormatGold          = ns.UI_FormatGold
local FormatNumber        = ns.UI_FormatNumber
local DrawEmptyState      = ns.UI_DrawEmptyState
local ShowTooltip         = ns.UI_ShowTooltip
local HideTooltip         = ns.UI_HideTooltip
local ApplyProfessionCraftingQualityAtlasToTexture = ns.UI_ApplyProfessionCraftingQualityAtlasToTexture
local GetEnchantmentCraftingQualityTierFromItemLink = ns.UI_GetEnchantmentCraftingQualityTierFromItemLink

local GEAR_SLOTS         = ns.GEAR_SLOTS
local SLOT_BY_ID         = ns.SLOT_BY_ID
local EQUIP_LOC_TO_SLOTS = ns.EQUIP_LOC_TO_SLOTS

local format = string.format
local tinsert = table.insert
local wipe = wipe
local debugprofilestop = debugprofilestop

local GearFact = ns.UI.Factory

local function GearTabL(key, fallback)
    local v = ns.L and ns.L[key]
    if type(v) == "string" and v ~= "" and v ~= key then
        return v
    end
    return fallback
end

local UI_LAYOUT      = ns.UI_LAYOUT or {}
local SIDE_MARGIN    = UI_LAYOUT.SIDE_MARGIN or 16
local TOP_MARGIN     = UI_LAYOUT.TOP_MARGIN or 12

local function GetLocalizedText(key, fallback)
    return GearTabL(key, fallback)
end

local function GetUpgradeTrackHex(englishName)
    if ns.UI_GetUpgradeTrackTierHex then
        return ns.UI_GetUpgradeTrackTierHex(englishName)
    end
    return nil
end

local function FormatTrackMarkup(englishName, text, fallbackQuality)
    if ns.UI_FormatUpgradeTrackMarkup then
        return ns.UI_FormatUpgradeTrackMarkup(englishName, text, fallbackQuality)
    end
    local hex = GetUpgradeTrackHex(englishName) or (GetQualityHex and GetQualityHex(fallbackQuality or 0)) or "ffffff"
    return "|cff" .. hex .. (text or "") .. "|r"
end

local function FormatFloat2(value)
    if type(value) ~= "number" then return nil end
    return format("%.2f", value)
end

local function LocalizeUpgradeTrackName(name)
    if not name or name == "" then return name end
    if issecretvalue and issecretvalue(name) then return name end
    local keyMap = {
        Adventurer = "PVE_CREST_ADV", Veteran = "PVE_CREST_VET", Champion = "PVE_CREST_CHAMP",
        Hero = "PVE_CREST_HERO", Myth = "PVE_CREST_MYTH", Explorer = "PVE_CREST_EXPLORER",
    }
    local key = keyMap[name]
    if key and ns.L and ns.L[key] then return ns.L[key] end
    return name
end

local function GetClassHex(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "ffffff"
end

local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleasePooledRowsInSubtree = ns.UI_ReleasePooledRowsInSubtree

local _gearRecChildScratch = {}
local function PackGearRecChildren(recContent, ...)
    wipe(_gearRecChildScratch)
    local n = select("#", ...)
    for i = 1, n do
        local c = select(i, ...)
        if c then _gearRecChildScratch[#_gearRecChildScratch + 1] = c end
    end
    return _gearRecChildScratch
end

local function GearGetFrameContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

local PAPERDOLL_SCALE = 1.10
local function P(n) return math.floor(n * PAPERDOLL_SCALE + 0.5) end
local SLOT_SIZE      = P(38)
local SLOT_GAP       = P(5)
local DOLL_PAD       = P(12)
local SLOT_TO_ARROW_GAP = P(4)   -- slot ile upgrade ikonu arası
local ARROW_TO_TEXT_GAP = P(6)   -- ok ile yazı arası boşluk (artık yaslamalı olduğu için pozitif olmalı)
local TRACK_TEXT_W   = P(136)  -- Track metin taşmasını engellemek için genişletildi
-- Paperdoll status: gem + enchant stacked on outer (track) side.
-- Increase (upgrade) / lock: small icon inside the item square, corner chosen per column so it stays visible
-- (center "toward model" sat under the 3D portrait sibling) and does not overlap the outer gem/enchant column.
local STATUS_OUTER_ICON = P(17)
local STATUS_UPGRADE_ICON = P(21)
local STATUS_UPGRADE_DRAW_MULT = 0.78
local STATUS_UPGRADE_BG_PAD = 3
local STATUS_UPGRADE_BORDER = 2
local STATUS_HOST_GAP = P(4)
local STATUS_OUTER_GAP_V = P(3)
local STATUS_OUTER_COL_W = STATUS_OUTER_ICON
local STATUS_OUTER_COL_H = STATUS_OUTER_ICON + STATUS_OUTER_GAP_V + STATUS_OUTER_ICON
local STATUS_TEXT_WARD_W = STATUS_OUTER_COL_W
local STATUS_ICON_INSET = 1
-- DEBUG: show upgrade arrow on every occupied slot. Set false for release.
local GEAR_DEBUG_ALWAYS_SHOW_UPGRADE = false
-- When false, hide paperdoll missing-enchant / empty-socket alert triangles (upgrade chip is separate).
local GEAR_PAPERDOLL_ENCHANT_GEM_ALERTS = false
-- Inline ilvl separator in recommendation FontStrings (Unicode → renders as tofu); same atlas as storage row ilvl arrow.
local GEAR_ILVL_ARROW_ATLAS = "common-dropdown-icon-play"
local GEAR_ILVL_ARROW_INLINE_SZ = 14
local GEAR_ILVL_ARROW_INLINE_MARKUP = (CreateAtlasMarkup and CreateAtlasMarkup(GEAR_ILVL_ARROW_ATLAS, GEAR_ILVL_ARROW_INLINE_SZ, GEAR_ILVL_ARROW_INLINE_SZ))
    or ("|A:" .. GEAR_ILVL_ARROW_ATLAS .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. "|a")
local CURRENCY_PANEL_W = 248
local GEAR_STAT_PANEL_W = 292
local CENTER_GAP     = P(10)
local CURRENCY_PAPERDOLL_GAP = 14  -- boşluk crest paneli ile paperdoll arası

-- Fixed panel widths: sol = yazı + ikon + slot, sağ = slot + ikon + yazı
local LEFT_PANEL_W   = TRACK_TEXT_W + ARROW_TO_TEXT_GAP + STATUS_TEXT_WARD_W + SLOT_TO_ARROW_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + 2 + ARROW_TO_TEXT_GAP + TRACK_TEXT_W
local MODEL_W       = P(262)
--- Inner 3D portrait viewport: tiled fill only (`paperChrome` is clip host — no extra border).
local GEAR_MODEL_VIEWPORT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

---@param parent Frame
---@param width number
---@param height number
---@param accent table|nil
---@return Frame
local function CreateGearSubpanel(parent, width, height, accent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width or 100, height or 100)
    if ns.GearUI_Chrome and ns.GearUI_Chrome.ApplySubpanel then
        ns.GearUI_Chrome.ApplySubpanel(f, accent)
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    end
    return f
end

local function ApplyGearModelViewportFill(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(GEAR_MODEL_VIEWPORT_BACKDROP)
    local bg = COLORS.bg or COLORS.bgCard or { 0.042, 0.042, 0.055, 0.98 }
    frame:SetBackdropColor(bg[1], bg[2], bg[3], (bg[4] or 1) * 0.95)
end

--- Row striping inside sub-cards: subtle lift on bgCard (avoid viewport-gray slabs).
local function GearPanelRowBgColor(zebra)
    local base = COLORS.bgCard or COLORS.bg or { 0.118, 0.118, 0.145, 0.98 }
    local lift = (zebra % 2 == 0) and 0.014 or 0.005
    return base[1] + lift, base[2] + lift, base[3] + lift * 1.05, base[4] or 0.98
end

-- Paperdoll blok genişliği (sol kolon + model + sağ kolon) — kart içinde ortalanır
local PAPERDOLL_BLOCK_W = LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP + RIGHT_PANEL_W

local SLOT_HALF = SLOT_SIZE / 2
local TEXT_HALF_W = TRACK_TEXT_W / 2
local TEXT_OFFSET_FROM_SLOT_CENTER = SLOT_HALF + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + ARROW_TO_TEXT_GAP + TEXT_HALF_W
local PAPERDOLL_COL_INSET = 4
local PAPER_TRACK_EDGE_PAD = 12
local MAX_PAPER_MODEL_BOOST = 32

--- Right edge of right-column track labels (CENTER anchor + LEFT justify within TRACK_TEXT_W).
---@param baseX number
---@param modelW number
---@return number contentRightX
local function GearPaperdollContentRightX(baseX, modelW)
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP
    return rightX + SLOT_HALF + TEXT_OFFSET_FROM_SLOT_CENTER + math.ceil(TRACK_TEXT_W * 0.5) + PAPER_TRACK_EDGE_PAD
end

---@param modelW number
---@param baseX number|nil
---@return number columnWidth
local function GearPaperdollColumnWidth(modelW, baseX)
    local bx = baseX or PAPERDOLL_COL_INSET
    return math.ceil(GearPaperdollContentRightX(bx, modelW) + PAPERDOLL_COL_INSET)
end

local PAPERDOLL_LAYOUT_W = GearPaperdollColumnWidth(MODEL_W + MAX_PAPER_MODEL_BOOST)
local GEAR_PAPER_COL_FIXED_W = PAPERDOLL_LAYOUT_W

if ns.GearUI_BindPaperdollLayoutConstants then
    ns.GearUI_BindPaperdollLayoutConstants(PAPERDOLL_LAYOUT_W, LEFT_PANEL_W)
elseif ns.GearUI_RefreshMinScrollWidthCache then
    ns.GearUI_RefreshMinScrollWidthCache()
end

local GEAR_LAYOUT = ns.GEAR_LAYOUT or {}
local GEAR_PANEL_GAP = GEAR_LAYOUT.COL_GAP or 14
local GEAR_PAPER_COL_W = GEAR_PAPER_COL_FIXED_W
local CARD_PAD = GEAR_LAYOUT.CARD_PAD or 12
local GEAR_BOTTOM_STAT_MIN_W = GEAR_LAYOUT.BOTTOM_STAT_MIN_W or 136
local GEAR_BOTTOM_CURR_MIN_W = GEAR_LAYOUT.BOTTOM_CURR_MIN_W or 148
local GEAR_BOTTOM_BAND_MIN_H = GEAR_LAYOUT.BOTTOM_BAND_MIN_H or 120

local function ComputeGearLayoutWidths(cardInnerW, recEnabled)
    if ns.GearUI_ComputeTopRowLayout then
        local _, paperW, sideW = ns.GearUI_ComputeTopRowLayout(cardInnerW, nil)
        return math.max(paperW or 0, GEAR_PAPER_COL_FIXED_W), sideW
    end
    if ns.GearUI_ComputeLayoutWidths then
        local paperW, sideW = ns.GearUI_ComputeLayoutWidths(cardInnerW, recEnabled)
        return math.max(paperW or 0, GEAR_PAPER_COL_FIXED_W), sideW
    end
    local paperW = math.max(GEAR_PAPER_COL_FIXED_W, PAPERDOLL_BLOCK_W)
    local inner = math.max(0, (cardInnerW or 0) - GEAR_PANEL_GAP)
    paperW = math.max(paperW, math.min(paperW, inner))
    return paperW, math.max(0, inner - paperW)
end

--- Body zones: top (paperdoll | stats+currencies) + bottom (recommendations).
---@param card Frame
---@param layout table
---@param panelTopY number
---@param recEnabled boolean
local function EnsureGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if not card or not layout then return end
    if not layout.bodyHost then
        local body = CreateFrame("Frame", nil, card)
        if body.SetClipsChildren then body:SetClipsChildren(true) end
        layout.bodyHost = body
    end
    layout.bodyHost:ClearAllPoints()
    layout.bodyHost:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, panelTopY)
    layout.bodyHost:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)

    if not layout.topHost then
        local top = CreateFrame("Frame", nil, layout.bodyHost)
        if top.SetClipsChildren then top:SetClipsChildren(true) end
        layout.topHost = top
    end
    layout.topHost:SetParent(layout.bodyHost)
    layout.topHost:Show()

    if not layout.leftColHost then
        local left = CreateFrame("Frame", nil, layout.topHost)
        if left.SetClipsChildren then left:SetClipsChildren(true) end
        layout.leftColHost = left
    end
    layout.leftColHost:SetParent(layout.topHost)
    layout.leftColHost:Show()

    if not layout.centerGapHost then
        local center = CreateFrame("Frame", nil, layout.topHost)
        center:EnableMouse(false)
        if center.SetClipsChildren then center:SetClipsChildren(true) end
        layout.centerGapHost = center
    end
    layout.centerGapHost:SetParent(layout.topHost)

    if not layout.rightColHost then
        local right = CreateFrame("Frame", nil, layout.topHost)
        if right.SetClipsChildren then right:SetClipsChildren(true) end
        layout.rightColHost = right
    end
    layout.rightColHost:SetParent(layout.topHost)
    layout.rightColHost:Show()

    if recEnabled then
        if not layout.bottomColHost then
            local bottom = CreateFrame("Frame", nil, layout.bodyHost)
            if bottom.SetClipsChildren then bottom:SetClipsChildren(true) end
            layout.bottomColHost = bottom
        end
        layout.bottomColHost:SetParent(layout.bodyHost)
        layout.bottomColHost:Show()
    elseif layout.bottomColHost then
        layout.bottomColHost:Hide()
    end
end

--- Stretch top row + bottom recommendations band.
---@param card Frame
---@param layout table
---@param panelTopY number
---@param recEnabled boolean
---@return number|nil storageW measured bottom band width
local function RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if not card or not layout then return nil end
    EnsureGearCardColumnHosts(card, layout, panelTopY, recEnabled == true)
    local gap = layout.panelGutter or GEAR_LAYOUT.COL_GAP or GEAR_PANEL_GAP
    local sectionGap = layout.sectionGap or GEAR_LAYOUT.SECTION_GAP or 12
    local paperColW = math.max(GEAR_PAPER_COL_FIXED_W, layout.paperColW or GEAR_PAPER_COL_FIXED_W)
    layout.paperColW = paperColW
    local sideColW = math.max(1, layout.sideColW or layout.storageW or 0)
    local recZoneH = layout.recZoneH or 0
    local body = layout.bodyHost
    local top = layout.topHost
    local left = layout.leftColHost
    local right = layout.rightColHost
    local bottom = layout.bottomColHost
    if not body or not top or not left or not right then return nil end

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    if recEnabled and bottom and recZoneH > 0 then
        top:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, recZoneH + sectionGap)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(recZoneH)
        bottom:Show()
    else
        top:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
        if bottom then bottom:Hide() end
    end

    local paperBandH = math.max(1, layout.paperdollNaturalH or layout.paperZoneH or 1)
    layout.paperZoneH = paperBandH

    -- Right rail pinned to card top-right; paperdoll stays left (never under stats).
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
    left:SetSize(paperColW, paperBandH)
    if left.SetClipsChildren then
        left:SetClipsChildren(true)
    end

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(sideColW)
    if right.SetClipsChildren then
        right:SetClipsChildren(true)
    end

    local center = layout.centerGapHost
    if center then
        center:ClearAllPoints()
        center:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        center:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 0)
        center:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
        center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        center:Show()
    end

    if layout.colDivider then
        layout.colDivider:SetParent(top)
        layout.colDivider:ClearAllPoints()
        if center then
            layout.colDivider:SetPoint("TOP", center, "TOP", 0, 0)
            layout.colDivider:SetPoint("BOTTOM", center, "BOTTOM", 0, 0)
            layout.colDivider:SetPoint("CENTER", center, "CENTER", 0, 0)
        else
            layout.colDivider:SetPoint("TOP", right, "TOPLEFT", -math.floor(gap * 0.5), 0)
            layout.colDivider:SetPoint("BOTTOM", right, "BOTTOMLEFT", -math.floor(gap * 0.5), 0)
        end
        layout.colDivider:Show()
    end

    local topW = (top.GetWidth and top:GetWidth()) or 0
    local minTopW = paperColW + gap + sideColW
    layout.topRowMinW = minTopW
    layout.topRowOverlaps = (topW > 0 and topW < minTopW - 1)
    if layout.topStackDivider and layout.topStackDivider.Hide then
        layout.topStackDivider:Hide()
    end

    if sideColW < 1 and right.GetWidth then
        sideColW = right:GetWidth() or sideColW
    end
    layout.sideColW = sideColW
    layout.topLayoutMode = "row"

    local storageW = nil
    if recEnabled and layout.storagePanel and bottom then
        layout.storagePanel:SetParent(bottom)
        layout.storagePanel:ClearAllPoints()
        layout.storagePanel:SetPoint("TOPLEFT", bottom, "TOPLEFT", 0, 0)
        layout.storagePanel:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
        if layout.storagePanel.GetWidth then
            storageW = layout.storagePanel:GetWidth()
        end
    end

    if layout.horizDivider then
        layout.horizDivider:Hide()
    end
    layout.recLeft = nil
    layout.storageW = storageW or layout.cardInnerW
    return storageW
end

--- Re-anchor paperdoll slots + center model after live resize (DrawPaperDollInCard positions are fixed at paint time).
---@param card Frame
---@param layout table
local function RelayoutGearPaperdollInCard(card, layout)
    if not card or not layout then return end
    local slotList = card._gearSlotInspectList
    if not slotList or #slotList == 0 then return end

    local paperParent = layout.leftColHost or card
    local useColHost = layout.leftColHost ~= nil
    local baseX = useColHost and PAPERDOLL_COL_INSET or ((layout.paperLeft or CARD_PAD) + PAPERDOLL_COL_INSET)
    local paperColW = layout.paperColW or PAPERDOLL_BLOCK_W
    local modelBoost = math.max(0, math.min(32, paperColW - PAPERDOLL_BLOCK_W - PAPERDOLL_COL_INSET * 2))
    layout.paperdollBaseX = baseX
    layout.modelBoost = modelBoost

    local modelW = MODEL_W + modelBoost
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP
    local rowStep = SLOT_SIZE + SLOT_GAP

    local paperdollNaturalH = layout.paperdollNaturalH or 0
    local paperBandH = paperdollNaturalH
    layout.paperZoneH = paperBandH
    local vertCenterPad = 0
    local startY
    if useColHost then
        startY = -vertCenterPad
    else
        local paperOriginY = layout.panelTopY
        if paperOriginY == nil then paperOriginY = -(CARD_PAD + 22) end
        startY = paperOriginY - vertCenterPad
    end
    local modelX = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY
    layout.modelX = modelX
    layout.modelTopY = modelTopY

    local posBySlot = {}
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i = 1, #leftSlots do
        posBySlot[leftSlots[i]] = { leftX, startY - (i - 1) * rowStep }
    end
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i = 1, #rightSlots do
        posBySlot[rightSlots[i]] = { rightX, startY - (i - 1) * rowStep }
    end
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (modelW + CENTER_GAP - weaponRowW) / 2
    local maxRows = math.max(#leftSlots, #rightSlots)
    local bottomY = startY - maxRows * rowStep - 8
    for i = 1, #weaponSlots do
        local sid = weaponSlots[i]
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        posBySlot[sid] = { wx, bottomY }
    end

    for si = 1, #slotList do
        local sb = slotList[si]
        local slotID = sb and sb._slotID
        local pos = slotID and posBySlot[slotID]
        if sb and pos then
            sb:ClearAllPoints()
            sb:SetPoint("TOPLEFT", paperParent, "TOPLEFT", pos[1], pos[2])
        end
    end

    local numRightRows = #rightSlots
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE

    local function anchorModelFrame(fr)
        if not fr or not fr.ClearAllPoints then return end
        fr:ClearAllPoints()
        fr:SetSize(modelW, MODEL_H)
        fr:SetPoint("TOPLEFT", paperParent, "TOPLEFT", modelX, modelTopY)
        if fr.SetParent and paperParent then
            fr:SetParent(paperParent)
        end
    end
    anchorModelFrame(ns._gearDressModel)
    anchorModelFrame(ns._gearPortraitPanel)
    anchorModelFrame(ns._gearPaperdollCenterPlaceholder)

    local measuredPaperW = GearPaperdollColumnWidth(modelW, baseX)
    layout.paperColW = math.max(GEAR_PAPER_COL_FIXED_W, layout.paperColW or 0, measuredPaperW)
    layout.measuredPaperColW = measuredPaperW
    if layout.leftColHost and layout.leftColHost.SetSize then
        local bandH = layout.paperdollNaturalH or layout.paperZoneH or paperdollNaturalH
        layout.leftColHost:SetSize(layout.paperColW, bandH)
    end
    if layout.paperChrome and layout.paperChrome.SetSize then
        layout.paperChrome:SetSize(layout.paperColW, layout.paperZoneH or paperdollNaturalH)
    end

    local centerShown = nil
    if ns._gearDressModel and ns._gearDressModel.IsShown and ns._gearDressModel:IsShown() then
        centerShown = ns._gearDressModel
    elseif ns._gearPortraitPanel and ns._gearPortraitPanel.IsShown and ns._gearPortraitPanel:IsShown() then
        centerShown = ns._gearPortraitPanel
    end
    if centerShown and ns._gearModelBorder then
        ns._gearModelBorder:ClearAllPoints()
        ns._gearModelBorder:SetPoint("TOPLEFT", centerShown, "TOPLEFT", -1, 1)
        ns._gearModelBorder:SetPoint("BOTTOMRIGHT", centerShown, "BOTTOMRIGHT", 1, -1)
    end
end

--- Three-zone grid: left-top paperdoll, left-bottom stats|currencies, right recommendations (~equal area).
---@param panelH number viewport-filled content height
---@param paperdollMinH number minimum paperdoll block height
---@param bottomBandMinH number minimum stats+currencies band height
---@param sectionGap number
---@return number paperZoneH
---@return number bottomZoneH
local function ComputeGearLeftColumnHeights(panelH, paperdollMinH, bottomBandMinH, sectionGap)
    local gap = sectionGap or 12
    local bottomH = math.max(GEAR_BOTTOM_BAND_MIN_H, bottomBandMinH or 0)
    local paperMin = paperdollMinH or 0
    local minStack = paperMin + gap + bottomH
    local paperZoneH = paperMin
    if panelH > minStack then
        paperZoneH = paperMin + (panelH - minStack)
    end
    return paperZoneH, bottomH
end

local function GetGearTabMinCardInnerW()
    if ns.GearUI_GetGearTabMinCardInnerW then
        return ns.GearUI_GetGearTabMinCardInnerW(WarbandNexus:IsGearStorageRecommendationsEnabled())
    end
    return GEAR_PAPER_COL_FIXED_W + GEAR_PANEL_GAP + (GEAR_LAYOUT.SIDE_COL_MIN_W or 280)
end

local function ResolveGearTabCardInnerWidth(scrollChildW)
    if ns.GearUI_ResolveCardInnerWidth then
        return ns.GearUI_ResolveCardInnerWidth(scrollChildW, SIDE_MARGIN)
    end
    return GetGearTabMinCardInnerW()
end

--- Stretch gear card across scroll child; cap to viewport when scrollChild is wider than visible area.
---@param card Frame
---@param parent Frame
---@param yOffset number
---@param mf Frame|nil main frame (scroll viewport width)
---@return number cardInnerW
local function AnchorGearCardFillWidth(card, parent, yOffset, mf)
    if not card or not parent then return GetGearTabMinCardInnerW() end
    local side = SIDE_MARGIN or 16
    local scrollChildW = (parent.GetWidth and parent:GetWidth()) or 0
    local outerW = math.max(1, scrollChildW - 2 * side)
    -- Never squeeze the gear card to the visible viewport when scrollChild is wider:
    -- horizontal scroll reveals overflow instead of truncating paperdoll / stats / recommendations.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", side, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -side, yOffset)
    return math.max(1, outerW - 2 * CARD_PAD)
end

---@param cardInnerW number
---@return number cardOuterW
local function GearTabCardOuterWidth(cardInnerW)
    return math.max(1, (cardInnerW or 0) + CARD_PAD * 2)
end

--- Measured inner width after card stretch anchors (never wider than the card frame).
---@param card Frame|nil
---@return number cardInnerW
local function GetGearCardInnerWidthFromCard(card)
    if not card or not card.GetWidth then
        return GetGearTabMinCardInnerW()
    end
    local outerW = card:GetWidth() or 0
    if outerW < 1 then
        return GetGearTabMinCardInnerW()
    end
    return math.max(1, outerW - 2 * CARD_PAD)
end

local function ComputeGearStatColumnWidths(statInnerW, colGap)
    if ns.GearUI_ComputeStatColumnWidths then
        return ns.GearUI_ComputeStatColumnWidths(statInnerW, colGap)
    end
    return 80, 48, 44
end

--- Reflow stat/currency FontString widths after bottom-band resize (no full PopulateContent).
---@param layout table
local function RelayoutGearBottomBandTypography(layout)
    if not layout then return end
    local statPanel = layout.statPanel
    local currencyPanel = layout.currencyPanel
    local statColW = math.max(1, layout.sideColW or layout.statColW or 0)
    local currColW = math.max(1, layout.sideColW or layout.currColW or 0)

    if statPanel and statPanel._wnGearStatMetrics and statPanel._wnGearStatRows then
        local m = statPanel._wnGearStatMetrics
        local gap = m.statColGap or 8
        local pad = m.statPad or 10
        local valW = m.valColW or 72
        local pctW = m.pctColW or 52
        local rows = statPanel._wnGearStatRows
        for i = 1, #rows do
            local row = rows[i]
            local y = row.y or 0
            if row.val then
                row.val:ClearAllPoints()
                row.val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -pad, y)
                row.val:SetWidth(valW)
                row.val:SetJustifyH("RIGHT")
            end
            if row.hasPct and row.pct then
                row.pct:ClearAllPoints()
                row.pct:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -(pad + valW + gap), y)
                row.pct:SetWidth(pctW)
                row.pct:SetJustifyH("RIGHT")
            elseif row.pct then
                row.pct:Hide()
            end
            if row.label then
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", statPanel, "TOPLEFT", pad, y)
                local labelRight = pad + valW + gap + (row.hasPct and (pctW + gap) or 0)
                row.label:SetPoint("RIGHT", statPanel, "RIGHT", -labelRight, y)
                row.label:SetJustifyH("LEFT")
            end
        end
    end

    if currencyPanel and currencyPanel._wnGearCurrMetrics and currencyPanel._wnGearCurrRows then
        local cm = currencyPanel._wnGearCurrMetrics
        local currAmtReserve = (ns.GEAR_LAYOUT and ns.GEAR_LAYOUT.CURR_AMOUNT_COL_W) or 108
        cm.currAmtReserve = currAmtReserve
        local rows = currencyPanel._wnGearCurrRows
        for i = 1, #rows do
            local row = rows[i]
            if row.name then
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", currencyPanel, "RIGHT", -cm.currPad - currAmtReserve, 0)
                row.name:SetPoint("TOP", row.icon, "TOP", 0, 0)
                row.name:SetPoint("BOTTOM", row.icon, "BOTTOM", 0, 0)
            end
            if row.amount and row.icon then
                row.amount:ClearAllPoints()
                row.amount:SetPoint("RIGHT", currencyPanel, "RIGHT", -cm.currPad, 0)
                row.amount:SetPoint("TOP", row.icon, "TOP", 0, 0)
                row.amount:SetPoint("BOTTOM", row.icon, "BOTTOM", 0, 0)
            end
        end
    end
end

--- Stats + currencies stacked in the right column (top host).
---@param card Frame
---@param layout table
local function RelayoutGearSideColumnInCard(card, layout)
    if not card or not layout then return end
    local sideParent = layout.rightColHost
    if not sideParent then return end
    local sideColW = math.max(1, layout.sideColW or layout.statColW or 0)
    local sideInset = GEAR_LAYOUT.SIDE_PANEL_INSET or 6
    local innerW = math.max(1, sideColW - sideInset * 2)
    local statPanelH = math.max(80, layout.statPanelH or layout.statBandH or GEAR_BOTTOM_BAND_MIN_H)
    local currPanelH = math.max(80, layout.currenciesH or layout.currBandH or GEAR_BOTTOM_BAND_MIN_H)
    local bandGap = layout.sideBandGap or GEAR_LAYOUT.SIDE_BAND_GAP or 10
    layout.bottomBandMode = "stack"
    layout.statColW = sideColW
    layout.currColW = sideColW
    layout.sideBandGap = bandGap
    layout.sideColNaturalH = statPanelH + bandGap + currPanelH

    if layout.statPanel then
        layout.statPanel:SetParent(sideParent)
        layout.statPanel:ClearAllPoints()
        layout.statPanel:SetSize(innerW, statPanelH)
        layout.statPanel:SetPoint("TOPLEFT", sideParent, "TOPLEFT", sideInset, 0)
        layout.statPanel:SetPoint("TOPRIGHT", sideParent, "TOPRIGHT", -sideInset, 0)
    end
    if layout.statCurrDiv then
        layout.statCurrDiv:SetParent(sideParent)
        layout.statCurrDiv:ClearAllPoints()
        local divY = -statPanelH - math.floor(bandGap * 0.5)
        layout.statCurrDiv:SetPoint("TOPLEFT", sideParent, "TOPLEFT", sideInset, divY)
        layout.statCurrDiv:SetPoint("TOPRIGHT", sideParent, "TOPRIGHT", -sideInset, divY)
        layout.statCurrDiv:SetHeight(1)
        layout.statCurrDiv:Show()
    end
    if layout.currencyPanel then
        layout.currencyPanel:SetParent(sideParent)
        layout.currencyPanel:ClearAllPoints()
        layout.currencyPanel:SetSize(innerW, currPanelH)
        layout.currencyPanel:SetPoint("TOPLEFT", sideParent, "TOPLEFT", sideInset, -statPanelH - bandGap)
        layout.currencyPanel:SetPoint("BOTTOMRIGHT", sideParent, "BOTTOMRIGHT", -sideInset, 0)
    end
    RelayoutGearBottomBandTypography(layout)
end

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

-- In-place paperdoll refresh: PLAYER_EQUIPMENT_CHANGED debounce may only list one slot of a swap pair.
local GEAR_REFRESH_PAIR_SLOTS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }
-- Paperdoll slot list for cache-warm repaints (GET_ITEM_INFO / metadata); stable table — no fresh {} in hot path.
local GEAR_PAPERDOLL_REFRESH_SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
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

--- Enchant spell id from item hyperlink payload (same field as ItemLinkHasEnchantment).
local function GetItemHyperlinkEnchantmentId(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if issecretvalue and issecretvalue(itemLink) then return nil end
    local segment = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:[^|]+)|h") or itemLink
    local body = segment:match("^item:(.+)$") or segment
    local _, enc = body:match("^(%d+):([^:]*):")
    if not _ then
        _, enc = body:match("^(%d+):([^:]*)$")
    end
    if not enc or enc == "" then return nil end
    local e = tonumber(enc)
    if e and e > 0 then return e end
    return nil
end

local function ResolveGearSpellName(spellID)
    if not spellID or spellID <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    return nil
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
local function SetupGearSlotEnchantQualityTexture(tex, tierIdx, pixelSize)
    if not tex then return false end
    local tier = tonumber(tierIdx) or 1
    if tier < 1 then tier = 1 end
    local sz = tonumber(pixelSize) or GEAR_ENCHANT_QUALITY_SZ
    if sz < 10 then sz = 10 end
    if ApplyProfessionCraftingQualityAtlasToTexture and ApplyProfessionCraftingQualityAtlasToTexture(tex, tier, sz) then
        return true
    end
    tex:SetTexture("Interface\\Icons\\Trade_Engraving")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(0.82, 0.76, 1.0, 0.92)
    tex:SetSize(sz, sz)
    tex:Show()
    return true
end

-- Per-socket gem / empty-socket art on paperdoll (C_Item.GetItemNumSockets / GetItemGem; warcraft.wiki.gg API pages 12.0.1).
local MAX_GEAR_ITEM_SOCKETS = 6
local GEAR_SOCKET_GEM_PX = P(14)
local GEAR_SOCKET_GEM_GAP = 2
-- Blizzard socket art (backslashes; matches FrameXML conventions).
local EMPTY_SOCKET_TEX_BY_SUFFIX = {
    META = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Hydraulic",
    RED = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Red",
    YELLOW = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Yellow",
    BLUE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Blue",
    PRISMATIC = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
    HYDRAULIC = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Hydraulic",
    COGWHEEL = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Cogwheel",
    DOMINATION = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
}
local EMPTY_SOCKET_TEX_DEFAULT = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

local function CollectEmptySocketSuffixesFromStats(stats)
    local list = {}
    if not stats then return list end
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k))
            and string.find(k, "EMPTY_SOCKET_", 1, true) then
            local suf = string.match(k, "^EMPTY_SOCKET_(.+)$") or "PRISMATIC"
            local c = tonumber(v)
            if not c or c < 1 then c = 1 end
            for j = 1, c do
                if EMPTY_SOCKET_TEX_BY_SUFFIX[suf] then
                    list[#list + 1] = suf
                else
                    list[#list + 1] = "PRISMATIC"
                end
            end
        end
    end
    return list
end

local function GetGearGemIconTexture(gemLink)
    if not gemLink or type(gemLink) ~= "string" or (issecretvalue and issecretvalue(gemLink)) then
        return nil
    end
    local ic = ns.GearUI_GetItemIconSafe(gemLink)
    if ic and ic ~= 0 and ic ~= "" then return ic end
    local id = nil
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            id = C_Item.GetItemInfoInstant(gemLink)
        end
    end)
    if not id then
        local m = gemLink:match("item:(%d+)")
        id = m and tonumber(m) or nil
    end
    if id and C_Item and C_Item.GetItemIconByID then
        local ok, r = pcall(C_Item.GetItemIconByID, id)
        if ok and r and r ~= 0 and r ~= "" then return r end
    end
    if id and GetItemIcon then
        local ok, r = pcall(GetItemIcon, id)
        if ok and r and r ~= 0 and r ~= "" then return r end
    end
    return "Interface\\Icons\\INV_Misc_Gem_01"
end

-- Gem per socket: C_Item.GetItemGem / GetItemGem return (name, itemLink) — second value is the hyperlink (warcraft.wiki.gg API pages).
local function GetItemGemForSocket(itemLink, socketIndex)
    if not itemLink or not socketIndex then return nil end
    local gemName, gemLink
    local ok, a, b = pcall(function()
        if C_Item and C_Item.GetItemGem then
            return C_Item.GetItemGem(itemLink, socketIndex)
        end
    end)
    if ok then
        gemName, gemLink = a, b
    end
    if gemLink and type(gemLink) == "string" and gemLink ~= "" and not (issecretvalue and issecretvalue(gemLink)) then
        return gemLink
    end
    if GetItemGem then
        ok, a, b = pcall(GetItemGem, itemLink, socketIndex)
        if ok and b and type(b) == "string" and b ~= "" and not (issecretvalue and issecretvalue(b)) then
            return b
        end
    end
    return nil
end

---@param itemLink string
---@param slotID number|nil
---@param useLiveSlot boolean|nil When true, retry C_Item.GetItemNumSockets(ItemLocation) for equipped item.
---@return table entries { { gemLink = string|nil, emptyTexture = string }, ... }
---@return string sig Dedupe signature for GearSlotPaperdollVisualEquals
local function ComputeGearSocketLayout(itemLink, slotID, useLiveSlot)
    local entries = {}
    if not itemLink or type(itemLink) ~= "string" or (issecretvalue and issecretvalue(itemLink)) then
        return entries, ""
    end
    local n = 0
    pcall(function()
        if C_Item and C_Item.GetItemNumSockets then
            n = tonumber(C_Item.GetItemNumSockets(itemLink)) or 0
        end
    end)
    if (not n or n <= 0) and useLiveSlot and slotID and ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemNumSockets then
        pcall(function()
            local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
            if loc and loc:IsValid() then
                n = tonumber(C_Item.GetItemNumSockets(loc)) or 0
            end
        end)
    end
    local stats = (GetItemStats and GetItemStats(itemLink)) or {}
    local emptyFromStats = 0
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k)) and string.find(k, "EMPTY_SOCKET_", 1, true) then
            local c = tonumber(v)
            if not c or c < 1 then c = 1 end
            emptyFromStats = emptyFromStats + c
        end
    end
    local maxGemIdx = 0
    for i = 1, MAX_GEAR_ITEM_SOCKETS do
        local g = GetItemGemForSocket(itemLink, i)
        if g then maxGemIdx = i end
    end
    if (not n or n <= 0) then
        n = math.max(emptyFromStats, maxGemIdx, (emptyFromStats > 0 or maxGemIdx > 0) and (emptyFromStats + maxGemIdx) or 0)
    end
    if n > MAX_GEAR_ITEM_SOCKETS then n = MAX_GEAR_ITEM_SOCKETS end
    if n <= 0 then return entries, "" end

    local emptySuffixQueue = CollectEmptySocketSuffixesFromStats(stats)
    local eq = 1

    local sigParts = {}
    for i = 1, n do
        local gem = GetItemGemForSocket(itemLink, i)
        if gem then
            local id = nil
            pcall(function()
                if C_Item and C_Item.GetItemInfoInstant then
                    id = C_Item.GetItemInfoInstant(gem)
                end
            end)
            if not id and not (issecretvalue and issecretvalue(gem)) then
                local m = gem:match("item:(%d+)")
                id = m and tonumber(m) or nil
            end
            entries[#entries + 1] = { gemLink = gem, emptyTexture = nil }
            sigParts[#sigParts + 1] = "g" .. tostring(id or 0)
        else
            local suf = emptySuffixQueue[eq]
            eq = eq + 1
            local tex = (suf and EMPTY_SOCKET_TEX_BY_SUFFIX[suf]) or EMPTY_SOCKET_TEX_DEFAULT
            entries[#entries + 1] = { gemLink = nil, emptyTexture = tex }
            sigParts[#sigParts + 1] = "e" .. tostring(i) .. ":" .. tostring(suf or "p")
        end
    end
    return entries, table.concat(sigParts, ":")
end

local function PlaceGearSocketClusterInSlotBottom(btn, cluster)
    if not btn or not cluster then return end
    cluster:ClearAllPoints()
    local anchor = btn.iconTex or btn
    cluster:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 5)
end

local function HideGearSocketCluster(btn)
    local c = btn and btn._gearSocketCluster
    if c then c:Hide() end
end

--- Layout mode for paperdoll flanks: left column + main hand vs right column + off-hand.
local function GetGearStatusLayoutMode(side)
    if side == "left" or side == "bottom" or side == "bottom_left" then
        return "left"
    end
    if side == "right" or side == "bottom_right" then
        return "right"
    end
    return "left"
end

local function EnsureGearOuterSideHost(btn)
    if not btn._gearOuterSideHost then
        local outer = GearFact:CreateContainer(btn, STATUS_OUTER_COL_W, STATUS_OUTER_COL_H, false)
        local gemCell = GearFact:CreateContainer(outer, STATUS_OUTER_COL_W, STATUS_OUTER_ICON, false)
        local encCell = GearFact:CreateContainer(outer, STATUS_OUTER_COL_W, STATUS_OUTER_ICON, false)
        outer:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 2)
        outer._gemCell = gemCell
        outer._encCell = encCell
        btn._gearOuterSideHost = outer
    end
    return btn._gearOuterSideHost
end

--- Outer column: gem + enchant stacked when both; single cell vertically centered when only one.
local function ApplyGearOuterSideCellLayout(outer, gemCell, encCell, hasGem, hasEnc)
    gemCell:ClearAllPoints()
    encCell:ClearAllPoints()
    if hasGem and hasEnc then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_COL_H)
        gemCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        gemCell:SetPoint("TOPRIGHT", outer, "TOPRIGHT", 0, 0)
        encCell:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 0, 0)
        encCell:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", 0, 0)
        gemCell:Show()
        encCell:Show()
    elseif hasGem then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetPoint("CENTER", outer, "CENTER", 0, 0)
        gemCell:Show()
        encCell:SetSize(1, 1)
        encCell:Hide()
    elseif hasEnc then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetPoint("CENTER", outer, "CENTER", 0, 0)
        encCell:Show()
        gemCell:SetSize(1, 1)
        gemCell:Hide()
    else
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_COL_H)
        gemCell:SetSize(1, 1)
        encCell:SetSize(1, 1)
        gemCell:Hide()
        encCell:Hide()
    end
end

--- Gem/enchant on outer (track) side; mirrored for right column.
local function PlaceGearOuterSideHost(btn, side, hasGem, hasEnc)
    local icon = btn.iconTex or btn
    local mode = GetGearStatusLayoutMode(side)
    local outer = EnsureGearOuterSideHost(btn)
    local gemCell = outer._gemCell
    local encCell = outer._encCell
    outer:ClearAllPoints()
    ApplyGearOuterSideCellLayout(outer, gemCell, encCell, hasGem, hasEnc)
    local cx = (mode == "left") and -(SLOT_HALF + STATUS_HOST_GAP + STATUS_OUTER_COL_W / 2)
        or (SLOT_HALF + STATUS_HOST_GAP + STATUS_OUTER_COL_W / 2)
    outer:SetPoint("CENTER", icon, "CENTER", cx, 0)
    return outer, gemCell, encCell
end

--- Upgrade chip: optional green border (outer) + dark fill + arrow; and/or lock.
local function PlaceGearUpgradeLockTowardModel(btn, icon, side, upgradeArrowBgBorder, upgradeArrowBg, upgradeArrow, lockIcon)
    if not icon then return end
    local baseSz = STATUS_UPGRADE_ICON - 2 * STATUS_ICON_INSET
    local uSz = math.max(10, math.floor(baseSz * STATUS_UPGRADE_DRAW_MULT + 0.5))
    local inset = math.max(1, math.floor(STATUS_ICON_INSET + 0.5))
    local yInset = -inset
    local bgPad = STATUS_UPGRADE_BG_PAD
    local bgSz = uSz + 2 * bgPad
    local br = STATUS_UPGRADE_BORDER
    local borderSz = bgSz + 2 * br

    local function cornerAt(tex, sz, dx, dy)
        if not tex then return end
        tex:SetSize(sz, sz)
        tex:ClearAllPoints()
        if side == "left" or side == "bottom_left" then
            tex:SetPoint("TOPLEFT", icon, "TOPLEFT", dx, dy)
        elseif side == "right" or side == "bottom_right" then
            tex:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -dx, dy)
        else
            tex:SetPoint("TOP", icon, "TOP", 0, dy)
        end
    end

    if upgradeArrow then
        if upgradeArrowBgBorder and upgradeArrowBg then
            cornerAt(upgradeArrowBgBorder, borderSz, inset - br, yInset + br)
            upgradeArrowBg:SetSize(bgSz, bgSz)
            upgradeArrowBg:ClearAllPoints()
            upgradeArrowBg:SetPoint("CENTER", upgradeArrowBgBorder, "CENTER", 0, 0)
        elseif upgradeArrowBg then
            cornerAt(upgradeArrowBg, bgSz, inset - 1, yInset + 1)
        end
        upgradeArrow:SetSize(uSz, uSz)
        upgradeArrow:ClearAllPoints()
        if upgradeArrowBg then
            upgradeArrow:SetPoint("CENTER", upgradeArrowBg, "CENTER", 0, 0)
        elseif side == "left" or side == "bottom_left" then
            upgradeArrow:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            upgradeArrow:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        else
            upgradeArrow:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end

    if lockIcon then
        local lockSz = math.max(12, math.floor(baseSz * 0.88 + 0.5))
        lockIcon:SetSize(lockSz, lockSz)
        lockIcon:ClearAllPoints()
        if side == "left" or side == "bottom_left" then
            lockIcon:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            lockIcon:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        else
            lockIcon:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end
end

--- Upgrade chip on slot icon (green = affordable, yellow = upgrade path but short on crests).
---@param btn Frame
---@param slotData table|nil
---@param notUpgradeable boolean|nil
local function GearSlotRefreshUpgradeArrow(btn, slotData, notUpgradeable)
    if not btn or not btn._gearUpgradeArrow then return end
    local slotID = btn._slotID
    local hasItem = slotData and slotData.itemLink and slotData.itemLink ~= ""
        and not (issecretvalue and issecretvalue(slotData.itemLink))
    if not hasItem then
        btn._gearUpgradeArrow:Hide()
        if btn._gearUpgradeArrowBgBorder then btn._gearUpgradeArrowBgBorder:Hide() end
        if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Hide() end
        return
    end
    local up = btn._gearUpgradeInfo and btn._gearUpgradeInfo[slotID]
    local currencies = btn._gearCurrencyAmounts
    local canAfford = up and up.canUpgrade and not notUpgradeable and (
        up.canAffordNext == true
        or (ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(up, currencies))
    )
    local showUpChip = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE
        or (canAfford == true)
    if showUpChip then
        btn._gearUpgradeArrow:Show()
        if btn._gearUpgradeArrowBgBorder then btn._gearUpgradeArrowBgBorder:Show() end
        if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Show() end
        if btn._gearUpgradeArrow.SetVertexColor then
            if GEAR_DEBUG_ALWAYS_SHOW_UPGRADE or canAfford then
                if btn._gearUpgradeArrowCraftedAtlas then
                    btn._gearUpgradeArrow:SetVertexColor(1, 1, 1)
                else
                    btn._gearUpgradeArrow:SetVertexColor(0.2, 1, 0.5)
                end
            else
                btn._gearUpgradeArrow:SetVertexColor(1, 0.9, 0.35)
            end
        end
    else
        btn._gearUpgradeArrow:Hide()
        if btn._gearUpgradeArrowBgBorder then btn._gearUpgradeArrowBgBorder:Hide() end
        if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Hide() end
    end
    btn._gearLastCanAffordNext = canAfford == true
end

local function GearSlotClearPaperdollOverlays(btn)
    if not btn then return end
    HideGearSocketCluster(btn)
    if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
    if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    if btn.missingGemIcon then btn.missingGemIcon:Hide() end
    if btn._gearOuterSideHost then btn._gearOuterSideHost:Hide() end
    if btn.warnIcon then btn.warnIcon:Hide() end
end

local function UpdateGearSocketCluster(btn, entries, opts)
    opts = opts or {}
    if not btn then return end
    if not entries or #entries == 0 then
        HideGearSocketCluster(btn)
        return
    end
    local gemPx = tonumber(opts.gemPx)
    local gemGap = tonumber(opts.gemGap)
    if gemGap == nil then
        gemGap = opts.anchorCell and 0 or GEAR_SOCKET_GEM_GAP
    end
    if not gemPx and opts.anchorCell then
        local capW = STATUS_OUTER_COL_W
        local n = #entries
        if n > 0 then
            gemPx = math.floor((capW - math.max(0, n - 1) * gemGap) / n)
            if gemPx < 8 then gemPx = 8 end
            if gemPx > capW - 2 then gemPx = math.max(8, capW - 2) end
        else
            gemPx = GEAR_SOCKET_GEM_PX
        end
    elseif not gemPx then
        gemPx = GEAR_SOCKET_GEM_PX
    end
    if gemPx < 6 then gemPx = 6 end
    if not btn._gearSocketCluster then
        local f = GearFact:CreateContainer(btn, 24, 24, false)
        f:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 3)
        btn._gearSocketCluster = f
        f._gemTex = {}
    end
    local f = btn._gearSocketCluster
    local gems = f._gemTex
    local n = #entries
    local w = n * gemPx + math.max(0, n - 1) * gemGap
    f:SetSize(w, gemPx)
    for i = 1, MAX_GEAR_ITEM_SOCKETS do
        local t = gems[i]
        if i <= n then
            if not t then
                t = f:CreateTexture(nil, "OVERLAY", nil, 7)
                gems[i] = t
                t:SetSize(gemPx, gemPx)
            else
                t:SetSize(gemPx, gemPx)
            end
            local e = entries[i]
            if e and e.gemLink then
                local ic = GetGearGemIconTexture(e.gemLink)
                if ic then
                    if type(ic) == "number" then
                        t:SetTexture(ic)
                    else
                        t:SetTexture(ic)
                    end
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                else
                    t:SetTexture("Interface\\Icons\\INV_Misc_Gem_01")
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            else
                local texPath = (e and e.emptyTexture) or EMPTY_SOCKET_TEX_DEFAULT
                t:SetTexture(texPath)
                t:SetTexCoord(0, 1, 0, 1)
            end
            t:ClearAllPoints()
            local x0 = (i - 1) * (gemPx + gemGap)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0)
            t:Show()
        elseif t then
            t:Hide()
        end
    end
    f:Show()
    f:ClearAllPoints()
    if opts.anchorCell then
        f:SetPoint("CENTER", opts.anchorCell, "CENTER", 0, 0)
    else
        PlaceGearSocketClusterInSlotBottom(btn, f)
    end
end

--- GetItemStats + socket scan per slot is expensive when multiplied by ~16 slots on Gear first paint.
--- Run once on the next frame (WN-PERF heavy tab first paint).
local function GearSlotApplyDeferredEnchantGemInspect(btn)
    if not btn then return end
    local slotData = btn._slotDataRef
    local slotID = btn._slotID
    local st = btn._gearInspectSt
    local ctx = btn._gearLayoutCtx
    if not slotData or not slotData.itemLink or not st or not ctx then
        GearSlotClearPaperdollOverlays(btn)
        return
    end
    local link = slotData.itemLink
    if issecretvalue and issecretvalue(link) then
        st.socketEntries = nil
        st.socketSig = ""
        st.ready = true
        GearSlotClearPaperdollOverlays(btn)
        return
    end

    st.hasEnchant = ItemLinkHasEnchantment(link)
    local stats = GetItemStats and GetItemStats(link) or {}
    st.isMissingGem = false
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k)) and string.find(k, "EMPTY_SOCKET_", 1, true) then
            st.isMissingGem = true
            break
        end
    end
    st.isEnchantable = ns.GearUI_IsPrimaryEnchantExpected(slotID, slotData)
    st.craftingQualityTier = GetGearSlotEnchantQualityTier(link)

    local sockEntries, sockSig = ComputeGearSocketLayout(link, slotID, btn._gearIsCurrentChar == true)
    sockSig = sockSig or ""
    if st.ready and st.socketSig == sockSig then
        local notUp = (slotData and slotData.notUpgradeable) and true or false
        if not notUp and btn._gearUpgradeInfo and slotID then
            local up = btn._gearUpgradeInfo[slotID]
            if up and up.notUpgradeable then notUp = true end
        end
        GearSlotRefreshUpgradeArrow(btn, slotData, notUp)
        return
    end
    st.socketEntries = sockEntries
    st.socketSig = sockSig

    local hasEnchant = st.hasEnchant
    local isMissingGem = st.isMissingGem
    local isEnchantable = st.isEnchantable
    local showSocketRow = sockEntries and #sockEntries > 0
    local showEnchantQuality = hasEnchant
    local missEnchant = isEnchantable and not hasEnchant
    local craftingQualityTier = st.craftingQualityTier
    local enchantDisplayTier = tonumber(craftingQualityTier) or 1
    if enchantDisplayTier < 1 then enchantDisplayTier = 1 end

    if GEAR_PAPERDOLL_ENCHANT_GEM_ALERTS ~= true then
        missEnchant = false
        isMissingGem = false
    end

    local side = ctx.side
    local upgradeArrow = ctx.upgradeArrow
    local lockIcon = btn._gearLockIcon
    local icon = btn.iconTex or btn

    local showGemHost = showSocketRow or isMissingGem
    local showEnchantHost = showEnchantQuality or missEnchant

    local outer, gemHost, encHost = PlaceGearOuterSideHost(btn, side, showGemHost, showEnchantHost)
    local inner = STATUS_OUTER_ICON - 2 * STATUS_ICON_INSET
    PlaceGearUpgradeLockTowardModel(btn, icon, side, btn._gearUpgradeArrowBgBorder, btn._gearUpgradeArrowBg, upgradeArrow, lockIcon)

    if showGemHost or showEnchantHost then
        outer:Show()
    else
        outer:Hide()
    end

    local encSz = inner
    if showEnchantQuality then
        if not btn.enchantQualityIcon then
            local eqTex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.enchantQualityIcon = eqTex
        end
        SetupGearSlotEnchantQualityTexture(btn.enchantQualityIcon, enchantDisplayTier, encSz)
        btn.enchantQualityIcon:ClearAllPoints()
        btn.enchantQualityIcon:SetPoint("CENTER", encHost, "CENTER", 0, 0)
        btn.enchantQualityIcon:Show()
        if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    elseif missEnchant then
        if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
        if not btn.missingEnchantIcon then
            local ic = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.missingEnchantIcon = ic
        end
        btn.missingEnchantIcon:SetSize(inner, inner)
        btn.missingEnchantIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        btn.missingEnchantIcon:ClearAllPoints()
        btn.missingEnchantIcon:SetPoint("CENTER", encHost, "CENTER", 0, 0)
        btn.missingEnchantIcon:Show()
    else
        if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
        if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    end

    if showSocketRow then
        if btn.missingGemIcon then btn.missingGemIcon:Hide() end
        UpdateGearSocketCluster(btn, st.socketEntries, {
            anchorCell = gemHost,
        })
    elseif isMissingGem then
        HideGearSocketCluster(btn)
        if not btn.missingGemIcon then
            local ic = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.missingGemIcon = ic
        end
        btn.missingGemIcon:SetSize(inner, inner)
        btn.missingGemIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        btn.missingGemIcon:ClearAllPoints()
        btn.missingGemIcon:SetPoint("CENTER", gemHost, "CENTER", 0, 0)
        btn.missingGemIcon:Show()
    else
        HideGearSocketCluster(btn)
        if btn.missingGemIcon then btn.missingGemIcon:Hide() end
    end

    local notUp = (slotData and slotData.notUpgradeable) and true or false
    if not notUp and btn._gearUpgradeInfo and slotID then
        local up = btn._gearUpgradeInfo[slotID]
        if up and up.notUpgradeable then notUp = true end
    end
    GearSlotRefreshUpgradeArrow(btn, slotData, notUp)

    st.ready = true
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
---@param hasUpgradePath boolean|nil if true, show upgrade arrow (next tier exists; may tint when unaffordable)
---@param statusText string|nil e.g. "Veteran 6/6", "Champion 4/8", or nil to show ilvl/"—"
---@param textSide string|nil "right" | "left" | "top" — where to place status text relative to icon
---@param isNotUpgradeable boolean|nil if true, show a lock icon overlay (item confirmed not upgradeable)
---@param centerTextOnIcon boolean|nil if true, center slot name + track text relative to slot icon (weapon row)
---@param upgradeInfo table|nil optional; when set, tooltip shows next upgrade tier and cost for this slot
---@param currencyAmounts table|nil optional; map currencyID -> amount (for "you have X" in tooltip if needed)
---@param itemTooltipContext table|nil optional { level, specID } — rewrite item link for C_TooltipInfo primary-stat lines (Gear tab / viewed character)
---@param charKey string|nil canonical character key for persisted upgrade tooltip append
---@param isCurrentChar boolean|nil live player — enables tooltip scan fallback in GearService
---@return Frame btn
local function CreateSlotButton(parent, slotID, slotData, x, y, hasUpgradePath, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    -- Slot her zaman aynı boyutta; ikon görünmese bile boşluk rezerve (empty texture)
    local btn = GearFact:CreateButton(parent, SLOT_SIZE, SLOT_SIZE, true)
    btn:SetPoint("TOPLEFT", x, y)
    if btn.SetClipsChildren then btn:SetClipsChildren(false) end
    btn._slotID = slotID
    btn._slotDataRef = slotData
    btn._gearUpgradeInfo = upgradeInfo
    btn._gearCurrencyAmounts = currencyAmounts
    btn._gearIsCurrentChar = (isCurrentChar == true)
    btn._gearInspectSt = {
        hasEnchant = false,
        isMissingGem = false,
        isEnchantable = false,
        craftingQualityTier = nil,
        ready = false,
        socketSig = "",
        socketEntries = nil,
    }
    btn._needsDeferredInspect = false
    if slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
        btn._needsDeferredInspect = true
    end
    if parent then
        parent._gearSlotInspectList = parent._gearSlotInspectList or {}
        tinsert(parent._gearSlotInspectList, btn)
    end

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
    local rimInset = GearGetFrameContentInset()
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", rimInset, -rimInset)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -rimInset, rimInset)
    btn.iconTex = tex

    -- ilvl label (bottom-right overlay); font must be set before any SetText (WoW requirement)
    local ilvlLabel = btn:CreateFontString(nil, "OVERLAY")
    ilvlLabel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -rimInset, rimInset)
    ilvlLabel:SetFontObject(SystemFont_Tiny)  -- ensure font set before Populate() ever calls SetText
    if FontManager and FontManager.CreateFontString then
        local fs = FontManager:CreateFontString(btn, GFR("gearSlotIlvl"), "OVERLAY")
        if fs and fs.SetFontObject then
            fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -rimInset, rimInset)
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
            local icon = ns.GearUI_GetItemIconSafe(data.itemLink) or ns.GearUI_GetItemIconSafe(data.itemID)
            if (not icon or icon == 0 or icon == "") and isCurrentChar == true and btn._slotID
                and ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemIcon then
                pcall(function()
                    local loc = ItemLocation:CreateFromEquipmentSlot(btn._slotID)
                    if loc and loc:IsValid() then
                        local ic = C_Item.GetItemIcon(loc)
                        if ic and ic ~= 0 and ic ~= "" then icon = ic end
                    end
                end)
            end
            if icon then
                tex:SetVertexColor(1, 1, 1, 1)
                tex:SetTexture(icon)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif not (issecretvalue and issecretvalue(data.itemLink)) then
                -- Item cache not warmed yet — avoid empty-slot art while link is valid.
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
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
            GearSlotClearPaperdollOverlays(btn)
        end
    end

    Populate(slotData)

    local side = textSide or "right"
    local upgradeArrow = nil

    local isBottomLeft  = (side == "bottom" or side == "bottom_left")
    local isBottomRight = (side == "bottom_right")

    -- Ortadan çizgi: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ/alt)
    local upSlot = upgradeInfo and upgradeInfo[slotID]
    local isCraftedSlot = upSlot and upSlot.isCrafted
    local canAffordNext = upSlot and upSlot.canUpgrade and (
        upSlot.canAffordNext == true
        or (ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(upSlot, currencyAmounts))
    )
    local statusUpgradeSz = STATUS_UPGRADE_ICON - 2 * STATUS_ICON_INSET
    local wantDebugUpgrade = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE == true and slotData and slotData.itemLink
        and not (issecretvalue and issecretvalue(slotData.itemLink))
    -- Always reserve an arrow texture when the slot has an item (unless lock-only), so a late upgradeInfo refresh can still show/hide in _gearApplySlotVisual.
    local hasItemNow = slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink))
    local lockOnly = isNotUpgradeable and hasItemNow and not wantDebugUpgrade
    if not lockOnly and (hasUpgradePath or wantDebugUpgrade or hasItemNow) then
        local upgradeBd = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrowBgBorder = upgradeBd
        upgradeBd:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        upgradeBd:SetVertexColor(0.1, 0.78, 0.26, 0.95)
        if upgradeBd.SetDrawLayer then upgradeBd:SetDrawLayer("OVERLAY", 5) end
        if upgradeBd.SetFrameLevel and btn.GetFrameLevel then
            upgradeBd:SetFrameLevel((btn:GetFrameLevel() or 0) + 2)
        end

        local upgradeBg = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrowBg = upgradeBg
        upgradeBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        upgradeBg:SetVertexColor(0, 0, 0, 0.88)
        if upgradeBg.SetDrawLayer then upgradeBg:SetDrawLayer("OVERLAY", 6) end
        if upgradeBg.SetFrameLevel and btn.GetFrameLevel then
            upgradeBg:SetFrameLevel((btn:GetFrameLevel() or 0) + 3)
        end

        upgradeArrow = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrow = upgradeArrow
        if upgradeArrow.SetFrameLevel and btn.GetFrameLevel then
            upgradeArrow:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
        end
        local useCraftedAtlas = isCraftedSlot and hasUpgradePath and canAffordNext
        btn._gearUpgradeArrowCraftedAtlas = (useCraftedAtlas == true)
        if useCraftedAtlas and upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("Professions-Crafting-Orders-Icon", false)
            if upgradeArrow.SetVertexColor then upgradeArrow:SetVertexColor(1, 1, 1) end
        elseif upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("loottoast-arrow-green", false)
            if upgradeArrow.SetVertexColor then upgradeArrow:SetVertexColor(0.2, 1, 0.48) end
        else
            upgradeArrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            upgradeArrow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            upgradeArrow:SetVertexColor(0.15, 1, 0.42)
        end
        if upgradeArrow.SetDrawLayer then upgradeArrow:SetDrawLayer("OVERLAY", 7) end
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, upgradeBd, upgradeBg, upgradeArrow, nil)
    elseif lockOnly then
        local lockIcon = btn:CreateTexture(nil, "OVERLAY")
        btn._gearLockIcon = lockIcon
        lockIcon:SetSize(statusUpgradeSz, statusUpgradeSz)
        if lockIcon.SetFrameLevel and btn.GetFrameLevel then
            lockIcon:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
        end
        if lockIcon.SetDrawLayer then lockIcon:SetDrawLayer("OVERLAY", 7) end
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, nil, nil, nil, lockIcon)
        lockIcon:SetTexture("Interface\\Common\\LockIcon")
        lockIcon:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    end

    -- Tooltip: item link + simplified upgrade info (custom tooltip service)
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]

    -- Enchant/gem/socket scan deferred to next frame (see GearSlotApplyDeferredEnchantGemInspect).
    btn._gearLayoutCtx = { side = side, upgradeArrow = upgradeArrow, upgradeArrowBg = btn._gearUpgradeArrowBg, upgradeArrowBgBorder = btn._gearUpgradeArrowBgBorder }

    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            local up = upgradeInfo and upgradeInfo[slotID]
            local additionalLines = {}
            local underTitleLines

            -- Stat / enchant / gem body comes from C_TooltipInfo.GetHyperlink in TooltipService (Blizzard lines + icons).
            -- Only append Warband-specific upgrade / recraft hints below.

            if up and up.isCrafted then
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                local tierLabel = LocalizeUpgradeTrackName(up.craftedTierName or "Crafted")
                if not up.canUpgrade then
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_CRAFTED_MAX_ILVL_LINE"]) or "%s (max ilvl %d)", tierLabel, up.currentIlvl or 0),
                        color = { 0.6, 0.6, 0.6 }
                    }
                else
                    local range = ns.GearUI_GetCraftedIlvlRange(up, currencyAmounts)
                    if range then
                        local bestName = LocalizeUpgradeTrackName(range.bestCrestName or "")
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_CRAFTED_RECAST_TO_LINE"]) or "Recraft to %s (ilvl %d)", bestName, range.maxIlvl),
                            color = { 0.4, 1, 0.4 }
                        }
                    else
                        additionalLines[#additionalLines + 1] = {
                            text = (ns.L and ns.L["GEAR_CRAFTED_NO_CRESTS"]) or "No crests available for recraft",
                            color = { 0.8, 0.5, 0.2 }
                        }
                    end
                end
            elseif up and up.canUpgrade then
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                local affordable = up.affordableUpgrades
                local goldOnly = up.goldOnlyUpgrades
                if affordable == nil and ns.GearUI_CalculateAffordableUpgrades then
                    affordable, goldOnly = ns.GearUI_CalculateAffordableUpgrades(up, currencyAmounts)
                end
                affordable = affordable or 0
                goldOnly = goldOnly or 0
                if affordable > 0 then
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
                    local crestNeed = (ns.GearUI_GetNextStepCrestNeed and ns.GearUI_GetNextStepCrestNeed(up)) or (up.crestCost or 20)
                    local cid = up.currencyID or 0
                    local haveCrests = (currencyAmounts and currencyAmounts[cid]) or 0
                    local goldCopper = (ns.GearUI_GetGearCurrencyGoldCopper and ns.GearUI_GetGearCurrencyGoldCopper(currencyAmounts))
                        or ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
                    local goldNeed = up.moneyCost or (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000)
                    if crestNeed > 0 then
                        local crestWord = (ns.L and ns.L["GEAR_TT_DAWNCREST_WORD"]) or "Dawncrest"
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_TT_NEXT_STEP_CRESTS"]) or "Next step: %d %s.", crestNeed, crestWord),
                            color = { 0.85, 0.85, 0.85 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_NEED_MORE_CRESTS_FORMAT"]) or "%s %d/%d - need more crests", LocalizeUpgradeTrackName(up.trackName or ""), haveCrests, crestNeed),
                            color = { 1, 0.55, 0.25 }
                        }
                    elseif goldCopper < goldNeed then
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_TT_NEXT_STEP_GOLD_ONLY"]) or "Next step: gold only (you already reached this item level on this slot)."),
                            color = { 1, 0.85, 0.4 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format("Gold %d / %d", math.floor(goldCopper / 10000), math.floor(goldNeed / 10000)),
                            color = { 1, 0.55, 0.25 }
                        }
                    else
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_NEED_MORE_CRESTS_FORMAT"]) or "%s %d/%d - need more crests", LocalizeUpgradeTrackName(up.trackName or ""), haveCrests, crestNeed),
                            color = { 1, 0.55, 0.25 }
                        }
                    end
                end
            end

            if #additionalLines == 0 then
                additionalLines = nil
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
    -- Labels: API slot 11 = first finger, 12 = second (matches default Character frame top-to-bottom).
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
        btn._gearTrackLabel = trackLabel
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
            local blockCenterOffset = 8
            trackLabel:ClearAllPoints()
            trackLabel:SetWidth(textWidth or TRACK_TEXT_W)
            trackLabel:SetPoint("CENTER", btn, "CENTER", textCenterX, -blockCenterOffset)

            if side == "left" or isBottomLeft then
                trackLabel:SetJustifyH("RIGHT")
            elseif side == "right" or isBottomRight then
                trackLabel:SetJustifyH("LEFT")
            else
                trackLabel:SetJustifyH("CENTER")
            end

            if slotNameLabel then
                slotNameLabel:ClearAllPoints()
                slotNameLabel:SetPoint("BOTTOM", trackLabel, "TOP", 0, 2)
                if side == "left" or isBottomLeft then
                    slotNameLabel:SetPoint("RIGHT", trackLabel, "RIGHT", 0, 0)
                    slotNameLabel:SetJustifyH("RIGHT")
                elseif side == "right" or isBottomRight then
                    slotNameLabel:SetPoint("LEFT", trackLabel, "LEFT", 0, 0)
                    slotNameLabel:SetJustifyH("LEFT")
                else
                    slotNameLabel:SetPoint("CENTER", trackLabel, "CENTER", 0, 0)
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

    function btn._gearApplySlotVisual(self, slotData, canUpgrade, trackStatusText, notUpgradeable)
        local prev = self._slotDataRef
        local prevLink = prev and prev.itemLink
        local newLink = slotData and slotData.itemLink
        local function linkEmpty(l)
            return not l or l == "" or (issecretvalue and issecretvalue(l))
        end
        local linkUnchanged = linkEmpty(newLink) == linkEmpty(prevLink)
            and (linkEmpty(newLink) or newLink == prevLink)

        self._slotDataRef = slotData
        self._needsDeferredInspect = false
        if slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
            local st = self._gearInspectSt
            if not linkUnchanged or not st or not st.ready then
                self._needsDeferredInspect = true
            end
        end
        if not linkUnchanged then
            if self._gearInspectSt then
                self._gearInspectSt.ready = false
                self._gearInspectSt.socketSig = ""
                self._gearInspectSt.socketEntries = nil
            end
            GearSlotClearPaperdollOverlays(self)
        end
        Populate(slotData)
        if self._gearTrackLabel then
            local t = (type(trackStatusText) == "string" and trackStatusText ~= "") and trackStatusText or ""
            if t == "" then
                self._gearTrackLabel:Hide()
            else
                self._gearTrackLabel:SetText(t)
                self._gearTrackLabel:Show()
            end
        end
        GearSlotRefreshUpgradeArrow(self, slotData, notUpgradeable)
        if self._gearLockIcon then
            if notUpgradeable and slotData and slotData.itemLink then self._gearLockIcon:Show() else self._gearLockIcon:Hide() end
        end
        self._gearLastCanAffordNext = canUpgrade == true
    end

    local upInit = upgradeInfo and upgradeInfo[slotID]
    local canAffordInit = upInit and upInit.canUpgrade and (
        upInit.canAffordNext == true
        or (ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(upInit, currencyAmounts))
    )
    local trackTextInit = (statusText and statusText ~= "") and statusText or nil
    btn:_gearApplySlotVisual(slotData, canAffordInit, trackTextInit, isNotUpgradeable)

    return btn
end

-- ============================================================================
-- PAPERDOLL CARD  (full width; doll centered like Characters screen)
-- ============================================================================

local CURRENCY_ROW_H = 26
local ROW_H = 34

--- Build track/tier string from upgradeInfo[slotID], e.g. "Veteran 2/6".
--- For crafted items, shows tier name + ilvl (e.g. "Myth 285") or upgrade arrow (e.g. "Hero → Myth 285").
local function GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)
    local up = upgradeInfo and upgradeInfo[slotID]
    if not up then return nil end

    -- Crafted items: show current tier + achievable recraft target
    if up.isCrafted then
        local currentEnglish = up.craftedTierName or "Crafted"
        local currentTier = LocalizeUpgradeTrackName(currentEnglish)
        local range = currencyAmounts and ns.GearUI_GetCraftedIlvlRange(up, currencyAmounts) or nil
        local canRecast = range and range.maxIlvl > (up.currentIlvl or 0)
            and (up.canAffordNext == true
                or (currencyAmounts and ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(up, currencyAmounts)))
        if canRecast then
            local bestEnglish = range.bestCrestName or ""
            return FormatTrackMarkup(currentEnglish, currentTier, quality)
                .. " → "
                .. FormatTrackMarkup(bestEnglish, LocalizeUpgradeTrackName(bestEnglish) .. " " .. tostring(range.maxIlvl), quality)
        end
        return FormatTrackMarkup(currentEnglish, currentTier .. " " .. tostring(up.currentIlvl or 0), quality)
    end

    local englishTrack = up.trackName
    local track = (englishTrack and englishTrack ~= "") and LocalizeUpgradeTrackName(englishTrack) or nil
    local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
    if maxT and maxT > 0 and track then
        local base = FormatTrackMarkup(englishTrack, track .. " " .. tostring(curT) .. "/" .. tostring(maxT), quality)
        local aff = up.affordableUpgrades
        if (not aff or aff == 0) and currencyAmounts and ns.GearUI_CalculateAffordableUpgrades then
            aff = select(1, ns.GearUI_CalculateAffordableUpgrades(up, currencyAmounts))
        end
        local canAffordNext = up.canAffordNext == true
            or (currencyAmounts and ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(up, currencyAmounts))
        if canAffordNext and aff and aff > 0 then
            local targetTier = curT + aff
            local TRACK_ILVLS = ns.TRACK_ILVLS
            local tiers = TRACK_ILVLS and TRACK_ILVLS[englishTrack]
            local ilvlSuffix = (tiers and tiers[targetTier]) and (" " .. tostring(tiers[targetTier])) or ""
            return base .. "|cff66ff66 → " .. tostring(targetTier) .. "/" .. tostring(maxT) .. ilvlSuffix .. "|r"
        end
        return base
    end
    if track and track ~= "" then return FormatTrackMarkup(englishTrack, track, quality) end
    return nil
end

--- Offline character center panel: class-accent top rule + bottom bar with badge (3D/2D preview only).
---@param centerRef Frame
---@param classFile string|nil
local function ApplyGearOfflineCenterChrome(centerRef, classFile)
    if not centerRef then return end
    local chrome = ns._gearOfflineCenterChrome
    if not chrome then
        chrome = GearFact:CreateContainer(centerRef, 100, 100, false)
        chrome:SetAllPoints()
        chrome:EnableMouse(false)
        chrome:EnableMouseWheel(false)
        chrome.isPersistentRowElement = true
        local topLine = chrome:CreateTexture(nil, "ARTWORK", nil, 2)
        topLine:SetHeight(2)
        topLine:SetPoint("TOPLEFT", chrome, "TOPLEFT", 0, -1)
        topLine:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", 0, -1)
        chrome._topLine = topLine
        local bar = GearFact:CreateContainer(chrome, 100, 36, false)
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

--- Draw paperdoll: sol panel (yazı-ikon-slot) | orta (model) | sağ panel (slot-ikon-yazı).
--- paperParent: left column host (coordinates relative to its TOPLEFT).
--- baseX: inset from paperParent left (typically PAPERDOLL_COL_INSET).
--- paperOriginY: Y offset from paperParent TOPLEFT (0 when parent is leftColHost).
local function DrawPaperDollInCard(paperParent, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar, baseX, charKey, paperOriginY, paperdollNaturalH, paperBandH, opts)
    opts = opts or {}
    paperParent = paperParent or opts.cardRef
    local card = opts.cardRef or paperParent
    baseX = baseX or PAPERDOLL_COL_INSET
    local modelW = MODEL_W + (tonumber(opts.modelBoost) or 0)
    card._gearSlotInspectList = {}
    local itemTooltipContext = ns.GearUI_BuildGearTabItemTooltipContext(charData)
    -- Sol panel: fixed width; slot sağda (yazı - ikon - slot)
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local leftColRight = baseX + LEFT_PANEL_W
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP

    local slots = gearData and gearData.slots or {}
    local function GetSlotData(slotID) return slots[slotID] end
    local function HasUpgradePathForSlot(slotID)
        local up = upgradeInfo and upgradeInfo[slotID]
        return ns.GearUI_GearUpgradeInfoHasPath and ns.GearUI_GearUpgradeInfoHasPath(up)
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
        anchorY = 0
    end
    local startY = anchorY - vertCenterPad

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i = 1, #leftSlots do
        local slotID = leftSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(paperParent, slotID, GetSlotData(slotID), leftX, startY - (i - 1) * rowStep, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    -- Right column: 6 armor + 2 trinkets — slot | ikon | yazı (finger slots 11 then 12 = API order).
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i = 1, #rightSlots do
        local slotID = rightSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(paperParent, slotID, GetSlotData(slotID), rightX, startY - (i - 1) * rowStep, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    -- Alt panel: slot üstte, altında ikon + yazı (yazılar aşağı); silahlar birbirine yakın
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local WEAPON_TEXT_W = TRACK_TEXT_W
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (modelW + CENTER_GAP - weaponRowW) / 2
    local maxRows = math.max(#leftSlots, #rightSlots)
    local bottomY = startY - maxRows * rowStep - 8
    for i = 1, #weaponSlots do
        local slotID = weaponSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        local weaponSide = (i == 1) and "bottom_left" or "bottom_right"  -- Main Hand solunda, Off Hand sağında
        CreateSlotButton(paperParent, slotID, GetSlotData(slotID), wx, bottomY, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- trinket altına kadar
    local modelX    = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY

    local function runPaperdollCenterPaint()
        local classFile = charData and charData.classFile
        local accent    = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }
        if ns._gearPaperdollCenterPlaceholder then
            ns._gearPaperdollCenterPlaceholder:Hide()
        end
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
            local rimInsetPan = GearGetFrameContentInset()
            local tex = pan:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", pan, "TOPLEFT", rimInsetPan, -rimInsetPan)
            tex:SetPoint("BOTTOMRIGHT", pan, "BOTTOMRIGHT", -rimInsetPan, rimInsetPan)
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            pan._tex = tex
            pan.isPersistentRowElement = true
            ns._gearPortraitPanel = pan
        end
        if not pan._wnGearTooltipPanelBg then
            ApplyGearModelViewportFill(pan)
            pan._wnGearTooltipPanelBg = true
        end
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
        ApplyGearModelViewportFill(clip)
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
        local il = GearFact:CreateContainer(clip, math.max(1, clip:GetWidth() or modelW), math.max(1, clip:GetHeight() or MODEL_H), false)
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

    -- Offline alts: no DressUpModel / 2D portrait — class card only (see block below).
    if isCurrentChar ~= true then
        if ns._gearDressModel then ns._gearDressModel:Hide() end
        if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
        if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
    elseif not centerRef then
        local clip = AcquireGearDressModel()
        if not clip._wnGearTooltipPanelBg then
            ApplyGearModelViewportFill(clip)
            clip._wnGearTooltipPanelBg = true
        end
        if clip._SetClassTint then clip:_SetClassTint(classFile) end
        clip._viewCharKey = charKey
        local m = clip._model
        if clip:GetParent() ~= scrollParent then clip:SetParent(scrollParent) end
        clip:ClearAllPoints()
        clip:SetSize(modelW, MODEL_H)
        clip:SetPoint("TOPLEFT", paperParent, "TOPLEFT", modelX, modelTopY)
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

    -- Online (current character) 2D portrait fallback: only when the live DressUpModel
    -- failed AND we're on the player. SetPortraitTexture("player") is reliable; we never
    -- run SetPortraitTextureFromCreatureDisplayID for offline alts here.
    if not centerRef and isCurrentChar == true then
        local pan = AcquireGearPortraitPanel()
        if pan:GetParent() ~= scrollParent then pan:SetParent(scrollParent) end
        pan:ClearAllPoints()
        pan:SetSize(modelW, MODEL_H)
        pan:SetPoint("TOPLEFT", paperParent, "TOPLEFT", modelX, modelTopY)
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
            name:SetWidth(modelW - 16)
            name:SetJustifyH("CENTER")
            name:SetShadowOffset(1, -1)
            name:SetShadowColor(0, 0, 0, 0.95)
            portrait._name = name

            -- "Lv N · Race" meta line.
            local meta = FontManager:CreateFontString(portrait, GFR("gearPortraitMeta"), "OVERLAY")
            meta:SetPoint("TOP", name, "BOTTOM", 0, -2)
            meta:SetWidth(modelW - 16)
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
        portrait:SetSize(modelW, MODEL_H)
        portrait:SetPoint("TOPLEFT", paperParent, "TOPLEFT", modelX, modelTopY)
        portrait:SetFrameLevel(card:GetFrameLevel() + 5)
        ApplyGearModelViewportFill(portrait)

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
        ilvlFrame = GearFact:CreateContainer(card, 120, 22, false)
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
        nameWrapper = GearFact:CreateContainer(card, 200, 20, false)
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

    if card._wnGearHeroRibbon then
        if nameWrapper and nameWrapper.Hide then nameWrapper:Hide() end
        if ilvlFrame and ilvlFrame.Hide then ilvlFrame:Hide() end
    elseif displayName ~= "" then
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

    if opts and opts.deferCenter then
        local ph = ns._gearPaperdollCenterPlaceholder
        if not ph then
            ph = CreateFrame("Frame", nil, card, "BackdropTemplate")
            ph.isPersistentRowElement = true
            ns._gearPaperdollCenterPlaceholder = ph
        end
        ph:SetParent(card)
        ph:ClearAllPoints()
        ph:SetSize(modelW, MODEL_H)
        ph:SetPoint("TOPLEFT", paperParent, "TOPLEFT", modelX, modelTopY)
        ApplyGearModelViewportFill(ph)
        ph:SetFrameLevel((card:GetFrameLevel() or 2) + 3)
        ph:Show()
        card._gearPaperdollCenterDefer = runPaperdollCenterPaint
        return
    end

    runPaperdollCenterPaint()
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

-- Character panel–style stat tints (values / percentages; labels stay neutral).
local GEAR_SECONDARY_STAT_RGB = {
    { 1.00, 0.82, 0.35 },
    { 0.35, 0.95, 0.55 },
    { 0.45, 0.65, 1.00 },
    { 0.78, 0.35, 0.95 },
}

local function GetGearPrimaryStatRGB(statId, classFile)
    if statId == 3 then
        return 0.58, 0.86, 0.48
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    if statId == 1 then return 0.78, 0.61, 0.43 end
    if statId == 2 then return 1.00, 0.82, 0.00 end
    if statId == 4 then return 0.41, 0.80, 0.94 end
    return 1, 1, 1
end

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

--- Viewport-aware gear card height for the left stack + full-height recommendations column.
---@param mf Frame|nil
---@param yOffset number
---@param leftStackH number paperdoll + stats/currencies band
---@param paperdollNaturalH number
---@return number panelH
local function ResolveGearTabPanelHeight(mf, yOffset, leftStackH, paperdollNaturalH)
    local panelH = math.max(leftStackH or 0, paperdollNaturalH or 0)
    local bodyAvailH = (ns.UI_GetMainTabScrollBodyHeight and ns.UI_GetMainTabScrollBodyHeight(mf)) or 0
    if bodyAvailH > 0 then
        local cardChromeV = CARD_PAD + 24 + CARD_PAD
        local maxPanelH = math.max(1, bodyAvailH - math.abs(yOffset or 0) - 12 - cardChromeV)
        panelH = math.max(panelH, maxPanelH)
    end
    return panelH
end

--- Equipped gear card: paperdoll (left) | stats+currencies (right) | recommendations (bottom).
--- charKey: key from dropdown (used for currency/gold lookup).
--- isCurrentChar: true if selected character is the logged-in one (live portrait fallback).
--- currencies: array from GetGearUpgradeCurrenciesFromDB (passed to avoid duplicate API calls).
---@param storageScanPending boolean When true and there are no rows yet, show a loading line instead of the empty-state copy.
local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar, currencies, storageFindings, storageScanPending)
    local rowStep = SLOT_SIZE + SLOT_GAP
    -- Content height: section + slot columns + gap + weapon row (Main/Off Hand) + bottom pad so card border is below weapons
    local HERO_RIBBON_H = GEAR_LAYOUT.HERO_RIBBON_H or 44
    local contentTop = 8
    local weaponBottom = 8 * rowStep + 8 + SLOT_SIZE
    local paperdollNaturalH = contentTop + weaponBottom + CARD_PAD
    currencies = currencies or {}
    -- Stats + currencies band under paperdoll (side by side within paper column width).
    local GEAR_SUBPANEL_PAD = GEAR_LAYOUT.SUBPANEL_PAD or 12
    local GEAR_SUBPANEL_HDR = GEAR_LAYOUT.SUBPANEL_HDR or 36
    local GEAR_STAT_COL_GAP = GEAR_LAYOUT.STAT_COL_GAP or 8
    local cardH = CARD_PAD + HERO_RIBBON_H + 12 + paperdollNaturalH + CARD_PAD

    local parentW = (parent and parent.GetWidth) and parent:GetWidth() or 0

    -- New card on every DrawPaperDollCard: PopulateContent tears down scrollChild, so roster changes cannot reuse the old card here.
    local card = CreateCard(parent, cardH)
    if card.SetClipsChildren then
        card:SetClipsChildren(true)
    end
    local mfDraw = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    AnchorGearCardFillWidth(card, parent, yOffset, mfDraw)
    local cardInnerW = GetGearCardInnerWidthFromCard(card)
    if (card:GetWidth() or 0) < 1 and parentW > 0 then
        cardInnerW = ResolveGearTabCardInnerWidth(parentW)
    end

    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }

    -- ── Crest / gold block heights (drawn under character stats in main column) ──
    local crestCurrencies = {}
    local goldCurrency = nil
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur.isGold then goldCurrency = cur else crestCurrencies[#crestCurrencies + 1] = cur end
    end

    local playbookTooltipPayload = nil

    -- Currency panel height: header + crest rows + divider + gold + short footer + bottom pad
    local CREST_ROW_H = GEAR_LAYOUT.CREST_ROW_H or 28
    local FOOTER_HINT_H = 20
    local FOOTER_HINT_PAD = 10

    local PANEL_GAP = GEAR_PANEL_GAP
    local recEnabled = WarbandNexus:IsGearStorageRecommendationsEnabled()
    if ns.GearUI_ClampCardInnerWidth then
        cardInnerW = ns.GearUI_ClampCardInnerWidth(cardInnerW)
    end
    local paperColW, sideColW, layoutInnerW
    if ns.GearUI_ComputeTopRowLayout then
        _, paperColW, sideColW, layoutInnerW = ns.GearUI_ComputeTopRowLayout(cardInnerW, nil)
    else
        paperColW, sideColW = ComputeGearLayoutWidths(cardInnerW, recEnabled)
        layoutInnerW = cardInnerW
    end
    local topLayoutMode = "row"
    local storageW = layoutInnerW or cardInnerW
    local paperLeft = CARD_PAD

    local panelTopY = -(CARD_PAD + HERO_RIBBON_H + 10)
    local SECTION_GAP = GEAR_LAYOUT.SECTION_GAP or 16
    local modelBoost = math.max(0, math.min(32, paperColW - PAPERDOLL_BLOCK_W - PAPERDOLL_COL_INSET * 2))

    local STAT_ROW_H = GEAR_LAYOUT.STAT_ROW_H or 24
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
                        statId = stat.id,
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
                            statId = stat.id,
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
    local function ComputeGearMidHeights(subHdr, statRowH, crestRowH)
        local statH = subHdr + (statContentRows * statRowH) + (hasDivider and 8 or 0) + 12
        if statContentRows == 0 then
            statH = subHdr + 56
        end
        local currH = subHdr + #crestCurrencies * crestRowH + 12 + 28 + FOOTER_HINT_H + FOOTER_HINT_PAD + 8
        return statH, currH
    end
    local statPanelH, currenciesH = ComputeGearMidHeights(GEAR_SUBPANEL_HDR, STAT_ROW_H, CREST_ROW_H)
    local SIDE_BAND_GAP = GEAR_LAYOUT.SIDE_BAND_GAP or 10
    local _, statColW, currColW, _, sideColNaturalH = "stack", sideColW, sideColW, SIDE_BAND_GAP, statPanelH + SIDE_BAND_GAP + currenciesH
    if ns.GearUI_ComputeSideColumnLayout then
        _, statColW, currColW, _, sideColNaturalH = ns.GearUI_ComputeSideColumnLayout(sideColW, statPanelH, currenciesH, SIDE_BAND_GAP)
    end
    local topZoneNatural = math.max(paperdollNaturalH, sideColNaturalH)
    local leftStackHNatural = topZoneNatural

    local mfHostEarly = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local panelH = ResolveGearTabPanelHeight(mfHostEarly, yOffset, leftStackHNatural, paperdollNaturalH)
    local recZoneH = 0
    if recEnabled and ns.GearUI_ComputeRecBandHeight then
        recZoneH = ns.GearUI_ComputeRecBandHeight(true, panelH, topZoneNatural)
    elseif recEnabled then
        recZoneH = GEAR_LAYOUT.REC_BAND_MIN_H or 200
    end
    if recEnabled and recZoneH > 0 then
        panelH = math.max(panelH, topZoneNatural + SECTION_GAP + recZoneH)
        leftStackHNatural = topZoneNatural + SECTION_GAP + recZoneH
    end
    local paperZoneH = paperdollNaturalH
    local statBandH = statPanelH
    local currBandH = currenciesH
    local yPaperBandTop = panelTopY

    local gearHosts = {
        paperColW = paperColW,
        sideColW = sideColW,
        paperLeft = paperLeft,
        sectionGap = SECTION_GAP,
        recZoneH = recZoneH,
        topZoneH = topZoneNatural,
        topLayoutMode = topLayoutMode,
        layoutInnerW = layoutInnerW,
        paperZoneH = paperZoneH,
        paperdollNaturalH = paperdollNaturalH,
        sideColNaturalH = sideColNaturalH,
        cardInnerW = cardInnerW,
        panelGutter = GEAR_LAYOUT.COL_GAP or PANEL_GAP,
    }
    local gearChrome = ns.GearUI_Chrome
    local heroRibbon = gearChrome and gearChrome.CreateCharacterRibbon
        and gearChrome.CreateCharacterRibbon(card, charData, accent, { height = HERO_RIBBON_H })
    if heroRibbon then
        heroRibbon:ClearAllPoints()
        heroRibbon:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
        heroRibbon:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
        gearHosts.heroRibbon = heroRibbon
        card._wnGearHeroRibbon = true
    end

    EnsureGearCardColumnHosts(card, gearHosts, panelTopY, recEnabled)
    RelayoutGearCardColumnHosts(card, gearHosts, panelTopY, recEnabled)
    local leftCol = gearHosts.leftColHost
    local bodyHost = gearHosts.bodyHost
    local rightCol = gearHosts.rightColHost
    local horizParent = leftCol or card

    local colDiv
    if bodyHost then
        colDiv = bodyHost:CreateTexture(nil, "ARTWORK")
        colDiv:SetColorTexture(accent[1] * 0.18, accent[2] * 0.18, accent[3] * 0.18, 0.40)
        colDiv:SetWidth(1)
        gearHosts.colDivider = colDiv
        local stackDiv = bodyHost:CreateTexture(nil, "ARTWORK")
        stackDiv:SetColorTexture(accent[1] * 0.28, accent[2] * 0.28, accent[3] * 0.28, 0.55)
        stackDiv:SetHeight(1)
        stackDiv:Hide()
        gearHosts.topStackDivider = stackDiv
    end

    local paperChrome = CreateFrame("Frame", nil, horizParent, "BackdropTemplate")
    paperChrome:SetPoint("TOPLEFT", horizParent, "TOPLEFT", 0, 0)
    paperChrome:SetSize(paperColW, paperZoneH)
    paperChrome:EnableMouse(false)
    if paperChrome.SetFrameLevel and card.GetFrameLevel then
        paperChrome:SetFrameLevel((card:GetFrameLevel() or 2) + 1)
    end
    if gearChrome and gearChrome.ApplyPaperdollViewport then
        gearChrome.ApplyPaperdollViewport(paperChrome, accent)
    elseif paperChrome.SetBackdrop then
        pcall(paperChrome.SetBackdrop, paperChrome, nil)
    end
    if paperChrome.SetClipsChildren then
        paperChrome:SetClipsChildren(true)
    end
    gearHosts.paperChrome = paperChrome

    local statPanel = CreateGearSubpanel(rightCol or horizParent, statColW, statBandH, accent)
    statPanel:SetSize(statColW, statPanelH)
    statPanel:SetPoint("TOPLEFT", rightCol or horizParent, "TOPLEFT", 0, 0)
    statPanel:SetPoint("TOPRIGHT", rightCol or horizParent, "TOPRIGHT", 0, 0)
    statPanel:EnableMouse(false)
    if statPanel.SetFrameLevel and rightCol and rightCol.SetFrameLevel then
        rightCol:SetFrameLevel((leftCol and leftCol:GetFrameLevel() or 2) + 2)
        statPanel:SetFrameLevel((paperChrome:GetFrameLevel() or 3) + 2)
    end
    if statPanel.SetClipsChildren then
        statPanel:SetClipsChildren(true)
    end
    gearHosts.statPanel = statPanel

    local currencyPanel = CreateGearSubpanel(rightCol or horizParent, currColW, currBandH, accent)
    currencyPanel:SetSize(currColW, currBandH)
    currencyPanel:SetPoint("TOPLEFT", rightCol or horizParent, "TOPLEFT", 0, -statPanelH - SIDE_BAND_GAP)
    currencyPanel:SetPoint("BOTTOMRIGHT", rightCol or horizParent, "BOTTOMRIGHT", 0, 0)
    currencyPanel:EnableMouse(false)
    if currencyPanel.SetClipsChildren then
        currencyPanel:SetClipsChildren(false)
    end
    if currencyPanel.SetFrameLevel then
        currencyPanel:SetFrameLevel(statPanel:GetFrameLevel() or 5)
    end

    local statCurrDiv = ns._gearStatCurrDiv
    if not statCurrDiv then
        statCurrDiv = card:CreateTexture(nil, "ARTWORK")
        statCurrDiv:SetWidth(1)
        ns._gearStatCurrDiv = statCurrDiv
    end
    statCurrDiv:SetParent(rightCol or horizParent)
    statCurrDiv:SetColorTexture(accent[1] * 0.20, accent[2] * 0.20, accent[3] * 0.20, 0.45)
    local divY = -statPanelH - math.floor(SIDE_BAND_GAP * 0.5)
    statCurrDiv:SetPoint("TOPLEFT", rightCol or horizParent, "TOPLEFT", 0, divY)
    statCurrDiv:SetPoint("TOPRIGHT", rightCol or horizParent, "TOPRIGHT", 0, divY)
    statCurrDiv:SetHeight(1)
    statCurrDiv:Show()
    gearHosts.statCurrDiv = statCurrDiv
    gearHosts.currencyPanel = currencyPanel

    local SUBPANEL_TITLE_INSET = 8
    local statPad = GEAR_SUBPANEL_PAD
    local statInnerW = math.max(1, statColW - statPad * 2)
    local labelColW, valColW, pctColW = ComputeGearStatColumnWidths(statInnerW, GEAR_STAT_COL_GAP)
    statPanel._wnGearStatMetrics = {
        statPad = statPad,
        statColGap = GEAR_STAT_COL_GAP,
        labelColW = labelColW,
        valColW = valColW,
        pctColW = pctColW,
    }
    statPanel._wnGearStatRows = {}
    local statRowRefs = statPanel._wnGearStatRows
    local currPad = GEAR_SUBPANEL_PAD
    -- Amount column width aligned with stats value block (symmetric L/R insets inside each half).
    local currInnerW = math.max(1, currColW - currPad * 2)
    local currAmtReserve = (ns.GEAR_LAYOUT and ns.GEAR_LAYOUT.CURR_AMOUNT_COL_W) or 108
    currencyPanel._wnGearCurrMetrics = {
        currPad = currPad,
        currAmtReserve = currAmtReserve,
        valColW = valColW,
        pctColW = pctColW,
        statColGap = GEAR_STAT_COL_GAP,
    }
    currencyPanel._wnGearCurrRows = {}
    local currRowRefs = currencyPanel._wnGearCurrRows

    local statHdrText = (ns.L and ns.L["GEAR_CHARACTER_STATS"]) or "Character Stats"
    local statHdr = gearChrome and gearChrome.CreateSectionHeader
        and gearChrome.CreateSectionHeader(statPanel, statHdrText, accent)
    if statHdr then
        statHdr:ClearAllPoints()
        statHdr:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 0, 0)
        statHdr:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", 0, 0)
    end

    local classFile = charData and charData.classFile
    local function paintGearMidColumnDeferred()
        local subHdr = GEAR_SUBPANEL_HDR
        local statRowH = STAT_ROW_H
        local crestRowH = CREST_ROW_H
        local statY = -subHdr
        local zebra = 0

        if #primaryRows > 0 or #secondaryRows > 0 then
            for i = 1, #primaryRows do
                zebra = zebra + 1
                local rowBg = statPanel:CreateTexture(nil, "BACKGROUND")
                rowBg:SetPoint("TOPLEFT", statPanel, "TOPLEFT", math.max(0, statPad - 2), statY + 1)
                rowBg:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -math.max(0, statPad - 2), statY + 1)
                rowBg:SetHeight(statRowH - 1)
                local rbR, rbG, rbB, rbA = GearPanelRowBgColor(zebra)
                rowBg:SetColorTexture(rbR, rbG, rbB, rbA)

                local stat = primaryRows[i]
                local pr, pg, pb = GetGearPrimaryStatRGB(stat.statId, classFile)
                local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
                val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
                val:SetWidth(valColW)
                val:SetJustifyH("RIGHT")
                val:SetTextColor(pr, pg, pb)
                val:SetText(stat.value)
                val:SetShadowOffset(1, -1)
                val:SetShadowColor(0, 0, 0, 0.8)

                local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
                row:SetPoint("TOPLEFT", statPanel, "TOPLEFT", statPad, statY)
                row:SetPoint("RIGHT", statPanel, "RIGHT", -(statPad + valColW + GEAR_STAT_COL_GAP), statY)
                row:SetWordWrap(false)
                row:SetJustifyH("LEFT")
                row:SetTextColor(0.88, 0.88, 0.88)
                row:SetText(stat.label)
                row:SetShadowOffset(1, -1)
                row:SetShadowColor(0, 0, 0, 0.8)

                statRowRefs[#statRowRefs + 1] = { label = row, pct = nil, val = val, y = statY, hasPct = false }
                statY = statY - statRowH
            end

            if hasDivider then
                local statDiv = statPanel:CreateTexture(nil, "ARTWORK")
                statDiv:SetPoint("TOPLEFT", statPad, statY - 2)
                statDiv:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY - 2)
                statDiv:SetHeight(1)
                statDiv:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)
                statY = statY - 8
            end

            for i = 1, #secondaryRows do
                zebra = zebra + 1
                local rowBg = statPanel:CreateTexture(nil, "BACKGROUND")
                rowBg:SetPoint("TOPLEFT", statPanel, "TOPLEFT", math.max(0, statPad - 2), statY + 1)
                rowBg:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -math.max(0, statPad - 2), statY + 1)
                rowBg:SetHeight(statRowH - 1)
                local rbR, rbG, rbB, rbA = GearPanelRowBgColor(zebra)
                rowBg:SetColorTexture(rbR, rbG, rbB, rbA)

                local stat = secondaryRows[i]
                local secRgb = GEAR_SECONDARY_STAT_RGB[i] or { 1, 1, 1 }
                local sr, sg, sb = secRgb[1], secRgb[2], secRgb[3]
                local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
                val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
                val:SetWidth(valColW)
                val:SetJustifyH("RIGHT")
                val:SetTextColor(sr * 0.82, sg * 0.82, sb * 0.82)
                val:SetText(stat.ratingStr or "0")
                val:SetShadowOffset(1, -1)
                val:SetShadowColor(0, 0, 0, 0.8)

                local pctFs = FontManager:CreateFontString(statPanel, GFR("gearStatPct"), "OVERLAY")
                pctFs:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -(statPad + valColW + GEAR_STAT_COL_GAP), statY)
                pctFs:SetWidth(pctColW)
                pctFs:SetJustifyH("RIGHT")
                pctFs:SetTextColor(sr, sg, sb)
                pctFs:SetText(stat.pctStr or "0.0%")
                pctFs:SetShadowOffset(1, -1)
                pctFs:SetShadowColor(0, 0, 0, 0.8)

                local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
                row:SetPoint("TOPLEFT", statPanel, "TOPLEFT", statPad, statY)
                row:SetPoint("RIGHT", statPanel, "RIGHT", -(statPad + valColW + GEAR_STAT_COL_GAP + pctColW + GEAR_STAT_COL_GAP), statY)
                row:SetWordWrap(false)
                row:SetJustifyH("LEFT")
                row:SetTextColor(0.88, 0.88, 0.88)
                row:SetText(stat.label)
                row:SetShadowOffset(1, -1)
                row:SetShadowColor(0, 0, 0, 0.8)

                statRowRefs[#statRowRefs + 1] = { label = row, pct = pctFs, val = val, y = statY, hasPct = true }
                statY = statY - statRowH
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

        local currHdrText = (ns.L and ns.L["GEAR_UPGRADE_CURRENCIES"]) or "Upgrade Currencies"
        local currHdr = gearChrome and gearChrome.CreateSectionHeader
            and gearChrome.CreateSectionHeader(currencyPanel, currHdrText, accent, { fontRole = "gearPanelTitle" })
        if currHdr then
            currHdr:ClearAllPoints()
            currHdr:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", 0, 0)
            currHdr:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", 0, 0)
        end

        -- Crest rows: icon | name (clipped) | fixed-width amount column (symmetric insets with stats panel).
        local curY = -subHdr
        local iconSize = 24
for i = 1, #crestCurrencies do
            local cur = crestCurrencies[i]
            -- Alternating row bg
            local rowBg = currencyPanel:CreateTexture(nil, "BACKGROUND")
            rowBg:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
            rowBg:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
            rowBg:SetHeight(crestRowH)
            local rbR, rbG, rbB, rbA = GearPanelRowBgColor(i)
            rowBg:SetColorTexture(rbR, rbG, rbB, rbA)

            local ico = currencyPanel:CreateTexture(nil, "ARTWORK")
            ico:SetSize(iconSize, iconSize)
            ico:SetPoint("TOPLEFT", currPad, curY)
            ico:SetTexture(cur.icon or "Interface\\Icons\\INV_Misc_Coin_01")
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local crestHitW = math.max(1, currColW - currPad * 2)
            local crestHit = GearFact:CreateContainer(currencyPanel, crestHitW, crestRowH, false)
            crestHit:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
            crestHit:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
            crestHit:SetHeight(crestRowH)
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
                displayCrestName = FormatTrackMarkup(firstWord, firstWord, nil)
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
            amountText:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY)
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

            currRowRefs[#currRowRefs + 1] = { icon = ico, name = nameText, amount = amountText }
            curY = curY - crestRowH
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
            goldAmt:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY)
            goldAmt:SetPoint("TOP", goldIco, "TOP", 0, 0)
            goldAmt:SetPoint("BOTTOM", goldIco, "BOTTOM", 0, 0)
            goldAmt:SetJustifyH("RIGHT")
            goldAmt:SetShadowOffset(1, -1)
            goldAmt:SetShadowColor(0, 0, 0, 0.8)
            local copper = (goldCurrency.amount or 0) * 10000 + (goldCurrency.silver or 0) * 100 + (goldCurrency.copper or 0)
            goldAmt:SetText("|cffffff00" .. FormatGold(copper) .. "|r")
            currRowRefs[#currRowRefs + 1] = { icon = goldIco, name = goldText, amount = goldAmt }
        end

        -- Short hint under gold (season progress on crest amounts).
        local shiftHint = FontManager:CreateFontString(currencyPanel, "small", "OVERLAY")
        shiftHint:SetPoint("BOTTOMLEFT", currencyPanel, "BOTTOMLEFT", currPad, FOOTER_HINT_PAD)
        shiftHint:SetPoint("BOTTOMRIGHT", currencyPanel, "BOTTOMRIGHT", -currPad, FOOTER_HINT_PAD)
        shiftHint:SetJustifyH("CENTER")
        shiftHint:SetText("|cff777777" .. GetLocalizedText("SHIFT_HINT_SEASON_PROGRESS_SHORT", "Shift: Season progress") .. "|r")
        shiftHint:SetShadowOffset(1, -1)
        shiftHint:SetShadowColor(0, 0, 0, 0.8)
    end

    local recScroll, recContent, scroll, storageContentW = nil, nil, nil, nil
    local storagePad = 8
    -- Title only (no subtitle): tighter header so the recommendations table gains viewport height.
    local storageHeaderH = GEAR_LAYOUT.STORAGE_PANEL_HDR or 36
    local storageBarW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local rowH = 34
    -- Storage row data before the panel shell so overflow math matches the deferred row paint pass.
    local storageRows = {}
    if recEnabled then
    do
            local equippedSlots = gearData and gearData.slots or {}
            local seenItemLink = {}
            if storageFindings then
                for slotID, candidates in pairs(storageFindings) do
                    local best = candidates and candidates[1]
                    if best then
                        local currentDisplay = (equippedSlots[slotID] and equippedSlots[slotID].itemLevel) or 0
                        local target = best.itemLevel or 0
                        local scanBase = tonumber(best.equippedIlvlAtFind) or currentDisplay
                        if target > scanBase then
                            local linkKey = best.itemLink or ("id:" .. tostring(best.itemID or 0))
                            if not seenItemLink[linkKey] then
                                seenItemLink[linkKey] = true
                                local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
                                storageRows[#storageRows + 1] = {
                                    slotID = slotID,
                                    slotName = (slotDef and slotDef.label) or GetLocalizedText("GEAR_SLOT_FALLBACK_FORMAT", "Slot %d"):format(tonumber(slotID) or 0),
                                    currentIlvl = currentDisplay,
                                    targetIlvl = target,
                                    itemLink = best.itemLink,
                                    itemID = best.itemID,
                                    source = best.source or "",
                                    sourceType = best.sourceType or "",
                                    sourceClassFile = best.sourceClassFile,
                                    delta = target - scanBase,
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

        -- ── BOTTOM BAND: Gear upgrade recommendations (full width) ──
        local storageParent = gearHosts.bottomColHost or card
        local storagePanel = CreateGearSubpanel(storageParent, storageW, recZoneH > 0 and recZoneH or panelH, accent)
        storagePanel:ClearAllPoints()
        storagePanel:SetPoint("TOPLEFT", storageParent, "TOPLEFT", 0, 0)
        storagePanel:SetPoint("BOTTOMRIGHT", storageParent, "BOTTOMRIGHT", 0, 0)
        if storagePanel.GetWidth then
            local mw = storagePanel:GetWidth()
            if mw and mw > 0 then storageW = mw end
        end
        if storagePanel.SetClipsChildren then
            storagePanel:SetClipsChildren(true)
        end
        local storagePanelH = storagePanel.GetHeight and storagePanel:GetHeight() or panelH
        local storageHdrText = GetLocalizedText("GEAR_STORAGE_TITLE", "Gear Upgrade Recommendations")
        local storageHdr = gearChrome and gearChrome.CreateSectionHeader
            and gearChrome.CreateSectionHeader(storagePanel, storageHdrText, accent, { fontRole = "gearStorageCardTitle" })
        if storageHdr then
            storageHdr:ClearAllPoints()
            storageHdr:SetPoint("TOPLEFT", storagePanel, "TOPLEFT", 0, 0)
            storageHdr:SetPoint("TOPRIGHT", storagePanel, "TOPRIGHT", 0, 0)
        end

        local viewportH = storagePanelH - storageHeaderH - storagePad - 10
        scroll = ns.UI.Factory and ns.UI.Factory.CreateScrollFrame and ns.UI.Factory:CreateScrollFrame(storagePanel, "UIPanelScrollFrameTemplate", true)
        local sbCol
        -- Pre-compute overflow so we can decide whether to reserve space for the scrollbar column at all.
        local storageHdrScroll = (#storageRows > 0) and ns.GearUI_STORAGE_REC_TABLE_HDR or 0
        local rowsOverflow = (#storageRows * rowH + storageHdrScroll) > viewportH
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
            local contentW = rowsOverflow
                and math.max(120, storageW - storagePad * 2 - storageBarW)
                or  math.max(120, storageW - storagePad * 2)
            storageContentW = contentW
            local contentH = math.max(#storageRows * rowH + storageHdrScroll, viewportH)
            local content = GearFact:CreateContainer(scroll, contentW, contentH, false)
            recScroll = scroll
            recContent = content
            scroll:SetScrollChild(content)

            if #storageRows == 0 then
                local empty = FontManager:CreateFontString(content, GFR("gearStorageEmpty"), "OVERLAY")
                content._gearStorageStatusFont = empty
                empty:SetAllPoints()
                empty:SetJustifyH("CENTER")
                empty:SetJustifyV("MIDDLE")
                if storageScanPending then
                    empty:SetText(GetLocalizedText("GEAR_STORAGE_SCANNING", "Scanning storage for upgrades..."))
                    empty:SetTextColor(0.65, 0.68, 0.75)
                else
                    empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY", "No transferable stash upgrade beats your equipped items for these slots."))
                    empty:SetTextColor(0.55, 0.55, 0.6)
                end
            end
            if ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scroll)
            end
            local mfHost = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mfHost and recContent and recScroll and storagePanel then
                mfHost._gearStorageRecHost = {
                    drawGen = ns._gearTabDrawGen,
                    canonKey = charKey,
                    recContent = recContent,
                    recScroll = recScroll,
                    sbCol = sbCol,
                    storagePanel = storagePanel,
                    storageW = storageW,
                    storagePad = storagePad,
                    storageHeaderH = storageHeaderH,
                    storageBarW = storageBarW,
                    rowH = rowH,
                }
                if storageScanPending then
                    mfHost._gearStorageScanningShownAt = GetTime()
                end
            end
        end
        gearHosts.storagePanel = storagePanel
        RelayoutGearCardColumnHosts(card, gearHosts, panelTopY, recEnabled)
        RelayoutGearSideColumnInCard(card, gearHosts)
    end

  -- Paperdoll in left column host (clips inside paperColW; stats/currencies stay in rightColHost).
    local paperParent = leftCol or card
    DrawPaperDollInCard(paperParent, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true,
        PAPERDOLL_COL_INSET, charKey, 0, paperdollNaturalH, paperZoneH,
        { cardRef = card, deferCenter = true, modelBoost = modelBoost })

    -- Staged paint: one idle tick per stage (mid+center -> storage rows -> slot inspect) to avoid stacking FRAME SPIKEs.
    local gearDeferGen = ns._gearTabDrawGen
    local mfDefer = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfDefer then
        mfDefer._gearDeferChainActive = true
    end
    local function scheduleGearStorageTryStartOnce(genNow)
        if not mfDefer then return end
        -- `finishGearDeferChain` can run more than once per paint (early exits + final slot batch).
        -- Without this, two C_Timer(0) calls race: the second sees `pending` nil and used to orphan `_gearStorageDeferAwaiting`.
        if mfDefer._gearStorageTryStartScheduledFor == genNow then
            return
        end
        mfDefer._gearStorageTryStartScheduledFor = genNow
        local scanDelay = (ns.GEAR_STORAGE_SCAN_START_DELAY_SEC) or 0.035
        C_Timer.After(scanDelay, function()
            mfDefer._gearStorageTryStartScheduledFor = nil
            if genNow ~= (ns._gearTabDrawGen or 0) then return end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
            ns.GearUI_TryStartPendingGearStorageScan(mfDefer, genNow)
        end)
    end

    local function finishGearDeferChain()
        if mfDefer then
            mfDefer._gearDeferChainActive = false
            local genNow = ns._gearTabDrawGen or 0
            ns.GearUI_TryDismissGearContentVeil(mfDefer, genNow)
            if WarbandNexus:IsGearStorageRecommendationsEnabled() then
                local scanPending = mfDefer._gearPendingStorageScan
                -- Kick yielded storage find whenever the tab asked for a scan (defer or pending),
                -- even if `_gearPopulateCanonKey` briefly diverged from `deferAwaitCanon` (would orphan
                -- "Scanning storage..." when TryStart returned early without starting `RunYield`).
                local needKick = (scanPending and scanPending.paintGen == genNow)
                    or (ns._gearStorageDeferAwaiting and ns._gearStorageDeferAwaitCanon ~= nil)
                if needKick then
                    mfDefer._gearPendingStorageScan = {
                        canon = ns._gearStorageDeferAwaitCanon or (scanPending and scanPending.canon),
                        paintGen = genNow,
                    }
                    scheduleGearStorageTryStartOnce(genNow)
                    WarbandNexus:GearStoragePanelDebug(("finishGearDeferChain -> schedule TryStart gen=%s canon=%s"):format(
                        tostring(genNow), tostring(mfDefer._gearPendingStorageScan and mfDefer._gearPendingStorageScan.canon)))
                end
            else
                ns._gearStorageDeferAwaiting = false
                ns._gearStorageDeferAwaitCanon = nil
                mfDefer._gearPendingStorageScan = nil
            end
        end
    end
    C_Timer.After(0, function()
        if gearDeferGen ~= ns._gearTabDrawGen then
            finishGearDeferChain()
            return
        end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
            finishGearDeferChain()
            return
        end
        if not card or not card.GetParent or not card:GetParent() then
            finishGearDeferChain()
            return
        end
        local P = ns.Profiler
        local function runMid()
            paintGearMidColumnDeferred()
        end
        if P and P.enabled and P.Wrap and P.SliceLabel then
            P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_MidColumn_deferred"), runMid)
        else
            runMid()
        end

        local centerFn = card._gearPaperdollCenterDefer
        card._gearPaperdollCenterDefer = nil
        local function runStorageRowsThenInspect()
            if scroll and recContent and #storageRows > 0 and storageContentW then
                local nStorageRows = #storageRows
                local function fillStorageRows()
                    ns.GearUI_PaintGearStorageRowsBatched(recContent, recScroll, storageRows, storageContentW, rowH, charData, gearDeferGen, nil)
                end
                if P and P.enabled and P.Wrap and P.SliceLabel then
                    P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_StorageRows_deferred"), fillStorageRows)
                else
                    fillStorageRows()
                end
            end

            if card._gearSlotInspectList and #card._gearSlotInspectList > 0 then
                local slotList = card._gearSlotInspectList
                local inspectIdx = 1
                local SLOTS_PER_FRAME = 4
                local function runSlotInspectBatch()
                    if gearDeferGen ~= (ns._gearTabDrawGen or 0) then
                        finishGearDeferChain()
                        return
                    end
                    if not (WarbandNexus.IsStillOnTab and WarbandNexus:IsStillOnTab("gear")) then
                        finishGearDeferChain()
                        return
                    end
                    if not card or not card.GetParent or not card:GetParent() then
                        finishGearDeferChain()
                        return
                    end
                    local function runSlice()
                        local n = #slotList
                        local endIdx = math.min(inspectIdx + SLOTS_PER_FRAME - 1, n)
                        for si = inspectIdx, endIdx do
                            local sb = slotList[si]
                            if sb and sb._needsDeferredInspect then
                                GearSlotApplyDeferredEnchantGemInspect(sb)
                            end
                        end
                        inspectIdx = endIdx + 1
                        if inspectIdx <= n then
                            C_Timer.After(0, runSlotInspectBatch)
                        else
                            finishGearDeferChain()
                        end
                    end
                    if P and P.enabled and P.Wrap and P.SliceLabel then
                        P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_SlotInspect_deferred"), runSlice)
                    else
                        runSlice()
                    end
                end
                C_Timer.After(0, runSlotInspectBatch)
            else
                finishGearDeferChain()
            end
        end

        if centerFn then
            C_Timer.After(0, function()
                if gearDeferGen ~= ns._gearTabDrawGen then
                    finishGearDeferChain()
                    return
                end
                if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
                    finishGearDeferChain()
                    return
                end
                if not card or not card.GetParent or not card:GetParent() then
                    finishGearDeferChain()
                    return
                end
                if P and P.enabled and P.Wrap and P.SliceLabel then
                    P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_PaperdollCenter_deferred"), centerFn)
                else
                    centerFn()
                end
                C_Timer.After(0, runStorageRowsThenInspect)
            end)
        else
            C_Timer.After(0, runStorageRowsThenInspect)
        end
    end)

    cardH = CARD_PAD + HERO_RIBBON_H + 10 + panelH + CARD_PAD
    if recContent then
        local newViewportH = (recZoneH > 0 and recZoneH or panelH) - storageHeaderH - storagePad - 10
        local storageHdrScroll = (#storageRows > 0) and ns.GearUI_STORAGE_REC_TABLE_HDR or 0
        recContent:SetHeight(math.max(#storageRows * rowH + storageHdrScroll, math.max(newViewportH, 40)))
        if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
        end
    end

    card:SetHeight(cardH)

    card:Show()
    local mfHost = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfHost then
        mfHost._gearPaperdollCard = card
        card._wnGearViewportLayout = {
            scrollYOffset = yOffset,
            paperdollNaturalH = paperdollNaturalH,
            paperZoneH = paperZoneH,
            paperdollNaturalH = paperdollNaturalH,
            topZoneH = topZoneNatural,
            recZoneH = recZoneH,
            leftStackHNatural = leftStackHNatural,
            panelH = panelH,
            statPanelH = statPanelH,
            currenciesH = currenciesH,
            statBandH = statBandH,
            currBandH = currBandH,
            sectionGap = SECTION_GAP,
            statColW = statColW,
            currColW = currColW,
            sideColW = sideColW,
            sideBandGap = SIDE_BAND_GAP,
            paperLeft = paperLeft,
            panelTopY = panelTopY,
            panelGutter = GEAR_LAYOUT.COL_GAP or PANEL_GAP,
            statPanel = statPanel,
            statCurrDiv = statCurrDiv,
            currencyPanel = currencyPanel,
            paperChrome = paperChrome,
            colDivider = colDiv,
            topStackDivider = gearHosts.topStackDivider,
            topLayoutMode = topLayoutMode,
            layoutInnerW = layoutInnerW,
            sideColNaturalH = sideColNaturalH,
            storagePanel = storagePanel,
            cardInnerW = cardInnerW,
            paperColW = paperColW,
            storageW = storageW,
            storageHeaderH = storageHeaderH,
            storagePad = storagePad,
            recScroll = recScroll,
            recContent = recContent,
            sbCol = sbCol,
            storageBarW = storageBarW,
            storageRowCount = storageRows and #storageRows or 0,
            rowH = rowH,
            bodyHost = gearHosts.bodyHost,
            topHost = gearHosts.topHost,
            leftColHost = gearHosts.leftColHost,
            rightColHost = gearHosts.rightColHost,
            bottomColHost = gearHosts.bottomColHost,
        }
        local layoutSync = card._wnGearViewportLayout
        if card._gearSlotInspectList and #card._gearSlotInspectList > 0 then
            RelayoutGearPaperdollInCard(card, layoutSync)
            RelayoutGearCardColumnHosts(card, layoutSync, panelTopY, recEnabled)
            if EnforceGearTopRowNoOverlap(card, layoutSync, mfDraw) then
                RelayoutGearCardColumnHosts(card, layoutSync, panelTopY, recEnabled)
            end
            RelayoutGearSideColumnInCard(card, layoutSync)
        end
    end
    return yOffset - cardH - 12, cardH
end

--- Sync recommendations host metrics after column width changes (resize commit / relayout).
---@param mf Frame|nil
---@param layout table|nil
local function SyncGearStorageRecHostFromLayout(mf, layout)
    if not mf or not layout then return end
    local host = mf._gearStorageRecHost
    if not host then return end
    if layout.storagePanel and layout.storagePanel.GetWidth then
        local measuredW = layout.storagePanel:GetWidth()
        if measuredW and measuredW > 0 then
            layout.storageW = measuredW
        end
    end
    if not layout.storageW then return end
    host.storageW = layout.storageW
    host.storagePad = layout.storagePad or host.storagePad
    host.storageHeaderH = layout.storageHeaderH or host.storageHeaderH
    host.storageBarW = layout.storageBarW or host.storageBarW
    host.rowH = layout.rowH or host.rowH
    host.storagePanel = layout.storagePanel or host.storagePanel
    host.recScroll = layout.recScroll or host.recScroll
    host.recContent = layout.recContent or host.recContent
    host.sbCol = layout.sbCol or host.sbCol
end

--- Widen scroll child when paper + gap + side exceeds card inner (never overlap columns).
---@param card Frame|nil
---@param layout table
---@param mf Frame|nil
---@return boolean widened
local function EnforceGearTopRowNoOverlap(card, layout, mf)
    if not layout then return false end
    local gap = layout.panelGutter or GEAR_PANEL_GAP
    local paperColW = math.max(GEAR_PAPER_COL_FIXED_W, layout.paperColW or GEAR_PAPER_COL_FIXED_W)
    local sideColW = math.max(1, layout.sideColW or 0)
    local needInner = paperColW + gap + sideColW
    layout.minTopRowInnerW = needInner
    layout.paperColW = paperColW

    local cardInner = layout.cardInnerW or 0
    if card and card.GetWidth then
        cardInner = GetGearCardInnerWidthFromCard(card)
    end
    if cardInner >= needInner - 1 then
        layout.cardInnerW = math.max(cardInner, needInner)
        layout.layoutInnerW = math.max(layout.layoutInnerW or 0, needInner)
        return false
    end

    layout.cardInnerW = needInner
    layout.layoutInnerW = math.max(layout.layoutInnerW or 0, needInner)
    layout.storageW = math.max(layout.storageW or 0, needInner)

    if not mf or not mf.scrollChild or not mf.scrollChild.SetWidth then
        return false
    end

    local side = SIDE_MARGIN or 16
    local scrollW = needInner + CARD_PAD * 2 + side * 2
    if ns.GearUI_GetGearTabMinScrollWidth then
        scrollW = math.max(scrollW, ns.GearUI_GetGearTabMinScrollWidth())
    end
    local viewportW = (mf.scroll and mf.scroll.GetWidth and mf.scroll:GetWidth()) or 0
    mf.scrollChild:SetWidth(math.max(viewportW, scrollW))

    if card then
        layout.cardInnerW = GetGearCardInnerWidthFromCard(card)
    end
    return true
end

--- Live resize / post-populate: stretch gear card columns to scroll body bottom (footer).
---@param mf Frame|nil
---@param contentWidth number|nil scroll viewport width (prefer over frozen scrollChild during corner-drag)
---@param opts table|nil `{ chromeOnly = boolean }` skip storage row repaint during live drag (anchors still run)
---@return boolean handled
function ns.GearUI_RelayoutGearTabViewportFill(mf, contentWidth, opts)
    opts = opts or {}
    local chromeOnly = opts.chromeOnly == true
    if not mf or mf.currentTab ~= "gear" then return false end
    local card = mf._gearPaperdollCard
    local layout = card and card._wnGearViewportLayout
    if not card or not layout or not card.GetParent or not card:GetParent() then return false end

    local function heightNear(a, b, eps)
        return math.abs((a or 0) - (b or 0)) <= (eps or 2)
    end

    local scrollChild = mf.scrollChild
    local parent = card:GetParent()
    local parentW = (scrollChild and scrollChild.GetWidth and scrollChild:GetWidth())
        or (parent and parent.GetWidth and parent:GetWidth())
        or contentWidth
    if (not parentW or parentW < 1) then
        if ns.UI_LayoutCoordinator and ns.UI_LayoutCoordinator.GetScrollContentWidth then
            parentW = ns.UI_LayoutCoordinator:GetScrollContentWidth(mf)
        elseif mf.scroll and mf.scroll.GetWidth then
            parentW = mf.scroll:GetWidth()
        end
    end
    if parent and layout.scrollYOffset ~= nil then
        AnchorGearCardFillWidth(card, parent, layout.scrollYOffset, mf)
    end
    layout.cardInnerW = GetGearCardInnerWidthFromCard(card)
    if (card:GetWidth() or 0) < 1 and parentW and parentW > 0 then
        layout.cardInnerW = ResolveGearTabCardInnerWidth(parentW)
    end
    if ns.GearUI_ClampCardInnerWidth then
        layout.cardInnerW = ns.GearUI_ClampCardInnerWidth(layout.cardInnerW)
    end
    local recEnabled = WarbandNexus:IsGearStorageRecommendationsEnabled()
    if layout.cardInnerW and layout.cardInnerW > 0 then
        local cardInnerW = layout.cardInnerW
        local paperColW, sideColW, layoutInnerW
        if ns.GearUI_ComputeTopRowLayout then
            _, paperColW, sideColW, layoutInnerW = ns.GearUI_ComputeTopRowLayout(cardInnerW, nil)
        else
            paperColW, sideColW = ComputeGearLayoutWidths(cardInnerW, recEnabled)
            layoutInnerW = cardInnerW
        end
        layout.topLayoutMode = "row"
        layout.paperColW = math.max(GEAR_PAPER_COL_FIXED_W, paperColW or 0)
        layout.sideColW = sideColW
        local minRowInner = (ns.GearUI_GetTopRowMinInnerW and ns.GearUI_GetTopRowMinInnerW(layout.paperColW, sideColW))
            or (layout.paperColW + GEAR_PANEL_GAP + sideColW)
        layout.layoutInnerW = math.max(layoutInnerW or 0, minRowInner)
        layout.storageW = layout.layoutInnerW or cardInnerW
        layout.panelGutter = GEAR_PANEL_GAP
    end

    local paperdollNaturalH = layout.paperdollNaturalH or 0
    local statPanelH = layout.statPanelH or 0
    local currenciesH = layout.currenciesH or 0
    local sideBandGap = layout.sideBandGap or GEAR_LAYOUT.SIDE_BAND_GAP or 10
    local sectionGap = layout.sectionGap or 12
    local panelTopY = layout.panelTopY or (-CARD_PAD - 22)
    local horizParentLay = layout.leftColHost or card
    local panelH = layout.panelH or 0
    local recZoneH = layout.recZoneH or 0
    local topZoneNatural = layout.topZoneH or paperdollNaturalH

    if not chromeOnly then
        local sideColNaturalH = statPanelH + sideBandGap + currenciesH
        if ns.GearUI_ComputeSideColumnLayout and layout.sideColW then
            local _, _, _, _, h = ns.GearUI_ComputeSideColumnLayout(layout.sideColW, statPanelH, currenciesH, sideBandGap)
            sideColNaturalH = h
        end
        topZoneNatural = math.max(paperdollNaturalH, sideColNaturalH)
        layout.topZoneH = topZoneNatural
        layout.sideColNaturalH = sideColNaturalH
        layout.topLayoutMode = "row"
        panelH = ResolveGearTabPanelHeight(mf, layout.scrollYOffset or 0, topZoneNatural, paperdollNaturalH)
        recZoneH = 0
        if recEnabled and ns.GearUI_ComputeRecBandHeight then
            recZoneH = ns.GearUI_ComputeRecBandHeight(true, panelH, topZoneNatural)
        elseif recEnabled then
            recZoneH = GEAR_LAYOUT.REC_BAND_MIN_H or 200
        end
        if recEnabled and recZoneH > 0 then
            panelH = math.max(panelH, topZoneNatural + sectionGap + recZoneH)
        end
        layout.panelH = panelH
        layout.recZoneH = recZoneH
        layout.paperZoneH = paperdollNaturalH
        layout.leftStackHNatural = recEnabled and (topZoneNatural + sectionGap + recZoneH) or topZoneNatural
    end

    RelayoutGearPaperdollInCard(card, layout)

    local measuredStorageW = RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if EnforceGearTopRowNoOverlap(card, layout, mf) then
        RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    end
    if measuredStorageW and measuredStorageW > 0 then
        layout.storageW = measuredStorageW
    end

    local cardH = CARD_PAD + 24 + panelH + CARD_PAD
    if layout.paperChrome and layout.paperChrome.SetSize and layout.paperColW then
        layout.paperChrome:SetParent(horizParentLay)
        layout.paperChrome:SetSize(layout.paperColW, layout.paperZoneH or layout.paperdollNaturalH or topZoneNatural)
        layout.paperChrome:ClearAllPoints()
        layout.paperChrome:SetPoint("TOPLEFT", horizParentLay, "TOPLEFT", 0, 0)
    end
    RelayoutGearSideColumnInCard(card, layout)
    if not chromeOnly or not heightNear(card:GetHeight(), cardH) then
        card:SetHeight(cardH)
    end
    if not chromeOnly then
        SyncGearStorageRecHostFromLayout(mf, layout)
    end

    local recContent = layout.recContent
    if not chromeOnly and recContent and layout.storageW and ns.GearUI_RelayoutStorageRecColumns then
        local storagePad = layout.storagePad or 8
        local storageBarW = layout.storageBarW or 0
        local storagePanelH = (layout.storagePanel and layout.storagePanel.GetHeight)
            and layout.storagePanel:GetHeight() or 0
        local storageHeaderH = layout.storageHeaderH or 30
        local rowH = layout.rowH or 34
        local storageRowCount = layout.storageRowCount or 0
        local hdrExtra = (storageRowCount > 0) and (ns.GearUI_STORAGE_REC_TABLE_HDR or 0) or 0
        local rowsOverflow = (storageRowCount * rowH + hdrExtra) > math.max(
            storagePanelH - storageHeaderH - storagePad - 10, 1)
        local contentW = rowsOverflow
            and math.max(120, layout.storageW - storagePad * 2 - storageBarW)
            or math.max(120, layout.storageW - storagePad * 2)
        ns.GearUI_RelayoutStorageRecColumns(recContent, contentW)
    end

    if not chromeOnly and recContent and layout.storagePanel then
        local storageHeaderH = layout.storageHeaderH or 30
        local storagePad = layout.storagePad or 8
        local rowH = layout.rowH or 34
        local storagePanelH = (layout.storagePanel and layout.storagePanel.GetHeight)
            and layout.storagePanel:GetHeight() or panelH
        local newViewportH = storagePanelH - storageHeaderH - storagePad - 10
        local storageHdrScroll = (layout.storageRowCount and layout.storageRowCount > 0)
            and (ns.GearUI_STORAGE_REC_TABLE_HDR or 0) or 0
        recContent:SetHeight(math.max((layout.storageRowCount or 0) * rowH + storageHdrScroll, math.max(newViewportH, 40)))
        local recScroll = layout.recScroll
        if recScroll and ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
        end
    end

    if not chromeOnly and ns.UI_SyncMainTabScrollChrome and mf.scrollChild then
        local viewportH = (ns.UI_GetMainTabScrollBodyHeight and ns.UI_GetMainTabScrollBodyHeight(mf)) or 0
        local bodyExtent = math.abs(layout.scrollYOffset or 0) + cardH + 12
        if viewportH > 0 then
            bodyExtent = math.max(bodyExtent, viewportH)
        end
        ns.UI_SyncMainTabScrollChrome(mf, mf.scrollChild, bodyExtent)
    end
    if not chromeOnly and ns.GearUI_UpdateScrollWidthHint then
        ns.GearUI_UpdateScrollWidthHint(mf)
    end
    if not chromeOnly then
        local host = mf._gearStorageRecHost
        if host and host.recContent and WarbandNexus.RedrawGearStorageRecommendationsOnly then
            host.recContent._gearRecForceNextPaint = true
            local gen = ns._gearTabDrawGen or 0
            ns._gearStorageAllowEquipSigInvBypass = true
            WarbandNexus:RedrawGearStorageRecommendationsOnly(host.canonKey or mf._gearPopulateCanonKey, gen, true)
            ns._gearStorageAllowEquipSigInvBypass = false
        end
    end
    return true
end

local function BuildLiveEquippedSlotSnapshot(slotID)
    if not slotID or not GetInventoryItemLink then return nil end
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink or (issecretvalue and issecretvalue(itemLink)) then return nil end
    local itemID = nil
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            itemID = C_Item.GetItemInfoInstant(itemLink)
        end
    end)
    if not itemID and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
        local idFromLink = itemLink:match("item:(%d+)")
        itemID = idFromLink and tonumber(idFromLink) or nil
    end
    if not itemID and not itemLink then return nil end
    local quality = 0
    local ilvl = 0
    pcall(function()
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local v = C_Item.GetDetailedItemLevelInfo(itemLink)
            if v and v > 0 then ilvl = v end
        end
    end)
    pcall(function()
        if C_Item and C_Item.GetItemInfo then
            local _, _, q, level = C_Item.GetItemInfo(itemLink)
            if q then quality = q end
            if (not ilvl or ilvl <= 0) and level and level > 0 then ilvl = level end
        end
    end)
    return {
        itemID = itemID,
        itemLink = itemLink,
        itemLevel = ilvl,
        quality = quality,
    }
end

--- True when slot data or prior ref carries a non-empty item link (not secret).
---@param slotRef table|nil
---@return boolean
local function GearSlotHasInspectableItemLink(slotRef)
    if not slotRef or not slotRef.itemLink or slotRef.itemLink == "" then return false end
    if issecretvalue and issecretvalue(slotRef.itemLink) then return true end
    return true
end

--- Skip redundant _gearApplySlotVisual when icon/labels/overlays already match.
---@param sb Frame|nil
---@param slotData table|nil
---@param canUpgrade boolean|nil
---@param trackText string|nil
---@param notUpgradeable boolean|nil
---@return boolean
local function GearSlotPaperdollVisualEquals(sb, slotData, canUpgrade, trackText, notUpgradeable)
    if not sb then return false end
    local prev = sb._slotDataRef
    local newLink = slotData and slotData.itemLink
    local prevLink = prev and prev.itemLink
    if newLink and issecretvalue and issecretvalue(newLink) then return false end
    if prevLink and issecretvalue and issecretvalue(prevLink) then return false end
    local function linkEmpty(l)
        return not l or l == ""
    end
    if linkEmpty(newLink) ~= linkEmpty(prevLink) then return false end
    if not linkEmpty(newLink) and newLink ~= prevLink then return false end

    local function asNum(x)
        local n = tonumber(x)
        return (type(n) == "number") and n or 0
    end
    if asNum(slotData and slotData.itemLevel) ~= asNum(prev and prev.itemLevel) then return false end
    if asNum(slotData and slotData.quality) ~= asNum(prev and prev.quality) then return false end
    if asNum(slotData and slotData.itemID) ~= asNum(prev and prev.itemID) then return false end

    if not linkEmpty(newLink) and newLink == prevLink then
        local nsig = ""
        local okSig, _ent, sig = pcall(ComputeGearSocketLayout, newLink, sb._slotID, sb._gearIsCurrentChar == true)
        if okSig and type(sig) == "string" then nsig = sig end
        local osig = (sb._gearInspectSt and sb._gearInspectSt.socketSig) or ""
        if nsig ~= osig then return false end
    end

    local upShown = sb._gearUpgradeArrow and sb._gearUpgradeArrow:IsShown() == true
    local expectUpgradeShown = (GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and slotData and slotData.itemLink and slotData.itemLink ~= ""
            and not (issecretvalue and issecretvalue(slotData.itemLink)))
        or (canUpgrade == true and not notUpgradeable)
    if expectUpgradeShown ~= upShown then return false end

    local aff = canUpgrade == true
    if sb._gearLastCanAffordNext ~= aff then return false end

    local wantLock = false
    if not (GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and slotData and slotData.itemLink and slotData.itemLink ~= ""
        and not (issecretvalue and issecretvalue(slotData.itemLink))) then
        if notUpgradeable and slotData and slotData.itemLink
            and not (issecretvalue and issecretvalue(slotData.itemLink)) then
            wantLock = true
        end
    end
    local lockShown = sb._gearLockIcon and sb._gearLockIcon:IsShown() == true
    if wantLock ~= lockShown then return false end

    local tNew = (type(trackText) == "string" and trackText ~= "") and trackText or ""
    local tOld = ""
    local tl = sb._gearTrackLabel
    if tl and tl.IsShown and tl:IsShown() and tl.GetText then
        tOld = tl:GetText() or ""
    end
    if tNew ~= tOld then return false end

    return true
end

-- Exports for GearUI.lua (runtime; avoids extra locals in main chunk)
ns.GEAR_PAPERDOLL = ns.GEAR_PAPERDOLL or {}
local P = ns.GEAR_PAPERDOLL
P.GEAR_REFRESH_PAIR_SLOTS = GEAR_REFRESH_PAIR_SLOTS
P.GEAR_DEBUG_ALWAYS_SHOW_UPGRADE = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE
P.GEAR_PAPERDOLL_ENCHANT_GEM_ALERTS = GEAR_PAPERDOLL_ENCHANT_GEM_ALERTS
P.SLOT_SIZE = SLOT_SIZE
P.TRACK_TEXT_W = TRACK_TEXT_W
P.PAPERDOLL_BLOCK_W = PAPERDOLL_BLOCK_W
P.MODEL_W = MODEL_W
P.GEAR_PAPER_COL_W = GEAR_PAPER_COL_W
P.GEAR_PAPER_COL_FIXED_W = GEAR_PAPER_COL_FIXED_W

ns.GearUI_PaperdollColumnWidth = GearPaperdollColumnWidth
ns.GearUI_GetGearTabMinCardInnerW_Paperdoll = GetGearTabMinCardInnerW
ns.GearUI_ResolveGearTabCardInnerWidth = ResolveGearTabCardInnerWidth
ns.GearUI_DrawPaperDollCard = DrawPaperDollCard
ns.GearUI_GetSlotTrackText = GetSlotTrackText
ns.GearUI_GearSlotApplyDeferredEnchantGemInspect = GearSlotApplyDeferredEnchantGemInspect
ns.GearUI_GearSlotPaperdollVisualEquals = GearSlotPaperdollVisualEquals
ns.GearUI_ComputeGearSocketLayout = ComputeGearSocketLayout
ns.GearUI_BuildLiveEquippedSlotSnapshot = BuildLiveEquippedSlotSnapshot
ns.GearUI_GearSlotHasInspectableItemLink = GearSlotHasInspectableItemLink
ns.GearUI_ApplyGearSubpanelChrome = ApplyGearSubpanelChrome
ns.GearUI_ApplyGearInnerPanelChrome = ApplyGearSubpanelChrome
ns.GearUI_GearPanelRowBgColor = GearPanelRowBgColor
