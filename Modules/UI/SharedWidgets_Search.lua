--[[
    Warband Nexus - SharedWidgets SharedWidgets_Search (ops-029 slice)
    Loaded after Modules/UI/SharedWidgets.lua core exports.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local issecretvalue = issecretvalue

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local COLORS = ns.UI_COLORS
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateButton = ns.UI_CreateButton
local CreateIcon = ns.UI_CreateIcon
local GetColors = function() return ns.UI_COLORS end
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local function ResolveSurfaceTierColor(tier)
    if ns.UI_ResolveSurfaceTierColor then
        return ns.UI_ResolveSurfaceTierColor(tier)
    end
    local C = COLORS or {}
    if tier == "rowEven" then
        return C.surfaceRowEven or (UI_SPACING and UI_SPACING.ROW_COLOR_EVEN) or { 0.112, 0.112, 0.138, 0.96 }
    elseif tier == "rowOdd" then
        return C.surfaceRowOdd or (UI_SPACING and UI_SPACING.ROW_COLOR_ODD) or { 0.090, 0.090, 0.112, 0.96 }
    end
    return C.bg or { 0.065, 0.065, 0.082, 0.98 }
end

local function WnFormatRealmDisplay(raw)
    if not raw or raw == "" then return "" end
    if issecretvalue and issecretvalue(raw) then return "" end
    if ns.Utilities and ns.Utilities.FormatRealmName then
        return ns.Utilities:FormatRealmName(raw) or raw
    end
    return raw
end

local function WnSafeCharLine(char)
    local n = char and char.name
    local rlm = char and char.realm
    if n and issecretvalue and issecretvalue(n) then n = "?" end
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    n = n or "?"
    if rlm and rlm ~= "" then
        return n .. " - " .. WnFormatRealmDisplay(rlm)
    end
    return n
end

local function WnPickerTextLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

--- Plain-text blob for search (name + realm + level). Player names may include non-ASCII; do not strip them.
local function WnPlainSearchBlob(char)
    local n = char and char.name
    local rlm = char and char.realm or ""
    if n and issecretvalue and issecretvalue(n) then n = "" end
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    n = n or ""
    local rPretty = WnFormatRealmDisplay(rlm)
    local lv = tonumber(char and char.level) or 0
    return WnPickerTextLower(n .. " " .. tostring(rlm) .. " " .. tostring(rPretty) .. " " .. tostring(lv))
end

local function WnPickerLineMatchesChar(char, filterLower)
    if not filterLower or filterLower == "" then return true end
    local blob = WnPlainSearchBlob(char)
    if blob == "" then return false end
    return blob:find(filterLower, 1, true) ~= nil
end

--- Class-colored character name only (roster name column).
local function WnColoredCharacterName(char)
    local n = char and char.name
    if n and issecretvalue and issecretvalue(n) then n = "?" end
    n = n or "?"
    local cc = RAID_CLASS_COLORS and char.classFile and RAID_CLASS_COLORS[char.classFile]
    local r, g, b = 1, 1, 1
    if cc then
        r = cc.r or 1
        g = cc.g or 1
        b = cc.b or 1
    end
    local hx = string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return string.format("|cff%s%s|r", hx, n)
end

local function WnRosterLevelStr(char)
    local lv = tonumber(char and char.level)
    if not lv or lv < 1 then
        return "?"
    end
    return tostring(lv)
end

local function WnRosterRealmColored(char)
    local rlm = char and char.realm or ""
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    local rShow = WnFormatRealmDisplay(rlm)
    if rShow == "" then
        return ""
    end
    return "|cffffffff" .. rShow .. "|r"
end

--- Build members / non-member buckets for one custom header (same rules as legacy pick menu).
local function WnBuildCustomHeaderManageBuckets(addon, profile, charactersList, groupId)
    local members, candidates = {}, {}
    if not addon or not profile or not charactersList or not groupId or not ns.CharacterService then
        return members, candidates
    end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    for i = 1, #charactersList do
        local ch = charactersList[i]
        local ck = ns.UI_GetCharKey(ch)
        if ck and (ch.isTracked ~= false) and not ns.CharacterService:IsFavoriteCharacter(addon, ck) then
            local gid = ns.CharacterService:GetCharacterCustomSectionId(addon, ck)
            if gid == groupId then
                members[#members + 1] = { char = ch, key = ck }
            else
                candidates[#candidates + 1] = { char = ch, key = ck }
            end
        end
    end
    table.sort(members, function(a, b)
        return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
    end)
    table.sort(candidates, function(a, b)
        return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
    end)
    return members, candidates
end

--- Roster picker: `groupId` nil = new section (all eligible, checkboxes). Set = manage (members + bulk add).
function ns.UI_CreateCustomHeaderRosterPicker(parent, width, addon, profile, charactersList, groupId)
    if not parent or not addon or not profile or not charactersList or not ns.UI or not ns.UI.Factory or not ns.CharacterService then
        return nil
    end
    local Factory = ns.UI.Factory
    local L = ns.L
    local UI_SPACING = ns.UI_SPACING
    local itemPad = (UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8
    local filterAreaH = 38
    local scrollBarW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local ROW = 32
    local SECTION_BAR_H = 28
    local SECTION_AFTER = 10
    -- Same left gutter as checkbox rows; same right padding in both blocks so columns line up.
    local ROSTER_CONTENT_LEFT = 36
    local ROSTER_ROW_RIGHT_PAD = 10
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)

    local root = CreateFrame("Frame", nil, parent)
    if width and width > 60 then
        root:SetWidth(width)
    end
    root:SetHeight(80)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(root, { 0.06, 0.06, 0.08, 0.98 }, { (ns.UI_COLORS.accent[1] or 0.5) * 0.35, (ns.UI_COLORS.accent[2] or 0.35) * 0.35, (ns.UI_COLORS.accent[3] or 0.5) * 0.35, 0.5 })
    end

    local filterLabel = FontManager:CreateFontString(root, "small", "OVERLAY")
    filterLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -6)
    filterLabel:SetText((L and L["CUSTOM_HEADER_PICKER_FILTER_LABEL"]) or "Search")
    filterLabel:SetTextColor(0.65, 0.68, 0.74)

    local filterBg = Factory:CreateContainer(root, 100, filterAreaH - 6, true)
    filterBg:SetPoint("TOPLEFT", filterLabel, "BOTTOMLEFT", 0, -4)
    filterBg:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -16)
    local filterEb = Factory:CreateEditBox(filterBg)
    if filterEb.SetPoint then
        filterEb:SetPoint("TOPLEFT", filterBg, "TOPLEFT", 8, -6)
        filterEb:SetPoint("BOTTOMRIGHT", filterBg, "BOTTOMRIGHT", -8, 4)
    end
    filterEb:SetMaxLetters(48)

    local listHost = CreateFrame("Frame", nil, root)
    listHost:SetPoint("TOPLEFT", filterBg, "BOTTOMLEFT", 0, -itemPad)
    listHost:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -4, 4)

    local scrollFrame = Factory:CreateScrollFrame(listHost, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -scrollBarW, 0)
    scrollFrame:EnableMouseWheel(true)
    local scrollBarColumn = Factory:CreateScrollBarColumn(listHost, scrollBarW, 0, 0)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)

    local selected = {}
    local pendingAdd = {}
    local pendingRemove = {}
    local bin = ns.UI_RecycleBin

    local function rosterPickMapOn(map, key)
        if not map or not key then return false end
        return map[key] and true or false
    end

    local function syncRosterCheckboxVisual(toggle, on)
        if not toggle then return end
        local v = on and true or false
        if toggle.SetChecked then toggle:SetChecked(v) end
        if toggle.innerDot then toggle.innerDot:SetShown(v) end
    end

    local function effWidth()
        local w = root:GetWidth()
        if not w or w < 80 then
            w = width or 400
        end
        return w
    end

    local function collectEligible()
        local list = {}
        for i = 1, #charactersList do
            local ch = charactersList[i]
            local ck = ns.UI_GetCharKey(ch)
            if ck and (ch.isTracked ~= false) and not ns.CharacterService:IsFavoriteCharacter(addon, ck) then
                list[#list + 1] = { char = ch, key = ck }
            end
        end
        table.sort(list, function(a, b)
            return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
        end)
        return list
    end

    local function recycleScrollChildren()
        local ch = { scrollChild:GetChildren() }
        for i = 1, #ch do
            ch[i]:Hide()
            if bin then ch[i]:SetParent(bin) else ch[i]:SetParent(nil) end
        end
    end

    local function rebuild()
        recycleScrollChildren()
        local filterRaw = filterEb:GetText()
        if type(filterRaw) ~= "string" then filterRaw = "" end
        if issecretvalue and issecretvalue(filterRaw) then filterRaw = "" end
        local filterLower = WnPickerTextLower(filterRaw:match("^%s*(.-)%s*$") or "")

        local bw = effWidth() - 16 - scrollBarW
        if bw < 120 then bw = 120 end
        scrollChild:SetWidth(bw)
        local y = 0
        local LVL_COL_W = 44
        local COL_GAP = 8

        local function layoutRosterColumns(leftPad, rightReserve)
            local contentRight = bw - rightReserve
            local avail = contentRight - leftPad
            local realmW = math.floor(avail * 0.38)
            if realmW < 100 then realmW = 100 end
            local cap = math.min(230, math.floor(bw * 0.44))
            if realmW > cap then realmW = cap end
            local nameW = avail - LVL_COL_W - COL_GAP * 2 - realmW
            if nameW < 88 then
                nameW = 88
                realmW = math.max(72, avail - LVL_COL_W - COL_GAP * 2 - nameW)
            end
            local nameLeft = leftPad
            local lvX = nameLeft + nameW + COL_GAP
            local realmX = lvX + LVL_COL_W + COL_GAP
            return nameLeft, nameW, lvX, realmX, realmW, contentRight
        end

        local function paintRosterRowColumns(row, char, leftPad, rightReserve)
            local nameL, nameW, lvX, realmX, _, contentRight = layoutRosterColumns(leftPad, rightReserve)
            local nm = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(nm, "body") else nm:SetFontObject("GameFontNormal") end
            nm:SetPoint("LEFT", row, "LEFT", nameL, 0)
            nm:SetWidth(nameW)
            nm:SetJustifyH("LEFT")
            if nm.SetMaxLines then nm:SetMaxLines(1) end
            if nm.SetWordWrap then nm:SetWordWrap(false) end
            nm:SetText(WnColoredCharacterName(char))

            local lv = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(lv, "body") else lv:SetFontObject("GameFontNormal") end
            lv:SetPoint("LEFT", row, "LEFT", lvX, 0)
            lv:SetWidth(LVL_COL_W)
            lv:SetJustifyH("CENTER")
            lv:SetText("|cffffffff" .. WnRosterLevelStr(char) .. "|r")

            local rf = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(rf, "body") else rf:SetFontObject("GameFontNormal") end
            rf:SetPoint("LEFT", row, "LEFT", realmX, 0)
            rf:SetWidth(math.max(48, contentRight - realmX))
            rf:SetJustifyH("LEFT")
            if rf.SetMaxLines then rf:SetMaxLines(1) end
            if rf.SetWordWrap then rf:SetWordWrap(false) end
            rf:SetText(WnRosterRealmColored(char))
        end

        local function addPlaceholderLine(text, extraH, textLeftPad)
            local h = ROW + (extraH or 0)
            local wrap = CreateFrame("Frame", nil, scrollChild)
            wrap:SetSize(bw, h)
            wrap:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            local padL = (type(textLeftPad) == "number" and textLeftPad >= 0) and textLeftPad or 10
            local fs = FontManager:CreateFontString(wrap, "body", "OVERLAY")
            fs:SetPoint("LEFT", padL, 0)
            fs:SetPoint("RIGHT", wrap, "RIGHT", -10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(0.45, 0.45, 0.48)
            fs:SetText(text)
            y = y + h + 4
        end

        local function addColumnHeaderRow(leftPad, rightReserve)
            local nameL, nameW, lvX, realmX, _, contentRight = layoutRosterColumns(leftPad, rightReserve)
            local hdrH = 20
            local hf = CreateFrame("Frame", nil, scrollChild)
            hf:SetSize(bw, hdrH)
            hf:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            local c1 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c1:SetPoint("LEFT", hf, "LEFT", nameL, 0)
            c1:SetWidth(nameW)
            c1:SetJustifyH("LEFT")
            c1:SetTextColor(0.52, 0.55, 0.6)
            c1:SetText((L and L["CUSTOM_HEADER_COL_CHARACTER"]) or "Character")
            local c2 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c2:SetPoint("LEFT", hf, "LEFT", lvX, 0)
            c2:SetWidth(LVL_COL_W)
            c2:SetJustifyH("CENTER")
            c2:SetTextColor(1, 1, 1)
            c2:SetText((L and L["CUSTOM_HEADER_COL_LEVEL"]) or "Level")
            local c3 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c3:SetPoint("LEFT", hf, "LEFT", realmX, 0)
            c3:SetWidth(math.max(48, contentRight - realmX))
            c3:SetJustifyH("LEFT")
            c3:SetTextColor(1, 1, 1)
            c3:SetText((L and L["CUSTOM_HEADER_COL_REALM"]) or "Realm")
            y = y + hdrH + 4
        end

        local function addSectionTitle(txt)
            local bar = CreateFrame("Frame", nil, scrollChild)
            bar:SetSize(bw, SECTION_BAR_H)
            bar:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            if ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(bar, { 0.10, 0.10, 0.12, 0.82 }, { 0, 0, 0, 0 })
            end
            local fs = FontManager:CreateFontString(bar, "tabSubtitle", "OVERLAY")
            fs:SetPoint("LEFT", 10, 0)
            fs:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(txt)
            fs:SetTextColor(0.72, 0.76, 0.84)
            y = y + SECTION_BAR_H + SECTION_AFTER
        end

        if not groupId then
            local all = collectEligible()
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local shown = 0
            for i = 1, #all do
                local entry = all[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    shown = shown + 1
                    local ck = entry.key
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, rosterPickMapOn(selected, ck))
                    if cb then
                        cb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(cb, rosterPickMapOn(selected, ck))
                        cb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            selected[ck] = v and true or nil
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not cb then return end
                        local v = not (cb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(cb, v)
                        selected[ck] = v and true or nil
                    end)
                    y = y + ROW
                end
            end
            if shown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_PICKER_EMPTY"]) or "No matching characters.", 0, ROSTER_CONTENT_LEFT)
            end
        else
            local members, candidates = WnBuildCustomHeaderManageBuckets(addon, profile, charactersList, groupId)
            addSectionTitle((L and L["CUSTOM_HEADER_MENU_IN_HEADER"]) or "In this section")
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local memShown = 0
            for i = 1, #members do
                local entry = members[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    memShown = memShown + 1
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local ck = entry.key
                    local memChecked = not rosterPickMapOn(pendingRemove, ck)
                    local rmCb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, memChecked)
                    if rmCb then
                        rmCb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(rmCb, memChecked)
                        rmCb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            if v then
                                pendingRemove[ck] = nil
                            else
                                pendingRemove[ck] = true
                            end
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not rmCb then return end
                        local v = not (rmCb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(rmCb, v)
                        if v then
                            pendingRemove[ck] = nil
                        else
                            pendingRemove[ck] = true
                        end
                    end)
                    y = y + ROW
                end
            end
            if memShown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_MENU_NO_MEMBERS"]) or "No characters yet.", 2, ROSTER_CONTENT_LEFT)
            end
            y = y + 4
            addSectionTitle((L and L["CUSTOM_HEADER_MENU_ADD_TO_HEADER"]) or "Add characters")
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local candShown = 0
            for i = 1, #candidates do
                local entry = candidates[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    candShown = candShown + 1
                    local ck = entry.key
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, rosterPickMapOn(pendingAdd, ck))
                    if cb then
                        cb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(cb, rosterPickMapOn(pendingAdd, ck))
                        cb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            pendingAdd[ck] = v and true or nil
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not cb then return end
                        local v = not (cb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(cb, v)
                        pendingAdd[ck] = v and true or nil
                    end)
                    y = y + ROW
                end
            end
            if candShown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_MENU_NO_CANDIDATES"]) or "No eligible characters (favorites stay in Favorites).", 0, ROSTER_CONTENT_LEFT)
            end
        end

        scrollChild:SetHeight(math.max(y, 1))
        scrollFrame:SetVerticalScroll(0)
        if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(scrollFrame) end
    end

    filterEb:SetScript("OnTextChanged", function()
        rebuild()
    end)
    root:SetScript("OnSizeChanged", function()
        rebuild()
    end)
    rebuild()

    return {
        frame = root,
        filterEdit = filterEb,
        Rebuild = rebuild,
        GetSelectedKeys = function()
            local keys = {}
            if groupId then return keys end
            for ck, on in pairs(selected) do
                if on then keys[#keys + 1] = ck end
            end
            return keys
        end,
        ApplyPendingAdds = function()
            if not groupId then return 0 end
            local n = 0
            local function rosterAssignKey(ck)
                if not ck then return ck end
                if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                    return ns.Utilities:GetCanonicalCharacterKey(ck) or ck
                end
                return ck
            end
            for ck, on in pairs(pendingRemove) do
                if on then
                    local k = rosterAssignKey(ck)
                    if ns.CharacterService:SetCharacterCustomSection(addon, k, nil) then
                        n = n + 1
                    end
                end
            end
            wipe(pendingRemove)
            for ck, on in pairs(pendingAdd) do
                if on then
                    local k = rosterAssignKey(ck)
                    if ns.CharacterService:SetCharacterCustomSection(addon, k, groupId) then
                        n = n + 1
                    end
                end
            end
            wipe(pendingAdd)
            if n > 0 and addon.SendMessage then
                addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSection" })
            end
            rebuild()
            return n
        end,
        ClearSelection = function()
            wipe(selected)
            if groupId then
                wipe(pendingAdd)
                wipe(pendingRemove)
            end
            rebuild()
        end,
    }
end

--- [+] on header row: open same modal window as new section (addon:OpenCustomHeaderRosterWindow).
function ns.UI_ShowCustomHeaderMembersMenu(anchorFrame, groupId, profile, charactersList)
    if not groupId then return end
    local addon = _G.WarbandNexus or ns.WarbandNexus
    if not addon or not addon.OpenCustomHeaderRosterWindow then return end
    local function open()
        addon:OpenCustomHeaderRosterWindow(groupId)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, open)
    else
        open()
    end
end

-- CUSTOM HEADER DECORATOR (Characters / Professions / PvE single source)
-- Defined in Characters tab (profile.characterCustomGroups), consumed identically
-- in related tabs. Layout: [chevron] [icon] [gold-star] [title] ... [add-btn] [count]

-- Migrate legacy per-tab field names so a header decorated by an older code path
-- (e.g. ProfessionsUI's `_wnProfSectionGoldStar`/`_wnProfSectionCount`) reuses the
-- same widgets, preventing duplicate stars/counts when re-decorated by the helper.
local function MigrateLegacyCustomHeaderFields(headerFrame)
    if not headerFrame then return end
    if headerFrame._wnProfSectionGoldStar and not headerFrame._wnCustomHeaderGoldStarBtn then
        headerFrame._wnCustomHeaderGoldStarBtn = headerFrame._wnProfSectionGoldStar
        headerFrame._wnProfSectionGoldStar = nil
    end
    if headerFrame._wnProfSectionCount and not headerFrame._wnCustomHeaderCount then
        headerFrame._wnCustomHeaderCount = headerFrame._wnProfSectionCount
        headerFrame._wnProfSectionCount = nil
    end
end

--- Decorate a CreateCollapsibleHeader frame with the unified Custom Header chrome.
--- Idempotent: re-attaches existing widgets on subsequent calls (safe across redraws).
---
--- opts (table):
---   groupId          : string  custom header id (required)
---   memberCount      : number  count badge value (defaults to 0)
---   addon            : table   WarbandNexus addon ref
---   profile          : table   addon.db.profile
---   expandIcon       : Texture chevron from CreateCollapsibleHeader (return #2)
---   iconFrame        : Texture section atlas icon from CreateCollapsibleHeader (return #3)
---   headerText       : FontString title from CreateCollapsibleHeader (return #4)
---   includeAddButton : boolean show the [+] roster manage button (Character tab only)
---   addButtonRoster  : table   character list passed to picker (when includeAddButton)
---   refreshTab       : string  optional tab payload for WN_UI_MAIN_REFRESH_REQUESTED on toggle
---   addBtnSize       : number  optional override for + button size (default 16)
---   allowSectionHighlightToggle : boolean (default true). When false, no gold-star control (PvE/Professions: highlight only on Character tab).
function ns.UI_DecorateCustomHeader(headerFrame, opts)
    if not headerFrame or type(opts) ~= "table" then return end
    local groupId = opts.groupId
    if not groupId or groupId == "" then return end

    MigrateLegacyCustomHeaderFields(headerFrame)

    local addon = opts.addon or _G.WarbandNexus or ns.WarbandNexus
    local profile = opts.profile or (addon and addon.db and addon.db.profile)
    if not profile then return end

    local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
    local CharacterService = ns.CharacterService

    local headerHeight = headerFrame.GetHeight and headerFrame:GetHeight() or 0
    if headerHeight <= 0 then headerHeight = 36 end
    local addBtnSize = tonumber(opts.addBtnSize) or 16
    local starSize = math.max(16, math.min(22, headerHeight - 10))

    -- Count badge (right edge baseline; siblings re-anchor relative to this).
    local countFs = headerFrame._wnCustomHeaderCount
    if not countFs then
        countFs = FontManager:CreateFontString(headerFrame, "header", "OVERLAY")
        headerFrame._wnCustomHeaderCount = countFs
    end
    countFs:SetJustifyH("RIGHT")
    countFs:SetText("|cffaaaaaa" .. FormatNumber(opts.memberCount or 0) .. "|r")
    countFs:Show()

    -- [+] manage roster button (left of count). Character tab only.
    local addBtn = headerFrame._wnCustomHeaderAddBtn
    if opts.includeAddButton then
        if not addBtn and ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
            addBtn = ns.UI.Factory:CreateButton(headerFrame, addBtnSize, addBtnSize, true)
            headerFrame._wnCustomHeaderAddBtn = addBtn
            addBtn:SetFrameLevel((headerFrame:GetFrameLevel() or 2) + 3)
            local okA = false
            if addBtn.SetNormalAtlas then
                okA = pcall(function()
                    addBtn:SetNormalAtlas("communities-icon-addgroupplus")
                end)
            end
            if not okA then
                local gt = addBtn.GetNormalTexture and addBtn:GetNormalTexture()
                if gt then
                    gt:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
                    gt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
        if addBtn then
            addBtn:SetSize(addBtnSize, addBtnSize)
            local rosterChars = opts.addButtonRoster
            if (not rosterChars) and addon and addon.GetAllCharacters then
                rosterChars = addon:GetAllCharacters() or {}
            end
            local profileRef = profile
            local localGid = groupId
            addBtn:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_LEFT")
                GameTooltip:SetText((ns.L and ns.L["CUSTOM_HEADER_ROW_ADD_TOOLTIP"]) or "Add characters", 1, 1, 1)
                GameTooltip:AddLine((ns.L and ns.L["CUSTOM_HEADER_ROW_ADD_TOOLTIP_BODY"]) or "Pick tracked characters (non-favorites) to place in this header. Remove them here or via the row note icon.", 0.85, 0.85, 0.9, true)
                GameTooltip:Show()
            end)
            addBtn:SetScript("OnLeave", GameTooltip_Hide)
            addBtn:SetScript("OnClick", function(b)
                if ns.UI_ShowCustomHeaderMembersMenu then
                    ns.UI_ShowCustomHeaderMembersMenu(b, localGid, profileRef, rosterChars)
                end
            end)
            addBtn:Show()
        end
    elseif addBtn then
        addBtn:Hide()
    end

    local allowSectionHighlightToggle = opts.allowSectionHighlightToggle ~= false

    -- Gold-star highlight toggle (left of title, after section icon). Character tab only when allowSectionHighlightToggle.
    local isHighlighted = CharacterService and CharacterService.IsProfileCustomSectionHighlighted
        and CharacterService:IsProfileCustomSectionHighlighted(profile, groupId)
    local goldStar = headerFrame._wnCustomHeaderGoldStarBtn
    if not allowSectionHighlightToggle then
        if goldStar then
            goldStar:Hide()
            goldStar:SetScript("OnClick", nil)
            goldStar:EnableMouse(false)
        end
    elseif not goldStar and ns.UI_CreateFavoriteButton then
        goldStar = ns.UI_CreateFavoriteButton(
            headerFrame,
            groupId,
            isHighlighted,
            starSize,
            "RIGHT",
            -48,
            0,
            function()
                local addonRef = opts.addon or _G.WarbandNexus or ns.WarbandNexus
                if not addonRef or not addonRef.db or not addonRef.db.profile then
                    return false
                end
                local now = CharacterService and CharacterService.ToggleFavoriteCustomHeaderHighlight
                    and CharacterService:ToggleFavoriteCustomHeaderHighlight(addonRef, groupId)
                if now == nil then
                    return false
                end
                if addonRef.SendMessage then
                    if opts.refreshTab and opts.refreshTab ~= "" then
                        addonRef:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = opts.refreshTab, skipCooldown = true })
                    else
                        addonRef:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
                    end
                end
                return now
            end
        )
        headerFrame._wnCustomHeaderGoldStarBtn = goldStar
        if goldStar and goldStar.SetFrameLevel then
            goldStar:SetFrameLevel((headerFrame:GetFrameLevel() or 2) + 4)
        end
    end
    if allowSectionHighlightToggle and goldStar then
        goldStar:EnableMouse(true)
        goldStar.charKey = groupId
        goldStar.isFavorite = isHighlighted and true or false
        if goldStar.icon and ns.UI_StyleFavoriteIcon then
            ns.UI_StyleFavoriteIcon(goldStar.icon, isHighlighted)
        end
        goldStar:SetSize(starSize, starSize)
        if goldStar.icon then
            local iconSz = starSize * 0.65
            goldStar.icon:SetSize(iconSz, iconSz)
        end
        goldStar:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText((ns.L and ns.L["CUSTOM_HEADER_GOLD_STAR_TITLE"]) or "Gold section highlight", 1, 1, 1)
            GameTooltip:AddLine((ns.L and ns.L["CUSTOM_HEADER_GOLD_STAR_BODY"]) or "Click to give this section the same gold bar style as Favorites. You can highlight several sections. Click again to turn off for this section.", 0.85, 0.85, 0.9, true)
            GameTooltip:Show()
        end)
        goldStar:SetScript("OnLeave", GameTooltip_Hide)
        goldStar:Show()
    end

    -- ===== UNIFIED ANCHOR LAYOUT =====
    -- Right edge:    [add-btn?]  [count]   (count anchored to header right; add-btn left of count)
    -- Left of title: [chevron]   [icon]    [gold-star]   [title]
    local headerSide = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or (UI_LAYOUT and UI_LAYOUT.SIDE_MARGIN) or 12
    countFs:ClearAllPoints()
    if addBtn and addBtn:IsShown() then
        countFs:SetPoint("RIGHT", headerFrame, "RIGHT", -headerSide, 0)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("RIGHT", countFs, "LEFT", -6, 0)
    else
        countFs:SetPoint("RIGHT", headerFrame, "RIGHT", -headerSide, 0)
    end

    if allowSectionHighlightToggle and goldStar then
        goldStar:ClearAllPoints()
        local expandIcon = opts.expandIcon
        local iconFrame = opts.iconFrame
        local headerText = opts.headerText
        if expandIcon and iconFrame then
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
            goldStar:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
            if headerText then
                headerText:ClearAllPoints()
                headerText:SetPoint("LEFT", goldStar, "RIGHT", 12, 0)
                if countFs then
                    headerText:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
                end
                headerText:SetJustifyH("LEFT")
            end
        elseif expandIcon and headerText and countFs then
            -- Chevron + star + title + count (no section atlas icon — same left edge as Characters tab intent)
            goldStar:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
            headerText:ClearAllPoints()
            headerText:SetPoint("LEFT", goldStar, "RIGHT", 12, 0)
            headerText:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            headerText:SetJustifyH("LEFT")
        elseif addBtn and addBtn:IsShown() then
            goldStar:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
        else
            goldStar:SetPoint("RIGHT", countFs, "LEFT", -6, 0)
        end
    elseif opts.headerText and countFs then
        local ht = opts.headerText
        -- Match CreateCollapsibleHeader: [chevron] +8 + [atlas icon] +12 + title (do not anchor title to chevron only).
        if opts.expandIcon and opts.iconFrame then
            opts.iconFrame:ClearAllPoints()
            opts.iconFrame:SetPoint("LEFT", opts.expandIcon, "RIGHT", 8, 0)
            ht:ClearAllPoints()
            ht:SetPoint("LEFT", opts.iconFrame, "RIGHT", 12, 0)
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            ht:SetJustifyH("LEFT")
        elseif opts.expandIcon then
            ht:ClearAllPoints()
            ht:SetPoint("LEFT", opts.expandIcon, "RIGHT", 12, 0)
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            ht:SetJustifyH("LEFT")
        else
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
        end
    end
end

--- Back-compat alias (single roster picker).
function ns.UI_CreateCustomSectionCreatePicker(parent, width, _scrollH, addon, profile, charactersList)
    return ns.UI_CreateCustomHeaderRosterPicker(parent, width, addon, profile, charactersList, nil)
end

assert(ns.UI_CreateCustomHeaderRosterPicker, "SharedWidgets_Search: export missing")
