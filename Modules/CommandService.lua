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

-- Debug print helper (only shows when debug mode is enabled)
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print(...)
    end
end

--============================================================================
-- MAIN SLASH COMMAND HANDLER
--============================================================================

--- Main slash command router
--- Handles all /wn and /warbandnexus commands
---@param addon table WarbandNexus addon instance
---@param input string Command input from slash command
function CommandService:HandleSlashCommand(addon, input)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleSlashCommand: " .. tostring(input))
    
    local cmd = addon:GetArgs(input, 1)
    if cmd then cmd = cmd:lower() end
    
    -- No command - open addon window
    if not cmd or cmd == "" then
        addon:ShowMainWindow()
        return
    end
    
    -- Help command - show available commands
    if cmd == "help" then
        addon:Print("|cff00ccffWarband Nexus|r - Available commands:")
        addon:Print("  |cff00ccff/wn|r - Open addon window")
        addon:Print("  |cff00ccff/wn plan|r or |cff00ccff/wn plans|r - Toggle Plans Tracker window (floating)")
        addon:Print("  |cff00ccff/wn changelog|r or |cff00ccff/wn whatsnew|r or |cff00ccff/wn whatsnext|r - Show What's New (changelog) popup")
        addon:Print("  |cff00ccff/wn options|r - Open settings")
        addon:Print("  |cff00ccff/wn debug|r - Toggle debug mode")
        addon:Print("  |cff00ccff/wn clearcache|r - Clear collection cache & rescan (achievements, titles, etc.)")
        addon:Print("  |cff00ccff/wn scanachieves|r - Manually trigger achievement scan (bypass cooldown)")
        addon:Print("  |cff00ccff/wn scanquests [tww|df|sl]|r - Scan & debug daily quests")
        addon:Print("  |cff00ccff/wntest overflow|r - Check font overflow")
        addon:Print("  |cff00ccff/wn cleanup|r - Remove inactive characters (90+ days)")
        addon:Print("  |cffff8000/wn cleandb|r - Remove duplicate characters & deprecated storage")
        addon:Print("  |cff00ccff/wn resetrep|r - Reset reputation data (rebuild from API)")
        addon:Print("  |cff00ccff/wn resetcurr|r - Reset currency data (rebuild from API)")
        addon:Print("  |cff888888/wn scanrep|r - Force reputation scan (bypass throttle)")
        addon:Print("  |cff888888/wn scancurr|r - Force currency scan (bypass throttle)")
        addon:Print("  |cff00ccff/wn scanpve|r - Force PvE data collection (Great Vault, M+, Lockouts)")
        addon:Print("  |cff888888/wn checkpve|r - Debug: Check PvE data in DB for all characters")
        addon:Print("  |cff00ccff/wn track|r - Show character tracking popup")
        addon:Print("  |cff00ccff/wn track enable|r - Enable tracking for current character")
        addon:Print("  |cff00ccff/wn track disable|r - Disable tracking for current character")
        addon:Print("  |cff00ccff/wn track status|r - Check current tracking status")
        addon:Print("  |cffff0000/wn wipedb|r - [DANGER] Wipe ALL SavedVariables (requires /reload)")
        addon:Print("  |cff888888/wn testrepgain|r - Test single reputation gain notification")
        addon:Print("  |cff888888/wn testchat|r - Test chat notifications (5 rep + 1 standing + 5 currency)")
        addon:Print("  |cff00ccff/wn faction <id>|r - Debug specific faction (e.g., /wn faction 2640)")
        addon:Print("  |cff00ccff/wn headers|r - Show detailed test factions & hierarchy (Phase 1)")
        addon:Print("  |cff00ccff/wn rescan reputation|r - Force full reputation rescan")
        addon:Print("  |cff00ccff/wn validate reputation|r - Validate reputation data quality")
        addon:Print("  |cff888888/wn testloot [type]|r - Test notifications (mount/pet/toy/etc)")
        addon:Print("  |cff888888/wn testevents [type]|r - Test event system (collectible/plan/vault/quest)")
        addon:Print("  |cff888888/wn testeffect|r - Test visual effects (glow/flash/border)")
        addon:Print("  |cff888888/wn testvault|r - Test weekly vault slot notification")
        addon:Print("  |cff888888/wn testbag|r - Manually scan bags for collectibles (mount/pet/toy)")
        return
    end
    
    -- Public commands (always available)
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        addon:ShowMainWindow()
        return
    elseif cmd == "plans" or cmd == "plan" then
        if addon.TogglePlansTrackerWindow then
            addon:TogglePlansTrackerWindow()
        else
            addon:Print("|cffff6600Plans Tracker not available. Ensure Plans module is loaded.|r")
        end
        return
    elseif cmd == "changelog" or cmd == "changes" or cmd == "whatsnew" or cmd == "whatsnext" then
        -- Show changelog (bypasses "seen" check to show on demand); single source: ns.CHANGELOG
        if addon.ShowUpdateNotification and ns.CHANGELOG then
            local ok, err = pcall(function()
                addon:ShowUpdateNotification({
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "2.0.0",
                    date = ns.CHANGELOG.date or "",
                    changes = ns.CHANGELOG.changes or {"No changelog available"}
                })
            end)
            if not ok then
                addon:Print("|cffff0000[WN] Changelog error:|r " .. tostring(err))
            end
        else
            addon:Print("|cffff8000Changelog not available.|r ShowUpdateNotification=" .. tostring(addon.ShowUpdateNotification ~= nil) .. " CHANGELOG=" .. tostring(ns.CHANGELOG ~= nil))
        end
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
    elseif cmd == "cleandb" or cmd == "fixdb" then
        if addon.ForceCleanupDatabase then
            addon:ForceCleanupDatabase()
        else
            addon:Print("|cffff0000Database cleanup not available|r")
        end
        return
    elseif cmd == "resetrep" then
        CommandService:HandleResetRep(addon)
        return
    elseif cmd == "resetcurr" then
        CommandService:HandleResetCurr(addon)
        return
    elseif cmd == "scanrep" then
        -- Force reputation scan (bypass throttle)
        addon:Print("Forcing reputation scan...")
        if ns.ReputationCache then
            ns.ReputationCache:PerformFullScan(true)  -- bypass throttle
        else
            addon:Print("|cffff0000ERROR:|r ReputationCache not loaded")
        end
        return
    elseif cmd == "scancurr" then
        -- Force currency scan (bypass throttle)
        addon:Print("Forcing currency scan...")
        if ns.CurrencyCache then
            ns.CurrencyCache:PerformFullScan(true)  -- bypass throttle
        else
            addon:Print("|cffff0000ERROR:|r CurrencyCache not loaded")
        end
        return
    elseif cmd == "scanpve" then
        CommandService:HandleScanPvE(addon)
        return
    elseif cmd == "checkpve" then
        CommandService:HandleCheckPvE(addon)
        return
    elseif cmd == "trackchar" or cmd == "track" then
        -- Parse subcommand
        local subCmd = select(2, addon:GetArgs(input, 2))
        if subCmd == "enable" or subCmd == "on" then
            -- Enable tracking directly
            local charKey = ns.Utilities:GetCharacterKey()
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
                addon:Print("|cff00ff00Character tracking ENABLED!|r")
            end
        elseif subCmd == "disable" or subCmd == "off" then
            -- Disable tracking directly
            local charKey = ns.Utilities:GetCharacterKey()
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
                addon:Print("|cffff8800Character tracking DISABLED!|r")
            end
        elseif subCmd == "status" then
            -- Show tracking status
            local charKey = ns.Utilities:GetCharacterKey()
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
            addon:Print("|cff00ccffCharacter:|r " .. charKey)
            if isTracked then
                addon:Print("|cff00ff00Status:|r Tracking ENABLED")
            else
                addon:Print("|cffff8800Status:|r Tracking DISABLED (read-only mode)")
            end
        else
            -- Show tracking popup (default)
            CommandService:HandleTrackChar(addon)
        end
        return
    elseif cmd == "testchar" then
        -- Test character tracking dialog
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "TestCharacter-TestRealm"
        if ns.CharacterService then
            ns.CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
        end
        return
    elseif cmd == "testrepgain" then
        -- Test reputation gain notification (single, Snapshot-Diff payload)
        addon:Print("Testing reputation gain notification...")
        if addon.SendMessage then
            addon:SendMessage("WN_REPUTATION_GAINED", {
                factionID = 2640,
                factionName = "Brann Bronzebeard",
                gainAmount = 525,
                currentRep = 10625,
                maxRep = 21000,
                wasStandingUp = false,
            })
        end
        return
    elseif cmd == "testchat" then
        -- Test chat notifications using REAL DB data (DB-first architecture)
        -- Picks real factions/currencies from current character's DB,
        -- simulates gains (increments DB, fires lean events, ChatMessageService reads from DB)
        addon:Print("|cff00ccff--- Chat Notification Test (Real DB Data) ---|r")
        
        if not addon.SendMessage then
            addon:Print("|cffff0000ERROR:|r SendMessage not available")
            return
        end
        
        -- Collect real factions from DB (current character + account-wide)
        local repDB = addon.db and addon.db.global and addon.db.global.reputationData
        local curDB = addon.db and addon.db.global and addon.db.global.currencyData
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
        
        -- PRIORITY factions: Always test these (Guild, Brann, Blackwater Cartel)
        local priorityIDs = {1168, 2640, 2675}
        local repFactions = {}
        local usedIDs = {}
        
        for _, fid in ipairs(priorityIDs) do
            local dbData = addon:GetFactionByID(fid)
            if dbData then
                table.insert(repFactions, {id = fid, name = dbData.name or ("Faction " .. fid)})
                usedIDs[fid] = true
            end
        end
        
        -- Fill remaining slots (up to 5) from DB
        if repDB then
            for factionID, data in pairs((repDB.characters or {})[charKey] or {}) do
                if not usedIDs[factionID] and data.type ~= "header" and (data.maxValue or 0) > 1 and #repFactions < 5 then
                    table.insert(repFactions, {id = factionID, name = data.name or "?"})
                    usedIDs[factionID] = true
                end
            end
            for factionID, data in pairs(repDB.accountWide or {}) do
                if not usedIDs[factionID] and data.type ~= "header" and (data.maxValue or 0) > 1 and #repFactions < 5 then
                    table.insert(repFactions, {id = factionID, name = data.name or "?"})
                    usedIDs[factionID] = true
                end
            end
        end
        
        -- Gather up to 5 currencies with quantity > 0
        local currencies = {}
        if curDB and curDB.currencies then
            for currencyID, data in pairs(curDB.currencies[charKey] or {}) do
                if (data.quantity or 0) > 0 and #currencies < 5 then
                    table.insert(currencies, {id = currencyID, name = data.name or "?"})
                end
            end
        end
        
        if #repFactions == 0 and #currencies == 0 then
            addon:Print("|cffff0000No reputation or currency data in DB for current character.|r")
            addon:Print("|cff888888Try /wn rescan reputation first.|r")
            return
        end
        
        local delay = 0
        local INTERVAL = 0.3
        local totalEvents = 0
        
        -- Simulate reputation gains using Snapshot-Diff payload format
        -- Read live API data for each faction (same source as real Snapshot-Diff)
        for i, faction in ipairs(repFactions) do
            C_Timer.After(delay, function()
                local fakeGain = math.random(50, 500)
                
                -- Read live API data (same as PerformSnapshotDiff does)
                local currentRep, maxRep = 0, 0
                local factionName = faction.name
                if C_Reputation and C_Reputation.GetFactionDataByID then
                    local apiData = C_Reputation.GetFactionDataByID(faction.id)
                    if apiData then
                        factionName = apiData.name or factionName
                        local barMin = apiData.currentReactionThreshold or 0
                        local barMax = apiData.nextReactionThreshold or 0
                        currentRep = (apiData.currentStanding or 0) - barMin
                        maxRep = barMax - barMin
                    end
                end
                
                -- Fire event with full display data (matches Snapshot-Diff payload)
                addon:SendMessage("WN_REPUTATION_GAINED", {
                    factionID = faction.id,
                    factionName = factionName,
                    gainAmount = fakeGain,
                    currentRep = currentRep,
                    maxRep = maxRep,
                    wasStandingUp = false,
                })
                
                addon:Print(string.format("|cff888888[SIM]|r Rep: %s (ID:%d) +%d → %d/%d",
                    factionName, faction.id, fakeGain, currentRep, maxRep))
            end)
            delay = delay + INTERVAL
            totalEvents = totalEvents + 1
        end
        
        -- Simulate 1 standing change for first faction
        if #repFactions > 0 then
            C_Timer.After(delay, function()
                addon:SendMessage("WN_REPUTATION_GAINED", {
                    factionID = repFactions[1].id,
                    factionName = repFactions[1].name,
                    gainAmount = 0,
                    currentRep = 0,
                    maxRep = 0,
                    wasStandingUp = true,
                    standingName = "Honored",
                    standingColor = {r = 0.0, g = 0.6, b = 0.1},
                })
                addon:Print(string.format("|cff888888[SIM]|r Standing change: %s", repFactions[1].name))
            end)
            delay = delay + INTERVAL
            totalEvents = totalEvents + 1
        end
        
        -- Simulate currency gains (read from DB, increment, fire lean event)
        for i, currency in ipairs(currencies) do
            C_Timer.After(delay, function()
                local dbData = addon:GetCurrencyData(currency.id)
                if dbData then
                    local fakeGain = math.random(5, 100)
                    local oldQty = dbData.quantity or 0
                    
                    -- Write to DB
                    dbData.quantity = oldQty + fakeGain
                    
                    -- Fire lean event
                    addon:SendMessage("WN_CURRENCY_GAINED", {
                        currencyID = currency.id,
                        gainAmount = fakeGain,
                    })
                    
                    addon:Print(string.format("|cff888888[SIM]|r Cur: %s (ID:%d) +%d → %d",
                        currency.name, currency.id, fakeGain, oldQty + fakeGain))
                end
            end)
            delay = delay + INTERVAL
            totalEvents = totalEvents + 1
        end
        
        addon:Print(string.format("|cff00ff00Firing %d real events over %.1fs (Rep: %d, Cur: %d)...|r",
            totalEvents, delay, #repFactions + (#repFactions > 0 and 1 or 0), #currencies))
        return
    elseif cmd == "wipedb" then
        -- Check for confirmation
        local _, confirmArg = addon:GetArgs(input, 2)
        CommandService:HandleWipeDB(addon, confirmArg)
        return
    elseif cmd == "faction" then
        -- Debug specific faction: /wn faction 2640
        local _, factionIDStr = addon:GetArgs(input, 2)
        local factionID = tonumber(factionIDStr)
        CommandService:HandleDebugFaction(addon, factionID)
        return
    elseif cmd == "testparagon" then
        -- Quick test for paragon factions visible in UI
        CommandService:HandleTestParagon(addon)
        return
    elseif cmd == "checkcache" then
        -- Debug: Show which characters have cached reputation data
        print("|cff00ff00[Cache Debug]|r Character reputation data:")
        local allReps = addon:GetAllReputations()
        local charData = {}
        
        for _, rep in ipairs(allReps) do
            local charKey = rep._characterKey or "Unknown"
            if not charData[charKey] then
                charData[charKey] = {count = 0, class = rep._characterClass or "?"}
            end
            charData[charKey].count = charData[charKey].count + 1
        end
        
        for charKey, data in pairs(charData) do
            print(string.format("  %s (%s): %d reputations", charKey, data.class, data.count))
        end
        
    elseif cmd == "checkorder" then
        -- Check TWW faction order vs Blizzard API
        CommandService:HandleCheckOrder(addon)
        return
    elseif cmd == "headers" then
        -- Debug headers and test factions (detailed): /wn headers
        CommandService:HandleDebugHeaders(addon)
        return
    elseif cmd == "rescan" then
        -- Force rescan: /wn rescan reputation
        local subCmd = select(2, addon:GetArgs(input, 2))
        if subCmd == "reputation" or subCmd == "rep" then
            CommandService:HandleRescanReputation(addon)
        else
            addon:Print("|cffff0000Usage:|r /wn rescan reputation")
        end
        return
    elseif cmd == "validate" then
        -- Validate reputation data: /wn validate reputation
        local subCmd = select(2, addon:GetArgs(input, 2))
        if subCmd == "reputation" or subCmd == "rep" then
            CommandService:HandleValidateReputation(addon)
        else
            addon:Print("|cffff0000Usage:|r /wn validate reputation")
        end
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
    elseif cmd == "testbag" or cmd == "scanbag" then
        -- Test bag scan and collectible detection
        addon:Print("|cffffcc00Manually triggering bag scan...|r")
        if addon.ScanCharacterBags then
            addon:ScanCharacterBags()
            addon:Print("|cff00ff00Bag scan complete! Check for collectible notifications.|r")
        else
            addon:Print("|cffff0000ERROR: ScanCharacterBags not found!|r")
        end
        return
    elseif cmd == "scanquests" or cmd:match("^scanquests%s") then
        CommandService:HandleScanQuests(addon, cmd)
        return
    elseif cmd == "illusions" or cmd == "testillusions" then
        CommandService:HandleTestIllusions(addon, input)
        return
    elseif cmd == "debugpet" or cmd:match("^debugpet%s") then
        CommandService:HandleDebugPet(addon, input)
        return
    elseif cmd == "testloot" then
        CommandService:HandleTestLoot(addon, input)
        return
    elseif cmd == "testevents" then
        CommandService:HandleTestEvents(addon, input)
        return
    elseif cmd == "testeffect" then
        if addon.TestNotificationEffects then
            addon:TestNotificationEffects()
        else
            addon:Print("|cffff0000TestNotificationEffects not available.|r")
        end
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
---Debug specific faction (v2.0.0 - Scanner)
---@param addon table WarbandNexus addon instance
---@param factionID number Faction ID to inspect
function CommandService:HandleDebugFaction(addon, factionID)
    if not factionID or factionID == 0 then
        addon:Print("|cffff0000Usage:|r /wn faction <factionID>")
        addon:Print("|cff888888Example:|r /wn faction 2640 (Brann Bronzebeard)")
        return
    end
    
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    addon:Print("|cff00ccff    Faction Debug: " .. factionID .. "    |r")
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    
    -- Step 1: RAW API DATA from Scanner
    if _G.WNScannerDebug and ns.ReputationScanner then
        local rawData = ns.ReputationScanner:FetchFaction(factionID)
        if rawData then
            addon:Print("|cffffcc00[1] RAW API DATA (from Scanner)|r")
            addon:Print("  Name: " .. (rawData.name or "Unknown"))
            addon:Print("  Type Detection:")
            addon:Print("    isMajorFaction: " .. tostring(rawData.isMajorFaction or false))
            addon:Print("    isAccountWide: " .. tostring(rawData.isAccountWide or false))
            addon:Print("    reaction: " .. tostring(rawData.reaction))
            
            if rawData.paragon then
                addon:Print("  |cffff00ff[PARAGON RAW]|r")
                addon:Print("    currentValue: " .. tostring(rawData.paragon.currentValue))
                addon:Print("    threshold: " .. tostring(rawData.paragon.threshold))
                addon:Print("    hasRewardPending: " .. tostring(rawData.paragon.hasRewardPending))
            else
                addon:Print("  Paragon: None")
            end
        else
            addon:Print("|cffff0000  Faction not found in API|r")
            return
        end
    end
    
    -- Step 1b: FRIENDSHIP API DATA (separate from standard rep API)
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
        addon:Print("")
        addon:Print("|cffffcc00[1b] FRIENDSHIP API (C_GossipInfo)|r")
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            addon:Print("  |cff00ff00IS FRIENDSHIP FACTION|r")
            addon:Print("  friendshipFactionID: " .. tostring(friendInfo.friendshipFactionID))
            addon:Print("  standing: " .. tostring(friendInfo.standing))
            addon:Print("  maxRep: " .. tostring(friendInfo.maxRep))
            addon:Print("  name: " .. tostring(friendInfo.name))
            addon:Print("  text (rank): " .. tostring(friendInfo.text))
            addon:Print("  texture: " .. tostring(friendInfo.texture))
            addon:Print("  reaction: " .. tostring(friendInfo.reaction))
            addon:Print("  reactionThreshold: " .. tostring(friendInfo.reactionThreshold))
            addon:Print("  nextThreshold: " .. tostring(friendInfo.nextThreshold))
            if C_GossipInfo.GetFriendshipReputationRanks then
                local ranks = C_GossipInfo.GetFriendshipReputationRanks(factionID)
                if ranks then
                    addon:Print("  currentLevel: " .. tostring(ranks.currentLevel))
                    addon:Print("  maxLevel: " .. tostring(ranks.maxLevel))
                end
            end
        else
            addon:Print("  Not a friendship faction")
        end
    end
    
    -- Step 1c: SNAPSHOT DATA (live diff tracking)
    if ns.ReputationCache and ns.ReputationCache._snapshot then
        local snap = ns.ReputationCache._snapshot[factionID]
        addon:Print("")
        addon:Print("|cffffcc00[1c] SNAPSHOT STATE (live diff)|r")
        if snap then
            addon:Print("  barValue: " .. tostring(snap.barValue))
            addon:Print("  reaction: " .. tostring(snap.reaction))
            addon:Print("  isFriendship: " .. tostring(snap.isFriendship or false))
            if snap.isFriendship then
                addon:Print("  friendshipStanding: " .. tostring(snap.friendshipStanding))
                addon:Print("  friendshipMaxRep: " .. tostring(snap.friendshipMaxRep))
                addon:Print("  friendshipReactionThreshold: " .. tostring(snap.friendshipReactionThreshold))
                addon:Print("  friendshipNextThreshold: " .. tostring(snap.friendshipNextThreshold))
                addon:Print("  friendshipName (rank): " .. tostring(snap.friendshipName))
            end
            if snap.paragonValue then
                addon:Print("  paragonValue: " .. tostring(snap.paragonValue))
                addon:Print("  paragonThreshold: " .. tostring(snap.paragonThreshold))
            end
        else
            addon:Print("  |cffff8800Not in snapshot (faction not tracked yet)|r")
        end
    end
    
    -- Step 2: PROCESSED DATA from Processor
    if ns.ReputationProcessor and ns.ReputationScanner then
        local rawData = ns.ReputationScanner:FetchFaction(factionID)
        if rawData then
            local processed = ns.ReputationProcessor:Process(rawData)
            if processed then
                addon:Print("")
                addon:Print("|cffffcc00[2] PROCESSED DATA (from Processor)|r")
                addon:Print("  Type: " .. tostring(processed.type))
                addon:Print("  Standing: " .. tostring(processed.standingName))
                addon:Print("  Progress: " .. tostring(processed.currentValue) .. "/" .. tostring(processed.maxValue))
                addon:Print("  |cffff00ff[PARAGON FLAG]|r: " .. tostring(processed.hasParagon or false))
                
                if processed.hasParagon and processed.paragon then
                    addon:Print("  |cffff00ff[PARAGON PROCESSED]|r")
                    addon:Print("    current: " .. tostring(processed.paragon.current))
                    addon:Print("    max: " .. tostring(processed.paragon.max))
                    addon:Print("    cycles: " .. tostring(processed.paragon.completedCycles or 0))
                    addon:Print("    hasRewardPending: " .. tostring(processed.paragon.hasRewardPending))
                end
            end
        end
    end
    
    -- Step 3: DB STORAGE (what ResolveFactionData returns — same as chat/UI)
    if addon.GetFactionByID then
        local dbData = addon:GetFactionByID(factionID)
        addon:Print("")
        addon:Print("|cffffcc00[3] DB STORAGE (ResolveFactionData)|r")
        if dbData then
            addon:Print("  name: " .. tostring(dbData.name or "nil"))
            addon:Print("  type: " .. tostring(dbData.type or "nil"))
            addon:Print("  isHeader: " .. tostring(dbData.isHeader))
            addon:Print("  isHeaderWithRep: " .. tostring(dbData.isHeaderWithRep))
            addon:Print("  isAccountWide: " .. tostring(dbData.isAccountWide))
            addon:Print("  standingName: " .. tostring(dbData.standingName or "nil"))
            addon:Print("  currentValue: " .. tostring(dbData.currentValue or "nil"))
            addon:Print("  maxValue: " .. tostring(dbData.maxValue or "nil"))
            addon:Print("  hasParagon: " .. tostring(dbData.hasParagon or false))
            if dbData.classic then
                addon:Print("  |cff888888classic.current: " .. tostring(dbData.classic.current) .. ", classic.max: " .. tostring(dbData.classic.max) .. "|r")
            end
            if dbData.renown then
                addon:Print("  |cff888888renown.level: " .. tostring(dbData.renown.level) .. ", renown.current: " .. tostring(dbData.renown.current) .. ", renown.max: " .. tostring(dbData.renown.max) .. "|r")
            end
        else
            addon:Print("  |cffff0000NOT FOUND in DB|r")
        end
    end
    
    -- Step 4: RAW DB entries (both character and accountWide)
    if addon.db and addon.db.global and addon.db.global.reputationData then
        local repDB = addon.db.global.reputationData
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
        addon:Print("")
        addon:Print("|cffffcc00[4] RAW DB ENTRIES|r")
        local charEntry = (repDB.characters[charKey] or {})[factionID]
        local acctEntry = repDB.accountWide[factionID]
        if charEntry then
            addon:Print("  |cff00ff00characters[" .. charKey .. "]:|r type=" .. tostring(charEntry.type) .. " cv=" .. tostring(charEntry.currentValue) .. " mv=" .. tostring(charEntry.maxValue) .. " isHeader=" .. tostring(charEntry.isHeader) .. " isHWR=" .. tostring(charEntry.isHeaderWithRep))
        else
            addon:Print("  |cffff8800characters[" .. charKey .. "]:|r nil")
        end
        if acctEntry then
            addon:Print("  |cff00ff00accountWide:|r type=" .. tostring(acctEntry.type) .. " cv=" .. tostring(acctEntry.currentValue) .. " mv=" .. tostring(acctEntry.maxValue) .. " isHeader=" .. tostring(acctEntry.isHeader) .. " isHWR=" .. tostring(acctEntry.isHeaderWithRep))
        else
            addon:Print("  |cffff8800accountWide:|r nil")
        end
    end
    
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
end

---Debug headers and test factions with FULL details (Phase 2 Testing)
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugHeaders(addon)
    if not C_Reputation or not ns.ReputationScanner or not ns.ReputationProcessor then
        addon:Print("|cffff0000Error:|r API, Scanner, or Processor not available")
        return
    end
    
    addon:Print("|cff00ccff========================================")
    addon:Print("=== Reputation Data Debug (RAW + Processed) ===")
    addon:Print("========================================|r")
    
    -- Test factions: Mix of types for debugging
    local testIDs = {
        2653,  -- The Cartels of Undermine (HeaderWithRep parent)
        2685,  -- Gallagio (child of Cartels)
        2677,  -- Steamwheedle Cartel (child of Cartels)
        2601,  -- The Weaver (Friendship Paragon)
    }
    
    for _, factionID in ipairs(testIDs) do
        -- Fetch raw data
        local rawData = ns.ReputationScanner:FetchFaction(factionID)
        
        if not rawData then
            addon:Print(string.format("|cffff0000[%d] NOT FOUND|r", factionID))
        else
            -- Print RAW data first
            addon:Print(string.format("\n|cff00ccff[%d] RAW API DATA|r - %s", factionID, rawData.name or "Unknown"))
            addon:Print(string.format("  reaction: %s | currentStanding: %s", 
                tostring(rawData.reaction), tostring(rawData.currentStanding)))
            addon:Print(string.format("  currentThreshold: %s | nextThreshold: %s", 
                tostring(rawData.currentReactionThreshold), tostring(rawData.nextReactionThreshold)))
            addon:Print(string.format("  isHeader: %s | isHeaderWithRep: %s | isChild: %s", 
                tostring(rawData.isHeader), tostring(rawData.isHeaderWithRep), tostring(rawData.isChild)))
            addon:Print(string.format("  parentFactionID: %s", tostring(rawData.parentFactionID or "nil")))
            
            -- Paragon info (universal for all types)
            if rawData.paragon then
                addon:Print("|cffff00ff  [PARAGON DATA]|r")
                addon:Print(string.format("    currentValue: %s", tostring(rawData.paragon.currentValue)))
                addon:Print(string.format("    threshold: %s", tostring(rawData.paragon.threshold)))
            end
            
            -- Friendship info
            if rawData.friendship then
                addon:Print("|cffffcc00  [FRIENDSHIP DATA]|r")
                addon:Print(string.format("    standing: %s", tostring(rawData.friendship.standing)))
                addon:Print(string.format("    maxRep: %s", tostring(rawData.friendship.maxRep)))
                addon:Print(string.format("    reactionThreshold: %s", tostring(rawData.friendship.reactionThreshold)))
                addon:Print(string.format("    nextThreshold: %s", tostring(rawData.friendship.nextThreshold)))
                addon:Print(string.format("    reaction: %s", tostring(rawData.friendship.reaction)))
            end
            if rawData.friendshipRanks then
                addon:Print(string.format("    currentLevel: %s", tostring(rawData.friendshipRanks.currentLevel)))
                addon:Print(string.format("    maxLevel: %s", tostring(rawData.friendshipRanks.maxLevel)))
            end
            addon:Print(string.format("  friendshipParagon: %s", rawData.friendshipParagon and "YES" or "NO"))
            
            -- Process into normalized format
            local data = ns.ReputationProcessor:Process(rawData)
            
            if not data then
                addon:Print(string.format("|cffff0000[%d] PROCESSING FAILED|r", factionID))
            else
            -- Structure tags
            local structureTag = ""
            if data.isHeader then
                structureTag = "|cffffcc00[HEADER]|r"
            elseif data.isChild then
                structureTag = "|cff888888[CHILD]|r"
            end
            
            -- Type tags
            local typeTag = ""
            if data.renown then
                typeTag = "|cff00ffff[RENOWN]|r"
            elseif data.friendship then
                typeTag = "|cffffcc00[FRIENDSHIP]|r"
            elseif data.paragon then
                typeTag = "|cffff00ff[PARAGON]|r"
            else
                typeTag = "|cffffffff[CLASSIC]|r"
            end
            
            -- Combined header
            local fullTag = structureTag
            if structureTag ~= "" and typeTag ~= "" then
                fullTag = fullTag .. " " .. typeTag
            elseif typeTag ~= "" then
                fullTag = typeTag
            end
            
            addon:Print(string.format("\n|cff00ccff[%d]|r %s %s", factionID, fullTag, data.name or "Unknown"))
            
            -- Type & Standing
            addon:Print(string.format("  Type: |cff00ff00%s|r | Standing: |cff00ff00%s|r (ID: %d)", 
                data.type or "unknown",
                data.standingName or "Unknown",
                data.standingID or 0))
            
            -- Normalized progress (0-based)
            if data.currentValue and data.maxValue then
                local percent = (data.currentValue / data.maxValue) * 100
                addon:Print(string.format("  Progress: |cffff00ff%d/%d|r (%.1f%%)", 
                    data.currentValue, data.maxValue, percent))
            else
                addon:Print(string.format("  Progress: |cffff0000ERROR - currentValue:%s maxValue:%s|r", 
                    tostring(data.currentValue), tostring(data.maxValue)))
            end
            
            -- PARAGON-SPECIFIC INFO (detailed)
            if data.paragon then
                addon:Print(string.format("  |cffff00ff→ Paragon:|r"))
                addon:Print(string.format("    Current in cycle: |cff00ff00%d|r", data.paragon.current or 0))
                addon:Print(string.format("    Threshold per cycle: |cff00ff00%d|r", data.paragon.max or 0))
                addon:Print(string.format("    Completed cycles: |cff00ff00%d|r", data.paragon.completedCycles or 0))
                addon:Print(string.format("    Total value: |cff00ff00%d|r", data.paragon.totalValue or 0))
                if data.paragon.hasRewardPending then
                    addon:Print("    |cffff0000→ REWARD READY!|r")
                end
            end
            
            -- Type-specific info (concise)
            if data.renown then
                addon:Print(string.format("  |cff00ffff→ Renown Level %d|r", data.renown.level or 0))
            end
            
            if data.friendship then
                addon:Print(string.format("  |cffffcc00→ %s (Rank %d/%d)|r", 
                    data.friendship.reactionText or "Unknown",
                    data.friendship.level or 0,
                    data.friendship.maxLevel or 0))
            end
            
            -- Metadata (compact)
            local metadata = {}
            if data.isAccountWide then table.insert(metadata, "|cff00ff00Account-Wide|r") end
            if data.isCollapsed then table.insert(metadata, "|cff888888Collapsed|r") end
            if #metadata > 0 then
                addon:Print("  " .. table.concat(metadata, " | "))
            end
            end -- end if data (normalized)
        end -- end if rawData
    end -- end for
    
    addon:Print("\n|cff00ccff========================================")
    addon:Print("Tip: Use /wn faction <ID> for raw API dump")
    addon:Print("========================================|r")
end

---Force full reputation rescan (v2.0.0)
---@param addon table WarbandNexus addon instance
function CommandService:HandleRescanReputation(addon)
    addon:Print("|cffffcc00Forcing full reputation rescan...|r")
    
    -- Use global rescan function from ReputationCacheService
    if _G.WNRescanReputations then
        _G.WNRescanReputations()
        addon:Print("|cff00ff00Rescan complete! Check debug logs for details.|r")
    else
        addon:Print("|cffff0000Error:|r WNRescanReputations not found - ReputationCacheService not loaded")
    end
end

function CommandService:HandleResetRep(addon)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleResetRep triggered")
    
    addon:Print("|cffff9900═══════════════════════════════════════|r")
    addon:Print("|cffffcc00    Resetting Reputation System    |r")
    addon:Print("|cffff9900═══════════════════════════════════════|r")
    addon:Print(" ")
    addon:Print("|cffffcc00This will:|r")
    addon:Print("  • Clear ONLY current character's reputation data")
    addon:Print("  • Preserve account-wide reputations")
    addon:Print("  • Preserve other characters' data")
    addon:Print("  • Rebuild current character's data from WoW API")
    addon:Print(" ")
    
    -- Get current character name for message
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    addon:Print("|cff888888Resetting for: " .. charKey .. "|r")
    addon:Print(" ")
    
    -- v2.0.0: NEW cache system - ClearReputationCache handles everything
    if addon.ClearReputationCache then
        addon:ClearReputationCache()
        addon:Print("|cff00ff00✓ Character data cleared!|r")
        addon:Print("|cffffcc00→ Rescan will start in 1 second...|r")
        addon:Print("|cffffcc00→ Data will be saved automatically|r")
        addon:Print(" ")
        addon:Print("|cff00ff00TIP:|r Other characters' data is preserved")
        addon:Print("|cff888888Debug: /wn faction <id> to verify specific faction|r")
    else
        addon:Print("|cffff0000Error:|r ClearReputationCache not found")
    end
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleResetRep complete")
end

function CommandService:HandleResetCurr(addon)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleResetCurr triggered")
    
    addon:Print("|cffff9900═══════════════════════════════════════|r")
    addon:Print("|cffffcc00    Resetting Currency System    |r")
    addon:Print("|cffff9900═══════════════════════════════════════|r")
    addon:Print(" ")
    addon:Print("|cffffcc00This will:|r")
    addon:Print("  • Clear ONLY current character's currency data")
    addon:Print("  • Preserve other characters' data")
    addon:Print("  • Rebuild current character's data from WoW API")
    addon:Print(" ")
    
    -- Get current character name for message
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    addon:Print("|cff888888Resetting for: " .. charKey .. "|r")
    addon:Print(" ")
    
    -- Clear currency cache
    if addon.ClearCurrencyCache then
        addon:ClearCurrencyCache()
        addon:Print("|cff00ff00✓ Character data cleared!|r")
        addon:Print("|cffffcc00→ Rescan will start in 1 second...|r")
        addon:Print("|cffffcc00→ Data will be saved automatically|r")
        addon:Print(" ")
        addon:Print("|cff00ff00TIP:|r Other characters' data is preserved")
    else
        addon:Print("|cffff0000Error:|r ClearCurrencyCache not found")
    end
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleResetCurr complete")
end

--- Handle PvE data scan command
---@param addon table WarbandNexus addon instance
function CommandService:HandleScanPvE(addon)
    -- Request fresh data from Blizzard APIs
    if C_MythicPlus then
        C_MythicPlus.RequestMapInfo()
        C_MythicPlus.RequestRewards()
    end
    if C_WeeklyRewards then
        C_WeeklyRewards.OnUIInteract()
    end
    
    -- Wait 1 second for API responses, then collect data
    C_Timer.After(1, function()
        if addon.UpdatePvEData then
            addon:UpdatePvEData()
            addon:Print("|cff00ff00PvE data collected and saved.|r")
        else
            addon:Print("|cffff0000Error:|r PvE system not initialized")
        end
    end)
end

--- Handle PvE data check command (debug)
---@param addon table WarbandNexus addon instance
function CommandService:HandleCheckPvE(addon)
    local dbCache = addon.db and addon.db.global and addon.db.global.pveCache
    
    if not dbCache then
        addon:Print("|cffff0000No PvE cache found|r")
        return
    end
    
    addon:Print("|cff00ff00PvE cache exists (v" .. tostring(dbCache.version) .. ")|r")
    
    -- Check characters
    local characters = addon.db and addon.db.global and addon.db.global.characters or {}
    local charCount = 0
    
    addon:Print("|cffffcc00Checking characters in DB:|r")
    for charKey, charData in pairs(characters) do
        charCount = charCount + 1
        local hasKeystone = dbCache.mythicPlus and dbCache.mythicPlus.keystones and dbCache.mythicPlus.keystones[charKey]
        local hasVault = dbCache.greatVault and dbCache.greatVault.activities and dbCache.greatVault.activities[charKey]
        local hasScore = dbCache.mythicPlus and dbCache.mythicPlus.dungeonScores and dbCache.mythicPlus.dungeonScores[charKey]
        
        addon:Print(string.format("  |cff00ccff%s|r", charKey))
        addon:Print(string.format("    Keystone: %s", hasKeystone and "|cff00ff00YES|r" or "|cff888888NO|r"))
        addon:Print(string.format("    Vault: %s", hasVault and "|cff00ff00YES|r" or "|cff888888NO|r"))
        addon:Print(string.format("    Score: %s", hasScore and "|cff00ff00YES|r" or "|cff888888NO|r"))
    end
    
    if charCount == 0 then
        addon:Print("  |cff888888No characters found|r")
    end
    
    addon:Print(" ")
    addon:Print("|cff00ff00TIP:|r Use /wn scanpve while logged on each character")
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleCheckPvE complete")
end

---Manually trigger character tracking popup
---@param addon table WarbandNexus addon instance
function CommandService:HandleTrackChar(addon)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleTrackChar triggered")
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    addon:Print("|cff00ccff═══════════════════════════════════════|r")
    addon:Print("|cff00ccffManual Character Tracking Trigger|r")
    addon:Print("|cff00ccff═══════════════════════════════════════|r")
    addon:Print(" ")
    addon:Print("|cffffcc00Current Character:|r " .. charKey)
    addon:Print(" ")
    
    -- Show tracking confirmation popup
    if ns.CharacterService then
        ns.CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
        addon:Print("|cff00ff00→ Tracking popup shown!|r")
    else
        addon:Print("|cffff0000Error:|r CharacterService not found")
    end
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleTrackChar complete")
end

---Wipe ALL SavedVariables (destructive, requires /reload)
---@param addon table WarbandNexus addon instance
---@param confirmArg string|nil Confirmation argument
function CommandService:HandleWipeDB(addon, confirmArg)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleWipeDB triggered")
    
    -- Check for confirmation
    if not confirmArg or confirmArg:lower() ~= "confirm" then
        -- Show warning
        addon:Print("|cffff0000═══════════════════════════════════════|r")
        addon:Print("|cffff0000    ⚠️  DATABASE WIPE WARNING  ⚠️    |r")
        addon:Print("|cffff0000═══════════════════════════════════════|r")
        addon:Print(" ")
        addon:Print("|cffffcc00This will PERMANENTLY delete:|r")
        addon:Print("  • ALL character data (all realms)")
        addon:Print("  • ALL currency tracking")
        addon:Print("  • ALL reputation tracking")
        addon:Print("  • ALL item/storage data")
        addon:Print("  • ALL settings and preferences")
        addon:Print("  • ALL collected transmog/mount/pet data")
        addon:Print(" ")
        addon:Print("|cffff0000This action CANNOT be undone!|r")
        addon:Print(" ")
        addon:Print("|cffffcc00Type:|r  |cff00ff00/wn wipedb confirm|r  |cffffcc00to proceed|r")
        return
    end
    
    -- Confirmed - perform wipe
    addon:Print("|cffff0000═══════════════════════════════════════|r")
    addon:Print("|cffff0000    🔥 WIPING DATABASE 🔥    |r")
    addon:Print("|cffff0000═══════════════════════════════════════|r")
    addon:Print(" ")
    
    if addon.db then
        -- Wipe global data (all characters)
        if addon.db.global then
            wipe(addon.db.global)
            addon:Print("|cff00ff00✓|r Global data wiped")
        end
        
        -- Wipe profile data (current character settings)
        if addon.db.profile then
            wipe(addon.db.profile)
            addon:Print("|cff00ff00✓|r Profile data wiped")
        end
        
        -- CRITICAL: Wipe char data for ALL characters (AceDB stores per-character)
        -- Must use raw SavedVariables table because AceDB structure is complex
        if _G.WarbandNexusDB and _G.WarbandNexusDB.char then
            local charCount = 0
            
            -- Count total characters
            for charKey, _ in pairs(_G.WarbandNexusDB.char) do
                charCount = charCount + 1
            end
            
            -- WIPE ALL (including current character - will be recreated on next login)
            wipe(_G.WarbandNexusDB.char)
            
            addon:Print(string.format("|cff00ff00✓|r Character data wiped (%d characters removed)", charCount))
        end
        
        -- CRITICAL: Wipe AceDB profileKeys (stores which profile each character uses)
        -- This is in the raw SavedVariables table, not in db.global/profile/char
        if _G.WarbandNexusDB and _G.WarbandNexusDB.profileKeys then
            local keyCount = 0
            
            -- Count total keys
            for charKey, _ in pairs(_G.WarbandNexusDB.profileKeys) do
                keyCount = keyCount + 1
            end
            
            -- WIPE ALL
            wipe(_G.WarbandNexusDB.profileKeys)
            
            addon:Print(string.format("|cff00ff00✓|r Profile keys wiped (%d keys removed)", keyCount))
        end
        
        -- CRITICAL: Wipe AceDB profiles list (all saved profiles)
        if _G.WarbandNexusDB and _G.WarbandNexusDB.profiles then
            wipe(_G.WarbandNexusDB.profiles)
            addon:Print("|cff00ff00✓|r All profiles wiped")
        end
        
        addon:Print(" ")
        addon:Print("|cffffcc00All SavedVariables cleared from memory!|r")
        addon:Print(" ")
        addon:Print("|cffff8800IMPORTANT:|r Changes will be written to disk when you:")
        addon:Print("  • Type |cff00ff00/logout|r or |cff00ff00/reload|r")
        addon:Print("  • Exit the game")
        addon:Print(" ")
        addon:Print("|cffffcc00Recommended:|r Type |cff00ff00/reload|r now to apply changes|r")
    else
        addon:Print("|cffff0000Error:|r Database not initialized")
    end
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleWipeDB complete")
end

---Test paragon factions currently in cache
---@param addon table WarbandNexus addon instance
function CommandService:HandleTestParagon(addon)
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    addon:Print("|cff00ccff   Quick Paragon Test (Cache)    |r")
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    
    -- Get all cached reputations
    local allReps = addon:GetAllReputations()
    if not allReps or #allReps == 0 then
        addon:Print("|cffff0000No reputation data found in cache|r")
        addon:Print("|cffffcc00Run /wn resetrep first|r")
        return
    end
    
    -- Find paragon factions
    local paragonCount = 0
    for _, rep in ipairs(allReps) do
        if rep.hasParagon then
            paragonCount = paragonCount + 1
            local paragonData = rep.paragon
            
            if paragonData then
                addon:Print(string.format("|cffff00ff[%d] %s|r", rep.factionID, rep.name))
                addon:Print(string.format("  hasParagon: |cff00ff00true|r"))
                addon:Print(string.format("  type: %s", rep.type or "unknown"))
                addon:Print(string.format("  progress: %d/%d", paragonData.current or 0, paragonData.max or 10000))
                addon:Print(string.format("  cycles: %d", paragonData.completedCycles or 0))
                addon:Print(string.format("  reward: %s", tostring(paragonData.hasRewardPending or false)))
            else
                addon:Print(string.format("|cffffcc00[%d] %s|r", rep.factionID, rep.name))
                addon:Print(string.format("  hasParagon: |cff00ff00true|r"))
                addon:Print(string.format("  |cffff0000BUT paragon data is NIL!|r"))
            end
        end
    end
    
    addon:Print("|cff00ccff━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    addon:Print(string.format("|cff00ff00Found %d paragon factions in cache|r", paragonCount))
    
    if paragonCount == 0 then
        addon:Print("|cffffcc00No paragon factions found|r")
        addon:Print("|cffffcc00This is normal if you don't have any factions at Exalted with paragon overflow|r")
    end
end

--[[
    Check TWW faction order vs Blizzard API
    Debug command to verify _scanIndex values
]]
function CommandService:HandleCheckOrder(addon)
    addon:Print("|cffff00ff=== Faction Order Check ===|r")
    
    -- Get cache headers
    local headers = addon:GetReputationHeaders() or {}
    
    -- Find TWW header
    local twwHeader = nil
    for _, hdr in ipairs(headers) do
        if hdr.name == "The War Within" then
            twwHeader = hdr
            break
        end
    end
    
    if not twwHeader then
        addon:Print("|cffff0000TWW header not found in cache!|r")
        return
    end
    
    addon:Print(string.format("|cff00ff00Cache Order (TWW - %d factions):|r", #twwHeader.factions))
    
    for i, factionID in ipairs(twwHeader.factions) do
        local f = addon:GetReputationData(factionID)
        if f then
            local name = f.name or "Unknown"
            local scanIndex = f._scanIndex or 9999
            addon:Print(string.format("%d. %s (index: %d)", i, name, scanIndex))
        else
            addon:Print(string.format("%d. factionID %d (NOT FOUND)", i, factionID))
        end
    end
    
    addon:Print(" ")
    
    -- NEW: Check what UI sees after AggregateReputations
    addon:Print("|cffff00ffUI Order (after AggregateReputations):|r")
    if addon.Reputation and addon.Reputation.AggregateReputations then
        local aggregated = addon.Reputation:AggregateReputations()
        if aggregated and aggregated.accountWide then
            for _, headerData in ipairs(aggregated.accountWide) do
                if headerData.name == "The War Within" then
                    addon:Print(string.format("|cffff00ff%d factions in UI:|r", #headerData.factions))
                    for i, faction in ipairs(headerData.factions) do
                        local name = (faction.data and faction.data.name) or "Unknown"
                        local scanIndex = (faction.data and faction.data._scanIndex) or 9999
                        addon:Print(string.format("%d. %s (index: %d)", i, name, scanIndex))
                    end
                    break
                end
            end
        else
            addon:Print("|cffff0000aggregated.accountWide is nil!|r")
        end
    else
        addon:Print("|cffff0000Reputation:AggregateReputations not available!|r")
    end
    
    addon:Print(" ")
    addon:Print("|cff00ff00Blizzard API Order (first 9):|r")
    
    -- Expand all headers to see all factions
    if C_Reputation.ExpandAllFactionHeaders then
        C_Reputation.ExpandAllFactionHeaders()
    end
    
    for i = 1, 9 do
        local f = C_Reputation.GetFactionDataByIndex(i)
        if f then
            addon:Print(string.format("%d. %s (ID: %d)", i, f.name, f.factionID))
        end
    end
    
    addon:Print(" ")
    addon:Print("|cffffcc00Analysis:|r")
    addon:Print("|cffffcc00If Cache Order is correct but UI Order is wrong:|r")
    addon:Print("|cffffcc00→ Problem is in AggregateReputations() (line ~470-520)|r")
    addon:Print("|cffffcc00If scanIndex values are wrong/random:|r")
    addon:Print("|cffffcc00→ Problem is in Scanner or Processor|r")
end

function CommandService:HandleValidateReputation(addon)
    addon:Print("|cffffcc00Validating reputation data quality...|r")
    
    -- Get all cached reputations
    local allReps = addon:GetAllReputations()
    if not allReps or #allReps == 0 then
        addon:Print("|cffff0000No reputation data found in cache|r")
        return
    end
    
    -- Get standard thresholds from namespace
    local THRESHOLDS = ns.Constants and ns.Constants.CLASSIC_REP_THRESHOLDS or {}
    
    -- Track issues
    local issues = {
        classic_threshold = {},
        friendship_outlier = {},
        renown_outlier = {},
    }
    
    -- Scan all reputations
    for _, rep in ipairs(allReps) do
        -- Check Classic reputation thresholds
        if rep.type == "classic" and rep.standingID and rep.standingID < 8 then
            local standard = THRESHOLDS[rep.standingID]
            if standard and standard.range > 0 then
                local expectedMax = standard.range
                local actualMax = rep.maxValue or 0
                
                -- Check if threshold is significantly off (>30% deviation)
                if actualMax > expectedMax * 1.3 or actualMax < expectedMax * 0.7 then
                    table.insert(issues.classic_threshold, {
                        name = rep.name,
                        standing = rep.standingName or "Unknown",
                        actual = actualMax,
                        expected = expectedMax,
                    })
                end
            end
        end
        
        -- Check Friendship thresholds for outliers (ONLY for standard systems)
        -- NOTE: Cumulative friendship systems (Brann: 100 levels) can have 200k+ thresholds
        if rep.type == "friendship" and rep.maxValue and rep.friendship then
            local maxLevel = rep.friendship.maxLevel or 0
            -- Only flag outliers for standard friendship systems (≤10 levels)
            if rep.maxValue > 100000 and maxLevel <= 10 then
                table.insert(issues.friendship_outlier, {
                    name = rep.name,
                    threshold = rep.maxValue,
                    maxLevel = maxLevel,
                })
            end
        end
        
        -- Check Renown for outliers
        if rep.type == "renown" and rep.renown then
            if rep.maxValue and rep.maxValue > 25000 and rep.maxValue ~= 999999 then
                table.insert(issues.renown_outlier, {
                    name = rep.name,
                    level = rep.renown.level or 0,
                    threshold = rep.maxValue,
                })
            end
        end
    end
    
    -- Print report
    local totalIssues = #issues.classic_threshold + #issues.friendship_outlier + #issues.renown_outlier
    
    addon:Print(string.format("|cff00ff00Scanned %d factions|r", #allReps))
    addon:Print(string.format("|cffffcc00Found %d potential issues:|r", totalIssues))
    
    if #issues.classic_threshold > 0 then
        addon:Print("|cffff6b6bClassic Reputation Threshold Issues:|r")
        for _, issue in ipairs(issues.classic_threshold) do
            addon:Print(string.format("  • %s (%s): actual=%d, expected=%d",
                issue.name, issue.standing, issue.actual, issue.expected))
        end
    end
    
    if #issues.friendship_outlier > 0 then
        addon:Print("|cffff6b6bFriendship Threshold Outliers:|r")
        for _, issue in ipairs(issues.friendship_outlier) do
            addon:Print(string.format("  • %s: threshold=%d (unusually high)",
                issue.name, issue.threshold))
        end
    end
    
    if #issues.renown_outlier > 0 then
        addon:Print("|cffff6b6bRenown Threshold Outliers:|r")
        for _, issue in ipairs(issues.renown_outlier) do
            addon:Print(string.format("  • %s (Level %d): threshold=%d (unusually high)",
                issue.name, issue.level, issue.threshold))
        end
    end
    
    if totalIssues == 0 then
        addon:Print("|cff00ff00✓ All reputation data looks good!|r")
    else
        addon:Print("|cffffcc00Note: Some issues may be expected for special factions|r")
        addon:Print("|cffffcc00Use /wn resetrep to rebuild cache from API|r")
    end
end

--- Handle cache clear command
---@param addon table WarbandNexus addon instance
function CommandService:HandleClearCache(addon)
    DebugPrint("|cff9370DB[WN CommandService]|r HandleClearCache triggered")
    
    addon:Print("|cffffcc00Clearing collection cache...|r")
    
    -- Clear DB cache
    if addon.db and addon.db.global and addon.db.global.collectionCache then
        addon.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {} },
            version = "3.0.1",
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
    
    -- EVENT-DRIVEN: Request UI refresh via event instead of direct call
    C_Timer.After(2.0, function()
        addon:SendMessage("WN_DATA_UPDATED", {
            source = "collection",
            action = "cache_cleared"
        })
        addon:Print("|cff00ff00Cache refresh complete! UI updated.|r")
    end)
    
    addon:Print("|cff9370DB[WN]|r Background scans started. Check back in ~10 seconds!")
    
    DebugPrint("|cff00ff00[WN CommandService]|r HandleClearCache complete")
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
        -- Phase 3: CacheManager removed - Show cache service stats instead
        addon:Print("|cff9370DB[Cache Services Status]|r")
        addon:Print("Reputation Cache: " .. (addon.db.global.reputationCache and "Loaded" or "Empty"))
        addon:Print("Currency Cache: " .. (addon.db.global.currencyCache and "Loaded" or "Empty"))
        addon:Print("Collection Cache: " .. (addon.db.global.collectionCache and "Loaded" or "Empty"))
        addon:Print("PvE Cache: " .. (addon.db.global.pveCache and "Loaded" or "Empty"))
        addon:Print("Items Cache: Per-character, use /wn chars to see data")
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
    if not C_CurrencyInfo then
        addon:Print("|cffff0000C_CurrencyInfo API not available|r")
        return
    end
    
    local etherealFound = {}
    
    -- Scan by iterating through possible currency IDs
    for id = 3000, 3200 do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.name and info.name ~= "" then
            if info.name:match("Ethereal") or info.name:match("Season") then
                table.insert(etherealFound, string.format("[%d] %s: %d", 
                    id, info.name, info.quantity or 0))
            end
        end
    end
    
    if #etherealFound > 0 then
        addon:Print("|cff00ff00Ethereal/Season currencies:|r")
        for _, line in ipairs(etherealFound) do
            addon:Print("  " .. line)
        end
    else
        addon:Print("|cffffcc00No Ethereal currencies found|r")
    end
end

--- Handle enum check command
---@param addon table WarbandNexus addon instance
function CommandService:HandleEnumCheck(addon)
    if Enum and Enum.WeeklyRewardChestThresholdType then
        addon:Print("WeeklyRewardChestThresholdType: Raid=" .. tostring(Enum.WeeklyRewardChestThresholdType.Raid) .. 
                    ", M+=" .. tostring(Enum.WeeklyRewardChestThresholdType.Activities) .. 
                    ", PvP=" .. tostring(Enum.WeeklyRewardChestThresholdType.RankedPvP) ..
                    ", World=" .. tostring(Enum.WeeklyRewardChestThresholdType.World))
    else
        addon:Print("Enum not available")
    end
    
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        if activities and #activities > 0 then
            addon:Print("Vault Activities: " .. #activities)
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
                DebugPrint(log)
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

--- Handle illusion test command
---@param addon table WarbandNexus addon instance
---@param input string Full command input
function CommandService:HandleTestIllusions(addon, input)
    local subCmd = addon:GetArgs(input, 2, 1)
    
    DebugPrint("|cff00ff00[WN Illusion Test]|r Starting...")
    
    -- Check API availability
    if not C_TransmogCollection then
        DebugPrint("|cffff0000ERROR:|r C_TransmogCollection namespace not found")
        return
    end
    
    if not C_TransmogCollection.GetIllusions then
        DebugPrint("|cffff0000ERROR:|r C_TransmogCollection.GetIllusions not found")
        return
    end
    
    -- Get illusions
    DebugPrint("|cffffcc00Calling GetIllusions()...|r")
    local illusions = C_TransmogCollection.GetIllusions()
    
    if not illusions then
        DebugPrint("|cffff0000ERROR:|r GetIllusions() returned nil")
        return
    end
    
    if type(illusions) ~= "table" then
        DebugPrint("|cffff0000ERROR:|r GetIllusions() returned " .. type(illusions) .. " instead of table")
        return
    end
    
    local count = #illusions
    DebugPrint("|cff00ff00SUCCESS:|r GetIllusions() returned " .. count .. " illusions")
    
    -- /wn illusions <id> - Test specific illusion
    if subCmd and tonumber(subCmd) then
        local visualID = tonumber(subCmd)
        DebugPrint("|cff00ccff========================================|r")
        DebugPrint("|cffffcc00Testing visualID: " .. visualID .. "|r")
        DebugPrint("|cff00ccff========================================|r")
        
        -- Find in array
        local found = false
        for i, info in ipairs(illusions) do
            if info and info.visualID == visualID then
                found = true
                DebugPrint("|cff00ff00[1] Found in GetIllusions() at index " .. i .. "|r")
                DebugPrint("  ALL FIELDS:")
                for k, v in pairs(info) do
                    if type(v) ~= "function" and type(v) ~= "table" then
                        DebugPrint("    " .. tostring(k) .. " = " .. tostring(v))
                    end
                end
                break
            end
        end
        
        if not found then
            DebugPrint("|cffff0000[1] visualID " .. visualID .. " NOT found in GetIllusions()|r")
        end
        
        -- Test GetIllusionStrings
        DebugPrint("|cffffcc00[2] Testing GetIllusionStrings(" .. visualID .. "):|r")
        if C_TransmogCollection.GetIllusionStrings then
            local name, hyperlink, sourceText = C_TransmogCollection.GetIllusionStrings(visualID)
            DebugPrint("  name = " .. tostring(name))
            DebugPrint("  hyperlink = " .. tostring(hyperlink))
            DebugPrint("  sourceText = " .. tostring(sourceText))
        else
            DebugPrint("  |cffff0000GetIllusionStrings() not found|r")
        end
        
        DebugPrint("|cff00ccff========================================|r")
        return
    end
    
    -- List mode - show first 20
    DebugPrint("|cff00ccff========================================|r")
    DebugPrint("|cffffcc00Showing first 20 illusions:|r")
    DebugPrint("|cff00ccff========================================|r")
    
    for i = 1, math.min(20, count) do
        local info = illusions[i]
        if info then
            local visualID = info.visualID or "???"
            local name = info.name or "???"
            local collected = info.isCollected and "|cff00ff00✓|r" or "|cffff0000✗|r"
            DebugPrint(string.format("%d. ID: %s | %s %s", i, tostring(visualID), collected, name))
        end
    end
    
    DebugPrint("|cff00ccff========================================|r")
    DebugPrint("|cff888888Use: /wn illusions <visualID> to test specific illusion|r")
end

-- ============================================================================
-- DEBUG PET/MOUNT ITEM COMMAND
-- ============================================================================
-- Usage: /wn debugpet <itemID>
-- Dumps all API return values for a given item to help diagnose detection issues

function CommandService:HandleDebugPet(addon, input)
    local _, itemIDStr = addon:GetArgs(input, 2)
    local itemID = tonumber(itemIDStr)
    
    if not itemID then
        addon:Print("|cffffcc00Usage: /wn debugpet <itemID>|r")
        addon:Print("|cff888888Example: /wn debugpet 232859|r (Lab Rat)")
        return
    end
    
    addon:Print("|cff00ccff=== DEBUG PET/COLLECTIBLE: itemID " .. itemID .. " ===|r")
    
    -- 1. GetItemInfo
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
          itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID = GetItemInfo(itemID)
    
    addon:Print("|cffffcc00[GetItemInfo]|r")
    if not classID then
        addon:Print("  |cffff0000FAILED - item data not loaded. Requesting...|r")
        C_Item.RequestLoadItemDataByID(itemID)
        C_Timer.After(1, function()
            CommandService:HandleDebugPet(addon, input)
        end)
        return
    end
    addon:Print("  name: " .. tostring(itemName))
    addon:Print("  classID: " .. tostring(classID) .. " (" .. tostring(itemType) .. ")")
    addon:Print("  subclassID: " .. tostring(subclassID) .. " (" .. tostring(itemSubType) .. ")")
    addon:Print("  icon: " .. tostring(itemTexture))
    addon:Print("  link: " .. tostring(itemLink))
    
    -- 2. GetItemSpell
    local spellName, spellID = GetItemSpell(itemID)
    addon:Print("|cffffcc00[GetItemSpell]|r")
    addon:Print("  spellName: " .. tostring(spellName))
    addon:Print("  spellID: " .. tostring(spellID))
    
    -- 3. C_PetJournal.GetPetInfoByItemID
    addon:Print("|cffffcc00[C_PetJournal.GetPetInfoByItemID]|r")
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        -- Return: name, icon, petType, creatureID, sourceText, description,
        --         isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID
        local pName, pIcon, pType, creatureID, sourceText, description,
              isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        addon:Print("  name: " .. tostring(pName))
        addon:Print("  icon: " .. tostring(pIcon))
        addon:Print("  speciesID (13th): " .. tostring(speciesID))
        addon:Print("  petType: " .. tostring(pType) .. " | creatureID: " .. tostring(creatureID))
        addon:Print("  canBattle: " .. tostring(canBattle) .. " | tradeable: " .. tostring(tradeable))
        
        if speciesID and type(speciesID) == "number" then
            local numOwned, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
            addon:Print("  |cff00ff00owned: " .. tostring(numOwned) .. "/" .. tostring(limit) .. "|r")
        else
            addon:Print("  |cffff8800speciesID is nil or not a number|r")
        end
    else
        addon:Print("  |cffff0000API NOT AVAILABLE|r")
    end
    
    -- 4. C_MountJournal.GetMountFromItem
    addon:Print("|cffffcc00[C_MountJournal.GetMountFromItem]|r")
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        addon:Print("  mountID: " .. tostring(mountID))
        if mountID then
            local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            addon:Print("  name: " .. tostring(name) .. " | collected: " .. tostring(isCollected))
        end
    else
        addon:Print("  |cffff0000API NOT AVAILABLE|r")
    end
    
    -- 5. C_ToyBox.GetToyInfo
    addon:Print("|cffffcc00[C_ToyBox.GetToyInfo]|r")
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local toyItemID, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
        addon:Print("  toyItemID: " .. tostring(toyItemID))
        addon:Print("  toyName: " .. tostring(toyName))
        if PlayerHasToy then
            addon:Print("  PlayerHasToy: " .. tostring(PlayerHasToy(itemID)))
        end
    else
        addon:Print("  |cffff0000API NOT AVAILABLE|r")
    end
    
    -- 6. C_TooltipInfo.GetItemByID
    addon:Print("|cffffcc00[C_TooltipInfo.GetItemByID]|r")
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local success, tooltipData = pcall(C_TooltipInfo.GetItemByID, itemID)
        if success and tooltipData then
            addon:Print("  type: " .. tostring(tooltipData.type))
            addon:Print("  id: " .. tostring(tooltipData.id))
            addon:Print("  hyperlink: " .. tostring(tooltipData.hyperlink))
            if tooltipData.lines then
                addon:Print("  lines (" .. #tooltipData.lines .. "):")
                for i, line in ipairs(tooltipData.lines) do
                    if i <= 10 then  -- Limit to first 10 lines
                        local left = line.leftText or ""
                        local right = line.rightText or ""
                        local lineType = line.type or "?"
                        addon:Print("    [" .. i .. "] type=" .. tostring(lineType) .. " L: " .. left .. (right ~= "" and (" | R: " .. right) or ""))
                    end
                end
                if #tooltipData.lines > 10 then
                    addon:Print("    ... (" .. (#tooltipData.lines - 10) .. " more lines)")
                end
            end
        else
            addon:Print("  |cffff0000FAILED or nil|r")
        end
    else
        addon:Print("  |cffff0000API NOT AVAILABLE|r")
    end
    
    -- 7. CheckNewCollectible result
    addon:Print("|cffffcc00[CheckNewCollectible]|r")
    if addon.CheckNewCollectible then
        local result = addon:CheckNewCollectible(itemID, itemLink)
        if result then
            addon:Print("  |cff00ff00DETECTED:|r type=" .. tostring(result.type) .. " id=" .. tostring(result.id) .. " name=" .. tostring(result.name))
        else
            addon:Print("  |cffff8800returned nil (not detected as collectible)|r")
        end
    end
    
    addon:Print("|cff00ccff=== END DEBUG ===|r")
end
