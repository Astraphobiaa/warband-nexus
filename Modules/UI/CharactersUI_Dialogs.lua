--[[
    Warband Nexus - Characters tab: manual reorder + custom section dialogs (split from CharactersUI.lua).
    WarbandNexus:ReorderCharacter, OpenRenameCustomSectionDialog, OpenCustomCharacterHeaderDialog,
    OpenCustomHeaderRosterWindow, ConfirmDeleteCustomCharacterHeader.
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local B = assert(ns.CharactersUI and ns.CharactersUI._bind, "CharactersUI_Dialogs: load Modules/UI/CharactersUI.lua first")
local WarbandNexus = B.WarbandNexus
local E = B.E
local issecretvalue = issecretvalue
local CreateCharacterDeleteDialogButton = B.CreateCharacterDeleteDialogButton
local GetCharKey = B.GetCharKey
local tinsert = B.tinsert
local ResolveSessionCharactersTableKey = B.ResolveSessionCharactersTableKey
local tremove = table.remove

--- One side/bottom pad for every popup body (UI_LAYOUT.PAGE_STACK.SIDE).
local function DialogPad()
    local ps = ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK
    return (ps and ps.SIDE) or 12
end
--- True if a stored order key string refers to the logged-in session (manual sort / pin-to-top).
local function OrderKeyIsSessionChar(orderKey)
    if not orderKey then return false end
    local storage = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    if storage and orderKey == storage then return true end
    local resolved = ResolveSessionCharactersTableKey()
    if resolved and orderKey == resolved then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local canonOrder = ns.Utilities:GetCanonicalCharacterKey(orderKey)
        if storage and canonOrder == storage then return true end
        if resolved and canonOrder == resolved then return true end
    end
    return false
end

function WarbandNexus:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then
        return
    end
    
    local charKey = GetCharKey(char)
    local favoriteKeySet = (ns.CharacterService and ns.CharacterService.BuildFavoriteKeySet)
        and ns.CharacterService:BuildFavoriteKeySet(self) or {}
    
    -- Don't update lastSeen when reordering (keep current timestamps)
    local currentPlayerKey = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    
    -- Get or initialize custom order
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {},
            untracked = {},
        }
    end
    
    if not self.db.profile.characterOrder[listKey] then
        self.db.profile.characterOrder[listKey] = {}
    end
    
    local customOrder = self.db.profile.characterOrder[listKey]
    
    -- If no custom order exists, seed from GetAllCharacters order for this category (online char first).
    if #customOrder == 0 then
        local allChars = self:GetAllCharacters()
        local keysInCategory = {}
        for i = 1, #allChars do
            local c = allChars[i]
            local key = GetCharKey(c)
            if key then
                local isTracked = c.isTracked ~= false
                local isFav = false
                if ns.CharacterService then
                    isFav = (ns.CharacterService.IsFavoriteFromKeySet and ns.CharacterService:IsFavoriteFromKeySet(favoriteKeySet, key))
                        or ns.CharacterService:IsFavoriteCharacter(self, key)
                end
                -- Section membership outranks favorite status, matching the roster split above.
                local gid = (ns.CharacterService and ns.CharacterService.GetCharacterCustomSectionId)
                    and ns.CharacterService:GetCharacterCustomSectionId(self, key)
                    or (self.db.profile.characterGroupAssignments or {})[key]
                if gid == "" then gid = nil end
                local inCategory = false
                if listKey == "favorites" then
                    inCategory = isTracked and isFav and gid == nil
                elseif listKey == "regular" then
                    inCategory = isTracked and not isFav and gid == nil
                elseif listKey == "untracked" then
                    inCategory = not isTracked
                elseif ns.CharacterService and ns.CharacterService.ParseCustomGroupIdFromListKey then
                    local grpId = ns.CharacterService:ParseCustomGroupIdFromListKey(listKey)
                    if grpId then
                        inCategory = isTracked and gid == grpId
                    end
                end
                if inCategory then
                    keysInCategory[#keysInCategory + 1] = key
                end
            end
        end
        local seen = {}
        if currentPlayerKey then
            for i = 1, #keysInCategory do
                if OrderKeyIsSessionChar(keysInCategory[i]) then
                    customOrder[1] = keysInCategory[i]
                    seen[keysInCategory[i]] = true
                    break
                end
            end
        end
        for i = 1, #keysInCategory do
            local k = keysInCategory[i]
            if not seen[k] then
                customOrder[#customOrder + 1] = k
                seen[k] = true
            end
        end
    end
    
    -- Find current index in custom order
    local currentIndex = nil
    for i = 1, #customOrder do
        local key = customOrder[i]
        if key == charKey then
            currentIndex = i
            break
        end
    end
    
    if not currentIndex then 
        -- Character not in custom order, add it
        tinsert(customOrder, charKey)
        currentIndex = #customOrder
    end
    
    -- Calculate new index
    local newIndex = currentIndex + direction
    
    if newIndex < 1 or newIndex > #customOrder then
        return
    end
    
    -- Swap in custom order
    customOrder[currentIndex], customOrder[newIndex] = customOrder[newIndex], customOrder[currentIndex]

    -- Logged-in character stays at top of this section after any reorder (matches DrawCharacterList).
    if currentPlayerKey then
        for i = 1, #customOrder do
            if OrderKeyIsSessionChar(customOrder[i]) then
                if i > 1 then
                    local c = tremove(customOrder, i)
                    tinsert(customOrder, 1, c)
                end
                break
            end
        end
    end
    
    -- Save and refresh
    self.db.profile.characterOrder[listKey] = customOrder
    
    local tk = ResolveSessionCharactersTableKey() or currentPlayerKey
    if self.db.global.characters and tk and self.db.global.characters[tk] then
        self.db.global.characters[tk].lastSeen = time()
    end
    
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
end

--- Compact rename dialog for one custom section. The new-section dialog carries a full roster
--- picker, which is far more window than a rename needs.
---@param groupId string
---@param currentName string|nil
function WarbandNexus:OpenRenameCustomSectionDialog(groupId, currentName)
    if not groupId or groupId == "" then return end
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local FontMgr = ns.FontManager
    if not CreateExternalWindow or not ns.UI or not ns.UI.Factory or not ns.UI.Factory.CreateEditBox then
        return
    end
    local L = ns.L
    local dialogW = 420
    local PAD = DialogPad()
    local innerW = dialogW - PAD * 2
    local dialog, contentFrame = CreateExternalWindow({
        name = "WnRenameCustomSectionDialog",
        title = (L and L["CUSTOM_HEADER_RENAME_DIALOG_TITLE"]) or "Rename section",
        icon = "socialqueuing-icon-group",
        iconIsAtlas = true,
        width = dialogW,
        height = 190,
    })
    if not dialog or not contentFrame then return end

    local nameLabel = FontMgr:CreateFontString(contentFrame, "tabSubtitle", "OVERLAY")
    nameLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)
    nameLabel:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD)
    nameLabel:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(nameLabel, "Bright")
    nameLabel:SetText((L and L["CUSTOM_HEADER_NEW_DIALOG_LABEL"]) or "Section name")

    local editBg = ns.UI.Factory:CreateContainer(contentFrame, innerW, 44, false)
    editBg:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -8)
    editBg:SetPoint("TOPRIGHT", nameLabel, "BOTTOMRIGHT", 0, -8)
    if ns.UI_ApplyInputChrome then
        ns.UI_ApplyInputChrome(editBg)
    end
    local eb = ns.UI.Factory:CreateEditBox(editBg)
    eb:SetPoint("TOPLEFT", editBg, "TOPLEFT", 8, -8)
    eb:SetPoint("BOTTOMRIGHT", editBg, "BOTTOMRIGHT", -8, 8)
    if eb.SetMaxLetters then eb:SetMaxLetters(32) end
    if currentName and not (issecretvalue and issecretvalue(currentName)) then
        eb:SetText(tostring(currentName))
    end
    eb:SetAutoFocus(true)
    if eb.HighlightText then eb:HighlightText() end

    local function Submit()
        local t = eb:GetText()
        if issecretvalue and issecretvalue(t) then return end
        t = (type(t) == "string" and t:match("^%s*(.-)%s*$")) or ""
        if t == "" then return end
        if ns.CharacterService and ns.CharacterService.RenameCustomCharacterSection then
            ns.CharacterService:RenameCustomCharacterSection(WarbandNexus, groupId, t)
        end
        if dialog.Close then dialog:Close() else dialog:Hide() end
        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
    end
    eb:SetScript("OnEnterPressed", Submit)
    eb:SetScript("OnEscapePressed", function()
        if dialog.Close then dialog:Close() else dialog:Hide() end
    end)

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, innerW, 40)
    btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD, PAD)
    btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PAD, PAD)
    local saveBtn = CreateCharacterDeleteDialogButton(btnContainer,
        (L and L["SAVE"]) or _G.SAVE or "Save", 160, false)
    if saveBtn then
        saveBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        saveBtn:SetScript("OnClick", Submit)
    end
    local cancelBtn = CreateCharacterDeleteDialogButton(btnContainer,
        (L and L["CANCEL"]) or _G.CANCEL or "Cancel", 160, false)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
