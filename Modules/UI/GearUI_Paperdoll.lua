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
local SLOT_TO_ARROW_GAP = P(4)   -- gap between slot and upgrade icon
local ARROW_TO_TEXT_GAP = P(6)   -- gap between arrow and text (must be positive now that text is justified)
local TRACK_TEXT_W   = P(136)  -- widened to prevent Track text overflow
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
local GEAR_PAPERDOLL_ENCHANT_GEM_ALERTS = true
-- Inline ilvl separator in recommendation FontStrings (Unicode → renders as tofu); same atlas as storage row ilvl arrow.
local GEAR_ILVL_ARROW_ATLAS = "common-dropdown-icon-play"
local GEAR_ILVL_ARROW_INLINE_SZ = 14
local GEAR_ILVL_ARROW_INLINE_MARKUP = (CreateAtlasMarkup and CreateAtlasMarkup(GEAR_ILVL_ARROW_ATLAS, GEAR_ILVL_ARROW_INLINE_SZ, GEAR_ILVL_ARROW_INLINE_SZ))
    or ("|A:" .. GEAR_ILVL_ARROW_ATLAS .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. "|a")
local CURRENCY_PANEL_W = 248
local GEAR_STAT_PANEL_W = 292
local GEAR_REC_STACK_MIN_H = 200
local GEAR_REC_STACK_MAX_H = 280
local CENTER_GAP     = P(10)
local CURRENCY_PAPERDOLL_GAP = 14  -- gap between crest panel and paperdoll

-- Fixed panel widths: left = text + icon + slot, right = slot + icon + text
local LEFT_PANEL_W   = TRACK_TEXT_W + ARROW_TO_TEXT_GAP + STATUS_TEXT_WARD_W + SLOT_TO_ARROW_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + 2 + ARROW_TO_TEXT_GAP + TRACK_TEXT_W
local MODEL_W       = P(262)
local GEAR_MODEL_VIEWPORT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

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

local function GearPanelRowBgColor(zebra)
    local base = COLORS.bgCard or COLORS.bg or { 0.118, 0.118, 0.145, 0.98 }
    local lift = (zebra % 2 == 0) and 0.014 or 0.005
    return base[1] + lift, base[2] + lift, base[3] + lift * 1.05, base[4] or 0.98
end

-- Paperdoll block width (left column + model + right column) — centered inside the card
local PAPERDOLL_BLOCK_W = LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP + RIGHT_PANEL_W

local SLOT_HALF = SLOT_SIZE / 2
local TEXT_HALF_W = TRACK_TEXT_W / 2
local TEXT_OFFSET_FROM_SLOT_CENTER = SLOT_HALF + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + ARROW_TO_TEXT_GAP + TEXT_HALF_W
local PAPERDOLL_COL_INSET = 4
local PAPER_TRACK_EDGE_PAD = 12
local MAX_PAPER_MODEL_BOOST = 48

local function GearPaperdollContentRightX(baseX, modelW)
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP
    return rightX + SLOT_HALF + TEXT_OFFSET_FROM_SLOT_CENTER + math.ceil(TRACK_TEXT_W * 0.5) + PAPER_TRACK_EDGE_PAD
end

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
    if ns.GearUI_ComputeTopRowWidths then
        local paperW, recW = ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
        return math.max(paperW or 0, GEAR_PAPER_COL_FIXED_W), recW or 0
    end
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

local function EnsureGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if not card or not layout then return end
    if not layout.bodyHost then
        local body = CreateFrame("Frame", nil, card)
        if body.SetClipsChildren then body:SetClipsChildren(false) end
        layout.bodyHost = body
    end
    layout.bodyHost:ClearAllPoints()
    layout.bodyHost:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, panelTopY)
    layout.bodyHost:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
    if layout.bodyHost.SetClipsChildren then
        layout.bodyHost:SetClipsChildren(false)
    end

    if not layout.topHost then
        local top = CreateFrame("Frame", nil, layout.bodyHost)
        if top.SetClipsChildren then top:SetClipsChildren(false) end
        layout.topHost = top
    end
    layout.topHost:SetParent(layout.bodyHost)
    layout.topHost:Show()
    if layout.topHost.SetClipsChildren then
        layout.topHost:SetClipsChildren(false)
    end

    if not layout.leftColHost then
        local left = CreateFrame("Frame", nil, layout.topHost)
        -- Track labels + outer gem/enchant column extend past slot bounds; must not clip.
        if left.SetClipsChildren then left:SetClipsChildren(false) end
        layout.leftColHost = left
    end
    layout.leftColHost:SetParent(layout.topHost)
    layout.leftColHost:Show()
    if layout.leftColHost.SetClipsChildren then
        layout.leftColHost:SetClipsChildren(false)
    end

    if not layout.paperTopHost then
        local paperTop = CreateFrame("Frame", nil, layout.leftColHost)
        if paperTop.SetClipsChildren then paperTop:SetClipsChildren(false) end
        layout.paperTopHost = paperTop
    end
    layout.paperTopHost:SetParent(layout.leftColHost)
    layout.paperTopHost:Show()

    if not layout.paperBottomHost then
        local paperBottom = CreateFrame("Frame", nil, layout.leftColHost)
        if paperBottom.SetClipsChildren then paperBottom:SetClipsChildren(false) end
        layout.paperBottomHost = paperBottom
    end
    layout.paperBottomHost:SetParent(layout.leftColHost)
    layout.paperBottomHost:Show()

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

local function RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if not card or not layout then return nil end
    EnsureGearCardColumnHosts(card, layout, panelTopY, recEnabled == true)
    local gap = layout.panelGutter or GEAR_LAYOUT.COL_GAP or GEAR_PANEL_GAP
    local paperColW = math.max(GEAR_PAPER_COL_FIXED_W, layout.paperColW or GEAR_PAPER_COL_FIXED_W)
    layout.paperColW = paperColW
    local recColW = math.max(0, layout.recColW or layout.sideColW or layout.storageW or 0)
    local body = layout.bodyHost
    local top = layout.topHost
    local left = layout.leftColHost
    local right = layout.rightColHost
    local bottom = layout.bottomColHost
    if not body or not top or not left then return nil end

    local contentBandH = math.max(1, layout.contentBandH or layout.paperZoneH or layout.paperdollNaturalH or 1)
    layout.contentBandH = contentBandH
    layout.paperZoneH = contentBandH

    local topW = (top.GetWidth and top:GetWidth()) or 0
    if topW < 1 then
        topW = layout.cardInnerW or 0
    end
    if topW < 1 and card and card.GetWidth then
        topW = GetGearCardInnerWidthFromCard(card)
    end
    local minTopW = paperColW + (recColW > 0 and (gap + recColW) or 0)
    layout.topRowMinW = minTopW
    local rowOverlaps = (topW > 0 and topW < minTopW - 1)
    layout.topRowOverlaps = rowOverlaps
    local useStack = rowOverlaps and recEnabled and recColW > 0 and right and bottom

    left:ClearAllPoints()
    if left.SetClipsChildren then
        left:SetClipsChildren(false)
    end

    local bottomH = math.max(0, layout.paperBottomBandH or 0)
    local paperTop = layout.paperTopHost
    local paperBottom = layout.paperBottomHost
    local function layoutPaperColumnInHost(host)
        if not paperTop or not host then return end
        paperTop:ClearAllPoints()
        if paperBottom and bottomH > 0 then
            paperBottom:ClearAllPoints()
            paperBottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
            paperBottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
            paperBottom:SetHeight(bottomH)
            paperBottom:Show()
            paperTop:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            paperTop:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            paperTop:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, bottomH)
        else
            if paperBottom then paperBottom:Hide() end
            paperTop:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            paperTop:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        end
    end

    local storageW = nil
    layout.topRowStacked = false
    layout.recStackH = nil
    layout.topRowStackExtraH = 0

    if useStack then
        layout.topLayoutMode = "stack"
        layout.topRowStacked = true
        local recStackH = math.max(
            GEAR_REC_STACK_MIN_H,
            math.min(GEAR_REC_STACK_MAX_H, math.floor(contentBandH * 0.40 + 0.5)))
        layout.recStackH = recStackH
        layout.topRowStackExtraH = recStackH + gap

        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
        top:SetHeight(contentBandH)

        bottom:Show()
        bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -gap)
        bottom:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -gap)
        bottom:SetHeight(recStackH)

        left:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
        left:SetWidth(math.max(paperColW, topW))

        layoutPaperColumnInHost(left)

        right:SetParent(bottom)
        right:Show()
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", bottom, "TOPLEFT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
        if right.SetClipsChildren then
            right:SetClipsChildren(true)
        end

        if layout.centerGapHost then layout.centerGapHost:Hide() end
        if layout.colDivider and layout.colDivider.Hide then layout.colDivider:Hide() end
        if layout.topStackDivider then
            layout.topStackDivider:SetParent(body)
            layout.topStackDivider:ClearAllPoints()
            layout.topStackDivider:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
            layout.topStackDivider:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
            layout.topStackDivider:Show()
        end
        if layout.horizDivider and layout.horizDivider.Hide then layout.horizDivider:Hide() end

        storageW = math.max(1, topW)
        if layout.storagePanel then
            layout.storagePanel:SetParent(right)
            layout.storagePanel:ClearAllPoints()
            layout.storagePanel:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
            layout.storagePanel:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
            if layout.storagePanel.GetWidth then
                local mw = layout.storagePanel:GetWidth()
                if mw and mw > 0 then storageW = mw end
            end
        end
        layout.topRowOverlaps = false
    else
        layout.topLayoutMode = "row"
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
        top:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
        if bottom then bottom:Hide() end

        left:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
        left:SetWidth(paperColW)
        layoutPaperColumnInHost(left)

        if recEnabled and recColW > 0 and right then
            right:SetParent(top)
            right:Show()
            right:ClearAllPoints()
            right:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
            right:SetWidth(recColW)
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

            if layout.storagePanel then
                layout.storagePanel:SetParent(right)
                layout.storagePanel:ClearAllPoints()
                layout.storagePanel:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
                layout.storagePanel:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
                if layout.storagePanel.GetWidth then
                    storageW = layout.storagePanel:GetWidth()
                end
            end
        else
            if right then right:Hide() end
            if layout.centerGapHost then layout.centerGapHost:Hide() end
            if layout.colDivider and layout.colDivider.Hide then layout.colDivider:Hide() end
            recColW = 0
        end

        if layout.topStackDivider and layout.topStackDivider.Hide then
            layout.topStackDivider:Hide()
        end
        if layout.horizDivider and layout.horizDivider.Hide then
            layout.horizDivider:Hide()
        end
    end

    layout.recColW = recColW
    layout.sideColW = recColW
    layout.storageW = storageW or (useStack and topW) or recColW
    return storageW
