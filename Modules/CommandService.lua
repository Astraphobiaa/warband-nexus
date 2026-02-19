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
        addon:Print("  |cff00ccff/wn changelog|r — " .. ((ns.L and ns.L["CMD_CHANGELOG"]) or "Show changelog"))
        addon:Print("  |cff00ccff/wn debug|r — " .. ((ns.L and ns.L["CMD_DEBUG"]) or "Toggle debug mode"))
        addon:Print("  |cff00ccff/wn profiler|r — " .. ((ns.L and ns.L["CMD_PROFILER"]) or "Performance profiler"))
        addon:Print("  |cff00ccff/wn help|r — " .. ((ns.L and ns.L["CMD_HELP"]) or "Show this list"))
        if addon.db and addon.db.profile and addon.db.profile.debugMode then
            addon:Print("  |cff00ccff/wn trydebug|r — Try counter state and source resolution simulation")
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
        
    elseif cmd == "changelog" or cmd == "changes" or cmd == "whatsnew" then
        if addon.ShowUpdateNotification and ns.CHANGELOG then
            local ok, err = pcall(function()
                addon:ShowUpdateNotification({
                    version = ns.CHANGELOG.version or (ns.Constants and ns.Constants.ADDON_VERSION) or "2.1.0",
                    date = ns.CHANGELOG.date or "",
                    changes = ns.CHANGELOG.changes or {"No changelog available"}
                })
            end)
            if not ok then
                addon:Print("|cffff0000[WN] Changelog error:|r " .. tostring(err))
            end
        end
        return
        
    elseif cmd == "debug" then
        CommandService:HandleDebugToggle(addon)
        return
        
    elseif cmd == "profiler" or cmd == "prof" or cmd == "perf" then
        if ns.Profiler then
            local _, subCmd, arg3 = addon:GetArgs(input, 3)
            ns.Profiler:HandleCommand(addon, subCmd, arg3)
        else
            addon:Print("|cffff6600" .. ((ns.L and ns.L["PROFILER_NOT_LOADED"]) or "Profiler module not loaded.") .. "|r")
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
        
    else
        addon:Print("|cffff6600" .. ((ns.L and ns.L["UNKNOWN_DEBUG_CMD"]) or "Unknown debug command:") .. "|r " .. cmd)
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
