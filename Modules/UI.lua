--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
-- CRITICAL: FontManager is lazy-loaded to prevent initialization errors
local FontManager  -- Will be set on first access
local L = ns.L

-- Unique AceEvent handler identity for UI.lua
-- AceEvent uses events[eventname][self] = handler, so each module needs a unique
-- 'self' table to prevent overwriting other modules' handlers for the same event.
local UIEvents = {}

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- Lazy-load FontManager (prevent race conditions)
local function GetFontManager()
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then
            error("FontManager not available in namespace!")
        end
    end
    return FontManager
end

-- Import shared UI components from SharedWidgets
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor

local format = string.format

-- Layout Constants (computed dynamically)
local CONTENT_MIN_WIDTH = 1280   -- Minimum to fit Statistics 3-card row + character/gear layouts without overflow
local CONTENT_MIN_HEIGHT = 650   -- Multi-level structures minimum
local ROW_HEIGHT = 26

-- Window geometry helpers
local function GetWindowProfile()
    if not WarbandNexus.db or not WarbandNexus.db.profile then return nil end
    return WarbandNexus.db.profile
end

local function GetWindowDimensions()
    local profile = GetWindowProfile()
    if profile and profile.windowWidth then
        local savedWidth = profile.windowWidth
        local savedHeight = profile.windowHeight
        
        -- Validate saved values are within bounds
        local screen = WarbandNexus:API_GetScreenInfo()
        local maxWidth = math.floor(screen.width * 0.95)
        local maxHeight = math.floor(screen.height * 0.95)
        
        savedWidth = math.max(CONTENT_MIN_WIDTH, math.min(savedWidth, maxWidth))
        savedHeight = math.max(CONTENT_MIN_HEIGHT, math.min(savedHeight, maxHeight))
        
        return savedWidth, savedHeight
    end
    
    -- First time: calculate optimal size
    local defaultWidth, defaultHeight = 
        WarbandNexus:API_CalculateOptimalWindowSize(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT)
    
    return defaultWidth, defaultHeight
end

-- Convert frame top-left to UIParent offset space using physical-pixel conversion.
-- This avoids coordinate drift when frame scale differs from UIParent scale.
local function GetFrameTopLeftInParentCoords(frame)
    if not frame then return nil, nil end
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if left == nil or top == nil then return nil, nil end

    -- GetLeft() and GetTop() are already in the frame's effective scale coordinate space.
    -- When using SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y), the x and y offsets
    -- are also interpreted in the frame's effective scale coordinate space.
    -- Therefore, we can use GetLeft/GetTop directly without any scale conversion.
    return left, top
end

-- Save window position and size to DB.
-- Always uses absolute TOPLEFT/BOTTOMLEFT coordinates via GetLeft()/GetTop()
-- to avoid anchor point confusion after StartMoving/StopMovingOrSizing.
local function SaveWindowGeometry(frame)
    if not frame then return end
    local profile = GetWindowProfile()
    if not profile then return end
    
    -- Save size
    profile.windowWidth = frame:GetWidth()
    profile.windowHeight = frame:GetHeight()
    
    -- Save absolute position using GetLeft/GetTop (anchor-independent).
    -- This is immune to anchor point changes caused by StartMoving().
    -- Convert from frame's effective scale to UIParent's coordinate space.
    local left, top = GetFrameTopLeftInParentCoords(frame)
    if left and top then
        if not profile.windowPosition then
            profile.windowPosition = {}
        end
        profile.windowPosition.point = "TOPLEFT"
        profile.windowPosition.relativePoint = "BOTTOMLEFT"
        profile.windowPosition.x = left
        profile.windowPosition.y = top
    end
end

-- Restore window position from DB (returns true if restored, false for first-time)
local function RestoreWindowPosition(frame)
    local profile = GetWindowProfile()
    if not profile or not profile.windowPosition then return false end

    local pos = profile.windowPosition
    if not pos.x or not pos.y then return false end

    -- Validate position is on-screen (clamp to visible area)
    local screen = WarbandNexus:API_GetScreenInfo()
    local frameScale = frame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1
    if frameScale <= 0 then frameScale = 1 end
    if parentScale <= 0 then parentScale = 1 end
    
    -- Get screen dimensions in the frame's coordinate space
    -- screen.width/height are in UIParent's coordinate space.
    local screenWidthInFrameCoords = (screen.width * parentScale) / frameScale
    local screenHeightInFrameCoords = (screen.height * parentScale) / frameScale
    
    local frameW = frame:GetWidth() or 0
    local frameH = frame:GetHeight() or 0
    
    local x = math.max(0, math.min(pos.x, screenWidthInFrameCoords - frameW * 0.25))
    local y = math.max(frameH * 0.25, math.min(pos.y, screenHeightInFrameCoords))

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    return true
end

-- Custom drag: preserves the clicked point under the cursor (no StartMoving teleport).
-- StartMoving() uses the frame's anchor as handle, causing the window to "jump"
-- when clicking anywhere except TOPLEFT. This uses GetCursorPosition + OnUpdate instead.
local function StartCustomDrag(frame)
    if not frame or InCombatLockdown() then return end

    local cx, cy = GetCursorPosition()

    local left = frame:GetLeft()
    local top = frame:GetTop()
    if left == nil or top == nil then return end

    local frameScale = frame:GetEffectiveScale()
    if not frameScale or frameScale <= 0 then frameScale = 1 end

    local leftPx = left * frameScale
    local topPx = top * frameScale

    frame._dragOffsetX = cx - leftPx
    frame._dragOffsetY = cy - topPx
    frame._isCustomDragging = true

    frame:SetScript("OnUpdate", function(self)
        if not self._isCustomDragging then
            self:SetScript("OnUpdate", nil)
            return
        end
        local x, y = GetCursorPosition()
        local newLeftPx = x - self._dragOffsetX
        local newTopPx = y - self._dragOffsetY
        
        -- Convert physical pixels back to the frame's coordinate space
        local newLeft = newLeftPx / frameScale
        local newTop = newTopPx / frameScale
        
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
end

local function StopCustomDrag(frame)
    if not frame then return end
    frame._isCustomDragging = false
    frame._dragOffsetX = nil
    frame._dragOffsetY = nil
    frame:SetScript("OnUpdate", nil)
end

-- Re-anchor frame to its current visual position using TOPLEFT.
-- Ensures consistent anchor state before save/restore.
--
-- IMPORTANT: GetLeft()/GetTop() return coordinates in the frame's effective scale
-- space, but SetPoint offsets are in UIParent's coordinate space. We must convert
-- between the two when they differ (e.g., due to UI scale, custom frame scale).
local function NormalizeFramePosition(frame)
    if not frame or not frame.GetLeft or not frame.GetTop then return end
    local left, top = GetFrameTopLeftInParentCoords(frame)
    if left == nil or top == nil then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Reset window to default center position and size
local function ResetWindowGeometry(frame)
    if not frame then return end
    
    local defaultWidth, defaultHeight = 
        WarbandNexus:API_CalculateOptimalWindowSize(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT)
    
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:SetSize(defaultWidth, defaultHeight)
    
    -- Clear saved position/size
    local profile = GetWindowProfile()
    if profile then
        profile.windowWidth = defaultWidth
        profile.windowHeight = defaultHeight
        profile.windowPosition = nil
    end
    
    -- Refresh content at new size (gear/professions: keep minimum width so content does not squeeze)
    if frame.scrollChild and frame.scroll then
        local w = frame.scroll:GetWidth()
        if frame.currentTab == "gear" and ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0 then
            w = math.max(w, ns.MIN_GEAR_CARD_W)
        end
        if frame.currentTab == "professions" and ns.ComputeProfessionsGridWidth then
            local profW = ns.ComputeProfessionsGridWidth()
            if profW > 0 then w = math.max(w, profW) end
        end
        if frame.currentTab == "pve" and ns.ComputePvEMinScrollWidth then
            local pveW = ns.ComputePvEMinScrollWidth(WarbandNexus)
            if pveW > 0 then w = math.max(w, pveW) end
        end
        frame.scrollChild:SetWidth(w)
        if frame.columnHeaderInner and frame.columnHeaderClip and frame.columnHeaderClip:GetHeight() > 1 then
            frame.columnHeaderInner:SetWidth(w)
        end
    end
    WarbandNexus:PopulateContent()
end

local mainFrame = nil
-- REMOVED: local currentTab - now using mainFrame.currentTab (fixes tab switching bug)
local currentItemsSubTab = "personal" -- Default to Personal Items (Bank + Inventory)
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Hidden frame that collects orphaned non-pooled UI elements.
-- WoW frames are NEVER garbage collected — SetParent(nil) leaves them permanently
-- in memory with a nil parent. The recycleBin gives them a valid hidden parent
-- so they at least have proper frame hierarchy.
local recycleBin = CreateFrame("Frame", "WarbandNexusRecycleBin", UIParent)
recycleBin:Hide()
recycleBin:SetSize(1, 1)
recycleBin:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9999, 9999)
ns.UI_RecycleBin = recycleBin

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_SetItemsSubTab = function(val)
    currentItemsSubTab = val
    -- No longer syncing BankFrame tabs (read-only mode)
end
ns.UI_GetExpandedGroups = function() return expandedGroups end
ns.UI_GetExpandAllActive = function() return WarbandNexus.itemsExpandAllActive end

