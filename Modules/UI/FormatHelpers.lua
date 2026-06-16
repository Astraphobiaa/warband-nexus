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

-- SHIFT-AWARE SEASON PROGRESS BINDING
-- Default view: current bag balance only, colored by cap state (open=green, capped=red).
-- Hold Shift: expanded "<bag> \194\183 <earned> / <cap>" view, same color rule.
-- Bindings auto-refresh on MODIFIER_STATE_CHANGED. Weak keys so retired FontStrings GC cleanly.
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
local function ResolveSeasonBinding(entry)
    if type(entry) == "table" and entry.cd ~= nil then
        return entry.cd, entry.compactShift == true
    end
    return entry, false
end

local function ApplySeasonProgressBindingText(fs, entry, expanded)
    if not fs or not fs.SetText then return end
    local cd, compact = ResolveSeasonBinding(entry)
    local text = FormatSeasonProgressShiftAware(cd, expanded, compact)
    if type(entry) == "table" and entry.warbandTotal ~= nil then
        text = text .. SeasonMutedHex() .. " / " .. FormatNumber(entry.warbandTotal) .. "|r"
    end
    fs:SetText(text)
end

local _seasonAmountBindings = setmetatable({}, { __mode = "k" })
local _seasonAmountWatcher
local function EnsureSeasonAmountWatcher()
    if _seasonAmountWatcher then return end
    _seasonAmountWatcher = CreateFrame("Frame")
    _seasonAmountWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    _seasonAmountWatcher:SetScript("OnEvent", function(_, _, key)
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        local expanded = IsShiftKeyDown() and true or false
        for fs, entry in pairs(_seasonAmountBindings) do
            if fs and fs.SetText and fs.IsObjectType then
                ApplySeasonProgressBindingText(fs, entry, expanded)
            end
        end
    end)
end
local function BindSeasonProgressAmount(fs, cd, opts)
    if not fs or not fs.SetText then return end
    EnsureSeasonAmountWatcher()
    local compact = opts and opts.compactShift == true
    local entry = { cd = cd, compactShift = compact }
    if opts and opts.warbandTotal ~= nil then
        entry.warbandTotal = opts.warbandTotal
    end
    _seasonAmountBindings[fs] = entry
    ApplySeasonProgressBindingText(fs, entry, IsShiftKeyDown() and true or false)
end
local function UnbindSeasonProgressAmount(fs)
    if fs then _seasonAmountBindings[fs] = nil end
end
local function RefreshSeasonProgressAmount(fs, cd, opts)
    if not fs or not fs.SetText then return end
    local compact = opts and opts.compactShift == true
    if cd ~= nil then
        _seasonAmountBindings[fs] = { cd = cd, compactShift = compact }
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
    ApplySeasonProgressBindingText(fs, entry, IsShiftKeyDown() and true or false)
end

-- Achievement criteria helpers: Modules/UI/AchievementCriteriaHelpers.lua (loaded after this file in TOC)

-- NAMESPACE EXPORTS

function ns.UI_RefreshSeasonProgressBindings()
    if not _seasonAmountWatcher then return end
    local expanded = IsShiftKeyDown() and true or false
    for fs, entry in pairs(_seasonAmountBindings) do
        if fs and fs.SetText and fs.IsObjectType then
            ApplySeasonProgressBindingText(fs, entry, expanded)
        end
    end
end

-- Create FormatHelpers service object
local FormatHelpers = {
    FormatGold = FormatGold,
    FormatNumber = FormatNumber,
    FormatTextNumbers = FormatTextNumbers,
    FormatMoney = FormatMoney,
}

-- Export to namespace
ns.FormatHelpers = FormatHelpers

-- Legacy exports (backward compatibility)
ns.UI_FormatNumber = FormatNumber
ns.UI_FormatTextNumbers = FormatTextNumbers
ns.UI_FormatGold = FormatGold
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatSeasonProgressCurrencyLine = FormatSeasonProgressCurrencyLine
ns.UI_FormatSeasonProgressShiftAware = FormatSeasonProgressShiftAware
ns.UI_BindSeasonProgressAmount = BindSeasonProgressAmount
ns.UI_UnbindSeasonProgressAmount = UnbindSeasonProgressAmount
ns.UI_NormalizeColonLabelSpacing = NormalizeColonLabelSpacing

-- Module loaded - verbose logging removed
