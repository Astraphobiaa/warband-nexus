#!/usr/bin/env lua
--[[
    Regression test: multi-return API destructuring reads the value its variable is named after.

    Several call sites skipped the wrong number of `_` placeholders, so `minLvl` held the item level,
    `level` held the quality, `classID` held the icon, `tex` held the equip slot and `specID` held the
    display ID. Lua raises nothing for that; the wrong value was persisted or used silently.
    GetMountInfoByID #13 is isSteadyFlight, not "is for dragonriding" (the opposite meaning); it was
    stored as isForDragonriding until 2026-10-22.

    This scans every shipped Lua file for `a, b, c = [pcall(]API(...)` destructuring of the APIs below
    and checks each meaningfully named variable against the documented return order.
    Return orders: Blizzard_APIDocumentationGenerated 12.1.5 (70448), ItemDocumentation.lua for
    C_Item.*. C_PetJournal.GetPetInfoByItemID, GetAchievementInfo, GetAchievementCriteriaInfo and
    GetProfessionInfo are not in the generated docs; their orders come from the warcraft.wiki.gg API
    pages (via Ketho/vscode-wow-api Wiki.lua, 12.0.5 snapshot; wiki.gg itself was offline 2026-10-21).
]]

local ROOT = os.getenv("WN_ROOT") or "."

local RETURNS = {
    ["C_Item.GetItemInfo"] = { "itemName", "itemLink", "itemQuality", "itemLevel", "itemMinLevel", "itemType",
        "itemSubType", "itemStackCount", "itemEquipLoc", "itemTexture", "sellPrice", "classID", "subclassID",
        "bindType", "expansionID", "setID", "isCraftingReagent" },
    ["C_Item.GetItemInfoInstant"] = { "itemID", "itemType", "itemSubType", "itemEquipLoc", "icon", "classID", "subClassID" },
    ["C_PetJournal.GetPetInfoByItemID"] = { "name", "icon", "petType", "creatureID", "sourceText", "description",
        "isWild", "canBattle", "isTradeable", "isUnique", "obtainable", "displayID", "speciesID" },
    ["C_MountJournal.GetMountInfoByID"] = { "name", "spellID", "icon", "isActive", "isUsable", "sourceType",
        "isFavorite", "isFactionSpecific", "faction", "shouldHideOnChar", "isCollected", "mountID", "isSteadyFlight" },
}
RETURNS["GetAchievementInfo"] = { "id", "name", "points", "completed", "month", "day", "year", "description",
    "flags", "icon", "rewardText", "isGuild", "wasEarnedByMe", "earnedBy", "isStatistic" }
RETURNS["GetAchievementCriteriaInfo"] = { "criteriaString", "criteriaType", "completed", "quantity", "reqQuantity",
    "charName", "flags", "assetID", "quantityString", "criteriaID", "eligible", "duration", "elapsed" }
RETURNS["GetProfessionInfo"] = { "name", "icon", "skillLevel", "maxSkillLevel", "numAbilities", "spelloffset",
    "skillLine", "skillModifier", "specializationIndex", "specializationOffset", "skillLineName" }
-- Legacy global with the same return order as C_Item.GetItemInfo.
RETURNS["GetItemInfo"] = RETURNS["C_Item.GetItemInfo"]
RETURNS["C_Item.GetItemInfoInstant"].alias = "GetItemInfoInstant"
RETURNS["GetItemInfoInstant"] = RETURNS["C_Item.GetItemInfoInstant"]

