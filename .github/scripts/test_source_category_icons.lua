-- Behaviour test: collection / plan / profession source-category glyphs come from the addon icon registry.
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
    t.GetAtlas = function(self) return self.atlas end
    t.GetTexture = function(self) return self.texture end
    t.SetTexCoord = function() end
    t.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
    t.SetDesaturated = function() end
    t.SetSize = function() end
    t.Show = function(self) self.shown = true end
    t.Hide = function(self) self.shown = false end
    return t
end
local MONO = { 0.1, 0.1, 0.1 }
local function BaseNs()
    local ns = { Constants = { EVENTS = {} }, L = setmetatable({}, { __index = function(_, k) return k end }), UI = { Factory = {} } }
    ns.WarbandNexus = { RegisterMessage = function() end }
    ns.UI_GetMonochromeIconVertex = function(a) return { MONO[1], MONO[2], MONO[3], a or 1 } end
    load("Modules/UI/IconRegistry.lua", ns)
    return ns
end

print("Phase 1: Collections source categories resolve to registry icons")
do
    local ns = BaseNs()
    load("Modules/UI/CollectionsUI_SourceData.lua", ns)
    local SD = ns.CollectionsUI_SourceData
    local want = { drop = "chest", quest = "scroll", vendor = "stall", profession = "anvil", petbattle = "paw",
        achievement = "trophy", worldevent = "calendar", promotion = "gift", tcg = "cards", shop = "shop_bag",
        discovery = "compass", tradingpost = "tag", pvp = "pvp", unknown = "question" }
    local lists = { { "mount", SD.SOURCE_CATEGORIES, SD.GetMountCategoryIcon },
        { "pet", SD.PET_SOURCE_CATEGORIES, SD.GetPetCategoryIcon },
        { "toy", SD.TOY_SOURCE_CATEGORIES, SD.GetToyCategoryIcon } }
    for li = 1, #lists do
        local name, cats, getter = lists[li][1], lists[li][2], lists[li][3]
        local bad = {}
        for i = 1, #cats do
            local k = cats[i].key
            local icon = getter(k)
            local file = icon and ns.UI_GetIconFile(icon)
            if icon ~= want[k] or not ns.UI_IsAddonMediaTexture(file) then bad[#bad + 1] = k .. "=" .. tostring(icon) end
        end
        check(#cats > 0 and #bad == 0, name .. ": every category is its registry media key (" .. table.concat(bad, ",") .. ")")
    end
    local lists_src = read("Modules/UI/CollectionsUI_Lists.lua")
    check(lists_src:find("ns.UI_SetIcon(catIconTex, catIconKey)", 1, true) ~= nil, "Lists: section header icon gets the registry file + theme tint")
end

print("Phase 2: plan source markup uses registry glyphs")
do
    local ns = BaseNs()
    load("Modules/UI/PlanCardFactory.lua", ns)
    local mk = ns.UI_PlanSourceIconMarkup
    local want = { loot = "chest", quest = "scroll", location = "pin", profession = "anvil", class = "stall" }
    for kind, key in pairs(want) do
        local m = mk(kind, 16)
        local file = ns.UI_SmallIconFile(ns.UI_GetIconFile(key))  -- 16 px markup draws the 32 px copy
        check(m:find("|A:", 1, true) == nil and file and m:find("|T" .. file .. ":", 1, true) ~= nil
            and m:find(":255:255:255|t", 1, true) ~= nil, "kind " .. kind .. " -> registry " .. key .. " file, colored (neutral tint)")
    end
    check(read("Modules/UI/PlanCardFactory.lua"):find("|A:Repair", 1, true) == nil, "no Repair atlas in plan source rows")
end

print("Phase 3: profession uniques column + recipe companion storage icons")
do
    local ns = BaseNs()
    load("Modules/UI/ProfessionsUI.lua", ns)
    local c = ns.ProfessionsUI._drawChunk
    local tex = FakeTex()
    c.ApplyProfessionHeaderIconTexture(tex, c.PROF_HEADER_ICON_BY_COL.uniques)
    check(tex.texture == ns.UI_GetIconFile("sparkle") and tex.atlas == nil and tex.shown == true, "uniques header draws the registry sparkle file")
    check(tex.vertex and tex.vertex[1] == 1 and tex.vertex[2] == 1 and tex.vertex[3] == 1, "uniques header keeps the colored sparkle neutral (no theme tint)")
    local other = FakeTex()
    c.ApplyProfessionHeaderIconTexture(other, c.PROF_HEADER_ICON_BY_COL.treatise)
    check(other.texture == "Interface\\Icons\\INV_Inscription_Tradeskill01", "file-path columns unchanged")
    local prof = read("Modules/UI/ProfessionsUI.lua")
    check(prof:find('"QuestTurnin"', 1, true) == nil and prof:find('ns.UI_SetIcon(iicon, "scroll")', 1, true) ~= nil, "info button uses registry scroll")
    local rc = read("Modules/UI/RecipeCompanionWindow.lua")
    check(rc:find('CreateStorageIcon(bagRow, "bag")', 1, true) ~= nil and rc:find('CreateStorageIcon(bankRow, "vault")', 1, true) ~= nil,
        "recipe companion bag/bank rows use registry bag/vault")
end

print(string.format("Total: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