end

local function ComputeGearPaperdollSlotStartY(paperZoneH, maxRows, anchorY, extraTopInset)
    local rowStep = SLOT_SIZE + SLOT_GAP
    local columnH = (maxRows - 1) * rowStep + SLOT_SIZE
    local zoneH = tonumber(paperZoneH) or columnH
    local padTop = math.max(0, math.floor((zoneH - columnH) * 0.5 + 0.5))
    return (tonumber(anchorY) or 0) - padTop - (tonumber(extraTopInset) or 0)
end

local function AnchorGearPaperChromeBehindModel(chrome, modelHost, cardRef)
    if not chrome then return end
    if not modelHost or not modelHost.IsShown or not modelHost:IsShown() then
        if chrome.Hide then chrome:Hide() end
        return
    end
    chrome:SetParent(modelHost:GetParent() or modelHost)
    chrome:ClearAllPoints()
    chrome:SetPoint("TOPLEFT", modelHost, "TOPLEFT", 0, 0)
    chrome:SetPoint("BOTTOMRIGHT", modelHost, "BOTTOMRIGHT", 0, 0)
    chrome:EnableMouse(false)
    chrome:Show()
    if chrome.SetFrameLevel then
        local ml = (modelHost.GetFrameLevel and modelHost:GetFrameLevel()) or 2
        chrome:SetFrameLevel(math.max(1, ml - 1))
    elseif cardRef and cardRef.GetFrameLevel then
        chrome:SetFrameLevel((cardRef:GetFrameLevel() or 2) + 1)
    end
end

