--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
-- CRITICAL: FontManager is lazy-loaded to prevent initialization errors
local FontManager  -- Will be set on first access
local L = ns.L

local issecretvalue = issecretvalue

-- Unique AceEvent handler identity for UI.lua
-- AceEvent uses events[eventname][self] = handler, so each module needs a unique
-- 'self' table to prevent overwriting other modules' handlers for the same event.
local UIEvents = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

--- SavedVars may use strict booleans or legacy `1`; match Settings checkboxes reliably.
local function ProfileFlagOn(v)
    return v == true or v == 1
end

--- Main-tab perf timings: Debug + Verbose both on (any legacy truthy). `/wn debug` alone does not spam chat.
local function IsTabPerfMonitorEnabled()
    local p = WarbandNexus.db and WarbandNexus.db.profile
    return p and ProfileFlagOn(p.debugMode) and ProfileFlagOn(p.debugVerbose)
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
local wipe = wipe
local debugprofilestart = debugprofilestart
local debugprofilestop = debugprofilestop

-- Reused buffers for frame child/region enumeration (one WoW API call per pack; avoids fresh tables each PopulateContent).
local _uiChildEnumScratch = {}
local _uiRegionEnumScratch = {}
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

-- Layout Constants (computed dynamically)
local CONTENT_MIN_WIDTH = 1280   -- Minimum to fit Statistics 3-card row + character/gear layouts without overflow
local CONTENT_MIN_HEIGHT = 650   -- Multi-level structures minimum

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
    
    UpdateScrollLayout(frame)
    WarbandNexus:PopulateContent()
end

-- Compute the correct scrollChild width for the current tab.
-- Tabs with wide inline layouts (gear, professions, pve) enforce a minimum width
-- so horizontal scrollbar kicks in instead of squeezing content.
local function ComputeScrollChildWidth(frame)
    if not frame or not frame.scroll then return 0 end
    local w = frame.scroll:GetWidth()
    local tab = frame.currentTab
    if tab == "gear" and ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0 then
        w = math.max(w, ns.MIN_GEAR_CARD_W)
    elseif tab == "professions" and ns.ComputeProfessionsGridWidth then
        local profW = ns.ComputeProfessionsGridWidth()
        if profW > 0 then w = math.max(w, profW) end
    elseif tab == "pve" and ns.ComputePvEMinScrollWidth then
        local pveW = ns.ComputePvEMinScrollWidth(WarbandNexus)
        if pveW > 0 then w = math.max(w, pveW) end
    end
    return w
end

-- Update scrollChild and frozen column header widths in one call.
local function UpdateScrollLayout(frame)
    if not frame or not frame.scrollChild or not frame.scroll then return end
    local w = ComputeScrollChildWidth(frame)
    frame.scrollChild:SetWidth(w)
    if frame.columnHeaderInner and frame.columnHeaderClip and frame.columnHeaderClip:GetHeight() > 1 then
        frame.columnHeaderInner:SetWidth(w)
    end
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
local SEARCH_TAB_IDS = { "items", "gear", "currency", "storage", "reputation", "plans_mount", "plans_pet", "plans_toy", "plans_transmog", "plans_illusion", "plans_title", "plans_achievement" }

local function ClearAllSearchBoxes()
    local SSM = ns.SearchStateManager
    if SSM and SSM.ClearSearch then
        for i = 1, #SEARCH_TAB_IDS do
            SSM:ClearSearch(SEARCH_TAB_IDS[i])
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
    if ns and ns._wnSuppressToggleMainOnce then
        return
    end
    -- Modal-first behavior: if Settings is open, close it first.
    local settingsPanel = _G.WarbandNexusSettingsPanel
    if settingsPanel and settingsPanel:IsShown() then
        settingsPanel:Hide()
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
            DebugPrint("|cffff0000[WN UI]|r ERROR: Failed to create main window. See /wn help.")
            return
        end
    end
    
    -- Store reference for external access (FontManager, etc.)
    self.mainFrame = mainFrame
    
    -- Restore last active tab (persisted in DB), default to Characters
    local lastTab = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.lastTab
    mainFrame.currentTab = lastTab or "chars"
    mainFrame.isMainTabSwitch = true  -- First open = main tab switch

    -- Show before PopulateContent: while hidden, scroll:GetWidth() is often 0 → blank/black To-Do (and other tabs).
    mainFrame:Show()
    self:PopulateContent()
    mainFrame.isMainTabSwitch = false  -- Reset flag
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
                local anyFixed = false
                for _, btn in pairs(mainFrame.tabButtons) do
                    if btn.label then
                        local font, size = btn.label:GetFont()
                        if not font or not size then
                            if fm then fm:ApplyFont(btn.label, "body") end
                            anyFixed = true
                        end
                        local text = btn.label:GetText()
                        if text and not (issecretvalue and issecretvalue(text)) then
                            btn.label:SetText(text)
                        end
                    end
                end
                -- Only rebuild content if fonts actually needed fixing
                if anyFixed then
                    UpdateTabButtonStates(mainFrame)
                    self:PopulateContent()
                end
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

-- Canonical tab order: single source of truth for visibility, creation, and navigation.
local MAIN_TAB_ORDER = { "chars", "storage", "items", "gear", "currency", "reputations", "pve", "professions", "collections", "plans", "stats" }

