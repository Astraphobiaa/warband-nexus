--[[ Warband Nexus - Easy Access - VaultButton_SavedInstances.lua ]]

local ADDON_NAME, ns = ...
local M = assert(ns.VaultButton)
local WarbandNexus = ns.WarbandNexus
local S = M.state

local function VB__setfenv()
    return setmetatable({ M = M, ns = ns, WarbandNexus = WarbandNexus, S = M.state }, {
        __index = function(_, k)
            local v = M[k]
            if v ~= nil then return v end
            return _G[k]
        end,
    })
end
setfenv(1, VB__setfenv())
-- ============================================================================
-- Saved Instances (raid + dungeon lockouts)
-- ============================================================================
M.DIFF_INFO = {
    [17] = { short = "LFR",    name = "Looking For Raid", color = {0.55, 0.55, 0.55}, hex = "aaaaaa" },
    [14] = { short = "N",      name = "Normal",           color = {0.12, 0.78, 0.12}, hex = "1eff00" },
    [15] = { short = "H",      name = "Heroic",           color = {0.00, 0.44, 0.87}, hex = "0070dd" },
    [16] = { short = "M",      name = "Mythic",           color = {0.64, 0.21, 0.93}, hex = "a335ee" },
    -- 5-player saved instances (GetSavedInstanceInfo difficultyID)
    [1]  = { short = "N",      name = "Normal",           color = {0.12, 0.78, 0.12}, hex = "1eff00" },
    [2]  = { short = "H",      name = "Heroic",           color = {0.00, 0.44, 0.87}, hex = "0070dd" },
    [23] = { short = "M",      name = "Mythic",           color = {0.64, 0.21, 0.93}, hex = "a335ee" },
    [8]  = { short = "M+",     name = "Mythic Keystone",  color = {0.90, 0.45, 0.10}, hex = "ff8000" },
}
M.FALLBACK_DIFF = { short = "?", name = "Unknown", color = {0.4, 0.4, 0.4}, hex = "aaaaaa" }
M.DIFFICULTY_ORDER_DESC = { 16, 15, 14, 17 }  -- Mythic > Heroic > Normal > LFR
-- Sort priority for the Saved Instances grid: LFR first, then N, H, M (dungeons align to same tiers)
M.DIFF_SORT_RANK = { [17] = 1, [14] = 2, [1] = 2, [15] = 3, [2] = 3, [16] = 4, [23] = 4, [8] = 5 }

function M.GetDiffInfo(difficulty)
    return DIFF_INFO[difficulty] or FALLBACK_DIFF
end

function M.GetClassHexFromCharacters(charKey)
    local chars = GetCharacters()
    local entry = chars and chars[charKey]
    return GetClassHex(entry and entry.classFile), entry and entry.name or charKey
end

---Saved lockout rows must carry resetAt (absolute server time); never show expired or unknown-age rows.
function M.IsSavedLockoutRowActive(inst, nowS)
    if not inst or type(nowS) ~= "number" then return false end
    local ra = inst.resetAt
    if type(ra) ~= "number" then return false end
    if issecretvalue and issecretvalue(ra) then return false end
    return ra > nowS
end

