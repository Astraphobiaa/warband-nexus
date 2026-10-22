#!/usr/bin/env lua
--[[
    Regression test: fields read from API result tables exist in the documented struct.

    Reading a field the struct does not have returns nil without any error, so the branch built on it
    silently never runs. Found and fixed:
      - QuestInfo (C_QuestLog.GetInfo) has no mapID / zoneName: the quest-log scan never matched a map.
      - TransmogIllusionInfo has no name / spellID / sourceText: new-illusion toasts and illusion plans
        always fell back to "Illusion <id>".
      - WeeklyRewardActivityRewardInfo has no itemLevel, TraitEntryRankInfo no maxRanks, ProfessionInfo
        no iconFileID / texture / skillLineID / parentSkillLineID (2026-10-22): dead fallbacks that
        never ran; the same-window check in ProfessionsUI never matched a parent/child skill line.
    This scans every shipped Lua file: a variable assigned from one of the APIs below (directly, via
    pcall, or as an element of a list API's result) must only have documented fields read from it.
    Field lists: Blizzard_APIDocumentationGenerated 12.1.5 (70448).
]]

local ROOT = os.getenv("WN_ROOT") or "."

local STRUCTS = {
    QuestInfo = { "title", "questLogIndex", "questID", "campaignID", "level", "difficultyLevel", "suggestedGroup",
        "frequency", "isHeader", "useMinimalHeader", "sortAsNormalQuest", "isCollapsed", "startEvent", "isTask",
        "isBounty", "isStory", "isScaling", "isOnMap", "hasLocalPOI", "isHidden", "isAutoComplete",
        "overridesSortOrder", "readyForTranslation", "isInternalOnly", "isAbandonOnDisable", "headerSortKey",
        "questClassification" },
    TransmogIllusionInfo = { "visualID", "sourceID", "icon", "isCollected", "isUsable", "isHideVisual" },
    CurrencyInfo = { "name", "description", "currencyID", "isHeader", "isHeaderExpanded", "currencyListDepth",
        "isTypeUnused", "isShowInBackpack", "quantity", "trackedQuantity", "iconFileID", "maxQuantity",
        "canEarnPerWeek", "quantityEarnedThisWeek", "isTradeable", "quality", "maxWeeklyQuantity", "totalEarned",
        "discovered", "useTotalEarnedForMaxQty", "isAccountWide", "isAccountTransferable", "transferPercentage",
        "rechargingCycleDurationMS", "rechargingAmountPerCycle" },
    ItemUpgradeItemInfo = { "iconID", "name", "itemUpgradeable", "displayQuality", "highWatermarkSlot",
        "currUpgrade", "maxUpgrade", "minItemLevel", "maxItemLevel", "upgradeLevelInfos", "customUpgradeString",
        "upgradeCostTypesForSeason" },
    TraitEntryRankInfo = { "entryID", "rank" },
    TraitNodeInfo = { "ID", "posX", "posY", "flags", "entryIDs", "entryIDsWithCommittedRanks", "canPurchaseRank",
        "canRefundRank", "isAvailable", "isVisible", "isDisplayError", "ranksPurchased", "ranksIncreased",
        "entryIDToRanksIncreased", "activeRank", "currentRank", "activeEntry", "nextEntry", "maxRanks", "totalMaxRanks",
        "type", "visibleEdges", "meetsEdgeRequirements", "groupIDs", "conditionIDs", "isCascadeRepurchasable",
        "cascadeRepurchaseEntryID", "subTreeID", "subTreeActive" },
    ProfessionInfo = { "profession", "professionID", "sourceCounter", "professionName", "expansionName", "skillLevel",
        "maxSkillLevel", "skillModifier", "isPrimaryProfession", "parentProfessionID", "parentProfessionName" },
    WeeklyRewardActivityInfo = { "type", "index", "threshold", "progress", "id", "activityTierID", "level", "claimID",
        "raidString", "rewards" },
    WeeklyRewardActivityRewardInfo = { "type", "id", "quantity", "itemDBID" },
}
-- struct -> field -> { nested struct, isList }: `var.field.x` and `local e = var.field[...]` are checked too.
local NESTED = {
    TraitNodeInfo = { activeEntry = { "TraitEntryRankInfo" }, nextEntry = { "TraitEntryRankInfo" } },
    WeeklyRewardActivityInfo = { rewards = { "WeeklyRewardActivityRewardInfo", true } },
}
-- api -> { struct, isList }
local APIS = {
    ["C_QuestLog.GetInfo"] = { "QuestInfo" },
    ["C_TransmogCollection.GetIllusionInfo"] = { "TransmogIllusionInfo" },
    ["C_TransmogCollection.GetIllusions"] = { "TransmogIllusionInfo", true },
    ["C_CurrencyInfo.GetCurrencyInfo"] = { "CurrencyInfo" },
    ["C_ItemUpgrade.GetItemUpgradeItemInfo"] = { "ItemUpgradeItemInfo" },
    ["C_Traits.GetNodeInfo"] = { "TraitNodeInfo" },
    ["C_TradeSkillUI.GetProfessionInfoBySkillLineID"] = { "ProfessionInfo" },
    ["C_TradeSkillUI.GetProfessionInfoByRecipeID"] = { "ProfessionInfo" },
    ["C_TradeSkillUI.GetBaseProfessionInfo"] = { "ProfessionInfo" },
    ["C_TradeSkillUI.GetChildProfessionInfo"] = { "ProfessionInfo" },
    ["C_TradeSkillUI.GetChildProfessionInfos"] = { "ProfessionInfo", true },
    ["C_WeeklyRewards.GetActivities"] = { "WeeklyRewardActivityInfo", true },
}
local SCAN_LINES = 60

local FIELDSET = {}
for name, list in pairs(STRUCTS) do
    FIELDSET[name] = {}
    for i = 1, #list do FIELDSET[name][list[i]] = true end
end

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
    src = src:gsub('"[^"\n]*"', '""')
    local lines = {}
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    local relPath = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")

    local scanReads
    function scanReads(var, struct, fromLine, label)
        local fields = FIELDSET[struct]
        local nested = NESTED[struct]
        local varPat = var:gsub("%p", "%%%0")
        for ln = fromLine, math.min(#lines, fromLine + SCAN_LINES) do
            local l = lines[ln]
            if ln > fromLine and l:find("local%s+[%w_,%s]*%f[%w_]" .. varPat .. "%f[^%w_]") then break end
            if nested then
                for field, sub in pairs(nested) do
                    local fieldPat = varPat .. "%." .. field
                    if sub[2] then
                        local elem = l:match("local%s+([%w_]+)%s*=%s*" .. fieldPat .. "%[")
                        if elem then scanReads(elem, sub[1], ln, label .. "." .. field .. " element") end
                    else
                        for subField in l:gmatch("%f[%w_]" .. fieldPat .. "%.([%a_][%w_]*)") do
                            checked = checked + 1
                            if not FIELDSET[sub[1]][subField] then
                                failures[#failures + 1] = string.format("%s:%d  %s.%s.%s — %s (%s.%s) has no field `%s`",
                                    relPath, ln, var, field, subField, sub[1], label, field, subField)
                            end
                        end
                    end
                end
            end
            for field in l:gmatch("%f[%w_]" .. varPat .. "%.([%a_][%w_]*)") do
                checked = checked + 1
                if not fields[field] then
                    failures[#failures + 1] = string.format("%s:%d  %s.%s — %s (%s) has no field `%s`",
                        relPath, ln, var, field, struct, label, field)
                end
            end
        end
    end

    for ln = 1, #lines do
        local l = lines[ln]
        for api, spec in pairs(APIS) do
            local apiPat = api:gsub("%.", "%%.")
            local var = l:match("local%s+([%w_]+)%s*=%s*" .. apiPat .. "%s*%(")
                or l:match("local%s+[%w_]+%s*,%s*([%w_]+)%s*=%s*pcall%(%s*" .. apiPat .. "%s*[,%)]")
            if var then
                if spec[2] then
                    -- List API: track `local e = var[...]` element variables.
                    local listPat = var:gsub("%p", "%%%0")
                    for ln2 = ln + 1, math.min(#lines, ln + SCAN_LINES) do
                        local elem = lines[ln2]:match("local%s+([%w_]+)%s*=%s*" .. listPat .. "%[")
                        if elem then scanReads(elem, spec[1], ln2, api .. " element") end
                    end
                    -- `for _, e in ipairs(var)` / `pairs(var)`
                    for ln2 = ln + 1, math.min(#lines, ln + SCAN_LINES) do
                        local elem = lines[ln2]:match("for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+i?pairs%(%s*" .. listPat .. "%s*%)")
                        if elem then scanReads(elem, spec[1], ln2, api .. " element") end
                    end
                else
                    scanReads(var, spec[1], ln, api)
                end
            end
        end
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("API struct field suite failed with " .. #failures .. " failure(s).")
end
if checked < 20 then
    error("API struct field suite matched too few field reads (" .. checked .. "); the scanner is broken.")
end
print("API struct field suite: ALL TESTS PASSED.")
