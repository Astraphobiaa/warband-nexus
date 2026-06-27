--[[
    Warband Nexus - PvE Great Vault grid paint + tooltip helpers.
    Split from PvEUI.lua (ops-037).
    Loaded before Modules/UI/PvEUI.lua.
]]

local _, ns = ...
ns.PvEUI = ns.PvEUI or {}
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local ApplyVisuals = ns.UI_ApplyVisuals
local COLORS = ns.UI_COLORS
local FormatNumber = ns.UI_FormatNumber or function(n)
    local num = tonumber(n)
    if num == nil then return "0" end
    return tostring(num)
end

local VAULT_SLOT_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local VAULT_SLOT_CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
local VAULT_SLOT_UPARROW = "|A:loottoast-arrow-green:12:12|a"
local issecretvalue = issecretvalue

local function SafeVaultNumber(v, default)
    default = default or 0
    if v == nil then return default end
    if issecretvalue and issecretvalue(v) then return default end
    return tonumber(v) or default
end

local function SafeStorageKey(s)
    if not s or s == "" then return nil end
    if issecretvalue and issecretvalue(s) then return nil end
    return s
end

local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

local function BindForwardScrollWheel(frame)
    local fwd = ns.UI_ForwardMouseWheelToScrollAncestor
    if not frame or not fwd then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        fwd(self, delta)
    end)
end

local function VaultRGB3(r, g, b)
    return { r, g, b }
end

local function VaultSpacerColor()
    local r, g, b = 0.3, 0.3, 0.3
    if ns.UI_GetTextRoleRGB then
        r, g, b = ns.UI_GetTextRoleRGB("Dim")
    end
    return VaultRGB3(r, g, b)
end

local function VaultMutedLineColor()
    local r, g, b = 0.4, 0.4, 0.4
    if ns.UI_GetTextRoleRGB then
        r, g, b = ns.UI_GetTextRoleRGB("Muted")
    end
    return VaultRGB3(r, g, b)
end

local function VaultDimLineColor()
    local r, g, b = 0.5, 0.5, 0.5
    if ns.UI_GetTextRoleRGB then
        r, g, b = ns.UI_GetTextRoleRGB("Dim")
    end
    return VaultRGB3(r, g, b)
end

local function VaultCompleteLineColor()
    if ns.UI_GetSemanticGreenColor then
        local r, g, b = ns.UI_GetSemanticGreenColor()
        return VaultRGB3(r, g, b)
    end
    return VaultRGB3(0.5, 1, 0.5)
end

local function VaultInfoLineColor()
    local c = ns.UI_COLORS and ns.UI_COLORS.accent
    if c then
        return VaultRGB3(c[1] * 0.55 + 0.35, c[2] * 0.55 + 0.55, c[3] * 0.55 + 0.85)
    end
    return VaultRGB3(0.63, 0.82, 1)
end

local function VaultBrightHex()
    if ns.UI_GetBrightHex then return ns.UI_GetBrightHex() end
    if ns.UI_GetTextRoleHex then return ns.UI_GetTextRoleHex("Bright") end
    return "|cffeeeeee"
end

local function VaultBrightColor()
    if ns.UI_GetTextRoleRGB then
        local r, g, b = ns.UI_GetTextRoleRGB("Bright")
        return VaultRGB3(r, g, b)
    end
    return VaultRGB3(1, 1, 1)
end

local function VaultGoldHex()
    if ns.UI_GetSemanticGoldHex then return ns.UI_GetSemanticGoldHex() end
    return "|cffffd700"
end


--[[
    Determine if a vault activity slot is at maximum completion level
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name ("Raid", "M+", "World", "PvP")
    @return boolean - True if at maximum level, false otherwise
]]
local function IsVaultSlotAtMax(activity, typeName)
    if not activity then
        return false
    end
    local level = SafeVaultNumber(activity.level, nil)
    if level == nil then
        return false
    end
    
    -- Define max thresholds per activity type
    if typeName == "Raid" then
        -- DifficultyIDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
        return level == 16 -- Only Mythic is max
    elseif typeName == "M+" then
        -- For M+: 0=Mythic 0 (base mythic), 2+=Keystone level
        -- Max is keystone level 10 or higher
        return level >= 10
    elseif typeName == "World" then
        -- For World/Delves, Tier 8 is max
        return level >= 8
    elseif typeName == "PvP" then
        -- PvP has no tier progression
        return true
    end
    
    return false
end

--- Canonical PvE cache key for a character row (matches GetPvEData / pveCache writes).
function ns.PvEUI.GetCanonicalKeyForChar(char)
    if not char then return nil end
    if ns.Utilities and ns.Utilities.ResolveCharacterRowKey then
        local rk = ns.Utilities:ResolveCharacterRowKey(char)
        rk = SafeStorageKey(rk)
        if rk then
            if ns.Utilities.GetCanonicalCharacterKey then
                return ns.Utilities:GetCanonicalCharacterKey(rk) or rk
            end
            return rk
        end
    end
    local raw = SafeStorageKey(char._key)
    if not raw and ns.UI_GetCharKey then
        raw = SafeStorageKey(ns.UI_GetCharKey(char))
    end
    if not raw then return nil end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
    end
    return raw
end

--- Completed slot but reward can still improve (API iLvl or difficulty/M+ tier ceiling).
local function PvE_SlotShowsVaultUpgrade(act, typeName)
    if not act then return false end
    local ni = SafeVaultNumber(act.nextLevelIlvl, 0)
    if ni > 0 then return true end
    local th = SafeVaultNumber(act.threshold, 0)
    local prog = SafeVaultNumber(act.progress, 0)
    if th <= 0 or prog < th then return false end
    if IsVaultSlotAtMax(act, typeName) then return false end
    return true
end