--============================================================================
-- UI-SPECIFIC HELPERS
--============================================================================
-- (Shared helpers are now imported from SharedWidgets at top of file)

--============================================================================
-- MAIN FUNCTIONS
--============================================================================

-- Clear all search state on main tab change
local function ClearAllSearchBoxes()
    local SSM = ns.SearchStateManager
    if SSM and SSM.ClearSearch then
        -- Clear all known search IDs
        local tabIds = { "items", "gear", "currency", "storage", "reputation", "plans_mount", "plans_pet", "plans_toy", "plans_transmog", "plans_illusion", "plans_title", "plans_achievement" }
        for _, id in ipairs(tabIds) do
            SSM:ClearSearch(id)
        end
    end
    -- Clear My Plans active search
    ns._plansActiveSearch = nil
    ns._gearSearchText = nil
end

function WarbandNexus:ToggleMainWindow()
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
        self.mainFrame = nil  -- Clear reference
    else
        self:ShowMainWindow()
    end
end

-- Manual open via /wn show or minimap click -> Opens Characters tab
function WarbandNexus:ShowMainWindow()
    -- TAINT PROTECTION: Prevent UI manipulation during combat
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not ready. Please wait a moment and try again.")
        -- Try again after 1 second
        C_Timer.After(1.0, function()
            if WarbandNexus and WarbandNexus.ShowMainWindow then
                WarbandNexus:ShowMainWindow()
            end
        end)
        return
    end
    
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
        
        -- GUARD: Check if CreateMainWindow succeeded
        if not mainFrame then
            DebugPrint("|cffff0000[WN UI]|r ERROR: Failed to create main window. See /wn errors for details.")
            return
        end
    end
    
    -- Store reference for external access (FontManager, etc.)
    self.mainFrame = mainFrame
    
    -- Restore last active tab (persisted in DB), default to Characters
    local lastTab = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.lastTab
    mainFrame.currentTab = lastTab or "chars"
    mainFrame.isMainTabSwitch = true  -- First open = main tab switch
    
    self:PopulateContent()
    mainFrame.isMainTabSwitch = false  -- Reset flag
    mainFrame:Show()
    -- Ensure frame is always anchored TOPLEFT when visible so drag never "teleports"
    -- (StartMoving uses current anchor; CENTER would make the window jump to cursor-as-center).
    NormalizeFramePosition(mainFrame)

    -- Loading overlay is standalone — no action needed here
    
    -- SAFETY: Deferred tab label re-render (catches font loading race conditions)
    -- On first open after locale switch, fonts may not be fully loaded yet.
    -- Re-applying after 0.1s ensures labels render correctly once fonts are ready.
    if not mainFrame._tabLabelsVerified then
        mainFrame._tabLabelsVerified = true
        C_Timer.After(0.1, function()
            if mainFrame and mainFrame:IsShown() and mainFrame.tabButtons then
                local fm = GetFontManager()
                for _, btn in pairs(mainFrame.tabButtons) do
                    if btn.label then
                        local font, size = btn.label:GetFont()
                        if not font or not size then
                            -- Font was not applied yet: re-apply
                            if fm then fm:ApplyFont(btn.label, "body") end
                        end
                        -- Re-set text to force WoW to re-render the glyph
                        local text = btn.label:GetText()
                        if text then btn.label:SetText(text) end
                    end
                end
                -- Re-apply tab highlight state
                self:PopulateContent()
            end
        end)
    end
end

-- Bank open -> Opens Items tab with correct sub-tab based on NPC type
-- User must manually open via /wn or minimap button

function WarbandNexus:HideMainWindow()
    if mainFrame then
        mainFrame:Hide()
    end
end

--============================================================================
-- TAB BUTTON STATE (must be defined before CreateMainWindow so tab OnClick closure can see it)
--============================================================================
-- Tab key -> profile modulesEnabled key (tabs without entry are always shown: chars, stats)
local TAB_TO_MODULE = {
    items = "items",
    storage = "storage",
    pve = "pve",
    reputations = "reputations",
    currency = "currencies",
    professions = "professions",
    gear = "gear",
    collections = "collections",
    plans = "plans",
}

local function IsTabModuleEnabled(key)
    local moduleKey = TAB_TO_MODULE[key]
    if not moduleKey then return true end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not db or not db.modulesEnabled then return true end
    return db.modulesEnabled[moduleKey] ~= false
end

local function UpdateTabVisibility(f)
    if not f or not f.tabButtons or not f.tabButtons.chars then return end
    local tabDefs = {
        { key = "chars" }, { key = "items" }, { key = "storage" }, { key = "pve" },
        { key = "reputations" }, { key = "currency" }, { key = "professions" },
        { key = "gear" }, { key = "collections" }, { key = "plans" }, { key = "stats" },
    }
    local TAB_GAP = 5
    local prevBtn = nil
    for i = 1, #tabDefs do
        local key = tabDefs[i].key
        local btn = f.tabButtons[key]
        if btn then
            local show = IsTabModuleEnabled(key)
            btn:SetShown(show)
            if show then
                if prevBtn then
                    btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP, 0)
                else
                    btn:SetPoint("LEFT", f.nav or btn:GetParent(), "LEFT", 10, 0)
                end
                prevBtn = btn
            end
        end
    end
end

local function UpdateTabButtonStates(f)
    if not f or not f.tabButtons or not f.currentTab then return end
    local freshColors = ns.UI_COLORS
    local accentColor = freshColors and freshColors.accent
    if not accentColor then return end
    local fm = GetFontManager()
    for key, btn in pairs(f.tabButtons) do
        if not btn:IsShown() then
            -- Skip hidden (module-disabled) tabs
        else
        if key == f.currentTab then
            btn.active = true
            if btn.label then
                btn.label:SetTextColor(1, 1, 1)
                local font, size = btn.label:GetFont()
                if font and size then
                    btn.label:SetFont(font, size, "OUTLINE")
                elseif fm then
                    fm:ApplyFont(btn.label, "body")
                    font, size = btn.label:GetFont()
                    if font and size then btn.label:SetFont(font, size, "OUTLINE") end
                end
            end
            if btn.activeBar then btn.activeBar:SetAlpha(1) end
            if UpdateBorderColor then UpdateBorderColor(btn, {accentColor[1], accentColor[2], accentColor[3], 1}) end
            if btn.SetBackdropColor then btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1) end
        else
            btn.active = false
            if btn.label then
                btn.label:SetTextColor(0.7, 0.7, 0.7)
                local font, size = btn.label:GetFont()
                if font and size then
                    btn.label:SetFont(font, size, "")
                elseif fm then
                    fm:ApplyFont(btn.label, "body")
                end
            end
            if btn.activeBar then btn.activeBar:SetAlpha(0) end
            if UpdateBorderColor then UpdateBorderColor(btn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1}) end
            if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 1) end
        end
        end
    end
end

