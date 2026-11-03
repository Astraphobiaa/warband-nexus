#!/usr/bin/env lua
--[[
    Regression test: class icons come from the addon's own painted crest files, never Blizzard class art.

    - UI_GetClassIconFile: each of the 13 classes maps to its own 128 px file (ring, or -Bare on request);
      lookup is case-insensitive; unknown classes return nil. No 512 px atlas (the client crashed drawing it).
    - UI_ApplyClassIconTexture: sets that file with the full TexCoord, never an atlas name;
      an unknown class falls back to the question-mark icon.
    - The Lua class table and scripts/build_class_icon_atlas.py CLASS_ORDER list the same classes.

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

local PREFIX = "Interface\\AddOns\\WarbandNexus\\Media\\ClassCrest-"
local ns = { Constants = { WN_CLASS_CREST_PREFIX = PREFIX } }
LoadFile("Modules/UI/IconRegistry.lua", ns)
LoadFile("Modules/UI/SharedWidgets_Icons.lua", ns)

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
    MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

print("Phase 1: every class has its own crest file")
local GetFile = ns.UI_GetClassIconFile
assert_eq(type(GetFile), "function", "UI_GetClassIconFile is exported")
for classFile in pairs(CLASS_IDS) do
    assert_eq(GetFile(classFile), PREFIX .. classFile .. ".tga", classFile .. " ring crest file")
    assert_eq(GetFile(classFile, true), PREFIX .. classFile .. "-Bare.tga", classFile .. " bare crest file")
    for _, suffix in ipairs({ ".tga", "-Bare.tga" }) do
        local fh = io.open(ROOT .. "/Media/ClassCrest-" .. classFile .. suffix, "rb")
        local head = fh and fh:read(18)
        if fh then fh:close() end
        local w = head and (head:byte(13) + head:byte(14) * 256)
        assert_eq(w, 128, "Media/ClassCrest-" .. classFile .. suffix .. " is a 128 px TGA")
    end
end
assert_eq(GetFile("hunter"), GetFile("HUNTER"), "class file lookup is case-insensitive")
assert_eq(GetFile("ADVENTURER"), nil, "unknown class has no crest")
assert_eq(GetFile(nil), nil, "nil class has no crest")
assert_eq(io.open(ROOT .. "/Media/ClassIcons.tga", "rb"), nil, "the 512 px atlas is not shipped")

print("Phase 2: ApplyClassIconTexture uses the crest file, not Blizzard class art")
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
assert_eq(tex.path, GetFile("MAGE"), "ring crest by default")
assert_eq(tex.filter, nil, "default filtering (no TRILINEAR)")
assert_eq(tex.tc and tex.tc[1] == 0 and tex.tc[2] == 1 and tex.tc[3] == 0 and tex.tc[4] == 1, true, "full TexCoord")
assert_eq(tex.atlas, nil, "no Blizzard atlas name is set")
Apply(tex, "DRUID", true)
assert_eq(tex.path, GetFile("DRUID", true), "bare crest on request")
Apply(tex, "ADVENTURER")
assert_eq(tex.path, ns.UI_GetIconFile("question"), "unknown class falls back to the registry question icon")

print("Phase 3: Lua class table matches the crest build script")
local py = ReadFile("scripts/build_class_icon_atlas.py")
local order = {}
for name in py:match("CLASS_ORDER = %[(.-)%]"):gmatch('"(%a+)"') do order[#order + 1] = name:upper() end
assert_eq(#order, 13, "build script lists 13 classes")
for i = 1, #order do
    assert_eq(CLASS_IDS[order[i]], i, "build script class " .. i .. " is " .. order[i])
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Class icon atlas suite failed with " .. failed .. " failure(s).")
end
print("Class icon atlas suite: ALL TESTS PASSED.")
