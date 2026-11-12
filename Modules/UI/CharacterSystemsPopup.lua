--[[
    Warband Nexus - Talents / Skills detail windows (WoW Forever).

    The roster cells are one icon each and their tooltips say what the character has; these
    windows are the full picture.

    Content paradigm, decided before coding (WN detail-popup rules):
      - Talents are a GRID with arrows. The tree has real geometry -- posX columns, posY tiers --
        and the service hands it over as tab.columns, node.column and tier.position, so the window
        reproduces the talent frame's own shape, holes included. node.edges carries the
        prerequisite links, drawn as connector lines between the squares; without them a talent
        tree is just a scattering of icons. Three tabs side by side, ordered left to right by
        posX, because the client publishes no tab names (subTreeID was nil on all 50 nodes).
      - Skills are a GRID too, five across, each icon over the level it is learned at. The names
        are long and would set the column width on their own; the icon is what a player
        recognises, and the real spell tooltip carries the name on hover.

    Icons go through ns.UI_CreateIcon so they get the project's border and icon-well chrome
    instead of a bare texture, and the tooltips are Blizzard's own (GameTooltip:SetSpellByID)
    behind UI_SafeSetGameTooltipOwner / UI_SafeHideGameTooltip, so a secret value or a combat
    lockdown cannot take the frame down with it.
]]

local ADDON_NAME, ns = ...
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateIcon = ns.UI_CreateIcon
local Factory = ns.UI and ns.UI.Factory

-- Talent grid. ICON + GAP is the column pitch; ROW_H leaves room for the rank under each square.
local TALENT_ICON = 40
local TALENT_GAP = 20
local TALENT_CAPTION_H = 22      -- rank strip + "3/5" under a square; connectors start below it
local TALENT_ROW_H = TALENT_ICON + TALENT_CAPTION_H + 14
local TAB_GAP = 32
local PAD = 18
-- Talents and Skills open at one shared size, so switching between them keeps the window still.
-- Talents grows wider only when its trees need it (never clipped).
local SYSTEMS_POPUP_W = 960
local SYSTEMS_POPUP_H = 760
local TIER_LABEL_W = 34

-- Skill grid: five across, icon over "Lv. N".
local SKILL_COLUMNS = 5
local SKILL_ICON = 40
local SKILL_CELL_W = SKILL_ICON + 30
local SKILL_CELL_H = SKILL_ICON + 22
local SECTION_HEAD_H = 26

-- Blizzard icon art carries a built-in border roughly 8% in from each edge; trimming it lets our
-- own border be the only one on screen.
local SPELL_ICON_TRIM = 0.08

-- Gap between the viewport and the scrollbar lane; the same value the other popups use.
local SCROLL_GAP = 2
-- Distance from the bar column to the window's right edge: the bar sits at the edge, not a full
-- content PAD in from it.
local SCROLL_EDGE = 4

local LINE_RGBA = { 0.45, 0.42, 0.55, 0.9 }
local LINE_DIM_RGBA = { 0.3, 0.3, 0.34, 0.6 }
local LINE_THICKNESS = 2

local function L(key, fallback)
    local tbl = ns.L
    return (tbl and tbl[key]) or fallback
end

--- Theme-aware muted ink. A branch, not `a and f() or x, y, z` -- that form keeps only the first
--- return of the call and appends the literals (Lua 5.1 multi-return trap).
local function Muted()
    if ns.UI_GetTextRoleRGB then
        local r, g, b = ns.UI_GetTextRoleRGB("Muted")
        if r then return r, g, b end
    end
    return 0.6, 0.6, 0.65
end

--- Real spell tooltip on hover; falls back to the plain name when there is no spell id (trainer
--- services only carry one when their link happens to parse).
local function SpellTooltipOnEnter(self)
    if not ns.UI_SafeSetGameTooltipOwner(self, "ANCHOR_RIGHT") then return end
    local spellID = self._wnSpellID
    if spellID and GameTooltip.SetSpellByID then
        if pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) then
            GameTooltip:Show()
            return
        end
    end
    GameTooltip:SetText(self._wnSpellName or "")
    if self._wnSpellSub and self._wnSpellSub ~= "" then
        GameTooltip:AddLine(self._wnSpellSub, 0.7, 0.7, 0.75)
    end
    GameTooltip:Show()
end

local function SpellTooltipOnLeave()
    ns.UI_SafeHideGameTooltip()
end

--- Bordered icon with a caption under it, pooled on the host.
local function AcquireIconCell(host, pool, index, size)
    local cell = pool[index]
    if not cell then
        cell = CreateIcon(host, nil, size, false, nil, false)
        if not cell then return nil end
        -- Blizzard spell art ships with its own bevelled frame baked into the file. Drawn whole
        -- it sits directly under our icon-well border and the two read as a double edge, so the
        -- outer ring is cropped off -- the same trim the profession icons use.
        if cell.texture then
            cell.texture:SetTexCoord(SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM,
                SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM)
        end
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", SpellTooltipOnEnter)
        cell:SetScript("OnLeave", SpellTooltipOnLeave)
        cell.caption = FontManager:CreateFontString(cell, "small", "OVERLAY")
        cell.caption:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell.caption:SetJustifyH("CENTER")
        pool[index] = cell
    end
    cell:SetParent(host)
    -- CreateIcon hides the frame during setup; nothing shows until the caller asks.
    cell:Show()
    return cell
end

