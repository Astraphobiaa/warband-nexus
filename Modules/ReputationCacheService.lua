--[[
    Warband Nexus - Reputation Cache Service (v3.0.0 - Snapshot-Diff Architecture)
    
    ARCHITECTURE: Snapshot-Diff + AceDB
    
    Zero chat message parsing. Zero name→ID lookups.
    factionID comes DIRECTLY from WoW API iteration — 100% reliable.
    
    Data Flow:
    1) Initialize → 2s timer → BuildSnapshot (silent, no login spam)
       + Rebuilt after each PerformFullScan (picks up new factions)
    2) UPDATE_FACTION fires → PerformSnapshotDiff (via dedicated frame)
    3) Diff: iterate known factionIDs via GetFactionDataByID
    4) Detect: gainAmount = newBarValue - oldBarValue (integer diff, O(1) per faction)
    5) Fire WN_REPUTATION_GAINED with full display data from API
    6) ChatMessageService prints directly (no DB lookup needed)
    7) Update snapshot immediately
    8) Background FullScan updates rich DB for UI
    
    Guards:
    - Non-cancelling updateThrottle: Only one background scan at a time
    - Snapshot rebuilt silently after each FullScan (picks up new factions)
    
    Architecture: Snapshot → Diff → Event → ChatMessageService
                  Scanner → Processor → DB → UI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import dependencies
local Scanner = ns.ReputationScanner
local Processor = ns.ReputationProcessor
local Constants = ns.Constants

-- Debug print helper
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print("|cff00ffff[ReputationCache]|r", ...)
    end
end

-- ============================================================================
-- STATE (Minimal - No RAM cache)
-- ============================================================================

local ReputationCache = {
    -- Metadata only (no data storage)
    version = "1.0.0",
    lastFullScan = 0,
    lastUpdate = 0,
    
    -- Throttle timers
    fullScanThrottle = nil,
    updateThrottle = nil,
    
    -- UI refresh debounce (for handling multiple rapid updates)
    uiRefreshTimer = nil,
    pendingUIRefresh = false,
    
    -- Snapshot state for diff-based gain detection
    -- Stored on object (not local) so PerformFullScan can rebuild it directly.
    -- Avoids AceEvent one-handler-per-event collision with Core.lua/UI modules.
    _snapshot = {},         -- [factionID] = { barValue, reaction, paragonValue?, paragonThreshold? }
    _snapshotReady = false,
    
    -- Flags
    isInitialized = false,
    isScanning = false,
}