end

function WarbandNexus:OpenCustomCharacterHeaderDialog()
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not CreateExternalWindow or not ns.UI or not ns.UI.Factory or not ns.UI.Factory.CreateEditBox or not ns.UI_CreateCustomHeaderRosterPicker then
        return
    end
    local L = ns.L
    local profile = self.db and self.db.profile
    local characters = (self.GetAllCharacters and self:GetAllCharacters()) or {}
    local dialogW = 820
    local PAD = DialogPad()
    local innerW = dialogW - PAD * 2
    local dialog, contentFrame = CreateExternalWindow({
        name = "WnNewCustomHeaderDialog",
        title = (L and L["CUSTOM_HEADER_NEW_DIALOG_TITLE"]) or "New custom section",
        icon = "socialqueuing-icon-group",
        iconIsAtlas = true,
        width = dialogW,
        height = 620,
    })
    if not dialog or not contentFrame or not profile then return end

    local hint = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    hint:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)
    hint:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    ns.UI_SetTextColorRole(hint, "Normal")
    hint:SetText((L and L["CUSTOM_HEADER_NEW_DIALOG_HINT"]) or "Name (max 32). Search and tick optional. Enter in name saves.")

    local nameLabel = FontMgr:CreateFontString(contentFrame, "tabSubtitle", "OVERLAY")
    nameLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    nameLabel:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -12)
    nameLabel:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(nameLabel, "Bright")
    nameLabel:SetText((L and L["CUSTOM_HEADER_NEW_DIALOG_LABEL"]) or "Section name")

    local editBg = ns.UI.Factory:CreateContainer(contentFrame, innerW, 44, false)
    editBg:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -8)
    editBg:SetPoint("TOPRIGHT", nameLabel, "BOTTOMRIGHT", 0, -8)
    if ns.UI_ApplyInputChrome then
        ns.UI_ApplyInputChrome(editBg)
    end
    local eb = ns.UI.Factory:CreateEditBox(editBg)
    if eb.SetPoint then
        eb:SetPoint("TOPLEFT", editBg, "TOPLEFT", 10, -8)
        eb:SetPoint("BOTTOMRIGHT", editBg, "BOTTOMRIGHT", -10, 6)
    end
    eb:SetMaxLetters(32)
    eb:SetAutoFocus(true)

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, innerW, 40)
    btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD, PAD)
    btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PAD, PAD)
    local okLbl = (L and L["CUSTOM_HEADER_NEW_DIALOG_CREATE"]) or "Create section"
    local cancelLbl = CANCEL or "Cancel"

    local HF = ns.UI and ns.UI.Factory
    local host = HF and HF:CreateContainer(contentFrame, math.max(1, innerW), 420, false)
    if not host then
        host = CreateFrame("Frame", nil, contentFrame)
    end
    host:SetPoint("LEFT", contentFrame, "LEFT", PAD, 0)
    host:SetPoint("RIGHT", contentFrame, "RIGHT", -PAD, 0)
    host:SetPoint("TOP", editBg, "BOTTOM", 0, -10)
    host:SetPoint("BOTTOM", btnContainer, "TOP", 0, 12)

    local picker = ns.UI_CreateCustomHeaderRosterPicker(host, innerW, WarbandNexus, profile, characters, nil)
    if picker and picker.frame then
        picker.frame:SetAllPoints(host)
    end

    local function trySubmit()
        local t = eb:GetText()
        if issecretvalue and issecretvalue(t) then return end
        if type(t) == "string" then
            t = t:match("^%s*(.-)%s*$") or ""
        else
            t = ""
        end
        if t == "" then
            return
        end
        local addedId
        if ns.CharacterService and ns.CharacterService.AddCustomCharacterSection then
            addedId = ns.CharacterService:AddCustomCharacterSection(WarbandNexus, t)
        end
        if not addedId then
            return
        end
        if picker and picker.GetSelectedKeys and ns.CharacterService and ns.CharacterService.SetCharacterCustomSection then
            local keys = picker.GetSelectedKeys()
            for i = 1, #keys do
                local raw = keys[i]
                if raw then
                    local k = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(raw)) or raw
                    ns.CharacterService:SetCharacterCustomSection(WarbandNexus, k, addedId, true)
                end
            end
        end
        if dialog.Close then dialog:Close() else dialog:Hide() end
        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
    end

    eb:SetScript("OnEnterPressed", function()
        trySubmit()
    end)

    local okBtn = CreateThemedButton and CreateThemedButton(btnContainer, okLbl, 168, 34)
    if okBtn then
        okBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        okBtn:SetScript("OnClick", trySubmit)
    end
    local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, cancelLbl, 150, 34)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
    dialog:Show()
    if picker and picker.Rebuild and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if picker.Rebuild then picker.Rebuild() end
        end)
    end
