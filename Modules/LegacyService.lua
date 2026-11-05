--[[
    Warband Nexus - Legacy Service (WoW Forever)

    The Legacy System is Forever's account-wide progression, and it is what this addon is for: 65
    points at launch, earned once across the whole account and never duplicated between characters.
    It is NOT a separate API. Measured on build 1.60.1.70790:

      - Progress is major faction 2802 "Legacy Track" (2800 is "PvP Rank Points"). Its renown levels
        are the reward tiers -- 15, 25, 40 and 55 -- and GetRenownRewardsForLevel names the reward
        even while the tier is locked, which is how an unearned reward can be shown in advance.
      - The challenges behind the points are the achievement category tree: 29 categories and 111
        entries, each with criteria and live progress, readable with the plain GetAchievement* API.

    Data layer only: everything here writes db.global.legacy and then emits WN_LEGACY_UPDATED.
    Nothing in this file touches UI.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local LEGACY_FACTION_ID = 2802
local PVP_RANK_FACTION_ID = 2800

local pcall, type, tonumber = pcall, type, tonumber

--- Both tracks live behind the same renown API; the ids are the only thing that separates them.
local function ReadRenownTrack(factionID)
    if type(C_MajorFactions) ~= "table" then return nil end
    local okData, data = pcall(C_MajorFactions.GetMajorFactionData, factionID)
    if not okData or type(data) ~= "table" then return nil end
    local track = {
        factionID = factionID,
        name = tostring(data.name or ""),
        level = tonumber(data.renownLevel) or 0,
        levelThreshold = tonumber(data.renownLevelThreshold) or 0,
        tiers = {},
    }
    local okLevels, levels = pcall(C_MajorFactions.GetRenownLevels, factionID)
    if not okLevels or type(levels) ~= "table" then return track end
    for i = 1, #levels do
        local entry = levels[i]
        local lvl = (type(entry) == "table" and tonumber(entry.level)) or tonumber(entry)
        if lvl then
            local tier = {
                level = lvl,
                locked = (type(entry) == "table") and (entry.locked and true or false) or nil,
            }
            local okR, rewards = pcall(C_MajorFactions.GetRenownRewardsForLevel, factionID, lvl)
            if okR and type(rewards) == "table" and #rewards > 0 then
                tier.rewards = {}
                for r = 1, #rewards do
                    local rw = rewards[r]
                    tier.rewards[r] = {
                        name = rw and tostring(rw.name or "") or "",
                        itemID = rw and tonumber(rw.itemID) or nil,
                        -- Enum.RenownRewardDisplayType: Mount / Transmog / Title / Item / Toy...
                        rewardType = rw and rw.renownRewardType or nil,
                        icon = rw and rw.icon or nil,
                    }
                end
            end
            track.tiers[#track.tiers + 1] = tier
        end
    end
    return track
end

--- Walk the achievement category tree. Criteria come back for unfinished entries too, which is the
--- whole point: a player wants to see what the next point costs, not only what is already earned.
local MAX_ENTRIES = 400
local function ReadChallenges()
    local out = { categories = {}, entries = {}, earned = 0, total = 0 }
    if type(GetCategoryList) ~= "function" then return out end
    local okList, cats = pcall(GetCategoryList)
    if not okList or type(cats) ~= "table" then return out end
    local seen = 0
    for ci = 1, #cats do
        local catID = cats[ci]
        local okName, catName, parentID = pcall(GetCategoryInfo, catID)
        out.categories[#out.categories + 1] = {
            id = catID,
            name = okName and tostring(catName) or nil,
            parent = okName and parentID or nil,
        }
        local okNum, num = pcall(GetCategoryNumAchievements, catID)
        if okNum and type(num) == "number" then
            for ai = 1, num do
                if seen >= MAX_ENTRIES then return out end
                local ok, id, name, points, completed = pcall(GetAchievementInfo, catID, ai)
                if ok and id then
                    local entry = {
                        id = id,
                        category = catID,
                        name = tostring(name),
                        points = tonumber(points) or 0,
                        completed = completed and true or false,
                    }
                    local okC, nCrit = pcall(GetAchievementNumCriteria, id)
                    if okC and type(nCrit) == "number" and nCrit > 0 then
                        entry.criteria = {}
                        for k = 1, nCrit do
                            local okK, cname, _, done, have, need = pcall(GetAchievementCriteriaInfo, id, k)
                            if okK then
                                entry.criteria[k] = {
                                    name = tostring(cname),
                                    done = done and true or false,
                                    have = tonumber(have) or 0,
                                    need = tonumber(need) or 0,
                                }
                            end
                        end
                    end
                    out.entries[#out.entries + 1] = entry
                    out.total = out.total + 1
                    if entry.completed then out.earned = out.earned + 1 end
                    seen = seen + 1
                end
            end
        end
    end
    return out
end

--[[
    Reward names arrive empty for some tiers -- measured on Forever, the 15-point toy came back
    with no name while the pet, tabard and mount resolved. That is the usual cold item cache, so
    it is filled in with Item:CreateFromItemID + ContinueOnItemLoad rather than a blocking
    GetItemInfo, and WN_LEGACY_UPDATED is re-emitted once a name lands so the UI repaints.
]]
local function ResolveMissingRewardNames(addon, track)
    if not track or type(Item) ~= "table" or not Item.CreateFromItemID then return end
    for ti = 1, #(track.tiers or {}) do
        local tier = track.tiers[ti]
        for ri = 1, #(tier.rewards or {}) do
            local reward = tier.rewards[ri]
            if reward and reward.itemID and (not reward.name or reward.name == "") then
                local item = Item:CreateFromItemID(reward.itemID)
                if item and not item:IsItemEmpty() then
                    item:ContinueOnItemLoad(function()
                        local resolved = item:GetItemName()
                        if type(resolved) == "string" and resolved ~= "" then
                            reward.name = resolved
                            local events = ns.Constants and ns.Constants.EVENTS
                            if events and events.LEGACY_UPDATED and addon.SendMessage then
                                addon:SendMessage(events.LEGACY_UPDATED)
                            end
                        end
                    end)
                end
            end
        end
    end
end

--- Collect and persist. Returns the stored table, or nil when this client has no Legacy System.
function WarbandNexus:ScanLegacyProgress()
    if self.SupportsFeature and not self:SupportsFeature("legacy") then return nil end
    if not self.db or not self.db.global then return nil end

    local legacyTrack = ReadRenownTrack(LEGACY_FACTION_ID)
    if not legacyTrack or legacyTrack.name == "" then return nil end

    local store = {
        scannedAt = time(),
        track = legacyTrack,
        pvpRank = ReadRenownTrack(PVP_RANK_FACTION_ID),
        challenges = ReadChallenges(),
    }
    self.db.global.legacy = store
    ResolveMissingRewardNames(self, legacyTrack)

    local events = ns.Constants and ns.Constants.EVENTS
    if events and events.LEGACY_UPDATED and self.SendMessage then
        self:SendMessage(events.LEGACY_UPDATED)
    end
    return store
end

--- Read-only accessor for UI: never scans, so a paint can never stall on the achievement walk.
function WarbandNexus:GetLegacyProgress()
    return self.db and self.db.global and self.db.global.legacy or nil
end

--- Next unearned reward tier, for a "what am I working toward" line.
function WarbandNexus:GetNextLegacyReward()
    local store = self:GetLegacyProgress()
    local track = store and store.track
    if not track or not track.tiers then return nil end
    for i = 1, #track.tiers do
        local tier = track.tiers[i]
        if tier.level and tier.level > (track.level or 0) then
            return tier
        end
    end
    return nil
end
