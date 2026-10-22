#!/usr/bin/env lua
--[[
    Regression test: custom tooltip colours follow the theme, and C_TooltipInfo text that may be secret is
    not parsed.

    RenderCustomTooltip handed caller colours (`line.color`, `leftColor`, `rightColor`, `titleAffixPair`)
    straight to the frame. ~40 callers pass fixed dark-theme RGB ({1,1,1}, {0.9,0.9,0.9}), so in light
    mode PvE / Characters / Professions / Reputation tooltips showed white text on a light card. The item
    path already remapped Blizzard line colours; `underTitleLines` and `additionalLines` did not.
    Since 2026-10-22 every caller colour goes through the same remap (ns.UI_RemapGameTooltipLineColor),
    which is a pass-through in dark mode.

    Also (2026-10-22): the crafting-quality scan ran tonumber() / :match() on surfaced line fields and
    line text without a secret check; the item body compared leftText / rightText with "" unguarded.

    Loads the shipped Modules/TooltipService.lua under wow_stub.lua. The remap is the shipped
    ThemeAPI.RemapGameTooltipLineColor, extracted from SharedWidgets_Theme.lua with loadstring.
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

-- Shipped remap, with the theme reduced to the light / dark text roles from SharedWidgets_Theme.lua.
local LIGHT = false
local ROLES = {
    dark = { Bright = { 1, 1, 1 }, Normal = { 0.85, 0.85, 0.85 }, Muted = { 0.70, 0.70, 0.72 }, Dim = { 0.55, 0.55, 0.55 } },
    light = { Bright = { 0.12, 0.12, 0.14 }, Normal = { 0.24, 0.24, 0.28 }, Muted = { 0.38, 0.38, 0.42 }, Dim = { 0.50, 0.50, 0.54 } },
}
local function RoleRGB(role)
    local c = ROLES[LIGHT and "light" or "dark"][role]
    return c[1], c[2], c[3]
end
local remapSrc = ReadFile("Modules/UI/SharedWidgets_Theme.lua"):match("(function ThemeAPI%.RemapGameTooltipLineColor%(r, g, b%).-\nend)\n")
assert(remapSrc, "RemapGameTooltipLineColor not found in SharedWidgets_Theme.lua")
local remapChunk = assert(loadstring("local ThemeAPI, IsLightModeEnabled = ...\n" .. remapSrc
    .. "\nreturn ThemeAPI.RemapGameTooltipLineColor", "@RemapGameTooltipLineColor"))
local ThemeAPI = {
    GetTextRoleRGB = RoleRGB,
    GetSemanticGoldColor = function() if LIGHT then return 0.55, 0.40, 0.05 end return 1, 0.82, 0 end,
}
local Remap = remapChunk(ThemeAPI, function() return LIGHT end)

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { showTooltipItemID = false }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.TooltipGameTooltip = { Install = function() end }
ns.UI_RemapGameTooltipLineColor = Remap
ns.UI_GetTextRoleRGB = RoleRGB
ns.UI_GetTooltipLabelColor = function() return RoleRGB("Muted") end
ns.UI_GetTooltipBodyColor = function() return RoleRGB("Normal") end
ns.UI_GetTooltipDescColor = function() return RoleRGB("Muted") end
ns.UI_GetSemanticGoldColor = ThemeAPI.GetSemanticGoldColor
ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93 } }
Enum.TooltipDataLineType = { ItemEnchantmentPermanent = 15 }
local tooltipLinesByLink = {}
C_TooltipInfo = {
    GetHyperlink = function(link) return tooltipLinesByLink[link] end,
    GetItemByID = function(id) return tooltipLinesByLink[id] end,
}

local chunk = assert(loadstring(ReadFile("Modules/TooltipService.lua"), "@Modules/TooltipService.lua"))
chunk("WarbandNexus", ns)
local TS = assert(ns.TooltipService, "TooltipService not exported")