--- Vault tracker column display (shared with Easy Access; Shift shows remaining events only).
function ns.PvEUI.FormatVaultTrackColumn(activityList, slotCount, typeName, vaultLootClaimable, _)
    if ns.VaultFormatCategoryColumn and ns.VaultSlotsFromActivityList then
        local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        local vb = profile and profile.vaultButton or {}
        local slots, catKey = ns.VaultSlotsFromActivityList(activityList, slotCount, typeName)
        return ns.VaultFormatCategoryColumn(slots, catKey, {
            shiftHeld = IsShiftKeyDown and IsShiftKeyDown(),
            showRewardProgress = vb.showRewardProgress == true,
            showRewardItemLevel = vb.showRewardItemLevel == true,
            vaultLootClaimable = vaultLootClaimable == true,
        })
    end
    local READY = VAULT_SLOT_CHECK
    local NOT_READY = VAULT_SLOT_CROSS
    local GREEN_ARROW = VAULT_SLOT_UPARROW
    local readyClaimLabel = GetLocalizedText("VAULT_READY_TO_CLAIM", "Ready")
    if vaultLootClaimable then
        return "|cff44ff44" .. readyClaimLabel .. "|r"
    end
    slotCount = slotCount or 3
    if slotCount < 1 then slotCount = 3 end
    local parts = {}
    for s = 1, slotCount do
        local act = activityList and activityList[s]
        local th = SafeVaultNumber(act and act.threshold, 0)
        local prog = SafeVaultNumber(act and act.progress, 0)
        local complete = (th > 0 and prog >= th)
        if not complete then
            parts[s] = NOT_READY
        elseif PvE_SlotShowsVaultUpgrade(act, typeName) then
            parts[s] = GREEN_ARROW
        else
            parts[s] = READY
        end
    end
    return table.concat(parts, " ")
end

--- All slots in one vault track meet threshold (weekly objectives done for that row).
local function PvE_VaultTrackSlotsAllComplete(activityList, slotCount)
    slotCount = tonumber(slotCount) or 0
    if slotCount < 1 then return false end
    for s = 1, slotCount do
        local act = activityList and activityList[s]
        local th = SafeVaultNumber(act and act.threshold, 0)
        local prog = SafeVaultNumber(act and act.progress, 0)
        if th <= 0 or prog < th then
            return false
        end
    end
    return true
end

--- Raid + M+ + World tracks all slots complete (same idea as full vault grid filled).
local function PvE_AllVaultTracksComplete(vaultActs)
    if not vaultActs then return false end
    local raidT = vaultActs.raids and #vaultActs.raids or 3
    local dT = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
    local wT = vaultActs.world and #vaultActs.world or 3
    return PvE_VaultTrackSlotsAllComplete(vaultActs.raids, raidT)
        and PvE_VaultTrackSlotsAllComplete(vaultActs.mythicPlus, dT)
        and PvE_VaultTrackSlotsAllComplete(vaultActs.world, wT)
end

--[[
    Get reward item level from activity data or calculate fallback
    @param activity table - Activity data from Great Vault
    @return number|nil - Item level or nil if unavailable
]]
local function GetRewardItemLevel(activity)
    if not activity then
        return nil
    end
    
    -- Priority: Use rewardItemLevel field (extracted from C_WeeklyRewards.GetExampleRewardItemHyperlinks)
    if activity.rewardItemLevel then
        local rewardIlvl = SafeVaultNumber(activity.rewardItemLevel, 0)
        if rewardIlvl > 0 then
            return rewardIlvl
        end
    end
    
    return nil
end

--[[
    Get next tier/difficulty name for upgrade display
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name
    @return string|nil - Next tier/difficulty name (e.g., "Tier 2", "+6", "Mythic")
]]
local function GetNextTierName(activity, typeName)
    if not activity then
        return nil
    end
    local currentLevel = SafeVaultNumber(activity.level, nil)
    if currentLevel == nil then
        return nil
    end
    
    local mythicLabel = GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")
    local heroicLabel = GetLocalizedText("DIFFICULTY_HEROIC", "Heroic")
    local normalLabel = GetLocalizedText("DIFFICULTY_NORMAL", "Normal")
    local tierFmt = GetLocalizedText("TIER_FORMAT", "Tier %d")
    
    -- World/Delves tier progression (Tier 1-8)
    if typeName == "World" then
        if currentLevel >= 8 then
            return nil -- Already at max (Tier 8)
        end
        return string.format(tierFmt, currentLevel + 1)
    end
    
    -- Raid difficulty progression: LFR(17) → Normal(14) → Heroic(15) → Mythic(16)
    if typeName == "Raid" then
        if currentLevel == 16 then
            return nil -- Already at Mythic (max)
        elseif currentLevel == 15 then
            return mythicLabel
        elseif currentLevel == 14 then
            return heroicLabel
        elseif currentLevel == 17 then
            return normalLabel
        end
    end
    
    -- M+ keystone progression: 0=Mythic 0, 2+=Keystone level → Tier X
    if typeName == "M+" or typeName == "Dungeon" then
        if currentLevel >= 10 then
            return nil
        end
        local nextLevel = currentLevel + 1
        if currentLevel == 0 then
            nextLevel = 2
        end
        return string.format(tierFmt, nextLevel)
    end
    
    return nil
end

--[[
    Get maximum tier/difficulty name
    @param typeName string - Activity type name
    @return string|nil - Max tier/difficulty name
]]
local function GetMaxTierName(typeName)
    local tierFmt = GetLocalizedText("TIER_FORMAT", "Tier %d")
    if typeName == "World" then
        return string.format(tierFmt, 8)
    elseif typeName == "Raid" then
        return GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")
    elseif typeName == "M+" or typeName == "Dungeon" then
        return string.format(tierFmt, 10)
    elseif typeName == "PvP" then
        return nil -- PvP has no progression
    end
    return nil
end

--[[
    Get display text for vault activity completion
    @param activity table - Activity data
    @param typeName string - Activity type name
    @return string - Display text for the activity (e.g., "Heroic", "+7", "Tier 1")
]]
local function GetVaultActivityDisplayText(activity, typeName)
    local unknownLabel = GetLocalizedText("UNKNOWN", "Unknown")
    local mythicLabel = GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")
    local heroicLabel = GetLocalizedText("DIFFICULTY_HEROIC", "Heroic")
    local normalLabel = GetLocalizedText("DIFFICULTY_NORMAL", "Normal")
    local lfrLabel = GetLocalizedText("DIFFICULTY_LFR", "LFR")
    local tierFmt = GetLocalizedText("TIER_FORMAT", "Tier %d")
    local pvpLabel = GetLocalizedText("PVP_TYPE", "PvP")
    
    if not activity then
        return unknownLabel
    end
    
    if typeName == "Raid" then
        local difficulty = unknownLabel
        local raidLevel = SafeVaultNumber(activity.level, nil)
        if raidLevel then
            -- Raid difficultyIDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
            -- Use exact matches — LFR (17) > Mythic (16) by ID
            if raidLevel == 16 then
                difficulty = mythicLabel
            elseif raidLevel == 15 then
                difficulty = heroicLabel
            elseif raidLevel == 14 then
                difficulty = normalLabel
            elseif raidLevel == 17 then
                difficulty = lfrLabel
            end
        end
        return difficulty
    elseif typeName == "M+" or typeName == "Dungeon" then
        local level = SafeVaultNumber(activity.level, 0)
        if level == 0 then
            return mythicLabel .. " 0"
        else
            return string.format(tierFmt, level)
        end
    elseif typeName == "World" then
        local tier = SafeVaultNumber(activity.level, 1)
        return string.format(tierFmt, tier)
    elseif typeName == "PvP" then
        return pvpLabel
    end
    
    return typeName
