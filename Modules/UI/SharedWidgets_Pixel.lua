--[[
    Warband Nexus - SharedWidgets pixel-scale helpers (ops-026 Phase 2 slice)
    Loaded before Modules/UI/SharedWidgets.lua; exports ns.GetPixelScale / PixelSnap / ResetPixelScale.
]]

local _, ns = ...

local mult = nil

local function GetPixelScale(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    else
        local resolution = GetCVar("gxWindowedResolution") or "1920x1080"
        local _, h = string.match(resolution, "(%d+)x(%d+)")
        h = tonumber(h)
        if h and h > 0 then physH = h end
    end

    local scaleTarget = frame or UIParent
    local effectiveScale = scaleTarget and scaleTarget.GetEffectiveScale and scaleTarget:GetEffectiveScale() or 1
    if not effectiveScale or effectiveScale <= 0 then effectiveScale = 1 end

    if not frame or frame == UIParent then
        if mult then return mult end
        mult = 768.0 / (physH * effectiveScale)
        return mult
    end

    return 768.0 / (physH * effectiveScale)
end

local function ResetPixelScale()
    mult = nil
end

local function PixelSnap(value)
    if not value then return 0 end
    local pixelScale = GetPixelScale()
    return math.floor(value / pixelScale + 0.5) * pixelScale
end

local scaleHandler = CreateFrame("Frame")
scaleHandler:RegisterEvent("UI_SCALE_CHANGED")
scaleHandler:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleHandler:SetScript("OnEvent", function()
    mult = nil
    C_Timer.After(0, function()
        if ns.UI_UpdateBorderColor and ns.BORDER_REGISTRY then
            for i = 1, #ns.BORDER_REGISTRY do
                local frame = ns.BORDER_REGISTRY[i]
                if frame and frame.BorderTop and not frame._wnMainShellBackdrop and not frame._wnBorderlessSurface then
                    local pixelScale = GetPixelScale(frame)
                    frame.BorderTop:SetHeight(pixelScale)
                    frame.BorderBottom:SetHeight(pixelScale)
                    frame.BorderLeft:ClearAllPoints()
                    frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                    frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                    frame.BorderLeft:SetWidth(pixelScale)
                    frame.BorderRight:ClearAllPoints()
                    frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                    frame.BorderRight:SetWidth(pixelScale)
                end
            end
        end
    end)
end)

ns.GetPixelScale = GetPixelScale
ns.PixelSnap = PixelSnap
ns.ResetPixelScale = ResetPixelScale

-- ADDON UI SCALE (profile.uiScale — separate from WoW UI Scale / font slider)

local UISCALE_MIN = 0.6
local UISCALE_MAX = 1.5
local SCALE_REGISTRY = {}

local function ClampAddonUIScale(scale)
    scale = tonumber(scale) or 1.0
    return math.max(UISCALE_MIN, math.min(UISCALE_MAX, scale))
end

function ns.UI_GetAddonUIScale()
    local db = ns.db and ns.db.profile
    return ClampAddonUIScale(db and db.uiScale)
end

function ns.UI_ApplyAddonUIScale(frame)
    if not frame or not frame.SetScale then return end
    frame:SetScale(ns.UI_GetAddonUIScale())
end

function ns.UI_RegisterScaledFrame(frame)
    if not frame then return end
    for i = 1, #SCALE_REGISTRY do
        if SCALE_REGISTRY[i] == frame then
            ns.UI_ApplyAddonUIScale(frame)
            return
        end
    end
    table.insert(SCALE_REGISTRY, frame)
    ns.UI_ApplyAddonUIScale(frame)
end

function ns.UI_UnregisterScaledFrame(frame)
    if not frame then return end
    for i = #SCALE_REGISTRY, 1, -1 do
        if SCALE_REGISTRY[i] == frame then
            table.remove(SCALE_REGISTRY, i)
            return
        end
    end
end

--- Re-apply profile.uiScale to main shell and every registered external window.
function ns.UI_ApplyAddonUIScaleToAll()
    local scale = ns.UI_GetAddonUIScale()
    for i = #SCALE_REGISTRY, 1, -1 do
        local f = SCALE_REGISTRY[i]
        if not f or not f.SetScale then
            table.remove(SCALE_REGISTRY, i)
        else
            f:SetScale(scale)
        end
    end
    local mf = ns.WarbandNexus and ns.WarbandNexus.UI and ns.WarbandNexus.UI.mainFrame
    if mf and mf.SetScale then
        mf:SetScale(scale)
    end
end

assert(ns.GetPixelScale and ns.PixelSnap, "SharedWidgets_Pixel: pixel exports missing")
assert(ns.UI_GetAddonUIScale and ns.UI_ApplyAddonUIScaleToAll, "SharedWidgets_Pixel: UIScale exports missing")
