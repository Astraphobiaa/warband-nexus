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

local ICON_PATH = ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga"
local HOOKED = {}

---@type table<Button, boolean>
local wnJournalButtons = setmetatable({}, { __mode = "k" })

-- Achievement list rows only (never AchievementCategoryTemplateMixin — sidebar category buttons).
-- Midnight journal binds rows via AchievementTemplateMixin:Init inside a recycled ScrollBox.
local ACHIEVEMENT_ROW_HOOKS = {
    { mix = "AchievementTemplateMixin", hooks = { Init = "rowInit" } },
    { mix = "AchievementFullSearchResultsButtonMixin", hooks = { Init = "rowInit" } },
}

local WN_CATEGORY_LIST_MIN_IDS = 80
local WN_ATTACH_RETRY_SEC = 0.06
local WN_ATTACH_MAX_ATTEMPTS = 4
local WN_FRAME_OPEN_HOOK_DEFER_SEC = 0.12

local function AchievementCompletedSafe(completed)
    if issecretvalue and issecretvalue(completed) then return false end
    if completed == nil then return false end
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
    if issecretvalue and issecretvalue(retId) then return nil end
    if not ok or retId == nil then return nil end
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
    local iconBlock = row.Icon
    if iconBlock and iconBlock.IsObjectType and iconBlock:IsObjectType("Frame") then
        return iconBlock
    end
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

--- Per-row state lives in weak tables, never as fields on Blizzard ScrollBox rows (that taints them).
local planBtnByRow = setmetatable({}, { __mode = "k" })
local rowAttachTimer = setmetatable({}, { __mode = "k" })
local rowLastAttachAchID = setmetatable({}, { __mode = "k" })
local rowAttachPendingAchID = setmetatable({}, { __mode = "k" })

local function EnsureWNButton(parent, achievementID)
    if not parent or not achievementID then return end
    local btn = planBtnByRow[parent]
    local anchor = ResolveJournalIconAnchor(parent) or parent
    if btn and btn.achievementID == achievementID and btn:IsShown() then
        if btn:GetParent() == anchor then
            RefreshWNIconVisual(btn, achievementID)
            return
        end
    end
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

        planBtnByRow[parent] = btn
    end

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
        if ns.UI_SafeSetGameTooltipOwner(self, "ANCHOR_LEFT") then
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
                        GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP"] or "|cffccaa00Warband Nexus|r\nClick to add this achievement to your To-Do List (same as the To-Do button).")
                    end
                end
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", ns.UI_SafeHideGameTooltip)

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

local function RowStillBoundToAchievement(row, achID)
    if not row or not achID then return false end
    local rowId = SafeAchievementID(row.id)
    local rowAchId = SafeAchievementID(row.achievementID)
    if rowId == achID or rowAchId == achID then return true end
    return ResolveAchievementIDFromArgs(row) == achID
end

local function CancelRowAttachTimer(row)
    if not row then return end
    local t = rowAttachTimer[row]
    if t and t.Cancel then
        t:Cancel()
    end
    rowAttachTimer[row] = nil
end

local function HideRowWNButton(row)
    CancelRowAttachTimer(row)
    if row then rowLastAttachAchID[row] = nil end
    local btn = row and planBtnByRow[row]
    if btn then btn:Hide() end
end

---Attach WN icon on a bound row. Returns true when done (show or hide); false → retry later.
local function RunRowWNAttach(row, achID)
    if not row or not achID or not RowStillBoundToAchievement(row, achID) then
        return true
    end
    if GetAchievementCompletedFlag(achID) or AchievementCompletedSafe(row.completed) then
        HideRowWNButton(row)
        return true
    end
    local ok = select(1, pcall(GetAchievementInfo, achID))
    if not ok and not SafeAchievementID(achID) then
        return false
    end
    rowLastAttachAchID[row] = achID
    EnsureWNButton(row, achID)
    return true
end