local function IsTabModuleEnabled(key)
    local moduleKey = TAB_TO_MODULE[key]
    if not moduleKey then return true end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not db or not db.modulesEnabled then return true end
    return db.modulesEnabled[moduleKey] ~= false
end

local function UpdateTabVisibility(f)
    if not f or not f.tabButtons or not f.tabButtons.chars then return end
    local TAB_GAP = 5
    local prevBtn = nil
    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
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
            return mainFrame
        else
            -- Zombie frame detected - cleanup and recreate
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
    -- MEDIUM: plays nice with Blizzard UI and other addons (DIALOG was always on top of HIGH/MEDIUM).
    if ns.WindowManager and ns.WindowManager.ApplyStrata then
        ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.MAIN)
    else
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(50)
    end
    if f.SetToplevel then
        f:SetToplevel(true)
    end
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

        UpdateScrollLayout(self)
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
            if InCombatLockdown and InCombatLockdown() then
                return
            end
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
            UpdateScrollLayout(f)
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
    local title = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
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
    f.closeBtn = closeBtn

    -- Debug-only: quick /reload (WoW has no Lua hot-reload; saves typing during addon dev)
    local reloadDebugBtn = CreateFrame("Button", nil, header)
    reloadDebugBtn:SetSize(28, 28)
    reloadDebugBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(reloadDebugBtn, {0.12, 0.14, 0.18, 0.92}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75})
    end
    local reloadIcon = reloadDebugBtn:CreateTexture(nil, "ARTWORK")
    reloadIcon:SetSize(16, 16)
    reloadIcon:SetPoint("CENTER")
    do
        local picked = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local atlases = { "StreamCinematic-Restart-button", "common-icon-rotateleft" }
            for ai = 1, #atlases do
                local ok, info = pcall(C_Texture.GetAtlasInfo, atlases[ai])
                if ok and info then
                    reloadIcon:SetAtlas(atlases[ai])
                    picked = true
                    break
                end
            end
        end
        if not picked then
            reloadIcon:SetTexture("Interface\\COMMON\\StreamRestart")
        end
    end
    reloadIcon:SetVertexColor(0.75, 0.92, 1)
    reloadDebugBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    reloadDebugBtn:SetScript("OnEnter", function(self)
        reloadIcon:SetVertexColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.18, 0.22, 0.28, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DEBUG_RELOAD_UI_BTN"]) or "Reload UI", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["DEBUG_RELOAD_UI_TOOLTIP"]) or "Reload the entire interface (/reload). WoW cannot hot-reload addon Lua; use this after saving files.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    reloadDebugBtn:SetScript("OnLeave", function(self)
        reloadIcon:SetVertexColor(0.75, 0.92, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.12, 0.14, 0.18, 0.92}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75})
        end
        GameTooltip:Hide()
    end)
    f.reloadDebugBtn = reloadDebugBtn

    -- Utility buttons in header (left of Close) so nav row is tabs-only and never overlaps when minimized
    local DISCORD_URL = "https://discord.gg/warbandnexus"
    local settingsBtn = CreateFrame("Button", nil, header)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", reloadDebugBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() WarbandNexus:OpenOptions() end)
    f.settingsBtn = settingsBtn

    local infoBtn = CreateFrame("Button", nil, header)
    infoBtn:SetSize(28, 28)
    infoBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    infoBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    infoBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    infoBtn:SetScript("OnClick", function() WarbandNexus:ShowInfoDialog() end)
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["HEADER_INFO_TOOLTIP"]) or "Addon guide & credits", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["HEADER_INFO_TOOLTIP_HINT"]) or "Features, supporters, and contributors at the top", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

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

    -- Tracking status: compact chip (accent rail + icon + single-line label), left of Discord
    -- Match header accentDark family — avoid flat black (0.06…) which clashes with the title bar
    local trackingChip = CreateFrame("Frame", nil, header, "BackdropTemplate")
    trackingChip:SetHeight(30)
    trackingChip:SetPoint("RIGHT", discordBtn, "LEFT", -8, 0)
    local COL_TRACK = ns.UI_COLORS
    local baseDark = (COL_TRACK and COL_TRACK.accentDark) or {0.28, 0.14, 0.41}
    local chipLift = 0.06
    local chipBg = {
        math.min(1, baseDark[1] + chipLift),
        math.min(1, baseDark[2] + chipLift),
        math.min(1, baseDark[3] + chipLift),
        0.88,
    }
    if ApplyVisuals and COL_TRACK then
        ApplyVisuals(trackingChip, chipBg, {COL_TRACK.accent[1], COL_TRACK.accent[2], COL_TRACK.accent[3], 0.24})
    end

    local trackingAccent = trackingChip:CreateTexture(nil, "ARTWORK", nil, 1)
    trackingAccent:SetWidth(3)
    trackingAccent:SetPoint("TOPLEFT", trackingChip, "TOPLEFT", 0, -1)
    trackingAccent:SetPoint("BOTTOMLEFT", trackingChip, "BOTTOMLEFT", 0, 1)
    trackingAccent:SetColorTexture(0.22, 0.9, 0.42, 1)
    f.trackingStatusAccent = trackingAccent

    local trackingStatusBtn = CreateFrame("Button", nil, trackingChip)
    trackingStatusBtn:SetAllPoints(trackingChip)
    trackingStatusBtn:EnableMouse(true)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(trackingStatusBtn)
    end
    f.statusBadge = trackingStatusBtn
    f.trackingChip = trackingChip

    local iconBack = CreateFrame("Frame", nil, trackingChip, "BackdropTemplate")
    iconBack:SetSize(20, 20)
    iconBack:SetPoint("LEFT", trackingAccent, "RIGHT", 6, 0)
    iconBack:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    iconBack:SetBackdropColor(
        math.min(1, baseDark[1] + chipLift * 0.35),
        math.min(1, baseDark[2] + chipLift * 0.35),
        math.min(1, baseDark[3] + chipLift * 0.35),
        0.5
    )

    local trackingIcon = iconBack:CreateTexture(nil, "ARTWORK")
    trackingIcon:SetSize(14, 14)
    trackingIcon:SetPoint("CENTER", iconBack, "CENTER", 0, 0)
    local ok = pcall(trackingIcon.SetAtlas, trackingIcon, "common-icon-checkmark", false)
    if not ok then
        trackingIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
    end
    trackingIcon:SetVertexColor(0.35, 1, 0.45)
    f.statusIcon = trackingIcon

    local statusText = FontManager:CreateFontString(trackingStatusBtn, FontManager:GetFontRole("mainShellTrackingStatus"), "OVERLAY")
    statusText:SetPoint("LEFT", iconBack, "RIGHT", 8, 0)
    statusText:SetPoint("RIGHT", trackingChip, "RIGHT", -8, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetWordWrap(false)
    statusText:SetNonSpaceWrap(false)
    f.statusText = statusText
    trackingChip:SetWidth(112)

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

        local label = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabLabel"), "OVERLAY")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(text)
        btn.label = label

        -- Row count badge (dimmed, right of label)
        local countLabel = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabCount"), "OVERLAY")
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

            -- Invalidate any in-flight tab-switch timers (rapid clicks); paired with checks inside C_Timer callbacks.
            f._tabSwitchGen = (f._tabSwitchGen or 0) + 1
            local tabSwitchGen = f._tabSwitchGen
            local targetTab = self.key

            local previousTab = f.currentTab

            -- Dev-only: main tab switch timings (debugprofilestop ms); see IsTabPerfMonitorEnabled (see pool/populate hooks below).
            if IsTabPerfMonitorEnabled() then
                f._wnPerfMainTabSwitch = {
                    gen = tabSwitchGen,
                    fromTab = previousTab,
                    toTab = targetTab,
                }
                debugprofilestart()
            else
                f._wnPerfMainTabSwitch = nil
            end

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
            -- PERFORMANCE: Frame 1 — pool release + detach old tab content; Frame 2 — PopulateContent.
            -- Keeps teardown and full redraw off the same frame (reduces hitch on heavy tabs).
            C_Timer.After(0, function()
                if tabSwitchGen ~= f._tabSwitchGen then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen then
                        f._wnPerfMainTabSwitch = nil
                        debugprofilestop()
                    end
                    return
                end
                if f.currentTab ~= targetTab then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen then
                        f._wnPerfMainTabSwitch = nil
                        debugprofilestop()
                    end
                    return
                end
                local scrollChild = f.scrollChild
                if scrollChild then
                    if ReleaseAllPooledChildren then ReleaseAllPooledChildren(scrollChild) end
                    local nc = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
                    for i = 1, nc do
                        local child = _uiChildEnumScratch[i]
                        if not (child.isPooled and child.rowType) and not child.isPersistentRowElement then
                            child:Hide()
                            child:SetParent(recycleBin)
                        elseif child.isPersistentRowElement then
                            -- Persistent elements (e.g. Gear 3D DressUpModel) survive tab teardown but must be
                            -- hidden on tab switch so they don't render over other tabs. The owning tab's
                            -- refresh re-shows them when re-entered.
                            child:Hide()
                        end
                    end
                    f._contentPreCleared = true
                end
                local pAfterPool = f._wnPerfMainTabSwitch
                if pAfterPool and pAfterPool.gen == tabSwitchGen and f.currentTab == targetTab then
                    if IsTabPerfMonitorEnabled() then
                        pAfterPool.msClickToPoolEnd = debugprofilestop()
                        debugprofilestart()
                    else
                        f._wnPerfMainTabSwitch = nil
                        debugprofilestop()
                    end
                end
                C_Timer.After(0, function()
                    if tabSwitchGen ~= f._tabSwitchGen then
                        local pStale = f._wnPerfMainTabSwitch
                        if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                            f._wnPerfMainTabSwitch = nil
                            f._wnPerfTabSwitchPendingLog = nil
                            debugprofilestop()
                        end
                        return
                    end
                    if f.currentTab ~= targetTab then
                        local pStale = f._wnPerfMainTabSwitch
                        if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                            f._wnPerfMainTabSwitch = nil
                            f._wnPerfTabSwitchPendingLog = nil
                            debugprofilestop()
                        end
                        return
                    end
                    local pBeforePop = f._wnPerfMainTabSwitch
                    if pBeforePop and pBeforePop.gen == tabSwitchGen and pBeforePop.msClickToPoolEnd then
                        if IsTabPerfMonitorEnabled() then
                            f._wnPerfTabSwitchPendingLog = tabSwitchGen
                        else
                            f._wnPerfMainTabSwitch = nil
                            debugprofilestop()
                        end
                    end
                    WarbandNexus:PopulateContent()
                    f.isMainTabSwitch = false
                end)
            end)
        end)

        return btn
    end
    
    -- Tab labels keyed by MAIN_TAB_ORDER (single source of truth)
    local TAB_LABELS = {
        chars       = (ns.L and ns.L["TAB_CHARACTERS"]) or "Characters",
        storage     = (ns.L and ns.L["TAB_STORAGE"]) or "Storage",
        items       = (ns.L and ns.L["TAB_ITEMS"]) or "Items",
        gear        = (ns.L and ns.L["TAB_GEAR"]) or "Gear",
        currency    = (ns.L and ns.L["TAB_CURRENCIES"]) or "Currencies",
        reputations = (ns.L and ns.L["TAB_REPUTATIONS"]) or "Reputations",
        pve         = (ns.L and ns.L["TAB_PVE"]) or "PvE",
        professions = (ns.L and ns.L["TAB_PROFESSIONS"]) or "Professions",
        collections = (ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections",
        plans       = (ns.L and ns.L["TAB_PLANS"]) or "To-Do",
        stats       = (ns.L and ns.L["TAB_STATISTICS"]) or "Statistics",
    }
    
    -- Create tabs: default 95px + 5px gap, expand only when needed
    local prevBtn = nil
    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
        local btn = CreateTabButton(nav, TAB_LABELS[key], key)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP, 0)
        else
            btn:SetPoint("LEFT", nav, "LEFT", 10, 0)
        end
        f.tabButtons[key] = btn
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
    local pendingPopulateSkipCooldown = false
    local populateDebounceGen = 0  -- Invalidates deferred callbacks after hide or superseding schedule (esp. C_Timer.After fallback)
    local POPULATE_DEBOUNCE = 0.1  -- 100ms coalesce window (resets on each new message = last event wins)
    local lastEventPopulateTime = 0
    local POPULATE_COOLDOWN = 0.8  -- Skip event-driven rebuild if one ran within 800ms
    -- This prevents duplicate rebuilds from WN_ITEMS_UPDATED (~0.5s) + WN_BAGS_UPDATED (~1.0s)
    -- firing for the same loot event. Does NOT affect direct PopulateContent calls (tab switch, resize).
    -- Profession events (concentration, knowledge, recipe) use skipCooldown so updates always show.
    
    local function SchedulePopulateContent(skipCooldown)
        if not f or not f:IsShown() then return end
        if skipCooldown then
            pendingPopulateSkipCooldown = true
        end
        if pendingPopulateTimer and pendingPopulateTimer.Cancel then
            pendingPopulateTimer:Cancel()
            pendingPopulateTimer = nil
        end
        populateDebounceGen = populateDebounceGen + 1
        local myGen = populateDebounceGen
        if C_Timer and C_Timer.NewTimer then
            pendingPopulateTimer = C_Timer.NewTimer(POPULATE_DEBOUNCE, function()
                pendingPopulateTimer = nil
                if myGen ~= populateDebounceGen then return end
                local useSkip = pendingPopulateSkipCooldown
                pendingPopulateSkipCooldown = false
                if not f or not f:IsShown() then return end
                local now = GetTime()
                if not useSkip and (now - lastEventPopulateTime) < POPULATE_COOLDOWN then
                    return  -- Recent rebuild already handled this data change
                end
                lastEventPopulateTime = now
                WarbandNexus:PopulateContent()
            end)
            return
        end
        local afterHandle = C_Timer.After(POPULATE_DEBOUNCE, function()
            pendingPopulateTimer = nil
            if myGen ~= populateDebounceGen then return end
            local useSkip = pendingPopulateSkipCooldown
            pendingPopulateSkipCooldown = false
            if not f or not f:IsShown() then return end
            local now = GetTime()
            if not useSkip and (now - lastEventPopulateTime) < POPULATE_COOLDOWN then
                return  -- Recent rebuild already handled this data change
            end
            lastEventPopulateTime = now
            WarbandNexus:PopulateContent()
        end)
        if type(afterHandle) == "table" and afterHandle.Cancel then
            pendingPopulateTimer = afterHandle
        else
            pendingPopulateTimer = true
        end
    end
    
    -- NOTE: All RegisterMessage calls use UIEvents as the 'self' key to avoid
    -- overwriting other modules' handlers for the same AceEvent message.
    -- AceEvent allows only ONE handler per (event, self) pair.
    -- Must bypass POPULATE_COOLDOWN: after login/alt switch, ITEMS_UPDATED etc. can set lastEventPopulateTime
    -- and this refresh would be dropped — leaving Character tab layout stale or visually broken.
    -- Gear tab rebuilds 3D paperdoll + full card — avoid skipCooldown (full populate every ~0.1s) on
    -- rapid WN_CHARACTER_UPDATED (e.g. item level ticks at 0.3s, DataService) or models appear to "flicker".
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "chars" or f.currentTab == "stats" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "gear" then
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
        if not f or not f:IsShown() then return end
        -- PvE tab + Characters tab (mythic key column reads character row; mirror updates from PvECacheService)
        if f.currentTab == "pve" then
            -- Vault data arrives asynchronously via WEEKLY_REWARDS_UPDATE.
            -- Reset cooldown so this event is never silently dropped.
            lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            lastEventPopulateTime = 0
            SchedulePopulateContent(true)
        end
    end)
    
    -- REMOVED: WARBAND_CURRENCIES_UPDATED — no SendMessage exists for this string; dead handler.

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "currency" or f.currentTab == "gear" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            -- Total Gold / WoW Token card reads token price; refresh without 800ms cooldown drop.
            SchedulePopulateContent(true)
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end)

    -- Reputation tab content: ReputationUI.lua registers DrawReputationTab for many WN_REPUTATION_* events.
    -- Tab badge count: refresh cheaply when cache updates without full PopulateContent if user is elsewhere.
    -- ReputationUI.lua redraws the tab on these when active; only refresh the tab button badge when elsewhere.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_CACHE_READY, function()
        if not f or not f:IsShown() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)
    
    -- WN_REPUTATION_* refresh: ReputationUI.lua registers DrawReputationTab (avoid double PopulateContent here)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PLANS_UPDATED, function()
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
    
    -- BAGS_UPDATED also feeds the gear-tab recommendation scan (cross-character bag items
    -- are candidates) so newly looted BoEs surface without a manual reopen.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.BAGS_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "storage" or f.currentTab == "gear") then
            SchedulePopulateContent()
        end
    end)

    -- Money: chars Total Gold card, gear-tab affordability (gold-only upgrades).
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MONEY_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "chars" or f.currentTab == "gear" then
            SchedulePopulateContent(true)
        end
    end)

    -- Currency variants: gear upgrade panel + currency tab depend on full currency state.
    local function refreshCurrency()
        if not f or not f:IsShown() then return end
        if f.currentTab == "currency" or f.currentTab == "gear" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            SchedulePopulateContent(true)
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCIES_UPDATED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_GAINED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_CACHE_READY, refreshCurrency)

    -- Collections: obtained/scan results + achievement tracking flips need to redraw cards.
    -- Plans tab also reads obtained state for try-counter rows.
    local function refreshCollection()
        if not f or not f:IsShown() then return end
        if f.currentTab == "collections" or f.currentTab == "plans" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            WarbandNexus:UpdateTabCountBadges("collections")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTIBLE_OBTAINED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_UPDATED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ACHIEVEMENT_TRACKING_UPDATED, refreshCollection)

    -- Vault: any vault data delta (slot completion, reward available, plan completion) must
    -- propagate to PvE tab (vault card) and chars-tab vault badge.
    local function refreshVault()
        if not f or not f:IsShown() then return end
        if f.currentTab == "pve" then
            lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_CHECKPOINT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_SLOT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_PLAN_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_REWARD_AVAILABLE, refreshVault)

    -- Tracking toggle changes the visible character roster on every tab that lists chars.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_TRACKING_CHANGED, function()
        if not f or not f:IsShown() then return end
        SchedulePopulateContent(true)
    end)

    -- Pure UI state (sub-tab switches, expand/collapse, column pickers, theme accent): coalesced rebuild.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, function(_, payload)
        if not f or not f:IsShown() then return end
        local tab = payload and payload.tab
        if tab and f.currentTab ~= tab then return end
        local skipCooldown = true
        if payload and payload.skipCooldown == false then
            skipCooldown = false
        end
        -- Bypass POPULATE_DEBOUNCE for explicit UI gestures (e.g. Storage section expand/collapse).
        if payload and payload.instantPopulate then
            if pendingPopulateTimer then
                if pendingPopulateTimer.Cancel then
                    pendingPopulateTimer:Cancel()
                end
            end
            pendingPopulateTimer = nil
            populateDebounceGen = populateDebounceGen + 1
            pendingPopulateSkipCooldown = false
            if not f or not f:IsShown() then return end
            lastEventPopulateTime = GetTime()
            WarbandNexus:PopulateContent()
            return
        end
        SchedulePopulateContent(skipCooldown)
    end)

    -- Gold management edits + bank money log: chars tab gold cards / popup.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GOLD_MANAGEMENT_CHANGED, function()
        if f and f:IsShown() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_BANK_MONEY_LOG_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)

    -- Item metadata async warm-up: cross-character SV links are often cold on login.
    -- Gear tab storage recommendations rely on link-based ilvl (e.g. WuE 253 vs template 233);
    -- when the warm-up completes, re-scan so previously-skipped candidates surface.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEM_METADATA_READY, function()
        if f and f:IsShown() and f.currentTab == "gear" then
            SchedulePopulateContent()
        end
    end)

    -- Blizzard fires GET_ITEM_INFO_RECEIVED whenever a cold-cache hyperlink finishes
    -- async resolution. ResolveStorageItemIlvl bails out (returns 0) on cold links,
    -- so we must re-run the gear scan once the client cache warms — otherwise the
    -- recommendation list stays empty for the entire session.
    if not UIEvents._itemInfoFrame then
        local infoFrame = CreateFrame("Frame")
        UIEvents._itemInfoFrame = infoFrame
        infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        infoFrame:SetScript("OnEvent", function(_, _, itemID, success)
            if not success then return end
            if not f or not f:IsShown() then return end
            if f.currentTab == "gear" then
                SchedulePopulateContent()
            end
        end)
    end

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MODULE_TOGGLED, function(_, moduleName)
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

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.FONT_CHANGED, function()
        if f and f:IsShown() then
            SchedulePopulateContent()
        end
    end)

    -- Loading bar is now a standalone floating frame (see CreateLoadingOverlay below)
    
    -- Master OnHide: cleanup when addon window closes
    f:SetScript("OnHide", function(self)
        if pendingPopulateTimer then
            if pendingPopulateTimer.Cancel then
                pendingPopulateTimer:Cancel()
            end
        end
        pendingPopulateTimer = nil
        pendingPopulateSkipCooldown = false
        populateDebounceGen = populateDebounceGen + 1
        StopCustomDrag(self)
        SaveWindowGeometry(self)
        if ns.HideGearCharacterDropdown then
            ns.HideGearCharacterDropdown()
        end
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

    --- Show/hide header Reload button when debug mode is on (boolean or legacy SavedVars `1`; matches ProfileFlagOn / Settings toggles).
    function f:SyncMainHeaderDebugReloadLayout()
        local reloadBtn = self.reloadDebugBtn
        local settBtn = self.settingsBtn
        local clsBtn = self.closeBtn
        if not reloadBtn or not settBtn or not clsBtn then return end
        local p = WarbandNexus.db and WarbandNexus.db.profile
        local show = p and ProfileFlagOn(p.debugMode)
        reloadBtn:SetShown(show)
        settBtn:ClearAllPoints()
        if show then
            settBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -6, 0)
        else
            settBtn:SetPoint("RIGHT", clsBtn, "LEFT", -6, 0)
        end
    end
    f:SyncMainHeaderDebugReloadLayout()
    
    -- Frame is already hidden (Hide() called immediately after CreateFrame)
    return f
