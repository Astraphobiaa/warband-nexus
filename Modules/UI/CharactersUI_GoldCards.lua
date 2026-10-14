--[[
    Warband Nexus - Characters tab: gold summary card trio geometry (split from CharactersUI.lua).
    Current Character / Warband Gold / Total Gold + WoW Token cards: metrics, stack-mode hysteresis,
    interior layout and live-resize relayout. WarbandNexus:DrawCharacterList in CharactersUI.lua builds the frames
    and calls these through ns.CharactersUI at paint time.
]]

local ADDON_NAME, ns = ...
local B = assert(ns.CharactersUI and ns.CharactersUI._bind, "CharactersUI_GoldCards: load Modules/UI/CharactersUI.lua first")
local COLORS = B.COLORS

--- Narrow layout: stacked Total Gold / WoW Token subtitle+body column height (`MAIN_SHELL.HEADER_BAR_HEIGHT` rhythm).
local function CharactersTotalGoldTokenStackTextHeight()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.HEADER_BAR_HEIGHT or 40
end

local CHAR_GOLD_ROW_MIN_WIDTH = 500
local GOLD_CARD_STD_HEIGHT = 90
local GOLD_CARD_TALL_HEIGHT = 108
-- Side-by-side Total Gold | Token needs room for two icons + two long money strings;
-- on compact/laptop screens (<380 card width), stack vertically to grant full card width.
local GOLD_TOKEN_MIN_SPLIT_WIDTH = 380

local CHAR_GOLD_STACK_HYSTERESIS = 24

local function ComputeCharactersGoldCardMetrics(hostW, leftMargin, rightMargin, cardSpacing, layoutState)
    local innerGoldW = math.max(1, hostW - leftMargin - rightMargin)
    local totalSpacing = cardSpacing * 2
    local stackGoldCards
    if layoutState and layoutState.stackGoldCards ~= nil then
        if layoutState.stackGoldCards then
            stackGoldCards = innerGoldW < (CHAR_GOLD_ROW_MIN_WIDTH + CHAR_GOLD_STACK_HYSTERESIS)
        else
            stackGoldCards = innerGoldW < (CHAR_GOLD_ROW_MIN_WIDTH - CHAR_GOLD_STACK_HYSTERESIS)
        end
    else
        stackGoldCards = innerGoldW < CHAR_GOLD_ROW_MIN_WIDTH
    end
    local goldCardW1, goldCardW2, goldCardW3
    if stackGoldCards then
        goldCardW1 = innerGoldW
        goldCardW2 = innerGoldW
        goldCardW3 = innerGoldW
    else
        goldCardW1 = math.floor((innerGoldW - totalSpacing) / 3)
        goldCardW2 = goldCardW1
        goldCardW3 = innerGoldW - totalSpacing - goldCardW1 - goldCardW2
    end
    local stackGoldTokenInCard3
    if layoutState and layoutState.stackGoldTokenInCard3 ~= nil then
        if layoutState.stackGoldTokenInCard3 then
            stackGoldTokenInCard3 = goldCardW3 < (GOLD_TOKEN_MIN_SPLIT_WIDTH + CHAR_GOLD_STACK_HYSTERESIS)
        else
            stackGoldTokenInCard3 = goldCardW3 < (GOLD_TOKEN_MIN_SPLIT_WIDTH - CHAR_GOLD_STACK_HYSTERESIS)
        end
    else
        stackGoldTokenInCard3 = goldCardW3 < GOLD_TOKEN_MIN_SPLIT_WIDTH
    end
    local card12H = GOLD_CARD_STD_HEIGHT
    local card3H = stackGoldTokenInCard3 and GOLD_CARD_TALL_HEIGHT or GOLD_CARD_STD_HEIGHT
    return {
        innerGoldW = innerGoldW,
        stackGoldCards = stackGoldCards,
        stackGoldTokenInCard3 = stackGoldTokenInCard3,
        goldCardW1 = goldCardW1,
        goldCardW2 = goldCardW2,
        goldCardW3 = goldCardW3,
        card12H = card12H,
        card3H = card3H,
        cardSpacing = cardSpacing,
    }
end

