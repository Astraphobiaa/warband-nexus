#!/usr/bin/env lua
--[[
    Regression test: calls match the argument shape Blizzard documents.

    Lua ignores extra arguments and pcall hides type errors, so a wrong call shape fails silently:
      - C_ItemUpgrade.GetItemUpgradeItemInfo() takes NO argument; it describes the item placed in the
        Item Upgrade frame. Passing an equipment-slot location made every slot inherit that one item's
        ranks and costs while the frame was open.
      - C_ItemUpgrade.GetHighWatermarkSlotForItem / GetHighWatermarkForItem take "Item ID, Link, or
        Name". An ItemLocation errored inside a pcall, so no watermark was ever read.
    Source: Blizzard_APIDocumentationGenerated 12.1.5 (70448), ItemUpgradeDocumentation.lua.
]]

local ROOT = os.getenv("WN_ROOT") or "."

-- api -> rule. "noargs": must be called with (). "itemInfo": first argument must not be an ItemLocation.
local RULES = {
    ["C_ItemUpgrade.GetItemUpgradeItemInfo"] = "noargs",
    ["C_ItemUpgrade.GetItemHyperlink"] = "noargs",
    ["C_ItemUpgrade.GetHighWatermarkSlotForItem"] = "itemInfo",
    ["C_ItemUpgrade.GetHighWatermarkForItem"] = "itemInfo",
}

local function listFiles()
    local out = {}
    local p = io.popen('find "' .. ROOT .. '/Modules" "' .. ROOT .. '/Core.lua" -name "*.lua" 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local checked, failures = 0, {}
for _, path in ipairs(listFiles()) do
    local fh = io.open(path, "rb")
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(c) return (c:gsub("[^\n]", "")) end)
    src = src:gsub("%-%-[^\n]*", "")
    local relPath = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    -- Location variables created in this file (e.g. `local location = ItemLocation:CreateFrom...`).
    local locationVars = {}
    for v in src:gmatch("local%s+([%w_]+)%s*=%s*ItemLocation:Create") do locationVars[v] = true end
    for api, rule in pairs(RULES) do
        local apiPat = api:gsub("%.", "%%.")
        for pos, args in src:gmatch("()" .. apiPat .. "%s*(%b())") do
            local _, nl = src:sub(1, pos):gsub("\n", "")
            local inner = args:sub(2, -2):gsub("^%s+", ""):gsub("%s+$", "")
            checked = checked + 1
            if rule == "noargs" and inner ~= "" then
                failures[#failures + 1] = string.format("%s:%d  %s takes no arguments, got (%s)", relPath, nl + 1, api, inner)
            elseif rule == "itemInfo" then
                local first = inner:match("^([%w_]+)")
                if inner:find("ItemLocation") or (first and locationVars[first]) then
                    failures[#failures + 1] = string.format("%s:%d  %s wants an item ID/link/name, got ItemLocation (%s)", relPath, nl + 1, api, inner)
                end
            end
        end
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("API call shape suite failed with " .. #failures .. " failure(s).")
end
if checked < 3 then
    error("API call shape suite matched too few call sites (" .. checked .. "); the scanner is broken.")
end
print("API call shape suite: ALL TESTS PASSED.")
