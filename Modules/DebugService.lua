--[[============================================================================
    DEBUG SERVICE
    Centralized debugging and testing utilities for Warband Nexus
    
    Handles:
    - Debug logging with profile-based control
    - Test commands for development
    - Bank debugging utilities
    - Force scanning and data wiping
    
    Architecture: Service Pattern
    - All methods accept addon instance as first parameter
    - No direct state storage, uses addon.db
    - Provides utilities for slash commands
============================================================================]]

local addonName, ns = ...
local DebugService = {}
ns.DebugService = DebugService

--============================================================================
-- DEBUG LOGGING
--============================================================================

--- Print debug message if debug mode is enabled in profile
---@param addon table WarbandNexus addon instance
---@param message string Message to print
function DebugService:Debug(addon, message)
    if addon.db and addon.db.profile and addon.db.profile.debugMode then
        addon:Print("|cff888888[DEBUG]|r " .. tostring(message))
    end
end

--============================================================================
-- TEST COMMANDS
--============================================================================

--- Handle test commands for development and debugging
---@param addon table WarbandNexus addon instance
---@param input string Command input from slash command
function DebugService:TestCommand(addon, input)
    print("|cff9370DB[WN DebugService]|r TestCommand triggered: " .. tostring(input))
    
    local cmd, subcmd = addon:GetArgs(input, 2)
    
    if not cmd or cmd == "" then
        addon:Print("|cff00ccffWarband Nexus Test Commands|r")
        addon:Print("  |cff00ccff/wntest overflow|r - Check font overflow status")
        addon:Print("  |cff00ccff/wntest rep|r - Force reputation scan")
        addon:Print("  |cff00ccff/wntest rep ui|r - Force reputation UI refresh")
        addon:Print("  |cff00ccff/wntest rep event|r - Simulate reputation change")
        addon:Print("  |cff00ccff/wntest achievement [id]|r - Test achievement (default: 60981)")
        addon:Print("  |cff00ccff/wntest plan [id]|r - Test plan completion (default: 60981)")
        addon:Print("|cff888888Examples:|r")
        addon:Print("|cff888888  /wntest achievement 60981|r")
        addon:Print("|cff888888  /wntest plan 60981|r")
        return
    end
    
    if cmd == "overflow" then
        if not ns.OverflowMonitor then
            addon:Print("|cffff0000OverflowMonitor not loaded!|r")
            return
        end
        
        local hasOverflow = ns.OverflowMonitor:CheckAll()
        
        if not hasOverflow then
            addon:Print("|cff00ff00No font overflow detected!|r")
        else
            addon:Print("|cffffcc00Font overflow detected in visible UI elements!|r")
            addon:Print("Try reducing font scale in settings.")
        end
    elseif cmd == "rep" then
        if not subcmd or subcmd == "" then
            -- Force reputation scan
            if addon.ScanReputations then
                addon:Print("|cff00ccffForcing reputation scan...|r")
                addon.currentTrigger = "TEST_COMMAND"
                addon:ScanReputations()
                addon:Print("|cff00ff00Reputation scan complete!|r")
            else
                addon:Print("|cffff0000ScanReputations not available!|r")
            end
        elseif subcmd == "ui" then
            -- Force UI refresh
            if addon.UI and addon.UI.RefreshUI then
                addon:Print("|cff00ccffForcing reputation UI refresh...|r")
                addon.UI:RefreshUI()
                addon:Print("|cff00ff00UI refreshed!|r")
            else
                addon:Print("|cffff0000UI not available or not on reputation tab!|r")
            end
        elseif subcmd == "event" then
            -- Simulate reputation change event
            addon:Print("|cff00ccffSimulating UPDATE_FACTION event...|r")
            addon:SendMessage("WARBAND_REPUTATIONS_UPDATED")
            addon:Print("|cff00ff00Event sent!|r")
        else
            addon:Print("|cffff0000Unknown rep subcommand:|r " .. subcmd)
            addon:Print("Use: /wntest rep [ui|event]")
        end
    elseif cmd == "achievement" then
        -- Test achievement notification with ID
        local achievementID = tonumber(subcmd) or 60981
        if addon.TestLootNotification then
            addon:Print("|cff00ccffTesting achievement notification (ID: " .. achievementID .. ")...|r")
            addon:TestLootNotification("achievement", achievementID)
        else
            addon:Print("|cffff0000TestLootNotification not available!|r")
        end
    elseif cmd == "plan" then
        -- Test plan completion notification with achievement ID
        local achievementID = tonumber(subcmd) or 60981
        if addon.TestLootNotification then
            addon:Print("|cff00ccffTesting plan completion (Achievement ID: " .. achievementID .. ")...|r")
            addon:TestLootNotification("plan", achievementID)
        else
            addon:Print("|cffff0000TestLootNotification not available!|r")
        end
    else
        addon:Print("|cffff0000Unknown test command:|r " .. cmd)
        addon:Print("Use /wntest to see available commands")
    end
    
    print("|cff00ff00[WN DebugService]|r TestCommand complete")
