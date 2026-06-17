--[[
    Warband Nexus — toast FX tier only (motion stays in NotificationManager slide-in).
    Default is minimal: no sun burst, no icon bounce, no border strobe.
]]

local ADDON_NAME, ns = ...

local ToastFx = {}
ns.NotificationToastFx = ToastFx

---@param config table ShowModalNotification config
---@return string tier minimal | celebration | standard
function ToastFx.InferTier(config)
    if not config then return "minimal" end
    if config.toastFxTier then return config.toastFxTier end
    if config.planReminderToast then return "minimal" end
    if config.compact then return "minimal" end
    -- Full earned / loot panel: one soft sheen pass (no star burst).
    return "standard"
end

---Reserved; prior icon/border pulses removed (too noisy).
function ToastFx.PlayAccentEffects(_toastHost, _tier)
end