local function RelayoutGearPaperdollInCard(card, layout)
    if not card or not layout then return end
    local slotList = card._gearSlotInspectList
    if not slotList or #slotList == 0 then return end

    local paperParent = layout.paperTopHost or layout.leftColHost or card
    local useColHost = layout.leftColHost ~= nil
    local baseX = useColHost and PAPERDOLL_COL_INSET or ((layout.paperLeft or CARD_PAD) + PAPERDOLL_COL_INSET)
    local paperColW = layout.paperColW or PAPERDOLL_BLOCK_W
    local modelBoost = math.max(0, math.min(MAX_PAPER_MODEL_BOOST, paperColW - GEAR_PAPER_COL_FIXED_W))
    layout.paperdollBaseX = baseX
    layout.modelBoost = modelBoost

    local modelW = MODEL_W + modelBoost
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP
    local rowStep = SLOT_SIZE + SLOT_GAP

    local paperdollNaturalH = layout.paperdollNaturalH or 0
    local paperBandH = layout.paperZoneH or layout.paperTopZoneH or paperdollNaturalH
    layout.paperZoneH = paperBandH
    local pl = card._wnGearPaperdollLayout or {}
    local topInset = tonumber(pl.topContentInset) or 0
    local anchorY = pl.paperOriginY
    if anchorY == nil then
        anchorY = useColHost and 0 or layout.panelTopY
        if anchorY == nil then anchorY = -(CARD_PAD + 22) end
    end
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    local maxRows = math.max(#leftSlots, #rightSlots)
    local paperZoneH = layout.paperTopZoneH or layout.paperZoneH or paperBandH or paperdollNaturalH
    local startY = ComputeGearPaperdollSlotStartY(paperZoneH, maxRows, anchorY, topInset)
    local modelX = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY
    layout.modelX = modelX
    layout.modelTopY = modelTopY

    local posBySlot = {}
    for i = 1, #leftSlots do
        posBySlot[leftSlots[i]] = { leftX, startY - (i - 1) * rowStep }
    end
    for i = 1, #rightSlots do
        posBySlot[rightSlots[i]] = { rightX, startY - (i - 1) * rowStep }
    end
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (modelW + CENTER_GAP - weaponRowW) / 2
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
        local bandH = layout.contentBandH or layout.paperZoneH or layout.paperdollNaturalH or paperdollNaturalH
        layout.leftColHost:SetSize(layout.paperColW, bandH)
    end
    local centerShown = nil
    if ns._gearDressModel and ns._gearDressModel.IsShown and ns._gearDressModel:IsShown() then
        centerShown = ns._gearDressModel
    elseif ns._gearPortraitPanel and ns._gearPortraitPanel.IsShown and ns._gearPortraitPanel:IsShown() then
        centerShown = ns._gearPortraitPanel
    end
    if layout.paperChrome then
        AnchorGearPaperChromeBehindModel(layout.paperChrome, centerShown, card)
    end
    if centerShown and ns._gearModelBorder then
        ns._gearModelBorder:ClearAllPoints()
        ns._gearModelBorder:SetPoint("TOPLEFT", centerShown, "TOPLEFT", -1, 1)
        ns._gearModelBorder:SetPoint("BOTTOMRIGHT", centerShown, "BOTTOMRIGHT", 1, -1)
    end
end

local function GetGearTabMinCardInnerW()
    if ns.GearUI_GetGearTabMinCardInnerW then
        return ns.GearUI_GetGearTabMinCardInnerW(WarbandNexus:IsGearStorageRecommendationsEnabled())
    end
    return GEAR_PAPER_COL_FIXED_W + GEAR_PANEL_GAP + (GEAR_LAYOUT.REC_COL_MIN_W or 300)
end

local function ResolveGearTabCardInnerWidth(scrollChildW)
    if ns.GearUI_ResolveCardInnerWidth then
        return ns.GearUI_ResolveCardInnerWidth(scrollChildW, SIDE_MARGIN)
    end
    return GetGearTabMinCardInnerW()
end

local function AnchorGearCardFillWidth(card, parent, yOffset, mf)
    if not card or not parent then return GetGearTabMinCardInnerW() end
    local side = SIDE_MARGIN or 16
    local scrollChildW = (parent.GetWidth and parent:GetWidth()) or 0
    local outerW = math.max(1, scrollChildW - 2 * side)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", side, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -side, yOffset)
    return math.max(1, outerW - 2 * CARD_PAD)
end

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

local function GetGearSlotEnchantQualityTier(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if not GetEnchantmentCraftingQualityTierFromItemLink then return nil end
    local q = GetEnchantmentCraftingQualityTierFromItemLink(itemLink)
    q = tonumber(q)
    if q and q >= 1 then return q end
    return nil
end

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
            tex:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -dx, dy)
        elseif side == "right" or side == "bottom_right" then
            tex:SetPoint("TOPLEFT", icon, "TOPLEFT", dx, dy)
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
            upgradeArrow:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            upgradeArrow:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        else
            upgradeArrow:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end

    if lockIcon then
        local lockSz = math.max(12, math.floor(baseSz * 0.88 + 0.5))
        lockIcon:SetSize(lockSz, lockSz)
        lockIcon:ClearAllPoints()
        if side == "left" or side == "bottom_left" then
            lockIcon:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            lockIcon:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        else
            lockIcon:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end
end

local function BuildGearPaperCrestRows(currencies, charKey, isCurrentChar)
    local rows = {}
    local goldCurrency = nil
    local byId = {}
    for i = 1, #(currencies or {}) do
        local cur = currencies[i]
        if cur then
            if cur.isGold then
                goldCurrency = cur
            elseif cur.currencyID then
                byId[cur.currencyID] = cur
            end
        end
    end
    local MS1 = ns.Constants and ns.Constants.DAWNCREST_UI
    local ordered = MS1 and MS1.COLUMN_IDS
    local labelKeys = MS1 and MS1.PVE_LABEL_KEYS
    local function resolveCrestIcon(currencyID)
        if WarbandNexus and WarbandNexus.GetCurrencyData then
            local cd = WarbandNexus:GetCurrencyData(currencyID, charKey)
            if cd and (cd.icon or cd.iconFileID) then
                return cd.icon or cd.iconFileID
            end
        end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if ok and info and info.iconFileID and info.iconFileID > 0 then
                return info.iconFileID
            end
        end
        return 134400
    end
    local function mergeRow(currencyID, base)
        local row = {
            currencyID = currencyID,
            amount = base and tonumber(base.amount) or 0,
            name = base and base.name,
            icon = resolveCrestIcon(currencyID),
            maxQuantity = base and base.maxQuantity,
        }
        if isCurrentChar and WarbandNexus and WarbandNexus.GetCurrencyData then
            local cd = WarbandNexus:GetCurrencyData(currencyID, charKey)
            if cd then
                row.amount = cd.quantity or row.amount
                if cd.name and cd.name ~= "" then row.name = cd.name end
                if cd.icon or cd.iconFileID then row.icon = cd.icon or cd.iconFileID end
                row.maxQuantity = cd.maxQuantity
            end
        end
        if labelKeys and labelKeys[currencyID] and ns.L and ns.L[labelKeys[currencyID]] then
            row.displayName = ns.L[labelKeys[currencyID]]
        end
        rows[#rows + 1] = row
    end
    if ordered then
        for i = 1, #ordered do
            local id = ordered[i]
            if byId[id] then
                mergeRow(id, byId[id])
                byId[id] = nil
            end
        end
    end
    for id, base in pairs(byId) do
        mergeRow(id, base)
    end
    return rows, goldCurrency
end

local function GearSlotHideLegacyIncreaseLabels(btn)
    if not btn then return end
    if btn._gearIncNextFs then btn._gearIncNextFs:Hide() end
    if btn._gearIncTargetFs then btn._gearIncTargetFs:Hide() end
    btn._gearLastIncNext = nil
    btn._gearLastIncTarget = nil
end

local function GearSlotRefreshUpgradeArrow(btn, slotData, notUpgradeable)
    if not btn or not btn._gearUpgradeArrow then return end
    local slotID = btn._slotID
    local hasItem = slotData and slotData.itemLink and slotData.itemLink ~= ""
        and not (issecretvalue and issecretvalue(slotData.itemLink))
    if not hasItem then
        btn._gearUpgradeArrow:Hide()
        if btn._gearUpgradeArrowBgBorder then btn._gearUpgradeArrowBgBorder:Hide() end
        if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Hide() end
        GearSlotHideLegacyIncreaseLabels(btn)
        return
    end
    local up = btn._gearUpgradeInfo and btn._gearUpgradeInfo[slotID]
    local currencies = btn._gearCurrencyAmounts
    local arrowDisplay = nil
    if up and ns.GearUI_GetUpgradeArrowDisplay then
        arrowDisplay = ns.GearUI_GetUpgradeArrowDisplay(up, currencies)
        up.upgradeArrowDisplay = arrowDisplay
    end
    local showUpChip = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE
        or (arrowDisplay == "green")
    local canAfford = (arrowDisplay == "green")
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
    GearSlotHideLegacyIncreaseLabels(btn)
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
    GearSlotHideLegacyIncreaseLabels(btn)
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

local function GearSlotApplyDeferredEnchantGemInspect(btn)
    if not btn then return end
    local slotData = btn._slotDataRef
    local slotID = btn._slotID
    local st = btn._gearInspectSt
    local ctx = btn._gearLayoutCtx
    if not slotData or not slotData.itemLink or not st then
        GearSlotClearPaperdollOverlays(btn)
        return
    end
    if not ctx then
        ctx = { side = btn._gearTextSide or "right", upgradeArrow = btn._gearUpgradeArrow }
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

-- SLOT ICON BUTTON -> Modules/UI/GearUI_Paperdoll_Slots.lua (ops-040)
ns.GearUI_Paperdoll = ns.GearUI_Paperdoll or {}
ns.GearUI_Paperdoll._slotDeps = {
    GearFact = GearFact,
    SLOT_SIZE = SLOT_SIZE,
    GFR = GFR,
    FontManager = FontManager,
    GearGetFrameContentInset = GearGetFrameContentInset,
    EMPTY_SLOT_TEXTURE = EMPTY_SLOT_TEXTURE,
    SLOT_FALLBACK_TEXTURE = SLOT_FALLBACK_TEXTURE,
    COLORS = COLORS,
    GearSlotRefreshUpgradeArrow = GearSlotRefreshUpgradeArrow,
    GearSlotClearPaperdollOverlays = GearSlotClearPaperdollOverlays,
    PlaceGearUpgradeLockTowardModel = PlaceGearUpgradeLockTowardModel,
    STATUS_UPGRADE_ICON = STATUS_UPGRADE_ICON,
    STATUS_ICON_INSET = STATUS_ICON_INSET,
    GEAR_DEBUG_ALWAYS_SHOW_UPGRADE = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE,
    TRACK_TEXT_W = TRACK_TEXT_W,
    TEXT_OFFSET_FROM_SLOT_CENTER = TEXT_OFFSET_FROM_SLOT_CENTER,
    ShowTooltip = ShowTooltip,
    HideTooltip = HideTooltip,
    SLOT_BY_ID = SLOT_BY_ID,
    tinsert = tinsert,
    issecretvalue = issecretvalue,
    format = format,
    GearSlotHideLegacyIncreaseLabels = GearSlotHideLegacyIncreaseLabels,
    SLOT_HALF = SLOT_HALF,
}
-- PAPERDOLL CARD  (full width; doll centered like Characters screen)

local CURRENCY_ROW_H = 26
local ROW_H = 34

local function FormatSlotUpgradeCurrencySuffix(up, currencyAmounts)
    if not up or not up.canUpgrade or up.notUpgradeable then return nil end
    if up.isCrafted then
        local range = currencyAmounts and ns.GearUI_GetCraftedIlvlRange and ns.GearUI_GetCraftedIlvlRange(up, currencyAmounts) or nil
        if not range or not range.nextTierCost or range.nextTierCost <= 0 then return nil end
        local have = range.nextTierHave or 0
        local need = range.nextTierCost
        local hex = (have >= need) and "66ee88" or "ff8844"
        local fmt = (ns.L and ns.L["GEAR_SLOT_CURRENCY_HAVE_NEED"]) or "%d/%d"
        return " |cff" .. hex .. "(" .. format(fmt, have, need) .. ")|r"
    end
    local crestNeed = (ns.GearUI_GetNextStepCrestNeed and ns.GearUI_GetNextStepCrestNeed(up)) or (up.crestCost or 0)
    if crestNeed > 0 then
        local cid = up.currencyID or 0
        local have = (currencyAmounts and currencyAmounts[cid]) or 0
        local hex = (have >= crestNeed) and "66ee88" or "ff8844"
        local fmt = (ns.L and ns.L["GEAR_SLOT_CURRENCY_HAVE_NEED"]) or "%d/%d"
        local suffix = " |cff" .. hex .. "(" .. format(fmt, have, crestNeed) .. ")|r"
        if up.nextUpgradeIsDiscounted then
            suffix = suffix .. " |cff88ccff*|r"
        end
        return suffix
    end
    local goldNeed = up.moneyCost or (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000)
    local goldCopper = (ns.GearUI_GetGearCurrencyGoldCopper and ns.GearUI_GetGearCurrencyGoldCopper(currencyAmounts))
        or ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
    local haveGold = math.floor(goldCopper / 10000)
    local needGold = math.floor(goldNeed / 10000)
    local hex = (goldCopper >= goldNeed) and "66ee88" or "ff8844"
    local fmt = (ns.L and ns.L["GEAR_SLOT_CURRENCY_HAVE_NEED"]) or "%d/%d"
    return " |cff" .. hex .. "(" .. format(fmt, haveGold, needGold) .. ")|r"
end

local function GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts, slotData)
    local up = upgradeInfo and (upgradeInfo[slotID] or upgradeInfo[tostring(slotID)])
    if not up and slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
        if ns.Gear_ResolveSlotUpgradeTrackAndTier then
            local tn, tc, tm = ns.Gear_ResolveSlotUpgradeTrackAndTier(slotData)
            if tn and tc and tm and tm > 0 then
                local track = LocalizeUpgradeTrackName(tn)
                if track and track ~= "" then
                    return FormatTrackMarkup(tn, track .. " " .. tostring(tc) .. "/" .. tostring(tm), quality)
                end
            end
        end
        return nil
    end
    if not up then return nil end
    if slotData and ns.Gear_SyncUpgradeEntryFromSlot then
        up = ns.Gear_SyncUpgradeEntryFromSlot(up, slotData) or up
    end
    if slotData and ns.Gear_ResolveSlotUpgradeTrackAndTier and not up.isCrafted and not up.notUpgradeable then
        local maxT = tonumber(up.maxUpgrade) or 0
        if not up.trackName or up.trackName == "" or maxT <= 0 then
            local tn, tc, tm = ns.Gear_ResolveSlotUpgradeTrackAndTier(slotData)
            if tn and tc and tm then
                up.trackName = tn
                up.currUpgrade = tc
                up.maxUpgrade = tm
            end
        end
    end

    -- Crafted items: show current tier + achievable recraft target
    if up.isCrafted then
        local currentEnglish = up.craftedTierName or up.trackName or "Crafted"
        local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
        -- Crafted gear caps at 5/6 on every tier (not only Myth) — see GearService.
        if maxT > 5 then
            maxT = 5
            if curT > 5 then curT = 5 end
        end
        local currentTier = LocalizeUpgradeTrackName(currentEnglish)
        local range = currencyAmounts and ns.GearUI_GetCraftedIlvlRange and ns.GearUI_GetCraftedIlvlRange(up, currencyAmounts) or nil
        local canRecast = range and range.maxIlvl > (up.currentIlvl or 0)
            and (up.canAffordNext == true
                or (currencyAmounts and ns.GearUI_CanAffordNextUpgrade and ns.GearUI_CanAffordNextUpgrade(up, currencyAmounts)))
        if maxT > 0 and curT > 0 and currentTier then
            if canRecast then
                local bestEnglish = range.bestCrestName or ""
                return FormatTrackMarkup(currentEnglish, currentTier .. " " .. tostring(curT) .. "/" .. tostring(maxT), quality)
                    .. " → "
                    .. FormatTrackMarkup(bestEnglish, LocalizeUpgradeTrackName(bestEnglish) .. " " .. tostring(range.maxIlvl), quality)
            end
            return FormatTrackMarkup(currentEnglish, currentTier .. " " .. tostring(curT) .. "/" .. tostring(maxT), quality)
        end
        if canRecast then
            local bestEnglish = range.bestCrestName or ""
            return FormatTrackMarkup(currentEnglish, currentTier or LocalizeUpgradeTrackName(currentEnglish), quality)
                .. " → "
                .. FormatTrackMarkup(bestEnglish, LocalizeUpgradeTrackName(bestEnglish) .. " " .. tostring(range.maxIlvl), quality)
        end
        if currentTier and currentTier ~= "" then
            return FormatTrackMarkup(currentEnglish, currentTier, quality)
        end
    end

    local englishTrack = up.trackName
    local track = (englishTrack and englishTrack ~= "") and LocalizeUpgradeTrackName(englishTrack) or nil
    local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
    if maxT and maxT > 0 and track then
        return FormatTrackMarkup(englishTrack, track .. " " .. tostring(curT) .. "/" .. tostring(maxT), quality)
    end
    if track and track ~= "" then return FormatTrackMarkup(englishTrack, track, quality) end
    if slotData and slotData.upgradeTrack and not (issecretvalue and issecretvalue(slotData.upgradeTrack)) then
        local raw = slotData.upgradeTrack
        local englishTrack = raw:match("^(%S+)") or raw
        local trackLbl = LocalizeUpgradeTrackName(englishTrack)
        local curT = tonumber(slotData.currUpgrade) or tonumber(up.currUpgrade) or 0
        local maxT = tonumber(slotData.maxUpgrade) or tonumber(up.maxUpgrade) or 0
        if trackLbl and maxT > 0 then
            return FormatTrackMarkup(englishTrack, trackLbl .. " " .. tostring(curT) .. "/" .. tostring(maxT), quality)
        end
        if trackLbl and trackLbl ~= "" then
            return FormatTrackMarkup(englishTrack, trackLbl, quality)
        end
    end
    return nil
end

-- Stat helpers (must be above PaintGearPaperBottomBand — Lua 5.1 local scope).
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

local function PaintGearPaperBandRow(col, rowY, rowH, pad, valueColW, label, valueStr, iconFileID)
    local labelLeft = pad
    if iconFileID then
        local iconSz = math.min(22, rowH - 2)
        local ico = col:CreateTexture(nil, "ARTWORK")
        ico:SetSize(iconSz, iconSz)
        ico:SetPoint("TOPLEFT", col, "TOPLEFT", pad, rowY)
        ico:SetTexture(iconFileID)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        labelLeft = pad + iconSz + 6
    end
    if valueStr and valueStr ~= "" then
        local val = FontManager:CreateFontString(col, GFR("gearStatRating"), "OVERLAY")
        val:SetPoint("TOPRIGHT", col, "TOPRIGHT", -pad, rowY)
        val:SetWidth(valueColW)
        val:SetJustifyH("RIGHT")
        ns.UI_SetTextColorRole(val, "Bright")
        val:SetText(valueStr)
    end
    local labelRightInset = pad + valueColW + 8
    local row = FontManager:CreateFontString(col, GFR("gearStatLabel"), "OVERLAY")
    row:SetPoint("TOPLEFT", col, "TOPLEFT", labelLeft, rowY)
    row:SetPoint("TOPRIGHT", col, "TOPRIGHT", -labelRightInset, rowY)
    row:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(row, "Bright")
    row:SetText(label or "")
    return rowY - rowH
end

local function PaintGearStatGridRow(statCol, statY, statRowH, statPad, valueColW, label, valueStr, pctStr)
    local displayVal = valueStr or ""
    if pctStr and pctStr ~= "" then
        local fmt = (ns.L and ns.L["GEAR_STAT_VALUE_PCT_FORMAT"]) or "%s (%s)"
        displayVal = format(fmt, (valueStr and valueStr ~= "") and valueStr or "--", pctStr)
    end
    return PaintGearPaperBandRow(statCol, statY, statRowH, statPad, valueColW, label, displayVal, nil)
end

local function ComputeGearPaperStatValueColW(statInnerW, statPad)
    return math.max(96, math.floor((statInnerW - statPad * 2) * 0.42 + 0.5))
end

local function SafeGearStatNumber(val)
    if val == nil then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    if type(val) ~= "number" then return nil end
    return val
end

local function FormatGearStatDisplayNumber(val)
    local n = SafeGearStatNumber(val)
    if not n then return nil end
    return FormatNumber and FormatNumber(math.floor(n)) or tostring(math.floor(n))
end

local function BuildGearPaperStatRows(charData, isCurrentChar)
    local primaryRows = {}
    local secondaryRows = {}
    if isCurrentChar and UnitStat then
        local mainStat = (WarbandNexus.GetCurrentCharacterMainStat and WarbandNexus:GetCurrentCharacterMainStat()) or nil
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        for i = 1, #STAT_IDS do
            local stat = STAT_IDS[i]
            if stat.id == 3 then
            elseif mainStatId and stat.id ~= mainStatId then
                stat = nil
            end
            if stat then
                local ok, _, total = pcall(UnitStat, "player", stat.id)
                if ok then
                    local valueStr = FormatGearStatDisplayNumber(total)
                    if valueStr then
                        primaryRows[#primaryRows + 1] = {
                            statId = stat.id,
                            label = stat.label,
                            value = valueStr,
                        }
                    end
                end
            end
        end
        for i = 1, #SECONDARY_STATS do
            local stat = SECONDARY_STATS[i]
            local okR, rating = pcall(stat.fn)
            local okP, pct = pcall(stat.pctFn)
            local rNum = okR and SafeGearStatNumber(rating) or nil
            local pNum = okP and SafeGearStatNumber(pct) or nil
            if rNum or pNum then
                secondaryRows[#secondaryRows + 1] = {
                    label = stat.label,
                    pctStr = pNum and format("%.1f%%", pNum) or "--",
                    ratingStr = rNum and (FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum))) or "--",
                }
            end
        end
    elseif not isCurrentChar and charData and charData.stats then
        local mainStat = nil
        local mc = charData.stats.mainStatCode
        if mc == "STR" or mc == "AGI" or mc == "INT" then mainStat = mc end
        if not mainStat and WarbandNexus.GetCharacterMainStat then
            mainStat = WarbandNexus:GetCharacterMainStat(charData)
        end
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        local prim = charData.stats.primary
        if prim and next(prim) then
            for idx = 1, #STAT_IDS do
                local stat = STAT_IDS[idx]
                if stat.id == 3 then
                elseif mainStatId and stat.id ~= mainStatId then
                    stat = nil
                end
                if stat then
                    local valueStr = FormatGearStatDisplayNumber(prim[stat.id])
                    if valueStr then
                        primaryRows[#primaryRows + 1] = {
                            statId = stat.id,
                            label = stat.label,
                            value = valueStr,
                        }
                    end
                end
            end
        end
        local mergedSec = MergeOfflineSecondaryForGear(charData.stats.secondary)
        for j = 1, #mergedSec do
            local s = mergedSec[j]
            if s then
                local pNum = SafeGearStatNumber(s.pct)
                local rNum = SafeGearStatNumber(s.rating)
                if pNum or rNum then
                    secondaryRows[#secondaryRows + 1] = {
                        label = s.label,
                        pctStr = pNum and format("%.1f%%", pNum) or "--",
                        ratingStr = rNum and (FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum))) or "--",
                    }
                end
            end
        end
    end
    return primaryRows, secondaryRows