-- Loading state for UI (similar to PlansLoadingState pattern)
ns.ReputationLoadingState = ns.ReputationLoadingState or {
    isLoading = false,
    loadingProgress = 0,
    currentStage = (ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing...",
}

-- Fire UI refresh events (with optional debounce)
local function ScheduleUIRefresh(immediate)
    if immediate then
        -- Fire immediately (for resetrep, cache clear, etc.)
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
        end
        return
    end
    
    -- Cancel existing timer
    if ReputationCache.uiRefreshTimer then
        ReputationCache.uiRefreshTimer:Cancel()
    end
    
    -- Mark as pending
    ReputationCache.pendingUIRefresh = true
    
    -- Schedule new refresh (0.5 seconds after last update - for rapid rep gains)
    ReputationCache.uiRefreshTimer = C_Timer.NewTimer(0.5, function()
        if ReputationCache.pendingUIRefresh and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
            ReputationCache.pendingUIRefresh = false
        end
    end)
end

-- ============================================================================
-- DB INTERFACE (Direct Access)
-- ============================================================================

---Get direct reference to DB reputation data
---@return table DB table (WarbandNexus.db.global.reputationData)
local function GetDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    
    -- Ensure structure exists
    if not WarbandNexus.db.global.reputationData then
        WarbandNexus.db.global.reputationData = {
            version = ReputationCache.version,
            lastScan = 0,
            accountWide = {},
            characters = {},
            headers = {},
        }
    end
    
    return WarbandNexus.db.global.reputationData
end

-- ============================================================================
-- UNIFIED FACTION LOOKUP (Single Source of Truth)
-- ============================================================================
-- Every module MUST use this function to resolve faction data.
-- It guarantees the same DB reference is returned for a given factionID,
-- regardless of whether called from chat filter, ChatMessageService, or UI.
--
-- Priority:
--   1. Current character entry WITH real progress (maxValue > 1)
--   2. Account-wide entry WITH real progress (maxValue > 1)
--   3. Any other character's entry WITH real progress
--   4. Current character entry (even if header/no progress)
--   5. Account-wide entry (even if header/no progress)
-- ============================================================================

---Resolve the best available DB reference for a factionID.
---Returns the SAME table reference every time for the same factionID+state.
---
---Only looks at CURRENT CHARACTER and ACCOUNT-WIDE data.
---No other character fallback (not needed for chat — user's explicit requirement).
---
---Priority:
---  1. Current character entry with real progress (maxValue > 1)
---  2. Account-wide entry with real progress (maxValue > 1)
---  3. Current character entry (even without progress — e.g., header or freshly created)
---  4. Account-wide entry (even without progress)
---@param factionID number
---@return table|nil data Direct DB reference (modify it = modify DB)
local function ResolveFactionData(factionID)
    local db = GetDB()
    if not db then return nil end
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
    
    -- Current character
    local charData = (db.characters[charKey] or {})[factionID]
    
    -- Account-wide
    local acctData = db.accountWide[factionID]
    
    -- Prefer entry with real progress (maxValue > 1 = Processor normalized it correctly)
    if charData and (charData.maxValue or 0) > 1 then
        return charData
    end
    if acctData and (acctData.maxValue or 0) > 1 then
        return acctData
    end
    
    -- Fallback: return whatever exists (character preferred)
    return charData or acctData
end

---Migrate old data structure (if needed)
local function MigrateDB()
    local db = GetDB()
    if not db then return end
    
    -- Check version
    if db.version == ReputationCache.version then
        return -- Already up to date
    end
    
    -- Handle FORCE_REBUILD marker (from /wn resetrep)
    if db.version == "FORCE_REBUILD" then
        db.version = ReputationCache.version
        return
    end
    
    -- Ensure all required fields exist (preserves existing data)
    db.accountWide = db.accountWide or {}
    db.characters = db.characters or {}
    db.headers = db.headers or {}
    db.lastScan = db.lastScan or 0
    
    -- Update version
    db.version = ReputationCache.version
end

---Initialize cache (validates DB structure, does NOT clear data)
function ReputationCache:Initialize()
    if self.isInitialized then
        return
    end
    
    local db = GetDB()
    if not db then
        return
    end
    
    -- Migrate old structure if needed
    MigrateDB()
    
    -- Load metadata
    self.lastFullScan = db.lastScan or 0
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Count existing data
    local awCount = 0
    local charCounts = {}
    local currentCharCount = 0
    
    for _ in pairs(db.accountWide) do 
        awCount = awCount + 1
    end
    
    for charKey, charFactions in pairs(db.characters) do
        local count = 0
        for _ in pairs(charFactions) do 
            count = count + 1
        end
        charCounts[charKey] = count
        if charKey == currentCharKey then
            currentCharCount = count
        end
    end
    
    local totalCount = awCount
    for _, count in pairs(charCounts) do
        totalCount = totalCount + count
    end
    
    -- Determine if scan is needed
    local needsScan = false
    local scanReason = ""
    
    if totalCount == 0 then
        needsScan = true
        scanReason = "No data in DB"
    elseif currentCharCount == 0 then
        needsScan = true
        scanReason = "Current character (" .. currentCharKey .. ") has no data"
    else
        -- Check for version mismatch
        local dbVersion = db.version
        if dbVersion ~= self.version then
            needsScan = true
            scanReason = string.format("Version mismatch (DB: %s, Current: %s)", tostring(dbVersion), tostring(self.version))
        else
            local age = time() - self.lastFullScan
            local MAX_CACHE_AGE = 3600  -- 1 hour
            if age > MAX_CACHE_AGE then
                needsScan = true
                scanReason = string.format("Cache is old (%d seconds)", age)
            end
        end
    end
    
    if totalCount > 0 then
        DebugPrint(string.format("|cff00ff00[Reputation]|r Loaded %d factions from DB (%d account-wide)",
            totalCount, awCount))
        for charKey, charCount in pairs(charCounts) do
            local marker = (charKey == currentCharKey) and " (current)" or ""
            DebugPrint(string.format("|cff00ff00[Reputation]|r   %s: %d factions%s", charKey, charCount, marker))
        end
    end
    
    if needsScan then
        DebugPrint("|cffffcc00[Cache]|r " .. scanReason .. ", scheduling scan...")
        
        -- Set loading state for UI
        ns.ReputationLoadingState.isLoading = true
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_INITIALIZING"]) or "Initializing..."
        
        -- Fire loading started event to trigger UI refresh
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
        end
        
        C_Timer.After(3, function()
            if ReputationCache then
                ReputationCache:PerformFullScan()
            end
        end)
    else
        -- Fire ready event immediately (data exists and is fresh)
        C_Timer.After(0.1, function()
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            end
        end)
    end
    
    -- Register event listeners for real-time updates
    self:RegisterEventListeners()
    
    self.isInitialized = true
    DebugPrint("|cff00ff00[Cache]|r Direct DB architecture initialized")
end

---Build or rebuild the snapshot from current WoW API state.
---Iterates all factions via GetFactionDataByIndex (requires header expansion).
---Stored on ReputationCache._snapshot (not local) so it can be called from PerformFullScan.
---@param silent boolean If true, suppress all chat output
function ReputationCache:BuildSnapshot(silent)
    if not C_Reputation or not C_Reputation.GetNumFactions or not C_Reputation.GetFactionDataByIndex then
        return
    end
    
    -- Expand all headers to discover every faction
    if C_Reputation.ExpandAllFactionHeaders then
        C_Reputation.ExpandAllFactionHeaders()
    end
    
    wipe(self._snapshot)
    local count = 0
    
    local numFactions = C_Reputation.GetNumFactions() or 0
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.factionID and data.factionID > 0 then
            local fid = data.factionID
            
            self._snapshot[fid] = {
                barValue = data.currentStanding or 0,
                reaction = data.reaction or 0,
            }
            count = count + 1
            
            -- Track friendship value (separate API — e.g. Brann Bronzebeard)
            if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local friendInfo = C_GossipInfo.GetFriendshipReputation(fid)
                if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                    self._snapshot[fid].isFriendship = true
                    self._snapshot[fid].friendshipStanding = friendInfo.standing or 0
                    self._snapshot[fid].friendshipMaxRep = friendInfo.maxRep or 0
                    self._snapshot[fid].friendshipReactionThreshold = friendInfo.reactionThreshold or 0
                    self._snapshot[fid].friendshipNextThreshold = friendInfo.nextThreshold or 0
                    self._snapshot[fid].friendshipName = friendInfo.text or ""
                end
            end
            
            -- Track paragon value (separate API — only for factions with active paragon)
            if C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(fid) then
                local pVal, pThreshold = C_Reputation.GetFactionParagonInfo(fid)
                if pVal and pThreshold and pThreshold > 0 then
                    self._snapshot[fid].paragonValue = pVal
                    self._snapshot[fid].paragonThreshold = pThreshold
                end
            end
        end
    end
    
    self._snapshotReady = true
    if not silent then
        DebugPrint(string.format("|cff00ff00[Snapshot]|r Built: %d factions tracked", count))
    end
end

---Perform snapshot diff: detect reputation changes and fire events.
---Iterates known factionIDs via GetFactionDataByID (no header expansion needed).
---Cost: ~187 GetFactionDataByID calls, each is a C-side table lookup → <1ms total.
function ReputationCache:PerformSnapshotDiff()
    if not self._snapshotReady then return end
    if not C_Reputation or not C_Reputation.GetFactionDataByID then return end
    
    local snapshot = self._snapshot
    
    for factionID, old in pairs(snapshot) do
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data then
            local newBarValue = data.currentStanding or 0
            local newReaction = data.reaction or 0
            local barMin = data.currentReactionThreshold or 0
            local barMax = data.nextReactionThreshold or 0
            local factionName = data.name or ""
            
            local gainAmount = 0
            local isParagonGain = false
            local isFriendshipGain = false
            
            -- 1a. Check friendship standing change (separate API — e.g. Brann)
            if old.isFriendship and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
                if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                    local newFriendStanding = friendInfo.standing or 0
                    if newFriendStanding > old.friendshipStanding then
                        gainAmount = newFriendStanding - old.friendshipStanding
                        isFriendshipGain = true
                    end
                    -- Update friendship snapshot
                    old.friendshipStanding = newFriendStanding
                    old.friendshipMaxRep = friendInfo.maxRep or 0
                    old.friendshipReactionThreshold = friendInfo.reactionThreshold or 0
                    old.friendshipNextThreshold = friendInfo.nextThreshold or 0
                    old.friendshipName = friendInfo.text or ""
                end
            end
            
            -- 1b. Check standard barValue change (covers classic, renown, guild)
            --     Skip if friendship gain already detected (avoids double-counting)
            if gainAmount == 0 and newBarValue > old.barValue then
                gainAmount = newBarValue - old.barValue
            end
            
            -- 2. Check paragon value change (separate API — only for known paragon factions)
            if old.paragonValue ~= nil then
                if C_Reputation.IsFactionParagon(factionID) then
                    local newPVal, newPThreshold = C_Reputation.GetFactionParagonInfo(factionID)
                    if newPVal and newPVal > old.paragonValue then
                        gainAmount = newPVal - old.paragonValue
                        isParagonGain = true
                    end
                    -- Update paragon snapshot
                    old.paragonValue = newPVal or old.paragonValue
                    if newPThreshold and newPThreshold > 0 then
                        old.paragonThreshold = newPThreshold
                    end
                end
            elseif C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
                -- Newly entered paragon — initialize tracking (no gain message for first detection)
                local pVal, pThreshold = C_Reputation.GetFactionParagonInfo(factionID)
                if pVal and pThreshold and pThreshold > 0 then
                    old.paragonValue = pVal
                    old.paragonThreshold = pThreshold
                end
            end
            
            -- 3. Standing change detection (reaction number increased)
            local wasStandingUp = (newReaction > old.reaction)
            
            -- Update snapshot immediately (before firing events)
            old.barValue = newBarValue
            old.reaction = newReaction
            
            -- 4. Fire event if gain detected
            if gainAmount > 0 and WarbandNexus and WarbandNexus.SendMessage then
                local currentRep, maxRep
                
                if isParagonGain and old.paragonThreshold then
                    -- Paragon: progress within current cycle
                    local pThreshold = old.paragonThreshold
                    currentRep = (old.paragonValue or 0) % pThreshold
                    maxRep = pThreshold
                    -- Cycle boundary: show full bar instead of 0
                    if currentRep == 0 and (old.paragonValue or 0) > 0 then
                        currentRep = pThreshold
                    end
                elseif isFriendshipGain then
                    -- Friendship: progress within current rank
                    local rankMin = old.friendshipReactionThreshold or 0
                    local rankMax = old.friendshipNextThreshold or 0
                    currentRep = (old.friendshipStanding or 0) - rankMin
                    maxRep = (rankMax > rankMin) and (rankMax - rankMin) or 0
                else
                    -- Standard: 0-based progress within standing level
                    currentRep = newBarValue - barMin
                    maxRep = barMax - barMin
                end
                
                -- Safety: non-negative values, maxRep=0 means "hide progress"
                if currentRep < 0 then currentRep = 0 end
                if maxRep < 0 then maxRep = 0 end
                
                WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                    factionID = factionID,
                    factionName = factionName,
                    gainAmount = gainAmount,
                    currentRep = currentRep,
                    maxRep = maxRep,
                    wasStandingUp = wasStandingUp,
                })
                
                DebugPrint(string.format("|cff00ff00[DIFF]|r %s (ID:%d) +%d → %d/%d%s",
                    factionName, factionID, gainAmount, currentRep, maxRep,
                    wasStandingUp and " [STANDING UP]" or ""))
                    
            elseif wasStandingUp and WarbandNexus and WarbandNexus.SendMessage then
                -- Standing change without visible gain (e.g., renown level-up via threshold)
                local standingName = ns.STANDING_NAMES and ns.STANDING_NAMES[newReaction]
                local standingColor = ns.STANDING_COLORS and ns.STANDING_COLORS[newReaction]
                
                -- Check for renown standing name
                if not standingName and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                    local majorData = C_MajorFactions.GetMajorFactionData(factionID)
                    if majorData and majorData.renownLevel then
                        standingName = ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown") .. " " .. majorData.renownLevel
                        standingColor = ns.RENOWN_COLOR
                    end
                end
                
                -- Check for friendship rank name (e.g. Brann Bronzebeard)
                if not standingName and old.isFriendship and old.friendshipName and old.friendshipName ~= "" then
                    standingName = old.friendshipName
                    standingColor = standingColor or {r = 0.5, g = 0.8, b = 1.0}
                end
                
                WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                    factionID = factionID,
                    factionName = factionName,
                    gainAmount = 0,
                    currentRep = 0,
                    maxRep = 0,
                    wasStandingUp = true,
                    standingName = standingName,
                    standingColor = standingColor,
                })
                
                DebugPrint(string.format("|cff00ff00[DIFF]|r %s (ID:%d) STANDING UP → %s",
                    factionName, factionID, standingName or "Unknown"))
            end
        end
    end
