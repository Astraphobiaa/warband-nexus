--[[
    Warband Nexus - Legacy tab (WoW Forever only)

    View over db.global.legacy, which LegacyService owns (scan + WN_LEGACY_UPDATED). Nothing here
    calls a game API: the tab reads the stored snapshot, so a paint never walks the achievement tree.

      Legacy Track card   points earned / reward tiers (15 / 25 / 40 / 55) with their rewards
      Challenges          the achievement category tree, one collapsible section per root
                          (Classes, Tradeskills, Dungeons, Raids, Player vs. Player, Adventure);
                          subcategories inside, one row per challenge with its progress

    The tab is only built where the "legacy" capability is on (UI_MainShell TAB_CAPABILITY).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local issecretvalue = issecretvalue
local format = string.format

local LegacyUI = {}
ns.LegacyUI = LegacyUI

-- Every pixel value of the tab in one place.
local LAYOUT = {
    CARD_PAD = 12,
    TRACK_TITLE_H = 22,
    TIER_GAP = 10,
    TIER_CARD_H = 64,           -- reward card: 40px icon + padding
    TIER_PAD = 12,
    TIER_ICON = 40,
    TIER_CHECK = 18,
    TIER_TWO_COL_MIN_W = 760,   -- below this the reward cards stack in one column
    ROW_H = 40,              -- icon + name line + description line
    ROW_ICON = 28,
    ROW_TEXT_INSET = 14,
    SUBROW_EXTRA_INSET = 16, -- rows under a sub header sit one step right of it
    SUBHDR_GAP_BEFORE = 4,
    PROGRESS_W = 120,        -- right-hand progress block (bar + count)
    PROGRESS_BAR_H = 6,
    SECTION_GAP = 6,
}

-- Category the client marks as hidden; never a player-facing section.
local HIDDEN_CATEGORY_ID = 15425

local function L_(key, fallback)
    local L = ns.L
    local v = L and L[key]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function SafeText(s)
    if (issecretvalue and issecretvalue(s)) or s == nil then return "" end
    return tostring(s)
end

-- REFRESH: data changes repaint only while the tab is visible (thin listener, debounced by a frame).

local LegacyUIEvents = {}
local refreshPending = false

function LegacyUI.RequestRepaint()
    if refreshPending or not (C_Timer and C_Timer.After) then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mf and mf:IsShown() and mf.currentTab == "legacy" then
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "legacy", skipCooldown = true })
        end
    end)
end

if WarbandNexus and WarbandNexus.RegisterMessage and E.LEGACY_UPDATED then
    WarbandNexus.RegisterMessage(LegacyUIEvents, E.LEGACY_UPDATED, LegacyUI.RequestRepaint)
end

-- COLLAPSE STATE (profile, UI state only). Root sections start collapsed so the first paint stays
-- small; sub sections start open, so opening a root shows its challenges at once.

function LegacyUI.IsSectionExpanded(categoryID, defaultExpanded)
    local p = WarbandNexus.db and WarbandNexus.db.profile
    local t = p and p.legacyExpanded
    -- Not `t and t[id] or nil`: a stored false must survive (and/or turns it into nil -> default).
    local v
    if type(t) == "table" then v = t[categoryID] end
    if v == nil then return defaultExpanded and true or false end
    return v == true
end

--- Remember a section's state. No repaint: the section resizes in place (see ReflowUp).
function LegacyUI.PersistExpanded(categoryID, expanded)
    local p = WarbandNexus.db and WarbandNexus.db.profile
    if not p then return end
    p.legacyExpanded = type(p.legacyExpanded) == "table" and p.legacyExpanded or {}
    p.legacyExpanded[categoryID] = expanded and true or false
end

-- HEADER (fixedHeader title card, cached across paints like the other tabs)