end

--[[
    Build raid encounter lines for vault tooltips using cached GetActivityEncounterInfo data.
    Blizzard pattern: sorts by instanceID then uiOrder, groups by instance, shows bestDifficulty.
    @param lines table - Tooltip lines array to append to
    @param encounters table - Array of cached encounter info from PvECacheService
]]
local function BuildRaidEncounterLines(lines, encounters)
    if not encounters or #encounters == 0 then return end
    
    -- Sort: completed first within same instance, then by uiOrder (matches Blizzard EncountersSort)
    local sorted = {}
    for i = 1, #encounters do
        sorted[#sorted + 1] = encounters[i]
    end
    table.sort(sorted, function(a, b)
        if (a.instanceID or 0) ~= (b.instanceID or 0) then
            return (a.instanceID or 0) < (b.instanceID or 0)
        end
        local aCompleted = (a.bestDifficulty or 0) > 0
        local bCompleted = (b.bestDifficulty or 0) > 0
        if aCompleted ~= bCompleted then
            return aCompleted
        end
        return (a.uiOrder or 0) < (b.uiOrder or 0)
    end)
    
    local lastInstanceID = nil
    local encounterListLabel = GetLocalizedText("VAULT_ENCOUNTER_LIST_FORMAT", "%s")
    for i = 1, #sorted do
        local enc = sorted[i]
        if (enc.instanceID or 0) ~= (lastInstanceID or 0) then
            table.insert(lines, { text = " ", color = VaultSpacerColor() })
            local instName = enc.instanceName or ""
            table.insert(lines, {
                text = string.format("|cffffffcc" .. encounterListLabel .. "|r", instName),
                color = {1, 1, 0.8}
            })
            lastInstanceID = enc.instanceID
        end
        if enc.name then
            if (enc.bestDifficulty or 0) > 0 then
                local diffName = enc.difficultyName or "?"
                table.insert(lines, {
                    text = string.format("  |cff00ff00%s|r |cff888888(%s)|r", enc.name, diffName),
                    color = {0, 1, 0}
                })
            else
                table.insert(lines, {
                    text = string.format("  |cff666666- %s|r", enc.name),
                    color = VaultMutedLineColor()
                })
            end
        end
    end
end

--[[
    Fallback: Build raid boss lines from lockout data when GetActivityEncounterInfo isn't cached.
    Groups lockouts by instance, deduplicates bosses, shows highest difficulty per boss.
    @param lines table - Tooltip lines array to append to
    @param raidLockouts table - Array of raid lockout data from PvECacheService
]]
local DIFF_PRIORITY = { [16] = 4, [23] = 4, [15] = 3, [2] = 3, [14] = 2, [1] = 2, [17] = 1, [7] = 1 }
local function BuildRaidBossLinesFromLockouts(lines, raidLockouts)
    if not raidLockouts or #raidLockouts == 0 then return end

    local instances = {}
    local instanceOrder = {}
    for li = 1, #raidLockouts do
        local lockout = raidLockouts[li]
        if lockout.encounters and lockout.name then
            local instName = lockout.name
            if not instances[instName] then
                instances[instName] = {}
                instanceOrder[#instanceOrder + 1] = instName
            end
            local diff = lockout.difficultyName or "?"
            local prio = DIFF_PRIORITY[lockout.difficulty] or 0
            local bossMap = instances[instName]
            for ei = 1, #lockout.encounters do
                local enc = lockout.encounters[ei]
                if enc.name then
                    local existing = bossMap[enc.name]
                    if not existing then
                        bossMap[enc.name] = {
                            name = enc.name,
                            killed = enc.killed or false,
                            difficulty = diff,
                            priority = prio,
                            order = ei,
                        }
                    elseif enc.killed and (not existing.killed or prio > existing.priority) then
                        existing.killed = true
                        existing.difficulty = diff
                        existing.priority = prio
                    end
                end
            end
        end
    end

    local encounterListLabel = GetLocalizedText("VAULT_ENCOUNTER_LIST_FORMAT", "%s")
    for ii = 1, #instanceOrder do
        local instName = instanceOrder[ii]
        local bossMap = instances[instName]
        if bossMap then
            local bossList = {}
            for _, boss in pairs(bossMap) do
                if type(boss) == "table" and boss.name then
                    bossList[#bossList + 1] = boss
                end
            end
            table.sort(bossList, function(a, b) return (a.order or 0) < (b.order or 0) end)
            if #bossList > 0 then
                table.insert(lines, { text = " ", color = VaultSpacerColor() })
                table.insert(lines, {
                    text = string.format("|cffffffcc" .. encounterListLabel .. "|r", instName),
                    color = {1, 1, 0.8}
                })
                for bi = 1, #bossList do
                    local boss = bossList[bi]
                    if boss.killed then
                        table.insert(lines, {
                            text = string.format("  |cff00ff00%s|r |cff888888(%s)|r", boss.name, boss.difficulty),
                            color = {0, 1, 0}
                        })
                    else
                        table.insert(lines, {
                            text = string.format("  |cff666666- %s|r", boss.name),
                            color = VaultMutedLineColor()
                        })
                    end
                end
            end
        end
    end
end

--[[
    Build dungeon run lines for vault tooltips using Blizzard pattern.
    Uses C_MythicPlus.GetRunHistory for keystone runs + GetNumCompletedDungeonRuns for non-keystone.
    @param lines table - Tooltip lines array to append to
    @param runHistory table|nil - Runs from PvECacheService (keystone only, sorted desc by level)
    @param dungeonRunCounts table|nil - {heroic, mythic, mythicPlus} from GetNumCompletedDungeonRuns
    @param threshold number - Number of top runs to show for this slot
]]
local function BuildDungeonRunLines(lines, runHistory, dungeonRunCounts, threshold)
    if threshold <= 0 then return end
    
    local mythicLabel = GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")
    local heroicLabel = GetLocalizedText("DIFFICULTY_HEROIC", "Heroic")
    local topRunsLabel = GetLocalizedText("VAULT_TOP_RUNS_FORMAT", "Top %d Runs This Week")
    
    table.insert(lines, { text = " ", color = VaultSpacerColor() })
    table.insert(lines, {
        text = string.format("|cffffffcc" .. topRunsLabel .. "|r", threshold),
        color = {1, 1, 0.8}
    })
    
    -- Keystone runs (sorted descending by level)
    local runs = {}
    if runHistory then
        for ri = 1, #runHistory do
            runs[#runs + 1] = runHistory[ri]
        end
    end
    table.sort(runs, function(a, b)
        local aLvl = a.level or 0
        local bLvl = b.level or 0
        if aLvl ~= bLvl then return aLvl > bLvl end
        return (a.mapChallengeModeID or 0) < (b.mapChallengeModeID or 0)
    end)
    
    -- Show keystone runs (Blizzard pattern: level + dungeon name)
    local shown = 0
    for ri = 1, math.min(#runs, threshold) do
        local run = runs[ri]
        local dungeonName = run.dungeon or run.name or ""
        if not dungeonName or dungeonName == "" then
            if run.mapChallengeModeID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                dungeonName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID) or ""
            end
        end
        local lvl = run.level or 0
        local runText
        if lvl > 0 then
            runText = string.format("  %s+%d %s|r", VaultBrightHex(), lvl, dungeonName)
        else
            runText = string.format("  %s%s 0 %s|r", VaultBrightHex(), mythicLabel, dungeonName)
        end
        table.insert(lines, { text = runText, color = VaultBrightColor() })
        shown = shown + 1
    end
    
    -- Fill remaining slots with non-keystone runs (Mythic 0, Heroic) - Blizzard pattern
    local remaining = threshold - shown
    if remaining > 0 and dungeonRunCounts then
        local numMythic = dungeonRunCounts.mythic or 0
        local numHeroic = dungeonRunCounts.heroic or 0
        while numMythic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  %s%s 0|r", VaultBrightHex(), mythicLabel),
                color = VaultBrightColor()
            })
            numMythic = numMythic - 1
            remaining = remaining - 1
        end
        while numHeroic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  %s%s|r", VaultBrightHex(), heroicLabel),
                color = VaultBrightColor()
            })
            numHeroic = numHeroic - 1
            remaining = remaining - 1
        end
    end
