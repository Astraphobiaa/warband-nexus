--[[
    WarbandNexus - Vault Ready Button
    Draggable button showing Great Vault status across all characters.
    - Hover: compact list of ready/pending characters
    - Click: full table view (Name | iLvl | Raid | Dungeon | World | Status)
    - Row hover: tooltip showing iLvl reward per vault slot
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- Constants
-- ============================================================================
local BUTTON_SIZE   = 48
local BADGE_SIZE    = 18
local ROW_H         = 28
local HEADER_H      = 24
local FRAME_PAD     = 8
local MAX_ROWS      = 20
local ICON_TEXTURE  = "Interface\\AddOns\\WarbandNexus\\Media\\icon"
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_TreasureChest02"
local VOIDCORE_ID   = 3418

local COL_NAME      = 140
local COL_ILVL      = 50
local COL_RAID      = 62
local COL_DUNGEON   = 62
local COL_WORLD     = 62
local COL_BOUNTY    = 46   -- Trovehunter's Bounty (done/not)
local COL_VOIDCORE  = 58   -- Nebulous Voidcore (current/seasonMax)
local COL_STATUS    = 56
local TABLE_W = FRAME_PAD*2 + COL_NAME + COL_ILVL + COL_RAID + COL_DUNGEON + COL_WORLD + COL_BOUNTY + COL_VOIDCORE + COL_STATUS + 10

local TRACK_ICONS = {
    raids      = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    mythicPlus = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    world      = "Interface\\Icons\\INV_Misc_Map_01",
    bounty     = "Interface\\Icons\\INV_Misc_Bag_10_Green",
    voidcore   = "Interface\\Icons\\inv_cosmicvoid_orb",
}

local CHECK  = "|cff33dd33✔|r"
local CROSS  = "|cff666666✘|r"
local DASH   = "|cff666666—|r"

-- ============================================================================
-- DB helpers
-- ============================================================================
local function GetPveCache()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.pveCache or nil
end

local function GetCharacters()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.characters or nil
end

local function GetSavedPos()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return nil end
    return WarbandNexus.db.profile.vaultButtonPos
end

local function SavePos(x, y)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    WarbandNexus.db.profile.vaultButtonPos = { x = x, y = y }
end

-- ============================================================================
-- Data helpers
-- ============================================================================
local function GetClassHex(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return string.format("%02x%02x%02x",
            math.floor((c.r or 1)*255), math.floor((c.g or 1)*255), math.floor((c.b or 1)*255))
    end
    return "aaaaaa"
end

local function GetCurrentCharKey()
    return ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey() or nil
end

local function GetCharActivities(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    return pveCache.greatVault and pveCache.greatVault.activities
        and pveCache.greatVault.activities[charKey] or nil
end

local function HasAnyProgress(charKey)
    local acts = GetCharActivities(charKey)
    if not acts then return false end
    for _, cat in ipairs({ acts.raids, acts.mythicPlus, acts.world }) do
        if cat then
            for _, a in ipairs(cat) do
                local p = tonumber(a.progress) or 0
                local t = tonumber(a.threshold) or 0
                if t > 0 and p >= t then return true end
            end
        end
    end
    return false
end

local function GetSlotData(charKey, category)
    local acts = GetCharActivities(charKey)
    local cat  = acts and acts[category] or {}
    local slots = {}
    for i = 1, 3 do
        local a = cat[i]
        local prog   = a and (tonumber(a.progress) or 0) or 0
        local thresh = a and (tonumber(a.threshold) or 0) or 0
        slots[i] = {
            complete  = thresh > 0 and prog >= thresh,
            ilvl      = a and a.rewardItemLevel or 0,
            progress  = prog,
            threshold = thresh,
        }
    end
    return slots
end

--- Count how many vault slots are complete across all categories
local function CountReadySlots(charKey)
    local n = 0
    for _, cat in ipairs({ "raids", "mythicPlus", "world" }) do
        for _, s in ipairs(GetSlotData(charKey, cat)) do
            if s.complete then n = n + 1 end
        end
    end
    return n
end

--- Get Trovehunter's Bounty status for a character
--- Returns: true = done, false = not done, nil = unknown (never logged in)
local function GetBountyStatus(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local delveChar = pveCache.delves and pveCache.delves.characters
        and pveCache.delves.characters[charKey]
    if not delveChar then return nil end
    return delveChar.bountifulComplete
end

--- Get Nebulous Voidcore data for a character { current, seasonMax }
--- Uses WarbandNexus:GetCurrencyData which reads from CurrencyCacheService.
--- - quantity    = how many you currently hold (unspent)
--- - totalEarned = season progress (how many earned this season, shown as X/seasonMax)
--- - seasonMax   = season cap (increases by 2 each week)
local function GetVoidcoreData(charKey)
    if not WarbandNexus or not WarbandNexus.GetCurrencyData then return nil end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, VOIDCORE_ID, charKey)
    if not ok or not cd then return nil end
    local sm = tonumber(cd.seasonMax) or 0
    local te = tonumber(cd.totalEarned) or 0
    local qty = tonumber(cd.quantity) or 0
    -- If useTotalEarnedForMaxQty, season progress = totalEarned; otherwise use quantity
    local progress = cd.useTotalEarnedForMaxQty and te or qty
    return {
        quantity    = qty,        -- currently held (unspent)
        progress    = progress,   -- season earned (for X/seasonMax display)
        seasonMax   = sm,
        isCapped    = sm > 0 and progress >= sm,
    }
end

--- Open WarbandNexus main window on the PvE tab
local function OpenWNPveTab()
    if WarbandNexus and WarbandNexus.ShowMainWindow then
        WarbandNexus:ShowMainWindow()
        C_Timer.After(0.05, function()
            local mf = WarbandNexus.mainFrame
            if mf and mf.tabButtons and mf.tabButtons["pve"] then
                mf.tabButtons["pve"]:Click()
            end
        end)
    end
end

local function SlotSymbols(slots)
    local parts = {}
    for i = 1, 3 do
        table.insert(parts, slots[i].complete and CHECK or CROSS)
    end
    return table.concat(parts, " ")
end

local function BuildCharList()
    local pveCache   = GetPveCache()
    local characters = GetCharacters()
    if not pveCache or not characters then return {} end
    local rewards    = pveCache.greatVault and pveCache.greatVault.rewards
    local currentKey = GetCurrentCharKey()
    local result     = {}
    for charKey, charData in pairs(characters) do
        local rewardData = rewards and rewards[charKey]
        local isReady    = rewardData and rewardData.hasAvailableRewards or false
        local isPending  = not isReady and HasAnyProgress(charKey)
        if isReady or isPending then
            table.insert(result, {
                charKey   = charKey,
                name      = charData.name or charKey,
                realm     = charData.realm or "",
                classFile = charData.classFile or "WARRIOR",
                itemLevel = charData.itemLevel or 0,
                isReady   = isReady,
                isPending = isPending,
                isCurrent = (charKey == currentKey),
                bounty    = GetBountyStatus(charKey),
                voidcore  = GetVoidcoreData(charKey),
                slots     = CountReadySlots(charKey),
            })
        end
    end
    table.sort(result, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.isReady   ~= b.isReady   then return a.isReady   end
        return a.name < b.name
    end)
    return result
end

local function CountReady()
    local n = 0
    for _, e in ipairs(BuildCharList()) do
        if e.isReady then n = n + 1 end
    end
    return n
end

-- ============================================================================
-- UI state
-- ============================================================================
local S = { button=nil, badge=nil, badgeBg=nil, border=nil, tableFrame=nil, rows={} }

-- ============================================================================
-- Table frame
-- ============================================================================
local function HideTable()
    if S.tableFrame then S.tableFrame:Hide() end
end

local function BuildTableFrame()
    if S.tableFrame then return end

    local f = CreateFrame("Frame", "WarbandNexusVaultTable", UIParent, "BackdropTemplate")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, 0.97)
    f:SetBackdropBorderColor(0.5, 0.4, 0.8, 0.9)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, -6)
    title:SetTextColor(0.7, 0.5, 1.0, 1)
    title:SetText("WN Vault Tracker")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", HideTable)

    -- Header row
    local headerY = -(HEADER_H + 8)
    local hRow = CreateFrame("Frame", nil, f)
    hRow:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, headerY)
    hRow:SetSize(TABLE_W - FRAME_PAD*2, HEADER_H)
    local hBg = hRow:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(0.12, 0.10, 0.18, 1)

    -- Header cells
    local function HCell(text, x, w, isIcon, iconTex)
        if isIcon and iconTex then
            local icon = hRow:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("CENTER", hRow, "LEFT", x + w/2, 0)
            icon:SetTexture(iconTex)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            local fs = hRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
            fs:SetSize(w, HEADER_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            fs:SetTextColor(0.8, 0.8, 1.0)
            fs:SetText(text)
        end
    end

    local hx = 0
    HCell("Character",  hx, COL_NAME,    false)              ; hx = hx + COL_NAME
    HCell("iLvl",       hx, COL_ILVL,    false)              ; hx = hx + COL_ILVL
    HCell(nil,          hx, COL_RAID,    true,  TRACK_ICONS.raids)      ; hx = hx + COL_RAID
    HCell(nil,          hx, COL_DUNGEON, true,  TRACK_ICONS.mythicPlus) ; hx = hx + COL_DUNGEON
    HCell(nil,          hx, COL_WORLD,   true,  TRACK_ICONS.world)      ; hx = hx + COL_WORLD
    HCell(nil,          hx, COL_BOUNTY,  true,  TRACK_ICONS.bounty)     ; hx = hx + COL_BOUNTY
    HCell(nil,          hx, COL_VOIDCORE,true,  TRACK_ICONS.voidcore)   ; hx = hx + COL_VOIDCORE
    HCell("Status",     hx, COL_STATUS,  false)

    -- Separator
    local sep = f:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  FRAME_PAD,  headerY - HEADER_H)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -FRAME_PAD, headerY - HEADER_H)
    sep:SetColorTexture(0.4, 0.3, 0.6, 0.6)

    -- Scroll
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     FRAME_PAD, headerY - HEADER_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(TABLE_W - FRAME_PAD*2)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = scroll:GetVerticalScroll()
        scroll:SetVerticalScroll(math.max(0, cur - delta * ROW_H * 2))
    end)

    S.tableFrame   = f
    S.tableScroll  = scroll
    S.tableContent = content
