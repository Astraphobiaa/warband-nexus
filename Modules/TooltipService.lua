--[[
    Warband Nexus - Tooltip Service Module
    Central tooltip management system
    
    Architecture:
    - Single reusable tooltip frame (lazy init)
    - Event-driven show/hide
    - Multiple tooltip types (custom, item, currency, hybrid)
    - Auto-hide on combat/world transitions
    
    API:
    WarbandNexus.Tooltip:Show(frame, data)
    WarbandNexus.Tooltip:Hide()
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS

-- Midnight 12.0: Secret Values API (nil on pre-12.0 clients, backward-compatible)
local issecretvalue = issecretvalue
-- Upvalue for GUID parsing in object tooltip hook
local strsplit = strsplit
local tonumber = tonumber

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

-- Singleton tooltip frame (lazy initialized)
local tooltipFrame = nil
local isVisible = false
local currentAnchor = nil
local isInitialized = false

-- Event names (single source: Constants.EVENTS)
local TOOLTIP_SHOW = E.TOOLTIP_SHOW
local TOOLTIP_HIDE = E.TOOLTIP_HIDE

-- ============================================================================
-- TOOLTIP SERVICE
-- ============================================================================

local TooltipService = {}

--[[
    Initialize tooltip service
    Creates the singleton frame and registers safety events
]]
function TooltipService:Initialize()
    if isInitialized then return end
    
    -- Lazy init: Create frame when first needed
    -- This is called explicitly from Core.lua
    self:Debug("TooltipService initialized")
    isInitialized = true
    
    -- Register safety events
    self:RegisterSafetyEvents()
end

--[[
    Get or create tooltip frame (lazy init)
]]
local function GetTooltipFrame()
    if not tooltipFrame and ns.UI and ns.UI.TooltipFactory then
        tooltipFrame = ns.UI.TooltipFactory:CreateTooltipFrame()
    end
    return tooltipFrame
end

--[[
    Validate tooltip data structure
    @param data table - Tooltip data
    @return boolean - Valid or not
]]
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

--[[
    Show tooltip
    @param anchorFrame Frame - Frame to anchor to
    @param data table - Tooltip data structure
]]
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
    
    -- Clear previous content
    frame:Clear()
    -- Optional wide tooltips (e.g. PvE vault summary); clamp to sane bounds for small resolutions
    if data.maxWidth and tonumber(data.maxWidth) then
        local mw = tonumber(data.maxWidth)
        frame.fixedWidth = math.max(260, math.min(mw, 820))
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
    
    -- Finalize layout (ensure size is correct even if no body lines were added)
    frame:LayoutLines()
    
    -- Position and show
    self:PositionTooltip(frame, anchorFrame, data.anchor or "ANCHOR_RIGHT")
    frame:Show()
    
    currentAnchor = anchorFrame
    isVisible = true
    
    -- Fire event (if AceEvent available)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_SHOW, data)
    end
end

--[[
    Hide tooltip
]]
function TooltipService:Hide()
    local frame = GetTooltipFrame()
    if not frame or not isVisible then 
        return 
    end
    
    frame:Clear()
    frame:Hide()
    
    currentAnchor = nil
    isVisible = false
    
    -- Fire event
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_HIDE)
    end
end

-- ============================================================================
-- ITEM LINK TOOLTIP CONTEXT (linkLevel + specializationID in payload)
-- Blizzard uses fields 9–10 of the item payload for primary-stat / set-bonus
-- display. Links from another character (e.g. bank alt) keep that character's
-- spec; rewrite so Gear tab tooltips match the viewed character.
-- See https://warcraft.wiki.gg/wiki/ItemLink (linkLevel, specializationID).
-- ============================================================================

---@param itemLink string|nil
---@param itemID number|nil
---@param linkLevel number
---@param specializationID number
---@return string|nil
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
---@param text string|nil
---@return string
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

---@param leftText string|nil
---@param rightText string|nil
---@return boolean
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

---@param line table|nil
---@return boolean
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

---@param n number|nil
---@return string|nil
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
---@param specID number
---@return string|nil
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

---@param leftText string|nil
---@param rightText string|nil
---@return string
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
---@param plain string
---@return string|nil "strength"|"agility"|"intellect"
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
---@param line table TooltipDataLine (mutated)
---@param ctx table itemTooltipContext { specID, level }
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
        line.leftColor = { r = 1, g = 1, b = 1 }
        line.rightColor = { r = 1, g = 1, b = 1 }
    else
        line.leftColor = { r = 0.65, g = 0.65, b = 0.65 }
        line.rightColor = { r = 0.65, g = 0.65, b = 0.65 }
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

-- ============================================================================
-- RENDERING METHODS
-- ============================================================================

--[[
    Render custom tooltip with structured data
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
]]
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
        local tr, tg, tb = 1, 0.82, 0
        if data.titleColor then
            tr, tg, tb = data.titleColor[1], data.titleColor[2], data.titleColor[3]
        end
        frame:SetTitle(data.title, tr, tg, tb)
    end
    
    -- 3) Description (below title, optional)
    if data.description then
        local dr, dg, db = 0.8, 0.8, 0.8
        if data.descriptionColor then
            dr, dg, db = data.descriptionColor[1], data.descriptionColor[2], data.descriptionColor[3]
        end
        frame:SetDescription(data.description, dr, dg, db)
    end
    
    -- 4) Data lines
    if data.lines then
        for _, line in ipairs(data.lines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                local leftColor = line.leftColor or {1, 1, 1}
                local rightColor = line.rightColor or {1, 1, 1}
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
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
            elseif line.left then
                local leftColor = line.leftColor or {1, 1, 1}
                frame:AddLine(line.left, leftColor[1], leftColor[2], leftColor[3], line.wrap or false)
            elseif line.text then
                local color = line.color or {1, 1, 1}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render item tooltip using C_TooltipInfo (full Blizzard data in our custom frame)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data {itemID, itemLink, additionalLines}
]]
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
                    frame:AddDoubleLine(leftText or "", rightText, lr, lg, lb, rr, rg, rb)
                else
                    -- Single line
                    local lr, lg, lb = 1, 1, 1
                    if line.leftColor then
                        lr = line.leftColor.r or 1
                        lg = line.leftColor.g or 1
                        lb = line.leftColor.b or 1
                    end
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
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading details...", 0.7, 0.7, 0.7)
        else
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading...", 0.7, 0.7, 0.7)
        end
    end
    
    -- Additional custom lines (Item ID, stack count, location, instructions, etc.)
    if data.additionalLines then
        frame:AddSpacer(4)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                local leftColor = line.leftColor or {1, 1, 1}
                local rightColor = line.rightColor or {1, 1, 1}
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
                )
            elseif line.text then
                local color = line.color or {0.6, 0.4, 0.8}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Return tooltip stat lines for an item (for use under profession equipment in custom tooltips).
    Skips title line; returns left/right lines with colors. Safe for secret values (Midnight).
    @param itemLink string|nil - Item hyperlink (preferred)
    @param itemID number|nil - Item ID fallback when itemLink is nil
    @return table - Array of { left, right, leftColor, rightColor }
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
            local leftColor = lc and { lc.r or 1, lc.g or 1, lc.b or 1 } or { 0.85, 0.85, 0.85 }
            local rightColor = rc and { rc.r or 1, rc.g or 1, rc.b or 1 } or { 0.75, 0.75, 0.75 }
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
    @param itemLink string|nil
    @param itemID number|nil
    @param slotKey string "tool" | "accessory1" | "accessory2"
    @return table - Array of { left, right, leftColor, rightColor }
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
    out[1] = { left = slotLabel, right = "", leftColor = {0.7, 0.7, 0.9}, rightColor = {0.75, 0.75, 0.75} }

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
                    out[#out + 1] = {
                        left = left,
                        right = right,
                        leftColor = lc and { lc.r or 1, lc.g or 1, lc.b or 1 } or { 0.85, 0.85, 0.85 },
                        rightColor = rc and { rc.r or 1, rc.g or 1, rc.b or 1 } or { 0.75, 0.75, 0.75 },
                    }
                end
            end
        end
    end
    return out
end

