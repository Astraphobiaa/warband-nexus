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
    version = "1.5.0",  -- Bumped: non-destructive migration (zero data wipe, force rescan only)
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
            factionInfo = {},  -- [factionID] = { pn=parentFactionName, pid=parentFactionID } (stored once, not per char)
        }
    end
    -- Ensure factionInfo exists (for existing DBs that were created without it)
    if not WarbandNexus.db.global.reputationData.factionInfo then
        WarbandNexus.db.global.reputationData.factionInfo = {}
    end
    
    return WarbandNexus.db.global.reputationData
end

-- ============================================================================
-- SESSION-ONLY METADATA CACHE (never persisted)
-- ============================================================================

local repMetadataCache = {}           -- [factionID] = { name, description, type, ... }
local repMetadataCacheOrder = {}      -- Circular buffer eviction order
local repMetadataCacheHead = 1        -- Circular buffer head index
local REP_METADATA_CACHE_MAX = 256

---Resolve faction metadata from WoW API (cached in session RAM, never persisted).
---Returns faction-level info: name, description, type, isAccountWide, isMajorFaction, etc.
---IMPORTANT: Does NOT cache results where the API returned nil/empty name.
---This allows re-fetching on next call once the API has loaded the data.
---@param factionID number
---@return table|nil metadata
local function ResolveFactionMetadata(factionID)
    if not factionID or factionID == 0 then return nil end
    
    -- Check RAM cache first
    local cached = repMetadataCache[factionID]
    if cached then return cached end
    
    -- Fetch from WoW API
    if not C_Reputation or not C_Reputation.GetFactionDataByID then return nil end
    local fData = C_Reputation.GetFactionDataByID(factionID)
    if not fData then return nil end
    
    -- GUARD: Do NOT cache if API returned nil/empty name.
    -- This means the data isn't loaded yet — return nil so HydrateFactionData
    -- uses the stored compact name instead. Next call will retry the API.
    if not fData.name or fData.name == "" then
        return nil
    end
    
    -- Determine type
    local factionType = "classic"
    local isMajorFaction = false
    if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
        factionType = "renown"
        isMajorFaction = true
    elseif C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            factionType = "friendship"
        end
    end
    
    -- Resolve isAccountWide from BOTH API sources (matching ReputationScanner):
    -- 1. factionData.isAccountWide (may be nil in 12.0)
    -- 2. C_Reputation.IsAccountWideReputation (dedicated API, more reliable)
    local isAccountWide = fData.isAccountWide or false
    if not isAccountWide and C_Reputation.IsAccountWideReputation then
        isAccountWide = C_Reputation.IsAccountWideReputation(factionID) or false
    end
    
    local metadata = {
        factionID = factionID,
        name = fData.name,
        description = fData.description or "",
        isHeader = fData.isHeader or false,
        isHeaderWithRep = fData.isHeaderWithRep or false,
        isAccountWide = isAccountWide,
        isMajorFaction = isMajorFaction,
        type = factionType,
    }
    
    -- Only cache COMPLETE metadata (has a real name from the API)
    -- Circular buffer eviction (O(1) instead of O(n) table.remove)
    if #repMetadataCacheOrder >= REP_METADATA_CACHE_MAX then
        local evictID = repMetadataCacheOrder[repMetadataCacheHead]
        if evictID then
            repMetadataCache[evictID] = nil
        end
        repMetadataCacheOrder[repMetadataCacheHead] = factionID
        repMetadataCacheHead = (repMetadataCacheHead % REP_METADATA_CACHE_MAX) + 1
    else
        repMetadataCacheOrder[#repMetadataCacheOrder + 1] = factionID
    end
    
    repMetadataCache[factionID] = metadata
    
    return metadata
end

---Clear session-only reputation metadata cache
function WarbandNexus:ClearReputationMetadataCache()
    wipe(repMetadataCache)
    wipe(repMetadataCacheOrder)
    repMetadataCacheHead = 1
end

-- ============================================================================
-- COMPACT ↔ HYDRATE: SV stores only progress data, metadata fetched on-demand
-- ============================================================================

---Extract compact progress-only data from a normalized faction object.
---This is what gets persisted to SV. Essential metadata is preserved to avoid
---API dependency at render time (prevents "Faction #XXXX" placeholder names).
---@param normalized table Full normalized faction data from Processor
---@return table compact Progress data + essential metadata (name, type, isAccountWide)
local function CompactFactionData(normalized)
    local compact = {
        currentValue = normalized.currentValue,
        maxValue = normalized.maxValue,
        reaction = normalized.reaction,
        _scanIndex = normalized._scanIndex,
        _scanTime = normalized._scanTime or time(),
        hasParagon = normalized.hasParagon or false,
        
        -- Essential metadata (persisted to avoid API dependency at render time)
        _name = normalized.name,
        _type = normalized.type,
        _isAccountWide = normalized.isAccountWide or false,
        _isHeader = normalized.isHeader or false,
        _isHeaderWithRep = normalized.isHeaderWithRep or false,
    }
    
    -- Paragon progress (character-specific, API only for current char)
    if normalized.paragon then
        compact.paragon = {
            current = normalized.paragon.current,
            max = normalized.paragon.max,
            completedCycles = normalized.paragon.completedCycles,
            hasRewardPending = normalized.paragon.hasRewardPending,
        }
    end
    
    -- Renown level (character-specific for offline chars)
    if normalized.renown then
        compact.renown = {
            level = normalized.renown.level,
            current = normalized.renown.current,
            max = normalized.renown.max,
        }
    end
    
    -- Friendship (character-specific for offline chars)
    if normalized.friendship then
        compact.friendship = {
            level = normalized.friendship.level,
            maxLevel = normalized.friendship.maxLevel,
            reactionText = normalized.friendship.reactionText,
            current = normalized.friendship.current,
            max = normalized.friendship.max,
        }
    end
    
    return compact
end

---Hydrate compact SV data into full normalized format by combining with API metadata.
---Priority: stored compact metadata > live API metadata > fallback defaults.
---This ensures the UI never shows "Faction #XXXX" placeholders.
---@param factionID number
---@param compact table Compact data from SV (includes _name, _type, _isAccountWide)
---@param isAccountWide boolean Whether this is from the accountWide bucket
---@return table hydrated Full normalized faction data for UI consumption
local function HydrateFactionData(factionID, compact, isAccountWide)
    local metadata = ResolveFactionMetadata(factionID)
    
    -- Resolve isAccountWide from ALL sources (any true → account-wide):
    -- 1. Storage bucket (which DB table it's in)
    -- 2. Stored compact metadata from last scan (_isAccountWide)
    -- 3. Live API metadata (may change between patches)
    local resolvedAccountWide = isAccountWide
        or (compact._isAccountWide == true)
        or (metadata and metadata.isAccountWide)
        or false
    
    -- Resolve name: prefer stored name > API name > fallback
    local resolvedName
    if compact._name and compact._name ~= "" then
        resolvedName = compact._name
    elseif metadata and metadata.name then
        resolvedName = metadata.name
    else
        resolvedName = "Faction #" .. factionID
    end
    
    -- Resolve type: prefer stored > API > fallback
    local resolvedType = compact._type or (metadata and metadata.type) or "classic"
    
    -- Resolve parentFactionID from factionInfo (stored once per factionID)
    local db = GetDB()
    local fi = db and db.factionInfo and db.factionInfo[factionID]
    local parentFactionID = nil
    if type(fi) == "table" then
        parentFactionID = fi.pid
    end
    
    local hydrated = {
        -- Resolved metadata (stored compact > API > fallback)
        factionID = factionID,
        name = resolvedName,
        description = metadata and metadata.description or "",
        type = resolvedType,
        isHeader = (compact._isHeader == true) or (metadata and metadata.isHeader) or false,
        isHeaderWithRep = (compact._isHeaderWithRep == true) or (metadata and metadata.isHeaderWithRep) or false,
        isAccountWide = resolvedAccountWide,
        isMajorFaction = metadata and metadata.isMajorFaction or false,
        
        -- From factionInfo (stored once per factionID)
        parentFactionID = parentFactionID,
        
        -- From compact (SV)
        currentValue = compact.currentValue or 0,
        maxValue = compact.maxValue or 1,
        reaction = compact.reaction or 4,
        _scanIndex = compact._scanIndex or 99999,
        _scanTime = compact._scanTime or time(),
        hasParagon = compact.hasParagon or false,
        paragon = compact.paragon,
        renown = compact.renown,
        friendship = compact.friendship,
    }
    
    -- Derive standing name/color from reaction
    local reaction = hydrated.reaction
    if hydrated.hasParagon and hydrated.paragon then
        hydrated.standingName = (hydrated.paragon.hasRewardPending)
            and (((ns.L and ns.L["REP_REWARD_WAITING"]) or "Reward Waiting"))
            or (((ns.L and ns.L["REP_PARAGON_LABEL"]) or "Paragon"))
        hydrated.standingColor = ns.PARAGON_COLOR or {r = 0, g = 0.5, b = 1}
        hydrated.standingID = reaction
    elseif hydrated.type == "renown" and hydrated.renown then
        hydrated.standingName = ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown") .. " " .. (hydrated.renown.level or 0)
        hydrated.standingColor = ns.RENOWN_COLOR or {r = 1, g = 0.82, b = 0}
        hydrated.standingID = 8
    elseif hydrated.type == "friendship" and hydrated.friendship then
        hydrated.standingName = hydrated.friendship.reactionText or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        hydrated.standingColor = ns.RENOWN_COLOR or {r = 1, g = 0.82, b = 0}
        hydrated.standingID = hydrated.friendship.level or 4
    elseif hydrated.type == "header" then
        hydrated.standingName = "Header"
        hydrated.standingColor = {r = 1, g = 1, b = 1}
        hydrated.standingID = 0
    else
        hydrated.standingName = ns.STANDING_NAMES and ns.STANDING_NAMES[reaction] or "Unknown"
        hydrated.standingColor = ns.STANDING_COLORS and ns.STANDING_COLORS[reaction] or {r = 1, g = 1, b = 1}
        hydrated.standingID = reaction
    end
    
    return hydrated
end

-- ============================================================================
-- UNIFIED FACTION LOOKUP (Single Source of Truth)
-- ============================================================================

---Resolve the best available DB entry for a factionID and hydrate it.
---Priority:
---  1. Current character entry with real progress (maxValue > 1)
---  2. Account-wide entry with real progress (maxValue > 1)
---  3. Current character entry (even without progress)
---  4. Account-wide entry (even without progress)
---@param factionID number
---@return table|nil data Hydrated faction data
local function ResolveFactionData(factionID)
    local db = GetDB()
    if not db then return nil end
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
    
    -- Current character
    local charData = (db.characters[charKey] or {})[factionID]
    
    -- Account-wide
    local acctData = db.accountWide[factionID]
    
    -- Prefer entry with real progress (maxValue > 1 = has meaningful data)
    if charData and (charData.maxValue or 0) > 1 then
        return HydrateFactionData(factionID, charData, false)
    end
    if acctData and (acctData.maxValue or 0) > 1 then
        return HydrateFactionData(factionID, acctData, true)
    end
    
    -- Fallback: return whatever exists (character preferred)
    if charData then
        return HydrateFactionData(factionID, charData, false)
    end
    if acctData then
        return HydrateFactionData(factionID, acctData, true)
    end
    
    return nil
end

---Migrate old data structure (if needed).
---NOTE: Does NOT update db.version here — that happens after PerformFullScan
---completes successfully. This ensures a version mismatch triggers a re-scan.
local function MigrateDB()
    local db = GetDB()
    if not db then return end
    
    -- Check version
    if db.version == ReputationCache.version then
        return -- Already up to date
    end
    
    -- Handle FORCE_REBUILD marker (from /wn resetrep)
    if db.version == "FORCE_REBUILD" then
        db.version = nil  -- Will be set by UpdateAll after successful scan
        return
    end
    
    -- Version mismatch: NON-DESTRUCTIVE migration.
    -- DO NOT wipe any data — UpdateAll() will:
    --   1. Overwrite current character's data (wipe + re-store)
    --   2. Overwrite account-wide entries (with fresh isAccountWide detection)
    --   3. Purge stale character-specific entries that are now account-wide
    --   4. Rebuild headers and factionInfo
    -- Other characters' data is FULLY PRESERVED (both character-specific and AW).
    DebugPrint("|cff9370DB[ReputationCache]|r [Migrate] Version mismatch ("
        .. tostring(db.version) .. " -> " .. ReputationCache.version .. ") — non-destructive rescan")
    
    -- Only clear metadata that will be rebuilt by the scan
    db.lastScan = 0
    
    -- Ensure structure exists
    db.accountWide = db.accountWide or {}
    db.characters = db.characters or {}
    db.headers = db.headers or {}
    db.factionInfo = db.factionInfo or {}
    
    -- DO NOT update db.version here.
    -- Version is updated in UpdateAll() after a successful scan.
    -- This ensures Initialize() detects the mismatch and triggers a re-scan.
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
    
    -- Reputation data loaded from DB
    
    if needsScan then
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
end

---Build or rebuild the snapshot from current WoW API state.
---Iterates all factions via GetFactionDataByIndex (requires header expansion).
---Stored on ReputationCache._snapshot (not local) so it can be called from PerformFullScan.
---@param silent boolean If true, suppress all chat output
function ReputationCache:BuildSnapshot(silent)
    DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Action] SnapshotBuild triggered")
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
                barMax = data.nextReactionThreshold or 0,
            }
            count = count + 1
            
            -- Track renown level (separate API — for level-up detection in diff)
            if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                local majorData = C_MajorFactions.GetMajorFactionData(fid)
                if majorData and majorData.renownLevel then
                    self._snapshot[fid].renownLevel = majorData.renownLevel
                    self._snapshot[fid].isMajorFaction = true
                end
            end
            
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
    -- Snapshot built silently
