--[[
    Warband Nexus — Blizzard Achievement Journal integration
    WN icon: circular, bottom-right on achievement icon frame; click adds achievement to To-Do (+ Add parity).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local L = ns.L
local Constants = ns.Constants
local E = Constants and Constants.EVENTS
local issecretvalue = issecretvalue

local ICON_PATH = "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga"
local HOOKED = {}

---@type table<Button, boolean>
local wnJournalButtons = setmetatable({}, { __mode = "k" })

local ACHIEVEMENT_ROW_MIXINS = {
    "AchievementTemplateMixin",
    "AchievementFullSearchResultsButtonMixin",
    "AchievementTemplateSummaryMixin",
}

---Methods Blizzard rows may use instead of or in addition to Init (Midnight ScrollBox templates vary).
local ACHIEVEMENT_ROW_METHODS = {
    "Init",
    "SetAchievement",
    "DisplayAchievement",
    "Setup",
    "RefreshDisplay",
}

local function AchievementCompletedSafe(completed)
    if completed == nil then return false end
    if issecretvalue and issecretvalue(completed) then return false end
    return completed and true or false
end

---GetAchievementInfo after pcall: returns are id, name, points, completed, ... (NOT id at select 2 when skipping — always use explicit indices).
local function GetAchievementCompletedFlag(achievementID)
    local ok, _, _, _, completed = pcall(GetAchievementInfo, achievementID)
    if not ok then return false end
    return AchievementCompletedSafe(completed)
end

local function SafeAchievementID(v)
    if type(v) ~= "number" or v <= 0 then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    local ok, retId = pcall(GetAchievementInfo, v)
    if not ok or retId == nil then return nil end
    if issecretvalue and issecretvalue(retId) then return nil end
    if retId == v then return v end
    return nil
end

local function AchievementIDFromMixedTable(t)
    if type(t) ~= "table" then return nil end
    return SafeAchievementID(t.id)
        or SafeAchievementID(t.achievementID)
        or SafeAchievementID(t.achievementId)
end

local function ResolveAchievementIDFromArgs(self, ...)
    if self then
        if self.GetElementData then
            local okD, data = pcall(function()
                return self:GetElementData()
            end)
            if okD and type(data) == "table" then
                local sid = AchievementIDFromMixedTable(data)
                if sid then return sid end
                if type(data.achievement) == "number" then
                    sid = SafeAchievementID(data.achievement)
                    if sid then return sid end
                elseif type(data.achievement) == "table" then
                    sid = AchievementIDFromMixedTable(data.achievement)
                    if sid then return sid end
                end
            end
        end
        local achField = self.achievement
        if achField ~= nil then
            if type(achField) == "number" then
                local sid = SafeAchievementID(achField)
                if sid then return sid end
            elseif type(achField) == "table" then
                local sid = AchievementIDFromMixedTable(achField)
                if sid then return sid end
            end
        end
        local sidSelf = SafeAchievementID(self.id)
            or SafeAchievementID(self.achievementID)
            or SafeAchievementID(self.achievementId)
        if sidSelf then return sidSelf end
    end
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        local sid = SafeAchievementID(v)
        if sid then return sid end
        if type(v) == "table" then
            sid = AchievementIDFromMixedTable(v)
            if sid then return sid end
        end
    end
    return nil
end

local function RefreshWNIconVisual(btn, achievementID)
    if not btn or not achievementID then return end
    local planned = WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievementID)
    local tex = btn.WNTex
    if tex then
        if planned then
            tex:SetVertexColor(0.35, 1, 0.45, 1)
        else
            tex:SetVertexColor(1, 1, 1, 1)
        end
    end
end

local function RefreshAllWNJournalIcons()
    for btn in pairs(wnJournalButtons) do
        local aid = btn.achievementID
        if aid then
            if GetAchievementCompletedFlag(aid) then
                btn:Hide()
            elseif btn:IsShown() then
                RefreshWNIconVisual(btn, aid)
            end
        end
    end
end

--- Anchor WN control to the achievement art/icon frame (bottom-right of gold square), not the full row.
local function ResolveJournalIconAnchor(row)
    if not row then return nil end
    local function tryFrame(key)
        local f = row[key]
        if f and type(f) == "table" and f.IsObjectType then
            local ok, w, h = pcall(function()
                return f:GetWidth(), f:GetHeight()
            end)
            if ok and w and h and w >= 36 and w <= 88 and h >= 36 and h <= 88 then
                return f
            end
        end
        return nil
    end
    local direct = tryFrame("Icon") or tryFrame("icon") or tryFrame("IconBorder") or tryFrame("iconBorder")
        or tryFrame("AchievementIcon") or tryFrame("Background")
    if direct then return direct end
    local best, bestArea = nil, 0
    local n = row.GetNumChildren and row:GetNumChildren() or 0
    for i = 1, n do
        local c = select(i, row:GetChildren())
        if c and c.IsObjectType and (c:IsObjectType("Frame") or c:IsObjectType("Button")) then
            local ok, w, h = pcall(function()
                return c:GetWidth(), c:GetHeight()
            end)
            if ok and w and h and w >= 40 and h >= 40 and w <= 96 and h <= 96 and math.abs(w - h) <= 12 then
                local area = w * h
                if area > bestArea then
                    bestArea = area
                    best = c
                end
            end
        end
    end
    return best or row
end

local function ApplyCircularWNTexture(btn)
    local tex = btn.WNTex
    if not tex then return end
    tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    if btn._wnCircleMask then return end
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    btn._wnCircleMask = mask
end

local function EnsureWNButton(parent, achievementID)
    if not parent or not achievementID then return end
    local btn = parent.WarbandNexusPlanBtn
    if not btn then
        btn = CreateFrame("Button", nil, parent)
        btn:SetFrameStrata("HIGH")
        btn:RegisterForClicks("LeftButtonUp")
        if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(true) end
        if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(true) end

        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(ICON_PATH)
        if tex.SetDesaturated then tex:SetDesaturated(false) end
        tex:SetAlpha(1)
        btn.WNTex = tex
        ApplyCircularWNTexture(btn)

        local hi = btn:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.15)

        parent.WarbandNexusPlanBtn = btn
    end

    local anchor = ResolveJournalIconAnchor(parent) or parent
    if btn:GetParent() ~= anchor then
        btn:SetParent(anchor)
    end

    btn:SetSize(24, 24)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
    btn:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 5) + 25)
    ApplyCircularWNTexture(btn)

    btn.achievementID = achievementID
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        -- Midnight: GameTooltip:SetText(text [, color, alpha, wrap]) — do not pass legacy r,g,b,wrap four floats.
        if InCombatLockdown() then
            GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMBAT"] or "Unavailable in combat.")
        else
            local aid = self.achievementID
            if GetAchievementCompletedFlag(aid) then
                GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMPLETE"] or "This achievement is already completed.")
            else
                if aid and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(aid) then
                    GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP_REMOVE"] or "|cffccaa00Warband Nexus|r\nClick to remove this achievement from your To-Do List.")
                else
                    GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP"] or "|cffccaa00Warband Nexus|r\nClick to add this achievement to your To-Do List (same as + Add).")
                end
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        local aid = self.achievementID
        if not aid then return end
        if GetAchievementCompletedFlag(aid) then
            if WarbandNexus.Print then
                WarbandNexus:Print("|cff888888" .. ((L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMPLETE"]) or "This achievement is already completed.") .. "|r")
            end
            return
        end

        local planAdded, planRemoved = false, false
        if WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(aid) then
            -- Toggle: already on list → remove it.
            local plans = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.plans
            if plans and WarbandNexus.RemovePlan then
                for i = 1, #plans do
                    local p = plans[i]
                    if p and p.type == "achievement" and p.achievementID == aid then
                        planRemoved = WarbandNexus:RemovePlan(p.id) and true or false
                        break
                    end
                end
            end
        elseif WarbandNexus.BuildAchievementPlanPayload and WarbandNexus.AddPlan then
            local payload = WarbandNexus:BuildAchievementPlanPayload(aid)
            if payload then
                local planID = WarbandNexus:AddPlan(payload)
                planAdded = planID ~= nil
            end
        end

        if planAdded then
            PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        elseif planRemoved then
            PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
        end
        RefreshWNIconVisual(self, aid)
        if GameTooltip:IsOwned(self) then
            self:GetScript("OnEnter")(self)
        end
    end)

    RefreshWNIconVisual(btn, achievementID)
    wnJournalButtons[btn] = true
    btn:Show()
    if btn.Raise then btn:Raise() end
end

local function OnAchievementTemplateInit(self, ...)
    if not self then return end
    local achID = ResolveAchievementIDFromArgs(self, ...)
    local btn = self.WarbandNexusPlanBtn
    if not achID then
        if btn then btn:Hide() end
        return
    end

    local ok = select(1, pcall(GetAchievementInfo, achID))
    if not ok then
        if btn then btn:Hide() end
        return
    end

    -- Only show on incomplete achievements; hide once earned.
    if GetAchievementCompletedFlag(achID) then
        if btn then btn:Hide() end
        return
    end

    EnsureWNButton(self, achID)
end

local function HookMixinTable(mixinTable, methodName, hookLabel)
    if not mixinTable or type(mixinTable[methodName]) ~= "function" or HOOKED[hookLabel] then return end
    hooksecurefunc(mixinTable, methodName, OnAchievementTemplateInit)
    HOOKED[hookLabel] = true
end

local function InstallAchievementJournalHooks()
    for mi = 1, #ACHIEVEMENT_ROW_MIXINS do
        local mixName = ACHIEVEMENT_ROW_MIXINS[mi]
        local m = _G[mixName]
        if type(m) == "table" then
            for mj = 1, #ACHIEVEMENT_ROW_METHODS do
                local method = ACHIEVEMENT_ROW_METHODS[mj]
                HookMixinTable(m, method, mixName .. "." .. method)
            end
        end
    end

    -- Globals appear after Blizzard_AchievementUI loads; retry open hooks each install pass.
    local function onAchievementFrameOpened()
        if Utilities and Utilities.SafeLoadAddOn then
            Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
        end
        C_Timer.After(0, InstallAchievementJournalHooks)
        C_Timer.After(0.08, RefreshAllWNJournalIcons)
    end
    if not HOOKED.__OpenAchievementFrameToAchievement and type(OpenAchievementFrameToAchievement) == "function" then
        hooksecurefunc("OpenAchievementFrameToAchievement", onAchievementFrameOpened)
        HOOKED.__OpenAchievementFrameToAchievement = true
    end
    if not HOOKED.__ToggleAchievementFrame and type(ToggleAchievementFrame) == "function" then
        hooksecurefunc("ToggleAchievementFrame", onAchievementFrameOpened)
        HOOKED.__ToggleAchievementFrame = true
    end
    if not HOOKED.__AchievementFrame_LoadUI and type(AchievementFrame_LoadUI) == "function" then
        hooksecurefunc("AchievementFrame_LoadUI", function()
            C_Timer.After(0, InstallAchievementJournalHooks)
            C_Timer.After(0.08, RefreshAllWNJournalIcons)
        end)
        HOOKED.__AchievementFrame_LoadUI = true
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ACHIEVEMENT_EARNED")
loader:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_AchievementUI" then
            if Utilities and Utilities.SafeLoadAddOn then
                Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
            end
            InstallAchievementJournalHooks()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        if Utilities and Utilities.SafeLoadAddOn then
            Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
        end
        InstallAchievementJournalHooks()
        C_Timer.After(0.5, InstallAchievementJournalHooks)
        return
    end
    if event == "ACHIEVEMENT_EARNED" then
        RefreshAllWNJournalIcons()
    end
end)

-- Blizzard_EventUtil (embedded): ensures hooks run even if load order differs.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_AchievementUI", function()
        if Utilities and Utilities.SafeLoadAddOn then
            Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
        end
        InstallAchievementJournalHooks()
        C_Timer.After(0.1, RefreshAllWNJournalIcons)
    end)
end

C_Timer.After(0, function()
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
    end
    InstallAchievementJournalHooks()
end)

if E and WarbandNexus and WarbandNexus.RegisterMessage then
    WarbandNexus:RegisterMessage(E.PLANS_UPDATED, RefreshAllWNJournalIcons)
end
