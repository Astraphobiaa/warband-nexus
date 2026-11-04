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
    check(tex.vertex and tex.vertex[1] == 1 and tex.vertex[2] == 1 and tex.vertex[3] == 1,
        "settings nav glyph is colored art: neutral vertex (no theme ink)")
    -- every main tab is on the registry now; storage keeps its own crate glyph instead of the items one.
    -- The items tab is labelled Bank: banker money sacks (vault), not the bag glyph (2026-11-04).
    for _, pair in ipairs({ { "items", "vault" }, { "storage", "crate" }, { "reputation", "medal" }, { "characters", "character" } }) do
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
    check(not has("Modules/Constants.lua", "icon_cooldownmanager") and not has("Modules/ReminderService.lua", "icon_cooldownmanager")
        and has("Modules/VaultButton_SavedInstances.lua", 'ns.UI_SetIcon(titleIcon, "reminder")'), "Reminder alerts use the registry bell")
    check(has("Modules/UI/SharedWidgets_EmptyState.lua", 'search = "search"') and not has("Modules/UI/SharedWidgets_EmptyState.lua", "common-search-magnifyingglass"),
        "No-results empty state uses the registry magnifier")
    check(not has("Modules/UI/PlanCardFactory.lua", "socialqueuing-icon-eye") and not has("Modules/UI/SharedWidgets_Factory.lua", "socialqueuing-icon-eye")
        and has("Modules/UI/SharedWidgets_Factory.lua", 'SetNormalTexture(ns.UI_GetIconFile("wowhead"))'), "Wowhead buttons use the registry Wowhead rocket")
    check(has("Modules/UI/ProfessionsUI.lua", 'gathering   = { iconKey = "gathering" }') and not has("Modules/UI/CharactersUI_Dialogs.lua", "socialqueuing-icon-group")
        and not has("Modules/UI/CharactersUI_Row.lua", "AvailableQuestIcon") and not has("Modules/UI/CharactersUI_Row.lua", "INV_Misc_Note_01")
        and not has("Core.lua", "UI-HUD-MicroMenu-Questlog-Mouseover") and not has("Modules/UI/StatisticsUI.lua", "DastardlyDuos"),
        "Gathering column, section dialogs, unspent points, assign button, update notice and progress card use registry icons")
    check(has("Modules/NotificationManager.lua", 'tryCounter = IconFile("try_counter")') and not has("Modules/NotificationManager.lua", "INV_Misc_Lucky_MoneyEnvelope"),
        "Try counter toasts use the registry try counter pouch")
    check(not has("Modules/UI/SharedWidgets_Icons.lua", "StatusIcon-Online") and has("Modules/UI/SharedWidgets_Icons.lua", 'ns.UI_GetIconFile("online")'),
        "Online indicator uses the registry green gem")
    local grips = { "Modules/UI/UI_MainShell.lua", "Modules/UI/PlansTrackerWindow.lua", "Modules/UI/RecipeCompanionWindow.lua", "Modules/UI/ProfessionInfoWindow.lua", "Modules/VaultButton_SavedInstances.lua" }
    for i = 1, #grips do
        check(not has(grips[i], "SizeGrabber") and has(grips[i], 'ns.UI_GetIconFile("resize_grip")'), grips[i] .. ": resize grip from the registry")
    end
    check(not has("Modules/UI/SharedWidgets_Search.lua", "housing-floor-arrow") and has("Modules/UI/SharedWidgets_Search.lua", 'ns.UI_GetIconFile("arrow_gold")'),
        "Sort arrows use the registry gold arrow")
    check(not has("Modules/UI/PlanCardFactory.lua", "questtypeicon-heroic") and not has("Modules/UI/PlanCardFactory.lua", "questtypeicon-raid")
        and not has("Modules/UI/PlansUI_Dialogs.lua", "questtypeicon")
        and has("Modules/NotificationManager.lua", 'icon = IconFile("quest_raid")'), "Great Vault dungeon/raid/world markers use registry icons")
    check(not has("Modules/UI/PvEUI_VaultGrid.lua", "Head_Dragon_01") and has("Modules/UI/PvEUI_VaultGrid.lua", 'Dungeon = "quest_dungeon"'),
        "PvE vault grid rows use the registry door markers")
    check(not has("Modules/UI/ReputationUI.lua", "Achievement_PVP_A_A") and not has("Modules/UI/ReputationUI.lua", "EverybodysFriend")
        and has("Modules/UI/ReputationUI.lua", 'ns.UI_GetIconFile("faction_horde")'), "Reputation faction/guild/generic headers use registry icons")
    check(not has("Modules/UI/MailDetailsPopup.lua", "Tracking\\Mailbox") and not has("Modules/UI/MailDetailsPopup.lua", "INV_Letter_15"),
        "Mail details popup uses the registry envelope")
    check(not has("Modules/NotificationManager.lua", "bountifulbags") and not has("Modules/UI/PlanCardFactory.lua", '"greatVault-whole-normal"')
        and has("Modules/VaultButton_Core.lua", 'iconKey = "great_vault"'), "Great Vault toasts, plan card and vault menu use the registry vault icon")
    local shellSrc = read("Modules/UI/SettingsUI_Shell.lua")
    local railKeys = { general = "settings", modules = "modules", access = "keyboard", filters = "filter",
        notifications = "notifications", appearance = "palette", advanced = "sliders" }
    for panelId, key in pairs(railKeys) do
        check(shellSrc:find("\n    " .. panelId .. " = {.-iconKey = \"" .. key .. "\"") ~= nil,
            "Settings rail " .. panelId .. " uses its own glyph " .. key)
    end
    check(not has("Modules/UI/SettingsUI_Shell.lua", "UI_ApplyMainNavTabGlyph(tabIcon"),
        "Settings rail draws registry glyphs, not the main tab icons")