end

--[[
    Build world/delve tier progress lines for vault tooltips using cached GetSortedProgressForActivity.
    Blizzard pattern: sorted descending by difficulty, shows tier and completion count.
    @param lines table - Tooltip lines array to append to
    @param worldTierProgress table|nil - Cached tier progress from PvECacheService
    @param threshold number - Desired number of runs to show
]]
local function BuildWorldProgressLines(lines, worldTierProgress, threshold)
    if not worldTierProgress or #worldTierProgress == 0 or threshold <= 0 then return end
    
    local topRunsLabel = GetLocalizedText("VAULT_TOP_RUNS_FORMAT", "Top %d Runs This Week")
    local delveTierFmt = GetLocalizedText("VAULT_DELVE_TIER_FORMAT", "Tier %d (%d)")
    
    table.insert(lines, { text = " ", color = VaultSpacerColor() })
    table.insert(lines, {
        text = string.format("|cffffffcc" .. topRunsLabel .. "|r", threshold),
        color = {1, 1, 0.8}
    })
    
    local desiredRuns = threshold
    for wi = 1, #worldTierProgress do
        local tierProg = worldTierProgress[wi]
        local numRuns = math.min(tierProg.numPoints or 0, desiredRuns)
        if numRuns <= 0 then break end
        desiredRuns = desiredRuns - numRuns
        table.insert(lines, {
            text = string.format("  %s" .. delveTierFmt .. "|r", VaultBrightHex(), tierProg.difficulty or 0, numRuns),
            color = VaultBrightColor()
        })
    end
end

