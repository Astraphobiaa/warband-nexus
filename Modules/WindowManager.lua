--[[
    Warband Nexus - Window Manager
    Centralized window lifecycle management for all addon frames.

    Responsibilities:
    - Hierarchical ESC close: popups first, then floating windows, then main window.
    - Combat safety: hide all windows on PLAYER_REGEN_DISABLED, restore on PLAYER_REGEN_ENABLED.
    - Standardized frame strata/level assignment.
    - Single ESC key handler pattern (avoids UISpecialFrames taint issues).
    - ToggleGameMenu: use hooksecurefunc ONLY — never replace the global with addon Lua; that
      taints ESC and Blizzard’s ToggleGameMenu then fails on protected calls (e.g. SpellStopCasting).

    Usage:
        ns.WindowManager:Register(frame, priority, closeFunc)
        ns.WindowManager:Unregister(frame)
        ns.WindowManager:InstallESCHandler(frame)

    Priority levels (higher = closes first on ESC):
        MAIN     = 10   -- Main addon window
        FLOATING = 20   -- Companion/detail windows (ProfessionInfo, RecipeCompanion, PlansTracker)
        POPUP    = 30   -- Dialogs, popups (GoldManagement, InformationDialog, TryCountPopup, etc.)
]]

local ADDON_NAME, ns = ...

local WindowManager = {}
ns.WindowManager = WindowManager

---Chat debug (Lua 5.1): only when WarbandNexus.db.profile.debugMode is on.
local function DebugWarbandEsc(msg, ...)
    local W = rawget(_G, "WarbandNexus")
    local db = W and W.db and W.db.profile
    if not (db and db.debugMode) then return end
    if not (W and W.Print) then return end
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, msg, ...)
        text = ok and s or tostring(msg)
    else
        text = tostring(msg)
    end
    W:Print("|cff00ccff[WN ESC]|r " .. text)
end

-- Priority constants
WindowManager.PRIORITY = {
    MAIN     = 10,
    FLOATING = 20,
    POPUP    = 30,
}

-- Recommended strata/level per priority tier
-- WoW strata order: FULLSCREEN_DIALOG > FULLSCREEN > DIALOG > HIGH > MEDIUM > LOW > BACKGROUND
-- MAIN uses MEDIUM so default Blizzard panels (same strata) and HIGH-strata windows (bags, bank)
-- can stack above the addon when focused — avoids trapping the UI under a DIALOG-layer main frame.
-- FLOATING sits in HIGH so it stays above MAIN without needing FULLSCREEN_DIALOG.
WindowManager.STRATA = {
    [10] = { strata = "MEDIUM",             level = 50 },
    [20] = { strata = "HIGH",               level = 120 },
    [30] = { strata = "FULLSCREEN_DIALOG", level = 300 },
}

-- Internal registry: { { frame, priority, closeFunc, wasVisibleBeforeCombat } }
local registry = {}

-- ============================================================================
-- REGISTRATION
-- ============================================================================

--[[
    Register a window with the manager.

    @param frame      Frame   - The window frame
    @param priority   number  - Priority level (use WindowManager.PRIORITY constants)
    @param closeFunc  function|nil - Custom close function (default: frame:Hide())
]]
function WindowManager:Register(frame, priority, closeFunc)
    if not frame then return end
    -- Remove existing entry for same frame (re-registration)
    self:Unregister(frame)
    registry[#registry + 1] = {
        frame    = frame,
        priority = priority or self.PRIORITY.FLOATING,
        closeFunc = closeFunc,
        wasVisibleBeforeCombat = false,
    }
end

function WindowManager:Unregister(frame)
    if not frame then return end
    for i = #registry, 1, -1 do
        if registry[i].frame == frame then
            table.remove(registry, i)
        end
    end
end

-- ============================================================================
-- ESC HIERARCHY
-- ============================================================================

