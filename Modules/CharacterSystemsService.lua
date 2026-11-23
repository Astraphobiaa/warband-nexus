--[[
    Warband Nexus - talent tree and spellbook scan for the Character tab.

    Shape of the data, as measured by /wn charprobe on a live Forever client (build 70790,
    interface 16001) rather than taken from a wiki page:

    TALENTS -- the Traits system under Enum.TraitConfigType.CamelotCombat (4). Every Classic
    talent global (GetNumTalentTabs, GetTalentTabInfo, GetTalentInfo, UnitCharacterPoints) probed
    ABSENT, so this is the only surface. One config (426102 for the test Shaman) holding ONE tree
    (1082) with 50 nodes covering all three talent tabs at once. The tabs are not named anywhere
    the API exposes; they are separated by posX, which falls into clean bands with a wide gap
    between them (1020-2820 / 5020-6820 / 9080-10880 on the Shaman). Sorting the bands by posX
    reproduces the game's own left-to-right tab order, which is how a vanilla player reads a build
    ("0/0/0"), so that is the order used here.

    Within a tab, posY groups nodes into tiers (2130, 2730, ... 5730 -- a fixed 600 step, but the
    code ranks distinct values rather than assuming it). The tier's requirement is not derived
    from its index: each node carries a condition whose spentAmountRequired is the real gate
    (0, 5, 10, 15, 20, 25, 30), and isMet says whether it is passed. That distinction matters --
    a locked talent is locked either because the tier gate is unmet OR because a parent talent was
    not taken (meetsEdgeRequirements), and the two need different wording.

    SPELLS -- the spellbook lists ONLY learned spells. A wide sweep of slots 1..300 across both
    banks on a level 8 character found 22 entries, every one of them Enum.SpellBookItemType.Spell,
    and not a single FutureSpell. So "which abilities are still locked and at what level" cannot be
    answered from this client; what can be answered is which are known and at what level each was
    learned (GetSpellBookItemLevelLearned reports it: 0 for always-known, 1, 4, 6 ...).
    GetNumSpellBookSkillLines counts only the class lines (4 on the Shaman), but profession tabs
    sit past that count and are still addressable -- index 5/6/7 answered First Aid / Cooking /
    Mining -- so the class lines and the profession lines are read separately.

    Layer: this is a Service. It writes db.global.characters[key].systems and emits
    WN_CHARACTER_SYSTEMS_UPDATED; it never touches the UI.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local EVENTS = ns.Constants and ns.Constants.EVENTS
local MSG_SYSTEMS_UPDATED = (EVENTS and EVENTS.CHARACTER_SYSTEMS_UPDATED)
    or "WN_CHARACTER_SYSTEMS_UPDATED"

-- Tabs are split on the gap between CONSECUTIVE posX values. Measured on the Shaman tree: inside
-- a tab the columns step by 600 (9080, 9680, 10280, 10880), and the jump to the next tab is 2200
-- (2820 -> 5020). So the threshold has to sit between 600 and 2200 -- 1200 is clear of both.
-- (It was 2500 at first, which is ABOVE the real gap: every tab merged into one and the column
-- rendered a single "0" instead of "0/0/0".)
local TAB_BAND_GAP = 1200

-- Stamped on every scan. Alts are scanned when they log in, so a change to the SHAPE of this
-- data (the tab grouping, say) leaves older rows holding something the UI would draw wrongly.
-- Readers reject a row below this, which shows the alt as unscanned until it next logs in --
-- honest, and better than rendering a tree that was grouped by superseded rules.
local SYSTEMS_SCAN_VERSION = 6
local MAX_TREE_NODES = 400
local MAX_SPELL_SLOTS = 400
local MAX_PROFESSION_TAB = 16

local function Supports(key)
    if WarbandNexus.SupportsFeature then
        return WarbandNexus:SupportsFeature(key)
    end
    return true
end

--- Rank the distinct values of `set` ascending, returning value -> 1-based index. Used for both
--- tiers (posY) and tabs (posX) so neither depends on the spacing staying what it is today.
local function RankDistinct(set)
    local values = {}
    for v in pairs(set) do values[#values + 1] = v end
    table.sort(values)
    local rank = {}
    for i = 1, #values do rank[values[i]] = i end
    return rank, values
end

--- One talent node, resolved far enough for a tooltip line: name, ranks, and why it is locked.
local function ReadTalentNode(configID, nodeID)
    local ok, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or type(node) ~= "table" then return nil end
    if node.isVisible == false then return nil end
    local entryIDs = node.entryIDs
    local entryID = (type(entryIDs) == "table") and entryIDs[1] or nil
    if not entryID then return nil end

    local row = {
        nodeID = nodeID,
        posX = tonumber(node.posX) or 0,
        posY = tonumber(node.posY) or 0,
        rank = tonumber(node.currentRank) or 0,
        maxRanks = tonumber(node.maxRanks) or 0,
        available = node.isAvailable and true or false,
        meetsEdges = node.meetsEdgeRequirements ~= false,
    }

    -- Outgoing edges: the arrows a talent frame draws from a prerequisite down to what it
    -- unlocks. Only the node ids are kept -- the popup turns them into lines once it knows where
    -- each square landed.
    local edges = node.visibleEdges
    if type(edges) == "table" and #edges > 0 then
        local targets = {}
        for e = 1, #edges do
            local edge = edges[e]
            local target = (type(edge) == "table") and (edge.targetNode or edge.visibleEdge) or edge
            if type(target) == "number" then targets[#targets + 1] = target end
        end
        if #targets > 0 then row.edges = targets end
    end

    local okE, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if okE and type(entry) == "table" and entry.definitionID
        and type(C_Traits.GetDefinitionInfo) == "function" then
        local okD, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
        if okD and type(def) == "table" then
            row.spellID = def.spellID
            if def.overrideName and def.overrideName ~= "" then
                row.name = tostring(def.overrideName)
            elseif def.spellID and type(C_Spell) == "table" then
                local okS, sname = pcall(C_Spell.GetSpellName, def.spellID)
                if okS and sname then row.name = tostring(sname) end
                local okI, icon = pcall(C_Spell.GetSpellTexture, def.spellID)
                if okI then row.icon = icon end
            end
        end
    end

    -- The gate is the condition's spentAmountRequired, not the tier index: a tier can be reached
    -- by points spent anywhere in the same tab, and isMet already accounts for that.
    local conds = node.conditionIDs
    if type(conds) == "table" and conds[1] and type(C_Traits.GetConditionInfo) == "function" then
        local okC, cond = pcall(C_Traits.GetConditionInfo, configID, conds[1])
        if okC and type(cond) == "table" then
            row.gate = tonumber(cond.spentAmountRequired) or 0
            row.gateMet = cond.isMet and true or false
        end
    end
    row.gate = row.gate or 0
    if row.gateMet == nil then row.gateMet = true end
    return row
end

--- Group resolved nodes into tabs (posX bands, left to right) and tiers (posY, top down).
local function GroupTalentNodes(nodes)
    local xs, ys = {}, {}
    for i = 1, #nodes do
        xs[nodes[i].posX] = true
        ys[nodes[i].posY] = true
    end
    local _, xValues = RankDistinct(xs)
    local tierRank = RankDistinct(ys)

    -- Walk the sorted x values and start a new tab wherever the gap to the previous one is wide.
    local tabOfX, tabCount = {}, 0
    local prev
    for i = 1, #xValues do
        local x = xValues[i]
        if not prev or (x - prev) > TAB_BAND_GAP then tabCount = tabCount + 1 end
        tabOfX[x] = tabCount
        prev = x
    end

    local tabs = {}
    for i = 1, tabCount do
        tabs[i] = { index = i, spent = 0, tiers = {}, tierOrder = {} }
    end
    for i = 1, #nodes do
        local node = nodes[i]
        local tab = tabs[tabOfX[node.posX]]
        if tab then
            tab.spent = tab.spent + node.rank
            local tierIndex = tierRank[node.posY] or 1
            local tier = tab.tiers[tierIndex]
            if not tier then
                tier = { index = tierIndex, gate = node.gate, met = node.gateMet, nodes = {} }
                tab.tiers[tierIndex] = tier
                tab.tierOrder[#tab.tierOrder + 1] = tierIndex
            end
            -- A tier's gate is one number for the whole row; take the highest seen in case a
            -- node in the row carries no condition of its own.
            if (node.gate or 0) > (tier.gate or 0) then
                tier.gate = node.gate
                tier.met = node.gateMet
            end
            tier.nodes[#tier.nodes + 1] = node
        end
    end
    -- Column index within the tab, so the popup can draw a real grid with holes where a tier has
    -- no talent in that column -- which is what the talent frame itself looks like. Ranked rather
    -- than divided by a step, so an unusual tree spacing still lands on whole columns.
    for i = 1, #tabs do
        local tab = tabs[i]
        local xs = {}
        for k = 1, #tab.tierOrder do
            local tier = tab.tiers[tab.tierOrder[k]]
            for n = 1, #tier.nodes do xs[tier.nodes[n].posX] = true end
        end
        local columnRank
        columnRank, tab.columnValues = RankDistinct(xs)
        tab.columns = #tab.columnValues
        for k = 1, #tab.tierOrder do
            local tier = tab.tiers[tab.tierOrder[k]]
            for n = 1, #tier.nodes do
                tier.nodes[n].column = columnRank[tier.nodes[n].posX] or 1
            end
        end
    end
    for i = 1, #tabs do
        table.sort(tabs[i].tierOrder)
        -- Tier numbers are per tab: renumber so "tier 3" means the third row of THIS tab even
        -- when a tab has no node on some shared row.
        for position = 1, #tabs[i].tierOrder do
            local tier = tabs[i].tiers[tabs[i].tierOrder[position]]
            tier.position = position
            table.sort(tier.nodes, function(a, b)
                if a.posX ~= b.posX then return a.posX < b.posX end
                return (a.name or "") < (b.name or "")
            end)
        end
    end
    return tabs
end

--- Read the whole talent tree. Returns nil on a client without the Forever talent system.
function WarbandNexus:ScanTalentTree()
    if not Supports("classicTalentTree") then return nil end
    if type(C_Traits) ~= "table" or type(C_ClassTalents) ~= "table" then return nil end
    local okID, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not okID or type(configID) ~= "number" then return nil end
    local okC, config = pcall(C_Traits.GetConfigInfo, configID)
    if not okC or type(config) ~= "table" or type(config.treeIDs) ~= "table" then return nil end

    local nodes = {}
    for t = 1, #config.treeIDs do
        local treeID = config.treeIDs[t]
        local okT, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if okT and type(nodeIDs) == "table" then
            for n = 1, math.min(#nodeIDs, MAX_TREE_NODES) do
                local row = ReadTalentNode(configID, nodeIDs[n])
                if row then nodes[#nodes + 1] = row end
            end
        end
    end
    if #nodes == 0 then return nil end

    local tabs = GroupTalentNodes(nodes)
    local spent, total = 0, 0
    for i = 1, #tabs do
        spent = spent + tabs[i].spent
        for k = 1, #tabs[i].tierOrder do
            local tier = tabs[i].tiers[tabs[i].tierOrder[k]]
            for n = 1, #tier.nodes do total = total + tier.nodes[n].maxRanks end
        end
    end
    local unspent = 0
    if type(_G.GetNumUnspentTalents) == "function" then
        local okU, u = pcall(_G.GetNumUnspentTalents)
        if okU and type(u) == "number" then unspent = u end
    end
    return {
        configID = configID,
        configType = config.type,
        spent = spent,
        unspent = unspent,
        totalRanks = total,
        tabs = tabs,
        nodeCount = #nodes,
    }
end

--- Learned spells, grouped by spellbook line. Profession tabs sit past
--- GetNumSpellBookSkillLines, so they are swept separately and marked.
function WarbandNexus:ScanSpellBook()
    local SB = C_SpellBook
    if type(SB) ~= "table" or type(SB.GetSpellBookSkillLineInfo) ~= "function" then return nil end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local SPELL = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
    local FUTURE_SPELL = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) or 2

    local okN, classLines = pcall(SB.GetNumSpellBookSkillLines)
    if not okN or type(classLines) ~= "number" then return nil end

    -- Profession tabs are learnable at any time, so sweep a few indices past the class count
    -- rather than stopping at it; a missing index simply answers nothing.
    local lines, known, future = {}, 0, 0
    for i = 1, math.max(classLines, MAX_PROFESSION_TAB) do
        local okL, info = pcall(SB.GetSpellBookSkillLineInfo, i)
        if okL and type(info) == "table" and info.name then
            local offset = tonumber(info.itemIndexOffset) or 0
            local count = tonumber(info.numSpellBookItems) or 0
            local line = {
                index = i,
                name = tostring(info.name),
                icon = info.iconID,
                isProfession = i > classLines,
                spells = {},
            }
            for slot = offset + 1, math.min(offset + count, MAX_SPELL_SLOTS) do
                local okI, item = pcall(SB.GetSpellBookItemInfo, slot, bank)
                -- FutureSpell is read the same way as Spell on purpose. A level 8 character
                -- returned none, but "none at level 8" is not "never" -- the client may well
                -- start publishing upcoming ranks further along, and a scan that only accepted
                -- Spell would quietly keep ignoring them. Take whatever the API offers and mark
                -- it; the tooltip then shows locked abilities the day they appear, with no code
                -- change. Trainer data fills the gap until (or instead of) that.
                local isSpell = okI and type(item) == "table"
                    and (item.itemType == SPELL or item.itemType == FUTURE_SPELL)
                if isSpell then
                    local level
                    if type(SB.GetSpellBookItemLevelLearned) == "function" then
                        local okV, v = pcall(SB.GetSpellBookItemLevelLearned, slot, bank)
                        if okV and type(v) == "number" then level = v end
                    end
                    local isKnown = (item.itemType == SPELL)
                    line.spells[#line.spells + 1] = {
                        name = tostring(item.name),
                        subName = (item.subName and item.subName ~= "")
                            and tostring(item.subName) or nil,
                        spellID = item.spellID,
                        -- Without this the window drew the red "?" placeholder for every known
                        -- spell: the icon was simply never read off the spellbook item.
                        icon = item.iconID,
                        passive = item.isPassive and true or false,
                        level = level or 0,
                        known = isKnown,
                    }
                    if isKnown then
                        known = known + 1
                    else
                        future = future + 1
                    end
                end
            end
            if #line.spells > 0 then
                -- Highest first: the newest ability is the one a player looks for.
                table.sort(line.spells, function(a, b)
                    if a.level ~= b.level then return a.level > b.level end
                    return a.name < b.name
                end)
                lines[#lines + 1] = line
            end
        end
    end
    if #lines == 0 then return nil end
    return { lines = lines, known = known, future = future, classLineCount = classLines }
end

--[[
    Name the talent tabs.

    Nothing in the talent API names them: subTreeID is nil on every node, GetTreeInfo carries no
    name, the Classic GetTalentTabInfo is absent and GetSpecializationInfo answers nothing. The
    spellbook does hold the three names -- Enhancement, Restoration, Elemental Combat for a Shaman
    -- but in a different order than the tree's posX bands, so pairing them by position would be a
    coin toss.

    The link that does hold: a spec's spellbook line is drawn with one of that spec's own spell
    icons, and the matching talent uses the same icon. Measured on the live client, that named two
    of the three bands outright (Enhancement -> Improved Lightning Shield, Restoration -> Improved
    Healing Wave). The third follows by elimination, which is deduction rather than a guess -- and
    only when exactly one line and one band are left over. Anything less certain stays unnamed.
]]
local function NameTalentTabs(talents, spells)
    if not talents or not talents.tabs or not spells or not spells.lines then return end
    local classLines = tonumber(spells.classLineCount) or 0
    if classLines < 2 then return end

    -- Spec lines only: index 1 is General, and anything past the class count is a profession.
    local specLines = {}
    for i = 1, #spells.lines do
        local line = spells.lines[i]
        if line.index and line.index > 1 and line.index <= classLines and line.icon then
            specLines[#specLines + 1] = { name = line.name, icon = line.icon }
        end
    end
    if #specLines == 0 then return end

    -- Every icon each band draws with.
    local bandIcons = {}
    for t = 1, #talents.tabs do
        local set = {}
        local tab = talents.tabs[t]
        for k = 1, #tab.tierOrder do
            local tier = tab.tiers[tab.tierOrder[k]]
            for n = 1, #tier.nodes do
                if tier.nodes[n].icon then set[tier.nodes[n].icon] = true end
            end
        end
        bandIcons[t] = set
    end

    local takenBand, namedLine = {}, {}
    for i = 1, #specLines do
        local hit, hits = nil, 0
        for t = 1, #talents.tabs do
            if not takenBand[t] and bandIcons[t][specLines[i].icon] then
                hit, hits = t, hits + 1
            end
        end
        if hits == 1 then
            talents.tabs[hit].name = specLines[i].name
            takenBand[hit] = true
            namedLine[i] = true
        end
    end

    -- Exactly one of each left over: the pairing is forced.
    local restLine, restBand, lineCount, bandCount = nil, nil, 0, 0
    for i = 1, #specLines do
        if not namedLine[i] then
            restLine = specLines[i]
            lineCount = lineCount + 1
        end
    end
    for t = 1, #talents.tabs do
        if not takenBand[t] then
            restBand = t
            bandCount = bandCount + 1
        end
    end
    if lineCount == 1 and bandCount == 1 then
        talents.tabs[restBand].name = restLine.name
    end
end

--[[
    Profession recipes.

    The same two halves the Skills column has -- what is known and what is not -- but from the
    trade skill surface rather than a trainer. Measured on the live client with a profession
    window open: GetAllRecipeIDs answered 18 ids for Mining and GetRecipeInfo carried `learned`
    (1 known, 17 not), plus name, icon and categoryID. There is NO skill requirement on a recipe
    (requiredLevel came back nil), so "can learn now" is not answerable from here; that lives on
    the profession trainer and is a separate pass.

    Which profession the open window belongs to comes from GetBaseProfessionInfo: professionID
    186 / "Mining" / skill 23 of 75, which is the same skill line the character row already
    stores. GetTradeSkillLine is absent on this client, so that record is the only key.

    Only readable while the window is open, so this runs from TRADE_SKILL_LIST_UPDATE and merges
    into whatever previous professions were captured.
]]
local MAX_RECIPES = 3000
-- Recipes read per frame. A retail profession lists well over a thousand recipes, each a dozen
-- api calls; read in one frame that froze the client for seconds.
local RECIPE_SCAN_CHUNK = 40
local MAX_CATEGORY_DEPTH = 4
local MAX_REAGENT_SLOTS = 12
-- Retail reagents come in up to three quality tiers per slot; modifying slots list many options.
local MAX_SLOT_ITEMS = 8
local MAX_OUTPUT_QUALITIES = 5

--- Plain string from an api field, or nil when it is missing or secret.
local function SafeString(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

--- Plain number from an api field, or nil when it is missing or secret.
local function SafeNumber(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

--- Why a scan cannot run right now. "foreign" means the open window is not this character's own
--- profession (a linked or guild list, or an NPC crafter) -- retrying cannot fix that. Everything
--- else ("dead", "notReady") is transient.
local function RecipeScanBlocker()
    if type(UnitIsDeadOrGhost) == "function" then
        local okD, dead = pcall(UnitIsDeadOrGhost, "player")
        if okD and dead == true then return "dead" end
    end
    local TS = C_TradeSkillUI
    local function Ask(fn)
        if type(fn) ~= "function" then return false end
        local ok, v = pcall(fn)
        return ok and v == true
    end
    if Ask(TS.IsTradeSkillLinked) or Ask(TS.IsTradeSkillGuild) or Ask(TS.IsNPCCrafting) then
        return "foreign"
    end
    if type(TS.IsTradeSkillReady) == "function" then
        local okR, ready = pcall(TS.IsTradeSkillReady)
        if okR and ready == false then return "notReady" end
    end
    return nil
end

--- Category id -> { name, parent }, walking up to the profession's top header. Names come from the
--- open window only, so they are stored with the recipes for the offline view.
local function ReadRecipeCategories(categoryIDs)
    local out = {}
    if type(C_TradeSkillUI.GetCategoryInfo) ~= "function" then return out end
    for id in pairs(categoryIDs) do
        local cur, depth = id, 0
        while cur and cur > 0 and not out[cur] and depth < MAX_CATEGORY_DEPTH do
            local okC, info = pcall(C_TradeSkillUI.GetCategoryInfo, cur)
            if not okC or type(info) ~= "table" then break end
            local name = SafeString(info.name)
            if not name then break end
            local parent = tonumber(info.parentCategoryID)
            if parent and parent <= 0 then parent = nil end
            local cat = { name = name, parent = parent }
            -- Retail draws a rank bar on expansion headers (Blizzard_ProfessionsRecipeList.lua);
            -- the same fields drive ours, and stay nil where a client has none.
            if info.hasProgressBar then
                cat.rank = tonumber(info.skillLineCurrentLevel)
                cat.rankMax = tonumber(info.skillLineMaxLevel)
                cat.rankStart = tonumber(info.skillLineStartingRank)
            end
            out[cur] = cat
            cur = parent
            depth = depth + 1
        end
    end
    return out
end

--- CraftingQualityInfo atlas for inline text. iconChat is the one Blizzard drops into strings
--- (Professions.GetChatIconMarkupForQuality); iconSmall carries padding and reads tiny inline.
local function QualityAtlas(qi)
    return SafeString(qi.iconChat) or SafeString(qi.iconSmall) or SafeString(qi.icon)
end

--- Reagent quality tier of one item (retail 1-3) and its inline atlas, as the schematic slots draw it.
local function ReadReagentTier(itemID)
    local TS = C_TradeSkillUI
    local tier, atlas
    if type(TS.GetItemReagentQualityByItemInfo) == "function" then
        local ok, q = pcall(TS.GetItemReagentQualityByItemInfo, itemID)
        tier = ok and SafeNumber(q) or nil
    end
    if tier and type(TS.GetItemReagentQualityInfo) == "function" then
        local ok, qi = pcall(TS.GetItemReagentQualityInfo, itemID)
        if ok and type(qi) == "table" then atlas = QualityAtlas(qi) end
    end
    return tier, atlas
end

--- Item ids a slot accepts, in api order (lowest quality tier first for basic slots).
local function SlotItemIDs(slot)
    local list = type(slot.reagents) == "table" and slot.reagents or nil
    if not list then return nil end
    local ids
    for i = 1, math.min(#list, MAX_SLOT_ITEMS) do
        local id = type(list[i]) == "table" and tonumber(list[i].itemID)
        if id then
            ids = ids or {}
            ids[#ids + 1] = id
        end
    end
    return ids
end

--[[
    Reagents and product of one recipe, grouped the way Blizzard_ProfessionsRecipeSchematicForm
    groups slots: Enum.CraftingReagentType Basic -> "Reagents", Modifying -> "Optional Reagents",
    Finishing -> "Finishing Reagents"; Automatic slots are never drawn there and are skipped, as
    are slots flagged hiddenInCraftingForm. A basic slot keeps every quality tier it accepts so the
    have-count covers all of them. nil when the schematic is not readable (gathering recipes).
]]
local function ReadRecipeSchematic(recipeID)
    if type(C_TradeSkillUI.GetRecipeSchematic) ~= "function" then return nil end
    local okS, sc = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not okS or type(sc) ~= "table" then return nil end
    local RT = Enum and Enum.CraftingReagentType
    local BASIC = RT and RT.Basic or 1
    local MODIFYING = RT and RT.Modifying or 0
    local FINISHING = RT and RT.Finishing or 2
    local out = {
        outputItemID = tonumber(sc.outputItemID),
        quantityMin = tonumber(sc.quantityMin),
        quantityMax = tonumber(sc.quantityMax),
        productQuality = SafeNumber(sc.productQuality),
        isRecraft = sc.isRecraft and true or nil,
        hasOperation = sc.hasCraftingOperationInfo and true or nil,
    }
    local slots = sc.reagentSlotSchematics
    if type(slots) ~= "table" then return out end
    for i = 1, math.min(#slots, MAX_REAGENT_SLOTS) do
        local slot = slots[i]
        local ids = type(slot) == "table" and not slot.hiddenInCraftingForm and SlotItemIDs(slot)
        if ids then
            local rtype = tonumber(slot.reagentType)
            local count = tonumber(slot.quantityRequired) or 1
            -- A client without reagentType falls back to `required`, as the old capture did.
            local isBasic = (rtype == BASIC) or (rtype == nil and slot.required ~= false)
            if isBasic then
                local rg = { itemID = ids[1], count = count }
                if #ids > 1 then
                    rg.tiers = {}
                    for t = 1, #ids do
                        local tier, atlas = ReadReagentTier(ids[t])
                        rg.tiers[t] = { itemID = ids[t], tier = tier, atlas = atlas }
                    end
                end
                out.reagents = out.reagents or {}
                out.reagents[#out.reagents + 1] = rg
            elseif rtype == MODIFYING or rtype == FINISHING then
                local info = type(slot.slotInfo) == "table" and slot.slotInfo or nil
                local rank = info and tonumber(info.requiredSkillRank)
                out.optional = out.optional or {}
                out.optional[#out.optional + 1] = {
                    kind = rtype == FINISHING and "finishing" or "modifying",
                    label = info and SafeString(info.slotText) or nil,
                    itemIDs = ids,
                    count = count,
                    required = slot.required and true or nil,
                    rank = (rank and rank > 0) and rank or nil,
                }
            end
        end
    end
    return out
end

--[[
    The product's quality ladder, read the way Blizzard_ProfessionsRecipeCrafterDetails builds its
    "quality bonuses" tooltip: per quality index, GetRecipeItemQualityInfo gives the tier atlas and
    GetRecipeOutputItemData(recipeID, {}, nil, qualityIDs[i]) the item at that quality.
    qualityItemIDs (one item per tier) and qualityIlvlBonuses (one ilvl step per tier) are kept
    as the api gives them.
]]
local function ReadRecipeQualities(recipeID, info)
    local qIDs = type(info.qualityIDs) == "table" and info.qualityIDs or nil
    local itemIDs = type(info.qualityItemIDs) == "table" and info.qualityItemIDs or nil
    local bonuses = type(info.qualityIlvlBonuses) == "table" and info.qualityIlvlBonuses or nil
    local n = math.max(qIDs and #qIDs or 0, itemIDs and #itemIDs or 0, bonuses and #bonuses or 0)
    if n == 0 then return nil end
    local TS = C_TradeSkillUI
    local list = {}
    for idx = 1, math.min(n, MAX_OUTPUT_QUALITIES) do
        local q = {
            qualityID = qIDs and tonumber(qIDs[idx]) or nil,
            itemID = itemIDs and tonumber(itemIDs[idx]) or nil,
            ilvlBonus = bonuses and tonumber(bonuses[idx]) or nil,
        }
        if type(TS.GetRecipeItemQualityInfo) == "function" then
            local ok, qi = pcall(TS.GetRecipeItemQualityInfo, recipeID, idx)
            if ok and type(qi) == "table" then q.atlas = QualityAtlas(qi) end
        end
        if q.qualityID and type(TS.GetRecipeOutputItemData) == "function" then
            local ok, o = pcall(TS.GetRecipeOutputItemData, recipeID, {}, nil, q.qualityID)
            if ok and type(o) == "table" then
                q.link = SafeString(o.hyperlink)
                q.itemID = q.itemID or tonumber(o.itemID)
            end
        end
        list[idx] = q
    end
    return list
end

--[[
    Skill vs difficulty, the expected quality and the concentration cost with no optional
    reagents slotted -- the numbers the retail details panel opens with. Only asked for recipes
    whose schematic says it has operation info (quality crafts).
]]
local function ReadRecipeOperation(recipeID)
    local TS = C_TradeSkillUI
    if type(TS.GetCraftingOperationInfo) ~= "function" then return nil end
    local ok, op = pcall(TS.GetCraftingOperationInfo, recipeID, {}, nil, false)
    if not ok or type(op) ~= "table" then return nil end
    local skill = (SafeNumber(op.baseSkill) or 0) + (SafeNumber(op.bonusSkill) or 0)
    local difficulty = (SafeNumber(op.baseDifficulty) or 0) + (SafeNumber(op.bonusDifficulty) or 0)
    if skill <= 0 and difficulty <= 0 then return nil end
    local conc = SafeNumber(op.concentrationCost)
    return {
        skill = skill,
        difficulty = difficulty,
        quality = SafeNumber(op.craftingQuality),
        concentration = (conc and conc > 0) and conc or nil,
        concentrationCurrencyID = SafeNumber(op.concentrationCurrencyID),
        isQualityCraft = op.isQualityCraft and true or nil,
    }
end

--[[
    The text the retail schematic form shows around the reagents (Blizzard_ProfessionsRecipe
    SchematicForm.lua): the recipe description, the required tools / spell focus ("Requires:
    Anvil"), and for an unlearned recipe where it is taught. All three are only answerable while
    the window is open, so they are captured with the recipe for the offline view. `met` on a
    requirement is live state (am I standing at an anvil) and is deliberately not stored.
]]
local function ReadRecipeExtras(recipeID, learned)
    local TS = C_TradeSkillUI
    local description, source, requires
    if type(TS.GetRecipeDescription) == "function" then
        local ok, d = pcall(TS.GetRecipeDescription, recipeID, {})
        description = ok and SafeString(d) or nil
    end
    if not learned and type(TS.GetRecipeSourceText) == "function" then
        local ok, t = pcall(TS.GetRecipeSourceText, recipeID)
        source = ok and SafeString(t) or nil
    end
    if type(TS.GetRecipeRequirements) == "function" then
        local ok, reqs = pcall(TS.GetRecipeRequirements, recipeID)
        if ok and type(reqs) == "table" then
            for i = 1, math.min(#reqs, 4) do
                local name = type(reqs[i]) == "table" and SafeString(reqs[i].name)
                if name then
                    requires = requires or {}
                    requires[#requires + 1] = name
                end
            end
        end
    end
    return description, source, requires
end

--[[
    Everything else the retail schematic form reads live: the cooldown / charges line
    (GetRecipeCooldown -> cooldown, isDayCooldown, charges, maxCharges), the real product
    (GetRecipeOutputItemData -> CraftingRecipeOutputInfo { icon, hyperlink, itemID }, which also
    covers enchants whose schematic has no outputItemID), the recipe link the list uses for
    shift-click (GetRecipeLink), and for a learned recipe with a higher rank, where that rank is
    taught. A cooldown is stored as an end time so the offline view can count it down.
]]
local function ReadRecipeLive(recipeID, learned, nextRecipeID, now)
    local TS = C_TradeSkillUI
    local out = {}
    if type(TS.GetRecipeCooldown) == "function" then
        local ok, cd, isDay, charges, maxCharges = pcall(TS.GetRecipeCooldown, recipeID)
        if ok then
            cd, charges, maxCharges = tonumber(cd), tonumber(charges), tonumber(maxCharges)
            if cd and cd > 0 then
                out.cooldownEndsAt = now + cd
                out.cooldownIsDay = isDay and true or nil
            end
            if maxCharges and maxCharges > 0 then
                out.charges, out.maxCharges = charges or 0, maxCharges
            end
        end
    end
    if type(TS.GetRecipeOutputItemData) == "function" then
        local ok, info = pcall(TS.GetRecipeOutputItemData, recipeID)
        if ok and type(info) == "table" then
            out.outputLink = SafeString(info.hyperlink)
            out.outputItemID = tonumber(info.itemID)
            out.outputIcon = tonumber(info.icon)
        end
    end
    if type(TS.GetRecipeLink) == "function" then
        local ok, link = pcall(TS.GetRecipeLink, recipeID)
        out.recipeLink = ok and SafeString(link) or nil
    end
    if learned and nextRecipeID and type(TS.GetRecipeSourceText) == "function" then
        local ok, t = pcall(TS.GetRecipeSourceText, nextRecipeID)
        out.nextSource = ok and SafeString(t) or nil
    end
    return out
end

--- Profession tiers (retail expansions: "Classic Mining", "Khaz Algar Mining", ...). Each has its
--- own rank, which the retail rank bar switches between. Empty where a client has no children.
local function ReadProfessionTiers()
    local TS = C_TradeSkillUI
    if type(TS.GetChildProfessionInfos) ~= "function" then return nil end
    local ok, infos = pcall(TS.GetChildProfessionInfos)
    if not ok or type(infos) ~= "table" or #infos == 0 then return nil end
    local tiers = {}
    for i = 1, math.min(#infos, 16) do
        local t = infos[i]
        if type(t) == "table" and tonumber(t.professionID) then
            tiers[#tiers + 1] = {
                professionID = tonumber(t.professionID),
                name = SafeString(t.expansionName) or SafeString(t.professionName),
                skillLevel = tonumber(t.skillLevel) or 0,
                maxSkillLevel = tonumber(t.maxSkillLevel) or 0,
                skillModifier = tonumber(t.skillModifier),
            }
        end
    end
    return #tiers > 0 and tiers or nil
end

--- The expansion tier the window is showing (retail header: "Midnight Alchemy 100 (+40) / 100").
--- GetBaseProfessionInfo answers for the base skill line, whose rank is not what the header draws.
local function ReadActiveTier(baseID)
    local TS = C_TradeSkillUI
    if type(TS.GetChildProfessionInfo) ~= "function" then return nil end
    local ok, t = pcall(TS.GetChildProfessionInfo)
    if not ok or type(t) ~= "table" then return nil end
    local id = tonumber(t.professionID)
    if not id or id <= 0 or id == baseID then return nil end
    local mod = tonumber(t.skillModifier)
    return {
        professionID = id,
        name = SafeString(t.professionName) or SafeString(t.expansionName),
        skillLevel = tonumber(t.skillLevel) or 0,
        maxSkillLevel = tonumber(t.maxSkillLevel) or 0,
        skillModifier = (mod and mod > 0) and mod or nil,
    }
end

--- true -> true, anything else -> nil: flags are stored only when set, to keep the row small.
local function Flag(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v == true or nil
end

--[[
    Merge a fresh read into what was stored, by recipe id.

    A read can come back short without anything having changed: GetRecipeInfo answers nil for a
    recipe whose data is not cached yet, and the list is still filling while the window opens. A
    plain replace turned every such moment into lost recipes. So a recipe the new read could not
    see keeps its stored row, and a field the new read could not fill keeps its stored value.
]]
local MERGE_CARRY = {
    categoryID = true, reagents = true, outputItemID = true, outputLink = true, outputIcon = true,
    quantityMin = true, quantityMax = true, description = true, requires = true, source = true,
    link = true, recipeLink = true, icon = true, order = true, difficulty = true, skillUps = true,
    itemLevel = true, maxQuality = true, supportsQualities = true,
    optional = true, qualities = true, operation = true, productQuality = true,
}

local function MergeRecipeRows(fresh, previous)
    if type(previous) ~= "table" or type(previous.recipes) ~= "table" then return fresh end
    local seen = {}
    for i = 1, #fresh.recipes do seen[fresh.recipes[i].id] = fresh.recipes[i] end
    for i = 1, #previous.recipes do
        local old = previous.recipes[i]
        if type(old) == "table" and old.id then
            local cur = seen[old.id]
            if not cur then
                fresh.recipes[#fresh.recipes + 1] = old
            else
                for k, v in pairs(old) do
                    -- Only what a short read can miss is carried over. State that changes on its
                    -- own (first craft, cooldowns, favourites) must take the fresh read's nil.
                    if cur[k] == nil and MERGE_CARRY[k] and not (k == "source" and cur.learned) then
                        cur[k] = v
                    end
                end
            end
        end
    end
    if type(previous.categories) == "table" then
        fresh.categories = fresh.categories or {}
        for id, c in pairs(previous.categories) do
            if fresh.categories[id] == nil then fresh.categories[id] = c end
        end
    end
    -- A transient 0 (window still coming up) must not overwrite a real rank.
    if (fresh.skillLevel or 0) <= 0 and (tonumber(previous.skillLevel) or 0) > 0 then
        fresh.skillLevel = previous.skillLevel
        fresh.maxSkillLevel = previous.maxSkillLevel
    end
    return fresh
end

--- One recipe's full row, or nil when the api has no name for it yet.
local function ReadRecipeRow(recipeID, i, hits, now)
    local okR, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    local name = okR and type(info) == "table" and SafeString(info.name)
    if not name then return nil end
    local categoryID = tonumber(info.categoryID)
    if not (categoryID and categoryID > 0) then categoryID = nil end
    local sc = ReadRecipeSchematic(recipeID) or {}
    local reagents, outputItemID = sc.reagents, sc.outputItemID
    local qualities = ReadRecipeQualities(recipeID, info)
    local operation = sc.hasOperation and ReadRecipeOperation(recipeID) or nil
    local learned = info.learned and true or false
    local description, source, requires = ReadRecipeExtras(recipeID, learned)
    local nextRecipeID = tonumber(info.nextRecipeID)
    local live = ReadRecipeLive(recipeID, learned, nextRecipeID, now)
    if categoryID then hits.category = hits.category + 1 end
    if reagents then hits.reagents = hits.reagents + 1 end
    if reagents and reagents[1] and reagents[1].tiers then hits.tiers = hits.tiers + 1 end
    if sc.optional then hits.optional = hits.optional + 1 end
    if qualities then hits.qualities = hits.qualities + 1 end
    if operation then hits.operation = hits.operation + 1 end
    if description then hits.description = hits.description + 1 end
    if source then hits.source = hits.source + 1 end
    if requires then hits.requires = hits.requires + 1 end
    if live.outputItemID or outputItemID then hits.output = hits.output + 1 end
    if live.cooldownEndsAt or live.maxCharges then hits.cooldown = hits.cooldown + 1 end
    if live.recipeLink or SafeString(info.hyperlink) then hits.link = hits.link + 1 end
    if not learned then hits.unlearned = hits.unlearned + 1 end
    return {
        id = recipeID,
        -- The api's own list order is the order the profession window draws them in.
        order = i,
        name = name,
        icon = info.icon,
        learned = learned,
        categoryID = categoryID,
        -- Enum.TradeskillRelativeDifficulty: 0 optimal, 1 medium, 2 easy, 3 trivial.
        difficulty = tonumber(info.relativeDifficulty),
        skillUps = tonumber(info.numSkillUps),
        canSkillUp = info.canSkillUp and true or false,
        link = SafeString(info.hyperlink) or live.recipeLink,
        reagents = reagents,
        outputItemID = live.outputItemID or outputItemID,
        outputLink = live.outputLink,
        outputIcon = live.outputIcon,
        quantityMin = sc.quantityMin,
        quantityMax = sc.quantityMax,
        optional = sc.optional,
        productQuality = sc.productQuality,
        isRecraft = sc.isRecraft,
        qualities = qualities,
        operation = operation,
        alwaysLowestQuality = Flag(info.alwaysUsesLowestQuality),
        description = description,
        source = source,
        requires = requires,
        nextSource = live.nextSource,
        cooldownEndsAt = live.cooldownEndsAt,
        cooldownIsDay = live.cooldownIsDay,
        charges = live.charges,
        maxCharges = live.maxCharges,
        -- TradeSkillRecipeInfo fields the retail list / schematic form draw.
        itemLevel = (tonumber(info.itemLevel) or 0) > 0 and tonumber(info.itemLevel) or nil,
        maxTrivialLevel = tonumber(info.maxTrivialLevel),
        firstCraft = Flag(info.firstCraft),
        favorite = Flag(info.favorite),
        disabled = Flag(info.disabled),
        disabledReason = SafeString(info.disabledReason),
        nextRecipeID = nextRecipeID,
        previousRecipeID = tonumber(info.previousRecipeID),
        unlockedRecipeLevel = tonumber(info.unlockedRecipeLevel),
        currentRecipeExperience = tonumber(info.currentRecipeExperience),
        nextLevelRecipeExperience = tonumber(info.nextLevelRecipeExperience),
        supportsQualities = Flag(info.supportsQualities),
        maxQuality = tonumber(info.maxQuality),
        isGathering = Flag(info.isGatheringRecipe),
        isEnchanting = Flag(info.isEnchantingRecipe),
        isSalvage = Flag(info.isSalvageRecipe),
        sourceType = tonumber(info.sourceType),
    }
end

local FinishRecipeScan  -- forward declare: the chunk driver ends there

local recipeScanGen = 0

--[[
    Returns entry, or nil plus a reason ("dead", "foreign", "notReady", "empty", "noRow").
    With onDone and C_Timer, the read is spread over frames (RECIPE_SCAN_CHUNK recipes each),
    the call returns nil, "pending", and onDone(entry, reason) runs when it settles. A newer scan,
    a closed window or another profession taking the window abandons the one in flight.
]]
function WarbandNexus:ScanProfessionRecipes(onDone)
    if type(C_TradeSkillUI) ~= "table" then return nil, "noApi" end
    if type(C_TradeSkillUI.GetBaseProfessionInfo) ~= "function" then return nil, "noApi" end
    local blocker = RecipeScanBlocker()
    if blocker then return nil, blocker end
    local okBase, base = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not okBase or type(base) ~= "table" then return nil, "notReady" end
    -- `not base.professionID` was not enough: the id is 0 while the window is still coming up,
    -- and 0 is TRUE in Lua. That stored a nameless entry under key 0 carrying whichever recipe
    -- list happened to be loaded -- and the profession it really belonged to never got one.
    local professionID = tonumber(base.professionID)
    local professionName = SafeString(base.professionName)
    if not professionID or professionID <= 0 then return nil, "notReady" end
    if not professionName then return nil, "notReady" end
    if type(C_TradeSkillUI.GetAllRecipeIDs) ~= "function" then return nil, "noApi" end
    local okIDs, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIDs or type(ids) ~= "table" or #ids == 0 then return nil, "empty" end

    local now = time()
    local entry = {
        professionID = professionID,
        name = professionName,
        skillLevel = tonumber(base.skillLevel) or 0,
        maxSkillLevel = tonumber(base.maxSkillLevel) or 0,
        -- Racial / gear bonus the retail rank bar shows as "(+15)".
        skillModifier = (tonumber(base.skillModifier) or 0) > 0 and tonumber(base.skillModifier) or nil,
        expansionName = SafeString(base.expansionName),
        tiers = ReadProfessionTiers(),
        activeTier = ReadActiveTier(professionID),
        scannedAt = now,
        recipes = {},
    }
    -- How many recipes each api answered for. Zero on a client means that api is empty there,
    -- which is the difference between "nothing to show" and "we never asked".
    local hits = {
        category = 0, reagents = 0, description = 0, source = 0, requires = 0, output = 0,
        cooldown = 0, link = 0, unlearned = 0, tiers = 0, optional = 0, qualities = 0, operation = 0,
    }
    entry.apiHits = hits
    local categoryIDs = {}
    local categoryIDs = {}
    local total = math.min(#ids, MAX_RECIPES)
    local async = type(onDone) == "function" and C_Timer and C_Timer.After
    recipeScanGen = recipeScanGen + 1
    local gen = recipeScanGen
    local addon = self
    local nextIndex = 1
    local function step()
        if gen ~= recipeScanGen then return end
        if async and nextIndex > 1 then
            -- Between frames the window can close or switch profession; stop rather than mix lists.
            local blocker = RecipeScanBlocker()
            if blocker then return onDone(nil, blocker) end
            local okB, nowBase = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if not okB or type(nowBase) ~= "table" or tonumber(nowBase.professionID) ~= professionID then
                return onDone(nil, "notReady")
            end
        end
        local last = async and math.min(total, nextIndex + RECIPE_SCAN_CHUNK - 1) or total
        for i = nextIndex, last do
            local r = ReadRecipeRow(ids[i], i, hits, now)
            if r then
                if r.categoryID then categoryIDs[r.categoryID] = true end
                entry.recipes[#entry.recipes + 1] = r
            end
        end
        nextIndex = last + 1
        if nextIndex <= total then
            C_Timer.After(0, step)
            return
        end
        local e, reason = FinishRecipeScan(addon, entry, categoryIDs, professionID)
        if async then return onDone(e, reason) end
        return e, reason
    end
    if async then
        step()
        return nil, "pending"
    end
    return step()
end

function FinishRecipeScan(self, entry, categoryIDs, professionID)
    if #entry.recipes == 0 then return nil, "empty" end
    entry.categories = ReadRecipeCategories(categoryIDs)

    if not self.db or not self.db.global then return nil, "noRow" end
    local key = ns.Utilities and ns.Utilities:GetCharacterStorageKey(self)
    local row = key and self.db.global.characters and self.db.global.characters[key]
    if not row then return nil, "noRow" end
    row.systems = row.systems or { version = SYSTEMS_SCAN_VERSION, scannedAt = time() }
    row.systems.recipes = row.systems.recipes or {}
    -- Sweep out anything an earlier build filed under a non-id: those rows can never be looked
    -- up, and they take the place of the profession whose window was actually open.
    for pid in pairs(row.systems.recipes) do
        if type(pid) ~= "number" or pid <= 0 then row.systems.recipes[pid] = nil end
    end
    entry = MergeRecipeRows(entry, row.systems.recipes[professionID])

    local known = 0
    for i = 1, #entry.recipes do
        if entry.recipes[i].learned then known = known + 1 end
    end
    entry.known = known
    -- Known first, then by name: a player scanning the window looks for what is missing, and an
    -- alphabetical block of each is easier to read than the api's own order.
    table.sort(entry.recipes, function(a, b)
        if a.learned ~= b.learned then return a.learned end
        return a.name < b.name
    end)

    row.systems.recipes[professionID] = entry
    self:SendMessage(MSG_SYSTEMS_UPDATED, { charKey = key, professionID = entry.professionID })
    return entry
end

--[[
    Every saved character that has learned recipeID, read from the recipe captures above (all
    expansion tiers, both clients). The older ProfessionService summary (GetCraftersForRecipe) only
    keeps Midnight tiers, so it is merged in as a fallback for characters with no capture yet.
    @return { { charKey, charName, classFile } } sorted by name
]]
function WarbandNexus:GetRecipeKnownBy(recipeID)
    local out = {}
    local chars = recipeID and self.db and self.db.global and self.db.global.characters
    if type(chars) ~= "table" then return out end
    local seen = {}
    for charKey, row in pairs(chars) do
        local all = type(row) == "table" and type(row.systems) == "table" and row.systems.recipes
        if type(all) == "table" then
            for _, entry in pairs(all) do
                local list = type(entry) == "table" and entry.recipes
                if type(list) == "table" then
                    for i = 1, #list do
                        local r = list[i]
                        if r.id == recipeID then
                            if r.learned and not seen[charKey] then
                                seen[charKey] = true
                                out[#out + 1] = {
                                    charKey = charKey,
                                    charName = ns.CharDisplayName and ns.CharDisplayName(row, charKey) or charKey,
                                    classFile = row.classFile or row.class,
                                }
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    if self.GetCraftersForRecipe then
        local ok, legacy = pcall(self.GetCraftersForRecipe, self, recipeID)
        if ok and type(legacy) == "table" then
            for i = 1, #legacy do
                local c = legacy[i]
                if c.charKey and not seen[c.charKey] then
                    seen[c.charKey] = true
                    out[#out + 1] = { charKey = c.charKey, charName = c.charName, classFile = c.classFile }
                end
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.charName) < tostring(b.charName) end)
    return out
end

--- Recipes captured for one profession of one character; nil until its window has been opened.
function WarbandNexus:GetProfessionRecipes(charKey, professionID)
    -- Read past the version gate on purpose: recipes have one shape and survive a scan-version
    -- bump (see ScanCharacterSystems), but GetCharacterSystems hides the whole table until the
    -- character logs in again -- which left an offline alt's recipes unreachable.
    if not professionID or not self.db or not self.db.global then return nil end
    local chars = self.db.global.characters
    local row = charKey and chars and chars[charKey]
    local all = row and type(row.systems) == "table" and row.systems.recipes
    local entry = type(all) == "table" and all[professionID] or nil
    if type(entry) ~= "table" or type(entry.recipes) ~= "table" or #entry.recipes == 0 then return nil end
    return entry
end

--- Scan both systems for the current character and persist them on its row.
function WarbandNexus:ScanCharacterSystems()
    if not self.db or not self.db.global then return nil end
    local key = ns.Utilities and ns.Utilities:GetCharacterStorageKey(self)
    if not key then return nil end
    local chars = self.db.global.characters
    local row = chars and chars[key]
    if not row then return nil end

    local previous = row.systems
    local carry = (type(previous) == "table")
        and (tonumber(previous.version) or 0) >= SYSTEMS_SCAN_VERSION

    -- Dead or a ghost: the spellbook and trait APIs answer short or nil, and a ghost's spellbook
    -- is not the character's. Nothing read now is trustworthy, so the stored halves stay as they
    -- are and the next save after resurrection reads them again.
    local dead = false
    if type(UnitIsDeadOrGhost) == "function" then
        local okD, d = pcall(UnitIsDeadOrGhost, "player")
        dead = okD and d == true
    end
    local talents, spells
    if not dead then
        talents = self:ScanTalentTree()
        spells = self:ScanSpellBook()
        -- A tree read short (some nodes not answering yet) is a partial read, not a smaller tree:
        -- a class tree never loses nodes, so the fuller stored copy wins.
        local prevTalents = carry and previous.talents
        if talents and type(prevTalents) == "table"
            and (tonumber(prevTalents.nodeCount) or 0) > (tonumber(talents.nodeCount) or 0) then
            talents = nil
        end
        -- Needs both halves: the names come from the spellbook, the bands from the tree.
        NameTalentTabs(talents, spells)
    end
    --[[
        Merged, never replaced.

        A scan can come back empty for reasons that have nothing to do with the character: the
        API is quiet while dead, and the spellbook and trait tables are not populated the instant
        a reload finishes. Assigning a fresh table turned every one of those moments into data
        loss -- the talents a character had were replaced with nil, and the recipe cache, which
        costs a trip to each profession window to rebuild, was dropped on every character save
        because the new table simply had no `recipes` field.

        So an empty half leaves the stored half alone, and recipes always carry over. Previous
        talents/spells are only carried forward when they were written by THIS scan version;
        older ones are let go rather than drawn with rules that have since changed.
    ]]
    local systems = {
        version = SYSTEMS_SCAN_VERSION,
        scannedAt = time(),
        talents = talents or (carry and previous.talents) or nil,
        spells = spells or (carry and previous.spells) or nil,
        -- Recipes are keyed by profession id and have only ever had one shape, so they survive a
        -- version bump: losing them would send the player back to every profession window.
        recipes = (type(previous) == "table") and previous.recipes or nil,
    }
    row.systems = systems
    self:SendMessage(MSG_SYSTEMS_UPDATED, { charKey = key })
    return systems
end

--- Read-only accessor for the UI; nil when that character was never scanned, or was scanned by
--- a build whose data shape has since changed.
function WarbandNexus:GetCharacterSystems(charKey)
    if not self.db or not self.db.global then return nil end
    local chars = self.db.global.characters
    local row = charKey and chars and chars[charKey]
    local systems = row and row.systems
    if not systems then return nil end
    if (tonumber(systems.version) or 0) < SYSTEMS_SCAN_VERSION then return nil end
    return systems
end
