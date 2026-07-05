--[[
    Weekly Progress (daily_quests) create / edit dialog with per-category and per-catalog-item selection.
    Loaded before Modules/UI/PlansUI.lua.
]]

local ADDON_NAME, ns = ...

local E = ns.Constants and ns.Constants.EVENTS

local M = {}
ns.PlansUI_WeeklyPlanner = M

local function SafePlayerName()
    if ns.Utilities and ns.Utilities.SafePlayerName then
        return ns.Utilities:SafePlayerName()
    end
    local n = UnitName("player")
    if n and (not issecretvalue or not issecretvalue(n)) then return n end
    return nil
end

local function SafeRealmName()
    if ns.Utilities and ns.Utilities.SafeRealmName then
        return ns.Utilities:SafeRealmName()
    end
    local r = GetRealmName()
    if r and (not issecretvalue or not issecretvalue(r)) then return r end
    return nil
end

local LAYOUT = {
    PAD = 14,
    DIALOG_W = 560,
    DIALOG_H = 640,
    CHAR_HDR_H = 42,
    FOOTER_H = 50,
    ROW_H = 24,
    CAT_GAP = 10,
    SECTION_GAP = 16,
    CHECKBOX_W = 20,
    COLOR_BAR_W = 3,
    INNER_GAP = 6,
}

local function GetScrollbarReserve()
    local col = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local gap = 2
    return col, col + gap
end

local function GetCategoryDescs()
    local L = ns.L
    return {
        weeklyQuests = (L and L["QUEST_CATEGORY_DESC_WEEKLY"]) or "Spark, world boss, delves, Omnium Folio, Sporefall",
        worldQuests  = (L and L["QUEST_CATEGORY_DESC_WORLD"]) or "Every active world quest pin on your map",
        assignments  = (L and L["QUEST_CATEGORY_DESC_ASSIGNMENTS"]) or "Great Vault special assignments",
        dailyQuests  = (L and L["QUEST_CATEGORY_DESC_DAILY"]) or "Every active daily quest from NPCs on your map",
        events       = (L and L["QUEST_CATEGORY_DESC_EVENTS"]) or "Soiree, Abundance, Haranir, Stormarion",
    }
end

