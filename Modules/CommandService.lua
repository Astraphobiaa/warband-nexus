--[[============================================================================
    COMMAND SERVICE
    Centralized slash command routing and handling for Warband Nexus
    
    Handles:
    - Main slash command routing (/wn, /warbandnexus)
    - Public commands (window toggles, settings, help)
    - Optional debug-mode diagnostics (/wn debug)
============================================================================]]

local addonName, ns = ...
local CommandService = {}
ns.CommandService = CommandService

local tinsert = table.insert

local issecretvalue = issecretvalue

local IsDebugModeEnabled = ns.IsDebugModeEnabled

local function IsDebugOn()
    return IsDebugModeEnabled and IsDebugModeEnabled()
end

local function PrintSlashHelp(addon)
    addon:Print("|cff00ccffWarband Nexus|r — " .. ((ns.L and ns.L["AVAILABLE_COMMANDS"]) or "Available commands:"))
    addon:Print("  |cff00ccff/wn|r — " .. ((ns.L and ns.L["CMD_OPEN"]) or "Open addon window"))
    addon:Print("  |cff00ccff/wn saved|r — Saved Instances")
    addon:Print("  |cff00ccff/wn todo|r — " .. ((ns.L and ns.L["CMD_PLANS"]) or "To-Do Tracker"))
    addon:Print("  |cff00ccff/wn options|r — " .. ((ns.L and ns.L["CMD_OPTIONS"]) or "Settings"))
    addon:Print("  |cff00ccff/wn keys|r — Announce alt keystones (party)")
    addon:Print("  |cff00ccff/wn changelog|r — " .. ((ns.L and ns.L["CMD_CHANGELOG"]) or "Changelog popup"))
    addon:Print("  |cff00ccff/wn help|r — " .. ((ns.L and ns.L["CMD_HELP"]) or "This list"))
end

-- DEBUG: try count queries (/wn tc sync-stats, /wn trycount mount <id>)

---@param addon table WarbandNexus
---@param input string Raw slash payload after /wn
function CommandService:HandleTryCountDebugCommand(addon, input)
    local _, subCmd, collectibleType, id = addon:GetArgs(input, 4)
    local subLower = subCmd and (not (issecretvalue and issecretvalue(subCmd)) and subCmd:lower()) or nil
    if subLower == "sync-stats" or subLower == "syncstats" then
        if addon.ForceTryCounterStatisticsSync then
            addon:ForceTryCounterStatisticsSync()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return
    end
    if not collectibleType or not id then
        addon:Print("|cffff6600Usage:|r /wn trycount <type> <id>")
        addon:Print("|cff888888Example:|r /wn trycount item 226683")
        addon:Print("|cff888888Types:|r item, mount, pet, toy")
        addon:Print("|cff888888Smoke test:|r /wn tc test  (no debug required)")
        addon:Print("|cff888888Sync:|r /wn tc sync-stats  (re-read WoW Statistics for this character)")
        return
    end

    id = tonumber(id)
    if not id then
        addon:Print("|cffff6600Invalid ID:|r Must be a number")
        return
    end

    if issecretvalue and issecretvalue(collectibleType) then
        addon:Print("|cffff6600Invalid type:|r Must be one of: item, mount, pet, toy")
        return
    end
    local validTypes = { item = true, mount = true, pet = true, toy = true }
    local ctLower = collectibleType:lower()
    if not validTypes[ctLower] then
        addon:Print("|cffff6600Invalid type:|r Must be one of: item, mount, pet, toy")
        return
    end

    local count = addon:GetTryCount(ctLower, id)
    addon:Print(string.format("|cff9370DB[Try Count]|r %s |cff00ccff%d|r = |cffffff00%d attempts|r",
        ctLower, id, count))
end

-- MAIN SLASH COMMAND HANDLER

