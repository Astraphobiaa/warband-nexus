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
    
    -- Store reference to self for callbacks
    local addon = self
    
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
        
        -- Tooltip
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
            
            -- Warband bank gold
            local warbandData = addon.GetWarbandBankV2 and addon:GetWarbandBankV2() or addon.db.global.warbandBank
            local warbandGold = ns.Utilities:GetWarbandBankTotalCopper(addon, warbandData)
            
            tooltip:AddDoubleLine("Total Gold:", addon:API_FormatMoney(totalGold), 1, 1, 0.5, 1, 1, 1)
            tooltip:AddDoubleLine("Warband Bank:", addon:API_FormatMoney(warbandGold), 1, 1, 0.5, 1, 1, 1)
            tooltip:AddLine(" ")
            
            -- Character count
            local charCount = 0
            if addon.db.global.characters then
                for _ in pairs(addon.db.global.characters) do
                    charCount = charCount + 1
                end
            end
            tooltip:AddDoubleLine("Characters:", charCount, 0.7, 0.7, 0.7, 1, 1, 1)
            
            -- Last scan time
            local lastScan = (warbandData and warbandData.lastScan) or 0
            if lastScan > 0 then
                local timeSince = time() - lastScan
                local timeStr
                if timeSince < 60 then
                    timeStr = string.format("%d seconds ago", timeSince)
                elseif timeSince < 3600 then
                    timeStr = string.format("%d minutes ago", math.floor(timeSince / 60))
                else
                    timeStr = string.format("%d hours ago", math.floor(timeSince / 3600))
                end
                tooltip:AddDoubleLine("Last Scan:", timeStr, 0.7, 0.7, 0.7, 1, 1, 1)
            else
                tooltip:AddDoubleLine("Last Scan:", "Never", 0.7, 0.7, 0.7, 1, 0.5, 0.5)
            end
            
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00ff00Left-Click:|r Toggle window", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cff00ff00Right-Click:|r Quick menu", 0.7, 0.7, 0.7)
        end,
        
        OnEnter = function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
            
            -- Show tooltip content
            GameTooltip:SetText("|cff6a0dad[Warband Nexus]|r", 1, 1, 1)
            GameTooltip:AddLine(" ")
            
            -- Total gold across all characters
            local totalGold = 0
            if addon.db.global.characters then
                for _, charData in pairs(addon.db.global.characters) do
                    totalGold = totalGold + ns.Utilities:GetCharTotalCopper(charData)
                end
            end
            
            -- Warband bank gold
            local warbandData2 = addon.GetWarbandBankV2 and addon:GetWarbandBankV2() or addon.db.global.warbandBank
            local warbandGold = (warbandData2 and warbandData2.totalCopper) or 0
            
            GameTooltip:AddDoubleLine("Total Gold:", addon:API_FormatMoney(totalGold), 1, 1, 0.5, 1, 1, 1)
            GameTooltip:AddDoubleLine("Warband Bank:", addon:API_FormatMoney(warbandGold), 1, 1, 0.5, 1, 1, 1)
            GameTooltip:AddLine(" ")
            
            -- Character count
            local charCount = 0
            if addon.db.global.characters then
                for _ in pairs(addon.db.global.characters) do
                    charCount = charCount + 1
                end
            end
            GameTooltip:AddDoubleLine("Characters:", charCount, 0.7, 0.7, 0.7, 1, 1, 1)
            
            -- Last scan time
            local lastScan = (warbandData2 and warbandData2.lastScan) or 0
            if lastScan > 0 then
                local timeSince = time() - lastScan
                local timeStr
                if timeSince < 60 then
                    timeStr = string.format("%d seconds ago", timeSince)
                elseif timeSince < 3600 then
                    timeStr = string.format("%d minutes ago", math.floor(timeSince / 60))
                else
                    timeStr = string.format("%d hours ago", math.floor(timeSince / 3600))
                end
                GameTooltip:AddDoubleLine("Last Scan:", timeStr, 0.7, 0.7, 0.7, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine("Last Scan:", "Never", 0.7, 0.7, 0.7, 1, 0.5, 0.5)
            end
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Left-Click:|r Toggle window", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ff00Right-Click:|r Quick menu", 0.7, 0.7, 0.7)
            
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
        self:Print("Minimap button shown")
    else
        self:SetMinimapButtonVisible(false)
        self:Print("Minimap button hidden (use /wn minimap to show)")
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
            rootDescription:CreateButton("Toggle Window", function()
                self:ToggleMainWindow()
            end)
            
            -- Scan Bank (if open)
            local scanButton = rootDescription:CreateButton("Scan Bank", function()
                if self.bankIsOpen then
                    self:Print("Scanning bank...")
                    if self.warbandBankIsOpen and self.ScanWarbandBank then
                        self:ScanWarbandBank()
                    end
                    if self.ScanPersonalBank then
                        self:ScanPersonalBank()
                    end
                    self:Print("Scan complete!")
                else
                    self:Print("Bank is not open")
                end
            end)
            if not self.bankIsOpen then
                scanButton:SetEnabled(false)
            end
            
            rootDescription:CreateDivider()
            
            -- Options
            rootDescription:CreateButton("Options", function()
                self:OpenOptions()
            end)
            
            -- Hide Minimap Button
            rootDescription:CreateButton("Hide Minimap Button", function()
                self:SetMinimapButtonVisible(false)
                self:Print("Minimap button hidden (use /wn minimap to show)")
            end)
        end)
    else
        -- Fallback: Show commands
        self:Print("Right-click menu unavailable")
        self:Print("Use /wn show, /wn scan, /wn config")
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