--============================================================================
-- CREATE MAIN WINDOW
--============================================================================
function WarbandNexus:CreateMainWindow()
    -- ZOMBIE FRAME CLEANUP: Check for orphaned frames from failed initialization
    -- If a frame exists in global namespace but we don't have a reference, it's a zombie
    local existingGlobalFrame = _G["WarbandNexusFrame"]
    if existingGlobalFrame then
        -- Check if we already have a valid reference to this frame
        if mainFrame and mainFrame == existingGlobalFrame then
            -- Frame is valid and already created, just return it
            DebugPrint("|cff00ff00[WN UI]|r Main window already exists, reusing.")
            return mainFrame
        else
            -- Zombie frame detected - cleanup and recreate
            DebugPrint("|cffffff00[WN UI]|r WARNING: Zombie frame detected, cleaning up...")
            existingGlobalFrame:Hide()
            existingGlobalFrame:ClearAllPoints()
            if recycleBin then existingGlobalFrame:SetParent(recycleBin) else existingGlobalFrame:SetParent(nil) end
            
            -- Try to properly release the frame
            if existingGlobalFrame.UnregisterAllEvents then
                pcall(function() existingGlobalFrame:UnregisterAllEvents() end)
            end
            
            -- Clear global reference to allow new frame creation
            _G["WarbandNexusFrame"] = nil
        end
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        -- Log error instead of throwing (prevent addon from breaking)
        if self.ErrorLog then
            self.ErrorLog:LogError("CreateMainWindow", "FontManager not initialized", {
                fontManagerExists = ns.FontManager ~= nil,
                createFontStringExists = ns.FontManager and ns.FontManager.CreateFontString ~= nil,
            })
        end
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not initialized. Cannot create UI.")
        return nil
    end
    
    -- Update local reference (for rest of function)
    FontManager = fm
    
    -- Calculate window dimensions dynamically
    local windowWidth, windowHeight = GetWindowDimensions()
    
    -- Calculate bounds
    local screen = self:API_GetScreenInfo()
    local maxWidth = math.floor(screen.width * 0.95)
    local maxHeight = math.floor(screen.height * 0.95)
    
    -- Main frame
    local f = CreateFrame("Frame", "WarbandNexusFrame", UIParent)
    f:Hide()  -- CRITICAL: Hide immediately to prevent position flash (frame inherits UIParent visibility)
    f:SetSize(windowWidth, windowHeight)
    f:SetMovable(true)
    f:SetResizable(true)
    -- Dynamic bounds based on screen
    f:SetResizeBounds(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT, maxWidth, maxHeight)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        StartCustomDrag(self)
    end)
    f:SetScript("OnDragStop", function(self)
        StopCustomDrag(self)
        SaveWindowGeometry(self)
    end)
    f:SetFrameStrata("DIALOG")  -- DIALOG is above HIGH, ensures we're above BankFrame
    f:SetFrameLevel(100)         -- Extra high level for safety
    f:SetClampedToScreen(true)
    
    -- Apply user-configured UI scale (scales entire addon window + children)
    local uiScale = (WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.uiScale) or 1.0
    uiScale = math.max(0.6, math.min(1.5, uiScale))
    f:SetScale(uiScale)
    
    -- Restore saved position, or center on first use
    if not RestoreWindowPosition(f) then
        f:SetPoint("CENTER")
    end
    
    -- NOTE: Master OnHide is set later (after tab system creation) to consolidate all cleanup
    
    -- Apply pixel-perfect visuals (dark background, accent border)
    local ApplyVisuals = ns.UI_ApplyVisuals
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
    end
    
    -- OnSizeChanged handler - Update borders and scrollChild width
    -- Content will refresh on OnMouseUp (when resize is complete)
    local lastSizeW, lastSizeH = 0, 0
    f:SetScript("OnSizeChanged", function(self, width, height)
        local PixelSnap = ns.PixelSnap
        if PixelSnap then
            width = PixelSnap(width)
            height = PixelSnap(height)
        end

        local dw = width - lastSizeW
        local dh = height - lastSizeH
        if dw < 1 and dw > -1 and dh < 1 and dh > -1 then return end
        lastSizeW, lastSizeH = width, height

        if self.BorderTop then
            local pixelScale = (ns.GetPixelScale and ns.GetPixelScale(self)) or 1
            self.BorderTop:SetHeight(pixelScale)
            self.BorderBottom:SetHeight(pixelScale)
            self.BorderLeft:SetWidth(pixelScale)
            self.BorderRight:SetWidth(pixelScale)
        end

        if self.scrollChild and self.scroll then
            local w = self.scroll:GetWidth()
            if self.currentTab == "gear" and ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0 then
                w = math.max(w, ns.MIN_GEAR_CARD_W)
            end
            if self.currentTab == "professions" and ns.ComputeProfessionsGridWidth then
                local profW = ns.ComputeProfessionsGridWidth()
                if profW > 0 then w = math.max(w, profW) end
            end
            if self.currentTab == "pve" and ns.ComputePvEMinScrollWidth then
                local pveW = ns.ComputePvEMinScrollWidth(WarbandNexus)
                if pveW > 0 then w = math.max(w, pveW) end
            end
            self.scrollChild:SetWidth(w)
            if self.columnHeaderInner and self.columnHeaderClip and self.columnHeaderClip:GetHeight() > 1 then
                self.columnHeaderInner:SetWidth(w)
            end
        end
        if self.scroll and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
            ns.UI.Factory:UpdateHorizontalScrollBarVisibility(self.scroll)
        end
    end)
    
    -- Resize handle — anchored exactly at BOTTOMRIGHT to prevent size jump on click
    local resizeBtn = CreateFrame("Frame", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeBtn:EnableMouse(true)
    
    local resizeNormal = resizeBtn:CreateTexture(nil, "ARTWORK")
    resizeNormal:SetAllPoints()
    resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    
    local resizeHighlight = resizeBtn:CreateTexture(nil, "HIGHLIGHT")
    resizeHighlight:SetAllPoints()
    resizeHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    
    local isResizing = false
    resizeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isResizing = true
            resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeBtn:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isResizing then
            isResizing = false
            resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
            f:StopMovingOrSizing()
            SaveWindowGeometry(f)
            -- Ensure scrollChild width is updated BEFORE PopulateContent
            if f.scrollChild and f.scroll then
                local w = f.scroll:GetWidth()
                if f.currentTab == "gear" and ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0 then
                    w = math.max(w, ns.MIN_GEAR_CARD_W)
                end
                if f.currentTab == "professions" and ns.ComputeProfessionsGridWidth then
                    local profW = ns.ComputeProfessionsGridWidth()
                    if profW > 0 then w = math.max(w, profW) end
                end
                if f.currentTab == "pve" and ns.ComputePvEMinScrollWidth then
                    local pveW = ns.ComputePvEMinScrollWidth(WarbandNexus)
                    if pveW > 0 then w = math.max(w, pveW) end
                end
                f.scrollChild:SetWidth(w)
                if f.columnHeaderInner and f.columnHeaderClip and f.columnHeaderClip:GetHeight() > 1 then
                    f.columnHeaderInner:SetWidth(w)
                end
            end
            if f.scroll and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
                ns.UI.Factory:UpdateHorizontalScrollBarVisibility(f.scroll)
            end
            WarbandNexus:PopulateContent()
        end
    end)
    
    -- ===== SCALE / DISPLAY CHANGE HANDLER =====
    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("UI_SCALE_CHANGED")
    scaleFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleFrame:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            if not f then return end
            local screen = WarbandNexus:API_GetScreenInfo()
            local newMaxW = math.floor(screen.width * 0.95)
            local newMaxH = math.floor(screen.height * 0.95)
            f:SetResizeBounds(CONTENT_MIN_WIDTH, CONTENT_MIN_HEIGHT, newMaxW, newMaxH)
        end)
    end)

    -- ===== HEADER BAR =====
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:EnableMouse(true)
    f.header = header  -- Store reference for color updates
    
    -- Header dragging via RegisterForDrag (fires only on actual drag, not plain click).
    -- Custom drag preserves click offset so the clicked point stays under the cursor.
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        StartCustomDrag(f)
    end)
    header:SetScript("OnDragStop", function()
        StopCustomDrag(f)
        SaveWindowGeometry(f)
    end)
    
    -- Apply header visuals (accent dark background, accent border)
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")

    -- Title (WHITE - never changes with theme)
    local title = FontManager:CreateFontString(header, "title", "OVERLAY")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")
    title:SetTextColor(1, 1, 1)  -- Always white
    f.title = title  -- Store reference
    
    -- Close button (Factory pattern with atlas icon)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply custom visuals
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)

    -- Utility buttons in header (left of Close) so nav row is tabs-only and never overlaps when minimized
    local DISCORD_URL = "https://discord.gg/warbandnexus"
    local settingsBtn = CreateFrame("Button", nil, header)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() WarbandNexus:OpenOptions() end)

    local infoBtn = CreateFrame("Button", nil, header)
    infoBtn:SetSize(28, 28)
    infoBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    infoBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    infoBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    infoBtn:SetScript("OnClick", function() WarbandNexus:ShowInfoDialog() end)

    -- Discord button (tracking status is to its left)
    local discordBtn = CreateFrame("Button", nil, header)
    discordBtn:SetSize(30, 30)
    discordBtn:SetPoint("RIGHT", infoBtn, "LEFT", -6, 0)
    local discordIcon = discordBtn:CreateTexture(nil, "ARTWORK")
    discordIcon:SetAllPoints()
    discordIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\discord.tga")
    discordIcon:SetTexCoord(0, 1, 0, 1)
    local discordCopyFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    discordCopyFrame:SetSize(240, 28)
    discordCopyFrame:SetPoint("TOPRIGHT", discordBtn, "BOTTOMRIGHT", 0, -4)
    discordCopyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    discordCopyFrame:SetFrameLevel(500)
    discordCopyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    discordCopyFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    discordCopyFrame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    discordCopyFrame:Hide()
    local discordCopyBox = CreateFrame("EditBox", nil, discordCopyFrame)
    discordCopyBox:SetPoint("TOPLEFT", 6, -4)
    discordCopyBox:SetPoint("BOTTOMRIGHT", -6, 4)
    discordCopyBox:SetAutoFocus(false)
    discordCopyBox:SetFontObject(ChatFontNormal) -- required initial FontObject
    if ns.FontManager then
        local p = ns.FontManager:GetFontFace()
        local s = ns.FontManager:GetFontSize("body")
        local f = ns.FontManager:GetAAFlags()
        pcall(discordCopyBox.SetFont, discordCopyBox, p, s, f)
    end
    discordCopyBox:SetText(DISCORD_URL)
    discordCopyBox:SetCursorPosition(0)
    discordCopyBox:SetScript("OnEscapePressed", function() discordCopyFrame:Hide() end)
    discordCopyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    discordCopyBox:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.1, function() discordCopyFrame:Hide() end)
        end
    end)
    discordBtn:SetScript("OnEnter", function(self)
        discordIcon:SetAlpha(0.75)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DISCORD_TOOLTIP"]) or "Warband Nexus Discord", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY"]) or "Click to copy invite link", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    discordBtn:SetScript("OnLeave", function()
        discordIcon:SetAlpha(1.0)
        GameTooltip:Hide()
    end)
    discordBtn:SetScript("OnClick", function()
        if discordCopyFrame:IsShown() then
            discordCopyFrame:Hide()
            return
        end
        discordCopyBox:SetText(DISCORD_URL)
        discordCopyFrame:Show()
        discordCopyBox:SetFocus()
        discordCopyBox:HighlightText()
    end)

    -- Tracking status: framed badge [text] [icon] directly left of Discord
    local trackingStatusFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    trackingStatusFrame:SetSize(92, 36)
    trackingStatusFrame:SetPoint("RIGHT", discordBtn, "LEFT", -6, 0)
    if ApplyVisuals and ns.UI_COLORS then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(trackingStatusFrame, {0.12, 0.12, 0.15, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end

    local trackingStatusBtn = CreateFrame("Button", nil, trackingStatusFrame)
    trackingStatusBtn:SetAllPoints(trackingStatusFrame)
    trackingStatusBtn:EnableMouse(true)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(trackingStatusBtn)
    end
    f.statusBadge = trackingStatusBtn

    local trackingIcon = trackingStatusBtn:CreateTexture(nil, "ARTWORK")
    trackingIcon:SetSize(16, 16)
    trackingIcon:SetPoint("RIGHT", trackingStatusFrame, "RIGHT", -6, 0)
    local ok = pcall(trackingIcon.SetAtlas, trackingIcon, "common-icon-checkmark", false)
    if not ok then
        trackingIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
    end
    trackingIcon:SetVertexColor(0.3, 1, 0.4)
    f.statusIcon = trackingIcon

    local statusText = FontManager:CreateFontString(trackingStatusBtn, "small", "OVERLAY")
    statusText:SetPoint("RIGHT", trackingIcon, "LEFT", -4, 0)
    statusText:SetPoint("LEFT", trackingStatusFrame, "LEFT", 6, 0)
    statusText:SetPoint("TOP", trackingStatusFrame, "TOP", 0, -4)
    statusText:SetPoint("BOTTOM", trackingStatusFrame, "BOTTOM", 0, 4)
    statusText:SetJustifyH("CENTER")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetWordWrap(true)
    statusText:SetNonSpaceWrap(false)
    f.statusText = statusText

    -- Window Manager: register main window + ESC hierarchy + combat hide/restore
    if ns.WindowManager then
        ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.MAIN)
        ns.WindowManager:InstallESCHandler(f)
    end
    
    -- ===== NAV BAR (tabs only; utility buttons are in header to avoid overlap when minimized) =====
    local nav = CreateFrame("Frame", nil, f)
    nav:SetHeight(36)
    nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4) -- 4px gap below header
    nav:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    f.nav = nav
    -- Default tab set here; overridden by ShowMainWindow with persisted lastTab
    f.currentTab = "chars"
    f.tabButtons = {}
    f._tabScrollPositions = {}
    
    -- Tab styling function (default width fits 10 tabs in CONTENT_MIN_WIDTH without overflow)
    local DEFAULT_TAB_WIDTH = 108
    local TAB_HEIGHT = 34
    local TAB_PAD = 24  -- text padding inside button (12px each side)
    local TAB_GAP = 5   -- gap between tabs
    
    local function CreateTabButton(parent, text, key)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(DEFAULT_TAB_WIDTH, TAB_HEIGHT)
        btn.key = key

        -- Apply border and background
        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        
        -- Active indicator bar (bottom, rounded) (dynamic color)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        local accentColor = COLORS.accent
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(text)
        btn.label = label

        -- Row count badge (dimmed, right of label)
        local countLabel = FontManager:CreateFontString(btn, "small", "OVERLAY")
        countLabel:SetPoint("LEFT", label, "RIGHT", 3, 0)
        countLabel:SetTextColor(0.5, 0.5, 0.5, 0.8)
        countLabel:SetText("")
        countLabel:Hide()
        btn.countLabel = countLabel
        
        -- Keep default 95px, only expand if text doesn't fit
        local textWidth = label:GetStringWidth() or 0
        if textWidth + TAB_PAD > DEFAULT_TAB_WIDTH then
            btn:SetWidth(textWidth + TAB_PAD)
        end

        btn:SetScript("OnClick", function(self)
            -- Skip if this tab is already selected (avoid redundant refresh)
            if f.currentTab == self.key then return end

            local previousTab = f.currentTab

            -- Save scroll position of the tab we're leaving
            if previousTab and f.scroll then
                if not f._tabScrollPositions then f._tabScrollPositions = {} end
                f._tabScrollPositions[previousTab] = {
                    v = f.scroll:GetVerticalScroll() or 0,
                    h = f.scroll:GetHorizontalScroll() or 0,
                }
            end

            f.currentTab = self.key

            -- PERFORMANCE: Update tab bar visuals immediately so user sees switch without waiting for content
            UpdateTabButtonStates(f)

            -- Persist selected tab so the addon reopens where the user left off
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = self.key
            end

            -- Clear session-only collection metadata when leaving Plans (free RAM, avoid bloat)
            if previousTab == "plans" and WarbandNexus.ClearCollectionMetadataCache then
                WarbandNexus:ClearCollectionMetadataCache()
            end
            
            -- ABORT PROTOCOL: Cancel all async operations from previous tab
            -- This prevents race conditions when user switches tabs rapidly
            if WarbandNexus.AbortTabOperations then
                WarbandNexus:AbortTabOperations(previousTab)
            end
            
            -- Flag that this is a MAIN tab switch (not a sub-tab or refresh)
            f.isMainTabSwitch = true
            
            -- Clear all search boxes when switching main tabs
            ClearAllSearchBoxes()
            
            -- Close any open plan dialogs when switching tabs (if function exists)
            if WarbandNexus.CloseAllPlanDialogs then
                WarbandNexus:CloseAllPlanDialogs()
            end
            -- PERFORMANCE: Defer teardown and draw to next frame(s) so main thread stays responsive
            local targetTab = self.key
            C_Timer.After(0, function()
                if f.currentTab ~= targetTab then return end -- User switched again; skip to avoid wasted work
                local scrollChild = f.scrollChild
                if scrollChild then
                    if ReleaseAllPooledChildren then ReleaseAllPooledChildren(scrollChild) end
                    local children = {scrollChild:GetChildren()}
                    for i = 1, #children do
                        local child = children[i]
                        if not (child.isPooled and child.rowType) and not child.isPersistentRowElement then
                            child:Hide()
                            child:SetParent(recycleBin)
                        end
                    end
                end
                C_Timer.After(0, function()
                    if f.currentTab ~= targetTab then return end
                    WarbandNexus:PopulateContent()
                    f.isMainTabSwitch = false
                end)
            end)
        end)

        return btn
    end
    
    -- Tab definitions with locale keys
    local tabDefs = {
        { key = "chars",       text = (ns.L and ns.L["TAB_CHARACTERS"]) or "Characters" },
        { key = "items",       text = (ns.L and ns.L["TAB_ITEMS"]) or "Items" },
        { key = "storage",     text = (ns.L and ns.L["TAB_STORAGE"]) or "Storage" },
        { key = "pve",         text = (ns.L and ns.L["TAB_PVE"]) or "PvE" },
        { key = "reputations", text = (ns.L and ns.L["TAB_REPUTATIONS"]) or "Reputations" },
        { key = "currency",    text = (ns.L and ns.L["TAB_CURRENCIES"]) or "Currencies" },
        { key = "professions", text = (ns.L and ns.L["TAB_PROFESSIONS"]) or "Professions" },
        { key = "gear", text = (ns.L and ns.L["TAB_GEAR"]) or "Gear" },
        { key = "collections", text = (ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections" },
        { key = "plans",       text = (ns.L and ns.L["TAB_PLANS"]) or "To-Do" },
        { key = "stats",       text = (ns.L and ns.L["TAB_STATISTICS"]) or "Statistics" },
    }
    
    -- Create tabs: default 95px + 5px gap, expand only when needed
    local prevBtn = nil
    for _, def in ipairs(tabDefs) do
        local btn = CreateTabButton(nav, def.text, def.key)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP, 0)
        else
            btn:SetPoint("LEFT", nav, "LEFT", 10, 0)
        end
        f.tabButtons[def.key] = btn
        prevBtn = btn
    end
    
    UpdateTabVisibility(f)
    
    -- Function to update tab colors dynamically
    f.UpdateTabColors = function()
        local freshColors = ns.UI_COLORS
        local accentColor = freshColors.accent
        for _, btn in pairs(f.tabButtons) do
            if btn.activeBar then
                btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
            end
            
            -- Update colors based on active state (same as Plans tabs)
            if btn.active then
                btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
                btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
            else
                btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
                btn:SetBackdropBorderColor(accentColor[1] * 0.8, accentColor[2] * 0.8, accentColor[3] * 0.8, 1)
            end
        end
    end
    
    -- ===== CONTENT AREA =====
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", nav, "BOTTOMLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 45)
    f.content = content

    -- Background only on content (no border); border will be on viewport frame so scrollbars sit outside it
    if not content.SetBackdrop then
        Mixin(content, BackdropTemplateMixin)
    end
    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    if ns.UI_COLORS then
        local c = ns.UI_COLORS.border
        content:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    end

    -- Scroll layout: UI_LAYOUT; 2–3px gap between viewport and scrollbars so they don’t sit too close
    local LAYOUT = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local SCROLL_COLUMN_W = LAYOUT.SCROLLBAR_COLUMN_WIDTH or 22
    local SCROLL_GAP = 3
    local SCROLL_INSET_TOP = LAYOUT.SCROLL_CONTENT_TOP_PADDING or 12
    local H_BAR_H = LAYOUT.SCROLL_BAR_WIDTH or 16
    local H_BAR_BOTTOM = LAYOUT.SIDE_MARGIN or 10
    local H_ROW_H = SCROLL_COLUMN_W
    local SCROLL_INSET_BOTTOM = H_BAR_BOTTOM + H_ROW_H + SCROLL_GAP
    local SCROLL_INSET_LEFT = 4
    local SCROLL_INSET_RIGHT = SCROLL_COLUMN_W + SCROLL_GAP

    -- Viewport border frame: only the scroll area gets the border; scrollbars sit outside with SCROLL_GAP
    local viewportBorder = CreateFrame("Frame", nil, content)
    viewportBorder:SetPoint("TOPLEFT", content, "TOPLEFT", SCROLL_INSET_LEFT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SCROLL_INSET_RIGHT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", SCROLL_INSET_LEFT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -SCROLL_INSET_RIGHT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetFrameLevel(content:GetFrameLevel() + 1)
    if ApplyVisuals and ns.UI_COLORS then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(viewportBorder, {0.04, 0.04, 0.05, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    f.viewportBorder = viewportBorder

    -- Fixed header area: title cards, search boxes stay here (non-scrolling)
    -- Inset by 1px from viewport border so content doesn't overlap the border line
    local BORDER_INSET = 1
    local fixedHeader = CreateFrame("Frame", nil, content)
    fixedHeader:SetPoint("TOPLEFT", content, "TOPLEFT", SCROLL_INSET_LEFT + BORDER_INSET, -(SCROLL_INSET_TOP + BORDER_INSET))
    fixedHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(SCROLL_INSET_RIGHT + BORDER_INSET), -(SCROLL_INSET_TOP + BORDER_INSET))
    fixedHeader:SetHeight(1)
    fixedHeader:SetFrameLevel(viewportBorder:GetFrameLevel() + 1)
    f.fixedHeader = fixedHeader

    -- Column header clip: overlays the top of the scroll area at a higher frame level.
    -- Clips tab-specific column headers that sync horizontally with the scroll child
    -- but stay vertically fixed (frozen header pattern).
    -- Height = 1 when collapsed (invisible); tabs like ProfessionsUI expand it.
    -- Frame level content+6 ensures the BACKGROUND layer of this frame renders
    -- AFTER all layers of scroll (content+2), so the opaque backdrop properly
    -- covers data rows scrolling underneath the frozen column headers.
    local columnHeaderClip = CreateFrame("Frame", nil, content)
    columnHeaderClip:SetClipsChildren(true)
    columnHeaderClip:SetPoint("TOPLEFT", fixedHeader, "BOTTOMLEFT", 0, 0)
    columnHeaderClip:SetPoint("TOPRIGHT", fixedHeader, "BOTTOMRIGHT", 0, 0)
    columnHeaderClip:SetHeight(1)
    columnHeaderClip:SetFrameLevel(viewportBorder:GetFrameLevel() + 5)
    f.columnHeaderClip = columnHeaderClip

    local columnHeaderBg = columnHeaderClip:CreateTexture(nil, "BACKGROUND")
    columnHeaderBg:SetAllPoints()
    columnHeaderBg:SetColorTexture(0.08, 0.08, 0.10, 1)

    local columnHeaderInner = CreateFrame("Frame", nil, columnHeaderClip)
    columnHeaderInner:SetPoint("TOPLEFT", 0, 0)
    columnHeaderInner:SetPoint("BOTTOMLEFT", 0, 0)
    columnHeaderInner:SetWidth(1)
    f.columnHeaderInner = columnHeaderInner

    local scroll = ns.UI.Factory:CreateScrollFrame(content, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", fixedHeader, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("TOPRIGHT", fixedHeader, "BOTTOMRIGHT", 0, 0)
    scroll:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", SCROLL_INSET_LEFT + BORDER_INSET, SCROLL_INSET_BOTTOM + BORDER_INSET)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(SCROLL_INSET_RIGHT + BORDER_INSET), SCROLL_INSET_BOTTOM + BORDER_INSET)
    scroll:SetFrameLevel(viewportBorder:GetFrameLevel() + 1)
    f.scroll = scroll

    -- Vertical bar column: outside viewport border, same vertical range as scroll; button-to-button alignment
    local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(content, SCROLL_COLUMN_W, SCROLL_INSET_TOP, SCROLL_INSET_BOTTOM)
    scrollBarColumn:SetFrameLevel(viewportBorder:GetFrameLevel() + 2)
    f.scrollBarColumn = scrollBarColumn
    if scroll.ScrollBar and ns.UI.Factory.PositionScrollBarInContainer then
        ns.UI.Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
    end

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    -- Horizontal bar: same strip size as vertical column (H_ROW_H = 22px); same viewport gap (SCROLL_GAP)
    local hScrollContainer = CreateFrame("Frame", nil, content)
    hScrollContainer:SetPoint("LEFT", content, "LEFT", SCROLL_INSET_LEFT, 0)
    hScrollContainer:SetPoint("RIGHT", content, "RIGHT", -SCROLL_INSET_RIGHT, 0)
    hScrollContainer:SetPoint("BOTTOM", content, "BOTTOM", 0, H_BAR_BOTTOM)
    hScrollContainer:SetHeight(H_ROW_H)
    hScrollContainer:SetFrameLevel(viewportBorder:GetFrameLevel() + 2)
    f.hScrollContainer = hScrollContainer

    if ns.UI.Factory and ns.UI.Factory.CreateHorizontalScrollBar then
        local hScroll = ns.UI.Factory:CreateHorizontalScrollBar(scroll, hScrollContainer, true)
        if hScroll and hScroll.PositionInContainer then
            hScroll:PositionInContainer(hScrollContainer, 0)
            f.hScroll = hScroll
        end
    end

    -- Sync column header horizontal offset with main scroll frame.
    -- Every call to SetHorizontalScroll (scrollbar drag, Shift+wheel, button click,
    -- tab-switch restore) automatically repositions the frozen column header.
    local origSetHScroll = scroll.SetHorizontalScroll
    scroll.SetHorizontalScroll = function(self, value)
        origSetHScroll(self, value)
        if f.columnHeaderInner and f.columnHeaderClip then
            f.columnHeaderInner:ClearAllPoints()
            f.columnHeaderInner:SetPoint("TOPLEFT", f.columnHeaderClip, "TOPLEFT", -(value or 0), 0)
            f.columnHeaderInner:SetPoint("BOTTOMLEFT", f.columnHeaderClip, "BOTTOMLEFT", -(value or 0), 0)
        end
    end

    -- Pixel-snap scroll: snap every scroll offset to the nearest physical pixel boundary.
    -- Without this, scrollChild sits at sub-pixel positions (e.g., 123.456) causing ALL
    -- child frames to render with anti-aliasing — visible as wobbling/jittering borders.
    local origOnScroll = scroll:GetScript("OnVerticalScroll")
    local isSnappingScroll = false
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        local PixelSnap = ns.PixelSnap
        if PixelSnap and not isSnappingScroll then
            local snapped = PixelSnap(offset)
            if math.abs(snapped - offset) > 0.001 then
                isSnappingScroll = true
                self:SetVerticalScroll(snapped)
                isSnappingScroll = false
                return
            end
        end
        if origOnScroll then origOnScroll(self, offset) end
        if f._virtualScrollUpdate then
            f._virtualScrollUpdate()
        end
    end)

    -- Clip children to viewport so rows outside the visible area never bleed through
    scroll:SetClipsChildren(true)

    -- Note: scrollChild width is managed in PopulateContent() for consistency
    
    -- Store reference in WarbandNexus for cross-module access
    if not WarbandNexus.UI then
        WarbandNexus.UI = {}
    end
    WarbandNexus.UI.mainFrame = f
    
    -- ===== EVENT-DRIVEN UI UPDATES (DB-First Pattern) =====
    -- UI automatically refreshes when DB data changes.
    -- All listeners use SchedulePopulateContent() to coalesce rapid events
    -- (e.g., bank open fires WN_ITEMS_UPDATED + WN_BAGS_UPDATED + WN_ITEM_METADATA_READY
    -- within milliseconds -- without coalescing this causes 3+ PopulateContent calls).
    local Constants = ns.Constants
    
    local pendingPopulateTimer = nil
    local POPULATE_DEBOUNCE = 0.1  -- 100ms coalesce window
    local lastEventPopulateTime = 0
    local POPULATE_COOLDOWN = 0.8  -- Skip event-driven rebuild if one ran within 800ms
    -- This prevents duplicate rebuilds from WN_ITEMS_UPDATED (~0.5s) + WN_BAGS_UPDATED (~1.0s)
    -- firing for the same loot event. Does NOT affect direct PopulateContent calls (tab switch, resize).
    -- Profession events (concentration, knowledge, recipe) use skipCooldown so updates always show.
    
    local function SchedulePopulateContent(skipCooldown)
        if not f or not f:IsShown() then return end
        if pendingPopulateTimer then return end  -- already scheduled
        pendingPopulateTimer = C_Timer.After(POPULATE_DEBOUNCE, function()
            pendingPopulateTimer = nil
            if not f or not f:IsShown() then return end
            local now = GetTime()
            if not skipCooldown and (now - lastEventPopulateTime) < POPULATE_COOLDOWN then
                return  -- Recent rebuild already handled this data change
            end
            lastEventPopulateTime = now
            WarbandNexus:PopulateContent()
        end)
    end
    
    -- NOTE: All RegisterMessage calls use UIEvents as the 'self' key to avoid
    -- overwriting other modules' handlers for the same AceEvent message.
    -- AceEvent allows only ONE handler per (event, self) pair.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "chars" or f.currentTab == "gear" or f.currentTab == "stats") then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEMS_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "storage" or f.currentTab == "gear") then
            SchedulePopulateContent()
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GEAR_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "gear" then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PVE_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "pve" then
            -- Vault data arrives asynchronously via WEEKLY_REWARDS_UPDATE.
            -- Reset cooldown so this event is never silently dropped.
            lastEventPopulateTime = 0
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, "WARBAND_CURRENCIES_UPDATED", function()
        if f and f:IsShown() and (f.currentTab == "currency" or f.currentTab == "gear") then
            SchedulePopulateContent()
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, "WN_CURRENCY_UPDATED", function()
        if f and f:IsShown() and (f.currentTab == "currency" or f.currentTab == "gear") then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, "WARBAND_REPUTATIONS_UPDATED", function()
        if f and f:IsShown() and f.currentTab == "reputations" then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, "WN_PLANS_UPDATED", function()
        if f and f:IsShown() and f.currentTab == "plans" then
            SchedulePopulateContent()
        end
    end)
    
    -- Collection scan complete (plans/collections tab): skip cooldown so scan results show immediately
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
        if f and f:IsShown() and (f.currentTab == "plans" or f.currentTab == "collections") then
            SchedulePopulateContent(true)
        end
    end)
    
    -- Profession tab: skip cooldown so concentration/knowledge/recipe updates always refresh (no stale data)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CONCENTRATION_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "professions" or f.currentTab == "chars") then
            SchedulePopulateContent(true)
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.KNOWLEDGE_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "professions" or f.currentTab == "chars") then
            SchedulePopulateContent(true)
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.RECIPE_DATA_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CRAFTING_ORDERS_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_DATA_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    -- Profession equipment (slots 20/21/22): refresh when chars or professions tab visible so equipped gear updates in real time
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_COOLDOWNS_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_EQUIPMENT_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "professions" or f.currentTab == "chars") then
            SchedulePopulateContent(true)
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, "WN_BAGS_UPDATED", function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "storage") then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, "WN_MODULE_TOGGLED", function(_, moduleName)
        if not f or not f.tabButtons then return end
        -- Map module name to tab key (currencies -> currency; others same)
        local tabKey = (moduleName == "currencies") and "currency" or moduleName
        UpdateTabVisibility(f)
        if f.currentTab == tabKey then
            f.currentTab = "chars"
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = "chars"
            end
            UpdateTabButtonStates(f)
            SchedulePopulateContent()
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, "WN_FONT_CHANGED", function()
        if f and f:IsShown() then
            SchedulePopulateContent()
        end
    end)

    -- Loading bar is now a standalone floating frame (see CreateLoadingOverlay below)
    
    -- Master OnHide: cleanup when addon window closes
    f:SetScript("OnHide", function(self)
        StopCustomDrag(self)
        SaveWindowGeometry(self)
        if WarbandNexus.CloseAllPlanDialogs then
            WarbandNexus:CloseAllPlanDialogs()
        end
        ClearAllSearchBoxes()
        -- Close Settings window if open (child follows parent)
        local settingsFrame = _G["WarbandNexusSettingsFrame"]
        if settingsFrame and settingsFrame:IsShown() then
            settingsFrame:Hide()
        end
        -- Free session-only metadata caches (bounded FIFO, but no reason to keep in memory while closed)
        if WarbandNexus.ClearCurrencyMetadataCache then WarbandNexus:ClearCurrencyMetadataCache() end
        if WarbandNexus.ClearReputationMetadataCache then WarbandNexus:ClearReputationMetadataCache() end
        if WarbandNexus.ClearItemMetadataCache then WarbandNexus:ClearItemMetadataCache() end
        if WarbandNexus.ClearCollectionMetadataCache then WarbandNexus:ClearCollectionMetadataCache() end
    end)
    
    -- Frame is already hidden (Hide() called immediately after CreateFrame)
    return f
