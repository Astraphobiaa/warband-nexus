--[[
    Warband Nexus - Mail details popup (Shift+click on Characters mail icon).
    Scrollable inbox snapshot: message cards + full-width item list rows.
    Layout: WN-UI-detail-popups.mdc (content-fit width, scrollbar lane, measure-after-layout).
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateIcon = ns.UI_CreateIcon
local Factory = ns.UI.Factory
local SetTextColorRole = ns.UI_SetTextColorRole
local format = string.format
local floor = math.floor
local max = math.max

local SCROLLBAR_COL_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local SCROLLBAR_LANE = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or 28

local function ScrollContentGap()
    local hints = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints()
    return (hints and hints.scrollGap) or 2
end

-- Bottom-up width: scrollChild = CONTENT_W; popup shell adds pads + scrollbar lane.
local LAYOUT = {
    PAD = 12,
    CONTENT_W = 540,
    CARD_PAD = 14,
    CARD_GAP = 10,
    CARD_HEADER_H = 18,
    SUBTITLE_H = 24,
    SUBTITLE_SCROLL_GAP = 6,
    FOOTER_H = 38,
    FOOTER_GAP = 10,
    SCROLL_TOP_GAP = 6,
    FIELD_ROW_GAP = 4,
    ITEM_GRID_LABEL_GAP = 2,
    ITEM_ICON = 36,
    ITEM_ICON_TEX = 32,
    ROW_ICON = 18,
    ICON_GAP = 6,
    TEXT_GAP = 6,
    ITEM_ROW_GAP = 8,
    ROW_MIN_H = 20,
    ITEM_CARD_PAD = 6,
    ITEM_GRID_COLS = 2,
    ITEM_GRID_GAP = 10,
}

local POPUP_W = LAYOUT.CONTENT_W + (LAYOUT.PAD * 2) + SCROLLBAR_LANE
local POPUP_H = 620

local MAIL_ICON_FROM = "Interface\\Icons\\INV_Letter_15"
local MAIL_ICON_SUBJECT = "Interface\\Icons\\INV_Misc_Note_06"
local MAIL_ICON_GOLD = "Interface\\MoneyFrame\\UI-GoldIcon"
local MAIL_ICON_COD = "Interface\\Icons\\INV_Letter_16"
local MAIL_ICON_ITEMS = "Interface\\Icons\\INV_Misc_Enggizmos_19"

local function L(key, fallback)
    return (ns.L and ns.L[key]) or fallback
end

local function GoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    if ns.UI_GetTooltipTitleColor then
        return ns.UI_GetTooltipTitleColor()
    end
    return 1, 0.82, 0
end

local function CardBackdrop()
    if COLORS and COLORS.bgCard then
        return { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 0.96 }
    end
    if ns.UI_GetNestedCardBackdrop then
        return ns.UI_GetNestedCardBackdrop()
    end
    return { 0.08, 0.08, 0.1, 0.95 }
end

local function ItemCardBorder()
    if ns.UI_GetAccentBorderRGBA then
        return ns.UI_GetAccentBorderRGBA(0.35)
    end
    if COLORS and COLORS.border then
        return { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4 }
    end
    return { 0.25, 0.25, 0.3, 0.45 }
end

local function AcquireContainer(parent, w, h, bordered)
    if not Factory or not Factory.CreateContainer then return nil end
    return Factory:CreateContainer(parent, w, h, bordered == true)
end

local function ApplyRowIcon(host, iconPath, size)
    size = size or LAYOUT.ROW_ICON
    if CreateIcon and iconPath then
        local iconFrame = CreateIcon(host, iconPath, size, false, nil, true)
        if iconFrame then
            iconFrame:SetPoint("LEFT", 0, 0)
            iconFrame:Show()
            return iconFrame
        end
    end
    local tex = host:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetPoint("LEFT", 0, 0)
    tex:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return tex
end

local function QualityRGB(quality)
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r, c.g, c.b
    end
    if ns.UI_GetTooltipBodyColor then
        return ns.UI_GetTooltipBodyColor()
    end
    return 0.85, 0.85, 0.85
end

local function SetRole(fs, role)
    if SetTextColorRole and fs then
        SetTextColorRole(fs, role)
    end
end

local function AddLabelOnlyRow(parent, y, iconPath, labelKey, labelFallback, rowW)
    local row = AcquireContainer(parent, rowW, LAYOUT.ROW_MIN_H, false)
    if not row then return 0 end
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CARD_PAD, y)

    local iconHost = AcquireContainer(row, LAYOUT.ROW_ICON, LAYOUT.ROW_MIN_H, false)
    if iconHost then
        iconHost:SetPoint("LEFT", 0, 0)
        ApplyRowIcon(iconHost, iconPath, LAYOUT.ROW_ICON)
    end

    local textLeft = LAYOUT.ROW_ICON + LAYOUT.ICON_GAP
    local labelFs = FontManager:CreateFontString(row, "body", "OVERLAY")
    labelFs:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, 0)
    labelFs:SetJustifyH("LEFT")
    labelFs:SetWordWrap(false)
    local gr, gg, gb = GoldRGB()
    labelFs:SetTextColor(gr, gg, gb, 1)
    labelFs:SetText((L(labelKey, labelFallback) or labelFallback) .. ":")

    local usedH = max(LAYOUT.ROW_MIN_H, (labelFs.GetStringHeight and labelFs:GetStringHeight()) or LAYOUT.ROW_MIN_H)
    row:SetHeight(usedH)
    return usedH + LAYOUT.FIELD_ROW_GAP