end

--============================================================================
-- POPULATE CONTENT
--============================================================================
function WarbandNexus:PopulateContent()
    if not mainFrame then return end

    if mainFrame.SyncMainHeaderDebugReloadLayout then
        mainFrame:SyncMainHeaderDebugReloadLayout()
    end

    local pendingPerfGen = IsTabPerfMonitorEnabled() and mainFrame._wnPerfTabSwitchPendingLog or nil

    -- Detect tab switch vs same-tab refresh
    local isTabSwitch = (mainFrame._prevPopulatedTab ~= mainFrame.currentTab)
    mainFrame._prevPopulatedTab = mainFrame.currentTab

    -- Clear virtual scroll callback from previous tab
    local scrollChild = mainFrame.scrollChild
    if ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mainFrame)
    end

    if not scrollChild then
        if pendingPerfGen then
            debugprofilestop()
            mainFrame._wnPerfMainTabSwitch = nil
            mainFrame._wnPerfTabSwitchPendingLog = nil
        end
        return
    end

    -- Clear fixed header area and reset to minimal height
    local fixedHeader = mainFrame.fixedHeader
    if fixedHeader then
        local nch = PackVariadicInto(_uiChildEnumScratch, fixedHeader:GetChildren())
        for i = 1, nch do
            _uiChildEnumScratch[i]:Hide()
            _uiChildEnumScratch[i]:SetParent(recycleBin)
        end
        local nrg = PackVariadicInto(_uiRegionEnumScratch, fixedHeader:GetRegions())
        for i = 1, nrg do
            _uiRegionEnumScratch[i]:Hide()
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
        local nch2 = PackVariadicInto(_uiChildEnumScratch, columnHeaderInner:GetChildren())
        for i = 1, nch2 do
            _uiChildEnumScratch[i]:Hide()
            _uiChildEnumScratch[i]:SetParent(recycleBin)
        end
        columnHeaderInner:SetWidth(1)
        columnHeaderInner:ClearAllPoints()
        columnHeaderInner:SetPoint("TOPLEFT", columnHeaderClip, "TOPLEFT", 0, 0)
        columnHeaderInner:SetPoint("BOTTOMLEFT", columnHeaderClip, "BOTTOMLEFT", 0, 0)
    end
    
    -- CRITICAL FIX: Reset scrollChild height to prevent layout corruption across tabs
    scrollChild:SetHeight(1)  -- Reset to minimal height, will expand as content is added
    
    local wasPreCleared = isTabSwitch and mainFrame._contentPreCleared
    mainFrame._contentPreCleared = nil

    if not wasPreCleared then
        -- Release all pooled children first (returns them to pools for reuse)
        if ReleaseAllPooledChildren then
            ReleaseAllPooledChildren(scrollChild)
        end

        -- Move old non-pooled tab content (headers, cards, etc.) to the recycleBin to prevent
        -- overlap/stacking. Pooled frames are already released to their pools above — skip them.
        -- Persistent frames (3D models, reused placeholders) are also skipped.
        local nc3 = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
        for i = 1, nc3 do
            local child = _uiChildEnumScratch[i]
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
    end

    -- Hide persistent gear frames when leaving their tab
    if mainFrame.currentTab ~= "gear" then
        if ns._gearPlayerModel then ns._gearPlayerModel:Hide() end
        if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
        if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
        if ns._gearModelBorder then ns._gearModelBorder:Hide() end
        if ns._gearIlvlFrame then ns._gearIlvlFrame:Hide() end
        if ns._gearNameWrapper then ns._gearNameWrapper:Hide() end
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Tab bar: skip redundant UpdateTabButtonStates on main tab switch (OnClick already updated visuals)
    if not mainFrame.isMainTabSwitch then
        UpdateTabButtonStates(mainFrame)
    end
    
    -- Set scrollChild width once (ComputeScrollChildWidth handles tab-specific minimums)
    scrollChild:SetWidth(ComputeScrollChildWidth(mainFrame))

    -- Mark that pooled rows were already released in PopulateContent.
    -- Tab renderers can skip redundant ReleaseAllPooledChildren() calls in this pass.
    scrollChild._preparedByPopulate = true

    -- Draw based on current tab
    local height
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local trackedOnlyTabs = {
        items = true, storage = true, pve = true, reputations = true,
        currency = true, professions = true, gear = true, collections = true,
        plans = true, stats = true,
    }

    local tab = mainFrame.currentTab
    if not isTracked and trackedOnlyTabs[tab] then
        height = self:DrawTrackingRequiredBanner(scrollChild)
    elseif tab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif tab == "currency" then
        height = self:DrawCurrencyTab(scrollChild)
    elseif tab == "items" then
        height = self:DrawItemList(scrollChild)
    elseif tab == "storage" then
        height = self:DrawStorageTab(scrollChild)
    elseif tab == "pve" then
        height = self:DrawPvEProgress(scrollChild)
    elseif tab == "reputations" then
        height = self:DrawReputationTab(scrollChild)
    elseif tab == "stats" then
        height = self:DrawStatistics(scrollChild)
    elseif tab == "professions" then
        height = self:DrawProfessionsTab(scrollChild)
    elseif tab == "gear" then
        height = self:DrawGearTab(scrollChild)
    elseif tab == "collections" then
        height = self:DrawCollectionsTab(scrollChild)
    elseif tab == "plans" then
        height = self:DrawPlansTab(scrollChild)
    else
        height = self:DrawCharacterList(scrollChild)
    end
    scrollChild._preparedByPopulate = nil
    
    -- Set scrollChild height based on content + bottom padding
    local CONTENT_BOTTOM_PADDING = 8
    local contentBottom = height + CONTENT_BOTTOM_PADDING
    -- Gear tab: extend scrollChild to viewport so the gear card can fill downward (see DrawPaperDollCard fill).
    scrollChild:SetHeight(math.max(contentBottom, mainFrame.scroll:GetHeight()))

    -- After content height changes, clamp vertical scroll (avoids empty band when range shrinks or layout jumps)
    do
        local sc = mainFrame.scroll
        if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
            local maxV = sc:GetVerticalScrollRange() or 0
            local cur = sc:GetVerticalScroll() or 0
            if cur > maxV then
                sc:SetVerticalScroll(maxV)
            end
        end
    end
    
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

    -- Dev-only: one-line main tab switch timing after deferred PopulateContent (see tab OnClick).
    if pendingPerfGen and IsTabPerfMonitorEnabled() then
        local perf = mainFrame._wnPerfMainTabSwitch
        local ok = perf and perf.gen == pendingPerfGen and perf.msClickToPoolEnd and perf.gen == mainFrame._tabSwitchGen
            and mainFrame.currentTab == perf.toTab
        if ok then
            local msPopulate = debugprofilestop()
            local msg = format(
                "[WN Perf] main tab %s → %s | click→pool=%.2fms pool→populate=%.2fms sum=%.2fms",
                tostring(perf.fromTab),
                tostring(perf.toTab),
                perf.msClickToPoolEnd,
                msPopulate,
                perf.msClickToPoolEnd + msPopulate
            )
            -- Prefer addon chat pipeline (same as /wn messages); DebugPrint uses raw print and can be easy to miss.
            if WarbandNexus.Print then
                WarbandNexus:Print("|cff9e9e9e" .. msg .. "|r")
            else
                DebugPrint(msg)
            end
        else
            debugprofilestop()
        end
        mainFrame._wnPerfMainTabSwitch = nil
        mainFrame._wnPerfTabSwitchPendingLog = nil
    elseif pendingPerfGen then
        debugprofilestop()
        mainFrame._wnPerfMainTabSwitch = nil
        mainFrame._wnPerfTabSwitchPendingLog = nil
    end
