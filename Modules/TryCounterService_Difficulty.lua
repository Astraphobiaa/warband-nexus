--[[
    Warband Nexus - Try Counter difficulty gating (split from TryCounterService.lua, 2026-10-22)
    DifficultyID -> dropDifficulty labels, live / encounter difficulty resolution, drop filtering
    and the difficulty debug lines. Loaded after TryCounterService.lua; uses
    ns.TryCounter.Runtime + TC.Fns.
]]

local _, ns = ...

local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime

assert(Fns and RT and RT.tryCounterInstanceDiffCache, "TryCounterService_Difficulty: load TryCounterService.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local tryCounterInstanceDiffCache = RT.tryCounterInstanceDiffCache

local GetTime = GetTime
local format = string.format
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

-- Maps WoW difficultyID (from ENCOUNTER_END / GetRaidDifficultyID / GetDungeonDifficultyID)
-- to our dropDifficulty label strings.  Complete as of Patch 12.0.5 (May 2026).
-- https://warcraft.wiki.gg/wiki/DifficultyID
-- Regression: tests/test_trycounter.lua mirrors this table plus ResolveDifficultyLabel, DoesDifficultyMatch, FilterDropsByDifficulty.
local DIFFICULTY_ID_TO_LABELS = {
    -- Mythic tier
    [16]  = "Mythic",   -- Mythic raid
    [23]  = "Mythic",   -- Mythic dungeon
    [8]   = "Mythic",   -- Mythic Keystone
    -- Heroic tier
    [15]  = "Heroic",   -- Heroic raid
    [2]   = "Heroic",   -- Heroic dungeon
    [5]   = "Heroic",   -- 10-player Heroic (legacy)
    [6]   = "25H",      -- 25-player Heroic (legacy)
    [24]  = "Heroic",   -- Timewalking dungeon
    [236] = "Heroic",   -- Lorewalking dungeon
    -- Normal tier
    [14]  = "Normal",   -- Normal raid (flex)
    [1]   = "Normal",   -- Normal dungeon
    [3]   = "10N",      -- 10-player Normal (legacy)
    [4]   = "25N",      -- 25-player Normal (legacy)
    [9]   = "Normal",   -- 40-player raid (MC, BWL, AQ40, Naxx)
    [33]  = "Normal",   -- Timewalking raid
    [150] = "Normal",   -- Normal dungeon (alternate)
    [172] = "Normal",   -- World Boss
    [205] = "Normal",   -- Follower dungeon
    [216] = "Normal",   -- Quest (party) — Midnight leveling/quest dungeons
    [208] = "Normal",   -- Delves
    [220] = "Normal",   -- Story raid (solo)
    [241] = "Normal",   -- Lorewalking raid
    -- LFR tier
    [7]   = "LFR",      -- Looking for Raid (legacy, pre-SoO)
    [17]  = "LFR",      -- Looking for Raid (flex)
    [151] = "LFR",      -- Looking for Raid (Timewalking)
    -- Event tier (holiday bosses, world events)
    [18]  = "Normal",   -- Event raid
    [19]  = "Normal",   -- Event dungeon
    [232] = "Normal",   -- Event dungeon (alternate)
}
-- Bind onto RT here (not in the early RT.* block ~line 2045) so the satellite files
-- (TryCounterService_Loot.lua difficulty-skip path) get the real table, not nil.
RT.DIFFICULTY_ID_TO_LABELS = DIFFICULTY_ID_TO_LABELS

function Fns.ResolveDifficultyLabel(difficultyID)
    if not difficultyID or type(difficultyID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(difficultyID) then return nil end
    local mapped = DIFFICULTY_ID_TO_LABELS[difficultyID]
    if mapped then return mapped end
    if _G.GetDifficultyInfo then
        local ok, _, _, isHeroic, isChallengeMode, _, displayMythic, _, isLFR = pcall(_G.GetDifficultyInfo, difficultyID)
        if ok and isLFR then
            return "LFR"
        end
        if ok and isChallengeMode then
            return "Mythic"
        end
        if ok and displayMythic then
            return "Mythic"
        end
        if ok and isHeroic then
            return "Heroic"
        end
    end
    return nil
end

function Fns.ResolveLiveInstanceDifficultyID(instanceType, giDifficulty)
    local d = giDifficulty
    if d and issecretvalue and issecretvalue(d) then d = nil end
    if type(d) == "number" and d > 0 then return d end

    local it = instanceType
    if it and issecretvalue and issecretvalue(it) then it = nil end

    if it == "party" then
        local CCM = C_ChallengeMode
        if CCM and CCM.GetActiveKeystoneInfo then
            local level = select(1, CCM.GetActiveKeystoneInfo())
            if level and not (issecretvalue and issecretvalue(level)) and type(level) == "number" and level > 0 then
                return 8 -- Mythic Keystone
            end
        end
        local dd = GetDungeonDifficultyID and GetDungeonDifficultyID()
        if dd and not (issecretvalue and issecretvalue(dd)) and type(dd) == "number" and dd > 0 then
            return dd
        end
    elseif it == "raid" then
        local rd = GetRaidDifficultyID and GetRaidDifficultyID()
        if rd and not (issecretvalue and issecretvalue(rd)) and type(rd) == "number" and rd > 0 then
            return rd
        end
    elseif it == "scenario" then
        -- Megadungeons (Mechagon, Dawn of the Infinite) report instanceType "scenario"; use dungeon difficulty.
        local dd = GetDungeonDifficultyID and GetDungeonDifficultyID()
        if dd and not (issecretvalue and issecretvalue(dd)) and type(dd) == "number" and dd > 0 then
            return dd
        end
    end
    return nil
end

local function MatchSingleDifficulty(label, requiredDifficulty, difficultyID)
    if requiredDifficulty == "Timewalking" then
        return difficultyID == 24 or difficultyID == 33 or difficultyID == 151 or label == "Timewalking"
    elseif requiredDifficulty == "Mythic" then
        return label == "Mythic"
    elseif requiredDifficulty == "Heroic" then
        -- Threshold: Heroic+ (Heroic, Mythic, legacy 25H) — matches standard "drops on Heroic or higher" mounts
        -- like Invincible's Reins (25H only, covered by "25H" explicit) or Life-Binder's Handmaiden (Heroic+).
        return label == "Heroic" or label == "Mythic" or label == "25H"
    elseif requiredDifficulty == "25H" then
        return label == "25H"
    elseif requiredDifficulty == "Normal" then
        -- Flex Normal / Heroic / Mythic raid & legacy sizes — excludes LFR/TW-LFR.
        return label == "Normal" or label == "Heroic" or label == "Mythic" or label == "10N" or label == "25N"
    elseif requiredDifficulty == "10N" then
        return label == "10N"
    elseif requiredDifficulty == "25N" then
        return label == "25N"
    elseif requiredDifficulty == "25-man" then
        -- Legacy 25-player (or flex Ulduar Normal); e.g. Ulduar Mimiron's Head.
        return label == "25N" or label == "25H" or label == "Normal"
    elseif requiredDifficulty == "LFR" then
        return label == "LFR"
    end
    return false
end

function Fns.DoesDifficultyMatch(difficultyID, requiredDifficulty)
    if not requiredDifficulty or requiredDifficulty == "All Difficulties" then
        return true
    end
    if not difficultyID then return false end
    if issecretvalue and issecretvalue(difficultyID) then return false end

    -- Timewalking gate: matches ONLY Timewalking instances (dungeon 24, raid 33, LFR 151).
    if requiredDifficulty == "Timewalking" then
        return difficultyID == 24 or difficultyID == 33 or difficultyID == 151
    end

    local label = Fns.ResolveDifficultyLabel(difficultyID)
    if not label then return false end

    -- Array form: explicit whitelist (OR across entries, no threshold expansion).
    if type(requiredDifficulty) == "table" then
        for i = 1, #requiredDifficulty do
            local req = requiredDifficulty[i]
            if type(req) == "string" then
                if req == "Timewalking" then
                    if difficultyID == 24 or difficultyID == 33 or difficultyID == 151 then
                        return true
                    end
                elseif MatchSingleDifficulty(label, req, difficultyID) then
                    return true
                end
            end
        end
        return false
    end

    return MatchSingleDifficulty(label, requiredDifficulty, difficultyID)
end

--- Chat segment for a drop's difficulty requirement ([WN-Drops] lines).
--- Array form lists every accepted difficulty and greens only the one the player is currently in;
--- the others are gray ("drops there too, you are just not in it"). Red is reserved for a single
--- gate the player fails, amber for "current difficulty unknown".
---@param reqDiff string|table|nil
---@param encDiff number|nil
---@return string
function Fns.FormatDropDifficultySegment(reqDiff, encDiff)
    if not reqDiff or reqDiff == "All Difficulties" then return "|cff888888\226\128\148|r" end
    local label = nil
    if encDiff and not (issecretvalue and issecretvalue(encDiff)) then
        label = Fns.ResolveDifficultyLabel(encDiff)
    end
    if type(reqDiff) == "table" then
        local parts = {}
        for i = 1, #reqDiff do
            local d = reqDiff[i]
            if type(d) == "string" then
                -- Exact label compare, not DoesDifficultyMatch: "Heroic" is a threshold that also
                -- matches Mythic, which would green both entries while standing in Mythic.
                local color = "|cffffaa00"
                if label or encDiff then
                    if d == "Timewalking" then
                        color = (encDiff == 24 or encDiff == 33 or encDiff == 151) and "|cff00ff00" or "|cff888888"
                    else
                        color = (label == d) and "|cff00ff00" or "|cff888888"
                    end
                end
                parts[#parts + 1] = color .. d .. "|r"
            end
        end
        if #parts == 0 then return "|cff888888\226\128\148|r" end
        return "(" .. table.concat(parts, "/") .. ")"
    end
    if not label and not encDiff then return "(|cffffaa00" .. reqDiff .. "|r)" end
    local color = Fns.DoesDifficultyMatch(encDiff, reqDiff) and "|cff00ff00" or "|cffff6666"
    return "(" .. color .. reqDiff .. "|r)"
end

function Fns.ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    -- Priority 0: ENCOUNTER_START cache (captured at pull, typically non-secret in Midnight 12.0).
    -- This beats GetInstanceInfo because it persists through the brief secret-value window that
    -- can wrap GetInstanceInfo return values during active encounters.
    if RT.currentEncounterCache.difficultyID
        and type(RT.currentEncounterCache.difficultyID) == "number"
        and RT.currentEncounterCache.difficultyID > 0
        and RT.currentEncounterCache.startTime > 0
        and (GetTime() - RT.currentEncounterCache.startTime) <= RT.ENCOUNTER_CACHE_TTL then
        return RT.currentEncounterCache.difficultyID
    end

    if inInstance then
        local _, typ, liveDiff, _, _, _, _, iid = GetInstanceInfo()
        local safeIid = iid
        if safeIid and issecretvalue and issecretvalue(safeIid) then safeIid = nil end
        local safeLive = liveDiff
        if safeLive and issecretvalue and issecretvalue(safeLive) then safeLive = nil end
        local resolvedLive = Fns.ResolveLiveInstanceDifficultyID(typ, safeLive)
        if tryCounterInstanceDiffCache.instanceID and safeIid
            and tryCounterInstanceDiffCache.instanceID == safeIid
            and tryCounterInstanceDiffCache.difficultyID
            and tryCounterInstanceDiffCache.difficultyID > 0 then
            return tryCounterInstanceDiffCache.difficultyID
        end
        if resolvedLive then
            return resolvedLive
        end
    end
    if recentKillDiff and not (issecretvalue and issecretvalue(recentKillDiff)) then
        return recentKillDiff
    end
    -- No guess past this point. The old last resort was GetRaidDifficultyID() or GetDungeonDifficultyID(),
    -- but the raid preference is always a number (warcraft.wiki.gg API_GetRaidDifficultyID), so inside a
    -- 5-man it returned e.g. 14 and gated Heroic / Mythic dungeon drops out. Unknown fails closed.
    return nil
end

function Fns.ResolveEncounterDifficultyForLootGating(inInstance, recentKillDiff, liveDifficultyID)
    local d = Fns.ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    if d and issecretvalue and issecretvalue(d) then
        d = nil
    end
    if not d and liveDifficultyID and not (issecretvalue and issecretvalue(liveDifficultyID)) then
        d = liveDifficultyID
    end
    if not d and inInstance then
        local _, _, liveDiff = GetInstanceInfo()
        if liveDiff and not (issecretvalue and issecretvalue(liveDiff)) then
            d = liveDiff
        end
    end
    return d
end

function Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    local trackable = {}
    local diffSkipped = nil
    if not drops then return trackable, diffSkipped end
    local npcDropDifficulty = drops.dropDifficulty
    local npcDifficultyIDs = drops.difficultyIDs
    for i = 1, #drops do
        local drop = drops[i]
        local reqDiff = drop.dropDifficulty or npcDropDifficulty
        local reqDiffIDs = drop.difficultyIDs or npcDifficultyIDs
        local diffOk = true
        if reqDiff then
            if encounterDiffID then
                diffOk = Fns.DoesDifficultyMatch(encounterDiffID, reqDiff)
            else
                -- Fail-closed by default when difficulty is unknown (prevents Mythic mount +1 on Normal).
                -- Exception: Mythic-only drops in scenario megadungeons (Mechagon, DotI) — no per-boss
                -- kill statistic and GetInstanceInfo difficulty is often nil; these instances are Mythic-only.
                -- Multi-return trap: `X and X()` truncates to one value, dropping instType (Lua 5.1).
                -- Guard the call separately so both returns survive.
                local inInst, instType
                if Fns.GetTryCounterInstanceType then
                    inInst, instType = Fns.GetTryCounterInstanceType()
                end
                if inInst and instType == "scenario" and reqDiff == "Mythic" then
                    diffOk = true
                else
                    diffOk = false
                end
            end
        end
        -- difficultyIDs whitelist: when present, encounter difficultyID MUST be in the list.
        -- Required because the "Mythic" label aliases multiple WoW IDs (16 = Mythic raid,
        -- 8 = Mythic Keystone, 23 = Mythic dungeon). Same npcID can appear in M+ dungeon
        -- AND raid (e.g. Midnight Falls — npcID 214650 in March on Quel'Danas Mythic raid vs the
        -- same npcID appearing in M+ Mythic dungeon contexts); the raid-only
        -- mount must not increment on M+ kills.
        if diffOk and reqDiffIDs and type(reqDiffIDs) == "table" and #reqDiffIDs > 0 then
            if not encounterDiffID or (issecretvalue and issecretvalue(encounterDiffID)) then
                diffOk = false
            else
                local match = false
                for j = 1, #reqDiffIDs do
                    if reqDiffIDs[j] == encounterDiffID then match = true; break end
                end
                diffOk = match
            end
        end
        if diffOk then
            if drop.repeatable or not Fns.IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        elseif not diffSkipped and reqDiff ~= "Timewalking" then
            diffSkipped = { drop = drop, required = reqDiff }
        end
    end

    -- Per-drop instance MapID exclusions (GetInstanceInfo index 8): same npcID reused across
    -- unrelated instances (e.g. Legion Seat of the Triumvirate vs Midnight raid Midnight Falls).
    if #trackable > 0 then
        local mapInstanceID = select(8, GetInstanceInfo())
        -- issecretvalue first: comparing a secret (`> 0`) throws in tainted code.
        if mapInstanceID and not (issecretvalue and issecretvalue(mapInstanceID))
            and type(mapInstanceID) == "number" and mapInstanceID > 0 then
            local filtered = {}
            for ti = 1, #trackable do
                local drop = trackable[ti]
                local excl = drop and drop.excludeInstanceIDs
                local skip = false
                if type(excl) == "table" then
                    for ei = 1, #excl do
                        if excl[ei] == mapInstanceID then
                            skip = true
                            break
                        end
                    end
                end
                if not skip then
                    filtered[#filtered + 1] = drop
                end
            end
            trackable = filtered
        end
    end

    return trackable, diffSkipped
end

function Fns.DebugLogDifficultyFilterEmpty(WN, context, drops, encounterDiffID, trackable, diffSkipped)
    if not WN or not Fns.IsTryCounterLootDebugEnabled(WN) then return end
    if trackable and #trackable > 0 then return end
    local label = Fns.ResolveDifficultyLabel(encounterDiffID)
    local req = diffSkipped and diffSkipped.required or (drops and drops.dropDifficulty) or "?"
    local drop = diffSkipped and diffSkipped.drop
    local collected = (drop and Fns.IsCollectibleCollected(drop)) and "yes" or "no"
    local encStr = (encounterDiffID ~= nil) and tostring(encounterDiffID) or "nil"
    local labelStr = label or "nil"
    local tmpl = (ns.L and ns.L["TRYCOUNTER_DIFF_FILTER_DEBUG"])
        or "Difficulty filter: no trackable drops (encDiff=%s, label=%s, required=%s, collected=%s)."
    WN:Print("|cff9370DB[WN-TC]|r " .. format(tmpl, encStr, labelStr, tostring(req), collected)
        .. " [" .. tostring(context) .. "]")
end

function Fns.TryCounterProbeRequirementText(reqDiff)
    local L = ns.L
    if not reqDiff or reqDiff == "" or reqDiff == "All Difficulties" then
        return (L and L["TRYCOUNTER_PROBE_REQ_ANY"]) or "any difficulty"
    end
    if reqDiff == "Mythic" then return (L and L["TRYCOUNTER_PROBE_REQ_MYTHIC"]) or "Mythic only" end
    if reqDiff == "LFR" then return (L and L["TRYCOUNTER_PROBE_REQ_LFR"]) or "LFR only" end
    if reqDiff == "Normal" then return (L and L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"]) or "Normal+ raid (not LFR)" end
    if reqDiff == "Heroic" then return (L and L["TRYCOUNTER_PROBE_REQ_HEROIC"]) or "Heroic+ (includes Mythic & 25H)" end
    if reqDiff == "25H" then return (L and L["TRYCOUNTER_PROBE_REQ_25H"]) or "25-player Heroic only" end
    if reqDiff == "10N" then return (L and L["TRYCOUNTER_PROBE_REQ_10N"]) or "10-player Normal only" end
    if reqDiff == "25N" then return (L and L["TRYCOUNTER_PROBE_REQ_25N"]) or "25-player Normal only" end
    if reqDiff == "25-man" then return (L and L["TRYCOUNTER_PROBE_REQ_25MAN"]) or "25-player Normal or Heroic" end
    if reqDiff == "Timewalking" then return (L and L["TRYCOUNTER_PROBE_REQ_TIMEWALKING"]) or "Timewalking only" end
    return tostring(reqDiff)
end

function Fns.TryCounterDebugEmitMountProbeLine(WN, encName, ann, drop, npcDropDifficulty, effDiff)
    if not WN or not ann or not drop then return end
    local L = ns.L
    local reqDiff = drop.dropDifficulty or npcDropDifficulty
    local reqText = Fns.TryCounterProbeRequirementText(reqDiff)
    local diffUnknown = not effDiff or (issecretvalue and issecretvalue(effDiff))
    local diffMatches = not diffUnknown
        and (not reqDiff or reqDiff == "All Difficulties" or Fns.DoesDifficultyMatch(effDiff, reqDiff))
    local collectedNonRepeat = (not drop.repeatable) and Fns.IsCollectibleCollected(drop)
    local statusText
    if collectedNonRepeat then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_COLLECTED"]) or "Already collected"
    elseif diffUnknown then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"]) or "Difficulty unknown"
    elseif not diffMatches then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"]) or "Not available on current difficulty"
    else
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"]) or "Obtainable on current difficulty"
    end
    local mountDisp = tostring(ann.name or "?")
    local lineFmt = (L and L["TRYCOUNTER_PROBE_MOUNT_LINE"])
        or "%s > %s > %s > %s"
    local line = format(lineFmt,
        tostring(encName or "?"),
        mountDisp,
        reqText,
        statusText)
    Fns.TryCounterLootDebug(WN, "flow", "%s", line)
end
