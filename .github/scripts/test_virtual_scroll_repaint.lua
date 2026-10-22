#!/usr/bin/env lua
--[[
    Regression test: a scroll step does not repopulate rows whose content did not change.

    VirtualListModule re-ran populateRowFn for every visible row on every scroll event (each wheel
    step, every frame of a thumb drag) even when the row frame was reused for the same item: on the
    Characters tab that is ~15 closures + text / texture work per row, 20-30 rows per event.
    Now, on a scroll paint (UI_MainShell sets mainFrame._vlmScrollPaint), a reused row already
    populated for the same index in the current content generation is only re-anchored. Every
    non-scroll paint (setup, refresh, in-place refill + repaint) starts a new generation and
    repopulates, so data changes always show.

    Loads the shipped Modules/UI/VirtualListModule.lua under wow_stub.lua with permissive fake frames.
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

-- Permissive frame: unknown methods are no-ops; geometry is fixed so every row is "visible".
local Frame = {}
Frame.__index = function(t, k)
    local m = rawget(Frame, k)
    if m then return m end
    -- Only WoW-style methods (Capitalized) are permissive no-ops; data fields stay nil.
    if type(k) == "string" and k:match("^%u") then return function() return nil end end
    return nil
end
function Frame.new(parent)
    return setmetatable({ _parent = parent, _shown = true, _scripts = {} }, Frame)
end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p end
function Frame:IsVisible() return not self._hidden end
function Frame:IsShown() return self._shown end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:GetHeight() return 400 end
function Frame:GetWidth() return 600 end
function Frame:GetTop() return 1000 end
function Frame:GetBottom() return 600 end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return 600 end
function Frame:GetVerticalScroll() return self._scroll or 0 end
function Frame:SetVerticalScroll(v) self._scroll = v end
function Frame:GetScrollChild() return self._child end
function Frame:SetScript(n, fn) self._scripts[n] = fn end
function Frame:GetScript(n) return self._scripts[n] end
function Frame:GetChildren() return end
function Frame:GetNumChildren() return 0 end

local ns = {}
ns.DebugPrint = function() end
ns.UI_LAYOUT = {}
local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
LoadFile("Modules/UI/VirtualListModule.lua")
local VLM = ns.VirtualListModule

local mainFrame = Frame.new(nil)
mainFrame.scroll = Frame.new(mainFrame)
mainFrame.scrollChild = Frame.new(mainFrame.scroll)
mainFrame.scroll._child = mainFrame.scrollChild
local container = Frame.new(mainFrame.scrollChild)

local flatList = {}
for i = 1, 60 do
    flatList[i] = { type = "row", yOffset = (i - 1) * 30, height = 30, data = { id = i }, rowReuseSig = "row" .. i }
end

local populates = 0
VLM.SetupVirtualList(mainFrame, container, 0, flatList, {
    createRowFn = function() return Frame.new(container) end,
    populateRowFn = function() populates = populates + 1 end,
    incrementalRowReuse = true,
})
container._vlm_incrementalRowReuse = true

local function scrollPaint()
    mainFrame._vlmScrollPaint = true
    mainFrame._virtualScrollUpdate()
    mainFrame._vlmScrollPaint = nil
end

print("Phase 1: Scroll paints keep unchanged rows")
do
    populates = 0
    mainFrame._virtualScrollUpdate()                 -- a data repaint: everything populates
    local first = populates
    assert_eq(first > 0, true, "non-scroll paint populates the visible rows")
    populates = 0
    scrollPaint()
    scrollPaint()
    assert_eq(populates, 0, "two scroll steps over the same rows repopulate nothing")
    mainFrame.scroll:SetVerticalScroll(90)           -- three rows further down
    scrollPaint()
    assert_eq(populates > 0 and populates < first, true,
        "scrolling down populates only the rows that entered (" .. populates .. " of " .. first .. ")")
end

print("Phase 2: Any non-scroll paint repopulates (data may have changed in place)")
do
    populates = 0
    flatList[1].data.id = 99                         -- in-place refill
    VLM.RepaintVisible(container)
    assert_eq(populates > 0, true, "RepaintVisible repopulates")
    populates = 0
    mainFrame._virtualScrollUpdate()                 -- direct (non-scroll) updater call
    assert_eq(populates > 0, true, "a direct updater call outside scrolling repopulates")
end

print("Phase 2b: A list swapped while the container was hidden repopulates on the next scroll")
do
    mainFrame._virtualScrollUpdate()                 -- settle
    local swapped = {}
    for i = 1, #flatList do
        swapped[i] = { type = "row", yOffset = flatList[i].yOffset, height = 30, data = { id = 500 + i },
            rowReuseSig = flatList[i].rowReuseSig }  -- same sigs: the reuse path would match
    end
    container._hidden = true
    VLM.RefreshVirtualListFlatList(mainFrame, container, swapped)
    container._hidden = nil
    populates = 0
    scrollPaint()
    assert_eq(populates > 0, true, "rows repopulate for the swapped list")
end

print("Phase 3: The main shell marks scroll paints and always clears the mark (static)")
do
    local fh = assert(io.open(ROOT .. "/Modules/UI/UI_MainShell.lua", "rb"))
    local shell = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    local block = shell:match("f%._vlmScrollPaint = true(.-)f%._vlmScrollPaint = nil")
    assert_eq(block ~= nil and block:find("pcall(f._virtualScrollUpdate)", 1, true) ~= nil, true,
        "OnVerticalScroll sets the flag, runs the update under pcall, then clears it")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Virtual scroll repaint suite failed with " .. failed .. " failure(s).")
end
print("Virtual scroll repaint suite: ALL TESTS PASSED.")
