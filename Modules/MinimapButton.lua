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
    local totalGoldLbl = (ns.L and ns.L["TOTAL_GOLD_LABEL"]) or "Total Gold:"
    local charsLbl = (ns.L and ns.L["CHARACTERS_COLON"]) or "Characters:"
    local leftClickLbl = (ns.L and ns.L["LEFT_CLICK_TOGGLE"]) or "Left-Click: Toggle window"
    local rightClickLbl = (ns.L and ns.L["RIGHT_CLICK_PLANS"]) or "Right-Click: Open Plans"
    
    -- Create DataBroker object
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = "Warband Nexus",
        icon = "Interface\\AddOns\\WarbandNexus\\Media\\icon",
        
        -- Left-click: Toggle main window
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                addon:ToggleMainWindow()
            elseif button == "RightButton" then
                addon:ShowMinimapMenu()
            end
        end,
        
        -- Tooltip (Total Gold + Char Count, no Last Scan)
        OnTooltipShow = function(tooltip)
            if not tooltip or not tooltip.AddLine then return end

            tooltip:SetText("|cff6a0dad[Warband Nexus]|r", 1, 1, 1)
            tooltip:AddLine(" ")

            -- Total gold across all characters
            local totalGold = 0
            if addon.db.global.characters then
                for _, charData in pairs(addon.db.global.characters) do
                    totalGold = totalGold + ns.Utilities:GetCharTotalCopper(charData)
                end
            end
            tooltip:AddDoubleLine(totalGoldLbl, addon:API_FormatMoney(totalGold), 1, 1, 1, 1, 0.82, 0)

            -- Character count
            local charCount = 0
            if addon.db.global.characters then
                for _ in pairs(addon.db.global.characters) do
                    charCount = charCount + 1
                end
            end
            tooltip:AddDoubleLine(charsLbl, tostring(charCount), 1, 1, 1, 1, 1, 1)

            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00ff00" .. leftClickLbl .. "|r", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cff00ff00" .. rightClickLbl .. "|r", 0.7, 0.7, 0.7)
        end,

        OnEnter = function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
            GameTooltip:SetText("|cff6a0dad[Warband Nexus]|r", 1, 1, 1)
            GameTooltip:AddLine(" ")

            local totalGold = 0
            if addon.db.global.characters then
                for _, charData in pairs(addon.db.global.characters) do
                    totalGold = totalGold + ns.Utilities:GetCharTotalCopper(charData)
                end
            end
            GameTooltip:AddDoubleLine(totalGoldLbl, addon:API_FormatMoney(totalGold), 1, 1, 1, 1, 0.82, 0)

            local charCount = 0
            if addon.db.global.characters then
                for _ in pairs(addon.db.global.characters) do
                    charCount = charCount + 1
                end
            end
            GameTooltip:AddDoubleLine(charsLbl, tostring(charCount), 1, 1, 1, 1, 1, 1)

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00" .. leftClickLbl .. "|r", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ff00" .. rightClickLbl .. "|r", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end,
        
        OnLeave = function()
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
end

-- ============================================================================
-- RIGHT-CLICK MENU
-- ============================================================================

--[[
    Show right-click context menu
    Provides quick access to common actions
]]
function WarbandNexus:ShowMinimapMenu()
    -- Modern TWW 11.0+ menu system
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(UIParent, function(ownerRegion, rootDescription)
            -- Header
            rootDescription:CreateTitle("Warband Nexus")
            
            -- Toggle Window
            rootDescription:CreateButton((ns.L and ns.L["TOGGLE_WINDOW"]) or "Toggle Window", function()
                self:ToggleMainWindow()
            end)
            
            -- Scan Bank (if open)
            local scanButton = rootDescription:CreateButton((ns.L and ns.L["SCAN_BANK_MENU"]) or "Scan Bank", function()
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
            rootDescription:CreateButton((ns.L and ns.L["COLLECTION_PLANS"]) or "Collection Plans", function()
                if self.TogglePlansTrackerWindow then
                    self:TogglePlansTrackerWindow()
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
        self:Print((ns.L and ns.L["USE_COMMANDS_MSG"]) or "Use /wn show, /wn scan, /wn config")
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