end

--============================================================================
-- BANK DEBUGGING
--============================================================================

--- Print comprehensive bank debug information
--- Helps diagnose Warband Bank detection issues
---@param addon table WarbandNexus addon instance
function DebugService:PrintBankDebugInfo(addon)
    print("|cff9370DB[WN DebugService]|r PrintBankDebugInfo triggered")
    
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
    
    print("|cff00ff00[WN DebugService]|r PrintBankDebugInfo complete")
end

--- Force scan Warband Bank without checking if it's open (for debugging)
---@param addon table WarbandNexus addon instance
function DebugService:ForceScanWarbandBank(addon)
    print("|cff9370DB[WN DebugService]|r ForceScanWarbandBank triggered")
    
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
        print("|cff00ff00[WN DebugService]|r Force scan succeeded")
    else
        addon:Print("|cffff0000Force scan failed. Bank might not be accessible.|r")
        print("|cffff0000[WN DebugService]|r Force scan failed")
    end
end

--============================================================================
-- CHARACTER & PVE DEBUG INFO
--============================================================================

--- Print list of all tracked characters with their info
---@param addon table WarbandNexus addon instance
function DebugService:PrintCharacterList(addon)
    print("|cff9370DB[WN DebugService]|r PrintCharacterList triggered")
    
    addon:Print("=== Tracked Characters ===")
    
    local chars = addon:GetAllCharacters()
    if #chars == 0 then
        addon:Print("No characters tracked yet.")
        return
    end
    
    for _, char in ipairs(chars) do
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
    
    print("|cff00ff00[WN DebugService]|r PrintCharacterList complete")
end

--- Print current character's PvE data (vault, M+, lockouts) for debugging
---@param addon table WarbandNexus addon instance
function DebugService:PrintPvEData(addon)
    print("|cff9370DB[WN DebugService]|r PrintPvEData triggered")
    
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    addon:Print("=== PvE Data for " .. name .. " ===")
    
    local pveData = addon:CollectPvEData()
    
    -- Great Vault
    addon:Print("|cffffd700Great Vault:|r")
    if pveData.greatVault and #pveData.greatVault > 0 then
        for i, activity in ipairs(pveData.greatVault) do
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
        for i, lockout in ipairs(pveData.lockouts) do
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
    if addon.db.global.characters and addon.db.global.characters[key] then
        addon.db.global.characters[key].pve = pveData
        addon.db.global.characters[key].lastSeen = time()
        addon:Print("|cff00ff00Data saved! Use /wn pve to view in UI|r")
    end
    
    print("|cff00ff00[WN DebugService]|r PrintPvEData complete")
end

--============================================================================
-- DATA MANAGEMENT
--============================================================================

--- Wipe all addon data and reload UI
--- WARNING: This is a destructive operation that cannot be undone
---@param addon table WarbandNexus addon instance
function DebugService:WipeAllData(addon)
    print("|cffff9900[WN DebugService]|r WipeAllData triggered - DESTRUCTIVE OPERATION")
    
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
    print("|cffff0000[WN DebugService]|r Database wiped, reloading UI")
    
    -- Reload UI after a short delay
    C_Timer.After(1, function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        else
            ReloadUI()
        end
    end)
end
