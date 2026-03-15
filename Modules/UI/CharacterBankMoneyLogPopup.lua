--[[
    Warband Nexus - Character Bank Money Logs Popup
    Tabbed view: All / Deposit / Withdraw (transaction log) + Contributions (per-character summary).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow

local ROW_INDENT = 10
local SCROLL_BAR_W = 24
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

-- Transaction log (All/Deposit/Withdraw): same width as Contributions, same gaps, Amount as G/S/C
local CONTENT_W = SUM_TOTAL_W
local LOG_COL_TIME = 90
local LOG_COL_CHAR = SUM_COL_CHAR
local LOG_COL_TYPE = 90
local LOG_COL_TOFROM = 200
local LOG_COL_AMOUNT = SUM_COL_DEPOSIT  -- G/S/C sub-columns
local LOG_COL_GAP = SUM_COL_GAP

local WINDOW_W = math.max(800, SUM_TOTAL_W + (PADDING * 2) + SCROLL_BAR_W)
local WINDOW_H = 520

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

local function GetClassColorForEntry(entry, charKey)
    local classFile = entry.classFile
    if not classFile and ns.Utilities and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
        local key = entry.character or charKey
        if key then
            local charData = WarbandNexus.db.global.characters[key]
            if not charData and key:find("-") then
                local name, realm = key:match("^([^-]+)-(.*)$")
                if name and realm then
                    key = ns.Utilities:GetCharacterKey(name, realm)
                    charData = WarbandNexus.db.global.characters[key]
                end
            end
            classFile = charData and (charData.classFile or charData.class)
        end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b, 1
    end
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

    local children = { contentFrame:GetChildren() }
    for i = 1, #children do
        children[i]:SetParent(nil)
        children[i]:Hide()
    end

    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or nil
    local headerHeight = 28
    local rowHeight = 26
    local rowSpacing = 2

    dialog._moneyLogTab = dialog._moneyLogTab or "all"

    --=========================================================================
    -- DATA HELPERS
    --=========================================================================
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

    --=========================================================================
    -- TAB BAR
    --=========================================================================
    local TAB_DEFS = {
        { key = "all",           label = (ns.L and ns.L["MONEY_LOGS_FILTER_ALL"]) or "All" },
        { key = "deposit",       label = (ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit" },
        { key = "withdraw",      label = (ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw" },
        { key = "contributions", label = (ns.L and ns.L["MONEY_LOGS_SUMMARY_TITLE"]) or "Contributions" },
    }

    local tabBar = ns.UI.Factory:CreateContainer(contentFrame, math.max(CONTENT_W, SUM_TOTAL_W), 30)
    tabBar:SetPoint("TOPLEFT", PADDING, -8)
    tabBar:SetPoint("TOPRIGHT", -PADDING, -8)

    local tabButtons = {}
    local function setTabVisuals(btn, selected)
        if not ApplyVisuals then return end
        if selected then
            ApplyVisuals(btn, {0.14, 0.12, 0.08, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7})
        else
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5})
        end
    end

    local TAB_GAP = 4
    local tabBarW = math.max(CONTENT_W, SUM_TOTAL_W)
    local tabBtnW = math.max(100, math.floor((tabBarW - (TAB_GAP * (#TAB_DEFS - 1))) / #TAB_DEFS))
    for idx = 1, #TAB_DEFS do
        local def = TAB_DEFS[idx]
        local btn = ns.UI.Factory:CreateButton(tabBar, tabBtnW, 26)
        if idx == 1 then
            btn:SetPoint("LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", tabButtons[idx - 1], "RIGHT", TAB_GAP, 0)
        end
        if ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        local lbl = FontManager:CreateFontString(btn, "body", "OVERLAY")
        lbl:SetPoint("CENTER")
        lbl:SetText(def.label)
        lbl:SetTextColor(1, 1, 1, 1)
        lbl:SetJustifyH("CENTER")
        lbl:SetWordWrap(false)
        tabButtons[idx] = btn
    end

    --=========================================================================
    -- TRANSACTION LOG PANEL (All / Deposit / Withdraw)
    --=========================================================================
    local logPanel = CreateFrame("Frame", nil, contentFrame)
    logPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    logPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local logHeaderRow = ns.UI.Factory:CreateContainer(logPanel, CONTENT_W, headerHeight)
    logHeaderRow:SetPoint("TOPLEFT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(logHeaderRow, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
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

    local logScroll = ns.UI.Factory:CreateScrollFrame(logPanel, nil, true)
    logScroll:SetPoint("TOPLEFT", logHeaderRow, "BOTTOMLEFT", 0, -4)
    logScroll:SetPoint("BOTTOMRIGHT", logPanel, "BOTTOMRIGHT", 0, 36)

    local logScrollChild = logScroll:GetScrollChild()
    if not logScrollChild then
        logScrollChild = CreateFrame("Frame", nil, logScroll)
        logScrollChild:SetSize(1, 1)
        logScroll:SetScrollChild(logScrollChild)
    end
    logScrollChild:SetWidth(CONTENT_W)

    local logFooter = ns.UI.Factory:CreateContainer(logPanel, 1, 32)
    logFooter:SetPoint("BOTTOMLEFT", 0, 0)
    logFooter:SetPoint("BOTTOMRIGHT", 0, 0)

    local resetBtn = ns.UI.Factory:CreateButton(logFooter, 100, 28)
    resetBtn:SetPoint("LEFT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(resetBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    if ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(resetBtn)
    end
    local resetLabel = FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText((ns.L and ns.L["MONEY_LOGS_RESET"]) or "Reset")
    resetLabel:SetTextColor(1, 1, 1, 1)

    local function populateLogScroll(filter)
        local kids = { logScrollChild:GetChildren() }
        for i = 1, #kids do kids[i]:SetParent(nil); kids[i]:Hide() end
        logScrollChild:SetHeight(1)

        local entries = getFilteredEntries(filter)
        if #entries == 0 then
            local emptyText = FontManager:CreateFontString(logScrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
            emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
            emptyText:SetTextColor(0.7, 0.7, 0.7, 1)
            logScrollChild:SetHeight(rowHeight + 8)
            return
        end

        local rowY = 0
        for i = #entries, 1, -1 do
            local entry = entries[i]
            local row = ns.UI.Factory:CreateContainer(logScrollChild, CONTENT_W, rowHeight)
            row:SetPoint("TOPLEFT", 0, -rowY)
            ns.UI.Factory:ApplyRowBackground(row, (#entries - i + 1))

            local lx = ROW_INDENT
            local timeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            timeText:SetPoint("LEFT", lx, 0)
            timeText:SetText(FormatTime(entry.timestamp))
            timeText:SetTextColor(1, 0.9, 0.2, 1)
            lx = lx + LOG_COL_TIME + LOG_COL_GAP

            local charText = FontManager:CreateFontString(row, "body", "OVERLAY")
            charText:SetPoint("LEFT", lx, 0)
            charText:SetWidth(LOG_COL_CHAR - 4)
            charText:SetJustifyH("LEFT")
            charText:SetWordWrap(false)
            charText:SetText(entry.character or "-")
            charText:SetTextColor(GetClassColorForEntry(entry, charKey))
            lx = lx + LOG_COL_CHAR + LOG_COL_GAP

            local typeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            typeText:SetPoint("LEFT", lx, 0)
            if entry.type == "deposit" then
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
                typeText:SetTextColor(0.35, 0.9, 0.45, 1)
            else
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
                typeText:SetTextColor(1, 0.65, 0.25, 1)
            end
            lx = lx + LOG_COL_TYPE + LOG_COL_GAP

            local toFromText = FontManager:CreateFontString(row, "body", "OVERLAY")
            toFromText:SetPoint("LEFT", lx, 0)
            toFromText:SetWidth(LOG_COL_TOFROM - 4)
            toFromText:SetWordWrap(false)
            toFromText:SetText(GetToFromText(entry.type))
            toFromText:SetTextColor(0.8, 0.8, 0.85, 1)
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
                t:SetTextColor(1, 1, 1, 1)
                lx = lx + amountWidths[j]
            end

            rowY = rowY + rowHeight + rowSpacing
        end
        logScrollChild:SetHeight(math.max(rowY + 8, 1))
    end

    --=========================================================================
    -- CONTRIBUTIONS PANEL
    --=========================================================================
    local contribPanel = CreateFrame("Frame", nil, contentFrame)
    contribPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    contribPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local contribHeaderRow = ns.UI.Factory:CreateContainer(contribPanel, SUM_TOTAL_W, headerHeight)
    contribHeaderRow:SetPoint("TOPLEFT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(contribHeaderRow, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
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

    local contribScroll = ns.UI.Factory:CreateScrollFrame(contribPanel, nil, true)
    contribScroll:SetPoint("TOPLEFT", contribHeaderRow, "BOTTOMLEFT", 0, -4)
    contribScroll:SetPoint("BOTTOMRIGHT", contribPanel, "BOTTOMRIGHT", 0, 0)

    local contribScrollChild = contribScroll:GetScrollChild()
    if not contribScrollChild then
        contribScrollChild = CreateFrame("Frame", nil, contribScroll)
        contribScrollChild:SetSize(1, 1)
        contribScroll:SetScrollChild(contribScrollChild)
    end
    contribScrollChild:SetWidth(SUM_TOTAL_W)

    local function populateContribScroll()
        local kids = { contribScrollChild:GetChildren() }
        for i = 1, #kids do kids[i]:SetParent(nil); kids[i]:Hide() end
        contribScrollChild:SetHeight(1)

        local summaryData = getSummary()
        if #summaryData == 0 then
            local emptyText = FontManager:CreateFontString(contribScrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
            emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
            emptyText:SetTextColor(0.7, 0.7, 0.7, 1)
            contribScrollChild:SetHeight(rowHeight + 8)
            return
        end

        local rowY = 0
        for i = 1, #summaryData do
            local s = summaryData[i]
            local row = ns.UI.Factory:CreateContainer(contribScrollChild, SUM_TOTAL_W, rowHeight)
            row:SetPoint("TOPLEFT", 0, -rowY)
            ns.UI.Factory:ApplyRowBackground(row, i)

            -- Character: left-aligned
            local ct = FontManager:CreateFontString(row, "body", "OVERLAY")
            ct:SetPoint("LEFT", ROW_INDENT, 0)
            ct:SetWidth(SUM_COL_CHAR - ROW_INDENT)
            ct:SetJustifyH("LEFT")
            ct:SetWordWrap(false)
            ct:SetText(s.charKey or "-")
            ct:SetTextColor(GetClassColorForEntry({ classFile = s.classFile }, charKey))

            -- Deposit G/S/C
            local dG, dS, dC = FormatMoneyParts(s.deposit)
            local depColor = { 0.35, 0.9, 0.45, 1 }
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
            local withColor = { 1, 0.65, 0.25, 1 }
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
            -- Tam yeşil / tam kırmızı, ara ton yok
            local netColor = (netVal >= 0) and { 0.15, 1, 0.15, 1 } or { 1, 0.15, 0.15, 1 }
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
    end

    --=========================================================================
    -- TAB SWITCHING
    --=========================================================================
    local function switchTab(tabKey)
        dialog._moneyLogTab = tabKey
        for idx = 1, #TAB_DEFS do
            setTabVisuals(tabButtons[idx], TAB_DEFS[idx].key == tabKey)
        end
        if tabKey == "contributions" then
            logPanel:Hide()
            contribPanel:Show()
            populateContribScroll()
        else
            contribPanel:Hide()
            logPanel:Show()
            populateLogScroll(tabKey)
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
    end

    dialog:SetScript("OnShow", refreshCurrentTab)

    WarbandNexus.UnregisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED")
    WarbandNexus.RegisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED", refreshCurrentTab)
    local oldOnHide = dialog:GetScript("OnHide")
    dialog:SetScript("OnHide", function()
        if oldOnHide then oldOnHide() end
        WarbandNexus.UnregisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED")
    end)

    switchTab(dialog._moneyLogTab or "all")
    dialog:Show()
end

ns.UI_ShowCharacterBankMoneyLogPopup = function(...)
    WarbandNexus:ShowCharacterBankMoneyLogPopup(...)
end
