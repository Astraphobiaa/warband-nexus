--[[
    Warband Nexus - Tooltip Service Module
    Lazy singleton tooltip; extends GameTooltip for item/world anchors only.
    WarbandNexus.Tooltip:Show(frame, data) / :Hide()

    WN_NONUI_UI: Lazy tooltip singleton and internal helper frames (`CreateFrame`) are intentionally outside SharedWidgets Factory.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS

-- Midnight 12.0: Secret Values API (nil on pre-12.0 clients, backward-compatible)
local issecretvalue = issecretvalue
-- Upvalue for GUID parsing in object tooltip hook
local strsplit = strsplit
local tonumber = tonumber

-- Singleton tooltip frame (lazy initialized)
local tooltipFrame = nil
local isVisible = false
local currentAnchor = nil
local currentAnchorPref = "ANCHOR_AUTO"
local isInitialized = false

-- Event names (single source: Constants.EVENTS)
local TOOLTIP_SHOW = E.TOOLTIP_SHOW
local TOOLTIP_HIDE = E.TOOLTIP_HIDE

local TooltipService = {}

local function RemapTooltipLineRGB(r, g, b)
    if ns.UI_RemapGameTooltipLineColor then
        return ns.UI_RemapGameTooltipLineColor(r, g, b)
    end
    return r or 1, g or 1, b or 1
end

local function TooltipBodyRGB()
    if ns.UI_GetTooltipBodyColor then
        return ns.UI_GetTooltipBodyColor()
    end
    return 0.85, 0.85, 0.85
end

local function TooltipBrightRGB()
    if ns.UI_GetTextRoleRGB then
        return ns.UI_GetTextRoleRGB("Bright")
    end
    return 1, 1, 1
end

function TooltipService:Initialize()
    if isInitialized then return end
    
    -- Lazy init: Create frame when first needed
    -- This is called explicitly from Core.lua
    self:Debug("TooltipService initialized")
    isInitialized = true
    
    -- Register safety events
    self:RegisterSafetyEvents()
end

local function GetTooltipFrame()
    if not tooltipFrame and ns.UI and ns.UI.TooltipFactory then
        tooltipFrame = ns.UI.TooltipFactory:CreateTooltipFrame()
    end
    return tooltipFrame
end

function TooltipService:ValidateData(data)
    if not data or type(data) ~= "table" then
        return false
    end
    
    -- Type is required
    if not data.type then
        return false
    end
    
    -- Validate based on type
    if data.type == "custom" then
        return data.lines ~= nil
    elseif data.type == "item" then
        return data.itemID ~= nil or data.itemLink ~= nil
    elseif data.type == "currency" then
        return data.currencyID ~= nil
    elseif data.type == "hybrid" then
        return (data.itemID or data.currencyID) and data.lines
    end
    
    return false
end

function TooltipService:Show(anchorFrame, data)
    local frame = GetTooltipFrame()
    if not frame or not anchorFrame or not data then 
        return 
    end
    
    -- Validate data
    if not self:ValidateData(data) then
        self:Debug("Invalid tooltip data")
        return
    end

    -- Hide while rebuilding so intermediate LayoutLines passes are never painted.
    frame:Hide()
    
    -- Clear previous content
    frame:Clear()
    -- Optional wide tooltips (e.g. PvE vault summary); clamp to sane bounds for small resolutions
    if data.maxWidth and tonumber(data.maxWidth) then
        local mw = tonumber(data.maxWidth)
        frame.fixedWidth = math.max(260, math.min(mw, 820))
    end

    if frame.BeginBatchLayout then
        frame:BeginBatchLayout()
    end

    -- Render based on type
    if data.type == "custom" then
        self:RenderCustomTooltip(frame, data)
    elseif data.type == "item" then
        self:RenderItemTooltip(frame, data)
    elseif data.type == "currency" then
        self:RenderCurrencyTooltip(frame, data)
    elseif data.type == "hybrid" then
        self:RenderHybridTooltip(frame, data)
    end
    
    -- Finalize layout once (batch mode skips per-line LayoutLines during render).
    if frame.EndBatchLayout then
        frame:EndBatchLayout()
    else
        frame:LayoutLines()
    end
    
    currentAnchor = anchorFrame
    currentAnchorPref = data.anchor or "ANCHOR_AUTO"
    
    -- Position then show (single visible frame at final anchor).
    self:PositionTooltip(frame, anchorFrame, currentAnchorPref)
    frame:Show()
    isVisible = true
    
    -- Fire event (if AceEvent available)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_SHOW, data)
    end
end

function TooltipService:Hide()
    local frame = GetTooltipFrame()
    if not frame or not isVisible then 
        return 
    end
    
    frame:Clear()
    frame:Hide()
    
    currentAnchor = nil
    currentAnchorPref = "ANCHOR_AUTO"
    isVisible = false
    
    -- Fire event
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_HIDE)
    end
end

-- ITEM LINK TOOLTIP CONTEXT (linkLevel + specializationID in payload)
-- Blizzard uses fields 9–10 of the item payload for primary-stat / set-bonus
-- display. Links from another character (e.g. bank alt) keep that character's
-- spec; rewrite so Gear tab tooltips match the viewed character.
-- See https://warcraft.wiki.gg/wiki/ItemLink (linkLevel, specializationID).