function LegacyUI.PaintHeader(mf, side)
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local headerParent = (chrome and chrome.headerParent) or (mf and mf.fixedHeader)
    if not headerParent then return end
    local y = (chrome and chrome.yOffset) or 8
    local cache = mf._legacyFixedHeaderCache
    local card = cache and cache.titleCard
    if not card then
        local ac = ns.UI_COLORS and ns.UI_COLORS.accent or { 0.6, 0.4, 1 }
        local hex = format("%02x%02x%02x", ac[1] * 255, ac[2] * 255, ac[3] * 255)
        card = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "legacy",
            titleText = "|cff" .. hex .. L_("LEGACY_TITLE", "Legacy") .. "|r",
            subtitleText = L_("LEGACY_SUBTITLE", "Account-wide Legacy points, reward tiers and challenges"),
            showUnderline = false,
        }))
        mf._legacyFixedHeaderCache = { titleCard = card }
    end
    card:SetParent(headerParent)
    card:Show()
    if chrome and ns.UI_PageStack_Place then
        chrome.yOffset = y
        y = ns.UI_PageStack_Place(chrome, card)
    else
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", side, -y)
        card:SetPoint("TOPRIGHT", -side, -y)
        y = y + (card:GetHeight() or 60) + 8
    end
    if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, y) end
end

-- LEGACY TRACK CARD
--
-- Title row (track name, points earned), then one reward card per tier in a two-column grid (one
-- column when the body is narrow): reward icon | name over "<kind> - <n> points" | state. Earned
-- tiers get a green check and a green edge, the next tier reads in gold, later ones muted. No bar:
-- the tier cards already say how far along the track is, a second empty bar only added noise.

local REWARD_KIND_LABEL = {
    mount = { "LEGACY_REWARD_MOUNT", "Mount" },
    pet = { "LEGACY_REWARD_PET", "Pet" },
    toy = { "LEGACY_REWARD_TOY", "Toy" },
    title = { "LEGACY_REWARD_TITLE", "Title" },
    appearance = { "LEGACY_REWARD_APPEARANCE", "Appearance" },
    spell = { "LEGACY_REWARD_SPELL", "Spell" },
    item = { "LEGACY_REWARD_ITEM", "Item" },
}

local function RewardKindLabel(kind)
    local def = kind and REWARD_KIND_LABEL[kind]
    return def and L_(def[1], def[2]) or nil
end

