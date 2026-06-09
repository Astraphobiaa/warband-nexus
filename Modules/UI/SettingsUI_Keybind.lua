--[[
    Warband Nexus - Settings toggle keybind helpers + capture stop hook.
    Split from SettingsUI.lua (Lua 5.1 local limit).
    Loaded before Modules/UI/SettingsUI.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus

local state = {
    stopListening = nil,
    button = nil,
}

ns.SettingsKeybind = ns.SettingsKeybind or {}

ns.SettingsKeybind.IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

function ns.SettingsKeybind.GetToggleBindingDisplayText()
    local key = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        and WarbandNexus.db.profile.toggleKeybind
    if not key or key == "" then
        return (ns.L and ns.L["KEYBINDING_UNBOUND"]) or "Not set"
    end
    return (GetBindingText and GetBindingText(key)) or key
end

function ns.SettingsKeybind.IsForbiddenToggleKeybind(key)
    if not key or key == "" then return false end
    local k = tostring(key):upper()
    return (k == "ESC" or k == "ESCAPE" or k == "ESCAPEKEY")
end

function ns.SettingsKeybind.SaveToggleKeybind(key)
    if not WarbandNexus or not WarbandNexus.db then return false end
    if ns.SettingsKeybind.IsForbiddenToggleKeybind(key) then
        WarbandNexus.db.profile.toggleKeybind = nil
        if WarbandNexus.ApplyToggleKeybind then
            WarbandNexus:ApplyToggleKeybind()
        end
        if WarbandNexus.Print then
            WarbandNexus:Print("|cffff6600Toggle keybind cannot be ESC. Binding cleared.|r")
        end
        return false
    end
    WarbandNexus.db.profile.toggleKeybind = key
    if WarbandNexus.ApplyToggleKeybind then
        WarbandNexus:ApplyToggleKeybind()
    end
    return true
end

function ns.SettingsKeybind.RegisterCaptureHooks(stopListeningFn, button)
    state.stopListening = stopListeningFn
    state.button = button
end

function WarbandNexus:StopSettingsKeybindCapture()
    if state.stopListening then
        state.stopListening()
    end
    if state.button and state.button.EnableKeyboard then
        state.button:EnableKeyboard(false)
    end
    local mf = _G.WarbandNexusFrame
    if mf and mf:IsShown() and not InCombatLockdown() then
        if mf.EnableKeyboard then
            mf:EnableKeyboard(true)
        end
        if mf.SetPropagateKeyboardInput then
            mf:SetPropagateKeyboardInput(true)
        end
    end
end