--- Clear the content frame between opens: children to the recycle bin, FontStrings hidden.
local function ResetContent(content)
    local children = { content:GetChildren() }
    local bin = ns.UI_RecycleBin
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end
    local regions = { content:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            region:Hide()
        end
    end
end

--[[
    Scroll viewport + scrollbar, assembled from the Factory's own pieces.

    The lane the bar occupies is NOT reserved permanently. Factory:WireScrollBarColumnLayout
    records two bottom-right anchors -- one with the lane, one without -- and
    UpdateScrollBarVisibility picks between them once the content height is known. A window whose
    content fits therefore uses its full width and shows no bar; one that overflows gives the lane
    back to the column. That logic already existed in the Factory; this file had grown its own
    copy, which is exactly the duplication that keeps producing drift.

    Returns the scroll frame, its child, and the width the child may use.
]]
local function BuildScroll(content, width, topInset)
    if not Factory or not Factory.CreateScrollFrame or not Factory.CreateContainer then return nil end
    local barW = ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth() or 26

    local column = Factory.CreateBareScrollBarColumn
        and Factory:CreateBareScrollBarColumn(content, barW)
        or Factory:CreateScrollBarColumn(content, barW, 0, 0)
    local scroll = Factory:CreateScrollFrame(content, "UIPanelScrollFrameTemplate", true)
    if not scroll or not column then return nil end

    -- Initial placement, lane reserved: the wire below replaces the bottom-right point on the
    -- first visibility pass, but the frame has to be somewhere until then.
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(PAD + (topInset or 0)))
    scroll:SetPoint("BOTTOMRIGHT", column, "BOTTOMLEFT", -SCROLL_GAP, PAD)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    if ns.UI_EnableStandardScrollWheel then ns.UI_EnableStandardScrollWheel(scroll) end

    -- One wire, the caller's own insets: the top one differs per window (a summary line sits
    -- above the grid in two of the three).
    if Factory.WireScrollLaneWithInsets then
        Factory:WireScrollLaneWithInsets(scroll, content, column, {
            left = PAD, top = PAD + (topInset or 0), right = SCROLL_EDGE, bottom = PAD, gap = SCROLL_GAP,
        })
    elseif Factory.EnsureScrollBarColumnSync then
        Factory:EnsureScrollBarColumnSync(scroll, column, { width = barW, gap = SCROLL_GAP })
    end

    local lane = barW + SCROLL_GAP
    local contentW = width - PAD - SCROLL_EDGE - lane
    local child = Factory:CreateContainer(scroll, contentW, 1, false)
    if not child then return nil end
    child:SetWidth(contentW)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    -- Without this the child swallows the wheel and the view never moves.
    if child.EnableMouseWheel then child:EnableMouseWheel(true) end
    child:Show()

    return scroll, child, contentW
end

--[[
    Called once the child has its final height.

    The Factory decides the lane from the content height, then the child is widened to whatever
    the viewport ended up being -- the headers are anchored to both of the child's edges, so they
    span the row either way. Deferred as well as immediate: a frame's height is not settled on the
    pass that builds it.
]]
local function RefreshScrollBar(scroll)
    if not scroll then return end
    local function sync()
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scroll)
        elseif scroll.UpdateScrollBarVisibility then
            scroll:UpdateScrollBarVisibility()
        end
        local child = scroll:GetScrollChild()
        local w = scroll:GetWidth()
        if child and w and w > 1 then child:SetWidth(w) end
    end
    sync()
    if Factory and Factory.DeferScrollBarVisibility then
        Factory:DeferScrollBarVisibility(scroll)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, sync) end
end

-- ---------------------------------------------------------------------------
-- Talent tree
-- ---------------------------------------------------------------------------

--- One connector between two squares. Horizontal, vertical and diagonal links all reduce to a
--- thin rectangle, so a single pooled texture per edge is enough.
local function DrawConnector(host, pool, index, x1, y1, x2, y2, lit)
    local line = pool[index]
    if not line then
        line = host:CreateTexture(nil, "BACKGROUND", nil, 2)
        pool[index] = line
    end
    line:SetParent(host)
    line:ClearAllPoints()
    local rgba = lit and LINE_RGBA or LINE_DIM_RGBA
    line:SetColorTexture(rgba[1], rgba[2], rgba[3], rgba[4])
    -- Thickness and snapping go through the shared pixel helpers rather than a literal 2, so a
    -- connector lands on whole physical pixels at every UI scale, like every other rule we draw.
    if math.abs(x1 - x2) < 1 then
        -- Straight down: the common case in a classic tree.
        line:SetPoint("TOPLEFT", host, "TOPLEFT", x1 - 1, y1)
        line:SetHeight(math.max(1, math.abs(y2 - y1)))
        if ns.UI_SetRuleThickness then
            ns.UI_SetRuleThickness(line, "vertical", LINE_THICKNESS)
        else
            line:SetWidth(LINE_THICKNESS)
        end
    else
        -- Sideways or diagonal: drawn as the horizontal leg. A rotated texture would need a
        -- frame of its own per edge for no real gain at this size.
        line:SetPoint("TOPLEFT", host, "TOPLEFT", math.min(x1, x2), math.min(y1, y2) - 1)
        line:SetWidth(math.max(1, math.abs(x2 - x1)))
        if ns.UI_SetRuleThickness then
            ns.UI_SetRuleThickness(line, "horizontal", LINE_THICKNESS)
        else
            line:SetHeight(LINE_THICKNESS)
        end
    end
    if ns.UI_SnapRuleTexture then ns.UI_SnapRuleTexture(line) end
    line:Show()
end

--- Draw one talent tab: header, tier gates, squares, then the connectors between them.
--[[
    Rank strip under a square (talents and skills): one tick per rank, left to right --
    learned bright, buyable now green, not yet dim. n = 0 hides it (single-rank nodes).
    stateOf(ctx, i) -> "known" | "ready" | "locked".
]]
local RANK_PIP_H = 3
local RANK_PIP_GAP = 1

