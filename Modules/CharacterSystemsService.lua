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
local MAX_RECIPES = 600
function WarbandNexus:ScanProfessionRecipes()
    if type(C_TradeSkillUI) ~= "table" then return nil end
    if type(C_TradeSkillUI.GetBaseProfessionInfo) ~= "function" then return nil end
    local okBase, base = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not okBase or type(base) ~= "table" then return nil end
    -- `not base.professionID` was not enough: the id is 0 while the window is still coming up,
    -- and 0 is TRUE in Lua. That stored a nameless entry under key 0 carrying whichever recipe
    -- list happened to be loaded -- and the profession it really belonged to never got one.
    local professionID = tonumber(base.professionID)
    local professionName = base.professionName
    if not professionID or professionID <= 0 then return nil end
    if type(professionName) ~= "string" or professionName == "" then return nil end
    if type(C_TradeSkillUI.GetAllRecipeIDs) ~= "function" then return nil end
    local okIDs, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIDs or type(ids) ~= "table" or #ids == 0 then return nil end

    local entry = {
        professionID = professionID,
        name = tostring(professionName),
        skillLevel = tonumber(base.skillLevel) or 0,
        maxSkillLevel = tonumber(base.maxSkillLevel) or 0,
        scannedAt = time(),
        recipes = {},
    }
    local known = 0
    for i = 1, math.min(#ids, MAX_RECIPES) do
        local okR, info = pcall(C_TradeSkillUI.GetRecipeInfo, ids[i])
        if okR and type(info) == "table" and info.name then
            local learned = info.learned and true or false
            if learned then known = known + 1 end
            entry.recipes[#entry.recipes + 1] = {
                id = ids[i],
                name = tostring(info.name),
                icon = info.icon,
                learned = learned,
            }
        end
    end
    if #entry.recipes == 0 then return nil end
    entry.known = known
    -- Known first, then by name: a player scanning the window looks for what is missing, and an
    -- alphabetical block of each is easier to read than the api's own order.
    table.sort(entry.recipes, function(a, b)
        if a.learned ~= b.learned then return a.learned end
        return a.name < b.name
    end)

    if not self.db or not self.db.global then return nil end
    local key = ns.Utilities and ns.Utilities:GetCharacterStorageKey(self)
    local row = key and self.db.global.characters and self.db.global.characters[key]
    if not row then return nil end
    row.systems = row.systems or { version = SYSTEMS_SCAN_VERSION, scannedAt = time() }
    row.systems.recipes = row.systems.recipes or {}
    -- Sweep out anything an earlier build filed under a non-id: those rows can never be looked
    -- up, and they take the place of the profession whose window was actually open.
    for pid in pairs(row.systems.recipes) do
        if type(pid) ~= "number" or pid <= 0 then row.systems.recipes[pid] = nil end
    end
    row.systems.recipes[professionID] = entry
    self:SendMessage(MSG_SYSTEMS_UPDATED, { charKey = key, professionID = entry.professionID })
    return entry
end

--- Recipes captured for one profession of one character; nil until its window has been opened.
function WarbandNexus:GetProfessionRecipes(charKey, professionID)
    local systems = self:GetCharacterSystems(charKey)
    local all = systems and systems.recipes
    return all and professionID and all[professionID] or nil
end

--- Scan both systems for the current character and persist them on its row.
function WarbandNexus:ScanCharacterSystems()
    if not self.db or not self.db.global then return nil end
    local key = ns.Utilities and ns.Utilities:GetCharacterStorageKey(self)
    if not key then return nil end
    local chars = self.db.global.characters
    local row = chars and chars[key]
    if not row then return nil end

    local talents = self:ScanTalentTree()
    local spells = self:ScanSpellBook()
    -- Needs both halves: the names come from the spellbook, the bands from the tree.
    NameTalentTabs(talents, spells)
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
    local previous = row.systems
    local carry = (type(previous) == "table")
        and (tonumber(previous.version) or 0) >= SYSTEMS_SCAN_VERSION
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
