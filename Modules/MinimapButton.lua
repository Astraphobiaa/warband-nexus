--[[
    Warband Nexus - Minimap Button Module
    LibDBIcon integration for easy access
    
    Features:
    - Click to toggle main window
    - Right-click for quick menu
    - Tooltip with summary info
    - Draggable icon position
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

-- ============================================================================
-- DATA BROKER OBJECT
-- ============================================================================

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
    local leftClickLbl  = (L and L["LEFT_CLICK_TOGGLE"])   or "Left-Click: Toggle window"
    local rightClickLbl = (L and L["RIGHT_CLICK_PLANS"])   or "Right-Click: Open Plans"
    local holdShiftLbl  = (L and L["TOOLTIP_HOLD_SHIFT"])  or "  Hold [Shift] for full list"
    
    local FormatGold = ns.UI_FormatGold
    local TOOLTIP_CHAR_LIMIT = 10
    local currentCharKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    
    -- Hidden frame for Shift key polling (LibDBIcon frames don't reliably support OnUpdate)
    local shiftPollFrame = CreateFrame("Frame")
    shiftPollFrame:Hide()
    
    local function UpdateTooltip(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        
        tooltip:SetText("|cff6a0dad[" .. ((L and L["ADDON_NAME"]) or "Warband Nexus") .. "]|r", 1, 1, 1)
        tooltip:AddLine(" ")

        local totalCopper = 0
        local charGoldList = {}
        local showAll = IsShiftKeyDown()
        
        if addon.db.global.characters then
            for charKey, charData in pairs(addon.db.global.characters) do
                local copper
                if charKey == currentCharKey then
                    copper = GetMoney() or 0
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
        
        tooltip:AddDoubleLine("|cffffffff" .. charsGoldLbl .. "|r",  "|cffffff00" .. FormatGold(totalCopper) .. "|r")
        tooltip:AddDoubleLine("|cffffffff" .. warbandGoldLbl .. ":|r", "|cffffff00" .. FormatGold(warbandCopper) .. "|r")
        tooltip:AddDoubleLine("|cffffffff" .. totalGoldLbl .. "|r",  "|cff00ff00" .. FormatGold(totalCopper + warbandCopper) .. "|r")

        tooltip:AddLine(" ")
        tooltip:AddLine("|cff00ff00" .. leftClickLbl .. "|r", 0.7, 0.7, 0.7)
        tooltip:AddLine("|cff00ff00" .. rightClickLbl .. "|r", 0.7, 0.7, 0.7)
        
        tooltip:SetClampedToScreen(true)
    end
    
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = (ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus",
        icon = "Interface\\AddOns\\WarbandNexus\\Media\\icon",
        
        OnClick = function(clickedframe, button)
            if InCombatLockdown() then return end
            if button == "LeftButton" then
                addon:ToggleMainWindow()
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
            
            -- Poll Shift state on a dedicated frame for instant refresh
            shiftPollFrame._lastShift = IsShiftKeyDown()
            shiftPollFrame:SetScript("OnUpdate", function(self)
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
            shiftPollFrame:SetScript("OnUpdate", nil)
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

--[[
    Show/hide minimap button
    @param show boolean - True to show, false to hide
]]
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
        self:Print((ns.L and ns.L["MINIMAP_HIDDEN_MSG"]) or "Minimap button hidden (use /wn minimap to show)")
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

-- ============================================================================
-- RIGHT-CLICK MENU
-- ============================================================================

--[[
    Show right-click context menu
    Provides quick access to common actions
]]
function WarbandNexus:ShowMinimapMenu(anchorFrame)
    -- Modern TWW 11.0+ menu system
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(UIParent, function(ownerRegion, rootDescription)
            local function OpenVaultTrackerView()
                if InCombatLockdown() then return end
                if self.db and self.db.profile then
                    self.db.profile.pveVaultTrackerMode = true
                    self.db.profile.lastTab = "pve"
                end

                if not self.mainFrame or not self.mainFrame:IsShown() then
                    self:ShowMainWindow()
                end

                local mainFrame = self.mainFrame
                if mainFrame then
                    mainFrame.currentTab = "pve"
                    if E and self.SendMessage then
                        self:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
                    end
                end
            end

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
            
            -- Plans Tracker
            rootDescription:CreateButton((ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List", function()
                if self.TogglePlansTrackerWindow then
                    self:TogglePlansTrackerWindow()
                end
            end)

            -- Easy Access (floating shortcut)
            rootDescription:CreateButton((ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access", function()
                if self.OpenVaultButtonQuickMenu then
                    self:OpenVaultButtonQuickMenu(anchorFrame)
                else
                    OpenVaultTrackerView()
                end
            end)

            rootDescription:CreateDivider()

            -- Options
            rootDescription:CreateButton((ns.L and ns.L["OPTIONS_MENU"]) or "Options", function()
                self:OpenOptions()
            end)
            
            -- Hide Minimap Button
            rootDescription:CreateButton((ns.L and ns.L["HIDE_MINIMAP_BUTTON"]) or "Hide Minimap Button", function()
                self:SetMinimapButtonVisible(false)
                self:Print((ns.L and ns.L["MINIMAP_HIDDEN_MSG"]) or "Minimap button hidden (use /wn minimap to show)")
            end)
        end)
    else
        -- Fallback: Show commands
        self:Print((ns.L and ns.L["MENU_UNAVAILABLE_MSG"]) or "Right-click menu unavailable")
        self:Print((ns.L and ns.L["USE_COMMANDS_MSG"]) or "Use /wn show, /wn options, /wn help")
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

--[[
    Slash command for minimap button
    /wn minimap - Toggle minimap button visibility
]]
function WarbandNexus:MinimapSlashCommand()
    self:ToggleMinimapButton()
end