local function ApplyItemLinkTooltipContext(itemLink, itemID, linkLevel, specializationID)
    if not linkLevel or linkLevel < 1 or not specializationID or specializationID < 1 then
        return itemLink
    end
    if (not itemLink or itemLink == "") and itemID then
        if C_Item and C_Item.GetItemInfo then
            itemLink = select(2, C_Item.GetItemInfo(itemID))
        elseif GetItemInfo then
            itemLink = select(2, GetItemInfo(itemID))
        end
    end
    if not itemLink or itemLink == "" then return itemLink end
    if issecretvalue and issecretvalue(itemLink) then return itemLink end

    local hs, he = itemLink:find("|Hitem:", 1, true)
    if not hs or not he then return itemLink end
    local hName = itemLink:find("|h", he + 1, true)
    if not hName then return itemLink end

    local head = itemLink:sub(1, he)
    local payload = itemLink:sub(he + 1, hName - 1)
    local tail = itemLink:sub(hName)

    local parts = {}
    local pos = 1
    local plen = #payload
    while pos <= plen do
        local col = payload:find(":", pos, true)
        if not col then
            parts[#parts + 1] = payload:sub(pos)
            break
        end
        parts[#parts + 1] = payload:sub(pos, col - 1)
        pos = col + 1
    end
    while #parts < 10 do
        parts[#parts + 1] = ""
    end
    parts[9] = tostring(linkLevel)
    parts[10] = tostring(specializationID)
    return head .. table.concat(parts, ":") .. tail
end

---Strip |cn / |cHEX+ / |r so SetTextColor applies (embedded colors override FontString color).
local function StripTooltipTextForStatMatch(text)
    if not text or type(text) ~= "string" then return "" end
    if issecretvalue and issecretvalue(text) then return "" end
    local s = text:gsub("|cn[^|]*|", "")
    -- Variable-length |c + hex (6–10+ digits seen across clients); repeat until stable.
    local prev
    repeat
        prev = s
        s = s:gsub("|c[0-9A-Fa-f]+", "", 1)
    until s == prev
    return (s:gsub("|r", ""))
end

local function IsItemTooltipClassRestrictionLine(leftText, rightText)
    if leftText and issecretvalue and issecretvalue(leftText) then return false end
    if rightText and issecretvalue and issecretvalue(rightText) then return false end
    local combined = tostring(leftText or "")
    if rightText and tostring(rightText) ~= "" then
        combined = combined .. " " .. tostring(rightText)
    end
    local plain = StripTooltipTextForStatMatch(combined)
    plain = plain:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if plain == "" then return false end
    plain = plain:lower()
    if plain:find("^classes%s*:") or plain:find("^classi%s*:") or plain:find("^clases?%s*:") or plain:find("^classe?%s*:") or plain:find("^klassen?%s*:") then
        return true
    end
    return false
end

local function IsVisuallyEmptyTooltipDataLine(line)
    if not line then return true end
    local l, r = line.leftText, line.rightText
    if l and issecretvalue and issecretvalue(l) then return false end
    if r and issecretvalue and issecretvalue(r) then return false end
    l = l and tostring(l):gsub("%s", "") or ""
    r = r and tostring(r):gsub("%s", "") or ""
    return l == "" and r == ""
end

-- Blizzard primaryStat: 1=Str, 2=Agi, 4=Int. Used for which Str/Agi/Int line is "yours" on item tooltips.
-- Midnight: DH 1480 Devourer = Intellect; Havoc/Vengeance = Agility (see SpecializationID table on wiki).
-- For unknown spec IDs, ResolvePrimaryStatKindForSpec falls back to scanning GetSpecializationInfoForClassID.
local SPEC_ID_PRIMARY_KIND = {
    [250] = "strength", [251] = "strength", [252] = "strength", [1455] = "strength",
    [577] = "agility", [581] = "agility", [1480] = "intellect", [1456] = "agility",
    [102] = "intellect", [103] = "agility", [104] = "agility", [105] = "intellect", [1447] = "intellect",
    [1467] = "intellect", [1468] = "intellect", [1473] = "intellect", [1465] = "intellect",
    [253] = "agility", [254] = "agility", [255] = "agility", [1448] = "agility",
    [62] = "intellect", [63] = "intellect", [64] = "intellect", [1449] = "intellect",
    [268] = "agility", [270] = "intellect", [269] = "agility", [1450] = "agility",
    [65] = "intellect", [66] = "strength", [70] = "strength", [1451] = "strength",
    [256] = "intellect", [257] = "intellect", [258] = "intellect", [1452] = "intellect",
    [259] = "agility", [260] = "agility", [261] = "agility", [1453] = "agility",
    [262] = "intellect", [263] = "agility", [264] = "intellect", [1444] = "intellect",
    [265] = "intellect", [266] = "intellect", [267] = "intellect", [1454] = "intellect",
    [71] = "strength", [72] = "strength", [73] = "strength", [1446] = "strength",
}

local function PrimaryStatCodeToKind(n)
    n = tonumber(n)
    if not n then return nil end
    if n == 1 then return "strength" end
    if n == 2 then return "agility" end
    if n == 4 then return "intellect" end
    if LE_UNIT_STAT_STRENGTH and n == LE_UNIT_STAT_STRENGTH then return "strength" end
    if LE_UNIT_STAT_AGILITY and n == LE_UNIT_STAT_AGILITY then return "agility" end
    if LE_UNIT_STAT_INTELLECT and n == LE_UNIT_STAT_INTELLECT then return "intellect" end
    return nil
end

-- One cache: many tooltip lines share the same specID; avoid re-scanning class rows every line.
local _primaryKindBySpec = {}
local _primaryKindLookupFailed = {}

--- Primary stat line kind for tooltip coloring: Str/Agi/Int that matches the character's spec.
--- Order: (1) C_SpecializationInfo for that spec+class (covers all client-defined specs, future patches),
--- (2) static SPEC_ID_PRIMARY_KIND, (3) C_SpecializationInfo.GetSpecPrimaryStat if present, (4) return scan.
local function ResolvePrimaryStatKindForSpec(specID)
    if not specID or specID < 1 then return nil end
    if _primaryKindBySpec[specID] then return _primaryKindBySpec[specID] end
    if _primaryKindLookupFailed[specID] then return nil end

    local sex = 2
    if UnitSex and _G.UnitExists and UnitExists("player") then
        local u = UnitSex("player")
        if u == 2 or u == 3 then sex = u end
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
        and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local f = C_SpecializationInfo.GetSpecializationInfo
        for classID = 1, 20 do
            local nSpec = GetNumSpecializationsForClassID(classID)
            if nSpec and nSpec > 0 then
                for specIndex = 1, nSpec do
                    if select(1, GetSpecializationInfoForClassID(classID, specIndex)) == specID then
                        -- pcall: ok, r1..rN from GetSpecializationInfo. Returns specId, name, desc, icon, role, primaryStat, ...
                        local pack = { pcall(f, specIndex, false, false, nil, sex, nil, classID) }
                        if not pack[1] then
                            pack = { pcall(f, C_SpecializationInfo, specIndex, false, false, nil, sex, nil, classID) }
                        end
                        if pack[1] and pack[2] == specID and pack[7] then
                            local k = PrimaryStatCodeToKind(pack[7])
                            if k then
                                _primaryKindBySpec[specID] = k
                                return k
                            end
                        end
                    end
                end
            end
        end
    end

    do
        local t = SPEC_ID_PRIMARY_KIND[specID]
        if t then
            _primaryKindBySpec[specID] = t
            return t
        end
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecPrimaryStat then
        local ok, code = pcall(C_SpecializationInfo.GetSpecPrimaryStat, C_SpecializationInfo, specID)
        if not ok or not code then
            ok, code = pcall(C_SpecializationInfo.GetSpecPrimaryStat, specID)
        end
        if ok and code then
            local k = PrimaryStatCodeToKind(code)
            if k then
                _primaryKindBySpec[specID] = k
                return k
            end
        end
    end

    if GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        for classID = 1, 20 do
            local nSpec = GetNumSpecializationsForClassID(classID)
            if nSpec and nSpec > 0 then
                for idx = 1, nSpec do
                    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = GetSpecializationInfoForClassID(classID, idx)
                    if r1 == specID then
                        for _, v in ipairs({ r6, r7, r8, r9, r10, r11, r12, r5, r4, r3, r2 }) do
                            local k = PrimaryStatCodeToKind(v)
                            if k then
                                _primaryKindBySpec[specID] = k
                                return k
                            end
                        end
                    end
                end
            end
        end
    end

    _primaryKindLookupFailed[specID] = true
    return nil
end

local function GetCombinedPlainLeftRight(leftText, rightText)
    local l = StripTooltipTextForStatMatch(leftText or "")
    local r = StripTooltipTextForStatMatch(rightText or "")
    l = (l:match("^%s*(.-)%s*$") or "")
    r = (r:match("^%s*(.-)%s*$") or "")
    if l ~= "" and r ~= "" then return l .. " " .. r end
    if l ~= "" then return l end
    return r
end

---Which primary stat this "+N …" line is (not Stamina / secondaries).
local function DetectPrimaryStatLineKindFromPlain(plain)
    if not plain or plain == "" or not plain:find("^%s*%+?%d+") then return nil end
    local L = ns.L
    local packs = {
        { "intellect", { SPELL_STAT4_NAME, ITEM_MOD_INTELLECT_SHORT, L and L["STAT_INTELLECT"] } },
        { "strength", { SPELL_STAT1_NAME, ITEM_MOD_STRENGTH_SHORT, L and L["STAT_STRENGTH"] } },
        { "agility", { SPELL_STAT2_NAME, ITEM_MOD_AGILITY_SHORT, L and L["STAT_AGILITY"] } },
    }
    for p = 1, #packs do
        local kind = packs[p][1]
        local names = packs[p][2]
        for i = 1, #names do
            local n = names[i]
            if type(n) == "string" and n ~= "" and plain:find(n, 1, true) then return kind end
        end
    end
    return nil
end

---Only the selected spec's main stat is white; other Str/Agi/Int on the same item stay dimmed.
local function ApplyGearTabPrimaryStatLineHighlight(line, ctx)
    if not line or not ctx then return end
    local specID = tonumber(ctx.specID)
    if not specID or specID < 1 then return end
    local want = ResolvePrimaryStatKindForSpec(specID)
    if not want then return end

    local plain = GetCombinedPlainLeftRight(line.leftText, line.rightText)
    local lineKind = DetectPrimaryStatLineKindFromPlain(plain)
    if not lineKind then return end

    line.leftText = StripTooltipTextForStatMatch(line.leftText or "")
    line.rightText = StripTooltipTextForStatMatch(line.rightText or "")
    if lineKind == want then
        if ns.UI_IsLightMode and ns.UI_IsLightMode() and ns.UI_GetTextRoleRGB then
            local br, bg, bb = ns.UI_GetTextRoleRGB("Bright")
            line.leftColor = { r = br, g = bg, b = bb }
            line.rightColor = { r = br, g = bg, b = bb }
        else
            line.leftColor = { r = 1, g = 1, b = 1 }
            line.rightColor = { r = 1, g = 1, b = 1 }
        end
    else
        if ns.UI_IsLightMode and ns.UI_IsLightMode() and ns.UI_GetTextRoleRGB then
            local dr, dg, db = ns.UI_GetTextRoleRGB("Dim")
            line.leftColor = { r = dr, g = dg, b = db }
            line.rightColor = { r = dr, g = dg, b = db }
        else
            line.leftColor = { r = 0.65, g = 0.65, b = 0.65 }
            line.rightColor = { r = 0.65, g = 0.65, b = 0.65 }
        end
    end
end

-- TooltipDataLineType (Blizzard): ItemEnchantmentPermanent = 15
local TOOLTIP_LINE_ITEM_ENCHANTMENT_PERMANENT = (Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent) or 15

-- Blizzard surfaces tooltip args onto line tables (see TooltipUtil.SurfaceArgs); lines also carry raw .args.
local PROFESSION_QUALITY_LINE_KEYS = {
    "craftingQuality",
    "quality",
    "qualityTier",
    "tier",
    "qualityIndex",
    "professionQuality",
    "itemEnchantmentQuality",
    "enchantQuality",
}

local function TooltipSurfaceLineArgs(line)
    if not line or type(line) ~= "table" then return end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, line)
    end
    local args = line.args
    if type(args) ~= "table" then return end
    for ai = 1, #args do
        local a = args[ai]
        if type(a) == "table" and type(a.field) == "string" and a.field ~= "" then
            local v = a.stringVal or a.intVal or a.floatVal
            if v == nil and a.boolVal ~= nil then v = a.boolVal end
            if v == nil and a.colorVal ~= nil then v = a.colorVal end
            if v == nil and a.guidVal ~= nil then v = a.guidVal end
            if v ~= nil and rawget(line, a.field) == nil then
                line[a.field] = v
            end
        end
    end
end

local function TooltipSurfaceAllLines(tooltipData)
    if not tooltipData or type(tooltipData.lines) ~= "table" then return end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end
    for i = 1, #tooltipData.lines do
        TooltipSurfaceLineArgs(tooltipData.lines[i])
    end
end

--- Pull tier digit from inline `|A:Professions-ChatIcon-Quality-Tier<N>:...|a` atlas markers
--- Blizzard renders enchant tier as an inline atlas in the line text, not as a surfaced field
local function ExtractTierFromInlineAtlasMarker(text)
    if not text or type(text) ~= "string" then return nil end
    local d = text:match("Professions%-ChatIcon%-Quality%-[^:|]-Tier(%d)")
        or text:match("Professions%-Icon%-Quality%-Tier(%d)")
        or text:match("Professions%-Quality%-Tier(%d)")
        or text:match("ChatIcon%-Quality%-Tier(%d)")
    local n = tonumber(d)
    if n and n >= 1 and n <= 10 then return n end
    return nil
end

local function ExtractProfessionCraftingQualityTierFromTooltipLine(line)
    if not line then return nil end
    TooltipSurfaceLineArgs(line)
    for ki = 1, #PROFESSION_QUALITY_LINE_KEYS do
        local k = PROFESSION_QUALITY_LINE_KEYS[ki]
        local v = line[k]
        local n = tonumber(v)
        if n and n >= 1 and n <= 10 then
            return math.floor(n + 0.5)
        end
    end
    local fromLeft = ExtractTierFromInlineAtlasMarker(line.leftText)
    if fromLeft then return fromLeft end
    local fromRight = ExtractTierFromInlineAtlasMarker(line.rightText)
    if fromRight then return fromRight end
    return nil
end

local function ClampMidnightProfessionQualityTier(n)
    if type(n) ~= "number" then return nil end
    local t = math.floor(n + 0.5)
    if t < 1 then t = 1 end
    if t > 3 then t = 3 end
    return t
end

local _enchantCraftingTierCache = {}
local ENCHANT_TIER_CACHE_MAX = 120

local function TrimEnchantTierCacheIfNeeded()
    local n = 0
    for _ in pairs(_enchantCraftingTierCache) do
        n = n + 1
        if n >= ENCHANT_TIER_CACHE_MAX then
            wipe(_enchantCraftingTierCache)
            return
        end
    end
end

local function GetEnchantmentCraftingQualityTierFromItemLinkTooltipScan(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if issecretvalue and issecretvalue(itemLink) then return nil end
    local cached = _enchantCraftingTierCache[itemLink]
    if cached ~= nil then return cached end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if not ok or not data or type(data.lines) ~= "table" then return nil end
    TooltipSurfaceAllLines(data)
    local found = nil
    for i = 1, #data.lines do
        local ln = data.lines[i]
        if ln and ln.type == TOOLTIP_LINE_ITEM_ENCHANTMENT_PERMANENT then
            found = ExtractProfessionCraftingQualityTierFromTooltipLine(ln)
            if found then break end
        end
    end
    if found then
        TrimEnchantTierCacheIfNeeded()
        _enchantCraftingTierCache[itemLink] = found
    end
    return found
end

--- Gear slot glyph + external callers: enchant row quality from tooltip data (not item GetCraftingQuality).
local function GetEnchantmentCraftingQualityTierFromItemLink(itemLink)
    local t = GetEnchantmentCraftingQualityTierFromItemLinkTooltipScan(itemLink)
    return ClampMidnightProfessionQualityTier(t)
end

local _anyLineProfessionTierCache = {}
local ANY_LINE_TIER_CACHE_MAX = 120

local function TrimAnyLineProfessionTierCacheIfNeeded()
    local n = 0
    for _ in pairs(_anyLineProfessionTierCache) do
        n = n + 1
        if n >= ANY_LINE_TIER_CACHE_MAX then
            wipe(_anyLineProfessionTierCache)
            return
        end
    end
end

--- First profession crafting-quality tier found on any tooltip line (gems, consumables, etc.).
--- Enchant-specific path remains `GetEnchantmentCraftingQualityTierFromItemLink` (permanent-enchant line only).
local function GetProfessionCraftingQualityTierFromItemLinkAnyLineScan(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if issecretvalue and issecretvalue(itemLink) then return nil end
    local cached = _anyLineProfessionTierCache[itemLink]
    if cached ~= nil then return cached end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if not ok or not data or type(data.lines) ~= "table" then return nil end
    TooltipSurfaceAllLines(data)
    local found = nil
    for i = 1, #data.lines do
        local ln = data.lines[i]
        found = ExtractProfessionCraftingQualityTierFromTooltipLine(ln)
        if found then break end
    end
    if found then
        TrimAnyLineProfessionTierCacheIfNeeded()
        _anyLineProfessionTierCache[itemLink] = found
    end
    return ClampMidnightProfessionQualityTier(found)
end

function TooltipService:RenderCustomTooltip(frame, data)
    -- 1) Icon (top-left; icon=false explicitly hides icon, nil falls back to question mark)
    if data.icon == false then
        -- Explicitly no icon requested
    elseif data.icon then
        frame:SetIcon(data.icon, data.iconIsAtlas)
    elseif data.title then
        -- Show fallback question mark only if there's a title (real tooltip)
        frame:SetIcon(nil)
    end
    
    -- 2) Title (always at top)
    if data.title then
        local tr, tg, tb, ta = 1, 0.82, 0, 1
        if data.titleColor then
            tr, tg, tb = data.titleColor[1], data.titleColor[2], data.titleColor[3]
        elseif ns.UI_GetTooltipTitleColor then
            tr, tg, tb, ta = ns.UI_GetTooltipTitleColor()
        end
        frame:SetTitle(data.title, tr, tg, tb)
    end
    
    -- 3) Description (below title, optional)
    if data.description then
        local dr, dg, db = TooltipBodyRGB()
        if data.descriptionColor then
            dr, dg, db = data.descriptionColor[1], data.descriptionColor[2], data.descriptionColor[3]
        elseif ns.UI_GetTooltipBodyColor then
            dr, dg, db = ns.UI_GetTooltipBodyColor()
        end
        frame:SetDescription(data.description, dr, dg, db)
    end

    if data.titleAffixPair and frame.AddTitleAffixPair then
        local ap = data.titleAffixPair
        local lc = ap.leftColor
        if not lc then
            local lr, lg, lb = TooltipBrightRGB()
            lc = { lr, lg, lb }
        end
        local rc = ap.rightColor
        if not rc and ns.UI_GetSemanticGoldColor then
            local gr, gg, gb = ns.UI_GetSemanticGoldColor()
            rc = { gr, gg, gb }
        elseif not rc then
            rc = { 0.83, 0.69, 0.22 }
        end
        frame:AddTitleAffixPair(ap.left, ap.right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
    end
    
    -- 4) Data lines
    if data.lines then
        for _, line in ipairs(data.lines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.type == "divider" and frame.AddBodyDivider then
                frame:AddBodyDivider()
            elseif line.type == "section_label" and frame.AddSectionLabel then
                local c = line.color
                if not c then
                    local mr, mg, mb = (ns.UI_GetTooltipLabelColor and ns.UI_GetTooltipLabelColor()) or 0.7, 0.7, 0.72
                    c = { mr, mg, mb }
                end
                frame:AddSectionLabel(line.text, c[1], c[2], c[3])
            elseif line.type == "centered" and frame.AddCenteredLine then
                local c = line.color
                if not c then
                    local cr, cg, cb = TooltipBrightRGB()
                    c = { cr, cg, cb }
                end
                frame:AddCenteredLine(line.text, c[1], c[2], c[3])
            elseif line.left and line.right then
                local leftColor = line.leftColor
                if not leftColor then
                    local lr, lg, lb = (ns.UI_GetTooltipLabelColor and ns.UI_GetTooltipLabelColor()) or 0.7, 0.7, 0.72
                    leftColor = { lr, lg, lb }
                end
                local rightColor = line.rightColor
                if not rightColor then
                    local rr, rg, rb = (ns.UI_GetTextRoleRGB and ns.UI_GetTextRoleRGB("Bright")) or 1, 1, 1
                    rightColor = { rr, rg, rb }
                end
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3],
                    { balanced = line.balanced == true }
                )
            elseif line.type == "vault_grid_row" then
                frame:AddVaultGridRow(
                    line.name,
                    line.realm,
                    line.colRaid,
                    line.colMplus,
                    line.colWorld,
                    line.widths,
                    { isHeader = line.isHeader == true }
                )
            elseif line.type == "vault_track_row" then
                frame:AddVaultTrackRow(
                    line.colRaid,
                    line.colMplus,
                    line.colWorld,
                    line.colW,
                    { isHeader = line.isHeader == true }
                )
            elseif line.left then
                local leftColor = line.leftColor
                if not leftColor then
                    local lr, lg, lb = (ns.UI_GetTooltipLabelColor and ns.UI_GetTooltipLabelColor()) or 0.7, 0.7, 0.72
                    leftColor = { lr, lg, lb }
                end
                frame:AddLine(line.left, leftColor[1], leftColor[2], leftColor[3], line.wrap or false)
            elseif line.text then
                local color = line.color
                if not color then
                    local cr, cg, cb = TooltipBodyRGB()
                    color = { cr, cg, cb }
                end
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

