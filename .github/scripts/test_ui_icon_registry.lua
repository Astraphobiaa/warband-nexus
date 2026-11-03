#!/usr/bin/env lua
--[[
    Regression test: semantic UI icons come from the addon's own Media files, never Blizzard UI art.

    - Every ns.UI_ICONS entry has a file; no entry lists Blizzard atlases.
    - Every Media path in the registry exists on disk as a TGA (case-exact: the Linux packager is case-sensitive).
    - Each shipped Icon-*.tga is a 64x64 32-bit TGA, as WoW needs power-of-two sizes.
    - UI_SetIcon applies the file with a trilinear filter; mono keys follow the theme vertex, colored keys stay neutral.

    Loads the shipped Modules/UI/IconRegistry.lua under wow_stub.lua.
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

local ns = { Constants = {} }
LoadFile("Modules/Constants.lua", ns)
LoadFile("Modules/UI/IconRegistry.lua", ns)

local MEDIA_PREFIX = "Interface\\AddOns\\WarbandNexus\\"

print("Phase 1: every registry entry points at a shipped file")
local keys = {}
for k in pairs(ns.UI_ICONS) do keys[#keys + 1] = k end
table.sort(keys)
assert_eq(#keys >= 30, true, "registry has the full set (" .. #keys .. " keys)")
for i = 1, #keys do
    local k = keys[i]
    local e = ns.UI_ICONS[k]
    assert_eq(e.atlases, nil, k .. " lists no Blizzard atlas")
    assert_eq(e.file ~= nil, true, k .. " has a file")
    if type(e.file) == "string" then
        assert_eq(e.file:sub(1, #MEDIA_PREFIX), MEDIA_PREFIX, k .. " file is addon media")
        local rel = e.file:sub(#MEDIA_PREFIX + 1):gsub("\\", "/")
        local fh = io.open(ROOT .. "/" .. rel, "rb")
        assert_eq(fh ~= nil, true, k .. " -> " .. rel .. " exists")
        if fh then
            local h = fh:read(18)
            fh:close()
            local w = h:byte(13) + h:byte(14) * 256
            local hh = h:byte(15) + h:byte(16) * 256
            assert_eq(w == 64 and hh == 64 and h:byte(17) == 32, true, rel .. " is 64x64 32-bit")
        end
    end
end

print("Phase 2: UI_SetIcon applies our file, theme tint for mono only")
ns.UI_GetMonochromeIconVertex = function(a) return { 0.1, 0.1, 0.1, a or 1 } end
local function FakeTexture()
    local t = {}
    function t:SetTexture(path, wh, wv, filter) self.path, self.filter = path, filter end
    function t:SetTexCoord(...) self.tc = { ... } end
    function t:SetAtlas(name) self.atlas = name end
    function t:SetDesaturated() end
    function t:SetVertexColor(r, g, b, a) self.vc = { r, g, b, a } end
    return t
end
local tex = FakeTexture()
local ok, how = ns.UI_SetIcon(tex, "settings")
assert_eq(ok and how, "file", "settings applied from file")
assert_eq(tex.path, ns.UI_ICONS.settings.file, "settings uses its registry file")
assert_eq(tex.filter, "TRILINEAR", "trilinear filter")
assert_eq(tex.atlas, nil, "no atlas set")
assert_eq(tex.vc and tex.vc[1], 0.1, "mono key follows the theme vertex")
ns.UI_SetIcon(tex, "favorite_on")
assert_eq(tex.vc and tex.vc[1] == 1 and tex.vc[2] == 1 and tex.vc[3] == 1, true, "colored key keeps a neutral vertex")
ns.UI_SetIcon(tex, "sort_up")
assert_eq(tex.tc and tex.tc[3] == 1 and tex.tc[4] == 0, true, "sort_up flips the down triangle")
assert_eq(ns.UI_GetIconFile("attention"), ns.UI_ICONS.attention.file, "UI_GetIconFile returns the entry file")
assert_eq(ns.UI_IsAddonMediaTexture(ns.UI_ICONS.lock.file), true, "own media is recognised")
assert_eq(ns.UI_IsAddonMediaTexture("Interface\\Icons\\INV_Misc_Coin_01"), false, "Blizzard icons are not")

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("UI icon registry suite failed with " .. failed .. " failure(s).")
end
print("UI icon registry suite: ALL TESTS PASSED.")
