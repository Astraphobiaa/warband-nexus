--[[
    Warband Nexus - Window Factory
    
    Unified external window/dialog system with modern UI conventions.
    
    Provides:
    - Standardized dialog/popup creation
    - Duplicate prevention
    - Draggable headers
    - Click outside to close
    - ESC key to close
    - Modern styling with borders
    - Close button with icon
    
    Extracted from SharedWidgets.lua (174 lines)
    Location: Lines 2189-2362
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
-- Import dependencies from namespace
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local FontManager = ns.FontManager
local CreateIcon = ns.UI_CreateIcon

--============================================================================
-- RUNTIME DEPENDENCY VALIDATION
--============================================================================

local function ValidateDependencies()
    local missing = {}
    
    if not COLORS then table.insert(missing, "UI_COLORS") end
    if not ApplyVisuals then table.insert(missing, "UI_ApplyVisuals") end
    if not FontManager then table.insert(missing, "FontManager") end
    if not CreateIcon then table.insert(missing, "UI_CreateIcon") end
    
    if #missing > 0 then
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Missing dependencies: " .. table.concat(missing, ", "))
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Ensure SharedWidgets.lua loads before WindowFactory.lua in .toc")
        return false
    end
    
    return true
end

-- Defer validation to first use (allows SharedWidgets to complete loading)
-- Dependencies checked at runtime in CreateExternalWindow function

--============================================================================
-- EXTERNAL WINDOW SYSTEM
--============================================================================

---Creates a standardized external window/dialog with modern UI features
---@param config table Configuration table
---@field name string Unique dialog name (required)
---@field title string Dialog title (required)
---@field icon string Icon path/atlas (required)
---@field width number|nil Width in pixels (default 400)
---@field height number|nil Height in pixels (default 300)
---@field iconIsAtlas boolean|nil If true, icon is an atlas name (default false)
---@field onClose function|nil Callback when dialog closes
---@field preventDuplicates boolean|nil Prevent multiple instances (default true)
---@return Frame|nil dialog Main dialog frame
---@return Frame|nil contentFrame Frame where you add your content
---@return Frame|nil header Header frame (for custom additions)
local function CreateExternalWindow(config)
    -- Runtime dependency check (deferred to first use)
    if not COLORS or not ApplyVisuals or not FontManager or not CreateIcon then
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Missing dependencies - SharedWidgets not loaded")
        return nil
    end
    
    -- Validate config
    if not config or not config.name or not config.title or not config.icon then
        error("CreateExternalWindow: name, title, and icon are required")
        return nil
    end
    
    local globalName = "WarbandNexus_" .. config.name
    local width = config.width or 400
    local height = config.height or 300
    local preventDuplicates = (config.preventDuplicates ~= false) -- default true
    
    -- Prevent duplicates
    if preventDuplicates then
        if _G[globalName] and _G[globalName]:IsShown() then
            return nil -- Already open
        end
    end
    
    -- Create dialog frame
    local dialog = CreateFrame("Frame", globalName, UIParent)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(dialog, {0.05, 0.05, 0.07, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    
    -- Header bar
    local header = CreateFrame("Frame", nil, dialog)
    header:SetHeight(45)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    
    -- Apply header border
    if ApplyVisuals then
        ApplyVisuals(header, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
    end
    
    -- Make header draggable
    header:EnableMouse(true)
    header:SetMovable(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)
    
    -- Icon (support both texture and atlas)
    local iconIsAtlas = config.iconIsAtlas or false
    local iconFrame = CreateIcon(header, config.icon, 28, iconIsAtlas, nil, true)
    iconFrame:SetPoint("LEFT", 12, 0)
    iconFrame:Show()  -- CRITICAL: Show the header icon!
    
    -- Title
    local titleText = FontManager:CreateFontString(header, "title", "OVERLAY")
    titleText:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    titleText:SetText("|cffffffff" .. config.title .. "|r")
    
    -- Close button (X) - Factory pattern with atlas icon
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply custom visuals (dark background, accent border)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    
    -- Close function
    local function CloseDialog()
        if config.onClose then
            config.onClose()
        end
        dialog:Hide()
        dialog:SetParent(nil)
        _G[globalName] = nil
    end
    
    closeBtn:SetScript("OnClick", CloseDialog)
    
    -- Content frame (where users add their content)
    local contentFrame = CreateFrame("Frame", nil, dialog)
    contentFrame:SetPoint("TOPLEFT", 8, -53) -- Below header
    contentFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Click outside to close (using OnUpdate to detect clicks)
    local clickOutsideFrame = CreateFrame("Frame", nil, UIParent)
    clickOutsideFrame:SetAllPoints()
    clickOutsideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickOutsideFrame:SetFrameLevel(99) -- Just below dialog
    clickOutsideFrame:EnableMouse(true)
    clickOutsideFrame:SetScript("OnMouseDown", function()
        CloseDialog()
    end)
    
    -- Hide click outside frame when dialog is hidden
    dialog:SetScript("OnHide", function()
        clickOutsideFrame:Hide()
        if config.onClose then
            config.onClose()
        end
    end)
    
    dialog:SetScript("OnShow", function()
        clickOutsideFrame:Show()
    end)
    
    -- Close on Escape (combat-safe: SetPropagateKeyboardInput is protected in 12.0)
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            CloseDialog()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)
    
    -- Store close function
    dialog.Close = CloseDialog
    
    return dialog, contentFrame, header
end

--============================================================================
-- ACHIEVEMENT CRITERIA POPUP (Shared, pooled frame)
--============================================================================

local achievementPopup = nil  -- Single shared frame, reused across clicks

local function ShowAchievementPopup(achievementID, anchorFrame)
    if not achievementID or not anchorFrame then return end
    
    -- Toggle: if popup is already showing this achievement, close it
    if achievementPopup and achievementPopup:IsShown() and achievementPopup._currentID == achievementID then
        achievementPopup:Hide()
        return
    end
    
    local L = ns.L
    
    -- Resolve achievement info
    local ok, id, name, points, completed, month, day, year, description, flags, icon,
          rewardText, isGuild, wasEarnedByMe, earnedBy = pcall(GetAchievementInfo, achievementID)
    if not ok or not name then return end
    
    local POPUP_WIDTH = 340
    local PADDING = 14
    local ICON_SIZE = 40
    local BTN_HEIGHT = 26
    local BTN_WIDTH = 90
    local CONTENT_WIDTH = POPUP_WIDTH - (2 * PADDING)
    local NAME_WIDTH = CONTENT_WIDTH - ICON_SIZE - 10
    
    -- Create shared frame on first use
    if not achievementPopup then
        local popup = CreateFrame("Frame", "WarbandNexus_AchievementPopup", UIParent)
        popup:SetSize(POPUP_WIDTH, 180)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(200)
        popup:EnableMouse(true)
        if not InCombatLockdown() then
            popup:EnableKeyboard(true)
            popup:SetPropagateKeyboardInput(true)
        end
        
        if ApplyVisuals then
            ApplyVisuals(popup, {0.05, 0.05, 0.07, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9})
        end
        
        -- Register with UISpecialFrames for native ESC-to-close
        tinsert(UISpecialFrames, "WarbandNexus_AchievementPopup")
        
        -- Click-outside dismiss: check popup AND all child buttons
        local function IsMouseOverPopup(frame)
            if frame:IsMouseOver() then return true end
            if frame._trackBtn and frame._trackBtn:IsMouseOver() then return true end
            if frame._addBtn and frame._addBtn:IsMouseOver() then return true end
            return false
        end
        
        popup._mouseWasDown = false
        popup:SetScript("OnUpdate", function(self)
            if not self:IsShown() then return end
            local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            -- Detect mouse-down edge (transition from up to down)
            if isDown and not self._mouseWasDown then
                if not IsMouseOverPopup(self) then
                    self:Hide()
                end
            end
            self._mouseWasDown = isDown
        end)
        
        -- Icon
        popup._icon = popup:CreateTexture(nil, "ARTWORK")
        popup._icon:SetSize(ICON_SIZE, ICON_SIZE)
        popup._icon:SetPoint("TOPLEFT", PADDING, -PADDING)
        
        -- Name (right of icon, top-aligned; status icon is prepended to text)
        popup._name = FontManager:CreateFontString(popup, "title", "OVERLAY")
        popup._name:SetPoint("TOPLEFT", popup._icon, "TOPRIGHT", 10, 0)
        popup._name:SetJustifyH("LEFT")
        popup._name:SetWordWrap(true)
        popup._name:SetMaxLines(2)
        popup._name:SetWidth(NAME_WIDTH)
        
        -- Points line (below name)
        popup._points = FontManager:CreateFontString(popup, "body", "OVERLAY")
        popup._points:SetPoint("TOPLEFT", popup._name, "BOTTOMLEFT", 0, -3)
        popup._points:SetJustifyH("LEFT")
        popup._points:SetWidth(NAME_WIDTH)
        
        -- Separator line
        popup._separator = popup:CreateTexture(nil, "ARTWORK")
        popup._separator:SetHeight(1)
        popup._separator:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4)
        
        -- Description
        popup._desc = FontManager:CreateFontString(popup, "body", "OVERLAY")
        popup._desc:SetJustifyH("LEFT")
        popup._desc:SetWordWrap(true)
        popup._desc:SetMaxLines(6)
        popup._desc:SetSpacing(2)
        popup._desc:SetWidth(CONTENT_WIDTH)
        
        -- Reward text
        popup._reward = FontManager:CreateFontString(popup, "body", "OVERLAY")
        popup._reward:SetPoint("TOPLEFT", popup._desc, "BOTTOMLEFT", 0, -6)
        popup._reward:SetJustifyH("LEFT")
        popup._reward:SetWordWrap(true)
        popup._reward:SetMaxLines(2)
        popup._reward:SetWidth(CONTENT_WIDTH)
        
        -- Button row (Track + Add)
        popup._trackBtn = CreateFrame("Button", nil, popup)
        popup._trackBtn:SetSize(BTN_WIDTH, BTN_HEIGHT)
        popup._trackBtn:SetPoint("BOTTOMLEFT", PADDING, 10)
        if ApplyVisuals then
            ApplyVisuals(popup._trackBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        popup._trackLabel = FontManager:CreateFontString(popup._trackBtn, "body", "OVERLAY")
        popup._trackLabel:SetPoint("CENTER")
        popup._trackBtn:SetScript("OnEnter", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.18, 0.18, 0.22, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}) end
        end)
        popup._trackBtn:SetScript("OnLeave", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}) end
        end)
        
        popup._addBtn = CreateFrame("Button", nil, popup)
        popup._addBtn:SetSize(BTN_WIDTH, BTN_HEIGHT)
        popup._addBtn:SetPoint("LEFT", popup._trackBtn, "RIGHT", 8, 0)
        if ApplyVisuals then
            ApplyVisuals(popup._addBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        popup._addLabel = FontManager:CreateFontString(popup._addBtn, "body", "OVERLAY")
        popup._addLabel:SetPoint("CENTER")
        popup._addBtn:SetScript("OnEnter", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.18, 0.18, 0.22, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}) end
        end)
        popup._addBtn:SetScript("OnLeave", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}) end
        end)
        
        achievementPopup = popup
    end
    
    local popup = achievementPopup
    
    -- Populate data
    popup._currentID = achievementID
    popup._icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    
    -- Title: status icon + achievement name + (Planned) indicator
    local statusIcon = completed
        and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"
        or  "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"
    local nameColor = completed and "|cff44ff44" or "|cffffffff"
    local plannedTag = ""
    local WarbandNexus = ns.WarbandNexus
    if WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievementID) then
        local plannedWord = (L and L["PLANNED"]) or "Planned"
        plannedTag = " |cffffcc00(" .. plannedWord .. ")|r"
    end
    popup._name:SetText(statusIcon .. " " .. nameColor .. (name or "Unknown") .. "|r" .. plannedTag)
    
    -- Points line
    if points and points > 0 then
        local ptsFormat = L["ACHIEVEMENT_POINTS_FORMAT"] or "%d pts"
        popup._points:SetText("|cffffd700" .. string.format(ptsFormat, points) .. "|r")
        popup._points:Show()
    else
        popup._points:SetText("")
        popup._points:Hide()
    end
    
    -- Calculate header height using explicit widths (accurate on first render)
    local nameHeight = popup._name:GetStringHeight() or 16
    local pointsHeight = popup._points:IsShown() and ((popup._points:GetStringHeight() or 14) + 3) or 0
    local headerBottom = PADDING + math.max(ICON_SIZE, nameHeight + pointsHeight) + 8
    
    -- Position separator below header
    popup._separator:ClearAllPoints()
    popup._separator:SetPoint("TOPLEFT", popup, "TOPLEFT", PADDING, -headerBottom)
    popup._separator:SetPoint("RIGHT", popup, "RIGHT", -PADDING, 0)
    
    -- Description below separator
    local contentTop = headerBottom + 8
    popup._desc:ClearAllPoints()
    popup._desc:SetPoint("TOPLEFT", PADDING, -contentTop)
    
    if description and description ~= "" then
        popup._desc:SetText("|cffdddddd" .. description .. "|r")
        popup._desc:Show()
    else
        popup._desc:SetText("")
        popup._desc:Hide()
    end
    
    -- Reward below description
    if rewardText and rewardText ~= "" then
        popup._reward:SetText("|cffffcc00" .. (L["REWARD_LABEL"] or "Reward:") .. "|r |cffffffff" .. rewardText .. "|r")
        popup._reward:Show()
    else
        popup._reward:SetText("")
        popup._reward:Hide()
    end
    
    -- Track button
    local CT_ACHIEVEMENT = 2
    if completed then
        popup._trackLabel:SetText("|cff888888" .. (L["TRACK"] or "Track") .. "|r")
        popup._trackBtn:SetScript("OnClick", nil)
        popup._trackBtn:SetAlpha(0.4)
        popup._trackBtn:SetScript("OnEnter", nil)
        popup._trackBtn:SetScript("OnLeave", nil)
    else
        popup._trackBtn:SetAlpha(1)
        local function IsTracked()
            if C_ContentTracking and C_ContentTracking.IsTracking then
                local okTrack, result = pcall(C_ContentTracking.IsTracking, CT_ACHIEVEMENT, achievementID)
                if okTrack then return result end
            end
            return false
        end
        local function UpdateTrackLabel()
            if IsTracked() then
                popup._trackLabel:SetText("|cff44ff44" .. (L["TRACKED"] or "Tracked") .. "|r")
            else
                popup._trackLabel:SetText("|cffffcc00" .. (L["TRACK"] or "Track") .. "|r")
            end
        end
        UpdateTrackLabel()
        popup._trackBtn:SetScript("OnClick", function()
            if C_ContentTracking and C_ContentTracking.ToggleTracking then
                local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 0
                pcall(C_ContentTracking.ToggleTracking, CT_ACHIEVEMENT, achievementID, stopType)
            end
            UpdateTrackLabel()
        end)
        popup._trackBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
        popup._trackBtn:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
    end
    
    -- Add button
    local WarbandNexus = ns.WarbandNexus
    if completed then
        popup._addLabel:SetText("|cff888888" .. (L["ADD_PLAN"] or "Add") .. "|r")
        popup._addBtn:SetScript("OnClick", nil)
        popup._addBtn:SetAlpha(0.4)
        popup._addBtn:SetScript("OnEnter", nil)
        popup._addBtn:SetScript("OnLeave", nil)
    else
        popup._addBtn:SetAlpha(1)
        local isPlanned = WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievementID)
        if isPlanned then
            popup._addLabel:SetText("|cff44ff44" .. (L["ADDED"] or "Added") .. "|r")
            popup._addBtn:SetScript("OnClick", nil)
        else
            popup._addLabel:SetText("|cffffcc00+ " .. (L["ADD_PLAN"] or "Add") .. "|r")
            popup._addBtn:SetScript("OnClick", function()
                if WarbandNexus and WarbandNexus.AddPlan then
                    WarbandNexus:AddPlan({
                        type = "achievement",
                        achievementID = achievementID,
                        name = name,
                        icon = icon,
                        points = points,
                    })
                    popup:Hide()
                    if WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end
            end)
        end
        popup._addBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
        popup._addBtn:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
    end
    
    -- Calculate total height and size the popup
    local function RecalculateSize()
        local descH = popup._desc:IsShown() and (popup._desc:GetStringHeight() or 14) or 0
        local rewardH = popup._reward:IsShown() and ((popup._reward:GetStringHeight() or 0) + 6) or 0
        local total = contentTop + descH + rewardH + 12 + BTN_HEIGHT + 16
        popup:SetSize(POPUP_WIDTH, math.max(130, total))
    end
    RecalculateSize()
    
    -- Anchor near the clicked element
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    popup:SetClampedToScreen(true)
    popup._mouseWasDown = true  -- Prevent immediate dismiss (mouse is down from the click that opened us)
    popup:Show()
    popup:Raise()
    
    -- Recalculate after layout pass to fix first-render sizing
    C_Timer.After(0, function()
        if popup:IsShown() then
            RecalculateSize()
        end
    end)
end

local function HideAchievementPopup()
    if achievementPopup and achievementPopup:IsShown() then
        achievementPopup:Hide()
    end
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_CreateExternalWindow = CreateExternalWindow
ns.UI_ShowAchievementPopup = ShowAchievementPopup
ns.UI_HideAchievementPopup = HideAchievementPopup

-- Module loaded - verbose logging removed