end

local function AddFieldRow(parent, y, iconPath, labelKey, labelFallback, value, rowW, valueMaxLines)
    if not value or value == "" then return 0 end
    valueMaxLines = valueMaxLines or 2
    local row = AcquireContainer(parent, rowW, LAYOUT.ROW_MIN_H, false)
    if not row then return 0 end
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CARD_PAD, y)

    local iconHost = AcquireContainer(row, LAYOUT.ROW_ICON, LAYOUT.ROW_MIN_H, false)
    if iconHost then
        iconHost:SetPoint("LEFT", 0, 0)
        ApplyRowIcon(iconHost, iconPath, LAYOUT.ROW_ICON)
    end

    local textLeft = LAYOUT.ROW_ICON + LAYOUT.ICON_GAP
    local labelFs = FontManager:CreateFontString(row, "body", "OVERLAY")
    labelFs:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, 0)
    labelFs:SetJustifyH("LEFT")
    labelFs:SetWordWrap(false)
    local gr, gg, gb = GoldRGB()
    labelFs:SetTextColor(gr, gg, gb, 1)
    labelFs:SetText((L(labelKey, labelFallback) or labelFallback) .. ":")

    local valueFs = FontManager:CreateFontString(row, "body", "OVERLAY")
    valueFs:SetPoint("TOPLEFT", labelFs, "TOPRIGHT", LAYOUT.TEXT_GAP, 0)
    valueFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    valueFs:SetJustifyH("LEFT")
    valueFs:SetWordWrap(true)
    valueFs:SetMaxLines(valueMaxLines)
    SetRole(valueFs, "Bright")
    valueFs:SetText(value)

    local labelH = (labelFs.GetStringHeight and labelFs:GetStringHeight()) or LAYOUT.ROW_MIN_H
    local valueH = (valueFs.GetStringHeight and valueFs:GetStringHeight()) or LAYOUT.ROW_MIN_H
    local usedH = max(LAYOUT.ROW_MIN_H, labelH, valueH)
    row:SetHeight(usedH)
    return usedH + LAYOUT.FIELD_ROW_GAP
end