function M.BuildSavedInstancesData()
    local pveCache = GetPveCache()
    local lo = pveCache and pveCache.lockouts
    if not lo then return {} end
    local raidLockouts = lo.raids
    local dungeonLockouts = lo.dungeons

    -- Group by (instanceName + difficultyName) -> list of {charKey, killed, total}
    local nowServer = (GetServerTime and GetServerTime()) or time()
    local groups = {}

    function M.AccumulateLockoutBranch(lockoutsByChar)
        if not lockoutsByChar or type(lockoutsByChar) ~= "table" then return end
        for charKey, instances in pairs(lockoutsByChar) do
            if type(instances) == "table" then
                for _, inst in pairs(instances) do
                    if inst and inst.name and IsSavedLockoutRowActive(inst, nowServer) then
                        local diffName = inst.difficultyName or "Unknown"
                        local key = inst.name .. "||" .. diffName
                        local g = groups[key]
                        if not g then
                            g = {
                                instanceName = inst.name,
                                difficultyName = diffName,
                                difficulty = inst.difficulty,
                                instanceID = inst.instanceID,
                                characters = {},
                            }
                            groups[key] = g
                        elseif (not g.instanceID) and inst.instanceID then
                            g.instanceID = inst.instanceID
                        end
                        local total = tonumber(inst.numEncounters) or (inst.encounters and #inst.encounters) or 0
                        local killed = tonumber(inst.encounterProgress) or 0
                        if killed == 0 and inst.encounters then
                            for ei = 1, #inst.encounters do
                                local e = inst.encounters[ei]
                                if e and e.killed then killed = killed + 1 end
                            end
                        end
                        g.characters[#g.characters + 1] = {
                            charKey = charKey,
                            killed = killed,
                            total = total,
                            reset = (function()
                                local now = (GetServerTime and GetServerTime()) or time()
                                if inst.resetAt and inst.resetAt > now then
                                    return inst.resetAt - now
                                elseif inst.resetAt and inst.resetAt <= now then
                                    return 0
                                end
                                return inst.reset
                            end)(),
                            encounters = inst.encounters,
                        }
                    end
                end
            end
        end
    end

    AccumulateLockoutBranch(raidLockouts)
    AccumulateLockoutBranch(dungeonLockouts)

    local list = {}
    for _, g in pairs(groups) do
        table.sort(g.characters, function(a, b) return (a.charKey or "") < (b.charKey or "") end)
        table.insert(list, g)
    end
    table.sort(list, function(a, b)
        local ra = DIFF_SORT_RANK[a.difficulty] or 99
        local rb = DIFF_SORT_RANK[b.difficulty] or 99
        if ra ~= rb then return ra < rb end
        return (a.instanceName or "") < (b.instanceName or "")
    end)
    return list
end

M.SAVED_FRAME_W = 760
M.SAVED_FILTER_H = 36
M.SAVED_CARD_BASE = 190
M.SAVED_CARD_MIN = 152
M.SAVED_CARD_MAX = 240
M.CARD_GAP = 10
M.SAVED_GROUP_CHEVRON_SIZE = 20
M.SAVED_GROUP_PROGRESS_W = 62

local savedLiveEventFrame = nil
local savedLiveRefreshPending = false

function M.ScheduleSavedInstancesLiveRefresh(triggerPvEUpdate)
    if S._savedUserInteractUntil and GetTime() < S._savedUserInteractUntil then
        return
    end
    -- RequestRaidInfo drives UPDATE_INSTANCE_INFO; PvECacheService performs the
    -- delayed cache write after Blizzard's saved-instance API has populated.
    if RequestRaidInfo then
        pcall(RequestRaidInfo)
    end
    if savedLiveRefreshPending then return end
    savedLiveRefreshPending = true
    C_Timer.After(0.12, function()
        savedLiveRefreshPending = false
        if S.savedFrame and S.savedFrame:IsShown() then
            RefreshSavedInstances()
        end
    end)
end

local StartSavedInstancesLiveRefresh = function()
    if savedLiveEventFrame then return end
    savedLiveEventFrame = CreateFrame("Frame")
    savedLiveEventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
    savedLiveEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    savedLiveEventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    savedLiveEventFrame:RegisterEvent("RAID_INSTANCE_WELCOME")
    savedLiveEventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    savedLiveEventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    savedLiveEventFrame:RegisterEvent("ENCOUNTER_END")
    savedLiveEventFrame:SetScript("OnEvent", function(_, event)
        if not (S.savedFrame and S.savedFrame:IsShown()) then return end
        if event == "ENCOUNTER_END" then
            -- Encounter end can race cache writes; small delay keeps list accurate.
            C_Timer.After(0.2, function()
                if S.savedFrame and S.savedFrame:IsShown() then
                    ScheduleSavedInstancesLiveRefresh(true)
                end
            end)
            return
        end
        ScheduleSavedInstancesLiveRefresh(true)
    end)
end

local StopSavedInstancesLiveRefresh = function()
    if not savedLiveEventFrame then return end
    savedLiveEventFrame:SetScript("OnEvent", nil)
    savedLiveEventFrame:UnregisterAllEvents()
    savedLiveEventFrame = nil
    savedLiveRefreshPending = false
end

function M.BuildSavedInstancesFrame()
    if S.savedFrame and (S.savedFrame._savedLayoutVersion or 0) ~= SAVED_INSTANCES_LAYOUT_VERSION then
        ReleaseSavedInstanceRows()
        S.savedFrame:Hide()
        S.savedFrame = nil
        S.savedScroll = nil
        S.savedContent = nil
    end
    if S.savedFrame then return end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusSavedInstances", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusSavedInstances")
    f:SetSize(SAVED_FRAME_W, 480)
    f:SetClampedToScreen(true)
    -- Match Vault Tracker table strata so an open tracker cannot paint its scrollbar over this window.
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(560, 420, 1200, 920)
    else
        f:SetMinResize(560, 420)
    end
    f:EnableMouse(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()
    f:SetScript("OnShow", function()
        StartSavedInstancesLiveRefresh()
        ScheduleSavedInstancesLiveRefresh(true)
    end)
    f:SetScript("OnHide", function()
        StopSavedInstancesLiveRefresh()
        ReleaseSavedInstanceRows()
    end)

    local chrome = VF:CreateContainer(f, 32, 32, false)
    local chromeBandH = VBAnchorChromeBandTop(chrome, f)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    if ApplyVisuals then
        ApplyVisuals(chrome, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end

    local titleIcon = chrome:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")

    local FontManager = ns.FontManager
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        title = FontManager:CreateFontString(chrome, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        title = VBFontString(chrome, "body")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText((ns.L and ns.L["SAVED_INSTANCES_TITLE"]) or "Saved Instances")
    title:SetTextColor(1, 1, 1)

    local close = VF:CreateButton(chrome, 28, 28, true)
    close:SetPoint("RIGHT", -8, 0)
    if ApplyVisuals then
        ApplyVisuals(close, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8})
    end
    local closeIcon = close:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() closeIcon:SetVertexColor(1, 0.2, 0.2) end)
    close:SetScript("OnLeave", function() closeIcon:SetVertexColor(0.9, 0.3, 0.3) end)

    -- Filter / search bar
    local lay = VBGetSavedInstancesLayout()
    f._savedLayout = lay
    f._savedLayoutVersion = lay.layoutVersion

    local filterY = -(chromeBandH + lay.filterBelowChrome)
    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:SetHeight(SAVED_FILTER_H)
    filterRow:SetPoint("TOPLEFT", f, "TOPLEFT", lay.pad, filterY)
    filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -lay.pad, filterY)
    if ApplyVisuals then
        ApplyVisuals(filterRow, {0.06, 0.06, 0.08, 1}, {accent[1], accent[2], accent[3], 0.4})
    end

    S.savedFilters = { lfr = true, normal = true, heroic = true, mythic = true }
    S.savedFilterButtons = {}
    local filterBtns = {
        { key = "lfr",     label = "LFR", diff = 17 },
        { key = "normal",  label = "N",   diff = 14 },
        { key = "heroic",  label = "H",   diff = 15 },
        { key = "mythic",  label = "M",   diff = 16 },
    }
    local fx = lay.pad
    for _, fb in ipairs(filterBtns) do
        local di = GetDiffInfo(fb.diff)
        local b = CreateFrame("Button", nil, filterRow)
        b:SetSize(fb.key == "lfr" and 38 or 28, 22)
        b:SetPoint("LEFT", fx, 0)
        if ApplyVisuals then
            ApplyVisuals(b, {di.color[1] * 0.35, di.color[2] * 0.35, di.color[3] * 0.35, 1}, {di.color[1], di.color[2], di.color[3], 0.85})
        end
        if FontManager and FontManager.CreateFontString then
            lbl = FontManager:CreateFontString(b, "small", "OVERLAY")
        else
            lbl = VBFontString(b, "small")
        end
        lbl:SetPoint("CENTER")
        lbl:SetText("|cff" .. di.hex .. fb.label .. "|r")
        b:SetScript("OnClick", function()
            S.savedFilters[fb.key] = not S.savedFilters[fb.key]
            RefreshSavedInstances()
        end)
        b._applyState = function()
            local active = S.savedFilters[fb.key]
            if ApplyVisuals then
                local vf = ns.UI.Factory
                if vf and vf.UpdateBorderColor then
                    vf:UpdateBorderColor(b, {di.color[1], di.color[2], di.color[3], active and 1 or 0.3})
                end
            end
            lbl:SetAlpha(active and 1 or 0.45)
        end
        b._applyState()
        S.savedFilterButtons[fb.key] = b
        fx = fx + b:GetWidth() + 4
    end

    -- Char count summary on the right of filter row (matches addon side margin)
    if FontManager and FontManager.CreateFontString then
        summary = FontManager:CreateFontString(filterRow, "small", "OVERLAY")
    else
        summary = VBFontString(filterRow, "small")
    end
    summary:SetPoint("RIGHT", filterRow, "RIGHT", -lay.pad, 0)
    summary:SetTextColor(0.75, 0.75, 0.8)
    f.summary = summary

    -- Scroll body — same anchors as Vault Tracker table (symmetric FRAME_PAD; bar inside scroll frame).
    local scroll = VF:CreateScrollFrame(f, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", lay.pad, filterY - SAVED_FILTER_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -lay.pad, lay.pad)
    local content = VF:CreateContainer(scroll, math.max(320, SAVED_FRAME_W - lay.pad * 2), 1, false)
    scroll:SetScrollChild(content)

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -lay.pad, lay.pad)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        if not InCombatLockdown or not InCombatLockdown() then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if f:IsShown() then
            RefreshSavedInstances()
        end
    end)

    f._savedResizeToken = 0
    f:SetScript("OnSizeChanged", function(self)
        if not self:IsShown() then return end
        self._savedResizeToken = (self._savedResizeToken or 0) + 1
        local token = self._savedResizeToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if S.savedFrame and S.savedFrame:IsShown() and S.savedFrame._savedResizeToken == token then
                    RefreshSavedInstances()
                end
            end)
        else
            RefreshSavedInstances()
        end
    end)

    S.savedFrame = f
    S.savedScroll = scroll
    S.savedContent = content