function M.ShowDailyPlanDialog(editPlan)
    local COLORS = ns.UI_COLORS
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    local Factory = ns.UI.Factory
    local FontManager = ns.FontManager
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
    local CreateIcon = ns.UI_CreateIcon
    local ApplyVisuals = ns.UI_ApplyVisuals

    if not CreateExternalWindow or not Factory then return end

    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]

    local isEdit = editPlan and editPlan.type == "daily_quests"
    if isEdit then
        currentName = editPlan.characterName or currentName
        currentRealm = editPlan.characterRealm or currentRealm
    elseif WarbandNexus:HasActiveDailyPlan(currentName, currentRealm) then
        WarbandNexus:ShowDailyPlanExistsDialog(currentName, currentRealm)
        return
    end

    local selectedQuestTypes = {
        weeklyQuests = true,
        worldQuests  = false,
        assignments  = true,
        dailyQuests  = false,
        events       = true,
    }
    local selectedCatalogKeys = {}

    if isEdit then
        local qt = editPlan.questTypes
        if qt then
            for k, v in pairs(selectedQuestTypes) do
                selectedQuestTypes[k] = (qt[k] ~= false)
            end
        end
        local stored = editPlan.trackedCatalogKeys
        if type(stored) == "table" then
            for k, v in pairs(stored) do
                if v then selectedCatalogKeys[k] = true end
            end
        end
    end

    local function RebuildDefaultCatalogKeys()
        wipe(selectedCatalogKeys)
        local defaults = WarbandNexus:BuildDefaultTrackedCatalogKeys(selectedQuestTypes)
        for k, v in pairs(defaults) do
            if v then selectedCatalogKeys[k] = true end
        end
    end

    if not isEdit or not next(selectedCatalogKeys) then
        RebuildDefaultCatalogKeys()
    end

    local titleKey = isEdit and "WEEKLY_PROGRESS_EDIT_TITLE" or "WEEKLY_PROGRESS_ADD_TITLE"
    local PAD = LAYOUT.PAD
    local DIALOG_W = LAYOUT.DIALOG_W
    local DIALOG_H = LAYOUT.DIALOG_H
    local CHAR_HDR_H = LAYOUT.CHAR_HDR_H
    local FOOTER_H = LAYOUT.FOOTER_H
    local scrollbarW, sbReserve = GetScrollbarReserve()
    local scrollContentW = DIALOG_W - (PAD * 2) - sbReserve
    local labelIndent = LAYOUT.CHECKBOX_W + LAYOUT.INNER_GAP + LAYOUT.COLOR_BAR_W + LAYOUT.INNER_GAP
    local descW = math.max(120, scrollContentW - labelIndent - 4)

    local dialog, contentFrame = CreateExternalWindow({
        name = isEdit and "WeeklyProgressEditDialog" or "DailyPlanDialog",
        title = (ns.L and ns.L[titleKey]) or (isEdit and "Edit Weekly Progress" or "Track Weekly Progress"),
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        width = DIALOG_W,
        height = DIALOG_H,
    })
    if not dialog then return end

    local charFrame = Factory:CreateContainer(contentFrame, scrollContentW + (PAD * 2), CHAR_HDR_H, false)
    charFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)

    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon and ns.UI_GetRaceIcon(englishRace, gender) or "Interface\\Icons\\INV_Misc_QuestionMark"

    local iconContainer = Factory:CreateContainer(charFrame, 32, 32)
    iconContainer:SetPoint("LEFT", 10, 0)
    if ns.UI_ApplyIconWellChrome then
        ns.UI_ApplyIconWellChrome(iconContainer)
    elseif ApplyVisuals and classColors then
        ApplyVisuals(iconContainer, COLORS.bgCard, { classColors.r, classColors.g, classColors.b, 1 })
    end
    local charIconFrame = CreateIcon and CreateIcon(iconContainer, raceAtlas, 26, true, nil, true)
    if charIconFrame then
        charIconFrame:SetPoint("CENTER")
        charIconFrame:Show()
    end

    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 8, 0)
    if classColors then charText:SetTextColor(classColors.r, classColors.g, classColors.b) end
    charText:SetText(currentName .. "-" .. currentRealm)

    local contentLabel = FontManager:CreateFontString(charFrame, "small", "OVERLAY")
    contentLabel:SetPoint("RIGHT", -PAD, 0)
    ns.UI_SetTextColorRole(contentLabel, "Muted")
    contentLabel:SetText((ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight")

    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local categoryDescs = GetCategoryDescs()
    local bodyRows = {}
    local scrollChild
    local scrollFrame

    local function ReleaseBodyRows()
        for i = 1, #bodyRows do
            local row = bodyRows[i]
            if row and row.Hide then row:Hide() end
        end
        wipe(bodyRows)
    end

    local function TrackRow(widget)
        bodyRows[#bodyRows + 1] = widget
        return widget
    end

    local function RebuildScrollContent()
        if not scrollChild then return end
        ReleaseBodyRows()
        local y = 0

        local catSection = TrackRow(FontManager:CreateFontString(scrollChild, "subtitle", "OVERLAY"))
        catSection:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        catSection:SetWidth(scrollContentW)
        catSection:SetJustifyH("LEFT")
        ns.UI_SetTextColorRole(catSection, "Bright")
        catSection:SetText((ns.L and ns.L["WEEKLY_TRACK_CATEGORIES"]) or (ns.L and ns.L["QUEST_TYPES"]) or "Track categories:")
        y = y + 22 + LAYOUT.SECTION_GAP

        for i = 1, #CATEGORIES do
            local catInfo = CATEGORIES[i]
            local catKey = catInfo.key
            local display = CAT_DISPLAY[catKey] or {}
            local catColor = display.color or { 0.8, 0.8, 0.8 }
            local catName = display.name and display.name() or catKey

            local cb = TrackRow(CreateThemedCheckbox(scrollChild, selectedQuestTypes[catKey]))
            cb:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)

            local colorBar = scrollChild:CreateTexture(nil, "ARTWORK")
            colorBar:SetSize(LAYOUT.COLOR_BAR_W, LAYOUT.CHECKBOX_W)
            colorBar:SetPoint("LEFT", cb, "RIGHT", LAYOUT.INNER_GAP, 0)
            colorBar:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)
            bodyRows[#bodyRows + 1] = colorBar

            local label = TrackRow(FontManager:CreateFontString(scrollChild, "body", "OVERLAY"))
            label:SetPoint("LEFT", colorBar, "RIGHT", LAYOUT.INNER_GAP, 0)
            label:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
            label:SetJustifyH("LEFT")
            ns.UI_SetTextColorRole(label, "Bright")
            label:SetText(catName)

            local desc = TrackRow(FontManager:CreateFontString(scrollChild, "small", "OVERLAY"))
            desc:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", labelIndent, -(y + LAYOUT.CHECKBOX_W + 2))
            desc:SetWidth(descW)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            ns.UI_SetTextColorRole(desc, "Muted")
            desc:SetText(categoryDescs[catKey] or "")
            local descH = desc:GetStringHeight() or 14

            cb:SetScript("OnClick", function(self2)
                local isChecked = self2:GetChecked()
                selectedQuestTypes[catKey] = isChecked
                if self2.innerDot then self2.innerDot:SetShown(isChecked) end
                if isChecked then
                    local Catalog = ns.MidnightQuestCatalog
                    if Catalog and Catalog.GetSelectableForCategory then
                        local rows = Catalog.GetSelectableForCategory(catKey)
                        for ri = 1, #rows do
                            local e = rows[ri]
                            if e and e.catalogKey then
                                selectedCatalogKeys[e.catalogKey] = true
                            end
                        end
                    end
                else
                    local Catalog = ns.MidnightQuestCatalog
                    if Catalog and Catalog.GetSelectableForCategory then
                        local rows = Catalog.GetSelectableForCategory(catKey)
                        for ri = 1, #rows do
                            local e = rows[ri]
                            if e and e.catalogKey then
                                selectedCatalogKeys[e.catalogKey] = nil
                            end
                        end
                    end
                end
                RebuildScrollContent()
            end)

            y = y + LAYOUT.CHECKBOX_W + 2 + descH + LAYOUT.CAT_GAP
        end

        y = y + LAYOUT.SECTION_GAP

        local itemsLabel = TrackRow(FontManager:CreateFontString(scrollChild, "subtitle", "OVERLAY"))
        itemsLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        itemsLabel:SetWidth(scrollContentW)
        itemsLabel:SetJustifyH("LEFT")
        ns.UI_SetTextColorRole(itemsLabel, "Bright")
        itemsLabel:SetText((ns.L and ns.L["WEEKLY_TRACK_ITEMS"]) or "Track specific objectives:")
        y = y + 22 + 8

        local Catalog = ns.MidnightQuestCatalog
        if Catalog and Catalog.GetSelectableForCategory then
            for ci = 1, #CATEGORIES do
                local catInfo = CATEGORIES[ci]
                local catKey = catInfo.key
                if selectedQuestTypes[catKey] then
                    local display = CAT_DISPLAY[catKey] or {}
                    local catColor = display.color or { 0.8, 0.8, 0.8 }
                    local catName = display.name and display.name() or catKey

                    local hdr = TrackRow(FontManager:CreateFontString(scrollChild, "small", "OVERLAY"))
                    hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    hdr:SetWidth(scrollContentW)
                    hdr:SetJustifyH("LEFT")
                    hdr:SetText(format("|cff%02x%02x%02x%s|r",
                        math.floor(catColor[1] * 255), math.floor(catColor[2] * 255), math.floor(catColor[3] * 255), catName))
                    y = y + 18

                    local selectable = Catalog.GetSelectableForCategory(catKey)
                    for si = 1, #selectable do
                        local entry = selectable[si]
                        local ckey = entry.catalogKey
                        if ckey then
                            local titleLine = entry.title or ckey
                            if entry.coreWeekly then
                                titleLine = titleLine .. " " .. ((ns.L and ns.L["WEEKLY_CORE_BADGE"]) or "(core)")
                            end

                            local row = TrackRow(Factory:CreateContainer(scrollChild, scrollContentW, LAYOUT.ROW_H, false))
                            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)

                            local itemCb = CreateThemedCheckbox(row, selectedCatalogKeys[ckey] == true)
                            itemCb:SetPoint("TOPLEFT", 0, -2)
                            itemCb:SetScript("OnClick", function(self2)
                                local checked = self2:GetChecked()
                                selectedCatalogKeys[ckey] = checked or nil
                                if self2.innerDot then self2.innerDot:SetShown(checked) end
                            end)

                            local lbl = FontManager:CreateFontString(row, "small", "OVERLAY")
                            lbl:SetPoint("TOPLEFT", itemCb, "TOPRIGHT", LAYOUT.INNER_GAP, 0)
                            lbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                            lbl:SetJustifyH("LEFT")
                            lbl:SetWordWrap(true)
                            ns.UI_SetTextColorRole(lbl, "Normal")
                            lbl:SetText(titleLine)

                            local rowH = math.max(LAYOUT.ROW_H, lbl:GetStringHeight() + 4)
                            if entry.description and entry.description ~= "" then
                                local descFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                descFs:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
                                descFs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                                descFs:SetJustifyH("LEFT")
                                descFs:SetWordWrap(true)
                                ns.UI_SetTextColorRole(descFs, "Muted")
                                descFs:SetText(entry.description)
                                rowH = math.max(rowH, LAYOUT.ROW_H + (descFs:GetStringHeight() or 12) + 2)
                            end
                            row:SetHeight(rowH)

                            y = y + rowH + 4
                        end
                    end

                    if catKey == "worldQuests" or catKey == "dailyQuests" or catKey == "assignments" then
                        local note = TrackRow(FontManager:CreateFontString(scrollChild, "small", "OVERLAY"))
                        note:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", labelIndent, -y)
                        note:SetWidth(descW)
                        note:SetJustifyH("LEFT")
                        note:SetWordWrap(true)
                        ns.UI_SetTextColorRole(note, "Muted")
                        note:SetText((ns.L and ns.L["WEEKLY_TRACK_DYNAMIC_NOTE"]) or "All active map quests in this category are tracked when enabled.")
                        y = y + (note:GetStringHeight() or 14) + 6
                    end

                    y = y + 6
                end
            end

            -- Upcoming patch objectives (preview only; not selectable until live)
            local upcomingAny = false
            for ci = 1, #CATEGORIES do
                local catKey = CATEGORIES[ci].key
                if selectedQuestTypes[catKey] then
                    local upcoming = Catalog.GetSelectableForCategory(catKey, { includeUpcoming = true })
                    for ui = 1, #upcoming do
                        local entry = upcoming[ui]
                        if entry and Catalog.IsEntryAvailable and not Catalog.IsEntryAvailable(entry) then
                            upcomingAny = true
                            break
                        end
                    end
                    if upcomingAny then break end
                end
            end
            if upcomingAny then
                y = y + LAYOUT.SECTION_GAP
                local upHdr = TrackRow(FontManager:CreateFontString(scrollChild, "subtitle", "OVERLAY"))
                upHdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                upHdr:SetWidth(scrollContentW)
                upHdr:SetJustifyH("LEFT")
                ns.UI_SetTextColorRole(upHdr, "Bright")
                upHdr:SetText((ns.L and ns.L["WEEKLY_CATALOG_SECTION_UPCOMING"]) or "Patch 12.0.7 (upcoming)")
                y = y + 20
                local upNote = TrackRow(FontManager:CreateFontString(scrollChild, "small", "OVERLAY"))
                upNote:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                upNote:SetWidth(scrollContentW)
                upNote:SetJustifyH("LEFT")
                upNote:SetWordWrap(true)
                ns.UI_SetTextColorRole(upNote, "Muted")
                upNote:SetText((ns.L and ns.L["WEEKLY_CATALOG_UPCOMING_NOTE"]) or "These objectives appear when patch 12.0.7 is live on your client.")
                y = y + (upNote:GetStringHeight() or 14) + 8
                for ci = 1, #CATEGORIES do
                    local catKey = CATEGORIES[ci].key
                    if selectedQuestTypes[catKey] then
                        local upcoming = Catalog.GetSelectableForCategory(catKey, { includeUpcoming = true })
                        for ui = 1, #upcoming do
                            local entry = upcoming[ui]
                            if entry and Catalog.IsEntryAvailable and not Catalog.IsEntryAvailable(entry) then
                                local line = TrackRow(FontManager:CreateFontString(scrollChild, "small", "OVERLAY"))
                                line:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", labelIndent, -y)
                                line:SetWidth(descW)
                                line:SetJustifyH("LEFT")
                                line:SetWordWrap(true)
                                ns.UI_SetTextColorRole(line, "Muted")
                                line:SetText("- " .. (entry.title or entry.catalogKey or "?"))
                                y = y + (line:GetStringHeight() or 14) + 2
                            end
                        end
                    end
                end
            end
        end

        scrollChild:SetHeight(math.max(1, y + 12))
        if scrollFrame and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scrollFrame)
        end
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end

    local function ApplyEssentialsPreset()
        selectedQuestTypes.weeklyQuests = true
        selectedQuestTypes.events = true
        selectedQuestTypes.assignments = true
        selectedQuestTypes.worldQuests = false
        selectedQuestTypes.dailyQuests = false
        RebuildDefaultCatalogKeys()
        RebuildScrollContent()
    end

    local function ApplyTrackAllPreset()
        for k in pairs(selectedQuestTypes) do
            selectedQuestTypes[k] = true
        end
        wipe(selectedCatalogKeys)
        local allKeys = WarbandNexus:BuildAllAvailableTrackedCatalogKeys(selectedQuestTypes)
        for k, v in pairs(allKeys) do
            if v then selectedCatalogKeys[k] = true end
        end
        RebuildScrollContent()
    end

    local PRESET_H = 34
    local presetBar = Factory:CreateContainer(contentFrame, scrollContentW + (PAD * 2), PRESET_H, false)
    presetBar:SetPoint("TOPLEFT", charFrame, "BOTTOMLEFT", 0, -6)

    local essentialsBtn = CreateThemedButton(presetBar, (ns.L and ns.L["WEEKLY_PRESET_ESSENTIALS"]) or "Weekly essentials", 150)
    essentialsBtn:SetPoint("LEFT", 0, 0)
    essentialsBtn:SetScript("OnClick", ApplyEssentialsPreset)

    local allBtn = CreateThemedButton(presetBar, (ns.L and ns.L["WEEKLY_PRESET_ALL"]) or "Track all", 120)
    allBtn:SetPoint("LEFT", essentialsBtn, "RIGHT", 8, 0)
    allBtn:SetScript("OnClick", ApplyTrackAllPreset)

    local scrollTop = -(PAD + CHAR_HDR_H + PRESET_H + 6)
    scrollFrame = Factory:CreateScrollFrame(contentFrame, nil, true)
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -(PAD + sbReserve), FOOTER_H)

    if Factory.CreateBareScrollBarColumn and Factory.EnsureScrollBarColumnSync then
        local scrollBarColumn = Factory:CreateBareScrollBarColumn(contentFrame, scrollbarW)
        Factory:EnsureScrollBarColumnSync(scrollFrame, scrollBarColumn, { width = scrollbarW, gap = 2 })
    elseif Factory.CreateScrollBarColumn and Factory.PositionScrollBarInContainer then
        local scrollBarColumn = Factory:CreateScrollBarColumn(contentFrame, scrollbarW, 0, 0)
        if scrollFrame.ScrollBar then
            Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
    end

    scrollChild = Factory:CreateContainer(scrollFrame, scrollContentW, 200, false)
    if scrollFrame.SetScrollChild then
        scrollFrame:SetScrollChild(scrollChild)
    end
    scrollChild:SetWidth(scrollContentW)

    if ns.UI_EnableStandardScrollWheel then
        ns.UI_EnableStandardScrollWheel(scrollFrame)
    end
    if scrollFrame.SetClipsChildren then
        scrollFrame:SetClipsChildren(true)
    end

    RebuildScrollContent()

    local createBtn = CreateThemedButton(contentFrame, isEdit and ((ns.L and ns.L["SAVE"]) or "Save") or ((ns.L and ns.L["CREATE_PLAN"]) or "Track Character"), 140)
    createBtn:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD + 20, PAD)
    createBtn:SetScript("OnClick", function()
        local keysCopy = {}
        for k, v in pairs(selectedCatalogKeys) do
            if v then keysCopy[k] = true end
        end
        if isEdit then
            if WarbandNexus:UpdateDailyPlanTracking(editPlan, selectedQuestTypes, keysCopy) then
                dialog.Close()
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end
        else
            local plan = WarbandNexus:CreateDailyPlan(currentName, currentRealm, selectedQuestTypes, keysCopy)
            if plan then
                dialog.Close()
            end
        end
    end)

    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 100)
    cancelBtn:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -(PAD + 20), PAD)
    cancelBtn:SetScript("OnClick", function() dialog.Close() end)

    dialog:Show()
