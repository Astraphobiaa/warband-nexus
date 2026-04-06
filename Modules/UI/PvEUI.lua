--[[
    Warband Nexus - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
    
    DATA FLOW ARCHITECTURE (CACHE-FIRST):
    ==========================================
    1. PvECacheService: Event-driven data collection (WEEKLY_REWARDS_UPDATE, MYTHIC_PLUS_*, etc.)
    2. Database: Persistent storage (db.global.pveCache)
    3. UI (this file): Reads from cache via GetPvEData(charKey)
    
    ACCEPTABLE API CALLS (UI-only):
    - C_DateAndTime.GetSecondsUntilWeeklyReset() - Fallback for weekly reset timer
    - C_ChallengeMode.GetMapUIInfo() - Dungeon name/icon (not cached, static data)
    - C_CurrencyInfo.GetCurrencyInfo() - Currency details for TWW currencies
    - C_Item.GetItemIconByID() - Trovehunter's Bounty icon for Bountiful column header
    
    DEPRECATED API CALLS (Moved to PvECacheService):
    - C_MythicPlus.GetOwnedKeystoneLevel() → Use pveData.keystone.level
    - C_MythicPlus.GetOwnedKeystoneChallengeMapID() → Use pveData.keystone.mapID
    - C_MythicPlus.GetCurrentAffixes() → Use allPveData.currentAffixes
    - C_WeeklyRewards.GetActivities() → Use pveData.vaultActivities
    
    Event Registration: WN_PVE_UPDATED (auto-refresh UI when cache updates)
]]

local ADDON_NAME, ns = ...

-- Unique AceEvent handler identity for PvEUI
local PvEUIEvents = {}
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateIcon = ns.UI_CreateIcon
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local ApplyVisuals = ns.UI_ApplyVisuals  -- For border re-application
local FormatNumber = ns.UI_FormatNumber
local COLORS = ns.UI_COLORS

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().headerSpacing or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().topMargin or 8

-- PvE inline grid: min width for horizontal scroll + columnHeaderInner (see ProfessionsUI / UI.lua)
local PVE_ROW_LEFT_CLUSTER_W = 12 + 20 + 4 + 33 + 6 -- expand + gap + favorite + gap to name
local PVE_ROW_MIDDLE_MAX_W = 30 + 60 + 30 + 80     -- bullets + level + ilvl (worst case)
local PVE_CHAR_HEADER_H_MARGIN = 20                -- char row inset 10 + 10
local PVE_COLUMN_HEADER_PAD = 2
local PVE_COL_SPACING = 1                        -- crest / coffer / key (tight)
local PVE_KEY_TO_VAULT_GAP = 14                  -- currency block ↔ first vault column
local PVE_VAULT_CLUSTER_GAP = 12                 -- Raid | Dungeon | World (readable groups)
local PVE_COL_RIGHT_MARGIN = 8
local PVE_DAWNCREST_COL_W = 128                  -- qty/max (R:rem)
local PVE_COFFER_COL_W = 132
local PVE_KEY_COL_W = 88
local PVE_VAULT_COL_W = 70                       -- triplet of marks per track

--- Header icon for Bountiful column — Blizzard art from Trovehunter's Bounty item.
---@return number|string fileID from API, or texture path fallback
local function GetTrovehunterBountyColumnIcon()
    local Constants = ns.Constants
    local primary = (Constants and Constants.TROVEHUNTERS_BOUNTY_ITEM_ID) or 252415
    local alt = Constants and Constants.TROVEHUNTERS_BOUNTY_ITEM_ID_ALT
    if C_Item and C_Item.GetItemIconByID then
        local ok, fileID = pcall(C_Item.GetItemIconByID, primary)
        if ok and type(fileID) == "number" and fileID > 0 then
            return fileID
        end
        if alt and alt ~= primary then
            local ok2, fileID2 = pcall(C_Item.GetItemIconByID, alt)
            if ok2 and type(fileID2) == "number" and fileID2 > 0 then
                return fileID2
            end
        end
    end
    return "Interface\\Icons\\INV_10_WorldQuests_Scroll"
end

--- Minimum scrollChild width so inline columns do not overlap; enables horizontal scrollbar.
function ns.ComputePvEMinScrollWidth(self)
    if not self or not self.GetAllCharacters then return 0 end
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        if char.isTracked ~= false then
            characters[#characters + 1] = char
        end
    end
    local maxNameRealmWidth = 0
    local FM = ns.FontManager
    if FM and #characters > 0 then
        local tempMeasure = FM:CreateFontString(UIParent, "body", "OVERLAY")
        tempMeasure:Hide()
        for i = 1, #characters do
            local c = characters[i]
            local realmStr = ns.Utilities and ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
            tempMeasure:SetText((c.name or "Unknown") .. "  -  " .. realmStr)
            local w = tempMeasure:GetStringWidth()
            if w and w > maxNameRealmWidth then maxNameRealmWidth = w end
        end
        tempMeasure:SetParent(nil)
    end
    local nameWidth = math.max(230, math.ceil(maxNameRealmWidth) + 8)
    local PVE_BOUNTIFUL_COL_W = 44
    local inlineTotal = 5 * PVE_DAWNCREST_COL_W + PVE_COFFER_COL_W + PVE_KEY_COL_W + 3 * PVE_VAULT_COL_W + PVE_BOUNTIFUL_COL_W
    local gapSum = 6 * PVE_COL_SPACING + PVE_KEY_TO_VAULT_GAP + 2 * PVE_VAULT_CLUSTER_GAP + PVE_KEY_TO_VAULT_GAP
    inlineTotal = inlineTotal + gapSum + PVE_COL_RIGHT_MARGIN
    return PVE_CHAR_HEADER_H_MARGIN + PVE_ROW_LEFT_CLUSTER_W + nameWidth + PVE_ROW_MIDDLE_MAX_W + inlineTotal
end

-- Performance: Local function references
local format = string.format
local date = date

--- Tooltip / icon frames use EnableMouse and would block wheel; forward to main tab ScrollFrame.
local function BindForwardScrollWheel(frame)
    local fwd = ns.UI_ForwardMouseWheelToScrollAncestor
    if not frame or not fwd then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        fwd(self, delta)
    end)
end

-- Expand/Collapse State Management
local expandedStates = {}

local function IsExpanded(key, defaultState)
    -- Check for Expand All override
    if WarbandNexus and WarbandNexus.pveExpandAllActive then
        return true
    end
    if expandedStates[key] == nil then
        expandedStates[key] = defaultState
    end
    return expandedStates[key]
end

local function ToggleExpand(key, newState)
    expandedStates[key] = newState
    WarbandNexus:RefreshUI()
end

--============================================================================
-- EVENT-DRIVEN UI REFRESH
--============================================================================

---Register event listener for PvE updates
---@param parent Frame Parent frame for event registration
local function RegisterPvEEvents(parent)
    -- Register only once per parent
    if parent.pveUpdateHandler then
        return
    end
    parent.pveUpdateHandler = true
    
    -- WN_PVE_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- pve tab refresh via PopulateContent → DrawPvEProgress. Having both caused double rebuild.
    
    -- Event listener cleanup (silent)
end

--============================================================================
-- GREAT VAULT HELPER FUNCTIONS
--============================================================================

--[[
    Determine if a vault activity slot is at maximum completion level
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name ("Raid", "M+", "World", "PvP")
    @return boolean - True if at maximum level, false otherwise
]]
local function IsVaultSlotAtMax(activity, typeName)
    if not activity or not activity.level then
        return false
    end
    
    local level = activity.level
    
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
    if activity.rewardItemLevel and activity.rewardItemLevel > 0 then
        return activity.rewardItemLevel
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
    if not activity or not activity.level then
        return nil
    end
    
    local currentLevel = activity.level
    
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    
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
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    if typeName == "World" then
        return string.format(tierFmt, 8)
    elseif typeName == "Raid" then
        return (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
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
    local unknownLabel = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local lfrLabel = (ns.L and ns.L["DIFFICULTY_LFR"]) or "LFR"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    local pvpLabel = (ns.L and ns.L["PVP_TYPE"]) or "PvP"
    
    if not activity then
        return unknownLabel
    end
    
    if typeName == "Raid" then
        local difficulty = unknownLabel
        if activity.level then
            -- Raid difficultyIDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
            -- CRITICAL: Use exact matches — LFR (17) > Mythic (16) by ID
            if activity.level == 16 then
                difficulty = mythicLabel
            elseif activity.level == 15 then
                difficulty = heroicLabel
            elseif activity.level == 14 then
                difficulty = normalLabel
            elseif activity.level == 17 then
                difficulty = lfrLabel
            end
        end
        return difficulty
    elseif typeName == "M+" or typeName == "Dungeon" then
        local level = activity.level or 0
        if level == 0 then
            return mythicLabel .. " 0"
        else
            return string.format(tierFmt, level)
        end
    elseif typeName == "World" then
        local tier = activity.level or 1
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
    local encounterListLabel = (ns.L and ns.L["VAULT_ENCOUNTER_LIST_FORMAT"]) or "%s"
    for i = 1, #sorted do
        local enc = sorted[i]
        if (enc.instanceID or 0) ~= (lastInstanceID or 0) then
            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
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
                    color = {0.4, 0.4, 0.4}
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

    local encounterListLabel = (ns.L and ns.L["VAULT_ENCOUNTER_LIST_FORMAT"]) or "%s"
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
                table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
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
                            color = {0.4, 0.4, 0.4}
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
    
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local topRunsLabel = (ns.L and ns.L["VAULT_TOP_RUNS_FORMAT"]) or "Top %d Runs This Week"
    
    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
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
            runText = string.format("  |cffffffff+%d %s|r", lvl, dungeonName)
        else
            runText = string.format("  |cffffffff%s 0 %s|r", mythicLabel, dungeonName)
        end
        table.insert(lines, { text = runText, color = {1, 1, 1} })
        shown = shown + 1
    end
    
    -- Fill remaining slots with non-keystone runs (Mythic 0, Heroic) - Blizzard pattern
    local remaining = threshold - shown
    if remaining > 0 and dungeonRunCounts then
        local numMythic = dungeonRunCounts.mythic or 0
        local numHeroic = dungeonRunCounts.heroic or 0
        while numMythic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  |cffffffff%s 0|r", mythicLabel),
                color = {1, 1, 1}
            })
            numMythic = numMythic - 1
            remaining = remaining - 1
        end
        while numHeroic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  |cffffffff%s|r", heroicLabel),
                color = {1, 1, 1}
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
    
    local topRunsLabel = (ns.L and ns.L["VAULT_TOP_RUNS_FORMAT"]) or "Top %d Runs This Week"
    local delveTierFmt = (ns.L and ns.L["VAULT_DELVE_TIER_FORMAT"]) or "Tier %d (%d)"
    
    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
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
            text = string.format("  |cffffffff" .. delveTierFmt .. "|r", tierProg.difficulty or 0, numRuns),
            color = {1, 1, 1}
        })
    end
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

