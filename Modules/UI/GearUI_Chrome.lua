--[[
    Warband Nexus - Gear tab visual chrome (modern layout primitives).
    Loaded before GearUI_Paperdoll.lua; keeps draw chunk under local limit.
]]

local _, ns = ...

local COLORS = ns.UI_COLORS or {}
local FontManager = ns.FontManager
local GearFact = ns.UI and ns.UI.Factory
local format = string.format
local floor = math.floor

local Chrome = {}
ns.GearUI_Chrome = Chrome

local function GFR(roleKey)
    return FontManager and FontManager.GetFontRole and FontManager:GetFontRole(roleKey) or "default"
end

local function ResolveAccent(accent)
    return accent or COLORS.accent or { 0.55, 0.45, 0.78 }
end

--- Raised sub-card with accent top edge (paperdoll viewport, recommendations).
---@param frame Frame
---@param accent table|nil
function Chrome.ApplySubpanel(frame, accent)
    if not frame then return end
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    elseif ns.UI_ApplyVisuals then
        local ac = ResolveAccent(accent)
        local bg = COLORS.bgCard or COLORS.bg or { 0.10, 0.10, 0.12, 0.98 }
        ns.UI_ApplyVisuals(frame, bg, { ac[1], ac[2], ac[3], 0.55 })
    end
    if not frame._wnGearTopHighlight then
        frame._wnGearTopHighlight = frame:CreateTexture(nil, "BORDER")
    end
    local hi = frame._wnGearTopHighlight
    local ac = ResolveAccent(accent)
    hi:ClearAllPoints()
    hi:SetHeight(1)
    hi:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    hi:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    hi:SetColorTexture(ac[1], ac[2], ac[3], 0.42)
    hi:Show()
end

--- Inset viewport behind the 3D model / portrait.
---@param frame Frame
---@param accent table|nil
function Chrome.ApplyPaperdollViewport(frame, accent)
    if not frame or not frame.SetBackdrop then return end
    local ac = ResolveAccent(accent)
    local bg = COLORS.bgDeep or COLORS.bgCard or COLORS.bg or { 0.035, 0.035, 0.048, 0.98 }
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.94)
    frame:SetBackdropBorderColor(ac[1] * 0.35, ac[2] * 0.35, ac[3] * 0.35, 0.55)
end

--- Left accent bar + title (replaces centered section titles).
---@param parent Frame
---@param titleText string
---@param accent table|nil
---@param opts table|nil
---@return Frame host
function Chrome.CreateSectionHeader(parent, titleText, accent, opts)
    opts = opts or {}
    local L = ns.GEAR_LAYOUT or {}
    local h = opts.height or L.SECTION_HDR_H or 28
    local pad = opts.pad or L.SUBPANEL_PAD or 10
    local barPadL = opts.accentPadLeft or pad
    local barW = L.SECTION_ACCENT_W or 3
    local hideAccentBar = opts.hideAccentBar == true
    local ac = ResolveAccent(accent)

    local host = (GearFact and GearFact.CreateContainer)
        and GearFact:CreateContainer(parent, 100, h, false)
        or CreateFrame("Frame", nil, parent)
    host:SetHeight(h)

    local bar = host:CreateTexture(nil, "ARTWORK")
    local titleAnchor = host
    local titlePadL = pad
    if not hideAccentBar then
        bar:SetWidth(barW)
        bar:SetPoint("TOPLEFT", host, "TOPLEFT", barPadL, -4)
        bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", barPadL, 4)
        bar:SetColorTexture(ac[1], ac[2], ac[3], 0.92)
        titleAnchor = bar
        titlePadL = 8
    else
        bar:Hide()
    end

    local fs = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(host, GFR(opts.fontRole or "gearSectionTitle"), "OVERLAY")
    if fs then
        fs:SetPoint("LEFT", titleAnchor, hideAccentBar and "LEFT" or "RIGHT", titlePadL, 0)
        fs:SetPoint("RIGHT", host, "RIGHT", -pad, 0)
        fs:SetJustifyH("LEFT")
        local tc = opts.titleColor
        if tc then
            fs:SetTextColor(tc[1], tc[2], tc[3])
        else
            fs:SetTextColor(0.93, 0.93, 0.96)
        end
        fs:SetText(titleText or "")
    end
    if opts.underlineHeader then
        local rule = host:CreateTexture(nil, "BORDER")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", pad, 2)
        rule:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -pad, 2)
        rule:SetColorTexture(ac[1] * 0.45, ac[2] * 0.45, ac[3] * 0.45, 0.65)
        host._wnHeaderRule = rule
    end
    host._wnTitle = fs
    host._wnAccentBar = bar
    return host
end

