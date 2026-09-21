--[[
    Warband Nexus - Collection notification dedup (ring buffer + persistent DB layers).
    Split from CollectionService.lua to reduce main chunk size (Lua 5.1 local limit).
    Loaded from WarbandNexus.toc immediately before Modules/CollectionService.lua.

    Layers: persistent DB (notifiedCollectibles) | bag-detect TTL | session ring (id/name cooldown)
    Achievement toast ack: WasAchievementToastDisplayed / MarkAchievementToastDisplayed (toast actually shown)
    Replace-mode fallback: ScheduleAchievementToastFallback when AddAlert does not fire after ACHIEVEMENT_EARNED
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue

local IsDebugVerboseEnabled = ns.IsDebugVerboseEnabled
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter(
    nil,
    { verboseOnly = true, suppressWhenTryCounterLoot = true }
)) or function() end
local function DebugPrintf(fmt, ...)
    if IsDebugVerboseEnabled and IsDebugVerboseEnabled() then
        DebugPrint(string.format(fmt, ...))
    end
end
-- RING BUFFER: O(1) bounded dedup cache
-- Fixed-size circular array. When full, the oldest entry is evicted automatically.
-- Supports time-based cooldown checks via the stored timestamp.

---Create a new ring buffer with the given capacity
---@param capacity number Maximum entries before eviction
---@return table ringBuffer
local function CreateRingBuffer(capacity)
    return {
        entries = {},       -- [slot] = { key, timestamp, cooldown }
        lookup = {},        -- [key] = slot (for O(1) existence check)
        capacity = capacity,
        head = 1,           -- Next write position (1-indexed, wraps)
        size = 0,           -- Current number of valid entries
    }
end

---Check if a key exists in the ring buffer and is within its cooldown
---@param rb table Ring buffer
---@param key string Lookup key
---@return boolean isActive True if key was recently added and cooldown hasn't expired
local function RingBufferCheck(rb, key)
    local slot = rb.lookup[key]
    if not slot then return false end
    
    local entry = rb.entries[slot]
    if not entry or entry.key ~= key then
        -- Slot was overwritten by a newer entry; stale lookup
        rb.lookup[key] = nil
        return false
    end
    
    local elapsed = GetTime() - entry.timestamp
    if elapsed < entry.cooldown then
        return true
    end
    
    -- Expired
    return false
end

---Add or refresh a key in the ring buffer
---@param rb table Ring buffer
---@param key string Lookup key
---@param cooldown number Cooldown in seconds
local function RingBufferAdd(rb, key, cooldown)
    -- If key already exists and is in a valid slot, update in-place
    local existingSlot = rb.lookup[key]
    if existingSlot then
        local entry = rb.entries[existingSlot]
        if entry and entry.key == key then
            entry.timestamp = GetTime()
            entry.cooldown = cooldown
            return
        end
        -- Stale lookup, will be overwritten below
    end
    
    -- Evict oldest entry at head position if buffer is full
    local slot = rb.head
    local old = rb.entries[slot]
    if old then
        rb.lookup[old.key] = nil  -- Remove old entry's lookup
    end
    
    -- Write new entry
    rb.entries[slot] = { key = key, timestamp = GetTime(), cooldown = cooldown }
    rb.lookup[key] = slot
    
    -- Advance head
    rb.head = (slot % rb.capacity) + 1
    if rb.size < rb.capacity then
        rb.size = rb.size + 1
    end
end

-- Unified session dedup buffer (replaces 3 separate tables + O(n) cleanups)
-- Capacity 64: more than enough for rapid loot events without memory growth
local recentNotifications = CreateRingBuffer(64)

local function CollectiblePayloadObtainedBy()
    local name = UnitName("player")
    if not name or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
    return name
end

-- Cooldown constants
local NOTIFICATION_COOLDOWN = 5    -- By type_id: 5 seconds
local NAME_DEBOUNCE_COOLDOWN = 2   -- By item name: 2 seconds
local BAG_PET_NAME_COOLDOWN = 60   -- Pet name fallback: 60 seconds

-- LAYER 0: Persistent DB (notifiedCollectibles) — permanent dedup
-- Records every collectible that was successfully notified. Prevents
-- duplicate notifications across sessions (e.g. WoW re-fires NEW_TOY_ADDED
-- on login for already-owned toys). Keys: "type_id" → true.

---Initialize notifiedCollectibles DB (persistent across reloads)
local function InitializeNotifiedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not WarbandNexus.db.global.notifiedCollectibles then
        WarbandNexus.db.global.notifiedCollectibles = {}
    end
end

---Check if a collectible was already notified in a previous session
---@param collectibleType string "mount", "pet", "toy"
---@param collectibleID number Collectible ID
---@return boolean wasNotified
local function WasAlreadyNotified(collectibleType, collectibleID)
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.notifiedCollectibles then
        return false
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    return WarbandNexus.db.global.notifiedCollectibles[key] == true
end

---Mark a collectible as notified (persistent, survives reload/logout)
---@param collectibleType string "mount", "pet", "toy"
---@param collectibleID number Collectible ID
local function MarkAsPermanentlyNotified(collectibleType, collectibleID)
    InitializeNotifiedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.notifiedCollectibles then
        return
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    WarbandNexus.db.global.notifiedCollectibles[key] = true
end

-- LAYER 1: Persistent DB (bagDetectedCollectibles) — unchanged semantics

---Initialize bag-detected collectibles DB (persistent across reloads)
local function InitializeBagDetectedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not WarbandNexus.db.global.bagDetectedCollectibles then
        WarbandNexus.db.global.bagDetectedCollectibles = {}
    end
end

local BAG_DETECTED_EXPIRY = 7200  -- 2 hours

---Check if collectible was detected in bag scan (time-limited, 2 hour expiry)
---@param collectibleType string Type: "mount", "pet", "toy"
---@param collectibleID number Collectible ID
---@return boolean wasDetected
local function WasDetectedInBag(collectibleType, collectibleID)
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.bagDetectedCollectibles then
        return false
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    local detectedAt = WarbandNexus.db.global.bagDetectedCollectibles[key]
    -- Legacy support: `true` (boolean) from old code → treat as expired
    if detectedAt == true then
        WarbandNexus.db.global.bagDetectedCollectibles[key] = nil
        return false
    end
    if type(detectedAt) == "number" then
        if (time() - detectedAt) < BAG_DETECTED_EXPIRY then
            return true
        end
        WarbandNexus.db.global.bagDetectedCollectibles[key] = nil
    end
    return false
end

---Mark collectible as detected in bag (session-persistent with timestamp)
---@param collectibleType string Type: "mount", "pet", "toy"
---@param collectibleID number Collectible ID
local function MarkAsDetectedInBag(collectibleType, collectibleID)
    InitializeBagDetectedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.bagDetectedCollectibles then
        return
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    WarbandNexus.db.global.bagDetectedCollectibles[key] = time()
    DebugPrintf("|cff00ffff[WN DeDupe]|r Marked %s %s as BAG-DETECTED", collectibleType, collectibleID)
end

-- LAYER 2: Session ring buffer — O(1) dedup for all short-term checks

---Check if an item name was recently shown (2s debounce)
---@param itemName string The item/collectible name
---@return boolean
local function WasRecentlyShownByName(itemName)
    if not itemName or (issecretvalue and issecretvalue(itemName)) then return false end
    local blocked = RingBufferCheck(recentNotifications, "name:" .. itemName)
    if blocked then
        DebugPrintf("|cffff8800[WN NameDebounce]|r '%s' → BLOCKED (quick debounce)", itemName)
    end
    return blocked
end

---Mark item name as recently shown (2s debounce)
---@param itemName string
local function MarkAsShownByName(itemName)
    if not itemName or (issecretvalue and issecretvalue(itemName)) then return end
    RingBufferAdd(recentNotifications, "name:" .. itemName, NAME_DEBOUNCE_COOLDOWN)
end

---Check if collectible was recently notified by ID (5s cooldown)
---@param collectibleType string
---@param collectibleID number
---@return boolean
local function WasRecentlyNotified(collectibleType, collectibleID)
    local key = "id:" .. collectibleType .. "_" .. tostring(collectibleID)
    local blocked = RingBufferCheck(recentNotifications, key)
    if blocked then
        DebugPrintf("|cff888888[WN DeDupe]|r %s %s → BLOCKED (id cooldown)", collectibleType, collectibleID)
    end
    return blocked
end

---Mark collectible as notified by ID (5s cooldown)
---@param collectibleType string
---@param collectibleID number
local function MarkAsNotified(collectibleType, collectibleID)
    RingBufferAdd(recentNotifications, "id:" .. collectibleType .. "_" .. tostring(collectibleID), NOTIFICATION_COOLDOWN)
end

-- Achievement toast acknowledgment (session): set only after WN modal actually queued for display.
local achievementToastDisplayed = {}

---@param achievementID number
---@return boolean
local function WasAchievementToastDisplayed(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return false end
    if issecretvalue and issecretvalue(achievementID) then return false end
    return achievementToastDisplayed[achievementID] == true
end

---@param achievementID number
local function MarkAchievementToastDisplayed(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    achievementToastDisplayed[achievementID] = true
end

-- Replace mode: ACHIEVEMENT_EARNED may fire without a matching AddAlert; fallback after short delay.
local pendingAchievementToast = {}
local ACHIEVEMENT_TOAST_FALLBACK_SEC = 1.25

---@param achievementID number
local function ClearPendingAchievementToast(achievementID)
    if achievementID then
        pendingAchievementToast[achievementID] = nil
    end
end

---@param achievementID number
local function ScheduleAchievementToastFallback(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    local NP = ns.NotificationPresentation
    if not NP or not NP.UseWarbandAchievementPopups() then return end
    pendingAchievementToast[achievementID] = true
    C_Timer.After(ACHIEVEMENT_TOAST_FALLBACK_SEC, function()
        if not pendingAchievementToast[achievementID] then return end
        local addon = WarbandNexus
        if not addon then
            pendingAchievementToast[achievementID] = nil
            return
        end
        if WasAchievementToastDisplayed(achievementID) or WasAlreadyNotified("achievement", achievementID) then
            pendingAchievementToast[achievementID] = nil
            return
        end
        local shown = addon.ShowAchievementNotification and addon:ShowAchievementNotification(achievementID)
        if shown then
            pendingAchievementToast[achievementID] = nil
            return
        end
        pendingAchievementToast[achievementID] = nil
        if addon.InvokeBlizzardAchievementAddAlert then
            addon:InvokeBlizzardAchievementAddAlert(achievementID)
        end
    end)
end

local Notify = {
    NOTIFICATION_COOLDOWN = NOTIFICATION_COOLDOWN,
    NAME_DEBOUNCE_COOLDOWN = NAME_DEBOUNCE_COOLDOWN,
    BAG_PET_NAME_COOLDOWN = BAG_PET_NAME_COOLDOWN,
    InitializeNotifiedDB = InitializeNotifiedDB,
    InitializeBagDetectedDB = InitializeBagDetectedDB,
    WasAlreadyNotified = WasAlreadyNotified,
    MarkAsPermanentlyNotified = MarkAsPermanentlyNotified,
    WasDetectedInBag = WasDetectedInBag,
    MarkAsDetectedInBag = MarkAsDetectedInBag,
    WasRecentlyShownByName = WasRecentlyShownByName,
    MarkAsShownByName = MarkAsShownByName,
    WasRecentlyNotified = WasRecentlyNotified,
    MarkAsNotified = MarkAsNotified,
    WasAchievementToastDisplayed = WasAchievementToastDisplayed,
    MarkAchievementToastDisplayed = MarkAchievementToastDisplayed,
    ClearPendingAchievementToast = ClearPendingAchievementToast,
    ScheduleAchievementToastFallback = ScheduleAchievementToastFallback,
    ACHIEVEMENT_TOAST_FALLBACK_SEC = ACHIEVEMENT_TOAST_FALLBACK_SEC,
    CollectiblePayloadObtainedBy = CollectiblePayloadObtainedBy,
    MarkPetNameBagCooldown = function(itemName)
        if not itemName or (issecretvalue and issecretvalue(itemName)) then return end
        RingBufferAdd(recentNotifications, "petname:" .. itemName, BAG_PET_NAME_COOLDOWN)
    end,
    IsPetNameBagCooldownActive = function(itemName)
        if not itemName or (issecretvalue and issecretvalue(itemName)) then return false end
        return RingBufferCheck(recentNotifications, "petname:" .. itemName)
    end,
}

ns.CollectionNotify = Notify