end

local function RefreshTable()
    BuildTableFrame()
    local content = S.tableContent
    local list    = BuildCharList()

    for _, row in ipairs(S.rows) do row:Hide() end
    S.rows = {}

    if #list == 0 then
        S.tableFrame:SetSize(TABLE_W, 120)
        content:SetSize(TABLE_W - FRAME_PAD*2, 40)
        local msg = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("CENTER", content, "CENTER")
        msg:SetTextColor(0.5, 0.5, 0.5)
        msg:SetText("No vault activity this week.")
        S.tableFrame:Show()
        return
    end

    local catDefs = {
        { key="raids",      width=COL_RAID,    label="Raid"    },
        { key="mythicPlus", width=COL_DUNGEON, label="Dungeon" },
        { key="world",      width=COL_WORLD,   label="World"   },
    }

    for i, e in ipairs(list) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(TABLE_W - FRAME_PAD*2, ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:EnableMouse(true)

        -- Background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if e.isCurrent then
            bg:SetColorTexture(0.12, 0.10, 0.18, 1.0)
        elseif i % 2 == 0 then
            bg:SetColorTexture(0.08, 0.08, 0.11, 0.95)
        else
            bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
        end

        -- Hover highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.25, 0.5, 0.3)

        -- Left stripe
        local stripe = row:CreateTexture(nil, "BORDER")
        stripe:SetWidth(3)
        stripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
        stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        if e.isReady then
            stripe:SetColorTexture(0.2, 0.9, 0.3, 1)
        else
            stripe:SetColorTexture(1.0, 0.85, 0.0, 1)
        end

        -- Row separator
        if i > 1 then
            local rowSep = row:CreateTexture(nil, "BORDER")
            rowSep:SetHeight(1)
            rowSep:SetPoint("TOPLEFT",  row, "TOPLEFT",  3, 0)
            rowSep:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            rowSep:SetColorTexture(0.2, 0.18, 0.28, 0.5)
        end

        -- Name
        local x = 0
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", x+6, 0)
        nameFS:SetSize(COL_NAME-6, ROW_H)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetText("|cff" .. GetClassHex(e.classFile) .. e.name .. "|r")
        x = x + COL_NAME

        -- iLvl
        local ilvlFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ilvlFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        ilvlFS:SetSize(COL_ILVL, ROW_H)
        ilvlFS:SetJustifyH("CENTER")
        ilvlFS:SetJustifyV("MIDDLE")
        ilvlFS:SetText(e.itemLevel > 0
            and ("|cffd4af37" .. string.format("%.0f", e.itemLevel) .. "|r")
            or  "|cff666666—|r")
        x = x + COL_ILVL

        -- Vault columns
        local allSlots = {}
        for _, cat in ipairs(catDefs) do
            local slots = GetSlotData(e.charKey, cat.key)
            allSlots[cat.key] = slots
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            fs:SetSize(cat.width, ROW_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            fs:SetText(SlotSymbols(slots))
            x = x + cat.width
        end

        -- Trovehunter's Bounty
        local bountyFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bountyFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        bountyFS:SetSize(COL_BOUNTY, ROW_H)
        bountyFS:SetJustifyH("CENTER")
        bountyFS:SetJustifyV("MIDDLE")
        local b = e.bounty
        bountyFS:SetText(b == nil and DASH or (b and CHECK or CROSS))
        x = x + COL_BOUNTY

        -- Nebulous Voidcore (current / seasonMax)
        local voidcoreFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        voidcoreFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        voidcoreFS:SetSize(COL_VOIDCORE, ROW_H)
        voidcoreFS:SetJustifyH("CENTER")
        voidcoreFS:SetJustifyV("MIDDLE")
        local vc = e.voidcore
        if not vc then
            voidcoreFS:SetText(DASH)
        else
            local sm = vc.seasonMax or 0
            if sm > 0 then
                local capColor = vc.isCapped and "|cffdd3333" or "|cffd4af37"
                voidcoreFS:SetText(capColor .. vc.progress .. "|r|cffaaaaaa/|r|cffd4af37" .. sm .. "|r")
            else
                voidcoreFS:SetText("|cffd4af37" .. vc.quantity .. "|r")
            end
        end
        x = x + COL_VOIDCORE

        -- Status
        local statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        statusFS:SetSize(COL_STATUS, ROW_H)
        statusFS:SetJustifyH("CENTER")
        statusFS:SetJustifyV("MIDDLE")
        statusFS:SetText(e.isReady and "|cff33dd33Ready|r" or "|cffffff00Pending|r")

        -- Row tooltip: iLvl per slot + bounty status
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local hex = GetClassHex(e.classFile)
            local ilvlLabel = e.itemLevel > 0
                and ("  |cffd4af37" .. string.format("%.0f", e.itemLevel) .. " iLvl|r") or ""
            GameTooltip:AddLine("|cff" .. hex .. e.name .. "|r" .. ilvlLabel)
            GameTooltip:AddLine(" ")
            for _, cat in ipairs(catDefs) do
                local slots = allSlots[cat.key]
                local parts = {}
                for si = 1, 3 do
                    local s = slots[si]
                    if s.complete then
                        parts[si] = s.ilvl > 0
                            and ("|cffd4af37" .. s.ilvl .. "|r")
                            or  "|cff33dd33✔|r"
                    else
                        parts[si] = "|cff666666✘|r"
                    end
                end
                GameTooltip:AddDoubleLine(
                    "|cffaaaaaa" .. cat.label .. "|r",
                    table.concat(parts, "  "),
                    0.7, 0.7, 0.7, 1, 1, 1)
            end
            -- Bounty line
            local bountyLabel = b == nil and "|cff666666Unknown|r"
                or (b and "|cff33dd33Collected|r" or "|cffdd3333Not collected|r")
            GameTooltip:AddDoubleLine("|cffaaaaaTrovehunter's Bounty|r", bountyLabel, 0.7,0.7,0.7, 1,1,1)
            -- Voidcore line
            local vc2 = e.voidcore
            if vc2 then
                local sm = vc2.seasonMax or 0
                local vcLabel
                if sm > 0 then
                    vcLabel = (vc2.isCapped and "|cffdd3333" or "|cffd4af37")
                        .. vc2.progress .. "/" .. sm
                        .. (vc2.isCapped and " (Capped)|r" or "|r")
                        .. (vc2.quantity > 0 and ("|cffaaaaaa  (" .. vc2.quantity .. " held)|r") or "")
                else
                    vcLabel = "|cffd4af37" .. vc2.quantity .. " held|r"
                end
                GameTooltip:AddDoubleLine("|cffaaaaaNebulous Voidcore|r", vcLabel, 0.7,0.7,0.7, 1,1,1)
            end
            GameTooltip:AddLine(" ")
            if e.isReady then
                GameTooltip:AddLine("|cff33dd33Vault ready to claim!|r")
            else
                GameTooltip:AddLine("|cffffff00Available at weekly reset.|r")
            end
            GameTooltip:AddLine("|cff555555[Click] Open PvE tab|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click row to open WN PvE tab
        row:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" then
                HideTable()
                OpenWNPveTab()
            end
        end)

        table.insert(S.rows, row)
    end

    local visRows  = math.min(#list, MAX_ROWS)
    local contentH = #list * ROW_H
    local viewH    = visRows * ROW_H
    local totalH   = HEADER_H + 10 + viewH + FRAME_PAD + 32

    content:SetSize(TABLE_W - FRAME_PAD*2, contentH)
    S.tableFrame:SetSize(TABLE_W, totalH)
    S.tableScroll:SetVerticalScroll(0)
    S.tableFrame:Show()
end

local function ToggleTable()
    if S.tableFrame and S.tableFrame:IsShown() then
        HideTable()
    else
        RefreshTable()
        if S.tableFrame and S.button and not S.tableFrame:GetPoint() then
            S.tableFrame:ClearAllPoints()
            local bY = S.button:GetTop() or 0
            if bY > GetScreenHeight() / 2 then
                S.tableFrame:SetPoint("BOTTOMLEFT", S.button, "TOPLEFT", 0, 4)
            else
                S.tableFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -4)
            end
        end
    end
end

-- ============================================================================
-- Badge
-- ============================================================================
local function UpdateBadge()
    if not S.badge then return end
    local count = CountReady()
    if count > 0 then
        S.badge:SetText(count)
        S.badgeBg:Show()
        S.badge:Show()
        if S.border then S.border:SetBackdropBorderColor(0.2, 1.0, 0.3, 1.0) end
    else
        S.badge:Hide()
        S.badgeBg:Hide()
        if S.border then S.border:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8) end
    end
    if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
