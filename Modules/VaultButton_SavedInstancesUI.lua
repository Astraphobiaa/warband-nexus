--[[ Warband Nexus - Easy Access - VaultButton_SavedInstancesUI.lua ]]

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

--- Stable key for Saved Instances group collapse state (instance + difficulty).
function M.MakeSavedGroupKey(group)
    return string.format("%s||%s", group.instanceName or "?", tostring(group.difficulty or 0))
end

--- Build the section header for an (instance, difficulty) group
function M.BuildGroupHeader(parent, group, totalW, collapsed)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local diffInfo = GetDiffInfo(group.difficulty)

    local header = CreateFrame("Button", nil, parent)
    header:SetSize(totalW, 30)
    header:EnableMouse(true)

    if ApplyVisuals then
        ApplyVisuals(header, {diffInfo.color[1] * 0.18, diffInfo.color[2] * 0.18, diffInfo.color[3] * 0.18, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.85})
    end

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)

    -- Difficulty stripe (left edge)
    local stripe = header:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    -- Difficulty badge
    local badgeW = diffInfo.short == "LFR" and 36 or 22
    local badge = ns.UI.Factory:CreateContainer(header, badgeW, 16, false)
    badge:SetPoint("LEFT", 12, 0)
    badge:EnableMouse(false)
    if ApplyVisuals then
        ApplyVisuals(badge, {diffInfo.color[1] * 0.5, diffInfo.color[2] * 0.5, diffInfo.color[3] * 0.5, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1})
    end
    if FontManager and FontManager.CreateFontString then
        badgeFS = FontManager:CreateFontString(badge, "small", "OVERLAY")
    else
        badgeFS = VBFontString(badge, "small")
    end
    badgeFS:SetPoint("CENTER")
    badgeFS:SetText("|cffffffff" .. diffInfo.short .. "|r")

    -- Instance name
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(header, "body", "OVERLAY")
    else
        nameFS = VBFontString(header, "body")
    end
    nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    nameFS:SetPoint("RIGHT", header, "RIGHT", -110, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetMaxLines(1)
    nameFS:SetText(group.instanceName)
    nameFS:SetTextColor(1, 1, 1)

    -- Right side fixed columns: [characters] [progress]
    local bosses = AggregateBosses(group)
    local cleared, total = 0, bosses and #bosses or 0
    if bosses then
        for _, b in ipairs(bosses) do if #b.killers > 0 then cleared = cleared + 1 end end
    end

    local chev = header:CreateTexture(nil, "OVERLAY")
    chev:SetSize(SAVED_GROUP_CHEVRON_SIZE, SAVED_GROUP_CHEVRON_SIZE)
    chev:SetPoint("RIGHT", -10, 0)
    function M.UpdateChevron()
        if collapsed then
            chev:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover")
        else
            chev:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
        end
    end
    UpdateChevron()
    header._savedUpdateChevron = UpdateChevron

    if FontManager and FontManager.CreateFontString then
        progressFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        progressFS = VBFontString(header, "small")
    end
    progressFS:SetJustifyH("CENTER")
    progressFS:SetWordWrap(false)
    progressFS:SetTextColor(0.85, 0.85, 0.9)
    progressFS:SetWidth(SAVED_GROUP_PROGRESS_W)
    progressFS:SetPoint("RIGHT", chev, "LEFT", -10, 0)
    local progColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    progressFS:SetText(string.format("%s%2d/%-2d|r", progColor, cleared, total))

    if FontManager and FontManager.CreateFontString then
        countLabelFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        countLabelFS = VBFontString(header, "small")
    end
    countLabelFS:SetJustifyH("LEFT")
    countLabelFS:SetWordWrap(false)
    countLabelFS:SetTextColor(0.85, 0.85, 0.9)
    countLabelFS:SetWidth(86)
    countLabelFS:SetPoint("RIGHT", progressFS, "LEFT", -10, 0)
    countLabelFS:SetText(#group.characters == 1 and "character" or "characters")

    if FontManager and FontManager.CreateFontString then
        countNumFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        countNumFS = VBFontString(header, "small")
    end
    countNumFS:SetJustifyH("RIGHT")
    countNumFS:SetWordWrap(false)
    countNumFS:SetTextColor(0.85, 0.85, 0.9)
    countNumFS:SetWidth(18)
    countNumFS:SetPoint("RIGHT", countLabelFS, "LEFT", -6, 0)
    countNumFS:SetText(string.format("%2d", #group.characters))

    nameFS:ClearAllPoints()
    nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    nameFS:SetPoint("RIGHT", countNumFS, "LEFT", -12, 0)

    header:SetScript("OnEnter", function(self)
        local bossTotal = bosses and #bosses or 0
        local bossCleared = 0
        if bosses then
            for i = 1, #bosses do
                if #(bosses[i].killers or {}) > 0 then
                    bossCleared = bossCleared + 1
                end
            end
        end
        WNTooltipShow(self, {
            type = "custom",
            title = group.instanceName or "?",
            lines = {
                { text = "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r" },
                { text = EAL("EA_TOOLTIP_INSTANCE_BOSSES", "%d/%d bosses defeated", bossCleared, bossTotal), color = {0.88, 0.88, 0.9} },
                { text = EAL("EA_TOOLTIP_INSTANCE_CHARS", "%d characters on lockout", #group.characters), color = {0.7, 0.7, 0.75} },
                { text = " " },
                { text = (ns.L and ns.L["SAVED_INSTANCES_EXPAND_HINT"]) or "Click to expand character lockouts", color = {0.55, 0.55, 0.55} },
            },
        })
    end)
    header:SetScript("OnLeave", function() WNTooltipHide() end)

    return header
end

function M.BuildSavedInstanceArtCache()
    if S.savedInstanceArtByName then return S.savedInstanceArtByName end
    S.savedInstanceArtByName = {}
    if not EJ_GetInstanceByIndex or not EJ_GetInstanceInfo then
        return S.savedInstanceArtByName
    end

    for raidFlag = 0, 1 do
        for idx = 1, 250 do
            local okIdx, journalID = pcall(EJ_GetInstanceByIndex, idx, raidFlag == 1)
            if not okIdx or not journalID then break end
            if not (issecretvalue and issecretvalue(journalID)) then
                local okInfo, name, _, bgImage, buttonImage, loreImage = pcall(EJ_GetInstanceInfo, journalID)
                if okInfo and name and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                    local key = string.lower(name)
                    if key ~= "" and not S.savedInstanceArtByName[key] then
                        S.savedInstanceArtByName[key] = buttonImage or loreImage or bgImage
                    end
                end
            end
        end
    end
    return S.savedInstanceArtByName
end

function M.GetSavedInstanceArt(group)
    if not group then return nil end
    if group.instanceID and EJ_GetInstanceInfo and not (issecretvalue and issecretvalue(group.instanceID)) then
        local okInfo, _, _, bgImage, buttonImage, loreImage = pcall(EJ_GetInstanceInfo, group.instanceID)
        local direct = okInfo and (buttonImage or loreImage or bgImage) or nil
        if direct then return direct end
    end

    local name = group.instanceName
    if not name or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then
        return nil
    end
    local map = BuildSavedInstanceArtCache()
    return map and map[string.lower(name)] or nil
end

local FormatSavedResetShort = function(secondsLeft)
    if not secondsLeft or secondsLeft <= 0 then return "" end
    local hours = math.floor(secondsLeft / 3600)
    local days = math.floor(hours / 24)
    if days > 0 then
        local fmt = (ns.L and ns.L["SAVED_INSTANCES_RESET_DAYS"]) or "%dd"
        return string.format(fmt, days)
    end
    if hours > 0 then
        local fmt = (ns.L and ns.L["SAVED_INSTANCES_RESET_HOURS"]) or "%dh"
        return string.format(fmt, hours)
    end
    return (ns.L and ns.L["SAVED_INSTANCES_RESET_LESS_HOUR"]) or "<1h"
end

function M.BuildInstanceCard(parent, group, cardSize)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local diffInfo = GetDiffInfo(group.difficulty)
    local bosses = AggregateBosses(group)
    local total = bosses and #bosses or 0
    local cleared = 0
    if bosses then
        for i = 1, #bosses do
            if #bosses[i].killers > 0 then
                cleared = cleared + 1
            end
        end
    end

    local card = CreateFrame("Button", nil, parent)
    card:SetSize(cardSize, cardSize)
    card:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(card, {0.04, 0.04, 0.06, 0.96}, {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.65})
    end

    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)
    stripe:SetHeight(2)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    local titleFS = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(card, "body", "OVERLAY")
        or VBFontString(card, "body")
    titleFS:SetPoint("TOPLEFT", 8, -8)
    titleFS:SetPoint("TOPRIGHT", -8, -8)
    titleFS:SetJustifyH("CENTER")
    titleFS:SetJustifyV("TOP")
    titleFS:SetWordWrap(true)
    titleFS:SetMaxLines(2)
    titleFS:SetText(group.instanceName or "?")

    local art = card:CreateTexture(nil, "BORDER")
    art:SetPoint("TOPLEFT", 12, -40)
    art:SetPoint("TOPRIGHT", -12, -40)
    art:SetPoint("BOTTOM", card, "BOTTOM", 0, 28)
    art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local instanceArt = GetSavedInstanceArt(group)
    art:SetTexture(instanceArt or "Interface\\Icons\\INV_Misc_QuestionMark")
    if not instanceArt then
        art:SetDesaturated(true)
        art:SetVertexColor(0.65, 0.65, 0.65, 1)
    else
        art:SetDesaturated(false)
        art:SetVertexColor(1, 1, 1, 1)
    end

    local diffFS = VBFontString(card, "small")
    diffFS:SetPoint("BOTTOM", card, "BOTTOM", 0, 11)
    diffFS:SetText("|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r")

    local progFS = VBFontString(card, "small")
    progFS:SetPoint("BOTTOM", diffFS, "TOP", 0, 2)
    local pColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%d/%d|r", pColor, cleared, total))

    card:SetScript("OnEnter", function(self)
        local lines = {}
        lines[#lines + 1] = { text = "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r" }
        lines[#lines + 1] = {
            text = EAL("EA_TOOLTIP_INSTANCE_BOSSES", "%d/%d bosses defeated", cleared, total),
            color = {0.88, 0.88, 0.9},
        }

        if bosses and #bosses > 0 then
            lines[#lines + 1] = { text = " " }
            for bi = 1, #bosses do
                local b = bosses[bi]
                local killers = b.killers or {}
                local bossName = b.name or EAL("EA_TOOLTIP_BOSS_FALLBACK", "Boss %d", bi)
                if #killers == 0 then
                    lines[#lines + 1] = {
                        left = bossName,
                        right = EAL("EA_TOOLTIP_BOSS_NOT_KILLED", "Not defeated"),
                        leftColor = {0.9, 0.9, 0.92},
                        rightColor = {0.65, 0.65, 0.68},
                    }
                else
                    local parts = {}
                    for ki = 1, #killers do
                        local kHex, kName = GetClassHexFromCharacters(killers[ki])
                        parts[#parts + 1] = "|cff" .. kHex .. kName .. "|r"
                    end
                    lines[#lines + 1] = {
                        left = bossName,
                        right = table.concat(parts, ", "),
                        leftColor = {0.9, 0.9, 0.92},
                        rightColor = {0.88, 0.88, 0.9},
                    }
                end
            end
        end

        local clearedChars = {}
        for ci = 1, #group.characters do
            local c = group.characters[ci]
            local killedN = c.killed or 0
            local totalBoss = c.total or 0
            if totalBoss > 0 and killedN >= totalBoss then
                local cHex, cName = GetClassHexFromCharacters(c.charKey)
                local resetTag = FormatSavedResetShort(c.reset)
                if resetTag ~= "" then
                    clearedChars[#clearedChars + 1] = string.format("|cff%s%s|r (%s)", cHex, cName or c.charKey, resetTag)
                else
                    clearedChars[#clearedChars + 1] = string.format("|cff%s%s|r", cHex, cName or c.charKey)
                end
            end
        end
        if #clearedChars > 0 then
            lines[#lines + 1] = { text = " " }
            lines[#lines + 1] = {
                text = EAL("EA_TOOLTIP_INSTANCE_CLEARED_BY", "Fully cleared by: %s", table.concat(clearedChars, ", ")),
                color = {0.75, 0.75, 0.78},
                wrap = true,
            }
        end

        WNTooltipShow(self, {
            type = "custom",
            title = group.instanceName or "?",
            lines = lines,
        })
    end)
    card:SetScript("OnLeave", function() WNTooltipHide() end)

    return card
end

local RefreshSavedInstances = function()
    BuildSavedInstancesFrame()
    local content = S.savedContent
    if not content then return end

    ReleaseSavedInstanceRows()

    local list = BuildSavedInstancesData()
    local filtered = {}
    local filters = S.savedFilters or {}
    for i = 1, #list do
        local g = list[i]
        local diff = g.difficulty
        local pass = (diff == 17 and filters.lfr)
            or (diff == 14 and filters.normal)
            or (diff == 15 and filters.heroic)
            or (diff == 16 and filters.mythic)
            or (diff ~= 14 and diff ~= 15 and diff ~= 16 and diff ~= 17)
        if pass then
            filtered[#filtered + 1] = g
        end
    end

    if S.savedFilterButtons then
        for _, b in pairs(S.savedFilterButtons) do
            if b._applyState then b._applyState() end
        end
    end

    if S.savedFrame and S.savedFrame.summary then
        local charSet = {}
        for i = 1, #filtered do
            local g = filtered[i]
            for ci = 1, #g.characters do
                charSet[g.characters[ci].charKey] = true
            end
        end
        local n = 0
        for _ in pairs(charSet) do n = n + 1 end
        local sumFmt = (ns.L and ns.L["SAVED_INSTANCES_SUMMARY"]) or "%d instances · %d characters"
        S.savedFrame.summary:SetText(string.format(sumFmt, #filtered, n))
    end

    local lay = (S.savedFrame and S.savedFrame._savedLayout) or VBGetSavedInstancesLayout()
    local viewportW = (S.savedScroll and S.savedScroll.GetWidth and S.savedScroll:GetWidth()) or SAVED_FRAME_W
    local contentW = math.max(320, viewportW)
    content:SetWidth(contentW)

    if #filtered == 0 then
        local FontManager = ns.FontManager
        if FontManager and FontManager.CreateFontString then
            msg = FontManager:CreateFontString(content, "body", "OVERLAY")
        else
            msg = VBFontString(content, "body")
        end
        msg:SetPoint("CENTER", content, "CENTER", 0, -20)
        msg:SetTextColor(0.6, 0.6, 0.6)
        if #list == 0 then
            msg:SetText((ns.L and ns.L["SAVED_INSTANCES_EMPTY"]) or "No saved lockouts yet.\nLog in a character with raid or dungeon lockouts.")
        else
            msg:SetText((ns.L and ns.L["SAVED_INSTANCES_NO_FILTER_MATCH"]) or "No instances match the current filters.")
        end
        msg:SetJustifyH("CENTER")
        content:SetHeight(math.max(80, lay.contentTopGap + 60))
        S.savedRows[#S.savedRows + 1] = msg
        local vf = ns.UI.Factory
        if vf and vf.UpdateScrollBarVisibility and S.savedScroll then
            vf:UpdateScrollBarVisibility(S.savedScroll)
        end
        S.savedFrame:Show()
        return
    end

    table.sort(filtered, function(a, b)
        local nameA = a.instanceName or ""
        local nameB = b.instanceName or ""
        if nameA ~= nameB then return nameA < nameB end
        local ra = DIFF_SORT_RANK[a.difficulty] or 99
        local rb = DIFF_SORT_RANK[b.difficulty] or 99
        if ra ~= rb then return ra < rb end
        return (a.difficultyName or "") < (b.difficultyName or "")
    end)

local GROUP_GAP = lay.contentTopGap
local ROW_GAP = 3
    local rowW = contentW
    local y = lay.contentTopGap
    local prevScroll = (S.savedScroll and S.savedScroll.GetVerticalScroll and S.savedScroll:GetVerticalScroll()) or 0

    S.savedGroupCollapsed = S.savedGroupCollapsed or {}

    for gi = 1, #filtered do
        local group = filtered[gi]
        if gi > 1 then
            y = y + GROUP_GAP
        end

        local groupKey = MakeSavedGroupKey(group)
        local collapsed = S.savedGroupCollapsed[groupKey] == true

        local header = BuildGroupHeader(content, group, rowW, collapsed)
        header._savedGroupKey = groupKey
        header:SetScript("OnClick", nil)
        header:SetScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" then return end
            S._savedUserInteractUntil = GetTime() + 0.45
            local wasCollapsed = S.savedGroupCollapsed[groupKey] == true
            S.savedGroupCollapsed[groupKey] = not wasCollapsed
            RefreshSavedInstances()
        end)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        S.savedRows[#S.savedRows + 1] = header
        y = y + header:GetHeight() + ROW_GAP

        if not collapsed then
            local roster = group.characters or {}
            table.sort(roster, function(a, b)
                local _, nameA = GetClassHexFromCharacters(a.charKey)
                local _, nameB = GetClassHexFromCharacters(b.charKey)
                return (nameA or a.charKey or "") < (nameB or b.charKey or "")
            end)

            for ci = 1, #roster do
                local c = roster[ci]
                local charRow = BuildLockoutRow(content, c, c.encounters, group, rowW)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                S.savedRows[#S.savedRows + 1] = charRow
                y = y + charRow:GetHeight() + ROW_GAP
            end
        end
    end

    content:SetHeight(math.max(40, y + lay.contentBottomPad))
    local viewportH = (S.savedScroll and S.savedScroll.GetHeight and S.savedScroll:GetHeight()) or 0
    local maxY = math.max(0, (content:GetHeight() or 0) - viewportH)
    S.savedScroll:SetVerticalScroll(math.min(maxY, math.max(0, prevScroll)))
    local vf = ns.UI.Factory
    if vf and vf.UpdateScrollBarVisibility and S.savedScroll then
        vf:UpdateScrollBarVisibility(S.savedScroll)
    end
    S.savedFrame:Show()
end

local ToggleSavedInstances = function()
    if S.savedFrame and S.savedFrame:IsShown() then
        S.savedFrame:Hide()
        return
    end
    HideTable()
    HideMenu()
    BuildSavedInstancesFrame()
    if S.savedFrame and S.button and not S.savedFrame:GetPoint() then
        S.savedFrame:ClearAllPoints()
        S.savedFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -6)
    end
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    -- Fresh open: explicitly start at the top before RefreshSavedInstances clamps the new content.
    if S.savedScroll and S.savedScroll.SetVerticalScroll then
        S.savedScroll:SetVerticalScroll(0)
    end
    RefreshSavedInstances()
end

M.FormatSavedResetShort = FormatSavedResetShort
M.RefreshSavedInstances = RefreshSavedInstances
M.ToggleSavedInstances = ToggleSavedInstances

