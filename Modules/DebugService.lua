--[[============================================================================
    DEBUG SERVICE
    Centralized debugging and testing utilities for Warband Nexus
    
    Handles:
    - Debug logging with profile-based control
    - Bank debugging utilities
    - Force scanning and data wiping
    
    Architecture: Service Pattern
    - All methods accept addon instance as first parameter
    - No direct state storage, uses addon.db
    - Provides utilities for slash commands
============================================================================]]

local addonName, ns = ...
local issecretvalue = issecretvalue
local DebugService = {}
ns.DebugService = DebugService
local IsDebugModeEnabled = ns.IsDebugModeEnabled or function() return false end
local IsDebugVerboseEnabled = ns.IsDebugVerboseEnabled or function() return false end

--============================================================================
-- DEBUG LOGGING
--============================================================================

-- Noisy prefixes: only shown when debugVerbose is true (avoids cache/scan/tooltip spam)
local DEBUG_VERBOSE_PREFIXES = {
    ["[CurrencyCache]"] = true,
    ["[ReputationCache]"] = true,
    ["[WN BAG SCAN]"] = true,
    ["[Tooltip]"] = true,
    ["[Recharge Timer]"] = true,
    ["[Knowledge]"] = true,
}

--- Print debug message if debug mode is enabled in profile.
--- Noisy messages (cache, scan, tooltip, etc.) require debugVerbose to be true.
---@param addon table WarbandNexus addon instance
---@param message string Message to print
function DebugService:Debug(addon, message)
    if not IsDebugModeEnabled() then return end
    local msg = tostring(message)
    for prefix in pairs(DEBUG_VERBOSE_PREFIXES) do
        if msg:find(prefix, 1, true) then
            if not IsDebugVerboseEnabled() then return end
            break
        end
    end
    addon:Print("|cff888888[DEBUG]|r " .. msg)
end

--============================================================================
-- BANK DEBUGGING
--============================================================================

--- Print comprehensive bank debug information
--- Helps diagnose Warband Bank detection issues
---@param addon table WarbandNexus addon instance
function DebugService:PrintBankDebugInfo(addon)
    addon:Print("=== Bank Debug Info ===")
    
    -- Internal state flags
    addon:Print("Internal Flags:")
    addon:Print("  self.bankIsOpen: " .. tostring(addon.bankIsOpen))
    addon:Print("  self.warbandBankIsOpen: " .. tostring(addon.warbandBankIsOpen))
    
    -- BankFrame check
    addon:Print("BankFrame:")
    addon:Print("  exists: " .. tostring(BankFrame ~= nil))
    if BankFrame then
        addon:Print("  IsShown: " .. tostring(BankFrame:IsShown()))
    end
    
    -- Bag slot check (most reliable)
    addon:Print("Warband Bank Bags:")
    for i = 1, 5 do
        local bagID = Enum.BagIndex["AccountBankTab_" .. i]
        if bagID then
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            local itemCount = 0
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info and info.itemID then
                        itemCount = itemCount + 1
                    end
                end
            end
            addon:Print("  Tab " .. i .. ": BagID=" .. bagID .. ", Slots=" .. tostring(numSlots) .. ", Items=" .. itemCount)
        end
    end
    
    -- Final result
    addon:Print("IsWarbandBankOpen(): " .. tostring(ns.Utilities:IsWarbandBankOpen(addon)))
    addon:Print("======================")
end

--- Force scan Warband Bank without checking if it's open (for debugging)
---@param addon table WarbandNexus addon instance
function DebugService:ForceScanWarbandBank(addon)
    addon:Print("Force scanning Warband Bank (bypassing open check)...")
    
    -- Temporarily mark bank as open for scan
    local wasOpen = addon.bankIsOpen
    addon.bankIsOpen = true
    
    -- Use the existing Scanner module
    local success = addon:ScanWarbandBank()
    
    -- Restore original state
    addon.bankIsOpen = wasOpen
    
    if success then
        addon:Print("Force scan complete!")
    else
        addon:Print("|cffff0000Force scan failed. Bank might not be accessible.|r")
    end
end

--============================================================================
-- CHARACTER & PVE DEBUG INFO
--============================================================================

