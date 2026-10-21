#!/usr/bin/env lua
--[[
    Regression test: shipped code does not reference WoW functions that are gone in 12.1.5.

    test_deprecated_api_calls.lua accepts a feature-detected call (`if X then X() end`). For a function
    that no longer exists that guard is not safety, it is a branch that can never run: it hides a
    missing feature (crafting-order counts, hero spec name, plan chat links, journal search restore)
    or keeps dead fallbacks next to the code that really runs. This lint fails on ANY reference:
    call, feature-detect, `_G.X` / `_G["X"]` lookup, or hooksecurefunc target.

    Each name is absent from both Blizzard_APIDocumentationGenerated 12.1.5 (70448) and
    Ketho/BlizzardInterfaceResources' in-game GlobalAPI dump (checked 2026-10-22). The replacement
    noted next to each one is what the code uses instead.
]]

local ROOT = os.getenv("WN_ROOT") or "."

-- [namespace] = { [function] = replacement }
local REMOVED_NAMESPACED = {
    C_CraftingOrders = {
        GetNumPersonalOrders = "GetPersonalOrdersInfo()[i].numPersonalOrders",
        GetNumGuildOrders = "CRAFTINGORDERS_UPDATE_ORDER_COUNT payload",
    },
    C_ClassTalents = { GetHeroTalentSpecInfo = "C_Traits.GetSubTreeInfo(configID, subTreeID).name" },
    C_ToyBox = { GetFilterString = "ToyBox.searchString" },
    C_MountJournal = { GetSearch = "MountJournal.searchBox:GetText()" },
    C_Item = {
        IsCraftingReagent = "C_Item.GetItemInfo 17th return",
        GetItemLinkByID = "C_Item.GetItemInfo 2nd return",
    },
    C_PetJournal = { GetPetLink = "C_PetJournal.GetBattlePetLink(petGUID)" },
    C_Mail = { SendMail = "SendMail" },
    C_PlayerInfo = { GetRaceInfo = "UnitSex / UnitRace" },
    C_AchievementInfo = { GetAchievementLink = "GetAchievementLink" },
    C_Container = { UseItemByGUID = "C_Container.UseContainerItem" },
    C_TradeSkillUI = {
        GetRecipeReagentInfo = "C_TradeSkillUI.GetRecipeSchematic",
        GetRecipeNumReagents = "C_TradeSkillUI.GetRecipeSchematic",
    },
    C_SpecializationInfo = { GetSpecPrimaryStat = "SPEC_MAIN_STAT / GetSpecializationInfo" },
    C_ItemUpgrade = { GetItemUpgradeCost = "C_ItemUpgrade.GetItemUpgradeItemInfo" },
    C_TaskQuest = { GetQuestsForPlayerByMapID = "C_TaskQuest.GetQuestsOnMap" },
}

local REMOVED_GLOBALS = {
    GetNumFactions = "C_Reputation.GetNumFactions",
    GetFactionInfo = "C_Reputation.GetFactionDataByIndex",
    GetSpellTexture = "C_Spell.GetSpellTexture",
    GetItemSpell = "C_Item.GetItemSpell",
    GetAddOnMetadata = "C_AddOns.GetAddOnMetadata",
    AddTrackedAchievement = "C_ContentTracking.ToggleTracking",
    RemoveTrackedAchievement = "C_ContentTracking.ToggleTracking",
    GetTrackedAchievements = "C_ContentTracking.IsTracking",
    UseContainerItem = "C_Container.UseContainerItem",
}

local function listFiles()
    local out = {}
    local p = io.popen('find "' .. ROOT .. '/Modules" "' .. ROOT .. '/Core.lua" -name "*.lua" 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    table.sort(out)
    return out
end

local function splitLines(src)
    local lines = {}
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    return lines
end

local function esc(s) return (s:gsub("%p", "%%%0")) end

local checkedFiles, failures = 0, {}
for _, path in ipairs(listFiles()) do
    local fh = io.open(path, "rb")
    local src = fh:read("*a")
    fh:close()
    checkedFiles = checkedFiles + 1
    -- Comments out (line count kept), strings kept for hook / _G["X"] forms, then a string-free copy.
    src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(c) return (c:gsub("[^\n]", "")) end)
    src = src:gsub("%-%-[^\n]*", "")
    local withStrings = splitLines(src)
    local code = splitLines((src:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")))
    local relPath = path:gsub("^" .. esc(ROOT) .. "/", "")

    local function fail(ln, what, replacement)
        failures[#failures + 1] = string.format("%s:%d  references removed %s (use %s)", relPath, ln, what, replacement)
    end

    for ln = 1, #code do
        local l, ls = code[ln], withStrings[ln]
        for ns, fns in pairs(REMOVED_NAMESPACED) do
            if l:find(ns, 1, true) then
                for fn, replacement in pairs(fns) do
                    if l:find("%f[%w_]" .. ns .. "%s*%.%s*" .. fn .. "%f[^%w_]")
                        or ls:find("%f[%w_]" .. ns .. "%s*,%s*[\"']" .. fn .. "[\"']")
                        or ls:find("%f[%w_]" .. ns .. "%s*%[%s*[\"']" .. fn .. "[\"']%s*%]") then
                        fail(ln, ns .. "." .. fn, replacement)
                    end
                end
            end
        end
        for name, replacement in pairs(REMOVED_GLOBALS) do
            if ls:find(name, 1, true) then
                local hit = l:find("_G%s*%.%s*" .. name .. "%f[^%w_]")
                    or ls:find("_G%s*%[%s*[\"']" .. name .. "[\"']%s*%]")
                    or ls:find("hooksecurefunc%(%s*[\"']" .. name .. "[\"']")
                if not hit then
                    -- Bare identifier: not a field / method of something else.
                    for pre in l:gmatch("([%.:%w_]?)%f[%w_]" .. name .. "%f[^%w_]") do
                        if pre ~= "." and pre ~= ":" then hit = true break end
                    end
                end
                if hit then fail(ln, name, replacement) end
            end
        end
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nFiles scanned: %d | Failures: %d", checkedFiles, #failures))
if checkedFiles == 0 then error("no files scanned under " .. ROOT) end
if #failures > 0 then
    error("Removed API reference lint failed with " .. #failures .. " failure(s).")
end
print("Removed API reference lint: ALL TESTS PASSED.")
