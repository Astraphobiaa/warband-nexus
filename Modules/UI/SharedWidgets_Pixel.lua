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

assert(ns.GetPixelScale and ns.PixelSnap, "SharedWidgets_Pixel: pixel exports missing")
