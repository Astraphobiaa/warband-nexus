--[[
    Warband Nexus - Recipe detail: where the reagents are and who knows the recipe.

    The recipe detail pane (CharacterSystemsPopup) is the one surface for a recipe: the saved-recipe
    window from the Characters tab and the live companion beside Blizzard's profession frame both
    draw it. This file adds the warband part the old Recipe Companion window showed on its own:

      * a per-reagent table, opened from the reagent row: every character's bags and bank, the
        Warband Bank and the total (WarbandNexus:GetReagentHoldings);
      * a "Known by" line with the characters that know the recipe (GetCraftersForRecipe).

    Pure view: every number comes from the profession service, read from saved data, so an offline
    alt's recipe shows that alt's view. Elements are pooled on the detail table `d`.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

local H = {}
ns.RecipeHoldingsUI = H

local ROW_H = 20            -- holdings table row
local HEAD_H = 18           -- holdings column header
local CARD_PAD = 4          -- inset of the rows inside the bordered card
local COL_W = 54            -- count columns (rank columns, or bags / bank, then total)
local MAX_COLS = 4          -- up to three quality ranks plus the total
local ICON_W = 14           -- class crest / Warband icon in front of a row name
local MAX_KNOWN_NAMES = 4   -- "Known by" names before "+N"

local function L(key, fallback)
    local tbl = ns.L
    return (tbl and tbl[key]) or fallback
end

local function Factory()
    return ns.UI and ns.UI.Factory
end

local function ClassHex(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function RoleHex(role)
    if ns.UI_GetTextRoleHexRaw then return ns.UI_GetTextRoleHexRaw(role) end
    return "ffffff"
end

local function GoldHex()
    if ns.UI_GetSemanticGoldHex then return (ns.UI_GetSemanticGoldHex():gsub("|cff", "")) end
    return "ffcc00"
end

local function CharName(charKey)
    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    local cd = chars and charKey and chars[charKey]
    if cd and ns.CharDisplayName then return ns.CharDisplayName(cd, charKey), cd.classFile or cd.class end
    return charKey or "?", nil
end

--- Count for a column: grouped below a million ("99.999"), short above ("1.2M") so stacks of
--- any size stay inside COL_W.
local function Short(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    return ns.UI_FormatNumber and ns.UI_FormatNumber(n) or tostring(n)
end

local function Count(n, hex)
    n = tonumber(n) or 0
    if n <= 0 then return "|cff" .. RoleHex("Dim") .. "-|r" end
    return "|cff" .. (hex or RoleHex("Bright")) .. Short(n) .. "|r"
end

--- Quality-rank mark for a column header: Blizzard's inline chat atlas of that tier's item
--- (static item data, so it reads for offline alts too), else the saved atlas, else "R<n>".
local function TierMark(tier, index)
    local atlas
    local TS = C_TradeSkillUI
    if tier and tier.itemID and TS and TS.GetItemReagentQualityInfo then
        local ok, qi = pcall(TS.GetItemReagentQualityInfo, tier.itemID)
        local a = ok and type(qi) == "table" and (qi.iconChat or qi.iconSmall)
        if type(a) == "string" and not (issecretvalue and issecretvalue(a)) then atlas = a end
    end
    atlas = atlas or (tier and tier.atlas)
    if not atlas then return "R" .. index end
    local h = 16
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local w = (info and info.height and info.height > 0) and math.floor(h * info.width / info.height + 0.5) or h
    return string.format("|A:%s:%d:%d|a", atlas, h, w)
end

-- ---------------------------------------------------------------------------
-- Pool: one bordered card per open reagent, its rows pooled inside it
-- ---------------------------------------------------------------------------

local function AcquireCard(d, index)
    d.holdCards = d.holdCards or {}
    local card = d.holdCards[index]
    if not card then
        local F = Factory()
        card = F and F:CreateContainer(d.pane, 10, 10, true)
        if not card then return nil end
        card.rows = {}
        d.holdCards[index] = card
    end
    for i = 1, #card.rows do card.rows[i]:Hide() end
    card:Show()
    return card
end

--- Bags / bank per rank of the hovered row (the columns show bags + bank together).
local function RowOnEnter(self)
    local t = self._wnTip
    if not t or not ns.UI_SafeSetGameTooltipOwner(self, "ANCHOR_RIGHT") then return end
    local tr, tg, tb = ns.UI_GetTooltipTitleColor()
    local br, bg, bb = ns.UI_GetTooltipBodyColor()
    GameTooltip:AddLine(t.title, tr, tg, tb)
    for i = 1, #t.lines do
        local line = t.lines[i]
        GameTooltip:AddDoubleLine(line[1], line[2], br, bg, bb, br, bg, bb)
    end
    GameTooltip:Show()
end

local function RowOnLeave()
    if ns.UI_SafeHideGameTooltip then ns.UI_SafeHideGameTooltip() end
end

local function AcquireCardRow(card, index)
    local row = card.rows[index]
    if not row then
        local F = Factory()
        row = F and F:CreateContainer(card, 10, ROW_H, false)
        if not row then return nil end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_W, ICON_W)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.cols = {}
        local anchor, point = row, "RIGHT"
        for c = MAX_COLS, 1, -1 do
            local fs = FontManager:CreateFontString(row, "body", "OVERLAY")
            fs:SetPoint("RIGHT", anchor, point, c == MAX_COLS and -8 or 0, 0)
            fs:SetWidth(COL_W)
            -- Centred under the header: rank marks, "-" and counts of any width share one axis.
            fs:SetJustifyH("CENTER")
            fs:SetWordWrap(false)
            row.cols[c] = fs
            anchor, point = fs, "LEFT"
        end
        row:EnableMouse(true)
        row:SetScript("OnEnter", RowOnEnter)
        row:SetScript("OnLeave", RowOnLeave)
        card.rows[index] = row
    end
    row:Show()
    return row
end

--- Hide everything this file drew; called at the start of every detail paint.
function H.Begin(d)
    d.cardUsed = 0
    if d.holdCards then
        for i = 1, #d.holdCards do d.holdCards[i]:Hide() end
    end
    if d.expandAll then d.expandAll:Hide() end
end

-- ---------------------------------------------------------------------------
-- Holdings table under one reagent row
-- ---------------------------------------------------------------------------

--- Item ids of every quality tier a reagent slot takes (rank 1 first).
function H.ReagentItemIDs(rg)
    local ids = {}
    if type(rg.tiers) == "table" and #rg.tiers > 0 then
        for t = 1, #rg.tiers do ids[#ids + 1] = rg.tiers[t].itemID end
    elseif rg.itemID then
        ids[1] = rg.itemID
    end
    return ids
end

--[[
    One table row. kind: "head" (column labels), "char" (class crest), "warband" (Warband icon),
    "total". vals fills the rightmost #vals columns (the last one is the total). Zebra rows come
    from the Factory row background; the viewed character gets the online-character accent so
    "whose view is this" reads at a glance. tip: optional { title, lines = { {left, right} } }.
]]
local function FillRow(card, index, y, kind, name, vals, classFile, isSelf, tip)
    local row = AcquireCardRow(card, index)
    local h = (kind == "head") and HEAD_H or ROW_H
    if not row then return y - h end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, y)
    row:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    row:SetHeight(h)
    local F = Factory()
    if F then
        if kind == "head" then
            if row.bg then row.bg:Hide() end
        else
            F:ApplyRowBackground(row, index)
            if row.bg then row.bg:Show() end
        end
        if F.ApplyOnlineCharacterHighlight then F:ApplyOnlineCharacterHighlight(row, isSelf == true) end
    end
    row.icon:Show()
    if kind == "char" and ns.UI_ApplyClassIconTexture and classFile then
        ns.UI_ApplyClassIconTexture(row.icon, classFile)
    elseif kind == "warband" and ns.UI_SetIcon then
        ns.UI_SetIcon(row.icon, "warband")
    else
        row.icon:Hide()
    end
    -- The name gives up exactly the room the shown columns take.
    local first = MAX_COLS - #vals + 1
    row.name:SetPoint("RIGHT", row, "RIGHT", -(COL_W * #vals + 8 + 6), 0)
    row.name:SetText(name)
    for c = 1, MAX_COLS do
        if c >= first then
            row.cols[c]:SetText(vals[c - first + 1])
            row.cols[c]:Show()
        else
            row.cols[c]:Hide()
        end
    end
    row._wnTip = tip
    return y - h
end

--- Hover lines for a row of a ranked reagent: per rank, bags and bank.
local function RankTip(title, marks, bagTiers, bankTiers)
    local bagsL, bankL = L("RECIPES_HOLD_BAGS", "Bags"), L("RECIPES_HOLD_BANK", "Bank")
    local lines = {}
    for t = 1, #marks do
        local bag, bank = (bagTiers and bagTiers[t]) or 0, (bankTiers and bankTiers[t]) or 0
        lines[#lines + 1] = { marks[t], bagsL .. " " .. Short(bag) .. "   " .. bankL .. " " .. Short(bank) }
    end
    return { title = title, lines = lines }
end

--[[
    Draw the table for reagent `rg` with its top edge at `y` (pane coordinates), from `left` to the
    pane's right padding: a bordered card. A ranked reagent gets one column per quality rank
    (bags + bank of that rank; hover a row for the split) and the total; a single-item reagent
    gets Bags | Bank | Total. Rows: the viewed character, every other character holding any of
    it, the Warband Bank, and the total. Returns the height used.
]]
function H.DrawHoldings(d, rg, y, left)
    local ids = H.ReagentItemIDs(rg)
    local h = WarbandNexus.GetReagentHoldings and WarbandNexus:GetReagentHoldings(ids, d.charKey)
    if not h then return 0 end
    d.cardUsed = (d.cardUsed or 0) + 1
    local card = AcquireCard(d, d.cardUsed)
    if not card then return 0 end
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", d.pane, "TOPLEFT", left, y)
    card:SetPoint("RIGHT", d.pane, "RIGHT", -d.padX, 0)

    local muted, bright = "|cff" .. RoleHex("Muted"), "|cff" .. RoleHex("Bright")
    local ranked = #ids > 1
    local nTier = math.min(#ids, MAX_COLS - 1)
    local marks = {}
    if ranked then
        for t = 1, nTier do marks[t] = TierMark(rg.tiers and rg.tiers[t] or { itemID = ids[t] }, t) end
    end
    local totalHead = muted .. L("RECIPES_HOLD_TOTAL", "Total") .. "|r"

    -- Row values: per rank (ranked) or bags / bank (single item), then the row total.
    local function Vals(tiers, bag, bank, total, hex)
        local v = {}
        if ranked then
            for t = 1, nTier do v[t] = Count(tiers and tiers[t], hex) end
        else
            v[1], v[2] = Count(bag, hex), Count(bank, hex)
        end
        v[#v + 1] = Count(total, hex)
        return v
    end

    local n, ry = 1, -CARD_PAD
    local head = {}
    if ranked then
        for t = 1, nTier do head[t] = marks[t] end
    else
        head[1] = muted .. L("RECIPES_HOLD_BAGS", "Bags") .. "|r"
        head[2] = muted .. L("RECIPES_HOLD_BANK", "Bank") .. "|r"
    end
    head[#head + 1] = totalHead
    ry = FillRow(card, n, ry, "head", muted .. L("RECIPES_HOLD_CHARACTER", "Character") .. "|r", head)

    local selfName, selfClass = CharName(d.charKey)
    local me = h.self
    n = n + 1
    ry = FillRow(card, n, ry, "char", "|cff" .. ClassHex(selfClass) .. selfName .. "|r",
        Vals(me.tiers, me.bag, me.bank, me.bag + me.bank), selfClass, true,
        ranked and RankTip(selfName, marks, me.bagTiers, me.bankTiers) or nil)
    local bagSum, bankSum = me.bag, me.bank
    for i = 1, #h.others do
        local o = h.others[i]
        if o.bag + o.bank > 0 then
            bagSum, bankSum = bagSum + o.bag, bankSum + o.bank
            n = n + 1
            ry = FillRow(card, n, ry, "char", "|cff" .. ClassHex(o.classFile) .. (o.charName or "?") .. "|r",
                Vals(o.tiers, o.bag, o.bank, o.bag + o.bank), o.classFile, false,
                ranked and RankTip(o.charName or "?", marks, o.bagTiers, o.bankTiers) or nil)
        end
    end
    n = n + 1
    ry = FillRow(card, n, ry, "warband", "|cff" .. GoldHex() .. L("ITEMS_WARBAND_BANK", "Warband Bank") .. "|r",
        Vals(h.warband.tiers, 0, h.warband.total, h.warband.total))
    bankSum = bankSum + h.warband.total
    n = n + 1
    ry = FillRow(card, n, ry, "total", bright .. L("RECIPES_HOLD_TOTAL", "Total") .. "|r",
        Vals(h.tierTotals, bagSum, bankSum, h.total, RoleHex("Bright")))

    local height = -ry + CARD_PAD
    card:SetHeight(height)
    return height
end

-- ---------------------------------------------------------------------------
-- "Show all" toggle beside the Reagents header
-- ---------------------------------------------------------------------------

--- Button that opens or closes every reagent's table at once. onClick runs after the state flips.
function H.PlaceExpandAll(d, head, reagents, onClick)
    local F = Factory()
    if not F then return end
    if not d.expandAll then
        local btn = F:CreateButton(d.pane, 84, 20, false)
        if not btn then return end
        if ns.UI_ApplyVisuals and ns.UI_GetControlChromeBackdrop then
            local a = ns.UI_COLORS and ns.UI_COLORS.accent or { 0.5, 0.4, 0.7 }
            ns.UI_ApplyVisuals(btn, ns.UI_GetControlChromeBackdrop(), { a[1], a[2], a[3], 0.6 })
        end
        btn.label = FontManager:CreateFontString(btn, "small", "OVERLAY")
        btn.label:SetPoint("CENTER", 0, 0)
        ns.UI_SetTextColorRole(btn.label, "Bright")
        btn:SetScript("OnClick", function(self)
            local dd = self._wnDetail
            local list = self._wnReagents or {}
            local open = not self._wnAllOpen
            for i = 1, #list do dd.expanded[list[i].itemID or i] = open or nil end
            if self._wnOnClick then self._wnOnClick() end
        end)
        d.expandAll = btn
    end
    local btn = d.expandAll
    local allOpen = #reagents > 0
    for i = 1, #reagents do
        if not d.expanded[reagents[i].itemID or i] then allOpen = false break end
    end
    btn._wnDetail, btn._wnReagents, btn._wnOnClick, btn._wnAllOpen = d, reagents, onClick, allOpen
    btn.label:SetText(allOpen and L("RECIPES_HIDE_ALL", "Hide all") or L("RECIPES_SHOW_ALL", "Show all"))
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", d.pane, "RIGHT", -d.padX, 0)
    btn:SetPoint("TOP", head, "TOP", 0, 3)
    btn:Show()
end

-- ---------------------------------------------------------------------------
-- Known by
-- ---------------------------------------------------------------------------

--- "Known by: A, B, C +2" in class colours, or nil when no saved character knows the recipe.
function H.KnownByText(recipeID)
    if not recipeID or not WarbandNexus.GetCraftersForRecipe then return nil end
    local ok, crafters = pcall(WarbandNexus.GetCraftersForRecipe, WarbandNexus, recipeID)
    if not ok or type(crafters) ~= "table" or #crafters == 0 then return nil end
    local names = {}
    for i = 1, math.min(#crafters, MAX_KNOWN_NAMES) do
        local c = crafters[i]
        names[#names + 1] = "|cff" .. ClassHex(c.classFile) .. (c.charName or "?") .. "|r"
    end
    local text = table.concat(names, ", ")
    if #crafters > MAX_KNOWN_NAMES then text = text .. "  +" .. (#crafters - MAX_KNOWN_NAMES) end
    return string.format(L("RECIPES_KNOWN_BY", "Known by: %s"), text)
end