--- One tier: the first reward carries the card (every Legacy tier has exactly one).
local function PaintTierCard(card, tier, level, isNext)
    local pad = LAYOUT.TIER_PAD
    local tl = tonumber(tier.level) or 0
    local earned = level >= tl
    local reward = tier.rewards and tier.rewards[1] or nil

    -- Earned: semantic green edge on the bordered container.
    if earned and card.SetBackdropBorderColor and ns.UI_GetSemanticGreenColor then
        local r, g, b = ns.UI_GetSemanticGreenColor()
        card:SetBackdropBorderColor(r, g, b, 0.9)
    end

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(LAYOUT.TIER_ICON, LAYOUT.TIER_ICON)
    icon:SetPoint("LEFT", card, "LEFT", pad, 0)
    if reward and reward.icon then
        icon:SetTexture(reward.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDesaturated(not earned and not isNext)
    else
        ns.UI_SetIcon(icon, "trophy")
    end

    -- Right: state. A check + "Earned", or how many points remain.
    local state = FontManager:CreateFontString(card, "body", "OVERLAY")
    state:SetPoint("RIGHT", card, "RIGHT", -pad, 0)
    state:SetJustifyH("RIGHT")
    if earned then
        local check = card:CreateTexture(nil, "OVERLAY")
        check:SetSize(LAYOUT.TIER_CHECK, LAYOUT.TIER_CHECK)
        check:SetPoint("RIGHT", state, "LEFT", -4, 0)
        ns.UI_SetIcon(check, "status_ok")
        state:SetText(ns.UI_GetSemanticGreenHex() .. L_("LEGACY_TIER_EARNED", "Earned") .. "|r")
    else
        local hex = isNext and ns.UI_GetSemanticGoldHex() or ns.UI_GetTextRoleHex("Muted")
        state:SetText(hex .. format(L_("LEGACY_TIER_NEED_FMT", "%d to go"), tl - level) .. "|r")
    end

    local name = FontManager:CreateFontString(card, "header", "OVERLAY")
    name:SetPoint("BOTTOMLEFT", icon, "RIGHT", 12, 2)
    name:SetPoint("RIGHT", state, "LEFT", -(LAYOUT.TIER_CHECK + 12), 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local rewardName = reward and SafeText(reward.name) or ""
    name:SetText(rewardName ~= "" and rewardName or L_("LEGACY_REWARD_PENDING", "Reward"))
    ns.UI_SetTextColorRole(name, (earned or isNext) and "Bright" or "Normal")

    local meta = FontManager:CreateFontString(card, "small", "OVERLAY")
    meta:SetPoint("TOPLEFT", icon, "RIGHT", 12, -3)
    meta:SetPoint("RIGHT", state, "LEFT", -(LAYOUT.TIER_CHECK + 12), 0)
    meta:SetJustifyH("LEFT")
    meta:SetWordWrap(false)
    local kind = RewardKindLabel(reward and reward.kind)
    local pts = format(L_("LEGACY_TIER_FMT", "%d points"), tl)
    meta:SetText(kind and (kind .. "  -  " .. pts) or pts)
    ns.UI_SetTextColorRole(meta, "Muted")
end

function LegacyUI.PaintTrackCard(parent, track, y, side, contentW)
    local pad = LAYOUT.CARD_PAD
    local tiers = track.tiers or {}
    local level = tonumber(track.level) or 0
    local maxLevel = (tiers[#tiers] and tonumber(tiers[#tiers].level)) or 0
    local cols = (contentW >= LAYOUT.TIER_TWO_COL_MIN_W) and 2 or 1
    local rows = math.ceil(#tiers / cols)
    local gridH = rows * LAYOUT.TIER_CARD_H + math.max(0, rows - 1) * LAYOUT.TIER_GAP
    local cardH = pad + LAYOUT.TRACK_TITLE_H + LAYOUT.TIER_GAP + gridH + pad

    local card = ns.UI_CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", side, -y)
    card:SetPoint("TOPRIGHT", -side, -y)
    card:Show()

    local title = FontManager:CreateFontString(card, "header", "OVERLAY")
    title:SetPoint("TOPLEFT", pad, -pad)
    title:SetText(SafeText(track.name) ~= "" and SafeText(track.name) or L_("LEGACY_TRACK_TITLE", "Legacy Track"))
    ns.UI_SetTextColorRole(title, "Bright")

    local points = FontManager:CreateFontString(card, "body", "OVERLAY")
    points:SetPoint("TOPRIGHT", -pad, -pad)
    points:SetJustifyH("RIGHT")
    points:SetText(format(L_("LEGACY_POINTS_FMT", "%d / %d points"), level, maxLevel))
    ns.UI_SetTextColorRole(points, "Bright")

    if #tiers == 0 then return y + cardH end
    local innerW = math.max(1, contentW - pad * 2)
    local cellW = math.floor((innerW - (cols - 1) * LAYOUT.TIER_GAP) / cols)
    local top = pad + LAYOUT.TRACK_TITLE_H + LAYOUT.TIER_GAP
    local nextMarked = false
    for i = 1, #tiers do
        local tier = tiers[i]
        local isNext = false
        if not nextMarked and level < (tonumber(tier.level) or 0) then
            isNext = true
            nextMarked = true
        end
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cell = ns.UI.Factory:CreateContainer(card, cellW, LAYOUT.TIER_CARD_H, true)
        cell:SetPoint("TOPLEFT", pad + col * (cellW + LAYOUT.TIER_GAP),
            -(top + row * (LAYOUT.TIER_CARD_H + LAYOUT.TIER_GAP)))
        cell:Show()
        PaintTierCard(cell, tier, level, isNext)
    end
    return y + cardH
end

-- CHALLENGES

--- Root sections in id order, each with its direct entries and its subcategories (with entries).
function LegacyUI.BuildChallengeTree(ch)
    local roots, byID = {}, {}
    local cats = ch and ch.categories or {}
    for i = 1, #cats do
        local c = cats[i]
        if c and c.id and c.id ~= HIDDEN_CATEGORY_ID then
            byID[c.id] = { id = c.id, name = SafeText(c.name), parent = c.parent, entries = {}, subs = {} }
        end
    end
    for _, node in pairs(byID) do
        local parentNode = node.parent and byID[node.parent]
        if parentNode then
            parentNode.subs[#parentNode.subs + 1] = node
        elseif node.parent == -1 then
            roots[#roots + 1] = node
        end
    end
    local entries = ch and ch.entries or {}
    for i = 1, #entries do
        local e = entries[i]
        local node = e and byID[e.category]
        if node then node.entries[#node.entries + 1] = e end
    end
    local function byId(a, b) return a.id < b.id end
    table.sort(roots, byId)
    for i = 1, #roots do
        local r = roots[i]
        table.sort(r.subs, byId)
        local earned, total = 0, 0
        local function count(list)
            for k = 1, #list do
                total = total + 1
                if list[k].completed then earned = earned + 1 end
            end
        end
        count(r.entries)
        for s = 1, #r.subs do count(r.subs[s].entries) end
        r.earned, r.total = earned, total
    end
    -- A root with no challenges anywhere under it is not a section.
    local out = {}
    for i = 1, #roots do
        if roots[i].total > 0 then out[#out + 1] = roots[i] end
    end
    return out
end

--- Progress of one challenge: done flag, numerator, denominator. One counted criterion reads as
--- "have / need"; several read as criteria done / criteria total.
function LegacyUI.GetProgress(e)
    if e.completed then return true, 1, 1 end
    local crit = e.criteria
    if type(crit) ~= "table" or #crit == 0 then return false, nil, nil end
    if #crit == 1 and (tonumber(crit[1].need) or 0) > 1 then
        return false, tonumber(crit[1].have) or 0, tonumber(crit[1].need) or 0
    end
    local done = 0
    for i = 1, #crit do if crit[i].done then done = done + 1 end end
    return false, done, #crit
end

function LegacyUI.FormatEarnedDate(d)
    if type(d) ~= "table" or not d.year then return nil end
    local y = d.year < 100 and (2000 + d.year) or d.year
    return format("%02d.%02d.%04d", d.day or 0, d.month or 0, y)
end

--- Description, reward and criteria on hover (semantic tooltip colours; light mode safe).
function LegacyUI.ShowEntryTooltip(row)
    local e = row and row._wnLegacyEntry
    if not e or not ns.UI_SafeSetGameTooltipOwner or not ns.UI_SafeSetGameTooltipOwner(row, "ANCHOR_RIGHT") then return end
    local tr, tg, tb = ns.UI_GetTooltipTitleColor()
    local br, bg, bb = ns.UI_GetTooltipBodyColor()
    local dr, dg, db = ns.UI_GetTooltipDescColor()
    GameTooltip:SetText(SafeText(e.name), tr, tg, tb)
    if e.description then GameTooltip:AddLine(SafeText(e.description), dr, dg, db, true) end
    if e.rewardText then
        local gr, gg, gb = 1, 0.82, 0
        if ns.UI_GetSemanticGoldColor then gr, gg, gb = ns.UI_GetSemanticGoldColor() end
        GameTooltip:AddLine(SafeText(e.rewardText), gr, gg, gb, true)
    end
    local crit = e.criteria or {}
    if #crit > 0 then GameTooltip:AddLine(" ") end
    for i = 1, #crit do
        local c = crit[i]
        local need = tonumber(c.need) or 0
        local right = c.done and L_("LEGACY_COMPLETED", "Completed")
            or ((need > 1) and format("%d / %d", tonumber(c.have) or 0, need) or "-")
        GameTooltip:AddDoubleLine(SafeText(c.name), right, br, bg, bb, br, bg, bb)
    end
    GameTooltip:Show()
end

--- Right-hand progress block shared by sub headers and rows: count text over a thin accent bar.
function LegacyUI.PaintProgressBlock(holder, done, num, den, rightInset)
    local text = FontManager:CreateFontString(holder, "body", "OVERLAY")
    text:SetJustifyH("RIGHT")
    text:SetWidth(LAYOUT.PROGRESS_W)
    if done then
        text:SetPoint("RIGHT", holder, "RIGHT", -rightInset, 0)
        text:SetText(ns.UI_GetSemanticGreenHex() .. L_("LEGACY_COMPLETED", "Completed") .. "|r")
        return
    end
    if not den or den <= 0 then
        text:SetPoint("RIGHT", holder, "RIGHT", -rightInset, 0)
        text:SetText(ns.UI_GetTextRoleHex("Muted") .. L_("LEGACY_NOT_STARTED", "Not started") .. "|r")
        return
    end
    text:SetPoint("BOTTOMRIGHT", holder, "RIGHT", -rightInset, 1)
    text:SetText(format("%d / %d", num or 0, den))
    ns.UI_SetTextColorRole(text, "Bright")
    local bar = ns.UI_CreateProgressBar(holder, LAYOUT.PROGRESS_W, LAYOUT.PROGRESS_BAR_H, nil, nil, true)
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", holder, "RIGHT", -rightInset, -3)
        bar:SetMinMaxValues(0, den)
        bar:SetValue(math.min(num or 0, den))
        local ac = ns.UI_COLORS and ns.UI_COLORS.accent
        if ac and not bar._wnBlizzardChrome then bar:SetStatusBarColor(ac[1], ac[2], ac[3], 1) end
    end
end

--- Challenge row: icon | name over description | progress block (or "Completed" + date).
function LegacyUI.PaintEntryRow(host, e, y, rowIndex, inset)
    local row, nextY = ns.UI.Factory:CreateDataRow(host, y, rowIndex, LAYOUT.ROW_H)
    if not row then return y end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(LAYOUT.ROW_ICON, LAYOUT.ROW_ICON)
    icon:SetPoint("LEFT", inset, 0)
    if e.icon then
        icon:SetTexture(e.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Unearned challenges read dimmer; earned ones at full strength.
        icon:SetAlpha(e.completed and 1 or 0.75)
    else
        ns.UI_SetIcon(icon, "trophy")
    end

    local done, num, den = LegacyUI.GetProgress(e)
    LegacyUI.PaintProgressBlock(row, done, num, den, LAYOUT.ROW_TEXT_INSET)
    local textRight = LAYOUT.ROW_TEXT_INSET + LAYOUT.PROGRESS_W + 16

    local name = FontManager:CreateFontString(row, "body", "OVERLAY")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(SafeText(e.name))
    ns.UI_SetTextColorRole(name, "Bright")

    local subText = e.description and SafeText(e.description) or nil
    local dateStr = done and LegacyUI.FormatEarnedDate(e.earnedDate)
    if dateStr then
        subText = (subText and (subText .. "  ") or "") .. format(L_("LEGACY_EARNED_ON_FMT", "Earned %s"), dateStr)
    end
    if subText and subText ~= "" then
        name:SetPoint("BOTTOMLEFT", icon, "RIGHT", 10, 1)
        name:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)
        local desc = FontManager:CreateFontString(row, "small", "OVERLAY")
        desc:SetPoint("TOPLEFT", icon, "RIGHT", 10, -2)
        desc:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)
        desc:SetText(subText)
        ns.UI_SetTextColorRole(desc, "Muted")
    else
        name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)
    end

    row:EnableMouse(true)
    row._wnLegacyEntry = e
    row:SetScript("OnEnter", LegacyUI.ShowEntryTooltip)
    row:SetScript("OnLeave", ns.UI_SafeHideGameTooltip)
    return nextY
end

function LegacyUI.CountEarned(list)
    local earned = 0
    for i = 1, #list do if list[i].completed then earned = earned + 1 end end
    return earned
end

--[[
    Section tree, same model as the Currency / Reputation tabs: every section is a WRAP holding its
    collapsible header and a BODY under it. Sibling wraps chain to each other's bottom, so when one
    wrap changes height everything below it moves with no repaint; a toggle resizes its own wrap,
    then walks up (ReflowUp) re-measuring each ancestor body, and finally re-syncs the scroll child.

    Heights are kept as numbers on the frames (_wnLegacyH) rather than measured from GetTop/GetBottom,
    which read nil on frames created this same frame. Bodies are built on first expand.
]]
local function HeaderH()
    return (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT) or 36
end

local function BaseIndent()
    return (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 15
end

--- Wrap height from its own header + (open) body.
local function WrapHeight(wrap)
    local body = wrap._wnLegacyBody
    local bodyH = (body and wrap._wnLegacyOpen) and (body._wnLegacyH or 0) or 0
    return HeaderH() + bodyH
end

--- Body height: its direct rows plus every child wrap and the gaps before them.
local function BodyHeight(body)
    local h = body._wnLegacyRowsH or 0
    local kids = body._wnLegacyChildWraps or {}
    for i = 1, #kids do
        h = h + LAYOUT.SUBHDR_GAP_BEFORE + WrapHeight(kids[i])
    end
    return h
end

local function ApplyWrap(wrap)
    local body = wrap._wnLegacyBody
    if body then
        if wrap._wnLegacyOpen then
            body._wnLegacyH = BodyHeight(body)
            body:SetHeight(math.max(0.1, body._wnLegacyH))
            body:Show()
        else
            body:Hide()
            body:SetHeight(0.1)
        end
    end
    wrap:SetHeight(WrapHeight(wrap))
end

--- Re-measure from a toggled wrap up to the host, then hand the new content bottom to the shell.
function LegacyUI.ReflowUp(wrap)
    local w = wrap
    while w do
        ApplyWrap(w)
        w = w._wnLegacyParentWrap
    end
    local ctx = LegacyUI._ctx
    if not ctx or not ctx.host then return end
    local hostH = 0
    for i = 1, #ctx.rootWraps do
        hostH = hostH + WrapHeight(ctx.rootWraps[i]) + LAYOUT.SECTION_GAP
    end
    ctx.host:SetHeight(math.max(1, hostH))
    if ns.UI_SyncMainTabScrollChrome and ctx.mf and ctx.scrollChild then
        ns.UI_SyncMainTabScrollChrome(ctx.mf, ctx.scrollChild, ctx.hostTop + hostH + ctx.bottomGap)
    end
end

--- Section header inside a wrap: chevron, optional icon, title, progress block on the right.
local function AttachHeader(wrap, node, open, earned, total, iconTex, onToggle)
    local header = ns.UI_CreateCollapsibleHeader(wrap, SafeText(node.name), "legacy_" .. tostring(node.id),
        open, onToggle, iconTex, false, nil, iconTex == nil, { useFullParentWidth = true })
    if not header then return end
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, 0)
    header:SetHeight(HeaderH())
    LegacyUI.PaintProgressBlock(header, total > 0 and earned == total, earned, total, LAYOUT.ROW_TEXT_INSET)
end

--- Wrap + body for one section. `build(body)` fills the body (rows, child wraps) and runs once.
local function CreateSectionWrap(parentFrame, width, node, open, earned, total, iconTex, parentWrap, build)
    local wrap = ns.UI.Factory:CreateContainer(parentFrame, width, HeaderH(), false)
    wrap:SetWidth(width)
    if wrap.SetClipsChildren then wrap:SetClipsChildren(true) end
    wrap._wnLegacyParentWrap = parentWrap
    wrap._wnLegacyOpen = open and true or false
    wrap:Show()

    local body = ns.UI.Factory:CreateContainer(wrap, width, 0.1, false)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, -HeaderH())
    body:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, -HeaderH())
    body._wnLegacyChildWraps = {}
    wrap._wnLegacyBody = body

    local function ensureBuilt()
        if body._wnLegacyBuilt then return end
        body._wnLegacyBuilt = true
        build(body, wrap)
    end

    AttachHeader(wrap, node, open, earned, total, iconTex, function(isExpanded)
        wrap._wnLegacyOpen = isExpanded and true or false
        LegacyUI.PersistExpanded(node.id, isExpanded)
        if isExpanded then ensureBuilt() end
        LegacyUI.ReflowUp(wrap)
    end)

    if open then ensureBuilt() end
    ApplyWrap(wrap)
    return wrap
end

--- Chain `frame` under `prev` (or at `topY` in `parentFrame` when first), at `left` from the parent.
local function ChainBelow(parentFrame, frame, prev, left, topY, gap)
    frame:ClearAllPoints()
    if prev then
        frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
    else
        frame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", left, -topY)
    end
end

function LegacyUI.PaintChallenges(parent, ch, y, side, contentW)
    local roots = LegacyUI.BuildChallengeTree(ch)
    if #roots == 0 then return y end
    local host = ns.UI.Factory:CreateContainer(parent, contentW, 1, false)
    host:SetPoint("TOPLEFT", side, -y)
    host:SetPoint("TOPRIGHT", -side, -y)
    host:Show()

    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local ctx = { host = host, rootWraps = {}, mf = mf, scrollChild = parent, hostTop = y,
        bottomGap = ((ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK and ns.UI_LAYOUT.PAGE_STACK.SECTION_GAP) or 12) }
    LegacyUI._ctx = ctx

    local indent = BaseIndent()
    local subW = math.max(1, contentW - indent)
    local prevRoot
    for i = 1, #roots do
        local root = roots[i]
        local rootOpen = LegacyUI.IsSectionExpanded(root.id, false)
        local rootWrap = CreateSectionWrap(host, contentW, root, rootOpen, root.earned, root.total, nil, nil,
            function(body, wrap)
                local ry = 0
                for k = 1, #root.entries do
                    ry = LegacyUI.PaintEntryRow(body, root.entries[k], ry, k, LAYOUT.ROW_TEXT_INSET)
                end
                body._wnLegacyRowsH = ry
                local prevSub
                for s = 1, #root.subs do
                    local sub = root.subs[s]
                    if #sub.entries > 0 then
                        local first = sub.entries[1]
                        local subWrap = CreateSectionWrap(body, subW, sub, LegacyUI.IsSectionExpanded(sub.id, true),
                            LegacyUI.CountEarned(sub.entries), #sub.entries, first and first.icon or nil, wrap,
                            function(subBody)
                                local sy = 0
                                for k = 1, #sub.entries do
                                    sy = LegacyUI.PaintEntryRow(subBody, sub.entries[k], sy, k, LAYOUT.ROW_TEXT_INSET)
                                end
                                subBody._wnLegacyRowsH = sy
                            end)
                        ChainBelow(body, subWrap, prevSub, indent, ry + LAYOUT.SUBHDR_GAP_BEFORE, LAYOUT.SUBHDR_GAP_BEFORE)
                        body._wnLegacyChildWraps[#body._wnLegacyChildWraps + 1] = subWrap
                        prevSub = subWrap
                    end
                end
            end)
        ChainBelow(host, rootWrap, prevRoot, 0, 0, LAYOUT.SECTION_GAP)
        ApplyWrap(rootWrap)
        ctx.rootWraps[#ctx.rootWraps + 1] = rootWrap
        prevRoot = rootWrap
    end

    local hostH = 0
    for i = 1, #ctx.rootWraps do
        hostH = hostH + WrapHeight(ctx.rootWraps[i]) + LAYOUT.SECTION_GAP
    end
    host:SetHeight(math.max(1, hostH))
    return y + hostH
end

-- TAB ENTRY

function WarbandNexus:DrawLegacyTab(parent)
    local mf = self.UI and self.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local side = (metrics and metrics.sideMargin) or 12
    local ps = (ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK) or {}
    local sectionGap = ps.SECTION_GAP or 12
    -- Measure the scroll child itself: it already excludes the reserved scrollbar gutter, which
    -- metrics.contentWidth does not -- the tier cells ran past the card's right edge.
    local contentW = math.max(1, (parent:GetWidth() or 600) - side * 2)

    LegacyUI.PaintHeader(mf, side)

    local y = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local store = self.GetLegacyProgress and self:GetLegacyProgress()
    if not store or type(store.track) ~= "table" then
        local _, h = ns.UI_CreateEmptyStateCard(parent, "legacy", y, { sideInset = side })
        return y + (h or 120)
    end
    if ns.UI_HideEmptyStateCard then ns.UI_HideEmptyStateCard(parent, "legacy") end

    y = LegacyUI.PaintTrackCard(parent, store.track, y, side, contentW) + sectionGap
    y = LegacyUI.PaintChallenges(parent, store.challenges, y, side, contentW)
    return y + sectionGap
end