local function ScheduleWNButtonAttachRetry(row, achID, attempt)
    if not row or not achID then return end
    attempt = attempt or 2
    if attempt > WN_ATTACH_MAX_ATTEMPTS then
        if SafeAchievementID(achID) and RowStillBoundToAchievement(row, achID) then
            rowLastAttachAchID[row] = achID
            EnsureWNButton(row, achID)
        end
        return
    end
    if rowAttachPendingAchID[row] == achID and rowAttachTimer[row] then
        return
    end
    CancelRowAttachTimer(row)
    rowAttachPendingAchID[row] = achID
    local delay = (attempt == 2) and 0 or WN_ATTACH_RETRY_SEC
    local function runAttach()
        rowAttachTimer[row] = nil
        rowAttachPendingAchID[row] = nil
        if RunRowWNAttach(row, achID) then return end
        ScheduleWNButtonAttachRetry(row, achID, attempt + 1)
    end
    if delay <= 0 then
        C_Timer.After(0, runAttach)
    elseif C_Timer and C_Timer.NewTimer then
        rowAttachTimer[row] = C_Timer.NewTimer(delay, runAttach)
    else
        C_Timer.After(delay, runAttach)
    end
end

local function TryAttachRowWNButton(row, achID)
    if not row or not achID then return end
    if GetAchievementCompletedFlag(achID) or AchievementCompletedSafe(row.completed) then
        HideRowWNButton(row)
        return
    end
    if rowLastAttachAchID[row] == achID then
        local btn = planBtnByRow[row]
        if btn and btn.achievementID == achID and btn:IsShown() then
            RefreshWNIconVisual(btn, achID)
            return
        end
    end
    CancelRowAttachTimer(row)
    rowLastAttachAchID[row] = achID
    if RunRowWNAttach(row, achID) then
        return
    end
    ScheduleWNButtonAttachRetry(row, achID, 2)
end

local function OnAchievementRowInit(self, ...)
    if not self then return end
    local achID = ResolveAchievementIDFromArgs(self, ...)
    if not achID then
        HideRowWNButton(self)
        return
    end
    TryAttachRowWNButton(self, achID)
end

local ROW_HOOK_HANDLERS = {
    rowInit = OnAchievementRowInit,
}

---One-shot after the journal opens (ScrollBox Init hooks handle scroll recycling).
local function RefreshVisibleAchievementRows()
    local achFrame = _G.AchievementFrameAchievements
    local scrollBox = achFrame and achFrame.ScrollBox
    if not scrollBox or not scrollBox.ForEachFrame then return end
    scrollBox:ForEachFrame(function(frame)
        if not frame then return end
        local achID = SafeAchievementID(frame.id) or SafeAchievementID(frame.achievementID)
        if achID then
            TryAttachRowWNButton(frame, achID)
        end
    end)
end

local function HookMixinMethod(mixinTable, methodName, hookLabel, handler)
    if not mixinTable or type(mixinTable[methodName]) ~= "function" or HOOKED[hookLabel] then return end
    if type(handler) ~= "function" then return end
    hooksecurefunc(mixinTable, methodName, handler)
    HOOKED[hookLabel] = true
end

local InstallAchievementJournalHooks

---Do not load Blizzard_AchievementUI until GetCategoryList() is populated (early load freezes FoS sub-tabs).
local function LoadAchievementUIWhenReady(done, attempt)
    attempt = attempt or 1
    local list = GetCategoryList and GetCategoryList() or {}
    if #list < WN_CATEGORY_LIST_MIN_IDS and attempt < 24 then
        C_Timer.After(0.25, function()
            LoadAchievementUIWhenReady(done, attempt + 1)
        end)
        return
    end
    if InCombatLockdown() and attempt < 30 then
        C_Timer.After(0.5, function()
            LoadAchievementUIWhenReady(done, attempt + 1)
        end)
        return
    end
    local achUILoaded = Utilities and Utilities.CheckAddOnLoaded
        and Utilities:CheckAddOnLoaded("Blizzard_AchievementUI")
    if Utilities and Utilities.SafeLoadAddOn and not achUILoaded then
        Utilities:SafeLoadAddOn("Blizzard_AchievementUI")
    end
    C_Timer.After(0, function()
        InstallAchievementJournalHooks()
        if done then done() end
    end)
end

local function OnAchievementFrameOpened()
    LoadAchievementUIWhenReady(function()
        C_Timer.After(WN_FRAME_OPEN_HOOK_DEFER_SEC, InstallAchievementJournalHooks)
        C_Timer.After(0.15, function()
            RefreshAllWNJournalIcons()
            RefreshVisibleAchievementRows()
        end)
    end)
end