end

---Register event listeners for real-time reputation updates
function ReputationCache:RegisterEventListeners()
    if not WarbandNexus or not WarbandNexus.RegisterEvent then
        return
    end
    
    -- ============================================================
    -- SNAPSHOT-DIFF ARCHITECTURE (v3.0.0)
    --
    -- CRITICAL: Do NOT register PLAYER_ENTERING_WORLD or WN_REPUTATION_CACHE_READY
    -- on WarbandNexus — AceEvent allows only ONE handler per event per object.
    -- Core.lua and ReputationUI.lua already register those, so ours would be
    -- overwritten (or would overwrite theirs).
    --
    -- Instead: Build snapshot via direct timer + after each PerformFullScan.
    -- ============================================================
    
    -- ============================================================
    -- SUPPRESS Blizzard's default reputation chat message.
    -- CONDITIONAL: Only suppress if snapshot is ready (graceful degradation).
    -- If snapshot not ready, let Blizzard's message through.
    -- TAINT-SAFE: Filter only returns true/false; no Blizzard frame or state modified.
    -- ============================================================
    ChatFrame_AddMessageEventFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", function(self, event, message, ...)
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return false  -- Not tracking → pass through Blizzard's message
        end
        if not ReputationCache._snapshotReady then
            return false  -- Snapshot not ready → graceful degradation, show Blizzard message
        end
        return true  -- Snapshot ready → suppress (our [WN-Rep] message replaces it)
    end)
    
    -- ============================================================
    -- EVENT: UPDATE_FACTION — Primary gain detection
    -- Uses dedicated frame to avoid AceEvent single-handler collision.
    -- Fires PerformSnapshotDiff immediately (no debounce) for instant chat.
    -- ============================================================
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_FACTION")
    eventFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    eventFrame:SetScript("OnEvent", function(frame, event)
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        if not ReputationCache._snapshotReady then return end
        
        -- Diff immediately — instant chat feedback
        ReputationCache:PerformSnapshotDiff()
        
        -- Background FullScan for rich DB (UI needs Processor-normalized data)
        if not ReputationCache.updateThrottle then
            ReputationCache.updateThrottle = C_Timer.NewTimer(0.5, function()
                ReputationCache.updateThrottle = nil
                ReputationCache:PerformFullScan()
            end)
        end
    end)
    
    -- ============================================================
    -- EVENT: QUEST_TURNED_IN — Quest rep may lag behind UPDATE_FACTION
    -- Uses AceEvent (no collision — no other module registers QUEST_TURNED_IN on WarbandNexus)
    -- ============================================================
    WarbandNexus:RegisterEvent("QUEST_TURNED_IN", function()
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        
        -- Short delay for API to reflect quest reward rep
        if not ReputationCache.updateThrottle then
            ReputationCache.updateThrottle = C_Timer.NewTimer(0.2, function()
                ReputationCache.updateThrottle = nil
                if ReputationCache._snapshotReady then
                    ReputationCache:PerformSnapshotDiff()
                end
                ReputationCache:PerformFullScan()
            end)
        end
    end)
    
    -- ============================================================
    -- INITIAL SNAPSHOT BUILD (direct timer — no event dependency)
    -- 2s delay ensures API is ready after login/reload.
    -- ============================================================
    C_Timer.After(2, function()
        if not ReputationCache._snapshotReady then
            ReputationCache:BuildSnapshot(true)
            DebugPrint("|cff00ff00[Snapshot]|r Initial build via timer (2s after RegisterEventListeners)")
        end
    end)
    
    DebugPrint("|cff00ff00[ReputationCache]|r v3.0.0 Snapshot-Diff architecture registered")
