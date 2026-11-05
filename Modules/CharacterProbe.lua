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
                    }
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
        skillLines = ProbeSkillLines(),
        professions = ProbeProfessions(),
        talents = ProbeTalents(),
        crafting = ProbeCrafting(),
    }
    self.db.global.charProbe = probe
    return probe
end
