--[[
    Warband Nexus - UI Layout Probe (`/wn uiprobe`)

    Reads the real on-screen rectangle of every frame in the main window's scroll chain and prints
    the differences between them. It exists because layout drift is invisible in source: each frame
    looks correctly anchored where it is declared, and the mismatch only appears once the anchors
    resolve against each other at runtime. Screenshots can show that something is off by a few
    pixels but not which frame owns those pixels.

    What it checks, per tab:
      * the viewport rim, the scroll frame, the scrollbar column and the bar all share a top and a
        bottom -- a column taller than the viewport it serves is the "arrows hang past the panel"
        symptom;
      * the scroll child is not taller than the viewport when the page has nothing to scroll --
        a few stray pixels there is a scrollbar on an empty page;
      * the fixed header, the viewport and the horizontal bar agree on a right edge.

    Output is one line per frame plus a verdict list, so two tabs can be compared by eye.
    Read-only: it moves nothing.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
--- Live markup role table (`SharedWidgets_Theme.lua`). Mutated in place on theme change,
--- so this reference stays current -- never copy a role out of it into another local.
local HEX = ns.UI_HEX

local format = string.format

--- Rounded edges of a frame in screen space, or nil when it has no resolved rect yet.
---@param frame Frame|nil
---@return table|nil
local function Rect(frame)
    if not frame or not frame.GetLeft then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local function n(v) return math.floor(v + 0.5) end
    return { left = n(l), right = n(r), top = n(t), bottom = n(b), w = n(r - l), h = n(t - b) }
end

local function Line(label, rect)
    if not rect then
        return format("   %-18s %s", label, "(no rect)")
    end
    return format("   %-18s x %d..%d (w %d)   y %d..%d (h %d)",
        label, rect.left, rect.right, rect.w, rect.bottom, rect.top, rect.h)
end

--- One frame's expected relationship to another, as a pass/fail line.
local function Compare(out, label, a, b, field, tolerance)
    if not (a and b) then return end
    local diff = a[field] - b[field]
    if diff < 0 then diff = -diff end
    if diff <= (tolerance or 0) then return end
    out[#out + 1] = format("%s%s|r off by %d px", HEX.red, label, diff)
end

--- Dump the main window's scroll chain and the mismatches between its frames.
---@return boolean ran
function WarbandNexus:PrintUILayoutProbe()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() then
        self:Print(HEX.orange .. "[WN]|r uiprobe: open the main window first.|r")
        return false
    end

    local content = Rect(mf.content)
    local rim = Rect(mf.viewportBorder)
    local header = Rect(mf.fixedHeader)
    local scroll = Rect(mf.scroll)
    local child = Rect(mf.scrollChild)
    local column = Rect(mf.scrollBarColumn)
    local bar = Rect(mf.scroll and mf.scroll.ScrollBar)
    local hBar = Rect(mf.hScrollContainer)
    -- The tab's own top-level block inside the scroll child: when the child overflows a page that
    -- has nothing to scroll, this is usually the frame that reported itself too tall.
    local body = Rect(mf.scrollChild and (mf.scrollChild.resultsContainer
        or mf.scrollChild._wnTabBodyBlock))

    self:Print(format("%s[WN]|r uiprobe: tab %s", HEX.info, tostring(mf.currentTab)))
    self:Print(Line("content", content))
    self:Print(Line("fixedHeader", header))
    self:Print(Line("viewportBorder", rim))
    self:Print(Line("scroll", scroll))
    self:Print(Line("scrollChild", child))
    self:Print(Line("scrollBarColumn", column)
        .. ((mf.scrollBarColumn and mf.scrollBarColumn:IsShown()) and "  [shown]" or "  [hidden]"))
    self:Print(Line("ScrollBar", bar))
    self:Print(Line("hScrollContainer", hBar))
    self:Print(Line("tab body block", body))

    local sync = mf.scrollChild and mf.scrollChild._wnLastSync
    if sync then
        self:Print(format("   %-18s tab=%s body=%d viewport=%d fill=%s -> %s (call #%d)",
            "last height sync", tostring(sync.tab), math.floor(sync.bodyH or 0),
            math.floor(sync.viewportH or 0), tostring(sync.fill),
            tostring(math.floor(sync.result or -1)), sync.n or 0))
    else
        self:Print(format("   %-18s %snever ran -- the height came from somewhere else|r",
            "last height sync", HEX.orange))
    end

    -- The lane decision, with the numbers it was made on. "A bar on an empty page" is a visibility
    -- verdict, not a geometry fault, so the rect lines above can all agree while it is still wrong.
    local sf = mf.scroll
    local range = (sf and sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
    local offset = (sf and sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0
    local shownNow = (mf.scrollBarColumn and mf.scrollBarColumn.IsShown and mf.scrollBarColumn:IsShown()) and true or false
    self:Print(format("   %-18s range=%.1f offset=%.1f shown=%s keepLane=%s",
        "lane", range, offset, tostring(shownNow), tostring(sf and sf._wnKeepScrollLane or false)))

    local problems = {}

    -- A lane handed to a bar that has nothing to move is the "empty page still scrolls" symptom.
    if shownNow and range <= 1 and not (sf and sf._wnKeepScrollLane) then
        problems[#problems + 1] = format(
            "%sscrollbar lane is OPEN with no scroll range -- something shows the column past the visibility pass|r",
            HEX.red)
    end
    if range <= 1 and offset > 0.5 then
        problems[#problems + 1] = format("%sviewport is scrolled %.1f px with no range|r", HEX.red, offset)
    end

    -- The column serves the viewport, so it spans exactly the viewport.
    Compare(problems, "column top vs scroll top", column, scroll, "top", 0)
    Compare(problems, "column bottom vs scroll bottom", column, scroll, "bottom", 0)
    -- The rim encloses the fixed header AND the viewport, so it meets the header at the top and
    -- the viewport at the bottom. (A first version of this compared the rim to the scroll frame at
    -- both ends and reported the header's own height, 170 px, as a fault on every tab.)
    Compare(problems, "rim top vs header top", rim, header, "top", 0)
    Compare(problems, "rim bottom vs scroll bottom", rim, scroll, "bottom", 0)
    -- Only when the bar is actually on screen. With the lane handed back the column is hidden and
    -- parked past the viewport's right edge, which is where its anchor puts it and harms nothing;
    -- reporting that was noise on every page that had nothing to scroll.
    local columnShown = mf.scrollBarColumn and mf.scrollBarColumn.IsShown and mf.scrollBarColumn:IsShown()
    if rim and column and columnShown and column.right > rim.right then
        problems[#problems + 1] = format("%sscrollbar sits %d px OUTSIDE the container|r",
            HEX.red, column.right - rim.right)
    end
    -- Header and viewport are the two full-width bands; they share a right edge.
    Compare(problems, "header right vs rim right", header, rim, "right", 0)

    -- Nothing to scroll must mean no scroll range.
    if child and scroll then
        local overflow = child.h - scroll.h
        if overflow > 0 then
            local range = (mf.scroll.GetVerticalScrollRange and mf.scroll:GetVerticalScrollRange()) or 0
            problems[#problems + 1] = format(
                "%sscrollChild is %d px taller than the viewport (range %.1f)|r",
                HEX.red, overflow, range)
        end
    end

    if #problems == 0 then
        self:Print(format("   %sno mismatch|r", HEX.green))
    else
        for i = 1, #problems do
            self:Print("   " .. problems[i])
        end
    end
    return true
end
