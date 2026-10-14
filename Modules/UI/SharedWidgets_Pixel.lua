--[[
    Warband Nexus - SharedWidgets pixel-scale helpers (ops-026 Phase 2 slice)
    Loaded before Modules/UI/SharedWidgets.lua; exports ns.GetPixelScale / PixelSnap / ResetPixelScale.
]]

local _, ns = ...

local mult = nil
-- Physical screen height, cached: GetPixelScale runs on every pixel-perfect SetPoint/SetSize.
-- Cleared with `mult` on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED (ResetPixelScale).
local cachedPhysH = nil

local function ReadPhysicalHeight()
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
    return physH
end

local function GetPixelScale(frame)
    local physH = cachedPhysH
    if not physH then
        physH = ReadPhysicalHeight()
        cachedPhysH = physH
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
    cachedPhysH = nil
end

--- Snap to the physical pixel grid. Pass the frame the value lives in: inside a
--- frame scaled by profile.uiScale the grid differs from UIParent's.
local function PixelSnap(value, frame)
    if not value then return 0 end
    local pixelScale = GetPixelScale(frame)
    return math.floor(value / pixelScale + 0.5) * pixelScale
end

--- Round a UI-unit length to a whole number of physical pixels on frame's grid.
--- A rule 1.33px thick renders as 1 or 2px depending on its sub-pixel offset.
local function PixelRound(value, frame, minPixels)
    local pixelScale = GetPixelScale(frame)
    local n = math.floor((value or 0) / pixelScale + 0.5)
    if minPixels and n < minPixels then n = minPixels end
    return n * pixelScale
end

--- Card/container border thickness: 1 UI unit rounded to whole physical pixels (min 1).
--- Keeps the visual weight of the original 1-unit border on every display (2px on a
--- high-DPI screen at ~0.6 scale, 1px at 1080p) while every edge stays crisp.
local function GetBorderThickness(frame)
    return PixelRound(1, frame, 1)
end

--- Solid rule/border textures: exact physical-pixel thickness with grid snapping OFF.
--- Matches ElvUI (Toolkit DisablePixelSnap) and EllesmereUI (PP.CreateBorder): with snapping on,
--- a 1px strip at a fractional offset rounds to 0 and VANISHES or doubles as the window moves.
--- Crispness comes from pixel-aligned positions (PixelSnap), not from the engine snap.
local function SnapRuleTexture(tex)
    if not tex or not tex.SetSnapToPixelGrid then return end
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

-- Rules sized by UI_SetRuleThickness: region -> { orientation, pixels }. Weak keys so
-- released/garbage frames drop out; re-sized on UI/addon scale changes.
local RULE_REGISTRY = setmetatable({}, { __mode = "k" })

local function ApplyRuleThickness(region, orientation, pixels)
    -- Textures take their grid from the owning frame.
    local host = region
    if region.IsObjectType and not region:IsObjectType("Frame") and region.GetParent then
        host = region:GetParent() or region
    end
    local thickness = pixels * GetPixelScale(host)
    if orientation == "vertical" then
        region:SetWidth(thickness)
    else
        region:SetHeight(thickness)
    end
end

--- Size a hairline / separator to N whole physical pixels on its own grid and snap it.
--- Use for every visible line instead of SetHeight(1) / SetWidth(1): 1 UI unit is a
--- fractional pixel count at most UI scales and flickers 1px<->2px when the window moves.
---@param region Region texture (snapped) or thin frame
---@param orientation string "horizontal" (sets height) | "vertical" (sets width)
---@param pixels number|nil physical pixels, default 1
local function SetRuleThickness(region, orientation, pixels)
    if not region then return end
    ns.UI_PixelPerfectFrame(region)
    pixels = math.max(1, math.floor((tonumber(pixels) or 1) + 0.5))
    ApplyRuleThickness(region, orientation, pixels)
    if region.SetSnapToPixelGrid then
        SnapRuleTexture(region)
    end
    RULE_REGISTRY[region] = RULE_REGISTRY[region] or {}
    RULE_REGISTRY[region].orientation = orientation
    RULE_REGISTRY[region].pixels = pixels
end

local function RefreshRegisteredRules()
    for region, spec in pairs(RULE_REGISTRY) do
        ApplyRuleThickness(region, spec.orientation, spec.pixels)
    end
end

--- Re-size every registered 1px border to its frame's current pixel scale.
--- Needed after WoW UI scale / display changes AND after profile.uiScale changes.
local function RefreshRegisteredBorderThickness()
    RefreshRegisteredRules()
    if not (ns.UI_UpdateBorderColor and ns.BORDER_REGISTRY) then return end
    for i = 1, #ns.BORDER_REGISTRY do
        local frame = ns.BORDER_REGISTRY[i]
        if frame and frame.BorderTop and not frame._wnMainShellBackdrop and not frame._wnBorderlessSurface then
            local pixelScale = GetBorderThickness(frame)
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

local scaleHandler = CreateFrame("Frame")
scaleHandler:RegisterEvent("UI_SCALE_CHANGED")
scaleHandler:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleHandler:SetScript("OnEvent", function()
    mult = nil
    cachedPhysH = nil
    C_Timer.After(0, RefreshRegisteredBorderThickness)
end)

ns.GetPixelScale = GetPixelScale
ns.PixelSnap = PixelSnap
ns.ResetPixelScale = ResetPixelScale
ns.UI_RefreshRegisteredBorderThickness = RefreshRegisteredBorderThickness
ns.PixelRound = PixelRound
ns.UI_GetBorderThickness = GetBorderThickness
ns.UI_SnapRuleTexture = SnapRuleTexture
ns.UI_SetRuleThickness = SetRuleThickness

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
    -- Effective scale changed for every border inside these frames.
    RefreshRegisteredBorderThickness()
