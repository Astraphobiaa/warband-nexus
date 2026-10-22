#!/usr/bin/env lua
--[[
    Regression test (static): tabs build their section chrome through SectionPool.

    Each tab below used to create its section wraps / bodies / collapsible headers with
    Factory:CreateContainer / CreateCollapsibleHeader on every redraw and park the previous ones in
    the recycle bin forever. For every adopted draw function this checks that:
      - every CreateCollapsibleHeader call gets SectionPool.HeaderOpts and is remembered;
      - no section wrap / body is created with Factory:CreateContainer directly;
      - teardown discards through SectionPool (no raw SetParent(recycleBin)).
    The pool itself is driven by test_section_pool.lua.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n"):gsub("%-%-[^\n]*", "")
    fh:close()
    return src
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end
local function count(s, pat)
    local n = 0
    for _ in s:gmatch(pat) do n = n + 1 end
    return n
end

-- { label, file, function header pattern, allowed direct CreateContainer calls (non-section chrome) }
local ADOPTED = {
    { "Currency", "Modules/UI/CurrencyUI.lua", "function WarbandNexus:DrawCurrencyList%(container, width%)" },
    { "Reputation", "Modules/UI/ReputationUI.lua", "function WarbandNexus:DrawReputationList%(container, width%)" },
    -- Characters: the two text blocks inside the persistent gold-card bundle (built once).
    { "Characters", "Modules/UI/CharactersUI.lua", "function WarbandNexus:DrawCharacterList%(parent%)", 2 },
    { "Collections", "Modules/UI/CollectionsUI_Lists.lua", "local function PopulateSectionedList%(cfg, scrollChild," },
    { "Professions", "Modules/UI/ProfessionsUI_DrawTab.lua", "function WarbandNexus:DrawProfessionsTab%(parent%)" },
    { "Items", "Modules/UI/ItemsUI.lua", "function WarbandNexus:DrawItemsResults%(parent, yOffset, width, currentItemsSubTab, itemsSearchText%)" },
}

for i = 1, #ADOPTED do
    local label, rel, head, allowCC = ADOPTED[i][1], ADOPTED[i][2], ADOPTED[i][3], ADOPTED[i][4] or 0
    local src = ReadFile(rel)
    local s = src:find(head)
    check(s ~= nil, label .. ": draw function found")
    if s then
        local body = src:sub(s, (src:find("\nfunction ", s + 1) or #src))
        local headers = count(body, "CreateCollapsibleHeader%(")
        check(headers > 0 and headers == count(body, "SP%.HeaderOpts%("),
            label .. ": every collapsible header goes through SectionPool.HeaderOpts (" .. headers .. ")")
        check(count(body, "SP%.Remember%(") == headers, label .. ": every pooled header is remembered")
        check(count(body, "CreateContainer%(") == allowCC, label .. ": no direct Factory:CreateContainer for section chrome")
        check(body:find("SetParent%(recycleBin") == nil and body:find("SetParent%(bin%)") == nil,
            label .. ": no raw recycle-bin parking")
        check(body:find("SP.BeginPass(", 1, true) ~= nil, label .. ": teardown starts a SectionPool pass")
    end
end

-- Shared results container teardown keeps pooled sections in place and marks the rest as garbage.
do
    local src = ReadFile("Modules/UI/SearchResultsRenderer.lua")
    local prep = src:match("function SearchResultsRenderer:PrepareContainer%(container%)(.-)\nend\n")
    check(prep and prep:find("child._wnSectionPooled", 1, true) ~= nil, "PrepareContainer keeps SectionPool frames in place")
    check(prep and prep:find("UI_SectionPool.Discard(child)", 1, true) ~= nil, "PrepareContainer discards through SectionPool")
end

-- Plans teardown (chrome not pooled yet: quest rows need their own pool) at least marks its garbage.
do
    local src = ReadFile("Modules/UI/PlansUI.lua")
    check(src:find("ns.UI_SectionPool.Discard(child)", 1, true) ~= nil, "Plans teardown discards through SectionPool")
end

-- Characters: per-paint labels on pooled headers / content frames are cached, not recreated.
do
    local src = ReadFile("Modules/UI/CharactersUI.lua")
    check(count(src, 'FontManager:CreateFontString%(%w+Header, FontManager:GetFontRole%("sectionHeaderCount"%)') == 0
        and src:find("headerFrame._wnSectionCountFs = fs", 1, true) ~= nil,
        "Characters: section count labels come from the cached SectionCountFS")
    check(src:find("contentFrame._wnEmptyText", 1, true) ~= nil, "Characters: empty-section text is cached on the content frame")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Section pool adoption suite failed with " .. failed .. " failure(s).")
end
print("Section pool adoption suite: ALL TESTS PASSED.")
