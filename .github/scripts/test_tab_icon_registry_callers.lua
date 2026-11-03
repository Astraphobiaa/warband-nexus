-- Behaviour test: tab icons and storage markers come from the addon icon registry (Media/Icon-*.tga),
-- never a Blizzard atlas / Interface\Icons file, and mono glyphs follow the theme tint on refresh.
-- Run from repo root: luajit <this file>
local ROOT = os.getenv("WN_ROOT") or "."
local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if cond then print("  ok   " .. msg) else failures = failures + 1; print("  FAIL " .. msg) end
end
local function read(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"))
    local t = fh:read("*a"); fh:close(); return t
end
local function load(rel, ns)
    local chunk = assert(loadstring(read(rel), "@" .. rel))
    chunk("WarbandNexus", ns)
end

local function FakeTex()
    local t = { calls = {} }
    t.SetTexture = function(self, f) self.texture = f; self.atlas = nil end
    t.SetAtlas = function(self, a) self.atlas = a; self.calls[#self.calls + 1] = { "SetAtlas", a }; return true end
    t.GetTexture = function(self) return self.texture end
    t.SetTexCoord = function() end
    t.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
    t.SetDesaturated = function() end
    t.SetPoint = function() end
    t.SetSnapToPixelGrid = function() end
    t.SetTexelSnappingBias = function() end
    return t
end
local function FakeFrame()
    local f = {}
    f.SetSize = function() end
    f.EnableMouse = function() end
    f.CreateTexture = function() return FakeTex() end
    return f
end

-- Theme glyph vertex under test control: dark = white-ish, light = dark ink.
local themeVertex = { 0.9, 0.9, 0.9 }
local function BaseNs()
    local ns = { Constants = {}, L = setmetatable({}, { __index = function(_, k) return k end }) }
    ns.UI_GetMonochromeIconVertex = function(a) return { themeVertex[1], themeVertex[2], themeVertex[3], a or 1 } end
    load("Modules/UI/IconRegistry.lua", ns)
    return ns
end
local function TitleCardNs()
    local ns = BaseNs()
    ns.UI = {}; ns.UI_ApplyVisuals = function() end; ns.UI_CreateCard = function() end
    ns.UITheme = { COLORS = {} }
    ns.UI_CreateFrame = function() return FakeFrame() end
    ns.refreshCalls = 0
    ns.UI_RefreshColors = function() ns.refreshCalls = ns.refreshCalls + 1 end
    load("Modules/UI/SharedWidgets_TitleCard.lua", ns)
    return ns
end

print("Phase 1: tab -> registry key (Easy Access menu rows, aliases)")
do
    local ns = TitleCardNs()
    local get = ns.UI_GetTabRegistryIconKey
    check(type(get) == "function", "UI_GetTabRegistryIconKey exported")
    get = get or function() return nil end
    check(get("characters") == "character" and get("chars") == "character", "characters/chars -> character")
    check(get("reputation") == "medal" and get("statistics") == "bar_chart", "reputation/statistics aliases resolve")
    check(get("storage") == "crate", "storage keeps its own crate key")
    load("Modules/VaultButton_Core.lua", ns)
    local defs = ns.VaultButton.LAUNCHER_ACTION_DEFS
    local missing = {}
    for id, def in pairs(defs) do
        if def.iconTab then
            local k = get(def.iconTab)
            if not (k and ns.UI_ICONS[k] and ns.UI_ICONS[k].file) then missing[#missing + 1] = id end
        end
    end
    check(#missing == 0, "every Easy Access iconTab row resolves to a registry icon file" .. (#missing > 0 and (" (missing: " .. table.concat(missing, ",") .. ")") or ""))
end

print("Phase 2: title card header icon = registry glyph, re-tinted on theme refresh")
do
    themeVertex = { 0.9, 0.9, 0.9 }
    local ns = TitleCardNs()
    local hdr = ns.UI_CreateHeaderIcon({}, nil, { tabKey = "reputation" })
    local icon = hdr.icon
    check(icon.texture == ns.UI_GetIconFile("medal") and #icon.calls == 0, "reputation header: registry Medal file, no SetAtlas")
    -- tab glyphs are colored illustrations: neutral vertex in both themes, never the mono glyph tint
    check(icon.vertex and icon.vertex[1] == 1, "colored header glyph keeps its own colors on the dark theme")
    themeVertex = { 0.1, 0.1, 0.1 }
    ns.UI_RefreshColors()
    check(ns.refreshCalls == 1, "theme refresh still runs the wrapped refresh")
    check(icon.vertex and icon.vertex[1] == 1, "colored header glyph keeps its own colors after a light theme refresh")
    local tracked = FakeTex()
    -- clock is still a mono key: a tracked mono icon is re-tinted on theme refresh
    ns.UI_SetIcon(tracked, "clock")
    if ns.UI_TrackRegistryIconTint then ns.UI_TrackRegistryIconTint(tracked, "clock") end
    themeVertex = { 0.9, 0.9, 0.9 }
    ns.UI_RefreshColors()
    check(tracked.vertex[1] == 0.9 and tracked.texture == ns.UI_GetIconFile("clock"), "tracked sub-tab/menu icon re-tinted, same file")
end

print("Phase 3: tooltip item-count markers are registry markup with the theme tint")
do
    local stubOk = pcall(dofile, ".github/scripts/wow_stub.lua")
    check(stubOk, "wow_stub loads")
    themeVertex = { 1, 1, 1 }
    local ns = BaseNs()
    local WN = {}
    WN.GetDetailedItemCountsFast = function()
        return {
            characters = { { isLiveSession = true, charName = "Live", bagCount = 2, bankCount = 3, classFile = "MAGE" } },
            warbandBank = 4,
            guilds = { { guildName = "G", count = 5 } },
        }
    end
    ns.WarbandNexus = WN
    _G.WarbandNexus = WN
    load("Modules/TooltipService_GameTooltip.lua", ns)
    local GT = ns.TooltipGameTooltip
    local function joined()
        local rows = GT.BuildWNItemCountRows(100, false, true) or {}
        local parts = {}
        for i = 1, #rows do
            local r = rows[i]
            parts[#parts + 1] = tostring(r.left or r.label or "") .. "|" .. tostring(r.right or r.rightText or "")
        end
        return table.concat(parts, "\n")
    end
    local dark = joined()
    for _, key in ipairs({ "bag", "vault", "warband", "guild" }) do
        local file = ns.UI_GetIconFile(key)
        local small = ns.UI_SmallIconFile(file)  -- 16 px markup draws the 32 px copy
        check(type(file) == "string" and ns.UI_IsAddonMediaTexture(file) and dark:find("|T" .. small .. ":16:16", 1, true) ~= nil,
            "marker '" .. key .. "' is the registry Media file at 16x16")
    end
    check(not dark:find("|A:", 1, true) and not dark:find("Banker", 1, true) and not dark:find("warbands-icon", 1, true),
        "no Blizzard atlas markup left in item-count rows")
    check(dark:find(":255:255:255|t", 1, true) ~= nil, "dark theme: white glyph tint in markup")
    themeVertex = { 0, 0, 0 }
    local light = joined()
    -- all four storage markers are colored: they keep their own colors on the light theme too
    for _, key in ipairs({ "bag", "vault", "warband", "guild" }) do
        check(light:find("|T" .. ns.UI_SmallIconFile(ns.UI_GetIconFile(key)) .. ":16:16:0:0:32:32:0:32:0:32:255:255:255|t", 1, true) ~= nil,
            "light theme: colored '" .. key .. "' marker keeps its own colors")
    end
    -- a mono key's markup follows the theme tint (no stale cache across a theme switch)
    local ck = ns.UI_SmallIconFile(ns.UI_GetIconFile("clock"))  -- 16 px markup draws the 32 px copy
    local lightClock = ns.UI_GetIconMarkup("clock", 16, 16)
    themeVertex = { 1, 1, 1 }
    local darkClock = ns.UI_GetIconMarkup("clock", 16, 16)
    check(lightClock:find("|T" .. ck .. ":16:16:0:0:32:32:0:32:0:32:0:0:0|t", 1, true) ~= nil
        and darkClock:find("|T" .. ck .. ":16:16:0:0:32:32:0:32:0:32:255:255:255|t", 1, true) ~= nil,
        "light theme: markup follows the new tint (no stale cache)")
end

print("Phase 4: converted call sites (source)")
do
    local function has(rel, s) return read(rel):find(s, 1, true) ~= nil end
    local callers = {
        "Modules/VaultButton.lua", "Modules/UI/SharedWidgets_EmptyState.lua", "Modules/UI/SettingsUI_Shell.lua",
        "Modules/UI/InformationDialog.lua", "Modules/UI/GearUI.lua", "Modules/UI/UI_MainShell.lua",
    }
    for i = 1, #callers do
        check(not has(callers[i], "UI_GetTabIcon"), callers[i] .. ": no UI_GetTabIcon caller left")
    end
    -- every empty state (reputation included) now maps to a registry key through EMPTY_STATE_ICON_KEYS
    check(has("Modules/UI/SharedWidgets_EmptyState.lua", 'reputation = "medal"')
        and has("Modules/UI/SharedWidgets_EmptyState.lua", "ns.UI_SetIcon(tex, registryIconKey)"), "Reputation empty state: registry glyph")
    check(has("Modules/UI/InformationDialog.lua", "ns.UI_ApplyMainNavTabGlyph(icon, entry.tab)"), "Information feature cards: registry glyph")
    local items = read("Modules/UI/ItemsUI.lua")
    check(items:find('key = "inventory",[^\n]*iconKey = "bag"') and items:find('key = "personal",[^\n]*iconKey = "vault"')
        and items:find('key = "warband",[^\n]*iconKey = "warband"') and items:find('key = "guild",[^\n]*iconKey = "guild"'),
        "Items sub-tabs: bag / vault / warband / guild registry keys")
    check(not items:find("INV_Misc_Bag_07", 1, true) and not items:find('iconAtlas = "warbands-icon"', 1, true), "Items sub-tabs: no Blizzard icon/atlas")
    check(not has("Modules/UI/CharactersUI.lua", '"warbands-icon"') and has("Modules/UI/CharactersUI.lua", 'ns.UI_SetIcon(wbIconTex, "warband")'),
        "Warband gold card: registry warband glyph")
end

print(string.format("Total: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