local function FormatItemMeta(item)
    local parts = {}
    if item.ilvl and item.ilvl > 0 then
        parts[#parts + 1] = format("%s %d", L("MAIL_DETAILS_ILVL", "iLvl"), item.ilvl)
    end
    if item.count and item.count > 1 then
        parts[#parts + 1] = format("x%d", item.count)
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "   ")
end

--- One tooltip payload per item id/link (icon vs name hover must not diverge).
local function ResolveMailItemTooltipData(item)
    if ns.MailSnapshot and ns.MailSnapshot.NormalizeMailItem then
        item = ns.MailSnapshot.NormalizeMailItem(item)
    end
    if not item then return nil end

    local link = item.link
    local itemID = item.itemID
    if link and issecretvalue and issecretvalue(link) then
        link = nil
    end

    if not link and itemID and C_Item and C_Item.GetItemLinkByID then
        local ok, resolved = pcall(C_Item.GetItemLinkByID, itemID)
        if ok and type(resolved) == "string" and resolved ~= "" then
            if not (issecretvalue and issecretvalue(resolved)) then
                link = resolved
            end
        end
    end

    if not itemID and link and type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
        local idStr = link:match("item:(%d+)")
        if idStr then
            itemID = tonumber(idStr)
        end
    end

    if not link and not itemID then
        return nil
    end

    return { type = "item", itemID = itemID, itemLink = link, fallbackName = item.name, stableWidth = 350, anchor = "ANCHOR_RIGHT" }
end

local function PrefetchMailSnapshotItems(messages)
    local TooltipService = ns.TooltipService
    if not TooltipService or not TooltipService.PrefetchItemID then return end
    if not messages then return end
    for mi = 1, #messages do
        local items = messages[mi] and messages[mi].items
        if items then
            for ii = 1, #items do
                local it = items[ii]
                if it and it.itemID then
                    TooltipService:PrefetchItemID(it.itemID)
                end
            end
        end
    end
end

local function PaintItemRow(parent, item, y, x, cellW)
    local pad = LAYOUT.ITEM_CARD_PAD
    local iconSz = LAYOUT.ITEM_ICON
    local iconTexSz = LAYOUT.ITEM_ICON_TEX

    local row = AcquireContainer(parent, cellW, iconSz + pad * 2, false)
    if not row then return LAYOUT.ITEM_ROW_GAP end
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y)
    row._wnTooltipData = ResolveMailItemTooltipData(item)

    local iconHost = AcquireContainer(row, iconSz, iconSz, false)
    if iconHost then
        iconHost:SetPoint("TOPLEFT", pad, -pad)
        iconHost:EnableMouse(false)
        if ApplyVisuals and ns.UI_GetIconWellBackdrop and ns.UI_GetIconWellBorder then
            ApplyVisuals(iconHost, ns.UI_GetIconWellBackdrop(), ns.UI_GetIconWellBorder())
        end
        local iconPath = item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        if type(iconPath) == "string" and iconPath ~= "" then
            if CreateIcon then
                local iconFrame = CreateIcon(iconHost, iconPath, iconTexSz, false, nil, true)
                if iconFrame then
                    iconFrame:SetPoint("CENTER")
                    iconFrame:Show()
                end
            else
                local iconTex = iconHost:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(iconTexSz, iconTexSz)
                iconTex:SetPoint("CENTER")
                iconTex:SetTexture(iconPath)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
    end

    local maxTextW = cellW - (pad * 2) - iconSz - LAYOUT.TEXT_GAP
    local name = item.name or L("UNKNOWN", "Unknown")
    local nr, ng, nb = QualityRGB(item.quality)
    local nameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
    nameFs:SetPoint("TOPLEFT", iconHost, "TOPRIGHT", LAYOUT.TEXT_GAP, -1)
    nameFs:SetWidth(max(40, maxTextW))
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    nameFs:SetMaxLines(1)
    nameFs:SetTextColor(nr, ng, nb, 1)
    nameFs:SetText(name)

    local metaText = FormatItemMeta(item)
    local metaFs
    if metaText then
        metaFs = FontManager:CreateFontString(row, "small", "OVERLAY")
        metaFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
        metaFs:SetWidth(max(40, maxTextW))
        metaFs:SetJustifyH("LEFT")
        metaFs:SetWordWrap(false)
        metaFs:SetMaxLines(1)
        SetRole(metaFs, "Muted")
        metaFs:SetText(metaText)
    end

    local nameH = (nameFs.GetStringHeight and nameFs:GetStringHeight()) or 14
    local metaH = metaFs and metaFs.GetStringHeight and metaFs:GetStringHeight() or 0
    local textH = nameH + (metaH > 0 and (metaH + 2) or 0)
    local contentH = max(iconSz + pad * 2, textH + pad * 2)

    row:SetSize(cellW, contentH)

    if ApplyVisuals then
        ApplyVisuals(row, CardBackdrop(), ItemCardBorder())
    elseif ns.UI_ApplyBorderlessSurface then
        ns.UI_ApplyBorderlessSurface(row, CardBackdrop(), { surfaceTier = "card" })
    end

    local tooltipData = row._wnTooltipData
    if tooltipData then
        local tooltipAnchor = AcquireContainer(row, iconSz, iconSz, false)
        if tooltipAnchor then
            tooltipAnchor:SetPoint("TOPLEFT", row, "TOPLEFT", pad, -pad)
            tooltipAnchor:EnableMouse(false)

            local hit = AcquireContainer(row, cellW, contentH, false)
            if hit then
                hit:ClearAllPoints()
                hit:SetAllPoints(row)
                hit:SetFrameLevel((row:GetFrameLevel() or 0) + 20)
                hit:EnableMouse(true)
                hit:SetScript("OnEnter", function()
                    local TooltipService = ns.TooltipService
                    if TooltipService then
                        TooltipService:Show(tooltipAnchor, tooltipData)
                    end
                end)
                hit:SetScript("OnLeave", function()
                    if ns.TooltipService then
                        ns.TooltipService:Hide()
                    end
                end)
            end
        end
    end

    return contentH + LAYOUT.ITEM_ROW_GAP