end

--============================================================================
-- TAB COUNT BADGES
--============================================================================
--- Update tab count badges next to nav labels.
---@param whichTab? string|nil If "currency" or "reputations", only refresh that badge (lighter than full counts pass).
function WarbandNexus:UpdateTabCountBadges(whichTab)
    if not mainFrame or not mainFrame.tabButtons then return end

    local counts = {}
    local needCurrency = (whichTab == nil or whichTab == "currency")
    local needReputations = (whichTab == nil or whichTab == "reputations")

    if needCurrency and ns.CurrencyCacheService and ns.CurrencyCacheService.GetAllCachedCurrencyIDs then
        local ids = ns.CurrencyCacheService:GetAllCachedCurrencyIDs()
        if ids then counts.currency = #ids end
    end

    if needReputations and ns.ReputationCacheService and ns.ReputationCacheService.GetCachedFactionCount then
        local ok, n = pcall(ns.ReputationCacheService.GetCachedFactionCount, ns.ReputationCacheService)
        if ok and type(n) == "number" then counts.reputations = n end
    end

    if whichTab then
        local btn = mainFrame.tabButtons[whichTab]
        local cl = btn and btn.countLabel
        if cl then
            local c = counts[whichTab]
            if c and c > 0 then
                cl:SetText("(" .. c .. ")")
                cl:Show()
            else
                cl:SetText("")
                cl:Hide()
            end
        end
        return
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

    local title = GetFontManager():CreateFontString(card, GetFontManager():GetFontRole("trackingRequiredBannerTitle"), "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -2)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.55, 0.45)
    title:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_TITLE"]) or "Character is not tracked")

    local desc = GetFontManager():CreateFontString(card, GetFontManager():GetFontRole("trackingRequiredBannerBody"), "OVERLAY")
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
    local accent = mainFrame.trackingStatusAccent
    local chip = mainFrame.trackingChip
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()

    local function BadgeOneLine(s)
        if not s or s == "" then return s end
        if issecretvalue and issecretvalue(s) then return "" end
        return (s:gsub("\n+", " "))
    end

    local function SizeTrackingChip()
        if not chip or not mainFrame.statusText then return end
        local tw = mainFrame.statusText:GetStringWidth() or 0
        -- 3px rail + 6 + 20 icon tile + 8 gap + text + right pad
        local w = 3 + 6 + 20 + 8 + tw + 10
        chip:SetWidth(math.max(96, math.min(280, w)))
    end

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
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_BANK"]) or "Bank is Active"))
            mainFrame.statusText:SetTextColor(0.75, 0.95, 0.82)
        elseif isTracked then
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_TRACKING"]) or "Tracking"))
            mainFrame.statusText:SetTextColor(0.82, 0.98, 0.88)
        else
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_UNTRACKED"]) or "Not Tracking"))
            mainFrame.statusText:SetTextColor(1, 0.72, 0.58)
        end
    end

    if accent then
        if isOpen or isTracked then
            accent:SetColorTexture(0.18, 0.88, 0.48, 1)
        else
            accent:SetColorTexture(0.95, 0.42, 0.22, 1)
        end
    end

    if isOpen then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.45, 1, 0.55)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["BANK_IS_ACTIVE"]) or "Bank is Active", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    elseif isTracked then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.45, 1, 0.55)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_ACTIVE_DESC"]) or "Data collection and updates are active.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    else
        if icon then
            local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
            if not ok then
                icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
            end
            icon:SetVertexColor(1, 0.55, 0.42)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_NOT_ENABLED_TOOLTIP"]) or "Character tracking is disabled.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to enable tracking.")
    end

    SizeTrackingChip()
