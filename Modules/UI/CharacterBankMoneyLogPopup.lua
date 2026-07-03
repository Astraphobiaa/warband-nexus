--[[
    Warband Nexus - Character Bank Money Logs Popup
    Tabbed view: All / Deposit / Withdraw (transaction log) + Contributions (per-character summary).

    WN_FACTORY: Tabs, scroll hosts, rows, footers prefer `Factory` methods; scroll uses
    CreateScrollBarColumn + PositionScrollBarInContainer + UpdateScrollBarVisibility (MailDetails pattern).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow
local Factory = ns.UI.Factory

local issecretvalue = issecretvalue

local function ControlChromeBg()
    if ns.UI_GetControlChromeBackdrop then
        return ns.UI_GetControlChromeBackdrop()
    end
    return COLORS and COLORS.bgCard or { 0.12, 0.12, 0.15, 1 }
end

local function ControlChromeHoverBg()
    if ns.UI_GetControlChromeHoverBackdrop then
        return ns.UI_GetControlChromeHoverBackdrop()
    end
    return COLORS and COLORS.surfaceRowEven or { 0.18, 0.18, 0.22, 1 }
end

local function HeaderRowBg()
    local c = COLORS
    return c and (c.surfaceHeaderChrome or c.bgCard) or { 0.08, 0.08, 0.10, 1 }
end

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    return 1, 0.9, 0.2, 1
end

local function SemanticGreenRGB()
    if ns.UI_GetSemanticGreenColor then
        return ns.UI_GetSemanticGreenColor()
    end
    return 0.35, 0.9, 0.45, 1
end

local function SemanticOrangeRGB()
    if ns.UI_GetSemanticOrangeColor then
        return ns.UI_GetSemanticOrangeColor()
    end
    return 1, 0.65, 0.25, 1
end

local function SemanticRedRGB()
    if ns.UI_GetSemanticRedColor then
        return ns.UI_GetSemanticRedColor()
    end
    return 1, 0.15, 0.15, 1
end

local ROW_INDENT = 10
local SCROLLBAR_COL_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local SCROLLBAR_LANE = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or 28
local SCROLL_GAP = 2
local PADDING = 12

-- Contributions: Character + Deposit(G/S/C) + Withdraw(G/S/C) + Net(G/S/C) for alignment
local SUM_COL_CHAR = 240
local SUM_COL_G = 100   -- Gold (fits "2.000.000" + icon)
local SUM_COL_S = 50   -- Silver
local SUM_COL_C = 50   -- Copper
local SUM_COL_DEPOSIT = SUM_COL_G + SUM_COL_S + SUM_COL_C
local SUM_COL_WITHDRAW = SUM_COL_G + SUM_COL_S + SUM_COL_C
local SUM_COL_NET = SUM_COL_G + SUM_COL_S + SUM_COL_C
local SUM_COL_GAP = 20  -- Space between major columns for readability
local SUM_TOTAL_W = SUM_COL_CHAR + SUM_COL_GAP + SUM_COL_DEPOSIT + SUM_COL_GAP + SUM_COL_WITHDRAW + SUM_COL_GAP + SUM_COL_NET
-- Row indent + column budget (must match header/row lx walk or content bleeds under scrollbar)
local TABLE_CONTENT_W = ROW_INDENT + SUM_TOTAL_W

-- Transaction log (All/Deposit/Withdraw): same width as Contributions, same gaps, Amount as G/S/C
local CONTENT_W = TABLE_CONTENT_W
local LOG_COL_TIME = 90
local LOG_COL_CHAR = SUM_COL_CHAR
local LOG_COL_TYPE = 90
local LOG_COL_TOFROM = 200
local LOG_COL_AMOUNT = SUM_COL_DEPOSIT  -- G/S/C sub-columns
local LOG_COL_GAP = SUM_COL_GAP

local WINDOW_W = math.max(800, TABLE_CONTENT_W + (PADDING * 2) + SCROLLBAR_LANE)
local WINDOW_H = 520
local TAB_BAR_H = 30
local TAB_BTN_H = 26

local function FormatTime(timestamp)
    if not timestamp or timestamp <= 0 then return "-" end
    return date("%d.%m %H:%M", timestamp)
end

local ICON_SZ = 12

-- Coin icon markup: use atlas (renders in FontStrings); fallback to |T texture path
local COIN_ATLAS_GOLD   = "coin-gold"
local COIN_ATLAS_SILVER = "coin-silver"
local COIN_ATLAS_COPPER = "coin-copper"
local COIN_TEXTURE_FMT  = "|TInterface\\MoneyFrame\\UI-%sIcon:" .. ICON_SZ .. ":" .. ICON_SZ .. ":0:0|t"
local function GetCoinMarkup(coinType)
    if CreateAtlasMarkup then
        local atlas = coinType == "gold" and COIN_ATLAS_GOLD or (coinType == "silver" and COIN_ATLAS_SILVER or COIN_ATLAS_COPPER)
        local ok, markup = pcall(CreateAtlasMarkup, atlas, ICON_SZ, ICON_SZ)
        if ok and markup and markup ~= "" then return markup end
    end
    local name = (coinType == "gold" and "Gold") or (coinType == "silver" and "Silver") or "Copper"
    return string.format(COIN_TEXTURE_FMT, name)
end

local function FormatAmount(copper)
    if ns.UI_FormatMoney then
        return ns.UI_FormatMoney(copper or 0, 14)
    end
    if WarbandNexus.API_FormatMoney then
        return WarbandNexus:API_FormatMoney(copper or 0)
    end
    return tostring(copper or 0)
end

--- Return gold, silver, copper as separate formatted strings (with icon) for column alignment
local function FormatMoneyParts(copper)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = math.floor(copper % 100)
    local function sep(n)
        local s = tostring(n)
        local k
        repeat s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1.%2") until k == 0
        return s
    end
    local gIcon, sIcon, cIcon = GetCoinMarkup("gold"), GetCoinMarkup("silver"), GetCoinMarkup("copper")
    local gStr = (gold > 0) and ("|cffffd700" .. sep(gold) .. "|r" .. gIcon) or ""
    local sStr = (silver > 0 or gold > 0) and ("|cffc7c7cf" .. string.format("%02d", silver) .. "|r" .. sIcon) or ""
    local cStr = ("|cffeda55f" .. string.format("%02d", c) .. "|r" .. cIcon)
    return gStr, sStr, cStr
end

--- Same as FormatMoneyParts but for net (signed) values. If plainForNet then no embedded
--- gold/silver/copper colors — row will use SetTextColor green/red for the whole amount.
local function FormatMoneyPartsSigned(copper, plainForNet)
    copper = math.abs(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = math.floor(copper % 100)
    local function sep(n)
        local s = tostring(n)
        local k
        repeat s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1.%2") until k == 0
        return s
    end
    local gIcon, sIcon, cIcon = GetCoinMarkup("gold"), GetCoinMarkup("silver"), GetCoinMarkup("copper")
    local gStr, sStr, cStr
    if plainForNet then
        gStr = (gold > 0) and (sep(gold) .. gIcon) or ""
        sStr = (silver > 0 or gold > 0) and (string.format("%02d", silver) .. sIcon) or ""
        cStr = string.format("%02d", c) .. cIcon
    else
        gStr = (gold > 0) and ("|cffffd700" .. sep(gold) .. "|r" .. gIcon) or ""
        sStr = (silver > 0 or gold > 0) and ("|cffc7c7cf" .. string.format("%02d", silver) .. "|r" .. sIcon) or ""
        cStr = ("|cffeda55f" .. string.format("%02d", c) .. "|r" .. cIcon)
    end
    return gStr, sStr, cStr
end

local function GetToFromText(entryType)
    if entryType == "deposit" then
        return (ns.L and ns.L["MONEY_LOGS_TO_WARBAND_BANK"]) or "Warband Bank"
    end
    return (ns.L and ns.L["MONEY_LOGS_FROM_WARBAND_BANK"]) or "From Warband Bank"
end

local function LookupCharacterRow(storageKey)
    if not storageKey or storageKey == "" then return nil end
    if issecretvalue and issecretvalue(storageKey) then return nil end
    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    if not chars then return nil end
    local charData = chars[storageKey]
    if charData then return charData end
    if type(storageKey) == "string" and storageKey:sub(1, 7) == "Player-" then
        for _, row in pairs(chars) do
            if type(row) == "table" and row.guid == storageKey then
                return row
            end
        end
    end
    local keySafe = type(storageKey) == "string" and not (issecretvalue and issecretvalue(storageKey))
    if keySafe and storageKey:find("-") and ns.Utilities and ns.Utilities.GetCharacterKey then
        local name, realm = storageKey:match("^([^%-]+)%-(.*)$")
        if name and realm then
            local legacy = ns.Utilities:GetCharacterKey(name, realm)
            if legacy and chars[legacy] then
                return chars[legacy]
            end
        end
    end
    return nil
end

local function ResolveMoneyLogCharacterLabel(entry)
    if entry and entry.characterName and entry.characterName ~= "" then
        if not (issecretvalue and issecretvalue(entry.characterName)) then
            return entry.characterName
        end
    end
    local storageKey = entry and entry.character
    if not storageKey or storageKey == "" then return "-" end
    if issecretvalue and issecretvalue(storageKey) then return "-" end
    if type(storageKey) == "string" and storageKey:sub(1, 7) ~= "Player-" then
        local name, realm = storageKey:match("^([^%-]+)%-(.+)$")
        if name and realm and ns.Utilities and ns.Utilities.FormatRealmName then
            return name .. "-" .. ns.Utilities:FormatRealmName(realm)
        end
        return storageKey
    end
    local charData = LookupCharacterRow(storageKey)
    if charData and charData.name and charData.name ~= "" then
        local name = charData.name
        local realm = charData.realm
        if realm and realm ~= "" then
            local pretty = ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(realm) or realm
            return name .. "-" .. pretty
        end
        return name
    end
    return storageKey
end

local function GetClassColorForEntry(entry, charKey)
    local classFile = entry.classFile
    if not classFile then
        local key = entry.character or charKey
        local charData = LookupCharacterRow(key)
        classFile = charData and (charData.classFile or charData.class)
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b, 1
    end
    local c = COLORS and COLORS.textNormal
    if c then return c[1], c[2], c[3], c[4] or 1 end
    return 0.85, 0.85, 0.9, 1
end

function WarbandNexus:ShowCharacterBankMoneyLogPopup()
    local dialog, contentFrame = CreateExternalWindow({
        name = "CharacterBankMoneyLogPopup",
        title = (ns.L and ns.L["MONEY_LOGS_TITLE"]) or "Money Logs",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        width = WINDOW_W,
        height = WINDOW_H,
        preventDuplicates = true,
    })

    if not dialog then return end

    if dialog.SetSize then
        dialog:SetSize(WINDOW_W, WINDOW_H)
    end

    local children = { contentFrame:GetChildren() }
    local bin = ns.UI_RecycleBin
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end

    local charKey = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and WarbandNexus
        and ns.CharacterService:ResolveSubsidiaryCharacterKey(WarbandNexus, nil))
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        or nil
    local headerHeight = 28
    local rowHeight = 26
    local rowSpacing = 2

    dialog._moneyLogTab = dialog._moneyLogTab or "all"

    -- DATA HELPERS
    local function getFilteredEntries(filter)
        if not WarbandNexus.GetCharacterBankMoneyLogs or type(WarbandNexus.GetCharacterBankMoneyLogs) ~= "function" then
            return {}
        end
        local raw = WarbandNexus:GetCharacterBankMoneyLogs() or {}
        if type(raw) ~= "table" then return {} end
        if filter == "all" then return raw end
        local out = {}
        for i = 1, #raw do
            if raw[i] and raw[i].type == filter then
                out[#out + 1] = raw[i]
            end
        end
        return out
    end

    local function getSummary()
        if not WarbandNexus.GetCharacterBankMoneyLogSummary or type(WarbandNexus.GetCharacterBankMoneyLogSummary) ~= "function" then
            return {}
        end
        return WarbandNexus:GetCharacterBankMoneyLogSummary()
    end

    -- TAB BAR
    local TAB_DEFS = {
        { key = "all",           label = (ns.L and ns.L["MONEY_LOGS_FILTER_ALL"]) or "All" },
        { key = "deposit",       label = (ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit" },
        { key = "withdraw",      label = (ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw" },
        { key = "contributions", label = (ns.L and ns.L["MONEY_LOGS_SUMMARY_TITLE"]) or "Contributions" },
    }

    -- Tab bar width matches table header (scrollbar lane sits below, not under tabs).
    local TAB_GAP = 4
    local TAB_COUNT = #TAB_DEFS
    local TAB_BAR_W = TABLE_CONTENT_W
    local TAB_BTN_W = math.max(72, math.floor((TAB_BAR_W - (TAB_GAP * (TAB_COUNT - 1))) / TAB_COUNT))

    local tabBar = Factory and Factory.CreateContainer and Factory:CreateContainer(contentFrame, TAB_BAR_W, TAB_BAR_H, false)
    if not tabBar then
        tabBar = CreateFrame("Frame", nil, contentFrame)
        tabBar:SetSize(TAB_BAR_W, TAB_BAR_H)
    end
    tabBar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -8)
    tabBar:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -(PADDING + SCROLLBAR_LANE), -8)

    local tabButtons = {}
    local function setTabVisuals(btn, selected)
        if not btn then return end
        if btn._wnBlizzardButton then
            if ns.UI_ApplyClassicNavTabActiveState then
                ns.UI_ApplyClassicNavTabActiveState(btn, selected)
            end
            return
        end
        if not ApplyVisuals then return end
        if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(btn) then return end
        if selected then
            ApplyVisuals(btn, ControlChromeHoverBg(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        else
            ApplyVisuals(btn, ControlChromeBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5 })
        end
    end

    for idx = 1, TAB_COUNT do
        local def = TAB_DEFS[idx]
        local btnW = TAB_BTN_W
        if idx == TAB_COUNT then
            btnW = TAB_BAR_W - ((TAB_BTN_W + TAB_GAP) * (TAB_COUNT - 1))
        end
        local btn = Factory and Factory.CreateButton and Factory:CreateButton(tabBar, btnW, TAB_BTN_H)
        if not btn then
            btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
            btn:SetSize(btnW, TAB_BTN_H)
        end
        btn:SetSize(btnW, TAB_BTN_H)
        if idx == 1 then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", tabButtons[idx - 1], "RIGHT", TAB_GAP, 0)
        end
        if Factory and Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
        end
        local lbl = FontManager:CreateFontString(btn, "body", "OVERLAY")
        lbl:SetPoint("LEFT", 4, 0)
        lbl:SetPoint("RIGHT", -4, 0)
        lbl:SetText(def.label)
        ns.UI_SetTextColorRole(lbl, "Bright")
        lbl:SetJustifyH("CENTER")
        lbl:SetWordWrap(false)
        if lbl.SetNonSpaceWrap then lbl:SetNonSpaceWrap(false) end
        tabButtons[idx] = btn
    end

    local function AcquireStretchPanel(parent)
        if Factory and Factory.CreateContainer then
            local p = Factory:CreateContainer(parent, 1, 1, false)
            if p then return p end
        end
        return CreateFrame("Frame", nil, parent)
    end

    local function AcquireScrollChildHost(scroll)
        if Factory and Factory.CreateContainer then
            local c = Factory:CreateContainer(scroll, 1, 1, false)
            if c then return c end
        end
        local f = CreateFrame("Frame", nil, scroll)
        f:SetSize(1, 1)
        return f
    end

    local LOG_FOOTER_H = 36
    local SCROLL_HEADER_GAP = 4

    -- Shared bar column: tab row through active panel bottom (Collections list-column pattern).
    local scrollBarColumn = Factory and Factory.CreateContainer and Factory:CreateContainer(contentFrame, SCROLLBAR_COL_W, 1, false)
    if scrollBarColumn then
        scrollBarColumn:SetFrameLevel((contentFrame:GetFrameLevel() or 0) + 8)
    end

    local function PositionMoneyLogScrollBar(bottomFrame)
        if not scrollBarColumn or not bottomFrame then return end
        scrollBarColumn:ClearAllPoints()
        scrollBarColumn:SetPoint("TOPRIGHT", tabBar, "TOPRIGHT", SCROLLBAR_LANE, 0)
        scrollBarColumn:SetPoint("BOTTOMRIGHT", bottomFrame, "BOTTOMRIGHT", SCROLLBAR_LANE, 0)
        scrollBarColumn:SetWidth(SCROLLBAR_COL_W)
        scrollBarColumn:Show()
    end

    local function RefreshMoneyLogScrollChrome(scroll)
        if not scroll then return end
        if scroll.ScrollBar and scrollBarColumn and Factory.PositionScrollBarInContainer then
            Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
        end
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scroll)
        end
    end

    local function SetupFactoryScroll(panel, headerRow, bottomFrame, childW)
        if not Factory or not Factory.CreateScrollFrame or not bottomFrame then
            return nil, nil
        end
        childW = childW or TABLE_CONTENT_W

        local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
        if not scroll then
            return nil, nil
        end

        scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -SCROLL_HEADER_GAP)
        scroll:SetPoint("BOTTOMRIGHT", bottomFrame, "TOPRIGHT", -SCROLL_GAP, 0)
        if scroll.SetClipsChildren then
            scroll:SetClipsChildren(true)
        end
        if ns.UI_EnableStandardScrollWheel then
            ns.UI_EnableStandardScrollWheel(scroll)
        end

        local scrollChild = scroll:GetScrollChild()
        if not scrollChild then
            scrollChild = AcquireScrollChildHost(scroll)
            scroll:SetScrollChild(scrollChild)
        end
        scrollChild:SetWidth(childW)
        if scrollChild.EnableMouseWheel then
            scrollChild:EnableMouseWheel(true)
        end

        return scroll, scrollChild
    end

    local function SetupContribScroll(panel, headerRow, childW)
        if not Factory or not Factory.CreateScrollFrame then
            return nil, nil
        end
        childW = childW or TABLE_CONTENT_W

        local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
        if not scroll then
            return nil, nil
        end

        scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -SCROLL_HEADER_GAP)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(SCROLLBAR_LANE + SCROLL_GAP), 0)
        if scroll.SetClipsChildren then
            scroll:SetClipsChildren(true)
        end
        if ns.UI_EnableStandardScrollWheel then
            ns.UI_EnableStandardScrollWheel(scroll)
        end

        local scrollChild = scroll:GetScrollChild()
        if not scrollChild then
            scrollChild = AcquireScrollChildHost(scroll)
            scroll:SetScrollChild(scrollChild)
        end
        scrollChild:SetWidth(childW)
        if scrollChild.EnableMouseWheel then
            scrollChild:EnableMouseWheel(true)
        end

        return scroll, scrollChild
    end

    local logPanel = AcquireStretchPanel(contentFrame)
    logPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -(8 + TAB_BAR_H + 8))
    logPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local logHeaderRow = ns.UI.Factory:CreateContainer(logPanel, 1, headerHeight, false)
    logHeaderRow:SetPoint("TOPLEFT", logPanel, "TOPLEFT", 0, 0)
    logHeaderRow:SetPoint("TOPRIGHT", logPanel, "TOPRIGHT", -SCROLLBAR_LANE, 0)
    logHeaderRow:SetHeight(headerHeight)
    if ApplyVisuals then
        ApplyVisuals(logHeaderRow, HeaderRowBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
    end

    local logX = ROW_INDENT
    local timeHeader = FontManager:CreateFontString(logHeaderRow, "body", "OVERLAY")
    timeHeader:SetPoint("LEFT", logX, 0)
    timeHeader:SetWidth(LOG_COL_TIME)
    timeHeader:SetJustifyH("CENTER")
    timeHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TIME"]) or "Time")
    timeHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    logX = logX + LOG_COL_TIME + LOG_COL_GAP

    local charHeader = FontManager:CreateFontString(logHeaderRow, "body", "OVERLAY")
    charHeader:SetPoint("LEFT", logX, 0)
    charHeader:SetWidth(LOG_COL_CHAR)
    charHeader:SetJustifyH("LEFT")
    charHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_CHARACTER"]) or "Character")
    charHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    logX = logX + LOG_COL_CHAR + LOG_COL_GAP

    local typeHeader = FontManager:CreateFontString(logHeaderRow, "body", "OVERLAY")
    typeHeader:SetPoint("LEFT", logX, 0)
    typeHeader:SetWidth(LOG_COL_TYPE)
    typeHeader:SetJustifyH("CENTER")
    typeHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TYPE"]) or "Type")
    typeHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    logX = logX + LOG_COL_TYPE + LOG_COL_GAP

    local toFromHeader = FontManager:CreateFontString(logHeaderRow, "body", "OVERLAY")
    toFromHeader:SetPoint("LEFT", logX, 0)
    toFromHeader:SetWidth(LOG_COL_TOFROM)
    toFromHeader:SetJustifyH("CENTER")
    toFromHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TOFROM"]) or "To / From")
    toFromHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    logX = logX + LOG_COL_TOFROM + LOG_COL_GAP

    local amountHeader = FontManager:CreateFontString(logHeaderRow, "body", "OVERLAY")
    amountHeader:SetPoint("LEFT", logX, 0)
    amountHeader:SetWidth(LOG_COL_AMOUNT)
    amountHeader:SetJustifyH("CENTER")
    amountHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_AMOUNT"]) or "Amount")
    amountHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local logFooter = ns.UI.Factory:CreateContainer(logPanel, 1, LOG_FOOTER_H)
    logFooter:SetPoint("BOTTOMLEFT", logPanel, "BOTTOMLEFT", 0, 0)
    logFooter:SetPoint("BOTTOMRIGHT", logPanel, "BOTTOMRIGHT", -SCROLLBAR_LANE, 0)

    local logScroll, logScrollChild = SetupFactoryScroll(logPanel, logHeaderRow, logFooter, TABLE_CONTENT_W)

    local resetBtn = ns.UI.Factory:CreateButton(logFooter, 100, 28)
    resetBtn:SetPoint("RIGHT", logFooter, "RIGHT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(resetBtn, ControlChromeBg(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    if ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(resetBtn)
    end
    local resetLabel = FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText((ns.L and ns.L["MONEY_LOGS_RESET"]) or "Reset")
    ns.UI_SetTextColorRole(resetLabel, "Bright")

    local function populateLogScroll(filter)
        if not logScroll or not logScrollChild then return end
        local kids = { logScrollChild:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #kids do kids[i]:Hide(); if bin then kids[i]:SetParent(bin) else kids[i]:SetParent(nil) end end
        logScrollChild:SetHeight(1)

        local entries = getFilteredEntries(filter)
        if #entries == 0 then
            local emptyText = FontManager:CreateFontString(logScrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
            emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
            ns.UI_SetTextColorRole(emptyText, "Muted")
            logScrollChild:SetHeight(rowHeight + 8)
            RefreshMoneyLogScrollChrome(logScroll)
            return
        end

        local rowY = 0
        for i = #entries, 1, -1 do
            local entry = entries[i]
            local row = ns.UI.Factory:CreateContainer(logScrollChild, TABLE_CONTENT_W, rowHeight)
            row:SetPoint("TOPLEFT", 0, -rowY)
            ns.UI.Factory:ApplyRowBackground(row, (#entries - i + 1))

            local lx = ROW_INDENT
            local timeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            timeText:SetPoint("LEFT", lx, 0)
            timeText:SetText(FormatTime(entry.timestamp))
            local tR, tG, tB, tA = SemanticGoldRGB()
            timeText:SetTextColor(tR, tG, tB, tA)
            lx = lx + LOG_COL_TIME + LOG_COL_GAP

            local charText = FontManager:CreateFontString(row, "body", "OVERLAY")
            charText:SetPoint("LEFT", lx, 0)
            charText:SetWidth(LOG_COL_CHAR - 4)
            charText:SetJustifyH("LEFT")
            charText:SetWordWrap(false)
            charText:SetText(ResolveMoneyLogCharacterLabel(entry))
            charText:SetTextColor(GetClassColorForEntry(entry, charKey))
            lx = lx + LOG_COL_CHAR + LOG_COL_GAP

            local typeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            typeText:SetPoint("LEFT", lx, 0)
            if entry.type == "deposit" then
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
                local gR, gG, gB, gA = SemanticGreenRGB()
                typeText:SetTextColor(gR, gG, gB, gA)
            else
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
                local oR, oG, oB, oA = SemanticOrangeRGB()
                typeText:SetTextColor(oR, oG, oB, oA)
            end
            lx = lx + LOG_COL_TYPE + LOG_COL_GAP

            local toFromText = FontManager:CreateFontString(row, "body", "OVERLAY")
            toFromText:SetPoint("LEFT", lx, 0)
            toFromText:SetWidth(LOG_COL_TOFROM - 4)
            toFromText:SetWordWrap(false)
            toFromText:SetText(GetToFromText(entry.type))
            ns.UI_SetTextColorRole(toFromText, "Normal")
            lx = lx + LOG_COL_TOFROM + LOG_COL_GAP

            -- Amount as G/S/C (same alignment as Contributions)
            local aG, aS, aC = FormatMoneyParts(entry.amount or 0)
            local amountParts = { aG, aS, aC }
            local amountWidths = { SUM_COL_G, SUM_COL_S, SUM_COL_C }
            for j = 1, 3 do
                local t = FontManager:CreateFontString(row, "body", "OVERLAY")
                t:SetPoint("RIGHT", row, "LEFT", lx + amountWidths[j], 0)
                t:SetWidth(amountWidths[j])
                t:SetJustifyH("RIGHT")
                t:SetText(amountParts[j] or "")
                ns.UI_SetTextColorRole(t, "Bright")
                lx = lx + amountWidths[j]
            end

            rowY = rowY + rowHeight + rowSpacing
        end
        logScrollChild:SetHeight(math.max(rowY + 8, 1))
        RefreshMoneyLogScrollChrome(logScroll)
    end

    -- CONTRIBUTIONS PANEL
    local contribPanel = AcquireStretchPanel(contentFrame)
    contribPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -(8 + TAB_BAR_H + 8))
    contribPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local contribHeaderRow = ns.UI.Factory:CreateContainer(contribPanel, 1, headerHeight, false)
    contribHeaderRow:SetPoint("TOPLEFT", contribPanel, "TOPLEFT", 0, 0)
    contribHeaderRow:SetPoint("TOPRIGHT", contribPanel, "TOPRIGHT", -SCROLLBAR_LANE, 0)
    contribHeaderRow:SetHeight(headerHeight)
    if ApplyVisuals then
        ApplyVisuals(contribHeaderRow, HeaderRowBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
    end

    -- Headers: Character (left) | Deposit | Withdraw | Net (centered over their columns)
    local sumCharHdr = FontManager:CreateFontString(contribHeaderRow, "body", "OVERLAY")
    sumCharHdr:SetPoint("LEFT", ROW_INDENT, 0)
    sumCharHdr:SetWidth(SUM_COL_CHAR - ROW_INDENT)
    sumCharHdr:SetJustifyH("LEFT")
    sumCharHdr:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_CHARACTER"]) or "Character")
    sumCharHdr:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local depLeft = ROW_INDENT + SUM_COL_CHAR + SUM_COL_GAP
    local sumDepHdr = FontManager:CreateFontString(contribHeaderRow, "body", "OVERLAY")
    sumDepHdr:SetPoint("LEFT", contribHeaderRow, "LEFT", depLeft, 0)
    sumDepHdr:SetWidth(SUM_COL_DEPOSIT)
    sumDepHdr:SetJustifyH("CENTER")
    sumDepHdr:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
    sumDepHdr:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local withLeft = depLeft + SUM_COL_DEPOSIT + SUM_COL_GAP
    local sumWithHdr = FontManager:CreateFontString(contribHeaderRow, "body", "OVERLAY")
    sumWithHdr:SetPoint("LEFT", contribHeaderRow, "LEFT", withLeft, 0)
    sumWithHdr:SetWidth(SUM_COL_WITHDRAW)
    sumWithHdr:SetJustifyH("CENTER")
    sumWithHdr:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
    sumWithHdr:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local netLeft = withLeft + SUM_COL_WITHDRAW + SUM_COL_GAP
    local sumNetHdr = FontManager:CreateFontString(contribHeaderRow, "body", "OVERLAY")
    sumNetHdr:SetPoint("LEFT", contribHeaderRow, "LEFT", netLeft, 0)
    sumNetHdr:SetWidth(SUM_COL_NET)
    sumNetHdr:SetJustifyH("CENTER")
    sumNetHdr:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_NET"]) or "Net")
    sumNetHdr:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local contribScroll, contribScrollChild = SetupContribScroll(contribPanel, contribHeaderRow, TABLE_CONTENT_W)

    local function populateContribScroll()
        if not contribScroll or not contribScrollChild then return end
        local kids = { contribScrollChild:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #kids do kids[i]:Hide(); if bin then kids[i]:SetParent(bin) else kids[i]:SetParent(nil) end end
        contribScrollChild:SetHeight(1)

        local summaryData = getSummary()
        if #summaryData == 0 then
            local emptyText = FontManager:CreateFontString(contribScrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
            emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
            ns.UI_SetTextColorRole(emptyText, "Muted")
            contribScrollChild:SetHeight(rowHeight + 8)
            RefreshMoneyLogScrollChrome(contribScroll)
            return
        end

        local rowY = 0
        for i = 1, #summaryData do
            local s = summaryData[i]
            local row = ns.UI.Factory:CreateContainer(contribScrollChild, TABLE_CONTENT_W, rowHeight)
            row:SetPoint("TOPLEFT", 0, -rowY)
            ns.UI.Factory:ApplyRowBackground(row, i)

            -- Character: left-aligned
            local ct = FontManager:CreateFontString(row, "body", "OVERLAY")
            ct:SetPoint("LEFT", ROW_INDENT, 0)
            ct:SetWidth(SUM_COL_CHAR - ROW_INDENT)
            ct:SetJustifyH("LEFT")
            ct:SetWordWrap(false)
            ct:SetText(ResolveMoneyLogCharacterLabel({ character = s.charKey, classFile = s.classFile }))
            ct:SetTextColor(GetClassColorForEntry({ classFile = s.classFile }, charKey))

            -- Deposit G/S/C
            local dG, dS, dC = FormatMoneyParts(s.deposit)
            local dr, dg, db, da = SemanticGreenRGB()
            local depColor = { dr, dg, db, da }
            local x = ROW_INDENT + SUM_COL_CHAR + SUM_COL_GAP
            local depParts = { dG, dS, dC }
            local depWidths = { SUM_COL_G, SUM_COL_S, SUM_COL_C }
            for j = 1, 3 do
                local t = FontManager:CreateFontString(row, "body", "OVERLAY")
                t:SetPoint("RIGHT", row, "LEFT", x + depWidths[j], 0)
                t:SetWidth(depWidths[j])
                t:SetJustifyH("RIGHT")
                t:SetText(depParts[j] or "")
                t:SetTextColor(depColor[1], depColor[2], depColor[3], depColor[4])
                x = x + depWidths[j]
            end
            x = x + SUM_COL_GAP

            -- Withdraw G/S/C
            local wG, wS, wC = FormatMoneyParts(s.withdraw)
            local wr, wg, wb, wa = SemanticOrangeRGB()
            local withColor = { wr, wg, wb, wa }
            local withParts = { wG, wS, wC }
            local withWidths = { SUM_COL_G, SUM_COL_S, SUM_COL_C }
            for j = 1, 3 do
                local t = FontManager:CreateFontString(row, "body", "OVERLAY")
                t:SetPoint("RIGHT", row, "LEFT", x + withWidths[j], 0)
                t:SetWidth(withWidths[j])
                t:SetJustifyH("RIGHT")
                t:SetText(withParts[j] or "")
                t:SetTextColor(withColor[1], withColor[2], withColor[3], withColor[4])
                x = x + withWidths[j]
            end
            x = x + SUM_COL_GAP

            -- Net G/S/C: green if positive, red if negative (plain text so SetTextColor applies)
            local netVal = s.net or 0
            -- Full green / full red, no in-between shades
            local nr, ng, nb, na
            if netVal >= 0 then
                nr, ng, nb, na = SemanticGreenRGB()
            else
                nr, ng, nb, na = SemanticRedRGB()
            end
            local netColor = { nr, ng, nb, na }
            local nG, nS, nC = FormatMoneyPartsSigned(netVal, true)
            local netParts = { nG, nS, nC }
            local netWidths = { SUM_COL_G, SUM_COL_S, SUM_COL_C }
            for j = 1, 3 do
                local t = FontManager:CreateFontString(row, "body", "OVERLAY")
                t:SetPoint("RIGHT", row, "LEFT", x + netWidths[j], 0)
                t:SetWidth(netWidths[j])
                t:SetJustifyH("RIGHT")
                t:SetText(netParts[j] or "")
                t:SetTextColor(netColor[1], netColor[2], netColor[3], netColor[4])
                x = x + netWidths[j]
            end

            rowY = rowY + rowHeight + rowSpacing
        end
        contribScrollChild:SetHeight(math.max(rowY + 8, 1))
        RefreshMoneyLogScrollChrome(contribScroll)
    end

    -- TAB SWITCHING
    local function switchTab(tabKey)
        dialog._moneyLogTab = tabKey
        for idx = 1, #TAB_DEFS do
            setTabVisuals(tabButtons[idx], TAB_DEFS[idx].key == tabKey)
        end
        if tabKey == "contributions" then
            logPanel:Hide()
            contribPanel:Show()
            PositionMoneyLogScrollBar(contribPanel)
            populateContribScroll()
            RefreshMoneyLogScrollChrome(contribScroll)
        else
            contribPanel:Hide()
            logPanel:Show()
            PositionMoneyLogScrollBar(logFooter)
            populateLogScroll(tabKey)
            RefreshMoneyLogScrollChrome(logScroll)
        end
    end

    for idx = 1, #TAB_DEFS do
        local def = TAB_DEFS[idx]
        tabButtons[idx]:SetScript("OnClick", function()
            switchTab(def.key)
        end)
    end

    resetBtn:SetScript("OnClick", function()
        if not WarbandNexus.ClearCharacterBankMoneyLogs then return end
        resetBtn:Disable()
        WarbandNexus:ClearCharacterBankMoneyLogs(nil)
        C_Timer.After(0.25, function()
            if resetBtn and resetBtn.Enable then resetBtn:Enable() end
        end)
    end)

    local function refreshCurrentTab()
        switchTab(dialog._moneyLogTab or "all")
        C_Timer.After(0, function()
            if not dialog or not dialog.IsShown or not dialog:IsShown() then return end
            local isContrib = dialog._moneyLogTab == "contributions"
            PositionMoneyLogScrollBar(isContrib and contribPanel or logFooter)
            RefreshMoneyLogScrollChrome(isContrib and contribScroll or logScroll)
        end)
    end

    dialog:SetScript("OnShow", refreshCurrentTab)

    WarbandNexus.UnregisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED)
    WarbandNexus.RegisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED, function()
        if dialog:IsShown() then
            refreshCurrentTab()
        end
    end)
    local oldOnHide = dialog:GetScript("OnHide")
    dialog:SetScript("OnHide", function()
        if oldOnHide then oldOnHide() end
        WarbandNexus.UnregisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED)
    end)

    switchTab(dialog._moneyLogTab or "all")
    dialog:Show()
end

ns.CharacterBankMoneyLogPopup = ns.CharacterBankMoneyLogPopup or {}
function ns.CharacterBankMoneyLogPopup.RefreshTheme()
    local d = _G.WarbandNexus_CharacterBankMoneyLogPopup
    if d and d:IsShown() and ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(d)
    end
end

-- (Popup opens through WarbandNexus:ShowCharacterBankMoneyLogPopup — see ItemsUI.)
