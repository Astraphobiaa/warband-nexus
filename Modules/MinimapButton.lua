--[[
    Warband Nexus - Minimap Button Module
    LibDBIcon broker for toggle, right-click menu, and draggable position.

    WN_NONUI_UI: `shiftPollFrame` (+ LibDBIcon) owns hidden polling/event frames; unrelated to SharedWidgets tabs.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants and ns.Constants.EVENTS

local issecretvalue = issecretvalue

--- Tooltip line name: prefer DB name; never :match on secret charKey.
local function GetMinimapTooltipCharName(charKey, charData)
    local n = charData and charData.name
    if n and not (issecretvalue and issecretvalue(n)) then return n end
    if charKey and not (issecretvalue and issecretvalue(charKey)) then
        return charKey:match("^([^-]+)") or charKey
    end
    return "?"
end

-- LibDBIcon reference
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBI = LibStub("LibDBIcon-1.0", true)

-- DATA BROKER OBJECT

--[[
    Initialize LibDataBroker object
    This creates the minimap button and defines its behavior
]]
function WarbandNexus:InitializeMinimapButton()
    -- Safety check: Make sure libraries are available
    if not LDB or not LDBI then
        return
    end

    -- Ensure minimap table exists in profile (guards against schema reset wiping defaults)
    if not self.db.profile.minimap then
        self.db.profile.minimap = { hide = false, minimapPos = 220, lock = false }
    end

    -- Store reference to self for callbacks
    local addon = self
    
    -- Localized labels
    local L = ns.L
    local charsGoldLbl  = (L and L["MINIMAP_CHARS_GOLD"])  or "Characters Gold:"
    local warbandGoldLbl = (L and L["HEADER_WARBAND_GOLD"]) or "Warband Gold"
    local totalGoldLbl  = (L and L["TOTAL_GOLD_LABEL"])    or "Total Gold:"
    local function MinimapLeftClickTooltipLine()
        local action = addon.GetMinimapLeftClickAction and addon:GetMinimapLeftClickAction() or "toggle"
        local VB = ns.VaultButton
        if action == "toggle" then
            return (L and L["LEFT_CLICK_TOGGLE"]) or "Left-Click: Toggle window"
        end
        if VB and VB.GetLauncherActionLabel then
            return ((L and L["MINIMAP_LEFT_CLICK_ACTION_FMT"]) or "Left-Click: %s")
                :format(VB.GetLauncherActionLabel(action))
        end
        return (L and L["LEFT_CLICK_TOGGLE"]) or "Left-Click: Toggle window"
    end
    local rightClickLbl = (L and L["MINIMAP_RIGHT_CLICK_MENU"]) or "Right-Click: Menu"
    local holdShiftLbl  = (L and L["TOOLTIP_HOLD_SHIFT"])  or "  Hold [Shift] for full list"
    
    local FormatGold = ns.UI_FormatGold
    local TOOLTIP_CHAR_LIMIT = 10
    local curRaw = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and addon
        and ns.CharacterService:ResolveSubsidiaryCharacterKey(addon, nil))
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
    local curCanon = curRaw
    if curRaw and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        curCanon = ns.Utilities:GetCanonicalCharacterKey(curRaw) or curRaw
    end
    
    -- Hidden frame for Shift key polling (LibDBIcon frames don't reliably support OnUpdate)
    local shiftPollFrame = CreateFrame("Frame")
    shiftPollFrame:Hide()
    
    local function UpdateTooltip(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        
        local addonNamePlain = (L and L["ADDON_NAME"]) or "Warband Nexus"
        local titleHex = "6a0dad"
        local tc = ns.UI_COLORS and ns.UI_COLORS.accent
        if tc and tc[1] and tc[2] and tc[3] then
            local function ch(x)
                return math.max(0, math.min(255, math.floor((tonumber(x) or 0) * 255 + 0.5)))
            end
            titleHex = string.format("%02x%02x%02x", ch(tc[1]), ch(tc[2]), ch(tc[3]))
        end
        tooltip:SetText("|cff" .. titleHex .. "[" .. addonNamePlain .. "]|r", 1, 1, 1)
        tooltip:AddLine(" ")

        local totalCopper = 0
        local charGoldList = {}
        local showAll = IsShiftKeyDown()
        
        if addon.db.global.characters then
            for charKey, charData in pairs(addon.db.global.characters) do
                local copper
                local ckCanon = charKey
                if ns.Utilities.GetCanonicalCharacterKey then
                    ckCanon = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
                end
                if ckCanon == curCanon then
                    copper = ns.Utilities:GetLiveCharacterMoneyCopper(ns.Utilities:GetCharTotalCopper(charData))
                else
                    copper = ns.Utilities:GetCharTotalCopper(charData)
                end
                totalCopper = totalCopper + copper
                local charName = GetMinimapTooltipCharName(charKey, charData)
                local charClass = charData.class or "WARRIOR"
                table.insert(charGoldList, { name = charName, copper = copper, class = charClass })
            end
        end
        
        table.sort(charGoldList, function(a, b) return a.copper > b.copper end)
        
        -- Character list (Shift expands full list)
        local totalChars = #charGoldList
        local displayCount = (showAll or totalChars <= TOOLTIP_CHAR_LIMIT) and totalChars or TOOLTIP_CHAR_LIMIT
        
        for i = 1, displayCount do
            local charInfo = charGoldList[i]
            local classColor = RAID_CLASS_COLORS[charInfo.class]
            local r, g, b = 0.8, 0.8, 0.8
            if classColor then r, g, b = classColor.r, classColor.g, classColor.b end
            tooltip:AddDoubleLine(charInfo.name, FormatGold(charInfo.copper), r, g, b, 1, 0.82, 0)
        end
        
        if not showAll and totalChars > TOOLTIP_CHAR_LIMIT then
            local remaining = totalChars - TOOLTIP_CHAR_LIMIT
            tooltip:AddLine(string.format("|cff888888" .. ((L and L["MINIMAP_MORE_FORMAT"]) or "... +%d more") .. "|r", remaining))
            tooltip:AddLine(holdShiftLbl, 0.5, 0.5, 0.5)
        end
        
        -- Summary: Characters Gold / Warband Gold / Total Gold
        tooltip:AddLine(" ")
        
        local warbandCopper = ns.Utilities:GetWarbandBankMoney() or 0
        if warbandCopper == 0 then
            warbandCopper = ns.Utilities:GetWarbandBankTotalCopper(addon) or 0
        end
        
        local brightHex = (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
        tooltip:AddDoubleLine(brightHex .. charsGoldLbl .. "|r",  "|cffffff00" .. FormatGold(totalCopper) .. "|r")
        tooltip:AddDoubleLine(brightHex .. warbandGoldLbl .. ":|r", "|cffffff00" .. FormatGold(warbandCopper) .. "|r")
        tooltip:AddDoubleLine(brightHex .. totalGoldLbl .. "|r",  "|cff00ff00" .. FormatGold(totalCopper + warbandCopper) .. "|r")

        tooltip:AddLine(" ")
        tooltip:AddLine("|cff00ff00" .. MinimapLeftClickTooltipLine() .. "|r", 0.7, 0.7, 0.7)
        tooltip:AddLine("|cff00ff00" .. rightClickLbl .. "|r", 0.7, 0.7, 0.7)
        
        tooltip:SetClampedToScreen(true)
    end
    
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = (ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus",
        icon = ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga",
        
        OnClick = function(clickedframe, button)
            if InCombatLockdown() then return end
            if button == "LeftButton" then
                if addon.RunMinimapLeftClickAction then
                    addon:RunMinimapLeftClickAction()
                else
                    addon:ToggleMainWindow()
                end
            elseif button == "RightButton" then
                addon:ShowMinimapMenu(clickedframe)
            end
        end,
        
        OnTooltipShow = function(tooltip)
            UpdateTooltip(tooltip)
        end,

        OnEnter = function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
            GameTooltip:SetClampedToScreen(true)
            UpdateTooltip(GameTooltip)
            GameTooltip:Show()
            
            -- Refresh on Shift changes via MODIFIER_STATE_CHANGED (never OnUpdate polling
            -- for event-available state). Tooltip is WN-owned here, so re-driving it is safe.
            shiftPollFrame._lastShift = IsShiftKeyDown()
            shiftPollFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
            shiftPollFrame:SetScript("OnEvent", function(self, _, key)
                if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
                local now = IsShiftKeyDown()
                if now ~= self._lastShift then
                    self._lastShift = now
                    GameTooltip:ClearLines()
                    UpdateTooltip(GameTooltip)
                    GameTooltip:Show()
                end
            end)
            shiftPollFrame:Show()
        end,

        OnLeave = function(frame)
            shiftPollFrame:Hide()
            shiftPollFrame:UnregisterEvent("MODIFIER_STATE_CHANGED")
            shiftPollFrame:SetScript("OnEvent", nil)
            GameTooltip:Hide()
        end,
    })
    
    -- Register with LibDBIcon
    LDBI:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
    
    -- Show/hide based on settings
    if self.db.profile.minimap.hide then
        LDBI:Hide(ADDON_NAME)
    else
        LDBI:Show(ADDON_NAME)
    end
end

function WarbandNexus:SetMinimapButtonVisible(show)
    if not LDBI then return end
    
    if show then
        LDBI:Show(ADDON_NAME)
        self.db.profile.minimap.hide = false
    else
        LDBI:Hide(ADDON_NAME)
        self.db.profile.minimap.hide = true
    end
end

--[[
    Toggle minimap button visibility
]]
function WarbandNexus:ToggleMinimapButton()
    if not LDBI then return end
    
    if self.db.profile.minimap.hide then
        self:SetMinimapButtonVisible(true)
        self:Print((ns.L and ns.L["MINIMAP_SHOWN_MSG"]) or "Minimap button shown")
    else
        self:SetMinimapButtonVisible(false)
        self:Print((ns.L and ns.L["MINIMAP_HIDDEN_MSG"]) or "Minimap button hidden (re-enable under Warband Nexus → Settings → Minimap).")
    end
end

--[[
    Update minimap button tooltip
    Called when data changes (gold, scan time, etc.)
]]
function WarbandNexus:UpdateMinimapTooltip()
    -- Force tooltip refresh if it's currently shown
    if GameTooltip:IsShown() and GameTooltip:GetOwner() then
        local owner = GameTooltip:GetOwner()
        if owner and owner.dataObject and owner.dataObject == ADDON_NAME then
            GameTooltip:ClearLines()
            local dataObj = LDB:GetDataObjectByName(ADDON_NAME)
            if dataObj and dataObj.OnTooltipShow then
                dataObj.OnTooltipShow(GameTooltip)
            end
            GameTooltip:Show()
        end
    end
    -- Note: Uses consolidated UpdateTooltip function via OnTooltipShow callback
end

-- RIGHT-CLICK MENU

--[[
    Show right-click context menu
    Provides quick access to common actions
]]
function WarbandNexus:GetMinimapLeftClickAction()
    local VB = ns.VaultButton
    local action = "toggle"
    if VB and VB.GetMinimapSettings then
        action = VB.GetMinimapSettings().leftClickAction or "toggle"
    elseif self.db and self.db.profile and self.db.profile.minimap then
        action = self.db.profile.minimap.leftClickAction or "toggle"
    end
    if VB and VB.NormalizeMinimapLeftClickAction then
        action = VB.NormalizeMinimapLeftClickAction(action)
    end
    return action
end

function WarbandNexus:RunMinimapLeftClickAction()
    if InCombatLockdown() then return end
    local action = self:GetMinimapLeftClickAction()
    if action == "toggle" then
        self:ToggleMainWindow()
        return
    end
    local VB = ns.VaultButton
    local def = VB and VB.LAUNCHER_ACTION_DEFS and VB.LAUNCHER_ACTION_DEFS[action]
    if def and def.kind == "main_tab" and def.tabKey and self.ShowMainWindow then
        self:ShowMainWindow(def.tabKey)
        return
    end
    if self.RunLauncherAction then
        self:RunLauncherAction(action, nil)
    elseif VB and VB.RunLauncherAction then
        VB.RunLauncherAction(action, nil)
    end
end

function WarbandNexus:ShowMinimapMenu(anchorFrame)
    -- Modern TWW 11.0+ menu system
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(UIParent, function(ownerRegion, rootDescription)
            -- Header
            rootDescription:CreateTitle((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")

            -- Toggle Window
            rootDescription:CreateButton((ns.L and ns.L["TOGGLE_WINDOW"]) or "Toggle Window", function()
                self:ToggleMainWindow()
            end)
            
            -- Scan Bank (if open)
            local scanButton = rootDescription:CreateButton((ns.L and ns.L["SCAN_BANK_MENU"]) or "Scan Bank", function()
                if InCombatLockdown() then return end
                -- GUARD: Only allow bank scan if character is tracked
                if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
                    self:Print((ns.L and ns.L["TRACKING_DISABLED_SCAN_MSG"]) or "Character tracking is disabled. Enable tracking in settings to scan bank.")
                    return
                end
                
                if self.bankIsOpen then
                    -- Scanning bank
                    if self.warbandBankIsOpen and self.ScanWarbandBank then
                        self:ScanWarbandBank()
                    end
                    if self.ScanPersonalBank then
                        self:ScanPersonalBank()
                    end
                    self:Print((ns.L and ns.L["SCAN_COMPLETE_MSG"]) or "Scan complete!")
                else
                    self:Print((ns.L and ns.L["BANK_NOT_OPEN_MSG"]) or "Bank is not open")
                end
            end)
            if not self.bankIsOpen then
                scanButton:SetEnabled(false)
            end
            
            -- Plans Tracker (floating To-Do window)
            rootDescription:CreateButton((ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List", function()
                if self.TogglePlansTrackerWindow then
                    self:TogglePlansTrackerWindow()
                end
            end)

            -- Options
            rootDescription:CreateButton((ns.L and ns.L["OPTIONS_MENU"]) or "Options", function()
                self:OpenOptions()
            end)
            
            -- Hide Minimap Button
            rootDescription:CreateButton((ns.L and ns.L["HIDE_MINIMAP_BUTTON"]) or "Hide Minimap Button", function()
                self:SetMinimapButtonVisible(false)
                self:Print((ns.L and ns.L["MINIMAP_HIDDEN_MSG"]) or "Minimap button hidden (re-enable under Warband Nexus → Settings → Minimap).")
            end)
        end)
    else
        -- Fallback: Show commands
        self:Print((ns.L and ns.L["MENU_UNAVAILABLE_MSG"]) or "Right-click menu unavailable")
        self:Print((ns.L and ns.L["USE_COMMANDS_MSG"]) or "Use /wn show, /wn options, /wn help")
    end
end

-- SLASH COMMANDS

--[[
    Legacy hook: minimap visibility is toggled from Settings → Minimap (no slash command).
]]
function WarbandNexus:MinimapSlashCommand()
    self:ToggleMinimapButton()
end
