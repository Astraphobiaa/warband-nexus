#!/usr/bin/env lua
--[[
    Regression test: section chrome is pooled and discarded chrome leaves the theme registries.

    Tabs rebuilt wraps / bodies / collapsible headers on every redraw and parked the old frames in
    WarbandNexusRecycleBin forever (WoW never frees frames); each new header also registered
    FontStrings / borders in FONT_REGISTRY, TEXT_COLOR_REGISTRY and BORDER_REGISTRY, whose prune
    never matched a parked frame. Modules/UI/SectionPool.lua re-binds section frames by key, marks
    real garbage `_wnDiscarded`, and the registries drop entries under discarded frames - but never
    entries under a pooled row / pooled section frame (those come back) or under tab-persistent
    chrome merely parked on a tab switch.

    Loads the shipped Modules/UI/SectionPool.lua under wow_stub.lua with fake frames.
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

local created = 0
local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
    local f = setmetatable({ _children = {}, _shown = true }, Frame)
    if parent then f:SetParent(parent) end
    return f
end
function Frame:SetParent(p)
    local old = self._parent
    if old then
        for i = #old._children, 1, -1 do if old._children[i] == self then table.remove(old._children, i) end end
    end
    self._parent = p
    if p then p._children[#p._children + 1] = self end
end
function Frame:GetParent() return self._parent end
function Frame:GetChildren() return unpack(self._children) end
function Frame:Hide() self._shown = false end
function Frame:Show() self._shown = true end
function Frame:ClearAllPoints() end
function Frame:SetSize() end
function Frame:SetAlpha() end

local ns = {}
ns.UI_RecycleBin = NewFrame(nil)
ns.UI = { Factory = { CreateContainer = function(_, parent)
    created = created + 1
    return NewFrame(parent)
end } }

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
LoadFile("Modules/UI/SectionPool.lua")
local SP = ns.UI_SectionPool

local host = NewFrame(nil)
local function pass(names)
    SP.BeginPass(host)
    SP.DiscardUnpooledChildren(host)
    local out = {}
    for i = 1, #names do
        local wrap = SP.Acquire(host, "wrap:" .. names[i], host, 100, 20)
        local body = SP.Acquire(host, "body:" .. names[i], wrap, 100, 0)
        local opts = SP.HeaderOpts(host, "hdr:" .. names[i], {})
        local header = opts.reuseHeader or ns.UI.Factory:CreateContainer(wrap)
        SP.Remember(host, "hdr:" .. names[i], header)
        out[i] = { wrap = wrap, body = body, header = header }
    end
    return out
end

print("Phase 1: Section frames are re-bound, not recreated")
do
    local first = pass({ "A", "B" })
    local afterFirst = created
    local second = pass({ "A", "B" })
    assert_eq(created, afterFirst, "second pass creates no frames")
    assert_eq(second[1].wrap, first[1].wrap, "wrap re-bound by key")
    assert_eq(second[2].header, first[2].header, "header re-bound by key")
    assert_eq(#ns.UI_RecycleBin._children, 0, "nothing parked in the recycle bin")
end

print("Phase 2: A duplicate key in one pass does not steal the pooled frame, and is discarded next pass")
do
    local res = pass({ "A", "A" })
    assert_eq(res[1].wrap ~= res[2].wrap, true, "second 'A' gets its own frame")
    local extraWrap = res[2].wrap
    pass({ "A" })
    assert_eq(extraWrap._wnDiscarded, true, "duplicate-key frame discarded on the next pass")
end

print("Phase 3: Unpooled leftovers under the host are discarded")
do
    local stray = NewFrame(host)
    local virtualRow = NewFrame(host); virtualRow._isVirtualRow = true
    local kept = NewFrame(host); kept._wnKeepOnTabSwitch = true
    pass({ "A" })
    assert_eq(stray._wnDiscarded, true, "stray child discarded")
    assert_eq(stray:GetParent(), ns.UI_RecycleBin, "stray child parked in the recycle bin")
    assert_eq(virtualRow._wnDiscarded, nil, "virtual row untouched")
    assert_eq(kept._wnDiscarded, nil, "tab-persistent chrome untouched")
end

print("Phase 4: Registry prune signal")
do
    local garbage = NewFrame(host)
    local fsUnderGarbage = NewFrame(garbage)                    -- stands in for a FontString
    local pooledRow = NewFrame(garbage); pooledRow.isPooled = true
    local fsUnderRow = NewFrame(pooledRow)
    local parkedHost = NewFrame(ns.UI_RecycleBin); parkedHost._wnKeepOnTabSwitch = true
    local fsUnderParked = NewFrame(parkedHost)
    local plainParked = NewFrame(ns.UI_RecycleBin)
    local fsUnderPlainParked = NewFrame(plainParked)
    SP.Discard(garbage)
    assert_eq(SP.IsDiscardedRegion(fsUnderGarbage), true, "entry under a discarded frame is dead")
    assert_eq(SP.IsDiscardedRegion(fsUnderRow), false, "entry under a pooled row survives (row comes back)")
    assert_eq(SP.IsDiscardedRegion(fsUnderParked), false, "entry under parked tab chrome survives")
    assert_eq(SP.IsDiscardedRegion(fsUnderPlainParked), false, "recycle-bin parent alone is not a discard signal")
end

print("Phase 4b: Frames another pool owns are parked but never marked as garbage")
do
    local storPooled = NewFrame(host); storPooled._wnStorPooled = true
    local fs = NewFrame(storPooled)
    SP.Discard(storPooled)                                       -- e.g. Currency teardown on the shared container
    assert_eq(storPooled._wnDiscarded, nil, "Storage-pooled frame not marked")
    assert_eq(SP.IsDiscardedRegion(fs), false, "its registry entries survive")
end

print("Phase 4c: A header replaced after a chrome change is discarded")
do
    pass({ "Z" })
    local oldHeader = SP.Get(host).frames["hdr:Z"]
    SP.BeginPass(host)
    local wrap = SP.Acquire(host, "wrap:Z", host, 1, 1)
    local fresh = ns.UI.Factory:CreateContainer(wrap)           -- reuse signature mismatch: new header
    SP.Remember(host, "hdr:Z", fresh)
    assert_eq(oldHeader._wnDiscarded, true, "old header discarded")
    assert_eq(oldHeader:GetParent(), ns.UI_RecycleBin, "old header no longer under the re-used wrap")
    assert_eq(SP.Get(host).frames["hdr:Z"], fresh, "new header pooled")
end

print("Phase 4d: Re-adopted, cached and pool-owned frames keep their registry entries")
do
    local cachedCard = NewFrame(host)                            -- e.g. Plans reset bar re-adopted every paint
    local fsCard = NewFrame(cachedCard)
    SP.Discard(cachedCard)
    assert_eq(SP.IsDiscardedRegion(fsCard), true, "parked discarded frame: dead")
    cachedCard:SetParent(host)                                   -- owner re-adopts it
    assert_eq(SP.IsDiscardedRegion(fsCard), false, "re-adopted frame is live again")

    local emptyCard = NewFrame(host); emptyCard._wnReadoptable = true
    SP.Discard(emptyCard)
    assert_eq(emptyCard._wnDiscarded, nil, "re-adoptable cached card is never marked")

    local protectedChild = NewFrame(host)
    ns.UI_IsProtectedResultsEmptyChild = function(child, owner) return child == protectedChild and owner == host end
    SP.Discard(protectedChild)
    assert_eq(protectedChild._wnDiscarded, nil, "protected results child is never marked")
    ns.UI_IsProtectedResultsEmptyChild = nil

    local extraBody = NewFrame(host)
    local vlmRow = NewFrame(extraBody); vlmRow._wnVlmRow = true
    local fsRow = NewFrame(vlmRow)
    SP.Discard(extraBody)
    assert_eq(SP.IsDiscardedRegion(fsRow), false, "virtual-list pooled row under discarded chrome survives")
end

print("Phase 4e: A re-acquired body drops last pass's virtual-list state")
do
    pass({ "V" })
    local body = SP.Get(host).frames["body:V"]
    body._vlm_flatList = {}
    body._virtualUpdater = function() end
    body._vlm_headerSig = "x"
    pass({ "V" })
    assert_eq(body._vlm_flatList == nil and body._virtualUpdater == nil and body._vlm_headerSig == nil, true,
        "stale _vlm_flatList / _virtualUpdater / _vlm_headerSig cleared")
end

print("Phase 5: The three registries prune discarded entries (static)")
do
    local function has(rel, pat)
        local fh = assert(io.open(ROOT .. "/" .. rel, "rb"))
        local src = fh:read("*a")
        fh:close()
        local n = 0
        for _ in src:gmatch(pat) do n = n + 1 end
        return n
    end
    assert_eq(has("Modules/FontManager.lua", "UI_IsDiscardedRegion%(fs%)") >= 2, true, "FONT_REGISTRY loops prune")
    assert_eq(has("Modules/UI/SharedWidgets_Theme.lua", "UI_IsDiscardedRegion%(fs%)") >= 1, true, "TEXT_COLOR_REGISTRY prunes")
    assert_eq(has("Modules/UI/SharedWidgets.lua", "UI_IsDiscardedRegion%(frame%)") >= 1, true, "BORDER_REGISTRY prunes")
    assert_eq(has("WarbandNexus.toc", "Modules\\UI\\SectionPool%.lua") == 1, true, "SectionPool.lua listed in the TOC")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Section pool suite failed with " .. failed .. " failure(s).")
end
print("Section pool suite: ALL TESTS PASSED.")
