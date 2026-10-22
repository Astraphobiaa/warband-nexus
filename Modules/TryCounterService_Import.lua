--[[
    Warband Nexus - Try Counter legacy mount tracker import (split from TryCounterService.lua, 2026-10-22)
    Optional cross-addon merge of mount attempts (max never lowers WN) + import backup / restore.
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local E = ns.Constants.EVENTS
local TC = ns.TryCounter or {}
local Fns = TC.Fns

assert(Fns, "TryCounterService_Import: load TryCounterService.lua first")

local tonumber = tonumber
local pairs = pairs
local format = string.format
local C_MountJournal = C_MountJournal
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

-- LEGACY MOUNT TRACKER IMPORT (optional cross-addon merge)
-- Reads a third-party addon global (AceDB profile.groups.mounts); only mount rows with attempts > 0.
-- Try keys: mount journal ID from C_MountJournal.GetMountFromItem(itemId), else itemId.

local LEGACY_MOUNT_TRACKER_GLOBAL = "Ra" .. "rity"

function Fns.ResolveMountTryKeyFromItemId(itemId)
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local m = C_MountJournal.GetMountFromItem(itemId)
        if m and not (issecretvalue and issecretvalue(m)) then
            local n = tonumber(m)
            if n and n > 0 then
                return n
            end
        end
    end
    return itemId
end

function Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, extAttempts)
    if not itemId or itemId < 1 or not extAttempts or extAttempts < 1 then
        return false
    end
    local mountKey = Fns.ResolveMountTryKeyFromItemId(itemId)
    -- Non-repeatable mounts: after collection, WN count is the frozen "tries to obtain" value.
    -- Do not raise it from Rarity/backup merge (avoids post-drop inflation when Rarity kept counting).
    local probeDrop = { type = "mount", itemID = itemId }
    if not self:IsRepeatableCollectible("mount", mountKey)
        and not self:IsRepeatableCollectible("mount", itemId)
        and Fns.IsCollectibleCollected(probeDrop) then
        return false
    end
    local wnA = self:GetTryCount("mount", mountKey) or 0
    local wnB = (mountKey ~= itemId) and (self:GetTryCount("mount", itemId) or 0) or 0
    local base = wnA
    if wnB > base then
        base = wnB
    end
    local total = base
    if extAttempts > total then
        total = extAttempts
    end
    if total > base then
        self:SetTryCount("mount", mountKey, total)
        if mountKey ~= itemId then
            self:SetTryCount("mount", itemId, total)
        end
        return true
    end
    return false
end

function Fns.MergeRarityProfileMountsIntoWnBackup(mounts)
    if not Fns.EnsureDB() or type(mounts) ~= "table" then
        return
    end
    local tc = WarbandNexus.db.global.tryCounts
    if not tc.rarityImportBackup then
        tc.rarityImportBackup = {}
    end
    local b = tc.rarityImportBackup
    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" and entry.enabled ~= false then
            local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
            local attempts = tonumber(entry.attempts) or 0
            if itemId and itemId > 0 and attempts > 0 then
                b[itemId] = math.max(b[itemId] or 0, attempts)
            end
        end
    end
    tc.rarityImportBackupAt = time()
end

--- Re-apply stored backup (no Rarity addon required). Safe to run after Rarity is removed.
---@return number updated
---@return number scanned
function WarbandNexus:RestoreRarityImportBackup()
    if not Fns.EnsureDB() then
        return 0, 0
    end
    local b = WarbandNexus.db.global.tryCounts.rarityImportBackup
    if type(b) ~= "table" then
        return 0, 0
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end
    local updated = 0
    local scanned = 0
    for itemIdRaw, attRaw in pairs(b) do
        local itemId = tonumber(itemIdRaw)
        local attempts = tonumber(attRaw)
        if itemId and itemId > 0 and attempts and attempts > 0 then
            scanned = scanned + 1
            if Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                updated = updated + 1
            end
        end
    end
    if updated > 0 and self.SendMessage then
        self:SendMessage(E.PLANS_UPDATED, { action = "legacy_mount_tracker_import" })
    end
    return updated, scanned
end

--- One-time handoff: try to load Rarity, merge several times (late AceDB init), refresh backup each successful read.
function WarbandNexus:ImportRarityMountHandoff()
    if not Fns.EnsureDB() then
        return
    end
    if InCombatLockdown() then
        self:Print("|cffff6600[WN]|r Exit combat, then run Rarity handoff again from Warband Nexus → Settings → Try Counter.")
        return
    end
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Rarity")
    end

    local delays = { 0.2, 1.0, 3.0, 8.0 }
    local pass = 0
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if not Fns.EnsureDB() then
                return
            end
            WarbandNexus:SyncRarityMountAttemptsMax()
            pass = pass + 1
            if pass == #delays then
                -- Re-apply saved backup so mount journal / keys are consistent even if earlier passes were cold.
                WarbandNexus:RestoreRarityImportBackup()
                local bn = 0
                local bk = WarbandNexus.db.global.tryCounts.rarityImportBackup
                if type(bk) == "table" then
                    for _ in pairs(bk) do
                        bn = bn + 1
                    end
                end
                if bn > 0 then
                    self:Print(string.format(
                        "|cff00ff00[WN]|r Rarity handoff complete. |cffffffff%d|r mount itemID(s) copied into WN backup + try counts (max). You can disable Rarity. If a count looks wrong: use Restore from backup in Try Counter settings.|r",
                        bn
                    ))
                else
                    self:Print("|cffff6600[WN]|r No Rarity mount data found. Enable the |cffffcc00Rarity|r addon in Esc → AddOns, |cff00ccff/reload|r, then run Rarity handoff from Try Counter settings.|r")
                end
            end
        end)
    end
    self:Print("|cff9370DB[WN]|r Rarity import running (multiple passes). Wait ~8s for the summary line.|r")