end

local function PaintItemGrid(listHost, items, innerW)
    local cols = LAYOUT.ITEM_GRID_COLS
    local gap = LAYOUT.ITEM_GRID_GAP
    local cellW = floor((innerW - (gap * (cols - 1))) / cols)
    local listY = 0
    local listH = 0
    local count = #items
    local idx = 1
    while idx <= count do
        local rowH = 0
        for col = 0, cols - 1 do
            local itemIndex = idx + col
            if itemIndex > count then
                break
            end
            local item = items[itemIndex]
            if ns.MailSnapshot and ns.MailSnapshot.NormalizeMailItem then
                item = ns.MailSnapshot.NormalizeMailItem(item)
            end
            local x = col * (cellW + gap)
            local cellH = PaintItemRow(listHost, item, listY, x, cellW)
            if cellH > rowH then
                rowH = cellH
            end
        end
        if rowH < 1 then
            rowH = LAYOUT.ITEM_ROW_GAP
        end
        listY = listY - rowH
        listH = listH + rowH
        idx = idx + cols
    end
    return max(1, listH)
end

local function ResolveMessageSender(msg)
    if ns.MailSnapshot and ns.MailSnapshot.ResolveDisplaySender then
        return ns.MailSnapshot.ResolveDisplaySender(msg)
    end
    return msg.sender or L("MAIL_TOOLTIP_UNKNOWN_SENDER", "Unknown")
end

