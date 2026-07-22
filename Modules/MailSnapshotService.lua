--[[
    Warband Nexus - Mail Snapshot Service
    Captures inbox summary for the logged-in character (sender, subject, gold, items).
    Other characters display the last snapshot from when that alt was played.

    Wiki: GetInboxHeaderInfo / GetInboxItem require a prior CheckInbox (mailbox open).
    HasNewMail and UPDATE_PENDING_MAIL work without opening mail.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants and ns.Constants.EVENTS
local issecretvalue = issecretvalue
local format = string.format
local floor = math.floor
local time = time

local M = {}
ns.MailSnapshot = M

local MailSnapshotEvents = {}

local SCAN_DEBOUNCE_SEC = 0.3
local scanPending = false

local MAIL_PREVIEW_MESSAGES = 3
local MAIL_SENDER_MAX_NORMAL = 32
local MAIL_SENDER_MAX_SHIFT = 72
local MAIL_SUBJECT_MAX_NORMAL = 44
local MAIL_SUBJECT_MAX_SHIFT = 120

local ATTACH_MAX = _G.ATTACHMENTS_MAX_RECEIVE or 12
local ITEM_CLASS_TRADEGOODS = LE_ITEM_CLASS_TRADEGOODS or 7
local ITEM_CLASS_CONSUMABLE = LE_ITEM_CLASS_CONSUMABLE or 0
local MAIL_SNAPSHOT_VERSION = 2
local MAX_PLAUSIBLE_STACK = 5000
local MAIL_ICON_FROM = "Interface\\Icons\\INV_Letter_15"
local MAIL_ICON_SUBJECT = "Interface\\Icons\\INV_Misc_Note_06"
local MAIL_ICON_CONTAINS = "Interface\\Icons\\INV_Misc_Bag_10"
local MAIL_ICON_GOLD = "Interface\\MoneyFrame\\UI-GoldIcon"
local MAIL_ICON_COD = "Interface\\Icons\\INV_Letter_16"
local MAIL_ICON_ITEMS = "Interface\\Icons\\INV_Misc_Enggizmos_19"
local MAIL_TOOLTIP_ICON_SIZE = 14
local MAIL_ITEM_INDENT = "    "

local function SafeMailString(val)
    if val == nil then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    if type(val) == "string" then
        if val == "" then return nil end
        return val
    end
    if type(val) == "number" then
        return tostring(val)
    end
    return nil
end

local function SafeMailNumber(val)
    if val == nil then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    local n = tonumber(val)
    if not n then return nil end
    return n
end

local function ResolveCharactersTableKey(addon)
    local CS = ns.CharacterService
    if CS and CS.ResolveCharactersTableKey and addon then
        local k = CS:ResolveCharactersTableKey(addon)
        if k then return k end
    end
    if ns.Utilities and ns.Utilities.GetCharacterStorageKey and addon then
        return ns.Utilities:GetCharacterStorageKey(addon)
    end
    return nil
end

local function ResolveMessageKey(tableKey)
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(tableKey) or tableKey
    end
    return tableKey
end

local function TruncateMailText(text, maxLen)
    if not text or text == "" then return text end
    if issecretvalue and issecretvalue(text) then return nil end
    if not maxLen or maxLen < 4 or #text <= maxLen then return text end
    return text:sub(1, maxLen - 3) .. "..."
end

local function TooltipGoldColor()
    if ns.UI_GetTooltipTitleColor then
        local r, g, b = ns.UI_GetTooltipTitleColor()
        return { r, g, b }
    end
    if ns.UI_GetSemanticGoldColor then
        local r, g, b = ns.UI_GetSemanticGoldColor()
        return { r, g, b }
    end
    return { 1, 0.82, 0 }
end

local function TooltipBodyColor()
    if ns.UI_GetTooltipBodyColor then
        local r, g, b = ns.UI_GetTooltipBodyColor()
        return { r, g, b }
    end
    return { 0.85, 0.85, 0.85 }
end

local function TooltipDimColor()
    if ns.UI_GetTooltipDescColor then
        local r, g, b = ns.UI_GetTooltipDescColor()
        return { r, g, b }
    end
    return { 0.65, 0.65, 0.65 }
end

local function TooltipBrightColor()
    if ns.UI_GetTextRoleRGB then
        local r, g, b = ns.UI_GetTextRoleRGB("Bright")
        return { r, g, b }
    end
    return { 1, 1, 1 }
end

local function TooltipLabelColor()
    if ns.UI_GetTooltipLabelColor then
        local r, g, b = ns.UI_GetTooltipLabelColor()
        return { r, g, b }
    end
    return TooltipDimColor()
end

local function TooltipInlineIcon(texture)
    if not texture or texture == "" then return "" end
    return format("|T%s:%d:%d:0:0|t ", texture, MAIL_TOOLTIP_ICON_SIZE, MAIL_TOOLTIP_ICON_SIZE)
end

local function ClassifyMailItemKind(itemID)
    if not itemID then return "other" end
    if C_Item and C_Item.IsCraftingReagent then
        local ok, isReagent = pcall(C_Item.IsCraftingReagent, itemID)
        if ok and isReagent then return "reagent" end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok then
            if classID == ITEM_CLASS_TRADEGOODS then return "reagent" end
            if classID == ITEM_CLASS_CONSUMABLE then return "consumable" end
        end
    end
    return "other"
end

local function ResolveMailItemIlvl(itemID, link)
    if link and not (issecretvalue and issecretvalue(link)) then
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
            ilvl = SafeMailNumber(ilvl)
            if ok and ilvl and ilvl > 0 then return ilvl end
        end
        if GetDetailedItemLevelInfo then
            local ok, ilvl = pcall(GetDetailedItemLevelInfo, link)
            ilvl = SafeMailNumber(ilvl)
            if ok and ilvl and ilvl > 0 then return ilvl end
        end
    end
    if itemID and C_Item and C_Item.GetCurrentItemLevel then
        local ok, ilvl = pcall(C_Item.GetCurrentItemLevel, itemID)
        ilvl = SafeMailNumber(ilvl)
        if ok and ilvl and ilvl > 0 then return ilvl end
    end
    return nil
end

local function ResolveItemQuality(itemID, link, inboxQuality)
    local q = SafeMailNumber(inboxQuality)
    if q and q >= 0 and q <= 7 then
        return q
    end
    if link and not (issecretvalue and issecretvalue(link)) and GetItemInfo then
        local ok, _, _, quality = pcall(GetItemInfo, link)
        q = SafeMailNumber(quality)
        if ok and q and q >= 0 and q <= 7 then
            return q
        end
    end
    if itemID and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, quality = pcall(C_Item.GetItemInfoInstant, itemID)
        q = SafeMailNumber(quality)
        if ok and q and q >= 0 and q <= 7 then
            return q
        end
    end
    return nil
end

local function NormalizeStackCount(count, itemID)
    count = SafeMailNumber(count)
    if not count or count < 1 then
        return 1
    end
    if itemID and count == itemID then
        return 1
    end
    local maxStack = MAX_PLAUSIBLE_STACK or 5000
    if count > maxStack then
        return 1
    end
    return math.floor(count)
end

local function NormalizeStoredMailItem(it)
    if not it or type(it) ~= "table" then return it end
    if type(it.icon) == "number" then
        it.icon = nil
    end
    if type(it.name) == "number" then
        it.name = nil
    end
    it.count = NormalizeStackCount(it.count, it.itemID)
    it.itemID = SafeMailNumber(it.itemID)
    it.quality = ResolveItemQuality(it.itemID, it.link, it.quality)
    if it.itemID and not it.kind then
        it.kind = ClassifyMailItemKind(it.itemID)
    end
    if it.itemID and not it.ilvl then
        it.ilvl = ResolveMailItemIlvl(it.itemID, it.link)
    end
    return it
end

function M.NormalizeMailItem(it)
    return NormalizeStoredMailItem(it)
end

local function NormalizeStoredMessage(msg)
    if not msg or type(msg) ~= "table" then return msg end
    local items = msg.items
    if not items then return msg end
    local deduped = {}
    local seenLinks = {}
    for i = 1, #items do
        local it = NormalizeStoredMailItem(items[i])
        if it and it.name then
            local linkKey = it.link or (it.itemID and ("id:" .. tostring(it.itemID)) or ("name:" .. it.name))
            if not seenLinks[linkKey] then
                seenLinks[linkKey] = true
                deduped[#deduped + 1] = it
            end
        end
    end
    msg.items = (#deduped > 0) and deduped or nil
    local daysLeft = SafeMailNumber(msg.daysLeft)
    if daysLeft and daysLeft > 0 then
        msg.daysLeft = daysLeft
    else
        msg.daysLeft = nil
    end
    return msg
end

--- Absolute expiry epoch for a stored message (snapshot scan time + fractional daysLeft).
function M.ResolveMessageExpiresAt(msg, scannedAt)
    if not msg or type(msg) ~= "table" then return nil end
    if type(msg.expiresAt) == "number" and msg.expiresAt > 0 then
        return msg.expiresAt
    end
    local daysLeft = SafeMailNumber(msg.daysLeft)
    if daysLeft and daysLeft > 0 and type(scannedAt) == "number" and scannedAt > 0 then
        return scannedAt + (daysLeft * 86400)
    end
    return nil
end

--- Compact mail expiry: largest unit only — `28D`, then `14H`, then `59M` (wiki: daysLeft is fractional days).
function M.FormatMailTimeRemaining(expiresAt)
    if not expiresAt or type(expiresAt) ~= "number" then return nil end
    local sec = expiresAt - time()
    if sec <= 0 then
        return (ns.L and ns.L["MAIL_DETAILS_EXPIRED"]) or "Expired"
    end
    local days = floor(sec / 86400)
    if days >= 1 then
        return format("%dD", days)
    end
    local hours = floor(sec / 3600)
    if hours >= 1 then
        return format("%dH", hours)
    end
    local mins = floor(sec / 60)
    if mins < 1 then
        mins = 1
    end
    return format("%dM", mins)
end

--- Shared mail row chrome: `Mail #1` (popup + Characters mail tooltip).
function M.FormatMailIndexLabel(mailIndex)
    local idx = tonumber(mailIndex) or 1
    local fmt = (ns.L and ns.L["MAIL_INDEX_LABEL"]) or "Mail #%d"
    return format(fmt, idx)
end

function M.NormalizeMailSnapshot(snap)
    if not snap or type(snap) ~= "table" then return snap end
    if snap.version == MAIL_SNAPSHOT_VERSION then
        return snap
    end
    local messages = snap.messages
    if messages then
        for i = 1, #messages do
            NormalizeStoredMessage(messages[i])
        end
    end
    snap.version = MAIL_SNAPSHOT_VERSION
    return snap
end

local function LocaleSender(key, fallback)
    return (ns.L and ns.L[key]) or fallback
end

--- Resolve display sender when GetInboxHeaderInfo returns nil (AH invoice, crafting order, GM, returned).
--- Wiki: GetInboxHeaderInfo sender; GetInboxInvoiceInfo for AH; C_Mail.GetCraftingOrderMailInfo for orders.
local function ResolveMailSender(mailIndex, sender, isGM, wasReturned)
    if sender ~= nil and issecretvalue and issecretvalue(sender) then
        return LocaleSender("MAIL_SENDER_RESTRICTED", "Restricted")
    end

    local safeSender = SafeMailString(sender)
    if safeSender then
        return safeSender
    end

    local gmFlag = SafeMailNumber(isGM)
    if gmFlag and gmFlag > 0 then
        return LocaleSender("MAIL_SENDER_GM", "Game Master")
    end

    if GetInboxInvoiceInfo then
        local okInv, invoiceType, _, playerName = pcall(GetInboxInvoiceInfo, mailIndex)
        if okInv and invoiceType then
            local invoicePlayer = SafeMailString(playerName)
            if invoicePlayer then
                return invoicePlayer
            end
            return LocaleSender("MAIL_SENDER_AUCTION_HOUSE", "Auction House")
        end
    end

    if C_Mail and C_Mail.GetCraftingOrderMailInfo then
        local okCraft, info = pcall(C_Mail.GetCraftingOrderMailInfo, mailIndex)
        if okCraft and type(info) == "table" then
            local crafter = SafeMailString(info.crafterName)
            if crafter then
                return crafter
            end
            local customer = SafeMailString(info.customerName)
            if customer then
                return customer
            end
            return LocaleSender("MAIL_SENDER_CRAFTING_ORDER", "Crafting Order")
        end
    end

    local returnedFlag = SafeMailNumber(wasReturned)
    if returnedFlag and returnedFlag > 0 then
        return LocaleSender("MAIL_SENDER_RETURNED", "Returned Mail")
    end

    return LocaleSender("MAIL_TOOLTIP_UNKNOWN_SENDER", "Unknown")
end

function M.ResolveDisplaySender(msg)
    if not msg then
        return LocaleSender("MAIL_TOOLTIP_UNKNOWN_SENDER", "Unknown")
    end
    local sender = SafeMailString(msg.sender)
    if sender then
        return sender
    end
    return LocaleSender("MAIL_TOOLTIP_UNKNOWN_SENDER", "Unknown")
end

local function ReadInboxItems(mailIndex)
    local items = {}
    if not GetInboxItem then return items end
    local seenLinks = {}
    for j = 1, ATTACH_MAX do
        local link
        if GetInboxItemLink then
            local okLink, rawLink = pcall(GetInboxItemLink, mailIndex, j)
            if okLink then
                link = SafeMailString(rawLink)
            end
        end
        if not link then
            break
        end
        if seenLinks[link] then
            break
        end
        seenLinks[link] = true

        -- Wiki 12.x: name, itemID, texture, count, quality, canUse
        local ok, name, itemID, texture, count, quality = pcall(GetInboxItem, mailIndex, j)
        if ok then
            name = SafeMailString(name)
            if name then
                itemID = SafeMailNumber(itemID)
                count = NormalizeStackCount(count, itemID)
                quality = ResolveItemQuality(itemID, link, quality)
                local icon = SafeMailString(texture)
                if (not icon) and itemID and C_Item and C_Item.GetItemInfoInstant then
                    local okTex, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, itemID)
                    if okTex then
                        icon = SafeMailString(tex)
                    end
                end
                items[#items + 1] = {
                    name = name,
                    itemID = itemID,
                    count = count,
                    icon = icon,
                    quality = quality,
                    link = link,
                    ilvl = ResolveMailItemIlvl(itemID, link),
                    kind = ClassifyMailItemKind(itemID),
                }
            end
        end
    end
    return items
end

local function SumMailGold(messages)
    if not messages then return 0 end
    local total = 0
    for i = 1, #messages do
        local msg = messages[i]
        if msg then
            local money = SafeMailNumber(msg.money) or 0
            if money > 0 then
                total = total + money
            end
        end
    end
    return total
end

function M.SumMailSnapshotGold(messages)
    return SumMailGold(messages)
end

local function BuildMessagesFromInbox(numItems)
    local messages = {}
    if not GetInboxHeaderInfo then
        return messages
    end
    if (not numItems or numItems < 1) and GetInboxNumItems then
        local okNum, n = pcall(GetInboxNumItems)
        if okNum and type(n) == "number" then
            numItems = n
        end
    end
    if not numItems or numItems < 1 then
        return messages
    end
    for i = 1, numItems do
        local okHdr, _, _, sender, subject, money, codAmount, daysLeft, hasItem, _, wasReturned, _, _, isGM =
            pcall(GetInboxHeaderInfo, i)
        if okHdr then
            sender = ResolveMailSender(i, sender, isGM, wasReturned)
            subject = SafeMailString(subject)
            money = SafeMailNumber(money) or 0
            codAmount = SafeMailNumber(codAmount) or 0
            daysLeft = SafeMailNumber(daysLeft)
            local entry = {
                sender = sender,
                subject = subject,
                money = money,
                cod = codAmount,
            }
            if daysLeft and daysLeft > 0 then
                entry.daysLeft = daysLeft
                entry.expiresAt = time() + (daysLeft * 86400)
            end
            if hasItem and tonumber(hasItem) and tonumber(hasItem) > 0 then
                entry.items = ReadInboxItems(i)
            end
            messages[#messages + 1] = entry
        end
    end
    return messages
end

function M.CharHasPendingMail(char)
    if not char then return false end
    if char.mailSnapshot then
        M.NormalizeMailSnapshot(char.mailSnapshot)
    end
    if char.hasMail then return true end
    local snap = char.mailSnapshot
    if snap and snap.messages and #snap.messages > 0 then
        return true
    end
    if snap and snap.count and snap.count > 0 then
        return true
    end
    return false
end

local function ResolveHasMailFlag(hasPending, numItems, messages)
    if hasPending or numItems > 0 then
        return true
    end
    if messages and #messages > 0 then
        return true
    end
    return false
end

function M.ApplyMailSnapshotToRow(row, hasPending, numItems, messages)
    if not row then return end
    local hasMail = ResolveHasMailFlag(hasPending, numItems, messages)
    row.hasMail = hasMail
    if not hasMail then
        row.mailSnapshot = nil
        return
    end
    row.mailSnapshot = {
        version = MAIL_SNAPSHOT_VERSION,
        scannedAt = time(),
        count = numItems,
        messages = messages or {},
    }
end

function WarbandNexus:ScanCurrentCharacterMailSnapshot(opts)
    opts = opts or {}
    if not self.db or not self.db.global or not self.db.global.characters then
        return false
    end
    local tableKey = ResolveCharactersTableKey(self)
    if not tableKey then return false end
    local row = self.db.global.characters[tableKey]
    if not row then return false end

    -- GUARD: untracked characters stay Characters-tab only. Never collect or persist the mail
    -- DETAIL snapshot (row.mailSnapshot: sender, subject, gold, per-item links) for a character
    -- the user chose not to track -- consistent with the fully-gated currency, reputation and
    -- PvE collectors. Without this, every untracked mailbox visit wrote full mail detail into
    -- SavedVariables.
    -- NOT gated here on purpose: the lightweight row.hasMail boolean, which is Characters-tab
    -- data (the envelope column in CharactersUI SetupCharacterMailColumn) and is maintained
    -- separately by DataService:UpdateMailStatus.
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end

    local hasPending = (HasNewMail and HasNewMail()) and true or false

    if not opts.forceInbox then
        if hasPending then
            row.hasMail = true
        elseif row.mailSnapshot then
            M.NormalizeMailSnapshot(row.mailSnapshot)
            row.hasMail = ResolveHasMailFlag(false, row.mailSnapshot.count or 0, row.mailSnapshot.messages)
        else
            row.hasMail = false
        end
        local msgKey = ResolveMessageKey(tableKey)
        if self.SendMessage and E and E.CHARACTER_UPDATED then
            self:SendMessage(E.CHARACTER_UPDATED, { charKey = msgKey, dataType = "mail" })
        end
        return true
    end

    local numItems = 0
    local totalItems = 0
    if GetInboxNumItems then
        local ok, n, total = pcall(GetInboxNumItems)
        if ok and type(n) == "number" then
            numItems = n
        end
        if ok and type(total) == "number" and total > 0 then
            totalItems = total
        end
    end
    local inboxCount = (totalItems > numItems) and totalItems or numItems

    local messages = {}
    if numItems > 0 then
        messages = BuildMessagesFromInbox(numItems)
    end

    M.ApplyMailSnapshotToRow(row, hasPending, inboxCount, messages)

    local msgKey = ResolveMessageKey(tableKey)
    if self.SendMessage and E and E.CHARACTER_UPDATED then
        self:SendMessage(E.CHARACTER_UPDATED, { charKey = msgKey, dataType = "mail" })
    end
    return true
end

function M.ScheduleScan(addon, forceInbox)
    if scanPending then return end
    scanPending = true
    C_Timer.After(SCAN_DEBOUNCE_SEC, function()
        scanPending = false
        if addon and addon.ScanCurrentCharacterMailSnapshot then
            addon:ScanCurrentCharacterMailSnapshot({ forceInbox = forceInbox == true })
        end
    end)
end

local function OnMailboxOpened()
    if CheckInbox then
        pcall(CheckInbox)
    end
    M.ScheduleScan(WarbandNexus, true)
end

local function SummarizeMailMessage(msg)
    local summary = {
        itemStacks = 0,
        itemSlots = 0,
        reagents = 0,
        consumables = 0,
        gold = msg.money or 0,
        cod = msg.cod or 0,
    }
    local items = msg.items
    if not items then return summary end
    summary.itemSlots = #items
    for i = 1, #items do
        local it = NormalizeStoredMailItem(items[i])
        local c = it.count or 1
        summary.itemStacks = summary.itemStacks + c
        local kind = it.kind or ClassifyMailItemKind(it.itemID)
        if kind == "reagent" then
            summary.reagents = summary.reagents + c
        elseif kind == "consumable" then
            summary.consumables = summary.consumables + c
        end
    end
    return summary
end

local function BuildItemsOnlySummary(summary, L)
    local parts = {}
    if summary.itemStacks > 0 then
        local fmt = (L and L["MAIL_TOOLTIP_CONTAINS_ITEMS"]) or "%d item(s)"
        parts[#parts + 1] = format(fmt, summary.itemStacks)
    end
    if summary.reagents > 0 then
        parts[#parts + 1] = format((L and L["MAIL_TOOLTIP_CONTAINS_REAGENTS"]) or "%d reagent(s)", summary.reagents)
    end
    if summary.consumables > 0 then
        parts[#parts + 1] = format((L and L["MAIL_TOOLTIP_CONTAINS_CONSUMABLES"]) or "%d consumable(s)", summary.consumables)
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

local function FormatMailItemLine(it, L)
    it = NormalizeStoredMailItem(it) or it
    local name = it.name or ((L and L["UNKNOWN"]) or "Unknown")
    local count = it.count or 1
    local ilvlPart = ""
    if it.ilvl and it.ilvl > 0 then
        ilvlPart = format((L and L["MAIL_TOOLTIP_ITEM_ILVL"]) or " (%d)", it.ilvl)
    end
    local countPart = ""
    if count > 1 then
        countPart = format((L and L["MAIL_TOOLTIP_ITEM_COUNT"]) or " x%d", count)
    end
    local hex = "ffffff"
    if it.quality and ns.UI_GetQualityHex then
        hex = ns.UI_GetQualityHex(it.quality) or hex
    elseif it.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality] then
        local c = ITEM_QUALITY_COLORS[it.quality]
        if c and c.r then
            hex = format("%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
        end
    end
    local iconPart = ""
    if it.icon and type(it.icon) == "string" and it.icon ~= "" then
        iconPart = format("|T%s:14:14:0:0|t ", it.icon)
    end
    return iconPart .. format("|cff%s%s%s%s|r", hex, name, ilvlPart, countPart)
end

local function TooltipColorHex(rgb)
    return format(
        "%02x%02x%02x",
        floor((rgb[1] or 1) * 255 + 0.5),
        floor((rgb[2] or 1) * 255 + 0.5),
        floor((rgb[3] or 1) * 255 + 0.5)
    )
end

local function AppendMailFieldRow(lines, icon, label, value, valueColor, labelGold)
    if not value or value == "" then return end
    local labelRgb = labelGold and TooltipGoldColor() or TooltipLabelColor()
    local valueRgb = (type(valueColor) == "table" and valueColor) or TooltipBrightColor()
    lines[#lines + 1] = {
        left = TooltipInlineIcon(icon)
            .. format("|cff%s%s|r ", TooltipColorHex(labelRgb), label .. ":")
            .. format("|cff%s%s|r", TooltipColorHex(valueRgb), value),
    }
end

local function AppendMailMessageBlock(lines, msg, opts)
    opts = opts or {}
    local L = opts.L
    local senderMax = opts.senderMax or MAIL_SENDER_MAX_NORMAL
    local subjectMax = opts.subjectMax or MAIL_SUBJECT_MAX_NORMAL
    local bodyColor = opts.bodyColor or TooltipBodyColor()
    local goldColor = opts.goldColor or TooltipGoldColor()
    local dimColor = opts.dimColor or TooltipDimColor()
    local mailIndex = opts.mailIndex or 1
    local scannedAt = opts.scannedAt

    if mailIndex > 1 then
        lines[#lines + 1] = { type = "divider" }
    else
        lines[#lines + 1] = { type = "spacer", height = 2 }
    end

    local expiresAt = M.ResolveMessageExpiresAt(msg, scannedAt)
    local timeText = expiresAt and M.FormatMailTimeRemaining(expiresAt)
    local bright = TooltipBrightColor()
    lines[#lines + 1] = {
        left = M.FormatMailIndexLabel(mailIndex),
        right = timeText or " ",
        leftColor = bright,
        rightColor = bright,
    }

    local sender = M.ResolveDisplaySender(msg)
    sender = TruncateMailText(sender, senderMax) or sender
    AppendMailFieldRow(
        lines,
        MAIL_ICON_FROM,
        (L and L["MAIL_TOOLTIP_FROM_LABEL"]) or "From",
        sender,
        TooltipBrightColor(),
        true
    )

    local subject = msg.subject
    if subject and subject ~= "" then
        subject = TruncateMailText(subject, subjectMax) or subject
        AppendMailFieldRow(
            lines,
            MAIL_ICON_SUBJECT,
            (L and L["MAIL_TOOLTIP_SUBJECT_LABEL"]) or "Subject",
            subject,
            TooltipBrightColor(),
            true
        )
    end

    local summary = SummarizeMailMessage(msg)
    local fmtMoney = ns.UI_FormatMoney
    if summary.gold > 0 and fmtMoney then
        AppendMailFieldRow(
            lines,
            MAIL_ICON_GOLD,
            (L and L["MAIL_TOOLTIP_GOLD_LABEL"]) or "Gold",
            fmtMoney(summary.gold, 12, true),
            goldColor,
            true
        )
    end
    if summary.cod > 0 and fmtMoney then
        AppendMailFieldRow(
            lines,
            MAIL_ICON_COD,
            (L and L["MAIL_TOOLTIP_CURRENCY_LABEL"]) or "Currency",
            fmtMoney(summary.cod, 12, true),
            goldColor,
            true
        )
    end
    local itemsText = BuildItemsOnlySummary(summary, L)
    if itemsText then
        AppendMailFieldRow(
            lines,
            MAIL_ICON_ITEMS,
            (L and L["MAIL_TOOLTIP_ITEMS"]) or "Items",
            itemsText,
            TooltipBrightColor(),
            true
        )
    end

    lines[#lines + 1] = { type = "spacer", height = 2 }
end

function M.BuildTooltipLines(char, isCurrent, opts)
    opts = opts or {}
    local L = ns.L
    local lines = {}
    local bodyColor = TooltipBodyColor()
    local dimColor = TooltipDimColor()
    local goldColor = TooltipGoldColor()

    local snap = char and char.mailSnapshot
    if snap then
        M.NormalizeMailSnapshot(snap)
    end
    local messages = snap and snap.messages
    local hasMail = M.CharHasPendingMail(char)

    if not hasMail then
        lines[#lines + 1] = {
            text = (L and L["MAIL_TOOLTIP_NO_MAIL"]) or "No mail waiting.",
            color = dimColor,
        }
        return lines
    end

    if not messages or #messages == 0 then
        lines[#lines + 1] = {
            text = (L and L["MAIL_TOOLTIP_PENDING_ONLY"]) or "Mail waiting. Open the mailbox on this character to refresh details.",
            color = bodyColor,
        }
        if not isCurrent then
            lines[#lines + 1] = {
                text = (L and L["MAIL_TOOLTIP_LOGIN_HINT"]) or "Log in on this character to update the list.",
                color = dimColor,
            }
        end
        return lines
    end

    local senderMax = MAIL_SENDER_MAX_NORMAL
    local subjectMax = MAIL_SUBJECT_MAX_NORMAL
    local showCount = math.min(#messages, MAIL_PREVIEW_MESSAGES)
    local blockOpts = {
        L = L,
        senderMax = senderMax,
        subjectMax = subjectMax,
        bodyColor = bodyColor,
        goldColor = goldColor,
        dimColor = dimColor,
        scannedAt = snap and snap.scannedAt,
    }

    for mi = 1, showCount do
        blockOpts.mailIndex = mi
        AppendMailMessageBlock(lines, messages[mi], blockOpts)
    end

    if #messages > MAIL_PREVIEW_MESSAGES then
        lines[#lines + 1] = {
            text = format((L and L["MAIL_TOOLTIP_MORE"]) or "... and %d more message(s).", #messages - MAIL_PREVIEW_MESSAGES),
            color = dimColor,
        }
    elseif snap and snap.count and snap.count > #messages then
        lines[#lines + 1] = {
            text = format((L and L["MAIL_TOOLTIP_MORE"]) or "... and %d more message(s).", snap.count - #messages),
            color = dimColor,
        }
    end

    lines[#lines + 1] = { type = "divider" }
    lines[#lines + 1] = {
        text = (L and L["MAIL_TOOLTIP_SHIFT_CLICK"]) or "Shift-click for full mail details.",
        color = dimColor,
    }

    if snap and snap.scannedAt and snap.scannedAt > 0 then
        lines[#lines + 1] = { type = "spacer", height = 4 }
        lines[#lines + 1] = {
            text = (L and L["MAIL_TOOLTIP_SCANNED"]) or "Snapshot from the last time this character was played.",
            color = dimColor,
        }
    end

    return lines
end

function WarbandNexus:InitializeMailSnapshotService()
    WarbandNexus.RegisterEvent(MailSnapshotEvents, "MAIL_SHOW", OnMailboxOpened)
    WarbandNexus.RegisterEvent(MailSnapshotEvents, "MAIL_INBOX_UPDATE", function()
        M.ScheduleScan(WarbandNexus, true)
    end)
    WarbandNexus.RegisterEvent(MailSnapshotEvents, "MAIL_CLOSED", function()
        M.ScheduleScan(WarbandNexus, true)
    end)
    WarbandNexus.RegisterEvent(MailSnapshotEvents, "PLAYER_ENTERING_WORLD", function()
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.ScanCurrentCharacterMailSnapshot then
                M.ScheduleScan(WarbandNexus, false)
            end
        end)
    end)
end