local function PaintRankStrip(cell, width, n, stateOf, ctx, height)
    height = height or RANK_PIP_H
    local pips = cell._wnPips
    if not pips then pips = {}; cell._wnPips = pips end
    local pipW = n > 0 and math.max(1, math.floor((width - (n - 1) * RANK_PIP_GAP) / n)) or 0
    local used = n * pipW + math.max(0, n - 1) * RANK_PIP_GAP
    local x0 = -math.floor(used / 2)
    local br, bg, bb = 1, 1, 1
    if ns.UI_GetTextRoleRGB then br, bg, bb = ns.UI_GetTextRoleRGB("Bright") end
    local gr, gg, gb = ns.UI_GetSemanticGreenColor()
    local mr, mg, mb = Muted()
    for i = 1, n do
        local pip = pips[i]
        if not pip then
            pip = cell:CreateTexture(nil, "OVERLAY")
            pip:SetTexture("Interface\\Buttons\\WHITE8X8")
            pips[i] = pip
        end
        pip:ClearAllPoints()
        pip:SetSize(pipW, height)
        pip:SetPoint("TOPLEFT", cell, "BOTTOM", x0 + (i - 1) * (pipW + RANK_PIP_GAP), -3)
        local st = stateOf(ctx, i)
        if st == "known" then
            pip:SetVertexColor(br, bg, bb, 1)
        elseif st == "ready" then
            pip:SetVertexColor(gr, gg, gb, 1)
        else
            pip:SetVertexColor(mr, mg, mb, 0.45)
        end
        pip:Show()
    end
    for i = n + 1, #pips do pips[i]:Hide() end
    return n > 0
end

local function TalentRankState(node, i)
    return i <= (node.rank or 0) and "known" or "locked"
end

local function DrawTalentTab(host, tab, pools, counters, left)
    -- Centred over this tree's own node columns (top centre), not pinned to its left edge.
    local cols = math.max(1, tonumber(tab.columns) or 1)
    local span = cols * (TALENT_ICON + TALENT_GAP) - TALENT_GAP
    local header = FontManager:CreateFontString(host, "subtitle", "OVERLAY")
    header:SetPoint("TOP", host, "TOPLEFT", left + TIER_LABEL_W + span / 2, 0)
    header:SetJustifyH("CENTER")
    -- The scan names the bands from the spellbook where it can prove the pairing; the numbered
    -- fallback is what a band gets when it could not.
    header:SetText(tab.name or string.format(L("TALENTS_TREE", "Tree %d"), tab.index))
    ns.UI_SetTextColorRole(header, "Bright")

    local placed = {}
    local top = -24
    for k = 1, #tab.tierOrder do
        local tier = tab.tiers[tab.tierOrder[k]]
        local y = top - (k - 1) * TALENT_ROW_H

        local label = FontManager:CreateFontString(host, "small", "OVERLAY")
        label:SetPoint("TOPLEFT", host, "TOPLEFT", left, y - 12)
        label:SetWidth(TIER_LABEL_W - 6)
        label:SetJustifyH("RIGHT")
        label:SetText(tostring(tier.gate or 0))
        if tier.met then
            ns.UI_SetTextColorRole(label, "Normal")
        else
            label:SetTextColor(Muted())
        end

        for n = 1, #tier.nodes do
            local node = tier.nodes[n]
            counters.icons = counters.icons + 1
            local cell = AcquireIconCell(host, pools.icons, counters.icons, TALENT_ICON)
            if cell then
                local col = (node.column or 1) - 1
                local x = left + TIER_LABEL_W + col * (TALENT_ICON + TALENT_GAP)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
                local taken = (node.rank or 0) > 0
                if cell.texture then
                    cell.texture:SetTexture(node.icon or 134400)
                    cell.texture:SetDesaturated(not taken)
                    cell.texture:SetAlpha(tier.met and 1 or 0.5)
                end
                local maxR = tonumber(node.maxRanks) or 0
                local hasStrip = PaintRankStrip(cell, TALENT_ICON, maxR > 1 and maxR or 0, TalentRankState, node)
                cell.caption:ClearAllPoints()
                cell.caption:SetPoint("TOP", cell, "BOTTOM", 0, hasStrip and -(RANK_PIP_H + 5) or -2)
                cell.caption:SetText(string.format("%d/%d", node.rank or 0, node.maxRanks or 0))
                if taken then
                    ns.UI_SetTextColorRole(cell.caption, "Bright")
                else
                    cell.caption:SetTextColor(Muted())
                end
                cell._wnSpellID = node.spellID
                cell._wnSpellName = node.name
                cell._wnSpellSub = nil
                placed[node.nodeID] = {
                    cx = x + TALENT_ICON / 2,
                    top = y,
                    bottom = y - TALENT_ICON - TALENT_CAPTION_H,
                    taken = taken,
                }
            end
        end
    end

    -- Connectors last: every square has to be placed before a line between two of them can be.
    for k = 1, #tab.tierOrder do
        local tier = tab.tiers[tab.tierOrder[k]]
        for n = 1, #tier.nodes do
            local node = tier.nodes[n]
            local from = placed[node.nodeID]
            if from and node.edges then
                for e = 1, #node.edges do
                    local to = placed[node.edges[e]]
                    if to then
                        counters.lines = counters.lines + 1
                        DrawConnector(host, pools.lines, counters.lines,
                            from.cx, from.bottom, to.cx, to.top, from.taken)
                    end
                end
            end
        end
    end
end