--[[
    Render currency tooltip (Blizzard data + custom additions)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
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
    frame:SetTitle(info.name, 1, 0.82, 0)
    
    -- 3) Description
    if info.description and info.description ~= "" then
        frame:SetDescription(info.description, 1, 1, 1)
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
                frame:AddLine(string.format("%s %s", currentLabel, fmtNumber(qty)), 1, 1, 1, false)
                if wCap > 0 then
                    frame:AddLine(string.format("%s: %s / %s", weeklyLabel, fmtNumber(teForWeek), fmtNumber(wCap)), 1, 1, 1, false)
                    if remWeek > 0 then
                        frame:AddLine(string.format("%s %s", fmtNumber(remWeek), remainingSuffix), 0.5, 1, 0.5, false)
                    else
                        frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                    end
                end
            elseif hasSeasonProgress then
                local teForSeason = (teNum ~= nil) and teNum or 0
                local remSeason = math.max((seasonMax or 0) - teForSeason, 0)
                frame:AddLine(string.format("%s %s", currentLabel, fmtNumber(qty)), 1, 1, 1, false)
                frame:AddLine(string.format("%s: %s / %s", seasonLabel, fmtNumber(teForSeason), fmtNumber(seasonMax or 0)), 1, 1, 1, false)
                if remSeason > 0 then
                    frame:AddLine(string.format("%s %s", fmtNumber(remSeason), remainingSuffix), 0.5, 1, 0.5, false)
                else
                    frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                end
            else
                -- No season cap: single Current / max line + remaining (weekly-style cap only)
                local cap = maxQty
                local rem = math.max((cap or 0) - (qty or 0), 0)
                frame:AddLine(string.format("%s / %s", fmtNumber(qty), fmtNumber(cap or 0)), 1, 1, 1, false)
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
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
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

-- ============================================================================
-- POSITIONING
-- ============================================================================

-- Tooltip offset constants
-- Tooltip gap from anchor
local TOOLTIP_GAP = 8

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

    local gap = TOOLTIP_GAP
    local candidates
    if anchor == "ANCHOR_LEFT" then
        candidates = {
            {"TOPRIGHT", "TOPLEFT", -gap, 0},
            {"BOTTOMRIGHT", "BOTTOMLEFT", -gap, 0},
            {"TOPLEFT", "TOPRIGHT", gap, 0},
            {"BOTTOMLEFT", "BOTTOMRIGHT", gap, 0},
            {"BOTTOMLEFT", "TOPLEFT", 0, gap},
            {"TOPLEFT", "BOTTOMLEFT", 0, -gap},
        }
    elseif anchor == "ANCHOR_TOP" then
        candidates = {
            {"BOTTOMLEFT", "TOPLEFT", 0, gap},
            {"BOTTOMRIGHT", "TOPRIGHT", 0, gap},
            {"TOPLEFT", "BOTTOMLEFT", 0, -gap},
            {"TOPRIGHT", "BOTTOMRIGHT", 0, -gap},
            {"TOPLEFT", "TOPRIGHT", gap, 0},
            {"TOPRIGHT", "TOPLEFT", -gap, 0},
        }
    elseif anchor == "ANCHOR_BOTTOM" then
        candidates = {
            {"TOPLEFT", "BOTTOMLEFT", 0, -gap},
            {"TOPRIGHT", "BOTTOMRIGHT", 0, -gap},
            {"BOTTOMLEFT", "TOPLEFT", 0, gap},
            {"BOTTOMRIGHT", "TOPRIGHT", 0, gap},
            {"TOPLEFT", "TOPRIGHT", gap, 0},
            {"TOPRIGHT", "TOPLEFT", -gap, 0},
        }
    else
        candidates = {
            {"TOPLEFT", "TOPRIGHT", gap, 0},
            {"BOTTOMLEFT", "BOTTOMRIGHT", gap, 0},
            {"TOPRIGHT", "TOPLEFT", -gap, 0},
            {"BOTTOMRIGHT", "BOTTOMLEFT", -gap, 0},
            {"BOTTOMLEFT", "TOPLEFT", 0, gap},
            {"TOPLEFT", "BOTTOMLEFT", 0, -gap},
        }
    end

    for i = 1, #candidates do
        local c = candidates[i]
        frame:ClearAllPoints()
        frame:SetPoint(c[1], anchorFrame, c[2], c[3], c[4])
        self:ClampToScreen(frame, screenW, screenH)
        if not self:IsOverlappingAnchor(frame, anchorFrame) then
            return
        end
    end

    -- Final fallback: force above/below with larger gap.
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, gap + 12)
    self:ClampToScreen(frame, screenW, screenH)
    if self:IsOverlappingAnchor(frame, anchorFrame) then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -(gap + 12))
        self:ClampToScreen(frame, screenW, screenH)
    end
end

--[[
    Position tooltip with smart screen-aware placement.
    Tries the requested anchor first; if it goes off-screen, flips to the opposite side.
    @param frame Frame - Tooltip frame
    @param anchorFrame Frame - Anchor frame
    @param anchor string - Preferred anchor point
]]
function TooltipService:PositionTooltip(frame, anchorFrame, anchor)
    frame:ClearAllPoints()
    
    -- Get screen dimensions
    local screenW = GetScreenWidth()
    local screenH = GetScreenHeight()
    local tooltipW = frame:GetWidth()
    local tooltipH = frame:GetHeight()
    
    -- Get anchor frame bounds
    local aLeft = anchorFrame:GetLeft() or 0
    local aRight = anchorFrame:GetRight() or 0
    local aTop = anchorFrame:GetTop() or 0
    local aBottom = anchorFrame:GetBottom() or 0
    
    if anchor == "ANCHOR_CURSOR" then
        -- Follow cursor
        local scale = frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x = x / scale
        y = y / scale
        local finalX = x + 16
        local finalY = y + 4
        -- Flip if off-screen
        if finalX + tooltipW > screenW then finalX = x - tooltipW - 4 end
        if finalY + tooltipH > screenH then finalY = y - tooltipH - 4 end
        if finalX < 0 then finalX = 4 end
        if finalY < 0 then finalY = 4 end
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalX, finalY)
        return
    end
    
    -- Smart placement: try preferred side, then opposite side.
    -- If neither side has enough room (wide row anchors), fall back to top/bottom
    -- so tooltip does not get clamped over the hovered row/cursor area.
    if anchor == "ANCHOR_RIGHT" or anchor == nil then
        local canRight = (aRight + TOOLTIP_GAP + tooltipW <= screenW)
        local canLeft = (aLeft - TOOLTIP_GAP - tooltipW >= 0)
        if canRight then
            frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
        elseif canLeft then
            frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -TOOLTIP_GAP, 0)
        elseif aTop + TOOLTIP_GAP + tooltipH <= screenH then
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        else
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        end
    elseif anchor == "ANCHOR_LEFT" then
        local canLeft = (aLeft - TOOLTIP_GAP - tooltipW >= 0)
        local canRight = (aRight + TOOLTIP_GAP + tooltipW <= screenW)
        if canLeft then
            frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -TOOLTIP_GAP, 0)
        elseif canRight then
            frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
        elseif aTop + TOOLTIP_GAP + tooltipH <= screenH then
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        else
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        end
    elseif anchor == "ANCHOR_TOP" then
        if aTop + TOOLTIP_GAP + tooltipH <= screenH then
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        else
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        end
    elseif anchor == "ANCHOR_BOTTOM" then
        if aBottom - TOOLTIP_GAP - tooltipH >= 0 then
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        else
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        end
    else
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
    end
    
    -- Final clamp: ensure tooltip stays fully on-screen
    self:ClampToScreen(frame, screenW, screenH)
    self:EnsureNoAnchorOverlap(frame, anchorFrame, anchor, screenW, screenH)
end

--[[
    Clamp tooltip frame to stay within screen boundaries.
    Adjusts position if any edge extends beyond the screen.
]]
function TooltipService:ClampToScreen(frame, screenW, screenH)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    
    if not left or not right or not top or not bottom then return end
    
    local dx, dy = 0, 0
    local margin = 4
    
    if right > screenW - margin then dx = (screenW - margin) - right end
    if left < margin then dx = margin - left end
    if top > screenH - margin then dy = (screenH - margin) - top end
    if bottom < margin then dy = margin - bottom end
    
    if dx ~= 0 or dy ~= 0 then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if point and relativeTo then
            frame:ClearAllPoints()
            frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + dx, (y or 0) + dy)
        end
    end
end

-- ============================================================================
-- SAFETY & AUTO-HIDE
-- ============================================================================

--[[
    Register events that should auto-hide tooltip
]]
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

    local function IsWarbandNexusOwner(owner)
        if not owner then return false end
        local mainFrame = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local cur = owner
        for _ = 1, 20 do
            if not cur then break end
            if cur == mainFrame then return true end
            if type(cur.GetParent) == "function" then
                cur = cur:GetParent()
            else
                break
            end
        end
        local n = (type(owner.GetName) == "function") and owner:GetName() or nil
        if n and n:find("WarbandNexus", 1, true) then
            return true
        end
        return false
    end

    local ownerAdjustQueued = setmetatable({}, { __mode = "k" })

    if not self._gameTooltipOwnerHooked and hooksecurefunc and GameTooltip then
        self._gameTooltipOwnerHooked = true
        hooksecurefunc(GameTooltip, "SetOwner", function(tooltip, owner, anchor)
            if tooltip ~= GameTooltip then return end
            if not owner then return end
            if anchor == "ANCHOR_CURSOR" then return end
            if not IsWarbandNexusOwner(owner) then return end
            if ownerAdjustQueued[owner] then return end
            ownerAdjustQueued[owner] = true
            SafeDefer(function()
                ownerAdjustQueued[owner] = nil
                if not GameTooltip or not GameTooltip:IsShown() then return end
                if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= owner then return end
                if type(owner.GetLeft) ~= "function" or type(owner.GetRight) ~= "function" then return end
                local sw, sh = GetScreenWidth(), GetScreenHeight()
                TooltipService:EnsureNoAnchorOverlap(GameTooltip, owner, anchor or "ANCHOR_RIGHT", sw, sh)
            end)
        end)
    end
