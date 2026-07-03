--[[
    Warband Nexus - Format Helpers
    Number/money/text formatters; load before SharedWidgets (.toc).
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local floor = math.floor
local format = string.format
local gsub = string.gsub
local find = string.find
local sub = string.sub
local insert = table.insert
local gmatch = string.gmatch
local function NormalizeColonLabelSpacing(label)
    if label == nil then return "" end
    if type(label) ~= "string" then
        label = tostring(label)
    end
    if label == "" then return "" end
    if issecretvalue and issecretvalue(label) then
        return ""
    end
    local trimmed = label:match("^%s*(.-)%s*$") or label
    trimmed = trimmed:gsub("%s*:%s*$", "")
    return trimmed .. " : "
end
function ns.UI_RGBToHex(r, g, b)
    return format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

-- NUMBER FORMATTING
local function FormatGold(copper)
    local gold = floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return goldStr .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end
local function FormatNumber(number)
    if not number or number == 0 then return "0" end
    
    -- Convert to string and handle negative numbers
    local formatted = tostring(floor(number))
    local negative = false
    
    if sub(formatted, 1, 1) == "-" then
        negative = true
        formatted = sub(formatted, 2)
    end
    
    -- Add thousand separators (dots for Turkish locale)
    local k
    while true do
        formatted, k = gsub(formatted, "^(%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    
    -- Re-add negative sign if needed
    if negative then
        formatted = "-" .. formatted
    end
    
    return formatted
end
local function FormatTextNumbers(text)
    if not text or text == "" then return text end
    if issecretvalue and issecretvalue(text) then return "" end
    
    -- Find all numbers (4+ digits) and format them
    -- Pattern matches whole numbers not already formatted (no dots inside)
    local result = text
    
    -- Process numbers in descending order of length to avoid partial replacements
    local numbers = {}
    for num in gmatch(text, "%d%d%d%d+") do
        -- Check if number is already formatted (contains dots)
        local alreadyFormatted = false
        local numStart, numEnd = find(result, num, 1, true)
        if numStart and numStart > 1 then
            -- Check if there's a dot before this number
            if sub(result, numStart - 1, numStart - 1) == "." then
                alreadyFormatted = true
            end
        end
        
        if not alreadyFormatted then
            insert(numbers, {value = num, length = #num})
        end
    end
    
    -- Sort by length (descending) to replace longer numbers first
    table.sort(numbers, function(a, b) return a.length > b.length end)
    
    -- Replace each number with its formatted version
    for i = 1, #numbers do
        local numData = numbers[i]
        local formatted = FormatNumber(tonumber(numData.value))
        -- Use pattern to match whole number (not part of a longer number)
        result = gsub(result, "(%D)" .. numData.value .. "(%D)", "%1" .. formatted .. "%2")
        result = gsub(result, "^" .. numData.value .. "(%D)", formatted .. "%1")
        result = gsub(result, "(%D)" .. numData.value .. "$", "%1" .. formatted)
        result = gsub(result, "^" .. numData.value .. "$", formatted)
    end
    
    return result
end

-- MONEY FORMATTING
local function GetMoneyGoldHex()
    if ns.UI_GetSemanticGoldHex then
        return ns.UI_GetSemanticGoldHex()
    end
    return "|cffffd700"
end

local function FormatMoney(copper, iconSize, showZero)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    showZero = showZero or false
    
    -- Calculate gold, silver, copper with explicit floor operations
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperAmount = floor(copper % 100)
    
    -- Build formatted string
    local parts = {}
    
    -- Gold (yellow/golden)
    if gold > 0 or showZero then
        -- Add thousand separators for gold (dots for Turkish locale)
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
            if k == 0 then break end
        end
        insert(parts, format("%s%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", GetMoneyGoldHex(), goldStr, iconSize, iconSize))
    end
    
    -- Silver (silver/gray) - Only pad if gold exists
    if silver > 0 or (showZero and gold > 0) then
        local fmt = (gold > 0) and "%02d" or "%d"
        insert(parts, format("|cffc7c7cf" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:0:0|t", silver, iconSize, iconSize))
    end
    
    -- Copper (bronze/copper) - Only pad if silver or gold exists
    if copperAmount > 0 or showZero or (gold == 0 and silver == 0) then
        local fmt = (gold > 0 or silver > 0) and "%02d" or "%d"
        insert(parts, format("|cffeda55f" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:0:0|t", copperAmount, iconSize, iconSize))
    end
    
    return table.concat(parts, " ")
end

--- Fixed-width G / S / C strings for column-aligned money rows (Statistics wealth, money logs).
--- Gold: up to 7 digits with thousand separators; silver/copper always 2 digits.
local function FormatMoneyPartsColumn(copper, iconSize)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 12
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end

    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperAmount = floor(copper % 100)

    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = gsub(goldStr, "^(-?%d+)(%d%d%d)", "%1.%2")
        if k == 0 then break end
    end

    local gIcon = format("|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", iconSize, iconSize)
    local sIcon = format("|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:0:0|t", iconSize, iconSize)
    local cIcon = format("|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:0:0|t", iconSize, iconSize)

    local gStr = format("%s%s|r%s", GetMoneyGoldHex(), goldStr, gIcon)
    local sStr = format("|cffc7c7cf%02d|r%s", silver, sIcon)
    local cStr = format("|cffeda55f%02d|r%s", copperAmount, cIcon)
    return gStr, sStr, cStr
end

-- SEASON / CAPPED CURRENCY LINE (Dawncrest, Coffer Key Shards, etc.)
-- Matches Gear tab: bag qty colored by earn room; "/ seasonMax" muted.

local CC_CAP_OPEN = "|cff6ee7a0"
local CC_CAPPED   = "|cffff6b6b"
local CC_WHITE    = "|cffeeeeee"  -- dark bootstrap; SeasonBrightHex uses UI_GetTextRoleHex at runtime
local CC_AMOUNT   = "|cfff0f4ff"
local CC_CAP_VAL  = "|cffb4bcc8"
local CC_MUTED    = "|cff7a8494"
local CC_SEP      = "|cff5c6570"

local function SeasonCapOpenHex()
    if ns.UI_GetSemanticGreenBrightHex then return ns.UI_GetSemanticGreenBrightHex() end
    return CC_CAP_OPEN
end
local function SeasonCappedHex()
    if ns.UI_RGBToHex and ns.UI_GetSemanticRedColor then
        return ns.UI_RGBToHex(ns.UI_GetSemanticRedColor())
    end
    return CC_CAPPED
end
local function SeasonBrightHex()
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Bright") end
    return CC_WHITE
end
local function SeasonAmountHex()
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Normal") end
    return CC_AMOUNT
end
local function SeasonCapValHex()
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Muted") end
    return CC_CAP_VAL
end
local function SeasonMutedHex()
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Dim") end
    return CC_MUTED
end
local function SeasonSepHex()
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Dim") end
    return CC_SEP
end
local EM_DASH_U   = "\226\128\148"
local function FormatSeasonProgressCurrencyLine(cd)
    if ns.Utilities and ns.Utilities.FormatCurrencySeasonProgressLine then
        return ns.Utilities.FormatCurrencySeasonProgressLine(cd)
    end
    if not cd then
        return SeasonMutedHex() .. "0|r"
    end
    local qty = tonumber(cd.quantity) or 0
    local maxQ = tonumber(cd.maxQuantity) or 0
    local teNum = tonumber(cd.totalEarned)
    local sm = tonumber(cd.seasonMax) or 0
    local cap = (sm > 0) and sm or ((maxQ > 0) and maxQ or 0)
    if cap > 0 then
        local progress = teNum or qty
        local progressColor = (progress >= cap) and SeasonCappedHex() or SeasonCapOpenHex()
        if teNum ~= nil and teNum ~= qty then
            return SeasonBrightHex() .. FormatNumber(qty) .. "|r " .. SeasonMutedHex() .. "\194\183|r " ..
                progressColor .. FormatNumber(teNum) .. "|r" ..
                SeasonMutedHex() .. " / " .. FormatNumber(cap) .. "|r"
        end
        return SeasonAmountHex() .. FormatNumber(qty) .. "|r " .. SeasonSepHex() .. "/|r " .. SeasonCapValHex() .. FormatNumber(cap) .. "|r"
    end
    if qty > 0 then
        return SeasonAmountHex() .. FormatNumber(qty) .. "|r"
    end
    return SeasonMutedHex() .. EM_DASH_U .. "|r"
end

-- PvE CURRENCY DISPLAY MODE (Current / Weekly toolbar + Shift invert)
local function PvEWeeklyProgressResolved(cd)
    if not cd then return 0, 0 end
    local qty = tonumber(cd.quantity) or 0
    local te = tonumber(cd.totalEarned)
    local sm = tonumber(cd.seasonMax) or 0
    local maxQ = tonumber(cd.maxQuantity) or 0
    local utils = ns.Utilities
    local isWeeklyShard = utils and (
        (utils.IsCofferKeyShardCurrency and utils:IsCofferKeyShardCurrency(cd.currencyID, cd.name))
        or (utils.IsWeeklyCapCurrency and utils:IsWeeklyCapCurrency(cd.currencyID, cd.name))
    )
    if isWeeklyShard and maxQ > 0 then
        return te or 0, maxQ
    end
    if utils and utils.IsRestoredCofferKeyCurrency and utils:IsRestoredCofferKeyCurrency(cd.currencyID, cd.name) and maxQ > 0 then
        return te or 0, maxQ
    end
    if sm > 0 then
        return te or 0, sm
    end
    if maxQ > 0 then
        return te or qty, maxQ
    end
    return qty, 0
end

local FormatPvECurrencyCurrentLine
local FormatPvECurrencyWeeklyLine

function ns.UI_GetPvECurrencyDisplayMode()
    local WN = ns.WarbandNexus
    local profile = WN and WN.db and WN.db.profile
    if profile and profile.pveCurrencyDisplayMode == "weekly" then
        return "weekly"
    end
    return "current"
end

function ns.UI_GetPvEShowWeeklyView()
    local weekly = (ns.UI_GetPvECurrencyDisplayMode() == "weekly")
    local shift = IsShiftKeyDown and IsShiftKeyDown() or false
    return weekly ~= shift
end

function ns.UI_TogglePvECurrencyDisplayMode()
    local mode = ns.UI_GetPvECurrencyDisplayMode()
    ns.UI_SetPvECurrencyDisplayMode((mode == "weekly") and "current" or "weekly")
end

function ns.UI_SetPvECurrencyDisplayMode(mode)
    local WN = ns.WarbandNexus
    if not WN or not WN.db or not WN.db.profile then return end
    WN.db.profile.pveCurrencyDisplayMode = (mode == "weekly") and "weekly" or "current"
    if ns.UI_RefreshSeasonProgressBindings then
        ns.UI_RefreshSeasonProgressBindings()
    end
    if ns.RefreshVaultShiftAwareDisplays then
        ns.RefreshVaultShiftAwareDisplays()
    end
    if WN.SendMessage then
        WN:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
    end
end

-- SHIFT-AWARE SEASON PROGRESS BINDING
-- Default view: current bag balance only, colored by cap state (open=green, capped=red).
-- Hold Shift: expanded "<bag> \194\183 <earned> / <cap>" view, same color rule.
-- PvE grid: toolbar Current/Weekly mode; Shift inverts. Bindings refresh on MODIFIER_STATE_CHANGED.
local function ResolveSeasonCapState(cd)
    if not cd then return 0, 0, 0, false end
    local qty = tonumber(cd.quantity) or 0
    local maxQ = tonumber(cd.maxQuantity) or 0
    local sm = tonumber(cd.seasonMax) or 0
    local cap = (sm > 0) and sm or maxQ
    local progress = tonumber(cd.totalEarned) or qty
    local capped = (cap > 0) and (progress >= cap)
    return qty, progress, cap, capped
end
local function FormatSeasonProgressShiftAware(cd, expanded, compactRemainingOnly)
    if not cd then return SeasonMutedHex() .. "0|r" end
    local qty, progress, cap, capped = ResolveSeasonCapState(cd)
    local color = (cap > 0) and (capped and SeasonCappedHex() or SeasonCapOpenHex()) or SeasonAmountHex()
    if not expanded then
        if cap > 0 or qty > 0 then
            return SeasonAmountHex() .. FormatNumber(qty) .. "|r"
        end
        return SeasonMutedHex() .. EM_DASH_U .. "|r"
    end
    if compactRemainingOnly and cap > 0 then
        local rem = math.max(cap - progress, 0)
        if rem > 0 then
            return color .. FormatNumber(rem) .. "|r"
        end
        return color .. FormatNumber(qty) .. "|r"
    end
    if cap > 0 then
        local progressTxt = (progress ~= qty)
            and (SeasonSepHex() .. " \194\183|r " .. color .. FormatNumber(progress) .. "|r ")
            or ""
        return SeasonAmountHex() .. FormatNumber(qty) .. "|r " ..
            progressTxt .. SeasonSepHex() .. "/|r " .. SeasonCapValHex() .. FormatNumber(cap) .. "|r"
    end
    if qty > 0 then return SeasonAmountHex() .. FormatNumber(qty) .. "|r" end
    return SeasonMutedHex() .. EM_DASH_U .. "|r"
end

FormatPvECurrencyCurrentLine = function(cd)
    return FormatSeasonProgressShiftAware(cd, false, false)
end

FormatPvECurrencyWeeklyLine = function(cd)
    if not cd then return SeasonMutedHex() .. EM_DASH_U .. "|r" end
    local progress, cap = PvEWeeklyProgressResolved(cd)
    if cap > 0 then
        local color = (progress >= cap) and SeasonCappedHex() or SeasonCapOpenHex()
        return color .. FormatNumber(progress) .. "|r " .. SeasonSepHex() .. "/|r " ..
            SeasonCapValHex() .. FormatNumber(cap) .. "|r"
    end
    local qty = tonumber(cd.quantity) or 0
    if qty > 0 then
        return SeasonAmountHex() .. FormatNumber(qty) .. "|r"
    end
    return SeasonMutedHex() .. EM_DASH_U .. "|r"
end

local function ResolveSeasonBinding(entry)
    if type(entry) == "table" and entry.cd ~= nil then
        return entry.cd, entry.compactShift == true
    end
    return entry, false
end

local function ResolveBindingShowWeekly(entry)
    if type(entry) == "table" and entry.pveDisplayMode then
        return ns.UI_GetPvEShowWeeklyView and ns.UI_GetPvEShowWeeklyView() or false
    end
    return IsShiftKeyDown and IsShiftKeyDown() or false
end

local function ApplySeasonProgressBindingText(fs, entry, forceWeekly)
    if not fs or not fs.SetText then return end
    local cd, compact = ResolveSeasonBinding(entry)
    local showWeekly = forceWeekly
    if showWeekly == nil then
        showWeekly = ResolveBindingShowWeekly(entry)
    end
    local text
    if type(entry) == "table" and entry.pveDisplayMode then
        text = showWeekly and FormatPvECurrencyWeeklyLine(cd) or FormatPvECurrencyCurrentLine(cd)
    else
        text = FormatSeasonProgressShiftAware(cd, showWeekly, compact)
    end
    if type(entry) == "table" and entry.warbandTotal ~= nil then
        text = text .. SeasonMutedHex() .. " / " .. FormatNumber(entry.warbandTotal) .. "|r"
    end
    fs:SetText(text)
end

local _seasonAmountBindings = setmetatable({}, { __mode = "k" })
local _pveBountyBindings = setmetatable({}, { __mode = "k" })
local PVE_BOUNTY_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local PVE_BOUNTY_CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"

local function ApplyPvEBountyBindingText(fs, entry)
    if not fs or not fs.SetText or not entry then return end
    if entry.unknown then
        fs:SetText(SeasonMutedHex() .. EM_DASH_U .. "|r")
        return
    end
    local showWeekly = ns.UI_GetPvEShowWeeklyView and ns.UI_GetPvEShowWeeklyView() or false
    if showWeekly then
        local progress = entry.done and 1 or 0
        local color = entry.done and SeasonCappedHex() or SeasonCapOpenHex()
        fs:SetText(color .. progress .. "|r " .. SeasonSepHex() .. "/|r " .. SeasonCapValHex() .. "1|r")
    else
        fs:SetText(entry.done and PVE_BOUNTY_CHECK or PVE_BOUNTY_CROSS)
    end
end

local _seasonAmountWatcher
local function EnsureSeasonAmountWatcher()
    if _seasonAmountWatcher then return end
    _seasonAmountWatcher = CreateFrame("Frame")
    _seasonAmountWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    _seasonAmountWatcher:SetScript("OnEvent", function(_, _, key)
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        for fs, entry in pairs(_seasonAmountBindings) do
            if fs and fs.SetText and fs.IsObjectType then
                ApplySeasonProgressBindingText(fs, entry)
            end
        end
        for fs, entry in pairs(_pveBountyBindings) do
            if fs and fs.SetText and fs.IsObjectType then
                ApplyPvEBountyBindingText(fs, entry)
            end
        end
    end)
end

local function BindPvEBountyDisplay(fs, bountyData)
    if not fs or not fs.SetText or not bountyData then return end
    EnsureSeasonAmountWatcher()
    _pveBountyBindings[fs] = bountyData
    ApplyPvEBountyBindingText(fs, bountyData)
end

local function UnbindPvEBountyDisplay(fs)
    if fs then _pveBountyBindings[fs] = nil end
end
local function BindSeasonProgressAmount(fs, cd, opts)
    if not fs or not fs.SetText then return end
    EnsureSeasonAmountWatcher()
    local compact = opts and opts.compactShift == true
    local entry = { cd = cd, compactShift = compact }
    if opts and opts.pveDisplayMode then
        entry.pveDisplayMode = true
    end
    if opts and opts.warbandTotal ~= nil then
        entry.warbandTotal = opts.warbandTotal
    end
    _seasonAmountBindings[fs] = entry
    ApplySeasonProgressBindingText(fs, entry)
end
local function UnbindSeasonProgressAmount(fs)
    if fs then _seasonAmountBindings[fs] = nil end
end
local function RefreshSeasonProgressAmount(fs, cd, opts)
    if not fs or not fs.SetText then return end
    local compact = opts and opts.compactShift == true
    if cd ~= nil then
        _seasonAmountBindings[fs] = { cd = cd, compactShift = compact }
        if opts and opts.pveDisplayMode then
            _seasonAmountBindings[fs].pveDisplayMode = true
        end
        if opts and opts.warbandTotal ~= nil then
            _seasonAmountBindings[fs].warbandTotal = opts.warbandTotal
        end
    end
    local entry = _seasonAmountBindings[fs]
    if opts and opts.compactShift ~= nil then
        compact = opts.compactShift == true
    end
    if opts and opts.warbandTotal ~= nil and entry then
        entry.warbandTotal = opts.warbandTotal
    end
    if opts and opts.pveDisplayMode ~= nil and entry then
        entry.pveDisplayMode = opts.pveDisplayMode == true
    end
    ApplySeasonProgressBindingText(fs, entry)
end

-- Achievement criteria helpers: Modules/UI/AchievementCriteriaHelpers.lua (loaded after this file in TOC)

-- NAMESPACE EXPORTS

function ns.UI_RefreshSeasonProgressBindings()
    for fs, entry in pairs(_seasonAmountBindings) do
        if fs and fs.SetText and fs.IsObjectType then
            ApplySeasonProgressBindingText(fs, entry)
        end
    end
    for fs, entry in pairs(_pveBountyBindings) do
        if fs and fs.SetText and fs.IsObjectType then
            ApplyPvEBountyBindingText(fs, entry)
        end
    end
end

-- Create FormatHelpers service object
local FormatHelpers = {
    FormatGold = FormatGold,
    FormatNumber = FormatNumber,
    FormatTextNumbers = FormatTextNumbers,
    FormatMoney = FormatMoney,
    FormatMoneyPartsColumn = FormatMoneyPartsColumn,
}

-- Export to namespace
ns.FormatHelpers = FormatHelpers

-- Legacy exports (backward compatibility)
ns.UI_FormatNumber = FormatNumber
ns.UI_FormatTextNumbers = FormatTextNumbers
ns.UI_FormatGold = FormatGold
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatMoneyPartsColumn = FormatMoneyPartsColumn
ns.UI_FormatSeasonProgressCurrencyLine = FormatSeasonProgressCurrencyLine
ns.UI_FormatSeasonProgressShiftAware = FormatSeasonProgressShiftAware
ns.UI_FormatPvECurrencyCurrentLine = FormatPvECurrencyCurrentLine
ns.UI_FormatPvECurrencyWeeklyLine = FormatPvECurrencyWeeklyLine
ns.UI_BindSeasonProgressAmount = BindSeasonProgressAmount
ns.UI_UnbindSeasonProgressAmount = UnbindSeasonProgressAmount
ns.UI_BindPvEBountyDisplay = BindPvEBountyDisplay
ns.UI_UnbindPvEBountyDisplay = UnbindPvEBountyDisplay
ns.UI_NormalizeColonLabelSpacing = NormalizeColonLabelSpacing

-- Module loaded - verbose logging removed