end

local GEAR_VIEWPORT_IDENTITY_H = 42

local function PaintGearViewportIdentity(viewportHost, charData, accent)
    if not viewportHost then return nil end
    local pad = 8
    local classFile = charData and charData.classFile
    local classHex = GetClassHex(classFile)
    local name = (charData and charData.name) or ""
    local realm = (charData and charData.realm) or ""
    if realm ~= "" and ns.Utilities and ns.Utilities.FormatRealmName then
        realm = ns.Utilities:FormatRealmName(realm) or realm
    end
    local avgIlvl = SafeGearStatNumber(charData and charData.itemLevel) or 0

    local bar = CreateFrame("Frame", nil, viewportHost)
    bar:SetHeight(GEAR_VIEWPORT_IDENTITY_H)
    bar:SetPoint("TOPLEFT", viewportHost, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", viewportHost, "TOPRIGHT", -pad, -pad)
    bar:EnableMouse(false)
    if bar.SetFrameLevel and viewportHost.GetFrameLevel then
        bar:SetFrameLevel((viewportHost:GetFrameLevel() or 0) + 24)
    end

    local nameRealmFs = FontManager:CreateFontString(bar, GFR("gearCharacterName"), "OVERLAY")
    nameRealmFs:SetPoint("TOP", bar, "TOP", 0, 0)
    nameRealmFs:SetPoint("LEFT", bar, "LEFT", 0, 0)
    nameRealmFs:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    nameRealmFs:SetHeight(18)
    nameRealmFs:SetJustifyH("CENTER")
    if ns.UI_ApplyOverlayLabelShadow then
        ns.UI_ApplyOverlayLabelShadow(nameRealmFs)
    else
        nameRealmFs:SetShadowOffset(1, -1)
        nameRealmFs:SetShadowColor(0, 0, 0, 1)
    end
    if name ~= "" and realm ~= "" then
        nameRealmFs:SetText("|cff" .. classHex .. name .. "|r |cff888888-|r |cffb8bac4" .. realm .. "|r")
    elseif name ~= "" then
        nameRealmFs:SetText("|cff" .. classHex .. name .. "|r")
    else
        nameRealmFs:SetText("|cff888888" .. ((ns.L and ns.L["GEAR_SECTION_CHARACTER"]) or "Character") .. "|r")
    end

    if avgIlvl > 0 then
        local ilvlFs = FontManager:CreateFontString(bar, GFR("gearIlvlBadge"), "OVERLAY")
        ilvlFs:SetPoint("TOP", nameRealmFs, "BOTTOM", 0, -2)
        ilvlFs:SetPoint("LEFT", bar, "LEFT", 0, 0)
        ilvlFs:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        ilvlFs:SetJustifyH("CENTER")
        local gr, gg, gb = (ns.UI_GetSemanticGoldColor and ns.UI_GetSemanticGoldColor()) or 1, 0.9, 0
        ilvlFs:SetTextColor(gr, gg, gb, 1)
        if ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(ilvlFs)
        else
            ilvlFs:SetShadowOffset(1, -1)
            ilvlFs:SetShadowColor(0, 0, 0, 1)
        end
        ilvlFs:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
    end
    return bar
end

local function ComputeGearPaperBottomBandHeights(primaryRows, secondaryRows, crestCount, subHdr, statRowH, crestRowH)
    local hasDivider = (#primaryRows > 0 and #secondaryRows > 0)
    local statContentRows = #primaryRows + #secondaryRows
    local statH = subHdr + (statContentRows * statRowH) + (hasDivider and 8 or 0) + 12
    if statContentRows == 0 then
        statH = subHdr + 56
    end
    local currH = subHdr + crestCount * crestRowH + 12 + 28 + 10
    local bandH = math.max(statH, currH, GEAR_LAYOUT.PAPER_BOTTOM_BAND_MIN_H or 132)
    return bandH, statH, currH
end

local function PaintGearPaperBottomBand(bottomHost, paperColW, bandH, charData, isCurrentChar, currencies, charKey, accent, primaryRows, secondaryRows)
    if not bottomHost or paperColW < 1 or bandH < 1 then return nil end
    local gearChrome = ns.GearUI_Chrome
    local splitGap = math.max(14, GEAR_LAYOUT.SIDE_BAND_GAP or 8)
    local statColW = math.max(120, math.floor((paperColW - splitGap) * 0.5 + 0.5))
    local currColW = math.max(120, paperColW - splitGap - statColW)
    local subHdr = GEAR_LAYOUT.SUBPANEL_HDR or 28
    local statRowH = GEAR_LAYOUT.STAT_ROW_H or 22
    local crestRowH = GEAR_LAYOUT.CREST_ROW_H or 26
    local statPad = GEAR_LAYOUT.SUBPANEL_PAD or 10
    if not primaryRows or not secondaryRows then
        primaryRows, secondaryRows = BuildGearPaperStatRows(charData, isCurrentChar)
    end

    local crestCurrencies, goldCurrency = BuildGearPaperCrestRows(currencies, charKey, isCurrentChar)

    local bandPanel = CreateGearSubpanel(bottomHost, paperColW, bandH, accent)
    bandPanel:SetAllPoints(bottomHost)

    local statCol = CreateFrame("Frame", nil, bandPanel)
    statCol:SetSize(statColW, bandH)
    statCol:SetPoint("TOPLEFT", bandPanel, "TOPLEFT", 0, 0)
    statCol:EnableMouse(false)
    if statCol.SetClipsChildren then statCol:SetClipsChildren(true) end

    local currCol = CreateFrame("Frame", nil, bandPanel)
    currCol:SetPoint("TOPLEFT", bandPanel, "TOPLEFT", statColW + splitGap, 0)
    currCol:SetPoint("TOPRIGHT", bandPanel, "TOPRIGHT", 0, 0)
    currCol:SetPoint("BOTTOM", bandPanel, "BOTTOM", 0, 0)
    currCol:EnableMouse(false)
    if currCol.SetClipsChildren then currCol:SetClipsChildren(true) end

    local midDiv = bandPanel:CreateTexture(nil, "ARTWORK")
    midDiv:SetColorTexture(accent[1] * 0.22, accent[2] * 0.22, accent[3] * 0.22, 0.5)
    midDiv:SetWidth(1)
    midDiv:SetPoint("TOP", bandPanel, "TOP", 0, -(subHdr - 4))
    midDiv:SetPoint("BOTTOM", bandPanel, "BOTTOM", 0, 6)
    midDiv:SetPoint("LEFT", statCol, "RIGHT", math.floor(splitGap * 0.5 + 0.5), 0)

    local statInnerW = math.max(1, statColW - statPad * 2)
    local currInnerW = math.max(1, currColW - statPad * 2)
    local valColW = math.max(96, math.floor(math.min(statInnerW, currInnerW) * 0.42 + 0.5))
    local function PaperSectionHdrOpts(titleColor)
        return {
            fontRole = "gearPanelTitle",
            hideAccentBar = true,
            underlineHeader = true,
            titleColor = titleColor,
        }
    end
    local statTitleColor = { 0.52, 0.82, 0.95 }
    local currTitleColor = { 0.96, 0.78, 0.38 }
    local statHdr = gearChrome and gearChrome.CreateSectionHeader
        and gearChrome.CreateSectionHeader(statCol, (ns.L and ns.L["GEAR_CHARACTER_STATS"]) or "Character Stats", accent, PaperSectionHdrOpts(statTitleColor))
    if statHdr then
        statHdr:SetPoint("TOPLEFT", statCol, "TOPLEFT", 0, 0)
        statHdr:SetPoint("TOPRIGHT", statCol, "TOPRIGHT", 0, 0)
    end
    local statY = -subHdr
    if #primaryRows > 0 or #secondaryRows > 0 then
        for i = 1, #primaryRows do
            local stat = primaryRows[i]
            statY = PaintGearStatGridRow(statCol, statY, statRowH, statPad, valColW, stat.label, stat.value, nil)
        end
        if #primaryRows > 0 and #secondaryRows > 0 then
            statY = statY - 6
        end
        for i = 1, #secondaryRows do
            local stat = secondaryRows[i]
            statY = PaintGearStatGridRow(
                statCol, statY, statRowH, statPad, valColW,
                stat.label, stat.ratingStr or "0", stat.pctStr or "0.0%")
        end
    else
        local noStats = FontManager:CreateFontString(statCol, GFR("gearEmptyStatsHint"), "OVERLAY")
        noStats:SetPoint("TOPLEFT", statCol, "TOPLEFT", statPad, statY)
        noStats:SetWidth(statInnerW)
        noStats:SetJustifyH("LEFT")
        ns.UI_SetTextColorRole(noStats, "Dim")
        noStats:SetText((ns.L and ns.L["GEAR_STATS_CURRENT_ONLY"]) or "Stats available for\ncurrent character only")
    end

    local currPad = statPad
    local currHdr = gearChrome and gearChrome.CreateSectionHeader
        and gearChrome.CreateSectionHeader(currCol, (ns.L and ns.L["GEAR_UPGRADE_CURRENCIES"]) or "Upgrade Currencies", accent, PaperSectionHdrOpts(currTitleColor))
    if currHdr then
        currHdr:SetPoint("TOPLEFT", currCol, "TOPLEFT", 0, 0)
        currHdr:SetPoint("TOPRIGHT", currCol, "TOPRIGHT", 0, 0)
    end
    local curY = -subHdr
    for i = 1, #crestCurrencies do
        local cur = crestCurrencies[i]
        local iconFileID = cur.icon or 134400
        local displayCrestName = cur.displayName
        if not displayCrestName or displayCrestName == "" then
            local rawCrestName = cur.name or ""
            if rawCrestName and not (issecretvalue and issecretvalue(rawCrestName)) and rawCrestName ~= "" then
                local firstWord = rawCrestName:match("^(%S+)")
                displayCrestName = FormatTrackMarkup(firstWord, firstWord, nil)
            else
                displayCrestName = rawCrestName
            end
        end
        local qty = tonumber(cur.amount) or 0
        local maxQ = tonumber(cur.maxQuantity) or 0
        local cd = {
            currencyID = cur.currencyID,
            quantity = qty,
            maxQuantity = maxQ,
            name = cur.name,
            icon = cur.icon,
        }
        local amountStr = tostring(qty)
        if ns.UI_FormatSeasonProgressCurrencyLine then
            amountStr = ns.UI_FormatSeasonProgressCurrencyLine(cd) or amountStr
        end
        curY = PaintGearPaperBandRow(currCol, curY, crestRowH, currPad, valColW, displayCrestName or "", amountStr, iconFileID)
    end
    if goldCurrency then
        curY = curY - 6
        local copper = (goldCurrency.amount or 0) * 10000 + (goldCurrency.silver or 0) * 100 + (goldCurrency.copper or 0)
        if goldCurrency._goldCopper then
            copper = goldCurrency._goldCopper
        end
        local goldLabel = (ns.L and ns.L["GOLD_LABEL"]) or "Gold"
        curY = PaintGearPaperBandRow(
            currCol, curY, crestRowH, currPad, valColW,
            goldLabel, "|cffffff00" .. FormatGold(copper) .. "|r",
            goldCurrency.icon or 133784)
    end

    bandPanel._wnStatCol = statCol
    bandPanel._wnCurrCol = currCol
    return bandPanel
end

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
        ns.UI_SetTextColorRole(label, "Bright", 0.95)
        if ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(label)
        else
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 0.9)
        end
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

local function DrawPaperDollInCard(paperParent, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar, baseX, charKey, paperOriginY, paperdollNaturalH, paperBandH, opts)
    opts = opts or {}
    paperParent = paperParent or opts.cardRef
    local card = opts.cardRef or paperParent
    baseX = baseX or PAPERDOLL_COL_INSET
    local modelW = MODEL_W + (tonumber(opts.modelBoost) or 0)
    card._gearSlotInspectList = {}
    if paperParent and paperParent ~= card then
        paperParent._gearSlotInspectList = nil
    end
    local itemTooltipContext = ns.GearUI_BuildGearTabItemTooltipContext(charData)
    -- Left panel: fixed width; slot on the right (text - icon - slot)
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local leftColRight = baseX + LEFT_PANEL_W
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + modelW + CENTER_GAP

    local slots = gearData and gearData.slots or {}
    local function GetSlotData(slotID)
        local persisted = slots[slotID]
        if not isCurrentChar or not ns.GearUI_BuildLiveEquippedSlotSnapshot then
            return persisted
        end
        local live = ns.GearUI_BuildLiveEquippedSlotSnapshot(slotID)
        if not live then return persisted end
        if not persisted then return live end
        local merged = {}
        for k, v in pairs(persisted) do
            merged[k] = v
        end
        if live.itemLink then merged.itemLink = live.itemLink end
        if live.itemID then merged.itemID = live.itemID end
        if live.itemLevel and live.itemLevel > 0 then merged.itemLevel = live.itemLevel end
        if live.quality and live.quality > 0 then merged.quality = live.quality end
        return merged
    end
    local function SlotAffordsUpgrade(slotID)
        local up = upgradeInfo and upgradeInfo[slotID]
        if not up or up.notUpgradeable or not up.canUpgrade then return false end
        if not ns.GearUI_GetUpgradeArrowDisplay then return false end
        local disp = ns.GearUI_GetUpgradeArrowDisplay(up, currencyAmounts)
        up.upgradeArrowDisplay = disp
        return disp == "green"
    end
    local function IsNotUpgradeable(slotID)
        local slot = slots[slotID]
        if slot and slot.notUpgradeable then return true end
        local up = upgradeInfo and upgradeInfo[slotID]
        if up and up.notUpgradeable then return true end
        return false
    end

    local rowStep = SLOT_SIZE + SLOT_GAP
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    local maxRows = math.max(#leftSlots, #rightSlots)
    local topInset = tonumber(opts.topContentInset) or 0
    local anchorY = paperOriginY
    if anchorY == nil then
        anchorY = 0
    end
    local paperZoneH = tonumber(paperBandH) or tonumber(paperdollNaturalH) or 0
    local startY = ComputeGearPaperdollSlotStartY(paperZoneH, maxRows, anchorY, topInset)

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    for i = 1, #leftSlots do
        local slotID = leftSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local slotData = GetSlotData(slotID)
        ns.GearUI_Paperdoll.CreateSlotButton(paperParent, slotID, slotData, leftX, startY - (i - 1) * rowStep, SlotAffordsUpgrade(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts, slotData), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar, card)
    end

    -- Right column: 6 armor + 2 trinkets — slot | icon | text (finger slots 11 then 12 = API order).
    for i = 1, #rightSlots do
        local slotID = rightSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local slotData = GetSlotData(slotID)
        ns.GearUI_Paperdoll.CreateSlotButton(paperParent, slotID, slotData, rightX, startY - (i - 1) * rowStep, SlotAffordsUpgrade(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts, slotData), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar, card)
    end

    -- Alt panel: weapons centered under model; text offset matches armor columns (TEXT_OFFSET_FROM_SLOT_CENTER).
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local WEAPON_TEXT_W = TRACK_TEXT_W
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (modelW + CENTER_GAP - weaponRowW) / 2
    local bottomY = startY - maxRows * rowStep - 8
    for i = 1, #weaponSlots do
        local slotID = weaponSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        local weaponSide = (i == 1) and "bottom_left" or "bottom_right"
        local slotData = GetSlotData(slotID)
        ns.GearUI_Paperdoll.CreateSlotButton(paperParent, slotID, slotData, wx, bottomY, SlotAffordsUpgrade(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts, slotData), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar, card)
    end

    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- down to the bottom trinket
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
    -- Paperdoll close-up: low camera distance; cam scale capped so radius normalize does not push camera away.
    local GEAR_FIXED_CAM_DISTANCE = 1.48
    local GEAR_CAM_FIT_PADDING = 0.48
    local GEAR_CAM_SCALE_CAP = 1.04
    local GEAR_PORTRAIT_ZOOM = 0.38
    local GEAR_FIXED_CAM_SCALE = 2.85
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
                if m.SetPortraitZoom then m:SetPortraitZoom(GEAR_PORTRAIT_ZOOM) end
                if m._normalized and m.SetModelScale and m.SetCameraDistance then
                    m:SetModelScale(m._scale)
                    local vw, vh = clip:GetWidth() or 1, clip:GetHeight() or 1
                    local aspectPad = (vh > 1 and (vw / vh) > 1.12) and 1.04 or 1.0
                    local camScale = m._scale
                    if camScale > GEAR_CAM_SCALE_CAP then camScale = GEAR_CAM_SCALE_CAP end
                    local camDist = GEAR_FIXED_CAM_DISTANCE
                        * GEAR_CAM_FIT_PADDING
                        * aspectPad
                        * m._zoom
                        * camScale
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
            local s = (GEAR_REFERENCE_RADIUS / r) * 0.94 * 1.38
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
        m._zoom = 0.65
        m._rotation = 0
        do
            local mv = gearData and gearData.modelView
            if type(mv) == "table" then
                if mv.rotation ~= nil then
                    m._rotation = tonumber(mv.rotation) or 0
                end
                if mv.zoom ~= nil then
                    local z = tonumber(mv.zoom)
                    if z and z > 0 then
                        -- Saved views from older builds were too far; pull toward new close-up default.
                        if z < 0.58 or (z >= 0.72 and z <= 1.12) then
                            z = 0.65
                        end
                        m._zoom = z
                    end
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
            if ns.UI_ApplyOverlayLabelShadow then
                ns.UI_ApplyOverlayLabelShadow(name)
            else
                name:SetShadowOffset(1, -1)
                name:SetShadowColor(0, 0, 0, 0.95)
            end
            portrait._name = name

            -- "Lv N · Race" meta line.
            local meta = FontManager:CreateFontString(portrait, GFR("gearPortraitMeta"), "OVERLAY")
            meta:SetPoint("TOP", name, "BOTTOM", 0, -2)
            meta:SetWidth(modelW - 16)
            meta:SetJustifyH("CENTER")
            ns.UI_SetTextColorRole(meta, "Normal")
            if ns.UI_ApplyOverlayLabelShadow then
                ns.UI_ApplyOverlayLabelShadow(meta)
            else
                meta:SetShadowOffset(1, -1)
                meta:SetShadowColor(0, 0, 0, 0.85)
            end
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
            local pillBg = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("card"))
                or COLORS.bgCard or COLORS.bgLight or COLORS.bg
            pill:SetBackdropColor(pillBg[1], pillBg[2], pillBg[3], (pillBg[4] or 1) * 0.85)
            local pillBorderA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.38 or 0.55
            local ac = COLORS.accent or { 0.5, 0.3, 0.8 }
            pill:SetBackdropBorderColor(ac[1] * 0.5, ac[2] * 0.5, ac[3] * 0.5, pillBorderA)
            portrait._pill = pill
            local pillLabel = FontManager:CreateFontString(pill, GFR("gearPortraitMeta"), "OVERLAY")
            pillLabel:SetPoint("CENTER", pill, "CENTER", 0, 0)
            local gr, gg, gb = (ns.UI_GetSemanticGoldColor and ns.UI_GetSemanticGoldColor()) or 1, 0.82, 0
            pillLabel:SetTextColor(gr, gg, gb, 1)
            if ns.UI_ApplyOverlayLabelShadow then
                ns.UI_ApplyOverlayLabelShadow(pillLabel)
            else
                pillLabel:SetShadowOffset(1, -1)
                pillLabel:SetShadowColor(0, 0, 0, 0.9)
            end
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
    local modelBorderA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.45 or 0.65
    modelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], modelBorderA)
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
        if ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(ilvlOverlay)
        else
            ilvlOverlay:SetShadowOffset(1, -1)
            ilvlOverlay:SetShadowColor(0, 0, 0, 1)
        end
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
        if ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(nameLabel)
        else
            nameLabel:SetShadowOffset(1, -1)
            nameLabel:SetShadowColor(0, 0, 0, 1)
        end
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

    if nameWrapper and nameWrapper.Hide then nameWrapper:Hide() end
    if ilvlFrame and ilvlFrame.Hide then ilvlFrame:Hide() end

    if centerRef and not card._wnGearHeroRibbon then
        local idHost = centerRef._clip or centerRef
        if ns._gearModelIdentityBar and ns._gearModelIdentityBar.Hide then
            ns._gearModelIdentityBar:Hide()
            ns._gearModelIdentityBar:SetParent(nil)
        end
        ns._gearModelIdentityBar = PaintGearViewportIdentity(idHost, charData, accent)
    end

    if opts.paperChrome and centerRef then
        AnchorGearPaperChromeBehindModel(opts.paperChrome, centerRef, card)
    end
    end

    if card then
        card._wnGearPaperdollLayout = {
            paperOriginY = paperOriginY,
            topContentInset = topInset,
            paperBandH = paperBandH,
            paperTopZoneH = paperZoneH,
            paperdollNaturalH = paperdollNaturalH,
            maxRows = maxRows,
        }
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

