--[[
    Warband Nexus - Character Bank Money Logs Popup
    Displays deposit/withdraw transactions: character, type, to/from, amount.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow

-- Column layout: widths for full character name (no truncation) and long amounts (9.999.999 g 99 s 99 c)
local COL_TIME = 90
local COL_CHARACTER = 280
local COL_TYPE = 82
local COL_TOFROM = 168
local COL_AMOUNT = 220
local ROW_INDENT = 10
local SCROLL_BAR_W = 24
local TOTAL_TABLE_W = COL_TIME + COL_CHARACTER + COL_TYPE + COL_TOFROM + COL_AMOUNT
local WINDOW_W = math.max(700, TOTAL_TABLE_W + (12 * 2) + SCROLL_BAR_W)
local WINDOW_H = 520
local CONTENT_W = TOTAL_TABLE_W

local function FormatTime(timestamp)
    if not timestamp or timestamp <= 0 then
        return "-"
    end
    return date("%d.%m %H:%M", timestamp)
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

local function GetToFromText(entryType)
    if entryType == "deposit" then
        return (ns.L and ns.L["MONEY_LOGS_TO_WARBAND_BANK"]) or "Warband Bank"
    end
    return (ns.L and ns.L["MONEY_LOGS_FROM_WARBAND_BANK"]) or "From Warband Bank"
end

local function GetClassColorForEntry(entry, charKey)
    local classFile = entry.classFile
    if not classFile and ns.Utilities and ns.Utilities.GetCharacterKey and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
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

    if not dialog then
        return
    end

    -- Clear existing content so we always build from scratch (avoids duplicate/stale UI on reuse)
    local children = { contentFrame:GetChildren() }
    for i = 1, #children do
        children[i]:SetParent(nil)
        children[i]:Hide()
    end

    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or nil

    -- Store active filter on dialog so it's the single source of truth (avoids closure/refresh confusion)
    dialog._moneyLogFilter = "all"

    local function getFilteredEntries()
        local filter = (dialog and dialog._moneyLogFilter) or "all"
        -- Account-wide: get full list (all characters' deposit/withdraw history)
        if not WarbandNexus.GetCharacterBankMoneyLogs or type(WarbandNexus.GetCharacterBankMoneyLogs) ~= "function" then
            if WarbandNexus.Print then
                WarbandNexus:Print("|cff00b4ffMoney Log:|r Service not loaded; cannot read entries.")
            end
            return {}
        end
        local raw = WarbandNexus:GetCharacterBankMoneyLogs() or {}
        if type(raw) ~= "table" then
            raw = {}
        end
        local totalCount = #raw
        local out
        if filter == "all" then
            out = raw
        else
            out = {}
            for i = 1, #raw do
                if raw[i] and raw[i].type == filter then
                    out[#out + 1] = raw[i]
                end
            end
        end
        local shownCount = #out
        if WarbandNexus.Print then
            local filterLabel = filter == "all" and "All" or (filter == "deposit" and "Deposit" or "Withdraw")
            WarbandNexus:Print(string.format("|cff00b4ffMoney Log:|r %d entries in storage, showing %d (filter: %s)", totalCount, shownCount, filterLabel))
        end
        return out
    end

    local yOffset = 12
    local PADDING = 12
    local headerHeight = 30
    local rowHeight = 26
    local rowSpacing = 2

    -- Filter: All | Deposit | Withdraw (above column headers)
    local filterBarHeight = 28
    local filterBar = ns.UI.Factory:CreateContainer(contentFrame, CONTENT_W, filterBarHeight)
    filterBar:SetPoint("TOPLEFT", PADDING, -yOffset)

    local filterBtnW = 90
    local allBtn = ns.UI.Factory:CreateButton(filterBar, filterBtnW, 24)
    allBtn:SetPoint("LEFT", 0, 0)
    local depositBtn = ns.UI.Factory:CreateButton(filterBar, filterBtnW, 24)
    depositBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
    local withdrawBtn = ns.UI.Factory:CreateButton(filterBar, filterBtnW, 24)
    withdrawBtn:SetPoint("LEFT", depositBtn, "RIGHT", 4, 0)

    local function setFilterVisuals(btn, selected)
        if ApplyVisuals then
            if selected then
                ApplyVisuals(btn, {0.14, 0.12, 0.08, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7})
            else
                ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5})
            end
        end
    end
    setFilterVisuals(allBtn, true)
    setFilterVisuals(depositBtn, false)
    setFilterVisuals(withdrawBtn, false)

    local allLabel = FontManager:CreateFontString(allBtn, "body", "OVERLAY")
    allLabel:SetPoint("CENTER")
    allLabel:SetText((ns.L and ns.L["MONEY_LOGS_FILTER_ALL"]) or "All")
    allLabel:SetTextColor(1, 1, 1, 1)
    local depositLabel = FontManager:CreateFontString(depositBtn, "body", "OVERLAY")
    depositLabel:SetPoint("CENTER")
    depositLabel:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
    depositLabel:SetTextColor(1, 1, 1, 1)
    local withdrawLabel = FontManager:CreateFontString(withdrawBtn, "body", "OVERLAY")
    withdrawLabel:SetPoint("CENTER")
    withdrawLabel:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
    withdrawLabel:SetTextColor(1, 1, 1, 1)

    yOffset = yOffset + filterBarHeight + 6

    local headerRow = ns.UI.Factory:CreateContainer(contentFrame, CONTENT_W, headerHeight)
    headerRow:SetPoint("TOPLEFT", PADDING, -yOffset)

    if ApplyVisuals then
        ApplyVisuals(headerRow, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
    end

    -- Headers: centered in each column to avoid shifting
    local timeHeader = FontManager:CreateFontString(headerRow, "body", "OVERLAY")
    timeHeader:SetPoint("LEFT", ROW_INDENT, 0)
    timeHeader:SetWidth(COL_TIME)
    timeHeader:SetJustifyH("CENTER")
    timeHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TIME"]) or "Time")
    timeHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local charHeader = FontManager:CreateFontString(headerRow, "body", "OVERLAY")
    charHeader:SetPoint("LEFT", ROW_INDENT + COL_TIME, 0)
    charHeader:SetWidth(COL_CHARACTER)
    charHeader:SetJustifyH("CENTER")
    charHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_CHARACTER"]) or "Character")
    charHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local typeHeader = FontManager:CreateFontString(headerRow, "body", "OVERLAY")
    typeHeader:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER, 0)
    typeHeader:SetWidth(COL_TYPE)
    typeHeader:SetJustifyH("CENTER")
    typeHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TYPE"]) or "Type")
    typeHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local toFromHeader = FontManager:CreateFontString(headerRow, "body", "OVERLAY")
    toFromHeader:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER + COL_TYPE, 0)
    toFromHeader:SetWidth(COL_TOFROM)
    toFromHeader:SetJustifyH("CENTER")
    toFromHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_TOFROM"]) or "To / From")
    toFromHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    local amountHeader = FontManager:CreateFontString(headerRow, "body", "OVERLAY")
    amountHeader:SetPoint("RIGHT", -ROW_INDENT, 0)
    amountHeader:SetWidth(COL_AMOUNT)
    amountHeader:SetJustifyH("RIGHT")
    amountHeader:SetText((ns.L and ns.L["MONEY_LOGS_COLUMN_AMOUNT"]) or "Amount")
    amountHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

    yOffset = yOffset + headerHeight + 6

    local scroll = ns.UI.Factory:CreateScrollFrame(contentFrame, nil, true)
    scroll:SetPoint("TOPLEFT", PADDING, -yOffset)
    scroll:SetPoint("BOTTOMRIGHT", -PADDING, 44)

    local scrollChild = scroll:GetScrollChild()
    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetSize(1, 1)
        scroll:SetScrollChild(scrollChild)
    end
    scrollChild:SetWidth(CONTENT_W)

    local rowY = 0
    local displayedEntries = getFilteredEntries()

    if #displayedEntries == 0 then
        local emptyText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
        emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
        emptyText:SetTextColor(0.7, 0.7, 0.7, 1)
        rowY = rowHeight + 8
    else
        for i = #displayedEntries, 1, -1 do
            local entry = displayedEntries[i]

            local row = ns.UI.Factory:CreateContainer(scrollChild, CONTENT_W, rowHeight)
            row:SetPoint("TOPLEFT", 0, -rowY)
            ns.UI.Factory:ApplyRowBackground(row, i)

            local timeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            timeText:SetPoint("LEFT", ROW_INDENT, 0)
            timeText:SetText(FormatTime(entry.timestamp))
            timeText:SetTextColor(1, 0.9, 0.2, 1)

            local charText = FontManager:CreateFontString(row, "body", "OVERLAY")
            charText:SetPoint("LEFT", ROW_INDENT + COL_TIME, 0)
            charText:SetWidth(COL_CHARACTER - 4)
            charText:SetWordWrap(false)
            charText:SetText(entry.character or "-")
            charText:SetTextColor(GetClassColorForEntry(entry, charKey))

            local typeText = FontManager:CreateFontString(row, "body", "OVERLAY")
            typeText:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER, 0)
            if entry.type == "deposit" then
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
                typeText:SetTextColor(0.35, 0.9, 0.45, 1)
            else
                typeText:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
                typeText:SetTextColor(1, 0.65, 0.25, 1)
            end

            local toFromText = FontManager:CreateFontString(row, "body", "OVERLAY")
            toFromText:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER + COL_TYPE, 0)
            toFromText:SetWidth(COL_TOFROM - 4)
            toFromText:SetWordWrap(false)
            toFromText:SetText(GetToFromText(entry.type))
            toFromText:SetTextColor(0.8, 0.8, 0.85, 1)

            local amountText = FontManager:CreateFontString(row, "body", "OVERLAY")
            amountText:SetPoint("RIGHT", -ROW_INDENT, 0)
            amountText:SetWidth(COL_AMOUNT - 4)
            amountText:SetJustifyH("RIGHT")
            amountText:SetText(FormatAmount(entry.amount))
            amountText:SetTextColor(1, 1, 1, 1)

            rowY = rowY + rowHeight + rowSpacing
        end
    end

    scrollChild:SetHeight(math.max(rowY + 8, 1))

    -- Footer with Reset button
    local footer = ns.UI.Factory:CreateContainer(contentFrame, contentFrame:GetWidth() - (PADDING * 2), 32)
    footer:SetPoint("BOTTOMLEFT", PADDING, 10)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 10)

    local resetBtn = ns.UI.Factory:CreateButton(footer, 100, 28)
    resetBtn:SetPoint("LEFT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(resetBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(resetBtn)
    end
    local resetLabel = FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText((ns.L and ns.L["MONEY_LOGS_RESET"]) or "Reset")
    resetLabel:SetTextColor(1, 1, 1, 1)

    local function refreshList()
        local displayedEntries = getFilteredEntries()
        scrollChild:SetHeight(1)
        local children = { scrollChild:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            child:SetParent(nil)
            child:Hide()
        end
        rowY = 0
        if #displayedEntries == 0 then
            local emptyText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", ROW_INDENT, -10)
            emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
            emptyText:SetTextColor(0.7, 0.7, 0.7, 1)
            rowY = rowHeight + 8
        else
            for i = #displayedEntries, 1, -1 do
                local entry = displayedEntries[i]
                local row = ns.UI.Factory:CreateContainer(scrollChild, CONTENT_W, rowHeight)
                row:SetPoint("TOPLEFT", 0, -rowY)
                ns.UI.Factory:ApplyRowBackground(row, i)
                local timeText = FontManager:CreateFontString(row, "body", "OVERLAY")
                timeText:SetPoint("LEFT", ROW_INDENT, 0)
                timeText:SetText(FormatTime(entry.timestamp))
                timeText:SetTextColor(1, 0.9, 0.2, 1)
                local charText = FontManager:CreateFontString(row, "body", "OVERLAY")
                charText:SetPoint("LEFT", ROW_INDENT + COL_TIME, 0)
                charText:SetWidth(COL_CHARACTER - 4)
                charText:SetWordWrap(false)
                charText:SetText(entry.character or "-")
                charText:SetTextColor(GetClassColorForEntry(entry, charKey))
                local typeText = FontManager:CreateFontString(row, "body", "OVERLAY")
                typeText:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER, 0)
                if entry.type == "deposit" then
                    typeText:SetText((ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit")
                    typeText:SetTextColor(0.35, 0.9, 0.45, 1)
                else
                    typeText:SetText((ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw")
                    typeText:SetTextColor(1, 0.65, 0.25, 1)
                end
                local toFromText = FontManager:CreateFontString(row, "body", "OVERLAY")
                toFromText:SetPoint("LEFT", ROW_INDENT + COL_TIME + COL_CHARACTER + COL_TYPE, 0)
                toFromText:SetWidth(COL_TOFROM - 4)
                toFromText:SetWordWrap(false)
                toFromText:SetText(GetToFromText(entry.type))
                toFromText:SetTextColor(0.8, 0.8, 0.85, 1)
                local amountText = FontManager:CreateFontString(row, "body", "OVERLAY")
                amountText:SetPoint("RIGHT", -ROW_INDENT, 0)
                amountText:SetWidth(COL_AMOUNT - 4)
                amountText:SetJustifyH("RIGHT")
                amountText:SetText(FormatAmount(entry.amount))
                amountText:SetTextColor(1, 1, 1, 1)
                rowY = rowY + rowHeight + rowSpacing
            end
        end
        scrollChild:SetHeight(math.max(rowY + 8, 1))
    end

    resetBtn:SetScript("OnClick", function()
        if not WarbandNexus.ClearCharacterBankMoneyLogs then return end
        resetBtn:Disable()
        WarbandNexus:ClearCharacterBankMoneyLogs(nil)
        -- List refresh is done once by WN_CHARACTER_BANK_MONEY_LOG_UPDATED handler; avoid duplicate refresh here
        C_Timer.After(0.25, function()
            if resetBtn and resetBtn.Enable then resetBtn:Enable() end
        end)
    end)

    allBtn:SetScript("OnClick", function()
        if dialog then dialog._moneyLogFilter = "all" end
        setFilterVisuals(allBtn, true)
        setFilterVisuals(depositBtn, false)
        setFilterVisuals(withdrawBtn, false)
        refreshList()
    end)
    depositBtn:SetScript("OnClick", function()
        if dialog then dialog._moneyLogFilter = "deposit" end
        setFilterVisuals(allBtn, false)
        setFilterVisuals(depositBtn, true)
        setFilterVisuals(withdrawBtn, false)
        refreshList()
    end)
    withdrawBtn:SetScript("OnClick", function()
        if dialog then dialog._moneyLogFilter = "withdraw" end
        setFilterVisuals(allBtn, false)
        setFilterVisuals(depositBtn, false)
        setFilterVisuals(withdrawBtn, true)
        refreshList()
    end)

    dialog:SetScript("OnShow", function()
        refreshList()
    end)

    -- Refresh list when a new log entry is added while window is open (unregister first so reopening does not stack handlers)
    WarbandNexus.UnregisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED")
    WarbandNexus.RegisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED", function()
        refreshList()
    end)
    local oldOnHide = dialog:GetScript("OnHide")
    dialog:SetScript("OnHide", function()
        if oldOnHide then oldOnHide() end
        WarbandNexus.UnregisterMessage(dialog, "WN_CHARACTER_BANK_MONEY_LOG_UPDATED")
    end)

    dialog:Show()
end

-- Namespace export
ns.UI_ShowCharacterBankMoneyLogPopup = function(...)
    WarbandNexus:ShowCharacterBankMoneyLogPopup(...)
end

