--[[
    Warband Nexus - Roadmap UI
    Weekly progression command center embedded in the To-Do / Plans window.
    Target: Midnight 12.1.0 (## Interface: 120100).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local Constants = ns.Constants
local issecretvalue = issecretvalue

local RoadmapUI = {}
ns.RoadmapUI = RoadmapUI

local currentCategoryPill = "pve" -- "pve" | "pvp" | "professions"
local selectedCharKey = nil

local function GetL(key, fallback)
    return (ns.L and ns.L[key]) or fallback
end

local function FormatTimeLeft(seconds)
    if not seconds or seconds <= 0 then return "0h" end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    else
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

local function ToggleCharacterDropdown(anchorBtn, parentRoot, onSelect)
    local dd = parentRoot._charDropdown
    if dd and dd:IsShown() then
        dd:Hide()
        return
    end

    if not dd then
        dd = CreateFrame("Frame", nil, parentRoot, "BackdropTemplate")
        dd:SetFrameStrata("DIALOG")
        dd:SetClampedToScreen(true)
        dd:EnableMouse(true)
        local bg = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        }
        dd:SetBackdrop(bg)
        dd:SetBackdropColor(0.08, 0.08, 0.12, 0.96)
        dd:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
        parentRoot._charDropdown = dd
    end

    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
    dd:SetWidth(math.max(180, anchorBtn:GetWidth()))

    if dd._items then
        for i = 1, #dd._items do
            dd._items[i]:Hide()
        end
    end
    dd._items = dd._items or {}

    local entries = {}
    -- 1. Current player
    entries[#entries + 1] = {
        key = nil,
        name = UnitName("player") or "Current Character",
        class = select(2, UnitClass("player")) or "WARRIOR",
        isCurrent = true,
    }

    -- 2. Alts from db.global.characters
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local chars = db and db.characters
    if chars then
        local curKey = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        for k, c in pairs(chars) do
            if k ~= curKey and c and c.isTracked ~= false and c.name then
                entries[#entries + 1] = {
                    key = k,
                    name = c.name,
                    realm = c.realm,
                    class = c.class or "WARRIOR",
                    level = c.level,
                }
            end
        end
    end

    local rowH = 22
    local scrollChild = nil
    if ns.UI_ApplyDropdownScrollLayout then
        scrollChild = select(2, ns.UI_ApplyDropdownScrollLayout(dd, #entries, rowH, { maxVisibleRows = 9 }))
    else
        local totalH = #entries * rowH + 8
        dd:SetHeight(math.min(220, totalH))
    end
    local parentHost = scrollChild or dd

    for idx = 1, #entries do
        local item = entries[idx]
        local btn = dd._items[idx]
        if not btn then
            btn = CreateFrame("Button", nil, parentHost)
            btn:SetHeight(rowH)
            local hi = btn:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints()
            hi:SetColorTexture(1, 1, 1, 0.08)
            local fs = FontManager:CreateFontString(btn, "body", "OVERLAY")
            fs:SetPoint("LEFT", 8, 0)
            fs:SetJustifyH("LEFT")
            btn._text = fs
            dd._items[idx] = btn
        elseif btn:GetParent() ~= parentHost then
            btn:SetParent(parentHost)
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", parentHost, "TOPLEFT", 4, -4 - ((idx - 1) * rowH))
        btn:SetPoint("TOPRIGHT", parentHost, "TOPRIGHT", -4, -4 - ((idx - 1) * rowH))
        btn:Show()

        local cc = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class]) or { r = 1, g = 1, b = 1 }
        local hex = string.format("|cff%02x%02x%02x", math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255))
        local star = item.isCurrent and "★ " or ""
        btn._text:SetText(star .. hex .. item.name .. "|r")

        btn:SetScript("OnClick", function()
            dd:Hide()
            if onSelect then onSelect(item.key) end
        end)
    end

    dd:Show()
end

--- Main drawing entry called from PlansUI
--- @param parent Frame scroll child
--- @param yOffset number
--- @param width number
--- @return number updated yOffset
function RoadmapUI:DrawRoadmapView(parent, yOffset, width)
    if not parent then return yOffset end
    local RS = ns.RoadmapService
    if not RS then return yOffset end

    local COLORS = ns.UI_COLORS
    local CreateCard = ns.UI_CreateCard
    local padH = (ns.UI_PlansContentPadH and ns.UI_PlansContentPadH()) or 14
    local contentW = math.max(300, (width or parent:GetWidth() or 500) - (padH * 2))

    -- Container frame reuse
    local root = parent._wnRoadmapRoot
    if not root then
        root = CreateFrame("Frame", nil, parent)
        parent._wnRoadmapRoot = root
    end
    root:Show()
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", padH, -yOffset)
    root:SetPoint("TOPRIGHT", -padH, -yOffset)

    if root._charDropdown then
        root._charDropdown:Hide()
    end

    -- Wipe existing children on redraw to maintain clean state
    if root._children then
        for i = 1, #root._children do
            local child = root._children[i]
            if child and child.Hide then child:Hide() end
        end
    end
    root._children = {}

    local curY = 0

    -- ========================================================================
    -- 1. TOP TOOLBAR: Category Switcher Pills + Alt Switcher + Reset Countdown
    -- ========================================================================
    local topBarH = 34
    local topBar = CreateCard(root, topBarH)
    topBar:SetPoint("TOPLEFT", 0, -curY)
    topBar:SetPoint("TOPRIGHT", 0, -curY)
    topBar:Show()
    root._children[#root._children + 1] = topBar

    local data = RS:GetCharacterPvERoadmap(selectedCharKey)

    -- Mode Switcher Pills: [ PvE ] [ PvP ] [ Professions ]
    local pills = {
        { id = "pve", label = GetL("ROADMAP_TAB_PVE", "PvE") },
        { id = "pvp", label = GetL("ROADMAP_TAB_PVP", "PvP") },
        { id = "professions", label = GetL("ROADMAP_TAB_PROFESSIONS", "Professions") },
    }

    local pillX = 8
    for pi = 1, #pills do
        local p = pills[pi]
        local isSel = (currentCategoryPill == p.id)
        local pillBtn = CreateFrame("Button", nil, topBar)
        pillBtn:SetSize(68, 22)
        pillBtn:SetPoint("LEFT", pillX, 0)
        pillX = pillX + 72

        local pillText = FontManager:CreateFontString(pillBtn, "small", "OVERLAY")
        pillText:SetPoint("CENTER", 0, 0)
        pillText:SetText(p.label)

        if isSel then
            local ac = COLORS.accent or { 0.4, 0.2, 0.6 }
            local pillBg = pillBtn:CreateTexture(nil, "BACKGROUND")
            pillBg:SetAllPoints()
            pillBg:SetColorTexture(ac[1], ac[2], ac[3], 0.7)
            ns.UI_SetTextColorRole(pillText, "Bright")
        else
            ns.UI_SetTextColorRole(pillText, "Normal")
        end

        pillBtn:SetScript("OnClick", function()
            currentCategoryPill = p.id
            if WarbandNexus and WarbandNexus.SendMessage and Constants and Constants.EVENTS then
                WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end
        end)
        root._children[#root._children + 1] = pillBtn
    end

    -- Character Selector Dropdown Button
    local charBtn = CreateFrame("Button", nil, topBar)
    charBtn:SetSize(160, 22)
    charBtn:SetPoint("LEFT", pillX + 8, 0)

    local charBtnBg = charBtn:CreateTexture(nil, "BACKGROUND")
    charBtnBg:SetAllPoints()
    charBtnBg:SetColorTexture(0.14, 0.14, 0.18, 0.8)

    local charFs = FontManager:CreateFontString(charBtn, "small", "OVERLAY")
    charFs:SetPoint("CENTER", 0, 0)
    local curCc = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.characterClass]) or { r = 1, g = 1, b = 1 }
    local curHex = string.format("|cff%02x%02x%02x", math.floor(curCc.r * 255), math.floor(curCc.g * 255), math.floor(curCc.b * 255))
    local prefix = data.isCurrentChar and "★ " or ""
    charFs:SetText(prefix .. curHex .. data.characterName .. "|r ▼")

    charBtn:SetScript("OnClick", function()
        ToggleCharacterDropdown(charBtn, root, function(k)
            selectedCharKey = k
            if WarbandNexus and WarbandNexus.SendMessage and Constants and Constants.EVENTS then
                WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end
        end)
    end)
    root._children[#root._children + 1] = charBtn

    -- Reset Timer on Right
    local resetFs = FontManager:CreateFontString(topBar, "body", "OVERLAY")
    resetFs:SetPoint("RIGHT", -12, 0)
    local timeLeftStr = FormatTimeLeft(data.resetSeconds)
    resetFs:SetText(string.format("%s: |cff00ff88%s|r", GetL("WEEKLY_RESET_LABEL", "Reset"), timeLeftStr))

    curY = curY + topBarH + 10

    -- ========================================================================
    -- 2. NON-PVE EMPTY STATES
    -- ========================================================================
    if currentCategoryPill ~= "pve" then
        local emptyCardH = 140
        local emptyCard = CreateCard(root, emptyCardH)
        emptyCard:SetPoint("TOPLEFT", 0, -curY)
        emptyCard:SetPoint("TOPRIGHT", 0, -curY)
        emptyCard:Show()
        root._children[#root._children + 1] = emptyCard

        local emptyTitle = FontManager:CreateFontString(emptyCard, "title", "OVERLAY")
        emptyTitle:SetPoint("CENTER", 0, 14)
        ns.UI_SetTextColorRole(emptyTitle, "Bright")
        emptyTitle:SetText(currentCategoryPill == "pvp" and GetL("ROADMAP_PVP_TITLE", "PvP Weekly Roadmap") or GetL("ROADMAP_PROF_TITLE", "Professions Roadmap"))

        local emptyDesc = FontManager:CreateFontString(emptyCard, "body", "OVERLAY")
        emptyDesc:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -6)
        ns.UI_SetTextColorRole(emptyDesc, "Normal")
        emptyDesc:SetText(GetL("ROADMAP_COMING_SOON", "Module coming in next phase. Check PvE for active reset milestones."))

        curY = curY + emptyCardH + 10
        root:SetHeight(curY)
        return yOffset + curY
    end

    -- ========================================================================
    -- 3. UNCLAIMED VAULT ALERT BANNER (If applicable)
    -- ========================================================================
    if data.vault.hasAvailableRewards then
        local alertH = 32
        local alert = CreateCard(root, alertH)
        alert:SetPoint("TOPLEFT", 0, -curY)
        alert:SetPoint("TOPRIGHT", 0, -curY)
        alert:Show()
        root._children[#root._children + 1] = alert

        local alertText = FontManager:CreateFontString(alert, "body", "OVERLAY")
        alertText:SetPoint("LEFT", 12, 0)
        alertText:SetText("|cffffd100★|r " .. GetL("ROADMAP_VAULT_REWARD_WAITING", "Great Vault rewards are ready to claim for this character!"))
        ns.UI_SetTextColorRole(alertText, "Bright")

        curY = curY + alertH + 10
    end

    -- ========================================================================
    -- 4. CARD: GREAT VAULT MATRIX (9 Milestone slots)
    -- ========================================================================
    local vaultCardH = 118
    local vaultCard = CreateCard(root, vaultCardH)
    vaultCard:SetPoint("TOPLEFT", 0, -curY)
    vaultCard:SetPoint("TOPRIGHT", 0, -curY)
    vaultCard:Show()
    root._children[#root._children + 1] = vaultCard

    local vHeader = FontManager:CreateFontString(vaultCard, "subheading", "OVERLAY")
    vHeader:SetPoint("TOPLEFT", 12, -10)
    vHeader:SetText(GetL("PVE_HEADER_GREAT_VAULT", "Great Vault Milestones"))
    ns.UI_SetTextColorRole(vHeader, "Bright")

    local vTracks = {
        { id = "raid", label = GetL("PVE_FILTER_RAID", "Raids"), data = data.vault.raid, thresholds = { 2, 4, 6 } },
        { id = "dungeon", label = GetL("PVE_FILTER_MYTHIC_PLUS", "Dungeons"), data = data.vault.dungeon, thresholds = { 1, 4, 8 } },
        { id = "world", label = GetL("PVE_FILTER_DELVES", "World / Delves"), data = data.vault.world, thresholds = { 2, 4, 8 } },
    }

    local trackY = -34
    for ti = 1, #vTracks do
        local trk = vTracks[ti]
        local trkLabel = FontManager:CreateFontString(vaultCard, "body", "OVERLAY")
        trkLabel:SetPoint("TOPLEFT", 14, trackY)
        trkLabel:SetWidth(95)
        trkLabel:SetJustifyH("LEFT")
        ns.UI_SetTextColorRole(trkLabel, "Normal")
        trkLabel:SetText(trk.label)

        -- 3 slots
        local slotX = 115
        for si = 1, 3 do
            local slotInfo = trk.data.slots[si] or {}
            local thresh = trk.thresholds[si] or 1
            local prog = slotInfo.progress or 0
            local isDone = slotInfo.completed or (prog >= thresh)

            local slotBox = CreateFrame("Frame", nil, vaultCard)
            slotBox:SetSize(86, 20)
            slotBox:SetPoint("TOPLEFT", slotX, trackY - 1)
            slotX = slotX + 92

            local bgTex = slotBox:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            if isDone then
                bgTex:SetColorTexture(0.12, 0.35, 0.18, 0.8)
            else
                bgTex:SetColorTexture(0.15, 0.15, 0.18, 0.6)
            end

            local sText = FontManager:CreateFontString(slotBox, "small", "OVERLAY")
            sText:SetPoint("CENTER", 0, 0)
            if isDone then
                local ilvlStr = (slotInfo.itemLevel and slotInfo.itemLevel > 0) and (" " .. slotInfo.itemLevel) or ""
                sText:SetText("|cff00ff88✓|r" .. ilvlStr)
            else
                sText:SetText(string.format("%d/%d", math.min(prog, thresh), thresh))
                ns.UI_SetTextColorRole(sText, "Normal")
            end
        end

        trackY = trackY - 24
    end

    curY = curY + vaultCardH + 10

    -- ========================================================================
    -- 5. TWO-COLUMN SPLIT: Bountiful Delves (Left) + Core Priorities (Right)
    -- ========================================================================
    local colW = math.floor((contentW - 10) / 2)
    local splitCardH = 200

    -- LEFT CARD: Today's Bountiful Delves
    local delveCard = CreateCard(root, splitCardH)
    delveCard:SetSize(colW, splitCardH)
    delveCard:SetPoint("TOPLEFT", 0, -curY)
    delveCard:Show()
    root._children[#root._children + 1] = delveCard

    local dHeader = FontManager:CreateFontString(delveCard, "subheading", "OVERLAY")
    dHeader:SetPoint("TOPLEFT", 12, -10)
    dHeader:SetText(GetL("ROADMAP_DELVES_HEADER", "Today's Bountiful Delves"))
    ns.UI_SetTextColorRole(dHeader, "Bright")

    local keyBadge = FontManager:CreateFontString(delveCard, "body", "OVERLAY")
    keyBadge:SetPoint("TOPRIGHT", -12, -10)
    keyBadge:SetText(string.format("|cff00ccff%d|r %s", data.delves.cofferKeys, GetL("ROADMAP_KEYS_HELD", "Keys")))

    local bDelves = data.delves.activeBountiful or {}
    local dItemY = -34
    if #bDelves == 0 then
        local noDelvesFs = FontManager:CreateFontString(delveCard, "body", "OVERLAY")
        noDelvesFs:SetPoint("TOPLEFT", 12, -50)
        noDelvesFs:SetText(GetL("ROADMAP_NO_BOUNTIFUL", "Log into a Midnight zone to scan active delve POIs."))
        ns.UI_SetTextColorRole(noDelvesFs, "Normal")
    else
        for bi = 1, math.min(4, #bDelves) do
            local bd = bDelves[bi]
            local row = CreateFrame("Frame", nil, delveCard)
            row:SetSize(colW - 24, 22)
            row:SetPoint("TOPLEFT", 12, dItemY)
            dItemY = dItemY - 24

            local dNameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
            dNameFs:SetPoint("LEFT", 0, 0)
            dNameFs:SetWidth(colW - 80)
            dNameFs:SetJustifyH("LEFT")
            local tag = bd.isNemesis and " |cffff4444[Nemesis]|r" or ""
            dNameFs:SetText(bd.name .. tag)
            ns.UI_SetTextColorRole(dNameFs, "Normal")

            if bd.position and bd.mapID then
                local pinBtn = CreateFrame("Button", nil, row)
                pinBtn:SetSize(46, 18)
                pinBtn:SetPoint("RIGHT", 0, 0)
                local pinFs = FontManager:CreateFontString(pinBtn, "small", "OVERLAY")
                pinFs:SetPoint("CENTER", 0, 0)
                pinFs:SetText(GetL("ROADMAP_PIN_DELVE", "Pin"))
                ns.UI_SetTextColorRole(pinFs, "Bright")

                pinBtn:SetScript("OnClick", function()
                    RS:SetDelveWaypoint(bd.mapID, bd.position)
                end)
            end
        end
    end

    -- RIGHT CARD: Core Weekly Priorities Checklist
    local questCard = CreateCard(root, splitCardH)
    questCard:SetSize(colW, splitCardH)
    questCard:SetPoint("TOPRIGHT", 0, -curY)
    questCard:Show()
    root._children[#root._children + 1] = questCard

    local qHeader = FontManager:CreateFontString(questCard, "subheading", "OVERLAY")
    qHeader:SetPoint("TOPLEFT", 12, -10)
    qHeader:SetText(GetL("ROADMAP_WEEKLIES_HEADER", "Weekly Priorities"))
    ns.UI_SetTextColorRole(qHeader, "Bright")

    local qItemY = -34
    local weeklies = data.weeklies or {}
    for wi = 1, math.min(6, #weeklies) do
        local w = weeklies[wi]
        local qRow = CreateFrame("Frame", nil, questCard)
        qRow:SetSize(colW - 24, 22)
        qRow:SetPoint("TOPLEFT", 12, qItemY)
        qItemY = qItemY - 24

        local mark = w.completed and "|cff00ff88✓|r " or "|cffffcc00•|r "
        local qNameFs = FontManager:CreateFontString(qRow, "body", "OVERLAY")
        qNameFs:SetPoint("LEFT", 0, 0)
        qNameFs:SetWidth(colW - 30)
        qNameFs:SetJustifyH("LEFT")
        qNameFs:SetText(mark .. w.title)
        if w.completed then
            ns.UI_SetTextColorRole(qNameFs, "Normal")
        else
            ns.UI_SetTextColorRole(qNameFs, "Bright")
        end
    end

    curY = curY + splitCardH + 10

    -- ========================================================================
    -- 6. TWO-COLUMN SPLIT: Seasonal Power (Left) + Raid Lockouts (Right)
    -- ========================================================================
    local bottomCardH = 72

    -- LEFT CARD: Seasonal Power & Keystones
    local powerCard = CreateCard(root, bottomCardH)
    powerCard:SetSize(colW, bottomCardH)
    powerCard:SetPoint("TOPLEFT", 0, -curY)
    powerCard:Show()
    root._children[#root._children + 1] = powerCard

    local spHeader = FontManager:CreateFontString(powerCard, "subheading", "OVERLAY")
    spHeader:SetPoint("TOPLEFT", 12, -8)
    spHeader:SetText(GetL("ROADMAP_POWER_HEADER", "Seasonal Power"))
    ns.UI_SetTextColorRole(spHeader, "Bright")

    local sp = data.seasonalPower
    local cText = FontManager:CreateFontString(powerCard, "body", "OVERLAY")
    cText:SetPoint("TOPLEFT", 14, -28)
    cText:SetText(string.format("%s: |cff00ff88%d|r/%d", sp.manafluxName, sp.manafluxHeld, sp.manafluxMax > 0 and sp.manafluxMax or 8))
    ns.UI_SetTextColorRole(cText, "Normal")

    local ksText = FontManager:CreateFontString(powerCard, "body", "OVERLAY")
    ksText:SetPoint("TOPLEFT", 14, -48)
    if sp.keystoneLevel > 0 then
        ksText:SetText(string.format("%s: |cff00ccff+%d|r", GetL("PVE_COL_KEYSTONE", "Keystone"), sp.keystoneLevel))
    else
        ksText:SetText(string.format("%s: %s", GetL("PVE_COL_KEYSTONE", "Keystone"), GetL("NONE", "None")))
    end
    ns.UI_SetTextColorRole(ksText, "Normal")

    -- RIGHT CARD: Raid Lockouts
    local raidCard = CreateCard(root, bottomCardH)
    raidCard:SetSize(colW, bottomCardH)
    raidCard:SetPoint("TOPRIGHT", 0, -curY)
    raidCard:Show()
    root._children[#root._children + 1] = raidCard

    local rHeader = FontManager:CreateFontString(raidCard, "subheading", "OVERLAY")
    rHeader:SetPoint("TOPLEFT", 12, -8)
    rHeader:SetText(GetL("ROADMAP_RAID_LOCKOUTS_HEADER", "Raid Lockouts"))
    ns.UI_SetTextColorRole(rHeader, "Bright")

    local lockouts = data.raidLockouts or {}
    if #lockouts == 0 then
        local noLocksFs = FontManager:CreateFontString(raidCard, "body", "OVERLAY")
        noLocksFs:SetPoint("TOPLEFT", 14, -34)
        noLocksFs:SetText(GetL("ROADMAP_NO_LOCKOUTS", "No active raid lockouts this week."))
        ns.UI_SetTextColorRole(noLocksFs, "Normal")
    else
        local rY = -28
        for ri = 1, math.min(2, #lockouts) do
            local lk = lockouts[ri]
            local lkFs = FontManager:CreateFontString(raidCard, "body", "OVERLAY")
            lkFs:SetPoint("TOPLEFT", 14, rY)
            rY = rY - 20
            local progStr = (lk.numEncounters > 0) and string.format("|cff00ff88%d/%d|r", lk.encounterProgress, lk.numEncounters) or "|cff00ff88Locked|r"
            lkFs:SetText(string.format("%s (%s): %s", lk.name, lk.difficultyName, progStr))
            ns.UI_SetTextColorRole(lkFs, "Normal")
        end
    end

    curY = curY + bottomCardH + 10

    root:SetHeight(curY)
    return yOffset + curY
end
