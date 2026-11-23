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
local function BuildScroll(content, width, topInset, pad)
    pad = pad or PAD
    if not Factory or not Factory.CreateScrollFrame or not Factory.CreateContainer then return nil end
    local barW = ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth() or 26

    local column = Factory.CreateBareScrollBarColumn
        and Factory:CreateBareScrollBarColumn(content, barW)
        or Factory:CreateScrollBarColumn(content, barW, 0, 0)
    local scroll = Factory:CreateScrollFrame(content, "UIPanelScrollFrameTemplate", true)
    if not scroll or not column then return nil end

    -- Initial placement, lane reserved: the wire below replaces the bottom-right point on the
    -- first visibility pass, but the frame has to be somewhere until then.
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -(pad + (topInset or 0)))
    scroll:SetPoint("BOTTOMRIGHT", column, "BOTTOMLEFT", -SCROLL_GAP, pad)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    if ns.UI_EnableStandardScrollWheel then ns.UI_EnableStandardScrollWheel(scroll) end

    -- One wire, the caller's own insets: the top one differs per window (a summary line sits
    -- above the grid in two of the three).
    if Factory.WireScrollLaneWithInsets then
        Factory:WireScrollLaneWithInsets(scroll, content, column, {
            left = pad, top = pad + (topInset or 0), right = SCROLL_EDGE, bottom = pad, gap = SCROLL_GAP,
        })
    elseif Factory.EnsureScrollBarColumnSync then
        Factory:EnsureScrollBarColumnSync(scroll, column, { width = barW, gap = SCROLL_GAP })
    end

    local lane = barW + SCROLL_GAP
    local contentW = width - pad - SCROLL_EDGE - lane
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
    Laid out like the retail Professions frame, because that is the window players already read:
    a recipe tree on the left (category headers that collapse, recipes under them in the
    profession's own order, a skill-up marker in front of each one that still gives points) and
    the selected recipe on the right (product, reagents with counts, learned state).

    Everything comes from the character's saved row, so an offline alt reads exactly like the
    character that is logged in. Learned recipes use the recipe ink, unlearned ones the dim ink,
    the same split Blizzard's list makes; the difficulty is carried by the skill-up marker rather
    than by recolouring the name, which keeps the list readable in the light theme too.

    Data captured by an older build has no categories, difficulty or reagents: those recipes land
    in one "Other" group and the detail pane simply leaves the missing parts out.
]]
local RECIPE_WIN_W = 860
local RECIPE_WIN_H = 640
local RECIPE_LIST_W = 360
local RECIPE_PANE_GAP = 10
local RECIPE_TOP_H = 46
local RECIPE_ROW_H = 24
local RECIPE_CAT_H = 26
local RECIPE_INDENT = 14
local RECIPE_ICON = 20
local RECIPE_LIST_PAD = 6
local DETAIL_ICON = 48
local REAGENT_ICON = 38
local REAGENT_ROW_H = 46
local RECIPE_SEARCH_W = 220
local RECIPE_RANK_W = 180
local RECIPE_RANK_H = 12
local OTHER_CATEGORY = 0

-- Blizzard_ProfessionsRecipeList.lua draws these markers; checked with C_Texture.GetAtlasInfo
-- before use so a client without them falls back to a coloured dot.
local SKILLUP_ATLAS = {
    [0] = "Professions-Icon-Skill-High",
    [1] = "Professions-Icon-Skill-Medium",
    [2] = "Professions-Icon-Skill-Low",
}
local COLLAPSE_ATLAS = "Professions-recipe-header-collapse"
local EXPAND_ATLAS = "Professions-recipe-header-expand"
local DIFFICULTY_RGB = {
    [0] = { 1.00, 0.50, 0.25 },
    [1] = { 1.00, 1.00, 0.00 },
    [2] = { 0.25, 0.75, 0.25 },
}

-- Per profession, per window lifetime of the session: collapsed headers, the filter, the pick.
local recipeViewState = {}

local function AtlasExists(atlas)
    if not atlas or type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and info ~= nil
end

local function SetAtlasOrHide(tex, atlas)
    if atlas and AtlasExists(atlas) then
        tex:SetAtlas(atlas)
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

-- COLORS lives on ns at call time (theme swaps mutate it in place).
local function AccentRGB()
    local c = ns.UI_COLORS and ns.UI_COLORS.accent
    return c or { 0.5, 0.4, 0.7 }
end

local function GoldHex()
    local hex = ns.UI_HEX
    return (hex and hex.gold) or "|cffffd100"
end

--- Recipe tooltip: the captured hyperlink first (it renders offline), then the recipe spell.
--[[
    Recipe window tooltips open beside the window, never on top of it: anchored to the owner they
    covered the reagent list they describe. The window is the tip host; the tooltip goes to its
    right edge, or its left when the screen has no room there. Owners outside the recipe window
    have no host and keep the plain owner anchor.
]]
local function TipHost(owner)
    return owner and (owner._wnTipHost or (owner._wnDetail and owner._wnDetail.host)) or nil
end

local function TipAnchor(owner)
    return TipHost(owner) and "ANCHOR_NONE" or "ANCHOR_RIGHT"
end

local function PlaceTipBeside(owner)
    local host = TipHost(owner)
    if not host or not GameTooltip:IsOwned(owner) then return end
    local hl, hr = host:GetLeft(), host:GetRight()
    local screenR = UIParent:GetRight()
    if not hl or not hr or not screenR then return end
    -- Compare in screen pixels: the window, the tooltip and UIParent can each carry their own scale.
    local hs, ts, us = host:GetEffectiveScale(), GameTooltip:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local tipW = (GameTooltip:GetWidth() or 0) * ts
    GameTooltip:ClearAllPoints()
    if hr * hs + tipW + 8 <= screenR * us or hl * hs < tipW + 8 then
        GameTooltip:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    else
        GameTooltip:SetPoint("TOPRIGHT", host, "TOPLEFT", -4, 0)
    end
end

local function RecipeTooltipOnEnter(self)
    local recipe = self._wnRecipe
    if not recipe or not ns.UI_SafeSetGameTooltipOwner(self, TipAnchor(self)) then return end
    if not (recipe.link and GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, recipe.link))
        and not (recipe.id and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, recipe.id)) then
        GameTooltip:SetText(recipe.name or "")
    end
    GameTooltip:Show()
    PlaceTipBeside(self)
end

local function ItemTooltipOnEnter(self)
    local itemID = self._wnItemID
    if not itemID or not ns.UI_SafeSetGameTooltipOwner(self, TipAnchor(self)) then return end
    if GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, itemID) then
        GameTooltip:Show()
        PlaceTipBeside(self)
    else
        ns.UI_SafeHideGameTooltip()
    end
end

