#!/usr/bin/env lua
--[[
    Regression test: class icons come from the addon's own painted crest atlas, never Blizzard class art.

    - UI_GetClassIconTexCoord: each of the 13 classes maps to its own 128 px cell of the 512 px atlas
      (cell = classID - 1), inset by half a texel; cells never overlap; unknown classes return nil.
    - UI_ApplyClassIconTexture: sets the atlas file (ring by default, bare on request) with the cell
      TexCoord, never an atlas name; an unknown class falls back to the question-mark icon.
    - The Lua cell table and scripts/build_class_icon_atlas.py CLASS_ORDER describe the same layout.

    Loads the shipped Modules/UI/SharedWidgets_Icons.lua under wow_stub.lua.
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
local function LoadFile(rel, ns)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

C_Item = C_Item or {}
C_Item.GetItemClassInfo = C_Item.GetItemClassInfo or function() return nil end

local ATLAS = "Interface\\AddOns\\WarbandNexus\\Media\\ClassIcons.tga"
local ATLAS_BARE = "Interface\\AddOns\\WarbandNexus\\Media\\ClassIconsBare.tga"
local ns = { Constants = { WN_CLASS_ICON_ATLAS = ATLAS, WN_CLASS_ICON_ATLAS_BARE = ATLAS_BARE } }
LoadFile("Modules/UI/SharedWidgets_Icons.lua", ns)

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
    MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}
local INSET = 0.5 / 512
local function near(a, b) return math.abs(a - b) < 1e-9 end

print("Phase 1: every class has its own atlas cell")
local GetTC = ns.UI_GetClassIconTexCoord
assert_eq(type(GetTC), "function", "UI_GetClassIconTexCoord is exported")
local seen = {}
for classFile, id in pairs(CLASS_IDS) do
    local cell = id - 1
    local col, row = cell % 4, math.floor(cell / 4)
    local l, r, t, b = GetTC(classFile)
    local ok = l ~= nil and near(l, col * 0.25 + INSET) and near(r, (col + 1) * 0.25 - INSET)
        and near(t, row * 0.25 + INSET) and near(b, (row + 1) * 0.25 - INSET)
    assert_eq(ok, true, classFile .. " -> cell " .. cell .. " (col " .. col .. ", row " .. row .. ")")
    local key = col .. ":" .. row
    assert_eq(seen[key], nil, classFile .. " does not share a cell")
    seen[key] = classFile
end
local l1 = GetTC("hunter")
local l2 = GetTC("HUNTER")
assert_eq(l1 ~= nil and l1 == l2, true, "class file lookup is case-insensitive")
assert_eq(GetTC("ADVENTURER"), nil, "unknown class has no cell")
assert_eq(GetTC(nil), nil, "nil class has no cell")

print("Phase 2: ApplyClassIconTexture uses the atlas file, not Blizzard class art")
local function FakeTexture()
    local t = { calls = {} }
    function t:SetTexture(path, wrapH, wrapV, filter) self.path, self.filter = path, filter end
    function t:SetTexCoord(l, r, top, b) self.tc = { l, r, top, b } end
    function t:SetAtlas(name) self.atlas = name end
    function t:SetDesaturated() end
    function t:SetAlpha() end
    function t:SetVertexColor() end
    return t
end
local Apply = ns.UI_ApplyClassIconTexture
local tex = FakeTexture()
Apply(tex, "MAGE")
local ml, mr, mt, mb = GetTC("MAGE")
assert_eq(tex.path, ATLAS, "ring atlas by default")
assert_eq(tex.filter, "TRILINEAR", "trilinear filtering for scaled icons")
assert_eq(tex.tc and tex.tc[1] == ml and tex.tc[2] == mr and tex.tc[3] == mt and tex.tc[4] == mb, true, "mage cell TexCoord")
assert_eq(tex.atlas, nil, "no Blizzard atlas name is set")
Apply(tex, "DRUID", true)
assert_eq(tex.path, ATLAS_BARE, "bare atlas on request")
Apply(tex, "ADVENTURER")
assert_eq(tex.path, "Interface\\Icons\\INV_Misc_QuestionMark", "unknown class falls back to the question mark")

print("Phase 3: Lua cell table matches the atlas build script")
local py = ReadFile("scripts/build_class_icon_atlas.py")
local order = {}
for name in py:match("CLASS_ORDER = %[(.-)%]"):gmatch('"(%a+)"') do order[#order + 1] = name:upper() end
assert_eq(#order, 13, "build script lists 13 classes")
for i = 1, #order do
    assert_eq(CLASS_IDS[order[i]], i, "build script cell " .. (i - 1) .. " is " .. order[i])
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Class icon atlas suite failed with " .. failed .. " failure(s).")
end
print("Class icon atlas suite: ALL TESTS PASSED.")