end

--============================================================================
-- POPULATE CONTENT
--============================================================================
function WarbandNexus:PopulateContent()
    if not mainFrame then return end

    -- Chars tab debounce: avoid 2–3x redraw when tab switch + WN_CHARACTER_UPDATED fire in quick succession
    if mainFrame.currentTab == "chars" and mainFrame._lastCharsDrawTime and (GetTime() - mainFrame._lastCharsDrawTime) < 0.25 then
        return
    end

    -- Detect tab switch vs same-tab refresh
    local isTabSwitch = (mainFrame._prevPopulatedTab ~= mainFrame.currentTab)
    mainFrame._prevPopulatedTab = mainFrame.currentTab

    -- Clear virtual scroll callback from previous tab
    local scrollChild = mainFrame.scrollChild
    if ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mainFrame)
    end

    if not scrollChild then return end

    -- Clear fixed header area and reset to minimal height
    local fixedHeader = mainFrame.fixedHeader
    if fixedHeader then
        local fhChildren = {fixedHeader:GetChildren()}
        for i = 1, #fhChildren do
            fhChildren[i]:Hide()
            fhChildren[i]:SetParent(recycleBin)
        end
        local fhRegions = {fixedHeader:GetRegions()}
        for i = 1, #fhRegions do
            fhRegions[i]:Hide()
        end
        fixedHeader:SetHeight(1)
    end

    -- Reset column header overlay to collapsed state.
    -- Child frames (colHeaderBar etc.) go to recycleBin; their textures/fontstrings
    -- travel with them. columnHeaderInner is repositioned to origin for the next tab.
    local columnHeaderClip = mainFrame.columnHeaderClip
    local columnHeaderInner = mainFrame.columnHeaderInner
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
    end
    if columnHeaderInner then
        local chChildren = {columnHeaderInner:GetChildren()}
        for i = 1, #chChildren do
            chChildren[i]:Hide()
            chChildren[i]:SetParent(recycleBin)
        end
        columnHeaderInner:SetWidth(1)
        columnHeaderInner:ClearAllPoints()
        columnHeaderInner:SetPoint("TOPLEFT", columnHeaderClip, "TOPLEFT", 0, 0)
        columnHeaderInner:SetPoint("BOTTOMLEFT", columnHeaderClip, "BOTTOMLEFT", 0, 0)
    end
    
    -- Get scroll frame width (already reduced by 24px for scroll bar)
    local scrollWidth = mainFrame.scroll:GetWidth()
    
    -- Set scrollChild width to full scroll frame width (no extra padding needed)
    scrollChild:SetWidth(scrollWidth)
    
    -- CRITICAL FIX: Reset scrollChild height to prevent layout corruption across tabs
    scrollChild:SetHeight(1)  -- Reset to minimal height, will expand as content is added
    
    -- Release all pooled children first (returns them to pools for reuse)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(scrollChild)
    end

    -- Move old non-pooled tab content (headers, cards, etc.) to the recycleBin to prevent
    -- overlap/stacking. Pooled frames are already released to their pools above — skip them.
    -- Persistent frames (3D models, reused placeholders) are also skipped.
    local children = {scrollChild:GetChildren()}
    for i = 1, #children do
        local child = children[i]
        if child._virtualVisibleFrames then
            child._virtualVisibleFrames = nil
        end
        if isTabSwitch then
            child._hasRenderedOnce = nil
        end
        if not (child.isPooled and child.rowType) and not child.isPersistentRowElement then
            child:Hide()
            child:SetParent(recycleBin)
        end
    end

    -- Hide persistent gear frames when leaving their tab
    if mainFrame.currentTab ~= "gear" then
        if ns._gearPlayerModel then ns._gearPlayerModel:Hide() end
        if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
        if ns._gearModelBorder then ns._gearModelBorder:Hide() end
        if ns._gearIlvlFrame then ns._gearIlvlFrame:Hide() end
        if ns._gearNameWrapper then ns._gearNameWrapper:Hide() end
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Sync tab bar active state (idempotent; on tab click we already updated for instant feedback)
    UpdateTabButtonStates(mainFrame)
    
    -- Draw based on current tab
    local height
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local trackedOnlyTabs = {
        items = true,
        storage = true,
        pve = true,
        reputations = true,
        currency = true,
    }

    if not isTracked and trackedOnlyTabs[mainFrame.currentTab] then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawTrackingRequiredBanner(scrollChild)
    elseif mainFrame.currentTab == "chars" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCharacterList(scrollChild)
        mainFrame._lastCharsDrawTime = GetTime()
    elseif mainFrame.currentTab == "currency" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCurrencyTab(scrollChild)
    elseif mainFrame.currentTab == "items" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawItemList(scrollChild)
    elseif mainFrame.currentTab == "storage" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawStorageTab(scrollChild)
    elseif mainFrame.currentTab == "pve" then
        local pveMinW = ns.ComputePvEMinScrollWidth and ns.ComputePvEMinScrollWidth(self) or 0
        scrollChild:SetWidth(pveMinW > 0 and math.max(scrollWidth, pveMinW) or scrollWidth)
        height = self:DrawPvEProgress(scrollChild)
    elseif mainFrame.currentTab == "reputations" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawReputationTab(scrollChild)
    elseif mainFrame.currentTab == "stats" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawStatistics(scrollChild)
    elseif mainFrame.currentTab == "professions" then
        local profMinW = ns.ComputeProfessionsGridWidth and ns.ComputeProfessionsGridWidth() or 0
        scrollChild:SetWidth(profMinW > 0 and math.max(scrollWidth, profMinW) or scrollWidth)
        height = self:DrawProfessionsTab(scrollChild)
    elseif mainFrame.currentTab == "gear" then
        local gearMinW = (ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0) and ns.MIN_GEAR_CARD_W or 0
        scrollChild:SetWidth(gearMinW > 0 and math.max(scrollWidth, gearMinW) or scrollWidth)
        height = self:DrawGearTab(scrollChild)
    elseif mainFrame.currentTab == "collections" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCollectionsTab(scrollChild)
    elseif mainFrame.currentTab == "plans" then
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawPlansTab(scrollChild)
    else
        scrollChild:SetWidth(scrollWidth)
        height = self:DrawCharacterList(scrollChild)
    end
    
    -- Set scrollChild height based on content + bottom padding
    -- CRITICAL: Use math.max to ensure scrollChild is at least viewport size
    -- Otherwise, WoW scroll frame won't work properly when content < viewport
    local CONTENT_BOTTOM_PADDING = 8
    scrollChild:SetHeight(math.max(height + CONTENT_BOTTOM_PADDING, mainFrame.scroll:GetHeight()))
    
    -- Update scroll bar visibility (hide if content fits)
    if ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
    
    -- Scroll position persistence: restore saved position on main tab switch,
    -- or reset to 0 if no saved position exists for this tab.
    if mainFrame.isMainTabSwitch then
        local savedScroll = mainFrame._tabScrollPositions and mainFrame._tabScrollPositions[mainFrame.currentTab]
        local restoreY = (savedScroll and savedScroll.v) or 0
        local restoreH = (savedScroll and savedScroll.h) or 0
        -- Clamp to valid range
        local maxV = mainFrame.scroll:GetVerticalScrollRange() or 0
        restoreY = math.max(0, math.min(restoreY, maxV))
        mainFrame.scroll:SetVerticalScroll(restoreY)
        mainFrame.scroll:SetHorizontalScroll(restoreH)
        if mainFrame.hScroll then
            mainFrame.hScroll:SetValue(restoreH)
        end
    end
    
    self:UpdateTabCountBadges()