function WarbandNexus:ShowTalentTreePopup(charKey, charName)
    local systems = self.GetCharacterSystems and self:GetCharacterSystems(charKey) or nil
    local talents = systems and systems.talents
    if not talents or not talents.tabs or #talents.tabs == 0 then return end

    local widest, tiers = 1, 0
    for i = 1, #talents.tabs do
        widest = math.max(widest, talents.tabs[i].columns or 1)
        tiers = math.max(tiers, #talents.tabs[i].tierOrder)
    end
    local tabW = TIER_LABEL_W + widest * (TALENT_ICON + TALENT_GAP)
    local gridW = #talents.tabs * tabW + (#talents.tabs - 1) * TAB_GAP
    local lane = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth() or 26)
        + SCROLL_GAP
    local width = math.max(SYSTEMS_POPUP_W, gridW + PAD * 2 + lane)
    local gridH = 24 + tiers * TALENT_ROW_H
    local height = SYSTEMS_POPUP_H

    local dialog, content = CreateExternalWindow({
        name = "CharacterTalentTreePopup",
        title = charName and (charName .. " - " .. L("CHARS_COL_TALENTS", "Talents"))
            or L("CHARS_COL_TALENTS", "Talents"),
        icon = ns.UI_GetIconFile("talents"),
        width = width,
        height = height,
        preventDuplicates = true,
    })
    if not dialog then return end
    ResetContent(content)

    local summary = FontManager:CreateFontString(content, "body", "OVERLAY")
    summary:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
    summary:SetJustifyH("LEFT")
    local parts = {}
    for i = 1, #talents.tabs do parts[#parts + 1] = tostring(talents.tabs[i].spent or 0) end
    local line = string.format("%s: %s", L("TALENTS_SPENT", "Points spent"), table.concat(parts, " / "))
    if (talents.unspent or 0) > 0 then
        line = line .. string.format("    %s: %d", L("TALENTS_UNSPENT", "Unspent points"), talents.unspent)
    end
    summary:SetText(line)
    ns.UI_SetTextColorRole(summary, "Bright")

    local scroll, child = BuildScroll(content, width, 24)
    if not scroll then return end

    dialog._wnPools = dialog._wnPools or { icons = {}, lines = {} }
    local pools = dialog._wnPools
    for i = 1, #pools.icons do pools.icons[i]:Hide() end
    for i = 1, #pools.lines do pools.lines[i]:Hide() end
    local counters = { icons = 0, lines = 0 }

    for i = 1, #talents.tabs do
        DrawTalentTab(child, talents.tabs[i], pools, counters, (i - 1) * (tabW + TAB_GAP))
    end
    child:SetHeight(gridH)
    RefreshScrollBar(scroll)
end

-- ---------------------------------------------------------------------------
-- Skills
-- ---------------------------------------------------------------------------

--- Rank number from a row's sub text ("Rank 3" / localized), nil for unranked spells.
local function RankNumber(entry)
    local sub = entry and entry.subName
    if type(sub) ~= "string" or (issecretvalue and issecretvalue(sub)) then return nil end
    local n = sub:match("(%d+)")
    return n and tonumber(n) or nil
end

--[[
    Skills window, laid out like the talent window.

      Top     one summary line: "Ready to train: 5 skills - 2 ranks" (or "nothing right now").
      Left    one tree per class tab, in TALENT order (Elemental, Enhancement, Restoration for a
              Shaman). Each spell is a square with "learned / total" ranks under it, like a talent's
              "2/5"; every row is one level (label on the left, as the talent tiers are) and holds
              the spells whose first rank comes at that level, so a tree reads top-down by level.
              Spells never learned sit in their tree too: the trainer names their tab
              (skillLine, recorded on a trainer visit).
      Right   "Ready to train" only: icon, name, the rank to buy.

      caption green   a rank is trainable now
      caption bright  every rank learned
      caption muted   nothing to do yet (icon greyed when no rank is learned)

    Hover a square for its rank list (rank, level, learned / ready / locked).
]]
local SKILL_TREE_COLS = 3        -- squares per level row inside one tree (wraps beyond)
local SKILL_ICON_SIZE = 34
local SKILL_NODE_GAP = 14
local SKILL_ROW_STEP = SKILL_ICON_SIZE + 24
local SKILL_TREE_GAP = 16
local SKILL_SUMMARY_H = 30
local SKILL_TREE_HEAD_H = 26
local SKILL_READY_W = 180        -- right-hand "Ready to train" column (3 trees + a 4th fit 960)
local SKILL_READY_ICON = 28
local SKILL_READY_ROW_H = 38
local SKILL_PIP_H = 4            -- skills' rank strip: many ranks, so a touch taller than talents'

local function RankStateText(state)
    if state == "known" then return L("SKILLS_STATE_LEARNED", "Learned") end
    if state == "ready" then return L("SKILLS_READY_TO_TRAIN", "Ready to train") end
    return L("SKILLS_LOCKED_BY_LEVEL", "Needs a higher level")
end

--[[
    Square hover, the way the trainer / spellbook shows a spell:
      the rank that matters -- the one to buy now, else the next locked one, else the highest
      learned -- as a real spell tooltip when its id is known (learned ranks always are), otherwise
      built from what the trainer recorded: name, "Rank N", the spell text, "Requires Level X"
      (red while unmet), and the training cost. Then the rank list, one line per rank.
]]
local function FocusRank(group)
    local ready, locked, known
    for i = 1, #group.ranks do
        local r = group.ranks[i]
        if r.state == "ready" and not ready then ready = r end
        if r.state == "locked" and not locked then locked = r end
        if r.state == "known" then known = r end
    end
    return ready or locked or known
end

