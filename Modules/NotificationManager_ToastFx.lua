--[[
    Warband Nexus — toast FX tier + entrance accents (motion stays in NotificationManager slide-in).
    Every toast gets an entrance accent; intensity scales with tier (minimal < standard < celebration).
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

-- Entrance accents layered on top of the sheen / sun burst. One shot each, created per
-- toast (toast hosts are not pooled, so the layers die with the toast).
local WHITE_TEX = "Interface\\BUTTONS\\WHITE8X8"
local EDGE_CORE_PX = 2      -- bright rim, in physical pixels
local EDGE_SOFT_PX = 7      -- soft inner falloff band, in physical pixels
local EDGE_SOFT_ALPHA = 0.32

local function CreateFxLayer(toastHost, w, h, frameLevel)
    local TF = ns.NotificationToastFactory
    if not (TF and TF.CreateToastLayer) then return nil end
    local layer = TF:CreateToastLayer(toastHost, w, h)
    layer:SetAllPoints(toastHost)
    layer:SetFrameLevel(frameLevel)
    layer:SetClipsChildren(true)
    layer:EnableMouse(false)
    if layer.SetIgnoreParentAlpha then layer:SetIgnoreParentAlpha(true) end
    return layer
end

local function AddEdgeBand(layer, side, thickness, r, g, b, a)
    local t = layer:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE_TEX)
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, b, a)
    if side == "TOP" or side == "BOTTOM" then
        t:SetPoint(side .. "LEFT", layer, side .. "LEFT", 0, 0)
        t:SetPoint(side .. "RIGHT", layer, side .. "RIGHT", 0, 0)
        t:SetHeight(thickness)
    else
        t:SetPoint("TOP" .. side, layer, "TOP" .. side, 0, 0)
        t:SetPoint("BOTTOM" .. side, layer, "BOTTOM" .. side, 0, 0)
        t:SetWidth(thickness)
    end
    return t
end

local EDGE_SIDES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

---Accent-colored rim flare: the toast border lights up, holds briefly, then fades.
---@param toastHost Frame
---@param w number
---@param h number
---@param peak number 0..1 overall intensity
function ToastFx.PlayEdgeGlow(toastHost, w, h, peak)
    if not toastHost or not w or not h or not peak or peak <= 0 then return end
    local layer = CreateFxLayer(toastHost, w, h, 5)
    if not layer then return end
    local accent = toastHost._toastFxAccent
    local r = (accent and accent[1]) or 1
    local g = (accent and accent[2]) or 0.82
    local b = (accent and accent[3]) or 0.3
    local px = (ns.GetPixelScale and ns.GetPixelScale(layer)) or 1
    for i = 1, #EDGE_SIDES do
        local side = EDGE_SIDES[i]
        AddEdgeBand(layer, side, EDGE_CORE_PX * px, r, g, b, 1)
        AddEdgeBand(layer, side, EDGE_SOFT_PX * px, r, g, b, EDGE_SOFT_ALPHA)
    end
    layer:SetAlpha(0)

    local ag = layer:CreateAnimationGroup()
    ag:SetScript("OnFinished", function() layer:Hide() end)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(peak)
    fadeIn:SetDuration(0.12)
    fadeIn:SetSmoothing("OUT")
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(peak)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.65)
    fadeOut:SetStartDelay(0.22)
    fadeOut:SetSmoothing("IN")
    ag:Play()
end

---White additive flash over the toast icon.
---@param toastHost Frame
---@param peak number 0..1
function ToastFx.PlayIconFlash(toastHost, peak)
    local icon = toastHost and toastHost._toastFxIcon
    if not icon or not peak or peak <= 0 or not icon.GetWidth then return end
    local iw, ih = icon:GetWidth() or 0, icon:GetHeight() or 0
    if iw < 1 or ih < 1 then return end
    local w, h = toastHost:GetWidth() or 0, toastHost:GetHeight() or 0
    if w < 1 or h < 1 then return end
    local layer = CreateFxLayer(toastHost, w, h, 6)
    if not layer then return end
    local flash = layer:CreateTexture(nil, "OVERLAY")
    flash:SetTexture(WHITE_TEX)
    flash:SetBlendMode("ADD")
    flash:SetVertexColor(1, 1, 1, 1)
    flash:SetAllPoints(icon)
    layer:SetAlpha(0)

    local ag = layer:CreateAnimationGroup()
    ag:SetScript("OnFinished", function() layer:Hide() end)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(peak)
    fadeIn:SetDuration(0.06)
    fadeIn:SetStartDelay(0.08)
    fadeIn:SetSmoothing("OUT")
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(peak)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.4)
    fadeOut:SetStartDelay(0.14)
    fadeOut:SetSmoothing("IN")
    ag:Play()
end