end

--- Modal roster editor for an existing custom header ([+] same UX as new section dialog).
function WarbandNexus:OpenCustomHeaderRosterWindow(groupId)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not groupId or not CreateExternalWindow or not ns.UI_CreateCustomHeaderRosterPicker then return end
    local profile = self.db and self.db.profile
    local characters = (self.GetAllCharacters and self:GetAllCharacters()) or {}
    if not profile then return end
    local L = ns.L
    local gtitle = tostring(groupId)
    local groups = profile.characterCustomGroups or {}
    for gi = 1, #groups do
        if groups[gi].id == groupId then
            gtitle = groups[gi].name or gtitle
            break
        end
    end
    local dialogW = 820
    local PAD = DialogPad()
    local innerW = dialogW - PAD * 2
    local safeName = "WnHdrRoster_" .. tostring(groupId):gsub("[^%a%d_]", "_")
    local dialog, contentFrame = CreateExternalWindow({
        name = safeName,
        title = gtitle,
        icon = "socialqueuing-icon-group",
        iconIsAtlas = true,
        width = dialogW,
        height = 620,
    })
    if not dialog or not contentFrame then return end

    local hint = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    hint:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD)
    hint:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    ns.UI_SetTextColorRole(hint, "Normal")
    hint:SetText((L and L["CUSTOM_HEADER_ROSTER_WINDOW_HINT"]) or "First list: boxes start checked (still in this section). Uncheck to queue a removal. Second list: tick to queue adds. Nothing is saved until you click Add selected.")

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, innerW, 40)
    btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD, PAD)
    btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PAD, PAD)
    local addLbl = (L and L["CUSTOM_HEADER_ADD_SELECTED"]) or "Add selected"
    local closeLbl = (L and L["CUSTOM_HEADER_ROSTER_CLOSE"]) or "Close"

    local HF = ns.UI and ns.UI.Factory
    local host = HF and HF:CreateContainer(contentFrame, math.max(1, innerW), 480, false)
    if not host then
        host = CreateFrame("Frame", nil, contentFrame)
    end
    host:SetPoint("LEFT", contentFrame, "LEFT", PAD, 0)
    host:SetPoint("RIGHT", contentFrame, "RIGHT", -PAD, 0)
    host:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    host:SetPoint("BOTTOM", btnContainer, "TOP", 0, 12)

    local picker = ns.UI_CreateCustomHeaderRosterPicker(host, innerW, WarbandNexus, profile, characters, groupId)
    if picker and picker.frame then
        picker.frame:SetAllPoints(host)
    end

    local addBtn = CreateThemedButton and CreateThemedButton(btnContainer, addLbl, 200, 34)
    if addBtn and picker and picker.ApplyPendingAdds then
        addBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        addBtn:SetScript("OnClick", function()
            picker.ApplyPendingAdds()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    local closeBtn = CreateThemedButton and CreateThemedButton(btnContainer, closeLbl, 160, 34)
    if closeBtn then
        closeBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        closeBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    dialog:Show()
    if picker and picker.Rebuild and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if picker.Rebuild then picker.Rebuild() end
        end)
    end
