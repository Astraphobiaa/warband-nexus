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

-- Stripped in the order the capture handler writes them (ALT-CTRL-SHIFT-KEY).
local KEYBIND_MODIFIER_PREFIXES = { "ALT-", "CTRL-", "SHIFT-" }
local KEYBIND_SEPARATOR = " - "

--- Readable form of a stored binding: modifier tokens and the base key joined by a spaced
--- separator. WoW stores the combo with "-" as the separator, so binding CTRL + the "-" key
--- produces "CTRL--", where the separator and the key itself are indistinguishable and the combo
--- looks truncated. Splitting on the known prefixes renders that as "CTRL - -".
--- Formatted from the stored key rather than GetBindingText: an in-game dump showed the API
--- returns the key unchanged here ("CTRL-C" -> "CTRL-C"), so it added nothing but client-dependent
--- surprises - passing its documented "KEY_" prefix collapsed the whole combo to "c--".
---@param key string|nil Stored binding, e.g. "CTRL-C", "CTRL--", "ALT-CTRL-SHIFT-F1"
---@return string|nil
function ns.SettingsKeybind.FormatBindingCombo(key)
    if type(key) ~= "string" or key == "" then
        return key
    end
    local parts = {}
    local rest = key
    for i = 1, #KEYBIND_MODIFIER_PREFIXES do
        local prefix = KEYBIND_MODIFIER_PREFIXES[i]
        if rest:sub(1, #prefix) == prefix and #rest > #prefix then
            parts[#parts + 1] = prefix:sub(1, #prefix - 1)
            rest = rest:sub(#prefix + 1)
        end
    end
    parts[#parts + 1] = rest
    return table.concat(parts, KEYBIND_SEPARATOR)
end

function ns.SettingsKeybind.GetToggleBindingDisplayText()
    local key = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        and WarbandNexus.db.profile.toggleKeybind
    if not key or key == "" then
        return (ns.L and ns.L["KEYBINDING_UNBOUND"]) or "Not set"
    end
    return ns.SettingsKeybind.FormatBindingCombo(key) or key
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
