--[[============================================================================
    COMMAND SERVICE
    Centralized slash command routing and handling for Warband Nexus
    
    Handles:
    - Main slash command routing (/wn, /warbandnexus)
    - Public commands (show, options, help, cleanup, etc.)
    - Debug commands (scan, currency, pve, etc.)
    - Test commands (testloot, testevents, testeffect)
    
    Architecture: Service Pattern
    - All methods accept addon instance as first parameter
    - No direct state storage, uses addon.db
    - Provides utilities for command parsing and execution
============================================================================]]

local addonName, ns = ...
local CommandService = {}
ns.CommandService = CommandService

--============================================================================
-- MAIN SLASH COMMAND HANDLER
--============================================================================

--- Main slash command router
--- Handles all /wn and /warbandnexus commands
---@param addon table WarbandNexus addon instance
---@param input string Command input from slash command
function CommandService:HandleSlashCommand(addon, input)
    print("|cff9370DB[WN CommandService]|r HandleSlashCommand: " .. tostring(input))
    
    local cmd = addon:GetArgs(input, 1)
    
    -- No command - open addon window
    if not cmd or cmd == "" then
        addon:ShowMainWindow()
        return
    end
    
    -- Help command - show available commands
    if cmd == "help" then
        addon:Print("|cff00ccffWarband Nexus|r - Available commands:")
        addon:Print("  |cff00ccff/wn|r - Open addon window")
        addon:Print("  |cff00ccff/wn options|r - Open settings")
        addon:Print("  |cff00ccff/wn debug|r - Toggle debug mode")
        addon:Print("  |cff00ccff/wn clearcache|r - Clear collection cache & rescan (achievements, titles, etc.)")
        addon:Print("  |cff00ccff/wn scanquests [tww|df|sl]|r - Scan & debug daily quests")
        addon:Print("  |cff00ccff/wntest overflow|r - Check font overflow")
        addon:Print("  |cff00ccff/wn cleanup|r - Remove inactive characters (90+ days)")
        addon:Print("  |cff00ccff/wn resetrep|r - Reset reputation data (rebuild from API)")
        addon:Print("  |cff888888/wn testloot [type]|r - Test notifications (mount/pet/toy/etc)")
        addon:Print("  |cff888888/wn testevents [type]|r - Test event system (collectible/plan/vault/quest)")
        addon:Print("  |cff888888/wn testeffect|r - Test visual effects (glow/flash/border)")
        addon:Print("  |cff888888/wn testvault|r - Test weekly vault slot notification")
        return
    end
    
    -- Public commands (always available)
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        addon:ShowMainWindow()
        return
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        addon:OpenOptions()
        return
    elseif cmd == "cleanup" then
        if addon.CleanupStaleCharacters then
            local removed = addon:CleanupStaleCharacters(90)
            if removed == 0 then
                addon:Print("|cff00ff00No inactive characters found (90+ days)|r")
            else
                addon:Print("|cff00ff00Removed " .. removed .. " inactive character(s)|r")
            end
        end
        return
    elseif cmd == "resetrep" then
        CommandService:HandleResetRep(addon)
        return
    elseif cmd == "clearcache" or cmd == "refreshcache" then
        CommandService:HandleClearCache(addon)
        return
    elseif cmd == "debug" then
        CommandService:HandleDebugToggle(addon)
        return
    elseif cmd == "spacing" then
        CommandService:HandleSpacingDebug(addon)
        return
    elseif cmd == "fixgender" then
        CommandService:HandleFixGender(addon)
        return
    elseif cmd == "savechar" then
        CommandService:HandleSaveChar(addon)
        return
    elseif cmd == "testvault" then
        CommandService:HandleTestVault(addon)
        return
    elseif cmd == "scanquests" or cmd:match("^scanquests%s") then
        CommandService:HandleScanQuests(addon, cmd)
        return
    end
    
    -- Debug commands (only work when debug mode is enabled)
    if not addon.db.profile.debugMode then
        addon:Print("|cffff6600Unknown command. Type |r|cff00ccff/wn help|r|cffff6600 for available commands.|r")
        return
    end
    
    -- Debug mode active - process debug commands
    CommandService:HandleDebugCommands(addon, cmd, input)