end

--- Generic destructive-action confirm (same shell as the custom-header delete dialog below).
---@param opts table { name:string, title:string, body:string|nil, confirmText:string|nil, onConfirm:function }
function ns.UI_ShowConfirmDialog(opts)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if type(opts) ~= "table" or type(opts.onConfirm) ~= "function" or not CreateExternalWindow then return end
    local dialog, contentFrame = CreateExternalWindow({
        name = opts.name or "WnConfirmDialog",
        title = opts.title or ((ns.L and ns.L["CONFIRM"]) or "Confirm"),
        icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        width = 420,
        height = 170,
    })
    if not dialog or not contentFrame then return end
    local PAD = DialogPad()
    local warn = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    warn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD * 2)
    warn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD * 2)
    warn:SetJustifyH("CENTER")
    warn:SetText(opts.body or ((ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!"))

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 360, 40)
    btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD, PAD)
    btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PAD, PAD)
    local okBtn = CreateThemedButton and CreateThemedButton(btnContainer, opts.confirmText or ((ns.L and ns.L["CONFIRM"]) or "Confirm"), 150, 36)
    if okBtn then
        okBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        okBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
            opts.onConfirm()
        end)
    end
    local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, (ns.L and ns.L["CANCEL"]) or "Cancel", 150, 36)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
    dialog:Show()
