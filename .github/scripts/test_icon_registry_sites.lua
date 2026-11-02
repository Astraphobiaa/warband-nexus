-- Behaviour test: UI glyphs in the converted sites come from the addon icon registry, not Blizzard atlases.
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
    local function rec(name) return function(self, ...) self.calls[#self.calls + 1] = { name, ... } end end
    t.SetTexture = function(self, f, ...) self.texture = f; self.atlas = nil; rec("SetTexture")(self, f, ...) end
    t.SetAtlas = function(self, a) self.atlas = a; self.calls[#self.calls + 1] = { "SetAtlas", a }; return true end
    t.GetTexture = function(self) return self.texture end
    t.SetTexCoord = rec("SetTexCoord")
    t.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
    t.SetDesaturated = rec("SetDesaturated")
    t.Show = rec("Show"); t.Hide = rec("Hide")
    return t
end
local function used(tex, name)
    for i = 1, #tex.calls do if tex.calls[i][1] == name then return true end end
    return false
end

local function BaseNs()
    local ns = { Constants = {}, L = setmetatable({}, { __index = function(_, k) return k end }) }
    ns.UI_GetMonochromeIconVertex = function(a) return { 0.1, 0.1, 0.1, a or 1 } end
    load("Modules/UI/IconRegistry.lua", ns)
    return ns
end

print("Phase 1: title card / nav settings glyph uses the registry")
do
    local ns = BaseNs()
    ns.UI = {}; ns.UI_ApplyVisuals = function() end; ns.UI_CreateCard = function() end
    ns.UITheme = { COLORS = {} }
    load("Modules/UI/SharedWidgets_TitleCard.lua", ns)
    check(ns.UI_GetTabIcon("settings") == nil, "UI_GetTabIcon('settings') gives no Blizzard atlas")
    local tex = FakeTex()
    ns.UI_ApplyMainNavTabGlyph(tex, "settings")
    check(tex.texture == ns.UI_GetIconFile("settings") and not used(tex, "SetAtlas"),
        "settings nav glyph is the registry Settings file, no SetAtlas")
    check(tex.vertex and tex.vertex[1] == 0.1, "settings nav glyph carries the mono theme vertex")
    local other = FakeTex()
    ns.UI_ApplyMainNavTabGlyph(other, "items")
    check(other.atlas == "Banker" and other._wnRegistryIcon == nil, "other tabs keep their atlas, no registry flag")
end

print("Phase 2: Easy Access launcher / status icons")
do
    local ns = BaseNs()
    load("Modules/VaultButton_Core.lua", ns)
    local VB = ns.VaultButton
    local def = VB.LAUNCHER_ACTION_DEFS.settings
    check(def.iconAtlas == nil, "settings launcher row has no Blizzard atlas")
    check(def.icon == ns.UI_GetIconFile("settings"), "settings launcher row icon is the registry Settings file")
    check(VB.EA_STATUS_ICON == ns.UI_GetIconFile("status_ok"), "Easy Access status icon is the registry StatusOk file")
end

print("Phase 3: Collections default category icon")
do
    local ns = BaseNs()
    load("Modules/UI/CollectionsUI_SourceData.lua", ns)
    local SD = ns.CollectionsUI_SourceData
    check(SD.GetMountCategoryIcon("no-such-category") == nil, "unknown mount category: nil (header draws registry attention)")
    check(SD.GetToyCategoryIcon("no-such-category") == nil, "unknown toy category: nil")
end

print("Phase 4: converted call sites (source)")
do
    local function has(rel, s) return read(rel):find(s, 1, true) ~= nil end
    check(not has("Modules/UI/SharedWidgets_Factory.lua", 'SetAtlas("common-icon-offscreen"'), "Factory: no common-icon-offscreen atlas")
    check(select(2, read("Modules/UI/SharedWidgets_Factory.lua"):gsub('UI_SetIcon%(%a+Icon, "arrow_left"%)', "")) == 4, "Factory: 4 scroll arrows via arrow_left")
    check(has("Modules/UI/GoldManagementPopup.lua", 'ns.UI_SetIcon(goldIcon, "money_gold")'), "Gold popup coin via money_gold")
    check(has("Modules/UI/SharedWidgets_StateCards.lua", 'ns.UI_GetIconFile("warning"), 24, false'), "Error card warning via registry file")
    check(not has("Modules/UI/SharedWidgets_Search.lua", "communities-icon-lock") and has("Modules/UI/SharedWidgets_Search.lua", 'ns.UI_SetIcon(nt, "lock")'), "Search lock button via registry")
    check(not has("Modules/UI/SharedWidgets_Search.lua", "communities-icon-addgroupplus"), "Search add button: no addgroupplus atlas")
    check(not has("Modules/VaultButton_Table.lua", "mechagon-projects"), "Vault table settings: no mechagon atlas")
    check(not has("Modules/VaultButton_Tooltip.lua", '"coin-gold"'), "Vault tooltip gold label: no coin-gold atlas")
    check(not has("Modules/UI/PvEUI_BodyPaint.lua", "ReadyCheck-Ready"), "PvE status column: no ReadyCheck file")
end

print(string.format("Total: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