--[[
    Close the highest-priority visible window.
    @return boolean - true if a window was closed, false if nothing to close
]]
function WindowManager:CloseTopWindow()
    -- Pick the topmost visible window: highest priority, then highest FrameLevel,
    -- then latest registration index (typical "opened last" among equal strata).
    local best = nil
    local bestPriority = -1
    local bestLevel = -1
    local bestIndex = 0
    for i = 1, #registry do
        local entry = registry[i]
        local frame = entry.frame
        if frame and frame:IsShown() then
            local p = entry.priority
            local lvl = frame:GetFrameLevel() or 0
            if p > bestPriority
                or (p == bestPriority and lvl > bestLevel)
                or (p == bestPriority and lvl == bestLevel and i > bestIndex) then
                best = entry
                bestPriority = p
                bestLevel = lvl
                bestIndex = i
            end
        end
    end
    if best then
        if best.frame and best.frame.GetName and best.frame:GetName() == "WarbandNexusSettingsPanel" then
            DebugWarbandEsc("[H3] CloseTopWindow picked WarbandNexusSettingsPanel (pri=%s)", tostring(best.priority))
        end
        if best.closeFunc then
            best.closeFunc()
        else
            best.frame:Hide()
        end
        return true
    end
    -- #region agent log
    do
        local sp = _G.WarbandNexusSettingsPanel
        local W = rawget(_G, "WarbandNexus")
        local db = W and W.db and W.db.profile
        if sp and sp.IsShown and sp:IsShown() and db and db.debugMode and W and W.Print then
            W:Print("|cff00ffff[WN ESC H5]|r CloseTopWindow: no registry candidate but WarbandNexusSettingsPanel is still shown (hypothesis: unregistered).")
        end
    end
    -- #endregion agent log
    return false
end

--[[
    Install the standardized ESC key handler on a frame.
    This replaces UISpecialFrames and individual OnKeyDown handlers.

    The handler calls CloseTopWindow() which respects the priority hierarchy:
    - If a popup is open, ESC closes the popup (not the floating/main window)
    - If only the main window is open, ESC closes the main window
    - If nothing is open, ESC propagates to the game (opens Game Menu)
]]
function WindowManager:InstallESCHandler(frame)
    if not frame then return end
    if not InCombatLockdown() then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    frame:SetScript("OnKeyDown", function(self, key)
        -- #region agent log
        do
            local W = rawget(_G, "WarbandNexus")
            local db = W and W.db and W.db.profile
            local settingsShown = _G.WarbandNexusSettingsPanel and _G.WarbandNexusSettingsPanel:IsShown()
            if db and db.debugMode and W and W.Print and settingsShown and self.GetName then
                local n = self:GetName()
                local interesting = (key == "ESCAPE" or key == "W" or key == "A" or key == "S" or key == "D" or key == "SPACE")
                if n == "WarbandNexusFrame" and interesting then
                    local prop = (self.IsPropagateKeyboardInput and self:IsPropagateKeyboardInput()) and "true" or "false"
                    W:Print("|cff00ffff[WN ESC H9]|r Main OnKeyDown while Settings open: key=" .. tostring(key) .. " propagate=" .. prop)
                end
            end
        end
        -- #endregion agent log
        if key == "ESCAPE" then
            -- #region agent log
            do
                local W = rawget(_G, "WarbandNexus")
                local db = W and W.db and W.db.profile
                if db and db.debugMode and W and W.Print and self.GetName
                    and self:GetName() == "WarbandNexusSettingsPanel" then
                    W:Print("|cff00ffff[WN ESC H6]|r InstallESCHandler: ESC reached WarbandNexusSettingsPanel OnKeyDown")
                end
            end
            -- #endregion agent log
            -- Consume ESC first, then close. If nothing closed, re-propagate.
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            local closed = ns.WindowManager:CloseTopWindow()
            if closed then
                -- Block the parallel Blizzard ESC path (ToggleGameMenu / CloseAllWindows hooks)
                -- from closing a second frame on the same ESC press.
                ns._wnEscJustHandled = true
                C_Timer.After(0, function() ns._wnEscJustHandled = nil end)
            end
            if not InCombatLockdown() then
                if closed then
                    -- Leaving propagate false on the key receiver (e.g. main window) breaks
                    -- further ESC / bindings. Restore next frame even if this frame hid itself.
                    C_Timer.After(0, function()
                        if self and self.SetPropagateKeyboardInput and not InCombatLockdown() then
                            self:SetPropagateKeyboardInput(true)
                        end
                    end)
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)
end

-- ============================================================================
-- STRATA / LEVEL HELPERS
-- ============================================================================

--[[
    Apply the recommended strata and level for a given priority.
    @param frame    Frame  - The window frame
    @param priority number - Priority level (MAIN, FLOATING, POPUP)
]]
function WindowManager:ApplyStrata(frame, priority)
    if not frame then return end
    local config = self.STRATA[priority]
    if config then
        frame:SetFrameStrata(config.strata)
        frame:SetFrameLevel(config.level)
    end
end