local function BuildMessageCard(scrollChild, msg, mailIndex, cardW, yTop, scannedAt)
    local card = AcquireContainer(scrollChild, cardW, 1, false)
    if not card then return LAYOUT.CARD_GAP end
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yTop)
    if ns.UI_ApplyBorderlessSurface then
        ns.UI_ApplyBorderlessSurface(card, CardBackdrop(), { surfaceTier = "card" })
    elseif ApplyVisuals then
        ApplyVisuals(card, CardBackdrop(), { 0, 0, 0, 0 })
        if ns.UI_HideFrameBorderQuartet then
            ns.UI_HideFrameBorderQuartet(card)
        end
    end

    local innerW = cardW - (LAYOUT.CARD_PAD * 2)
    local y = -LAYOUT.CARD_PAD

    local MailSnapshot = ns.MailSnapshot
    local indexText = (MailSnapshot and MailSnapshot.FormatMailIndexLabel and MailSnapshot.FormatMailIndexLabel(mailIndex))
        or format("Mail #%d", mailIndex or 1)
    local indexFs = FontManager:CreateFontString(card, "body", "OVERLAY")
    indexFs:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, y)
    indexFs:SetJustifyH("LEFT")
    SetRole(indexFs, "Bright")
    indexFs:SetText(indexText)

    local expiresAt = MailSnapshot and MailSnapshot.ResolveMessageExpiresAt
        and MailSnapshot.ResolveMessageExpiresAt(msg, scannedAt)
    local timeText = MailSnapshot and MailSnapshot.FormatMailTimeRemaining
        and expiresAt and MailSnapshot.FormatMailTimeRemaining(expiresAt)
    if timeText then
        local timeFs = FontManager:CreateFontString(card, "body", "OVERLAY")
        timeFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -LAYOUT.CARD_PAD, y)
        timeFs:SetJustifyH("RIGHT")
        SetRole(timeFs, "Bright")
        timeFs:SetText(timeText)
    end

    y = y - LAYOUT.CARD_HEADER_H

    local sender = ResolveMessageSender(msg)
    y = y - AddFieldRow(card, y, MAIL_ICON_FROM, "MAIL_TOOLTIP_FROM_LABEL", "From", sender, innerW, 2)

    if msg.subject and msg.subject ~= "" then
        y = y - AddFieldRow(card, y, MAIL_ICON_SUBJECT, "MAIL_TOOLTIP_SUBJECT_LABEL", "Subject", msg.subject, innerW, 3)
    end

    local fmtMoney = ns.UI_FormatMoney
    if msg.money and msg.money > 0 and fmtMoney then
        y = y - AddFieldRow(card, y, MAIL_ICON_GOLD, "MAIL_TOOLTIP_GOLD_LABEL", "Gold",
            fmtMoney(msg.money, 12, true), innerW, 1)
    end
    if msg.cod and msg.cod > 0 and fmtMoney then
        y = y - AddFieldRow(card, y, MAIL_ICON_COD, "MAIL_TOOLTIP_CURRENCY_LABEL", "Currency",
            fmtMoney(msg.cod, 12, true), innerW, 1)
    end

    local items = msg.items
    if items and #items > 0 then
        y = y - AddLabelOnlyRow(card, y, MAIL_ICON_ITEMS, "MAIL_TOOLTIP_ITEMS", "Items", innerW)
        y = y - LAYOUT.ITEM_GRID_LABEL_GAP

        local listHost = AcquireContainer(card, innerW, 1, false)
        if listHost then
            listHost:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, y)
            local listH = PaintItemGrid(listHost, items, innerW)
            listHost:SetHeight(listH)
            y = y - listH
        end
    end

    y = y - LAYOUT.CARD_PAD
    local cardH = -y
    card:SetHeight(cardH)
    return cardH + LAYOUT.CARD_GAP
end

local function ResolveScrollChildWidth(contentFrame)
    local cfW = contentFrame and contentFrame:GetWidth()
    if cfW and cfW > 0 then
        return max(LAYOUT.CONTENT_W, floor(cfW - (LAYOUT.PAD * 2) - SCROLLBAR_LANE + 0.5))
    end
    return LAYOUT.CONTENT_W
end