end

---Perform snapshot diff: detect reputation changes and fire events.
---Iterates known factionIDs via GetFactionDataByID (no header expansion needed).
---Cost: ~187 GetFactionDataByID calls, each is a C-side table lookup → <1ms total.
---PERF: Debounced — skips if another diff ran within the last 100ms (prevents duplicate
---      processing when UPDATE_FACTION and CHAT_MSG_COMBAT_FACTION_CHANGE both fire).
function ReputationCache:PerformSnapshotDiff()
    local now = GetTime()
    if self._lastDiffTime and (now - self._lastDiffTime) < 0.1 then
        DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Action] SnapshotDiff SKIPPED (debounce)")
        return  -- Another diff ran <100ms ago, skip
    end
    self._lastDiffTime = now
    
    DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Action] SnapshotDiff triggered")
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
            
            -- 1b. Check renown level-up (major factions only)
            --     When renown level increases, currentStanding RESETS to a lower value.
            --     Without this check, the diff would see a decrease and miss the gain.
            local isRenownLevelUp = false
            if gainAmount == 0 and old.isMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                local majorData = C_MajorFactions.GetMajorFactionData(factionID)
                if majorData and majorData.renownLevel and old.renownLevel then
                    local newRenownLevel = majorData.renownLevel
                    if newRenownLevel > old.renownLevel then
                        -- Renown level UP! Bar reset is expected.
                        -- Gain = (remaining rep in old level) + (current rep in new level)
                        local oldRemaining = math.max(0, (old.barMax or 0) - old.barValue)
                        gainAmount = oldRemaining + newBarValue
                        isRenownLevelUp = true
                        -- Update snapshot renown level
                        old.renownLevel = newRenownLevel
                    end
                end
            end
            
            -- 1c. Check standard barValue change (covers classic, renown within-level, guild)
            --     Skip if friendship or renown level-up gain already detected
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
            old.barMax = barMax
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
                
                -- Resolve standing name/color for display in chat
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
                
                -- Check for friendship rank name
                if not standingName and old.isFriendship and old.friendshipName and old.friendshipName ~= "" then
                    standingName = old.friendshipName
                    standingColor = standingColor or {r = 0.5, g = 0.8, b = 1.0}
                end
                
                WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                    factionID = factionID,
                    factionName = factionName,
                    gainAmount = gainAmount,
                    currentRep = currentRep,
                    maxRep = maxRep,
                    wasStandingUp = wasStandingUp,
                    standingName = standingName,
                    standingColor = standingColor,
                })
                
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
    -- ChatFilter.lua handles message group removal (ChatFrame_RemoveMessageGroup).
    -- This filter serves as a secondary safety net for any chat frame that
    -- still has COMBAT_FACTION_CHANGE enabled.
    -- ============================================================
    ChatFrame_AddMessageEventFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", function(self, event, message, ...)
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return false
        end
        if not ReputationCache._snapshotReady then
            return false
        end
        return true
    end)
    
    -- ============================================================
    -- EVENT: UPDATE_FACTION — Primary gain detection
    -- CHAT_MSG_COMBAT_FACTION_CHANGE — Fallback (12.0 compatibility)
    --   In Midnight 12.0, UPDATE_FACTION may not fire reliably for all
    --   reputation types. CHAT_MSG_COMBAT_FACTION_CHANGE is a raw WoW event
    --   that fires to EventFrames regardless of ChatFrame message group state.
    --   This mirrors the currency system's CHAT_MSG_CURRENCY fallback.
    -- ============================================================
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_FACTION")
    eventFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    
    -- Fallback frame: CHAT_MSG_COMBAT_FACTION_CHANGE (raw event, not affected by ChatFrame_RemoveMessageGroup)
    local chatFallbackFrame = CreateFrame("Frame")
    chatFallbackFrame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
    chatFallbackFrame:SetScript("OnEvent", function(frame, event, message, ...)
        DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Event] CHAT_MSG_COMBAT_FACTION_CHANGE fallback triggered")
        
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        if not ReputationCache._snapshotReady then return end
        
        -- Small delay: let API values settle (CHAT_MSG fires very early in the event chain)
        -- PERF: PerformSnapshotDiff has debounce, so this is cheap if UPDATE_FACTION already ran
        C_Timer.After(0.05, function()
            if ReputationCache._snapshotReady then
                ReputationCache:PerformSnapshotDiff()
            end
            
            -- PERF: Only schedule FullScan if UPDATE_FACTION handler didn't already
            -- (updateThrottle is shared — if already set, skip)
            if not ReputationCache.updateThrottle then
                ReputationCache.updateThrottle = C_Timer.NewTimer(1.5, function()
                    ReputationCache.updateThrottle = nil
                    ReputationCache:PerformFullScan()
                end)
            end
        end)
    end)
    
    eventFrame:SetScript("OnEvent", function(frame, event)
        DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Event] " .. event .. " triggered")
        
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        if not ReputationCache._snapshotReady then return end
        
        -- Diff immediately — instant chat feedback
        ReputationCache:PerformSnapshotDiff()
        
        -- PERF: Background FullScan staggered at 1.0s (was 0.5s) to avoid overlapping
        -- with currency FullScans that fire around the same time
        if not ReputationCache.updateThrottle then
            ReputationCache.updateThrottle = C_Timer.NewTimer(1.0, function()
                ReputationCache.updateThrottle = nil
                ReputationCache:PerformFullScan()
            end)
        end
    end)
    
    -- ============================================================
    -- EVENT: ENCOUNTER_END — Boss kills in raids/dungeons give rep
    -- UPDATE_FACTION may fire with a delay after encounter ends.
    -- Schedule a diff after 1s to catch delayed rep updates.
    -- ============================================================
    local encounterFrame = CreateFrame("Frame")
    encounterFrame:RegisterEvent("ENCOUNTER_END")
    encounterFrame:SetScript("OnEvent", function(frame, event, encounterID, encounterName, difficultyID, groupSize, success)
        if not success or success == 0 then return end  -- Only on successful kills
        DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Event] ENCOUNTER_END triggered: " .. tostring(encounterName))
        
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        if not ReputationCache._snapshotReady then return end
        
        -- Delayed diff: boss rep often takes 0.5-1s to appear in the API
        C_Timer.After(1.0, function()
            if ReputationCache._snapshotReady then
                ReputationCache:PerformSnapshotDiff()
            end
        end)
        -- Also schedule a second diff at 2s for slow rep (Sylvanas-type RP phases)
        C_Timer.After(2.0, function()
            if ReputationCache._snapshotReady then
                ReputationCache:PerformSnapshotDiff()
            end
        end)
    end)
    
    -- ============================================================
    -- EVENT: QUEST_TURNED_IN — Quest rep may lag behind UPDATE_FACTION
    -- Uses dedicated frame (DailyQuestManager also registers via AceEvent)
    -- ============================================================
    local questFrame = CreateFrame("Frame")
    questFrame:RegisterEvent("QUEST_TURNED_IN")
    questFrame:SetScript("OnEvent", function()
        DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Event] QUEST_TURNED_IN triggered")
        
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
        end
    end)
    
