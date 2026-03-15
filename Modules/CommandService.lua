--[[============================================================================
    COMMAND SERVICE
    Centralized slash command routing and handling for Warband Nexus
    
    Handles:
    - Main slash command routing (/wn, /warbandnexus)
    - Public commands (show, options, help, plans, etc.)
    - Debug toggle and profiler
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
    
    -- No command — open addon window
    if not cmd or cmd == "" then
        addon:ShowMainWindow()
        return
    end
    
    -- Help command
    if cmd == "help" then
        addon:Print("|cff00ccffWarband Nexus|r — " .. ((ns.L and ns.L["AVAILABLE_COMMANDS"]) or "Available commands:"))
        addon:Print("  |cff00ccff/wn|r — " .. ((ns.L and ns.L["CMD_OPEN"]) or "Open addon window"))
        addon:Print("  |cff00ccff/wn plan|r — " .. ((ns.L and ns.L["CMD_PLANS"]) or "Toggle Plans Tracker window"))
        addon:Print("  |cff00ccff/wn options|r — " .. ((ns.L and ns.L["CMD_OPTIONS"]) or "Open settings"))
        addon:Print("  |cff00ccff/wn minimap|r — " .. ((ns.L and ns.L["CMD_MINIMAP"]) or "Toggle minimap button"))
        addon:Print("  |cff00ccff/wn debug|r — " .. ((ns.L and ns.L["CMD_DEBUG"]) or "Toggle debug mode"))
        addon:Print("  |cff00ccff/wn trycounterdebug|r — Toggle try counter loot debug (no rep/currency spam)")
        addon:Print("  |cff00ccff/wn stonevaultdebug|r — Stonevault Mechsuit try count diagnostic")
        addon:Print("  |cff00ccff/wn profiler|r — " .. ((ns.L and ns.L["CMD_PROFILER"]) or "Performance profiler"))
        addon:Print("  |cff00ccff/wn toydebug <itemID>|r — Toy tooltip/source debug (prints to chat)")
        addon:Print("  |cff00ccff/wn firstcraft|r — " .. ((ns.L and ns.L["CMD_FIRSTCRAFT"]) or "List first-craft bonus recipes per expansion (open profession first)"))
        addon:Print("  |cff00ccff/wn profverify|r — Print profession Knowledge/Recipes/First Craft/Equipment (open profession K first to verify)")
        addon:Print("  |cff00ccff/wn chartest|r — Print current character's race/class API data (for icon debugging)")
        addon:Print("  |cff00ccff/wn gearupgradedebug|r — Print upgrade costs (API) and affordability per slot (current char)")
        addon:Print("  |cff00ccff/wn gearstoragedebug|r — Scan storage upgrades for all tracked characters/slots")
        addon:Print("  |cff00ccff/wn help|r — " .. ((ns.L and ns.L["CMD_HELP"]) or "Show this list"))
        if addon.db and addon.db.profile and addon.db.profile.debugMode then
            addon:Print("  |cff00ccff/wn changelog|r — " .. ((ns.L and ns.L["CMD_CHANGELOG"]) or "Show changelog"))
            addon:Print("  |cff00ccff/wn trydebug|r — Try counter state and source resolution simulation")
            addon:Print("  |cff00ccff/wn bountydebug|r — Print Special Assignment bounty API results for Midnight maps")
            addon:Print("  |cff00ccff/wn trycount <type> <id>|r — Check try count for a collectible")
            addon:Print("  |cff00ccff/wn check|r — Check what drops from your current target/mouseover")
            addon:Print("  |cff00ccff/wn testevents [type] [id]|r — Test notification events (e.g. reputation valeera)")
            addon:Print("  |cff00ccff/wn testloot [type] [id]|r — Test notification popups (criteria, vaultprogress, achievement, etc.; use help for list)")
        end
        return
    end
    
    -- ── Public commands (always available) ──
    
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        addon:ShowMainWindow()
        return
        
    elseif cmd == "plans" or cmd == "plan" then
        if addon.TogglePlansTrackerWindow then
            addon:TogglePlansTrackerWindow()
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["PLANS_NOT_AVAILABLE"]) or "Plans Tracker not available.") .. "|r")
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
        
        
    elseif cmd == "debug" then
        CommandService:HandleDebugToggle(addon)
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
        
    elseif cmd == "profiler" or cmd == "prof" or cmd == "perf" then
        if ns.Profiler then
            local _, subCmd, arg3 = addon:GetArgs(input, 3)
            ns.Profiler:HandleCommand(addon, subCmd, arg3)
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["PROFILER_NOT_LOADED"]) or "Profiler module not loaded.") .. "|r")
        end
        return

    elseif cmd == "stonevaultdebug" or cmd == "svdebug" then
        -- Stonevault Mechsuit: try count = statistic + local (Quest Starter = Mount Item = Mount)
        local db = addon.db and addon.db.global and addon.db.global.tryCounts
        local tc = db and db.mount or {}
        local ti = db and db.item or {}
        local ok, statVal = pcall(GetStatistic, 20500)
        if not ok then statVal = nil end
        addon:Print("|cff9370DB[Stonevault]|r statistic(20500)=" .. tostring(statVal) .. " | local item[226683]=" .. tostring(ti[226683]) .. " mount[2119]=" .. tostring(tc[2119]) .. " mount[221765]=" .. tostring(tc[221765]))
        addon:Print("|cff9370DB[Stonevault]|r GetTryCount = statistic + local => " .. tostring(addon:GetTryCount("mount", 2119)))
        return

    elseif cmd == "toydebug" or cmd == "toyinfo" then
        -- Always available: dump toy tooltip lines to chat (no debug mode required)
        CommandService:ToyDebugReport(addon, input)
        return

    elseif cmd == "firstcraft" or cmd == "fc" then
        -- Profession: list first-craft bonus recipes per content (expansion). Requires profession window open.
        if ns.ProfessionService and addon.PrintFirstCraftRecipesByContent then
            addon:PrintFirstCraftRecipesByContent()
        else
            addon:Print("|cffff6600[WN]|r " .. (ns.L and ns.L["PROF_FIRSTCRAFT_NO_DATA"] or "Professions module not available."))
        end
        return

    elseif cmd == "profverify" or cmd == "pv" then
        -- Profession: print Knowledge, Recipes, First Craft, Equipment for current char (open profession window first for live data).
        if addon.PrintProfessionVerify then
            addon:PrintProfessionVerify()
        else
            addon:Print("|cffff6600[WN]|r Profession verify not available.")
        end
        return

    elseif cmd == "chartest" or cmd == "charapi" then
        -- Character API test: print current character's race/class data as returned by the game API
        CommandService:CharacterAPITest(addon)
        return

    elseif cmd == "gearupgradedebug" or cmd == "geardebug" then
        if addon.GearUpgradeDebugReport then
            addon:GearUpgradeDebugReport()
        else
            addon:Print("|cffff6600[WN]|r Gear module not loaded.")
        end
        return
    elseif cmd == "gearstoragedebug" or cmd == "storagegeardebug" or cmd == "storagedebug" then
        if addon.GearStorageUpgradeDebugReportAll then
            addon:GearStorageUpgradeDebugReportAll()
        else
            addon:Print("|cffff6600[WN]|r Gear module not loaded.")
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
        
    elseif cmd == "changelog" or cmd == "changes" or cmd == "whatsnew" then
        if addon.ShowUpdateNotification and ns.CHANGELOG then
            local ok, err = pcall(function()
                addon:ShowUpdateNotification({
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "2.4.3",
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

    elseif cmd == "bountydebug" then
        CommandService:BountyDebugReport(addon)
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
        
        local validTypes = { item = true, mount = true, pet = true, toy = true }
        if not validTypes[collectibleType:lower()] then
            addon:Print("|cffff6600Invalid type:|r Must be one of: item, mount, pet, toy")
            return
        end
        
        local count = addon:GetTryCount(collectibleType:lower(), id)
        addon:Print(string.format("|cff9370DB[Try Count]|r %s |cff00ccff%d|r = |cffffff00%d attempts|r", 
            collectibleType:lower(), id, count))
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
-- BOUNTY / SPECIAL ASSIGNMENT DEBUG
--============================================================================

--- Print GetBountySetInfoForMapID and GetBountiesForMapID for Midnight maps.
--- Usage: /wn bountydebug (requires debug mode)
---@param addon table WarbandNexus addon instance
function CommandService:BountyDebugReport(addon)
    local MIDNIGHT_MAPS = {
        [2393] = "Silvermoon",
        [2395] = "Eversong Woods",
        [2424] = "Isle of Quel'Danas",
        [2413] = "Harandar",
        [2437] = "Zul'Aman",
        [2405] = "Voidstorm",
    }
    addon:Print("|cff9370DB[WN BountyDebug]|r Special Assignment API for Midnight maps:")
    for mapID, zoneName in pairs(MIDNIGHT_MAPS) do
        addon:Print("  |cff00ccff" .. zoneName .. "|r (mapID=" .. mapID .. "):")
        if C_QuestLog and C_QuestLog.GetBountySetInfoForMapID then
            local ok, d1, lockQuestID, bountySetID, isActivity = pcall(C_QuestLog.GetBountySetInfoForMapID, mapID)
            if ok then
                addon:Print("    GetBountySetInfoForMapID: lockQuestID=" .. tostring(lockQuestID) .. " bountySetID=" .. tostring(bountySetID))
            else
                addon:Print("    GetBountySetInfoForMapID: |cffff0000error|r " .. tostring(d1))
            end
        end
        if C_QuestLog and C_QuestLog.GetBountiesForMapID then
            local ok, bounties = pcall(C_QuestLog.GetBountiesForMapID, mapID)
            if ok and type(bounties) == "table" then
                addon:Print("    GetBountiesForMapID: " .. #bounties .. " bounty(ies)")
                for i = 1, #bounties do
                    local b = bounties[i]
                    if b and b.questID then
                        local title = "?"
                        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                            local t = C_QuestLog.GetTitleForQuestID(b.questID)
                            if t and (not issecretvalue or not issecretvalue(t)) then title = t end
                        end
                        addon:Print("      questID=" .. b.questID .. " title=" .. tostring(title))
                    end
                end
            else
                addon:Print("    GetBountiesForMapID: " .. (ok and "0 bounties" or "error " .. tostring(bounties)))
            end
        end
        if C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(mapID)
            if info and info.parentMapID and info.parentMapID > 0 then
                addon:Print("    parentMapID=" .. info.parentMapID)
            end
        end
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
            if left and type(left) == "string" and left ~= "" and (not _issecretvalue or not _issecretvalue(left)) and line.type == 2 then
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
                if left and type(left) == "string" and (not _issecretvalue or not _issecretvalue(left)) and left:find(sourceLabelClean, 1, true) then
                    pickedLine = i
                    pickReason = "left contains Source label"
                    break
                end
                if right and type(right) == "string" and (not _issecretvalue or not _issecretvalue(right)) and right:find(sourceLabelClean, 1, true) then
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
                local leftOk = left and type(left) == "string" and (not _issecretvalue or not _issecretvalue(left))
                local rightOk = right and type(right) == "string" and (not _issecretvalue or not _issecretvalue(right))
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
-- CHARACTER API TEST
--============================================================================

--- Print current character's race/class data as returned by the game API (for debugging race icon etc.)
---@param addon table WarbandNexus addon instance
function CommandService:CharacterAPITest(addon)
    local issecretvalue = _G.issecretvalue
    local function safeStr(val)
        if val == nil then return "nil" end
        if issecretvalue and issecretvalue(val) then return "(secret)" end
        return tostring(val)
    end

    addon:Print("|cff00ccff[WN] Character API (player)|r")
    addon:Print("  |cffaaaaaaUnitRace|r:")
    local raceLoc, raceFile = UnitRace("player")
    addon:Print("    localized = " .. safeStr(raceLoc) .. "  |  raceFile (English) = " .. safeStr(raceFile))
    addon:Print("  |cffaaaaaaUnitSex|r: " .. tostring(UnitSex("player")) .. " (1=unknown, 2=male, 3=female)")
    addon:Print("  |cffaaaaaaUnitClass|r:")
    local classLoc, classFile, classID = UnitClass("player")
    addon:Print("    className = " .. safeStr(classLoc) .. "  |  classFile = " .. safeStr(classFile) .. "  |  classID = " .. tostring(classID))
    if C_PlayerInfo and C_PlayerInfo.GetRaceInfo then
        addon:Print("  |cffaaaaaaC_PlayerInfo.GetRaceInfo()|r:")
        local raceInfo = C_PlayerInfo.GetRaceInfo()
        if raceInfo then
            addon:Print("    raceName = " .. safeStr(raceInfo.raceName) .. "  |  clientFileString = " .. safeStr(raceInfo.clientFileString) .. "  |  raceID = " .. safeStr(raceInfo.raceID))
        else
            addon:Print("    (nil)")
        end
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