local function ResolveGearTabPanelHeight(mf, yOffset, contentBandMinH, paperdollNaturalH)
    local panelH = math.max(contentBandMinH or 0, paperdollNaturalH or 0)
    local bodyAvailH = (ns.UI_GetMainTabScrollBodyHeight and ns.UI_GetMainTabScrollBodyHeight(mf)) or 0
    if bodyAvailH > 0 then
        local cardChromeV = CARD_PAD + 24 + CARD_PAD
        local maxPanelH = math.max(1, bodyAvailH - math.abs(yOffset or 0) - 12 - cardChromeV)
        panelH = math.max(panelH, maxPanelH)
    end
    return panelH
end

local function EnforceGearTopRowNoOverlap(card, layout, mf)
    if not layout then return false end
    local gap = layout.panelGutter or GEAR_PANEL_GAP
    local paperColW = math.max(GEAR_PAPER_COL_FIXED_W, layout.paperColW or GEAR_PAPER_COL_FIXED_W)
    local recColW = math.max(0, layout.recColW or layout.sideColW or 0)
    local needInner = paperColW + (recColW > 0 and (gap + recColW) or 0)
    layout.minTopRowInnerW = needInner
    layout.paperColW = paperColW
    if card and card.GetWidth then
        layout.cardInnerW = GetGearCardInnerWidthFromCard(card)
    end
    layout.layoutInnerW = layout.cardInnerW or layout.layoutInnerW or needInner
    return false