end

--- Aggregate per-boss state across characters: returns table[bossIdx] = { name, killers={charKey...} }
function M.AggregateBosses(group)
    local roster = nil
    for _, c in ipairs(group.characters) do
        if c.encounters and #c.encounters > 0 then roster = c.encounters; break end
    end
    if not roster then return nil end
    local bosses = {}
    for i, e in ipairs(roster) do
        bosses[i] = { name = e.name or ("Boss " .. i), killers = {} }
    end
    for _, c in ipairs(group.characters) do
        if c.encounters then
            for i, e in ipairs(c.encounters) do
                if e.killed and bosses[i] then
                    table.insert(bosses[i].killers, c.charKey)
                end
            end
        end
    end
    return bosses
end

--- Build one row representing a single character's lockout in a given (instance, difficulty)
-- Columns: [Character (class colored)] [Bosses dot row] [X/Y] [reset]
function M.BuildLockoutRow(parent, char, encounters, group, totalW)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local hex, charName = GetClassHexFromCharacters(char.charKey)
    local k, t = char.killed or 0, char.total or 0
    local diffInfo = GetDiffInfo(group.difficulty)

    local row = ns.UI.Factory:CreateContainer(parent, totalW, 26, false)
    row:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(row, {0.06, 0.06, 0.09, 0.95}, {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.28})
    else
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.09, 0.95)
    end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.25)

    -- Layout columns (equal-width predictable structure)
    local PAD = 8
    local NAME_W = 150
    local PROGRESS_W = SAVED_GROUP_PROGRESS_W
    local RESET_W = 48
    local dotsX = PAD + NAME_W + 8
    local dotsRight = totalW - PAD - PROGRESS_W - 8 - RESET_W - 8
    local dotsW = math.max(40, dotsRight - dotsX)

    -- Character name
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(row, "body", "OVERLAY")
    else
        nameFS = VBFontString(row, "body")
    end
    nameFS:SetPoint("LEFT", row, "LEFT", PAD, 0)
    nameFS:SetWidth(NAME_W)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetText("|cff" .. hex .. (charName or char.charKey) .. "|r")

    -- Boss dots (one per encounter, scaled to fit dotsW)
    local roster = encounters or {}
    local bossCount = #roster
    if bossCount > 0 then
        local size = math.max(8, math.min(14, math.floor((dotsW - (bossCount - 1) * 3) / bossCount)))
        local gap = math.max(2, math.floor((dotsW - bossCount * size) / math.max(1, bossCount - 1)))
        if bossCount == 1 then gap = 0 end
        for i, e in ipairs(roster) do
            -- Boss dot border (subtle outline for better definition)
            local dotBorder = row:CreateTexture(nil, "ARTWORK", nil, 0)
            dotBorder:SetSize(size + 2, size + 2)
            dotBorder:SetPoint("LEFT", row, "LEFT", dotsX + (i - 1) * (size + gap) - 1, 0)
            dotBorder:SetColorTexture(0.10, 0.10, 0.14, 1)
            local dot = row:CreateTexture(nil, "ARTWORK", nil, 1)
            dot:SetSize(size, size)
            dot:SetPoint("LEFT", row, "LEFT", dotsX + (i - 1) * (size + gap), 0)
            if e.killed then
                dot:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)
            else
                dot:SetColorTexture(0.14, 0.14, 0.18, 1)
            end
        end
    end

    -- Progress text
    if FontManager and FontManager.CreateFontString then
        progFS = FontManager:CreateFontString(row, "small", "OVERLAY")
    else
        progFS = VBFontString(row, "small")
    end
    progFS:SetPoint("RIGHT", row, "RIGHT", -PAD - RESET_W - 8, 0)
    progFS:SetWidth(PROGRESS_W)
    progFS:SetJustifyH("CENTER")
    local progColor = (t > 0 and k >= t) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%2d/%-2d|r", progColor, k, t))

    -- Reset countdown
    if FontManager and FontManager.CreateFontString then
        resetFS = FontManager:CreateFontString(row, "small", "OVERLAY")
    else
        resetFS = VBFontString(row, "small")
    end
    resetFS:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    resetFS:SetWidth(RESET_W)
    resetFS:SetJustifyH("RIGHT")
    resetFS:SetTextColor(0.55, 0.55, 0.6)
    if char.reset and char.reset > 0 then
        local hours = math.floor(char.reset / 3600)
        local days = math.floor(hours / 24)
        if days > 0 then
            resetFS:SetText(days .. "d")
        elseif hours > 0 then
            resetFS:SetText(hours .. "h")
        else
            resetFS:SetText("<1h")
        end
    end

    row:SetScript("OnEnter", function(self)
        local lines = {}
        lines[#lines + 1] = {
            text = "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r",
            color = {0.85, 0.85, 0.9},
        }
        if char.reset and char.reset > 0 then
            local resetTag = FormatSavedResetShort(char.reset)
            if resetTag ~= "" then
                lines[#lines + 1] = {
                    text = EAL("EA_TOOLTIP_LOCKOUT_RESET", "Lockout resets in %s", resetTag),
                    color = {0.65, 0.65, 0.7},
                }
            end
        end
        lines[#lines + 1] = {
            text = EAL("EA_TOOLTIP_LOCKOUT_PROGRESS", "%d/%d bosses defeated", k, t),
            color = {0.9, 0.9, 0.92},
        }
        if roster and #roster > 0 then
            lines[#lines + 1] = { text = " " }
            for i, e in ipairs(roster) do
                local bossName = e.name or EAL("EA_TOOLTIP_BOSS_FALLBACK", "Boss %d", i)
                if e.killed then
                    lines[#lines + 1] = { text = EAL("EA_TOOLTIP_BOSS_KILLED", "Defeated: %s", bossName), color = {0.35, 0.9, 0.4} }
                else
                    lines[#lines + 1] = { text = EAL("EA_TOOLTIP_BOSS_REMAINING", "Remaining: %s", bossName), color = {0.75, 0.75, 0.78} }
                end
            end
        end
        WNTooltipShow(self, {
            type = "custom",
            title = "|cff" .. hex .. (charName or char.charKey) .. "|r",
            lines = lines,
        })
    end)
    row:SetScript("OnLeave", function() WNTooltipHide() end)

    return row
end

M.StartSavedInstancesLiveRefresh = StartSavedInstancesLiveRefresh
M.StopSavedInstancesLiveRefresh = StopSavedInstancesLiveRefresh