end

-- ============================================================================
-- UPDATE OPERATIONS (Direct DB writes)
-- ============================================================================

---Update single faction (writes directly to DB)
---@param factionID number
---@param normalizedData table Normalized faction data from Processor
function ReputationCache:UpdateFaction(factionID, normalizedData)
    if not factionID or factionID == 0 then
        DebugPrint("ERROR: Invalid factionID")
        return false
    end
    
    if not normalizedData then
        DebugPrint("ERROR: Missing normalized data for faction " .. factionID)
        return false
    end
    
    local db = GetDB()
    if not db then
        DebugPrint("ERROR: DB not initialized")
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Write DIRECTLY to DB (no RAM cache)
    if normalizedData.isAccountWide then
        db.accountWide[factionID] = normalizedData
    else
        if not db.characters[currentCharKey] then
            db.characters[currentCharKey] = {}
        end
        db.characters[currentCharKey][factionID] = normalizedData
    end
    
    self.lastUpdate = time()
    
    -- Schedule UI refresh (debounced)
    ScheduleUIRefresh()
    
    return true
end

---Update all factions (MERGE into DB, preserves other characters' data)
---@param normalizedDataArray table Array of normalized faction data from Processor
function ReputationCache:UpdateAll(normalizedDataArray)
    if not normalizedDataArray or #normalizedDataArray == 0 then
        DebugPrint("ERROR: No data to update")
        return false
    end
    
    local db = GetDB()
    if not db then
        DebugPrint("ERROR: DB not initialized")
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- CRITICAL: Clear ONLY current character's data (preserve other characters)
    if not db.characters[currentCharKey] then
        db.characters[currentCharKey] = {}
    else
        wipe(db.characters[currentCharKey])
    end
    
    -- MERGE data into DB (account-wide gets updated, not replaced)
    local awCount = 0
    local charCount = 0
    
    for _, data in ipairs(normalizedDataArray) do
        if data.factionID then
            if data.isAccountWide then
                -- Update account-wide faction
                db.accountWide[data.factionID] = data
                awCount = awCount + 1
            else
                -- Add character-specific faction
                db.characters[currentCharKey][data.factionID] = data
                charCount = charCount + 1
            end
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    
    -- Build headers
    self:BuildHeaders()
    
    -- Fire UI refresh immediately (full scan always shows results)
    ScheduleUIRefresh(true)
    
    DebugPrint(string.format("|cff00ff00[Reputation]|r Updated: %d account-wide, %d character-specific (%s)",
        awCount, charCount, currentCharKey))
    
    return true
end

---Build headers from DB data (for UI grouping)
function ReputationCache:BuildHeaders()
    local db = GetDB()
    if not db then return end
    
    -- Group factions by first parent header (expansion)
    local headerMap = {}
    
    -- Process account-wide factions
    for factionID, data in pairs(db.accountWide) do
        if data.parentFactionName and data.parentFactionName ~= "" then
            if not headerMap[data.parentFactionName] then
                headerMap[data.parentFactionName] = {
                    name = data.parentFactionName,
                    factions = {},
                    sortKey = 99999,
                }
            end
            table.insert(headerMap[data.parentFactionName].factions, factionID)
        end
    end
    
    -- Process character-specific factions
    for charKey, charFactions in pairs(db.characters) do
        for factionID, data in pairs(charFactions) do
            if data.parentFactionName and data.parentFactionName ~= "" then
                if not headerMap[data.parentFactionName] then
                    headerMap[data.parentFactionName] = {
                        name = data.parentFactionName,
                        factions = {},
                        sortKey = 99999,
                    }
                end
                -- Don't duplicate factionID if already in list
                local exists = false
                for _, existingID in ipairs(headerMap[data.parentFactionName].factions) do
                    if existingID == factionID then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(headerMap[data.parentFactionName].factions, factionID)
                end
            end
        end
    end
    
    -- Calculate MinIndex for each header (for sorting)
    for headerName, headerData in pairs(headerMap) do
        local minIndex = 99999
        for _, factionID in ipairs(headerData.factions) do
            -- Check account-wide
            local data = db.accountWide[factionID]
            if not data then
                -- Check character-specific
                for _, charFactions in pairs(db.characters) do
                    data = charFactions[factionID]
                    if data then break end
                end
            end
            
            if data and data._scanIndex and data._scanIndex < minIndex then
                minIndex = data._scanIndex
            end
        end
        headerData.sortKey = minIndex
        
        -- Sort factions within header by scanIndex
        table.sort(headerData.factions, function(a, b)
            local dataA = db.accountWide[a]
            if not dataA then
                for _, charFactions in pairs(db.characters) do
                    dataA = charFactions[a]
                    if dataA then break end
                end
            end
            
            local dataB = db.accountWide[b]
            if not dataB then
                for _, charFactions in pairs(db.characters) do
                    dataB = charFactions[b]
                    if dataB then break end
                end
            end
            
            local indexA = (dataA and dataA._scanIndex) or 99999
            local indexB = (dataB and dataB._scanIndex) or 99999
            return indexA < indexB
        end)
    end
    
    -- Convert to array and sort headers
    local headers = {}
    for _, headerData in pairs(headerMap) do
        table.insert(headers, headerData)
    end
    
    table.sort(headers, function(a, b)
        return a.sortKey < b.sortKey
    end)
    
    -- Save to DB
    db.headers = headers
end

-- ============================================================================
-- READ OPERATIONS (Direct DB reads)
-- ============================================================================

---Get single faction from DB (unified lookup)
---@param factionID number
---@return table|nil Normalized faction data
function ReputationCache:GetFaction(factionID)
    return ResolveFactionData(factionID)
end

---Get all factions from DB (returns structure for internal use)
---@return table Factions structure {accountWide = {}, characters = {}}
function ReputationCache:GetAll()
    local db = GetDB()
    if not db then
        return {accountWide = {}, characters = {}}
    end
    
    return {
        accountWide = db.accountWide,
        characters = db.characters,
    }
end

---Get headers for UI grouping
---@return table Headers array
function ReputationCache:GetHeaders()
    local db = GetDB()
    if not db then return {} end
    
    return db.headers or {}
end

---Clear reputation data for current character only (preserves other characters)
---@param clearDB boolean Also clear SavedVariables (only current character's reputation data)
function ReputationCache:Clear(clearDB)
    DebugPrint("|cffff00ff[Cache]|r Clearing reputation data...")
    
    if clearDB then
        local db = GetDB()
        if db then
            -- Get current character key
            local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
            
            -- IMPORTANT: Only clear CURRENT character's reputation data
            -- Preserve: account-wide data, other characters' data, version, headers
            if db.characters and db.characters[currentCharKey] then
                wipe(db.characters[currentCharKey])
                DebugPrint("|cff00ff00[Cache]|r Cleared reputation data for: " .. currentCharKey)
            else
                DebugPrint("|cffffcc00[Cache]|r No data to clear for: " .. currentCharKey)
            end
            
            -- Reset scan time for current character only
            db.lastScan = 0
            
            -- Note: We do NOT clear:
            -- - db.accountWide (shared across all characters)
            -- - db.characters[otherCharKey] (other characters' data)
            -- - db.version (keep version tracking)
            -- - db.headers (will be rebuilt from remaining data)
        end
    end
    
    -- Reset metadata
    self.lastFullScan = 0
    self.lastUpdate = 0
    self.isScanning = false
    
    -- Fire events immediately (cache cleared)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_CLEARED")
    end
    ScheduleUIRefresh(true)
    
    -- Automatically start rescan after clearing
    if clearDB then
        -- Set loading state for UI
        ns.ReputationLoadingState.isLoading = true
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
        end
        
        DebugPrint("|cffffcc00[Cache]|r Starting automatic rescan in 1 second...")
        C_Timer.After(1, function()
            if ReputationCache then
                ReputationCache:PerformFullScan(true)  -- bypass throttle since we just cleared
            end
        end)
    else
        -- Clear loading state if not rescanning
        ns.ReputationLoadingState.isLoading = false
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."
    end
end

-- ============================================================================
-- SCAN OPERATIONS
-- ============================================================================

---Perform full scan of all reputations
function ReputationCache:PerformFullScan(bypassThrottle)
    if not Scanner or not Processor then
        -- Scanner or Processor not loaded
        return
    end
    
    -- Throttle check
    if not bypassThrottle then
        local now = time()
        local timeSinceLastScan = now - self.lastFullScan
        local MIN_SCAN_INTERVAL = 5  -- 5 seconds
        
        if timeSinceLastScan < MIN_SCAN_INTERVAL then
            DebugPrint(string.format("Scan throttled (%.1fs since last scan)", timeSinceLastScan))
            return
        end
    end
    
    if self.isScanning then
        DebugPrint("Scan already in progress, skipping...")
        return
    end
    
    self.isScanning = true
    
    -- Set loading state for UI
    ns.ReputationLoadingState.isLoading = true
    ns.ReputationLoadingState.loadingProgress = 0
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_FETCHING"]) or "Fetching reputation data..."
    
    -- Trigger UI refresh to show loading state
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
    end
    
    DebugPrint("|cff9370DB[Reputation]|r Starting full scan...")
    
    -- Scan raw data
    local rawData = Scanner:FetchAllFactions()
    
    if not rawData or #rawData == 0 then
        DebugPrint("|cffff0000[Reputation]|r Scan returned no data (API not ready?)")
        self.isScanning = false
        
        -- Clear loading state
        ns.ReputationLoadingState.isLoading = false
        
        -- Retry after delay
        C_Timer.After(5, function()
            if ReputationCache then
                ReputationCache:PerformFullScan(true)
            end
        end)
        return
    end
    
    -- Update progress
    ns.ReputationLoadingState.loadingProgress = 33
    ns.ReputationLoadingState.currentStage = string.format((ns.L and ns.L["REP_LOADING_PROCESSING"]) or "Processing %d factions...", #rawData)
    
    -- Process data
    local normalizedData = {}
    local updateInterval = math.max(10, math.floor(#rawData / 10))  -- Update every 10% or at least every 10 items
    
    for i, raw in ipairs(rawData) do
        local normalized = Processor:Process(raw)
        if normalized then
            table.insert(normalizedData, normalized)
        end
        
        -- Update progress and refresh UI periodically
        if i % updateInterval == 0 then
            local progress = 33 + math.floor((i / #rawData) * 33)  -- 33-66%
            ns.ReputationLoadingState.loadingProgress = progress
            ns.ReputationLoadingState.currentStage = string.format((ns.L and ns.L["REP_LOADING_PROCESSING_COUNT"]) or "Processing... (%d/%d)", i, #rawData)
            
            -- Trigger UI refresh to show progress updates
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
            end
        end
    end
    
    -- Update DB
    ns.ReputationLoadingState.loadingProgress = 66
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_SAVING"]) or "Saving to database..."
    self:UpdateAll(normalizedData)
    
    -- Complete - clear loading state immediately
    ns.ReputationLoadingState.isLoading = false
    ns.ReputationLoadingState.loadingProgress = 100
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_COMPLETE"]) or "Complete!"
    
    self.isScanning = false
    
    DebugPrint(string.format("|cff00ff00[Reputation]|r Scan complete: %d factions processed", #normalizedData))
    
    -- Fire cache ready event (will trigger UI refresh)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
        WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
    end
    
    -- Rebuild snapshot after FullScan (picks up newly discovered factions)
    -- Done directly — NOT via WN_REPUTATION_CACHE_READY (AceEvent collision risk)
    self:BuildSnapshot(true)
end

-- ============================================================================
-- PUBLIC API (Attached to WarbandNexus)
-- ============================================================================

---Get a single faction's DB data by factionID (O(1) direct access)
---Priority: current character > accountWide
---@param factionID number
---@return table|nil Normalized faction data reference (same as GetFactionByName)
function WarbandNexus:GetFactionByID(factionID)
    if not factionID then return nil end
    return ResolveFactionData(factionID)
end

---Get all normalized reputation data (ALL characters)
---@return table Array of normalized faction data with _characterKey metadata
function WarbandNexus:GetAllReputations()
    local db = GetDB()
    if not db then return {} end
    
    local result = {}
    
    -- Add account-wide reputations
    for factionID, data in pairs(db.accountWide) do
        local entry = {}
        for k, v in pairs(data) do
            entry[k] = v
        end
        entry._characterKey = (ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide"
        entry.isAccountWide = true
        table.insert(result, entry)
    end
    
    -- Add character-specific reputations (from ALL characters)
    for charKey, charFactions in pairs(db.characters) do
        -- Get character class
        local charClass = "WARRIOR"
        if WarbandNexus.db.global.characters then
            for _, char in pairs(WarbandNexus.db.global.characters) do
                local cKey = (char.name or "") .. "-" .. (char.realm or "")
                if cKey == charKey then
                    charClass = char.class or char.classFile or "WARRIOR"
                    charClass = string.upper(charClass)
                    break
                end
            end
        end
        
        for factionID, data in pairs(charFactions) do
            local entry = {}
            for k, v in pairs(data) do
                entry[k] = v
            end
            entry._characterKey = charKey
            entry._characterClass = charClass
            entry.isAccountWide = false
            table.insert(result, entry)
        end
    end
    
    return result
end

---Get reputation headers (for hierarchical display)
---@return table Array of {name, factions=[factionID, ...]}
function WarbandNexus:GetReputationHeaders()
    return ReputationCache:GetHeaders()
end

---Get single faction by ID
---@param factionID number
---@return table|nil Normalized faction data
function WarbandNexus:GetReputation(factionID)
    return ReputationCache:GetFaction(factionID)
end

---Trigger full reputation scan
function WarbandNexus:ScanReputations()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    ReputationCache:PerformFullScan(false)
end

---Clear reputation cache
function WarbandNexus:ClearReputationCache()
    ReputationCache:Clear(true)
end

-- ============================================================================
-- DEBUG VERIFICATION COMMANDS
-- ============================================================================

---Global debug function: Verify reputation data storage and retrieval
---Usage: /run WNVerifyReputationData(factionID)
_G.WNVerifyReputationData = function(factionID)
    if not factionID then
        print("|cffff0000[RepVerify]|r Usage: /run WNVerifyReputationData(factionID)")
        return
    end
    
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus or not WarbandNexus.db then
        print("|cffff0000[RepVerify]|r WarbandNexus not loaded")
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[RepVerify]|r DB not initialized")
        return
    end
    
    -- Get faction name
    local factionName = "Unknown"
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local factionData = C_Reputation.GetFactionDataByID(factionID)
        if factionData then
            factionName = factionData.name or "Unknown"
        end
    end
    
    print("|cff00ff00[RepVerify]|r Faction: " .. factionName .. " (ID:" .. factionID .. ")")
    print("=====================================")
    
    -- Check account-wide storage
    local accountWideData = db.accountWide[factionID]
    if accountWideData then
        print("|cffffcc00[Storage]|r Account-Wide (db.accountWide[" .. factionID .. "])")
        print("  isAccountWide: " .. tostring(accountWideData.isAccountWide))
        print("  Type: " .. (accountWideData.type or "unknown"))
        print("  Standing: " .. (accountWideData.standingName or "unknown"))
        print("  Progress: " .. (accountWideData.currentValue or 0) .. "/" .. (accountWideData.maxValue or 1))
    else
        print("|cff666666[Storage]|r NOT in account-wide storage")
    end
    
    -- Check character-specific storage
    print("")
    print("|cffffcc00[Character Storage]|r")
    local charCount = 0
    local highestChar = nil
    local highestProgress = -1
    
    for charKey, charFactions in pairs(db.characters) do
        local charData = charFactions[factionID]
        if charData then
            charCount = charCount + 1
            print("  " .. charKey .. ":")
            print("    isAccountWide: " .. tostring(charData.isAccountWide))
            print("    Type: " .. (charData.type or "unknown"))
            print("    Standing: " .. (charData.standingName or "unknown"))
            print("    Progress: " .. (charData.currentValue or 0) .. "/" .. (charData.maxValue or 1))
            
            -- Track highest
            local progress = charData.currentValue or 0
            if progress > highestProgress then
                highestProgress = progress
                highestChar = charKey
            end
        end
    end
    
    if charCount == 0 then
        print("  (None)")
    else
        print("")
        print("|cff00ff00[Highest Progress]|r " .. (highestChar or "None"))
    end
    
    -- Check UI data (GetAllReputations)
    print("")
    print("|cffffcc00[UI Data (GetAllReputations)]|r")
    local allReps = WarbandNexus:GetAllReputations()
    local found = false
    for _, rep in ipairs(allReps) do
        if rep.factionID == factionID then
            found = true
            print("  Character: " .. (rep._characterKey or "Unknown"))
            print("  isAccountWide: " .. tostring(rep.isAccountWide))
            print("  Type: " .. (rep.type or "unknown"))
            print("  Standing: " .. (rep.standingName or "unknown"))
            print("  Progress: " .. (rep.currentValue or 0) .. "/" .. (rep.maxValue or 1))
            print("  ---")
        end
    end
    
    if not found then
        print("  (Not found in GetAllReputations)")
    end
    
    print("=====================================")
end

---Global debug function: List all factions in storage
---Usage: /run WNListStoredReputations()
_G.WNListStoredReputations = function()
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus or not WarbandNexus.db then
        print("|cffff0000[RepVerify]|r WarbandNexus not loaded")
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[RepVerify]|r DB not initialized")
        return
    end
    
    -- Count account-wide
    local awCount = 0
    for _ in pairs(db.accountWide) do
        awCount = awCount + 1
    end
    
    -- Count character-specific
    local charCounts = {}
    local totalChar = 0
    for charKey, charFactions in pairs(db.characters) do
        local count = 0
        for _ in pairs(charFactions) do
            count = count + 1
        end
        charCounts[charKey] = count
        totalChar = totalChar + count
    end
    
    print("|cff00ff00[Stored Reputations]|r")
    print("=====================================")
    print("Account-Wide: " .. awCount .. " factions")
    print("Character-Specific: " .. totalChar .. " factions")
    print("")
    for charKey, count in pairs(charCounts) do
        print("  " .. charKey .. ": " .. count .. " factions")
    end
    print("=====================================")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.ReputationCache = ReputationCache

-- NOTE: Initialize() is called from Core.lua OnEnable() after DB is ready
-- Do NOT call Initialize() here - WarbandNexus.db may not be loaded yet