end

--============================================================================
-- TAB COUNT BADGES
--============================================================================
function WarbandNexus:UpdateTabCountBadges()
    if not mainFrame or not mainFrame.tabButtons then return end
    local db = self.db and self.db.profile
    local globalDB = self.db and self.db.global

    local counts = {}

    -- Currencies: use cache service count
    if ns.CurrencyCacheService and ns.CurrencyCacheService.GetAllCachedCurrencyIDs then
        local ids = ns.CurrencyCacheService:GetAllCachedCurrencyIDs()
        if ids then counts.currency = #ids end
    end

    -- Reputations: use cache service count
    if ns.ReputationCacheService and ns.ReputationCacheService.GetCachedFactionCount then
        local ok, n = pcall(ns.ReputationCacheService.GetCachedFactionCount, ns.ReputationCacheService)
        if ok and type(n) == "number" then counts.reputations = n end
    end

    for key, btn in pairs(mainFrame.tabButtons) do
        local cl = btn.countLabel
        if cl then
            local c = counts[key]
            if c and c > 0 then
                cl:SetText("(" .. c .. ")")
                cl:Show()
            else
                cl:SetText("")
                cl:Hide()
            end
        end
    end
end

--============================================================================
-- TRACKING REQUIRED BANNER
--============================================================================
function WarbandNexus:DrawTrackingRequiredBanner(parent)
    local card = CreateCard(parent, 170)
    card:SetPoint("TOPLEFT", 10, -20)
    card:SetPoint("TOPRIGHT", -10, -20)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 14, -14)
    local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
    if not ok then
        icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
    end
    icon:SetVertexColor(1, 0.4, 0.4)

    local title = GetFontManager():CreateFontString(card, "title", "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -2)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.55, 0.45)
    title:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_TITLE"]) or "Character is not tracked")

    local desc = GetFontManager():CreateFontString(card, "body", "OVERLAY")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -8)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.88, 0.88, 0.88)
    desc:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_DESC"]) or "This tab works only for tracked characters.\nEnable tracking from the Characters page using the tracking icon.")

    local openCharsBtn = CreateThemedButton(card, (ns.L and ns.L["OPEN_CHARACTERS_TAB"]) or "Open Characters", 170)
    openCharsBtn:SetPoint("BOTTOMLEFT", 14, 12)
    openCharsBtn:SetScript("OnClick", function()
        if mainFrame and mainFrame.tabButtons and mainFrame.tabButtons.chars then
            mainFrame.currentTab = "chars"
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = "chars"
            end
            UpdateTabButtonStates(mainFrame)
            WarbandNexus:PopulateContent()
        end
    end)

    return 200