end

print("Phase 5: colored art keeps a neutral vertex (every shipped glyph is colored)")
do
    local ns = BaseNs()
    local function has(rel, s) return read(rel):find(s, 1, true) ~= nil end
    -- About tab: the credits glyph is colored art now, so it draws neutral in both themes
    local credits = ns.UI_ICONS.credits
    check(credits and not credits.mono and ns.UI_GetIconFile("credits"):find("Icon%-Credits%.tga$") ~= nil,
        "credits is a colored (non-mono) registry entry on Icon-Credits.tga")
    local ct = FakeTex()
    check(ns.UI_SetIcon(ct, "credits") and ct.vertex and ct.vertex[1] == 1 and ct.vertex[2] == 1 and ct.vertex[3] == 1,
        "credits glyph draws with a neutral vertex")
    for _, rel in ipairs({ "Modules/UI/SettingsUI_Shell.lua", "Modules/UI/UI_MainShell.lua" }) do
        check(not has(rel, 'UI_SetWnIconTexture(tabIcon, "credits"') and has(rel, 'ns.UI_SetIcon(tabIcon, "credits")')
            and has(rel, 'tabIcon._wnRegistryIcon = "credits"'), rel .. ": About tab icon via the registry, tagged for the nav tint")
    end
    -- Run the real SharedWidgets helpers against the real registry (light mode, so mono = 0.1 ink)
    local swSrc = read("Modules/UI/SharedWidgets.lua")
    for line in swSrc:gmatch("\n(ns%.WN_ICON_VERTEX_[%w_]+ = %b{})") do
        assert(loadstring("local ns = ...; " .. line))(ns)
    end
    local function fn(name)
        local body = swSrc:match("\nfunction ns%." .. name .. "(%b().-\nend)\n")
        check(body ~= nil, "SharedWidgets: " .. name .. " found")
        if not body then return function() end end
        return assert(loadstring("local ns, COLORS, IsLightModeEnabled = ...; return function" .. body))(
            ns, { gold = { 1, 0.82, 0, 1 } }, function() return true end)
    end
    local applyStatus = fn("UI_ApplyCollectionRowStatusIcon")
    local st = FakeTex()
    applyStatus(st, true)
    check(st.texture == ns.UI_GetIconFile("status_ok") and st.vertex and st.vertex[1] == 1 and st.vertex[2] == 1 and st.vertex[3] == 1,
        "collected row tick: status_ok with neutral vertex (no gold recolor)")
    local vertexForKey = fn("UI_WnIconVertexForKey")
    local v1, v2 = vertexForKey("complete", false, false), vertexForKey("complete", false, true)
    check(v1[1] == 1 and v1[2] == 1 and v1[3] == 1 and (v1[4] or 1) == 1, "complete action: neutral vertex (no green recolor)")
    check(v2[1] == 1 and v2[2] == 1 and v2[3] == 1 and v2[4] == 0.35, "disabled complete action: neutral vertex, alpha 0.35 (no theme ink)")
    -- Call sites: status_ok / status_fail are never recolored; colored art dims with alpha only
    local ui, shell = read("Modules/UI.lua"), read("Modules/UI/UI_MainShell.lua")
    check(not ui:find('"status_[%a]+", { vertexColor') and not shell:find('"status_[%a]+", { vertexColor')
        and not has("Modules/UI.lua", "statusIcon:SetVertexColor(0.35, 1, 0.45"), "Tracking chip / banner status icons keep a neutral vertex")
    local row = "Modules/UI/CharactersUI_Row.lua"
    check(not has(row, "icon:SetVertexColor(0.35, 1, 0.45)") and not has(row, "icon:SetVertexColor(1, 0.55, 0.42)"),
        "Character row tracking icon keeps a neutral vertex")
    check(not has(row, "UI_GetMonochromeIconVertex(0.45)") and has(row, "row.keystoneIcon:SetAlpha(0.45)"),
        "No-key keystone dims with alpha, not theme ink")
    local vsi = "Modules/VaultButton_SavedInstancesUI.lua"
    check(not has(vsi, "art:SetDesaturated(true)") and not has(vsi, "SetVertexColor(0.65, 0.65, 0.65") and has(vsi, "art:SetAlpha(0.65)"),
        "Saved-instance fallback question icon dims with alpha, no desaturate/grey")
    local search = read("Modules/UI/SharedWidgets_Search.lua")
    local arrow = search:match("local function EnsureArrow(.-)btn:SetScript%(\"OnEnter\"")
    check(arrow and not arrow:find("UI_GetMonochromeIconVertex", 1, true) and arrow:find("nt:SetAlpha(enabled and 1 or 0.35)", 1, true) ~= nil,
        "Disabled gold reorder arrow dims with alpha, not theme ink")
