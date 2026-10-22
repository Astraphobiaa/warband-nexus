--[[
    Warband Nexus - Section frame pool (shared)

    WoW frames are never garbage collected. Tabs that rebuild their section chrome (wraps, bodies,
    collapsible headers) on every redraw used to park the old frames in WarbandNexusRecycleBin for
    good, and every new header added FontStrings / borders to the theme registries (FONT, TEXT_COLOR,
    BORDER), so memory and theme-refresh cost grew all session. This generalises the Storage tree's
    StorPool (ItemsUI_StorageDraw.lua): section frames are kept per host frame under stable keys and
    re-bound on the next pass.

    Pass protocol (per host, e.g. a tab's results container):
        ReleasePooledRowsInSubtree(host)       -- rows back to their pools first (caller)
        SectionPool.BeginPass(host)             -- hide + unanchor every pooled frame
        SectionPool.DiscardUnpooledChildren(host) -- old non-pooled direct children -> recycle bin
        wrap   = SectionPool.Acquire(host, "wrap:" .. key, parent, w, h)
        header = CreateCollapsibleHeader(..., SectionPool.HeaderOpts(host, "hdr:" .. key, visualOpts))
        SectionPool.Remember(host, "hdr:" .. key, header)

    Discarded frames carry `_wnDiscarded`; SectionPool.IsDiscardedRegion lets the registries drop
    entries that live under them (a pooled row or pooled section frame on the way up keeps the entry:
    those frames come back).
]]

local ADDON_NAME, ns = ...

local SectionPool = {}
ns.UI_SectionPool = SectionPool

-- Transient layout fields the section builders stamp on wraps / bodies; cleared on re-acquire.
-- The _vlm_* / _virtualUpdater fields: a re-used body that is not set up as a virtual list this pass
-- (e.g. a section turned empty) must not be found by relayout helpers with last pass's flat list.
-- ClearVirtualScroll already dropped the updater from the main frame on this paint.
SectionPool.STATE_FIELDS = {
    "_wnSectionFullH", "_wnVirtualContentHeight", "_wnSectionBodyBuilt", "_wnRowsContainer",
    "_vlm_flatList", "_virtualUpdater", "_vlm_headerSig",
}

local MAX_ANCESTOR_WALK = 16

function SectionPool.Get(host)
    local pool = host._wnSectionPool
    if not pool then
        pool = { frames = {}, used = {}, extras = {} }
        host._wnSectionPool = pool
    end
    return pool
end

--- Start a pass: every pooled frame is hidden and unanchored; keys become free again.
function SectionPool.BeginPass(host)
    local pool = SectionPool.Get(host)
    wipe(pool.used)
    -- Duplicate-key frames of the last pass were never pooled: discard them now.
    local extras = pool.extras
    for i = 1, #extras do
        SectionPool.Discard(extras[i])
        extras[i] = nil
    end
    for _, f in pairs(pool.frames) do
        f:Hide()
        f:ClearAllPoints()
    end
end

--- Park a frame (hidden) in the recycle bin and mark it as garbage. Frames another pool owns
--- (section / Storage pools, pooled rows, tab-persistent chrome) are parked but never marked: hosts
--- such as scrollChild.resultsContainer are shared by several tabs, and those frames come back.
function SectionPool.Discard(frame)
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
    -- Cached chrome an owner re-adopts later (empty-state / loading cards, Plans reset bar, protected
    -- results children) is never garbage either: a pruned registry entry does not come back.
    local owner = frame:GetParent()
    local protected = ns.UI_IsProtectedResultsEmptyChild and owner and ns.UI_IsProtectedResultsEmptyChild(frame, owner)
    if not (frame._wnSectionPooled or frame._wnStorPooled or frame.isPooled or frame._wnKeepOnTabSwitch
        or frame._wnReadoptable or protected) then
        frame._wnDiscarded = true
    end
    frame:SetParent(ns.UI_RecycleBin or UIParent)
end

--- Discard the host's direct children that are not pooled, virtual rows or tab-persistent chrome.
---@return number discarded
function SectionPool.DiscardUnpooledChildren(host, scratch)
    local children = scratch or {}
    local n = 0
    local function pack(...)
        n = select("#", ...)
        for i = 1, n do children[i] = select(i, ...) end
        for i = n + 1, #children do children[i] = nil end
    end
    pack(host:GetChildren())
    local discarded = 0
    for i = 1, n do
        local child = children[i]
        if child and not child._wnSectionPooled and not child._wnStorPooled and not child._isVirtualRow
            and not child._wnKeepOnTabSwitch and not child.isPooled then
            SectionPool.Discard(child)
            discarded = discarded + 1
        end
    end
    return discarded
end

--- Pooled container frame for `key` (created on first use). A key already taken in this pass (two
--- sections with the same name) gets a fresh, unpooled frame instead of stealing the first one.
function SectionPool.Acquire(host, key, parent, w, h)
    local pool = SectionPool.Get(host)
    local Factory = ns.UI and ns.UI.Factory
    if pool.used[key] then
        local extra = Factory and Factory:CreateContainer(parent, w, h, false) or nil
        if extra then pool.extras[#pool.extras + 1] = extra end
        return extra
    end
    pool.used[key] = true
    local f = pool.frames[key]
    if f then
        if f:GetParent() ~= parent then
            f:SetParent(parent)
        end
        local fields = SectionPool.STATE_FIELDS
        for i = 1, #fields do
            f[fields[i]] = nil
        end
        f._wnDiscarded = nil
        f:ClearAllPoints()
        if w and h then f:SetSize(w, h) end
        f:SetAlpha(1)
        f:Show()
        return f
    end
    f = Factory and Factory:CreateContainer(parent, w, h, false) or nil
    if f then
        f._wnSectionPooled = true
        pool.frames[key] = f
    end
    return f
end

--- visualOpts for CreateCollapsibleHeader with the cached header attached (rebound, not recreated).
function SectionPool.HeaderOpts(host, key, visualOpts)
    visualOpts = (type(visualOpts) == "table") and visualOpts or {}
    local pool = SectionPool.Get(host)
    if not pool.used[key] then
        visualOpts.reuseHeader = pool.frames[key]
    else
        visualOpts.reuseHeader = nil
    end
    return visualOpts
end

function SectionPool.Remember(host, key, header)
    if not header then return end
    local pool = SectionPool.Get(host)
    if pool.used[key] then
        -- Duplicate key this pass: keep the first one pooled, discard this one next pass.
        if header ~= pool.frames[key] then pool.extras[#pool.extras + 1] = header end
        return
    end
    pool.used[key] = true
    local old = pool.frames[key]
    if old and old ~= header then
        -- Chrome signature changed (e.g. classic <-> custom theme): the old header was not reused.
        old._wnSectionPooled = nil
        SectionPool.Discard(old)
    end
    header._wnSectionPooled = true
    pool.frames[key] = header
end

--- True when `region` (FontString / Texture / Frame) lives under a discarded frame with no pooled
--- frame in between, i.e. it can never be shown again and its registry entries are dead weight.
function SectionPool.IsDiscardedRegion(region)
    local node = region
    for _ = 1, MAX_ANCESTOR_WALK do
        if not node then return false end
        -- Only while still parked: a frame re-adopted by its owner since then is live again.
        if node._wnDiscarded then return node:GetParent() == ns.UI_RecycleBin end
        if node.isPooled or node._wnSectionPooled or node._wnStorPooled or node._wnKeepOnTabSwitch
            or node._wnInFramePool or node._wnVlmRow or node._wnReadoptable then
            return false
        end
        if not node.GetParent then return false end
        node = node:GetParent()
    end
    return false
end

ns.UI_IsDiscardedRegion = SectionPool.IsDiscardedRegion
