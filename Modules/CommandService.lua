--[[============================================================================
    COMMAND SERVICE
    Centralized slash command routing and handling for Warband Nexus
    
    Handles:
    - Main slash command routing (/wn, /warbandnexus)
    - Public commands (show, options, help, todo, etc.)
    - Debug toggle and profiler
============================================================================]]

local addonName, ns = ...
local CommandService = {}
ns.CommandService = CommandService

local issecretvalue = issecretvalue

-- Debug print helper (only shows when debug mode is enabled)
local DebugPrint = ns.DebugPrint

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
        addon:Print("|cff00ccffWarband Nexus|r — " .. ((ns.L and ns.L["AVAILABLE_COMMANDS"]) or "Available commands:"))
        addon:Print("  |cff00ccff/wn|r — " .. ((ns.L and ns.L["CMD_OPEN"]) or "Open addon window"))
        addon:Print("  |cff00ccff/wn todo|r — " .. ((ns.L and ns.L["CMD_PLANS"]) or "Toggle To-Do Tracker window"))
        addon:Print("  |cff00ccff/wn options|r — " .. ((ns.L and ns.L["CMD_OPTIONS"]) or "Open settings"))
        addon:Print("  |cff00ccff/wn keys|r — Announce alt keystones to party chat")
        addon:Print("  |cff00ccff/wn minimap|r — " .. ((ns.L and ns.L["CMD_MINIMAP"]) or "Toggle minimap button"))
        addon:Print("  |cff00ccff/wn debug|r — " .. ((ns.L and ns.L["CMD_DEBUG"]) or "Toggle debug mode"))
        addon:Print("  |cff00ccff/wn help|r — " .. ((ns.L and ns.L["CMD_HELP"]) or "Show this list"))
        addon:Print("  |cff00ccff/wn rarityimport|r — Copy Rarity mount attempts into WN + saved backup (use before disabling Rarity)")
        addon:Print("  |cff00ccff/wn rarityrestore|r — Re-apply WN backup (no Rarity needed)")
        addon:Print("  |cff00ccff/wn raritysync|r — One immediate max-merge while Rarity is loaded")
        if addon.db and addon.db.profile and addon.db.profile.debugMode then
            -- Literal English: avoids AceLocale returning missing keys as "CMD_*" in non-enUS clients
            addon:Print("|cff888888— Debug mode ON — advanced / diagnostic:|r")
            addon:Print("  |cff00ccff/wn trycounterdebug|r — Toggle try counter loot debug (verbose chat)")
            addon:Print("  |cff00ccff/wn markobtained <itemID>|r — Mark drop obtained (stops try counter)")
            addon:Print("  |cff00ccff/wn clearobtained <itemID>|r — Clear obtained marker (resume try counter)")
            addon:Print("  |cff00ccff/wn profiler|r — " .. ((ns.L and ns.L["CMD_PROFILER"]) or "Performance profiler"))
            addon:Print("  |cff00ccff/wn toydebug <itemID>|r — Toy tooltip/source dump (chat)")
            addon:Print("  |cff00ccff/wn firstcraft|r — " .. ((ns.L and ns.L["CMD_FIRSTCRAFT"]) or "First-craft recipes (open profession first)"))
            addon:Print("  |cff00ccff/wn profverify|r — Profession Knowledge/Recipes/Equipment dump")
            addon:Print("  |cff00ccff/wn changelog|r — " .. ((ns.L and ns.L["CMD_CHANGELOG"]) or "Show changelog"))
            addon:Print("  |cff00ccff/wn trydebug|r — Try counter state / source simulation")
            addon:Print("  |cff00ccff/wn trycount <type> <id>|r — Try count for item|mount|pet|toy")
            addon:Print("  |cff00ccff/wn legacymountpreview|r — Compare Rarity vs WN try counts (|cff00ccff/wn raritysync|r to merge now)")
            addon:Print("  |cff00ccff/wn legacyseedreset|r — Clear informational seed flag (does not block Rarity merge)")
            addon:Print("  |cff00ccff/wn trycounteraudit|r — List mount Statistics merge buckets (IDs per mount)")
            addon:Print("  |cff00ccff/wn check|r — Drops from target/mouseover")
            addon:Print("  |cff00ccff/wn test ...|r — Same as |cff00ccff/wntest ...|r (rep ui, rep event, overflow, …)")
            addon:Print("  |cff00ccff/wn testevents [type] [id]|r — Test notification events")
            addon:Print("  |cff00ccff/wn testloot [type] [id]|r — Test notification popups")
            addon:Print("  |cff00ccff/wn cleanup|r — Remove stale characters (90+ days inactive)")
            addon:Print("  |cff00ccff/wn track|r — enable | disable | status")
            addon:Print("  |cff00ccff/wn recover|r — Emergency recovery")
        else
            addon:Print("|cff888888More try-counter tools with |cff00ccff/wn debug|r|cff888888 then |cff00ccff/wn help|r.|r")
        end
        return
    end
    
    -- ── Public commands (always available) ──
    
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        addon:ShowMainWindow()
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
        
    elseif cmd == "minimap" then
        if addon.ToggleMinimapButton then
            addon:ToggleMinimapButton()
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["MINIMAP_NOT_AVAILABLE"]) or "Minimap button module not loaded.") .. "|r")
        end
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
            if addon.db and addon.db.global and addon.db.global.pveProgress then
                local pve = addon.db.global.pveProgress[char.key]
                if pve and pve.mythicPlus and pve.mythicPlus.keystone then
                    keystone = pve.mythicPlus.keystone
                end
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
                
                table.insert(reportLinesLocal, string.format("%s - %s", coloredName, keystoneLink))
                
                -- Use plain text for Party to prevent WoW Server from dropping unverified item links
                -- Format: Name [+Level Dungeon]
                local shortDungeonName = dungeonName:gsub("The ", ""):sub(1, 15) -- shorten dungeon names slightly if needed
                table.insert(reportLinesParty, string.format("%s [+%d %s]", char.name, keystone.level, shortDungeonName))
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
        CommandService:HandleDebugToggle(addon)
        return

    elseif cmd == "test" then
        -- Same as /wntest — routes to DebugService:TestCommand (rep ui, rep event, overflow, …)
        local _, nextPos = addon:GetArgs(input, 1)
        local rest = ""
        if type(nextPos) == "number" and nextPos < 1e9 then
            local tail = string.sub(input, nextPos)
            if tail and tail ~= "" then
                rest = string.gsub(tail, "^%s+", "") or ""
            end
        end
        if ns.DebugService and ns.DebugService.TestCommand then
            ns.DebugService:TestCommand(addon, rest)
        else
            addon:Print("|cffff0000[WN] DebugService not available.|r")
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

    elseif cmd == "markobtained" then
        local _, arg1 = addon:GetArgs(input, 2)
        local itemID = arg1 and tonumber(arg1)
        if not itemID or itemID < 1 then
            addon:Print("|cff00ccff/wn markobtained <itemID>|r — Mark a drop item as obtained so the try counter stops tracking it.")
            addon:Print("Example: |cff888888/wn markobtained 268730|r (Nether-Warped Egg)")
            return
        end
        if addon.MarkItemObtained then
            addon:MarkItemObtained(itemID)
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
            local itemName = GetItemInfoFn and GetItemInfoFn(itemID)
            addon:Print("|cff00ff00[WN]|r Marked " .. (itemName and ("|cffffd100" .. itemName .. "|r") or ("itemID " .. itemID)) .. " as obtained. Try counter will stop tracking it.")
        else
            addon:Print("|cffff6600[WN]|r TryCounter module not loaded.")
        end
        return

    elseif cmd == "clearobtained" then
        local _, arg1 = addon:GetArgs(input, 2)
        local itemID = arg1 and tonumber(arg1)
        if not itemID or itemID < 1 then
            addon:Print("|cff00ccff/wn clearobtained <itemID>|r — Clear the obtained marker so the try counter resumes tracking.")
            return
        end
        if addon.ClearItemObtained then
            addon:ClearItemObtained(itemID)
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
            local itemName = GetItemInfoFn and GetItemInfoFn(itemID)
            addon:Print("|cff00ff00[WN]|r Cleared obtained marker for " .. (itemName and ("|cffffd100" .. itemName .. "|r") or ("itemID " .. itemID)) .. ". Try counter will resume tracking.")
        else
            addon:Print("|cffff6600[WN]|r TryCounter module not loaded.")
        end
        return

    elseif cmd == "rarityimport" or cmd == "rarityhandoff" then
        if addon.ImportRarityMountHandoff then
            addon:ImportRarityMountHandoff()
        else
            addon:Print("|cffff6600[WN]|r Try counter module not loaded.")
        end
        return

    elseif cmd == "rarityrestore" or cmd == "rarityrestorebackup" then
        if addon.RestoreRarityImportBackup then
            local updated, scanned = addon:RestoreRarityImportBackup()
            updated = tonumber(updated) or 0
            scanned = tonumber(scanned) or 0
            addon:Print(string.format(
                "|cff00ff00[WN]|r Restored from WN backup: %d row(s) raised, %d backup row(s) applied (max vs WN).|r",
                updated, scanned
            ))
        else
            addon:Print("|cffff6600[WN]|r Try counter module not loaded.")
        end
        return

    elseif cmd == "raritysync" or cmd == "raritymerge" then
        if addon.SyncRarityMountAttemptsMax then
            local updated, scanned = addon:SyncRarityMountAttemptsMax()
            updated = tonumber(updated) or 0
            scanned = tonumber(scanned) or 0
            addon:Print(string.format(
                "|cff00ff00[WN]|r Rarity max-merge: %d mount row(s) raised vs stored WN, %d row(s) read with attempts > 0 (enable Rarity if 0).|r",
                updated, scanned
            ))
        else
            addon:Print("|cffff6600[WN]|r Try counter module not loaded.")
        end
        return
    end

    -- ── Debug commands (require debug mode) ──
    
    local isDebug = addon.db and addon.db.profile and addon.db.profile.debugMode
    if not isDebug then
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_COMMAND"]) or "Unknown command.") .. "|r " ..
            ((ns.L and ns.L["TYPE_HELP"]) or "Type") .. " |cff00ccff/wn help|r " ..
            ((ns.L and ns.L["FOR_AVAILABLE_COMMANDS"]) or "for available commands."))
        return
    end
    
    if cmd == "cleanup" then
        if addon.CleanupStaleCharacters then
            local removed = addon:CleanupStaleCharacters(90)
            if removed == 0 then
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["CLEANUP_NO_INACTIVE"]) or "No inactive characters found (90+ days).") .. "|r")
            else
                addon:Print("|cff00ff00" .. string.format((ns.L and ns.L["CLEANUP_REMOVED_FORMAT"]) or "Removed %d inactive character(s).", removed) .. "|r")
            end
        end
        return

    elseif cmd == "profiler" or cmd == "prof" or cmd == "perf" then
        if ns.Profiler then
            local _, subCmd, arg3 = addon:GetArgs(input, 3)
            ns.Profiler:HandleCommand(addon, subCmd, arg3)
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["PROFILER_NOT_LOADED"]) or "Profiler module not loaded.") .. "|r")
        end
        return

    elseif cmd == "toydebug" or cmd == "toyinfo" then
        CommandService:ToyDebugReport(addon, input)
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

    elseif cmd == "firstcraft" or cmd == "fc" then
        if ns.ProfessionService and addon.PrintFirstCraftRecipesByContent then
            addon:PrintFirstCraftRecipesByContent()
        else
            addon:Print("|cffff6600[WN]|r " .. (ns.L and ns.L["PROF_FIRSTCRAFT_NO_DATA"] or "Professions module not available."))
        end
        return

    elseif cmd == "profverify" or cmd == "pv" then
        if addon.PrintProfessionVerify then
            addon:PrintProfessionVerify()
        else
            addon:Print("|cffff6600[WN]|r Profession verify not available.")
        end
        return
        
    elseif cmd == "changelog" or cmd == "changes" or cmd == "whatsnew" then
        if addon.ShowUpdateNotification and ns.CHANGELOG then
            local ok, err = pcall(function()
                addon:ShowUpdateNotification({
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "2.5.15-beta1",
                    date = ns.CHANGELOG.date or "",
                    changes = ns.CHANGELOG.changes or {"No changelog available"}
                })
            end)
            if not ok then
                addon:Print("|cffff0000[WN] Changelog error:|r " .. tostring(err))
            end
        end
        return
        
    elseif cmd == "trackchar" or cmd == "track" then
        local subCmd = select(2, addon:GetArgs(input, 2))
        if subCmd == "enable" or subCmd == "on" then
            local charKey = ns.Utilities:GetCharacterKey()
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["TRACKING_ENABLED_MSG"]) or "Character tracking ENABLED!") .. "|r")
            end
        elseif subCmd == "disable" or subCmd == "off" then
            local charKey = ns.Utilities:GetCharacterKey()
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
                addon:Print("|cffff8800" .. ((ns.L and ns.L["TRACKING_DISABLED_MSG"]) or "Character tracking DISABLED!") .. "|r")
            end
        elseif subCmd == "status" then
            local charKey = ns.Utilities:GetCharacterKey()
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

    elseif cmd == "trydebug" then
        if addon.TryCounterDebugReport then
            addon:TryCounterDebugReport()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    elseif cmd == "legacymountpreview" or cmd == "legacypreview" then
        if addon.DebugLegacyMountTrackerImportPreview then
            addon:DebugLegacyMountTrackerImportPreview()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    elseif cmd == "legacyseedreset" then
        if addon.DebugResetLegacyMountTrackerSeed then
            addon:DebugResetLegacyMountTrackerSeed()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    elseif cmd == "trycounteraudit" or cmd == "tcaudit" then
        if addon.TryCounterAuditMountStatisticBuckets then
            addon:TryCounterAuditMountStatisticBuckets()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    elseif cmd == "trycount" or cmd == "tc" then
        local _, collectibleType, id = addon:GetArgs(input, 3)
        if not collectibleType or not id then
            addon:Print("|cffff6600Usage:|r /wn trycount <type> <id>")
            addon:Print("|cff888888Example:|r /wn trycount item 226683")
            addon:Print("|cff888888Types:|r item, mount, pet, toy")
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
        return
    
    elseif cmd == "check" or cmd == "loot" or cmd == "drops" then
        if addon.CheckTargetDrops then
            addon:CheckTargetDrops()
        else
            addon:Print("|cffff6600Try counter module not loaded.|r")
        end
        return

    elseif cmd == "testevents" then
        local _, typeArg, idArg = addon:GetArgs(input, 3)
        if addon.TestNotificationEvents then
            addon:TestNotificationEvents(typeArg, idArg)
        else
            addon:Print("|cffff6600Test events module not loaded.|r")
        end
        return

    elseif cmd == "testloot" then
        local _, typeArg, idArg, stepArg = addon:GetArgs(input, 4)
        if addon.TestLootNotification then
            addon:TestLootNotification(typeArg, idArg, stepArg)
        else
            addon:Print("|cffff6600Test loot notification module not loaded.|r")
        end
        return
        
    else
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_DEBUG_CMD"]) or "Unknown debug command:") .. "|r " .. cmd)
    end