--- Main slash command router
--- Handles all /wn and /warbandnexus commands
---@param addon table WarbandNexus addon instance
---@param input string Command input from slash command
function CommandService:HandleSlashCommand(addon, input)
    local cmd = addon:GetArgs(input, 1)
    if cmd then
        if issecretvalue and issecretvalue(cmd) then
            cmd = nil
        else
            cmd = cmd:lower()
        end
    end
    
    -- No command — open addon window
    if not cmd or cmd == "" then
        addon:ShowMainWindow()
        return
    end
    
    -- Help command
    if cmd == "help" then
        PrintSlashHelp(addon)
        return
    end
    
    -- ── Public commands (always available) ──
    
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        addon:ShowMainWindow()
        return

    elseif cmd == "saved" or cmd == "savedinstances" or cmd == "raids" then
        if addon.ToggleSavedInstancesWindow then
            addon:ToggleSavedInstancesWindow()
        else
            addon:Print("|cffff6600[WN]|r Saved Instances is not available yet.")
        end
        return

    elseif cmd == "todo" or cmd == "plans" or cmd == "plan" then
        if addon.TogglePlansTrackerWindow then
            addon:TogglePlansTrackerWindow()
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["PLANS_NOT_AVAILABLE"]) or "To-Do Tracker not available.") .. "|r")
        end
        return
        
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        addon:OpenOptions()
        return

    elseif cmd == "changelog" or cmd == "changes" or cmd == "whatsnew" then
        if addon.ShowUpdateNotification and ns.CHANGELOG then
            local ok, err = pcall(function()
                addon:ShowUpdateNotification({
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "3.1.1",
                    date = ns.CHANGELOG.date or "",
                    changes = ns.CHANGELOG.changes or {"No changelog available"}
                })
            end)
            if not ok then
                addon:Print("|cffff0000[WN] Changelog error:|r " .. tostring(err))
            end
        end
        return

    elseif cmd == "reminder" then
        local sub = addon:GetArgs(input, 2)
        if sub and issecretvalue and issecretvalue(sub) then sub = nil end
        sub = sub and sub:lower() or ""
        if sub == "syncwq" or sub == "syncquestcatalog" or sub == "sync" then
            if not addon.ScanMidnightQuests then
                addon:Print("|cffff6600[WN]|r Midnight quest scan not available.")
                return
            end
            local rows
            local INDEX = ns.ReminderWorldQuestIndex
            if INDEX and INDEX.DeepScanAllMaps then
                local okScan, scanned = pcall(INDEX.DeepScanAllMaps)
                if okScan and type(scanned) == "table" then rows = scanned end
            end
            if not rows or #rows == 0 then
                local ok, quests = pcall(function() return addon:ScanMidnightQuests() end)
                if ok and quests and quests.worldQuests then
                    rows = quests.worldQuests
                end
            end
            if not rows or #rows == 0 then
                addon:Print("|cffff6600[WN]|r Quest scan failed.")
                return
            end
            local n = #rows
            if ns.ReminderQuestCatalog and ns.ReminderQuestCatalog.RefreshDiscoveryFromScan then
                ns.ReminderQuestCatalog.RefreshDiscoveryFromScan()
            else
                local WQC = ns.ReminderWorldQuestCatalog
                if WQC and WQC.ImportFromScanRows then
                    WQC.ImportFromScanRows(rows)
                end
                if ns.ReminderQuestCatalog and ns.ReminderQuestCatalog.RecordDiscoveredWorldQuests then
                    ns.ReminderQuestCatalog.RecordDiscoveredWorldQuests(rows)
                end
            end
            if ns.ReminderQuestCatalog and ns.ReminderQuestCatalog.ClearRowCache then
                ns.ReminderQuestCatalog.ClearRowCache()
            end
            addon:Print(string.format("|cff00ccff[WN]|r Saved %d world quests to reminder catalog (account-wide). Reopen Set Alert to refresh.", n))
        else
            addon:Print("|cff00ccff/wn reminder syncwq|r — Scan Midnight maps and save all seen world quests to the maintained catalog.")
        end
        return

    elseif cmd == "tc" or cmd == "trycount" then
        local _, subCmd = addon:GetArgs(input, 2)
        local subLower = subCmd and (not (issecretvalue and issecretvalue(subCmd)) and subCmd:lower()) or nil
        if subLower == "test" then
            if addon.RunTryCounterSelfTest then
                addon:RunTryCounterSelfTest()
            else
                addon:Print("|cffff6600[WN]|r Try Counter module not loaded.")
            end
            return
        end
        if not IsDebugOn() then
            addon:Print("|cffff6600Usage:|r /wn tc test  — smoke test (always available)")
            addon:Print("|cff888888Other /wn tc commands need |cff00ccff/wn debug|r first.")
            return
        end
        CommandService:HandleTryCountDebugCommand(addon, input)
        return

    elseif cmd == "keys" or cmd == "keystones" then
        if not addon.GetAllCharacters then
            addon:Print("|cffff6600[WN] Character data not available.|r")
            return
        end
        
        local characters = addon:GetAllCharacters()
        local keysFound = 0
        local reportLinesLocal = {}
        local reportLinesParty = {}
        
        for i = 1, #characters do
            local char = characters[i]
            local keystone = nil
            if addon.GetPvEData then
                -- GetAllCharacters rows carry the table key as _key (no .key field).
                local pve = addon:GetPvEData(char._key)
                keystone = pve and pve.keystone
            end
            
            -- Fallback to v1 data if missing in v2
            if not keystone and char.mythicKey then
                keystone = char.mythicKey
            end
            
            if keystone and keystone.level and keystone.level > 0 then
                local dungeonName = keystone.dungeonName or "Unknown Dungeon"
                local mapID = keystone.dungeonID or keystone.mapID or 0
                
                -- Construct Class Colored Name for Local Print
                local classColor = char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile] or {r=1, g=1, b=1}
                local colorHex = string.format("ff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                local coloredName = string.format("|c%s%s|r", colorHex, char.name)
                
                -- Construct Clickable Keystone Link for Local Print
                local keystoneLink = string.format("|cffa335ee|Hitem:180653::::::::80:253::::::|h[%s (+%d)]|h|r", dungeonName, keystone.level)
                
                tinsert(reportLinesLocal, string.format("%s - %s", coloredName, keystoneLink))
                
                -- Use plain text for Party to prevent WoW Server from dropping unverified item links
                -- Format: Name [+Level Dungeon]
                local shortDungeonName = dungeonName:gsub("The ", ""):sub(1, 15) -- shorten dungeon names slightly if needed
                tinsert(reportLinesParty, string.format("%s [+%d %s]", char.name, keystone.level, shortDungeonName))
                keysFound = keysFound + 1
            end
        end
        
        if keysFound == 0 then
            addon:Print("|cffff6600[WN] No keystones found across your characters.|r")
        else
            if IsInGroup() and not IsInRaid() then
                SendChatMessage("[WN Keys]: Key List", "PARTY")
                local currentLine = ""
                local lineCount = 0
                local SEP = "  -  "

                for i = 1, #reportLinesParty do
                    -- Strip any pipe characters so Midnight's escape-code validator never fires.
                    local entry = reportLinesParty[i]:gsub("|", "")
                    if currentLine == "" then
                        currentLine = entry
                    else
                        -- Check if adding the next entry exceeds WoW's 255 character chat limit
                        if string.len(currentLine) + string.len(SEP) + string.len(entry) > 250 then
                            lineCount = lineCount + 1
                            local sendStr = currentLine
                            C_Timer.After(lineCount * 0.2, function()
                                SendChatMessage(sendStr, "PARTY")
                            end)
                            currentLine = entry
                        else
                            currentLine = currentLine .. SEP .. entry
                        end
                    end
                end
                
                if currentLine ~= "" then
                    lineCount = lineCount + 1
                    local sendStr = currentLine
                    C_Timer.After(lineCount * 0.2, function()
                        SendChatMessage(sendStr, "PARTY")
                    end)
                end
            else
                addon:Print("|cff00ccff[WN] Keystones (Not in a party, printing to self):|r")
                for i = 1, #reportLinesLocal do
                    addon:Print("  " .. reportLinesLocal[i])
                end
            end
        end
        return

    elseif cmd == "debug" then
        local _, sub, third = addon:GetArgs(input, 3)
        if sub and not (issecretvalue and issecretvalue(sub)) then
            sub = sub:lower()
            if sub == "verbose" then
                CommandService:HandleDebugVerboseToggle(addon)
                return
            elseif sub == "off" then
                CommandService:HandleDebugOff(addon)
                return
            elseif sub == "on" then
                if not addon.db or not addon.db.profile then return end
                if not addon.db.profile.debugMode then
                    CommandService:HandleDebugToggle(addon)
                end
                return
            elseif sub == "bags" or sub == "bag" or sub == "items" then
                if not IsDebugOn() then
                    addon:Print("|cffff6600[WN]|r Enable debug first: |cff00ccff/wn debug|r")
                    return
                end
                local BP = ns.ItemsCacheBagPerf
                if BP and BP.HandleCommand then
                    BP.HandleCommand(addon, third, nil)
                else
                    addon:Print("|cffff6600[WN]|r ItemsCacheBagPerf not loaded.|r")
                end
                return
            end
        end
        CommandService:HandleDebugToggle(addon)
        return
    end

    -- ── Debug-only commands (profiler, collection, diagnostics, tests) ──
    if not IsDebugOn() then
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_COMMAND"]) or "Unknown command.") .. "|r " ..
            ((ns.L and ns.L["TYPE_HELP"]) or "Type") .. " |cff00ccff/wn help|r " ..
            ((ns.L and ns.L["FOR_AVAILABLE_COMMANDS"]) or "for available commands."))
        return
    end

    if cmd == "charkeys" or cmd == "charkey" then
        local DS = ns.DebugService
        if DS and DS.PrintCharacterKeyDiagnostics then
            DS:PrintCharacterKeyDiagnostics(addon)
        else
            addon:Print("|cffff6600[WN]|r DebugService not loaded.|r")
        end
        return

    elseif cmd == "profiler" or cmd == "profile" then
        local P = ns.Profiler
        if not P or not P.HandleCommand then
            addon:Print("|cffff6600[WN]|r " .. ((ns.L and ns.L["PROFILER_NOT_LOADED"]) or "Profiler module not loaded.") .. "|r")
            return
        end
        local _, subCmd, arg3, arg4 = addon:GetArgs(input, 4)
        P:HandleCommand(addon, subCmd, arg3, arg4)
        return

    elseif cmd == "collection" or cmd == "collections" then
        local _, sub, third = addon:GetArgs(input, 3)
        sub = sub and sub:lower() or ""
        if sub == "rescan" then
            if addon.RequestCollectionDataRefreshForce then
                addon:RequestCollectionDataRefreshForce()
            else
                addon:Print("|cffff6600[WN]|r CollectionService not loaded.|r")
            end
            return
        elseif sub == "sync" or sub == "refresh" then
            if third and third:lower() == "force" then
                if addon.RequestCollectionDataRefreshForce then
                    addon:RequestCollectionDataRefreshForce()
                else
                    addon:Print("|cffff6600[WN]|r CollectionService not loaded.|r")
                end
            elseif addon.RequestCollectionDataRefresh then
                addon:RequestCollectionDataRefresh()
            else
                addon:Print("|cffff6600[WN]|r CollectionService not loaded.|r")
            end
            return
        elseif sub == "status" then
            if addon.PrintCollectionDataStatus then
                addon:PrintCollectionDataStatus()
            else
                addon:Print("|cffff6600[WN]|r CollectionService not loaded.|r")
            end
            return
        elseif sub == "rebuild" then
            local full = third and third:lower() == "full"
            if addon.DebugForceCollectionRebuild then
                addon:DebugForceCollectionRebuild(full)
            else
                addon:Print("|cffff6600[WN]|r DebugForceCollectionRebuild not available.|r")
            end
            return
        else
            addon:Print("|cff00ccff/wn collection sync|r — Run EnsureCollectionData when store is incomplete vs code version.")
            addon:Print("|cff00ccff/wn collection sync force|r — same as |cff00ccff/wn collection rescan|r (mount/pet/toy wipe + rescan).")
            addon:Print("|cff00ccff/wn collection status|r — Print collectionStore counts and loading state.")
            addon:Print("|cff00ccff/wn collection rebuild|r [|cff00ccfffull|r] — wipe store + full refetch.")
            return
        end

    elseif cmd == "uimap" then
        CommandService:HandleUiMapDebug(addon, input)
        return

    elseif cmd == "bagdebug" or cmd == "bagperf" then
        local _, subCmd, arg3 = addon:GetArgs(input, 3)
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.HandleCommand then
            BP.HandleCommand(addon, subCmd, arg3)
        else
            addon:Print("|cffff6600[WN]|r ItemsCacheBagPerf not loaded.|r")
        end
        return

    elseif cmd == "gearstash" or cmd == "stashrec" or cmd == "gearrec" then
        local _, itemArg = addon:GetArgs(input, 2)
        local probeID = itemArg and tonumber(itemArg) or nil
        if addon.DiagnoseGearStorageRecToChat then
            addon:DiagnoseGearStorageRecToChat(nil, probeID)
        else
            addon:Print("|cffff6600[WN]|r Gear stash diagnostic not loaded.")
        end
        return

    elseif cmd == "trycounterdebug" or cmd == "lootdebug" then
        if not addon.db or not addon.db.profile then
            addon:Print("|cffff6600[WN] Could not toggle: profile not ready.|r")
            return
        end
        addon.db.profile.debugTryCounterLoot = not addon.db.profile.debugTryCounterLoot
        if addon.db.profile.debugTryCounterLoot then
            addon:Print("|cff00ff00[WN] Try counter loot debug ENABLED. Open any loot (dumpster, chest, corpse) — you should see [WN-TryCounter] lines in chat.|r")
        else
            addon:Print("|cffff8800[WN] Try counter loot debug DISABLED.|r")
        end
        return

    elseif cmd == "testloot" or cmd == "testnotif" then
        local _, typeArg, idArg, stepArg = addon:GetArgs(input, 4)
        if addon.TestLootNotification then
            addon:TestLootNotification(typeArg, idArg, stepArg)
        end
        return

    elseif cmd == "testevents" then
        local _, typeArg, idArg = addon:GetArgs(input, 3)
        if addon.TestNotificationEvents then
            addon:TestNotificationEvents(typeArg, idArg)
        end
        return

    elseif cmd == "errors" or cmd == "error" then
        local _, subCmd, idxArg = addon:GetArgs(input, 3)
        if subCmd == "full" and addon.ShowErrorDetails then
            addon:ShowErrorDetails(tonumber(idxArg) or 1)
        elseif addon.PrintRecentErrors then
            addon:PrintRecentErrors(tonumber(subCmd) or 5)
        end
        return

    elseif cmd == "profverify" then
        if addon.PrintProfessionVerify then
            addon:PrintProfessionVerify()
        else
            addon:Print("|cffff6600[WN]|r Profession verify not available.|r")
        end
        return

    elseif cmd == "guidmigrate" then
        if ns.MigrationService and ns.MigrationService.RunGuidSubsidiaryRemap and addon.db then
            local n = ns.MigrationService:RunGuidSubsidiaryRemap(addon.db)
            addon:Print(string.format("|cff00ff00[WN]|r GUID subsidiary remap complete (%d key(s) considered).|r", n))
        else
            addon:Print("|cffff6600[WN]|r MigrationService unavailable.|r")
        end
        return

    elseif cmd == "cleanup" then
        if addon.CleanupStaleCharacters then
            local removed = addon:CleanupStaleCharacters(90)
            if removed == 0 then
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["CLEANUP_NO_INACTIVE"]) or "No inactive characters found (90+ days).") .. "|r")
            else
                addon:Print("|cff00ff00" .. string.format((ns.L and ns.L["CLEANUP_REMOVED_FORMAT"]) or "Removed %d inactive character(s).", removed) .. "|r")
            end
        end
        return

    elseif cmd == "dumpitem" or cmd == "iteminfo" then
        local _, idArg = addon:GetArgs(input, 2)
        local itemID = tonumber(idArg)
        if not itemID then
            addon:Print("|cffff6600Usage:|r /wn dumpitem <itemID>")
            return
        end
        CommandService:DumpItemReport(addon, itemID)
        return

    elseif cmd == "trackchar" or cmd == "track" then
        local subCmd = select(2, addon:GetArgs(input, 2))
        if subCmd == "enable" or subCmd == "on" then
            local charKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon))
                or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
            if ns.CharacterService and charKey then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["TRACKING_ENABLED_MSG"]) or "Character tracking ENABLED!") .. "|r")
            end
        elseif subCmd == "disable" or subCmd == "off" then
            local charKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon))
                or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
            if ns.CharacterService and charKey then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
                addon:Print("|cffff8800" .. ((ns.L and ns.L["TRACKING_DISABLED_MSG"]) or "Character tracking DISABLED!") .. "|r")
            end
        elseif subCmd == "status" then
            local charKey = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and ns.CharacterService:ResolveSubsidiaryCharacterKey(addon, nil))
                or (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon))
                or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
            local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(addon)
            addon:Print("|cff00ccff" .. ((ns.L and ns.L["CHARACTER_LABEL"]) or "Character:") .. "|r " .. charKey)
            if isTracked then
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["STATUS_LABEL"]) or "Status:") .. "|r " .. ((ns.L and ns.L["TRACKING_ENABLED"]) or "Tracking ENABLED"))
            else
                addon:Print("|cffff8800" .. ((ns.L and ns.L["STATUS_LABEL"]) or "Status:") .. "|r " .. ((ns.L and ns.L["TRACKING_DISABLED"]) or "Tracking DISABLED (read-only mode)"))
            end
        else
            addon:Print("|cff00ccff/wn track|r — " .. ((ns.L and ns.L["TRACK_USAGE"]) or "Usage: enable | disable | status"))
        end
        return
        
    elseif cmd == "recover" or cmd == "emergency" then
        if addon.EmergencyRecovery then
            addon:EmergencyRecovery()
        end
        return

    elseif cmd == "check" or cmd == "loot" or cmd == "drops" then
        if addon.CheckTargetDrops then
            addon:CheckTargetDrops()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    else
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_DEBUG_CMD"]) or "Unknown debug command:") .. "|r " .. tostring(cmd))
    end