end

--============================================================================
-- PUBLIC COMMAND HANDLERS
--============================================================================

--- Handle reputation reset command
---@param addon table WarbandNexus addon instance
function CommandService:HandleResetRep(addon)
    print("|cff9370DB[WN CommandService]|r HandleResetRep triggered")
    
    addon:Print("|cffff9900Resetting reputation data...|r")
    addon:Print("|cffff9900Debug logs will show API responses|r")
    
    -- Clear old metadata (v2: global storage)
    if addon.db.global.factionMetadata then
        addon.db.global.factionMetadata = {}
    end
    
    -- Clear global reputation data (v2)
    if addon.db.global.reputations then
        addon.db.global.reputations = {}
    end
    if addon.db.global.reputationHeaders then
        addon.db.global.reputationHeaders = {}
    end
    
    local playerKey = ns.Utilities:GetCharacterKey()
    
    -- Invalidate cache
    if addon.InvalidateReputationCache then
        addon:InvalidateReputationCache(playerKey)
    end
    
    -- Rebuild metadata and scan
    if addon.BuildFactionMetadata then
        addon:BuildFactionMetadata()
    end
    
    if addon.ScanReputations then
        C_Timer.After(0.5, function()
            addon.currentTrigger = "CMD_RESET"
            addon:ScanReputations()
            addon:Print("|cff00ff00Reputation data reset complete! Reloading UI...|r")
            
            -- Refresh UI
            if addon.RefreshUI then
                addon:RefreshUI()
            end
        end)
    end
    
    print("|cff00ff00[WN CommandService]|r HandleResetRep complete")
end

--- Handle cache clear command
---@param addon table WarbandNexus addon instance
function CommandService:HandleClearCache(addon)
    print("|cff9370DB[WN CommandService]|r HandleClearCache triggered")
    
    addon:Print("|cffffcc00Clearing collection cache...|r")
    
    -- Clear DB cache
    if addon.db and addon.db.global and addon.db.global.collectionCache then
        addon.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {} },
            version = "3.0.0",
            lastScan = 0
        }
        addon:Print("|cff00ff00Database cache cleared!|r")
    end
    
    -- Reinitialize cache (loads from DB, which is now empty)
    if addon.InitializeCollectionCache then
        addon:InitializeCollectionCache()
        addon:Print("|cff00ff00Cache reinitialized!|r")
    end
    
    -- Trigger background scans
    addon:Print("|cffffcc00Triggering background scans...|r")
    
    -- Scan collections (mounts, pets, toys)
    if addon.ScanCollectionsAsync then
        C_Timer.After(0.5, function()
            addon:ScanCollectionsAsync()
        end)
        addon:Print("  → Scanning mounts, pets, toys...")
    end
    
    -- Scan achievements + titles
    if addon.ScanAchievementsAsync then
        C_Timer.After(1.0, function()
            addon:ScanAchievementsAsync()
        end)
        addon:Print("  → Scanning achievements + titles...")
    end
    
    -- Refresh UI
    C_Timer.After(2.0, function()
        if addon.RefreshUI then
            addon:RefreshUI()
            addon:Print("|cff00ff00Cache refresh complete! UI updated.|r")
        end
    end)
    
    addon:Print("|cff9370DB[WN]|r Background scans started. Check back in ~10 seconds!")
    
    print("|cff00ff00[WN CommandService]|r HandleClearCache complete")
end

--- Handle debug mode toggle command
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugToggle(addon)
    addon.db.profile.debugMode = not addon.db.profile.debugMode
    if addon.db.profile.debugMode then
        addon:Print("|cff00ff00Debug mode enabled|r")
    else
        addon:Print("|cffff9900Debug mode disabled|r")
    end