-- ============================================================================
-- COMBAT HIDE / RESTORE
-- ============================================================================

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: hide all visible addon windows, remember state
        for i = 1, #registry do
            local entry = registry[i]
            if entry.frame and entry.frame:IsShown() then
                entry.wasVisibleBeforeCombat = true
                entry.frame:Hide()
            else
                entry.wasVisibleBeforeCombat = false
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: restore windows that were visible before combat
        for i = 1, #registry do
            local entry = registry[i]
            if entry.wasVisibleBeforeCombat and entry.frame then
                entry.frame:Show()
                -- Re-enable keyboard after combat restore (EnableKeyboard is not sticky across Hide/Show).
                -- Settings panel intentionally keeps keyboard off so the game binding stack keeps working.
                if not InCombatLockdown() then
                    local skipKb = entry.frame.GetName and entry.frame:GetName() == "WarbandNexusSettingsPanel"
                    if not skipKb then
                        if entry.frame.EnableKeyboard then
                            entry.frame:EnableKeyboard(true)
                        end
                        if entry.frame.SetPropagateKeyboardInput then
                            entry.frame:SetPropagateKeyboardInput(true)
                        end
                    elseif entry.frame.EnableKeyboard then
                        entry.frame:EnableKeyboard(false)
                    end
                end
                entry.wasVisibleBeforeCombat = false
            end
        end
    end
end)

-- ============================================================================
-- DRAG PROTECTION HELPER
-- ============================================================================

local function StartScaledDrag(dragFrame, moveFrame)
    local left = moveFrame:GetLeft()
    local top = moveFrame:GetTop()
    if not left or not top then return end

    local frameScale = moveFrame:GetEffectiveScale() or 1
    if frameScale <= 0 then frameScale = 1 end

    local cx, cy = GetCursorPosition()
    local leftPx = left * frameScale
    local topPx = top * frameScale

    dragFrame._wnDragState = {
        moveFrame = moveFrame,
        frameScale = frameScale,
        offsetX = cx - leftPx,
        offsetY = cy - topPx,
    }

    dragFrame:SetScript("OnUpdate", function(self)
        local state = self._wnDragState
        if not state then
            self:SetScript("OnUpdate", nil)
            return
        end
        local x, y = GetCursorPosition()
        local newLeft = (x - state.offsetX) / state.frameScale
        local newTop = (y - state.offsetY) / state.frameScale
        state.moveFrame:ClearAllPoints()
        state.moveFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
end

local function StopScaledDrag(dragFrame)
    dragFrame._wnDragState = nil
    dragFrame:SetScript("OnUpdate", nil)
end

--[[
    Install combat-safe, scale-correct drag handlers on a header/drag frame.
    Keeps cursor-grab point stable at any UI/frame scale.

    @param dragFrame Frame - The frame that receives drag events
    @param moveFrame Frame - The frame to move (usually the parent window)
    @param onDragStop function|nil - Optional callback after drag stops
]]
function WindowManager:InstallDragHandler(dragFrame, moveFrame, onDragStop)
    if not dragFrame or not moveFrame then return end
    dragFrame:EnableMouse(true)
    dragFrame:RegisterForDrag("LeftButton")
    dragFrame:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            StartScaledDrag(dragFrame, moveFrame)
        end
    end)
    dragFrame:SetScript("OnDragStop", function()
        StopScaledDrag(dragFrame)
        if onDragStop then
            onDragStop(moveFrame)
        end
    end)
end

-- ============================================================================
-- ESC BINDING (ToggleGameMenu) — works without frame keyboard focus
-- ============================================================================
--
-- NEVER assign _G.ToggleGameMenu = function() ... prev() end from addon code: that taints the
-- binding path and Blizzard’s implementation can hit ADDON_ACTION_FORBIDDEN on protected
-- calls (e.g. SpellStopCasting in UIParent). hooksecurefunc runs *after* the secure original,
-- so the Blizzard function keeps a clean execution path; we then apply the same hierarchy
-- as frame OnKeyDown (CloseTopWindow) and dismiss the game menu if we closed an addon window.

local toggleGameMenuEscHooked = false

local function DismissGameMenuIfOpen()
    local gf = _G.GameMenuFrame
    if not gf or not gf.IsShown or not gf:IsShown() then return end
    if HideUIPanel then
        pcall(HideUIPanel, gf)
    elseif gf.Hide then
        pcall(function() gf:Hide() end)
    end
end