--[[
    Category tree from the saved entry.

    Each node: { id, name, parent, depth, children, recipes, order, learned, total }. A recipe's
    category is a leaf; its parents come from the stored parent chain. Order follows the lowest
    api index found under a node, which reproduces the profession window's own ordering without
    having stored it separately.
]]
local function BuildRecipeTree(entry, query)
    local cats = type(entry.categories) == "table" and entry.categories or {}
    local nodes, roots = {}, {}

    local function Node(id)
        local n = nodes[id]
        if n then return n end
        local info = cats[id]
        n = {
            id = id,
            name = (info and info.name) or L("RECIPES_UNCATEGORIZED", "Other"),
            parent = info and info.parent or nil,
            rank = info and info.rank, rankMax = info and info.rankMax, rankStart = info and info.rankStart,
            children = {}, recipes = {}, order = math.huge, learned = 0, total = 0,
        }
        nodes[id] = n
        -- Refuse a parent link that would loop back to this node: a malformed chain must not
        -- hang the walks below.
        local cyclic, up, guard = false, n.parent, 0
        while up and guard < 8 do
            if up == id then cyclic = true break end
            up = cats[up] and cats[up].parent or nil
            guard = guard + 1
        end
        if n.parent and not cyclic and cats[n.parent] then
            local p = Node(n.parent)
            p.children[#p.children + 1] = n
        else
            n.parent = nil
            roots[#roots + 1] = n
        end
        return n
    end

    for i = 1, #entry.recipes do
        local r = entry.recipes[i]
        local name = r.name
        local match = true
        if query then
            match = type(name) == "string" and name:lower():find(query, 1, true) ~= nil
        end
        if match then
            local n = Node(r.categoryID or OTHER_CATEGORY)
            n.recipes[#n.recipes + 1] = r
            local order = tonumber(r.order) or (100000 + i)
            -- Counts and order bubble up so a header shows its whole subtree.
            local walk = n
            while walk do
                walk.total = walk.total + 1
                if r.learned then walk.learned = walk.learned + 1 end
                if order < walk.order then walk.order = order end
                walk = walk.parent and nodes[walk.parent] or nil
            end
        end
    end

    local function ByOrder(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return (a.name or "") < (b.name or "")
    end
    local function SortRecipes(a, b)
        local oa, ob = tonumber(a.order) or math.huge, tonumber(b.order) or math.huge
        if oa ~= ob then return oa < ob end
        return (a.name or "") < (b.name or "")
    end
    local function SortNode(n, depth)
        n.depth = depth
        table.sort(n.children, ByOrder)
        table.sort(n.recipes, SortRecipes)
        for i = 1, #n.children do SortNode(n.children[i], depth + 1) end
    end
    table.sort(roots, ByOrder)
    for i = 1, #roots do SortNode(roots[i], 0) end
    return roots
end

--- Flatten the tree into the visible rows: headers always, recipes only under open headers.
local function FlattenRecipeTree(roots, state, out)
    local function Walk(n)
        if n.total == 0 then return end
        out[#out + 1] = { kind = "category", node = n, depth = n.depth }
        if state.collapsed[n.id] then return end
        for i = 1, #n.children do Walk(n.children[i]) end
        for i = 1, #n.recipes do
            local r = n.recipes[i]
            if state.showUnlearned or r.learned then
                out[#out + 1] = { kind = "recipe", recipe = r, depth = n.depth + 1 }
            end
        end
    end
    for i = 1, #roots do Walk(roots[i]) end
    return out
end

-- Row geometry the list paints with; one table so the chunk's local budget is not spent on it.
local RL = {
    MARKER_W = 14,       -- fixed skill-up slot: every label starts at the same x per depth
    ICON_GAP = 4,
    LABEL_GAP = 6,
    BAR_W = 70,          -- category rank bar (retail expansion headers)
    BAR_H = 6,
    WELL_ALPHA = 0.55,
}

local function QualityRGB(itemID)
    if not itemID or not C_Item then return nil end
    local quality
    if C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
        if ok and type(q) == "number" then quality = q end
    end
    if not quality or not C_Item.GetItemQualityColor then return nil end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if ok and type(r) == "number" then return r, g, b end
    return nil
end

--- Bags + bank of one character for an item; nil when the count service is unavailable.
--- Memoised per window open: the list asks for the same reagent on many rows.
local function CharacterHaveCount(charKey, itemID, memo)
    if not charKey or not itemID or not WarbandNexus.GetDetailedItemCountsFast then return nil end
    if memo and memo[itemID] ~= nil then return memo[itemID] end
    local ok, counts = pcall(WarbandNexus.GetDetailedItemCountsFast, WarbandNexus, itemID)
    if not ok then return nil end
    local total = 0
    if type(counts) == "table" and type(counts.characters) == "table" then
        local U = ns.Utilities
        local want = (U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(charKey)) or charKey
        for i = 1, #counts.characters do
            local row = counts.characters[i]
            local k = row.charKey
            local canon = (k and U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(k)) or k
            if k == charKey or canon == want then total = tonumber(row.total) or 0 break end
        end
    end
    -- Crafting draws from the Warband Bank too (ItemUtil.GetCraftingReagentCount: includeAccountBank).
    if type(counts) == "table" then total = total + (tonumber(counts.warbandBank) or 0) end
    if memo then memo[itemID] = total end
    return total
end

--- Held count for one reagent slot: every quality tier it accepts counts, as the retail slot does.
local function ReagentHaveCount(charKey, rg, memo)
    local tiers = type(rg.tiers) == "table" and rg.tiers or nil
    if not tiers then return CharacterHaveCount(charKey, rg.itemID, memo) end
    local total
    for t = 1, #tiers do
        local n = CharacterHaveCount(charKey, tiers[t].itemID, memo)
        if n then total = (total or 0) + n end
    end
    return total
end

--- How many times the character could make a learned recipe from what it holds; the retail list
--- shows this as " [n]" after the name (GetCraftableCount, live-only -- rebuilt from saved bags).
local function CraftableCount(recipe, charKey, memo)
    local reagents = recipe.learned and type(recipe.reagents) == "table" and recipe.reagents
    if not reagents or #reagents == 0 then return nil end
    local best
    for i = 1, #reagents do
        local need = tonumber(reagents[i].count) or 1
        local have = ReagentHaveCount(charKey, reagents[i], memo)
        if have == nil then return nil end
        local n = math.floor(have / math.max(1, need))
        if not best or n < best then best = n end
    end
    return best
end

local function AcquireRecipeRow(child, pool, index)
    local row = pool[index]
    if not row then
        row = Factory:CreateButton(child, 10, RECIPE_ROW_H, true)
        if not row then return nil end
        if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.arrow = row:CreateTexture(nil, "ARTWORK")
        row.arrow:SetSize(13, 13)
        row.skillUp = row:CreateTexture(nil, "ARTWORK")
        row.skillUp:SetSize(RL.MARKER_W, RL.MARKER_W)
        row.skillUpText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.skillUpText:SetPoint("CENTER", row.skillUp, "CENTER", 0, 0)
        -- Bordered icon well, the same chrome every other WN icon uses, instead of a bare texture.
        row.iconWell = CreateIcon(row, nil, RECIPE_ICON, false,
            { 0.35, 0.35, 0.40, RL.WELL_ALPHA }, false)
        if row.iconWell and row.iconWell.texture then
            row.iconWell.texture:SetTexCoord(SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM, SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM)
        end
        row.label = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.count = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.count:SetJustifyH("RIGHT")
        row.bar = Factory.CreateProgressBar and Factory:CreateProgressBar(row, RL.BAR_W, RL.BAR_H)
        if row.bar then row.bar:Hide() end
        row:SetScript("OnLeave", SpellTooltipOnLeave)
        pool[index] = row
    end
    row:SetParent(child)
    row:Show()
    return row
end

local function PaintCategoryRow(row, item, state)
    local n = item.node
    local indent = item.depth * RECIPE_INDENT
    row:SetHeight(RECIPE_CAT_H)
    row.selected:Hide()
    if row.iconWell then row.iconWell:Hide() end
    row.skillUp:Hide()
    row.skillUpText:Hide()
    row._wnRecipe = nil
    row:SetScript("OnEnter", nil)

    local collapsed = state.collapsed[n.id] and true or false
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("LEFT", row, "LEFT", indent + 2, 0)
    local hasArrow = SetAtlasOrHide(row.arrow, collapsed and EXPAND_ATLAS or COLLAPSE_ATLAS)

    -- Right side: the expansion rank bar where the client has one (retail headers), else the
    -- learned / total count.
    row.count:ClearAllPoints()
    row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    ns.UI_SetTextColorRole(row.count, "Muted")
    row.count:Show()
    local rightAnchor = row.count
    if row.bar and n.rank and n.rankMax and n.rankMax > 0 then
        row.count:SetText(string.format("%d/%d", n.rank, n.rankMax))
        row.bar:ClearAllPoints()
        row.bar:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        if row.bar.SetMinMaxValues then
            row.bar:SetMinMaxValues(n.rankStart or 0, n.rankMax)
            row.bar:SetValue(math.min(n.rank, n.rankMax))
        end
        if row.bar.SetStatusBarColor then
            local a = AccentRGB()
            row.bar:SetStatusBarColor(a[1], a[2], a[3], 1)
        end
        row.bar:Show()
        rightAnchor = row.bar
    else
        if row.bar then row.bar:Hide() end
        row.count:SetText(string.format("%d/%d", n.learned, n.total))
    end

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", indent + (hasArrow and 18 or 4), 0)
    row.label:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
    -- Retail draws headers in the gold "normal" ink and a fully unlearned branch disabled.
    local prefix = hasArrow and "" or (collapsed and "+ " or "- ")
    if n.learned > 0 then
        row.label:SetText(GoldHex() .. prefix .. n.name .. "|r")
    else
        row.label:SetText(prefix .. n.name)
        ns.UI_SetTextColorRole(row.label, "Dim")
    end
end

local function PaintRecipeRow(row, item, state)
    local r = item.recipe
    -- Recipes sit one marker slot right of their header's arrow, like the retail tree.
    local x = item.depth * RECIPE_INDENT
    row:SetHeight(RECIPE_ROW_H)
    row.arrow:Hide()
    if row.bar then row.bar:Hide() end
    row._wnRecipe = r
    row._wnTipHost = state.tipHost
    row:SetScript("OnEnter", RecipeTooltipOnEnter)

    if state.selectedID == r.id then
        local a = AccentRGB()
        row.selected:SetColorTexture(a[1], a[2], a[3], 0.28)
        row.selected:Show()
    else
        row.selected:Hide()
    end

    -- Skill-up marker in its own fixed slot, only while the recipe still gives points.
    row.skillUp:ClearAllPoints()
    row.skillUp:SetPoint("CENTER", row, "LEFT", x + RL.MARKER_W / 2, 0)
    row.skillUpText:Hide()
    local diff = r.learned and r.canSkillUp ~= false and r.difficulty
    local shown = false
    if diff and SKILLUP_ATLAS[diff] then
        row.skillUp:SetSize(RL.MARKER_W, RL.MARKER_W)
        shown = SetAtlasOrHide(row.skillUp, SKILLUP_ATLAS[diff])
        if not shown and DIFFICULTY_RGB[diff] then
            local c = DIFFICULTY_RGB[diff]
            row.skillUp:SetColorTexture(c[1], c[2], c[3], 1)
            row.skillUp:SetSize(6, 6)
            row.skillUp:Show()
            shown = true
        end
        if shown and diff == 0 and (tonumber(r.skillUps) or 0) > 1 then
            local c = DIFFICULTY_RGB[0]
            row.skillUpText:SetText(tostring(r.skillUps))
            row.skillUpText:SetTextColor(c[1], c[2], c[3])
            row.skillUpText:Show()
        end
    else
        row.skillUp:Hide()
    end

    local well = row.iconWell
    if well then
        well:ClearAllPoints()
        well:SetPoint("LEFT", row, "LEFT", x + RL.MARKER_W + RL.ICON_GAP, 0)
        if well.texture then
            well.texture:SetTexture(r.outputIcon or r.icon or 134400)
            well.texture:SetDesaturated(not r.learned)
            well.texture:SetAlpha(r.learned and 1 or 0.7)
        end
        well:Show()
    end

    -- Craftable count, as the retail list prints it after the name.
    local can = CraftableCount(r, state.charKey, state.haveMemo)
    if can and can > 0 then
        row.count:ClearAllPoints()
        row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.count:SetText("[" .. can .. "]")
        ns.UI_SetTextColorRole(row.count, "Bright")
        row.count:Show()
    else
        row.count:Hide()
    end

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", well or row, well and "RIGHT" or "LEFT", RL.LABEL_GAP, 0)
    row.label:SetPoint("RIGHT", (can and can > 0) and row.count or row, (can and can > 0) and "LEFT" or "RIGHT", -4, 0)
    row.label:SetText(r.name or "")
    -- A disabled recipe reads as unavailable, like retail's locked rows; the reason is in the detail.
    -- One the character holds every reagent for reads green (theme-aware semantic green).
    local green = can and can > 0 and r.learned and not r.disabled
        and ns.PLAN_UI_COLORS and ns.PLAN_UI_COLORS.completedRgb
    if green then
        row.label:SetTextColor(green[1], green[2], green[3])
    else
        ns.UI_SetTextColorRole(row.label, (r.learned and not r.disabled) and "Bright" or "Dim")
    end
end

--[[
    Right pane: the selected recipe, laid out like the retail schematic form
    (Blizzard_ProfessionsRecipeSchematicForm.lua): product icon with the made count, product name
    in its quality colour, "Requires: <tool>" under it, the recipe description, then the reagent
    slots -- each an icon with have/need on it (red when short) and the reagent name beside it.
    An unlearned recipe shows where it is taught instead of the skill-up line.

    "Have" is the character's own bags + bank plus the shared Warband Bank from the saved item
    storage (GetDetailedItemCountsFast), so an offline alt shows what IT can craft with, not the
    logged-in one.
    Item names and icons load through Item:CreateFromItemID so an uncached reagent fills in when
    the client has it instead of blocking on GetItemInfo.
]]
local DETAIL_WRAP_W_PAD = PAD * 2

--- Quality-coloured icon border (retail reagent / product slots); the default chrome otherwise.
local function SetQualityBorder(iconFrame, itemID)
    if not iconFrame or not ns.UI_UpdateBorderColor then return end
    local r, g, b = QualityRGB(itemID)
    if r then
        ns.UI_UpdateBorderColor(iconFrame, { r, g, b, 0.9 })
    else
        local a = AccentRGB()
        ns.UI_UpdateBorderColor(iconFrame, { a[1], a[2], a[3], 0.6 })
    end
end

local function PaintItemName(fs, itemID, name)
    fs:SetText(name or "")
    local r, g, b = QualityRGB(itemID)
    if r then fs:SetTextColor(r, g, b) else ns.UI_SetTextColorRole(fs, "Bright") end
end

local function NewWrapText(pane, font)
    local fs = FontManager:CreateFontString(pane, font, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

--[[
    Inline quality mark sized from the text it sits in, never a fixed pixel count: the font height
    already follows the WN font setting and the UI scale, so the mark stays one text line tall on
    any monitor, resolution or scale. The width keeps the atlas's own aspect.
]]
local function QualityMarkup(atlas, fontHeight, itemID, recipeID, qualityIndex)
    -- Rows saved before iconChat was captured still hold the padded iconSmall; quality info is
    -- static game data (not per character), so the chat atlas is read live when the api has it.
    local TS = C_TradeSkillUI
    local ok, qi
    if TS and itemID and TS.GetItemReagentQualityInfo then
        ok, qi = pcall(TS.GetItemReagentQualityInfo, itemID)
    elseif TS and recipeID and qualityIndex and TS.GetRecipeItemQualityInfo then
        ok, qi = pcall(TS.GetRecipeItemQualityInfo, recipeID, qualityIndex)
    end
    local chat = ok and type(qi) == "table" and qi.iconChat
    if type(chat) == "string" and not (issecretvalue and issecretvalue(chat)) and chat ~= "" then atlas = chat end
    -- One text line tall (+1): a taller mark grows only its own line in a multi-line string, which
    -- breaks the block's rhythm and lifts the mark off the text.
    local h = math.max(10, math.floor((tonumber(fontHeight) or 12) + 1.5))
    local w = h
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info and tonumber(info.width) and tonumber(info.height) and info.height > 0 then
        w = math.max(1, math.floor(h * info.width / info.height + 0.5))
    end
    return string.format("|A:%s:%d:%d|a", atlas, h, w)
end

--- Font height of a string, or of a FontManager category when the string does not exist yet.
local function FontHeightOf(fs, category)
    if fs and fs.GetFont then
        local _, h = fs:GetFont()
        if tonumber(h) then return h end
    end
    return FontManager.GetFontSize and FontManager:GetFontSize(category or "body") or 12
end

--- "|A:tier1|a 3  |A:tier2|a 0" -- per-tier holdings, the breakdown the retail slot tooltip lists.
local function TierSummary(charKey, rg, memo, size)
    local tiers = type(rg.tiers) == "table" and rg.tiers or nil
    if not tiers then return nil end
    local parts = {}
    for t = 1, #tiers do
        local tr = tiers[t]
        local mark = tr.atlas and QualityMarkup(tr.atlas, size, tr.itemID)
            or (tr.tier and ("T" .. tr.tier)) or ("#" .. t)
        parts[#parts + 1] = mark .. " " .. tostring(CharacterHaveCount(charKey, tr.itemID, memo) or 0)
    end
    return table.concat(parts, "   ")
end

--- Reagent icon: the item tooltip, then one line per quality tier with what this character holds.
local function ReagentOnEnter(self)
    ItemTooltipOnEnter(self)
    local rg, d = self._wnReagent, self._wnDetail
    if not rg or not d or not GameTooltip:IsOwned(self) then return end
    local line = TierSummary(d.charKey, rg, d.haveMemo, FontHeightOf(GameTooltipTextLeft1))
    if line then
        local r, g, b = ns.UI_GetTooltipBodyColor()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(line, r, g, b)
        GameTooltip:Show()
        PlaceTipBeside(self)
    end
end

--- Optional / finishing slot: slot name, required rank, then every item it takes and how many held.
local function SlotOnEnter(self)
    local slot, d = self._wnSlot, self._wnDetail
    if not slot or not d or not ns.UI_SafeSetGameTooltipOwner(self, TipAnchor(self)) then return end
    local tr, tg, tb = ns.UI_GetTooltipTitleColor()
    local br, bg, bb = ns.UI_GetTooltipBodyColor()
    local title = slot.label or (slot.kind == "finishing" and L("RECIPES_FINISHING", "Finishing Reagents")
        or L("RECIPES_OPTIONAL", "Optional Reagents"))
    GameTooltip:AddLine(title, tr, tg, tb)
    if slot.required then GameTooltip:AddLine(L("RECIPES_SLOT_REQUIRED", "Required"), 1, 0.3, 0.3) end
    if slot.rank then
        GameTooltip:AddLine(string.format(L("RECIPES_SLOT_RANK", "Unlocks at skill %d"), slot.rank), br, bg, bb)
    end
    local ids = slot.itemIDs or {}
    for i = 1, #ids do
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(ids[i])
        if issecretvalue and issecretvalue(name) then name = nil end
        local qr, qg, qb = QualityRGB(ids[i])
        GameTooltip:AddDoubleLine(name or ("item:" .. ids[i]),
            tostring(CharacterHaveCount(d.charKey, ids[i], d.haveMemo) or 0),
            qr or br, qg or bg, qb or bb, br, bg, bb)
    end
    GameTooltip:Show()
    PlaceTipBeside(self)
end

local function AcquireSlotIcon(d, index)
    local cell = d.slots[index]
    if not cell then
        cell = CreateIcon(d.pane, nil, REAGENT_ICON, false, nil, false)
        if not cell then return nil end
        if cell.texture then
            cell.texture:SetTexCoord(SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM, SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM)
        end
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", SlotOnEnter)
        cell:SetScript("OnLeave", SpellTooltipOnLeave)
        cell.count = FontManager:CreateFontString(cell, "small", "OVERLAY")
        cell.count:SetDrawLayer("OVERLAY", 7)
        cell.count:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
        cell.count:SetTextColor(1, 1, 1)
        d.slots[index] = cell
    end
    cell:Show()
    return cell
end

local function BuildRecipeDetail(pane)
    local d = { pane = pane, reagents = {}, slots = {} }
    d.icon = CreateIcon(pane, nil, DETAIL_ICON, false, nil, false)
    if d.icon then
        d.icon:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
        if d.icon.texture then
            d.icon.texture:SetTexCoord(SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM, SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM)
        end
        d.icon:EnableMouse(true)
        d.icon:SetScript("OnEnter", function(self)
            local link = self._wnLink
            if link and ns.UI_SafeSetGameTooltipOwner(self, TipAnchor(self))
                and pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
                GameTooltip:Show()
                PlaceTipBeside(self)
                return
            end
            if self._wnItemID then ItemTooltipOnEnter(self) else RecipeTooltipOnEnter(self) end
        end)
        d.icon:SetScript("OnLeave", SpellTooltipOnLeave)
        d.icon._wnDetail = d
        d.made = FontManager:CreateFontString(d.icon, "body", "OVERLAY")
        d.made:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", -2, 2)
        d.made:SetTextColor(1, 1, 1)
    end
    d.name = FontManager:CreateFontString(pane, "title", "OVERLAY")
    d.name:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + DETAIL_ICON + 12, -PAD - 4)
    d.name:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.requires = FontManager:CreateFontString(pane, "small", "OVERLAY")
    d.requires:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
    d.requires:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
    d.requires:SetJustifyH("LEFT")
    d.category = FontManager:CreateFontString(pane, "small", "OVERLAY")
    d.category:SetJustifyH("LEFT")
    d.description = NewWrapText(pane, "body")
    d.statusHead = FontManager:CreateFontString(pane, "subtitle", "OVERLAY")
    d.statusHead:SetJustifyH("LEFT")
    d.statusBody = NewWrapText(pane, "body")
    d.info = NewWrapText(pane, "body")
    d.crafters = NewWrapText(pane, "small")
    -- Reagents whose warband holdings table is open (ProfessionRecipeHoldings), keyed by item id.
    d.expanded = {}
    d.padX = PAD
    d.reagentHead = FontManager:CreateFontString(pane, "subtitle", "OVERLAY")
    d.reagentHead:SetJustifyH("LEFT")
    d.reagentHead:SetText(L("RECIPES_REAGENTS", "Reagents"))
    ns.UI_SetTextColorRole(d.reagentHead, "Bright")
    d.optHead = FontManager:CreateFontString(pane, "subtitle", "OVERLAY")
    d.optHead:SetJustifyH("LEFT")
    d.optHead:SetText(L("RECIPES_OPTIONAL", "Optional Reagents"))
    ns.UI_SetTextColorRole(d.optHead, "Bright")
    d.finHead = FontManager:CreateFontString(pane, "subtitle", "OVERLAY")
    d.finHead:SetJustifyH("LEFT")
    d.finHead:SetText(L("RECIPES_FINISHING", "Finishing Reagents"))
    ns.UI_SetTextColorRole(d.finHead, "Bright")
    d.missing = NewWrapText(pane, "small")
    d.empty = FontManager:CreateFontString(pane, "body", "OVERLAY")
    d.empty:SetPoint("LEFT", pane, "LEFT", PAD, 0)
    d.empty:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
    d.empty:SetJustifyH("CENTER")
    d.empty:SetText(L("RECIPES_SELECT_HINT", "Select a recipe to see its details."))
    ns.UI_SetTextColorRole(d.empty, "Muted")
    return d
end

local function AcquireReagentRow(d, index)
    local row = d.reagents[index]
    if not row then
        row = Factory:CreateContainer(d.pane, 10, REAGENT_ROW_H, false)
        if not row then return nil end
        row.icon = CreateIcon(row, nil, REAGENT_ICON, false, nil, false)
        if row.icon then
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            -- Clip the art's baked-in frame so only our quality border shows.
            if row.icon.texture then
                row.icon.texture:SetTexCoord(SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM, SPELL_ICON_TRIM, 1 - SPELL_ICON_TRIM)
            end
            row.icon:EnableMouse(true)
            row.icon:SetScript("OnEnter", ReagentOnEnter)
            row.icon:SetScript("OnLeave", SpellTooltipOnLeave)
            -- have/need sits on a dark pill so it reads over any icon art, as on retail slots.
            row.countBg = row.icon:CreateTexture(nil, "OVERLAY", nil, 5)
            row.countBg:SetColorTexture(0, 0, 0, 0.75)
            row.count = FontManager:CreateFontString(row.icon, "small", "OVERLAY")
            row.count:SetDrawLayer("OVERLAY", 7)
            row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -3, 3)
            row.countBg:SetPoint("TOPLEFT", row.count, "TOPLEFT", -2, 1)
            row.countBg:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMRIGHT", 2, -1)
        end
        row.label = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.label:SetPoint("LEFT", row, "LEFT", REAGENT_ICON + 12, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        -- The row opens the reagent's warband holdings table; the chevron shows which way.
        if ns.UI_CreateCollapseExpandControl then
            row.chev = ns.UI_CreateCollapseExpandControl(row, false, { enableMouse = false, size = 14 })
            row.chev:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.label:SetPoint("RIGHT", row.chev, "LEFT", -4, 0)
        end
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self)
            local dd, key = self._wnDetail, self._wnKey
            if not dd or not key or not dd.Repaint then return end
            dd.expanded[key] = (not dd.expanded[key]) or nil
            dd.Repaint(dd)
        end)
        d.reagents[index] = row
    end
    row:Show()
    return row
end

--- Size the detail's scroll child to what was drawn and start the view at the top.
local function FinishRecipeDetail(d, y)
    if not d.scroll then return end
    d.pane:SetHeight(math.max(1, -y + PAD))
    -- A table opened or closed in place keeps the view where it was; a new recipe starts at the top.
    if not d.keepScroll then d.scroll:SetVerticalScroll(0) end
    RefreshScrollBar(d.scroll)
end

--- Stack the shown blocks top to bottom under the product header; heights come from the text.
local function StackDetail(d, blocks)
    local pane = d.pane
    -- The pane's rect may not be resolved on the pass that builds it; the window's own geometry
    -- gives the same width.
    local paneW = pane:GetWidth() or 0
    if paneW < 100 then
        paneW = RECIPE_WIN_W - PAD * 4 - RECIPE_LIST_W - RECIPE_PANE_GAP
    end
    local width = math.max(60, paneW - DETAIL_WRAP_W_PAD)
    local y = -(PAD + DETAIL_ICON + 14)
    for i = 1, #blocks do
        local b = blocks[i]
        local region, gap = b[1], b[2] or 8
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, y)
        if region.SetWidth and region.GetObjectType and region:GetObjectType() == "FontString" then
            region:SetWidth(width)
        else
            region:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
        end
        region:Show()
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 0
        y = y - h - gap
    end
    return y
end

local function PaintRecipeDetail(d, recipe, entry)
    -- Same recipe (by id: a rescan saves fresh row tables) repaints in place -- open holdings
    -- tables stay open and the scroll position is kept; another recipe starts closed, at the top.
    d.keepScroll = d.lastRecipe ~= nil and recipe ~= nil and d.lastRecipe.id == recipe.id
    if not d.keepScroll then wipe(d.expanded) end
    d.lastRecipe, d.lastEntry = recipe, entry
    d.Repaint = d.Repaint or function(dd) PaintRecipeDetail(dd, dd.lastRecipe, dd.lastEntry) end
    if ns.RecipeHoldingsUI then ns.RecipeHoldingsUI.Begin(d) end
    d.crafters:Hide()
    for i = 1, #d.reagents do d.reagents[i]:Hide() end
    for i = 1, #d.slots do d.slots[i]:Hide() end
    d.optHead:Hide()
    d.finHead:Hide()
    d.category:Hide()
    d.description:Hide()
    d.statusHead:Hide()
    d.statusBody:Hide()
    d.info:Hide()
    d.reagentHead:Hide()
    d.missing:Hide()
    if not recipe then
        if d.icon then d.icon:Hide() end
        d.name:SetText("")
        d.requires:SetText("")
        d.empty:ClearAllPoints()
        d.empty:SetPoint("CENTER", d.frame or d.pane, "CENTER", 0, 0)
        d.empty:Show()
        FinishRecipeDetail(d, 0)
        return
    end
    d.empty:Hide()

    -- Product header.
    local outID = tonumber(recipe.outputItemID)
    if d.icon then
        d.icon._wnRecipe = recipe
        d.icon._wnItemID = outID
        d.icon._wnLink = recipe.outputLink
        local tex = outID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(outID)
        SetQualityBorder(d.icon, outID)
        if d.icon.texture then
            d.icon.texture:SetTexture(recipe.outputIcon or tex or recipe.icon or 134400)
            d.icon.texture:SetDesaturated(not recipe.learned)
        end
        local qMin, qMax = tonumber(recipe.quantityMin), tonumber(recipe.quantityMax)
        if qMin and qMax and qMax > 1 then
            d.made:SetText(qMin == qMax and tostring(qMin) or (qMin .. "-" .. qMax))
        else
            d.made:SetText("")
        end
        d.icon:Show()
    end
    local outName = outID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(outID)
    if issecretvalue and issecretvalue(outName) then outName = nil end
    PaintItemName(d.name, outID, outName or recipe.name)
    if outID and not outName and Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(outID)
        local token = d.token
        if item and not item:IsItemEmpty() then
            item:ContinueOnItemLoad(function()
                if d.token ~= token then return end
                local n = item:GetItemName()
                if issecretvalue and issecretvalue(n) then return end
                PaintItemName(d.name, outID, n)
            end)
        end
    end
    if type(recipe.requires) == "table" and #recipe.requires > 0 then
        d.requires:SetText(string.format(L("RECIPES_REQUIRES", "Requires: %s"), table.concat(recipe.requires, ", ")))
        ns.UI_SetTextColorRole(d.requires, "Normal")
    else
        d.requires:SetText("")
    end

    local blocks = {}
    -- Category path, top header first.
    local cats = type(entry.categories) == "table" and entry.categories or {}
    local parts, id, guard = {}, recipe.categoryID, 0
    while id and cats[id] and guard < 6 do
        table.insert(parts, 1, cats[id].name)
        id = cats[id].parent
        guard = guard + 1
    end
    if #parts > 0 then
        d.category:SetText(table.concat(parts, " > "))
        ns.UI_SetTextColorRole(d.category, "Muted")
        blocks[#blocks + 1] = { d.category, 10 }
    end
    -- Every saved character that knows this recipe (the old Recipe Companion "Crafters" list).
    local knownBy = ns.RecipeHoldingsUI and ns.RecipeHoldingsUI.KnownByText(recipe.id)
    if knownBy then
        d.crafters:SetText(knownBy)
        ns.UI_SetTextColorRole(d.crafters, "Normal")
        blocks[#blocks + 1] = { d.crafters, 12 }
    end
    if recipe.description then
        d.description:SetText(recipe.description)
        ns.UI_SetTextColorRole(d.description, "Normal")
        blocks[#blocks + 1] = { d.description, 14 }
    end

    -- Unlearned: where it is taught (retail "Unlearned Recipe"). A learned recipe's skill-up
    -- colour is already the marker in the list, so the detail does not repeat it.
    if not recipe.learned then
        d.statusHead:SetText(L("RECIPES_UNLEARNED_HEADER", "Unlearned Recipe"))
        ns.UI_SetTextColorRole(d.statusHead, "Dim")
        blocks[#blocks + 1] = { d.statusHead, recipe.source and 4 or 14 }
        if recipe.source then
            d.statusBody:SetText(recipe.source)
            ns.UI_SetTextColorRole(d.statusBody, "Normal")
            blocks[#blocks + 1] = { d.statusBody, 14 }
        end
    end

    -- Facts block: muted labels, bright values (locale-safe -- only the %s value is coloured).
    -- What the player acts on: crafts the held reagents allow, concentration, cooldown / charges,
    -- first-craft bonus, recipe rank, why it is unavailable, where the next rank is taught.
    local bright = "|cff" .. ((ns.UI_GetTextRoleHexRaw and ns.UI_GetTextRoleHexRaw("Bright")) or "ffffff")
    local function V(v) return bright .. tostring(v) .. "|r" end
    local lines = {}
    if recipe.learned and not recipe.disabled and type(recipe.reagents) == "table" and #recipe.reagents > 0 then
        local can = CraftableCount(recipe, d.charKey, d.haveMemo)
        if can then
            local green = ns.PLAN_UI_COLORS and ns.PLAN_UI_COLORS.completed or "|cff44ff44"
            lines[#lines + 1] = string.format(L("RECIPES_CAN_CRAFT", "Can craft: %s"),
                can > 0 and (green .. can .. "|r") or V(0))
        end
    end
    local op = type(recipe.operation) == "table" and recipe.operation or nil
    if op and op.concentration then
        lines[#lines + 1] = string.format(L("RECIPES_CONCENTRATION", "Concentration: %s"), V(op.concentration))
    end
    if recipe.maxCharges then
        lines[#lines + 1] = string.format(L("RECIPES_CHARGES", "Charges: %s"),
            V((tonumber(recipe.charges) or 0) .. "/" .. recipe.maxCharges))
    end
    local ends = tonumber(recipe.cooldownEndsAt)
    if ends then
        local left = ends - time()
        if left > 0 then
            local txt = (SecondsToTime and SecondsToTime(left)) or (math.ceil(left / 60) .. " min")
            lines[#lines + 1] = string.format(L("RECIPES_COOLDOWN", "Cooldown: %s"), V(txt))
        else
            lines[#lines + 1] = string.format(L("RECIPES_COOLDOWN", "Cooldown: %s"), V(L("RECIPES_READY", "Ready")))
        end
    end
    if recipe.firstCraft and recipe.learned then
        lines[#lines + 1] = (ns.PLAN_UI_COLORS and ns.PLAN_UI_COLORS.completed or "|cff44ff44")
            .. L("RECIPES_FIRST_CRAFT", "First craft bonus available") .. "|r"
    end
    if recipe.alwaysLowestQuality then
        lines[#lines + 1] = L("RECIPES_LOWEST_QUALITY", "Always uses lowest quality reagents")
    end
    local lvl = tonumber(recipe.unlockedRecipeLevel)
    if lvl and lvl > 0 then
        local cur, nxt = tonumber(recipe.currentRecipeExperience), tonumber(recipe.nextLevelRecipeExperience)
        local rankText = string.format(L("RECIPES_RANK", "Rank %s"), V(lvl))
        if cur and nxt and nxt > 0 then rankText = rankText .. string.format("  (%d/%d)", cur, nxt) end
        lines[#lines + 1] = rankText
    end
    if recipe.disabled then
        lines[#lines + 1] = "|cffff4040" .. (recipe.disabledReason or L("RECIPES_DISABLED", "Unavailable")) .. "|r"
    end
    if recipe.learned and recipe.nextSource then
        lines[#lines + 1] = L("RECIPES_NEXT_RANK", "Next rank") .. ":\n" .. recipe.nextSource
    end
    if #lines > 0 then
        d.info:SetText(table.concat(lines, "\n"))
        if d.info.SetSpacing then d.info:SetSpacing(3) end
        ns.UI_SetTextColorRole(d.info, "Muted")
        blocks[#blocks + 1] = { d.info, 16 }
    end

    local reagents = type(recipe.reagents) == "table" and recipe.reagents or nil
    if reagents and #reagents > 0 then
        blocks[#blocks + 1] = { d.reagentHead, 10 }
    elseif recipe.order == nil then
        -- Captured by an older build: no reagents were recorded yet.
        d.missing:SetText(L("RECIPES_RESCAN_HINT",
            "Open this profession once more on this character to load its reagents and categories."))
        ns.UI_SetTextColorRole(d.missing, "Muted")
        blocks[#blocks + 1] = { d.missing, 8 }
    end
    local y = StackDetail(d, blocks)
    reagents = reagents or {}
    local HUI = ns.RecipeHoldingsUI
    if HUI and #reagents > 0 then
        HUI.PlaceExpandAll(d, d.reagentHead, reagents, function() d.Repaint(d) end)
    end

    local pane = d.pane
    local token = d.token
    for i = 1, #reagents do
        local rg = reagents[i]
        local row = AcquireReagentRow(d, i)
        if row then
            local key = rg.itemID or i
            row._wnDetail, row._wnKey = d, key
            if row.chev then ns.UI_CollapseExpandSetState(row.chev, d.expanded[key] == true) end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, y)
            row:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
            local need = tonumber(rg.count) or 1
            local have = ReagentHaveCount(d.charKey, rg, d.haveMemo)
            if row.icon then
                row.icon._wnItemID = rg.itemID
                row.icon._wnReagent = rg
                row.icon._wnDetail = d
                SetQualityBorder(row.icon, rg.itemID)
                local tex = (C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID(rg.itemID)
                if row.icon.texture then
                    row.icon.texture:SetTexture(tex or 134400)
                    row.icon.texture:SetDesaturated(have ~= nil and have < need)
                end
                if have then
                    row.count:SetText(string.format("%d/%d", have, need))
                    if have < need then row.count:SetTextColor(1, 0.3, 0.3) else row.count:SetTextColor(1, 1, 1) end
                else
                    row.count:SetText(tostring(need))
                    row.count:SetTextColor(1, 1, 1)
                end
                row.icon:Show()
            end
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(rg.itemID)
            if issecretvalue and issecretvalue(name) then name = nil end
            PaintItemName(row.label, rg.itemID, name or ("item:" .. tostring(rg.itemID)))
            -- Quality tiers held, under the name, like the retail slot's allocation readout.
            -- Same pip size as the Qualities line above, so one tier mark reads the same everywhere.
            local tierLine = TierSummary(d.charKey, rg, d.haveMemo, FontHeightOf(d.info))
            row.label:SetPoint("LEFT", row, "LEFT", REAGENT_ICON + 12, tierLine and 8 or 0)
            if tierLine then
                if not row.tiers then
                    row.tiers = FontManager:CreateFontString(row, "small", "OVERLAY")
                    row.tiers:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
                    row.tiers:SetJustifyH("LEFT")
                end
                row.tiers:SetText(tierLine)
                ns.UI_SetTextColorRole(row.tiers, "Normal")
                row.tiers:Show()
            elseif row.tiers then
                row.tiers:Hide()
            end
            if not name and Item and Item.CreateFromItemID then
                local item = Item:CreateFromItemID(rg.itemID)
                if item and not item:IsItemEmpty() then
                    item:ContinueOnItemLoad(function()
                        -- A later selection reuses the row; only the current one may write.
                        if d.token ~= token then return end
                        local loaded = item:GetItemName()
                        if issecretvalue and issecretvalue(loaded) then return end
                        PaintItemName(row.label, rg.itemID, loaded)
                        if row.icon and row.icon.texture then
                            row.icon.texture:SetTexture(item:GetItemIcon() or 134400)
                        end
                    end)
                end
            end
            y = y - REAGENT_ROW_H
            -- Open row: every character's bags / bank, the Warband Bank and the total, under it,
            -- across the full content width (same left / right edges as the reagent rows).
            if HUI and d.expanded[key] then
                y = y - HUI.DrawHoldings(d, rg, y, PAD) - 8
            end
        end
    end

    -- Optional, then finishing slots: one row of slot icons each, as the schematic form lays them.
    local optional = type(recipe.optional) == "table" and recipe.optional or {}
    y = y - (#reagents > 0 and 10 or 0)
    local used = 0
    local groups = { { "modifying", d.optHead }, { "finishing", d.finHead } }
    for gi = 1, #groups do
        local kind, head = groups[gi][1], groups[gi][2]
        local x, any = 0, false
        for i = 1, #optional do
            local slot = optional[i]
            if slot.kind == kind then
                if not any then
                    head:ClearAllPoints()
                    head:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, y)
                    head:Show()
                    y = y - (head:GetStringHeight() or 14) - 8
                    any = true
                end
                used = used + 1
                local cell = AcquireSlotIcon(d, used)
                if cell then
                    cell._wnSlot = slot
                    cell._wnDetail = d
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + x, y)
                    local ids = slot.itemIDs or {}
                    local first = ids[1]
                    local tex = first and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(first)
                    if cell.texture then
                        cell.texture:SetTexture(tex or 134400)
                        -- An unfilled slot: shown dim, the way retail draws an empty optional slot.
                        cell.texture:SetDesaturated(true)
                        cell.texture:SetAlpha(0.6)
                    end
                    if slot.required then
                        ns.UI_UpdateBorderColor(cell, { 1, 0.3, 0.3, 0.9 })
                    else
                        local a = AccentRGB()
                        ns.UI_UpdateBorderColor(cell, { a[1], a[2], a[3], 0.6 })
                    end
                    cell.count:SetText(#ids > 1 and tostring(#ids) or "")
                    x = x + REAGENT_ICON + 8
                end
            end
        end
        if any then y = y - REAGENT_ICON - 12 end
    end
    FinishRecipeDetail(d, y)
end

local function FindRecipe(entry, id)
    if not id then return nil end
    for i = 1, #entry.recipes do
        if entry.recipes[i].id == id then return entry.recipes[i] end
    end
    return nil
end

function WarbandNexus:ShowProfessionRecipesPopup(charKey, charName, professionID)
    local entry = self.GetProfessionRecipes and self:GetProfessionRecipes(charKey, professionID)
    if not entry or not Factory then return end

    local stateKey = tostring(charKey) .. ":" .. tostring(professionID)
    local state = recipeViewState[stateKey]
    if not state then
        state = { collapsed = {}, showUnlearned = true, query = nil, selectedID = nil }
        recipeViewState[stateKey] = state
    end

    local title = entry.name or L("TAB_PROFESSIONS", "Professions")
    local dialog, content = CreateExternalWindow({
        name = "CharacterProfessionRecipesPopup",
        title = charName and (charName .. " - " .. title) or title,
        icon = ns.UI_GetIconFile("anvil"),
        width = RECIPE_WIN_W,
        height = RECIPE_WIN_H,
        preventDuplicates = true,
    })
    if not dialog then return end
    ResetContent(content)

    -- Top strip: rank bar like the retail header, known count, search and the unlearned filter.
    local rank = FontManager:CreateFontString(content, "subtitle", "OVERLAY")
    rank:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
    rank:SetJustifyH("LEFT")
    -- Retail draws the active expansion tier's rank, not the base skill line's.
    local tier = type(entry.activeTier) == "table" and entry.activeTier or nil
    rank:SetText((tier and tier.name) or title)
    ns.UI_SetTextColorRole(rank, "Bright")

    local bar = Factory.CreateProgressBar and Factory:CreateProgressBar(content, RECIPE_RANK_W, RECIPE_RANK_H)
    local src = tier or entry
    local skill, maxSkill = tonumber(src.skillLevel) or 0, tonumber(src.maxSkillLevel) or 0
    if bar then
        bar:SetPoint("LEFT", rank, "RIGHT", 12, 0)
        if bar.SetMinMaxValues then
            bar:SetMinMaxValues(0, math.max(1, maxSkill))
            bar:SetValue(math.min(skill, math.max(1, maxSkill)))
        end
        -- The factory bar fills white; the retail rank bar is a coloured fill.
        if bar.SetStatusBarColor then
            local a = AccentRGB()
            bar:SetStatusBarColor(a[1], a[2], a[3], 1)
        end
        bar:Show()
    end
    local rankText = FontManager:CreateFontString(content, "small", "OVERLAY")
    rankText:SetPoint("LEFT", bar or rank, "RIGHT", 8, 0)
    local bonus = tonumber(src.skillModifier)
    rankText:SetText((bonus and bonus > 0)
        and string.format("%d |cff40ff40(+%d)|r / %d", skill, bonus, maxSkill)
        or string.format("%d / %d", skill, maxSkill))
    ns.UI_SetTextColorRole(rankText, "Bright")

    local known = FontManager:CreateFontString(content, "small", "OVERLAY")
    known:SetPoint("TOPLEFT", rank, "BOTTOMLEFT", 0, -4)
    known:SetJustifyH("LEFT")
    local captured = ""
    if entry.scannedAt and date then
        captured = "   " .. string.format(L("RECIPES_CAPTURED", "Saved %s"), date("%Y-%m-%d %H:%M", entry.scannedAt))
    end
    known:SetText(string.format("%s %d / %d", L("RECIPES_KNOWN", "Known recipes"),
        tonumber(entry.known) or 0, #entry.recipes) .. captured)
    ns.UI_SetTextColorRole(known, "Muted")

    -- Panes.
    local paneTop = PAD + RECIPE_TOP_H
    local listPane = Factory:CreateContainer(content, RECIPE_LIST_W, 10, true)
    listPane:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -paneTop)
    listPane:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", PAD, PAD)
    listPane:SetWidth(RECIPE_LIST_W)
    listPane:Show()
    local detailPane = Factory:CreateContainer(content, 10, 10, true)
    detailPane:SetPoint("TOPLEFT", listPane, "TOPRIGHT", RECIPE_PANE_GAP, 0)
    detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, PAD)
    detailPane:Show()
    -- Long recipes (many reagents plus optional and finishing slots) outgrow the pane: the
    -- detail draws into a scroll child, the same lane the other WN windows use.
    local detail = ns.RecipeDetailUI.Create(detailPane,
        RECIPE_WIN_W - PAD * 4 - RECIPE_LIST_W - RECIPE_PANE_GAP, dialog)

    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    local filterBtn = Factory:CreateButton(listPane, 10, searchH)
    local filterLabel
    if filterBtn then
        filterBtn:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", -RECIPE_LIST_PAD, -RECIPE_LIST_PAD)
        filterBtn:SetWidth(RECIPE_LIST_W - RECIPE_SEARCH_W - RECIPE_LIST_PAD * 3)
        if Factory.ApplyHighlight then Factory:ApplyHighlight(filterBtn) end
        filterLabel = FontManager:CreateFontString(filterBtn, "small", "OVERLAY")
        filterLabel:SetPoint("LEFT", 4, 0)
        filterLabel:SetPoint("RIGHT", -4, 0)
        filterLabel:SetJustifyH("CENTER")
        filterLabel:SetWordWrap(false)
        ns.UI_SetTextColorRole(filterLabel, "Bright")
        filterBtn:Show()
    end

    local scroll, child = BuildScroll(listPane, RECIPE_LIST_W, searchH + RECIPE_LIST_PAD, RECIPE_LIST_PAD)
    if not scroll then return end

    dialog._wnRecipeRows = dialog._wnRecipeRows or {}
    local pool = dialog._wnRecipeRows
    local visible = {}
    local Redraw

    detail.charKey = charKey
    -- Have-counts are read once per open and shared by the list's craftable counts and the detail.
    state.charKey = charKey
    state.tipHost = dialog
    state.haveMemo = {}
    detail.haveMemo = state.haveMemo
    local function Select(recipe)
        state.selectedID = recipe and recipe.id or nil
        -- New token per selection: item loads still in flight for the previous pick drop out.
        detail.token = (detail.token or 0) + 1
        PaintRecipeDetail(detail, recipe, entry)
    end

    local function RowOnClick(row)
        local item = row._wnItem
        if not item then return end
        if item.kind == "category" then
            local id = item.node.id
            state.collapsed[id] = not state.collapsed[id] or nil
        else
            Select(item.recipe)
        end
        Redraw()
    end

    -- Virtual list: only the rows inside the viewport exist as frames. A retail profession lists
    -- well over a thousand recipes, and a frame per recipe made every scroll step re-lay them all.
    local tops = {}
    local function Fill()
        for i = 1, #pool do pool[i]:Hide() end
        local n = #visible
        if n == 0 then return end
        local offset = scroll:GetVerticalScroll() or 0
        local viewH = scroll:GetHeight() or 0
        if viewH < RECIPE_ROW_H then viewH = RECIPE_WIN_H end
        -- First row whose bottom is below the top edge (binary search over the row tops).
        local lo, hi = 1, n
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if tops[mid + 1] and tops[mid + 1] <= offset then lo = mid + 1 else hi = mid end
        end
        local slot = 0
        for i = lo, n do
            if tops[i] > offset + viewH then break end
            local item = visible[i]
            slot = slot + 1
            local row = AcquireRecipeRow(child, pool, slot)
            if row then
                row._wnItem = item
                row:SetScript("OnClick", RowOnClick)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -tops[i])
                row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -tops[i])
                if item.kind == "category" then
                    PaintCategoryRow(row, item, state)
                else
                    PaintRecipeRow(row, item, state)
                end
            end
        end
    end
    scroll:HookScript("OnVerticalScroll", Fill)

    Redraw = function()
        wipe(visible)
        wipe(tops)
        local roots = BuildRecipeTree(entry, state.query)
        FlattenRecipeTree(roots, state, visible)
        local y, w = 0, child:GetWidth()
        for i = 1, #visible do
            tops[i] = -y
            y = y - ((visible[i].kind == "category") and RECIPE_CAT_H or RECIPE_ROW_H)
        end
        if #visible == 0 then
            child._wnEmpty = child._wnEmpty or FontManager:CreateFontString(child, "body", "OVERLAY")
            child._wnEmpty:SetPoint("TOP", child, "TOP", 0, -12)
            child._wnEmpty:SetText(L("NO_ITEMS_MATCH_GENERIC", "No items match your search"))
            ns.UI_SetTextColorRole(child._wnEmpty, "Muted")
            child._wnEmpty:Show()
            y = -40
        elseif child._wnEmpty then
            child._wnEmpty:Hide()
        end
        if w and w > 1 then child:SetWidth(w) end
        child:SetHeight(math.max(1, -y))
        RefreshScrollBar(scroll)
        -- A collapse or filter can shrink the list under the current offset.
        local maxOff = math.max(0, -y - (scroll:GetHeight() or 0))
        if (scroll:GetVerticalScroll() or 0) > maxOff then scroll:SetVerticalScroll(maxOff) end
        Fill()
        if filterLabel then
            filterLabel:SetText(state.showUnlearned and L("RECIPES_FILTER_ALL", "All recipes")
                or L("RECIPES_FILTER_LEARNED", "Learned only"))
        end
    end

    if filterBtn then
        filterBtn:SetScript("OnClick", function()
            state.showUnlearned = not state.showUnlearned
            Redraw()
        end)
    end

    local search = Factory:CreateSearchBox(listPane, RECIPE_SEARCH_W,
        L("RECIPES_SEARCH", "Search recipes..."), function(text)
            if issecretvalue and issecretvalue(text) then return end
            local q = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
            state.query = (q ~= "") and q or nil
            Redraw()
        end, state.query)
    if search then
        search:SetPoint("TOPLEFT", listPane, "TOPLEFT", RECIPE_LIST_PAD, -RECIPE_LIST_PAD)
        search:Show()
    end

    -- First open: pick the first learned recipe so the right pane is never blank by accident.
    if not state.selectedID then
        for i = 1, #entry.recipes do
            if entry.recipes[i].learned then state.selectedID = entry.recipes[i].id break end
        end
    end
    Select(FindRecipe(entry, state.selectedID))
    Redraw()
end

--[[
    The recipe detail pane as a shared component: this file's recipe window and the live companion
    beside Blizzard's profession frame (RecipeCompanionWindow) draw the same pane, so a recipe
    reads the same everywhere and lives in one place.
]]
ns.RecipeDetailUI = {
    --- Scrolling detail pane inside `pane`, `width` wide. `host` is the window tooltips open beside.
    Create = function(pane, width, host)
        local scroll, child = BuildScroll(pane, width, 0, 1)
        local d = BuildRecipeDetail(child or pane)
        d.frame, d.scroll, d.host = pane, scroll, host
        return d
    end,
    --- Paint saved recipe row `recipe` (from profession entry `entry`) as character `charKey` sees it.
    Paint = function(d, recipe, entry, charKey)
        -- Lay out at the viewport's current width: the host may have been resized (or restored to
        -- a saved size) since the pane was built, and wrapped text takes its width at paint time.
        local sw = d.scroll and d.scroll:GetWidth()
        if sw and sw > 1 then d.pane:SetWidth(sw) end
        d.charKey = charKey
        d.haveMemo = {}
        d.token = (d.token or 0) + 1
        PaintRecipeDetail(d, recipe, entry)
    end,
    --- Re-flow after the host window was resized (the scroll child follows the viewport width).
    Relayout = function(d)
        local sw = d.scroll and d.scroll:GetWidth()
        if sw and sw > 1 then d.pane:SetWidth(sw) end
        if d.lastRecipe ~= nil and d.Repaint then d.Repaint(d) end
        if d.scroll then RefreshScrollBar(d.scroll) end
    end,
    --- Height of the painted content (the scroll child), for hosts that size themselves to it.
    ContentHeight = function(d)
        return d.pane and d.pane:GetHeight() or 0
    end,
}
