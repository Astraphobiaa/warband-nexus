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

--============================================================================
-- MAIN SLASH COMMAND HANDLER
--============================================================================

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
        addon:Print("|cff00ccffWarband Nexus|r — " .. ((ns.L and ns.L["AVAILABLE_COMMANDS"]) or "Available commands:"))
        addon:Print("  |cff00ccff/wn|r — " .. ((ns.L and ns.L["CMD_OPEN"]) or "Open addon window"))
        addon:Print("  |cff00ccff/wn saved|r — Saved Instances")
        addon:Print("  |cff00ccff/wn todo|r — " .. ((ns.L and ns.L["CMD_PLANS"]) or "To-Do Tracker"))
        addon:Print("  |cff00ccff/wn options|r — " .. ((ns.L and ns.L["CMD_OPTIONS"]) or "Settings"))
        addon:Print("  |cff00ccff/wn keys|r — Announce alt keystones (party)")
        addon:Print("  |cff00ccff/wn changelog|r — " .. ((ns.L and ns.L["CMD_CHANGELOG"]) or "Changelog popup"))
        addon:Print("  |cff00ccff/wn debug|r — " .. ((ns.L and ns.L["CMD_DEBUG"]) or "Toggle debug mode (extra diagnostics)"))
        addon:Print("  |cff00ccff/wn uimap here|r — " .. ((ns.L and ns.L["CMD_UIMAP_HERE"]) or "Current uiMapID + parent chain (no debug)"))
        addon:Print("  |cff00ccff/wn collection sync|r — Refresh if version/categories need work (no wipe)")
        addon:Print("  |cff00ccff/wn collection sync force|r — |cff00ccff/wn collection rescan|r — remount pets/toys/mounts then rescan (no debug)")
        addon:Print("  |cff00ccff/wn collection status|r — Collection store snapshot (counts, loading)")
        addon:Print("  |cff00ccff/wn profiler|r — " .. ((ns.L and ns.L["CMD_PROFILER"]) or "Performance profiler"))
        addon:Print("  |cff00ccff/wn help|r — " .. ((ns.L and ns.L["CMD_HELP"]) or "This list"))
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            addon:Print("|cff888888— With debug ON:|r |cff00ccff/wn dumpitem|r, |cff00ccff/wn uimap catalog|r, |cff00ccff/wn trycounterdebug|r, |cff00ccff/wn trycount|r, |cff00ccff/wn check|r, |cff00ccff/wn track|r, |cff00ccff/wn cleanup|r, |cff00ccff/wn recover|r, |cff00ccff/wn collection rebuild|r")
        end
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
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "3.0.4",
                    date = ns.CHANGELOG.date or "",
                    changes = ns.CHANGELOG.changes or {"No changelog available"}
                })
            end)
            if not ok then
                addon:Print("|cffff0000[WN] Changelog error:|r " .. tostring(err))
            end
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
            if not (IsDebugModeEnabled and IsDebugModeEnabled()) then
                addon:Print("|cffff6600[WN]|r /wn collection rebuild needs |cff00ccff/wn debug|r. Use |cff00ccff/wn collection sync|r to refresh without wiping.|r")
                return
            end
            local full = third and third:lower() == "full"
            if addon.DebugForceCollectionRebuild then
                addon:DebugForceCollectionRebuild(full)
            else
                addon:Print("|cffff6600[WN]|r DebugForceCollectionRebuild not available.|r")
            end
            return
        else
            addon:Print("|cff00ccff/wn collection sync|r — Run EnsureCollectionData when store is incomplete vs code version.")
            addon:Print("|cff00ccff/wn collection sync force|r — same as |cff00ccff/wn collection rescan|r (mount/pet/toy wipe + rescan, no debug).")
            addon:Print("|cff00ccff/wn collection status|r — Print collectionStore counts and loading state.")
            addon:Print("|cff888888With |cff00ccff/wn debug|r:|r |cff00ccff/wn collection rebuild|r [|cff00ccfffull|r] — wipe store + full refetch (profiler friendly).")
            return
        end

    elseif cmd == "debug" then
        CommandService:HandleDebugToggle(addon)
        return

    elseif cmd == "uimap" then
        CommandService:HandleUiMapDebug(addon, input)
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

    end

    -- ── Debug commands (require debug mode) ──
    
    local isDebug = IsDebugModeEnabled and IsDebugModeEnabled()
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
                or ns.Utilities:GetCharacterKey()
            if ns.CharacterService and charKey then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
                addon:Print("|cff00ff00" .. ((ns.L and ns.L["TRACKING_ENABLED_MSG"]) or "Character tracking ENABLED!") .. "|r")
            end
        elseif subCmd == "disable" or subCmd == "off" then
            local charKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(addon))
                or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
                or ns.Utilities:GetCharacterKey()
            if ns.CharacterService and charKey then
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

    else
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_DEBUG_CMD"]) or "Unknown debug command:") .. "|r " .. cmd)
    end
end

--============================================================================
-- UI MAP DEBUG (reminder zone picker / C_Map)
--============================================================================

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
        addon:Print("  |cff00ccff/wn uimap here|r — player map + parents + optional instance (works without debug)")
        addon:Print("  |cff888888(debug ON)|r |cff00ccff/wn uimap catalog [section]|r — rows from ReminderZoneCatalog (omit section = all)")
        addon:Print("  |cff888888(debug ON)|r |cff00ccff/wn uimap id <uiMapID>|r — GetMapInfo + UIMapContentKind.Resolve")
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

    if not IsDebugModeEnabled or not IsDebugModeEnabled() then
        addon:Print("|cffff6600[WN uiMap]|r Enable debug: |cff00ccff/wn debug|r — then retry catalog/id.")
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

--============================================================================
-- ITEM DUMP (debug)
--============================================================================

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
        or (ns.Utilities and ns.Utilities:GetCharacterKey())
    local selData = selKey and db and db.characters and db.characters[selKey]
    if selData then
        p(string.format("Logged-in: name=%s class=%s specID=%s level=%s", tostring(selData.name), tostring(selData.classFile), tostring(selData.specID), tostring(selData.level)))
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

    local mf = addon.mainFrame
    if mf and mf.SyncMainHeaderDebugReloadLayout then
        mf:SyncMainHeaderDebugReloadLayout()
    end
end