local function ApplyTotalGoldCardInterior(bundle, stackToken)
    local totalGoldCard = bundle.total
    local divider = bundle.divider
    local tgIcon = bundle.tgIcon
    local tgTextContainer = bundle.tgTextContainer
    local tkIcon = bundle.tkIcon
    local tkTextContainer = bundle.tkTextContainer
    if not totalGoldCard or not divider or not tgIcon or not tgTextContainer or not tkIcon or not tkTextContainer then
        return
    end
    if stackToken then
        divider:Hide()
        tgIcon:ClearAllPoints()
        tgIcon:SetPoint("TOPLEFT", totalGoldCard, "TOPLEFT", 12, -12)
        tgTextContainer:ClearAllPoints()
        tgTextContainer:SetPoint("TOP", totalGoldCard, "TOP", 0, -10)
        tgTextContainer:SetPoint("LEFT", tgIcon, "RIGHT", 10, 0)
        tgTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        tgTextContainer:SetHeight(CharactersTotalGoldTokenStackTextHeight())
        local midRule = bundle.midRule
        if not midRule then
            midRule = totalGoldCard:CreateTexture(nil, "ARTWORK")
            if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(midRule, "horizontal", 1) else midRule:SetHeight(1) end
            midRule:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35)
            bundle.midRule = midRule
        end
        midRule:ClearAllPoints()
        midRule:SetPoint("LEFT", totalGoldCard, "LEFT", 10, 0)
        midRule:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        midRule:SetPoint("TOP", totalGoldCard, "TOP", 0, -52)
        midRule:Show()
        tkIcon:ClearAllPoints()
        tkIcon:SetPoint("TOPLEFT", totalGoldCard, "TOPLEFT", 14, -58)
        tkTextContainer:ClearAllPoints()
        tkTextContainer:SetPoint("TOP", totalGoldCard, "TOP", 0, -56)
        tkTextContainer:SetPoint("LEFT", tkIcon, "RIGHT", 10, 0)
        tkTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        tkTextContainer:SetHeight(CharactersTotalGoldTokenStackTextHeight())
    else
        if bundle.midRule then
            bundle.midRule:Hide()
        end
        divider:Show()
        divider:ClearAllPoints()
        divider:SetPoint("CENTER", totalGoldCard, "CENTER", 0, 0)
        tgIcon:ClearAllPoints()
        tgIcon:SetPoint("CENTER", totalGoldCard, "LEFT", 15 + 18, 0)
        tgTextContainer:ClearAllPoints()
        tgTextContainer:SetPoint("LEFT", tgIcon, "RIGHT", 12, 0)
        tgTextContainer:SetPoint("RIGHT", divider, "LEFT", -8, 0)
        tgTextContainer:SetPoint("TOP", tgIcon, "TOP", 0, 0)
        tgTextContainer:SetPoint("BOTTOM", tgIcon, "BOTTOM", 0, 0)
        tkIcon:ClearAllPoints()
        tkIcon:SetPoint("LEFT", divider, "RIGHT", 14, 0)
        tkTextContainer:ClearAllPoints()
        tkTextContainer:SetPoint("LEFT", tkIcon, "RIGHT", 10, 0)
        tkTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -12, 0)
        tkTextContainer:SetPoint("TOP", tkIcon, "TOP", 0, 0)
        tkTextContainer:SetPoint("BOTTOM", tkIcon, "BOTTOM", 0, 0)
    end
end

local function ApplyCharactersGoldCardsGeometry(bundle, hostW)
    if not bundle or not bundle.char or not bundle.wb or not bundle.total then
        return false
    end
    local leftMargin = bundle.leftMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local rightMargin = bundle.rightMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local cardSpacing = bundle.cardSpacing or (ns.UI_LAYOUT and ns.UI_LAYOUT.CARD_GAP) or 10
    local yAnchor = bundle.yOffset or 0
    local gm = ComputeCharactersGoldCardMetrics(hostW, leftMargin, rightMargin, cardSpacing, bundle._layoutState)
    local charGoldCard = bundle.char
    local wbGoldCard = bundle.wb
    local totalGoldCard = bundle.total

    charGoldCard:SetHeight(gm.card12H)
    charGoldCard:SetWidth(gm.goldCardW1)
    charGoldCard:ClearAllPoints()
    charGoldCard:SetPoint("TOPLEFT", bundle.parent, "TOPLEFT", leftMargin, -yAnchor)

    wbGoldCard:SetHeight(gm.card12H)
    wbGoldCard:SetWidth(gm.goldCardW2)
    wbGoldCard:ClearAllPoints()
    if gm.stackGoldCards then
        wbGoldCard:SetPoint("TOPLEFT", charGoldCard, "BOTTOMLEFT", 0, -cardSpacing)
    else
        wbGoldCard:SetPoint("TOPLEFT", charGoldCard, "TOPRIGHT", cardSpacing, 0)
    end

    totalGoldCard:SetHeight(gm.card3H)
    totalGoldCard:SetWidth(gm.goldCardW3)
    totalGoldCard:ClearAllPoints()
    if gm.stackGoldCards then
        totalGoldCard:SetPoint("TOPLEFT", wbGoldCard, "BOTTOMLEFT", 0, -cardSpacing)
    else
        totalGoldCard:SetPoint("TOPLEFT", wbGoldCard, "TOPRIGHT", cardSpacing, 0)
    end

    ApplyTotalGoldCardInterior(bundle, gm.stackGoldTokenInCard3)
    bundle._gm = gm
    bundle._layoutState = {
        stackGoldCards = gm.stackGoldCards,
        stackGoldTokenInCard3 = gm.stackGoldTokenInCard3,
    }
    return true