--- Paint the 3x3 Great Vault grid (Raid / Dungeon / World x 3 slots) on vaultCard (expanded row detail).
--- @return cardHeight, cardWidth
function WarbandNexus:PaintPvEVaultGridOnCard(vaultCard, opt)
    local baseCardWidth = opt.baseCardWidth
    local baseCardHeight = opt.baseCardHeight
    local vaultByType = opt.vaultByType
    local pve = opt.pve
    local vaultActivitiesData = opt.vaultActivitiesData
    local isCurrentChar = opt.isCurrentChar
    -- Recycle prior slot rows when repainting the same card (deferred expand path).
    if vaultCard then
        local bin = ns.UI_RecycleBin
        local children = { vaultCard:GetChildren() }
        for ci = 1, #children do
            local ch = children[ci]
            ch:Hide()
            ch:ClearAllPoints()
            if bin then ch:SetParent(bin) else ch:SetParent(nil) end
        end
    end
    -- WVT: enable slot clicks + tooltips for every card (Great Vault is global); expanded row uses current char only.
    local vaultSlotInteract = (opt.enableVaultSlotInteraction == true) or isCurrentChar
    -- Weekly Vault Tracker: plain container + no extra chrome; tighter rows/slots optional.
    local applyVaultCardChrome = (opt.applyVaultCardChrome ~= false)
    local minSlotBtnH = opt.minSlotBtnH or 44
    local rowVPad = opt.vaultRowVPad
    if rowVPad == nil then rowVPad = 4 end
    local trackIconSize = opt.trackIconSize or 18
    local slotFontKey = opt.slotFontKey or "body"
    local rowLabelFontKey = opt.rowLabelFontKey or "body"
    local slotTierYOffset = opt.slotTierYOffset
    if slotTierYOffset == nil then slotTierYOffset = 7 end
    -- Weekly Vault Tracker: fewer nested borders — flat rows, soft separators, subtle hover (no per-slot ApplyVisuals).
    local compactSlotStyle = (opt.compactSlotStyle == true)

    local ResolveSurface = ns.UI_ResolveSurfaceTierColor
    local function surfaceTier(tier, fallback)
        if ResolveSurface then
            return ResolveSurface(tier)
        end
        return fallback
    end
    local rowOdd = surfaceTier("rowOdd", { 0.05, 0.05, 0.07, 0.95 })
    local rowEven = surfaceTier("rowEven", { 0.09, 0.09, 0.11, 0.72 })
    local slotIdle = surfaceTier("card", { 0.06, 0.06, 0.09, 0.95 })
    local slotCompact = surfaceTier("rowEven", { 0.10, 0.10, 0.12, 0.82 })
    local labelBrightHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffe8e8e8"
    local labelMutedHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffbbbbbb"
    local dimHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim")) or "|cff666666"
    local borderC = (ns.UI_COLORS and ns.UI_COLORS.border) or { 0.20, 0.20, 0.24, 0.6 }

    local VAULT_LEFT_PAD  = 4
    local VAULT_RIGHT_PAD = 4
    local VAULT_COL_GAP   = 5   -- gap between columns
    local vaultColGap = opt.vaultColGap or VAULT_COL_GAP
    local leftPad = opt.vaultLeftPad or VAULT_LEFT_PAD
    local rightPad = opt.vaultRightPad or VAULT_RIGHT_PAD
    local VAULT_ROW_VPAD  = 4   -- row vertical padding (tighter = taller buttons)
    local borderPadding   = opt.borderPadding or 2
    local numRows         = 3
    local numCols         = 4   -- label + 3 slots

    local cardWidth = baseCardWidth
    local availableWidth  = cardWidth - (borderPadding * 2)
    local availableHeight = baseCardHeight - (borderPadding * 2)

    -- Compute one cell width, shared by ALL 4 columns
    local gapsTotal = leftPad + rightPad + vaultColGap * (numCols - 1)
    local VAULT_COL_W = math.floor((availableWidth - gapsTotal) / numCols)
    -- Alias for slot/label (they're identical)
    local VAULT_LABEL_W = VAULT_COL_W
    local VAULT_SLOT_W  = VAULT_COL_W

    local cellHeight = math.floor(availableHeight / numRows)
    local btnH       = math.max(minSlotBtnH, cellHeight - rowVPad * 2)

    local cardHeight = cellHeight * numRows + borderPadding * 2

    -- Set card dimensions for proper border
    vaultCard:SetHeight(cardHeight)
    vaultCard:SetWidth(cardWidth)

    -- Re-apply border after dimension change (skip when painting onto a plain container — WVT outer card already framed)
    if ApplyVisuals and applyVaultCardChrome then
        local cardBg = surfaceTier("card", { 0.05, 0.05, 0.07, 0.95 })
        local accentColor = (COLORS and COLORS.accent) or (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.4, 0.2, 0.58 }
        ApplyVisuals(vaultCard, cardBg, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end

    -- Default thresholds for each activity type (when no data exists)
    local defaultThresholds = {
        ["Raid"] = {2, 4, 6},
        ["Dungeon"] = {1, 4, 8},
        ["World"] = {3, 3, 3},
        ["PvP"] = {3, 3, 3}
    }

    -- Table Rows (3 ROWS - perfect grid alignment)
    local sortedTypes = {"Raid", "Dungeon", "World"}

    for rowIndex = 1, #sortedTypes do
        local typeName = sortedTypes[rowIndex]
        -- Map display name to actual data key
        local dataKey = typeName
        if typeName == "Dungeon" then
            dataKey = "M+"
        end
        local activities = vaultByType[dataKey]

        -- Calculate Y position (row 0, 1, 2) with border padding
        local rowY = borderPadding + ((rowIndex - 1) * cellHeight)

        -- Create row frame container. DELIBERATELY fresh each paint: the slot
        -- interiors below are deep state-branching (per-completion fontstrings,
        -- arrows, tooltip closures), so half-reusing the frames would stack new
        -- children onto old ones. This surface only repaints on row expand and
        -- on rare PVE_UPDATED events; the wipe path parks old frames in the
        -- recycle bin. The `if not X` guards below are for the fresh frame only.
        local rowFrame = ns.UI.Factory:CreateContainer(vaultCard)
        rowFrame:SetPoint("TOPLEFT", borderPadding, -rowY)
        rowFrame:SetSize(cardWidth - (borderPadding * 2), cellHeight)

        -- Row background
        if not rowFrame.bg then
            rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
            rowFrame.bg:SetAllPoints()
        end
        if compactSlotStyle then
            rowFrame.bg:SetColorTexture(rowEven[1], rowEven[2], rowEven[3], rowEven[4] or 0.72)
        else
            rowFrame.bg:SetColorTexture(rowOdd[1], rowOdd[2], rowOdd[3], rowOdd[4] or 0.95)
        end

        -- Track icon + label (left column, vertically centered)
        local trackIcons = {
            Raid    = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
            Dungeon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            World   = "Interface\\Icons\\INV_Misc_Map_01",
        }
        local trackIcon = rowFrame:CreateTexture(nil, "ARTWORK")
        trackIcon:SetSize(trackIconSize, trackIconSize)
        trackIcon:SetPoint("LEFT", rowFrame, "LEFT", leftPad, 0)
        trackIcon:SetTexture(trackIcons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark")
        trackIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local typeDisplayName = typeName
        if typeName == "Raid" then
            typeDisplayName = GetLocalizedText("VAULT_SLOT_RAIDS", "Raids")
        elseif typeName == "Dungeon" then
            typeDisplayName = GetLocalizedText("VAULT_SLOT_DUNGEON", "Dungeons")
        elseif typeName == "World" then
            typeDisplayName = GetLocalizedText("VAULT_WORLD", "World")
        end
        local label = FontManager:CreateFontString(rowFrame, rowLabelFontKey, "OVERLAY")
        label:SetPoint("LEFT", trackIcon, "RIGHT", 5, 0)
        -- Icon + gap consumed; rest of the column is text
        label:SetWidth(VAULT_LABEL_W - (trackIconSize + 5))
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(string.format("%s%s|r", compactSlotStyle and labelMutedHex or labelBrightHex, typeDisplayName))

        -- Row separator line (except for first row)
        if rowIndex > 1 then
            local sep = rowFrame:CreateTexture(nil, "BORDER")
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", leftPad, 0)
            sep:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -rightPad, 0)
            if compactSlotStyle then
                sep:SetColorTexture(borderC[1], borderC[2], borderC[3], 0.38)
            else
                sep:SetColorTexture(borderC[1], borderC[2], borderC[3], 0.6)
            end
        end

        -- Slot thresholds
        local thresholds = defaultThresholds[typeName] or {3, 3, 3}

        -- Vault toggle: click opens, click again closes
        local function OpenGreatVault()
            if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
                WeeklyRewardsFrame:Hide()
                return
            end
            if InCombatLockdown() then return end
            local U = ns.Utilities
            if U and U.SafeLoadAddOn then
                U:SafeLoadAddOn("Blizzard_WeeklyRewards")
            end
            if WeeklyRewardsFrame then
                WeeklyRewardsFrame:Show()
                if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
                    C_WeeklyRewards.OnUIInteract()
                end
                if WarbandNexus and WarbandNexus.EnsureWeeklyRewardsFrameHooks then
                    WarbandNexus:EnsureWeeklyRewardsFrameHooks()
                end
                C_Timer.After(0.2, function()
                    if WarbandNexus and WarbandNexus.RefreshVaultClaimState then
                        WarbandNexus:RefreshVaultClaimState()
                    end
                end)
            end
        end

        -- Theme accent color for online-char slot border
        local ac = ns.UI_COLORS and ns.UI_COLORS.accent or {0.40, 0.20, 0.58}

        for slotIndex = 1, 3 do
            -- Slot col index = 1..3 (col 0 is label). Uniform column widths + gaps.
            local xOffset = leftPad + slotIndex * (VAULT_COL_W + vaultColGap)
            local yOffset = -(cellHeight - btnH) / 2  -- vertically centered

            -- Intentionally raw: per-slot vault glyph + stripe + WeeklyRewards toggle (heavy state branching).
            local slotFrame = CreateFrame("Button", nil, rowFrame)
            slotFrame:SetSize(VAULT_SLOT_W, btnH)
            slotFrame:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", xOffset, yOffset)

            -- Slot base: very dark bg, no visible border yet (state sets it below)
            if not slotFrame.bg then
                slotFrame.bg = slotFrame:CreateTexture(nil, "BACKGROUND")
                slotFrame.bg:SetAllPoints()
            end
            if compactSlotStyle then
                slotFrame.bg:SetColorTexture(slotCompact[1], slotCompact[2], slotCompact[3], slotCompact[4] or 0.82)
            else
                slotFrame.bg:SetColorTexture(slotIdle[1], slotIdle[2], slotIdle[3], slotIdle[4] or 0.95)
            end

            -- Left-side state stripe (slimmer in compact tracker layout)
            if not slotFrame.stripe then
                slotFrame.stripe = slotFrame:CreateTexture(nil, "BORDER")
                slotFrame.stripe:SetWidth(compactSlotStyle and 2 or 3)
                slotFrame.stripe:SetPoint("TOPLEFT", slotFrame, "TOPLEFT", 0, 0)
                slotFrame.stripe:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", 0, 0)
            end

            -- Current char or WVT: click opens/closes Great Vault (compact = soft hover, no heavy slot border)
            if vaultSlotInteract then
                slotFrame:RegisterForClicks("LeftButtonUp")
                slotFrame:SetScript("OnClick", OpenGreatVault)
                slotFrame:SetScript("OnMouseDown", function(self) self:SetAlpha(compactSlotStyle and 0.88 or 0.65) end)
                slotFrame:SetScript("OnMouseUp", function(self) self:SetAlpha(1) end)
                if compactSlotStyle then
                    local hlTex = slotFrame:CreateTexture(nil, "HIGHLIGHT")
                    hlTex:SetBlendMode("ADD")
                    hlTex:SetAllPoints()
                    hlTex:SetColorTexture(1, 1, 1, 0.07)
                    slotFrame:SetHighlightTexture(hlTex)
                else
                    if ApplyVisuals then
                        ApplyVisuals(slotFrame,
                            {ac[1] * 0.14, ac[2] * 0.14, ac[3] * 0.18, 1},
                            {ac[1] * 0.70, ac[2] * 0.70, ac[3] * 0.70, 0.70})
                    end
                    local hl = slotFrame:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(ac[1], ac[2], ac[3], 0.14)
                end
            end

            -- Get activity data for this slot
            local activity = activities and activities[slotIndex]

            local threshold = SafeVaultNumber(activity and activity.threshold, SafeVaultNumber(thresholds[slotIndex], 0))
            local progress = SafeVaultNumber(activity and activity.progress, 0)
            local isComplete = (threshold > 0 and progress >= threshold)

            if activity and isComplete then
                local isAtMax = IsVaultSlotAtMax(activity, dataKey)
                -- State: completed — green tint (softer in compact tracker style)
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.20, 0.62, 0.26, 0.65)
                    slotFrame.bg:SetColorTexture(0.07, 0.14, 0.09, 0.88)
                else
                    slotFrame.stripe:SetColorTexture(0.20, 0.75, 0.20, 0.90)
                    slotFrame.bg:SetColorTexture(0.04, 0.10, 0.04, 0.95)
                end

                local displayText = GetVaultActivityDisplayText(activity, dataKey)
                local rewardIlvl  = GetRewardItemLevel(activity)
                local hasArrow    = not isAtMax
                -- ALL slot text uses identical width + centered position (equal everywhere)
                local textW = VAULT_SLOT_W - 12

                local tierText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                tierText:SetPoint("CENTER", slotFrame, "CENTER", 0, slotTierYOffset)
                tierText:SetWidth(textW)
                tierText:SetJustifyH("CENTER")
                tierText:SetWordWrap(false)
                tierText:SetText(string.format("|cff33dd33%s|r", displayText))

                if rewardIlvl and rewardIlvl > 0 then
                    local ilvlText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                    ilvlText:SetPoint("TOP", tierText, "BOTTOM", 0, -2)
                    ilvlText:SetWidth(textW)
                    ilvlText:SetJustifyH("CENTER")
                    ilvlText:SetWordWrap(false)
                    local ilvlFormat = GetLocalizedText("ILVL_FORMAT", "iLvl %d")
                    ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", rewardIlvl))
                end

                -- Upgrade arrow: `loottoast-arrow-green` (Blizzard loot toast); sublayer 7 so slot text stays underneath
                if hasArrow and slotFrame.stripe then
                    local arrowTexture = slotFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    arrowTexture:SetSize(compactSlotStyle and 18 or 22, compactSlotStyle and 18 or 22)
                    arrowTexture:SetPoint("LEFT", slotFrame.stripe, "RIGHT", 2, 0)
                    arrowTexture:SetAtlas("loottoast-arrow-green", false)
                end

                -- Add tooltip for completed slots
                if ShowTooltip then
                    slotFrame:EnableMouse(true)
                    slotFrame:SetScript("OnEnter", function(self)
                        local lines = {}
                        local displayText = GetVaultActivityDisplayText(activity, dataKey)
                        local rewardIlvl = GetRewardItemLevel(activity)
                        local tierFmt = GetLocalizedText("TIER_FORMAT", "Tier %d")
                        local mythicLabel = GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")

                        -- Current Reward header + value
                        if rewardIlvl and rewardIlvl > 0 then
                            table.insert(lines, {
                                text = string.format("|cff00ff00%s|r",
                                    GetLocalizedText("VAULT_REWARD", "Current Reward")),
                                color = VaultCompleteLineColor()
                            })
                            table.insert(lines, {
                                text = string.format("%siLvl %d|r  %s- (%s)|r", VaultGoldHex(),
                                    rewardIlvl, VaultBrightHex(), displayText),
                                color = VaultBrightColor()
                            })
                        end

                        -- Upgrade: "Improve to iLvl X: Complete on Y difficulty"
                        local isAtMaxSlot = IsVaultSlotAtMax(activity, dataKey)
                        if not isAtMaxSlot then
                            local nextTierName = GetNextTierName(activity, dataKey)
                            if nextTierName then
                                table.insert(lines, { text = " ", color = VaultSpacerColor() })
                                local improveLabel = GetLocalizedText("VAULT_IMPROVE_TO", "Improve to")
                                local nextIlvl = SafeVaultNumber(activity.nextLevelIlvl, 0)
                                if nextIlvl > 0 then
                                    table.insert(lines, {
                                        text = string.format("|cffa0d0ff%s iLvl %d:|r",
                                            improveLabel, nextIlvl),
                                        color = VaultInfoLineColor()
                                    })
                                end
                                local completeOnLabel = GetLocalizedText("VAULT_COMPLETE_ON", "Complete this activity on %s")
                                table.insert(lines, {
                                    text = string.format("|cff888888" .. completeOnLabel .. "|r", nextTierName),
                                    color = VaultDimLineColor()
                                })
                            end
                        end

                        -- RAID: Encounter list (primary: vault API, fallback: lockouts)
                        if dataKey == "Raid" then
                            if activity.encounters and #activity.encounters > 0 then
                                BuildRaidEncounterLines(lines, activity.encounters)
                            elseif pve.raidLockouts and #pve.raidLockouts > 0 then
                                BuildRaidBossLinesFromLockouts(lines, pve.raidLockouts)
                            end
                        end

                        -- DUNGEON: Top runs (Blizzard pattern: GetRunHistory + GetNumCompletedDungeonRuns)
                        if dataKey == "M+" then
                            local rawHistory = pve.mythicPlus and pve.mythicPlus.runHistory
                            local dungeonRunCounts = vaultActivitiesData and vaultActivitiesData.dungeonRunCounts
                            BuildDungeonRunLines(lines, rawHistory, dungeonRunCounts, threshold)
                        end

                        -- WORLD: Tier progress from GetSortedProgressForActivity (Blizzard pattern)
                        if dataKey == "World" then
                            local worldTierProgress = vaultActivitiesData and vaultActivitiesData.worldTierProgress
                            BuildWorldProgressLines(lines, worldTierProgress, threshold)
                        end

                        if vaultSlotInteract then
                            table.insert(lines, { text = " ", color = VaultSpacerColor() })
                            table.insert(lines, { text = "|cff00ccff" .. (GetLocalizedText("VAULT_CLICK_TO_OPEN", "Click to open Great Vault")) .. "|r", color = {0, 0.8, 1} })
                        end
                        local slotTitleFormat = GetLocalizedText("VAULT_SLOT_FORMAT", "%s Slot %d")
                        ShowTooltip(self, {
                            type = "custom",
                            icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                            title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                            lines = lines,
                        })
                    end)

                    slotFrame:SetScript("OnLeave", function(self)
                        if HideTooltip then
                            HideTooltip()
                        end
                    end)
                    BindForwardScrollWheel(slotFrame)
                end

            elseif activity and not isComplete then
                -- State: in-progress — amber tint
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.55, 0.42, 0.14, 0.58)
                    slotFrame.bg:SetColorTexture(0.11, 0.09, 0.05, 0.86)
                else
                    slotFrame.stripe:SetColorTexture(0.85, 0.60, 0.10, 0.85)
                    slotFrame.bg:SetColorTexture(0.10, 0.08, 0.02, 0.95)
                end

                local progressText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                progressText:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
                progressText:SetWidth(VAULT_SLOT_W - 12)
                progressText:SetJustifyH("CENTER")
                progressText:SetWordWrap(false)
                progressText:SetText(string.format("|cffffcc00%s|r" .. dimHex .. "/|r" .. labelMutedHex .. "%s|r",
                    FormatNumber(progress), FormatNumber(threshold)))

                -- Add tooltip for incomplete slots
                if ShowTooltip then
                    slotFrame:EnableMouse(true)
                    slotFrame:SetScript("OnEnter", function(self)
                        local lines = {}
                        local tierFmt = GetLocalizedText("TIER_FORMAT", "Tier %d")
                        local mythicLabel = GetLocalizedText("DIFFICULTY_MYTHIC", "Mythic")

                        local activityHint = ""
                        if dataKey == "M+" then
                            activityHint = GetLocalizedText("VAULT_DUNGEONS", "dungeons")
                        elseif dataKey == "Raid" then
                            activityHint = GetLocalizedText("VAULT_BOSS_KILLS", "boss kills")
                        elseif dataKey == "World" then
                            activityHint = GetLocalizedText("VAULT_WORLD_ACTIVITIES", "world activities")
                        else
                            activityHint = GetLocalizedText("VAULT_ACTIVITIES", "activities")
                        end

                        -- Unlock Reward header
                        local unlockLabel = GetLocalizedText("VAULT_UNLOCK_REWARD", "Unlock Reward")
                        table.insert(lines, {
                            text = string.format("|cff00ff00%s|r", unlockLabel),
                            color = VaultCompleteLineColor()
                        })

                        -- "Complete N more X to unlock"
                        local remaining = threshold - progress
                        if remaining > 0 then
                            local completeMoreLabel = GetLocalizedText("VAULT_COMPLETE_MORE_FORMAT", "Complete %d more %s this week to unlock.")
                            table.insert(lines, {
                                text = string.format("%s" .. completeMoreLabel .. "|r", VaultBrightHex(),
                                    remaining, activityHint),
                                color = VaultBrightColor()
                            })
                        end

                        -- M+ specific: "The item level will be based on the lowest of your top N runs (currently X)"
                        if dataKey == "M+" then
                            local currentTierText = GetVaultActivityDisplayText(activity, dataKey)
                            table.insert(lines, { text = " ", color = VaultSpacerColor() })
                            local basedOnLabel = GetLocalizedText("VAULT_BASED_ON_FORMAT", "The item level of this reward will be based on the lowest of your top %d runs this week (currently %s).")
                            table.insert(lines, {
                                text = string.format("|cff888888" .. basedOnLabel .. "|r",
                                    threshold, currentTierText),
                                color = VaultDimLineColor()
                            })
                        end

                        -- Raid specific: "The item level will be based on the difficulty of your boss kills"
                        if dataKey == "Raid" then
                            local currentDiffText = GetVaultActivityDisplayText(activity, dataKey)
                            table.insert(lines, { text = " ", color = VaultSpacerColor() })
                            local raidBasedLabel = GetLocalizedText("VAULT_RAID_BASED_FORMAT", "Reward based on highest difficulty defeated (currently %s).")
                            table.insert(lines, {
                                text = string.format("|cff888888" .. raidBasedLabel .. "|r", currentDiffText),
                                color = VaultDimLineColor()
                            })
                        end

                        -- RAID: Encounter list (primary: vault API, fallback: lockouts)
                        if dataKey == "Raid" then
                            if activity.encounters and #activity.encounters > 0 then
                                BuildRaidEncounterLines(lines, activity.encounters)
                            elseif pve.raidLockouts and #pve.raidLockouts > 0 then
                                BuildRaidBossLinesFromLockouts(lines, pve.raidLockouts)
                            end
                        end

                        -- DUNGEON: Top runs (Blizzard pattern)
                        if dataKey == "M+" and progress > 0 then
                            local rawHistory = pve.mythicPlus and pve.mythicPlus.runHistory
                            local dungeonRunCounts = vaultActivitiesData and vaultActivitiesData.dungeonRunCounts
                            BuildDungeonRunLines(lines, rawHistory, dungeonRunCounts, threshold)
                        end

                        -- WORLD: Tier progress (Blizzard pattern)
                        if dataKey == "World" and progress > 0 then
                            local worldTierProgress = vaultActivitiesData and vaultActivitiesData.worldTierProgress
                            BuildWorldProgressLines(lines, worldTierProgress, threshold)
                        end

                        if vaultSlotInteract then
                            table.insert(lines, { text = " ", color = VaultSpacerColor() })
                            table.insert(lines, { text = "|cff00ccff" .. (GetLocalizedText("VAULT_CLICK_TO_OPEN", "Click to open Great Vault")) .. "|r", color = {0, 0.8, 1} })
                        end
                        local slotTitleFormat = GetLocalizedText("VAULT_SLOT_FORMAT", "%s Slot %d")
                        ShowTooltip(self, {
                            type = "custom",
                            icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                            title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                            lines = lines,
                        })
                    end)

                    slotFrame:SetScript("OnLeave", function(self)
                        if HideTooltip then
                            HideTooltip()
                        end
                    end)
                    BindForwardScrollWheel(slotFrame)
                end
            else
                -- State: no data — dim stripe / neutral cell
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.16, 0.16, 0.20, 0.42)
                    slotFrame.bg:SetColorTexture(slotCompact[1], slotCompact[2], slotCompact[3], (slotCompact[4] or 0.82) * 0.92)
                else
                    slotFrame.stripe:SetColorTexture(borderC[1], borderC[2], borderC[3], 0.60)
                end

                local emptyText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                emptyText:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
                emptyText:SetWidth(VAULT_SLOT_W - 12)
                emptyText:SetJustifyH("CENTER")
                emptyText:SetWordWrap(false)
                if threshold > 0 then
                    emptyText:SetText(string.format(dimHex .. "%s|r" .. dimHex .. "/|r" .. dimHex .. "%s|r", FormatNumber(0), FormatNumber(threshold)))

                    -- Add tooltip for empty slots
                    if ShowTooltip then
                        slotFrame:EnableMouse(true)
                        slotFrame:SetScript("OnEnter", function(self)
                            local lines = {}

                            local activityHint = ""
                            if dataKey == "M+" then
                                activityHint = GetLocalizedText("VAULT_DUNGEONS", "dungeons")
                            elseif dataKey == "Raid" then
                                activityHint = GetLocalizedText("VAULT_BOSS_KILLS", "boss kills")
                            elseif dataKey == "World" then
                                activityHint = GetLocalizedText("VAULT_WORLD_ACTIVITIES", "world activities")
                            else
                                activityHint = GetLocalizedText("VAULT_ACTIVITIES", "activities")
                            end

                            local unlockLabel = GetLocalizedText("VAULT_UNLOCK_REWARD", "Unlock Reward")
                            table.insert(lines, {
                                text = string.format("|cff00ff00%s|r", unlockLabel),
                                color = VaultCompleteLineColor()
                            })
                            local completeMoreLabel = GetLocalizedText("VAULT_COMPLETE_MORE_FORMAT", "Complete %d more %s this week to unlock.")
                            table.insert(lines, {
                                text = string.format("%s" .. completeMoreLabel .. "|r", VaultBrightHex(),
                                    threshold, activityHint),
                                color = VaultBrightColor()
                            })

                            if vaultSlotInteract then
                                table.insert(lines, { text = " ", color = VaultSpacerColor() })
                                table.insert(lines, { text = "|cff00ccff" .. (GetLocalizedText("VAULT_CLICK_TO_OPEN", "Click to open Great Vault")) .. "|r", color = {0, 0.8, 1} })
                            end
                            local slotTitleFormat = GetLocalizedText("VAULT_SLOT_FORMAT", "%s Slot %d")
                            ShowTooltip(self, {
                                type = "custom",
                                icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                                lines = lines,
                            })
                        end)

                        slotFrame:SetScript("OnLeave", function(self)
                            if HideTooltip then
                                HideTooltip()
                            end
                        end)
                        BindForwardScrollWheel(slotFrame)
                    end
                else
                    emptyText:SetText(dimHex .. "-|r")
                end
            end
        end

        -- No need to increment vaultY anymore (using rowIndex)
    end

    return cardHeight, cardWidth
end
assert(ns.PvEUI and ns.PvEUI.FormatVaultTrackColumn, "PvEUI_VaultGrid: load before PvEUI.lua")