end

function WarbandNexus:ShowDailyPlanDialog()
    M.ShowDailyPlanDialog(nil)
end

function WarbandNexus:ShowWeeklyProgressPlanDialog(plan)
    M.ShowDailyPlanDialog(plan)
end

function WarbandNexus:ShowDailyPlanExistsDialog(characterName, characterRealm)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local CreateIcon = ns.UI_CreateIcon
    local FontManager = ns.FontManager
    if not CreateExternalWindow then return end

    local dialog, contentFrame = CreateExternalWindow({
        name = "DailyPlanDialog",
        title = (ns.L and ns.L["DAILY_QUEST_TRACKER"]) or "Midnight Quest Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        width = 460,
        height = 220,
    })
    if not dialog then return end

    local warningIconFrame = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", 40, false, nil, true)
    warningIconFrame:SetPoint("TOP", 0, -30)
    warningIconFrame:Show()

    local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
    warningText:SetPoint("TOP", warningIconFrame, "BOTTOM", 0, -10)
    warningText:SetText("|cffff9900" .. ((ns.L and ns.L["DAILY_PLAN_EXISTS"]) or "Plan Already Exists") .. "|r")

    local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -8)
    infoText:SetWidth(400)
    infoText:SetWordWrap(true)
    infoText:SetJustifyH("CENTER")
    local charFullName = characterName .. "-" .. characterRealm
    local dailyExistsDesc = (ns.L and ns.L["DAILY_PLAN_EXISTS_DESC"]) or "%s already has an active weekly quest plan. You can find it in the 'Weekly Progress' category."
    infoText:SetText("|cffaaaaaa" .. string.format(dailyExistsDesc, charFullName) .. "|r")

    local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
    okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -16)
    okBtn:SetScript("OnClick", function() dialog.Close() end)

    dialog:Show()
end