end

-- REMOVED: UpdateFooter — empty stub with no callers.

--============================================================================
-- DRAW ITEM LIST
--============================================================================
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

-- REMOVED: WarbandNexus:SetItemsSubTab / GetItemsSubTab — unused; ns.UI_SetItemsSubTab / ns.UI_GetItemsSubTab are the live API.

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
    
    if not success and IsDebugModeEnabled and IsDebugModeEnabled() then
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
    local dbg = IsDebugModeEnabled and IsDebugModeEnabled()
    if dbg then
    end
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
                if dbg then
                end
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
    if IsDebugModeEnabled and IsDebugModeEnabled() then
    end
    -- Show custom settings UI (renders AceConfig with themed widgets)
    if self.ShowSettings then
        self:ShowSettings()
    elseif ns.ShowSettings then
        ns.ShowSettings()
    else
        -- No settings UI available (ShowSettings should always exist)
        self:Print("|cff9370DB[Warband Nexus]|r " .. ((ns.L and ns.L["SETTINGS_UI_UNAVAILABLE"]) or "Settings UI not available. Try /wn to open the main window."))
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
    local wipe = table.wipe
    local overlayLabelParts = {}

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
            loadText = ns.FontManager:CreateFontString(bar, ns.FontManager:GetFontRole("loadingBarPrimaryText"), "OVERLAY")
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
            progText = ns.FontManager:CreateFontString(bar, ns.FontManager:GetFontRole("loadingBarSecondaryText"), "OVERLAY")
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

        -- Pending labels (GetPendingLabels returns ephemeral reused table — copy only what we display)
        local pending = LT:GetPendingLabels()
        local labelStr = ""
        if #pending > 0 then
            local shown = math.min(#pending, 2)
            wipe(overlayLabelParts)
            for i = 1, shown do
                overlayLabelParts[i] = pending[i]
            end
            labelStr = table.concat(overlayLabelParts, ", ", 1, shown)
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
                        -- Avoid leaving the sync bar visible forever if LoadingTracker never completes (e.g. rare init errors)
                        if loadingOverlay and loadingOverlay:IsShown() then
                            if loadingOverlay.spinGroup then loadingOverlay.spinGroup:Stop() end
                            loadingOverlay:Hide()
                        end
                        return
                    end
                    UpdateLoadingOverlay()
                end)
            end
        end)
    end)
end
