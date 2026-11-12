--[[
    Warband Nexus - character systems probe (`/wn charprobe`).

    Five questions the Character tab needs answered before a single column is drawn, and none of
    them can be settled from a wiki page -- Forever is a game type inside the Mainline build, so a
    namespace existing proves nothing (C_WeeklyRewards and C_MythicPlus are both present here and
    both empty). Only returned data counts.

      1. Spellbook: does the Mainline C_SpellBook surface list FUTURE spells (the ones not yet
         learned) alongside learned ones, and does GetSpellBookItemLevelLearned report their
         level? The wiki documents only the "returns 0 for non-Spell items" case and says nothing
         about FutureSpell, so this has to be measured.
      2. Skill lines: GetNumSkillLines / GetSkillLineInfo were removed from Mainline in 4.0.1.
         Forever is vanilla-plus, so weapon skills / defense / languages may be back. Ask.
      3. Professions: GetProfessions lost its firstAid return in 8.0.1. Forever has First Aid, so
         either that sixth return is back or first aid is an ordinary spellbook skill line.
         Capture every return position, not the five the wiki names.
      4. Talents: Enum.TraitConfigType carries a value named CamelotCombat (Camelot == Forever),
         which says Forever's talents run on the Traits system under its own config type rather
         than the Classic GetTalentInfo API. Verify by reading the active config, and probe the
         Classic globals in the same pass so the answer is measured, not inferred from an enum.
      5. Crafting: what the trade-skill surface reports while no profession window is open, which
         is what the craft companion has to survive.

    Bounded and pcall-guarded throughout; writes to db.global.charProbe, dropped on the next load
    like the other diagnostics. Nothing on the login path calls this.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local MAX_SPELLBOOK_ITEMS = 1200
local MAX_TALENT_NODES = 400
local MAX_SKILL_ROWS = 60

--- pcall a call and record either its values or why it failed, so "absent", "errored" and
--- "returned nil" stay three different answers in the dump instead of collapsing into one.
local function Probe(out, label, fn, ...)
    if type(fn) ~= "function" then
        out[label] = "ABSENT"
        return
    end
    local packed = { pcall(fn, ...) }
    if not packed[1] then
        out[label] = "ERROR: " .. tostring(packed[2])
        return
    end
    if packed[2] == nil and #packed == 2 then
        out[label] = "nil"
        return
    end
    local parts = {}
    for i = 2, #packed do
        local v = packed[i]
        parts[#parts + 1] = (type(v) == "table") and ("table(" .. #v .. ")") or tostring(v)
    end
    out[label] = table.concat(parts, " | ")
end

local SPELL_ITEM_TYPE_NAMES = {
    [0] = "None", [1] = "Spell", [2] = "FutureSpell", [3] = "PetAction", [4] = "Flyout",
}

--- Walk every spellbook skill line and record each slot as the UI would read it. The level column
--- is the whole point: it is what a "locked until level N" tooltip row needs.
local function ProbeSpellBook()
    local out = { lines = {}, items = {}, counts = {}, truncated = false }
    local SB = C_SpellBook
    if type(SB) ~= "table" or type(SB.GetNumSpellBookSkillLines) ~= "function" then
        out.available = false
        return out
    end
    out.available = true
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    out.playerBank = bank
    local okN, numLines = pcall(SB.GetNumSpellBookSkillLines)
    if not okN or type(numLines) ~= "number" then
        out.numLines = "ERROR"
        return out
    end
    out.numLines = numLines
    local seen = 0
    for i = 1, numLines do
        local okL, info = pcall(SB.GetSpellBookSkillLineInfo, i)
        if okL and type(info) == "table" then
            out.lines[#out.lines + 1] = {
                index = i,
                name = tostring(info.name),
                offset = info.itemIndexOffset,
                count = info.numSpellBookItems,
                isGuild = info.isGuild and true or false,
                shouldHide = info.shouldHide and true or false,
                specID = info.specID,
                offSpecID = info.offSpecID,
            }
            local offset = tonumber(info.itemIndexOffset) or 0
            local count = tonumber(info.numSpellBookItems) or 0
            for slot = offset + 1, offset + count do
                if seen >= MAX_SPELLBOOK_ITEMS then
                    out.truncated = true
                    break
                end
                local okI, item = pcall(SB.GetSpellBookItemInfo, slot, bank)
                if okI and type(item) == "table" then
                    local typeName = SPELL_ITEM_TYPE_NAMES[item.itemType] or tostring(item.itemType)
                    out.counts[typeName] = (out.counts[typeName] or 0) + 1
                    local level
                    if type(SB.GetSpellBookItemLevelLearned) == "function" then
                        local okV, v = pcall(SB.GetSpellBookItemLevelLearned, slot, bank)
                        level = okV and v or "ERROR"
                    end
                    out.items[#out.items + 1] = {
                        slot = slot,
                        line = i,
                        lineName = tostring(info.name),
                        name = tostring(item.name),
                        subName = (item.subName and item.subName ~= "") and tostring(item.subName) or nil,
                        type = typeName,
                        spellID = item.spellID,
                        actionID = item.actionID,
                        isPassive = item.isPassive and true or false,
                        isOffSpec = item.isOffSpec and true or false,
                        levelLearned = level,
                    }
                    seen = seen + 1
                end
            end
        end
        if out.truncated then break end
    end
    return out
end

--[[
    Wide spellbook sweep.

    The first pass walked only the slots each skill line declares and found 15 items, every one of
    them type Spell -- not a single FutureSpell on a level 8 character who plainly has spells still
    to learn. Two things could explain that, and they lead to opposite conclusions:

      a) Forever simply does not publish unlearned spells, in which case a "locked skills" tooltip
         cannot be built from the client at all.
      b) The future entries sit outside the offset/numSpellBookItems ranges. The wiki warns that a
         tab may use more slot indices than its count suggests, so this is not far-fetched.

    So scan a flat slot range in both banks, ignoring the line offsets entirely, and record
    anything that is not an ordinary learned spell. A level 8 character bounds how far this has to
    reach; 300 is far past the last declared slot (15).
]]
local MAX_WIDE_SLOT = 300
local function ProbeSpellBookWide()
    local out = { counts = {}, notable = {}, maxSlotSeen = 0 }
    local SB = C_SpellBook
    if type(SB) ~= "table" or type(SB.GetSpellBookItemInfo) ~= "function" then
        out.available = false
        return out
    end
    out.available = true
    local banks = {}
    if Enum and Enum.SpellBookSpellBank then
        banks[#banks + 1] = { name = "Player", id = Enum.SpellBookSpellBank.Player }
        banks[#banks + 1] = { name = "Pet", id = Enum.SpellBookSpellBank.Pet }
    else
        banks[#banks + 1] = { name = "Player", id = 0 }
    end
    for b = 1, #banks do
        local bank = banks[b]
        for slot = 1, MAX_WIDE_SLOT do
            local ok, item = pcall(SB.GetSpellBookItemInfo, slot, bank.id)
            if ok and type(item) == "table" and item.itemType ~= nil then
                local typeName = SPELL_ITEM_TYPE_NAMES[item.itemType] or tostring(item.itemType)
                local key = bank.name .. ":" .. typeName
                out.counts[key] = (out.counts[key] or 0) + 1
                if slot > out.maxSlotSeen then out.maxSlotSeen = slot end
                -- Learned player spells are already in the first pass; record only the rest.
                if typeName ~= "Spell" or bank.name ~= "Player" then
                    local level
                    if type(SB.GetSpellBookItemLevelLearned) == "function" then
                        local okV, v = pcall(SB.GetSpellBookItemLevelLearned, slot, bank.id)
                        level = okV and v or "ERROR"
                    end
                    out.notable[#out.notable + 1] = {
                        bank = bank.name,
                        slot = slot,
                        name = tostring(item.name),
                        type = typeName,
                        spellID = item.spellID,
                        levelLearned = level,
                    }
                end
            end
        end
    end
    return out
end

--[[
    Profession spellbook tabs.

    GetProfessions answered with tab indices 5, 6 and 7 while GetNumSpellBookSkillLines reported
    only 4 lines -- so either profession tabs live past the counted range, or the two APIs index
    different lists. The wiki says a GetProfessions index is valid for GetSpellBookSkillLineInfo,
    which cannot both be true here. Ask for a few indices past the declared count and see.
]]
local function ProbeSpellBookTabs()
    local out = {}
    local SB = C_SpellBook
    if type(SB) ~= "table" or type(SB.GetSpellBookSkillLineInfo) ~= "function" then
        out.available = false
        return out
    end
    out.available = true
    for i = 1, 12 do
        local ok, info = pcall(SB.GetSpellBookSkillLineInfo, i)
        if not ok then
            out[i] = "ERROR"
        elseif type(info) ~= "table" then
            out[i] = tostring(info)
        else
            out[i] = string.format("%s offset=%s count=%s hide=%s",
                tostring(info.name), tostring(info.itemIndexOffset),
                tostring(info.numSpellBookItems), tostring(info.shouldHide))
        end
    end
    return out
end

--[[
    Talent tab names.

    The tree splits into three clean posX bands, which are plainly Elemental / Enhancement /
    Restoration -- but nothing read so far NAMES them: subTreeID came back nil on all 50 nodes,
    GetTreeInfo carries no name, and the Classic GetTalentTabInfo is absent. The spellbook does
    hold the three names, but in a different order than the bands, so pairing them by position
    would be a guess.

    Forever's own talent frame shows names from somewhere, so the candidates left are swept here:
    the specialization API (GetNumSpecializations answered 1, which is odd for a client with no
    specs), the spellbook skill lines in full (specID / offSpecID were nil in the summary, but the
    whole record has not been looked at), and the trait sub-tree accessors.

    If every one of these answers nothing, then the client genuinely does not publish tab names
    and the UI keeps ordering them left to right without labels.
]]
local function ProbeTalentNames()
    local out = { specs = {}, spellLines = {}, trees = {} }
    Probe(out, "GetNumSpecializations", _G.GetNumSpecializations)
    Probe(out, "GetSpecialization", _G.GetSpecialization)
    for i = 1, 5 do
        local packed = { pcall(_G.GetSpecializationInfo, i) }
        if packed[1] and packed[2] ~= nil then
            local parts = {}
            for k = 2, math.min(#packed, 8) do parts[#parts + 1] = tostring(packed[k]) end
            out.specs[i] = table.concat(parts, " | ")
        end
    end

    -- Whole skill line records, not just the fields the first sweep printed.
    if type(C_SpellBook) == "table" and type(C_SpellBook.GetSpellBookSkillLineInfo) == "function" then
        for i = 1, 12 do
            local ok, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
            if ok and type(info) == "table" then
                local parts = {}
                for k, v in pairs(info) do
                    if type(k) == "string" then parts[#parts + 1] = k .. "=" .. tostring(v) end
                end
                table.sort(parts)
                out.spellLines[i] = table.concat(parts, ", ")
            end
        end
    end

    -- Every field of the tree record, and whatever the sub-tree accessors say.
    if type(C_Traits) == "table" and type(C_ClassTalents) == "table" then
        local okID, configID = pcall(C_ClassTalents.GetActiveConfigID)
        if okID and type(configID) == "number" then
            local okC, config = pcall(C_Traits.GetConfigInfo, configID)
            if okC and type(config) == "table" and type(config.treeIDs) == "table" then
                for t = 1, #config.treeIDs do
                    local treeID = config.treeIDs[t]
                    local row = { treeID = treeID }
                    local okT, tree = pcall(C_Traits.GetTreeInfo, configID, treeID)
                    if okT and type(tree) == "table" then
                        local parts = {}
                        for k, v in pairs(tree) do
                            if type(k) == "string" then
                                parts[#parts + 1] = k .. "=" .. tostring(v)
                            end
                        end
                        table.sort(parts)
                        row.info = table.concat(parts, ", ")
                    end
                    Probe(row, "GetSubTreeInfo_1", C_Traits.GetSubTreeInfo, configID, 1)
                    Probe(row, "GetTreeCurrencyInfo", C_Traits.GetTreeCurrencyInfo,
                        configID, treeID, false)
                    out.trees[#out.trees + 1] = row
                end
            end
        end
    end
    return out
end

--- The Classic skill window. Removed from Mainline in 4.0.1; if it answers here, Forever brought
--- weapon skills / defense / languages back and the Character tab has a second surface to read.
local function ProbeSkillLines()
    local out = { rows = {} }
    Probe(out, "GetNumSkillLines", _G.GetNumSkillLines)
    Probe(out, "GetSkillLineInfo_1", _G.GetSkillLineInfo, 1)
    Probe(out, "ExpandSkillHeader", _G.ExpandSkillHeader)
    if type(_G.GetNumSkillLines) ~= "function" or type(_G.GetSkillLineInfo) ~= "function" then
        return out
    end
    local okN, num = pcall(_G.GetNumSkillLines)
    if not okN or type(num) ~= "number" then return out end
    out.count = num
    for i = 1, math.min(num, MAX_SKILL_ROWS) do
        local ok, name, header, isExpanded, rank, tempPoints, modifier, maxRank,
            isAbandonable, stepCost, rankCost, minLevel, costType, desc =
            pcall(_G.GetSkillLineInfo, i)
        if ok then
            out.rows[#out.rows + 1] = {
                index = i,
                name = tostring(name),
                header = header and true or false,
                expanded = isExpanded and true or false,
                rank = rank,
                maxRank = maxRank,
                modifier = modifier,
                tempPoints = tempPoints,
                abandonable = isAbandonable and true or false,
                stepCost = stepCost,
                rankCost = rankCost,
                minLevel = minLevel,
                costType = costType,
                description = desc and tostring(desc) or nil,
            }
        end
    end
    return out
end

--- Professions. GetProfessions is documented as five returns on Mainline; capture six so a
--- restored firstAid slot shows up instead of being silently dropped.
local PROFESSION_RETURN_LABELS = { "prof1", "prof2", "archaeology", "fishing", "cooking", "sixth" }

local function ProbeTradeSkillLines(out)
    if type(C_TradeSkillUI) ~= "table" then return end
    local t = {}
    Probe(t, "GetAllProfessionTradeSkillLines", C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    Probe(t, "GetChildProfessionInfos", C_TradeSkillUI.GetChildProfessionInfos)
    Probe(t, "GetBaseProfessionInfo", C_TradeSkillUI.GetBaseProfessionInfo)
    Probe(t, "GetProfessionInfoBySkillLineID_171", C_TradeSkillUI.GetProfessionInfoBySkillLineID, 171)
    Probe(t, "IsTradeSkillReady", C_TradeSkillUI.IsTradeSkillReady)
    -- Every trade skill line this client knows, resolved to names: the only way to tell which
    -- professions exist here at all without learning each one.
    if type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) == "function"
        and type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) == "function" then
        local okA, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
        if okA and type(lines) == "table" then
            local named = {}
            for k = 1, #lines do
                local id = lines[k]
                local okB, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
                local isTable = okB and type(info) == "table"
                named[#named + 1] = {
                    skillLineID = id,
                    name = isTable and tostring(info.professionName) or nil,
                    parent = isTable and info.parentProfessionID or nil,
                    maxLevel = isTable and info.maxSkillLevel or nil,
                }
            end
            t.allLines = named
        end
    end
    out.tradeSkillUI = t
end

local function ProbeProfessions()
    local out = { returns = {}, info = {} }
    if type(_G.GetProfessions) ~= "function" then
        out.available = false
        return out
    end
    out.available = true
    local packed = { pcall(_G.GetProfessions) }
    if not packed[1] then
        out.error = tostring(packed[2])
        return out
    end
    out.returnCount = #packed - 1
    for i = 2, #packed do
        local label = PROFESSION_RETURN_LABELS[i - 1] or ("slot" .. (i - 1))
        local index = packed[i]
        out.returns[label] = index
        if type(index) == "number" and type(_G.GetProfessionInfo) == "function" then
            local okI, name, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset,
                skillLine, skillModifier, specIndex, specOffset, skillLineName =
                pcall(_G.GetProfessionInfo, index)
            if okI then
                out.info[label] = {
                    tabIndex = index,
                    name = tostring(name),
                    icon = icon,
                    skillLevel = skillLevel,
                    maxSkillLevel = maxSkillLevel,
                    numAbilities = numAbilities,
                    spellOffset = spellOffset,
                    skillLine = skillLine,
                    skillModifier = skillModifier,
                    specializationIndex = specIndex,
                    specializationOffset = specOffset,
                    skillLineName = skillLineName and tostring(skillLineName) or nil,
                }
            end
        end
    end
    Probe(out, "GetNumPrimaryProfessions", _G.GetNumPrimaryProfessions)
    Probe(out, "GetProfessionSkillLineID_1", _G.GetProfessionSkillLineID, 1)
    ProbeTradeSkillLines(out)
    return out
end

--- Resolve one trait node's first entry down to a spell name: a node id alone says nothing a
--- tooltip could show, so the probe has to prove the whole chain works, not just its first link.
local function DescribeTraitEntry(configID, entryID, row)
    local okE, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if not okE or type(entry) ~= "table" then return end
    row.entryType = entry.type
    row.entryMaxRanks = entry.maxRanks
    row.definitionID = entry.definitionID
    if not entry.definitionID or type(C_Traits.GetDefinitionInfo) ~= "function" then return end
    local okD, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
    if not okD or type(def) ~= "table" then return end
    row.spellID = def.spellID
    row.overrideName = def.overrideName and tostring(def.overrideName) or nil
    if def.spellID and type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local okS, sname = pcall(C_Spell.GetSpellName, def.spellID)
        row.spellName = (okS and sname) and tostring(sname) or nil
    end
end

--- Talents. Enum.TraitConfigType.CamelotCombat is the lead: read the active config and report its
--- type number, then walk one tree far enough to see whether nodes carry ranks and entries the
--- way a retail tree does.
local function ProbeTalents()
    local out = { classic = {}, traits = {}, nodes = {} }
    Probe(out.classic, "GetNumTalentTabs", _G.GetNumTalentTabs)
    Probe(out.classic, "GetTalentTabInfo_1", _G.GetTalentTabInfo, 1)
    Probe(out.classic, "GetNumTalents_1", _G.GetNumTalents, 1)
    Probe(out.classic, "GetTalentInfo_1_1", _G.GetTalentInfo, 1, 1)
    Probe(out.classic, "UnitCharacterPoints", _G.UnitCharacterPoints, "player")
    Probe(out.classic, "GetNumUnspentTalents", _G.GetNumUnspentTalents)

    if type(Enum) == "table" and type(Enum.TraitConfigType) == "table" then
        local types = {}
        for k, v in pairs(Enum.TraitConfigType) do
            if type(k) == "string" then types[k] = v end
        end
        out.configTypes = types
    end

    local configID
    if type(C_ClassTalents) == "table" then
        Probe(out.traits, "GetActiveConfigID", C_ClassTalents.GetActiveConfigID)
        Probe(out.traits, "GetActiveHeroTalentSpec", C_ClassTalents.GetActiveHeroTalentSpec)
        if type(C_ClassTalents.GetActiveConfigID) == "function" then
            local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
            if ok and type(id) == "number" then configID = id end
        end
    else
        out.traits.C_ClassTalents = "ABSENT"
    end
    Probe(out.traits, "GetSpecialization", _G.GetSpecialization)
    Probe(out.traits, "GetNumSpecializations", _G.GetNumSpecializations)

    if type(C_Traits) ~= "table" or not configID then
        out.configID = configID or "none"
        return out
    end
    out.configID = configID

    local okC, config = pcall(C_Traits.GetConfigInfo, configID)
    if not okC or type(config) ~= "table" then return out end
    out.config = {
        id = config.ID,
        type = config.type,
        name = config.name and tostring(config.name) or nil,
        treeIDs = config.treeIDs,
    }
    local trees = config.treeIDs
    if type(trees) ~= "table" then return out end
    for t = 1, #trees do
        local treeID = trees[t]
        local okT, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if okT and type(nodeIDs) == "table" then
            local bucket = { treeID = treeID, nodeCount = #nodeIDs, samples = {} }
            if type(C_Traits.GetTreeInfo) == "function" then
                local okTI, tree = pcall(C_Traits.GetTreeInfo, configID, treeID)
                if okTI and type(tree) == "table" then
                    bucket.treeGates = (type(tree.gates) == "table") and #tree.gates or 0
                    bucket.treeButtonType = tree.ButtonType
                end
            end
            for n = 1, math.min(#nodeIDs, MAX_TALENT_NODES) do
                local nodeID = nodeIDs[n]
                local okNI, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if okNI and type(node) == "table" then
                    local row = {
                        nodeID = nodeID,
                        type = node.type,
                        maxRanks = node.maxRanks,
                        currentRank = node.currentRank,
                        ranksPurchased = node.ranksPurchased,
                        isAvailable = node.isAvailable and true or false,
                        isVisible = node.isVisible and true or false,
                        canPurchase = node.canPurchaseRank and true or false,
                        entryCount = (type(node.entryIDs) == "table") and #node.entryIDs or 0,
                        -- posY is the only tier signal a trait tree carries: nodes on one row of
                        -- the old talent panel share it. conditionIDs plus meetsEdgeRequirements
                        -- say WHY a node is locked (points spent in the tab vs a missing parent),
                        -- which is the difference between "needs level 20" and "needs 5 points above".
                        posX = node.posX,
                        posY = node.posY,
                        meetsEdges = node.meetsEdgeRequirements and true or false,
                        conditionCount = (type(node.conditionIDs) == "table") and #node.conditionIDs or 0,
                        groupCount = (type(node.groupIDs) == "table") and #node.groupIDs or 0,
                        -- The three talent tabs are plainly there -- posX splits them into clean
                        -- bands -- but nothing read so far carries their NAMES (Elemental /
                        -- Enhancement / Restoration). subTreeID is the last candidate: if the
                        -- tabs are sub-trees, GetSubTreeInfo names them. If this stays nil the
                        -- client does not publish tab names at all and the UI must order them
                        -- left to right the way the talent frame does, without labels.
                        subTreeID = node.subTreeID,
                    }
                    if node.subTreeID and type(C_Traits.GetSubTreeInfo) == "function" then
                        local okST, sub = pcall(C_Traits.GetSubTreeInfo, configID, node.subTreeID)
                        if okST and type(sub) == "table" then
                            row.subTreeName = sub.name and tostring(sub.name) or nil
                        end
                    end
                    local conds = node.conditionIDs
                    if type(conds) == "table" and conds[1]
                        and type(C_Traits.GetConditionInfo) == "function" then
                        local okCo, cond = pcall(C_Traits.GetConditionInfo, configID, conds[1])
                        if okCo and type(cond) == "table" then
                            row.condType = cond.type
                            row.condSpent = cond.spentAmountRequired
                            row.condMet = cond.isMet and true or false
                            row.condGate = cond.isGate and true or false
                        end
                    end
                    local entryIDs = node.entryIDs
                    if type(entryIDs) == "table" and entryIDs[1] then
                        DescribeTraitEntry(configID, entryIDs[1], row)
                    end
                    bucket.samples[#bucket.samples + 1] = row
                end
            end
            out.nodes[#out.nodes + 1] = bucket
        end
    end
    return out
end

--[[
    Class trainer sweep.

    The wide spellbook sweep settled that unlearned spells are not in the spellbook: 22 slots, all
    of them Enum.SpellBookItemType.Spell, no FutureSpell anywhere in either bank. That is what a
    vanilla progression looks like -- spells are bought from a class trainer rather than granted on
    level-up, so the client has no "you will learn X at level Y" list to publish.

    Which leaves one place that list could still live: the trainer window itself. The Classic
    trainer API reports every service a trainer offers, including the ones the player cannot buy
    yet, with the level each needs -- enough to cache a full "locked skills" list after a single
    visit. Whether it survives on a Mainline build is unknown, so ask.

    Two readings matter and they are different answers:
      - ABSENT: the API is gone, and a locked-skills list cannot be built from this client at all.
      - present but answering 0 / nil with no trainer open: the API is there and only needs the
        window, which means the feature is possible, just event-driven.
]]
local function ProbeTrainer()
    local out = {}
    Probe(out, "GetNumTrainerServices", _G.GetNumTrainerServices)
    Probe(out, "GetTrainerServiceInfo_1", _G.GetTrainerServiceInfo, 1)
    Probe(out, "GetTrainerServiceLevelReq_1", _G.GetTrainerServiceLevelReq, 1)
    Probe(out, "GetTrainerServiceCost_1", _G.GetTrainerServiceCost, 1)
    Probe(out, "GetTrainerServiceTypeFilter", _G.GetTrainerServiceTypeFilter, "available")
    Probe(out, "SetTrainerServiceTypeFilter", _G.SetTrainerServiceTypeFilter)
    Probe(out, "IsTradeskillTrainer", _G.IsTradeskillTrainer)
    Probe(out, "C_SpellBook.GetSpellLevelLearned",
        type(C_Spell) == "table" and C_Spell.GetSpellLevelLearned or nil, 403)
    -- If the event does not exist the window can never be caught, which answers it on its own.
    if type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function" then
        for _, evt in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED" }) do
            local ok, valid = pcall(C_EventUtils.IsEventValid, evt)
            out[evt] = ok and (valid and true or false) or "unknown"
        end
    end
    return out
end

--[[
    Item level.

    The roster shows "iLvl 1.7" for a level 8 character whose equipped pieces scan as item levels
    3..10 (nine slots, 61 total, average 6.8). 1.75 is not that average under any slot count, so
    whatever GetAverageItemLevel reports here does not describe the gear.

    Two things to separate before deciding what the column should do:
      - Which of the two returns is wrong. The addon stores the second (avgItemLevelEquipped);
        if the first one is sane the fix is a different return, not a hidden column.
      - Whether per-item levels are sound. GetDetailedItemLevelInfo on each equipped link answers
        that, and those values are the ones the Gear tab draws -- they can stay even if the
        average goes.
]]
local function ProbeItemLevel()
    local out = { slots = {} }
    Probe(out, "GetAverageItemLevel", _G.GetAverageItemLevel)
    if type(_G.GetAverageItemLevel) == "function" then
        local ok, overall, equipped = pcall(_G.GetAverageItemLevel)
        if ok then
            out.overall = overall
            out.equipped = equipped
        end
    end
    Probe(out, "GetAverageItemLevelEquipped", _G.GetAverageItemLevelEquipped)
    -- Per-slot truth, straight from the equipped links, to compare against the average above.
    local sum, count = 0, 0
    for slot = 1, 19 do
        local okL, link = pcall(GetInventoryItemLink, "player", slot)
        if okL and link and not (issecretvalue and issecretvalue(link)) then
            local ilvl
            if type(C_Item) == "table" and type(C_Item.GetDetailedItemLevelInfo) == "function" then
                local okI, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
                if okI then ilvl = v end
            end
            out.slots[#out.slots + 1] = { slot = slot, itemLevel = ilvl }
            if type(ilvl) == "number" and ilvl > 0 then
                sum = sum + ilvl
                count = count + 1
            end
        end
    end
    out.equippedCount = count
    out.ownAverage = (count > 0) and (sum / count) or 0
    return out
end

--[[
    Profession recipes, measured with a trade skill window OPEN.

    The Skills column works because the class trainer publishes every spell with the level it
    needs. Professions need the same two halves -- what is known, and what is still to come -- but
    from a different surface, and which one carries them is not settled:

      - C_TradeSkillUI.GetAllRecipeIDs / GetRecipeInfo: the modern path. Closed, both answered
        empty, which says nothing either way. Open, GetRecipeInfo should say whether a recipe is
        `learned` and what it requires -- if those fields exist on this build.
      - The trainer list: a profession trainer answers GetTrainerServiceInfo like a class trainer
        does, but the requirement there is a SKILL value, not a character level, and whether
        GetTrainerServiceLevelReq carries it (or a GetTrainerServiceSkillReq exists at all) is
        unknown.

    So this records both, plus every field the first recipe actually has, rather than assuming a
    shape. Run it with a profession window open.
]]
local MAX_RECIPES = 400
local function ProbeRecipes()
    local out = { available = false, recipes = {}, fields = {} }
    if type(C_TradeSkillUI) ~= "table" then return out end
    out.available = true
    Probe(out, "IsTradeSkillReady", C_TradeSkillUI.IsTradeSkillReady)
    Probe(out, "GetTradeSkillLine", C_TradeSkillUI.GetTradeSkillLine)
    Probe(out, "GetBaseProfessionInfo", C_TradeSkillUI.GetBaseProfessionInfo)
    -- Which profession the open window belongs to is the one thing still missing before recipes
    -- can be cached per profession: GetTradeSkillLine is ABSENT here and GetBaseProfessionInfo
    -- answered a table with no array part, so its FIELDS are what matter, not its length.
    if type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local okB, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if okB and type(info) == "table" then
            local fields = {}
            for k, v in pairs(info) do
                if type(k) == "string" then fields[k] = type(v) .. "=" .. tostring(v) end
            end
            out.baseProfessionFields = fields
        end
    end
    if type(C_TradeSkillUI.GetChildProfessionInfos) == "function" then
        local okC, infos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
        if okC and type(infos) == "table" and infos[1] and type(infos[1]) == "table" then
            local fields = {}
            for k, v in pairs(infos[1]) do
                if type(k) == "string" then fields[k] = type(v) .. "=" .. tostring(v) end
            end
            out.childProfessionFields = fields
        end
    end
    -- Trainer side, in case the window is open at a trainer.
    Probe(out, "IsTradeskillTrainer", _G.IsTradeskillTrainer)
    Probe(out, "GetNumTrainerServices", _G.GetNumTrainerServices)
    Probe(out, "GetTrainerServiceSkillReq_1", _G.GetTrainerServiceSkillReq, 1)
    Probe(out, "GetTrainerServiceLevelReq_1", _G.GetTrainerServiceLevelReq, 1)
    Probe(out, "GetTrainerServiceInfo_1", _G.GetTrainerServiceInfo, 1)

    if type(C_TradeSkillUI.GetAllRecipeIDs) ~= "function" then return out end
    local okIDs, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIDs or type(ids) ~= "table" then return out end
    out.recipeCount = #ids
    if #ids == 0 then return out end

    -- Every key the first recipe carries, so the real shape is on record instead of the one the
    -- documentation describes.
    local okFirst, first = pcall(C_TradeSkillUI.GetRecipeInfo, ids[1])
    if okFirst and type(first) == "table" then
        for k, v in pairs(first) do
            if type(k) == "string" then out.fields[k] = type(v) .. "=" .. tostring(v) end
        end
    end

    local learned, unlearned = 0, 0
    for i = 1, math.min(#ids, MAX_RECIPES) do
        local okR, info = pcall(C_TradeSkillUI.GetRecipeInfo, ids[i])
        if okR and type(info) == "table" then
            if info.learned then learned = learned + 1 else unlearned = unlearned + 1 end
            if #out.recipes < 40 then
                out.recipes[#out.recipes + 1] = {
                    id = ids[i],
                    name = info.name and tostring(info.name) or nil,
                    learned = info.learned and true or false,
                    icon = info.icon,
                    difficulty = info.relativeDifficulty,
                    skillUps = info.numSkillUps,
                    required = info.requiredLevel or info.unlockedRecipeLevel,
                    categoryID = info.categoryID,
                }
            end
        end
    end
    out.learned = learned
    out.unlearned = unlearned
    return out
end

--- What the crafting companion sees with no profession window open. If these only answer while
--- TRADE_SKILL_SHOW is up, the companion has to be event-driven rather than poll on demand.
local function ProbeCrafting()
    local out = {}
    if type(C_TradeSkillUI) ~= "table" then
        out.available = false
        return out
    end
    out.available = true
    Probe(out, "IsTradeSkillReady", C_TradeSkillUI.IsTradeSkillReady)
    Probe(out, "GetTradeSkillLine", C_TradeSkillUI.GetTradeSkillLine)
    Probe(out, "IsTradeSkillGuild", C_TradeSkillUI.IsTradeSkillGuild)
    Probe(out, "IsNPCCrafting", C_TradeSkillUI.IsNPCCrafting)
    Probe(out, "GetFilteredRecipeIDs", C_TradeSkillUI.GetFilteredRecipeIDs)
    Probe(out, "GetAllRecipeIDs", C_TradeSkillUI.GetAllRecipeIDs)
    Probe(out, "GetRecipeInfo_1", C_TradeSkillUI.GetRecipeInfo, 1)
    -- The Classic crafting surface (TradeSkillFrame / CraftFrame) sits in _G, not C_TradeSkillUI.
    Probe(out, "GetNumTradeSkills", _G.GetNumTradeSkills)
    Probe(out, "GetTradeSkillInfo_1", _G.GetTradeSkillInfo, 1)
    Probe(out, "GetNumCrafts", _G.GetNumCrafts)
    Probe(out, "GetCraftInfo_1", _G.GetCraftInfo, 1)
    Probe(out, "GetCraftName", _G.GetCraftName)
    return out
end

--[[
    Character sheet stats.

    The Gear paperdoll was built for retail: four primaries and the four secondary ratings. A
    vanilla-era character sheet is a different list -- Spirit is a primary, Mastery and Versatility
    do not exist, and the defensive block (Defense, Dodge, Parry, Block) and the five resistances
    are what the player actually gears for. Which of those this client answers is not something to
    read off a wiki page, so every candidate is called here and the dump decides.
]]
local RESISTANCE_SCHOOLS = {
    [0] = "Physical", [1] = "Holy", [2] = "Fire", [3] = "Nature",
    [4] = "Frost", [5] = "Shadow", [6] = "Arcane",
}

local function ProbeStats()
    local out = {}

    -- Primaries, Spirit included: UnitStat returns base, stat, posBuff, negBuff.
    for statIndex = 1, 5 do
        Probe(out, "UnitStat[" .. statIndex .. "]", UnitStat, "player", statIndex)
    end
    Probe(out, "UnitArmor", UnitArmor, "player")

    -- Resistances: school 0 is armor on a vanilla sheet, 1..6 the magic schools.
    for school = 0, 6 do
        Probe(out, "UnitResistance[" .. school .. "=" .. (RESISTANCE_SCHOOLS[school] or "?") .. "]",
            UnitResistance, "player", school)
    end

    -- Offence.
    Probe(out, "UnitAttackPower", UnitAttackPower, "player")
    Probe(out, "UnitRangedAttackPower", UnitRangedAttackPower, "player")
    Probe(out, "UnitDamage", UnitDamage, "player")
    Probe(out, "UnitAttackSpeed", UnitAttackSpeed, "player")
    Probe(out, "GetCritChance", GetCritChance)
    Probe(out, "GetRangedCritChance", GetRangedCritChance)
    Probe(out, "GetSpellCritChance[2]", GetSpellCritChance, 2)
    Probe(out, "GetHitModifier", GetHitModifier)
    Probe(out, "GetSpellBonusDamage[2]", GetSpellBonusDamage, 2)
    Probe(out, "GetSpellBonusHealing", GetSpellBonusHealing)
    Probe(out, "GetManaRegen", GetManaRegen)

    -- Defence.
    Probe(out, "UnitDefense", UnitDefense, "player")
    Probe(out, "GetDodgeChance", GetDodgeChance)
    Probe(out, "GetParryChance", GetParryChance)
    Probe(out, "GetBlockChance", GetBlockChance)
    Probe(out, "GetShieldBlock", GetShieldBlock)

    -- Retail-only ratings: present here tells us the paperdoll's current list is still right.
    for _, ratingIndex in ipairs({ 9, 18, 26, 29 }) do
        Probe(out, "GetCombatRating[" .. ratingIndex .. "]", GetCombatRating, ratingIndex)
    end
    Probe(out, "GetHaste", GetHaste)
    Probe(out, "GetMasteryEffect", GetMasteryEffect)
    Probe(out, "GetAverageItemLevel", GetAverageItemLevel)

    return out
end

function WarbandNexus:WriteCharacterProbe()
    if not self.db or not self.db.global then return nil, "db" end
    local _, build, _, interface = GetBuildInfo()
    local okClass, _, classFile = pcall(UnitClass, "player")
    local probe = {
        takenAt = time(),
        build = tostring(build),
        interface = interface,
        level = (type(UnitLevel) == "function") and UnitLevel("player") or nil,
        class = okClass and classFile or nil,
        isForever = (ns.Capabilities and ns.Capabilities.IsForeverClient
            and ns.Capabilities.IsForeverClient()) or false,
        spellBook = ProbeSpellBook(),
        spellBookWide = ProbeSpellBookWide(),
        spellBookTabs = ProbeSpellBookTabs(),
        skillLines = ProbeSkillLines(),
        trainer = ProbeTrainer(),
        itemLevel = ProbeItemLevel(),
        professions = ProbeProfessions(),
        talents = ProbeTalents(),
        talentNames = ProbeTalentNames(),
        crafting = ProbeCrafting(),
        recipes = ProbeRecipes(),
        stats = ProbeStats(),
    }
    self.db.global.charProbe = probe
    return probe
end