function TooltipService:RenderItemTooltip(frame, data)
    local itemID = data.itemID
    local itemLink = data.itemLink
    if not itemID and not itemLink then return end

    local ctx = data.itemTooltipContext
    if ctx and ctx.level and ctx.specID and ctx.level >= 1 and ctx.specID >= 1 then
        -- Gear tab: preview for the *selected* character (not the logged-in one). Spec ID in the
        -- link drives which primary stat is "yours". linkLevel must be >= item min level or the
        -- client still greys primary stats (e.g. Lv90 weapon while selected char is 80 — we lift
        -- linkLevel to minLevel so the addon tooltip shows main stats as active for that spec).
        local minLv = 0
        local srcLink = data.itemLink
        local srcID = data.itemID
        if srcLink and type(srcLink) == "string" and not (issecretvalue and issecretvalue(srcLink)) then
            minLv = select(5, C_Item.GetItemInfo(srcLink)) or 0
        elseif srcID and C_Item and C_Item.GetItemInfo then
            minLv = select(5, C_Item.GetItemInfo(srcID)) or 0
        elseif srcID and GetItemInfo then
            minLv = select(5, GetItemInfo(srcID)) or 0
        end
        if minLv and issecretvalue and issecretvalue(minLv) then
            minLv = 0
        else
            minLv = tonumber(minLv) or 0
        end
        local effLevel = math.max(ctx.level, minLv, 1)
        itemLink = ApplyItemLinkTooltipContext(itemLink, itemID, effLevel, ctx.specID) or itemLink
    end
    
    -- Get basic info for icon and fallback
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture
    if itemLink then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    elseif itemID then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
    end
    
    -- 1) Icon
    frame:SetIcon(itemTexture or nil)
    
    -- 2) Get full tooltip data via C_TooltipInfo (modern TWW API, taint-safe)
    local tooltipData = nil
    if C_TooltipInfo then
        local ok, result = pcall(function()
            if itemLink then
                return C_TooltipInfo.GetHyperlink(itemLink)
            elseif itemID then
                return C_TooltipInfo.GetItemByID(itemID)
            end
        end)
        if ok and result then
            tooltipData = result
        end
    end
    
    if tooltipData and tooltipData.lines and #tooltipData.lines > 0 then
        -- Surface root + per-line args so craftingQuality etc. exist before profession/atlas rewrite.
        TooltipSurfaceAllLines(tooltipData)
        while #tooltipData.lines > 1 and IsVisuallyEmptyTooltipDataLine(tooltipData.lines[#tooltipData.lines]) do
            table.remove(tooltipData.lines)
        end
        
        -- First line = item name (title)
        local firstLine = tooltipData.lines[1]
        local titleText = firstLine.leftText or itemName or "Item"
        local titleR, titleG, titleB = 1, 1, 1
        
        if firstLine.leftColor then
            titleR = firstLine.leftColor.r or 1
            titleG = firstLine.leftColor.g or 1
            titleB = firstLine.leftColor.b or 1
        elseif itemQuality then
            local qColor = ITEM_QUALITY_COLORS[itemQuality]
            if qColor then
                titleR, titleG, titleB = qColor.r, qColor.g, qColor.b
            end
        end
        
        titleR, titleG, titleB = RemapTooltipLineRGB(titleR, titleG, titleB)
        frame:SetTitle(titleText, titleR, titleG, titleB)
        
        if data.underTitleLines then
            for _, u in ipairs(data.underTitleLines) do
                if u and u.text then
                    local c = u.color or { 0.8, 0.5, 0.2 }
                    if frame.AddTitleAffix then
                        frame:AddTitleAffix(u.text, c[1], c[2], c[3], u.wrap or false)
                    else
                        frame:AddLine(u.text, c[1], c[2], c[3], u.wrap or false)
                    end
                end
            end
        end

        -- All remaining lines = item data (binding, type, ilvl, stats, effects, etc.)
        for i = 2, #tooltipData.lines do
            local line = tooltipData.lines[i]
            local leftText = line.leftText
            local rightText = line.rightText
            local skipClass = data.itemTooltipContext and IsItemTooltipClassRestrictionLine(leftText, rightText)
            if not skipClass then
                if data.itemTooltipContext then
                    ApplyGearTabPrimaryStatLineHighlight(line, data.itemTooltipContext)
                end
                leftText = line.leftText
                rightText = line.rightText
                -- Skip completely empty lines (add spacer)
                if (not leftText or leftText == "") and (not rightText or rightText == "") then
                    frame:AddSpacer(4)
                elseif rightText and rightText ~= "" then
                    -- Double line (left + right)
                    local lr, lg, lb = 1, 1, 1
                    local rr, rg, rb = 1, 1, 1
                    if line.leftColor then
                        lr = line.leftColor.r or 1
                        lg = line.leftColor.g or 1
                        lb = line.leftColor.b or 1
                    end
                    if line.rightColor then
                        rr = line.rightColor.r or 1
                        rg = line.rightColor.g or 1
                        rb = line.rightColor.b or 1
                    end
                    lr, lg, lb = RemapTooltipLineRGB(lr, lg, lb)
                    rr, rg, rb = RemapTooltipLineRGB(rr, rg, rb)
                    frame:AddDoubleLine(leftText or "", rightText, lr, lg, lb, rr, rg, rb)
                else
                    -- Single line
                    local lr, lg, lb = 1, 1, 1
                    if line.leftColor then
                        lr = line.leftColor.r or 1
                        lg = line.leftColor.g or 1
                        lb = line.leftColor.b or 1
                    end
                    lr, lg, lb = RemapTooltipLineRGB(lr, lg, lb)
                    frame:AddLine(leftText, lr, lg, lb, line.wrapText or false)
                end
            end
        end
    else
        -- Fallback: basic C_Item.GetItemInfo data
        if itemName then
            local r, g, b = 1, 1, 1
            if itemQuality then
                local qColor = ITEM_QUALITY_COLORS[itemQuality]
                if qColor then r, g, b = qColor.r, qColor.g, qColor.b end
            end
            frame:SetTitle(itemName, r, g, b)
        else
            frame:SetTitle(string.format((ns.L and ns.L["ITEM_NUMBER_FORMAT"]) or "Item #%s", itemID or "?"), 1, 1, 1)
        end
        if data.underTitleLines then
            for _, u in ipairs(data.underTitleLines) do
                if u and u.text then
                    local c = u.color or { 0.8, 0.5, 0.2 }
                    if frame.AddTitleAffix then
                        frame:AddTitleAffix(u.text, c[1], c[2], c[3], u.wrap or false)
                    else
                        frame:AddLine(u.text, c[1], c[2], c[3], u.wrap or false)
                    end
                end
            end
        end
        if itemName then
            local dr, dg, db = (ns.UI_GetTooltipDescColor and ns.UI_GetTooltipDescColor()) or 0.7, 0.7, 0.7
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading details...", dr, dg, db)
        else
            local dr, dg, db = (ns.UI_GetTooltipDescColor and ns.UI_GetTooltipDescColor()) or 0.7, 0.7, 0.7
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading...", dr, dg, db)
        end
    end
    
    -- Additional custom lines (Item ID, stack count, location, instructions, etc.)
    if data.additionalLines then
        frame:AddSpacer(4)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                local leftColor, rightColor
                if line.leftColor then
                    leftColor = { line.leftColor[1], line.leftColor[2], line.leftColor[3] }
                else
                    local lr, lg, lb = TooltipBrightRGB()
                    leftColor = { lr, lg, lb }
                end
                if line.rightColor then
                    rightColor = { line.rightColor[1], line.rightColor[2], line.rightColor[3] }
                else
                    local rr, rg, rb = TooltipBrightRGB()
                    rightColor = { rr, rg, rb }
                end
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
                )
            elseif line.text then
                local color = line.color
                if not color and ns.UI_GetSemanticInfoColor then
                    local cr, cg, cb = ns.UI_GetSemanticInfoColor()
                    color = { cr, cg, cb }
                elseif not color then
                    color = { 0.6, 0.4, 0.8 }
                end
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Return tooltip stat lines for an item (for use under profession equipment in custom tooltips).
    Skips title line; returns left/right lines with colors. Safe for secret values (Midnight).
]]
function TooltipService:GetItemTooltipStatLines(itemLink, itemID)
    if not C_TooltipInfo then return {} end
    local tooltipData
    if itemLink and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
        if C_TooltipInfo.GetHyperlink then
            local ok, result = pcall(C_TooltipInfo.GetHyperlink, itemLink)
            if ok and result then tooltipData = result end
        end
    end
    if not tooltipData and itemID and C_TooltipInfo.GetItemByID then
        local ok, result = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and result then tooltipData = result end
    end
    if not tooltipData or not tooltipData.lines then return {} end
    if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, tooltipData) end
    local out = {}
    for i = 2, math.min(#tooltipData.lines, 12) do
        local line = tooltipData.lines[i]
        if not line then break end
        local left = line.leftText
        local right = line.rightText
        if issecretvalue then
            if left and issecretvalue(left) then left = nil end
            if right and issecretvalue(right) then right = nil end
        end
        left = (left and tostring(left):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        right = (right and tostring(right):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if left ~= "" or right ~= "" then
            local lc = line.leftColor
            local rc = line.rightColor
            local leftColor, rightColor
            if lc then
                local lr, lg, lb = RemapTooltipLineRGB(lc.r or 1, lc.g or 1, lc.b or 1)
                leftColor = { lr, lg, lb }
            else
                local lr, lg, lb = TooltipBodyRGB()
                leftColor = { lr, lg, lb }
            end
            if rc then
                local rr, rg, rb = RemapTooltipLineRGB(rc.r or 1, rc.g or 1, rc.b or 1)
                rightColor = { rr, rg, rb }
            else
                local rr, rg, rb = TooltipBodyRGB()
                rightColor = { rr, rg, rb }
            end
            out[#out + 1] = { left = left, right = right, leftColor = leftColor, rightColor = rightColor }
        end
    end
    return out
end

-- Profession gear: use client FrameXML globals (_G.INVTYPE_*) so slot labels match locale.
local function GetLocalizedEquipLocLabel(equipLoc)
    if not equipLoc or equipLoc == "" then return nil end
    local g = _G[equipLoc]
    if type(g) == "string" and g ~= "" then return g end
    return nil
end

local localizedProfessionSlotPatterns
local function GetLocalizedProfessionSlotPatterns()
    if localizedProfessionSlotPatterns then return localizedProfessionSlotPatterns end
    local keys = {
        "INVTYPE_WEAPONOFFHAND", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON",
        "INVTYPE_SHOULDER", "INVTYPE_PROFESSION_TOOL",
        "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
        "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND",
        "INVTYPE_CLOAK", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET",
        "INVTYPE_HOLDABLE",
    }
    local seen = {}
    local list = {}
    for i = 1, #keys do
        local s = _G[keys[i]]
        if type(s) == "string" and s ~= "" and not seen[s] then
            seen[s] = true
            list[#list + 1] = s
        end
    end
    table.sort(list, function(a, b) return #a > #b end)
    localizedProfessionSlotPatterns = list
    return list
end

--- Blizzard global strings use printf tokens (%s, %d). Lua patterns must not treat %s as whitespace:
--- take the literal prefix before the first '%%' for stable substring matching across locales.
local function LowerGlobalLocalizedPrefix(globalName)
    local s = _G[globalName]
    if type(s) ~= "string" or s == "" then return nil end
    local plain = s:match("^([^%%]*)") or s
    plain = plain:match("^%s*(.-)%s*$") or plain
    if plain == "" or #plain < 4 then return nil end
    return plain:lower()
end

local function TooltipCombinedLooksLikeBindingOrUnique(combinedLower)
    if combinedLower:find("binds when", 1, true) or combinedLower:find("unique%-equipped", 1, true)
        or combinedLower:find("when equipped", 1, true) then
        return true
    end
    local globalsList = {
        "ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_ON_USE", "ITEM_SOULBOUND",
        "ITEM_ACCOUNTBOUND", "ITEM_BIND_TO_BNETACCOUNT", "ITEM_BIND_TO_ACCOUNT",
        "ITEM_UNIQUE_EQUIPPED", "ITEM_UNIQUE",
    }
    for i = 1, #globalsList do
        local p = LowerGlobalLocalizedPrefix(globalsList[i])
        if p and combinedLower:find(p, 1, true) then return true end
    end
    return false
end

local function TooltipCombinedLooksLikeRequiresLevel(combinedLower)
    if combinedLower:find("requires level", 1, true) then return true end
    local p = LowerGlobalLocalizedPrefix("ITEM_MIN_LEVEL")
        or LowerGlobalLocalizedPrefix("ITEM_MIN_SKILL")
    if p and combinedLower:find(p, 1, true) then return true end
    return false
end

local function TooltipLineLooksLikeItemLevel(left, right)
    local il = _G.ITEM_LEVEL
    if type(il) ~= "string" or il == "" then il = "Item Level" end
    local kw = il:match("^([^%%]+)") or il
    kw = kw:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if kw == "" then return false end
    local l = (left or ""):lower()
    local r = (right or ""):lower()
    return (l:find(kw, 1, true) ~= nil) or (r:find(kw, 1, true) ~= nil)
end

local function TooltipLineLooksLikeProfessionEquipSkill(left)
    if not left or left == "" or not left:find("^%+%d") then return false end
    local skillWord = _G.SKILL
    if type(skillWord) == "string" and skillWord ~= "" then
        return left:lower():find(skillWord:lower(), 1, true) ~= nil
    end
    return left:find("Skill", 1, true) ~= nil
end

--[[
    Return only item level, stats, and equip-effect lines for profession equipment tooltips.
    Plus a first line for slot type (Tool / Head / Chest / etc.).
]]
function TooltipService:GetItemTooltipSummaryLines(itemLink, itemID, slotKey)
    local out = {}
    local L = ns.L
    local defaultTool = GetLocalizedEquipLocLabel("INVTYPE_PROFESSION_TOOL") or "Tool"
    local defaultAccessory = (L and L["PROFESSION_SUMMARY_SLOT_ACCESSORY"]) or "Accessory"
    local slotLabel = (slotKey == "tool") and defaultTool or defaultAccessory
    local initialSlotLabel = slotLabel

    -- Load tooltip data first (needed for slot inference when equipLoc is PROFESSION_GEAR)
    local tooltipData
    if C_TooltipInfo then
        if itemLink and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) and C_TooltipInfo.GetHyperlink then
            local ok, result = pcall(C_TooltipInfo.GetHyperlink, itemLink)
            if ok and result then tooltipData = result end
        end
        if not tooltipData and itemID and C_TooltipInfo.GetItemByID then
            local ok, result = pcall(C_TooltipInfo.GetItemByID, itemID)
            if ok and result then tooltipData = result end
        end
    end
    if tooltipData and tooltipData.lines and TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end

    -- Resolve slot: equipLoc from API, or from tooltip when INVTYPE_PROFESSION_GEAR
    if itemID or itemLink then
        local equipLoc = nil
        if C_Item and C_Item.GetItemInfo then
            local link = itemLink or (itemID and ("item:" .. tostring(itemID))) or nil
            local ok, name, _, _, _, _, _, _, eq = pcall(C_Item.GetItemInfo, link or itemID)
            if ok and eq and type(eq) == "string" and eq ~= "" then equipLoc = eq end
        end
        if (not equipLoc or equipLoc == "") and C_Item and C_Item.GetItemInfoInstant and itemID then
            local ok2, _, _, _, eqInst = pcall(C_Item.GetItemInfoInstant, itemID)
            if ok2 and eqInst and type(eqInst) == "string" and eqInst ~= "" then equipLoc = eqInst end
        end
        if equipLoc and equipLoc ~= "" then
            local mapped = GetLocalizedEquipLocLabel(equipLoc)
            if mapped then
                slotLabel = mapped
            elseif equipLoc:find("PROFESSION_GEAR") or equipLoc:find("Profession") then
                -- Infer from tooltip (e.g. "Unique-Equipped: Head (1)" or localized slot name)
                if tooltipData and tooltipData.lines then
                    local patterns = GetLocalizedProfessionSlotPatterns()
                    for i = 1, math.min(#tooltipData.lines, 5) do
                        local line = tooltipData.lines[i]
                        if line then
                            local left = line.leftText
                            local right = line.rightText
                            if issecretvalue then
                                if left and issecretvalue(left) then left = nil end
                                if right and issecretvalue(right) then right = nil end
                            end
                            left = (left and tostring(left)) or ""
                            right = (right and tostring(right)) or ""
                            for pi = 1, #patterns do
                                local pat = patterns[pi]
                                local escaped = pat:gsub("%%", "%%%%")
                                local word = "[%s%(:]" .. escaped .. "[%s%(]"
                                local startPat = "^" .. escaped .. "[%s%(]"
                                if (left ~= "" and (left:find(word) or left:find(startPat) or left == pat)) or (right ~= "" and (right:find(word) or right:find(startPat) or right == pat)) then
                                    slotLabel = pat
                                    break
                                end
                            end
                            if slotLabel ~= initialSlotLabel then break end
                        end
                    end
                end
            else
                slotLabel = equipLoc:gsub("INVTYPE_", ""):gsub("(%l)(%u)", "%1 %2")
                if not slotLabel or slotLabel == "" then slotLabel = defaultAccessory end
            end
        end
    end
    local slotLabelColor
    do
        local sr, sg, sb = (ns.UI_GetSemanticInfoColor and ns.UI_GetSemanticInfoColor()) or 0.7, 0.7, 0.9
        slotLabelColor = { sr, sg, sb }
    end
    out[1] = { left = slotLabel, right = "", leftColor = slotLabelColor, rightColor = slotLabelColor }

    if not tooltipData or not tooltipData.lines then return out end

    for i = 2, math.min(#tooltipData.lines, 14) do
        local line = tooltipData.lines[i]
        if not line then break end
        local left = line.leftText
        local right = line.rightText
        if issecretvalue then
            if left and issecretvalue(left) then left = nil end
            if right and issecretvalue(right) then right = nil end
        end
        left = (left and tostring(left):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        right = (right and tostring(right):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if left ~= "" or right ~= "" then
            local combined = (left .. " " .. right):lower()
            -- Exclude: binding, unique-equipped, requires level/skill (locale-aware via globals where present)
            if TooltipCombinedLooksLikeBindingOrUnique(combined) or TooltipCombinedLooksLikeRequiresLevel(combined) then
                -- skip
            else
                -- Include only: (1) Item Level, (2) stat lines (+Number), (3) equip effect (+X ... Skill).
                local isItemLevel = TooltipLineLooksLikeItemLevel(left, right)
                local isStat = left:find("^%+%d") or right:find("^%+%d")
                local isEquipEffect = TooltipLineLooksLikeProfessionEquipSkill(left)
                if isItemLevel or isStat or isEquipEffect then
                    local lc = line.leftColor
                    local rc = line.rightColor
                    local leftColor, rightColor
                    if lc then
                        local lr, lg, lb = RemapTooltipLineRGB(lc.r or 1, lc.g or 1, lc.b or 1)
                        leftColor = { lr, lg, lb }
                    else
                        local lr, lg, lb = TooltipBodyRGB()
                        leftColor = { lr, lg, lb }
                    end
                    if rc then
                        local rr, rg, rb = RemapTooltipLineRGB(rc.r or 1, rc.g or 1, rc.b or 1)
                        rightColor = { rr, rg, rb }
                    else
                        local rr, rg, rb = TooltipBodyRGB()
                        rightColor = { rr, rg, rb }
                    end
                    out[#out + 1] = {
                        left = left,
                        right = right,
                        leftColor = leftColor,
                        rightColor = rightColor,
                    }
                end
            end
        end
    end
    return out
end

--[[
    Render currency tooltip (Blizzard data + custom additions)
]]
function TooltipService:RenderCurrencyTooltip(frame, data)
    local currencyID = data.currencyID
    if not currencyID or not C_CurrencyInfo then return end
    
    -- Get currency info
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return end
    
    -- 1) Icon
    frame:SetIcon(info.iconFileID or nil)
    
    -- 2) Title
    local tr, tg, tb = 1, 0.82, 0
    if ns.UI_GetTooltipTitleColor then
        tr, tg, tb = ns.UI_GetTooltipTitleColor()
    end
    frame:SetTitle(info.name, tr, tg, tb)
    
    -- 3) Description
    if info.description and info.description ~= "" then
        local dr, dg, db = TooltipBodyRGB()
        if ns.UI_GetTooltipBodyColor then
            dr, dg, db = ns.UI_GetTooltipBodyColor()
        end
        frame:SetDescription(info.description, dr, dg, db)
    end

    -- Progress details (Current / Max / Season / Remaining) for key currencies.
    do
        local explicitCharKey = data.charKey
        local charKey = explicitCharKey or (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
        local currencyData = nil
        if WarbandNexus and WarbandNexus.GetCurrencyData and charKey then
            currencyData = WarbandNexus:GetCurrencyData(currencyID, charKey)
        end

        -- C_CurrencyInfo quantities / totalEarned are for the logged-in character only.
        -- When the tooltip is for another row (explicit charKey), never merge those API values.
        local canonRow = nil
        local canonCur = nil
        if ns.Utilities then
            if explicitCharKey and ns.Utilities.GetCanonicalCharacterKey then
                canonRow = ns.Utilities:GetCanonicalCharacterKey(explicitCharKey) or explicitCharKey
            elseif explicitCharKey then
                canonRow = explicitCharKey
            end
            if ns.Utilities.GetCharacterKey then
                canonCur = ns.Utilities:GetCharacterKey()
            end
            if canonCur and ns.Utilities.GetCanonicalCharacterKey then
                canonCur = ns.Utilities:GetCanonicalCharacterKey(canonCur) or canonCur
            end
        end
        local function normKey(k)
            return (k and k:gsub("%s+", "")) or ""
        end
        local useLiveCurrencyNumbers = (not explicitCharKey)
            or (canonRow and canonCur and normKey(canonRow) == normKey(canonCur))

        local qty
        if currencyData and currencyData.quantity ~= nil then
            qty = currencyData.quantity
        elseif useLiveCurrencyNumbers then
            qty = info.quantity or 0
        else
            qty = 0
        end
        local maxQty = (currencyData and currencyData.maxQuantity) or info.maxQuantity or 0
        local totalEarned = currencyData and currencyData.totalEarned
        if totalEarned == nil and useLiveCurrencyNumbers then
            if WarbandNexus and WarbandNexus.GetCurrencyProgressEarnedFromAPI then
                totalEarned = WarbandNexus:GetCurrencyProgressEarnedFromAPI(currencyID)
            end
            if totalEarned == nil and info.totalEarned ~= nil then
                if not (issecretvalue and issecretvalue(info.totalEarned)) then
                    totalEarned = tonumber(info.totalEarned)
                end
            end
        end
        local seasonMax = currencyData and currencyData.seasonMax
        if (seasonMax == nil or type(seasonMax) ~= "number" or seasonMax <= 0)
            and type(info.maxQuantity) == "number" and info.maxQuantity > 0
            and info.useTotalEarnedForMaxQty then
            seasonMax = info.maxQuantity
        end
        local hasSeasonProgress = (type(seasonMax) == "number" and seasonMax > 0)
        local teNum = (totalEarned ~= nil and type(totalEarned) == "number") and totalEarned or nil

        local function SafeCurrencyTooltipNum(v)
            if v == nil then return nil end
            if issecretvalue and issecretvalue(v) then return nil end
            return tonumber(v)
        end
        local isCofferShard = ns.Utilities and ns.Utilities.IsCofferKeyShardCurrency
            and ns.Utilities:IsCofferKeyShardCurrency(currencyID, info.name)
        local weeklyCapFromAPI = SafeCurrencyTooltipNum(info.maxWeeklyQuantity) or 0

        if hasSeasonProgress or (type(maxQty) == "number" and maxQty > 0) or isCofferShard then
            local fmtNumber = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
            local currentLabel = (ns.L and ns.L["CURRENT_ENTRIES_LABEL"]) or "Current:"
            local seasonLabel = (ns.L and ns.L["SEASON"]) or "Season"
            local weeklyLabel = (ns.L and ns.L["CURRENCY_LABEL_WEEKLY"]) or "Weekly"
            local cappedText = CAPPED or "Capped"
            local remainingSuffix = (ns.L and ns.L["VAULT_REMAINING_SUFFIX"]) or "remaining"
            frame:AddSpacer(6)

            if isCofferShard then
                local wCap = weeklyCapFromAPI
                if wCap <= 0 and type(maxQty) == "number" and maxQty > 0 then
                    wCap = maxQty
                end
                local teForWeek = (teNum ~= nil) and teNum or 0
                local remWeek = math.max(wCap - teForWeek, 0)
                local br, bg, bb = TooltipBrightRGB()
                frame:AddLine(string.format("%s %s", currentLabel, fmtNumber(qty)), br, bg, bb)
                if wCap > 0 then
                    frame:AddLine(string.format("%s: %s / %s", weeklyLabel, fmtNumber(teForWeek), fmtNumber(wCap)), br, bg, bb, false)
                    if remWeek > 0 then
                        frame:AddLine(string.format("%s %s", fmtNumber(remWeek), remainingSuffix), 0.5, 1, 0.5, false)
                    else
                        frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                    end
                end
            elseif hasSeasonProgress then
                local teForSeason = (teNum ~= nil) and teNum or 0
                local remSeason = math.max((seasonMax or 0) - teForSeason, 0)
                local br, bg, bb = TooltipBrightRGB()
                frame:AddLine(string.format("%s %s", currentLabel, fmtNumber(qty)), br, bg, bb)
                frame:AddLine(string.format("%s: %s / %s", seasonLabel, fmtNumber(teForSeason), fmtNumber(seasonMax or 0)), br, bg, bb, false)
                if remSeason > 0 then
                    frame:AddLine(string.format("%s %s", fmtNumber(remSeason), remainingSuffix), 0.5, 1, 0.5, false)
                else
                    frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                end
            else
                -- No season cap: single Current / max line + remaining (weekly-style cap only)
                local cap = maxQty
                local rem = math.max((cap or 0) - (qty or 0), 0)
                local br, bg, bb = TooltipBrightRGB()
                frame:AddLine(string.format("%s / %s", fmtNumber(qty), fmtNumber(cap or 0)), br, bg, bb, false)
                if rem > 0 then
                    frame:AddLine(string.format("%s %s", fmtNumber(rem), remainingSuffix), 0.5, 1, 0.5, false)
                else
                    frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                end
            end
        end
    end
    
    -- Add custom lines
    if data.additionalLines then
        frame:AddSpacer(8)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.text then
                local color = line.color or {0.6, 0.4, 0.8}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render hybrid tooltip (Blizzard + custom mixed)
]]
function TooltipService:RenderHybridTooltip(frame, data)
    -- First render Blizzard data
    if data.itemID then
        self:RenderItemTooltip(frame, data)
    elseif data.currencyID then
        self:RenderCurrencyTooltip(frame, data)
    end
    
    -- Then add custom lines (already handled in item/currency methods)
end

-- Tooltip offset constants (aligned with UI_SPACING.SIDE_MARGIN where possible)
local TOOLTIP_GAP = 8
local TOOLTIP_SCREEN_MARGIN = 8

local function RectsOverlap(aLeft, aRight, aTop, aBottom, bLeft, bRight, bTop, bBottom, pad)
    pad = pad or 0
    if not aLeft or not aRight or not aTop or not aBottom then return false end
    if not bLeft or not bRight or not bTop or not bBottom then return false end
    return not (
        (aRight + pad) < bLeft or
        (aLeft - pad) > bRight or
        (aTop + pad) < bBottom or
        (aBottom - pad) > bTop
    )
end

local function NormalizeTooltipAnchorPref(anchor)
    if not anchor or anchor == "ANCHOR_AUTO" then return "auto" end
    if anchor == "ANCHOR_LEFT" then return "left" end
    if anchor == "ANCHOR_TOP" then return "top" end
    if anchor == "ANCHOR_BOTTOM" then return "bottom" end
    return "right"
end

local function ResolveSideOrder(pref, aLeft, aRight, screenW)
    if pref == "left" then return { "left", "right" } end
    if pref == "right" then return { "right", "left" } end
    if pref == "top" or pref == "bottom" then return { "right", "left" } end
    local centerX = (aLeft + aRight) * 0.5
    if centerX < screenW * 0.55 then
        return { "right", "left" }
    end
    return { "left", "right" }
end

--- Build ranked placement candidates (Blizzard-style: side first with vertical center, then top/bottom).
local function BuildTooltipPlacementCandidates(pref, aLeft, aRight, screenW)
    local gap = TOOLTIP_GAP
    local out = {}
    local rank = 1

    local function push(point, relativePoint, x, y)
        out[#out + 1] = { point, relativePoint, x, y, rank = rank }
        rank = rank + 1
    end

    local function addSide(side)
        if side == "right" then
            push("LEFT", "RIGHT", gap, 0)
            push("TOPLEFT", "TOPRIGHT", gap, 0)
            push("BOTTOMLEFT", "BOTTOMRIGHT", gap, 0)
        else
            push("RIGHT", "LEFT", -gap, 0)
            push("TOPRIGHT", "TOPLEFT", -gap, 0)
            push("BOTTOMRIGHT", "BOTTOMLEFT", -gap, 0)
        end
    end

    local function addVertical(vert)
        if vert == "above" then
            push("BOTTOMLEFT", "TOPLEFT", 0, gap)
            push("BOTTOMRIGHT", "TOPRIGHT", 0, gap)
        else
            push("TOPLEFT", "BOTTOMLEFT", 0, -gap)
            push("TOPRIGHT", "BOTTOMRIGHT", 0, -gap)
        end
    end

    if pref == "top" then
        addVertical("above")
        addVertical("below")
        for i = 1, #ResolveSideOrder(pref, aLeft, aRight, screenW) do
            addSide(ResolveSideOrder(pref, aLeft, aRight, screenW)[i])
        end
    elseif pref == "bottom" then
        addVertical("below")
        addVertical("above")
        for i = 1, #ResolveSideOrder(pref, aLeft, aRight, screenW) do
            addSide(ResolveSideOrder(pref, aLeft, aRight, screenW)[i])
        end
    else
        local sides = ResolveSideOrder(pref, aLeft, aRight, screenW)
        addSide(sides[1])
        addSide(sides[2])
        addVertical("above")
        addVertical("below")
    end

    return out
end

--- Score a candidate: prefer low rank, no anchor overlap, minimal off-screen overflow.
local function ScoreTooltipPlacement(TooltipService, frame, anchorFrame, candidate, screenW, screenH, margin)
    frame:ClearAllPoints()
    frame:SetPoint(candidate[1], anchorFrame, candidate[2], candidate[3], candidate[4])
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom then
        return -1e9
    end
    local overflow = 0
    if right > screenW - margin then overflow = overflow + (right - screenW + margin) end
    if left < margin then overflow = overflow + (margin - left) end
    if top > screenH - margin then overflow = overflow + (top - screenH + margin) end
    if bottom < margin then overflow = overflow + (margin - bottom) end
    local overlap = TooltipService:IsOverlappingAnchor(frame, anchorFrame)
    local rankBonus = (20 - (candidate.rank or 20)) * 100
    if overlap then
        return rankBonus - 1e6 - overflow * 10
    end
    return rankBonus - overflow * 40
end

--- Pick the best on-screen placement for `frame` relative to `anchorFrame` (single pass, no post-show jump).
function TooltipService:ApplyBestTooltipPlacement(frame, anchorFrame, anchorPref, screenW, screenH)
    if not frame or not anchorFrame then return end
    screenW = screenW or GetScreenWidth()
    screenH = screenH or GetScreenHeight()
    local margin = TOOLTIP_SCREEN_MARGIN
    local aLeft, aRight = anchorFrame:GetLeft(), anchorFrame:GetRight()
    local aTop, aBottom = anchorFrame:GetTop(), anchorFrame:GetBottom()
    if not aLeft or not aRight or not aTop or not aBottom then
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", anchorFrame, "RIGHT", TOOLTIP_GAP, 0)
        self:ClampToScreen(frame, screenW, screenH)
        return
    end

    local pref = NormalizeTooltipAnchorPref(anchorPref)
    local candidates = BuildTooltipPlacementCandidates(pref, aLeft, aRight, screenW)
    local bestIdx = 1
    local bestScore = -1e9
    for i = 1, #candidates do
        local score = ScoreTooltipPlacement(self, frame, anchorFrame, candidates[i], screenW, screenH, margin)
        if score > bestScore then
            bestScore = score
            bestIdx = i
        end
    end

    local best = candidates[bestIdx]
    frame:ClearAllPoints()
    frame:SetPoint(best[1], anchorFrame, best[2], best[3], best[4])
    self:ClampToScreen(frame, screenW, screenH)

    if self:IsOverlappingAnchor(frame, anchorFrame) then
        for i = 1, #candidates do
            if i ~= bestIdx then
                local c = candidates[i]
                frame:ClearAllPoints()
                frame:SetPoint(c[1], anchorFrame, c[2], c[3], c[4])
                self:ClampToScreen(frame, screenW, screenH)
                if not self:IsOverlappingAnchor(frame, anchorFrame) then
                    return
                end
            end
        end
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP + 12)
        self:ClampToScreen(frame, screenW, screenH)
    end
end

function TooltipService:IsOverlappingAnchor(frame, anchorFrame)
    if not frame or not anchorFrame then return false end
    local fLeft = frame:GetLeft()
    local fRight = frame:GetRight()
    local fTop = frame:GetTop()
    local fBottom = frame:GetBottom()
    local aLeft = anchorFrame:GetLeft()
    local aRight = anchorFrame:GetRight()
    local aTop = anchorFrame:GetTop()
    local aBottom = anchorFrame:GetBottom()
    return RectsOverlap(fLeft, fRight, fTop, fBottom, aLeft, aRight, aTop, aBottom, 2)
end

function TooltipService:EnsureNoAnchorOverlap(frame, anchorFrame, anchor, screenW, screenH)
    if not frame or not anchorFrame then return end
    if not self:IsOverlappingAnchor(frame, anchorFrame) then return end
    self:ApplyBestTooltipPlacement(frame, anchorFrame, anchor, screenW, screenH)
end

--[[
    Position tooltip with smart screen-aware placement (score-based best candidate).
]]
function TooltipService:PositionTooltip(frame, anchorFrame, anchor)
    if anchor == "ANCHOR_CURSOR" then
        frame:ClearAllPoints()
        local screenW = GetScreenWidth()
        local screenH = GetScreenHeight()
        local tooltipW = frame:GetWidth()
        local tooltipH = frame:GetHeight()
        local scale = frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x = x / scale
        y = y / scale
        local finalX = x + 16
        local finalY = y + 4
        if finalX + tooltipW > screenW then finalX = x - tooltipW - 4 end
        if finalY + tooltipH > screenH then finalY = y - tooltipH - 4 end
        if finalX < 0 then finalX = 4 end
        if finalY < 0 then finalY = 4 end
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalX, finalY)
        return
    end

    self:ApplyBestTooltipPlacement(frame, anchorFrame, anchor)
end

function TooltipService:ClampToScreen(frame, screenW, screenH)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    
    if not left or not right or not top or not bottom then return end
    
    local margin = TOOLTIP_SCREEN_MARGIN
    local frameH = top - bottom
    local maxH = screenH - margin * 2

    -- Tall tooltips: pin top to screen margin so body stays reachable (no scroll host yet).
    if frameH > maxH and maxH > 0 then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(margin, left), screenH - margin)
        left = frame:GetLeft()
        right = frame:GetRight()
        top = frame:GetTop()
        bottom = frame:GetBottom()
        if not left or not right or not top or not bottom then return end
    end

    local dx, dy = 0, 0
    if right > screenW - margin then dx = (screenW - margin) - right end
    if left < margin then dx = margin - left end
    if top > screenH - margin then dy = (screenH - margin) - top end
    if bottom < margin then dy = margin - bottom end
    
    if dx ~= 0 or dy ~= 0 then
        local okPoint, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
        if okPoint and point and relativeTo then
            local okSet = pcall(function()
                frame:ClearAllPoints()
                frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + dx, (y or 0) + dy)
            end)
            if not okSet then return end
        end
    end
end

--- Re-run placement after theme/layout refresh while tooltip is visible.
function TooltipService:RepositionIfVisible(skipLayout)
    local frame = GetTooltipFrame()
    if not frame or not isVisible or not currentAnchor then return end
    if not skipLayout and frame.LayoutLines then
        frame:LayoutLines()
    end
    self:PositionTooltip(frame, currentAnchor, currentAnchorPref)
end

function TooltipService:RegisterSafetyEvents()
    -- PLAYER_REGEN_DISABLED: owned by Core.lua (OnCombatStart — hides main UI + tooltip)
    -- PLAYER_LEAVING_WORLD: use dedicated frame (avoids AceEvent collision)
    local safetyFrame = CreateFrame("Frame")
    safetyFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
    safetyFrame:SetScript("OnEvent", function()
        self:Hide()
    end)

    local function SafeDefer(fn)
        if type(fn) ~= "function" then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                pcall(fn)
            end)
        else
            pcall(fn)
        end
    end

    local GT = ns.TooltipGameTooltip
    if GT and GT.InstallGameTooltipOwnerHook then
        GT.InstallGameTooltipOwnerHook(self, SafeDefer)
    end
end


function TooltipService:Debug(msg)
    if WarbandNexus and WarbandNexus.Debug then
        WarbandNexus:Debug("[Tooltip] " .. msg)
    end
end

-- Attach to WarbandNexus namespace
local GT = ns.TooltipGameTooltip
assert(GT and GT.Install, "load TooltipService_GameTooltip.lua before TooltipService.lua")
GT.Install(TooltipService)

WarbandNexus.Tooltip = TooltipService

-- Export to ns for SharedWidgets access
ns.TooltipService = TooltipService

--- Enchant-only crafting tier (1–2) from tooltip scan; not item body GetCraftingQuality.
ns.UI_GetEnchantmentCraftingQualityTierFromItemLink = GetEnchantmentCraftingQualityTierFromItemLink

--- Crafting-quality tier from first matching line on item tooltip (socketed gems, etc.).