end

--============================================================================
-- UPDATE STATUS
--============================================================================
function WarbandNexus:UpdateStatus()
    if not mainFrame then return end

    local isOpen = self.bankIsOpen
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)

    local icon = mainFrame.statusIcon
    local badge = mainFrame.statusBadge
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()

    local function SetClickAndTooltip(tooltipText, tooltipHint)
        if badge then
            badge:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                if charKey and ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                    ns.CharacterService:ShowCharacterTrackingConfirmation(WarbandNexus, charKey)
                end
            end)
            badge:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tooltipText or "", 1, 1, 1)
                if tooltipHint then
                    GameTooltip:AddLine(tooltipHint, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end)
            badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    if mainFrame.statusText then
        if isOpen then
            mainFrame.statusText:SetText((ns.L and ns.L["TRACKING_BADGE_BANK"]) or "Bank is\nActive")
            mainFrame.statusText:SetTextColor(0.3, 1, 0.4)
        elseif isTracked then
            mainFrame.statusText:SetText((ns.L and ns.L["TRACKING_BADGE_TRACKING"]) or "Tracking")
            mainFrame.statusText:SetTextColor(0.3, 1, 0.4)
        else
            mainFrame.statusText:SetText((ns.L and ns.L["TRACKING_BADGE_UNTRACKED"]) or "Not\nTracking")
            mainFrame.statusText:SetTextColor(1, 0.5, 0.3)
        end
    end

    if isOpen then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.3, 1, 0.4)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["BANK_IS_ACTIVE"]) or "Bank is Active", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    elseif isTracked then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.3, 1, 0.4)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_ACTIVE_DESC"]) or "Data collection and updates are active.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    else
        if icon then
            local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
            if not ok then
                icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
            end
            icon:SetVertexColor(1, 0.4, 0.3)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_NOT_ENABLED_TOOLTIP"]) or "Character tracking is disabled.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to enable tracking.")
    end