InstallAchievementJournalHooks = function()
    for hi = 1, #ACHIEVEMENT_ROW_HOOKS do
        local spec = ACHIEVEMENT_ROW_HOOKS[hi]
        local m = _G[spec.mix]
        if type(m) == "table" and spec.hooks then
            for method, handlerKey in pairs(spec.hooks) do
                local handler = ROW_HOOK_HANDLERS[handlerKey]
                HookMixinMethod(m, method, spec.mix .. "." .. method, handler)
            end
        end
    end

    -- Globals appear after Blizzard_AchievementUI loads; retry open hooks each install pass.
    if not HOOKED.__OpenAchievementFrameToAchievement and type(OpenAchievementFrameToAchievement) == "function" then
        hooksecurefunc("OpenAchievementFrameToAchievement", OnAchievementFrameOpened)
        HOOKED.__OpenAchievementFrameToAchievement = true
    end
    if not HOOKED.__ToggleAchievementFrame and type(ToggleAchievementFrame) == "function" then
        hooksecurefunc("ToggleAchievementFrame", OnAchievementFrameOpened)
        HOOKED.__ToggleAchievementFrame = true
    end
    -- Current FrameXML entry point (OpenAchievementFrameToAchievement was removed).
    if not HOOKED.__AchievementFrame_ToggleAchievementFrame
        and type(AchievementFrame_ToggleAchievementFrame) == "function" then
        hooksecurefunc("AchievementFrame_ToggleAchievementFrame", OnAchievementFrameOpened)
        HOOKED.__AchievementFrame_ToggleAchievementFrame = true
    end
    if not HOOKED.__AchievementFrame_LoadUI and type(AchievementFrame_LoadUI) == "function" then
        hooksecurefunc("AchievementFrame_LoadUI", function()
            C_Timer.After(WN_FRAME_OPEN_HOOK_DEFER_SEC, InstallAchievementJournalHooks)
            C_Timer.After(0.12, function()
                RefreshAllWNJournalIcons()
                RefreshVisibleAchievementRows()
            end)
        end)
        HOOKED.__AchievementFrame_LoadUI = true
    end
end

local loader = CreateFrame("Frame")
-- Login warmup no longer force-loads Blizzard_AchievementUI (2026-10-22): journal hooks attach
-- through ADDON_LOADED / ContinueOnAddOnLoaded when the player first opens it. Only WN's own
-- category caches still need the "category list ready" signal at login.
local function ScheduleAchievementJournalWarmup(attempt)
    attempt = attempt or 1
    local list = GetCategoryList and GetCategoryList() or {}
    if #list < WN_CATEGORY_LIST_MIN_IDS and attempt < 24 then
        C_Timer.After(0.25, function()
            ScheduleAchievementJournalWarmup(attempt + 1)
        end)
        return
    end
    if ns.UI_InvalidateAchievementCategoryCaches then
        ns.UI_InvalidateAchievementCategoryCaches()
    end
    RefreshAllWNJournalIcons()
end

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ACHIEVEMENT_EARNED")
loader:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_AchievementUI" then
            C_Timer.After(0, function()
                InstallAchievementJournalHooks()
            end)
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        ScheduleAchievementJournalWarmup()
        return
    end
    if event == "ACHIEVEMENT_EARNED" then
        RefreshAllWNJournalIcons()
    end
end)

-- Blizzard_EventUtil (embedded): ensures hooks run even if load order differs.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_AchievementUI", function()
        C_Timer.After(0, function()
            InstallAchievementJournalHooks()
            C_Timer.After(0.1, RefreshAllWNJournalIcons)
            -- First open now loads the UI: rows were bound before the Init hook existed.
            C_Timer.After(0.15, RefreshVisibleAchievementRows)
        end)
    end)
end

if E and WarbandNexus and WarbandNexus.RegisterMessage then
    local AchFrameMsgListeners = ns._achFrameMsgListeners or {}
    ns._achFrameMsgListeners = AchFrameMsgListeners
    WarbandNexus.RegisterMessage(AchFrameMsgListeners, E.PLANS_UPDATED, RefreshAllWNJournalIcons)
    if E.COLLECTION_SCAN_COMPLETE then
        WarbandNexus.RegisterMessage(AchFrameMsgListeners, E.COLLECTION_SCAN_COMPLETE, function(_, data)
            local cat = data and data.category
            if cat and cat ~= "achievement" and cat ~= "all" then return end
            C_Timer.After(0.1, RefreshAllWNJournalIcons)
        end)
    end
end