end

-- ============================================================================
-- SHARED COLLECTIBLE DROP LINES (used by Unit and Item tooltip hooks)
-- ============================================================================

---Inject collectible drop lines into a GameTooltip.
---Shows header, item hyperlinks, collected/repeatable status, and try counts.
---Shared across NPC (Unit) and Container (Item) tooltip hooks.
---@param tooltip Frame GameTooltip or compatible tooltip frame
---@param drops table Array of drop entries { type, itemID, name [, guaranteed] [, repeatable] }
---@param npcID number|nil Optional NPC ID for lockout quest checking
local function InjectCollectibleDropLines(tooltip, drops, npcID)
    if not drops or #drops == 0 then return end

    local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local sourceDB = ns.CollectibleSourceDB

    -- Check daily/weekly lockout status for this NPC
    local isLockedOut = false
    if npcID and sourceDB and sourceDB.lockoutQuests then
        local questData = sourceDB.lockoutQuests[npcID]
        if questData then
            local questIDs = type(questData) == "table" and questData or { questData }
            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                for qi = 1, #questIDs do
                    if C_QuestLog.IsQuestFlaggedCompleted(questIDs[qi]) then
                        isLockedOut = true
                        break
                    end
                end
            end
        end
    end

    -- Spacer before drop lines
    tooltip:AddLine(" ")

    -- When locked out (already killed this period), show why drops are gray
    if isLockedOut then
        local lockoutHint = (ns.L and ns.L["TOOLTIP_NO_LOOT_UNTIL_RESET"]) or "No loot until next reset"
        tooltip:AddLine("|cff666666" .. lockoutHint .. "|r", 0.6, 0.6, 0.6)
    end

    for i = 1, #drops do
        local drop = drops[i]

        -- Get item hyperlink (quality-colored, bracketed)
        local _, itemLink
        if GetItemInfo then
            _, itemLink = GetItemInfo(drop.itemID)
        end
        if not itemLink then
            -- Item not cached yet — queue for next hover, use DB name as fallback
            if C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
            end
            -- Mounts: epic (purple); others: legacy orange fallback
            local fallbackColor = (drop.type == "mount") and "a335ee" or "ff8000"
            itemLink = "|cff" .. fallbackColor .. "[" .. (drop.name or ((ns.L and ns.L["TOOLTIP_UNKNOWN"]) or "Unknown")) .. "]|r"
        elseif drop.type == "mount" then
            -- Force epic (purple) for mount names in tooltip
            itemLink = itemLink:gsub("^|c%x%x%x%x%x%x%x%x%x", "|cffa335ee")
        end

        -- Collection status check
        local collected = false
        local collectibleID = nil

        if drop.type == "item" then
            -- Generic items (e.g. Miscellaneous Mechanica): collectibleID == itemID, never "collected"
            collectibleID = drop.itemID
            collected = false
            
            -- QUEST STARTER HANDLING: If this item starts a quest for a mount/pet/toy,
            -- check if the FINAL collectible is already obtained
            if drop.questStarters and #drop.questStarters > 0 then
                local questReward = drop.questStarters[1]
                if questReward and questReward.type then
                    if questReward.type == "mount" then
                        if C_MountJournal and C_MountJournal.GetMountFromItem then
                            local mountID = C_MountJournal.GetMountFromItem(questReward.itemID)
                            if issecretvalue and mountID and issecretvalue(mountID) then
                                mountID = nil
                            end
                            if mountID then
                                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                                if not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                                    collected = isCollected == true
                                end
                            end
                        end
                    elseif questReward.type == "pet" then
                        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(questReward.itemID)
                            if issecretvalue and specID and issecretvalue(specID) then
                                specID = nil
                            end
                            if specID then
                                local numCollected = C_PetJournal.GetNumCollectedInfo(specID)
                                if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                                    collected = numCollected and numCollected > 0
                                end
                            end
                        end
                    elseif questReward.type == "toy" then
                        if PlayerHasToy then
                            local hasToy = PlayerHasToy(questReward.itemID)
                            if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                                collected = hasToy == true
                            end
                        end
                    end
                end
            end
        elseif drop.type == "mount" then
            if C_MountJournal and C_MountJournal.GetMountFromItem then
                collectibleID = C_MountJournal.GetMountFromItem(drop.itemID)
                -- Midnight 12.0: GetMountFromItem can return secret value; still check collected via pcall
                if collectibleID then
                    local ok, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, collectibleID)
                    if ok and isCollected and not (issecretvalue and issecretvalue(isCollected)) then
                        collected = isCollected == true
                    end
                    if issecretvalue and issecretvalue(collectibleID) then
                        collectibleID = nil  -- do not use secret as key for try count / display
                    end
                end
            end
        elseif drop.type == "pet" then
            if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                -- speciesID is the 13th return value, NOT the 1st (which is pet name)
                local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                collectibleID = specID
                if collectibleID then
                    local ok, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, collectibleID)
                    if ok and numCollected and not (issecretvalue and issecretvalue(numCollected)) then
                        collected = numCollected > 0
                    end
                    if issecretvalue and issecretvalue(specID) then
                        collectibleID = nil
                    end
                end
            end
        elseif drop.type == "toy" then
            if PlayerHasToy then
                local hasToy = PlayerHasToy(drop.itemID)
                if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                    collected = hasToy == true
                end
            end
        end

        -- DB may tag teachable collectibles as generic "item"; align collected with journal/toy APIs
        if drop.type == "item" and not collected and drop.itemID then
            if PlayerHasToy then
                local okToy, hasToy = pcall(PlayerHasToy, drop.itemID)
                if okToy and hasToy == true and not (issecretvalue and issecretvalue(hasToy)) then
                    collected = true
                end
            end
            if not collected and C_MountJournal and C_MountJournal.GetMountFromItem then
                local okMid, mid = pcall(C_MountJournal.GetMountFromItem, drop.itemID)
                if okMid and mid and mid > 0 and not (issecretvalue and issecretvalue(mid)) then
                    local ok2, _, _, _, _, _, _, _, _, _, _, isColl = pcall(C_MountJournal.GetMountInfoByID, mid)
                    if ok2 and isColl == true and not (issecretvalue and issecretvalue(isColl)) then
                        collected = true
                    end
                end
            end
            if not collected and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                local ok1, _, _, _, _, _, _, _, _, _, _, _, specID = pcall(C_PetJournal.GetPetInfoByItemID, drop.itemID)
                if ok1 and specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                    local ok2, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, specID)
                    if ok2 and numCollected and not (issecretvalue and issecretvalue(numCollected)) and numCollected > 0 then
                        collected = true
                    end
                end
            end
        end

        -- Check repeatable and guaranteed flags
        -- If the DB sets repeatable explicitly (true/false), honor it — do not override with global index
        -- (avoids wrong "Repeatable" UI when another source or stale index disagrees).
        local isRepeatable = drop.repeatable
        local isGuaranteed = drop.guaranteed
        if not isGuaranteed and WarbandNexus and WarbandNexus.IsGuaranteedCollectible then
            isGuaranteed = WarbandNexus:IsGuaranteedCollectible(drop.type, collectibleID or drop.itemID)
        end
        if isRepeatable == nil and WarbandNexus and WarbandNexus.IsRepeatableCollectible then
            isRepeatable = WarbandNexus:IsRepeatableCollectible(drop.type, collectibleID or drop.itemID)
        end

        -- Try count (do not show for 100% guaranteed drops or when module disabled)
        local tryCount = 0
        local tryCounterEnabled = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
            and (not WarbandNexus.db.profile.modulesEnabled or WarbandNexus.db.profile.modulesEnabled.tryCounter ~= false)
        if tryCounterEnabled and not isGuaranteed and WarbandNexus and WarbandNexus.GetTryCount then
            if collectibleID then
                tryCount = WarbandNexus:GetTryCount(drop.type, collectibleID)
            end
            if tryCount == 0 then
                tryCount = WarbandNexus:GetTryCount(drop.type, drop.itemID)
            end
        end

        -- Build right-side status text
        -- Collected items: green checkmark prepended to item name, no right text.
        -- Repeatable items: always show try counter on the right.
        -- Locked out: everything gray.
        local rightText
        -- (showCollectedLine removed — checkmark is inline with item name)
        local attemptsWord = (ns.L and ns.L["TOOLTIP_ATTEMPTS"]) or "attempts"
        -- collectedWord removed — replaced by inline checkmark icon
        local guaranteedWord = (ns.L and ns.L["TOOLTIP_100_DROP"]) or "100% Drop"
        if isRepeatable then
            local attemptsColor = isLockedOut and "666666" or "ffff00"
            rightText = "|cff" .. attemptsColor .. tryCount .. " " .. attemptsWord .. "|r"
            -- collected status is shown via inline checkmark on the item line
        elseif isLockedOut and not collected then
            local attemptsColor = isLockedOut and "666666" or "888888"
            rightText = "|cff" .. attemptsColor .. tryCount .. " " .. attemptsWord .. "|r"
        elseif collected then
            rightText = ""
        elseif isGuaranteed then
            rightText = "|cff00ff00" .. guaranteedWord .. "|r"
        elseif tryCount > 0 then
            rightText = "|cffffff00" .. tryCount .. " " .. attemptsWord .. "|r"
        else
            -- Default 0 when no try count (non-repeatable, not collected, not guaranteed)
            rightText = "|cff8888880 " .. attemptsWord .. "|r"
        end

        -- When locked out and not collected, dim the item link to gray
        local displayLink = itemLink
        if isLockedOut and not collected then
            local plainName = drop.name or ((ns.L and ns.L["TOOLTIP_UNKNOWN"]) or "Unknown")
            if itemLink and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
                local linkName = itemLink:match("%[(.-)%]")
                if linkName then plainName = linkName end
            end
            displayLink = "|cff666666[" .. plainName .. "]|r"
        end

        -- Prepend green checkmark for collected items (inline texture for reliable rendering)
        if collected then
            displayLink = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t " .. displayLink
        end

        -- Append yellow (Planned) for items in the player's Plans list
        local isPlanned = false
        if WarbandNexus then
            if drop.type == "mount" and collectibleID and WarbandNexus.IsMountPlanned then
                isPlanned = WarbandNexus:IsMountPlanned(collectibleID)
            elseif drop.type == "pet" and collectibleID and WarbandNexus.IsPetPlanned then
                isPlanned = WarbandNexus:IsPetPlanned(collectibleID)
            elseif (drop.type == "toy" or drop.type == "item") and drop.itemID and WarbandNexus.IsItemPlanned then
                isPlanned = WarbandNexus:IsItemPlanned(drop.type, drop.itemID)
            end
        end
        if isPlanned and not collected then
            local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
            displayLink = displayLink .. " |cffffcc00(" .. plannedWord .. ")|r"
        end

        tooltip:AddDoubleLine(
            displayLink,
            rightText,
            1, 1, 1,  -- left color (overridden by hyperlink color codes)
            1, 1, 1   -- right color (overridden by inline color codes)
        )

        -- Show yields below item-type drops (e.g. Crackling Shard → Alunira)
        if drop.yields then
            for _, yield in ipairs(drop.yields) do
                local yieldCollected = false
                if yield.type == "mount" and yield.itemID then
                    if C_MountJournal and C_MountJournal.GetMountFromItem then
                        local okMid, mountID = pcall(C_MountJournal.GetMountFromItem, yield.itemID)
                        if okMid and mountID and not (issecretvalue and issecretvalue(mountID)) then
                            local okInfo, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
                            if okInfo and not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                                yieldCollected = isCollected == true
                            end
                        end
                    end
                elseif yield.type == "pet" and yield.itemID then
                    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                        local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(yield.itemID)
                        if specID and not (issecretvalue and issecretvalue(specID)) then
                            local numCollected = C_PetJournal.GetNumCollectedInfo(specID)
                            if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                                yieldCollected = numCollected and numCollected > 0
                            end
                        end
                    end
                elseif yield.type == "toy" and yield.itemID then
                    if PlayerHasToy then
                        local hasToy = PlayerHasToy(yield.itemID)
                        if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                            yieldCollected = hasToy == true
                        end
                    end
                end

                -- Check if yield is planned
                local yieldPlanned = false
                if WarbandNexus then
                    if yield.type == "mount" and yield.itemID and WarbandNexus.IsMountPlanned then
                        local yMountID = C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(yield.itemID)
                        if yMountID and not (issecretvalue and issecretvalue(yMountID)) then
                            yieldPlanned = WarbandNexus:IsMountPlanned(yMountID)
                        end
                    elseif yield.type == "pet" and yield.itemID and WarbandNexus.IsPetPlanned then
                        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, ySpecID = C_PetJournal.GetPetInfoByItemID(yield.itemID)
                            if ySpecID and not (issecretvalue and issecretvalue(ySpecID)) then
                                yieldPlanned = WarbandNexus:IsPetPlanned(ySpecID)
                            end
                        end
                    elseif yield.type == "toy" and yield.itemID and WarbandNexus.IsItemPlanned then
                        yieldPlanned = WarbandNexus:IsItemPlanned("toy", yield.itemID)
                    end
                end

                local yieldIcon = yieldCollected
                    and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
                    or  "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                local yieldColor = yieldCollected and "ff00ff00" or "ff999999"
                local typeLabel = yield.type == "mount" and "Mount"
                    or yield.type == "pet" and "Pet"
                    or yield.type == "toy" and "Toy"
                    or ""
                local yieldSuffix = ""
                if yieldPlanned and not yieldCollected then
                    local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                    yieldSuffix = " |cffffcc00(" .. plannedWord .. ")|r"
                end
                tooltip:AddLine(
                    "   " .. yieldIcon .. " |c" .. yieldColor .. yield.name .. " (" .. typeLabel .. ")|r" .. yieldSuffix,
                    1, 1, 1
                )
            end
        end
    end

    tooltip:Show()
