#!/usr/bin/env lua
--[[
    Regression test: a value is checked with issecretvalue BEFORE it is compared.

    CLAUDE.md: never compare secret values with ==, ~= or `not`. `x ~= nil and issecretvalue(x)` and
    `x ~= "" ...; if issecretvalue(x)` compare first. issecretvalue(nil) is false, so the secret check
    can always go first without changing behaviour. Found 2026-10-22 in 13 places, including
    ProfessionService's central SafeAPIString helper (`value ~= ""` ran before its secret check) and
    three ProfessionService sites that stored / compared raw API names.

    Static scan (Modules/**/*.lua and Core.lua):
      - the exact pattern `X ~= nil and [issecretvalue and] issecretvalue(X)` /
        `X ~= nil and not (issecretvalue and issecretvalue(X))` (13 sites fixed, none may come back);
      - Modules/ProfessionService.lua: no comparison of X with nil or "" before issecretvalue(X) on
        the same line, and SafeAPIString checks issecretvalue first;
      - every file (enforced 2026-10-22, 99 sites fixed): on a line that calls issecretvalue(X), nothing
        before that call may compare X with nil or "" (either operand order), or pass X to tonumber /
        tostring, call a method on X, or take #X. Rewrites keep the result for non-secret values, e.g.
        `x ~= "" and not (issecretvalue and issecretvalue(x))` -> `not (issecretvalue and
        issecretvalue(x)) and x ~= ""`, `x == "" or (issecretvalue and issecretvalue(x))` ->
        `(issecretvalue and issecretvalue(x)) or x == ""`. Truthiness (`x and`, `not x`) and type(x)
        are not flagged.
    Plus pinned sites (PINNED below) where the whole block is checked, not one line, and the two-line
    order (TWO_LINE_ALLOW below): the same unsafe uses on one of the 1-3 lines above issecretvalue(X).
]]