end

--- Handle spacing debug command
---@param addon table WarbandNexus addon instance
function CommandService:HandleSpacingDebug(addon)
    addon:Print("=== UI Spacing Constants ===")
    if ns.UI_LAYOUT then
        addon:Print("HEADER_SPACING (Should be 40): " .. tostring(ns.UI_LAYOUT.HEADER_SPACING))
        addon:Print("ROW_SPACING (Should be 28): " .. tostring(ns.UI_LAYOUT.ROW_SPACING))
        addon:Print("ROW_HEIGHT: " .. tostring(ns.UI_LAYOUT.ROW_HEIGHT))
        addon:Print("betweenRows: " .. tostring(ns.UI_LAYOUT.betweenRows))
        addon:Print("headerSpacing (Old): " .. tostring(ns.UI_LAYOUT.headerSpacing))
        addon:Print("SECTION_SPACING: " .. tostring(ns.UI_LAYOUT.SECTION_SPACING))
    else
        addon:Print("Error: ns.UI_LAYOUT is nil")
    end
end

--- Handle gender fix command
---@param addon table WarbandNexus addon instance
function CommandService:HandleFixGender(addon)
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if addon.db.global.characters and addon.db.global.characters[key] then
        local currentGender = addon.db.global.characters[key].gender
        local detectedGender = UnitSex("player")
        
        -- Try C_PlayerInfo as backup
        local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
        if raceInfo and raceInfo.gender ~= nil then
            -- Convert: C_PlayerInfo returns 0=male, 1=female
            detectedGender = (raceInfo.gender == 1) and 3 or 2
            addon:Print(string.format("|cff00ccffUsing C_PlayerInfo.GetRaceInfo().gender=%d → %d|r", 
                raceInfo.gender, detectedGender))
        end
        
        addon:Print(string.format("|cffff9900Current saved gender: %d (%s)|r", 
            currentGender or 0,
            currentGender == 3 and "Female" or (currentGender == 2 and "Male" or "Unknown")))
        addon:Print(string.format("|cff00ccffDetected gender: %d (%s)|r", 
            detectedGender or 0,
            detectedGender == 3 and "Female" or (detectedGender == 2 and "Male" or "Unknown")))
        
        if detectedGender and detectedGender ~= currentGender then
            addon.db.global.characters[key].gender = detectedGender
            addon:Print("|cff00ff00Gender updated! Refresh UI with /wn to see changes.|r")
        else
            addon:Print("|cffff0000No change needed or unable to detect gender.|r")
        end
    else
        addon:Print("|cffff0000Character data not found!|r")
    end
end

--- Handle character save command
---@param addon table WarbandNexus addon instance
function CommandService:HandleSaveChar(addon)
    addon:Print("|cff00ccffManually saving character data...|r")
    local success = addon:SaveCurrentCharacterData()
    if success ~= false then
        addon:Print("|cff00ff00Character saved successfully!|r")
    else
        addon:Print("|cffff0000Failed to save character data.|r")
    end
end

--- Handle test vault command
---@param addon table WarbandNexus addon instance
function CommandService:HandleTestVault(addon)
    local currentName = UnitName("player")
    if addon.ShowWeeklySlotNotification then
        addon:Print("|cff00ff00Testing weekly vault notification...|r")
        addon:ShowWeeklySlotNotification(currentName, "world", 1, 2)
    else
        addon:Print("|cffff0000Error: ShowWeeklySlotNotification not found!|r")
    end
end