end

--- Merge Rarity (or same-shape tracker) mount attempts using **max**, not sum — same boss kills as Statistics/Rarity must not double-count.
--- Runs on every schedule pass (login / alt / reload) so profile stays aligned with WN try counts.
--- On every successful read, merges into db.global.tryCounts.rarityImportBackup for offline restore.
---@return number updated rows touched
---@return number scanned rows with attempts > 0
function WarbandNexus:SyncRarityMountAttemptsMax()
    if not Fns.EnsureDB() then
        return 0, 0
    end

    local Ext = rawget(_G, LEGACY_MOUNT_TRACKER_GLOBAL)
    if not Ext or type(Ext) ~= "table" or not Ext.db or not Ext.db.profile or type(Ext.db.profile.groups) ~= "table" then
        return 0, 0
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end

    local mounts = Ext.db.profile.groups.mounts
    if type(mounts) ~= "table" then
        return 0, 0
    end

    local updated = 0
    local scanned = 0

    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" then
            if entry.enabled ~= false then
                local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
                local attempts = tonumber(entry.attempts) or 0
                if itemId and itemId > 0 and attempts > 0 then
                    scanned = scanned + 1
                    if Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                        updated = updated + 1
                    end
                end
            end
        end
    end

    if scanned > 0 then
        Fns.MergeRarityProfileMountsIntoWnBackup(mounts)
        local tc = WarbandNexus.db.global.tryCounts
        tc.legacyMountTrackerSeedComplete = true
    end

    if updated > 0 and self.SendMessage then
        self:SendMessage(E.PLANS_UPDATED, { action = "legacy_mount_tracker_import" })
    end

    return updated, scanned
end

---@deprecated Use SyncRarityMountAttemptsMax; kept for API compatibility.
function WarbandNexus:ImportLegacyMountTrackerAttempts()
    return self:SyncRarityMountAttemptsMax()
end

function WarbandNexus:DebugResetLegacyMountTrackerSeed()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        self:Print("|cffff6600[WN]|r Enable debug mode first (/wn debug).")
        return
    end
    if not Fns.EnsureDB() then
        return
    end
    WarbandNexus.db.global.tryCounts.legacyMountTrackerSeedComplete = false
    self:Print("|cff00ff00[WN]|r Seed flag cleared (informational). Rarity merge does not use this flag — with Rarity enabled, wait for post-login sync or trigger merge from Try Counter settings.")
end

function WarbandNexus:DebugLegacyMountTrackerImportPreview()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        self:Print("|cffff6600[WN]|r Enable debug mode first (/wn debug).")
        return
    end
    local Ext = rawget(_G, LEGACY_MOUNT_TRACKER_GLOBAL)
    if not Ext or not Ext.db or not Ext.db.profile or type(Ext.db.profile.groups) ~= "table" then
        self:Print("|cffff6600[WN]|r Legacy mount tracker not loaded.")
        return
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end
    local mounts = Ext.db.profile.groups.mounts
    if type(mounts) ~= "table" then
        self:Print("|cffff6600[WN]|r No groups.mounts in tracker profile.")
        return
    end
    local seedDone = WarbandNexus.db.global.tryCounts and WarbandNexus.db.global.tryCounts.legacyMountTrackerSeedComplete
    self:Print("|cff9370DB[WN]|r Mount tracker preview | seed done: " .. tostring(seedDone == true) .. " | itemID → mountKey | ext | WN")
    local n = 0
    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" and entry.enabled ~= false then
            local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
            local attempts = tonumber(entry.attempts) or 0
            if itemId and itemId > 0 and attempts > 0 then
                n = n + 1
                if n <= 40 then
                    local mk = Fns.ResolveMountTryKeyFromItemId(itemId)
                    local wMk = self:GetTryCount("mount", mk)
                    local wItem = (mk ~= itemId) and self:GetTryCount("mount", itemId) or wMk
                    self:Print(format(
                        "  |cffffd100%s|r | item=%d key=%d | ext=%d | WN(key)=%d | WN(item)=%d",
                        key, itemId, mk, attempts, wMk, wItem
                    ))
                end
            end
        end
    end
    if n > 40 then
        self:Print(format("|cff888888... +%d rows (cap 40)|r", n - 40))
    end
    self:Print(format("|cff9370DB[WN]|r Mount rows with attempts: %d", n))
end