end

function WarbandNexus:UpdateFooter()
end

--============================================================================
-- DRAW ITEM LIST
--============================================================================
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

-- Setter for currentItemsSubTab (called from Core.lua)
function WarbandNexus:SetItemsSubTab(subTab)
    if subTab == "warband" or subTab == "personal" or subTab == "guild" then
        currentItemsSubTab = subTab
    end
end

function WarbandNexus:GetItemsSubTab()
    return currentItemsSubTab
end

-- Track expanded state for each category (persists across refreshes)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

--============================================================================
-- TAB DRAWING FUNCTIONS (All moved to separate modules)
--============================================================================
-- DrawCharacterList moved to Modules/UI/CharactersUI.lua
-- DrawItemList moved to Modules/UI/ItemsUI.lua
-- DrawEmptyState moved to Modules/UI/ItemsUI.lua
-- DrawStorageTab moved to Modules/UI/StorageUI.lua
-- DrawPvEProgress moved to Modules/UI/PvEUI.lua
-- DrawStatistics moved to Modules/UI/StatisticsUI.lua


--============================================================================
-- REFRESH
--============================================================================

-- Refresh throttle constants
local REFRESH_THROTTLE = 0.05 -- Small delay for batching follow-up refreshes

function WarbandNexus:RefreshUI()
    -- Dismiss any open achievement popup before UI rebuild
    if ns.UI_HideAchievementPopup then
        ns.UI_HideAchievementPopup()
    end
    
    if mainFrame and mainFrame.tabButtons then
        UpdateTabVisibility(mainFrame)
    end
    
    -- Combat safety: defer frame operations to avoid taint
    -- NOTE: Uses UIEvents as 'self' key so we don't overwrite Core.lua's
    -- permanent PLAYER_REGEN_ENABLED → OnCombatEnd handler.
    if InCombatLockdown() then
        if not self._combatRefreshPending then
            self._combatRefreshPending = true
            WarbandNexus.RegisterEvent(UIEvents, "PLAYER_REGEN_ENABLED", function()
                WarbandNexus.UnregisterEvent(UIEvents, "PLAYER_REGEN_ENABLED")
                self._combatRefreshPending = false
                self:RefreshUI()
            end)
        end
        return
    end
    
    -- Prevent recursive calls during populate (safety flag)
    if self.isRefreshing then
        -- Schedule a follow-up refresh instead of executing recursively
        if not self.pendingRefresh then
            self.pendingRefresh = true
            C_Timer.After(REFRESH_THROTTLE, function()
                if WarbandNexus and WarbandNexus.pendingRefresh then
                    WarbandNexus.pendingRefresh = false
                    WarbandNexus:RefreshUI()
                end
            end)
        end
        return
    end
    
    -- CRITICAL FIX: Always execute the refresh immediately (no throttle on user actions)
    -- This ensures rows are always drawn when headers are toggled or tabs are switched
    self.isRefreshing = true
    
    -- Use pcall to ensure isRefreshing flag is always reset even if there's an error
    local success, err = pcall(function()
        if mainFrame and mainFrame:IsShown() then
            self:PopulateContent()
        end
    end)
    
    self.isRefreshing = false
    
    if not success and self.Debug then
        self:Debug("|cffff0000[RefreshUI] PopulateContent error: " .. tostring(err) .. "|r")
    end