function WarbandNexus:DrawPvEProgress(parent)
    local width = parent:GetWidth() - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.pveProgress"
        if self.db.global.pveCache and self.db.global.pveCache.version then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Register event listener (only once)
    RegisterPvEEvents(parent)
    
    -- Hide empty state card (will be shown again if needed)
    HideEmptyStateCard(parent, "pve")
    
    -- ===== AUTO-REFRESH CHECK (FULLY AUTOMATIC) =====
    local charKey = ns.Utilities:GetCharacterKey()
    local pveData = self:GetPvEData(charKey)
    
    -- Check multiple data completeness signals, not just keystone
    local needsRefresh = false
    if not pveData or not pveData.keystone then
        needsRefresh = true
    elseif pveData.vaultActivities then
        -- Check if any unlocked vault slot is missing iLvl (server was slow)
        local vaultCategories = {"raids", "mythicPlus", "world"}
        for ci = 1, #vaultCategories do
            local cat = vaultCategories[ci]
            local activities = pveData.vaultActivities[cat]
            if activities then
                for ai = 1, #activities do
                    local a = activities[ai]
                    if a and a.progress and a.threshold and a.progress >= a.threshold then
                        if not a.rewardItemLevel or a.rewardItemLevel == 0 then
                            needsRefresh = true
                            break
                        end
                    end
                end
            end
            if needsRefresh then break end
        end
    end
    
    -- Trigger refresh if needed (rate-limited to avoid spam)
    if needsRefresh and not ns.PvELoadingState.isLoading then
        local timeSinceLastAttempt = time() - (ns.PvELoadingState.lastAttempt or 0)
        if timeSinceLastAttempt > 10 then
            ns.PvELoadingState.lastAttempt = time()
            -- Poke server for fresh vault data before collecting
            if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
                C_WeeklyRewards.OnUIInteract()
            end
            if self.UpdatePvEData then
                self:UpdatePvEData()
            end
            -- Schedule a follow-up refresh after server responds (vault iLvl needs time)
            C_Timer.After(3, function()
                if self.UpdatePvEData then
                    self:UpdatePvEData()
                end
            end)
        end
    end
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) =====
    local titleCard = CreateCard(headerParent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("pve"))
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["PVE_TITLE"]) or "PvE Progress") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["PVE_SUBTITLE"]) or "Great Vault, Raid Lockouts & Mythic+ across your Warband"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    -- Weekly reset timer (standardized widget)
    local CreateResetTimer = ns.UI_CreateResetTimer
    local resetTimer = CreateResetTimer(
        titleCard,
        "RIGHT",
        -20,  -- 20px from right edge
        0,
        function()
            -- Use centralized GetWeeklyResetTime from PlansManager
            if WarbandNexus.GetWeeklyResetTime then
                local resetTimestamp = WarbandNexus:GetWeeklyResetTime()
                return resetTimestamp - GetServerTime()
            end
            
            -- Fallback: Use Blizzard API
            if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            
            return 0
        end
    )
    
    -- Sort Dropdown on the Title Card
    if ns.UI_CreateCharacterSortDropdown then
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        }
        if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
        local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.pveSort, function() self:RefreshUI() end)
        sortBtn:SetPoint("RIGHT", resetTimer.container, "LEFT", -15, 0)
    end
    
    titleCard:Show()
    headerYOffset = headerYOffset + GetLayout().afterHeader
    -- Title only; column headers live in columnHeaderClip (horizontal sync with scroll child)
    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    -- ===== COLUMN HEADER ROW (inline PvE status summary) =====
    -- All Midnight Dawncrest tiers (same IDs as vault currency card)
    local PVE_DAWNCRESTS = {
        { id = 3383, labelKey = "PVE_CREST_ADV" },
        { id = 3341, labelKey = "PVE_CREST_VET" },
        { id = 3343, labelKey = "PVE_CREST_CHAMP" },
        { id = 3345, labelKey = "PVE_CREST_HERO" },
        { id = 3347, labelKey = "PVE_CREST_MYTH" },
    }
    local PVE_RESTORED_KEY_FALLBACK_ID = 3089
    local PVE_SHARDS_ID = nil
    local PVE_RESTORED_KEY_ID = nil
    local PVE_SHARDS_ICON = "Interface\\Icons\\INV_Misc_Gem_Variety_01"
    local PVE_RESTORED_KEY_ICON = "Interface\\Icons\\INV_Misc_Key_13"

    -- Resolve dynamic Delve currency IDs by name so this works with changing IDs.
    if self.GetCurrenciesForUI then
        local allCurrencies = self:GetCurrenciesForUI()
        for currencyID, entry in pairs(allCurrencies) do
            local lowerName = entry and entry.name and string.lower(entry.name) or ""
            if lowerName ~= "" then
                if not PVE_SHARDS_ID and lowerName:find("coffer") and lowerName:find("shard") then
                    PVE_SHARDS_ID = currencyID
                    if entry.icon then PVE_SHARDS_ICON = entry.icon end
                end
                if not PVE_RESTORED_KEY_ID and lowerName:find("coffer") and lowerName:find("key") and lowerName:find("restored") then
                    PVE_RESTORED_KEY_ID = currencyID
                    if entry.icon then PVE_RESTORED_KEY_ICON = entry.icon end
                end
            end
        end
    end
    
    -- Fallback for Restored Coffer Key when dynamic lookup doesn't resolve.
    if not PVE_RESTORED_KEY_ID then
        PVE_RESTORED_KEY_ID = PVE_RESTORED_KEY_FALLBACK_ID
    end

    local PVE_COLUMNS = {}
    for i = 1, #PVE_DAWNCRESTS do
        local crestEntry = PVE_DAWNCRESTS[i]
        local crestIcon = 134400
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(crestEntry.id)
            if info and info.iconFileID then
                crestIcon = info.iconFileID
            end
        end
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "crest_" .. tostring(crestEntry.id),
            label = "",
            width = PVE_DAWNCREST_COL_W,
            icon = crestIcon,
            crestCurrencyId = crestEntry.id,
        }
    end
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "coffer_shards",
        label = "",
        width = PVE_COFFER_COL_W,
        icon = PVE_SHARDS_ICON,
        tooltipTitle = (ns.L and ns.L["PVE_COL_COFFER_SHARDS"]) or "Coffer Shards",
    }
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "restored_key",
        label = "",
        width = PVE_KEY_COL_W,
        icon = PVE_RESTORED_KEY_ICON,
        tooltipTitle = (ns.L and ns.L["PVE_COL_RESTORED_KEY"]) or "Restored Key",
    }
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "slot1",
        label = "",
        width = PVE_VAULT_COL_W,
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        tooltipTitle = (ns.L and ns.L["PVE_HEADER_RAIDS"]) or "Raids",
    }
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "slot2",
        label = "",
        width = PVE_VAULT_COL_W,
        icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
        tooltipTitle = (ns.L and ns.L["PVE_HEADER_DUNGEONS"]) or "Dungeons",
    }
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "slot3",
        label = "",
        width = PVE_VAULT_COL_W,
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        tooltipTitle = (ns.L and ns.L["VAULT_WORLD"]) or "World",
    }
    -- Bountiful weekly — Trovehunter's Bounty item icon (live fileID when API returns it)
    PVE_COLUMNS[#PVE_COLUMNS + 1] = {
        key = "bountiful",
        label = "",
        width = 44,
        icon = GetTrovehunterBountyColumnIcon(),
        tooltipTitle = (ns.L and ns.L["BOUNTIFUL_DELVE"]) or "Trovehunter's Bounty",
    }

    local COL_SPACING = PVE_COL_SPACING
    local COL_RIGHT_MARGIN = PVE_COL_RIGHT_MARGIN
    local COL_ICON_SIZE = 28
    local COL_HEADER_HEIGHT = 30
    local dawnN = #PVE_DAWNCRESTS
    local function GapBetweenColumns(leftIdx)
        if leftIdx == dawnN + 2 then return PVE_KEY_TO_VAULT_GAP end
        if leftIdx == dawnN + 3 or leftIdx == dawnN + 4 then return PVE_VAULT_CLUSTER_GAP end
        if leftIdx == dawnN + 5 then return PVE_KEY_TO_VAULT_GAP end
        return PVE_COL_SPACING
    end

    local yOffset = 8

    -- Check if module is disabled - show beautiful disabled state card (before column strip / scroll width)
    if not ns.Utilities:IsModuleEnabled("pve") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["PVE_TITLE"]) or "PvE Progress")
        return yOffset + cardHeight
    end
    
    -- Get all characters (filter tracked only for PvE display)
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    for _, char in ipairs(allCharacters) do
        if char.isTracked ~= false then  -- Default to tracked if not set
            table.insert(characters, char)
        end
    end
    
    -- Get current player key
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = self.db.profile.pveSort.key
        parent.sortAscending = self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    local sortOptions = {
        {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
        {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
        {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
        {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
        {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
    }
    
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    
    -- ===== SORT CHARACTERS WITH FAVORITES ALWAYS ON TOP =====
    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        -- CRITICAL: Use GetCharacterKey() normalization to match PvECacheService DB keys (same as CurrencyUI/ReputationUI)
        local charKey = ns.Utilities:GetCharacterKey(char.name or "Unknown", char.realm or "Unknown")
        
        -- Separate current character
        if charKey == currentPlayerKey then
            currentChar = char
        elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local sortMode = self.db.profile.pveSort and self.db.profile.pveSort.key
        
        if sortMode and sortMode ~= "manual" then
            table.sort(list, function(a, b)
                if sortMode == "name" then
                    return (a.name or ""):lower() < (b.name or ""):lower()
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then
                        return (a.level or 0) > (b.level or 0)
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
                        return (a.itemLevel or 0) > (b.itemLevel or 0)
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                elseif sortMode == "gold" then
                    local goldA = ns.Utilities:GetCharTotalCopper(a)
                    local goldB = ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then
                        return goldA > goldB
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                end
                -- Fallback
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
        
        local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for _, char in ipairs(list) do
                local key = ns.Utilities:GetCharacterKey(char.name or "Unknown", char.realm or "Unknown")
                charMap[key] = char
            end
            
            -- Add characters in custom order
            for _, charKey in ipairs(customOrder) do
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                table.insert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            for _, char in ipairs(remaining) do
                table.insert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc → name asc
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
    end
    
    -- Sort both groups with custom order
    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")
    
    -- Merge: Current first, then favorites, then regular
    local sortedCharacters = {}
    if currentChar then
        table.insert(sortedCharacters, currentChar)
    end
    for _, char in ipairs(favorites) do
        table.insert(sortedCharacters, char)
    end
    for _, char in ipairs(regular) do
        table.insert(sortedCharacters, char)
    end
    characters = sortedCharacters
    
    -- ===== NAME WIDTH (measured from longest name; no compression — scroll handles overflow) =====
    local tempMeasure = FontManager:CreateFontString(parent, "body", "OVERLAY")
    tempMeasure:Hide()
    local maxNameRealmWidth = 0
    for _, c in ipairs(characters) do
        local realmStr = ns.Utilities and ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
        tempMeasure:SetText((c.name or "Unknown") .. "  -  " .. realmStr)
        local w = tempMeasure:GetStringWidth()
        if w and w > maxNameRealmWidth then maxNameRealmWidth = w end
    end
    local bin = ns.UI_RecycleBin
    if bin then tempMeasure:SetParent(bin) else tempMeasure:SetParent(nil) end
    local nameWidth = math.max(230, math.ceil(maxNameRealmWidth) + 8)

    -- Wide enough for left cluster + name + level/ilvl + inline columns → horizontal scrollbar when needed
    local scrollFrame = parent:GetParent()
    local viewportW = (scrollFrame and scrollFrame:GetWidth()) or 800
    local inlineTotal = 0
    for pci = 1, #PVE_COLUMNS do
        inlineTotal = inlineTotal + PVE_COLUMNS[pci].width
    end
    for gi = 1, #PVE_COLUMNS - 1 do
        inlineTotal = inlineTotal + GapBetweenColumns(gi)
    end
    inlineTotal = inlineTotal + COL_RIGHT_MARGIN
    local minScrollW = PVE_CHAR_HEADER_H_MARGIN + PVE_ROW_LEFT_CLUSTER_W + nameWidth + PVE_ROW_MIDDLE_MAX_W + inlineTotal
    parent:SetWidth(math.max(viewportW, minScrollW))

    -- Frozen column header strip (scrolls horizontally with data — same pattern as ProfessionsUI)
    local mainFrameRef = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    local columnHeaderInner = mainFrameRef and mainFrameRef.columnHeaderInner
    local colHeaderParent = columnHeaderInner or headerParent
    local colHeaderOverlayH = 0

    if columnHeaderClip then
        columnHeaderClip:SetHeight(COL_HEADER_HEIGHT + PVE_COLUMN_HEADER_PAD)
        colHeaderOverlayH = COL_HEADER_HEIGHT + PVE_COLUMN_HEADER_PAD
    end
    if columnHeaderInner then
        columnHeaderInner:SetWidth(parent:GetWidth())
    end

    -- ===== COLUMN HEADER ROW (icons only, no text labels) =====
    local colHeaderRow = ns.UI.Factory:CreateContainer(colHeaderParent, 10, COL_HEADER_HEIGHT)
    if columnHeaderInner then
        colHeaderRow:SetPoint("TOPLEFT", SIDE_MARGIN, 0)
        colHeaderRow:SetPoint("TOPRIGHT", -SIDE_MARGIN, 0)
    else
        colHeaderRow:SetPoint("TOPLEFT", headerParent, "TOPLEFT", SIDE_MARGIN, -headerYOffset)
        colHeaderRow:SetPoint("TOPRIGHT", headerParent, "TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
        headerYOffset = headerYOffset + COL_HEADER_HEIGHT + 2
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    local colX = -COL_RIGHT_MARGIN
    for hci = #PVE_COLUMNS, 1, -1 do
        local col = PVE_COLUMNS[hci]
        colX = colX - col.width
        local colCenterX = colX + col.width * 0.5

        if col.icon or col.iconAtlas then
            local hitFrame = CreateFrame("Frame", nil, colHeaderRow)
            hitFrame:SetSize(COL_ICON_SIZE + 4, COL_ICON_SIZE + 4)
            hitFrame:SetPoint("RIGHT", colHeaderRow, "RIGHT", colCenterX + COL_ICON_SIZE * 0.5 + 2, 0)

            local iconTex = hitFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(COL_ICON_SIZE, COL_ICON_SIZE)
            iconTex:SetPoint("CENTER")
            if col.iconAtlas and iconTex.SetAtlas then
                iconTex:SetTexture(nil)
                pcall(function()
                    iconTex:SetAtlas(col.iconAtlas)
                end)
                local okAtlas = iconTex.GetAtlas and iconTex:GetAtlas()
                if not okAtlas and col.icon then
                    iconTex:SetTexture(col.icon)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            elseif col.icon then
                iconTex:SetTexture(col.icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            if ShowTooltip then
                hitFrame:EnableMouse(true)
                local tooltipTitle = col.tooltipTitle
                if not tooltipTitle then
                    if col.crestCurrencyId then
                        local meta = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(col.crestCurrencyId)
                        tooltipTitle = meta and meta.name
                    end
                    tooltipTitle = tooltipTitle or col.key or ""
                end
                hitFrame:SetScript("OnEnter", function(self)
                    ShowTooltip(self, {
                        type = "custom",
                        icon = col.iconAtlas or col.icon,
                        iconIsAtlas = col.iconAtlas ~= nil,
                        title = tooltipTitle,
                        lines = {},
                        anchor = "ANCHOR_BOTTOM"
                    })
                end)
                hitFrame:SetScript("OnLeave", function()
                    if HideTooltip then HideTooltip() end
                end)
                BindForwardScrollWheel(hitFrame)
            end
        end

        if hci > 1 then
            colX = colX - GapBetweenColumns(hci - 1)
        end
    end

    colHeaderRow:Show()

    -- Push scroll content below frozen column header overlay (ProfessionsUI pattern)
    yOffset = yOffset + colHeaderOverlayH

    -- ===== LOADING STATE (after column strip so content does not sit under frozen headers) =====
    if ns.PvELoadingState and ns.PvELoadingState.isLoading then
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                ns.PvELoadingState,
                (ns.L and ns.L["LOADING_PVE"]) or "Loading PvE Data..."
            )
            return newYOffset + 50
        end
    end

    -- ===== ERROR STATE (IF DATA COLLECTION FAILED) =====
    if ns.PvELoadingState and ns.PvELoadingState.error and not ns.PvELoadingState.isLoading then
        local UI_CreateErrorStateCard = ns.UI_CreateErrorStateCard
        if UI_CreateErrorStateCard then
            yOffset = UI_CreateErrorStateCard(parent, yOffset, ns.PvELoadingState.error)
        end
    end

    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local _, height = CreateEmptyStateCard(parent, "pve", yOffset)
        return yOffset + height
    end

    -- ===== CHARACTER COLLAPSIBLE HEADERS (Favorites first, then regular) =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        -- CRITICAL: Match DB keys (currency + PvE cache) — same canonical form as scans / SavedVariables.
        local charKey = ns.Utilities:GetCharacterKey(char.name or "Unknown", char.realm or "Unknown")
        if ns.Utilities.GetCanonicalCharacterKey then
            charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        end
        local isFavorite = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, charKey)
        
        -- Get PvE data from PvECacheService
        local pveData = self:GetPvEData(charKey) or {}
        
        -- Build legacy-compatible structure for rendering (backward compatibility)
        local pve = {
            keystone = pveData.keystone,
            vaultActivities = pveData.vaultActivities,
            hasUnclaimedRewards = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards,
            raidLockouts = pveData.raidLockouts,
            worldBosses = pveData.worldBosses,
            mythicPlus = pveData.mythicPlus,
            delves = pveData.delves,
        }
        
        -- Only the current (online) character starts expanded; all others collapsed.
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        local charExpanded = IsExpanded(charExpandKey, isCurrentChar)
        
        -- Create collapsible header
        -- Returns: header Button, expand arrow Texture (not a click target — use charHeader:Click() for toggle)
        local charHeader, expandIconTex = CreateCollapsibleHeader(
            parent,
            "", -- Empty text, we'll add it manually
            charExpandKey,
            charExpanded,
            function(isExpanded) ToggleExpand(charExpandKey, isExpanded) end,
            nil, nil, nil, true  -- noCategoryIcon: use favorite star only, no default gold icon
        )
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        if charHeader.SetClippingChildren then
            charHeader:SetClippingChildren(true)
        end
        
        yOffset = yOffset + GetLayout().headerSpacing  -- Standardized header spacing
        
        -- Favorite icon (view-only, left side, next to collapse button)
        -- Match Characters/Professions tabs: 33px column, 65% visual icon (~21px)
        local StyleFavoriteIcon = ns.UI_StyleFavoriteIcon
        local favColSize = 33
        local favIconSize = favColSize * 0.65
        
        local favFrame = CreateFrame("Frame", nil, charHeader)
        favFrame:SetSize(favColSize, favColSize)
        favFrame:SetPoint("LEFT", expandIconTex, "RIGHT", 4, 0)
        
        local favIcon = favFrame:CreateTexture(nil, "ARTWORK")
        favIcon:SetSize(favIconSize, favIconSize)
        favIcon:SetPoint("CENTER", 0, 0)
        StyleFavoriteIcon(favIcon, isFavorite)
        favFrame:Show()
        
        -- Character name text
        local xOffset = 0
        local spacerWidth = 30    -- Spacing around bullets (equal spacing)
        local levelWidth = 60     -- "Lv XX" 
        local ilvlWidth = 80      -- "iLvl XXX"
        
        -- Column 1: Character Name - Realm (single line, fixed width, left aligned)
        local charNameText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charNameText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        charNameText:SetWidth(nameWidth)
        charNameText:SetJustifyH("LEFT")
        local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ""
        charNameText:SetText(string.format("|cff%02x%02x%02x%s  -  %s|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name,
            displayRealm))
        xOffset = xOffset + nameWidth
        
        -- Column 2: Bullet separator (centered in spacer)
        local bullet1 = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        bullet1:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        bullet1:SetWidth(spacerWidth)
        bullet1:SetJustifyH("CENTER")
        bullet1:SetText("|cff666666•|r")
        xOffset = xOffset + spacerWidth
        
        -- Column 3: Level (fixed width, CENTER aligned for visual balance)
        local levelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        levelText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        levelText:SetWidth(levelWidth)
        levelText:SetJustifyH("CENTER")  -- CENTER for equal spacing on both sides
        local levelFormat = (ns.L and ns.L["LV_FORMAT"]) or "Lv %d"
        local levelString = string.format("|cff%02x%02x%02x" .. levelFormat .. "|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.level or 1)
        levelText:SetText(levelString)
        xOffset = xOffset + levelWidth
        
        -- Column 4: Bullet separator (only if iLvl exists, centered in spacer)
        if char.itemLevel and char.itemLevel > 0 then
            local bullet2 = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
            bullet2:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
            bullet2:SetWidth(spacerWidth)
            bullet2:SetJustifyH("CENTER")
            bullet2:SetText("|cff666666•|r")
            xOffset = xOffset + spacerWidth
            
            -- Column 5: iLvl (fixed width, left aligned)
            local ilvlText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
            ilvlText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
            ilvlText:SetWidth(ilvlWidth)
            ilvlText:SetJustifyH("LEFT")
            local ilvlFormat = (ns.L and ns.L["ILVL_FORMAT"]) or "iLvl %d"
            ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", char.itemLevel))
        end
        
        -- ===== INLINE COLUMN DATA (right-aligned, matching column headers) =====
        do
            local shardData = (PVE_SHARDS_ID and WarbandNexus:GetCurrencyData(PVE_SHARDS_ID, charKey)) or nil
            local shardQty = shardData and shardData.quantity or 0
            local shardMax = shardData and shardData.maxQuantity or 0
            local shardTE = shardData and shardData.totalEarned
            local shardSM = shardData and shardData.seasonMax

            local keyData = (PVE_RESTORED_KEY_ID and WarbandNexus:GetCurrencyData(PVE_RESTORED_KEY_ID, charKey)) or nil
            local keyQty = keyData and keyData.quantity or 0

            -- Vault summary from activities
            local vaultActs = pve.vaultActivities or {}
            -- Determine unlocked slot count from the best vault track (Raid / M+ / World / PvP).
            local function GetUnlockedCount(activityList)
                local unlocked = 0
                if not activityList then return unlocked end
                for idx = 1, #activityList do
                    local act = activityList[idx]
                    if act and act.threshold and act.threshold > 0 and act.progress and act.progress >= act.threshold then
                        unlocked = unlocked + 1
                    end
                end
                return unlocked
            end
            local raidUnlocked = GetUnlockedCount(vaultActs.raids)
            local dungeonUnlocked = GetUnlockedCount(vaultActs.mythicPlus)
            local worldUnlocked = GetUnlockedCount(vaultActs.world)

            local READY_ICON = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:13|t"
            local NOT_READY_ICON = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:13|t"
            local function FormatVaultSlots(unlocked, total)
                total = total or 3
                local parts = {}
                for s = 1, total do
                    parts[s] = (s <= unlocked) and READY_ICON or NOT_READY_ICON
                end
                -- Tight triplet; groups separated by column gaps (GapBetweenColumns), not spaces here
                return table.concat(parts, "")
            end

            --- Format currency for inline row: always show current quantity.
            local function FormatCurrencyStatus(qty)
                qty = qty or 0
                if qty > 0 then
                    return FormatNumber(qty)
                end
                return "\226\128\148"
            end

            local function BuildCurrencyTooltip(qty, maxQty, totalEarned, seasonMax)
                local lines = {}
                local currentLabel = (ns.L and ns.L["CURRENT_ENTRIES_LABEL"]) or "Current:"
                local seasonLabel = (ns.L and ns.L["SEASON"]) or "Season"
                local remainingSuffix = (ns.L and ns.L["VAULT_REMAINING_SUFFIX"]) or "remaining"
                local cappedText = CAPPED or "Capped"
                qty = qty or 0
                maxQty = maxQty or 0
                local sm = tonumber(seasonMax) or 0
                local teN = tonumber(totalEarned)

                local hasSeasonProgress = sm > 0
                if hasSeasonProgress then
                    local teForSeason = (teN ~= nil) and teN or 0
                    local remSeason = math.max(sm - teForSeason, 0)
                    table.insert(lines, { text = string.format("%s %s", currentLabel, FormatNumber(qty)), color = {1, 1, 1} })
                    table.insert(lines, { text = string.format("%s: %s / %s", seasonLabel, FormatNumber(teForSeason), FormatNumber(sm)), color = {1, 1, 1} })
                    if remSeason > 0 then
                        table.insert(lines, { text = string.format("%s %s", FormatNumber(remSeason), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    return lines
                end

                local cap = maxQty
                if cap and cap > 0 then
                    local rem = math.max(cap - qty, 0)
                    table.insert(lines, { text = string.format("%s / %s", FormatNumber(qty), FormatNumber(cap)), color = {1, 1, 1} })
                    if rem > 0 then
                        table.insert(lines, { text = string.format("%s %s", FormatNumber(rem), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    return lines
                end

                table.insert(lines, { text = FormatNumber(qty), color = {1, 1, 1} })
                return lines
            end

            -- Render inline values (right to left, matching column header positions)
            local inlineX = -COL_RIGHT_MARGIN
            local colValues = {}

            local DIM_COLOR = {0.45, 0.45, 0.45}
            local NORMAL_COLOR = {1, 1, 1}
            local CAP_OPEN_COLOR = {0.5, 1, 0.5}
            local CAPPED_COLOR = {1, 0.35, 0.35}
            local EM_DASH = "\226\128\148"

            local function GetCapStateColor(qty, maxQty, totalEarned, seasonMax)
                local sm = tonumber(seasonMax) or 0
                if sm > 0 then
                    local teN = tonumber(totalEarned)
                    if teN == nil then
                        return NORMAL_COLOR
                    end
                    local rem = math.max(sm - teN, 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                if maxQty and maxQty > 0 then
                    local rem = math.max(maxQty - (qty or 0), 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                return NORMAL_COLOR
            end

            local FormatSeasonLine = ns.UI_FormatSeasonProgressCurrencyLine
            for i = 1, #PVE_DAWNCRESTS do
                local cd = WarbandNexus:GetCurrencyData(PVE_DAWNCRESTS[i].id, charKey)
                local q = cd and cd.quantity or 0
                local m = cd and cd.maxQuantity or 0
                local te = cd and cd.totalEarned
                local sm = cd and cd.seasonMax
                local txt = FormatSeasonLine and FormatSeasonLine(cd) or FormatCurrencyStatus(q)
                local tipTitle = PVE_DAWNCRESTS[i] and PVE_DAWNCRESTS[i].name or ((ns.L and ns.L["TAB_CURRENCY"]) or "Currency")
                colValues[i] = {
                    text = txt,
                    richText = FormatSeasonLine ~= nil,
                    color = (not FormatSeasonLine) and ((txt == EM_DASH) and DIM_COLOR or GetCapStateColor(q, m, te, sm)) or nil,
                    tooltip = BuildCurrencyTooltip(q, m, te, sm),
                    tooltipTitle = tipTitle,
                    tooltipIcon = cd and cd.icon,
                    currencyID = PVE_DAWNCRESTS[i].id,
                }
            end

            local n = #PVE_DAWNCRESTS
            local shardTxt = FormatSeasonLine and FormatSeasonLine(shardData) or FormatCurrencyStatus(shardQty)
            colValues[n + 1] = {
                text = shardTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((shardTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(shardQty, shardMax, shardTE, shardSM)) or nil,
                tooltip = BuildCurrencyTooltip(shardQty, shardMax, shardTE, shardSM),
                tooltipTitle = (ns.L and ns.L["PVE_COL_COFFER_SHARDS"]) or "Coffer Shards",
                tooltipIcon = shardData and shardData.icon,
                currencyID = PVE_SHARDS_ID,
            }
            colValues[n + 2] = { text = keyQty > 0 and FormatNumber(keyQty) or EM_DASH, color = keyQty > 0 and NORMAL_COLOR or DIM_COLOR }
            local raidTotal = vaultActs.raids and #vaultActs.raids or 3
            local dungeonTotal = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
            local worldTotal = vaultActs.world and #vaultActs.world or 3
            colValues[n + 3] = { text = FormatVaultSlots(raidUnlocked, raidTotal), color = {1, 1, 1} }
            colValues[n + 4] = { text = FormatVaultSlots(dungeonUnlocked, dungeonTotal), color = {1, 1, 1} }
            colValues[n + 5] = { text = FormatVaultSlots(worldUnlocked, worldTotal), color = {1, 1, 1} }
            -- Bountiful / Trovehunter tracking is warband-scoped; always use live quest flags (same for every row).
            local bountifulDone = WarbandNexus.IsBountifulDelveWeeklyDone and WarbandNexus:IsBountifulDelveWeeklyDone() or false
            colValues[n + 6] = { text = bountifulDone and READY_ICON or NOT_READY_ICON, color = {1, 1, 1} }

            for ci = #PVE_COLUMNS, 1, -1 do
                local col = PVE_COLUMNS[ci]
                local val = colValues[ci]
                if val then
                    local cw = col.width
                    inlineX = inlineX - cw
                    local colText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
                    colText:SetPoint("RIGHT", charHeader, "RIGHT", inlineX + cw, 0)
                    colText:SetWidth(cw)
                    colText:SetJustifyH("CENTER")
                    colText:SetWordWrap(false)
                    colText:SetText(val.text)
                    if not val.richText and val.color then
                        colText:SetTextColor(val.color[1], val.color[2], val.color[3])
                    elseif val.richText then
                        colText:SetTextColor(1, 1, 1)
                    end
                    if val.tooltip and ShowTooltip then
                        local hit = CreateFrame("Frame", nil, charHeader)
                        hit:SetPoint("RIGHT", charHeader, "RIGHT", inlineX + cw, 0)
                        hit:SetSize(cw, ROW_HEIGHT)
                        hit:EnableMouse(true)
                        hit:SetScript("OnEnter", function(self)
                            if val.currencyID then
                                ShowTooltip(self, {
                                    type = "currency",
                                    currencyID = val.currencyID,
                                    charKey = charKey,
                                    anchor = "ANCHOR_TOP",
                                })
                            else
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = val.tooltipIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    title = val.tooltipTitle or ((ns.L and ns.L["TAB_CURRENCY"]) or "Currency"),
                                    lines = val.tooltip,
                                    anchor = "ANCHOR_TOP",
                                })
                            end
                        end)
                        hit:SetScript("OnLeave", function()
                            if HideTooltip then HideTooltip() end
                        end)
                        hit:SetScript("OnMouseUp", function(_, button)
                            if button == "LeftButton" and charHeader then
                                charHeader:Click()
                            end
                        end)
                        BindForwardScrollWheel(hit)
                    end
                    if ci > 1 then
                        inlineX = inlineX - GapBetweenColumns(ci - 1)
                    end
                end
            end
        end
        
        charHeader:SetAlpha(1)
        
        -- 3 Cards (only when expanded)
        if charExpanded then
            local cardContainer = ns.UI.Factory:CreateContainer(parent)
            cardContainer:SetPoint("TOPLEFT", 10, -yOffset)
            cardContainer:SetPoint("TOPRIGHT", -10, -yOffset)
            
            -- Calculate responsive card widths (pixel-snapped)
            -- Order: Overall Score (35%) → Keystone+Affixes (35%) → Vault (30%)
            local PixelSnap = ns.PixelSnap or function(v) return v end
            local totalWidth = PixelSnap(parent:GetWidth() - 20)
            local card1Width = PixelSnap(totalWidth * 0.35)  -- Overall Score (M+ dungeons)
            local card2Width = PixelSnap(totalWidth * 0.35)  -- Keystone + Affixes
            local card3Width = PixelSnap(totalWidth - card1Width - card2Width)  -- Vault (remainder ~30%)
            local cardSpacing = 5
            
            -- Card height will be calculated from vault card grid (with fallback)
            local cardHeight = 200  -- Default fallback height
            
            -- === CARD 1: OVERALL SCORE + M+ DUNGEONS (35%) ===
            local baseCardHeight = 200
            local mplusCard = CreateCard(cardContainer, baseCardHeight)
            mplusCard:SetPoint("TOPLEFT", 0, 0)
            mplusCard:SetWidth(PixelSnap(card1Width - cardSpacing))
            
            local mplusY = 15
            
            if not pve.mythicPlus then
                pve.mythicPlus = { overallScore = 0, bestRuns = {} }
            end
            
            local totalScore = pve.mythicPlus.overallScore or 0
            local scoreText = FontManager:CreateFontString(mplusCard, "title", "OVERLAY")
            scoreText:SetPoint("TOP", mplusCard, "TOP", 0, -mplusY)
            
            local scoreColor
            if totalScore >= 2500 then
                scoreColor = "|cffff8000"
            elseif totalScore >= 2000 then
                scoreColor = "|cffa335ee"
            elseif totalScore >= 1500 then
                scoreColor = "|cff0070dd"
            elseif totalScore >= 1000 then
                scoreColor = "|cff1eff00"
            elseif totalScore >= 500 then
                scoreColor = "|cffffffff"
            else
                scoreColor = "|cff9d9d9d"
            end
            
            local overallScoreLabel = (ns.L and ns.L["OVERALL_SCORE_LABEL"]) or "Overall Score:"
            scoreText:SetText(string.format("%s %s%s|r", overallScoreLabel, scoreColor, FormatNumber(totalScore)))
            mplusY = mplusY + 35
            
            if pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons > 0 then
                local totalDungeons = #pve.mythicPlus.dungeons
                local iconSize = 48
                local maxIconsPerRow = 6
                local iconSpacing = 6
                
                local numRows = math.ceil(totalDungeons / maxIconsPerRow)
                
                local highestKeyLevel = 0
                for _, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    if dungeon.bestLevel and dungeon.bestLevel > highestKeyLevel then
                        highestKeyLevel = dungeon.bestLevel
                    end
                end
                
                local cardWidthInner = (card1Width - cardSpacing)
                local borderPadding = 2
                local gridY = mplusY
                local rowSpacing = 24
                
                local dungeonsByRow = {}
                for i = 1, numRows do
                    dungeonsByRow[i] = {}
                end
                
                for i, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    local row = math.floor((i - 1) / maxIconsPerRow) + 1
                    table.insert(dungeonsByRow[row], dungeon)
                end
                
                local sidePadding = 12
                local firstRowIcons = math.min(maxIconsPerRow, totalDungeons)
                local availableWidth = cardWidthInner - (2 * (borderPadding + sidePadding))
                local consistentSpacing = (availableWidth - (firstRowIcons * iconSize)) / (firstRowIcons - 1)
                
                for rowIndex, dungeons in ipairs(dungeonsByRow) do
                    local iconsInThisRow = #dungeons
                    local rowY = gridY + ((rowIndex - 1) * (iconSize + rowSpacing))
                    
                    local startX
                    
                    if rowIndex == 1 and iconsInThisRow >= 4 then
                        startX = borderPadding + sidePadding
                    else
                        local totalRowWidth = (iconsInThisRow * iconSize) + ((iconsInThisRow - 1) * consistentSpacing)
                        startX = (cardWidthInner - totalRowWidth) / 2
                    end
                    
                    for colIndex, dungeon in ipairs(dungeons) do
                        local iconX = startX + ((colIndex - 1) * (iconSize + consistentSpacing))
                        
                        local iconFrame = CreateIcon(mplusCard, dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark", iconSize, false, nil, false)
                        local roundedX = math.floor(iconX + 0.5)
                        local roundedY = math.floor(rowY + 0.5)
                        iconFrame:SetPoint("TOPLEFT", roundedX, -roundedY)
                        iconFrame:EnableMouse(true)
                        BindForwardScrollWheel(iconFrame)
                        
                        local texture = iconFrame.texture
                        
                        if texture then
                            texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
                        end
                        local hasBestLevel = dungeon.bestLevel and dungeon.bestLevel > 0
                        local isHighest = hasBestLevel and dungeon.bestLevel == highestKeyLevel and highestKeyLevel >= 10
                        
                        if iconFrame.BorderTop then
                            local r, g, b, a
                            if isHighest then
                                r, g, b, a = 1, 0.82, 0, 0.9
                            elseif hasBestLevel then
                                local accentColor = COLORS.accent
                                r, g, b, a = accentColor[1], accentColor[2], accentColor[3], 0.8
                            else
                                r, g, b, a = 0.4, 0.4, 0.4, 0.6
                            end
                            iconFrame.BorderTop:SetVertexColor(r, g, b, a)
                            iconFrame.BorderBottom:SetVertexColor(r, g, b, a)
                            iconFrame.BorderLeft:SetVertexColor(r, g, b, a)
                            iconFrame.BorderRight:SetVertexColor(r, g, b, a)
                        end
                    
                    if hasBestLevel then
                        local backdrop = iconFrame:CreateTexture(nil, "BACKGROUND")
                        backdrop:SetSize(iconSize * 0.8, iconSize * 0.5)
                        backdrop:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        backdrop:SetColorTexture(0, 0, 0, 0.7)
                        
                        local levelShadow = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelShadow:SetPoint("CENTER", iconFrame, "CENTER", 1, -1)
                        levelShadow:SetText(string.format("|cff000000+%d|r", dungeon.bestLevel))
                        
                        local levelText = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        levelText:SetText(string.format("|cffffcc00+%d|r", dungeon.bestLevel))
                        
                        local dungeonScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        dungeonScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        
                        local score = dungeon.score or 0
                        local dScoreColor
                        if score >= 312 then
                            dScoreColor = "|cffff8000"
                        elseif score >= 250 then
                            dScoreColor = "|cffa335ee"
                        elseif score >= 187 then
                            dScoreColor = "|cff0070dd"
                        elseif score >= 125 then
                            dScoreColor = "|cff1eff00"
                        elseif score >= 62 then
                            dScoreColor = "|cffffffff"
                        else
                            dScoreColor = "|cff9d9d9d"
                        end
                        
                        dungeonScore:SetText(string.format("%s%s|r", dScoreColor, FormatNumber(score)))
                    else
                        texture:SetDesaturated(true)
                        texture:SetAlpha(0.4)
                        
                        local notDone = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        notDone:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        notDone:SetText("|cff666666?|r")
                        
                        local zeroScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        zeroScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        zeroScore:SetText("|cff444444-|r")
                    end
                    
                    if ShowTooltip and HideTooltip then
                        iconFrame:SetScript("OnEnter", function(self)
                            local tooltipLines = {}
                            if dungeon.name then
                                table.insert(tooltipLines, { text = dungeon.name, color = {1, 1, 1} })
                            end
                            if hasBestLevel then
                                local bestKeyLabel = (ns.L and ns.L["VAULT_BEST_KEY"]) or "Best Key:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffcc00+%d|r", bestKeyLabel, dungeon.bestLevel),
                                    color = {0.9, 0.9, 0.9}
                                })
                                local scoreLabel = (ns.L and ns.L["VAULT_SCORE"]) or "Score:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffffff%s|r", scoreLabel, FormatNumber(dungeon.score or 0)),
                                    color = {0.9, 0.9, 0.9}
                                })
                            else
                                local notCompletedLabel = (ns.L and ns.L["NOT_COMPLETED_SEASON"]) or "Not completed this season"
                                table.insert(tooltipLines, {
                                    text = "|cff888888" .. notCompletedLabel .. "|r",
                                    color = {0.6, 0.6, 0.6}
                                })
                            end
                            ShowTooltip(self, {
                                type = "custom",
                                icon = dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                                title = dungeon.name or ((ns.L and ns.L["VAULT_DUNGEON"]) or "Dungeon"),
                                lines = tooltipLines,
                                anchor = "ANCHOR_TOP"
                            })
                        end)
                        iconFrame:SetScript("OnLeave", function(self)
                            HideTooltip()
                        end)
                    end
                    
                    iconFrame:Show()
                    end
                end
            else
                local noData = FontManager:CreateFontString(mplusCard, "small", "OVERLAY")
                noData:SetPoint("TOPLEFT", 15, -mplusY)
                local noDataLabel = (ns.L and ns.L["NO_DATA"]) or "No data"
                noData:SetText("|cff666666" .. noDataLabel .. "|r")
            end
            
            mplusCard:Show()
            
            -- === CARD 2: KEYSTONE + AFFIXES (35%) ===
            local summaryCard = CreateCard(cardContainer, cardHeight)
            summaryCard:SetPoint("TOPLEFT", PixelSnap(card1Width), 0)
            summaryCard:SetWidth(PixelSnap(card2Width - cardSpacing))
            
            local cardPadding = 10
            local columnSpacing = 15
            local topColumnWidth = (card2Width - cardSpacing - cardPadding * 2 - columnSpacing) / 2
            
            -- Keystone (Left Column)
            local col1X = cardPadding
            local col1Y = 12
            
            local keystoneTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            keystoneTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col1X + topColumnWidth / 2, -col1Y)
            local keystoneLabel = (ns.L and ns.L["KEYSTONE"]) or "Keystone"
            keystoneTitle:SetText("|cffffffff" .. keystoneLabel .. "|r")
            keystoneTitle:SetJustifyH("CENTER")
            
            local keystoneData = pveData and pveData.keystone
            
            if keystoneData and keystoneData.level and keystoneData.level > 0 and keystoneData.mapID then
                local keystoneLevel = keystoneData.level
                local keystoneMapID = keystoneData.mapID
                
                if C_ChallengeMode then
                    local mapName, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(keystoneMapID)
                    
                    local iconSize = 50
                    local keystoneIcon = CreateIcon(summaryCard, texture or "Interface\\Icons\\Achievement_ChallengeMode_Gold", iconSize, false, nil, false)
                    keystoneIcon:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -5)
                    
                    if keystoneIcon.BorderTop then
                        local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                        keystoneIcon.BorderTop:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderBottom:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderLeft:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderRight:SetVertexColor(r, g, b, a)
                    end
                    keystoneIcon:Show()
                    
                    local kLevelText = FontManager:CreateFontString(summaryCard, "header", "OVERLAY")
                    kLevelText:SetPoint("TOP", keystoneIcon, "BOTTOM", 0, -3)
                    kLevelText:SetText(string.format("|cff00ff00+%d|r", keystoneLevel))
                    kLevelText:SetJustifyH("CENTER")
                    
                    local nameText = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
                    nameText:SetPoint("TOP", kLevelText, "BOTTOM", 0, 0)
                    nameText:SetWidth(topColumnWidth - 10)
                    nameText:SetJustifyH("CENTER")
                    nameText:SetWordWrap(true)
                    nameText:SetMaxLines(2)
                    nameText:SetText(mapName or ((ns.L and ns.L["KEYSTONE"]) or "Keystone"))
                else
                    local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                    local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                    noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                    noKeyText:SetJustifyH("CENTER")
                end
            else
                local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                noKeyText:SetJustifyH("CENTER")
            end
            
            -- Affixes (Right Column)
            local col2X = col1X + topColumnWidth + columnSpacing
            local col2Y = col1Y
            
            local affixesTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            affixesTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col2X + topColumnWidth / 2, -col2Y)
            local affixesLabel = (ns.L and ns.L["AFFIXES"]) or "Affixes"
            affixesTitle:SetText("|cffffffff" .. affixesLabel .. "|r")
            affixesTitle:SetJustifyH("CENTER")
            
            local allPveData = self:GetPvEData()
            local currentAffixes = allPveData and allPveData.currentAffixes
            
            if currentAffixes and #currentAffixes > 0 then
                local affixSize = 38
                local affixSpacing = 10
                local maxAffixes = math.min(#currentAffixes, 4)
                
                local aTotalWidth = (maxAffixes * affixSize) + ((maxAffixes - 1) * affixSpacing)
                local aStartX = col2X + (topColumnWidth - aTotalWidth) / 2
                local aStartY = col2Y + 23
                
                for i, affixData in ipairs(currentAffixes) do
                    if i <= maxAffixes then
                        local name = affixData.name
                        local description = affixData.description
                        local filedataid = affixData.icon
                        
                        if filedataid then
                            local xOffset = aStartX + ((i - 1) * (affixSize + affixSpacing))
                            local yOffset = aStartY
                            
                            local affixIcon = CreateIcon(summaryCard, filedataid, affixSize, false, nil, false)
                            local roundedX = math.floor(xOffset + 0.5)
                            local roundedY = math.floor(yOffset + 0.5)
                            affixIcon:SetPoint("TOPLEFT", roundedX, -roundedY)
                            
                            if affixIcon.BorderTop then
                                local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                                affixIcon.BorderTop:SetVertexColor(r, g, b, a)
                                affixIcon.BorderBottom:SetVertexColor(r, g, b, a)
                                affixIcon.BorderLeft:SetVertexColor(r, g, b, a)
                                affixIcon.BorderRight:SetVertexColor(r, g, b, a)
                            end
                            
                            if ShowTooltip then
                                affixIcon:EnableMouse(true)
                                affixIcon:SetScript("OnEnter", function(self)
                                    ShowTooltip(self, {
                                        type = "custom",
                                        icon = filedataid,
                                        title = name or ((ns.L and ns.L["AFFIX_TITLE_FALLBACK"]) or "Affix"),
                                        description = description,
                                        lines = {},
                                        anchor = "ANCHOR_RIGHT"
                                    })
                                end)
                                affixIcon:SetScript("OnLeave", function(self)
                                    if HideTooltip then HideTooltip() end
                                end)
                                BindForwardScrollWheel(affixIcon)
                            end
                            
                            affixIcon:Show()
                        end
                    end
                end
            else
                local noAffixesText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noAffixesText:SetPoint("TOP", affixesTitle, "BOTTOM", 0, -30)
                local noAffixesLabel = (ns.L and ns.L["NO_AFFIXES"]) or "No Affixes"
                noAffixesText:SetText("|cff888888" .. noAffixesLabel .. "|r")
                noAffixesText:SetJustifyH("CENTER")
            end

            -- Bottom row: Dawncrest/currency snapshot (restored under Keystone card)
            local crestCurrencies = {
                { id = 3383, fallbackIcon = 134400 },
                { id = 3341, fallbackIcon = 134400 },
                { id = 3343, fallbackIcon = 134400 },
                { id = 3345, fallbackIcon = 134400 },
                { id = 3347, fallbackIcon = 134400 },
            }
            local numCurrencies = #crestCurrencies
            local rowIconSize = 30
            local rowSpacing = 8
            local rowTopY = 138
            local rowAvailableW = (card2Width - cardSpacing) - (cardPadding * 2)
            local rowItemW = (rowAvailableW - (rowSpacing * (numCurrencies - 1))) / numCurrencies
            local rowStartX = cardPadding

            for ci = 1, numCurrencies do
                local curr = crestCurrencies[ci]
                local currencyEntry = WarbandNexus:GetCurrencyData(curr.id, charKey)
                local iconFileID = currencyEntry and currencyEntry.icon or curr.fallbackIcon
                local quantity = currencyEntry and currencyEntry.quantity or 0
                local maxQuantity = currencyEntry and currencyEntry.maxQuantity or 0
                local currencyName = currencyEntry and currencyEntry.name or ((ns.L and ns.L["TAB_CURRENCY"]) or "Currency")

                local slotX = rowStartX + ((ci - 1) * (rowItemW + rowSpacing))
                local iconCenterX = slotX + (rowItemW * 0.5)

                local crestIcon = CreateIcon(summaryCard, iconFileID, rowIconSize, false, nil, false)
                crestIcon:SetPoint("TOP", summaryCard, "TOPLEFT", math.floor(iconCenterX + 0.5), -rowTopY)
                crestIcon:Show()

                local amountText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                amountText:SetPoint("TOP", crestIcon, "BOTTOM", 0, -2)
                amountText:SetWidth(rowItemW + 8)
                amountText:SetJustifyH("CENTER")
                amountText:SetWordWrap(false)
                if ns.UI_FormatSeasonProgressCurrencyLine then
                    amountText:SetText(ns.UI_FormatSeasonProgressCurrencyLine(currencyEntry))
                else
                    local amtColor = "|cffffffff"
                    if maxQuantity > 0 then
                        local pct = (quantity / maxQuantity) * 100
                        if pct >= 100 then amtColor = "|cffff4444"
                        elseif pct >= 80 then amtColor = "|cffffaa00" end
                    end
                    amountText:SetText(string.format("%s%s|r", amtColor, FormatNumber(quantity)))
                end

                if ShowTooltip and HideTooltip then
                    crestIcon:EnableMouse(true)
                    crestIcon:SetScript("OnEnter", function(self)
                        ShowTooltip(self, {
                            type = "currency",
                            currencyID = curr.id,
                            charKey = charKey,
                            anchor = "ANCHOR_TOP",
                        })
                    end)
                    crestIcon:SetScript("OnLeave", function()
                        HideTooltip()
                    end)
                    BindForwardScrollWheel(crestIcon)
                end
            end
            
            summaryCard:Show()
            
            -- === CARD 3: GREAT VAULT (30%) ===
            local vaultCard = CreateCard(cardContainer, baseCardHeight)
            vaultCard:SetPoint("TOPLEFT", PixelSnap(card1Width + card2Width), 0)
            local baseCardWidth = card3Width
            
            -- Helper function to get WoW icon textures for vault activity types
            local function GetVaultTypeIcon(typeName)
                local icons = {
                    ["Raid"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
                    ["M+"] = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
                    ["World"] = "Interface\\Icons\\INV_Misc_Map_01"
                }
                return icons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            
            local vaultY = 0  -- No top padding - start from 0
        
        -- Get vault activities (from PvECacheService structure)
        local vaultActivitiesData = pve.vaultActivities
        
        -- CRITICAL: Create a NEW table on each render (don't reuse old data)
        local vaultActivities = {}
        
        -- Flatten vault activities (raids, mythicPlus, pvp, world) into single array
        if vaultActivitiesData then
            if vaultActivitiesData.raids then
                for _, activity in ipairs(vaultActivitiesData.raids) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.mythicPlus then
                for _, activity in ipairs(vaultActivitiesData.mythicPlus) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.pvp then
                for _, activity in ipairs(vaultActivitiesData.pvp) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.world then
                for _, activity in ipairs(vaultActivitiesData.world) do
                    table.insert(vaultActivities, activity)
                end
            end
        end
        
        if #vaultActivities > 0 then
            local vaultByType = {}
            for _, activity in ipairs(vaultActivities) do
                -- CRITICAL: Use locale-independent internal keys for vaultByType.
                -- Helper functions (IsVaultSlotAtMax, GetVaultActivityDisplayText, etc.)
                -- expect "Raid", "M+", "World", "PvP" — NOT locale strings.
                local internalKey = nil
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then internalKey = "Raid"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then internalKey = "M+"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then internalKey = "PvP"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then internalKey = "World"
                    end
                else
                    -- Fallback numeric values based on API:
                    -- 1 = Activities (M+), 2 = RankedPvP, 3 = Raid, 6 = World
                    if typeNum == 3 then internalKey = "Raid"
                    elseif typeNum == 1 then internalKey = "M+"
                    elseif typeNum == 2 then internalKey = "PvP"
                    elseif typeNum == 6 then internalKey = "World"
                    end
                end
                
                if internalKey then
                    if not vaultByType[internalKey] then vaultByType[internalKey] = {} end
                    table.insert(vaultByType[internalKey], activity)
                end
            end
            
            -- 4x3 GRID LAYOUT - PERFECT EQUAL DIVISIONS (WITH BORDER PADDING)
            
            -- Border padding (2px on all sides for 1px border)
            local borderPadding = 2
            
            -- Adjust dimensions to ensure perfect integer division
            local numRows = 3
            local numCols = 4
            
            -- Calculate perfect cell sizes (accounting for border)
            local availableWidth = baseCardWidth - (borderPadding * 2)
            local availableHeight = baseCardHeight - (borderPadding * 2)
            
            local cellWidth = math.floor(availableWidth / numCols)
            local cellHeight = math.floor(availableHeight / numRows)
            
            -- Recalculate exact card dimensions (add border padding back)
            cardWidth = (cellWidth * numCols) + (borderPadding * 2)
            cardHeight = (cellHeight * numRows) + (borderPadding * 2)
            
            -- CRITICAL: Set card dimensions for proper border
            vaultCard:SetHeight(cardHeight)
            vaultCard:SetWidth(cardWidth)
            
            -- Re-apply border after dimension change
            if ApplyVisuals then
                local accentColor = COLORS.accent
                ApplyVisuals(vaultCard, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
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
            
            for rowIndex, typeName in ipairs(sortedTypes) do
                -- Map display name to actual data key
                local dataKey = typeName
                if typeName == "Dungeon" then
                    dataKey = "M+"
                end
                local activities = vaultByType[dataKey]
                
                -- Calculate Y position (row 0, 1, 2) with border padding
                local rowY = borderPadding + ((rowIndex - 1) * cellHeight)
                
                -- Create row frame container (using Factory pattern)
                local rowFrame = ns.UI.Factory:CreateContainer(vaultCard)
                rowFrame:SetPoint("TOPLEFT", borderPadding, -rowY)
                rowFrame:SetSize(cardWidth - (borderPadding * 2), cellHeight)
                
                -- Row background: solid black (consistent with Overall/Affix cards)
                if not rowFrame.bg then
                    rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
                    rowFrame.bg:SetAllPoints()
                    rowFrame.bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)  -- Solid dark background
                end
                
                -- Type label (COLUMN 0 - Cell 0, left-aligned, vertically centered)
                local label = FontManager:CreateFontString(rowFrame, "title", "OVERLAY")
                label:SetPoint("LEFT", 5, 0)  -- 5px padding for readability
                label:SetWidth(cellWidth - 10)
                label:SetJustifyH("LEFT")
                -- Map typeName to locale key (plural for row labels, matching Blizzard)
                local typeDisplayName = typeName
                if typeName == "Raid" then
                    typeDisplayName = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or RAIDS or "Raids"
                elseif typeName == "Dungeon" then
                    typeDisplayName = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or DUNGEONS or "Dungeons"
                elseif typeName == "World" then
                    typeDisplayName = (ns.L and ns.L["VAULT_WORLD"]) or "World"
                end
                label:SetText(string.format("|cffffffff%s|r", typeDisplayName))
                
                -- Create individual slot frames in COLUMNS 1, 2, 3
                local thresholds = defaultThresholds[typeName] or {3, 3, 3}
                
                for slotIndex = 1, 3 do
                    -- Create slot container frame (using Factory pattern)
                    local slotFrame = ns.UI.Factory:CreateContainer(rowFrame)
                    local xOffset = slotIndex * cellWidth  -- Column 1, 2, 3
                    slotFrame:SetSize(cellWidth, cellHeight)
                    slotFrame:SetPoint("LEFT", rowFrame, "LEFT", xOffset, 0)
                    
                    -- Get activity data for this slot
                    local activity = activities and activities[slotIndex]
                    
                    local threshold = (activity and activity.threshold) or thresholds[slotIndex] or 0
                    local progress = activity and activity.progress or 0
                    local isComplete = (threshold > 0 and progress >= threshold)
                    
                    if activity and isComplete then
                        local isAtMax = IsVaultSlotAtMax(activity, dataKey)
                        
                        -- Tier text (line 1) - centered in cell
                        local displayText = GetVaultActivityDisplayText(activity, dataKey)
                        local tierText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                        tierText:SetPoint("CENTER", slotFrame, "CENTER", 0, 6)
                        tierText:SetWidth(cellWidth - 6)
                        tierText:SetJustifyH("CENTER")
                        tierText:SetWordWrap(false)
                        tierText:SetText(string.format("|cff00ff00%s|r", displayText))
                        
                        -- iLvl text (line 2) - centered below tier
                        local rewardIlvl = GetRewardItemLevel(activity)
                        if rewardIlvl and rewardIlvl > 0 then
                            local ilvlText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                            ilvlText:SetPoint("TOP", tierText, "BOTTOM", 0, -1)
                            ilvlText:SetWidth(cellWidth - 6)
                            ilvlText:SetJustifyH("CENTER")
                            ilvlText:SetWordWrap(false)
                            local ilvlFormat = (ns.L and ns.L["ILVL_FORMAT"]) or "iLvl %d"
                            ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", rewardIlvl))
                        end
                        
                        -- Upgrade arrow: left side, vertically centered to entire cell (both lines)
                        if not isAtMax then
                            local arrowTexture = slotFrame:CreateTexture(nil, "OVERLAY")
                            arrowTexture:SetSize(16, 16)
                            arrowTexture:SetPoint("LEFT", slotFrame, "LEFT", -2, 0)
                            arrowTexture:SetAtlas("loottoast-arrow-green")
                        end
                        
                        -- Add tooltip for completed slots
                        if ShowTooltip then
                            slotFrame:EnableMouse(true)
                            slotFrame:SetScript("OnEnter", function(self)
                                local lines = {}
                                local displayText = GetVaultActivityDisplayText(activity, dataKey)
                                local rewardIlvl = GetRewardItemLevel(activity)
                                local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
                                local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"

                                -- Current Reward header + value
                                if rewardIlvl and rewardIlvl > 0 then
                                    table.insert(lines, {
                                        text = string.format("|cff00ff00%s|r",
                                            (ns.L and ns.L["VAULT_REWARD"]) or "Current Reward"),
                                        color = {0.5, 1, 0.5}
                                    })
                                    table.insert(lines, {
                                        text = string.format("|cffffd700iLvl %d|r  |cffffffff- (%s)|r",
                                            rewardIlvl, displayText),
                                        color = {1, 1, 1}
                                    })
                                end

                                -- Upgrade: "Improve to iLvl X: Complete on Y difficulty"
                                local isAtMaxSlot = IsVaultSlotAtMax(activity, dataKey)
                                if not isAtMaxSlot then
                                    local nextTierName = GetNextTierName(activity, dataKey)
                                    if nextTierName then
                                        table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                                        local improveLabel = (ns.L and ns.L["VAULT_IMPROVE_TO"]) or "Improve to"
                                        if activity.nextLevelIlvl and activity.nextLevelIlvl > 0 then
                                            table.insert(lines, {
                                                text = string.format("|cffa0d0ff%s iLvl %d:|r",
                                                    improveLabel, activity.nextLevelIlvl),
                                                color = {0.63, 0.82, 1}
                                            })
                                        end
                                        local completeOnLabel = (ns.L and ns.L["VAULT_COMPLETE_ON"]) or "Complete this activity on %s"
                                        table.insert(lines, {
                                            text = string.format("|cff888888" .. completeOnLabel .. "|r", nextTierName),
                                            color = {0.5, 0.5, 0.5}
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

                                local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                    title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                                    lines = lines,
                                    anchor = "ANCHOR_TOP"
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
                        -- Incomplete: Show progress numbers (centered, body font to prevent overflow)
                        local progressText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                        progressText:SetPoint("CENTER", 0, 0)
                        progressText:SetWidth(cellWidth - 6)  -- Fit within cell
                        progressText:SetJustifyH("CENTER")
                        progressText:SetWordWrap(false)
                        progressText:SetText(string.format("|cffffcc00%s|r|cffffffff/|r|cffffcc00%s|r", 
                            FormatNumber(progress), FormatNumber(threshold)))
                        
                        -- Add tooltip for incomplete slots
                        if ShowTooltip then
                            slotFrame:EnableMouse(true)
                            slotFrame:SetScript("OnEnter", function(self)
                                local lines = {}
                                local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
                                local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"

                                local activityHint = ""
                                if dataKey == "M+" then
                                    activityHint = (ns.L and ns.L["VAULT_DUNGEONS"]) or "dungeons"
                                elseif dataKey == "Raid" then
                                    activityHint = (ns.L and ns.L["VAULT_BOSS_KILLS"]) or "boss kills"
                                elseif dataKey == "World" then
                                    activityHint = (ns.L and ns.L["VAULT_WORLD_ACTIVITIES"]) or "world activities"
                                else
                                    activityHint = (ns.L and ns.L["VAULT_ACTIVITIES"]) or "activities"
                                end

                                -- Unlock Reward header
                                local unlockLabel = (ns.L and ns.L["VAULT_UNLOCK_REWARD"]) or "Unlock Reward"
                                table.insert(lines, {
                                    text = string.format("|cff00ff00%s|r", unlockLabel),
                                    color = {0.5, 1, 0.5}
                                })

                                -- "Complete N more X to unlock"
                                local remaining = threshold - progress
                                if remaining > 0 then
                                    local completeMoreLabel = (ns.L and ns.L["VAULT_COMPLETE_MORE_FORMAT"]) or "Complete %d more %s this week to unlock."
                                    table.insert(lines, {
                                        text = string.format("|cffffffff" .. completeMoreLabel .. "|r",
                                            remaining, activityHint),
                                        color = {1, 1, 1}
                                    })
                                end

                                -- M+ specific: "The item level will be based on the lowest of your top N runs (currently X)"
                                if dataKey == "M+" then
                                    local currentTierText = GetVaultActivityDisplayText(activity, dataKey)
                                    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                                    local basedOnLabel = (ns.L and ns.L["VAULT_BASED_ON_FORMAT"]) or "The item level of this reward will be based on the lowest of your top %d runs this week (currently %s)."
                                    table.insert(lines, {
                                        text = string.format("|cff888888" .. basedOnLabel .. "|r",
                                            threshold, currentTierText),
                                        color = {0.5, 0.5, 0.5}
                                    })
                                end

                                -- Raid specific: "The item level will be based on the difficulty of your boss kills"
                                if dataKey == "Raid" then
                                    local currentDiffText = GetVaultActivityDisplayText(activity, dataKey)
                                    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                                    local raidBasedLabel = (ns.L and ns.L["VAULT_RAID_BASED_FORMAT"]) or "Reward based on highest difficulty defeated (currently %s)."
                                    table.insert(lines, {
                                        text = string.format("|cff888888" .. raidBasedLabel .. "|r", currentDiffText),
                                        color = {0.5, 0.5, 0.5}
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

                                local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                    title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                                    lines = lines,
                                    anchor = "ANCHOR_TOP"
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
                        -- No data: Show empty with threshold (centered, body font to prevent overflow)
                        local emptyText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                        emptyText:SetPoint("CENTER", 0, 0)
                        emptyText:SetWidth(cellWidth - 6)  -- Fit within cell
                        emptyText:SetJustifyH("CENTER")
                        emptyText:SetWordWrap(false)
                        if threshold > 0 then
                            emptyText:SetText(string.format("|cff888888%s|r|cff666666/|r|cff888888%s|r", FormatNumber(0), FormatNumber(threshold)))
                            
                            -- Add tooltip for empty slots
                            if ShowTooltip then
                                slotFrame:EnableMouse(true)
                                slotFrame:SetScript("OnEnter", function(self)
                                    local lines = {}

                                    local activityHint = ""
                                    if dataKey == "M+" then
                                        activityHint = (ns.L and ns.L["VAULT_DUNGEONS"]) or "dungeons"
                                    elseif dataKey == "Raid" then
                                        activityHint = (ns.L and ns.L["VAULT_BOSS_KILLS"]) or "boss kills"
                                    elseif dataKey == "World" then
                                        activityHint = (ns.L and ns.L["VAULT_WORLD_ACTIVITIES"]) or "world activities"
                                    else
                                        activityHint = (ns.L and ns.L["VAULT_ACTIVITIES"]) or "activities"
                                    end

                                    local unlockLabel = (ns.L and ns.L["VAULT_UNLOCK_REWARD"]) or "Unlock Reward"
                                    table.insert(lines, {
                                        text = string.format("|cff00ff00%s|r", unlockLabel),
                                        color = {0.5, 1, 0.5}
                                    })
                                    local completeMoreLabel = (ns.L and ns.L["VAULT_COMPLETE_MORE_FORMAT"]) or "Complete %d more %s this week to unlock."
                                    table.insert(lines, {
                                        text = string.format("|cffffffff" .. completeMoreLabel .. "|r",
                                            threshold, activityHint),
                                        color = {1, 1, 1}
                                    })

                                    local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                    ShowTooltip(self, {
                                        type = "custom",
                                        icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                        title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                                        lines = lines,
                                        anchor = "ANCHOR_TOP"
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
                            emptyText:SetText("|cff666666-|r")
                        end
                    end
                end
                
                -- No need to increment vaultY anymore (using rowIndex)
            end
        else
            -- No vault data: Still set card dimensions so it's visible
            vaultCard:SetHeight(baseCardHeight)
            vaultCard:SetWidth(baseCardWidth)
            
            local noVault = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
            noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            local noVaultLabel = (ns.L and ns.L["NO_VAULT_DATA"]) or "No vault data"
            noVault:SetText("|cff666666" .. noVaultLabel .. "|r")
        end
        
        vaultCard:Show()
            
            cardContainer:SetHeight(cardHeight or 200)
            yOffset = yOffset + (cardHeight or 200) + GetLayout().afterElement
        end
        
        -- Character sections flow directly one after another (like Characters tab)
    end
    
    return yOffset + 20
end

