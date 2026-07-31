--[[
    Warband Nexus — toast FX tier only (motion stays in NotificationManager slide-in).
    Default is minimal: no sun burst, no icon bounce, no border strobe.
]]

local ADDON_NAME, ns = ...

local ToastFx = {}
ns.NotificationToastFx = ToastFx

-- "You earned/obtained something permanent" moments read as achievements: these get the full
-- celebration (radial sun burst + sheen sweep) even in the compact toast layout. Everything
-- else (currency, reputation, plan/vault progress, reminders, criteria) stays quiet.
local CELEBRATION_NOTIF_TYPES = {
    achievement = true,
    title = true,
    mount = true,
    pet = true,
    toy = true,
    illusion = true,
    tryCounter = true,
}

---@param notifType string|nil
---@return boolean
function ToastFx.IsCelebrationNotif(notifType)
    return type(notifType) == "string" and CELEBRATION_NOTIF_TYPES[notifType] == true
end

---@param config table ShowModalNotification config
---@return string tier minimal | celebration | standard
function ToastFx.InferTier(config)
    if not config then return "minimal" end
    if config.toastFxTier then return config.toastFxTier end
    if config.planReminderToast then return "minimal" end
    -- Earned/obtained collectibles + achievements celebrate even in the compact layout.
    if ToastFx.IsCelebrationNotif(config.notifType) then return "celebration" end
    if config.compact then return "minimal" end
    -- Full earned / loot panel: one soft sheen pass (no star burst).
    return "standard"
end

---Reserved; prior icon/border pulses removed (too noisy).
function ToastFx.PlayAccentEffects(_toastHost, _tier)
end