end

local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar, currencies, storageFindings, storageScanPending)
    local rowStep = SLOT_SIZE + SLOT_GAP
    -- Content height: section + slot columns + gap + weapon row (Main/Off Hand) + bottom pad so card border is below weapons
    local contentTop = 8
    local weaponBottom = 8 * rowStep + 8 + SLOT_SIZE
    local slotsOnlyH = contentTop + weaponBottom + CARD_PAD
    currencies = currencies or {}
    local crestCount = 0
    for i = 1, #currencies do
        if not currencies[i].isGold then crestCount = crestCount + 1 end
    end
    local subHdr = GEAR_LAYOUT.SUBPANEL_HDR or 28
    local statRowH = GEAR_LAYOUT.STAT_ROW_H or 22
    local crestRowH = GEAR_LAYOUT.CREST_ROW_H or 26
    local primaryRows, secondaryRows = BuildGearPaperStatRows(charData, isCurrentChar == true)
    local paperBottomBandH = select(1, ComputeGearPaperBottomBandHeights(primaryRows, secondaryRows, crestCount, subHdr, statRowH, crestRowH))
    local paperdollNaturalH = slotsOnlyH + 10 + paperBottomBandH
    local cardH = CARD_PAD + 8 + paperdollNaturalH + CARD_PAD

    local parentW = (parent and parent.GetWidth) and parent:GetWidth() or 0

    -- New card on every DrawPaperDollCard: PopulateContent tears down scrollChild, so roster changes cannot reuse the old card here.
    local card = CreateCard(parent, cardH)
    if card.SetClipsChildren then
        card:SetClipsChildren(false)
    end
    local mfDraw = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    AnchorGearCardFillWidth(card, parent, yOffset, mfDraw)
    local cardInnerW = GetGearCardInnerWidthFromCard(card)
    if (card:GetWidth() or 0) < 1 and parentW > 0 then
        cardInnerW = ResolveGearTabCardInnerWidth(parentW)
    end

    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }

    local PANEL_GAP = GEAR_PANEL_GAP
    local recEnabled = WarbandNexus:IsGearStorageRecommendationsEnabled()
    local paperColW, recColW, layoutInnerW
    if ns.GearUI_ComputeTopRowWidths then
        paperColW, recColW, layoutInnerW = ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
    elseif ns.GearUI_ComputeTopRowLayout then
        _, paperColW, recColW, layoutInnerW = ns.GearUI_ComputeTopRowLayout(cardInnerW, nil)
        if not recEnabled then recColW = 0 end
    else
        paperColW, recColW = ComputeGearLayoutWidths(cardInnerW, recEnabled)
        layoutInnerW = cardInnerW
    end
    local topLayoutMode = "row"
    local storageW = recColW > 0 and recColW or (layoutInnerW or cardInnerW)
    local paperLeft = CARD_PAD

    local panelTopY = -(CARD_PAD + 6)
    local SECTION_GAP = GEAR_LAYOUT.SECTION_GAP or 16
    local modelBoost = math.max(0, math.min(MAX_PAPER_MODEL_BOOST, paperColW - GEAR_PAPER_COL_FIXED_W))

    local contentBandMinH = math.max(paperdollNaturalH, GEAR_LAYOUT.CONTENT_BAND_MIN_H or 360)
    local mfHostEarly = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local panelH = ResolveGearTabPanelHeight(mfHostEarly, yOffset, contentBandMinH, paperdollNaturalH)
    local contentBandH = panelH
    paperBottomBandH = select(1, ComputeGearPaperBottomBandHeights(primaryRows, secondaryRows, crestCount, subHdr, statRowH, crestRowH))
    local paperTopZoneH = math.max(slotsOnlyH, contentBandH - paperBottomBandH)

    local gearHosts = {
        paperColW = paperColW,
        recColW = recColW,
        sideColW = recColW,
        paperLeft = paperLeft,
        sectionGap = SECTION_GAP,
        topZoneH = contentBandH,
        contentBandH = contentBandH,
        topLayoutMode = topLayoutMode,
        layoutInnerW = layoutInnerW,
        paperZoneH = paperTopZoneH,
        paperTopZoneH = paperTopZoneH,
        paperBottomBandH = paperBottomBandH,
        slotsOnlyH = slotsOnlyH,
        paperdollNaturalH = paperdollNaturalH,
        cardInnerW = cardInnerW,
        panelGutter = GEAR_LAYOUT.COL_GAP or PANEL_GAP,
        panelH = panelH,
        modelBoost = modelBoost,
    }
    card._wnGearHeroRibbon = nil

    EnsureGearCardColumnHosts(card, gearHosts, panelTopY, recEnabled)
    RelayoutGearCardColumnHosts(card, gearHosts, panelTopY, recEnabled)
    local leftCol = gearHosts.leftColHost
    local paperTop = gearHosts.paperTopHost
    local paperBottom = gearHosts.paperBottomHost
    local bodyHost = gearHosts.bodyHost
    local rightCol = gearHosts.rightColHost
    local horizParent = paperTop or leftCol or card

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
    paperChrome:Hide()
    if gearChrome and gearChrome.ApplyPaperdollViewport then
        gearChrome.ApplyPaperdollViewport(paperChrome, accent)
    elseif paperChrome.SetBackdrop then
        pcall(paperChrome.SetBackdrop, paperChrome, nil)
    end
    if paperChrome.SetClipsChildren then
        paperChrome:SetClipsChildren(false)
    end
    gearHosts.paperChrome = paperChrome

    if paperBottom then
        local bandPanel = PaintGearPaperBottomBand(
            paperBottom, paperColW, paperBottomBandH,
            charData, isCurrentChar, currencies, charKey, accent,
            primaryRows, secondaryRows
        )
        gearHosts.statPanel = bandPanel
        gearHosts.currencyPanel = bandPanel
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

        -- ── RIGHT COLUMN: Gear upgrade recommendations (full height, aligned with paperdoll) ──
        local storageParent = gearHosts.rightColHost or card
        local storagePanel = CreateGearSubpanel(storageParent, storageW, contentBandH, accent)
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
        local recTitleColor = {
            math.min(1, accent[1] * 1.12),
            math.min(1, accent[2] * 1.12),
            math.min(1, accent[3] * 1.12),
        }
        local storageHdrText = GetLocalizedText("GEAR_RECOMMENDED_TITLE", "Recommended")
        local storageHdr = gearChrome and gearChrome.CreateSectionHeader
            and gearChrome.CreateSectionHeader(storagePanel, storageHdrText, accent, {
                fontRole = "gearStorageCardTitle",
                hideAccentBar = true,
                underlineHeader = true,
                titleColor = recTitleColor,
                height = storageHeaderH,
            })
        if storageHdr then
            storageHdr:ClearAllPoints()
            storageHdr:SetPoint("TOPLEFT", storagePanel, "TOPLEFT", storagePad, 0)
            storageHdr:SetPoint("TOPRIGHT", storagePanel, "TOPRIGHT", -storagePad, 0)
            if storageHdr.GetHeight then
                local hh = storageHdr:GetHeight()
                if hh and hh > 0 then storageHeaderH = hh end
            end
            if storageHdr.SetFrameLevel and storagePanel.GetFrameLevel then
                storageHdr:SetFrameLevel(storagePanel:GetFrameLevel() + 4)
            end
            storageHdr:Show()
        elseif FontManager then
            storageHdr = CreateFrame("Frame", nil, storagePanel)
            storageHdr:SetHeight(storageHeaderH)
            storageHdr:SetPoint("TOPLEFT", storagePanel, "TOPLEFT", storagePad, 0)
            storageHdr:SetPoint("TOPRIGHT", storagePanel, "TOPRIGHT", -storagePad, 0)
            local fs = FontManager:CreateFontString(storageHdr, GFR("gearStorageCardTitle"), "OVERLAY")
            if fs then
                fs:SetPoint("LEFT", storageHdr, "LEFT", 0, 0)
                fs:SetPoint("RIGHT", storageHdr, "RIGHT", 0, 0)
                fs:SetJustifyH("LEFT")
                fs:SetText(storageHdrText)
                fs:SetTextColor(recTitleColor[1], recTitleColor[2], recTitleColor[3])
            end
            local rule = storageHdr:CreateTexture(nil, "ARTWORK")
            rule:SetHeight(1)
            rule:SetPoint("BOTTOMLEFT", storageHdr, "BOTTOMLEFT", 0, 2)
            rule:SetPoint("BOTTOMRIGHT", storageHdr, "BOTTOMRIGHT", 0, 2)
            rule:SetColorTexture(accent[1] * 0.45, accent[2] * 0.45, accent[3] * 0.45, 0.65)
        end
        gearHosts.storageRecTitle = storageHdr

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
            scroll:SetPoint("TOPLEFT", storagePanel, "TOPLEFT", storagePad, -storageHeaderH)
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
                    ns.UI_SetTextColorRole(empty, "Muted")
                else
                    empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY", "No transferable stash upgrade beats your equipped items for these slots."))
                    ns.UI_SetTextColorRole(empty, "Dim")
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
    end

    -- Paperdoll slots + model in top band; stats/currencies sit in paperBottomHost below.
    local paperParent = paperTop or leftCol or card
    DrawPaperDollInCard(paperParent, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true,
        PAPERDOLL_COL_INSET, charKey, 0, slotsOnlyH, paperTopZoneH,
        {
            cardRef = card,
            deferCenter = true,
            modelBoost = modelBoost,
            topContentInset = 0,
            skipCenterIdentity = true,
            paperChrome = paperChrome,
        })

    -- Staged paint: one idle tick per stage (mid+center -> storage rows -> slot inspect) to avoid stacking FRAME SPIKEs.
    local gearDeferGen = ns._gearTabDrawGen
    local function IsGearDeferGenCurrent(gen)
        if ns.GearUI_IsPaintGenerationCurrent then
            return ns.GearUI_IsPaintGenerationCurrent(gen)
        end
        return gen ~= nil and gen == (ns._gearTabDrawGen or 0)
    end
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
            if not IsGearDeferGenCurrent(genNow) then return end
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
        if not IsGearDeferGenCurrent(gearDeferGen) then
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
                    if not IsGearDeferGenCurrent(gearDeferGen) then
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
                if not IsGearDeferGenCurrent(gearDeferGen) then
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

    cardH = CARD_PAD + 8 + panelH + CARD_PAD
    if recContent then
        local newViewportH = contentBandH - storageHeaderH - storagePad - 10
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
            slotsOnlyH = slotsOnlyH,
            paperZoneH = paperTopZoneH,
            paperTopZoneH = paperTopZoneH,
            paperBottomBandH = paperBottomBandH,
            contentBandH = contentBandH,
            topZoneH = contentBandH,
            panelH = panelH,
            sectionGap = SECTION_GAP,
            recColW = recColW,
            sideColW = recColW,
            paperLeft = paperLeft,
            panelTopY = panelTopY,
            panelGutter = GEAR_LAYOUT.COL_GAP or PANEL_GAP,
            paperChrome = paperChrome,
            colDivider = colDiv,
            topStackDivider = gearHosts.topStackDivider,
            topLayoutMode = topLayoutMode,
            layoutInnerW = layoutInnerW,
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
            paperTopHost = gearHosts.paperTopHost,
            paperBottomHost = gearHosts.paperBottomHost,
            statPanel = gearHosts.statPanel,
            currencyPanel = gearHosts.currencyPanel,
            rightColHost = gearHosts.rightColHost,
            bottomColHost = gearHosts.bottomColHost,
        }
        local layoutSync = card._wnGearViewportLayout
        if card._gearSlotInspectList and #card._gearSlotInspectList > 0 then
            EnforceGearTopRowNoOverlap(card, layoutSync, mfDraw)
            RelayoutGearPaperdollInCard(card, layoutSync)
            RelayoutGearCardColumnHosts(card, layoutSync, panelTopY, recEnabled)
            if layoutSync.topRowStackExtraH and layoutSync.topRowStackExtraH > 0 then
                cardH = cardH + layoutSync.topRowStackExtraH
            end
            layoutSync.topLayoutMode = layoutSync.topLayoutMode or topLayoutMode
            card:SetHeight(cardH)
            -- If defer chain exited early (empty list bug / tab switch), still paint enchant/gem once.
            local slotList = card._gearSlotInspectList
            for si = 1, #slotList do
                local sb = slotList[si]
                if sb and sb._needsDeferredInspect and sb._gearInspectSt and not sb._gearInspectSt.ready then
                    GearSlotApplyDeferredEnchantGemInspect(sb)
                end
            end
        end
    end
    return yOffset - cardH - 12, cardH