end

-- ============================================================================
-- ITEM DATA PRE-CACHE (eliminates first-hover tooltip delay)
-- ============================================================================

--[[
    Pre-request all item data from CollectibleSourceDB so that GetItemInfo
    returns instantly when the user hovers over an NPC / container / object.
    Without this, the first hover triggers an async server request and the
    tooltip renders with a fallback name instead of a quality-colored link.
    Batched over multiple frames to avoid FPS spikes.
]]
function TooltipService:PreCacheCollectibleItems()
    local sourceDB = ns.CollectibleSourceDB
    if not sourceDB then return end

    local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID
    if not RequestLoad then return end

    -- Collect unique item IDs from all source tables
    local itemIDs = {}
    local seen = {}
    local function Collect(tbl)
        if not tbl then return end
        for _, drops in pairs(tbl) do
            if type(drops) == "table" then
                for i = 1, #drops do
                    local d = drops[i]
                    if d and d.itemID and not seen[d.itemID] then
                        seen[d.itemID] = true
                        itemIDs[#itemIDs + 1] = d.itemID
                    end
                end
            end
        end
    end

    Collect(sourceDB.npcs)
    Collect(sourceDB.containers)
    Collect(sourceDB.objects)
    Collect(sourceDB.fishing)

    if #itemIDs == 0 then return end

    -- Batch-request: 20 items per frame tick to stay under budget
    local BATCH_SIZE = 20
    local idx = 1
    local function ProcessBatch()
        local batchEnd = math.min(idx + BATCH_SIZE - 1, #itemIDs)
        for i = idx, batchEnd do
            pcall(RequestLoad, itemIDs[i])
        end
        idx = batchEnd + 1
        if idx <= #itemIDs then
            C_Timer.After(0, ProcessBatch)
        else
            self:Debug("Pre-cached " .. #itemIDs .. " collectible item IDs for tooltip readiness")
        end
    end

    ProcessBatch()
end

-- ============================================================================
-- GAME TOOLTIP INJECTION (TAINT-SAFE)
-- ============================================================================

--[[
    Initialize GameTooltip hook for item count display
    Uses TooltipDataProcessor (TWW API) - TAINT-SAFE
    Shows item counts across all characters + total
]]
function TooltipService:InitializeGameTooltipHook()
    -- Modern TWW API (taint-safe)
    if not TooltipDataProcessor then
        self:Debug("TooltipDataProcessor not available - tooltip injection disabled")
        return
    end

    -- ================================================================
    -- ITEM TOOLTIP HANDLER — WN Search counts per character
    -- ================================================================
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile) then
            return
        end
        local showTooltipItemCount = WarbandNexus.db.profile.showTooltipItemCount
        if showTooltipItemCount == nil then
            -- Backward compatibility for older profiles that only had showItemCount.
            showTooltipItemCount = WarbandNexus.db.profile.showItemCount
        end
        if not showTooltipItemCount then
            return
        end
        if not tooltip or not tooltip.AddLine or not tooltip.AddDoubleLine then return end

        local itemID = data and data.id
        if not itemID then return end

        local ok, err = pcall(function()
            local details = WarbandNexus:GetDetailedItemCountsFast(itemID)
            if not details then return end

            local total = details.warbandBank or 0
            for i = 1, #details.characters do
                total = total + details.characters[i].bagCount + details.characters[i].bankCount
            end
            if total == 0 then return end

            tooltip:AddLine(" ")
            tooltip:AddLine((ns.L and ns.L["WN_SEARCH"]) or "WN Search", 0.4, 0.8, 1, 1)

            -- Atlas markup for storage type icons (uniform 16x16)
            local bagIcon     = CreateAtlasMarkup and CreateAtlasMarkup("Banker", 16, 16) or ""
            local bankIcon    = CreateAtlasMarkup and CreateAtlasMarkup("VignetteLoot", 16, 16) or ""
            local warbandIcon = CreateAtlasMarkup and CreateAtlasMarkup("warbands-icon", 16, 16) or ""

            if details.warbandBank > 0 then
                tooltip:AddDoubleLine(
                    warbandIcon .. " " .. ((ns.L and ns.L["TOOLTIP_WARBAND_BANK"]) or "Warband Bank"),
                    "x" .. details.warbandBank,
                    0.8, 0.8, 0.8, 0.3, 0.9, 0.3
                )
            end

            if #details.characters > 0 then
                local isShift = IsShiftKeyDown()
                local maxShow = isShift and 999 or 5
                local shown = 0

                for i = 1, #details.characters do
                    if shown >= maxShow then break end
                    local char = details.characters[i]
                    -- Only show characters that actually have this item
                    if char.bankCount > 0 or char.bagCount > 0 then
                        local cc = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }
                        if char.bankCount > 0 then
                            tooltip:AddDoubleLine(
                                bankIcon .. " " .. char.charName,
                                "x" .. char.bankCount,
                                cc.r, cc.g, cc.b, 0.3, 0.9, 0.3
                            )
                        end
                        if char.bagCount > 0 then
                            tooltip:AddDoubleLine(
                                bagIcon .. " " .. char.charName,
                                "x" .. char.bagCount,
                                cc.r, cc.g, cc.b, 0.3, 0.9, 0.3
                            )
                        end
                        shown = shown + 1
                    end
                end

                if not isShift and #details.characters > 5 then
                    tooltip:AddLine((ns.L and ns.L["TOOLTIP_HOLD_SHIFT"]) or "  Hold [Shift] for full list", 0.5, 0.5, 0.5)
                end
            end

            local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
            tooltip:AddDoubleLine(totalLabel .. ":", "x" .. total, 1, 0.82, 0, 1, 1, 1)
            tooltip:Show()
        end)

        if not ok and WarbandNexus.Debug then
            WarbandNexus:Debug("[Tooltip] Item PostCall error for itemID " .. tostring(itemID) .. ": " .. tostring(err))
        end
    end)

    -- ================================================================
    -- ITEM TOOLTIP: "(Planned)" indicator for items in the Plans list
    -- Checks mount/pet/toy/item plans and appends yellow text
    -- ================================================================
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not WarbandNexus then return end
        if not tooltip or not tooltip.AddLine then return end

        local itemID = data and data.id
        if not itemID then return end

        -- True if this item grants a toy/mount/pet the player already owns (hide "(Planned)" when complete)
        local function ItemTooltipCollectibleOwned(id)
            if not id then return false end
            if PlayerHasToy then
                local okToy, hasToy = pcall(PlayerHasToy, id)
                if okToy and hasToy == true and not (issecretvalue and issecretvalue(hasToy)) then
                    return true
                end
            end
            if C_MountJournal and C_MountJournal.GetMountFromItem then
                local ok1, mountID = pcall(C_MountJournal.GetMountFromItem, id)
                if ok1 and mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                    local ok2, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
                    if ok2 and isCollected == true and not (issecretvalue and issecretvalue(isCollected)) then
                        return true
                    end
                end
            end
            if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                local ok1, _, _, _, _, _, _, _, _, _, _, _, specID = pcall(C_PetJournal.GetPetInfoByItemID, id)
                if ok1 and specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                    local ok2, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, specID)
                    if ok2 and numCollected and not (issecretvalue and issecretvalue(numCollected)) and numCollected > 0 then
                        return true
                    end
                end
            end
            return false
        end

        local planned = false

        -- Check direct itemID (covers toys, generic items, any plan with itemID)
        if not planned and WarbandNexus.IsItemPlanned then
            planned = WarbandNexus:IsItemPlanned(nil, itemID)
        end

        -- Check mount (itemID → mountID)
        if not planned and WarbandNexus.IsMountPlanned
            and C_MountJournal and C_MountJournal.GetMountFromItem then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            if mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                planned = WarbandNexus:IsMountPlanned(mountID)
            end
        end

        -- Check pet (itemID → speciesID)
        if not planned and WarbandNexus.IsPetPlanned
            and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(itemID)
            if specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                planned = WarbandNexus:IsPetPlanned(specID)
            end
        end

        if planned and not ItemTooltipCollectibleOwned(itemID) then
            local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
            tooltip:AddLine("|cffffcc00(" .. plannedWord .. ")|r")
            tooltip:Show()
        end
    end)
    
    -- ----------------------------------------------------------------
    -- UNIT TOOLTIP: Collectible drop info from CollectibleSourceDB
    -- Shows item hyperlinks + collection status + try count on NPCs
    -- ----------------------------------------------------------------
    if Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        -- Upvalue WoW APIs used in the hook
        local UnitGUID = UnitGUID
        local strsplit = strsplit
        local tonumber = tonumber

        -- GameObject IDs that WoW sometimes shows with Unit (Creature) tooltip. Do not inject
        -- collectible drops on these (they are objects, not NPCs that drop mounts/pets).
        local UNIT_TOOLTIP_OBJECT_IDS = {
            [209780] = true,  -- Abandoned Restoration Stone (Midnight delve / world object as Unit tooltip)
            [209781] = true,  -- Empowered Restoration Stone (Midnight)
        }
        -- Unit names that are known GameObjects (name-fallback path). Do not show drops.
        local UNIT_TOOLTIP_OBJECT_NAMES = {
            ["Abandoned Restoration Stone"] = true,
            ["Empowered Restoration Stone"] = true,
        }

        -- Runtime name → drops cache (populated from successful GUID lookups)
        local nameDropCache = {}

        -- Runtime name → npcID cache (for lockout quest checking in name-fallback mode)
        local nameNpcIDCache = {}

        -- Localized npcNameIndex: built in the BACKGROUND using a coroutine to prevent
        -- game freezes. The old synchronous approach iterated ALL EJ tiers → instances →
        -- encounters → creatures (thousands of API calls) and froze the game for 10-15 seconds.
        --
        -- ARCHITECTURE:
        -- 1. Initialize immediately with English fallback from CollectibleSourceDB.npcNameIndex
        -- 2. Check SavedVariables cache — if locale + version match, load and SKIP EJ scan
        -- 3. If no cache: start a background coroutine that scans EJ for localized names
        -- 4. After EJ scan completes, save results to cache for future logins
        -- 5. Tooltip handler always has a working index (English until localized names arrive)
        local localizedNpcNameIndex = {}  -- Starts populated with English fallback
        local npcIndexBuildComplete = false  -- true when background coroutine finishes

        -- Immediately populate with English fallback so tooltips work before EJ scan
        local function InitializeEnglishFallback()
            local sourceDB = ns.CollectibleSourceDB
            if sourceDB and sourceDB.npcNameIndex then
                for name, npcIDs in pairs(sourceDB.npcNameIndex) do
                    localizedNpcNameIndex[name] = npcIDs
                end
            end
        end
        InitializeEnglishFallback()

        -- Compute a simple version fingerprint from CollectibleSourceDB.
        -- Changes when encounters or npcNameIndex is modified (addon update).
        local function GetCacheVersion()
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return 0 end
            local count = 0
            if sourceDB.encounters then
                for _ in pairs(sourceDB.encounters) do count = count + 1 end
            end
            if sourceDB.npcNameIndex then
                for _ in pairs(sourceDB.npcNameIndex) do count = count + 1 end
            end
            if sourceDB.npcs then
                for _ in pairs(sourceDB.npcs) do count = count + 1 end
            end
            return count
        end

        -- Try to load cached localized names from SavedVariables.
        -- Returns true if cache was valid and loaded.
        local function TryLoadFromCache()
            local addon = WarbandNexus or _G[addonName]
            if not addon or not addon.db or not addon.db.global then return false end

            local cache = addon.db.global.npcNameCache
            if not cache then return false end

            local currentLocale = GetLocale()
            local currentVersion = GetCacheVersion()

            if cache.locale ~= currentLocale or cache.version ~= currentVersion then
                -- Cache is stale (locale changed or DB updated)
                addon.db.global.npcNameCache = nil
                return false
            end

            -- Load cached names into the index
            local loaded = 0
            for name, npcIDs in pairs(cache.names) do
                localizedNpcNameIndex[name] = npcIDs
                loaded = loaded + 1
            end

            npcIndexBuildComplete = true
            if addon.Debug then
                addon:Debug("[Tooltip] NPC name index loaded from cache: %d names (locale: %s)", loaded, currentLocale)
            end
            return true
        end

        -- Save current localized names to SavedVariables cache.
        local function SaveToCache(ejEntries)
            local addon = WarbandNexus or _G[addonName]
            if not addon or not addon.db or not addon.db.global then return end

            -- Only save EJ-derived entries (not the English fallback from npcNameIndex)
            local names = {}
            local sourceDB = ns.CollectibleSourceDB
            local englishNames = (sourceDB and sourceDB.npcNameIndex) or {}

            for name, npcIDs in pairs(localizedNpcNameIndex) do
                -- Save ALL names (English + localized) so cache is self-contained
                -- Strip _seen metadata
                local clean = {}
                for i = 1, #npcIDs do
                    clean[i] = npcIDs[i]
                end
                names[name] = clean
            end

            addon.db.global.npcNameCache = {
                locale = GetLocale(),
                version = GetCacheVersion(),
                names = names,
            }

            if addon.Debug then
                local count = 0
                for _ in pairs(names) do count = count + 1 end
                addon:Debug("[Tooltip] NPC name index saved to cache: %d names", count)
            end
        end

        -- EJ SCAN REMOVED: The Encounter Journal scan iterated ~200 instances causing
        -- unavoidable FPS drops (each EJ_SelectInstance triggers WoW internal data loading).
        -- The 94 localized names it produced are NOT worth 6+ seconds of frame spikes.
        --
        -- Coverage without EJ scan:
        -- 1. English fallback names from CollectibleSourceDB.npcNameIndex (always available)
        -- 2. GUID-based method extracts NPC ID directly (works in most cases)
        -- 3. Runtime nameDropCache: populated from successful GUID lookups
        -- 4. ENCOUNTER_LOOT_RECEIVED handler: adds localized boss names at runtime
        -- 5. SavedVariables cache: persists any previously scanned names across sessions
        --
        -- The only gap: non-English client + secret GUID + first time seeing a boss.
        -- This resolves itself after one successful GUID lookup or boss kill.

        -- Load any previously cached names from SavedVariables (from older sessions)
        C_Timer.After(1.5, function()
            TryLoadFromCache()
            npcIndexBuildComplete = true
        end)

        -- Accessor: always returns the index (English fallback until EJ scan completes)
        local function GetLocalizedNpcNameIndex()
            return localizedNpcNameIndex
        end

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            if tooltip ~= GameTooltip then return end

            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB or not sourceDB.npcs then return end

            local drops = nil
            local resolvedNpcID = nil  -- Track NPC ID for lockout quest checking
            local zoneDrops = nil      -- Zone-wide drops to merge

            -- Helper: Get current zone's drops (if any)
            -- Returns: drops, raresOnly (boolean), hostileOnly (boolean)
            local function GetCurrentZoneDrops()
                if not sourceDB.zones then return nil, false, false end
                local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local mapID = (rawMapID and not (issecretvalue and issecretvalue(rawMapID))) and rawMapID or nil
                while mapID and mapID > 0 do
                    local zData = sourceDB.zones[mapID]
                    if zData then
                        -- New format: { drops = {...}, raresOnly = true, hostileOnly = true }
                        if zData.drops then
                            return zData.drops, zData.raresOnly == true, zData.hostileOnly == true
                        end
                        -- Old format: direct array of drops
                        return zData, false, false
                    end
                    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
                    local nextID = mapInfo and mapInfo.parentMapID
                    mapID = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
                end
                return nil, false, false
            end

            -- Helper: Check if mouseover unit is rare/elite (for raresOnly zones)
            local function IsMouseoverRareOrElite()
                local ok, classification = pcall(UnitClassification, "mouseover")
                if not ok or not classification then return false end
                if issecretvalue and issecretvalue(classification) then return false end
                -- "rare", "rareelite", "worldboss" are rare-quality units
                return classification == "rare" or classification == "rareelite" or classification == "worldboss"
            end

            -- Helper: Check if mouseover unit is attackable (for hostileOnly zones)
            local function IsMouseoverAttackable()
                local ok, canAttack = pcall(UnitCanAttack, "player", "mouseover")
                if ok and canAttack and not (issecretvalue and issecretvalue(canAttack)) and canAttack == true then
                    return true
                end
                -- Dead units are no longer attackable; check if it's a lootable corpse
                local okDead, isDead = pcall(UnitIsDead, "mouseover")
                if okDead and isDead and not (issecretvalue and issecretvalue(isDead)) and isDead == true then
                    local okReact, reaction = pcall(UnitReaction, "mouseover", "player")
                    if okReact and reaction and not (issecretvalue and issecretvalue(reaction))
                        and type(reaction) == "number" and reaction <= 4 then
                        return true
                    end
                end
                return false
            end

            -- In instances, do not show zone-wide drops on unit tooltips (avoids e.g. "Mount"
            -- appearing on objects like Empowered Restoration Stone that use Unit tooltip).
            local function ClearZoneDropsInInstance()
                if not zoneDrops or #zoneDrops == 0 then return end
                local inInstance = IsInInstance and IsInInstance()
                if inInstance and issecretvalue and issecretvalue(inInstance) then inInstance = nil end
                if inInstance then zoneDrops = nil end
            end

            -- METHOD 1: GUID-based lookup (works outside instances / when not secret)
            local ok, guid = pcall(UnitGUID, "mouseover")
            if ok and guid and not (issecretvalue and issecretvalue(guid)) then
                local unitType, _, _, _, _, rawID = strsplit("-", guid)
                if unitType == "Creature" or unitType == "Vehicle" then
                    local npcID = tonumber(rawID)
                    if npcID then
                        -- Skip known GameObjects that WoW shows as Unit tooltip (e.g. Empowered Restoration Stone)
                        if UNIT_TOOLTIP_OBJECT_IDS[npcID] then
                            drops = nil
                            zoneDrops = nil
                        else
                        drops = sourceDB.npcs[npcID]
                        if drops then resolvedNpcID = npcID end
                        -- Check for zone-wide drops (e.g., Midnight zone rare mounts)
                        local zRaresOnly, zHostileOnly
                        zoneDrops, zRaresOnly, zHostileOnly = GetCurrentZoneDrops()
                        -- If zone is raresOnly, only show on rare/elite units
                        if zoneDrops and zRaresOnly and not IsMouseoverRareOrElite() then
                            zoneDrops = nil
                        end
                        -- If zone is hostileOnly, only show on attackable units (not friendly NPCs/vendors)
                        if zoneDrops and zHostileOnly and not IsMouseoverAttackable() then
                            zoneDrops = nil
                        end
                        -- In instances, never show zone drops on unit tooltip (e.g. Empowered Restoration Stone)
                        ClearZoneDropsInInstance()
                        -- Cache name → drops and name → npcID for future secret-value fallback
                        if drops and #drops > 0 then
                            local ttLeft = _G["GameTooltipTextLeft1"]
                            if ttLeft and ttLeft.GetText then
                                local nm = ttLeft:GetText()
                                if nm and not (issecretvalue and issecretvalue(nm)) and nm ~= "" then
                                    nameDropCache[nm] = drops
                                    nameNpcIDCache[nm] = npcID
                                    -- Also persist to localizedNpcNameIndex for cross-session cache
                                    if not localizedNpcNameIndex[nm] then
                                        localizedNpcNameIndex[nm] = { npcID }
                                    end
                                end
                            end
                        end
                        end
                    end
                end
                -- If no NPC drops and no zone drops, exit early
                if not drops and not zoneDrops then return end
            end

            -- METHOD 2: Name-based fallback (Midnight 12.0 - GUID is secret in instances)
            -- Only enter if we have neither NPC drops nor zone drops from GUID lookup
            if not drops and not zoneDrops then
                -- Read NPC name from multiple sources (Blizzard renders these from secure code)
                local unitName = nil

                -- Try tooltip data lines first (most reliable in Midnight)
                if data and data.lines and data.lines[1] then
                    local lt = data.lines[1].leftText
                    -- Guard: leftText can itself be a secret value in Midnight instances
                    if lt and not (issecretvalue and issecretvalue(lt)) then
                        unitName = lt
                    end
                end

                -- Fallback: read from the tooltip's font string directly
                if not unitName then
                    local textLeft = _G["GameTooltipTextLeft1"]
                    if textLeft and textLeft.GetText then
                        local txt = textLeft:GetText()
                        if txt and not (issecretvalue and issecretvalue(txt)) then
                            unitName = txt
                        end
                    end
                end

                -- If everything is secret, we simply can't identify this NPC — bail out
                if not unitName or unitName == "" then return end
                -- Skip known GameObject names (e.g. Empowered Restoration Stone)
                if UNIT_TOOLTIP_OBJECT_NAMES[unitName] then return end

                -- Check runtime cache first (populated from previous GUID-based lookups)
                drops = nameDropCache[unitName]
                if drops then
                    resolvedNpcID = nameNpcIDCache[unitName]
                end

                -- Check localized npcNameIndex (covers instance bosses, locale-aware)
                if not drops then
                    local npcIDs = GetLocalizedNpcNameIndex()[unitName]
                    if npcIDs then
                        -- Merge drops from all matching NPC IDs
                        local merged = {}
                        local seen = {} -- Dedup by itemID
                        for _, npcID in ipairs(npcIDs) do
                            local npcDrops = sourceDB.npcs[npcID]
                            if npcDrops then
                                for j = 1, #npcDrops do
                                    local d = npcDrops[j]
                                    if not seen[d.itemID] then
                                        seen[d.itemID] = true
                                        merged[#merged + 1] = d
                                    end
                                end
                            end
                        end
                        if #merged > 0 then
                            drops = merged
                            -- Use first NPC ID for lockout checking
                            resolvedNpcID = npcIDs[1]
                        end
                    end
                end

                -- Name-fallback path: we cannot distinguish NPC vs GameObject (e.g. Empowered
                -- Restoration Stone uses Unit tooltip but is an object). Do NOT add zone drops here,
                -- or objects in Harandar etc. would show "Rootstalker Grimlynx / Vibrant Petalwing".
                -- Zone drops are only shown in METHOD 1 when GUID confirms Creature/Vehicle.
                zoneDrops = nil

                if (not drops or #drops == 0) and not zoneDrops then return end
            end

            -- Per-NPC collectible drops: only on hostile/attackable units. Friendly delve objects and
            -- NPCs that use a Creature unit tooltip must not show unrelated mount/pet lines from DB.
            if drops and #drops > 0 and not IsMouseoverAttackable() then
                drops = nil
            end
            if (not drops or #drops == 0) and (not zoneDrops or #zoneDrops == 0) then return end

            -- Merge zone drops with NPC drops (if any)
            local finalDrops = drops
            if zoneDrops and #zoneDrops > 0 then
                if not finalDrops or #finalDrops == 0 then
                    finalDrops = zoneDrops
                else
                    -- Merge: NPC drops first, then zone drops (deduplicated)
                    local merged = {}
                    local seen = {}
                    for i = 1, #finalDrops do
                        local d = finalDrops[i]
                        if not seen[d.itemID] then
                            seen[d.itemID] = true
                            merged[#merged + 1] = d
                        end
                    end
                    for i = 1, #zoneDrops do
                        local d = zoneDrops[i]
                        if not seen[d.itemID] then
                            seen[d.itemID] = true
                            merged[#merged + 1] = d
                        end
                    end
                    finalDrops = merged
                end
            end

            -- Use shared rendering function (pass npcID for lockout checking)
            InjectCollectibleDropLines(tooltip, finalDrops, resolvedNpcID)
        end)

        -- Expose diagnostic accessors (MUST be inside this scope to access closures)
        self._getLocalizedNpcNameIndex = GetLocalizedNpcNameIndex
        self._isNpcIndexReady = function() return npcIndexBuildComplete end
        -- Force rebuild: resets to English fallback and reloads cache
        self._forceRebuildIndex = function()
            localizedNpcNameIndex = {}
            npcIndexBuildComplete = false
            InitializeEnglishFallback()
            TryLoadFromCache()
            npcIndexBuildComplete = true
            return localizedNpcNameIndex
        end

        -- ENCOUNTER_END feed: Injects localized encounter name into tooltip caches.
        -- Called from TryCounterService when a boss is killed in an instance.
        -- Midnight 12.0+: treat encounterName / encounterID as potentially secret — no ==, no table keys
        -- until cleared (wow-taint-security). npcIDsOverride allows ID-secret kills to still cache by name
        -- when the name is non-secret.
        self._feedEncounterKill = function(encounterName, encounterID, npcIDsOverride)
            if not encounterName or (issecretvalue and issecretvalue(encounterName)) then return end
            if type(encounterName) ~= "string" or encounterName == "" then return end
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return end

            local encNpcIDs = npcIDsOverride
            if not encNpcIDs or type(encNpcIDs) ~= "table" or #encNpcIDs == 0 then
                if encounterID ~= nil and not (issecretvalue and issecretvalue(encounterID)) then
                    encNpcIDs = sourceDB.encounters and sourceDB.encounters[encounterID]
                end
            end
            if not encNpcIDs or #encNpcIDs == 0 then return end

            -- 1. Populate nameDropCache/nameNpcIDCache (used by METHOD 2 name lookup)
            local merged = {}
            local seen = {}
            local firstNpcID = nil
            for _, npcID in ipairs(encNpcIDs) do
                local npcDrops = sourceDB.npcs and sourceDB.npcs[npcID]
                if npcDrops then
                    if not firstNpcID then firstNpcID = npcID end
                    for j = 1, #npcDrops do
                        local d = npcDrops[j]
                        if not seen[d.itemID] then
                            seen[d.itemID] = true
                            merged[#merged + 1] = d
                        end
                    end
                end
            end

            if #merged > 0 then
                nameDropCache[encounterName] = merged
                nameNpcIDCache[encounterName] = firstNpcID
            end

            -- 2. Also inject into localizedNpcNameIndex if it has been built already
            if localizedNpcNameIndex and not localizedNpcNameIndex[encounterName] then
                local valid = {}
                for _, npcID in ipairs(encNpcIDs) do
                    if sourceDB.npcs and sourceDB.npcs[npcID] then
                        valid[#valid + 1] = npcID
                    end
                end
                if #valid > 0 then
                    localizedNpcNameIndex[encounterName] = valid
                end
            end
        end

        -- Expose cache save for PLAYER_LOGOUT persistence of runtime-discovered names
        WarbandNexus._saveNpcNameCache = function()
            if not localizedNpcNameIndex then return end
            local count = 0
            for _ in pairs(localizedNpcNameIndex) do count = count + 1 end
            if count == 0 then return end
            SaveToCache(0)
        end

        self:Debug("Unit tooltip hook initialized (collectible drops)")
    end

    -- ----------------------------------------------------------------
    -- ITEM TOOLTIP: Container collectible drops (paragon caches, bags, etc.)
    -- Checks CollectibleSourceDB.containers for the hovered item and injects
    -- collectible drop lines if found.
    -- ----------------------------------------------------------------
    if Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB or not sourceDB.containers then return end

            local itemID = data and data.id
            if not itemID then return end

            local containerData = sourceDB.containers[itemID]
            if not containerData then return end

            local drops = containerData.drops or containerData
            if not drops or type(drops) ~= "table" or #drops == 0 then return end

            InjectCollectibleDropLines(tooltip, drops)
        end)

        self:Debug("Container item tooltip hook initialized (collectible drops)")
    end

    self:Debug("GameTooltip hook initialized (TooltipDataProcessor)")
end

---Run self-diagnostic on tooltip systems. Called by /wn validate tooltip.
---Verifies localized npcNameIndex, lockout quest integration, and EJ API availability.
---@return table results { passed = bool, checks = { {name, status, detail} } }
function TooltipService:RunDiagnostics()
    local results = { passed = true, checks = {} }
    local function addCheck(name, ok, detail)
        results.checks[#results.checks + 1] = { name = name, status = ok, detail = detail }
        if not ok then results.passed = false end
    end

    -- 1. Check EJ API availability
    addCheck("EJ_GetEncounterInfo", EJ_GetEncounterInfo ~= nil, EJ_GetEncounterInfo and "Available" or "MISSING")
    addCheck("EJ_GetCreatureInfo", EJ_GetCreatureInfo ~= nil, EJ_GetCreatureInfo and "Available" or "MISSING")

    -- 2. Check localized npcNameIndex (force rebuild for fresh results)
    local sourceDB = ns.CollectibleSourceDB
    local index
    if self._forceRebuildIndex then
        index = self._forceRebuildIndex()
    elseif self._getLocalizedNpcNameIndex then
        index = self._getLocalizedNpcNameIndex()
    end
    if not index then index = {} end

    local totalNames = 0
    if index then
        for _ in pairs(index) do totalNames = totalNames + 1 end
    end

    -- Count how many names came from EJ vs static English
    local staticCount = 0
    if sourceDB and sourceDB.npcNameIndex then
        for _ in pairs(sourceDB.npcNameIndex) do staticCount = staticCount + 1 end
    end
    local ejNames = totalNames - staticCount
    if ejNames < 0 then ejNames = 0 end

    addCheck("localizedNpcNameIndex", totalNames > 0,
        totalNames .. " names (" .. ejNames .. " from EJ, " .. staticCount .. " static English)")

    -- 4. EJ spot-check: verify the localized index contains a known boss
    -- Check if "The Lich King" (or localized equivalent) is in the index
    -- NPC ID 36597 = The Lich King, should be reachable via encounters table
    local lichKingFound = false
    local lichKingName = nil
    if index then
        for name, npcIDs in pairs(index) do
            for _, npcID in ipairs(npcIDs) do
                if npcID == 36597 then
                    lichKingFound = true
                    lichKingName = name
                    break
                end
            end
            if lichKingFound then break end
        end
    end
    addCheck("EJ spot-check (Lich King npcID=36597)", lichKingFound,
        lichKingFound and ('"' .. lichKingName .. '"') or "Not found in index")

    -- 4. Verify lockoutQuests DB accessible
    local lockoutCount = 0
    if sourceDB and sourceDB.lockoutQuests then
        for _ in pairs(sourceDB.lockoutQuests) do lockoutCount = lockoutCount + 1 end
    end
    addCheck("lockoutQuests DB", lockoutCount > 0, lockoutCount .. " NPC lockout entries")

    -- 5. Check issecretvalue availability
    addCheck("issecretvalue API", issecretvalue ~= nil,
        issecretvalue and "Available (Midnight 12.0)" or "Not available (pre-12.0)")

    -- 6. Check C_Item.GetItemInfo availability
    addCheck("C_Item.GetItemInfo", C_Item and C_Item.GetItemInfo ~= nil,
        (C_Item and C_Item.GetItemInfo) and "Available" or "MISSING — using legacy GetItemInfo")

    -- 7. Check ENCOUNTER_END feed system
    addCheck("ENCOUNTER_END feed", self._feedEncounterKill ~= nil,
        self._feedEncounterKill and "Active — boss kills inject localized names into cache"
            or "NOT active — tooltip hook may not be initialized")

    return results
end

-- ============================================================================
-- CONCENTRATION TOOLTIP HOOK
-- ============================================================================

--[[
    Append cross-character concentration data to tooltips showing Concentration.
    
    Strategy (dual-layer, frame-path independent):
    
    1. TooltipDataProcessor (Currency type) — Blizzard's official modern API
       for post-processing tooltips. Since Concentration is a currency
       (concentrationCurrencyID), Blizzard uses SetCurrencyByID or similar
       to populate the tooltip. This fires reliably.
       
    2. GameTooltip:HookScript("OnShow") — Fallback for any non-currency
       tooltip path that still shows "Concentration" in the first line.
    
    Both are installed once at load time on GameTooltip (always available).
    No ProfessionsFrame frame-path discovery needed.
]]
local concentrationHookInstalled = false
local WN_CONCENTRATION_MARKER = (ns.L and ns.L["TOOLTIP_CONCENTRATION_MARKER"]) or "Warband Nexus - Concentration"
local CONCENTRATION_CACHE_TTL = 10
local concentrationCurrencyCache = {
    builtAt = 0,
    idSet = {},
    nameSet = {},
}

local function GetConcentrationCurrencyCache()
    local now = GetTime and GetTime() or 0
    if concentrationCurrencyCache.builtAt > 0 and (now - concentrationCurrencyCache.builtAt) < CONCENTRATION_CACHE_TTL then
        return concentrationCurrencyCache
    end

    local idSet = {}
    local nameSet = {}
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
        for _, charData in pairs(WarbandNexus.db.global.characters) do
            local concentrationData = charData and charData.concentration
            if concentrationData then
                for _, concData in pairs(concentrationData) do
                    local currencyID = concData and concData.currencyID
                    if type(currencyID) == "number" and currencyID > 0 then
                        idSet[currencyID] = true
                    end
                end
            end
        end
    end

    for currencyID in pairs(idSet) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and info and info.name and not (issecretvalue and issecretvalue(info.name)) then
            nameSet[info.name] = true
        end
    end

    concentrationCurrencyCache.builtAt = now
    concentrationCurrencyCache.idSet = idSet
    concentrationCurrencyCache.nameSet = nameSet
    return concentrationCurrencyCache
end

local function IsConcentrationCurrencyID(currencyID)
    if not currencyID then return false end
    local cache = GetConcentrationCurrencyCache()
    return cache.idSet[currencyID] == true
end

local function HasAlreadyInjected(tooltip)
    local marker = (ns.L and ns.L["TOOLTIP_CONCENTRATION_MARKER"]) or "Warband Nexus - Concentration"
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local lineText = line:GetText()
            if lineText and not (issecretvalue and issecretvalue(lineText)) and marker ~= "" and lineText:find(marker, 1, true) then
                return true
            end
        end
    end
    return false
end

local function IsConcentrationTooltip(tooltip)
    local firstLine = _G[tooltip:GetName() .. "TextLeft1"]
    if not firstLine then return false end
    local text = firstLine:GetText()
    if not text or (issecretvalue and issecretvalue(text)) then return false end
    local stripped = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    stripped = stripped:match("^%s*(.-)%s*$")
    if not stripped or stripped == "" then return false end
    local cache = GetConcentrationCurrencyCache()
    if cache.nameSet[stripped] then return true end
    return stripped == "Concentration"
end

-- The actual function that appends concentration data to a visible tooltip
local function AppendConcentrationData(tooltip)
    if not WarbandNexus or not WarbandNexus.GetAllConcentrationData then return end

    local allConc = WarbandNexus:GetAllConcentrationData()
    if not allConc or not next(allConc) then return end

    tooltip:AddLine(" ")
    tooltip:AddLine(WN_CONCENTRATION_MARKER, 0.4, 0.8, 1)

    -- Sort profession names for consistent display
    local profNames = {}
    for profName in pairs(allConc) do
        profNames[#profNames + 1] = profName
    end
    table.sort(profNames)

    for _, profName in ipairs(profNames) do
        local entries = allConc[profName]
        tooltip:AddLine("  " .. profName, 1, 0.82, 0)

        for ei = 1, #entries do
            local entry = entries[ei]
            local cc = RAID_CLASS_COLORS[entry.classFile] or { r = 1, g = 1, b = 1 }
            local charColor = string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            local timeStr = WarbandNexus:GetConcentrationTimeToFull(entry)
            local estimated = WarbandNexus:GetEstimatedConcentration(entry)
            local isFull = (estimated >= entry.max)

            local valueStr
            if isFull then
                valueStr = "|cff44ff44" .. entry.max .. " / " .. entry.max .. "|r  |cff44ff44" .. ((ns.L and ns.L["TOOLTIP_FULL"]) or "(Full)") .. "|r"
            else
                valueStr = "|cffffffff~" .. estimated .. " / " .. entry.max .. "|r  |cffffffff(" .. timeStr .. ")|r"
            end

            tooltip:AddDoubleLine(
                "    " .. charColor .. entry.charName .. "|r",
                valueStr,
                1, 1, 1, 1, 1, 1
            )
        end
    end

    tooltip:Show()
end

function TooltipService:InstallConcentrationTooltipHook()
    if concentrationHookInstalled then return end

    -- ----------------------------------------------------------------
    -- Layer 1: TooltipDataProcessor for Currency tooltips (modern API)
    -- Concentration is a currency. When Blizzard calls
    -- GameTooltip:SetCurrencyByID(concentrationCurrencyID), this fires.
    -- ----------------------------------------------------------------
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum.TooltipDataType and Enum.TooltipDataType.Currency then
        local CURRENCY_TYPE = Enum.TooltipDataType.Currency
        TooltipDataProcessor.AddTooltipPostCall(CURRENCY_TYPE, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
            if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
            if not data or not data.id or not IsConcentrationCurrencyID(data.id) then return end
            if HasAlreadyInjected(tooltip) then return end

            if WarbandNexus and WarbandNexus.Debug then
                WarbandNexus:Debug("[Conc Tooltip] Currency PostCall matched, currencyID=" .. tostring(data.id))
            end

            pcall(AppendConcentrationData, tooltip)
        end)
    end

    -- ----------------------------------------------------------------
    -- Layer 2: GameTooltip OnShow fallback
    -- Catches any non-currency code path (custom SetOwner + AddLine).
    -- ----------------------------------------------------------------
    GameTooltip:HookScript("OnShow", function(tooltip)
        if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
        if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
        if not IsConcentrationTooltip(tooltip) then return end
        if HasAlreadyInjected(tooltip) then return end

        if WarbandNexus and WarbandNexus.Debug then
            WarbandNexus:Debug("[Conc Tooltip] OnShow fallback matched")
        end

        pcall(AppendConcentrationData, tooltip)
    end)

    concentrationHookInstalled = true
    if self.Debug then
        self:Debug("Concentration tooltip hook installed (TooltipDataProcessor + OnShow dual strategy)")
    end
end

-- Install the hook immediately at load time — GameTooltip is always available.
TooltipService:InstallConcentrationTooltipHook()

-- ============================================================================
-- DEBUG
-- ============================================================================

function TooltipService:Debug(msg)
    if WarbandNexus and WarbandNexus.Debug then
        WarbandNexus:Debug("[Tooltip] " .. msg)
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Attach to WarbandNexus namespace
WarbandNexus.Tooltip = TooltipService

-- Export to ns for SharedWidgets access
ns.TooltipService = TooltipService

--- Enchant-only crafting tier (1–2) from tooltip scan; not item body GetCraftingQuality.
ns.UI_GetEnchantmentCraftingQualityTierFromItemLink = GetEnchantmentCraftingQualityTierFromItemLink
