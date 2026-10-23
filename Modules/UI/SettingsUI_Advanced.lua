--[[
    Warband Nexus - Settings UI advanced panel (Track Item DB, debug options).
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_Advanced.lua loaded before SettingsUI.lua - check the TOC")

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendAdvancedPanel(ctx)
    local H = M._H
    local wipe = H.wipe
    local WarbandNexus = H.WarbandNexus
    local COLORS = H.COLORS
    local FontManager = H.FontManager
    local ns = H.ns
    local issecretvalue = H.issecretvalue
    local SETTINGS_LAYOUT = H.SETTINGS_LAYOUT
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_SCROLL_INSET_BOTTOM = H.SETTINGS_SCROLL_INSET_BOTTOM
    local SETTINGS_COMPACT_BTN_H = H.SETTINGS_COMPACT_BTN_H
    local SETTINGS_CARD_OUTER_BOTTOM_PAD = H.SETTINGS_CARD_OUTER_BOTTOM_PAD
    local CONTENT_PADDING_TOP = H.CONTENT_PADDING_TOP
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local CreateDropdownWidget = H.CreateDropdownWidget
    local CreateInputWidget = H.CreateInputWidget
    local CreateButtonGrid = H.CreateButtonGrid
    local CreateThemedCheckbox = H.CreateThemedCheckbox
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local ApplySettingsChrome = H.ApplySettingsChrome
    local ApplySettingsAccentChromeIdle = H.ApplySettingsAccentChromeIdle
    local WireSettingsAccentButtonHover = H.WireSettingsAccentButtonHover
    local RegisterSettingsAccentChrome = H.RegisterSettingsAccentChrome
    local SettingsControlChrome = H.SettingsControlChrome
    local SettingsControlChromeHover = H.SettingsControlChromeHover
    local SettingsNestedCardBg = H.SettingsNestedCardBg
    local Settings_ShowWrappedTooltip = H.Settings_ShowWrappedTooltip
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- TRACK ITEM DB
    yOffset = AppendSettingsPanelIntro(parent, "advanced", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local trackSection = CreateSection(parent, (ns.L and ns.L["TRACK_ITEM_DB"]) or "Track Item DB", effectiveWidth)
    AnchorSectionTop(trackSection, yOffset)
    
    -- Collapsible: arrow + title aligned with other sections (15px left padding, same as CreateSection)
    local COLLAPSED_HEIGHT = CONTENT_PADDING_TOP  -- title bar only
    local trackIsCollapsed = true  -- default collapsed
    local HEADER_LEFT_INDENT = SETTINGS_LAYOUT.SECTION_CARD_PAD_X
    local ARROW_TITLE_GAP = 6
    
    local trackChevronBtn = ns.UI_CreateCollapseExpandControl(trackSection, not trackIsCollapsed, { enableMouse = false })
    trackChevronBtn:SetPoint("TOPLEFT", trackSection, "TOPLEFT", HEADER_LEFT_INDENT, -12)

    local titleText = trackSection.titleText
    titleText:ClearAllPoints()
    titleText:SetPoint("LEFT", trackChevronBtn, "RIGHT", ARROW_TITLE_GAP, 0)
    titleText:SetPoint("RIGHT", trackSection, "RIGHT", -HEADER_LEFT_INDENT, 0)
    titleText:SetPoint("TOP", trackChevronBtn, "TOP")
    titleText:SetPoint("BOTTOM", trackChevronBtn, "BOTTOM")
    
    local collapseBtn = ns.UI.Factory:CreateButton(trackSection, 1, 24, true)
    if collapseBtn then
        collapseBtn:SetPoint("TOPLEFT", trackChevronBtn, "TOPLEFT")
        collapseBtn:SetPoint("BOTTOMRIGHT", titleText, "BOTTOMRIGHT")
    end
    
    local trackYOffset = 0
    local trackContentWidth = GetSettingsSectionContentWidth(effectiveWidth)
    
    -- SUB-PANEL: Item Tracking
    
    local manageHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    manageHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    manageHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["MANAGE_ITEMS"]) or "Item Tracking") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Build unique item list from CollectibleSourceDB
    local itemRegistry = {}   -- { [key] = { name, type, itemID, repeatable, guaranteed, sources } }
    local dropdownValues = {} -- { [key] = "Display Name" }
    
    local function RegisterDrop(drop, sourceType, sourceID)
        if not drop or not drop.itemID or not drop.name then return end
        local key = (drop.type or "item") .. ":" .. drop.itemID
        if not itemRegistry[key] then
            itemRegistry[key] = {
                name = drop.name,
                type = drop.type or "item",
                itemID = drop.itemID,
                repeatable = drop.repeatable or false,
                guaranteed = drop.guaranteed or false,
                sources = {},
            }
            local typeLabel = ""
            if drop.type == "mount" then
                typeLabel = "|cff00ccff[" .. ((ns.L and ns.L["TYPE_MOUNT"]) or "Mount") .. "]|r "
            elseif drop.type == "pet" then
                typeLabel = "|cff44ff44[" .. ((ns.L and ns.L["TYPE_PET"]) or "Pet") .. "]|r "
            elseif drop.type == "toy" then
                typeLabel = "|cffff8800[" .. ((ns.L and ns.L["TYPE_TOY"]) or "Toy") .. "]|r "
            elseif drop.type == "illusion" then
                typeLabel = "|cffcc66ff[" .. ((ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion") .. "]|r "
            else
                typeLabel = "|cff888888[" .. ((ns.L and ns.L["TYPE_ITEM"]) or "Item") .. "]|r "
            end
            dropdownValues[key] = typeLabel .. drop.name
        end
        local sources = itemRegistry[key].sources
        local found = false
        for si = 1, #sources do
            local s = sources[si]
            if s.sourceType == sourceType and s.sourceID == sourceID then
                found = true
                break
            end
        end
        if not found then
            sources[#sources + 1] = { sourceType = sourceType, sourceID = sourceID }
        end
    end
    
    do
        local db = ns.CollectibleSourceDB
        if db then
            for npcID, npcData in pairs(db.npcs or {}) do
                for i = 1, #npcData do RegisterDrop(npcData[i], "npc", npcID) end
            end
            for objID, objData in pairs(db.objects or {}) do
                for i = 1, #objData do RegisterDrop(objData[i], "object", objID) end
            end
            for zoneID, zoneData in pairs(db.fishing or {}) do
                for i = 1, #zoneData do RegisterDrop(zoneData[i], "fishing", zoneID) end
            end
            for containerID, cData in pairs(db.containers or {}) do
                local drops = cData.drops or cData
                if type(drops) == "table" then
                    for i = 1, #drops do RegisterDrop(drops[i], "container", containerID) end
                end
            end
        end
    end
    
    -- Persistent state
    if not ns._trackDBSelected then ns._trackDBSelected = {} end
    
    -- Detail card (subtle background panel for selected item info)
    local detailCard = ns.UI.Factory:CreateContainer(trackSection.content, trackContentWidth, 80, true)
    if detailCard and ApplySettingsChrome then
        ApplySettingsChrome(detailCard, SettingsNestedCardBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5 })
    end
    
    -- Detail card children (created once, updated on selection)
    local detailNameText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailNameText:SetPoint("TOPLEFT", 10, -8)
    detailNameText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailNameText:SetJustifyH("LEFT")
    detailNameText:SetWordWrap(true)
    
    local detailInfoText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailInfoText:SetPoint("TOPLEFT", 10, -26)
    detailInfoText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailInfoText:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(detailInfoText, "Muted")
    detailInfoText:SetWordWrap(true)
    
    -- Tracked checkbox (inside detail card)
    local trackedCheckbox = CreateThemedCheckbox(detailCard)
    trackedCheckbox:SetPoint("TOPLEFT", 8, -48)
    
    local trackedLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    trackedLabel:SetPoint("LEFT", trackedCheckbox, "RIGHT", 6, 0)
    trackedLabel:SetText((ns.L and ns.L["TRACKED"]) or "Tracked")
    ns.UI_SetTextColorRole(trackedLabel, "Bright")
    
    -- Repeatable checkbox (inside detail card, right of Tracked)
    local repeatableCheckbox = CreateThemedCheckbox(detailCard)
    repeatableCheckbox:SetPoint("LEFT", trackedLabel, "RIGHT", 20, 0)
    
    local repeatableLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    repeatableLabel:SetPoint("LEFT", repeatableCheckbox, "RIGHT", 6, 0)
    repeatableLabel:SetText((ns.L and ns.L["REPEATABLE_LABEL"]) or "Repeatable")
    ns.UI_SetTextColorRole(repeatableLabel, "Bright")
    
    -- Placeholder when nothing is selected
    local detailPlaceholder = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailPlaceholder:SetPoint("TOPLEFT", 10, -8)
    detailPlaceholder:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailPlaceholder:SetText("|cff555555" .. ((ns.L and ns.L["SELECT_ITEM_HINT"]) or "Select an item above to view details.") .. "|r")
    detailPlaceholder:SetJustifyH("LEFT")
    
    trackedCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        local srcList = info.sources
        for si = 1, #srcList do
            local src = srcList[si]
            WarbandNexus:SetBuiltinTracked(src.sourceType, src.sourceID, info.itemID, isChecked)
        end
        local statusStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["TRACKED"]) or "Tracked") .. "|r")
            or ("|cffff6600" .. ((ns.L and ns.L["UNTRACKED"]) or "Untracked") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → %s", info.name, statusStr))
    end)
    
    repeatableCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        WarbandNexus:SetBuiltinRepeatable(info.type, info.itemID, isChecked)
        -- Update the info line to reflect the change
        info.repeatable = isChecked
        local repeatStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["YES"]) or "Yes") .. "|r")
            or ("|cff666666" .. ((ns.L and ns.L["NO"]) or "No") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → Repeatable: %s", info.name, repeatStr))
    end)
    
    local function IsItemFullyTracked(info)
        if not info or not info.sources then return true end
        local srcList2 = info.sources
        for si = 1, #srcList2 do
            local src = srcList2[si]
            if not WarbandNexus:IsBuiltinTracked(src.sourceType, src.sourceID, info.itemID) then
                return false
            end
        end
        return true
    end
    
    local function UpdateDetailPanel(key)
        local info = itemRegistry[key]
        if not info then
            detailPlaceholder:Show()
            detailNameText:SetText("")
            detailInfoText:SetText("")
            trackedCheckbox:Hide()
            trackedLabel:Hide()
            repeatableCheckbox:Hide()
            repeatableLabel:Hide()
            return
        end
        ns._trackDBSelected = { key = key }
        detailPlaceholder:Hide()
        
        -- Name with type color
        local typeColor = "ffffff"
        if info.type == "mount" then typeColor = "00ccff"
        elseif info.type == "pet" then typeColor = "44ff44"
        elseif info.type == "toy" then typeColor = "ff8800"
        elseif info.type == "illusion" then typeColor = "cc66ff" end
        detailNameText:SetText("|cff" .. typeColor .. info.name .. "|r")
        
        -- Info line (type + source count only, repeatable is now a checkbox)
        local typeName = info.type:sub(1,1):upper() .. info.type:sub(2)
        local srcCount = #info.sources
        local srcLabel = srcCount == 1 and ((ns.L and ns.L["SOURCE_SINGULAR"]) or "source") or ((ns.L and ns.L["SOURCE_PLURAL"]) or "sources")
        detailInfoText:SetText(format("%s  |cff444444·|r  %d %s", typeName, srcCount, srcLabel))
        
        -- Tracked checkbox
        local isTracked = IsItemFullyTracked(info)
        trackedCheckbox:SetChecked(isTracked)
        if trackedCheckbox.checkTexture then trackedCheckbox.checkTexture:SetShown(isTracked) end
        trackedCheckbox:Show()
        trackedLabel:Show()
        
        -- Repeatable checkbox (check override first, then DB default)
        local override = WarbandNexus:GetRepeatableOverride(info.type, info.itemID)
        local isRepeatable = (override ~= nil) and override or info.repeatable
        repeatableCheckbox:SetChecked(isRepeatable)
        if repeatableCheckbox.checkTexture then repeatableCheckbox.checkTexture:SetShown(isRepeatable) end
        repeatableCheckbox:Show()
        repeatableLabel:Show()
    end
    
    -- Dropdown: Select item from DB
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SELECT_ITEM"]) or "Select Item",
        desc = (ns.L and ns.L["SELECT_ITEM_DESC"]) or "Choose a collectible to manage.",
        values = function() return dropdownValues end,
        get = function()
            return ns._trackDBSelected and ns._trackDBSelected.key or nil
        end,
        set = function(_, val)
            UpdateDetailPanel(val)
        end,
    }, trackYOffset)
    
    -- Position detail card below dropdown (fixed height: always visible as card)
    local DETAIL_CARD_HEIGHT = 78
    detailCard:SetPoint("TOPLEFT", 0, trackYOffset)
    detailCard:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    detailCard:SetHeight(DETAIL_CARD_HEIGHT)
    detailCard:Show()
    
    -- Restore previous selection or show placeholder
    if ns._trackDBSelected and ns._trackDBSelected.key and itemRegistry[ns._trackDBSelected.key] then
        UpdateDetailPanel(ns._trackDBSelected.key)
    else
        detailPlaceholder:Show()
        detailNameText:SetText("")
        detailInfoText:SetText("")
        trackedCheckbox:Hide()
        trackedLabel:Hide()
        repeatableCheckbox:Hide()
        repeatableLabel:Hide()
    end
    trackYOffset = trackYOffset - DETAIL_CARD_HEIGHT - 16
    
    -- SUB-PANEL: Custom Entries
    
    -- Divider line
    local trackDivider2
    if ns.UI.Factory and ns.UI.Factory.CreateThemeDivider then
        trackDivider2 = ns.UI.Factory:CreateThemeDivider(trackSection.content, {
            orientation = "horizontal",
            variant = "section",
            thickness = 2,
        })
        if trackDivider2 then
            trackDivider2:SetPoint("TOPLEFT", 0, trackYOffset)
            trackDivider2:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
        end
    end
    trackYOffset = trackYOffset - 12
    
    -- Sub-header
    local customSectionHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customSectionHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    customSectionHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["CUSTOM_ENTRIES"]) or "Custom Entries") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Custom entries list (no separate "Current:" label — shown inline)
    local customListText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customListText:SetPoint("TOPLEFT", 4, trackYOffset)
    customListText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    customListText:SetJustifyH("LEFT")
    customListText:SetWordWrap(true)
    
    -- Custom entries list builder + remove dropdown value builder
    local removeDropdownValues = {}
    local function RefreshCustomList()
        if not WarbandNexus.db or not WarbandNexus.db.global then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local trackDB = WarbandNexus.db.global.trackDB
        if not trackDB or not trackDB.custom then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local lines = {}
        wipe(removeDropdownValues)
        for npcID, drops in pairs(trackDB.custom.npcs or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666npc:%s|r",
                    d.name or "?", repStr, tostring(npcID))
                local removeKey = "npc:" .. tostring(npcID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (npc:" .. npcID .. ")"
            end
        end
        for objID, drops in pairs(trackDB.custom.objects or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666obj:%s|r",
                    d.name or "?", repStr, tostring(objID))
                local removeKey = "object:" .. tostring(objID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (obj:" .. objID .. ")"
            end
        end
        if #lines == 0 then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
        else
            customListText:SetText(table.concat(lines, "\n"))
        end
    end
    RefreshCustomList()
    -- Use a safe minimum height for the custom list (at least 14px per line, min 14px)
    local customListH = customListText:GetStringHeight()
    if not customListH or customListH < 14 then customListH = 14 end
    trackYOffset = trackYOffset - customListH - 12
    
    -- Form state
    if not ns._trackDBForm then ns._trackDBForm = {} end
    
    -- Item ID label
    local itemIDLabel = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    itemIDLabel:SetPoint("TOPLEFT", 0, trackYOffset)
    itemIDLabel:SetText((ns.L and ns.L["ITEM_ID_INPUT"]) or "Item ID")
    ns.UI_SetTextColorRole(itemIDLabel, "Bright")
    itemIDLabel:SetScript("OnEnter", function(self)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["ITEM_ID_INPUT_DESC"]) or "Enter the item ID to track.")
    end)
    itemIDLabel:SetScript("OnLeave", function() ns.UI_SafeHideGameTooltip() end)
    trackYOffset = trackYOffset - 22
    
    -- Item ID editbox + Lookup button on the SAME row
    local editBoxWidth = math.floor(trackContentWidth * 0.45)
    local lookupBtnWidth = 100
    local inlineGap = 8
    
    local itemIDBox = ns.UI.Factory:CreateEditBox(trackSection.content)
    if itemIDBox then
        itemIDBox:SetHeight(30)
        itemIDBox:SetWidth(editBoxWidth)
        itemIDBox:SetPoint("TOPLEFT", 0, trackYOffset)
        itemIDBox:SetTextInsets(10, 10, 0, 0)
        itemIDBox:SetMaxLetters(20)
        itemIDBox:SetNumeric(false)
        if ApplySettingsChrome then
            ApplySettingsAccentChromeIdle(itemIDBox)
        end
        WireSettingsAccentButtonHover(itemIDBox)
        RegisterSettingsAccentChrome(itemIDBox)
        itemIDBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        itemIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    
    -- Lookup result text (positioned below the input row)
    local lookupResultText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    lookupResultText:SetPoint("TOPLEFT", 0, trackYOffset - 34)
    lookupResultText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    lookupResultText:SetText("")
    lookupResultText:SetWordWrap(true)
    lookupResultText:SetJustifyH("LEFT")
    
    -- Lookup button (inline, right of editbox)
    local lookupBtn = ns.UI.Factory:CreateButton(trackSection.content)
    lookupBtn:SetSize(lookupBtnWidth, SETTINGS_COMPACT_BTN_H)
    lookupBtn:SetPoint("LEFT", itemIDBox, "RIGHT", inlineGap, 0)
    local lookupBtnColor = { 0.20, 0.50, 0.70 }
    if ApplySettingsChrome then
        ApplySettingsChrome(lookupBtn, SettingsControlChrome(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
    end
    local lookupBtnText = FontManager:CreateFontString(lookupBtn, "body", "OVERLAY")
    lookupBtnText:SetPoint("CENTER")
    lookupBtnText:SetText((ns.L and ns.L["LOOKUP_ITEM"]) or "Lookup")
    lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
    lookupBtn:SetScript("OnClick", function()
        local rawID = itemIDBox:GetText()
        if issecretvalue and issecretvalue(rawID) then return end
        local itemID = tonumber(rawID)
        if not itemID then return end
        ns._trackDBForm.itemID = itemID
        ns._trackDBForm.itemName = nil
        ns._trackDBForm.itemIcon = nil
        ns._trackDBForm.itemType = nil
        WarbandNexus:LookupItem(itemID, function(_, name, icon, cType)
            if name then
                ns._trackDBForm.itemName = name
                ns._trackDBForm.itemIcon = icon
                ns._trackDBForm.itemType = cType
                local iconStr = icon and ("|T" .. icon .. ":16|t ") or ""
                lookupResultText:SetText(iconStr .. "|cff00ff00" .. name .. "|r |cff888888(" .. (cType or "item") .. ")|r")
            else
                lookupResultText:SetText("|cffff4444" .. ((ns.L and ns.L["ITEM_LOOKUP_FAILED"]) or "Item not found.") .. "|r")
            end
        end)
    end)
    lookupBtn:SetScript("OnEnter", function(self)
        if ApplySettingsChrome then
            ApplySettingsChrome(lookupBtn, SettingsControlChromeHover(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 1})
        end
        ns.UI_SetTextColorRole(lookupBtnText, "Bright")
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["LOOKUP_ITEM_DESC"]) or "Resolve item name and type from ID.")
    end)
    lookupBtn:SetScript("OnLeave", function()
        if ApplySettingsChrome then
            ApplySettingsChrome(lookupBtn, SettingsControlChrome(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
        end
        lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
        ns.UI_SafeHideGameTooltip()
    end)
    
    -- Advance past: editbox (30) + lookup result line (18) + gap (12)
    trackYOffset = trackYOffset - 30 - 18 - 12
    
    -- Source Type dropdown
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_TYPE"]) or "Source Type",
        desc = (ns.L and ns.L["SOURCE_TYPE_DESC"]) or "NPC or Object.",
        values = { npc = (ns.L and ns.L["SOURCE_TYPE_NPC"]) or "NPC", object = (ns.L and ns.L["SOURCE_TYPE_OBJECT"]) or "Object" },
        get = function() return ns._trackDBForm.sourceType or "npc" end,
        set = function(_, val) ns._trackDBForm.sourceType = val end,
    }, trackYOffset)
    
    -- Source ID input
    local sourceIDBox
    trackYOffset, sourceIDBox = CreateInputWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_ID"]) or "Source ID",
        desc = (ns.L and ns.L["SOURCE_ID_DESC"]) or "NPC ID or Object ID.",
        width = trackContentWidth * 0.45,
        numeric = true,
    }, trackYOffset)
    
    -- Repeatable checkbox
    trackYOffset = CreateCheckboxGrid(trackSection.content, {
        {
            key = "trackDB_repeatable",
            label = (ns.L and ns.L["REPEATABLE_TOGGLE"]) or "Repeatable",
            tooltip = (ns.L and ns.L["REPEATABLE_TOGGLE_DESC"]) or "Whether this drop can be attempted multiple times per lockout.",
            get = function() return ns._trackDBForm.repeatable or false end,
            set = function(val) ns._trackDBForm.repeatable = val end,
        },
    }, trackYOffset, trackContentWidth)
    
    -- [+ Add Entry] + [- Remove Selected] side-by-side
    if not ns._trackDBRemoveKey then ns._trackDBRemoveKey = nil end
    trackYOffset = CreateButtonGrid(trackSection.content, {
        {
            label = (ns.L and ns.L["ADD_ENTRY"]) or "+ Add Entry",
            tooltip = (ns.L and ns.L["ADD_ENTRY_DESC"]) or "Add this custom drop entry.",
            func = function()
                local f = ns._trackDBForm
                local rawItem = itemIDBox:GetText()
                local rawSrc = sourceIDBox:GetText()
                if (issecretvalue and issecretvalue(rawItem))
                    or (issecretvalue and issecretvalue(rawSrc)) then
                    return
                end
                local itemID = tonumber(rawItem)
                local sourceID = tonumber(rawSrc)
                if not itemID or not sourceID then
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Item ID and Source ID are required.") .. "|r")
                    return
                end
                local drop = {
                    type = f.itemType or "item",
                    itemID = itemID,
                    name = f.itemName or ("Item " .. itemID),
                    repeatable = f.repeatable or nil,
                }
                local ok = WarbandNexus:AddCustomDrop(f.sourceType or "npc", sourceID, drop, nil)
                if ok then
                    WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_ADDED"]) or "Custom entry added.") .. "|r")
                    ns._trackDBForm = {}
                    itemIDBox:SetText("")
                    sourceIDBox:SetText("")
                    lookupResultText:SetText("")
                    RefreshCustomList()
                else
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Failed to add entry.") .. "|r")
                end
            end,
            color = { 0.20, 0.60, 0.40 },
        },
        {
            label = (ns.L and ns.L["REMOVE_BUTTON"]) or "- Remove Selected",
            tooltip = (ns.L and ns.L["REMOVE_BUTTON_DESC"]) or "Remove the selected custom entry.",
            func = function()
                local val = ns._trackDBRemoveKey
                if not val or val == "" then return end
                local sourceType, sourceID, itemID = strsplit(":", val)
                sourceID = tonumber(sourceID)
                itemID = tonumber(itemID)
                if sourceType and sourceID and itemID then
                    local ok = WarbandNexus:RemoveCustomDrop(sourceType, sourceID, itemID)
                    if ok then
                        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_REMOVED"]) or "Entry removed.") .. "|r")
                        ns._trackDBRemoveKey = nil
                        RefreshCustomList()
                    end
                end
            end,
            color = { 0.60, 0.22, 0.22 },
        },
    }, trackYOffset, trackContentWidth, 160)
    
    -- Remove entry dropdown (select which custom entry to remove)
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["REMOVE_ENTRY"]) or "Remove Custom Entry",
        desc = (ns.L and ns.L["REMOVE_ENTRY_DESC"]) or "Select a custom entry to remove.",
        values = function() return removeDropdownValues end,
        get = function() return ns._trackDBRemoveKey end,
        set = function(_, val) ns._trackDBRemoveKey = val end,
    }, trackYOffset)
    
    -- Final section height (expanded)
    local trackContentHeight = SettingsMeasuredSectionContentHeight(trackYOffset)
    local trackExpandedHeight = trackContentHeight + CONTENT_PADDING_TOP + SETTINGS_CARD_OUTER_BOTTOM_PAD
    trackSection.content:SetHeight(trackContentHeight)
    
    -- Default collapsed: hide content, use collapsed height
    trackSection.content:Hide()
    trackSection:SetHeight(COLLAPSED_HEIGHT)
    
    local trackSectionYBase = yOffset  -- yOffset before track section
    yOffset = yOffset - COLLAPSED_HEIGHT - SETTINGS_SECTION_GAP  -- default collapsed offset
    
    -- ADVANCED
    
    local advSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(advSection, yOffset)
    
    -- Debug checkboxes: same 2-column row-major grid as other settings cards.
    -- Order fills [autoOptimize | debug] then [tryCounter | debugVerbose] so Verbose sits under Debug.
    local debugOptions = {
        {
            key = "autoOptimize",
            label = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE"]) or "Auto-Optimize Database",
            tooltip = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE_DESC"]) or "Automatically optimize the database on login to keep storage efficient.",
            get = function() return WarbandNexus.db.profile.autoOptimize ~= false end,
            set = function(value) WarbandNexus.db.profile.autoOptimize = value end,
        },
        {
            key = "debug",
            label = (ns.L and ns.L["DEBUG_MODE"]) or "Debug Logging",
            tooltip = (ns.L and ns.L["DEBUG_MODE_DESC"]) or "Output verbose debug messages to chat for troubleshooting",
            get = function() return WarbandNexus.db.profile.debugMode end,
            set = function(value)
                WarbandNexus.db.profile.debugMode = value
                if ns.Profiler and ns.Profiler.SyncWithDebugMode then
                    ns.Profiler:SyncWithDebugMode()
                end
                local mf = WarbandNexus.mainFrame
                if mf and mf.SyncMainHeaderDebugReloadLayout then
                    mf:SyncMainHeaderDebugReloadLayout()
                end
            end,
        },
        {
            key = "debugTryCounterLoot",
            label = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT"]) or "Try Counter Loot Debug",
            tooltip = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT_DESC"]) or "Log loot flow only (LOOT_OPENED, source resolution, zone fallback). Rep/currency cache logs are suppressed.",
            get = function() return WarbandNexus.db.profile.debugTryCounterLoot end,
            set = function(value) WarbandNexus.db.profile.debugTryCounterLoot = value end,
        },
        {
            key = "debugVerbose",
            parentKey = "debug",
            label = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE"]) or "Debug Verbose (cache/scan/tooltip logs)",
            tooltip = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE_DESC"]) or "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam.",
            get = function() return WarbandNexus.db.profile.debugVerbose end,
            set = function(value) WarbandNexus.db.profile.debugVerbose = value end,
        },
    }

    local advInnerW = GetSettingsSectionContentWidth(effectiveWidth)
    local advGridYOffset = CreateCheckboxGrid(advSection.content, debugOptions, 0, advInnerW)

    -- Calculate section height
    local advContentHeight = SettingsMeasuredSectionContentHeight(advGridYOffset)
    FinalizeSettingsSectionHeight(advSection, advContentHeight, false)
    
    -- Collapsible toggle handler for Track Item DB
    local function ToggleTrackSection()
        trackIsCollapsed = not trackIsCollapsed
        if trackIsCollapsed then
            trackSection.content:Hide()
            trackSection:SetHeight(COLLAPSED_HEIGHT)
            ns.UI_CollapseExpandSetState(trackChevronBtn, false)
        else
            trackSection.content:Show()
            trackSection:SetHeight(trackExpandedHeight)
            ns.UI_CollapseExpandSetState(trackChevronBtn, true)
        end
        -- Reposition Advanced section
        local advY = trackSectionYBase - trackSection:GetHeight() - SETTINGS_SECTION_GAP
        advSection:ClearAllPoints()
        AnchorSectionTop(advSection, advY)
        -- Recalculate total parent height
        local totalY = math.abs(advY) + advSection:GetHeight() + SETTINGS_SCROLL_INSET_BOTTOM
        parent:SetHeight(totalY)
    end
    collapseBtn:SetScript("OnClick", ToggleTrackSection)
    -- Make entire title text area clickable for convenience
    trackSection.titleText:SetScript("OnMouseUp", ToggleTrackSection)
    
    return yOffset
end