function WarbandNexus:ShowMailDetailsPopup(char)
    if not char then return end
    if not Factory or not Factory.CreateContainer or not Factory.CreateScrollFrame then return end

    local MailSnapshot = ns.MailSnapshot
    if not MailSnapshot or not MailSnapshot.CharHasPendingMail(char) then return end

    local existing = _G["WarbandNexus_MailDetailsPopup"]
    if existing and existing.Hide then
        existing:Hide()
    end

    local snap = char.mailSnapshot
    if snap and MailSnapshot.NormalizeMailSnapshot then
        MailSnapshot.NormalizeMailSnapshot(snap)
    end
    local messages = snap and snap.messages
    if not messages or #messages == 0 then return end

    PrefetchMailSnapshotItems(messages)

    local nameRich = (ns.UI_FormatClassColoredName and ns.UI_FormatClassColoredName(char.name, char.classFile))
        or (char.name or L("UNKNOWN", "Unknown"))
    local totalGold = (MailSnapshot.SumMailSnapshotGold and MailSnapshot.SumMailSnapshotGold(messages)) or 0
    local fmtMoney = ns.UI_FormatMoney
    local totalGoldText
    if fmtMoney then
        totalGoldText = format(L("MAIL_DETAILS_TOTAL_GOLD", "Total: %s"), fmtMoney(totalGold, 12, true))
    end

    local dialog, contentFrame = CreateExternalWindow({
        name = "MailDetailsPopup",
        title = L("MAIL_DETAILS_TITLE", "Mail Details"),
        icon = "Interface\\Minimap\\Tracking\\Mailbox",
        width = POPUP_W,
        height = POPUP_H,
        preventDuplicates = false,
    })
    if not dialog or not contentFrame then return end

    local subtitleLeft = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    subtitleLeft:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", LAYOUT.PAD, -LAYOUT.SCROLL_TOP_GAP)
    subtitleLeft:SetHeight(LAYOUT.SUBTITLE_H)
    subtitleLeft:SetJustifyH("LEFT")
    subtitleLeft:SetJustifyV("MIDDLE")
    subtitleLeft:SetText(nameRich)

    if totalGoldText then
        local subtitleRight = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        subtitleRight:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -(LAYOUT.PAD + SCROLLBAR_LANE), -LAYOUT.SCROLL_TOP_GAP)
        subtitleRight:SetPoint("TOPLEFT", subtitleLeft, "TOPRIGHT", LAYOUT.TEXT_GAP, 0)
        subtitleRight:SetHeight(LAYOUT.SUBTITLE_H)
        subtitleRight:SetJustifyH("RIGHT")
        subtitleRight:SetJustifyV("MIDDLE")
        local gr, gg, gb = GoldRGB()
        subtitleRight:SetTextColor(gr, gg, gb, 1)
        subtitleRight:SetText(totalGoldText)
    else
        subtitleLeft:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -(LAYOUT.PAD + SCROLLBAR_LANE), -LAYOUT.SCROLL_TOP_GAP)
    end

    local scrollTop = LAYOUT.SUBTITLE_H + LAYOUT.SCROLL_TOP_GAP + LAYOUT.SUBTITLE_SCROLL_GAP
    local scrollGap = ScrollContentGap()

    local footerReserved = 0
    local footerFs
    local footerParts = {}
    if snap.count and snap.count > #messages then
        footerParts[#footerParts + 1] = format(
            L("MAIL_TOOLTIP_MORE", "... and %d more message(s)."),
            snap.count - #messages)
    end
    if snap.scannedAt and snap.scannedAt > 0 then
        footerParts[#footerParts + 1] = L("MAIL_TOOLTIP_SCANNED", "Snapshot from the last time this character was played.")
    end
    if #footerParts > 0 then
        footerReserved = LAYOUT.FOOTER_H + LAYOUT.FOOTER_GAP
        footerFs = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        footerFs:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", LAYOUT.PAD, LAYOUT.FOOTER_GAP)
        footerFs:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -(LAYOUT.PAD + SCROLLBAR_LANE), LAYOUT.FOOTER_GAP)
        footerFs:SetHeight(LAYOUT.FOOTER_H)
        footerFs:SetJustifyH("CENTER")
        footerFs:SetJustifyV("MIDDLE")
        SetRole(footerFs, "Dim")
        footerFs:SetWordWrap(true)
        footerFs:SetMaxLines(3)
        footerFs:SetText(table.concat(footerParts, "\n"))
    end

    local scrollBottom = footerReserved > 0 and footerReserved or LAYOUT.PAD

    local scrollBarColumn = Factory:CreateScrollBarColumn(contentFrame, SCROLLBAR_COL_W, scrollTop, scrollBottom)
    local scroll = Factory:CreateScrollFrame(contentFrame, "UIPanelScrollFrameTemplate", true)
    if not scroll or not scrollBarColumn then return end

    scroll:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", LAYOUT.PAD, -scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", scrollBarColumn, "BOTTOMLEFT", -scrollGap, 0)
    if scroll.SetClipsChildren then
        scroll:SetClipsChildren(true)
    end
    if ns.UI_EnableStandardScrollWheel then
        ns.UI_EnableStandardScrollWheel(scroll)
    end
    if scroll.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
    end

    local cardW = ResolveScrollChildWidth(contentFrame)
    local scrollChild = AcquireContainer(scroll, cardW, 1, false)
    if not scrollChild then return end
    scrollChild:SetWidth(cardW)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    if scrollChild.EnableMouseWheel then
        scrollChild:EnableMouseWheel(true)
    end

    local y = 0
    local scannedAt = snap and snap.scannedAt
    for mi = 1, #messages do
        local cardH = BuildMessageCard(scrollChild, messages[mi], mi, cardW, y, scannedAt)
        y = y - cardH
    end
    scrollChild:SetHeight(max(1, -y))

    if Factory.UpdateScrollBarVisibility then
        Factory:UpdateScrollBarVisibility(scroll)
    end

    dialog:Show()
end

ns.UI_ShowMailDetailsPopup = function(char)
    if WarbandNexus and WarbandNexus.ShowMailDetailsPopup then
        WarbandNexus:ShowMailDetailsPopup(char)
    end
end
