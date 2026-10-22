#!/usr/bin/env lua
--[[
    Regression test: light-mode text ink on Collections / PvE / Plans / state cards / settings.

    Light mode swaps the text role ladder to charcoal ink, but several call sites painted fixed
    white (|cffffffff, SetTextColor(1,1,1)) or fixed grey (|cff888888 ...) and so stayed white or
    near invisible on the pale light cards. Dark mode is the frozen baseline: every helper switched
    to must resolve to exactly today's dark value (the only intended dark change is the GRAY BAN on
    Collections "obtained at" detail lines, Dim -> Bright).

    Loads the shipped Modules/UI/SharedWidgets_Theme.lua and Modules/UI/CollectionsUI_Shared.lua
    under wow_stub.lua, extracts single functions from the other files with loadstring, and drives
    them with the theme forced dark / light / classic. Call sites buried in large builders are
    checked statically.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg)
    end
end
local function check_eq(actual, expected, msg)
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
dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

local profile = { themeMode = "dark", uiTheme = "modern" }
local ns = {
    WarbandNexus = { db = { profile = profile, global = {} } },
    CollectionsUI = {},
    L = {},
    UI_LAYOUT = { PAGE_STACK = { SEARCH_HEIGHT = 32 } },
    UI = { Factory = {} },
}

local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