end

function WarbandNexus:ConfirmDeleteCustomCharacterHeader(groupId, groupName)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not groupId or not CreateExternalWindow then return end
    local dialog, contentFrame = CreateExternalWindow({
        name = "WnDeleteCustomHeaderDialog",
        title = (ns.L and ns.L["CUSTOM_HEADER_DELETE_DIALOG_TITLE"]) or "Delete custom header?",
        icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        width = 420,
        height = 190,
    })
    if not dialog or not contentFrame then return end
    local nm = groupName or groupId
    local PAD = DialogPad()
    local warn = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    warn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD, -PAD * 2)
    warn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -PAD, -PAD * 2)
    warn:SetJustifyH("CENTER")
    local fmt = (ns.L and ns.L["CUSTOM_HEADER_DELETE_DIALOG_BODY"]) or "Remove header |cffffcc00%s|r and ungroup its characters?"
    warn:SetText(string.format(fmt, nm))

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 360, 40)
    btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", PAD, PAD)
    btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PAD, PAD)
    local delBtn = CreateThemedButton and CreateThemedButton(btnContainer, (ns.L and ns.L["DELETE"]) or "Delete", 150, 36)
    if delBtn then
        delBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        delBtn:SetScript("OnClick", function()
            if ns.CharacterService and ns.CharacterService.RemoveCustomCharacterSection then
                ns.CharacterService:RemoveCustomCharacterSection(WarbandNexus, groupId)
            end
            if dialog.Close then dialog:Close() else dialog:Hide() end
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, (ns.L and ns.L["CANCEL"]) or "Cancel", 150, 36)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
    dialog:Show()
end