end

-- ============================================================================
-- UPDATE OPERATIONS (Direct DB writes)
-- ============================================================================

---Update single faction (stores compact progress data in SV, strips metadata).
---@param factionID number
---@param normalizedData table Normalized faction data from Processor
function ReputationCache:UpdateFaction(factionID, normalizedData)
    if not factionID or factionID == 0 then
        return false
    end
    
    if not normalizedData then
        return false
    end
    
    local db = GetDB()
    if not db then
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Store compact (progress-only) data in SV
    local compact = CompactFactionData(normalizedData)
    
    if normalizedData.isAccountWide then
        db.accountWide[factionID] = compact
        -- Purge this faction from ALL character buckets (it's account-wide now)
        -- KEY TYPE SAFETY: check both number and string variants
        local numFid = tonumber(factionID)
        for charKey, charFactions in pairs(db.characters) do
            if charFactions[factionID] then
                charFactions[factionID] = nil
            end
            -- Also purge string/number variant
            if numFid then
                if charFactions[numFid] then charFactions[numFid] = nil end
                if charFactions[tostring(numFid)] then charFactions[tostring(numFid)] = nil end
            end
        end
    else
        if not db.characters[currentCharKey] then
            db.characters[currentCharKey] = {}
        end
        db.characters[currentCharKey][factionID] = compact
    end
    
    -- Store faction-level info once per factionID (not per char)
    db.factionInfo = db.factionInfo or {}
    if normalizedData.parentFactionName or normalizedData.parentFactionID then
        db.factionInfo[factionID] = {
            pn = normalizedData.parentFactionName,
            pid = normalizedData.parentFactionID,
        }
    end
    
    self.lastUpdate = time()
    
    -- Schedule UI refresh (debounced)
    ScheduleUIRefresh()
    
    return true
end

---Update all factions (MERGE into DB, stores compact progress data).
---@param normalizedDataArray table Array of normalized faction data from Processor
function ReputationCache:UpdateAll(normalizedDataArray)
    if not normalizedDataArray or #normalizedDataArray == 0 then
        return false
    end
    
    local db = GetDB()
    if not db then
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
    
    -- Ensure factionInfo table exists (stores parentFactionName once per factionID)
    db.factionInfo = db.factionInfo or {}
    
    -- MERGE data into DB (compact format — progress only, metadata stripped)
    -- CRITICAL: All factionIDs are normalized to NUMBER keys to prevent type mismatches
    local awCount = 0
    local charCount = 0
    
    for _, data in ipairs(normalizedDataArray) do
        if data.factionID then
            local numFactionID = tonumber(data.factionID) or data.factionID  -- Normalize to number
            local compact = CompactFactionData(data)
            
            if data.isAccountWide then
                db.accountWide[numFactionID] = compact
                awCount = awCount + 1
            else
                db.characters[currentCharKey][numFactionID] = compact
                charCount = charCount + 1
            end
            
            -- Store faction-level info in shared factionInfo (once per factionID)
            if data.parentFactionName or data.parentFactionID then
                db.factionInfo[numFactionID] = {
                    pn = data.parentFactionName,
                    pid = tonumber(data.parentFactionID) or data.parentFactionID,
                }
            end
        end
    end
    
    -- CRITICAL: Purge stale character entries for factions that are now account-wide.
    -- Old scans (before isAccountWide fix or from other characters) may have stored
    -- account-wide factions in db.characters[charKey]. Remove them so they don't
    -- appear in both Account-Wide and Character-Based sections.
    -- KEY TYPE SAFETY: db.accountWide and db.characters may use different key types
    -- (number vs string). Check BOTH variants to ensure purge works.
    local purged = 0
    -- Build account-wide lookup with BOTH key types
    local awLookup = {}
    for fid in pairs(db.accountWide) do
        awLookup[fid] = true
        local nid = tonumber(fid)
        if nid then
            awLookup[nid] = true
            awLookup[tostring(nid)] = true
        end
    end
    for charKey, charFactions in pairs(db.characters) do
        for factionID in pairs(charFactions) do
            if awLookup[factionID] then
                charFactions[factionID] = nil
                purged = purged + 1
            end
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    
    -- Update version AFTER successful scan (MigrateDB defers this to here)
    db.version = self.version
    
    -- Build headers
    self:BuildHeaders()
    
    -- Fire UI refresh immediately (full scan always shows results)
    ScheduleUIRefresh(true)
    
    return true
end

---Build headers from DB data (for UI grouping).
---Uses factionInfo lookup for parentFactionName (stored once per factionID, not per char).
function ReputationCache:BuildHeaders()
    local db = GetDB()
    if not db then return end
    
    local factionInfo = db.factionInfo or {}
    
    -- Helper: get compact data for a factionID from any source (normalized lookup)
    local function FindCompactData(factionID)
        local numID = tonumber(factionID) or factionID
        local data = db.accountWide[numID] or db.accountWide[factionID]
        if data then return data end
        for _, charFactions in pairs(db.characters) do
            data = charFactions[numID] or charFactions[factionID]
            if data then return data end
        end
        return nil
    end
    
    -- Group factions by parentFactionName (from factionInfo lookup)
    local headerMap = {}
    
    -- Collect all known factionIDs (NORMALIZED to numbers to prevent duplicates)
    local allFactionIDs = {}
    for factionID in pairs(db.accountWide) do
        local numID = tonumber(factionID) or factionID
        allFactionIDs[numID] = true
    end
    for _, charFactions in pairs(db.characters) do
        for factionID in pairs(charFactions) do
            local numID = tonumber(factionID) or factionID
            allFactionIDs[numID] = true
        end
    end
    
    -- Group by parentFactionName (use NORMALIZED number keys for factionInfo lookup)
    for factionID in pairs(allFactionIDs) do
        local numID = tonumber(factionID) or factionID
        local fi = factionInfo[numID] or factionInfo[factionID]
        local parentName = (type(fi) == "table" and fi.pn) or (type(fi) == "string" and fi) or nil
        if parentName and parentName ~= "" then
            if not headerMap[parentName] then
                headerMap[parentName] = {
                    name = parentName,
                    factions = {},
                    sortKey = 99999,
                }
            end
            table.insert(headerMap[parentName].factions, numID)
        end
    end
    
    -- Calculate MinIndex for each header (for sorting)
    for _, headerData in pairs(headerMap) do
        local minIndex = 99999
        for _, factionID in ipairs(headerData.factions) do
            local data = FindCompactData(factionID)
            if data and data._scanIndex and data._scanIndex < minIndex then
                minIndex = data._scanIndex
            end
        end
        headerData.sortKey = minIndex
        
        -- Sort factions within header by scanIndex
        table.sort(headerData.factions, function(a, b)
            local dataA = FindCompactData(a)
            local dataB = FindCompactData(b)
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

---Clear ALL reputation data (nuclear wipe — fixes duplication from stale entries)
---@param clearDB boolean Also clear SavedVariables
function ReputationCache:Clear(clearDB)
    if clearDB then
        local db = GetDB()
        if db then
            -- NUCLEAR WIPE: Clear ALL reputation data (not just current character)
            -- This is the ONLY way to guarantee stale/duplicate entries are removed.
            -- Data will be rebuilt from scratch on next scan.
            wipe(db.accountWide)
            wipe(db.characters)
            wipe(db.headers)
            if db.factionInfo then wipe(db.factionInfo) end
            
            -- Reset version to force full re-scan
            db.version = nil
            db.lastScan = 0
            
            DebugPrint("|cff9370DB[ReputationCache]|r [Clear] NUCLEAR WIPE: all reputation data cleared")
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
    DebugPrint("|cff9370DB[ReputationCache]|r [Reputation Action] FullScan triggered (bypass=" .. tostring(bypassThrottle) .. ")")
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
            return
        end
    end
    
    if self.isScanning then
        return
    end
    
    -- PERF: Global coordination — if currency scan is running, defer to avoid
    -- two heavy scans in the same frame causing FPS drops
    if ns._fullScanInProgress then
        DebugPrint("|cff9370DB[ReputationCache]|r [PERF] Deferring FullScan — another scan in progress")
        C_Timer.After(1.0, function()
            if ReputationCache then
                ReputationCache:PerformFullScan(bypassThrottle)
            end
        end)
        return
    end
    
    self.isScanning = true
    ns._fullScanInProgress = true
    
    -- Set loading state for UI
    ns.ReputationLoadingState.isLoading = true
    ns.ReputationLoadingState.loadingProgress = 0
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_FETCHING"]) or "Fetching reputation data..."
    
    -- Trigger UI refresh to show loading state
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
    end
    
    -- Scan raw data
    local rawData = Scanner:FetchAllFactions()
    
    if not rawData or #rawData == 0 then
        self.isScanning = false
        ns._fullScanInProgress = false  -- PERF: Release global scan lock
        
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
    
    for i, raw in ipairs(rawData) do
        local normalized = Processor:Process(raw)
        if normalized then
            table.insert(normalizedData, normalized)
        end
    end
    -- PERF: Progress state updated once (not per-faction) — screen can't redraw mid-loop anyway
    ns.ReputationLoadingState.loadingProgress = 66
    ns.ReputationLoadingState.currentStage = string.format((ns.L and ns.L["REP_LOADING_PROCESSING_COUNT"]) or "Processed %d factions", #normalizedData)
    
    -- Update DB
    ns.ReputationLoadingState.loadingProgress = 66
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_SAVING"]) or "Saving to database..."
    self:UpdateAll(normalizedData)
    
    -- Complete - clear loading state immediately
    ns.ReputationLoadingState.isLoading = false
    ns.ReputationLoadingState.loadingProgress = 100
    ns.ReputationLoadingState.currentStage = (ns.L and ns.L["REP_LOADING_COMPLETE"]) or "Complete!"
    
    self.isScanning = false
    ns._fullScanInProgress = false  -- PERF: Release global scan lock
    
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

---Get all normalized reputation data (ALL characters).
---Hydrates compact SV data with on-demand API metadata.
---@return table Array of hydrated faction data with _characterKey metadata
function WarbandNexus:GetAllReputations()
    local db = GetDB()
    if not db then return {} end
    
    local result = {}
    
    -- Build account-wide lookup (NORMALIZED to number keys)
    local accountWideFactionIDs = {}
    for factionID in pairs(db.accountWide) do
        local numID = tonumber(factionID) or factionID
        accountWideFactionIDs[numID] = true
    end
    
    -- FINAL DEDUP: Track every factionID we've already emitted (prevents ANY duplication)
    local emittedFactionCharPairs = {}  -- ["factionID|charKey"] = true
    
    -- Add account-wide reputations (hydrated)
    for factionID, compact in pairs(db.accountWide) do
        local numID = tonumber(factionID) or factionID
        local dedupKey = numID .. "|AW"
        if not emittedFactionCharPairs[dedupKey] then
            emittedFactionCharPairs[dedupKey] = true
                    local entry = HydrateFactionData(numID, compact, true)
            entry.factionID = numID  -- Ensure normalized
            entry.isAccountWide = true  -- Single source of truth: account-wide section only
            entry._characterKey = (ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide"
            table.insert(result, entry)
        end
    end
    
    -- Add character-specific reputations (from ALL characters, hydrated)
    -- CRITICAL: Skip any factionID that already exists in accountWide
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
        
        for factionID, compact in pairs(charFactions) do
            local numID = tonumber(factionID) or factionID
            -- DEDUP: Skip if in accountWide OR already emitted for this character
            if not accountWideFactionIDs[numID] then
                local dedupKey = numID .. "|" .. charKey
                if not emittedFactionCharPairs[dedupKey] then
                    emittedFactionCharPairs[dedupKey] = true
                    local entry = HydrateFactionData(numID, compact, false)
                    entry.factionID = numID  -- Ensure normalized
                    entry.isAccountWide = false  -- Single source of truth: character-based section only
                    entry._characterKey = charKey
                    entry._characterClass = charClass
                    table.insert(result, entry)
                end
            end
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
    
    -- Check account-wide storage (compact format)
    local accountWideData = db.accountWide[factionID]
    if accountWideData then
        print("|cffffcc00[Storage]|r Account-Wide (db.accountWide[" .. factionID .. "]) [compact]")
        print("  Reaction: " .. (accountWideData.reaction or 0))
        print("  Progress: " .. (accountWideData.currentValue or 0) .. "/" .. (accountWideData.maxValue or 1))
        print("  HasParagon: " .. tostring(accountWideData.hasParagon))
    else
        print("|cff666666[Storage]|r NOT in account-wide storage")
    end
    
    -- Check character-specific storage (compact format)
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
            print("    Reaction: " .. (charData.reaction or 0))
            print("    Progress: " .. (charData.currentValue or 0) .. "/" .. (charData.maxValue or 1))
            print("    HasParagon: " .. tostring(charData.hasParagon))
            
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

---Global debug function: Dump duplication analysis
---Usage: /run WNRepDupCheck()
_G.WNRepDupCheck = function()
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus or not WarbandNexus.db then
        print("|cffff0000[DupCheck]|r WarbandNexus not loaded")
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[DupCheck]|r DB not initialized")
        return
    end
    
    print("|cffff00ff[DupCheck]|r Reputation Duplication Analysis")
    print("==============================================")
    print("DB Version: " .. tostring(db.version))
    print("Cache Version: " .. tostring(ReputationCache.version))
    
    -- Count entries
    local awCount = 0
    local awIDs = {}
    for fid in pairs(db.accountWide) do
        awCount = awCount + 1
        awIDs[tonumber(fid) or fid] = true
    end
    
    local charCount = 0
    local dupInBoth = 0
    local dupList = {}
    for charKey, charFactions in pairs(db.characters) do
        for fid in pairs(charFactions) do
            charCount = charCount + 1
            local numFid = tonumber(fid) or fid
            if awIDs[numFid] then
                dupInBoth = dupInBoth + 1
                table.insert(dupList, numFid)
            end
        end
    end
    
    print(string.format("Account-Wide entries: %d", awCount))
    print(string.format("Character entries: %d", charCount))
    print(string.format("|cffff0000DUPLICATES (in BOTH)|r: %d", dupInBoth))
    
    if dupInBoth > 0 then
        for _, fid in ipairs(dupList) do
            local name = "?"
            if C_Reputation and C_Reputation.GetFactionDataByID then
                local d = C_Reputation.GetFactionDataByID(fid)
                if d then name = d.name or "?" end
            end
            print(string.format("  |cffff0000DUP|r: %s (ID:%d)", name, fid))
        end
    end
    
    -- Check key types
    local numKeys = 0
    local strKeys = 0
    for fid in pairs(db.accountWide) do
        if type(fid) == "number" then numKeys = numKeys + 1
        elseif type(fid) == "string" then strKeys = strKeys + 1 end
    end
    for _, charFactions in pairs(db.characters) do
        for fid in pairs(charFactions) do
            if type(fid) == "number" then numKeys = numKeys + 1
            elseif type(fid) == "string" then strKeys = strKeys + 1 end
        end
    end
    print(string.format("Key types: %d number, %d string", numKeys, strKeys))
    
    -- Check API for sample AW detection
    print("")
    print("|cff00ff00[Live API Check]|r (first 5 AW factions):")
    local apiChecked = 0
    for fid in pairs(db.accountWide) do
        if apiChecked >= 5 then break end
        local numFid = tonumber(fid) or fid
        local apiAW = false
        if C_Reputation.IsAccountWideReputation then
            apiAW = C_Reputation.IsAccountWideReputation(numFid) or false
        end
        local name = "?"
        local d = C_Reputation.GetFactionDataByID(numFid)
        if d then name = d.name or "?" end
        print(string.format("  %s (ID:%d): API=%s, Stored=AW", name, numFid, tostring(apiAW)))
        apiChecked = apiChecked + 1
    end
    
    print("==============================================")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.ReputationCache = ReputationCache

-- NOTE: Initialize() is called from Core.lua OnEnable() after DB is ready
-- Do NOT call Initialize() here - WarbandNexus.db may not be loaded yet