end

print("Phase 6: colored UI glyphs are never tinted; state is alpha")
do
    local ns = BaseNs()
    -- The recolored glyph set comes from the build script (GLYPH_COLOR): every Icon-<Name>.tga listed there is colored art.
    local glyphFiles = {}
    local gc = read("scripts/build_ui_icons.py"):match("\nGLYPH_COLOR = (%b{})")
    for name in (gc or ""):gmatch('"(%w+)":%s*"#%x+"') do glyphFiles[name] = true end
    check(glyphFiles.Close and glyphFiles.Upgrade and glyphFiles.TriangleLeft, "GLYPH_COLOR parsed from scripts/build_ui_icons.py")
    local function isGlyphFile(file)
        local n = type(file) == "string" and file:match("Icon%-(%w+)%.tga$")
        return n and glyphFiles[n] or false
    end
    local glyphKeys = {}  -- registry keys (UI_SetIcon / UI_GetIconMarkup)
    for k, e in pairs(ns.UI_ICONS) do
        if isGlyphFile(e.file) then glyphKeys[k] = true end
    end
    local swSrc = read("Modules/UI/SharedWidgets.lua")
    local wnKeys = {}  -- WN_ICON_PATHS keys (UI_SetWnIconTexture / UI_SetMainChromeIcon / UI_ApplyWnActionIcon)
    for key, file in swSrc:gmatch('\n%s+(%w+) = %(C and C%.WN_ICON_%w+%) or "([^"]+)"') do
        if isGlyphFile(file) then wnKeys[key] = true end
    end
    check(glyphKeys.close and glyphKeys.upgrade and glyphKeys.arrow_left and wnKeys.todo and wnKeys.block,
        "glyph key sets resolved (registry + WN_ICON_PATHS)")

    -- Lint every module: a glyph texture never gets a non-neutral vertex, desaturate or markup tint.
    local function neutralArgs(args)
        local a, b, c = args:match("^%s*([^,]+),%s*([^,]+),%s*([^,%)]+)")
        local function one(x) return x and tonumber((x:gsub("%s", ""))) == 1 end
        return one(a) and one(b) and one(c)
    end
    local offenders = {}
    local function flag(rel, n, why) offenders[#offenders + 1] = rel .. ":" .. n .. " " .. why end
    local lsh = io.popen("find " .. ROOT .. "/Modules -name '*.lua'; ls " .. ROOT .. "/Core.lua")
    for path in lsh:lines() do
        local rel = path:sub(#ROOT + 2)
        local lines = {}
        for l in (read(rel) .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = l end
        for i = 1, #lines do
            local l = lines[i]
            local var, key, rest = l:match("UI_SetIcon%(%s*([%w_%.:%(%)]-)%s*,%s*\"([%w_]+)\"(.*)")
            local isGlyph = var and glyphKeys[key]
            if not isGlyph then
                var, key, rest = l:match("UI_Set%a+IconTexture%(%s*([%w_%.:%(%)]-)%s*,%s*\"([%w_]+)\"(.*)")
                if not var then var, key, rest = l:match("UI_SetMainChromeIcon%(%s*([%w_%.:%(%)]-)%s*,%s*\"([%w_]+)\"(.*)") end
                isGlyph = var and wnKeys[key]
            end
            if isGlyph then
                local vcArgs = rest:match("vertexColor%s*=%s*{([^}]*)}")
                if vcArgs and not neutralArgs(vcArgs) then flag(rel, i, key .. " opts.vertexColor tint") end
                local tintArg = l:match("UI_SetMainChromeIcon%(%s*[^,]+,%s*\"[%w_]+\"%s*,%s*{([^}]*)}")
                if tintArg and not neutralArgs(tintArg) then flag(rel, i, key .. " chrome icon tint") end
                local pat = var:gsub("[%(%)%.%:]", "%%%0")
                for j = i + 1, math.min(i + 20, #lines) do
                    local lj = lines[j]
                    if lj:find("local " .. var .. "%s*=") then break end
                    local args = lj:match(pat .. ":SetVertexColor%((.-)%)%s*[%w%-]*")
                    if args and not neutralArgs(args) then flag(rel, j, key .. " SetVertexColor(" .. args .. ")") end
                    if lj:find(pat .. ":SetDesaturated%(true%)") then flag(rel, j, key .. " desaturated") end
                end
            end
            local mk, margs = l:match("UI_GetIconMarkup%(\"([%w_]+)\"(.-)%)")
            if mk and glyphKeys[mk] and margs:find("{", 1, true) then flag(rel, i, mk .. " markup tint") end
            if l:find("desaturate%s*=%s*[^f%s]") then flag(rel, i, "desaturate option on a packaged icon") end
            if l:find("_wnCollapseVertexColor%s*=") and rel ~= "Modules/UI/SharedWidgets_Icons.lua" then
                flag(rel, i, "chevron collapse tint")
            end
            if l:find("UI_CreateCollapseExpandControl%(") then
                for j = i, math.min(i + 5, #lines) do
                    if lines[j]:find("vertexColor", 1, true) then flag(rel, j, "chevron vertexColor opt") break end
                    if j > i and lines[j]:find("^%s*}%)") then break end
                end
            end
        end
    end
    lsh:close()
    check(#offenders == 0, "no colored glyph is tinted, desaturated or markup-tinted"
        .. (#offenders > 0 and (" (" .. #offenders .. "):\n      " .. table.concat(offenders, "\n      ")) or ""))

    -- Targeted sources the line lint cannot see (state held in a shared table / hover handlers)
    local function has(rel, str) return read(rel):find(str, 1, true) ~= nil end
    check(not has("Modules/UI/SharedWidgets_TableKit.lua", "SORT_ACTIVE_OPTS.vertexColor"), "active sort arrow: no accent vertexColor")
    local fac = read("Modules/UI/SharedWidgets_Factory.lua")
    check(not fac:find("self%.icon:SetVertexColor%(currentColors%.accent"), "scroll arrow hover: no accent re-tint")
    check(not swSrc:find("_iconTexture:SetVertexColor(accentColor", 1, true), "theme refresh: scroll arrows not re-tinted with the accent")
    check(not has("Modules/UI/GearUI_Paperdoll.lua", "_gearUpgradeArrow:SetVertexColor(0.2, 1, 0.5)")
        and not has("Modules/UI/GearUI_Paperdoll.lua", "_gearUpgradeArrow:SetVertexColor(1, 0.9, 0.35)"), "gear upgrade arrow state: no green/yellow tint")
    check(not has("Modules/UI/CharactersUI_Row.lua", "icon:SetVertexColor(0.95, 0.35, 0.35)")
        and not has("Modules/UI/CharactersUI_Row.lua", "icon:SetVertexColor(1, 0.5, 0.5)"), "character delete X: no red tint")
    check(not has("Modules/UI/PlansTrackerWindow.lua", "SetVertexColor(closeR, closeG, closeB)"), "tracker close X: no semantic red tint")

    -- Behaviour: the real WN action helpers (SharedWidgets.lua) keep RGB neutral and express state with alpha
    local light = true
    for line in swSrc:gmatch("\n(ns%.WN_ICON_VERTEX_[%w_]+ = %b{})") do
        assert(loadstring("local ns = ...; " .. line))(ns)
    end
    local function fn(name)
        local body = swSrc:match("\nfunction ns%." .. name .. "(%b().-\nend)\n")
        check(body ~= nil, "SharedWidgets: " .. name .. " found")
        if not body then return function() end end
        return assert(loadstring("local ns, COLORS, IsLightModeEnabled = ...; return function" .. body))(
            ns, {}, function() return light end)
    end
    ns.UI_WnIconVertexForKey = fn("UI_WnIconVertexForKey")
    local forState = fn("UI_WnIconVertexForState")
    local function neutral(v) return v and v[1] == 1 and v[2] == 1 and v[3] == 1 end
    for _, mode in ipairs({ true, false }) do
        light = mode
        local tag = mode and "light" or "dark"
        for _, key in ipairs({ "todo", "alert", "track", "pin", "block", "delete" }) do
            local a, i, d = ns.UI_WnIconVertexForKey(key, true, false), ns.UI_WnIconVertexForKey(key, false, false), ns.UI_WnIconVertexForKey(key, false, true)
            check(neutral(a) and neutral(i) and neutral(d), tag .. ": " .. key .. " active/idle/disabled all neutral RGB")
            check((a[4] or 1) == 1 and (d[4] or 1) < (i[4] or 1), tag .. ": " .. key .. " active full alpha, disabled dimmer than idle")
        end
        local fa, fi, fd = forState(true, false), forState(false, false), forState(false, true)
        check(neutral(fa) and neutral(fi) and neutral(fd) and (fa[4] or 1) == 1 and (fi[4] or 1) < 1 and (fd[4] or 1) < (fi[4] or 1),
            tag .. ": UI_WnIconVertexForState neutral RGB, alpha 1 / idle / disabled")
    end
    local i = ns.UI_WnIconVertexForKey("todo", false, false)
    check((i[4] or 1) >= 0.55 and (i[4] or 1) <= 0.75, "idle action alpha is in the 0.55-0.75 band")
    local seen
    ns.UI_SetWnIconTexture = function(_, _, opts) seen = opts; return true end
    local apply = fn("UI_ApplyWnActionIcon")
    apply(FakeTex(), "todo", false, true)
    check(seen and not seen.desaturate and neutral(seen.vertexColor), "disabled action icon: no desaturate, neutral vertex")

    -- Behaviour: the real nav / header style helpers (SharedWidgets_Theme.lua)
    local themeSrc = read("Modules/UI/SharedWidgets_Theme.lua")
    local parts = {}
    for _, name in ipairs({ "ThemeAPI%.GetNavRailIconIdleVertex", "ThemeAPI%.GetNavTabIconMutedVertex",
        "ns%.UI_ApplyNavTabIconStyle", "ns%.UI_ApplyHeaderUtilityIconStyle" }) do
        local chunk = themeSrc:match("\n(function " .. name .. "%b().-\nend)\n")
        check(chunk ~= nil, "SharedWidgets_Theme: " .. name:gsub("%%", "") .. " found")
        parts[#parts + 1] = chunk or ""
    end
    local themeNs = { UI_ICONS = ns.UI_ICONS, UI_GetMonochromeIconVertex = function(a) return { 0.1, 0.1, 0.1, a or 1 } end }
    assert(loadstring("local ns, ThemeAPI, IsLightModeEnabled = ...\n" .. table.concat(parts, "\n")))(
        themeNs, {}, function() return light end)
    local function T() local t = FakeTex(); t.SetBlendMode = function() end; return t end
    light = false
    for _, case in ipairs({ { false, { rail = true }, "idle rail" }, { false, {}, "idle tab" }, { true, {}, "active tab" } }) do
        local t = T()
        t._wnRegistryIcon = "settings"
        themeNs.UI_ApplyNavTabIconStyle(t, case[1], case[2])
        check(neutral(t.vertex), "dark " .. case[3] .. " icon: neutral RGB (alpha " .. tostring(t.vertex and t.vertex[4]) .. ")")
    end
    local idleRail, active = T(), T()
    themeNs.UI_ApplyNavTabIconStyle(idleRail, false, { rail = true })
    themeNs.UI_ApplyNavTabIconStyle(active, true, {})
    check(idleRail.vertex[4] < 1 and active.vertex[4] == 1, "dark nav: idle dims with alpha, active is full")
    local hIdle, hHover = T(), T()
    themeNs.UI_ApplyHeaderUtilityIconStyle(hIdle, false)
    themeNs.UI_ApplyHeaderUtilityIconStyle(hHover, true)
    check(neutral(hIdle.vertex) and hIdle.vertex[4] < 1 and neutral(hHover.vertex) and hHover.vertex[4] == 1,
        "dark header utility icon: neutral RGB, idle alpha < hover alpha")
    -- light mode keeps the mono path for a future white-glyph entry
    light = true
    themeNs.UI_ICONS = { __stub_mono = { mono = true }, settings = ns.UI_ICONS.settings }
    local m, c = T(), T()
    m._wnRegistryIcon, c._wnRegistryIcon = "__stub_mono", "settings"
    themeNs.UI_ApplyNavTabIconStyle(m, false, {})
    themeNs.UI_ApplyNavTabIconStyle(c, false, {})
    check(m.vertex[1] == 0.1 and neutral(c.vertex), "light nav: mono entry follows theme ink, colored glyph stays neutral")
end

print(string.format("Total: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