local ROOT = os.getenv("WN_ROOT") or "."
local p = io.popen('find "' .. ROOT .. '/Modules" -name "*.lua" 2>/dev/null')
local files = { ROOT .. "/Core.lua" }
for line in p:lines() do files[#files + 1] = line end
p:close()

-- Uses of `esc` (an escaped variable name) that must not come before its secret check.
local function FirstUnsafeUse(pre, esc)
    local v = "%f[%w_%.]" .. esc .. "%f[^%w_%.]"
    local at
    local patterns = {
        v .. "%s*[~=]=%s*nil%f[^%w_]", v .. '%s*[~=]=%s*""', "%f[%w_]nil%s*[~=]=%s*" .. v, '""%s*[~=]=%s*' .. v,
        "tonumber%(%s*" .. v, "tostring%(%s*" .. v, v .. "%s*:%s*[%a_]", "#%s*" .. v,
    }
    for i = 1, #patterns do
        local hit = pre:find(patterns[i])
        if hit and (not at or hit < at) then at = hit end
    end
    return at
end

local checked, failures = 0, {}
for _, path in ipairs(files) do
    local fh = io.open(path, "rb")
    local ln = 0
    for line in fh:lines() do
        ln = ln + 1
        local code = line:gsub("%-%-.*$", "")
        for var in code:gmatch("issecretvalue%(%s*([%w_%.]+)%s*%)") do
            checked = checked + 1
            local esc = var:gsub("%p", "%%%0")
            local secretAt = code:find("issecretvalue%(%s*" .. esc .. "%s*%)")
            local isProfession = path:find("ProfessionService[%w_]*%.lua$") ~= nil
            local cmpAt
            if isProfession then
                cmpAt = code:find("%f[%w_%.]" .. esc .. "%s*[~=]=%s*nil") or code:find("%f[%w_%.]" .. esc .. '%s*[~=]=%s*""')
            else
                cmpAt = code:find("%f[%w_%.]" .. esc .. "%s*~=%s*nil%s+and%s+not%s+%(issecretvalue")
                    or code:find("%f[%w_%.]" .. esc .. "%s*~=%s*nil%s+and%s+issecretvalue")
                    or code:find("issecretvalue%s+and%s+" .. esc .. "%s*~=%s*nil%s+and")
            end
            if cmpAt and secretAt and cmpAt < secretAt then
                failures[#failures + 1] = string.format("%s:%d  `%s` is compared before issecretvalue(%s)",
                    path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", ""), ln, var, var)
            elseif secretAt and FirstUnsafeUse(code:sub(1, secretAt - 1), esc) then
                failures[#failures + 1] = string.format("%s:%d  `%s` is compared / converted before issecretvalue(%s)",
                    path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", ""), ln, var, var)
            end
        end
    end
    fh:close()
end

-- Two-line order (added 2026-10-22): a compare / tonumber / tostring / method / # on X in one of the
-- 1-3 lines above `issecretvalue(X)` runs before the guard just like the same-line case. The scan walks
-- up from the issecretvalue line and stops at a line that already checks issecretvalue(X) or opens a
-- function. TryCounterService_Handlers compared the ENCOUNTER_START / BOSS_KILL / ENCOUNTER_END name
-- with "" one line before its secret check, so a secret name errored the handler and lost the try.
-- TODO(other fix packages): the files below still carry this pattern (hit counts on 2026-10-22, after
-- the Utilities / ReminderService / TooltipService / Profiler / UIMapContentKind / TryCounter fixes).
-- Fixing one lowers its count; a file may not go above its count and files not listed must stay at 0.
-- Includes ProfessionService.lua (SafeAPIString caller ~64) and CurrencyCacheService.lua (~15, ~29).
local TWO_LINE_ALLOW = {
    ["Modules/AchievementFrameIntegration.lua"] = 2,
    ["Modules/CharacterService.lua"] = 2,
    ["Modules/ChatMessageService.lua"] = 1,
    ["Modules/CollectionService.lua"] = 5,
    ["Modules/CollectionService_JournalScan.lua"] = 1,
    ["Modules/CollectionService_Scan.lua"] = 1,
    ["Modules/Data/ReminderContentIndex.lua"] = 1,
    ["Modules/Data/ReminderMidnightFactionEmissaryData.lua"] = 1,
    ["Modules/Data/ReminderZoneCatalog.lua"] = 4,
    ["Modules/DataService_RosterHelpers.lua"] = 2,
    ["Modules/GearService.lua"] = 10,
    ["Modules/ItemsCacheService.lua"] = 3,
    ["Modules/MailSnapshotService.lua"] = 5,
    ["Modules/MigrationService.lua"] = 8,
    ["Modules/NotificationManager.lua"] = 9,
    ["Modules/NotificationManager_Tests.lua"] = 3,
    ["Modules/PvECacheService.lua"] = 6,
    ["Modules/PvPService.lua"] = 3,
    ["Modules/ReputationCacheService.lua"] = 3,
    ["Modules/ReputationScanner.lua"] = 2,
    ["Modules/TooltipService_GameTooltip.lua"] = 2,
    ["Modules/TryCounterService.lua"] = 2,
    ["Modules/TryCounterService_Debug.lua"] = 2,
    ["Modules/TryCounterService_LootSession.lua"] = 1,
    ["Modules/UI.lua"] = 1,
    ["Modules/UI/AchievementCriteriaHelpers.lua"] = 2,
    ["Modules/UI/CharacterBankMoneyLogPopup.lua"] = 3,
    ["Modules/UI/CharacterTrackingDialog.lua"] = 1,
    ["Modules/UI/CharactersUI.lua"] = 1,
    ["Modules/UI/CollectionsUI_Model.lua"] = 6,
    ["Modules/UI/CollectionsUI_Recent.lua"] = 1,
    ["Modules/UI/CollectionsUI_Shared.lua"] = 9,
    ["Modules/UI/CollectionsUI_SourceData.lua"] = 1,
    ["Modules/UI/CurrencyUI.lua"] = 1,
    ["Modules/UI/FormatHelpers.lua"] = 2,
    ["Modules/UI/GearUI.lua"] = 3,
    ["Modules/UI/GearUI_Chrome.lua"] = 1,
    ["Modules/UI/GearUI_Paperdoll.lua"] = 8,
    ["Modules/UI/GoldManagementPopup.lua"] = 1,
    ["Modules/UI/ItemsUI.lua"] = 3,
    ["Modules/UI/MailDetailsPopup.lua"] = 1,
    ["Modules/UI/PlanCardFactory.lua"] = 1,
    ["Modules/UI/PlansTrackerWindow.lua"] = 3,
    ["Modules/UI/PlansUI.lua"] = 1,
    ["Modules/UI/PlansUI_Browse.lua"] = 1,
    ["Modules/UI/PlansUI_SourceParser.lua"] = 1,
    ["Modules/UI/ProfessionsUI.lua"] = 6,
    ["Modules/UI/PvEUI.lua"] = 3,
    ["Modules/UI/PvEUI_VaultGrid.lua"] = 2,
    ["Modules/UI/PvPUI_Overview.lua"] = 2,
    ["Modules/UI/ReminderSetAlertDialog.lua"] = 1,
    ["Modules/UI/ReminderSetAlertDialog_Helpers.lua"] = 1,
    ["Modules/UI/ReputationUI.lua"] = 3,
    ["Modules/UI/SearchBoxComponent.lua"] = 1,
    ["Modules/UI/SearchResultsRenderer.lua"] = 1,
    ["Modules/UI/SharedWidgets.lua"] = 3,
    ["Modules/UI/SharedWidgets_Icons.lua"] = 1,
    ["Modules/UI/SharedWidgets_PlansLayout.lua"] = 1,
    ["Modules/UI/SharedWidgets_Search.lua"] = 2,
    ["Modules/UI/SharedWidgets_Theme.lua"] = 1,
    ["Modules/UI/SharedWidgets_TitleCard.lua"] = 2,
    ["Modules/VaultButton_Tooltip.lua"] = 2,
    ["Modules/VaultScanner.lua"] = 1,
}
local twoLineHits = {}
for _, path in ipairs(files) do
    local rel = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    local lines = {}
    for l in io.lines(path) do lines[#lines + 1] = (l:gsub("%-%-.*$", "")) end
    for i = 1, #lines do
        for var in lines[i]:gmatch("issecretvalue%(%s*([%w_%.]+)%s*%)") do
            local esc = var:gsub("%p", "%%%0")
            for k = i - 1, math.max(1, i - 3), -1 do
                local prev = lines[k]
                if prev:find("issecretvalue%(%s*" .. esc .. "%s*%)") or prev:find("%f[%w_]function%f[^%w_]") then break end
                if FirstUnsafeUse(prev, esc) then
                    twoLineHits[rel] = twoLineHits[rel] or {}
                    local list = twoLineHits[rel]
                    list[#list + 1] = string.format("%s:%d  `%s` is compared / converted on line %d, before issecretvalue(%s)",
                        rel, k, var, k, var)
                    break
                end
            end
        end
    end
end
for _, path in ipairs(files) do
    local rel = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    local list = twoLineHits[rel] or {}
    local allowed = TWO_LINE_ALLOW[rel] or 0
    checked = checked + 1
    if #list > allowed then
        for j = 1, #list do failures[#failures + 1] = list[j] end
        failures[#failures + 1] = string.format("%s  %d two-line secret-order hit(s), allow-list says %d", rel, #list, allowed)
    elseif #list < allowed then
        print(string.format("  note %s: %d two-line hit(s) left, allow-list says %d (lower it)", rel, #list, allowed))
    end
end

-- SafeAPIString (ProfessionService): its first statement must be the secret check.
do
    local fh = io.open(ROOT .. "/Modules/ProfessionService.lua", "rb")
    local src = fh:read("*a")
    fh:close()
    local body = src:match("local function SafeAPIString%(value%)(.-)\nend\n")
    checked = checked + 1
    local first = body and body:match("^%s*%-%-[^\n]*\n%s*([^\n]+)") or (body and body:match("^%s*([^\n]+)"))
    if not (first and first:find("issecretvalue", 1, true)) then
        failures[#failures + 1] = "Modules/ProfessionService.lua  SafeAPIString must check issecretvalue before any comparison"
    end
end

-- Pinned sites: inside the block that starts at `anchor`, the secret check on `var` comes before
-- the first other use of `var` (truthiness test, compare, tonumber). 2026-10-22: TooltipService ran
-- `not arg1` / tonumber(arg1) on TOOLTIP_DATA_UPDATE's dataInstanceID (number?, can be secret).
local PINNED = {
    { "Modules/TooltipService.lua", 'if event == "TOOLTIP_DATA_UPDATE" then', "arg1" },
    { "Modules/TooltipService.lua", 'if event == "GET_ITEM_INFO_RECEIVED" then', "arg1" },
    { "Modules/TooltipService.lua", 'if event == "GET_ITEM_INFO_RECEIVED" then', "arg2" },
    { "Modules/TooltipService.lua", "local instanceID = tooltipData and tooltipData.dataInstanceID", "instanceID" },
}
for i = 1, #PINNED do
    local rel, anchor, var = PINNED[i][1], PINNED[i][2], PINNED[i][3]
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    local src = fh and fh:read("*a"):gsub("\r\n", "\n"):gsub("%-%-[^\n]*", "") or ""
    if fh then fh:close() end
    checked = checked + 1
    local at = src:find(anchor, 1, true)
    if not at then
        failures[#failures + 1] = rel .. "  pinned anchor not found: " .. anchor
    else
        local block = src:sub(at + #anchor, at + #anchor + 600)
        local secretAt = block:find("issecretvalue%(" .. var .. "%)")
        local useAt = block:find("%f[%w_]" .. var .. "%f[^%w_]")
        while useAt and secretAt and useAt == secretAt + #"issecretvalue(" do
            useAt = block:find("%f[%w_]" .. var .. "%f[^%w_]", useAt + #var)
        end
        if not secretAt or (useAt and useAt < secretAt) then
            failures[#failures + 1] = string.format("%s  `%s` used before issecretvalue(%s) after: %s", rel, var, var, anchor)
        end
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("Secret check order suite failed with " .. #failures .. " failure(s).")
end
if checked < 50 then
    error("Secret check order suite matched too few issecretvalue calls (" .. checked .. "); the scanner is broken.")
end
print("Secret check order suite: ALL TESTS PASSED.")