end

--- Keep a ScrollFrame's vertical offset on the physical pixel grid.
--- Scrolled content is translated by the vertical offset at render time, so a fractional
--- offset (wheel step, or the engine clamping to a fractional range while the window is
--- resized) lands every HORIZONTAL line between two pixels: it thickens, thins or vanishes.
--- Vertical lines are unaffected (no horizontal scroll). Hook once per ScrollFrame.
---@param scrollFrame ScrollFrame
function ns.UI_KeepScrollOnPixelGrid(scrollFrame)
    if not scrollFrame or scrollFrame._wnScrollPixelGrid or not scrollFrame.HookScript then return end
    scrollFrame._wnScrollPixelGrid = true
    local resnapping = false
    local function Resnap(self)
        if resnapping then return end
        local cur = self:GetVerticalScroll() or 0
        if cur <= 0 then return end
        local pixelScale = GetPixelScale(self)
        local snapped = math.floor(cur / pixelScale + 0.5) * pixelScale
        local range = self:GetVerticalScrollRange() or 0
        if snapped > range then
            snapped = math.floor(range / pixelScale) * pixelScale
        end
        if snapped < 0 then snapped = 0 end
        if math.abs(snapped - cur) > 0.0005 then
            resnapping = true
            self:SetVerticalScroll(snapped)
            resnapping = false
        end
    end
    scrollFrame:HookScript("OnVerticalScroll", Resnap)
    scrollFrame:HookScript("OnScrollRangeChanged", Resnap)
end

-- PIXEL-PERFECT FRAMES (EllesmereUI `PP` / ElvUI `E:Scale` model)
-- A 1px border only renders crisp and constant when the frame it sits on starts on a whole
-- physical pixel. Layout code works in UI units (padding 8, percentage widths, centring),
-- which at most scales are fractional pixels, so borders smear across 2px and change as the
-- window resizes. Instead of rewriting every call site, frames get instance-level SetPoint /
-- SetSize / SetWidth / SetHeight that round numeric offsets and sizes to whole physical
-- pixels on the frame's own grid, then call the original method. Instance fields only: the
-- shared Blizzard metatables are never touched (no taint). Argument counts are preserved
-- because the C APIs count trailing nils.

---Round a UI-unit value to whole physical pixels on `region`'s grid. 0 and non-numbers pass
---through; a positive sub-pixel value (e.g. SetSize(0.1) hide tricks) keeps its authored size.
local function SnapForRegion(region, v)
    if type(v) ~= "number" or v == 0 then return v end
    -- Textures/FontStrings take the owning frame's grid (set once at install).
    local pixelScale = GetPixelScale(region._wnPPHost or region)
    local n = math.floor(v / pixelScale + 0.5)
    if n == 0 then return v end
    return n * pixelScale
end

local function PPSetPoint(self, ...)
    local n = select("#", ...)
    local raw = self._wnRawSetPoint
    if n <= 2 then
        return raw(self, ...)
    end
    local p, a2, a3, a4, a5 = ...
    if n == 3 then
        return raw(self, p, SnapForRegion(self, a2), SnapForRegion(self, a3))
    elseif n == 4 then
        return raw(self, p, a2, SnapForRegion(self, a3), SnapForRegion(self, a4))
    end
    return raw(self, p, a2, a3, SnapForRegion(self, a4), SnapForRegion(self, a5))
end

local function PPSetSize(self, w, h)
    return self._wnRawSetSize(self, SnapForRegion(self, w), SnapForRegion(self, h))
end

local function PPSetWidth(self, w, ...)
    return self._wnRawSetWidth(self, SnapForRegion(self, w), ...)
end

local function PPSetHeight(self, h, ...)
    return self._wnRawSetHeight(self, SnapForRegion(self, h), ...)
end

---Make a frame (or texture) pixel-perfect: every later SetPoint/SetSize/SetWidth/SetHeight
---lands on whole physical pixels. Idempotent; returns the region.
---@param region Region|nil
---@return Region|nil
function ns.UI_PixelPerfectFrame(region)
    if not region or region._wnPixelPerfect or not region.SetPoint then return region end
    region._wnPixelPerfect = true
    if region.IsObjectType and not region:IsObjectType("Frame") and region.GetParent then
        region._wnPPHost = region:GetParent()
    end
    region._wnRawSetPoint = region.SetPoint
    region.SetPoint = PPSetPoint
    if region.SetSize then
        region._wnRawSetSize = region.SetSize
        region.SetSize = PPSetSize
    end
    if region.SetWidth then
        region._wnRawSetWidth = region.SetWidth
        region.SetWidth = PPSetWidth
    end
    if region.SetHeight then
        region._wnRawSetHeight = region.SetHeight
        region.SetHeight = PPSetHeight
    end
    return region
end

---CreateFrame that returns a pixel-perfect frame. UI files shadow the global with:
---  local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
---so files loaded before this one still work (they just stay unsnapped until it loads).
function ns.UI_CreateFrame(...)
    return ns.UI_PixelPerfectFrame(CreateFrame(...))
end

assert(ns.GetPixelScale and ns.PixelSnap, "SharedWidgets_Pixel: pixel exports missing")
assert(ns.UI_GetAddonUIScale and ns.UI_ApplyAddonUIScaleToAll, "SharedWidgets_Pixel: UIScale exports missing")