end

--- Apply global UI scale to the main window. Called from SettingsUI when slider changes.
---@param newScale number Scale value (0.6 - 1.5)
function WarbandNexus:ApplyUIScale(newScale)
    if not mainFrame then return end
    newScale = math.max(0.6, math.min(1.5, newScale or 1.0))

    -- Save before scale change (position is in old scale space)
    SaveWindowGeometry(mainFrame)

    mainFrame:SetScale(newScale)

    -- Re-clamp to screen after scale change (frame may have shifted off-screen)
    NormalizeFramePosition(mainFrame)
    SaveWindowGeometry(mainFrame)

    -- Rebuild content so scroll dimensions and scrollbar visibility are recalculated
    if mainFrame:IsShown() then
        self:PopulateContent()
    end
end

-- REMOVED: RefreshMainWindow() and RefreshMainWindowContent() - duplicate wrappers, use RefreshUI() directly

--[[
    [CONSOLIDATED] RefreshUI duplicate removed (line 1040)
    The implementation at line 997 with throttling and recursive call prevention is kept.
    This duplicate (which closed/reopened the window) has been removed to prevent conflicts.
    The consolidated RefreshUI handles both normal refreshes and font/scale changes.
]]

--[[
    Force refresh of PvE tab if currently visible
    Provides instant refresh for responsive UI
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:RefreshPvEUI()
    DebugPrint("|cff9370DB[WN UI]|r RefreshPvEUI triggered")
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
                DebugPrint("|cff00ff00[WN UI]|r PvE tab refreshed")
            end
        end
    end
end

--[[
    Open addon settings/options UI
    Shows custom settings UI with themed widgets
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:OpenOptions()
    DebugPrint("|cff9370DB[WN UI]|r OpenOptions triggered")
    -- Show custom settings UI (renders AceConfig with themed widgets)
    if self.ShowSettings then
        self:ShowSettings()
    elseif ns.ShowSettings then
        ns.ShowSettings()
    else
        -- No settings UI available (ShowSettings should always exist)
        _G.print("|cff9370DB[Warband Nexus]|r " .. ((ns.L and ns.L["SETTINGS_UI_UNAVAILABLE"]) or "Settings UI not available. Try /wn to open the main window."))
    end
end

-- ===== STANDALONE LOADING OVERLAY =====
-- Floating bar that appears on screen during init, independent of the addon window.
-- Uses lightweight polling (0.5s ticker) to track LoadingTracker state.
-- AceEvent message hooks don't work from standalone contexts (plain tables
-- can't register as AceEvent receivers), so polling is the reliable approach.
--
-- LIFECYCLE: Ticker runs for up to MAX_POLL_LIFETIME seconds after PLAYER_LOGIN.
-- This covers both the initial login (tracked chars: ~15s) and the delayed
-- post-confirmation flow (user clicks "Tracked" at T+2.5s+: adds ~5s of ops).
-- Ticker is NOT cancelled on first completion — new operations can be registered
-- after the user confirms tracking, and the bar will reappear automatically.
do
    local loadingOverlay
    local pollTicker
    local completedShown = false
    local pollStartTime = 0
    local MAX_POLL_LIFETIME = 180 -- 3 minutes: covers late-confirm edge cases

    local function CreateLoadingOverlay()
        if loadingOverlay then return loadingOverlay end

        local C = ns.UI_COLORS
        if not C then return nil end

        local bar = CreateFrame("Frame", "WarbandNexusLoadingOverlay", UIParent, "BackdropTemplate")
        bar:SetSize(360, 34)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -12)
        bar:SetFrameStrata("HIGH")
        bar:SetFrameLevel(100)
        bar:SetClampedToScreen(true)
        bar:SetMovable(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", bar.StartMoving)
        bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
        bar:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        bar:SetBackdropColor(0.06, 0.06, 0.09, 1)
        bar:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
        bar:Hide()

        -- Progress fill
        local fill = bar:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", 1, 1)
        fill:SetWidth(1)
        fill:SetColorTexture(0.15, 0.55, 0.2, 0.6)
        bar.progressFill = fill

        -- Spinner
        local spinner = bar:CreateTexture(nil, "OVERLAY")
        spinner:SetSize(14, 14)
        spinner:SetPoint("LEFT", 8, 0)
        spinner:SetTexture("Interface\\COMMON\\StreamCircle")
        spinner:SetVertexColor(0.3, 0.9, 0.4, 0.9)
        bar.spinner = spinner

        local spinGroup = spinner:CreateAnimationGroup()
        local spinAnim = spinGroup:CreateAnimation("Rotation")
        spinAnim:SetDegrees(-360)
        spinAnim:SetDuration(1.2)
        spinGroup:SetLooping("REPEAT")
        bar.spinGroup = spinGroup

        local loadText
        if ns.FontManager then
            loadText = ns.FontManager:CreateFontString(bar, "body", "OVERLAY")
        else
            loadText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        loadText:SetPoint("LEFT", spinner, "RIGHT", 6, 0)
        loadText:SetPoint("RIGHT", bar, "RIGHT", -55, 0)
        loadText:SetJustifyH("LEFT")
        loadText:SetTextColor(0.3, 0.9, 0.4, 1)
        loadText:SetWordWrap(false)
        bar.loadingText = loadText

        local progText
        if ns.FontManager then
            progText = ns.FontManager:CreateFontString(bar, "body", "OVERLAY")
        else
            progText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        progText:SetPoint("RIGHT", -8, 0)
        progText:SetTextColor(0.3, 0.9, 0.4, 1)
        bar.progressText = progText

        loadingOverlay = bar
        return bar
    end

    local function UpdateLoadingOverlay()
        local LT = ns.LoadingTracker
        if not LT then return end

        local bar = loadingOverlay
        if not bar then
            bar = CreateLoadingOverlay()
            if not bar then return end
        end

        local done, total = LT:GetProgress()

        if LT:IsComplete() then
            if bar:IsShown() and not completedShown then
                completedShown = true
                bar.loadingText:SetText((ns.L and ns.L["SYNCING_COMPLETE"]) or "Syncing complete!")
                bar.progressText:SetText("")
                bar.progressFill:SetWidth(math.max(1, bar:GetWidth() - 2))
                C_Timer.After(2, function()
                    if bar and LT:IsComplete() then
                        bar.spinGroup:Stop()
                        bar:Hide()
                    end
                    -- Do NOT cancel ticker here: new operations may be registered
                    -- after user confirms tracking. Ticker auto-stops after MAX_POLL_LIFETIME.
                end)
            end
            return
        end

        if total == 0 then
            bar:Hide()
            return
        end

        -- New operations registered after a previous completion cycle
        bar:Show()
        bar.spinGroup:Play()
        completedShown = false

        -- Progress fill width
        local barWidth = bar:GetWidth() - 2
        if barWidth > 0 and total > 0 then
            bar.progressFill:SetWidth(math.max(1, barWidth * (done / total)))
        end

        -- Pending labels
        local pending = LT:GetPendingLabels()
        local labelStr = ""
        if #pending > 0 then
            local shown = math.min(#pending, 2)
            local parts = {}
            for i = 1, shown do
                parts[i] = pending[i]
            end
            labelStr = table.concat(parts, ", ")
            if #pending > shown then
                labelStr = labelStr .. " +" .. (#pending - shown)
            end
        end
        bar.loadingText:SetText(string.format((ns.L and ns.L["SYNCING_LABEL_FORMAT"]) or "WN Syncing : %s", labelStr))
        bar.progressText:SetText(format("%d / %d", done, total))
    end

    -- Start polling after PLAYER_LOGIN.
    -- Ticker runs for up to MAX_POLL_LIFETIME seconds, then auto-cancels.
    -- This ensures the overlay detects both initial-login ops AND
    -- post-confirmation ops (user clicks "Tracked" after the dialog).
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", function()
        C_Timer.After(1.5, function()
            pollStartTime = GetTime()
            UpdateLoadingOverlay()
            if not pollTicker then
                pollTicker = C_Timer.NewTicker(0.5, function()
                    if GetTime() - pollStartTime > MAX_POLL_LIFETIME then
                        if pollTicker then
                            pollTicker:Cancel()
                            pollTicker = nil
                        end
                        return
                    end
                    UpdateLoadingOverlay()
                end)
            end
        end)
    end)
end
