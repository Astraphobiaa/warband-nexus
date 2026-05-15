--[[
    Warband Nexus - Formatting Helpers
    
    Common formatting utilities for numbers, money, and text processing.
    
    Provides:
    - Number formatting with thousand separators
    - Money formatting (gold/silver/copper with icons)
    - Text number auto-formatting
    - Legacy gold formatting
    
    SharedWidgets no longer duplicates these; load order: FormatHelpers → SharedWidgets (.toc).
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

--- Trim trailing colon/spaces from a UI label and append a consistent ` … : ` separator.
--- Used for plan/source lines (Drop / Location / Vendor) so colon has balanced spaces.
---@param label string|nil
---@return string
local function NormalizeColonLabelSpacing(label)
    if label == nil then return "" end
    if type(label) ~= "string" then
        label = tostring(label)
    end
    if label == "" then return "" end
    if issecretvalue and issecretvalue(label) then
        return label
    end
    local trimmed = label:match("^%s*(.-)%s*$") or label
    trimmed = trimmed:gsub("%s*:%s*$", "")
    return trimmed .. " : "
end

--============================================================================
-- NUMBER FORMATTING
--============================================================================

---Format gold amount with separators and icon (legacy - simple gold display)
---@param copper number Total copper amount
---@return string Formatted gold string with icon
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

---Format number with thousand separators (e.g., 1.234.567)
---@param number number Number to format
---@return string Formatted number string with dots as thousand separators
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

---Format all numbers in text with thousand separators (e.g., "Get 50000 kills" -> "Get 50.000 kills")
---@param text string Text containing numbers
---@return string Text with all numbers formatted
local function FormatTextNumbers(text)
    if not text or text == "" then return text end
    if issecretvalue and issecretvalue(text) then return text end
    
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

--============================================================================
-- MONEY FORMATTING
--============================================================================

---Format money with gold, silver, and copper
---@param copper number Total copper amount
---@param iconSize number|nil Icon size (optional, default 14)
---@param showZero boolean|nil Show zero values (optional, default false)
---@return string Formatted money string with colors and icons
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
        insert(parts, format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", goldStr, iconSize, iconSize))
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

--============================================================================
-- SEASON / CAPPED CURRENCY LINE (Dawncrest, Coffer Key Shards, etc.)
-- Matches Gear tab: bag qty colored by earn room; "/ seasonMax" muted.
--============================================================================

local CC_CAP_OPEN = "|cff80ff80"
local CC_CAPPED   = "|cffff5959"
local CC_WHITE    = "|cffffffff"
local CC_MUTED    = "|cff888888"
local EM_DASH_U   = "\226\128\148"

---@param cd table|nil GetCurrencyData result (quantity, maxQuantity, totalEarned, seasonMax)
---@return string Colored amount text for FontString:SetText
---Three-segment season-progress format: `<current> · <earned> / <cap>`
---  current = bag balance (cd.quantity)             — white
---  earned  = season totalEarned (cd.totalEarned)   — green if room left, red if capped
---  cap     = season cap (cd.seasonMax/maxQuantity) — muted
---Falls back to current/cap when totalEarned is missing, or just current when no cap exists.
local function FormatSeasonProgressCurrencyLine(cd)
    if ns.Utilities and ns.Utilities.FormatCurrencySeasonProgressLine then
        return ns.Utilities.FormatCurrencySeasonProgressLine(cd)
    end
    if not cd then
        return CC_MUTED .. "0|r"
    end
    local qty = tonumber(cd.quantity) or 0
    local maxQ = tonumber(cd.maxQuantity) or 0
    local teNum = tonumber(cd.totalEarned)
    local sm = tonumber(cd.seasonMax) or 0
    local cap = (sm > 0) and sm or ((maxQ > 0) and maxQ or 0)
    if cap > 0 then
        local progress = teNum or qty
        local progressColor = (progress >= cap) and CC_CAPPED or CC_CAP_OPEN
        if teNum ~= nil and teNum ~= qty then
            return CC_WHITE .. FormatNumber(qty) .. "|r " .. CC_MUTED .. "\194\183|r " ..
                progressColor .. FormatNumber(teNum) .. "|r" ..
                CC_MUTED .. " / " .. FormatNumber(cap) .. "|r"
        end
        return progressColor .. FormatNumber(qty) .. "|r " .. CC_MUTED .. "/ " .. FormatNumber(cap) .. "|r"
    end
    if qty > 0 then
        return CC_WHITE .. FormatNumber(qty) .. "|r"
    end
    return CC_MUTED .. EM_DASH_U .. "|r"
end

--============================================================================
-- SHIFT-AWARE SEASON PROGRESS BINDING
-- Default view: current bag balance only, colored by cap state (open=green, capped=red).
-- Hold Shift: expanded "<bag> \194\183 <earned> / <cap>" view, same color rule.
-- Bindings auto-refresh on MODIFIER_STATE_CHANGED. Weak keys so retired FontStrings GC cleanly.
--============================================================================

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

local function FormatSeasonProgressShiftAware(cd, expanded)
    if not cd then return CC_MUTED .. "0|r" end
    local qty, progress, cap, capped = ResolveSeasonCapState(cd)
    local color = (cap > 0) and (capped and CC_CAPPED or CC_CAP_OPEN) or CC_WHITE
    if not expanded then
        if cap > 0 or qty > 0 then
            return color .. FormatNumber(qty) .. "|r"
        end
        return CC_MUTED .. EM_DASH_U .. "|r"
    end
    if cap > 0 then
        local progressTxt = (progress ~= qty)
            and (CC_MUTED .. "\194\183|r " .. color .. FormatNumber(progress) .. "|r ")
            or ""
        return color .. FormatNumber(qty) .. "|r " ..
            progressTxt .. CC_MUTED .. "/ " .. FormatNumber(cap) .. "|r"
    end
    if qty > 0 then return CC_WHITE .. FormatNumber(qty) .. "|r" end
    return CC_MUTED .. EM_DASH_U .. "|r"
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
        for fs, cd in pairs(_seasonAmountBindings) do
            if fs and fs.SetText and fs.IsObjectType then
                fs:SetText(FormatSeasonProgressShiftAware(cd, expanded))
            end
        end
    end)
end

---Bind a FontString to a currency-data object so it shows current-only by default
---and current\194\183earned/cap when Shift is held. Handles refresh on shift toggle.
---@param fs FontString
---@param cd table|nil
local function BindSeasonProgressAmount(fs, cd)
    if not fs or not fs.SetText then return end
    EnsureSeasonAmountWatcher()
    _seasonAmountBindings[fs] = cd
    fs:SetText(FormatSeasonProgressShiftAware(cd, IsShiftKeyDown() and true or false))
end

---Remove shift-aware binding so a reused FontString stops tracking stale currency data.
local function UnbindSeasonProgressAmount(fs)
    if fs then _seasonAmountBindings[fs] = nil end
end

---Update binding (e.g. on data refresh) and re-render with current shift state.
local function RefreshSeasonProgressAmount(fs, cd)
    if not fs or not fs.SetText then return end
    if cd ~= nil then _seasonAmountBindings[fs] = cd end
    local data = cd or _seasonAmountBindings[fs]
    fs:SetText(FormatSeasonProgressShiftAware(data, IsShiftKeyDown() and true or false))
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

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
ns.UI_BindSeasonProgressAmount = BindSeasonProgressAmount
ns.UI_UnbindSeasonProgressAmount = UnbindSeasonProgressAmount
ns.UI_RefreshSeasonProgressAmount = RefreshSeasonProgressAmount
ns.UI_NormalizeColonLabelSpacing = NormalizeColonLabelSpacing

-- Module loaded - verbose logging removed