-- Records every Add* / Set* call as "Method|text|r,g,b..." with %.3f numbers.
local function NewFrame()
    local calls = {}
    local frame = { calls = calls }
    local function rec(name)
        frame[name] = function(_, text, ...)
            local parts = { name, tostring(text) }
            local n = select("#", ...)
            for i = 1, n do
                local v = select(i, ...)
                if type(v) == "number" then parts[#parts + 1] = string.format("%.3f", v)
                elseif type(v) ~= "table" then parts[#parts + 1] = tostring(v) end
            end
            calls[#calls + 1] = table.concat(parts, "|")
        end
    end
    for _, m in ipairs({ "SetIcon", "SetTitle", "SetDescription", "AddTitleAffixPair", "AddSectionLabel",
        "AddCenteredLine", "AddDoubleLine", "AddLine", "AddTitleAffix", "AddSpacer", "AddBodyDivider" }) do
        rec(m)
    end
    return frame
end

local function find(frame, prefix)
    for i = 1, #frame.calls do
        if frame.calls[i]:sub(1, #prefix) == prefix then return frame.calls[i] end
    end
    return nil
end

local WHITE, SOFT = { 1, 1, 1 }, { 0.9, 0.9, 0.9 }
local customData = {
    title = "T",
    titleAffixPair = { left = "AL", right = "AR", leftColor = WHITE, rightColor = SOFT },
    lines = {
        { type = "section_label", text = "SL", color = WHITE },
        { type = "centered", text = "CE", color = WHITE },
        { left = "DL", right = "DR", leftColor = WHITE, rightColor = SOFT },
        { left = "SG", leftColor = WHITE },
        { text = "TX", color = SOFT },
        { text = "PU", color = { 0.6, 0.4, 0.8 } },
    },
}

print("Phase 1: dark mode passes caller colours through unchanged")
do
    LIGHT = false
    local f = NewFrame()
    TS:RenderCustomTooltip(f, customData)
    assert_eq(find(f, "AddTitleAffixPair|AL"), "AddTitleAffixPair|AL|AR|1.000|1.000|1.000|0.900|0.900|0.900", "dark: title affix pair")
    assert_eq(find(f, "AddSectionLabel|SL"), "AddSectionLabel|SL|1.000|1.000|1.000", "dark: section label")
    assert_eq(find(f, "AddCenteredLine|CE"), "AddCenteredLine|CE|1.000|1.000|1.000", "dark: centered line")
    assert_eq(find(f, "AddDoubleLine|DL"), "AddDoubleLine|DL|DR|1.000|1.000|1.000|0.900|0.900|0.900", "dark: double line")
    assert_eq(find(f, "AddLine|SG"), "AddLine|SG|1.000|1.000|1.000|false", "dark: left-only line")
    assert_eq(find(f, "AddLine|TX"), "AddLine|TX|0.900|0.900|0.900|false", "dark: text line")
    -- Byte-identical: the remap returns the very same numbers in dark mode.
    local r, g, b = Remap(0.123456789, 0.987654321, 0.5)
    assert_eq(r == 0.123456789 and g == 0.987654321 and b == 0.5, true, "dark: remap is an exact pass-through")
end

print("Phase 2: light mode remaps white / near-white caller colours to theme ink")
do
    LIGHT = true
    local f = NewFrame()
    TS:RenderCustomTooltip(f, customData)
    assert_eq(find(f, "AddTitleAffixPair|AL"), "AddTitleAffixPair|AL|AR|0.120|0.120|0.140|0.120|0.120|0.140", "light: title affix pair")
    assert_eq(find(f, "AddSectionLabel|SL"), "AddSectionLabel|SL|0.120|0.120|0.140", "light: section label")
    assert_eq(find(f, "AddCenteredLine|CE"), "AddCenteredLine|CE|0.120|0.120|0.140", "light: centered line")
    assert_eq(find(f, "AddDoubleLine|DL"), "AddDoubleLine|DL|DR|0.120|0.120|0.140|0.120|0.120|0.140", "light: double line")
    assert_eq(find(f, "AddLine|SG"), "AddLine|SG|0.120|0.120|0.140|false", "light: left-only line")
    assert_eq(find(f, "AddLine|TX"), "AddLine|TX|0.120|0.120|0.140|false", "light: text line")
    assert_eq(find(f, "AddLine|PU"), "AddLine|PU|0.600|0.400|0.800|false", "light: saturated colour kept")
end

print("Phase 3: item tooltip underTitleLines / additionalLines use the remap")
do
    tooltipLinesByLink[5001] = { lines = { { leftText = "Item Title" }, { leftText = "Body" } } }
    local itemData = { itemID = 5001, underTitleLines = { { text = "UT", color = WHITE } },
        additionalLines = { { text = "AD", color = WHITE }, { left = "AX", right = "AY", leftColor = WHITE, rightColor = SOFT } } }
    LIGHT = true
    local f = NewFrame()
    TS:RenderItemTooltip(f, itemData)
    assert_eq(find(f, "AddTitleAffix|UT"), "AddTitleAffix|UT|0.120|0.120|0.140|false", "light: under-title line remapped")
    assert_eq(find(f, "AddLine|AD"), "AddLine|AD|0.120|0.120|0.140|false", "light: additional line remapped")
    assert_eq(find(f, "AddDoubleLine|AX"), "AddDoubleLine|AX|AY|0.120|0.120|0.140|0.120|0.120|0.140", "light: additional double line remapped")
    LIGHT = false
    f = NewFrame()
    TS:RenderItemTooltip(f, itemData)
    assert_eq(find(f, "AddTitleAffix|UT"), "AddTitleAffix|UT|1.000|1.000|1.000|false", "dark: under-title line unchanged")
    assert_eq(find(f, "AddLine|AD"), "AddLine|AD|1.000|1.000|1.000|false", "dark: additional line unchanged")
end

print("Phase 4: secret tooltip fields are not parsed for the crafting tier")
do
    local Tier = assert(ns.UI_GetEnchantmentCraftingQualityTierFromItemLink, "enchant tier export missing")
    tooltipLinesByLink["|Hitem:1:plain|h"] = { lines = { { type = 15, craftingQuality = "2" } } }
    assert_eq(Tier("|Hitem:1:plain|h"), 2, "plain craftingQuality field is read")
    local secretTier = stub.MarkSecret("3")
    tooltipLinesByLink["|Hitem:2:secretfield|h"] = { lines = { { type = 15, craftingQuality = secretTier } } }
    assert_eq(Tier("|Hitem:2:secretfield|h"), nil, "secret craftingQuality is not passed to tonumber")
    local secretText = stub.MarkSecret("x |A:Professions-ChatIcon-Quality-Tier2:0:0|a")
    tooltipLinesByLink["|Hitem:3:secrettext|h"] = { lines = { { type = 15, leftText = secretText } } }
    assert_eq(Tier("|Hitem:3:secrettext|h"), nil, "secret line text is not matched for an atlas tier")
    stub.ClearSecrets()
end

print("Phase 5: item body blank test never compares possibly-secret line text")
do
    local src = ReadFile("Modules/TooltipService.lua")
    local body = src:match("function TooltipService:RenderItemTooltip%(frame, data%)(.-)\nfunction TooltipService:")
    assert_eq(body ~= nil, true, "RenderItemTooltip body found")
    body = (body or ""):gsub("%-%-[^\n]*", "")
    assert_eq(body:find('leftText%s*[~=]=%s*""') == nil, true, "no raw leftText compare with \"\"")
    assert_eq(body:find('rightText%s*[~=]=%s*""') == nil, true, "no raw rightText compare with \"\"")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Tooltip custom colour suite failed with " .. failed .. " failure(s).")
end
print("Tooltip custom colour suite: ALL TESTS PASSED.")