end

-- ============================================================================
-- Hover tooltip (simple list)
-- ============================================================================
local function ShowHoverTooltip(anchor)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("WN Vault Tracker", 0.7, 0.5, 1.0)
    local list = BuildCharList()
    local readyN, pendingN = 0, 0
    for _, e in ipairs(list) do
        if e.isReady then readyN = readyN + 1 else pendingN = pendingN + 1 end
    end
    if #list == 0 then
        GameTooltip:AddLine("No vault activity this week.", 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine(" ")
        for _, e in ipairs(list) do
            local hex    = GetClassHex(e.classFile)
            local realm  = e.realm ~= "" and ("|cff777777-"..e.realm.."|r") or ""
            local status = e.isReady
                and "|cff33dd33[ready]|r"
                or  "|cffffff00[next reset]|r"
            local slotStr = e.slots > 0
                and (" |cffaaaaaa("..e.slots.." slot"..(e.slots==1 and "" or "s")..")|r")
                or ""
            GameTooltip:AddDoubleLine(
                "|cff"..hex..e.name.."|r "..realm,
                status..slotStr,
                1,1,1, 1,1,1)
        end
        GameTooltip:AddLine(" ")
        if readyN   > 0 then GameTooltip:AddLine(readyN   .." ready to claim",            0.2, 1.0, 0.3) end
        if pendingN > 0 then GameTooltip:AddLine(pendingN .." in progress (next reset)",  1.0, 1.0, 0.2) end
    end
    GameTooltip:AddLine("|cff555555[Click] Full view  [Drag] Move|r")
    GameTooltip:Show()
end

-- ============================================================================
-- Main button
-- ============================================================================
local function BuildButton()
    if S.button then return end

    local btn = CreateFrame("Button", "WarbandNexusVaultButton", UIParent, "BackdropTemplate")
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetClampedToScreen(true)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(50)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = {left=2,right=2,top=2,bottom=2},
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 0.92)

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints(btn)
    border:SetFrameLevel(btn:GetFrameLevel() + 2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8)
    border:EnableMouse(false)
    S.border = border

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     6, -6)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 6)
    icon:SetTexture(ICON_TEXTURE)
    -- Fallback if custom icon didn't load
    if not icon:GetTexture() then
        icon:SetTexture(ICON_FALLBACK)
    end

    local badgeBg = btn:CreateTexture(nil, "OVERLAY")
    badgeBg:SetSize(BADGE_SIZE, BADGE_SIZE)
    badgeBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
    badgeBg:SetColorTexture(0.15, 0.75, 0.25, 1.0)
    badgeBg:Hide()
    S.badgeBg = badgeBg

    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("CENTER", badgeBg, "CENTER", 0, 0)
    badge:SetJustifyH("CENTER")
    badge:SetJustifyV("MIDDLE")
    badge:SetTextColor(1, 1, 1, 1)
    badge:Hide()
    S.badge = badge

    btn:SetScript("OnEnter", function(self) ShowHoverTooltip(self) end)
    btn:SetScript("OnLeave", function()     GameTooltip:Hide()      end)

    local dragged = false
    btn:SetScript("OnDragStart", function(self)
        dragged = true
        HideTable()
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        SavePos(x, y)
        C_Timer.After(0.05, function() dragged = false end)
    end)
    btn:SetScript("OnClick", function(self)
        if dragged then return end
        GameTooltip:Hide()
        ToggleTable()
    end)

    local pos = GetSavedPos()
    btn:ClearAllPoints()
    if pos and pos.x and pos.y then
        btn:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", 600, 0)
    end

    S.button = btn
    UpdateBadge()
end

-- ============================================================================
-- Events
-- ============================================================================
local eFrame = CreateFrame("Frame")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:SetScript("OnEvent", function()
    C_Timer.After(2, function() BuildButton(); UpdateBadge() end)
end)

local function HookWNMessages()
    if not WarbandNexus or not WarbandNexus.RegisterMessage then return end
    local E = ns.Constants and ns.Constants.EVENTS
    if not E then return end
    if E.PVE_UPDATED then
        WarbandNexus:RegisterMessage(E.PVE_UPDATED, function() UpdateBadge() end)
    end
    if E.CHARACTER_UPDATED then
        WarbandNexus:RegisterMessage(E.CHARACTER_UPDATED, function() UpdateBadge() end)
    end
end

local hFrame = CreateFrame("Frame")
hFrame:RegisterEvent("ADDON_LOADED")
hFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "WarbandNexus" then
        C_Timer.After(1, HookWNMessages)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