--- Print list of all tracked characters with their info
---@param addon table WarbandNexus addon instance
function DebugService:PrintCharacterList(addon)
    addon:Print("=== Tracked Characters ===")
    
    local chars = addon:GetAllCharacters()
    if #chars == 0 then
        addon:Print("No characters tracked yet.")
        return
    end
    
    for ci = 1, #chars do
        local char = chars[ci]
        local lastSeenText = ""
        if char.lastSeen then
            local diff = time() - char.lastSeen
            if diff < 60 then
                lastSeenText = "now"
            elseif diff < 3600 then
                lastSeenText = math.floor(diff / 60) .. "m ago"
            elseif diff < 86400 then
                lastSeenText = math.floor(diff / 3600) .. "h ago"
            else
                lastSeenText = math.floor(diff / 86400) .. "d ago"
            end
        end
        
        addon:Print(string.format("  %s (%s Lv%d) - %s",
            char.name or "?",
            char.classFile or "?",
            char.level or 0,
            lastSeenText
        ))
    end
    
    addon:Print("Total: " .. #chars .. " characters")
    addon:Print("==========================")
end

--- Print current character's PvE data (vault, M+, lockouts) for debugging
---@param addon table WarbandNexus addon instance
function DebugService:PrintPvEData(addon)
    local tableKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon)
    if not tableKey and ns.Utilities.GetCharacterStorageKey then
        tableKey = ns.Utilities:GetCharacterStorageKey(addon)
    end
    if not tableKey then
        tableKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    end
    if not tableKey then return end
    local name = UnitName("player")
    if name and issecretvalue and issecretvalue(name) then name = nil end
    addon:Print("=== PvE Data for " .. (name or "?") .. " ===")
    
    local pveData = addon:CollectPvEData()
    
    -- Great Vault
    addon:Print("|cffffd700Great Vault:|r")
    if pveData.greatVault and #pveData.greatVault > 0 then
        local gv = pveData.greatVault
        for i = 1, #gv do
            local activity = gv[i]
            local typeName = "Unknown"
            local typeNum = activity.type
            
            -- Try Enum first, fallback to numbers
            if Enum and Enum.WeeklyRewardChestThresholdType then
                if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                end
            else
                -- Fallback to numeric values
                if typeNum == 1 then typeName = "Raid"
                elseif typeNum == 2 then typeName = "M+"
                elseif typeNum == 3 then typeName = "PvP"
                elseif typeNum == 4 then typeName = "World"
                end
            end
            
            addon:Print(string.format("  %s (type=%d) [%d]: %d/%d (Level %d)", 
                typeName, typeNum, activity.index or 0, 
                activity.progress or 0, activity.threshold or 0,
                activity.level or 0))
        end
    else
        addon:Print("  No vault data available")
    end
    
    -- Mythic+
    addon:Print("|cffa335eeM+ Keystone:|r")
    if pveData.mythicPlus and pveData.mythicPlus.keystone then
        local ks = pveData.mythicPlus.keystone
        addon:Print(string.format("  %s +%d", ks.name or "Unknown", ks.level or 0))
    else
        addon:Print("  No keystone")
    end
    if pveData.mythicPlus then
        if pveData.mythicPlus.weeklyBest then
            addon:Print(string.format("  Weekly Best: +%d", pveData.mythicPlus.weeklyBest))
        end
        if pveData.mythicPlus.runsThisWeek then
            addon:Print(string.format("  Runs This Week: %d", pveData.mythicPlus.runsThisWeek))
        end
    end
    
    -- Lockouts
    addon:Print("|cff0070ddRaid Lockouts:|r")
    if pveData.lockouts and #pveData.lockouts > 0 then
        local lockouts = pveData.lockouts
        for i = 1, #lockouts do
            local lockout = lockouts[i]
            addon:Print(string.format("  %s (%s): %d/%d", 
                lockout.name or "Unknown",
                lockout.difficultyName or "Normal",
                lockout.progress or 0,
                lockout.total or 0))
        end
    else
        addon:Print("  No active lockouts")
    end
    
    addon:Print("===========================")
    
    -- Save the data
    if addon.db.global.characters and addon.db.global.characters[tableKey] then
        addon.db.global.characters[tableKey].pve = pveData
        addon.db.global.characters[tableKey].lastSeen = time()
        addon:Print("|cff00ff00Data saved! Open the PvE tab to view.|r")
    end
end

--============================================================================
-- DATA MANAGEMENT
--============================================================================

--- Wipe all addon data and reload UI
--- WARNING: This is a destructive operation that cannot be undone
---@param addon table WarbandNexus addon instance
function DebugService:WipeAllData(addon)
    addon:Print("|cffff9900Wiping all addon data...|r")
    
    -- Close UI first
    if addon.HideMainWindow then
        addon:HideMainWindow()
    end
    
    -- Clear all caches
    if addon.ClearAllCaches then
        addon:ClearAllCaches()
    end
    
    -- Reset the entire database
    if addon.db then
        addon.db:ResetDB(true)
    end
    
    addon:Print("|cff00ff00All data wiped! Reloading UI...|r")

    -- Reload UI after a short delay
    C_Timer.After(1, function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        else
            ReloadUI()
        end
    end)
end