end

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
    -- Prefer live viewport width during corner-drag (scrollChild width may stay frozen/wide).
    local layoutInnerFromViewport = nil
    if contentWidth and contentWidth > 0 then
        layoutInnerFromViewport = ResolveGearTabCardInnerWidth(contentWidth)
    end
    layout.cardInnerW = layoutInnerFromViewport or GetGearCardInnerWidthFromCard(card)
    if layout.cardInnerW < 1 and parentW and parentW > 0 then
        layout.cardInnerW = ResolveGearTabCardInnerWidth(parentW)
    end
    local recEnabled = WarbandNexus:IsGearStorageRecommendationsEnabled()
    if layout.cardInnerW and layout.cardInnerW > 0 then
        local cardInnerW = layout.cardInnerW
        local paperColW, recColW, layoutInnerW
        if ns.GearUI_ComputeTopRowWidths then
            paperColW, recColW, layoutInnerW = ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
        elseif ns.GearUI_ComputeTopRowLayout then
            _, paperColW, recColW, layoutInnerW = ns.GearUI_ComputeTopRowLayout(cardInnerW, nil)
            if not recEnabled then recColW = 0 end
        else
            paperColW, recColW = ComputeGearLayoutWidths(cardInnerW, recEnabled)
            layoutInnerW = cardInnerW
        end
        layout.paperColW = math.max(GEAR_PAPER_COL_FIXED_W, paperColW or 0)
        layout.recColW = recColW
        layout.sideColW = recColW
        layout.layoutInnerW = layoutInnerW or layout.cardInnerW or cardInnerW
        layout.storageW = recColW > 0 and recColW or (layout.layoutInnerW or cardInnerW)
        layout.panelGutter = GEAR_PANEL_GAP
    end

    local paperdollNaturalH = layout.paperdollNaturalH or 0
    local sectionGap = layout.sectionGap or 12
    local panelTopY = layout.panelTopY or (-CARD_PAD - 22)
    local horizParentLay = layout.paperTopHost or layout.leftColHost or card
    local panelH = layout.panelH or 0
    local contentBandMinH = math.max(paperdollNaturalH, GEAR_LAYOUT.CONTENT_BAND_MIN_H or 360)
    local bottomBand = layout.paperBottomBandH or 0

    if not chromeOnly then
        panelH = ResolveGearTabPanelHeight(mf, layout.scrollYOffset or 0, contentBandMinH, paperdollNaturalH)
        layout.panelH = panelH
        layout.contentBandH = panelH
        layout.topZoneH = panelH
        layout.paperTopZoneH = math.max(1, panelH - bottomBand)
        layout.paperZoneH = layout.paperTopZoneH
    end

    EnforceGearTopRowNoOverlap(card, layout, mf)
    RelayoutGearPaperdollInCard(card, layout)
    local measuredStorageW = RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    if measuredStorageW and measuredStorageW > 0 then
        layout.storageW = measuredStorageW
    end

    local cardH = CARD_PAD + 24 + panelH + CARD_PAD
    if layout.topRowStackExtraH and layout.topRowStackExtraH > 0 then
        cardH = cardH + layout.topRowStackExtraH
    end
    if layout.paperChrome then
        local modelHost = nil
        if ns._gearDressModel and ns._gearDressModel.IsShown and ns._gearDressModel:IsShown() then
            modelHost = ns._gearDressModel
        elseif ns._gearPortraitPanel and ns._gearPortraitPanel.IsShown and ns._gearPortraitPanel:IsShown() then
            modelHost = ns._gearPortraitPanel
        end
        AnchorGearPaperChromeBehindModel(layout.paperChrome, modelHost, card)
    end
    if layout.paperBottomBandH and layout.paperBottomBandH > 0 then
        RelayoutGearCardColumnHosts(card, layout, panelTopY, recEnabled)
    end
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
    if ns.Gear_GetEffectiveIlvl then
        ilvl = ns.Gear_GetEffectiveIlvl(itemLink) or 0
    else
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
    end
    if quality == 0 then
        pcall(function()
            if C_Item and C_Item.GetItemInfo then
                local _, _, q = C_Item.GetItemInfo(itemLink)
                if q then quality = q end
            end
        end)
    end
    ilvl = math.floor(tonumber(ilvl) or 0)
    return {
        itemID = itemID,
        itemLink = itemLink,
        itemLevel = ilvl,
        quality = quality,
    }