--- Handle scan quests command
---@param addon table WarbandNexus addon instance
---@param cmd string Command with arguments
function CommandService:HandleScanQuests(addon, cmd)
    local contentType = cmd:match("^scanquests%s+(%S+)") or "tww"
    
    if not addon.ScanDailyQuests then
        addon:Print("|cffff0000Error: ScanDailyQuests not found!|r")
        return
    end
    
    addon:Print("|cff00ff00Scanning daily quests for content: " .. contentType .. "|r")
    local quests = addon:ScanDailyQuests(contentType)
    
    addon:Print(string.format("|cff00ff00Results: %d daily, %d world, %d weekly, %d assignments|r",
        #quests.dailyQuests, #quests.worldQuests, #quests.weeklyQuests,
        #quests.assignments or 0))
    
    -- List daily quests
    if #quests.dailyQuests > 0 then
        addon:Print("|cffaaaaaa=== Daily Quests ===|r")
        for _, quest in ipairs(quests.dailyQuests) do
            addon:Print(string.format("  [%d] %s", quest.questID, quest.title))
        end
    end
end

--============================================================================
-- DEBUG COMMAND HANDLERS
--============================================================================

--- Handle debug commands (requires debug mode enabled)
---@param addon table WarbandNexus addon instance
---@param cmd string Command name
---@param input string Full command input
function CommandService:HandleDebugCommands(addon, cmd, input)
    if cmd == "scan" then
        addon:ScanWarbandBank()
    elseif cmd == "scancurr" then
        CommandService:HandleScanCurrency(addon)
    elseif cmd == "chars" or cmd == "characters" then
        addon:PrintCharacterList()
    elseif cmd == "storage" or cmd == "browse" then
        addon:ShowMainWindow()
        if addon.UI and addon.UI.mainFrame then
            addon.UI.mainFrame.currentTab = "storage"
            if addon.PopulateContent then
                addon:PopulateContent()
            end
        end
    elseif cmd == "pve" then
        addon:ShowMainWindow()
        if addon.UI and addon.UI.mainFrame then
            addon.UI.mainFrame.currentTab = "pve"
            if addon.PopulateContent then
                addon:PopulateContent()
            end
        end
    elseif cmd == "pvedata" or cmd == "pveinfo" then
        addon:PrintPvEData()
    elseif cmd == "enumcheck" then
        CommandService:HandleEnumCheck(addon)
    elseif cmd == "cache" or cmd == "cachestats" then
        if addon.PrintCacheStats then
            addon:PrintCacheStats()
        else
            addon:Print("CacheManager not loaded")
        end
    elseif cmd == "events" or cmd == "eventstats" then
        if addon.PrintEventStats then
            addon:PrintEventStats()
        else
            addon:Print("EventManager not loaded")
        end
    elseif cmd == "resetprof" then
        CommandService:HandleResetProfession(addon)
    elseif cmd == "currency" or cmd == "curr" then
        CommandService:HandleCurrencyDebug(addon)
    elseif cmd == "minimap" then
        if addon.ToggleMinimapButton then
            addon:ToggleMinimapButton()
        else
            addon:Print("Minimap button module not loaded")
        end
    elseif cmd == "vaultcheck" or cmd == "testvault" then
        if addon.TestVaultCheck then
            addon:TestVaultCheck()
        else
            addon:Print("Vault check module not loaded")
        end
    elseif cmd == "testloot" then
        CommandService:HandleTestLoot(addon, input)
    elseif cmd == "testevents" then
        CommandService:HandleTestEvents(addon, input)
    elseif cmd == "initloot" then
        addon:Print("|cff00ccff[DEBUG] Forcing InitializeLootNotifications...|r")
        if addon.InitializeLootNotifications then
            addon:InitializeLootNotifications()
        else
            addon:Print("|cffff0000ERROR: InitializeLootNotifications not found!|r")
        end
    elseif cmd == "testeffect" then
        if addon.TestNotificationEffects then
            addon:TestNotificationEffects()
        else
            addon:Print("|cffff0000TestNotificationEffects function not found!|r")
        end
    elseif cmd == "errors" then
        CommandService:HandleErrors(addon, input)
    elseif cmd == "recover" or cmd == "emergency" then
        if addon.EmergencyRecovery then
            addon:EmergencyRecovery()
        end
    elseif cmd == "dbstats" or cmd == "dbinfo" then
        if addon.PrintDatabaseStats then
            addon:PrintDatabaseStats()
        end
    elseif cmd == "optimize" or cmd == "dboptimize" then
        if addon.RunOptimization then
            addon:RunOptimization()
        end
    elseif cmd == "apireport" or cmd == "apicompat" then
        if addon.PrintAPIReport then
            addon:PrintAPIReport()
        end
    else
        addon:Print("|cffff6600Unknown command:|r " .. cmd)
    end
end

--============================================================================
-- DEBUG COMMAND IMPLEMENTATIONS
--============================================================================

--- Handle currency scan command
---@param addon table WarbandNexus addon instance
function CommandService:HandleScanCurrency(addon)
    addon:Print("=== Scanning ALL Currencies ===")
    if not C_CurrencyInfo then
        addon:Print("|cffff0000C_CurrencyInfo API not available!|r")
        return
    end
    
    local etherealFound = {}
    local totalScanned = 0
    
    -- Scan by iterating through possible currency IDs (brute force for testing)
    for id = 3000, 3200 do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.name and info.name ~= "" then
            totalScanned = totalScanned + 1
            
            -- Look for Ethereal or Season 3 related
            if info.name:match("Ethereal") or info.name:match("Season") then
                table.insert(etherealFound, string.format("[%d] %s (qty: %d)", 
                    id, info.name, info.quantity or 0))
            end
        end
    end
    
    if #etherealFound > 0 then
        addon:Print("|cff00ff00Found Ethereal/Season 3 currencies:|r")
        for _, line in ipairs(etherealFound) do
            addon:Print(line)
        end
    else
        addon:Print("|cffffcc00No Ethereal currencies found in range 3000-3200|r")
    end
    
    addon:Print(string.format("Total currencies scanned: %d", totalScanned))
end

--- Handle enum check command
---@param addon table WarbandNexus addon instance
function CommandService:HandleEnumCheck(addon)
    addon:Print("=== Enum.WeeklyRewardChestThresholdType Values ===")
    if Enum and Enum.WeeklyRewardChestThresholdType then
        addon:Print("  Raid: " .. tostring(Enum.WeeklyRewardChestThresholdType.Raid))
        addon:Print("  Activities (M+): " .. tostring(Enum.WeeklyRewardChestThresholdType.Activities))
        addon:Print("  RankedPvP: " .. tostring(Enum.WeeklyRewardChestThresholdType.RankedPvP))
        addon:Print("  World: " .. tostring(Enum.WeeklyRewardChestThresholdType.World))
    else
        addon:Print("  Enum.WeeklyRewardChestThresholdType not available")
    end
    addon:Print("=============================================")
    -- Also collect and show current vault activities
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        if activities and #activities > 0 then
            addon:Print("Current Vault Activities:")
            for i, activity in ipairs(activities) do
                addon:Print(string.format("  [%d] type=%s, index=%s, progress=%s/%s", 
                    i, tostring(activity.type), tostring(activity.index),
                    tostring(activity.progress), tostring(activity.threshold)))
            end
        else
            addon:Print("No current vault activities")
        end
    end
end

--- Handle profession reset command
---@param addon table WarbandNexus addon instance
function CommandService:HandleResetProfession(addon)
    if addon.ResetProfessionData then
        addon:ResetProfessionData()
        addon:Print("Profession data reset.")
    else
        -- Manual fallback
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        if addon.db.global.characters and addon.db.global.characters[key] then
            addon.db.global.characters[key].professions = nil
            addon:Print("Profession data manually reset")
        end
    end
end

--- Handle currency debug command
---@param addon table WarbandNexus addon instance
function CommandService:HandleCurrencyDebug(addon)
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    addon:Print("=== Currency Debug ===")
    if addon.db.global.characters and addon.db.global.characters[key] then
        local char = addon.db.global.characters[key]
        if char.currencies then
            local count = 0
            local etherealCurrencies = {}
            
            for currencyID, currency in pairs(char.currencies) do
                count = count + 1
                
                -- Look for Ethereal currencies
                if currency.name and currency.name:match("Ethereal") then
                    table.insert(etherealCurrencies, string.format("  [%d] %s: %d/%d (expansion: %s)", 
                        currencyID, currency.name, 
                        currency.quantity or 0, currency.maxQuantity or 0,
                        currency.expansion or "Unknown"))
                end
            end
            
            if #etherealCurrencies > 0 then
                addon:Print("|cff00ff00Ethereal Currencies Found:|r")
                for _, info in ipairs(etherealCurrencies) do
                    addon:Print(info)
                end
            else
                addon:Print("|cffffcc00No Ethereal currencies found!|r")
            end
            
            addon:Print(string.format("Total currencies collected: %d", count))
        else
            addon:Print("|cffff0000No currency data found!|r")
            addon:Print("Running UpdateCurrencyData()...")
            if addon.UpdateCurrencyData then
                addon:UpdateCurrencyData()
                addon:Print("|cff00ff00Currency data collected! Check again with /wn curr|r")
            end
        end
    else
        addon:Print("|cffff0000Character not found in database!|r")
    end
end

--- Handle test loot command
---@param addon table WarbandNexus addon instance
---@param input string Full command input
function CommandService:HandleTestLoot(addon, input)
    local typeArg, idArg = input:match("^testloot%s+(%w+)%s*(%d*)") -- Extract type and optional id
    if addon.TestLootNotification then
        addon:TestLootNotification(typeArg, idArg ~= "" and tonumber(idArg) or nil)
    else
        addon:Print("|cffff0000Loot notification module not loaded!|r")
        addon:Print("|cffff6600Attempting to initialize...|r")
        if addon.InitializeLootNotifications then
            addon:InitializeLootNotifications()
            addon:Print("|cff00ff00Manual initialization complete. Try /wn testloot again.|r")
        else
            addon:Print("|cffff0000InitializeLootNotifications function not found!|r")
        end
    end
end

--- Handle test events command
---@param addon table WarbandNexus addon instance
---@param input string Full command input
function CommandService:HandleTestEvents(addon, input)
    local typeArg, idArg = input:match("^testevents%s+(%w+)%s*(%d*)") -- Extract type and optional id
    if addon.TestNotificationEvents then
        addon:TestNotificationEvents(typeArg, idArg ~= "" and tonumber(idArg) or nil)
    else
        addon:Print("|cffff0000TestNotificationEvents function not found!|r")
    end
end

--- Handle errors command
---@param addon table WarbandNexus addon instance
---@param input string Full command input
function CommandService:HandleErrors(addon, input)
    local subCmd = addon:GetArgs(input, 2, 1)
    if subCmd == "full" or subCmd == "all" then
        addon:PrintRecentErrors(20)
    elseif subCmd == "clear" then
        if addon.ClearErrorLog then
            addon:ClearErrorLog()
        end
    elseif subCmd == "stats" then
        if addon.PrintErrorStats then
            addon:PrintErrorStats()
        end
    elseif subCmd == "export" then
        if addon.ExportErrorLog then
            local log = addon:ExportErrorLog()
            addon:Print("Error log exported. Check chat for full log.")
            -- Print full log (only in debug mode for cleanliness)
            if addon.db.profile.debugMode then
                print(log)
            end
        end
    elseif tonumber(subCmd) then
        if addon.ShowErrorDetails then
            addon:ShowErrorDetails(tonumber(subCmd))
        end
    else
        if addon.PrintRecentErrors then
            addon:PrintRecentErrors(5)
        end
    end
end