end

-- UI MAP DEBUG (reminder zone picker / C_Map)

local function uiMapSafeName(info)
    if not info then return nil end
    local n = info.name
    if not n or n == "" then return nil end
    if issecretvalue and issecretvalue(n) then return "<secret>" end
    return n
end

--- Throttled chat lines (long catalog dumps won’t drop silently).
local function printLinesThrottled(addon, lines)
    if not lines or #lines == 0 then return end
    local idx = 1
    local chunk = 14
    local function step()
        local last = math.min(idx + chunk - 1, #lines)
        for j = idx, last do
            addon:Print(lines[j])
        end
        idx = last + 1
        if idx <= #lines then
            C_Timer.After(0.06, step)
        end
    end
    step()
end

--- /wn uimap here | catalog [section] | id <uiMapID>
---@param addon table WarbandNexus
---@param input string Raw slash payload (after /wn)
function CommandService:HandleUiMapDebug(addon, input)
    local _, sub, arg = addon:GetArgs(input, 3)
    sub = sub and sub:lower() or ""

    local function banner(msg)
        addon:Print("|cff00ccff[WN uiMap]|r " .. msg)
    end

    if sub == "" or sub == "help" then
        banner("Usage:")
        addon:Print("  |cff00ccff/wn uimap here|r — player map + parents + optional instance")
        addon:Print("  |cff00ccff/wn uimap catalog [section]|r — rows from ReminderZoneCatalog (omit section = all)")
        addon:Print("  |cff00ccff/wn uimap id <uiMapID>|r — GetMapInfo + UIMapContentKind.Resolve")
        return
    end

    if sub == "here" or sub == "current" then
        if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then
            banner("|cffff6600C_Map API unavailable.|r")
            return
        end
        local okm, mid = pcall(C_Map.GetBestMapForUnit, "player")
        mid = okm and tonumber(mid) or nil
        if not mid or mid <= 0 then
            banner("|cffff6600Could not read player uiMapID.|r")
            return
        end
        banner("Player uiMapID = " .. tostring(mid))
        local chain = {}
        local cur = mid
        local guard = 0
        while cur and cur > 0 and guard < 32 do
            guard = guard + 1
            local ok, info = pcall(C_Map.GetMapInfo, cur)
            if not ok or not info then
                chain[#chain + 1] = "  " .. tostring(cur) .. " | <no GetMapInfo>"
                break
            end
            local nm = uiMapSafeName(info) or "?"
            local pid = tonumber(info.parentMapID)
            local mt = info.mapType
            chain[#chain + 1] = string.format("  %d | %s | parent=%s | mapType=%s",
                cur, nm, tostring(pid), tostring(mt))
            if not pid or pid <= 0 or pid == cur then break end
            cur = pid
        end
        for i = 1, #chain do addon:Print(chain[i]) end

        local okI, name, instType, difficultyID, _, _, _, _, instanceID = pcall(GetInstanceInfo)
        if okI and name and not (issecretvalue and issecretvalue(name)) then
            addon:Print(string.format("  Instance: %s | type=%s | instanceID=%s | difficultyID=%s",
                tostring(name), tostring(instType), tostring(instanceID), tostring(difficultyID)))
        end
        return
    end

    if sub == "id" then
        local mid = tonumber(arg)
        if not mid or mid <= 0 then
            banner("|cffff6600Usage:|r /wn uimap id <uiMapID>")
            return
        end
        if not C_Map or not C_Map.GetMapInfo then
            banner("|cffff6600C_Map.GetMapInfo unavailable.|r")
            return
        end
        local UICK = ns.UIMapContentKind
        if UICK and UICK.InvalidateCache then UICK.InvalidateCache() end
        if UICK and UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
        local ok, info = pcall(C_Map.GetMapInfo, mid)
        if not ok or not info then
            banner("id=" .. mid .. " | GetMapInfo failed")
            return
        end
        local nm = uiMapSafeName(info) or "?"
        local kind = UICK and UICK.Resolve and UICK.Resolve(mid, info) or "?"
        banner(string.format("id=%d | name=%s | parent=%s | mapType=%s | kind=%s",
            mid, nm, tostring(info.parentMapID), tostring(info.mapType), tostring(kind)))
        return
    end

    if sub == "catalog" then
        local cat = ns.ReminderZoneCatalog
        if not cat or not cat.sections or not cat.GetDisplayRowsForSection then
            banner("|cffff6600ReminderZoneCatalog not loaded.|r")
            return
        end
        if cat.InvalidateZoneApiCache then cat.InvalidateZoneApiCache() end
        local UICK = ns.UIMapContentKind
        if UICK and UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end

        local secIdx = tonumber(arg)
        local L = ns.L
        local lines = {}
        local nSec = #cat.sections
        local function appendSection(si)
            local sec = cat.sections[si]
            if not sec then return end
            local key = sec.localeKey or ("section_" .. si)
            local title = (L and L[key]) or key
            lines[#lines + 1] = "|cff00ccff=== [" .. si .. "/" .. nSec .. "] " .. title .. " ===|r"
            local rows = cat.GetDisplayRowsForSection(si) or {}
            if #rows == 0 then
                lines[#lines + 1] = "  |cff888888(no rows — API filtered all ids or empty section)|r"
                return
            end
            for ri = 1, #rows do
                local r = rows[ri]
                if r.headerKey then
                    local hk = r.headerKey
                    local ht = (L and hk ~= "" and L[hk]) or hk
                    lines[#lines + 1] = "|cffaaaaaa--- " .. ht .. "|r"
                elseif r.id then
                    local nm = r.displayName or ""
                    local kind = r.kind or "?"
                    lines[#lines + 1] = string.format("  [%s] %d | %s", kind, r.id, nm)
                end
            end
        end

        if secIdx and secIdx > 0 then
            if secIdx > nSec then
                banner("|cffff6600Invalid section (1–" .. nSec .. ").|r")
                return
            end
            appendSection(secIdx)
        else
            for si = 1, nSec do
                appendSection(si)
            end
        end

        banner("ReminderZoneCatalog.GetDisplayRowsForSection — " .. #lines .. " lines (throttled)")
        printLinesThrottled(addon, lines)
        return
    end

    banner("|cffff6600Unknown subcommand.|r Try |cff00ccff/wn uimap help|r")
end

-- ITEM DUMP (debug)

--- Dump persisted/API item data for support (/wn dumpitem). Chat output is the product.
---@param addon table WarbandNexus addon table
---@param itemID number Item ID to dump
function CommandService:DumpItemReport(addon, itemID)
    local function p(line) addon:Print("|cff00BFFF[ItemDump]|r " .. tostring(line)) end
    p("=== itemID=" .. tostring(itemID) .. " ===")

    -- C_Item.GetItemInfoInstant
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, id, itemType, itemSubType, equipLoc, icon, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok then
            p(string.format("Instant: type=%s subType=%s equipLoc=%s classID=%s subclassID=%s",
                tostring(itemType), tostring(itemSubType), tostring(equipLoc), tostring(classID), tostring(subclassID)))
        else
            p("Instant: error " .. tostring(id))
        end
    end

    -- C_Item.GetItemInfo (14 returns)
    if C_Item and C_Item.GetItemInfo then
        local ok, name, link, q, lvl, minLvl, type_, subType, stack, equipLoc, tex, sellPrice, classID, subclassID, bindType =
            pcall(C_Item.GetItemInfo, itemID)
        if ok then
            p(string.format("Info: name=%s quality=%s ilvl=%s minLvl=%s bindType=%s",
                tostring(name), tostring(q), tostring(lvl), tostring(minLvl), tostring(bindType)))
            p("Info link: " .. tostring(link))
        else
            p("Info: error " .. tostring(name))
        end
    end

    -- DetailedItemLevelInfo
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, val = pcall(C_Item.GetDetailedItemLevelInfo, itemID)
        p("DetailedIlvl(itemID): " .. tostring(ok and val or "err"))
    end

    -- GetItemStats — returns logged-in-player primary view (key reason for filter mismatches)
    if C_Item and C_Item.GetItemStats then
        local ok, stats = pcall(C_Item.GetItemStats, "item:" .. itemID)
        if ok and type(stats) == "table" then
            local keys = {}
            for k, v in pairs(stats) do keys[#keys+1] = tostring(k) .. "=" .. tostring(v) end
            table.sort(keys)
            p("Stats(by id, logged-in view): " .. (next(keys) and table.concat(keys, ", ") or "<empty>"))
        else
            p("Stats(by id): nil/err")
        end
    end

    -- Walk every persisted location for this item; print actual stored entry + per-link stats
    local found = 0
    local function reportEntry(where, item)
        if not item or item.itemID ~= itemID then return end
        found = found + 1
        local link = item.itemLink or item.link
        p(string.format("FOUND in %s: classID=%s subclassID=%s quality=%s isBound=%s equipLoc=%s",
            where, tostring(item.classID), tostring(item.subclassID), tostring(item.quality), tostring(item.isBound), tostring(item.equipLoc)))
        p("  link: " .. tostring(link))
        if link and C_Item and C_Item.GetDetailedItemLevelInfo then
            local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
            p("  link ilvl: " .. tostring(ok and ilvl or "err"))
        end
        if link and C_Item and C_Item.GetItemInfo then
            local ok, _, _, _, lvl, _, _, _, _, _, _, _, _, _, bt = pcall(C_Item.GetItemInfo, link)
            p("  link Info: ilvl=" .. tostring(ok and lvl or "err") .. " bindType=" .. tostring(ok and bt or "err"))
        end
        if link and C_Item and C_Item.GetItemStats then
            local ok, stats = pcall(C_Item.GetItemStats, link)
            if ok and type(stats) == "table" then
                local keys = {}
                for k, v in pairs(stats) do keys[#keys+1] = tostring(k) .. "=" .. tostring(v) end
                table.sort(keys)
                p("  link Stats: " .. (next(keys) and table.concat(keys, ", ") or "<empty>"))
            end
        end
    end

    local db = addon.db and addon.db.global
    -- Warband bank
    local wbData = (addon.GetWarbandBankData and addon:GetWarbandBankData()) or nil
    if wbData and wbData.items then
        for i = 1, #wbData.items do reportEntry("WarbandBank[" .. i .. "]", wbData.items[i]) end
    end
    -- Each character bag/bank
    if db and db.itemStorage then
        for charKey, _ in pairs(db.itemStorage) do
            if charKey ~= "warbandBank" and addon.GetItemsData then
                local d = addon:GetItemsData(charKey)
                if d then
                    if d.bags then for i = 1, #d.bags do reportEntry(charKey .. " bag[" .. i .. "]", d.bags[i]) end end
                    if d.bank then for i = 1, #d.bank do reportEntry(charKey .. " bank[" .. i .. "]", d.bank[i]) end end
                end
            end
        end
    end
    p("Total persisted instances: " .. found)

    -- Selected character context
    local selKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon))
        or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
    local selData = selKey and db and db.characters and db.characters[selKey]
    if selData then
        p(string.format("Logged-in: name=%s class=%s specID=%s level=%s", tostring(selData.name), tostring(selData.classFile), tostring(selData.specID), tostring(selData.level)))
    end
end

-- DEBUG TOGGLE

--- Toggle debug mode on/off
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugToggle(addon)
    if not addon.db or not addon.db.profile then return end
    
    addon.db.profile.debugMode = not addon.db.profile.debugMode
    
    if addon.db.profile.debugMode then
        addon:Print("|cff00ff00" .. ((ns.L and ns.L["DEBUG_ENABLED"]) or "Debug mode ENABLED.") .. "|r")
        addon:Print("|cff888888[WN]|r Cache/scan logs need Debug Verbose (Settings) or |cff00ccff/wn debug verbose on|r. Bag spikes: |cff00ccff/wn bagdebug on|r. Tab timings: |cff00ccff/wn profiler tabperf on|r. Phase splits: |cff00ccff/wn profiler verbose on|r.")
    else
        addon.db.profile.debugVerbose = false
        local pp = addon.db.profile.profilerPersist
        if pp then pp.tabPerfMonitor = false end
        addon:Print("|cffff8800" .. ((ns.L and ns.L["DEBUG_DISABLED"]) or "Debug mode DISABLED.") .. "|r")
    end

    if ns.Profiler and ns.Profiler.SyncWithDebugMode then
        ns.Profiler:SyncWithDebugMode()
    end

    local ev = ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.UI_DEBUG_HEADER_SYNC
    if ev and addon.SendMessage then
        addon:SendMessage(ev)
    end
end

--- Toggle debug verbose (cache/scan/tooltip trace tier).
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugVerboseToggle(addon)
    if not addon.db or not addon.db.profile then return end
    local p = addon.db.profile
    if not p.debugMode then
        p.debugMode = true
        addon:Print("|cff00ff00" .. ((ns.L and ns.L["DEBUG_ENABLED"]) or "Debug mode ENABLED.") .. "|r")
    end
    p.debugVerbose = not p.debugVerbose
    if p.debugVerbose then
        addon:Print("|cff00ff00[WN]|r Debug verbose ON (cache/scan logs → |cff00ccff/wn profiler trace|r).")
    else
        addon:Print("|cffff8800[WN]|r Debug verbose OFF.")
    end
    if ns.Profiler and ns.Profiler.SyncWithDebugMode then
        ns.Profiler:SyncWithDebugMode()
    end
end

--- Disable all debug tiers (mode, verbose, tab perf monitor).
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugOff(addon)
    if not addon.db or not addon.db.profile then return end
    local p = addon.db.profile
    p.debugMode = false
    p.debugVerbose = false
    p.debugItemsBagPerf = false
    if p.profilerPersist then p.profilerPersist.tabPerfMonitor = false end
    addon:Print("|cffff8800" .. ((ns.L and ns.L["DEBUG_DISABLED"]) or "Debug mode DISABLED.") .. "|r")
    if ns.Profiler and ns.Profiler.SyncWithDebugMode then
        ns.Profiler:SyncWithDebugMode()
    end
    local ev = ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.UI_DEBUG_HEADER_SYNC
    if ev and addon.SendMessage then
        addon:SendMessage(ev)
    end
end
