--[[
    Warband Nexus - class trainer cache (WoW Forever).

    Why this exists: on Forever the spellbook holds ONLY learned spells. A wide sweep of slots
    1..300 across both banks on a level 8 character returned 22 entries, every one of them
    Enum.SpellBookItemType.Spell and not a single FutureSpell -- so the client never publishes
    "you will learn X at level Y". That is what a vanilla progression looks like: spells are bought
    from a class trainer rather than granted on level-up, so the list lives on the trainer, not in
    the character.

    The trainer API is alive here (/wn charprobe: GetNumTrainerServices answered 0 rather than
    ABSENT with no trainer open, SetTrainerServiceTypeFilter raised a usage error rather than
    nil-called, and TRAINER_SHOW / TRAINER_UPDATE / TRAINER_CLOSED are all valid events). So one
    visit to a class trainer is enough to capture every teachable spell with its level
    requirement, and after that the Skill tooltip can name locked abilities away from the trainer.

    What is cached and what is not:
      - CACHED, per class, account-wide: the spell name, its rank, and the level it needs. That
        set is a property of the class, not of the character, so every alt of that class reads the
        same list and only the first one has to visit a trainer.
      - NOT cached: whether a given character knows a spell. The wiki's "used" / "available" /
        "unavailable" category is per character and goes stale the moment another alt looks at it.
        Known-ness is answered from that character's own spellbook scan instead.

    Filter handling: the wiki is explicit that service indices "are affected by the trainer
    filter", so a spell the player cannot learn yet can be hidden entirely. The three filters are
    read first, only the ones that are off get switched on, and the originals are put back in the
    same call -- the player's own filter choice survives. Flipping a filter may fire TRAINER_UPDATE
    (the wiki does not say either way), so the scan holds a re-entrancy flag rather than trusting
    it not to.

    Layer: Service. Writes db.global.trainerSkills and emits WN_TRAINER_SKILLS_UPDATED; never
    touches the UI.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local EVENTS = ns.Constants and ns.Constants.EVENTS
local MSG_TRAINER_UPDATED = (EVENTS and EVENTS.TRAINER_SKILLS_UPDATED)
    or "WN_TRAINER_SKILLS_UPDATED"

-- The three documented filter names. "header" is a row category, not a filter.
local FILTER_TYPES = { "available", "unavailable", "used" }
-- GetNumTrainerServices "will be the last valid value, rather than 0" for an invalid target, so
-- the count is never trusted on its own -- the loop also stops on the first nil name, as the
-- wiki's own examples do. The bound is a safety net against a stale huge count.
local MAX_SERVICES = 500

-- Stamped on the stored list. Version 1 wrote the per-character category into a field it called
-- `rank`, which broke matching; the names and level requirements it captured were correct, so
-- version 2 renames the field in place rather than throwing a trainer visit away.
-- Version 3 keys rows by name + level: the trainer lists one row PER RANK under the same name
-- (Lightning Bolt at 1, 8, 14, ... 56), and keying by name alone collapsed every rank into one
-- row carrying the last rank's level (Lightning Bolt 56). v2 rows are kept as they are -- each
-- is still one real rank -- and the next visit fills the rest in.
local TRAINER_CACHE_VERSION = 3
local CATEGORY_VALUES = { used = true, available = true, unavailable = true }

--- Bring a stored list up to the current shape. Returns the store, upgraded in place.
---
--- Lives here rather than in MigrationService because it is this service's own cache, carrying
--- its own version stamp; nothing else in the database refers to it.
local function UpgradeStore(store)
    if not store or type(store.services) ~= "table" then return store end
    if (tonumber(store.version) or 0) >= TRAINER_CACHE_VERSION then return store end
    if (tonumber(store.version) or 0) == 2 then
        store.version = TRAINER_CACHE_VERSION
        return store
    end
    -- v1 keyed rows by name + category, so one spell could be stored more than once as its
    -- category changed. Collapse by name, keeping whichever row learned a level requirement.
    local byName, order = {}, {}
    for i = 1, #store.services do
        local row = store.services[i]
        if type(row) == "table" and row.name then
            if row.rank ~= nil then
                if CATEGORY_VALUES[row.rank] then row.category = row.rank end
                row.rank = nil
            end
            local kept = byName[row.name]
            if not kept then
                byName[row.name] = row
                order[#order + 1] = row
            elseif row.level and not kept.level then
                kept.level = row.level
                kept.category = row.category or kept.category
            end
        end
    end
    store.services = order
    store.version = TRAINER_CACHE_VERSION
    return store
end

local scanning = false

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

--- Current state of the three service filters, so the player's own choice can be restored.
local function ReadFilters()
    if type(_G.GetTrainerServiceTypeFilter) ~= "function" then return nil end
    local state = {}
    for i = 1, #FILTER_TYPES do
        local name = FILTER_TYPES[i]
        local ok, on = pcall(_G.GetTrainerServiceTypeFilter, name)
        if not ok then return nil end
        state[name] = on and true or false
    end
    return state
end

--- Set only the filters that need changing; returns false when the setter is unavailable.
local function ApplyFilters(target)
    if type(_G.SetTrainerServiceTypeFilter) ~= "function" then return false end
    local changed = false
    for i = 1, #FILTER_TYPES do
        local name = FILTER_TYPES[i]
        local want = target[name]
        local ok, current = pcall(_G.GetTrainerServiceTypeFilter, name)
        if not ok or ((current and true or false) ~= want) then
            pcall(_G.SetTrainerServiceTypeFilter, name, want)
            changed = true
        end
    end
    return true, changed
end

--[[
    One service row, or nil for headers and anything unreadable.

    The wiki documents GetTrainerServiceInfo as `name, rank, category, expanded`. On this client
    the SECOND return is the CATEGORY: a real scan read back "used" and "unavailable" where a rank
    string was expected, and no rank text anywhere in the list. So the rank is not published here.
    The category is per character, which makes it useless in an account-wide cache -- it is kept
    for diagnostics and deliberately drives nothing cross-character.
]]
local function ReadService(index)
    local ok, name, r2, r3 = pcall(_G.GetTrainerServiceInfo, index)
    if not ok or name == nil then return nil, true end          -- second value: stop the walk
    if IsSecret(name) or IsSecret(r2) or IsSecret(r3) then return nil end
    -- Identify returns by VALUE: the slot holding the category has moved between builds (see
    -- above), so the category is whichever return is a category word, and any other non-empty
    -- string is the row's sub text -- the "Rank 3" the trainer window prints, when published.
    local category, subText
    for _, v in ipairs({ r2, r3 }) do
        if type(v) == "string" and v ~= "" then
            if v == "header" or CATEGORY_VALUES[v] then
                category = category or v
            elseif v ~= name then
                subText = subText or v
            end
        end
    end
    if category == "header" then return nil, false, tostring(name) end

    local entry = { name = tostring(name), category = category, subText = subText }
    -- Which spellbook tab the service belongs to ("Elemental Combat", ...): lets a spell the
    -- character never learned sit in the right tree. GetTrainerServiceSkillLine is in the Forever
    -- client's global list; classic returns the line NAME -- kept only when it is a plain string.
    if type(_G.GetTrainerServiceSkillLine) == "function" then
        local okS, line = pcall(_G.GetTrainerServiceSkillLine, index)
        if okS and type(line) == "string" and line ~= "" and not IsSecret(line) then
            entry.skillLine = line
        end
    end
    if type(_G.GetTrainerServiceLevelReq) == "function" then
        local okL, level = pcall(_G.GetTrainerServiceLevelReq, index)
        if okL and type(level) == "number" and level > 0 then entry.level = level end
    end
    if type(_G.GetTrainerServiceIcon) == "function" then
        local okI, icon = pcall(_G.GetTrainerServiceIcon, index)
        if okI and icon then entry.icon = icon end
    end
    -- The link is the only route to a spell id the wiki documents for a service; its format is
    -- not documented, so parse defensively and simply leave spellID nil when it does not match.
    if type(_G.GetTrainerServiceItemLink) == "function" then
        local okK, link = pcall(_G.GetTrainerServiceItemLink, index)
        if okK and type(link) == "string" and not IsSecret(link) then
            local id = link:match("|Hspell:(%d+)") or link:match("|Henchant:(%d+)")
            if id then entry.spellID = tonumber(id) end
        end
    end
    -- What the trainer window shows for the row: the spell's text and its price. Lets a rank the
    -- character never learned (no spell id to hand) still get a real tooltip.
    if type(_G.GetTrainerServiceDescription) == "function" then
        local okD, desc = pcall(_G.GetTrainerServiceDescription, index)
        if okD and type(desc) == "string" and desc ~= "" and not IsSecret(desc) then
            entry.description = desc
        end
    end
    if type(_G.GetTrainerServiceCost) == "function" then
        local okC, cost = pcall(_G.GetTrainerServiceCost, index)
        if okC and type(cost) == "number" and not IsSecret(cost) and cost > 0 then
            entry.cost = cost
        end
    end
    return entry
end

--- Walk the service list as it currently stands. Caller owns the filter state.
local function CollectServices()
    if type(_G.GetNumTrainerServices) ~= "function" then return nil end
    local okN, count = pcall(_G.GetNumTrainerServices)
    if not okN or type(count) ~= "number" or count <= 0 then return nil end
    local out = {}
    -- The Forever trainer lists its services under category headers -- the spellbook tabs. Every
    -- row after a header belongs to it, which is how a spell the character never learned gets its
    -- tree. GetTrainerServiceSkillLine wins when it answers with a name (ReadService).
    local currentHeader
    for i = 1, math.min(count, MAX_SERVICES) do
        local entry, stop, header = ReadService(i)
        if stop then break end
        if header then currentHeader = header end
        if entry then
            entry.skillLine = entry.skillLine or currentHeader
            out[#out + 1] = entry
        end
    end
    return out
end

--- One rank of one spell: the trainer lists every rank as its own row under the same name, and
--- the level requirement is what tells them apart.
local function ServiceKey(row)
    return tostring(row.name) .. "@" .. tostring(row.level or "-")
end

--- Merge a freshly read list into the stored one, keyed by name + level (one row per rank).
--- Merging rather than replacing: a trainer may show a subset, and nothing says a single visit
--- covers the whole class list.
---@param charKey string|nil character that made this visit: its "used" rows are known to it
local function MergeIntoCache(store, services, charKey, charLevel)
    local byKey = {}
    for i = 1, #store.services do
        byKey[ServiceKey(store.services[i])] = store.services[i]
    end
    local added, updated = 0, 0
    for i = 1, #services do
        local fresh = services[i]
        local key = ServiceKey(fresh)
        local existing = byKey[key]
        -- "used" is this character having learned the row. It never reverts, so it is safe to
        -- keep per character -- and it is the only proof for rows the spellbook never lists
        -- (weapon skills, armor proficiencies).
        if charKey and fresh.category == "used" then
            local target = existing or fresh
            target.usedBy = target.usedBy or {}
            target.usedBy[charKey] = true
        end
        -- The trainer's own verdict for THIS character at THIS level: "available" (can buy now),
        -- "unavailable" (level or a missing earlier rank), "used" (known). Kept per character with
        -- the level it was read at, so the summary can tell a prerequisite block from a level gate.
        if charKey and fresh.category then
            local target = existing or fresh
            target.categoryBy = target.categoryBy or {}
            target.categoryBy[charKey] = { c = fresh.category, lvl = charLevel }
        end
        if not existing then
            store.services[#store.services + 1] = fresh
            byKey[key] = fresh
            added = added + 1
        else
            -- Fill gaps only; a level that was readable once should not be lost to a visit
            -- where the row was filtered out of range.
            if fresh.level and existing.level ~= fresh.level then
                existing.level = fresh.level
                updated = updated + 1
            end
            if fresh.spellID and not existing.spellID then existing.spellID = fresh.spellID end
            if fresh.icon and not existing.icon then existing.icon = fresh.icon end
            if fresh.subText and not existing.subText then existing.subText = fresh.subText end
            if fresh.skillLine then existing.skillLine = fresh.skillLine end
            if fresh.description then existing.description = fresh.description end
            if fresh.cost then existing.cost = fresh.cost end
            existing.category = fresh.category or existing.category
            existing.rank = nil   -- drop the mislabelled field an earlier build wrote
        end
    end
    table.sort(store.services, function(a, b)
        local al, bl = a.level or 0, b.level or 0
        if al ~= bl then return al < bl end
        return a.name < b.name
    end)
    return added, updated
end

--- Scan the open class trainer. Returns nil when there is nothing to read.
function WarbandNexus:ScanTrainerServices()
    if scanning then return nil end
    if not self.db or not self.db.global then return nil end
    -- Tradeskill trainers teach recipes, not class spells; their list belongs to the profession
    -- surface, not to the Skill column.
    if type(_G.IsTradeskillTrainer) == "function" then
        local okT, isTrade = pcall(_G.IsTradeskillTrainer)
        if okT and isTrade then return nil end
    end
    local _, classFile = UnitClass("player")
    if not classFile or IsSecret(classFile) then return nil end

    scanning = true
    local restore = ReadFilters()
    local ok, services = pcall(function()
        -- Everything visible, so "unavailable" rows (the locked ones, which are the whole point)
        -- are in the list.
        ApplyFilters({ available = true, unavailable = true, used = true })
        return CollectServices()
    end)
    if restore then pcall(ApplyFilters, restore) end
    scanning = false

    if not ok or type(services) ~= "table" or #services == 0 then return nil end

    self.db.global.trainerSkills = self.db.global.trainerSkills or {}
    local store = UpgradeStore(self.db.global.trainerSkills[classFile])
    if not store then
        store = { services = {}, version = TRAINER_CACHE_VERSION }
        self.db.global.trainerSkills[classFile] = store
    end
    store.services = store.services or {}
    store.version = TRAINER_CACHE_VERSION
    local U = ns.Utilities
    local charKey = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(self) or nil
    if IsSecret(charKey) then charKey = nil end
    local scanLevel = UnitLevel and UnitLevel("player") or nil
    if IsSecret(scanLevel) then scanLevel = nil end
    local added, updated = MergeIntoCache(store, services, charKey, tonumber(scanLevel))
    store.scannedAt = time()
    store.lastSeen = #services

    self:SendMessage(MSG_TRAINER_UPDATED, {
        classFile = classFile,
        added = added,
        updated = updated,
        total = #store.services,
    })
    return store, added, updated
end

--- Everything this class can be taught, as captured so far. nil when no trainer was ever visited.
---@param classFile string|nil defaults to the current character's class
function WarbandNexus:GetTrainerSkills(classFile)
    if not self.db or not self.db.global then return nil end
    local cache = self.db.global.trainerSkills
    if not cache then return nil end
    if not classFile then
        local _, cf = UnitClass("player")
        classFile = cf
    end
    if not classFile or IsSecret(classFile) then return nil end
    local store = UpgradeStore(cache[classFile])
    if not store or not store.services or #store.services == 0 then return nil end
    return store
end

--[[
    Joining the two halves.

    The trainer cache says what the CLASS can be taught; the character's own spellbook scan says
    what THIS character knows. Neither alone answers the question the Skill column exists for --
    "is there anything to go train?" -- so they are matched here, by name plus rank, because that
    is the only key both sides carry (a service has no spell id unless its link happens to parse).
]]
--[[
    What the character knows, per spell NAME: the highest level among the ranks in its spellbook.
    The spellbook keeps every learned rank with the level it is learned at (Lightning Bolt: Rank 1
    at 1, Rank 2 at 8), and a trainer row is one rank with its level requirement -- so a row is
    known when the character holds a rank of that spell at or above the row's level. Matching by
    name alone hid every later rank as soon as the first was learned.
]]
local function KnownSpellLevels(systems)
    local known, levelSets = {}, {}
    local spells = systems and systems.spells
    if not spells or type(spells.lines) ~= "table" then return known, levelSets end
    for i = 1, #spells.lines do
        local line = spells.lines[i]
        for s = 1, #(line.spells or {}) do
            local spell = line.spells[s]
            if spell.known ~= false and spell.name then
                local key = tostring(spell.name)
                local lvl = tonumber(spell.level) or 0
                if (known[key] or -1) < lvl then known[key] = lvl end
                if lvl > 0 then
                    levelSets[key] = levelSets[key] or {}
                    levelSets[key][lvl] = true
                end
            end
        end
    end
    return known, levelSets
end

--[[
    Rank number of each leveled trainer row: its position among every level this spell is known
    to have a rank at -- the trainer's rows AND the ranks already in the spellbook. Counting trainer
    rows alone numbered from whatever the cache happened to hold (Lightning Bolt at 14 came out as
    R1 while the character already knows R1 at 1 and R2 at 8; it is R3).
]]
local function RankIndexByRow(services, knownLevelSets)
    local levels = {}
    for i = 1, #services do
        local row = services[i]
        if row.level then
            local key = tostring(row.name)
            levels[key] = levels[key] or {}
            levels[key][row.level] = true
        end
    end
    for key, set in pairs(knownLevelSets or {}) do
        if levels[key] then
            for lvl in pairs(set) do levels[key][lvl] = true end
        end
    end
    local order = {}
    for key, set in pairs(levels) do
        local list = {}
        for lvl in pairs(set) do list[#list + 1] = lvl end
        if #list > 1 then
            table.sort(list)
            local pos = {}
            for r = 1, #list do pos[list[r]] = r end
            order[key] = pos
        end
    end
    local rankOf = {}
    for i = 1, #services do
        local row = services[i]
        local pos = row.level and order[tostring(row.name)]
        if pos then rankOf[row] = pos[row.level] end
    end
    return rankOf
end

-- Memoised per character. The roster calls this once per row on every paint (the badge needs it),
-- and each call built three tables and walked the whole service list -- exactly the per-row
-- allocation the perf rules warn about. The stamp is the two scans behind the answer, so a new
-- trainer visit or a talent/spellbook rescan invalidates it on its own with no event wiring.
local summaryCache = {}

--- What a character still has to learn, split into "can train now" and "locked by level".
---@param charKey string|nil
---@param classFile string|nil
---@param level number|nil character level; defaults to the current player's
---@return table|nil summary { trainable = {}, locked = {}, knownCount = n, hasTrainerData = bool }
function WarbandNexus:GetSkillSummary(charKey, classFile, level)
    local systems = self.GetCharacterSystems and self:GetCharacterSystems(charKey) or nil
    local store = self:GetTrainerSkills(classFile)
    local charLevel = tonumber(level) or (UnitLevel and UnitLevel("player")) or 0
    local stamp = string.format("%s|%s|%s", tostring(systems and systems.scannedAt),
        tostring(store and store.scannedAt), tostring(charLevel))
    local cached = charKey and summaryCache[charKey]
    if cached and cached.stamp == stamp then return cached.summary end

    local known, knownLevelSets = KnownSpellLevels(systems)
    local knownCount = 0
    for _ in pairs(known) do knownCount = knownCount + 1 end

    local summary = {
        knownCount = knownCount,
        trainable = {},
        locked = {},
        hasTrainerData = false,
    }

    local function remember()
        if charKey then summaryCache[charKey] = { stamp = stamp, summary = summary } end
        return summary
    end

    if not store then return remember() end
    summary.hasTrainerData = true
    summary.scannedAt = store.scannedAt

    local rankOf = RankIndexByRow(store.services, knownLevelSets)
    local rankFmt = (ns.L and ns.L["SKILLS_RANK_FMT"]) or "Rank %d"
    for i = 1, #store.services do
        local service = store.services[i]
        local req = tonumber(service.level) or 0
        local knownLevel = known[tostring(service.name)]
        local snap = service.categoryBy and charKey and service.categoryBy[charKey] or nil
        local isKnown = (service.usedBy and charKey and service.usedBy[charKey])
            or (snap and snap.c == "used")
            or (knownLevel ~= nil and (req == 0 or knownLevel >= req))
        -- "unavailable" read at a level that already met the requirement means something else
        -- blocks it (an earlier rank not trained yet): not ready, whatever the level says. Read at
        -- a lower level it was only the level gate, which the current level may have cleared.
        local blocked = snap and snap.c == "unavailable" and snap.lvl and req <= snap.lvl
        if not isKnown then
            -- A view row, so the derived rank label never lands in the saved cache.
            local rank = rankOf[service]
            local view = {
                name = service.name,
                level = service.level,
                icon = service.icon,
                spellID = service.spellID,
                subName = service.subText or (rank and string.format(rankFmt, rank)) or nil,
                skillLine = service.skillLine,
                description = service.description,
                cost = service.cost,
            }
            if req > charLevel or blocked then
                summary.locked[#summary.locked + 1] = view
            else
                summary.trainable[#summary.trainable + 1] = view
            end
        end
    end
    return remember()
end

--[[
    Level-up notice (WoW Forever): "N skills ready to train".

    Spells are bought from a trainer here, so a level-up silently unlocks new spells and new ranks
    of known ones. On PLAYER_LEVEL_CHANGED(oldLevel, newLevel, real) -- the Forever client documents
    it -- the rows whose level requirement falls in (oldLevel, newLevel] are exactly what that
    level-up unlocked; nothing before it, nothing still locked. A row is a NEW SPELL when the
    character knows no rank of it yet, otherwise a NEW RANK. Weapon skills carry no level
    requirement (they are trainable from the start), so a level-up never announces them.
    `real` is false for level sync / scaling, which must not announce anything.
]]
--- Rows a level change unlocked, split into new spells and new ranks of known spells.
---@return table|nil newSpells, table|nil newRanks
function WarbandNexus:GetNewlyTrainableSkills(charKey, classFile, oldLevel, newLevel)
    oldLevel, newLevel = tonumber(oldLevel), tonumber(newLevel)
    if not oldLevel or not newLevel or newLevel <= oldLevel then return nil, nil end
    local summary = self:GetSkillSummary(charKey, classFile, newLevel)
    if not summary or not summary.hasTrainerData then return nil, nil end
    local known = KnownSpellLevels(self.GetCharacterSystems and self:GetCharacterSystems(charKey) or nil)
    local newSpells, newRanks = {}, {}
    for i = 1, #summary.trainable do
        local row = summary.trainable[i]
        local req = tonumber(row.level) or 0
        if req > oldLevel and req <= newLevel then
            if known[tostring(row.name)] ~= nil then
                newRanks[#newRanks + 1] = row
            else
                newSpells[#newSpells + 1] = row
            end
        end
    end
    return newSpells, newRanks
end

--- "Lightning Bolt (Rank 3), Stoneskin Totem, ..." -- at most `limit` names, then "+N".
local function JoinSkillNames(rows, limit)
    local parts = {}
    for i = 1, math.min(#rows, limit) do
        local r = rows[i]
        parts[#parts + 1] = r.subName and (tostring(r.name) .. " (" .. tostring(r.subName) .. ")") or tostring(r.name)
    end
    if #rows > limit then parts[#parts + 1] = "+" .. (#rows - limit) end
    return table.concat(parts, ", ")
end

local LevelUpEvents = {}

local function OnPlayerLevelChanged(_, oldLevel, newLevel, real)
    local addon = WarbandNexus
    if real == false then return end
    if IsSecret(oldLevel) or IsSecret(newLevel) then return end
    if not (addon.SupportsFeature and addon:SupportsFeature("trainedSpells")) then return end
    local n = addon.db and addon.db.profile and addon.db.profile.notifications
    if not n or n.enabled == false or n.showTrainerSkillNotifications == false then return end

    local U = ns.Utilities
    local charKey = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(addon) or nil
    local _, classFile = UnitClass("player")
    if not charKey or IsSecret(charKey) or not classFile or IsSecret(classFile) then return end

    local newSpells, newRanks = addon:GetNewlyTrainableSkills(charKey, classFile, oldLevel, newLevel)
    if not newSpells then return end
    local total = #newSpells + #newRanks
    if total == 0 then return end

    local L = ns.L or {}
    local title = string.format(L["SKILLS_LEVELUP_TITLE_FMT"] or "%d skills ready to train", total)
    local breakdown = {}
    if #newSpells > 0 then
        breakdown[#breakdown + 1] = string.format(L["SKILLS_LEVELUP_NEW_SPELLS_FMT"] or "%d new", #newSpells)
    end
    if #newRanks > 0 then
        breakdown[#breakdown + 1] = string.format(L["SKILLS_LEVELUP_NEW_RANKS_FMT"] or "%d new ranks", #newRanks)
    end
    local all = {}
    for i = 1, #newSpells do all[#all + 1] = newSpells[i] end
    for i = 1, #newRanks do all[#all + 1] = newRanks[i] end
    local first = all[1]

    local events = ns.Constants and ns.Constants.EVENTS
    if events and events.SHOW_NOTIFICATION then
        addon:SendMessage(events.SHOW_NOTIFICATION, { data = {
            title = title,
            message = table.concat(breakdown, "  -  "),
            subtitle = JoinSkillNames(all, 4),
            icon = (first and first.icon) or "Interface\\Icons\\INV_Misc_Book_11",
        } })
    end
end

if WarbandNexus and WarbandNexus.RegisterEvent then
    WarbandNexus.RegisterEvent(LevelUpEvents, "PLAYER_LEVEL_CHANGED", OnPlayerLevelChanged)
end
