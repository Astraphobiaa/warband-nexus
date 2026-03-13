--[[
    Warband Nexus - Window Manager
    Centralized window lifecycle management for all addon frames.

    Responsibilities:
    - Hierarchical ESC close: popups first, then floating windows, then main window.
    - Combat safety: hide all windows on PLAYER_REGEN_DISABLED, restore on PLAYER_REGEN_ENABLED.
    - Standardized frame strata/level assignment.
    - Single ESC key handler pattern (avoids UISpecialFrames taint issues).

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

-- Priority constants
WindowManager.PRIORITY = {
    MAIN     = 10,
    FLOATING = 20,
    POPUP    = 30,
}

-- Recommended strata/level per priority tier
-- WoW strata order: FULLSCREEN_DIALOG > DIALOG > HIGH > MEDIUM > LOW > BACKGROUND
-- FLOATING must be same strata as MAIN (DIALOG) but higher level to appear on top.
WindowManager.STRATA = {
    [10] = { strata = "DIALOG",            level = 100 },
    [20] = { strata = "DIALOG",            level = 200 },
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
    local best = nil
    local bestPriority = -1
    for i = 1, #registry do
        local entry = registry[i]
        if entry.frame and entry.frame:IsShown() and entry.priority > bestPriority then
            best = entry
            bestPriority = entry.priority
        end
    end
    if best then
        if best.closeFunc then
            best.closeFunc()
        else
            best.frame:Hide()
        end
        return true
    end
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
        if key == "ESCAPE" then
            -- Consume ESC first, then close. If nothing closed, re-propagate.
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            if not ns.WindowManager:CloseTopWindow() then
                -- Nothing to close — let ESC reach the Game Menu
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
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
                -- Re-enable keyboard input after combat restore
                if not InCombatLockdown() and entry.frame.SetPropagateKeyboardInput then
                    entry.frame:SetPropagateKeyboardInput(true)
                end
                entry.wasVisibleBeforeCombat = false
            end
        end
    end
end)

-- ============================================================================
-- DRAG PROTECTION HELPER
-- ============================================================================

--[[
    Install combat-safe drag handlers on a header/drag frame.
    Prevents StartMoving/StartSizing during combat lockdown.

    @param dragFrame Frame - The frame that receives drag events
    @param moveFrame Frame - The frame to move (usually the parent window)
]]
function WindowManager:InstallDragHandler(dragFrame, moveFrame)
    if not dragFrame or not moveFrame then return end
    dragFrame:EnableMouse(true)
    dragFrame:RegisterForDrag("LeftButton")
    dragFrame:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            moveFrame:StartMoving()
        end
    end)
    dragFrame:SetScript("OnDragStop", function()
        moveFrame:StopMovingOrSizing()
    end)
end