end

--============================================================================
-- TOY SOURCE DEBUG
--============================================================================

--- Dump tooltip lines and source resolution for a toy (which line becomes "source").
--- If tooltip is still "Retrieving item information", retries once after 2s.
--- Usage: /wn toydebug <itemID>
---@param addon table WarbandNexus addon instance
---@param input string Full slash command input
---@param skipRetry boolean If true, do not schedule a delayed retry (used for the 2s retry)
--- Dump everything we can read about an item: GetItemInfo, GetItemInfoInstant,
--- GetDetailedItemLevelInfo, GetItemStats, GetItemQualityByID, bind-type chain,
--- and a search through all stored bag/bank/warband-bank data for instances of this item.
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
    local selKey = ns.Utilities and ns.Utilities:GetCharacterKey() or nil
    local selData = selKey and db and db.characters and db.characters[selKey]
    if selData then
        p(string.format("Logged-in: name=%s class=%s specID=%s level=%s", tostring(selData.name), tostring(selData.classFile), tostring(selData.specID), tostring(selData.level)))
    end
end

function CommandService:ToyDebugReport(addon, input, skipRetry)
    local _, arg1 = addon:GetArgs(input, 2)
    local itemID = arg1 and tonumber(arg1)
    if not itemID or itemID < 1 then
        addon:Print("|cff00ccff/wn toydebug <itemID>|r — Show tooltip lines and which line is used as source")
        addon:Print("Example: |cff888888/wn toydebug 158078|r (Timewalker's Hearthstone)")
        if C_ToyBox and C_ToyBox.GetNumFilteredToys then
            local n = C_ToyBox.GetNumFilteredToys() or 0
            if n > 0 then
                local firstID = C_ToyBox.GetToyFromIndex(1)
                if firstID then
                    addon:Print("First toy in ToyBox itemID: |cff888888" .. tostring(firstID) .. "|r")
                end
            end
        end
        return
    end

    local _issecretvalue = issecretvalue
    local function safeStr(s)
        if s == nil then return "(nil)" end
        if type(s) ~= "string" then return tostring(s) end
        if _issecretvalue and _issecretvalue(s) then return "(secret)" end
        return s
    end

    addon:Print("|cff9370DB[WN ToyDebug]|r itemID = |cff00ccff" .. tostring(itemID) .. "|r")
    if not C_TooltipInfo then
        addon:Print("|cffff6600C_TooltipInfo not available.|r")
        return
    end

    -- Dump both APIs; same order as GetToySourceInfo: prefer GetToyByItemID (toy tooltip has Source/category)
    local byItem = C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(itemID)
    local byToy = C_TooltipInfo.GetToyByItemID and C_TooltipInfo.GetToyByItemID(itemID)
    local tooltipData = (byToy and byToy.lines and #byToy.lines > 0) and byToy or (byItem and byItem.lines and #byItem.lines > 0) and byItem or nil
    local sourceName = (byToy and byToy.lines and #byToy.lines > 0) and "GetToyByItemID" or "GetItemByID"

    -- WoW loads tooltip data asynchronously; often we get "Retrieving item information" (type 41) first
    local function isPlaceholderTooltip(data)
        if not data or not data.lines or #data.lines ~= 1 then return false end
        local left = data.lines[1] and data.lines[1].leftText
        if not left or type(left) ~= "string" then return false end
        if _issecretvalue and _issecretvalue(left) then return false end
        return left:find("Retrieving", 1, true) ~= nil or left:find("information", 1, true) ~= nil
    end
    if not skipRetry and (isPlaceholderTooltip(byItem) or isPlaceholderTooltip(byToy)) then
        addon:Print("|cffffcc00[WN ToyDebug]|r Tooltip still loading (Retrieving item information). Retrying in 2s...")
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                CommandService:ToyDebugReport(addon, input, true)
            end)
        end
        return
    end

    local function dumpLines(label, data)
        if not data or not data.lines or #data.lines == 0 then
            addon:Print("|cff888888" .. label .. ": no lines|r")
            return
        end
        addon:Print("|cff888888" .. label .. " (#lines = " .. #data.lines .. ")|r")
        for i = 1, #data.lines do
            local line = data.lines[i]
            local lt = safeStr(line and line.leftText)
            local rt = safeStr(line and line.rightText)
            local ty = (line and line.type ~= nil) and tostring(line.type) or "?"
            addon:Print(string.format("  [%d] type=%s left=%s right=%s", i, ty, lt, rt))
        end
    end
    dumpLines("GetItemByID", byItem)
    dumpLines("GetToyByItemID", byToy)

    if not tooltipData or not tooltipData.lines then
        addon:Print("|cffff6600No tooltip lines from either API.|r")
    else
        addon:Print("|cff888888GetToySourceInfo uses: " .. sourceName .. "|r")
        -- Which line would GetToySourceInfo use? (same logic as CollectionService)
        local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
        local sourceLabelClean = sourceLabel:gsub("[:%s]+$", "")
        local pickedLine = nil
        local pickReason = ""
        for i = 1, #tooltipData.lines do
            local line = tooltipData.lines[i]
            local left = line and line.leftText
            if left and type(left) == "string" and not (_issecretvalue and _issecretvalue(left)) and left ~= "" and line.type == 2 then
                pickedLine = i
                pickReason = "first line with type=2"
                break
            end
        end
        if not pickedLine then
            for i = 1, #tooltipData.lines do
                local line = tooltipData.lines[i]
                local left = line and line.leftText
                local right = line and line.rightText
                if left and type(left) == "string" and not (_issecretvalue and _issecretvalue(left)) and left:find(sourceLabelClean, 1, true) then
                    pickedLine = i
                    pickReason = "left contains Source label"
                    break
                end
                if right and type(right) == "string" and not (_issecretvalue and _issecretvalue(right)) and right:find(sourceLabelClean, 1, true) then
                    pickedLine = i
                    pickReason = "right contains Source label"
                    break
                end
            end
        end
        if not pickedLine then
            local sourceKeywords = {
                BATTLE_PET_SOURCE_1 or "Drop",
                BATTLE_PET_SOURCE_3 or "Vendor",
                BATTLE_PET_SOURCE_2 or "Quest",
            }
            for i = 1, #tooltipData.lines do
                local line = tooltipData.lines[i]
                local left = line and line.leftText
                local right = line and line.rightText
                local leftOk = left and type(left) == "string" and not (_issecretvalue and _issecretvalue(left))
                local rightOk = right and type(right) == "string" and not (_issecretvalue and _issecretvalue(right))
                for _, kw in ipairs(sourceKeywords) do
                    if (leftOk and left:find(kw, 1, true)) or (rightOk and right:find(kw, 1, true)) then
                        pickedLine = i
                        pickReason = "keyword match"
                        break
                    end
                end
                if pickedLine then break end
            end
        end
        if pickedLine then
            addon:Print("|cff00ff00SOURCE PICKED FROM: line " .. tostring(pickedLine) .. " (" .. pickReason .. ")|r")
        else
            addon:Print("|cffff6600SOURCE PICKED FROM: none (fallback to CollectibleSourceDB or \"Toy Collection\")|r")
        end
    end

    -- GetToySourceInfo result
    if addon.GetToySourceInfo then
        local info = addon:GetToySourceInfo(itemID)
        if info then
            addon:Print("|cff9370DB[GetToySourceInfo]|r source = |cffffffff" .. safeStr(info.source) .. "|r")
            addon:Print("|cff9370DB[GetToySourceInfo]|r description = |cff888888" .. safeStr(info.description) .. "|r")
        else
            addon:Print("|cffff6600GetToySourceInfo returned nil.|r")
        end
    end

    -- CollectibleSourceDB
    if ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetSourceStringForToy then
        local dbSrc = ns.CollectibleSourceDB.GetSourceStringForToy(itemID)
        addon:Print("|cff9370DB[GetSourceStringForToy]|r " .. (dbSrc and ("|cffffffff" .. safeStr(dbSrc) .. "|r") or "|cff888888nil (not in DB)|r"))
    end
end

--============================================================================
-- DEBUG TOGGLE
--============================================================================

--- Toggle debug mode on/off
---@param addon table WarbandNexus addon instance
function CommandService:HandleDebugToggle(addon)
    if not addon.db or not addon.db.profile then return end
    
    addon.db.profile.debugMode = not addon.db.profile.debugMode
    
    if addon.db.profile.debugMode then
        addon:Print("|cff00ff00" .. ((ns.L and ns.L["DEBUG_ENABLED"]) or "Debug mode ENABLED.") .. "|r")
    else
        addon:Print("|cffff8800" .. ((ns.L and ns.L["DEBUG_DISABLED"]) or "Debug mode DISABLED.") .. "|r")
    end
end
