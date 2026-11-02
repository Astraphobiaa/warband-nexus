-- Usage: lua5.1 .github/scripts/test_icon_call_sites.lua [root]. Static per-site check + dynamic check of the registry calls.
local ROOT = arg[1] or os.getenv("WN_ROOT") or "."
local pass, fail = 0, 0
local function check(c, msg) if c then pass = pass + 1 else fail = fail + 1; print("  FAIL " .. msg) end end
local function src(rel) local fh = assert(io.open(ROOT .. "/Modules/UI/" .. rel, "rb")); local t = fh:read("*a"); fh:close(); return t end
local function has(t, s) return t:find(s, 1, true) ~= nil end
local SITES = {
  { "CollectionsUI_Recent.lua", "talents-button-reset", 'ns.UI_SetIcon(resetTex, "reset")' },
  { "CollectionsUI_Recent.lua", "UI-RefreshButton", nil },
  { "PlansUI_WeeklyProgress.lua", "common-icon-checkmark", 'ns.UI_SetIcon(statusIcon, "status_ok")' },
  { "PlansUI_WeeklyProgress.lua", nil, 'ns.UI_SetIcon(objIcon, "status_ok")' },
  { "GearUI_Paperdoll.lua", "loottoast-arrow-green", 'ns.UI_SetIcon(upgradeArrow, "upgrade")' },
  { "GearUI_Paperdoll.lua", "UI-Dialog-Icon-AlertNew", 'ns.UI_SetIcon(btn.missingGemIcon, "attention")' },
  { "GearUI_Paperdoll.lua", "UI-SpellbookIcon-NextPage-Up", 'ns.UI_SetIcon(btn.missingEnchantIcon, "attention")' },
  { "GearUI_Paperdoll_Slots.lua", "Professions-Crafting-Orders-Icon", 'ns.UI_SetIcon(upgradeArrow, "crafting_order")' },
  { "GearUI_Paperdoll_Slots.lua", "loottoast-arrow-green", 'ns.UI_SetIcon(upgradeArrow, "upgrade")' },
  { "GearUI_Paperdoll_Slots.lua", "UI-SpellbookIcon-NextPage-Up", 'ns.UI_SetIcon(lockIcon, "lock"' },
  { "GearUI_Paperdoll_Slots.lua", "Interface\\\\Common\\\\LockIcon", nil },
  { "ReputationUI.lua", "warbands-icon", 'ns.UI_SetIcon(sectionIcon, "warband")' },
  { "ReputationUI.lua", "ReadyCheck-Ready", 'ns.UI_GetIconFile("status_ok")' },
  { "ItemsUI_StorageDraw.lua", "warbands-icon", 'ns.UI_SetIcon(warbandIcon, "warband")' },
  { "StatisticsUI.lua", "warbands-icon", 'ns.UI_SetIcon(wb.icon, "warband")' },
  { "CurrencyUI.lua", "warbands-icon", 'ns.UI_SetIcon(warbandIcon, "warband")' },
  { "PlanCardFactory.lua", "MiniMap-QuestArrow", 'ns.UI_SetIcon(checkArrow, "marker_up")' },
  { "PlanCardFactory.lua", "common-icon-checkmark", 'ns.UI_SetIcon(addedIcon.texture, "status_ok")' },
  { "RecipeCompanionWindow.lua", "PetJournal-FavoritesIcon", 'ns.UI_SetIcon(star, "favorite_on")' },
  { "RecipeCompanionWindow.lua", "warbands-icon", 'CreateStorageIcon(wbRow, "warband"' },
  { "PlansUI_Dialogs.lua", "PetJournal-FavoritesIcon", '"favorite_on" or "favorite_off"' },
  { "PlansUI_Dialogs.lua", "SetVertexColor(0.32, 0.32, 0.34)", nil },  -- GRAY BAN: no grey off star
  { "ProfessionsUI.lua", "transmog-icon-favorite", 'ns.UI_SetIcon(row.favIcon, "favorite_on")' },
  { "GearUI.lua", "auctionhouse-ui-loadingspinner", 'ns.UI_SetIcon(spinner, "spinner")' },
  { "GearUI.lua", "StreamCircle", nil },
  { "PvEUI_VaultGrid.lua", 'arrowTexture:SetAtlas("loottoast-arrow-green"', 'ns.UI_SetIcon(arrowTexture, "upgrade")' },
}
for i = 1, #SITES do
  local s = SITES[i]; local t = src(s[1])
  if s[2] then check(not has(t, s[2]), s[1] .. ": no Blizzard art '" .. s[2] .. "'") end
  if s[3] then check(has(t, s[3]), s[1] .. ": uses " .. s[3]) end
end
-- Tinted callers keep their tint AFTER the registry call (UI_SetIcon resets the vertex).
local function after(rel, a, b)
  local t = src(rel); local ia = t:find(a, 1, true); local ib = ia and t:find(b, ia, true)
  check(ia and ib and (ib - ia) < 200, rel .. ": '" .. b .. "' follows '" .. a .. "'")
end
after("GearUI_Paperdoll.lua", 'ns.UI_SetIcon(upgradeArrow, "upgrade")', "SetVertexColor(0.2, 1, 0.48)")
after("GearUI_Paperdoll_Slots.lua", 'ns.UI_SetIcon(upgradeArrow, "upgrade")', "SetVertexColor(0.2, 1, 0.48)")
after("PvEUI_VaultGrid.lua", 'ns.UI_SetIcon(arrowTexture, "upgrade")', "SetVertexColor(0.2, 1, 0.48)")
after("PlanCardFactory.lua", 'ns.UI_SetIcon(checkArrow, "marker_up")', "SetVertexColor(0.9, 0.9, 0.9, 1)")
-- Recent reset: OnLeave must restore the theme tint, not hard white (a mono glyph on a light card).
do
  local t = src("CollectionsUI_Recent.lua")
  local leave = t:match('resetBtn:SetScript%("OnLeave", function%(%)(.-)end%)')
  check(leave and not leave:find("SetVertexColor(1, 1, 1, 1)", 1, true) and leave:find('UI_SetIcon(resetTex, "reset")', 1, true),
    "CollectionsUI_Recent.lua: reset OnLeave restores the theme tint")
end
-- Dynamic: RecipeCompanionWindow CreateStorageIcon routes keys through the registry, atlases otherwise.
do
  local t = src("RecipeCompanionWindow.lua")
  local body = t:match("local function CreateStorageIcon%(parent, atlas, w, h%)(.-)\nend")
  check(body ~= nil, "CreateStorageIcon found")
  if body then
    local calls = {}
    local ns = { UI_SetIcon = function(tex, key) if key == "warband" then calls[#calls + 1] = "icon:" .. key; return true end return false end }
    local fn = assert(loadstring("local ns, PADDING, STORAGE_ICON = ...; return function(parent, atlas, w, h)" .. body .. "\nend"))(ns, 4, 16)
    local tex = { SetAtlas = function(_, a) calls[#calls + 1] = "atlas:" .. a end, SetSize = function() end, SetPoint = function() end }
    local parent = { CreateTexture = function() return tex end }
    fn(parent, "warband", 16, 16); fn(parent, "Banker")
    check(calls[1] == "icon:warband" and calls[2] == "atlas:Banker" and #calls == 2,
      "CreateStorageIcon: registry key -> UI_SetIcon, plain atlas -> SetAtlas (" .. table.concat(calls, ",") .. ")")
  end
end
print(string.format("Total: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