local function InstallToggleGameMenuEscPostHook()
    if toggleGameMenuEscHooked or type(hooksecurefunc) ~= "function" then return end
    if type(_G.ToggleGameMenu) ~= "function" then return end
    toggleGameMenuEscHooked = true
    hooksecurefunc("ToggleGameMenu", function()
        -- #region agent log
        do
            local W = rawget(_G, "WarbandNexus")
            local db = W and W.db and W.db.profile
            if db and db.debugMode and W and W.Print then
                W:Print("|cff00ffff[WN ESC H1a]|r ToggleGameMenu post-hook ran (ESC/game menu path).")
            end
        end
        -- #endregion agent log
        -- Settings panel: close explicitly first (registry / priority edge cases in some builds).
        local sp = _G.WarbandNexusSettingsPanel
        if sp and sp:IsShown() then
            -- #region agent log
            do
                local W = rawget(_G, "WarbandNexus")
                local db = W and W.db and W.db.profile
                if db and db.debugMode and W and W.Print then
                    local n, found = 0, false
                    for i = 1, #registry do
                        local fr = registry[i].frame
                        if fr then
                            n = n + 1
                            if fr == sp then found = true end
                        end
                    end
                    W:Print("|cff00ffff[WN ESC H1b]|r Settings open during ToggleGameMenu — registry_has_panel="
                        .. tostring(found) .. " registry_count=" .. tostring(n))
                end
            end
            -- #endregion agent log
            do
                local W = rawget(_G, "WarbandNexus")
                if W and W.Print then
                    W:Print("|cff00ccff[WN DIAG]|r ESC → ToggleGameMenu: closing Warband Nexus Settings")
                end
            end
            DebugWarbandEsc("ToggleGameMenu post-hook: Hide WarbandNexusSettingsPanel")
            sp:Hide()
            DismissGameMenuIfOpen()
            return
        end
        -- Main frame's InstallESCHandler already consumed this ESC and closed a window in the
        -- same key event. Don't let the fallback close another frame on the same ESC press.
        if ns._wnEscJustHandled then
            DismissGameMenuIfOpen()
            return
        end
        if WindowManager:CloseTopWindow() then
            DismissGameMenuIfOpen()
        end
    end)
end

local function TryInstallToggleGameMenuHook()
    if toggleGameMenuEscHooked then return true end
    InstallToggleGameMenuEscPostHook()
    return toggleGameMenuEscHooked
end

-- ESC stack (e.g. 11.x): may call CloseAllWindows / CloseWindows without ToggleGameMenu when a
-- FULLSCREEN_DIALOG panel is up — still close our settings panel after Blizzard runs theirs.
local closeAllWindowsEscHooked = false
local closeWindowsEscHooked = false

local function InstallCloseStackEscHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local function afterCloseStack()
        if ns._wnEscJustHandled then return end
        local sp = _G.WarbandNexusSettingsPanel
        if sp and sp:IsShown() then
            -- #region agent log
            do
                local W = rawget(_G, "WarbandNexus")
                local db = W and W.db and W.db.profile
                if db and db.debugMode and W and W.Print then
                    W:Print("|cff00ffff[WN ESC H4]|r CloseAllWindows/CloseWindows post-hook ran while Settings visible → Hide")
                end
            end
            -- #endregion agent log
            DebugWarbandEsc("CloseAllWindows/CloseWindows post-hook: Hide WarbandNexusSettingsPanel")
            sp:Hide()
            DismissGameMenuIfOpen()
        end
    end
    if not closeAllWindowsEscHooked and type(_G.CloseAllWindows) == "function" then
        closeAllWindowsEscHooked = true
        hooksecurefunc("CloseAllWindows", afterCloseStack)
    end
    if not closeWindowsEscHooked and type(_G.CloseWindows) == "function" then
        closeWindowsEscHooked = true
        hooksecurefunc("CloseWindows", afterCloseStack)
    end
end

-- Install as soon as ToggleGameMenu exists; retry across events so /reload and load order never miss it.
TryInstallToggleGameMenuHook()
InstallCloseStackEscHooks()
C_Timer.After(0, function()
    TryInstallToggleGameMenuHook()
    InstallCloseStackEscHooks()
end)
C_Timer.After(1, function()
    TryInstallToggleGameMenuHook()
    InstallCloseStackEscHooks()
end)

local escHookBootstrap = CreateFrame("Frame")
escHookBootstrap:RegisterEvent("PLAYER_LOGIN")
escHookBootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
escHookBootstrap:RegisterEvent("ADDON_LOADED")
escHookBootstrap:SetScript("OnEvent", function()
    InstallCloseStackEscHooks()
    if TryInstallToggleGameMenuHook() then
        escHookBootstrap:UnregisterAllEvents()
    end
end)