--- Compact character ribbon: class strip, name/realm, optional ilvl pill.
---@param parent Frame
---@param charData table|nil
---@param accent table|nil
---@param opts table|nil
---@return Frame host
function Chrome.CreateCharacterRibbon(parent, charData, accent, opts)
    opts = opts or {}
    local L = ns.GEAR_LAYOUT or {}
    local h = opts.height or L.HERO_RIBBON_H or 44
    local pad = opts.pad or L.CARD_PAD or 12
    local ac = ResolveAccent(accent)
    local classFile = charData and charData.classFile
    local classHex = "ffffff"
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        classHex = format("%02x%02x%02x", floor(c.r * 255), floor(c.g * 255), floor(c.b * 255))
    end

    local host = (GearFact and GearFact.CreateContainer)
        and GearFact:CreateContainer(parent, 100, h, false)
        or CreateFrame("Frame", nil, parent)
    host:SetHeight(h)

    local stripW = L.HERO_CLASS_STRIP_W or 4
    local strip = host:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(stripW)
    strip:SetPoint("TOPLEFT", host, "TOPLEFT", pad, -6)
    strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", pad, 6)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        strip:SetColorTexture(c.r, c.g, c.b, 0.95)
    else
        strip:SetColorTexture(ac[1], ac[2], ac[3], 0.85)
    end

    local name = (charData and charData.name) or ""
    local realm = (charData and charData.realm) or ""
    if realm ~= "" and ns.Utilities and ns.Utilities.FormatRealmName then
        realm = ns.Utilities:FormatRealmName(realm) or realm
    end

    local nameFs = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(host, GFR("gearCharacterName"), "OVERLAY")
    if nameFs then
        nameFs:SetPoint("TOPLEFT", strip, "TOPRIGHT", 10, -2)
        nameFs:SetJustifyH("LEFT")
        if name ~= "" then
            nameFs:SetText("|cff" .. classHex .. name .. "|r")
        else
            nameFs:SetText("|cff888888" .. ((ns.L and ns.L["GEAR_SECTION_CHARACTER"]) or "Character") .. "|r")
        end
    end

    local realmFs = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(host, GFR("gearStatLabel"), "OVERLAY")
    if realmFs then
        realmFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
        realmFs:SetJustifyH("LEFT")
        realmFs:SetTextColor(0.62, 0.64, 0.70)
        realmFs:SetText(realm ~= "" and realm or "")
    end

    local avgIlvl = charData and tonumber(charData.itemLevel) or 0
    if avgIlvl > 0 then
        local pillW = L.HERO_ILVL_PILL_W or 88
        local pillH = L.HERO_ILVL_PILL_H or 22
        local pill = (GearFact and GearFact.CreateContainer)
            and GearFact:CreateContainer(host, pillW, pillH, false)
            or CreateFrame("Frame", nil, host, "BackdropTemplate")
        pill:SetSize(pillW, pillH)
        pill:SetPoint("RIGHT", host, "RIGHT", -pad, 0)
        if pill.SetBackdrop then
            pill:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = true,
                tileSize = 8,
                edgeSize = 1,
            })
            pill:SetBackdropColor(ac[1] * 0.18, ac[2] * 0.18, ac[3] * 0.18, 0.95)
            pill:SetBackdropBorderColor(ac[1] * 0.55, ac[2] * 0.55, ac[3] * 0.55, 0.75)
        end
        local ilvlFs = FontManager and FontManager.CreateFontString
            and FontManager:CreateFontString(pill, GFR("gearIlvlBadge"), "OVERLAY")
        if ilvlFs then
            ilvlFs:SetPoint("CENTER", pill, "CENTER", 0, 0)
            ilvlFs:SetJustifyH("CENTER")
            local ilvlStr = format("%.2f", avgIlvl)
            local ilvlLabel = (ns.L and ns.L["ILVL_SHORT_LABEL"]) or "iLvl"
            ilvlFs:SetText("|cffffffff" .. ilvlStr .. " |cffaaaaaa" .. ilvlLabel .. "|r")
        end
        host._wnIlvlPill = pill
    end

    local rule = host:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", pad, 0)
    rule:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -pad, 0)
    rule:SetColorTexture(ac[1] * 0.25, ac[2] * 0.25, ac[3] * 0.25, 0.65)
    host._wnRule = rule

    host._wnName = nameFs
    host._wnRealm = realmFs
    host._wnStrip = strip
    return host
end

--- Muted table header row for storage recommendations.
---@param parent Frame
---@param contentW number
---@param accent table|nil
---@param paintFn function|nil existing column painter
function Chrome.PaintStorageTableHeaderShell(parent, contentW, accent, paintFn)
    if not parent then return end
    local L = ns.GEAR_LAYOUT or {}
    local hdrH = ns.GearUI_STORAGE_REC_TABLE_HDR or L.STORAGE_TABLE_HDR_H or 22
    local ac = ResolveAccent(accent)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    bg:SetHeight(hdrH)
    bg:SetColorTexture(ac[1] * 0.12, ac[2] * 0.12, ac[3] * 0.12, 0.85)
    if type(paintFn) == "function" then
        paintFn(parent, contentW)
    end
end