end

local function GearSlotHasInspectableItemLink(slotRef)
    if not slotRef or not slotRef.itemLink or slotRef.itemLink == "" then return false end
    if issecretvalue and issecretvalue(slotRef.itemLink) then return true end
    return true
end

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

    local upInfo = sb._gearUpgradeInfo and sb._gearUpgradeInfo[sb._slotID]
    local arrowDisplay = (upInfo and ns.GearUI_GetUpgradeArrowDisplay)
        and ns.GearUI_GetUpgradeArrowDisplay(upInfo, sb._gearCurrencyAmounts) or nil
    if upInfo then upInfo.upgradeArrowDisplay = arrowDisplay end
    local expectUpgradeShown = (GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and slotData and slotData.itemLink and slotData.itemLink ~= ""
            and not (issecretvalue and issecretvalue(slotData.itemLink)))
        or (arrowDisplay == "green" and not notUpgradeable)
    local upShown = sb._gearUpgradeArrow and sb._gearUpgradeArrow:IsShown() == true
    if expectUpgradeShown ~= upShown then return false end

    local aff = arrowDisplay == "green"
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

    local tNew = ""
    if type(trackText) == "string" and trackText ~= ""
        and not (issecretvalue and issecretvalue(trackText)) then
        tNew = trackText
    end
    local tOld = ""
    local tl = sb._gearTrackLabel
    if tl and tl.IsShown and tl:IsShown() and tl.GetText then
        local rawOld = tl:GetText()
        if rawOld and not (issecretvalue and issecretvalue(rawOld)) then
            tOld = rawOld
        end
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
ns.GearUI_DrawPaperDollCard = DrawPaperDollCard
ns.GearUI_GetSlotTrackText = GetSlotTrackText
ns.GearUI_GearSlotApplyDeferredEnchantGemInspect = GearSlotApplyDeferredEnchantGemInspect
ns.GearUI_GearSlotPaperdollVisualEquals = GearSlotPaperdollVisualEquals
ns.GearUI_BuildLiveEquippedSlotSnapshot = BuildLiveEquippedSlotSnapshot
ns.GearUI_GearSlotHasInspectableItemLink = GearSlotHasInspectableItemLink

function ns.GearUI_Paperdoll.RefreshTheme()
    local C = COLORS or ns.UI_COLORS or {}
    local accent = C.accent or { 0.5, 0.3, 0.8 }
    local borderA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.45 or 0.65

    if ns._gearModelBorder and ns._gearModelBorder.SetBackdropBorderColor then
        ns._gearModelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], borderA)
    end

    if ns._gearPortraitPanel then
        ApplyGearModelViewportFill(ns._gearPortraitPanel)
    end
    if ns._gearNoPreviewFrame then
        ApplyGearModelViewportFill(ns._gearNoPreviewFrame)
        local portrait = ns._gearNoPreviewFrame
        if portrait._pill and portrait._pill.SetBackdropColor then
            local pillBg = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("card"))
                or C.bgCard or C.bgLight or C.bg
            portrait._pill:SetBackdropColor(pillBg[1], pillBg[2], pillBg[3], (pillBg[4] or 1) * 0.85)
            local pillBorderA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.38 or 0.55
            portrait._pill:SetBackdropBorderColor(accent[1] * 0.5, accent[2] * 0.5, accent[3] * 0.5, pillBorderA)
        end
        if portrait._pillLabel then
            local gr, gg, gb = (ns.UI_GetSemanticGoldColor and ns.UI_GetSemanticGoldColor()) or 1, 0.82, 0
            portrait._pillLabel:SetTextColor(gr, gg, gb, 1)
            if ns.UI_ApplyOverlayLabelShadow then ns.UI_ApplyOverlayLabelShadow(portrait._pillLabel) end
        end
        if portrait._name and ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(portrait._name)
        end
        if portrait._meta and ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(portrait._meta)
        end
    end

    local overlayLabels = {}
    if ns._gearIlvlFrame and ns._gearIlvlFrame._label then
        overlayLabels[#overlayLabels + 1] = ns._gearIlvlFrame._label
    end
    if ns._gearNameWrapper and ns._gearNameWrapper._label then
        overlayLabels[#overlayLabels + 1] = ns._gearNameWrapper._label
    end
    if ns._gearOfflineCenterChrome and ns._gearOfflineCenterChrome._label then
        overlayLabels[#overlayLabels + 1] = ns._gearOfflineCenterChrome._label
    end
    for i = 1, #overlayLabels do
        if ns.UI_ApplyOverlayLabelShadow then
            ns.UI_ApplyOverlayLabelShadow(overlayLabels[i])
        end
    end

    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local card = mf and mf._gearPaperdollCard
    local inspectList = card and card._gearSlotInspectList
    if inspectList then
        local slotBg = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("viewport"))
            or C.surfaceViewport or { 0.05, 0.05, 0.07, 0.9 }
        for j = 1, #inspectList do
            local btn = inspectList[j]
            if btn and btn._gearSlotBg then
                btn._gearSlotBg:SetColorTexture(slotBg[1], slotBg[2], slotBg[3], slotBg[4] or 0.9)
            end
            if btn and btn.ilvlLabel and ns.UI_ApplyOverlayLabelShadow then
                ns.UI_ApplyOverlayLabelShadow(btn.ilvlLabel)
            end
        end
    end
end
