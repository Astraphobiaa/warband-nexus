--[[
    Warband Nexus - Formatting Helpers
    
    Common formatting utilities for numbers, money, and text processing.
    
    Provides:
    - Number formatting with thousand separators
    - Money formatting (gold/silver/copper with icons)
    - Compact money formatting (highest denomination only)
    - Text number auto-formatting
    - Legacy gold formatting
    
    Extracted from SharedWidgets.lua (176 lines)
    Location: Lines 1145-1320
]]

local ADDON_NAME, ns = ...

--============================================================================
-- NUMBER FORMATTING
--============================================================================

---Format gold amount with separators and icon (legacy - simple gold display)
---@param copper number Total copper amount
---@return string Formatted gold string with icon
local function FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
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
    local formatted = tostring(math.floor(number))
    local negative = false
    
    if string.sub(formatted, 1, 1) == "-" then
        negative = true
        formatted = string.sub(formatted, 2)
    end
    
    -- Add thousand separators (dots for Turkish locale)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(%d+)(%d%d%d)", '%1.%2')
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
    
    -- Find all numbers (4+ digits) and format them
    -- Pattern matches whole numbers not already formatted (no dots inside)
    local result = text
    
    -- Process numbers in descending order of length to avoid partial replacements
    local numbers = {}
    for num in string.gmatch(text, "%d%d%d%d+") do
        -- Check if number is already formatted (contains dots)
        local alreadyFormatted = false
        local numStart, numEnd = string.find(result, num, 1, true)
        if numStart and numStart > 1 then
            -- Check if there's a dot before this number
            if string.sub(result, numStart - 1, numStart - 1) == "." then
                alreadyFormatted = true
            end
        end
        
        if not alreadyFormatted then
            table.insert(numbers, {value = num, length = #num})
        end
    end
    
    -- Sort by length (descending) to replace longer numbers first
    table.sort(numbers, function(a, b) return a.length > b.length end)
    
    -- Replace each number with its formatted version
    for _, numData in ipairs(numbers) do
        local formatted = FormatNumber(tonumber(numData.value))
        -- Use pattern to match whole number (not part of a longer number)
        result = string.gsub(result, "(%D)" .. numData.value .. "(%D)", "%1" .. formatted .. "%2")
        result = string.gsub(result, "^" .. numData.value .. "(%D)", formatted .. "%1")
        result = string.gsub(result, "(%D)" .. numData.value .. "$", "%1" .. formatted)
        result = string.gsub(result, "^" .. numData.value .. "$", formatted)
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
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Build formatted string
    local parts = {}
    
    -- Gold (yellow/golden)
    if gold > 0 or showZero then
        -- Add thousand separators for gold (dots for Turkish locale)
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
            if k == 0 then break end
        end
        table.insert(parts, string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", goldStr, iconSize, iconSize))
    end
    
    -- Silver (silver/gray) - Only pad if gold exists
    if silver > 0 or (showZero and gold > 0) then
        local fmt = (gold > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffc7c7cf" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:0:0|t", silver, iconSize, iconSize))
    end
    
    -- Copper (bronze/copper) - Only pad if silver or gold exists
    if copperAmount > 0 or showZero or (gold == 0 and silver == 0) then
        local fmt = (gold > 0 or silver > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffeda55f" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:0:0|t", copperAmount, iconSize, iconSize))
    end
    
    return table.concat(parts, " ")
end

---Format money compact (short version, only highest denomination)
---@param copper number Total copper amount
---@param iconSize number|nil Icon size (optional, default 14)
---@return string Compact formatted money string
local function FormatMoneyCompact(copper, iconSize)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Show only the highest denomination
    if gold > 0 then
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize)
    else
        return string.format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize)
    end
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Number formatting
ns.UI_FormatNumber = FormatNumber
ns.UI_FormatTextNumbers = FormatTextNumbers

-- Money formatting
ns.UI_FormatGold = FormatGold
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatMoneyCompact = FormatMoneyCompact

print("|cff00ff00[WN FormatHelpers]|r Module loaded successfully (176 lines, 5 formatting functions)")