-- Variable-name pattern (lowercased) -> documented return name. First match wins, so specific first.
local CLASSIFY = {
    -- Mount journal. "dragonriding" maps to a name no API returns, so any such variable fails.
    { "dragonriding", "isForDragonriding" }, { "steadyflight", "isSteadyFlight" },
    { "hideonchar", "shouldHideOnChar" }, { "factionspecific", "isFactionSpecific" }, { "^faction$", "faction" },
    { "sourcetype", "sourceType" }, { "collected", "isCollected" }, { "favorite", "isFavorite" },
    { "wasearnedbyme", "wasEarnedByMe" }, { "earnedby", "earnedBy" }, { "isguild", "isGuild" },
    { "rewardtext", "rewardText" }, { "isstatistic", "isStatistic" }, { "assetid", "assetID" },
    { "criteriaid", "criteriaID" }, { "criteriatype", "criteriaType" }, { "reqquantity", "reqQuantity" },
    { "quantitystring", "quantityString" }, { "skilllinename", "skillLineName" }, { "skillline", "skillLine" },
    { "maxskill", "maxSkillLevel" }, { "skilllevel", "skillLevel" }, { "spelloffset", "spelloffset" },
    { "^achname$", "name" }, { "^name%d*$", "name" }, { "^achid$", "id" },
    { "minl", "itemMinLevel" }, { "reqlevel", "itemMinLevel" }, { "requiredlevel", "itemMinLevel" },
    { "subclass", "subclassID" }, { "classid", "classID" },
    { "speciesid", "speciesID" }, { "specid", "speciesID" }, { "displayid", "displayID" },
    { "equiploc", "itemEquipLoc" }, { "quality", "itemQuality" },
    { "ilvl", "itemLevel" }, { "itemlevel", "itemLevel" }, { "^level%d*$", "itemLevel" },
    { "texture", "itemTexture" }, { "^tex%d*$", "icon" }, { "^icon%d*$", "icon" },
    { "stack", "itemStackCount" }, { "sellprice", "sellPrice" }, { "bind", "bindType" },
    { "expansion", "expansionID" }, { "reagent", "isCraftingReagent" },
}
local EQUIV = { icon = { icon = true, itemTexture = true }, itemTexture = { icon = true, itemTexture = true },
    name = { name = true, itemName = true, criteriaString = true },
    subclassID = { subclassID = true, subClassID = true } }

local function classify(var)
    local v = var:lower()
    for i = 1, #CLASSIFY do
        if v:find(CLASSIFY[i][1]) then return CLASSIFY[i][2] end
    end
    return nil
end

local function listFiles()
    local out = {}
    local p = io.popen('find "' .. ROOT .. '/Modules" "' .. ROOT .. '/Core.lua" -name "*.lua" 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local checked, failures = 0, {}

local function checkStatement(relPath, lineNo, lhs, api, isPcall)
    local order = RETURNS[api]
    local vars = {}
    for v in lhs:gmatch("[%w_]+") do vars[#vars + 1] = v end
    if isPcall then table.remove(vars, 1) end
    for pos = 1, #vars do
        local want = vars[pos] ~= "_" and classify(vars[pos])
        if want then
            checked = checked + 1
            local got = order[pos]
            local ok = (got == want) or (EQUIV[want] and got and EQUIV[want][got])
            if not ok then
                failures[#failures + 1] = string.format("%s:%d  %s -> `%s` is return #%d (%s), expected %s",
                    relPath, lineNo, api, vars[pos], pos, tostring(got), want)
            end
        end
    end
end

for _, path in ipairs(listFiles()) do
    local fh = io.open(path, "rb")
    local src = fh:read("*a")
    fh:close()
    -- Strip comments but keep newlines so line numbers stay right.
    src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(c) return (c:gsub("[^\n]", "")) end)
    src = src:gsub("%-%-[^\n]*", "")
    local relPath = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    -- Statements of the form `local a, b,\n c = [pcall(]API(...)` may span lines.
    -- Try every `local` independently (anchored): with gmatch, a rejected match that swallowed the next
    -- `local` statement would also skip that statement.
    local searchFrom = 1
    while true do
        local startPos = src:find("%f[%w_]local%s", searchFrom)
        if not startPos then break end
        searchFrom = startPos + 5
        local lhs, rhs = src:match("^local%s+([%w_][%w_%s,]-)%s*=%s*([%w_%.]+%(?%s*[%w_%.]*)", startPos)
        local api, isPcall
        if not lhs then lhs, rhs = "", "" end
        local inner = rhs:match("^pcall%(%s*([%w_%.]+)")
        if inner then api, isPcall = inner, true else api = rhs:match("^([%w_%.]+)%(") end
        -- Only a pure `a, b,\n c` identifier list counts; `x if y then z` means the lazy match swallowed
        -- an earlier statement, so it is not this API's destructuring.
        local normalized = lhs:gsub("%s*,%s*", ","):gsub("^%s+", ""):gsub("%s+$", "")
        if normalized:find("%s") then api = nil end
        if api and RETURNS[api] then
            local _, nl = src:sub(1, startPos):gsub("\n", "")
            checkStatement(relPath, nl + 1, lhs, api, isPcall)
        end
    end
end

print(string.format("Checked %d named return slots", checked))
for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("API return position suite failed with " .. #failures .. " failure(s).")
end
if checked < 10 then
    error("API return position suite matched too few call sites (" .. checked .. "); the scanner is broken.")
end
print("API return position suite: ALL TESTS PASSED.")