local function SkillNodeOnEnter(self)
    local group = self._wnGroup
    if not group or not ns.UI_SafeSetGameTooltipOwner(self, "ANCHOR_RIGHT") then return end
    local tr, tg, tb = ns.UI_GetTooltipTitleColor()
    local br, bg, bb = ns.UI_GetTooltipBodyColor()
    local dr, dg, db = ns.UI_GetTooltipDescColor()
    local gr, gg, gb = ns.UI_GetSemanticGreenColor()
    local focus = FocusRank(group)
    local shown = false
    if focus and focus.spellID and GameTooltip.SetSpellByID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, focus.spellID)
    end
    if not shown then
        GameTooltip:SetText(tostring(group.name or ""), tr, tg, tb)
        if focus and focus.n then
            GameTooltip:AddLine(string.format(L("SKILLS_RANK_FMT", "Rank %d"), focus.n), dr, dg, db)
        end
        if focus and focus.description then
            -- Spell text in WoW's tooltip gold, from the theme (light-mode safe).
            local yr, yg, yb = ns.UI_GetSemanticGoldColor()
            GameTooltip:AddLine(focus.description, yr, yg, yb, true)
        end
    end
    if focus and focus.level and focus.level > 0 and focus.state ~= "known" then
        local lr, lg, lb = br, bg, bb
        if focus.state == "locked" then lr, lg, lb = ns.UI_GetSemanticRedColor() end
        GameTooltip:AddLine(string.format(L("SKILLS_PILL_LEVEL_FMT", "Requires level %d"), focus.level), lr, lg, lb)
    end
    if focus and focus.cost and focus.state ~= "known" and ns.UI_FormatMoney then
        GameTooltip:AddLine(ns.UI_FormatMoney(focus.cost, 12), br, bg, bb)
    end
    if #group.ranks > 1 then GameTooltip:AddLine(" ") end
    for i = 1, (#group.ranks > 1) and #group.ranks or 0 do
        local r = group.ranks[i]
        local left = r.n and string.format(L("SKILLS_RANK_FMT", "Rank %d"), r.n) or ""
        if r.level and r.level > 0 then
            left = (left ~= "" and (left .. "  -  ") or "") .. string.format(L("LEVEL_ABBR_N", "Lv. %d"), r.level)
        end
        local sr, sg, sb = dr, dg, db
        if r.state ~= "locked" then sr, sg, sb = gr, gg, gb end
        GameTooltip:AddDoubleLine(left, RankStateText(r.state), br, bg, bb, sr, sg, sb)
    end
    GameTooltip:Show()
end

--[[
    Model: spell groups (trainer rows + learned ranks folded together), the ready summary, and the
    trees -- one per class spellbook tab, then "Not learned yet".
]]
local function BuildSkillModel(addon, charKey, classFile, level)
    local summary = addon.GetSkillSummary and addon:GetSkillSummary(charKey, classFile, level) or nil
    local systems = addon.GetCharacterSystems and addon:GetCharacterSystems(charKey) or nil
    local spells = systems and systems.spells
    local classLines = tonumber(spells and spells.classLineCount) or 0
    local talentTabs = systems and systems.talents and systems.talents.tabs or nil

    -- Learned ranks per spell name, and the class tab each learned spell sits in.
    local knownRanks, knownEntry, lineOf, treeOrder = {}, {}, {}, {}
    if spells and spells.lines then
        for i = 1, #spells.lines do
            local line = spells.lines[i]
            -- Spec tabs only: index 1 is General, past classLineCount are professions.
            local isClassTab = line.index and line.index > 1 and line.index <= classLines
            if isClassTab then treeOrder[#treeOrder + 1] = line.name end
            for s = 1, #(line.spells or {}) do
                local sp = line.spells[s]
                if sp.name and sp.known ~= false then
                    local key = tostring(sp.name)
                    knownEntry[key] = knownEntry[key] or sp
                    if isClassTab then lineOf[key] = lineOf[key] or line.name end
                    knownRanks[key] = knownRanks[key] or {}
                    knownRanks[key][RankNumber(sp) or 0] = sp
                end
            end
        end
    end

    -- Talent order when the talent tabs carry the same names (they are named FROM these lines).
    if talentTabs and #talentTabs > 0 then
        local inBook, ordered, seen = {}, {}, {}
        for i = 1, #treeOrder do inBook[treeOrder[i]] = true end
        for i = 1, #talentTabs do
            local nm = talentTabs[i].name
            if nm and inBook[nm] and not seen[nm] then ordered[#ordered + 1] = nm; seen[nm] = true end
        end
        for i = 1, #treeOrder do
            if not seen[treeOrder[i]] then ordered[#ordered + 1] = treeOrder[i] end
        end
        treeOrder = ordered
    end

    local groups, byName = {}, {}
    local function groupFor(name, icon)
        local key = tostring(name)
        local g = byName[key]
        if not g then
            g = { name = name, icon = icon, ranks = {}, hasReady = false, firstLevel = 999 }
            byName[key] = g
            groups[#groups + 1] = g
        end
        g.icon = g.icon or icon
        return g
    end
    local readySkills, readyRanks = 0, 0
    local function addTrainer(row, state)
        local g = groupFor(row.name, row.icon)
        g.skillLine = g.skillLine or row.skillLine
        local lvl = tonumber(row.level)
        g.ranks[#g.ranks + 1] = { n = RankNumber(row), state = state, level = lvl, spellID = row.spellID,
            description = row.description, cost = row.cost }
        if lvl and lvl < g.firstLevel then g.firstLevel = lvl end
        if lvl then g.hasLevel = true end
        if state == "ready" then
            g.hasReady = true
            if knownRanks[tostring(row.name)] then readyRanks = readyRanks + 1 else readySkills = readySkills + 1 end
        end
    end
    if summary then
        for i = 1, #summary.trainable do addTrainer(summary.trainable[i], "ready") end
        for i = 1, #summary.locked do addTrainer(summary.locked[i], "locked") end
    end
    -- Learned class spells (no trainer row needed for them to show).
    for key, ranks in pairs(knownRanks) do
        if lineOf[key] then
            local e = knownEntry[key]
            local g = groupFor(e.name, e.icon)
            for n, sp in pairs(ranks) do
                local lvl = tonumber(sp.level)
                g.ranks[#g.ranks + 1] = { n = (n > 0) and n or nil, state = "known", level = lvl, spellID = sp.spellID }
                if lvl and lvl > 0 and lvl < g.firstLevel then g.firstLevel = lvl end
            end
        end
    end
    for i = 1, #groups do
        local g = groups[i]
        table.sort(g.ranks, function(a, b)
            if a.n and b.n then return a.n < b.n end
            if (a.n == nil) ~= (b.n == nil) then return a.n ~= nil end
            return (a.level or 0) < (b.level or 0)
        end)
        local learned, total = 0, 0
        for r = 1, #g.ranks do
            total = total + 1
            if g.ranks[r].state == "known" then learned = learned + 1 end
        end
        g.learned, g.total = learned, total
        if g.firstLevel == 999 then g.firstLevel = 1 end
    end

    -- Trees: class tabs (talent order). A spell goes to its learned tab, else the trainer's tab.
    local trees, byTree, ready = {}, {}, {}
    for i = 1, #treeOrder do
        local t = { title = treeOrder[i], groups = {} }
        trees[#trees + 1] = t
        byTree[treeOrder[i]] = t
    end
    --[[
        What is left after the class tabs:
          Weapon & Armor Skills  the trainer filed it under a non-class header (weapon master,
                                 armor), or it has no level requirement at all (weapon skills)
          Not learned yet        a class spell whose tab the trainer has not named yet -- only
                                 until the next trainer visit records the header; then it moves
                                 into its own tree and this one disappears
    ]]
    local weaponArmor, untabbed = {}, {}
    for i = 1, #groups do
        local g = groups[i]
        local key = tostring(g.name)
        local t = byTree[lineOf[key] or g.skillLine or ""]
        if t then
            t.groups[#t.groups + 1] = g
        elseif not knownRanks[key] then
            if g.skillLine or not g.hasLevel then
                weaponArmor[#weaponArmor + 1] = g
            else
                untabbed[#untabbed + 1] = g
            end
        end
        if g.hasReady then ready[#ready + 1] = g end
    end
    if #weaponArmor > 0 then
        trees[#trees + 1] = { title = L("SKILLS_WEAPON_ARMOR", "Weapon & Armor Skills"), groups = weaponArmor }
    end
    if #untabbed > 0 then
        trees[#trees + 1] = { title = L("SKILLS_NOT_LEARNED_YET", "Not learned yet"), groups = untabbed }
    end
    local function byLevelName(a, b)
        if a.firstLevel ~= b.firstLevel then return a.firstLevel < b.firstLevel end
        return tostring(a.name) < tostring(b.name)
    end
    local kept = {}
    for i = 1, #trees do
        if #trees[i].groups > 0 then
            table.sort(trees[i].groups, byLevelName)
            kept[#kept + 1] = trees[i]
        end
    end
    table.sort(ready, byLevelName)
    return {
        hasTrainerData = summary and summary.hasTrainerData or false,
        readySkills = readySkills,
        readyRanks = readyRanks,
        trees = kept,
        ready = ready,
    }
end

--- One tree: centred title, then band rows (level label on the left) of squares.
--- Returns the tree's height.
local function RankOrder(a, b)
    local an, bn = a.n or 0, b.n or 0
    if an ~= bn then return an < bn end
    return (a.level or 0) < (b.level or 0)
end

local function SkillRankState(group, i) return group.ranks[i].state end

local function DrawSkillTree(host, tree, pool, counters, left)
    local span = SKILL_TREE_COLS * (SKILL_ICON_SIZE + SKILL_NODE_GAP) - SKILL_NODE_GAP
    local header = FontManager:CreateFontString(host, "subtitle", "OVERLAY")
    header:SetPoint("TOP", host, "TOPLEFT", left + TIER_LABEL_W + span / 2, 0)
    header:SetJustifyH("CENTER")
    header:SetText(tostring(tree.title or ""))
    ns.UI_SetTextColorRole(header, "Bright")

    -- One row per level: the spells whose first rank comes at that level (wraps past the columns).
    local bands, bandOrder = {}, {}
    for i = 1, #tree.groups do
        local g = tree.groups[i]
        table.sort(g.ranks, RankOrder)
        local b = math.max(1, tonumber(g.firstLevel) or 1)
        if not bands[b] then bands[b] = {}; bandOrder[#bandOrder + 1] = b end
        bands[b][#bands[b] + 1] = g
    end
    table.sort(bandOrder)

    local gr, gg, gb = ns.UI_GetSemanticGreenColor()
    local y = -SKILL_TREE_HEAD_H
    for bi = 1, #bandOrder do
        local list = bands[bandOrder[bi]]
        local label = FontManager:CreateFontString(host, "small", "OVERLAY")
        label:SetPoint("TOPLEFT", host, "TOPLEFT", left, y - 12)
        label:SetWidth(TIER_LABEL_W - 6)
        label:SetJustifyH("RIGHT")
        label:SetText(tostring(bandOrder[bi]))
        label:SetTextColor(Muted())
        for k = 1, #list do
            local g = list[k]
            local col = (k - 1) % SKILL_TREE_COLS
            local rowY = y - math.floor((k - 1) / SKILL_TREE_COLS) * SKILL_ROW_STEP
            counters.icons = counters.icons + 1
            local cell = AcquireIconCell(host, pool, counters.icons, SKILL_ICON_SIZE)
            if cell then
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", host, "TOPLEFT",
                    left + TIER_LABEL_W + col * (SKILL_ICON_SIZE + SKILL_NODE_GAP), rowY)
                --[[
                    WoW's trainer / spellbook language, three states:
                      learned     full colour, normal frame, "learned / total"
                      learnable   full colour, GREEN frame and caption (a rank can be bought now)
                      not yet     greyed icon, frame dimmed, level requirement in RED
                ]]
                local unlearned = g.learned == 0
                local notYet = unlearned and not g.hasReady
                local isReady = g.hasReady
                if cell.texture then
                    cell.texture:SetTexture(g.icon or 134400)
                    cell.texture:SetDesaturated(notYet)
                    cell.texture:SetAlpha(notYet and 0.7 or 1)
                end
                if cell.SetBackdropBorderColor then
                    if not cell._wnDefaultBorder and cell.GetBackdropBorderColor then
                        cell._wnDefaultBorder = { cell:GetBackdropBorderColor() }
                    end
                    local d = cell._wnDefaultBorder
                    if isReady then
                        cell:SetBackdropBorderColor(gr, gg, gb, 1)
                    elseif d then
                        cell:SetBackdropBorderColor(d[1], d[2], d[3], notYet and 0.35 or (d[4] or 1))
                    end
                end
                --[[
                    Caption = the next step (the strip above already shows how far along it is):
                      all learned       green check
                      buyable now       green "R4" (the rank to buy)
                      next is locked    red "Lv. 14" (when the next rank opens)
                ]]
                local nextReady, nextLocked
                for r = 1, #g.ranks do
                    local rr = g.ranks[r]
                    if rr.state == "ready" and not nextReady then nextReady = rr end
                    if rr.state == "locked" and not nextLocked then nextLocked = rr end
                end
                local hasStrip = PaintRankStrip(cell, SKILL_ICON_SIZE + SKILL_NODE_GAP - 6,
                    (#g.ranks > 1) and #g.ranks or 0, SkillRankState, g, SKILL_PIP_H)
                cell.caption:ClearAllPoints()
                cell.caption:SetPoint("TOP", cell, "BOTTOM", 0, hasStrip and -(SKILL_PIP_H + 5) or -2)
                if nextReady then
                    cell.caption:SetText(nextReady.n and ("R" .. nextReady.n) or "")
                    cell.caption:SetTextColor(gr, gg, gb)
                elseif nextLocked and nextLocked.level then
                    cell.caption:SetText(string.format(L("LEVEL_ABBR_N", "Lv. %d"), nextLocked.level))
                    cell.caption:SetTextColor(ns.UI_GetSemanticRedColor())
                elseif g.total > 0 and g.learned >= g.total and ns.UI_GetIconMarkup then
                    cell.caption:SetText(ns.UI_GetIconMarkup("status_ok", 12, 12) or "")
                    cell.caption:SetTextColor(gr, gg, gb)
                else
                    cell.caption:SetText("")
                end
                cell._wnGroup = g
                cell:SetScript("OnEnter", SkillNodeOnEnter)
            end
        end
        y = y - math.ceil(#list / SKILL_TREE_COLS) * SKILL_ROW_STEP
    end
    return -y
end

--- Right-hand column: "Ready to train (n)", then one line per spell: icon, name, rank to buy.
local function DrawReadyColumn(host, ready, pool, counters, left)
    local header = FontManager:CreateFontString(host, "subtitle", "OVERLAY")
    header:SetPoint("TOPLEFT", host, "TOPLEFT", left, 0)
    header:SetJustifyH("LEFT")
    header:SetText(string.format("%s  (%d)", L("SKILLS_READY_TO_TRAIN", "Ready to train"), #ready))
    ns.UI_SetTextColorRole(header, "Bright")
    local gr, gg, gb = ns.UI_GetSemanticGreenColor()
    local y = -SKILL_TREE_HEAD_H
    if #ready == 0 then
        local none = FontManager:CreateFontString(host, "small", "OVERLAY")
        none:SetPoint("TOPLEFT", host, "TOPLEFT", left, y)
        none:SetWidth(SKILL_READY_W)
        none:SetJustifyH("LEFT")
        none:SetText(L("SKILLS_NOTHING_TO_TRAIN", "Nothing to learn right now"))
        ns.UI_SetTextColorRole(none, "Muted")
        return SKILL_TREE_HEAD_H + 20
    end
    for i = 1, #ready do
        local g = ready[i]
        counters.icons = counters.icons + 1
        local cell = AcquireIconCell(host, pool, counters.icons, SKILL_READY_ICON)
        if cell then
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", host, "TOPLEFT", left, y)
            if cell.texture then
                cell.texture:SetTexture(g.icon or 134400)
                cell.texture:SetDesaturated(false)
            end
            cell.caption:SetText("")
            if cell._wnPips then
                for p = 1, #cell._wnPips do cell._wnPips[p]:Hide() end
            end
            cell._wnGroup = g
            cell:SetScript("OnEnter", SkillNodeOnEnter)
        end
        local name = FontManager:CreateFontString(host, "body", "OVERLAY")
        name:SetPoint("TOPLEFT", host, "TOPLEFT", left + SKILL_READY_ICON + 8, y - 1)
        name:SetWidth(SKILL_READY_W - SKILL_READY_ICON - 8)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(tostring(g.name or ""))
        ns.UI_SetTextColorRole(name, "Bright")
        -- The rank(s) to buy now, e.g. "Rank 3"; unranked skills just say they are trainable.
        local buy = {}
        for r = 1, #g.ranks do
            local rk = g.ranks[r]
            if rk.state == "ready" and rk.n then buy[#buy + 1] = string.format(L("SKILLS_RANK_FMT", "Rank %d"), rk.n) end
        end
        local sub = FontManager:CreateFontString(host, "small", "OVERLAY")
        sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        sub:SetWidth(SKILL_READY_W - SKILL_READY_ICON - 8)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(#buy > 0 and table.concat(buy, ", ") or L("SKILLS_READY_TO_TRAIN", "Ready to train"))
        sub:SetTextColor(gr, gg, gb)
        y = y - SKILL_READY_ROW_H
    end
    return -y
end

function WarbandNexus:ShowSkillsPopup(charKey, charName, classFile, level)
    local model = BuildSkillModel(self, charKey, classFile, level)
    if #model.trees == 0 and not model.hasTrainerData then return end

    local dialog, content = CreateExternalWindow({
        name = "CharacterSkillsPopup",
        title = charName and (charName .. " - " .. L("CHARS_COL_SKILLS", "Skills"))
            or L("CHARS_COL_SKILLS", "Skills"),
        icon = ns.UI_GetIconFile("skills"),
        width = SYSTEMS_POPUP_W,
        height = SYSTEMS_POPUP_H,
        preventDuplicates = true,
    })
    if not dialog then return end
    ResetContent(content)

    -- Summary line above the trees: the answer to "is there anything to go train?".
    local summaryFs = FontManager:CreateFontString(content, "body", "OVERLAY")
    summaryFs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
    summaryFs:SetJustifyH("LEFT")
    if not model.hasTrainerData then
        summaryFs:SetText(L("SKILLS_VISIT_TRAINER", "Visit your class trainer once to list trainable skills"))
        ns.UI_SetTextColorRole(summaryFs, "Muted")
    elseif model.readySkills + model.readyRanks == 0 then
        summaryFs:SetText(L("SKILLS_NOTHING_TO_TRAIN", "Nothing to learn right now"))
        ns.UI_SetTextColorRole(summaryFs, "Muted")
    else
        summaryFs:SetText(string.format(L("SKILLS_READY_SUMMARY_FMT", "Ready to train: %d skills - %d ranks"),
            model.readySkills, model.readyRanks))
        summaryFs:SetTextColor(ns.UI_GetSemanticGreenColor())
    end

    local scroll, child, contentW = BuildScroll(content, SYSTEMS_POPUP_W, SKILL_SUMMARY_H)
    if not scroll then return end

    dialog._wnSkillPool = dialog._wnSkillPool or {}
    local pool = dialog._wnSkillPool
    for i = 1, #pool do pool[i]:Hide() end
    local counters = { icons = 0 }

    -- Trees on the left, "Ready to train" pinned to the right edge.
    local treeW = TIER_LABEL_W + SKILL_TREE_COLS * (SKILL_ICON_SIZE + SKILL_NODE_GAP) - SKILL_NODE_GAP
    local n = #model.trees
    local tallest = 0
    for i = 1, n do
        local h = DrawSkillTree(child, model.trees[i], pool, counters, (i - 1) * (treeW + SKILL_TREE_GAP))
        if h > tallest then tallest = h end
    end
    local readyLeft = math.max(n * (treeW + SKILL_TREE_GAP), (contentW or 0) - SKILL_READY_W)
    local readyH = DrawReadyColumn(child, model.ready, pool, counters, readyLeft)
    if readyH > tallest then tallest = readyH end
    child:SetHeight(math.max(1, tallest))
    RefreshScrollBar(scroll)
end


-- ---------------------------------------------------------------------------
-- Profession recipes
-- ---------------------------------------------------------------------------

--[[
    Same shape as the Skills window: sections of five icons across, the real tooltip on hover.

    Two differences, both forced by what the client publishes. There is no skill requirement on a
    recipe, so nothing can sit under the icon the way "Lv. 20" does -- the caption is dropped
    rather than filled with something invented. And there is no "can learn now" split for the same
    reason: that lives on the profession trainer, not in the recipe record.
]]
function WarbandNexus:ShowProfessionRecipesPopup(charKey, charName, professionID)
    local entry = self.GetProfessionRecipes and self:GetProfessionRecipes(charKey, professionID)
    if not entry or not entry.recipes or #entry.recipes == 0 then return end

    local learned, missing = {}, {}
    for i = 1, #entry.recipes do
        local recipe = entry.recipes[i]
        if recipe.learned then
            learned[#learned + 1] = recipe
        else
            missing[#missing + 1] = recipe
        end
    end

    local sections = {
        { title = L("RECIPES_KNOWN", "Known recipes"), rows = learned, tone = "known",
          emptyText = L("RECIPES_NONE_KNOWN", "None learned yet") },
        { title = L("RECIPES_NOT_LEARNED", "Not learned"), rows = missing, tone = "locked",
          emptyText = L("RECIPES_ALL_LEARNED", "Everything here is learned") },
    }

    local lane = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth() or 26)
        + SCROLL_GAP
    local width = PAD * 2 + SKILL_COLUMNS * SKILL_CELL_W + lane
    local gridH = 28
    for i = 1, #sections do
        local rows = math.ceil(#sections[i].rows / SKILL_COLUMNS)
        gridH = gridH + SECTION_HEAD_H + rows * SKILL_CELL_H
        if #sections[i].rows == 0 then gridH = gridH + SECTION_HEAD_H end
    end
    local height = math.min(700, gridH + 70)

    local title = entry.name or L("TAB_PROFESSIONS", "Professions")
    local dialog, content = CreateExternalWindow({
        name = "CharacterProfessionRecipesPopup",
        title = charName and (charName .. " - " .. title) or title,
        icon = ns.UI_GetIconFile("anvil"),
        width = width,
        height = height,
        preventDuplicates = true,
    })
    if not dialog then return end
    ResetContent(content)

    local head = FontManager:CreateFontString(content, "body", "OVERLAY")
    head:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
    head:SetJustifyH("LEFT")
    head:SetText(string.format("%s  %d / %d", title, entry.skillLevel or 0, entry.maxSkillLevel or 0))
    ns.UI_SetTextColorRole(head, "Bright")

    local scroll, child, contentW = BuildScroll(content, width, 22)
    if not scroll then return end

    dialog._wnRecipePool = dialog._wnRecipePool or {}
    local pool = dialog._wnRecipePool
    for i = 1, #pool do pool[i]:Hide() end

    local y, used = 0, 0
    for s = 1, #sections do
        local section = sections[s]
        local label = FontManager:CreateFontString(child, "subtitle", "OVERLAY")
        label:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        label:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)
        label:SetJustifyH("LEFT")
        label:SetText(string.format("%s  (%d)", section.title, #section.rows))
        ns.UI_SetTextColorRole(label, "Bright")
        y = y - SECTION_HEAD_H

        if #section.rows == 0 then
            local note = FontManager:CreateFontString(child, "small", "OVERLAY")
            note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            note:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)
            note:SetJustifyH("LEFT")
            note:SetText(section.emptyText or "")
            note:SetTextColor(Muted())
            y = y - SECTION_HEAD_H
        end

        for r = 1, #section.rows do
            local recipe = section.rows[r]
            used = used + 1
            local cell = AcquireIconCell(child, pool, used, SKILL_ICON)
            if cell then
                local col = (r - 1) % SKILL_COLUMNS
                local gridRow = math.floor((r - 1) / SKILL_COLUMNS)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", child, "TOPLEFT",
                    col * SKILL_CELL_W + (SKILL_CELL_W - SKILL_ICON) / 2,
                    y - gridRow * SKILL_CELL_H)
                if cell.texture then
                    cell.texture:SetTexture(recipe.icon or 134400)
                    cell.texture:SetDesaturated(not recipe.learned)
                end
                cell.caption:SetText("")
                cell._wnSpellID = recipe.id
                cell._wnSpellName = recipe.name
                cell._wnSpellSub = nil
            end
        end
        y = y - math.ceil(#section.rows / SKILL_COLUMNS) * SKILL_CELL_H
    end
    child:SetHeight(math.max(1, -y))
    RefreshScrollBar(scroll)
end