end

--- Corner-drag: card widths only; layout mode, anchors, and heights stay frozen until commit.
local function ApplyCharactersGoldCardsWidthOnly(bundle, hostW)
    if not bundle or not bundle.char or not bundle.wb or not bundle.total then
        return false
    end
    local gm = bundle._gm
    local layoutState = bundle._layoutState
    if not gm or not layoutState then
        return ApplyCharactersGoldCardsGeometry(bundle, hostW)
    end
    local leftMargin = bundle.leftMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local rightMargin = bundle.rightMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local cardSpacing = bundle.cardSpacing or gm.cardSpacing or (ns.UI_LAYOUT and ns.UI_LAYOUT.CARD_GAP) or 10
    local innerGoldW = math.max(1, hostW - leftMargin - rightMargin)
    if layoutState.stackGoldCards then
        bundle.char:SetWidth(innerGoldW)
        bundle.wb:SetWidth(innerGoldW)
        bundle.total:SetWidth(innerGoldW)
    else
        local totalSpacing = cardSpacing * 2
        local w1 = math.floor((innerGoldW - totalSpacing) / 3)
        local w2 = w1
        local w3 = innerGoldW - totalSpacing - w1 - w2
        bundle.char:SetWidth(w1)
        bundle.wb:SetWidth(w2)
        bundle.total:SetWidth(w3)
        if bundle._layoutState.stackGoldTokenInCard3 ~= nil then
            ApplyTotalGoldCardInterior(bundle, bundle._layoutState.stackGoldTokenInCard3)
        end
    end
    return true
end

--- True when commit would change gold stack mode or card heights (section yOffset chain must rebuild).
local function CharactersGoldLayoutNeedsFullRedraw(bundle, hostW)
    if not bundle or hostW < 1 then return false end
    local leftMargin = bundle.leftMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local rightMargin = bundle.rightMargin or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local cardSpacing = bundle.cardSpacing or (ns.UI_LAYOUT and ns.UI_LAYOUT.CARD_GAP) or 10
    local gm = ComputeCharactersGoldCardMetrics(hostW, leftMargin, rightMargin, cardSpacing, bundle._layoutState)
    local prevState = bundle._layoutState
    local prevGm = bundle._gm
    if prevState then
        if gm.stackGoldCards ~= prevState.stackGoldCards then return true end
        if gm.stackGoldTokenInCard3 ~= prevState.stackGoldTokenInCard3 then return true end
    end
    if prevGm then
        if gm.card3H ~= prevGm.card3H or gm.card12H ~= prevGm.card12H then return true end
    end
    return false
end

--- Live resize: three gold cards track viewport width (scrollChild width stays frozen mid-drag).
local function RelayoutCharactersGoldCards(scrollChild, contentWidth, mf)
    if not scrollChild then return false end
    local bundle = scrollChild._wnCharsGoldBundle
    if not bundle then return false end
    -- Cards occupy the same [side .. side+rowWidth] band as rows/sections. The geometry carves
    -- left+right margins out of hostW, so add them back onto the row draw width (matches the
    -- initial draw); passing the raw row width leaves the cards inset from the section headers.
    local hostW = 0
    if ns.UI_ResolveCharactersTabRowWidth then
        local addon = ns.WarbandNexus
        local rowScrollW = ns.UI_ResolveCharactersTabRowWidth(mf, scrollChild, nil, addon and addon._charListMaxGuildWidth) or 0
        if rowScrollW > 0 then
            local marginPair = (bundle.leftMargin or 0) + (bundle.rightMargin or 0)
            if marginPair <= 0 then
                marginPair = 2 * ((ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12)
            end
            hostW = rowScrollW + marginPair
        end
    end
    if hostW < 1 then hostW = contentWidth or 0 end
    if hostW < 1 and mf and ns.UI_GetMainTabViewportWidth then
        hostW = ns.UI_GetMainTabViewportWidth(mf)
    elseif hostW < 1 and mf and ns.UI_GetMainScrollContentWidth then
        hostW = ns.UI_GetMainScrollContentWidth(mf)
    end
    if hostW < 1 then return false end
    return ApplyCharactersGoldCardsGeometry(bundle, hostW)
end

ns.CharactersUI.ComputeCharactersGoldCardMetrics = ComputeCharactersGoldCardMetrics
ns.CharactersUI.ApplyTotalGoldCardInterior = ApplyTotalGoldCardInterior
ns.CharactersUI.RelayoutCharactersGoldCards = RelayoutCharactersGoldCards
