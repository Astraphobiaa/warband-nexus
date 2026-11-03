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
    -- every main tab is on the registry now; storage keeps its own crate glyph instead of the items one
    for _, pair in ipairs({ { "items", "bag" }, { "storage", "crate" }, { "reputation", "medal" }, { "characters", "character" } }) do
        local t = FakeTex()
        ns.UI_ApplyMainNavTabGlyph(t, pair[1])
        check(ns.UI_GetTabIcon(pair[1]) == nil and t._wnRegistryIcon == pair[2] and not used(t, "SetAtlas"),
            pair[1] .. " tab uses the registry " .. pair[2] .. " glyph, no Blizzard atlas")
    end
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
    check(not has("Modules/UI/CharactersUI_Row.lua", '"AllianceEmblem"') and has("Modules/UI/CharactersUI_Row.lua", 'ns.UI_SetIcon(row.factionIcon, "faction_alliance")')
        and has("Modules/UI/CharactersUI_Row.lua", 'ns.UI_SetIcon(row.factionIcon, "faction_horde")'), "Character row faction column via registry emblems")
    check(not has("Modules/UI/SharedWidgets_Icons.lua", "PlusManz-") and has("Modules/UI/SharedWidgets_Icons.lua", 'ns.UI_GetIconFile("faction_horde")'), "GetFactionIcon: registry emblems, no PlusManz files")
    local tc = "Modules/UI/SharedWidgets_TitleCard.lua"
    check(not has(tc, "TAB_HEADER_ICONS") and not has(tc, "TAB_NAV_TEXTURE_FALLBACK") and not has(tc, "AssaultsMapBanner"),
        "TitleCard: no Blizzard tab atlas or Interface\\Icons fallback tables")
    check(not has(tc, "honorsystem-icon-prestige") and has(tc, 'ns.UI_GetIconFile("character")'), "Character-specific headers use the registry character icon")
    check(not has(tc, "INV_Misc_QuestionMark") and not has("Modules/UI/SharedWidgets_Icons.lua", "INV_Misc_QuestionMark"),
        "Unknown tab / failed atlas fall back to the registry question icon")
    check(has("Modules/UI/SharedWidgets_Icons.lua", "if isAtlas and not (ns.UI_IsAddonMediaTexture"), "CreateIcon draws addon media as a file even with isAtlas")
    local pcf = "Modules/UI/PlanCardFactory.lua"
    check(has(pcf, 'illusion = "illusion"') and has(pcf, 'title = "title"') and has(pcf, 'mount = "book"') and not has(pcf, "dragon-rostrum")
        and not has(pcf, "UpgradeItem-32x32") and not has(pcf, "poi-legendsoftheharanir") and not has(pcf, "CreationCatalyst"),
        "Plan type icons are registry keys (no Blizzard type atlases)")
    check(not has("Modules/UI/PlansUI.lua", "UpgradeItem-32x32") and not has("Modules/UI/PlansUI_Browse.lua", "dragon-rostrum")
        and not has("Modules/UI/PlansTrackerWindow.lua", "INV_Enchant_Disenchant"), "Plans sub-tabs, browse and tracker use registry plan type icons")
    check(has("Modules/UI/ProfessionsUI.lua", 'knowledge   = { iconKey = "knowledge" }'), "Professions knowledge column uses the registry knowledge icon")
    check(has("Modules/UI/ProfessionsUI.lua", 'firstCraft  = { iconKey = "first_craft" }') and has("Modules/UI/ProfessionsUI.lua", 'weeklyQuest = { iconKey = "quest_weekly" }')
        and has("Modules/UI/PvPUI.lua", 'weekly = { iconKey = "quest_weekly" }'), "First craft and weekly quest columns use registry icons")
    check(has("Modules/DailyQuestManager.lua", 'iconKey = "quest_daily"') and has("Modules/DailyQuestManager.lua", 'iconKey = "quest_important"')
        and has("Modules/NotificationManager.lua", 'icon = IconFile("quest_weekly")'), "Quest type icons (daily, weekly, important) come from the registry")
    check(has("Modules/UI/CharactersUI_Row.lua", 'ns.UI_SetIcon(tex, "mail")') and not has("Modules/UI/CharactersUI_Row.lua", "minimap-tracking-mailbox")
        and has("Modules/MailSnapshotService.lua", 'IconFile("mail")'), "Pending mail badge and mail tooltip use the registry envelope")
    check(has("Modules/UI/PlanCardFactory.lua", 'SetNormalTexture(ns.UI_GetIconFile("link"))') and not has("Modules/UI/PlanCardFactory.lua", "UI-ChatIcon-Chat"),
        "Plan chat link button uses the registry chat bubble")
end

print(string.format("Total: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