--- Pull one function out of a shipped file (from `header` to the `end` at the same indent).
--- `ret` is the expression the chunk returns (the function value). Returns nil when absent.
local function Extract(rel, header, ret, env)
    local src = ReadFile(rel)
    local s = src:find(header, 1, true)
    if not s then return nil end
    local lineStart = 1
    local p = src:sub(1, s - 1):match(".*\n()")
    if p then lineStart = p end
    local indent = src:sub(lineStart, s - 1)
    local e = src:find("\n" .. indent .. "end\n", s, true)
    if not e then return nil end
    local body = src:sub(lineStart, e + #indent + 4)
    local chunk, err = loadstring(body .. "\nreturn " .. ret, "@" .. rel .. ":" .. header)
    if not chunk then error("extract " .. header .. ": " .. tostring(err), 0) end
    setfenv(chunk, setmetatable(env or {}, { __index = _G }))
    return chunk()
end

local function NewFS()
    local fs = {}
    function fs:SetTextColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    function fs:GetTextColor() return self.r, self.g, self.b, self.a end
    function fs:SetText(t) self.text = t end
    function fs:GetText() return self.text end
    function fs:SetShown(v) self.shown = v end
    function fs:Show() self.shown = true end
    return fs
end

LoadFile("Modules/UI/SharedWidgets_Theme.lua")
local ThemeAPI = ns.UITheme.ThemeAPI

local function SetTheme(mode)
    if mode == "classic" then
        profile.uiTheme, profile.themeMode = "classic", "dark"
    else
        profile.uiTheme, profile.themeMode = "modern", mode
    end
    ns.UI_SyncThemeSurfaceColors()
end

-- Expected role hex per theme (computed from the shipped palette, not hard-coded).
SetTheme("light")
local LIGHT = {}
for _, r in ipairs({ "Bright", "Normal", "Muted", "Dim" }) do LIGHT[r] = ns.UI_GetTextRoleHex(r) end
local LIGHT_BRIGHT = { ns.UI_ResolveTextRoleRGBA("Bright") }
SetTheme("dark")
check_eq(ns.UI_GetTextRoleHex("Bright"), "|cffffffff", "dark Bright role hex is today's |cffffffff")
check(LIGHT.Bright ~= "|cffffffff", "light Bright role hex is not white (" .. LIGHT.Bright .. ")")

-- ---------- ns.UI_GetThemedGreyHex (SharedWidgets.lua) ----------
print("\n[UI_GetThemedGreyHex]")
Extract("Modules/UI/SharedWidgets.lua", "function ns.UI_GetThemedGreyHex(", "ns.UI_GetThemedGreyHex",
    { ns = ns, IsLightModeEnabled = ns.UI_IsLightMode, ThemeAPI = ThemeAPI })
check(type(ns.UI_GetThemedGreyHex) == "function", "SharedWidgets.lua defines ns.UI_GetThemedGreyHex")
if type(ns.UI_GetThemedGreyHex) ~= "function" then
    -- Old code: the helper does not exist; the call sites below fall back to their literals.
    ns.UI_GetThemedGreyHex = function(darkHex) return darkHex end
end
local GREYS = {
    { "|cff666666", "Dim" }, { "|cff888888", "Dim" }, { "|cff888888", "Muted" },
    { "|cffaaaaaa", "Muted" }, { "|cff999999", "Muted" }, { "|cffcccccc", "Bright" },
}
for _, mode in ipairs({ "dark", "classic" }) do
    SetTheme(mode)
    for i = 1, #GREYS do
        local hex, role = GREYS[i][1], GREYS[i][2]
        check_eq(ns.UI_GetThemedGreyHex(hex, role), hex, mode .. ": " .. hex .. "/" .. role .. " keeps the literal")
    end
end
SetTheme("light")
for i = 1, #GREYS do
    local hex, role = GREYS[i][1], GREYS[i][2]
    check_eq(ns.UI_GetThemedGreyHex(hex, role), LIGHT[role], "light: " .. hex .. " resolves the " .. role .. " role")
end

-- ---------- L1: Collections list / achievement meta markup ----------
print("\n[L1 Collections list white hex + earned meta]")
SetTheme("dark")
LoadFile("Modules/UI/CollectionsUI_Shared.lua")
local M = ns.CollectionsUI
check_eq(M.CollectionsListWhiteHex(), "|cffffffff", "dark: CollectionsListWhiteHex unchanged")
SetTheme("light")
check_eq(M.CollectionsListWhiteHex(), LIGHT.Bright, "light: CollectionsListWhiteHex is the Bright role")

_G.GetAchievementInfo = function(id)
    -- id, name, points, completed, month, day, year, ..., wasEarnedByMe(13), earnedBy(14)
    return id, "Ach", 10, true, 3, 4, 24, "", 0, 0, "", false, false, nil
end
M.FormatAchievementEarnedCalendarDate = function() return "04.03.2024" end
SetTheme("dark")
M.InvalidateAchievementEarnedMetaCache()
local dDate, dWho = M.FormatAchievementEarnedRowMetaSplit(4242)
check_eq(dDate, "|cffffffff04.03.2024|r", "dark: earned date markup unchanged")
check_eq(dWho, "|cffffffffBy |r|cffffffffWarband|r", "dark: earned-by markup unchanged")
-- Theme toggle without a browse repopulate: cached strings must not keep the old ink.
SetTheme("light")
local lDate, lWho = M.FormatAchievementEarnedRowMetaSplit(4242)
check_eq(lDate, LIGHT.Bright .. "04.03.2024|r", "light: earned date uses Bright role ink (cache re-keyed on theme)")
check_eq(lWho, LIGHT.Bright .. "By |r" .. LIGHT.Bright .. "Warband|r", "light: earned-by uses Bright role ink")

-- Fixed sub-header subtitle (CollectionsUI_Model.lua).
M.GetCollectionsSubTabHeaderText = function() return "Mounts", "12 / 40 collected" end
M.CollectionsSubTabTrace = function() end
local UpdateSub = Extract("Modules/UI/CollectionsUI_Model.lua", "function M.UpdateCollectionsFixedSubHeaderText(",
    "M.UpdateCollectionsFixedSubHeaderText", { M = M, COLORS = ns.UI_COLORS, format = string.format, ns = ns })
local function NewSubRow()
    return { _title = NewFS(), _subtitle = NewFS(), Show = function() end }
end
SetTheme("dark")
local row = NewSubRow()
UpdateSub({ contentSubHeader = row }, "mounts")
check_eq(row._subtitle.text, "|cffffffff12 / 40 collected|r", "dark: sub-header subtitle markup unchanged")
SetTheme("light")
row = NewSubRow()
UpdateSub({ contentSubHeader = row }, "mounts")
check_eq(row._subtitle.text, LIGHT.Bright .. "12 / 40 collected|r", "light: sub-header subtitle uses Bright role ink")
-- Live switch on the SAME cached row: unchanged text must still be repainted with the new ink.
SetTheme("dark")
UpdateSub({ contentSubHeader = row }, "mounts")
check_eq(row._subtitle.text, "|cffffffff12 / 40 collected|r", "live light->dark: cached sub-header repainted")
SetTheme("light")
UpdateSub({ contentSubHeader = row }, "mounts")
check_eq(row._subtitle.text, LIGHT.Bright .. "12 / 40 collected|r", "live dark->light: cached sub-header repainted")

-- ---------- L2: collection row meta label chrome (SharedWidgets_RowPool.lua) ----------
print("\n[L2 ApplyCollectionRowMetaLabelChrome]")
local ApplyMeta = Extract("Modules/UI/SharedWidgets_RowPool.lua", "local function ApplyCollectionRowMetaLabelChrome(",
    "ApplyCollectionRowMetaLabelChrome", { ns = ns })
SetTheme("dark")
local fs = NewFS()
ApplyMeta(fs)
check(fs.r == 1 and fs.g == 1 and fs.b == 1 and fs.a == 1, "dark: meta label ink is 1,1,1,1 (unchanged)")
SetTheme("light")
fs = NewFS()
ApplyMeta(fs)
check(fs.r == LIGHT_BRIGHT[1] and fs.g == LIGHT_BRIGHT[2] and fs.b == LIGHT_BRIGHT[3],
    "light: meta label ink is the Bright role, not white")
-- A theme toggle repaints it through the role registry.
SetTheme("dark")
fs = NewFS()
ApplyMeta(fs)
SetTheme("light")
ns.UI_RefreshRoleTextColors()
check(fs.r == LIGHT_BRIGHT[1], "light: role registry repaints a meta label colored in dark")

-- ---------- L3: role helper alpha keeps the placeholder's 0.85 ----------
print("\n[L3 role overrides]")
SetTheme("dark")
fs = NewFS()
ns.UI_SetTextColorRole(fs, "Bright", 0.85)
check(fs.r == 1 and fs.g == 1 and fs.b == 1 and fs.a == 0.85, "dark: Bright role with alpha 0.85 == old SetTextColor(1,1,1,0.85)")
fs = NewFS()
ns.UI_SetTextColorRole(fs, "Bright")
check(fs.r == 1 and fs.g == 1 and fs.b == 1 and fs.a == 1, "dark: Bright role == old SetTextColor(1,1,1,1)")

-- ---------- L4: loading card percent (SharedWidgets_StateCards.lua) ----------
print("\n[L4 loading card progress]")
local scEnv = { ns = ns }
scEnv.ReadLoadingPercent = Extract("Modules/UI/SharedWidgets_StateCards.lua", "local function ReadLoadingPercent(",
    "ReadLoadingPercent", {})
local ApplyProgress = Extract("Modules/UI/SharedWidgets_StateCards.lua", "local function ApplyLoadingCardProgress(",
    "ApplyLoadingCardProgress", scEnv)
local function NewCard()
    return {
        _wnLoadingState = { currentStage = "Scanning", loadingProgress = 50 },
        _wnProgressText = NewFS(),
        _wnBarBg = { GetWidth = function() return 0 end },
    }
end
SetTheme("dark")
local card = NewCard()
ApplyProgress(card)
check_eq(card._wnProgressText.text, "|cff888888Scanning - 50%|r", "dark: loading percent text unchanged")
SetTheme("light")
card = NewCard()
ApplyProgress(card)
check_eq(card._wnProgressText.text, LIGHT.Muted .. "Scanning - 50%|r", "light: loading percent uses Muted role")

-- ---------- L5: Plans weekly progress grey (PlansUI_WeeklyProgress.lua) ----------
print("\n[L5 PlanGreyHex]")
local PlanGreyHex = Extract("Modules/UI/PlansUI_WeeklyProgress.lua", "local function PlanGreyHex(", "PlanGreyHex", { ns = ns })
check(type(PlanGreyHex) == "function", "WeeklyProgress defines PlanGreyHex")
if type(PlanGreyHex) == "function" then
    SetTheme("dark")
    check_eq(PlanGreyHex("|cff888888", "Dim"), "|cff888888", "dark: weekly zone/realm grey unchanged")
    check_eq(PlanGreyHex("|cffaaaaaa", "Muted"), "|cffaaaaaa", "dark: weekly sub-quest grey unchanged")
    SetTheme("light")
    check_eq(PlanGreyHex("|cff888888", "Dim"), LIGHT.Dim, "light: weekly zone/realm grey is the Dim role")
    check_eq(PlanGreyHex("|cffaaaaaa", "Muted"), LIGHT.Muted, "light: weekly sub-quest grey is the Muted role")
end

-- ---------- Static: listed call sites no longer paint fixed white / grey ----------
print("\n[static call sites]")
local function has(rel, pat) return ReadFile(rel):find(pat) ~= nil end
local function count(rel, plain)
    local src, n, pos = ReadFile(rel), 0, 1
    while true do
        local s, e = src:find(plain, pos, true)
        if not s then return n end
        n, pos = n + 1, e + 1
    end
end
local SHARED = "Modules/UI/CollectionsUI_Shared.lua"
check(not has(SHARED, "COLLECTIONS_LIST_META_WHITE"), "Shared: fixed COLLECTIONS_LIST_META_WHITE constant gone")
check(not has("Modules/UI/CollectionsUI_Model.lua", '"|cffffffff" %.%. subPlain'), "Model: sub-header subtitle no fixed white")
check_eq(count("Modules/UI/CollectionsUI_Model.lua", "row._subtitle:SetTextColor(1, 1, 1, 1)"), 0, "Model: subtitle role not overridden by SetTextColor(1,1,1,1)")
check_eq(count("Modules/UI/SharedWidgets_RowPool.lua", "SetTextColor(1, 1, 1, 1)"), 0, "RowPool: no SetTextColor(1,1,1,1) left")
check_eq(count("Modules/UI/CollectionsUI.lua", "SetTextColor(1, 1, 1, 1)"), 0, "CollectionsUI: filter labels not raw white")
check(has("Modules/UI/CollectionsUI.lua", 'UI_SetTextColorRole%(lblCollected, "Bright"%)')
    and has("Modules/UI/CollectionsUI.lua", 'UI_SetTextColorRole%(lblUncollected, "Bright"%)'), "CollectionsUI: filter labels use Bright role")
check_eq(count("Modules/UI/SearchBoxComponent.lua", "SetTextColor(1, 1, 1, 0.85)"), 0, "SearchBox: placeholder role not overridden")
check(has("Modules/UI/SearchBoxComponent.lua", 'UI_SetTextColorRole%(placeholderText, "Bright", 0%.85%)'), "SearchBox: placeholder Bright role with alpha 0.85")

local SC = "Modules/UI/SharedWidgets_StateCards.lua"
check_eq(count(SC, '"|cffcccccc" ..'), 0, "StateCards: Module Disabled title not fixed #cccccc")
check(has(SC, 'UI_GetThemedGreyHex%("|cffcccccc", "Bright"%)'), "StateCards: Module Disabled title Bright in light")
check(has(SC, 'UI_GetThemedGreyHex%("|cff999999", "Muted"%)'), "StateCards: DB badge grey is Muted in light")

local WP = "Modules/UI/PlansUI_WeeklyProgress.lua"
check_eq(count(WP, '"|cffaaaaaa" ..'), 0, "WeeklyProgress: sub-quest title not fixed #aaaaaa")
check_eq(count(WP, '"|cff888888" ..'), 0, "WeeklyProgress: zone not fixed #888888")
check_eq(count(WP, "|r |cff888888-%s|r"), 0, "WeeklyProgress: realm suffix not fixed #888888")

local PVE = "Modules/UI/PvEUI.lua"
for _, lit in ipairs({ '"|cff666666?|r"', '"|cff666666" ..', '"|cff888888" ..', '"|cffaaaaaa" ..', 'and "|cff888888")', 'or "|cffaaaaaa"' }) do
    check_eq(count(PVE, lit), 0, "PvEUI: no " .. lit)
end
check_eq(count(PVE, "ns.UI_GetThemedGreyHex("), 10, "PvEUI: ten grey sites resolve through UI_GetThemedGreyHex")

-- ---------- L6: GRAY BAN on Collections obtained-at lines ----------
print("\n[L6 GRAY BAN]")
check(has("Modules/UI/CollectionsUI_Model.lua", 'UI_SetTextColorRole%(obtainedAtLine, "Bright"%)'), "Model: mount/pet obtained-at line Bright")
check(has("Modules/UI/CollectionsUI_Draw.lua", 'UI_SetTextColorRole%(toyObtainedLine, "Bright"%)'), "Draw: toy obtained-at line Bright")

-- ---------- L7: notification dependents re-enable ----------
print("\n[L7 notification labels]")
local NOTIF = "Modules/UI/SettingsUI_Notifications.lua"
check(not has(NOTIF, "dep%.color"), "Notifications: no build-time dep.color copy")
check(not has(NOTIF, "useAlertFrameLabel, color = {1, 1, 1}"), "Notifications: useAlertFrameLabel not reset to raw white")
check(has(NOTIF, 'widget = useAlertFrameLabel, role = "Bright"'), "Notifications: useAlertFrameLabel re-enables with Bright role")
check(has(NOTIF, "ns%.UI_SetInkColor%(dep%.widget, COLORS%.accent%[1%], COLORS%.accent%[2%], COLORS%.accent%[3%]%)"),
    "Notifications: accent read at call time, and the Dim role from the disabled state is cleared")

-- ---------- L8: money log popup repainted on theme / accent change ----------
print("\n[L8 RefreshColors]")
do
    local src = ReadFile("Modules/UI/SharedWidgets.lua")
    local s = src:find("local function RefreshColors()", 1, true)
    local e = src:find("function ns.UI_RefreshExternalFloatingWindows()", 1, true)
    local body = (s and e) and src:sub(s, e) or ""
    check(body:find("ns.CharacterBankMoneyLogPopup.RefreshTheme()", 1, true) ~= nil, "RefreshColors repaints CharacterBankMoneyLogPopup")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then error("light-mode text role checks failed", 0) end
