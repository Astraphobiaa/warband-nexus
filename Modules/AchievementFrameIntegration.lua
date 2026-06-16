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
local WN_FEAT_OF_STRENGTH_CATEGORY_ID = 81
local WN_GUILD_CATEGORY_ID = 15076
local WN_ATTACH_RETRY_SEC = 0.06
local WN_ATTACH_MAX_ATTEMPTS = 4
local WN_FRAME_OPEN_HOOK_DEFER_SEC = 0.12

local function AchievementCompletedSafe(completed)
    if completed == nil then return false end
    if issecretvalue and issecretvalue(completed) then return false end
    return completed and true or false
end

local function SafeCategoryParent(categoryID)
    if not categoryID or not GetCategoryInfo then return nil end
    local _, parent = GetCategoryInfo(categoryID)
    if parent == nil or (issecretvalue and issecretvalue(parent)) then return nil end
    return parent
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
---Mirrors Blizzard AchievementFrameCategories_MakeCategoryList (runs once at AchievementUI load).
---If that load happens before GetCategoryList() is complete, FoS child tabs stay hidden until /reload.
local function WNCategories_MakeCategoryList(source, fakeSummaryId)
    local categories = {}
    if fakeSummaryId then
        categories[#categories + 1] = { id = fakeSummaryId }
    end
    if not source then return categories end
    for i = 1, #source do
        local id = source[i]
        if id then
            local parent = SafeCategoryParent(id)
            if parent == -1 or parent == WN_GUILD_CATEGORY_ID then
                categories[#categories + 1] = { id = id }
            end
        end
    end
    for i = #source, 1, -1 do
        local childID = source[i]
        if childID then
            local parent = SafeCategoryParent(childID)
            for j = 1, #categories do
                local category = categories[j]
                if category.id == parent then
                    category.parent = true
                    category.collapsed = true
                    local elementData = {
                        id = childID,
                        parent = category.id,
                        hidden = true,
                        isChild = (type(category.id) == "number"),
                    }
                    table.insert(categories, j + 1, elementData)
                end
            end
        end
    end
    return categories
end

local function CountChildCategoriesInBuiltList(categories, parentID)
    if not categories or not parentID then return 0 end
    local n = 0
    for i = 1, #categories do
        local c = categories[i]
        if c and c.parent == parentID and c.isChild then
            n = n + 1
        end
    end
    return n
end

local function CountApiChildCategories(parentID)
    if not parentID or not GetCategoryList or not GetCategoryInfo then return 0 end
    local list = GetCategoryList() or {}
    local n = 0
    for i = 1, #list do
        local id = list[i]
        if id then
            local parent = SafeCategoryParent(id)
            if parent == parentID then
                n = n + 1
            end
        end
    end
    return n
end

local function NeedsAchievementCategoryListRebuild()
    if not ACHIEVEMENT_FUNCTIONS or not ACHIEVEMENT_FUNCTIONS.categories then
        return false
    end
    local apiFoS = CountApiChildCategories(WN_FEAT_OF_STRENGTH_CATEGORY_ID)
    if apiFoS < 3 then
        return false
    end
    local builtFoS = CountChildCategoriesInBuiltList(ACHIEVEMENT_FUNCTIONS.categories, WN_FEAT_OF_STRENGTH_CATEGORY_ID)
    return builtFoS < apiFoS
end

local function RebuildAchievementFunctionsCategories()
    if not GetCategoryList then return false end
    local list = GetCategoryList() or {}
    if #list < WN_CATEGORY_LIST_MIN_IDS then
        return false
    end
    if ACHIEVEMENT_FUNCTIONS then
        ACHIEVEMENT_FUNCTIONS.categories = WNCategories_MakeCategoryList(list, "summary")
    end
    if COMPARISON_ACHIEVEMENT_FUNCTIONS then
        COMPARISON_ACHIEVEMENT_FUNCTIONS.categories = WNCategories_MakeCategoryList(list)
    end
    if type(AchievementFrameCategories_UpdateDataProvider) == "function"
        and AchievementFrame and AchievementFrame:IsShown()
        and AchievementFrameCategories and AchievementFrameCategories:IsShown() then
        pcall(AchievementFrameCategories_UpdateDataProvider)
    end
    return true
end

local function EnsureCategoryRebuildHooks()
    if HOOKED.__CategoriesUpdate then return end
    if type(AchievementFrameCategories_UpdateDataProvider) == "function" then
        hooksecurefunc("AchievementFrameCategories_UpdateDataProvider", function()
            if NeedsAchievementCategoryListRebuild() then
                RebuildAchievementFunctionsCategories()
            end
        end)
        HOOKED.__CategoriesUpdate = true
    end
    if type(AchievementFrameCategories_OnShow) == "function" then
        hooksecurefunc("AchievementFrameCategories_OnShow", function()
            if NeedsAchievementCategoryListRebuild() then
                RebuildAchievementFunctionsCategories()
            end
        end)
        HOOKED.__CategoriesOnShow = true
    end
end

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

local function EnsureWNButton(parent, achievementID)
    if not parent or not achievementID then return end
    local btn = parent.WarbandNexusPlanBtn
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

        parent.WarbandNexusPlanBtn = btn
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
                    GameTooltip:SetText(L and L["ACHIEVEMENT_FRAME_WN_TOOLTIP"] or "|cffccaa00Warband Nexus|r\nClick to add this achievement to your To-Do List (same as the To-Do button).")
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

local function RowStillBoundToAchievement(row, achID)
    if not row or not achID then return false end
    local rowId = SafeAchievementID(row.id)
    local rowAchId = SafeAchievementID(row.achievementID)
    if rowId == achID or rowAchId == achID then return true end
    return ResolveAchievementIDFromArgs(row) == achID
end

local function CancelRowAttachTimer(row)
    if not row then return end
    local t = row._wnAttachTimer
    if t and t.Cancel then
        t:Cancel()
    end
    row._wnAttachTimer = nil
end

local function HideRowWNButton(row)
    CancelRowAttachTimer(row)
    if row then row._wnLastAttachAchID = nil end
    local btn = row and row.WarbandNexusPlanBtn
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
    row._wnLastAttachAchID = achID
    EnsureWNButton(row, achID)
    return true
end

local function ScheduleWNButtonAttachRetry(row, achID, attempt)
    if not row or not achID then return end
    attempt = attempt or 2
    if attempt > WN_ATTACH_MAX_ATTEMPTS then
        if SafeAchievementID(achID) and RowStillBoundToAchievement(row, achID) then
            row._wnLastAttachAchID = achID
            EnsureWNButton(row, achID)
        end
        return
    end
    if row._wnAttachPendingAchID == achID and row._wnAttachTimer then
        return
    end
    CancelRowAttachTimer(row)
    row._wnAttachPendingAchID = achID
    local delay = (attempt == 2) and 0 or WN_ATTACH_RETRY_SEC
    local function runAttach()
        row._wnAttachTimer = nil
        row._wnAttachPendingAchID = nil
        if RunRowWNAttach(row, achID) then return end
        ScheduleWNButtonAttachRetry(row, achID, attempt + 1)
    end
    if delay <= 0 then
        C_Timer.After(0, runAttach)
    elseif C_Timer and C_Timer.NewTimer then
        row._wnAttachTimer = C_Timer.NewTimer(delay, runAttach)
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
    if row._wnLastAttachAchID == achID then
        local btn = row.WarbandNexusPlanBtn
        if btn and btn.achievementID == achID and btn:IsShown() then
            RefreshWNIconVisual(btn, achID)
            return
        end
    end
    CancelRowAttachTimer(row)
    row._wnLastAttachAchID = achID
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
        if NeedsAchievementCategoryListRebuild() then
            RebuildAchievementFunctionsCategories()
        end
        EnsureCategoryRebuildHooks()
        InstallAchievementJournalHooks()
        if done then done() end
    end)
end

local function OnAchievementFrameOpened()
    LoadAchievementUIWhenReady(function()
        if NeedsAchievementCategoryListRebuild() then
            RebuildAchievementFunctionsCategories()
        end
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
    EnsureCategoryRebuildHooks()
    if NeedsAchievementCategoryListRebuild() then
        RebuildAchievementFunctionsCategories()
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
local function ScheduleAchievementJournalWarmup()
    LoadAchievementUIWhenReady(function()
        if ns.UI_InvalidateAchievementCategoryCaches then
            ns.UI_InvalidateAchievementCategoryCaches()
        end
        RefreshAllWNJournalIcons()
    end)
end

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("ACHIEVEMENT_EARNED")
loader:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_AchievementUI" then
            C_Timer.After(0, function()
                if NeedsAchievementCategoryListRebuild() then
                    RebuildAchievementFunctionsCategories()
                end
                EnsureCategoryRebuildHooks()
                InstallAchievementJournalHooks()
            end)
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        ScheduleAchievementJournalWarmup()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if NeedsAchievementCategoryListRebuild() then
            RebuildAchievementFunctionsCategories()
        end
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
            if NeedsAchievementCategoryListRebuild() then
                RebuildAchievementFunctionsCategories()
            end
            EnsureCategoryRebuildHooks()
            InstallAchievementJournalHooks()
            C_Timer.After(0.1, RefreshAllWNJournalIcons)
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
