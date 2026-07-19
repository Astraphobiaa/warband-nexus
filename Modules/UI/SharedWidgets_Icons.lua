--[[
    Warband Nexus - SharedWidgets SharedWidgets_Icons (ops-029 slice)
    Loaded after Modules/UI/SharedWidgets.lua core exports.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local Constants = ns.Constants
local issecretvalue = issecretvalue

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local COLORS = ns.UI_COLORS
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ApplyVisuals = ns.UI_ApplyVisuals
local GetColors = function() return ns.UI_COLORS end
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

--- Item / plan icon well (light: visible stone tray; dark: near-black inset).
---@return table rgba
local function GetIconWellBackdrop()
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        local card = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
            or (COLORS and COLORS.bgCard)
        if card then
            return { card[1], card[2], card[3], card[4] or 1 }
        end
        return { 0.08, 0.08, 0.09, 1 }
    end
    if ns.UI_IsLightMode and ns.UI_IsLightMode() then
        return { 0.66, 0.65, 0.63, 1 }
    end
    return { 0.05, 0.05, 0.07, 0.95 }
end
ns.UI_GetIconWellBackdrop = GetIconWellBackdrop

--- Border stroke for icon wells.
---@return table rgba
local function GetIconWellBorder()
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        local bc = ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border
        if bc then
            return { bc[1], bc[2], bc[3], 1 }
        end
        return { 0.55, 0.48, 0.35, 1 }
    end
    if ns.UI_GetAccentBorderRGBA then
        return ns.UI_GetAccentBorderRGBA(0.6)
    end
    local ac = COLORS and COLORS.accent
    if ac then
        return { ac[1], ac[2], ac[3], 0.6 }
    end
    return { 0.6, 0.4, 1, 0.6 }
end
ns.UI_GetIconWellBorder = GetIconWellBorder

--- Item/plan icon well chrome (thin 1px in Classic; accent stroke in Modern).
---@param frame Frame|nil
local function ApplyIconWellChrome(frame)
    if not frame then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() and ns.UI_ApplyClassicIconWellChrome then
        ns.UI_ApplyClassicIconWellChrome(frame, GetIconWellBackdrop())
        return
    end
    if ApplyVisuals then
        ApplyVisuals(frame, GetIconWellBackdrop(), GetIconWellBorder())
    end
end
ns.UI_ApplyIconWellChrome = ApplyIconWellChrome

--- Collections list / Recent column row icons: Classic = bare icon (no well); Modern = icon well stroke.
---@param frame Frame|nil
local function ApplyListRowIconChrome(frame)
    if not frame then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        if ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(frame)
        elseif ns.UI_ApplyClassicInteriorFlatFill then
            ns.UI_ApplyClassicInteriorFlatFill(frame, { 0, 0, 0, 0 })
        end
        frame._wnListRowBareIcon = true
        return
    end
    ApplyIconWellChrome(frame)
end
ns.UI_ApplyListRowIconChrome = ApplyListRowIconChrome

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

--- Square icon action button (reminder / track / delete / todo / link).
function ns.UI_CreateIconActionButton(parent, size, iconKey, opts)
    if not parent or not iconKey then return nil end
    opts = type(opts) == "table" and opts or {}
    size = size or 24
    local btn = ns.UI.Factory and ns.UI.Factory.CreateButton and ns.UI.Factory:CreateButton(parent, size, size, true)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(size, size)
    end
    local tex = btn._wnIconTex
    if not tex then
        tex = btn:CreateTexture(nil, "OVERLAY")
        btn._wnIconTex = tex
    end
    tex:ClearAllPoints()
    local PCM = ns.UI_PLANS_CARD_METRICS
    local pad = opts.iconInset or (PCM and PCM.plansActionIconInset) or math.max(3, math.floor(size * 0.14))
    local iconSz = math.max(12, size - pad * 2)
    tex:SetSize(iconSz, iconSz)
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local disabled = opts.disabled == true
    local active = opts.active == true and not disabled
    btn._wnIconKey = iconKey
    btn._wnIconActive = active
    btn._wnIconDisabled = disabled
    function btn:WnRefreshIconAction(refActive, refDisabled)
        refDisabled = refDisabled == true
        refActive = refActive == true and not refDisabled
        self._wnIconActive = refActive
        self._wnIconDisabled = refDisabled
        local t = self._wnIconTex
        if t and ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(t, self._wnIconKey or iconKey, refActive, refDisabled)
        end
    end
    btn:WnRefreshIconAction(active, disabled)
    if opts.frameLevelOffset and btn.SetFrameLevel then
        btn:SetFrameLevel(parent:GetFrameLevel() + opts.frameLevelOffset)
    end
    if opts.onClick then
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetScript("OnClick", opts.onClick)
    end
    if opts.tooltipTitle and ns.TooltipService and ns.TooltipService.Show then
        btn:SetScript("OnEnter", function(self)
            ns.TooltipService:Show(self, {
                type = "custom",
                title = opts.tooltipTitle,
                icon = false,
                anchor = opts.tooltipAnchor or "ANCHOR_RIGHT",
                lines = opts.tooltipLines or {},
            })
        end)
        btn:SetScript("OnLeave", function()
            if ns.TooltipService.Hide then ns.TooltipService:Hide() end
        end)
    end
    return btn
end

-- COLLAPSE / EXPAND CHEVRON (shared control — single Button, one texture, state = packaged icon)

local function WnCollapseExpandApply(tex, isExpanded)
    if not tex then return end
    local key = isExpanded and "chevron_up" or "chevron_down"
    if not ns.UI_SetWnIconTexture(tex, key, nil) then
        local sp = UI_SPACING
        local up = sp.COLLAPSE_EXPAND_ATLAS_EXPANDED
        local down = sp.COLLAPSE_EXPAND_ATLAS_COLLAPSED
        tex:SetAtlas(isExpanded and up or down, false)
    end
end

function ns.UI_CollapseExpandSetState(btn, isExpanded)
    if not btn or not btn._wnCollapseTex then return end
    WnCollapseExpandApply(btn._wnCollapseTex, isExpanded)
    local c = btn._wnCollapseVertexColor
    if c then
        btn._wnCollapseTex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end

---@return Button btn Child has `_wnCollapseTex` (Texture). Mouse defaults to enabled; pass `enableMouse = false` when the parent header handles clicks.
function ns.UI_CreateCollapseExpandControl(parent, isExpanded, opts)
    opts = type(opts) == "table" and opts or {}
    local sz = tonumber(opts.size) or UI_SPACING.COLLAPSE_EXPAND_BUTTON_SIZE or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(sz, sz)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    btn._wnCollapseTex = tex
    WnCollapseExpandApply(tex, isExpanded)
    local vc = opts.vertexColor
    if vc then
        btn._wnCollapseVertexColor = { vc[1], vc[2], vc[3], vc[4] or 1 }
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    if opts.enableMouse == false then
        btn:EnableMouse(false)
    else
        btn:EnableMouse(true)
        if btn.RegisterForClicks then
            btn:RegisterForClicks("LeftButtonUp")
        end
    end
    return btn
end
--[[
    Create a pixel-perfect icon with border
    @param parent frame - Parent frame
    @param texture string/number - Texture path, atlas name, or fileID
    @param size number - Icon size (default 32)
    @param isAtlas boolean - If true, use SetAtlas instead of SetTexture (default false)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @param noBorder boolean - If true, skip border (default false)
    @return frame - Icon frame with .texture accessible
]]
local FILE_ICON_TEXCOORD = { 0.07, 0.93, 0.07, 0.93 }

function ns.UI_ApplyFileIconTexCoord(tex)
    if tex then
        tex:SetTexCoord(FILE_ICON_TEXCOORD[1], FILE_ICON_TEXCOORD[2], FILE_ICON_TEXCOORD[3], FILE_ICON_TEXCOORD[4])
    end
end

local function ApplyIconTexture(tex, texture, isAtlas)
    if not tex or not texture then return end
    if isAtlas then
        local success = pcall(tex.SetAtlas, tex, texture, false)
        if not success then
            success = pcall(tex.SetAtlas, tex, texture, true)
        end
        if not success then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                local texName = texture
                if texName ~= nil and not (issecretvalue and issecretvalue(texName)) then
                    DebugPrint("|cffff0000[WN CreateIcon]|r Atlas '" .. tostring(texName) .. "' failed, using fallback")
                end
            end
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            ns.UI_ApplyFileIconTexCoord(tex)
        end
        return
    end
    if type(texture) == "string" then
        tex:SetTexture(texture)
    else
        tex:SetTexture(texture)
    end
    ns.UI_ApplyFileIconTexCoord(tex)
end

local function CreateIcon(parent, texture, size, isAtlas, borderColor, noBorder)
    if not parent then return nil end
    
    size = size or 32
    isAtlas = isAtlas or false
    borderColor = borderColor or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    noBorder = noBorder or false
    
    -- Container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()  -- HIDE during setup (prevent flickering)
    frame:SetSize(size, size)
    
    -- Apply pixel-perfect border (unless noBorder is true)
    if not noBorder then
        if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
            and ns.UI_ApplyClassicIconWellChrome then
            local iconBg = (ns.UI_GetIconWellBackdrop and ns.UI_GetIconWellBackdrop())
                or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
                or { 0.08, 0.08, 0.09, 1 }
            ns.UI_ApplyClassicIconWellChrome(frame, iconBg)
        else
            local iconBg = { 0.05, 0.05, 0.07, 0.95 }
            local iconBorder = borderColor
            if ns.UI_IsLightMode and ns.UI_IsLightMode() then
                if ns.UI_GetIconWellBackdrop then
                    local bg = ns.UI_GetIconWellBackdrop()
                    iconBg = { bg[1], bg[2], bg[3], bg[4] or 1 }
                end
                if ns.UI_GetIconWellBorder then
                    iconBorder = ns.UI_GetIconWellBorder()
                end
            end
            ApplyVisuals(frame, iconBg, iconBorder)
        end
    end
    
    -- Icon texture (square fit inside frame; atlas keeps native UV)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    local inset
    if noBorder then
        inset = math.max(1, (GetPixelScale and GetPixelScale() or 1) * 2)
    elseif frame._wnClassicIconWell then
        inset = 3
    else
        -- Inset by 2 physical pixels to prevent texture bleeding into border
        inset = GetPixelScale() * 2
    end
    if noBorder then
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    else
        tex:SetPoint("TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    
    ApplyIconTexture(tex, texture, isAtlas)
    
    -- Anti-flicker optimization
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    tex:SetVertexColor(1, 1, 1, 1)
    
    -- Store texture reference
    frame.texture = tex
    
    -- Caller will Show() when fully setup
    return frame
end

--[[
    Create a layered paragon reputation icon with glow, bag, and optional checkmark
    @param parent Frame - Parent frame
    @param size number - Icon size (default 18)
    @param hasRewardPending boolean - If true, show checkmark overlay
    @return frame - Icon frame with layered textures
]]
local function CreateParagonIcon(parent, size, hasRewardPending)
    if not parent then return nil end
    
    size = size or 18
    
    -- Container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    -- Ensure frame level is high enough to show glow
    frame:SetFrameLevel(parent:GetFrameLevel() + 5)
    
    -- Layer order: BACKGROUND < BORDER < ARTWORK < OVERLAY
    -- 1. Glow (BACKGROUND layer - behind everything, only if reward pending)
    -- Blizzard uses sublevel -3 and ADD blend mode for glow effects
    local glowTex = nil
    if hasRewardPending then
        glowTex = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
        -- Make glow larger than frame (200% size) to make it more visible
        local glowSize = size * 2.0
        glowTex:SetSize(glowSize, glowSize)
        glowTex:SetPoint("CENTER", frame, "CENTER", 0, 0)
        local glowSuccess = pcall(function()
            glowTex:SetAtlas("ParagonReputation_Glow", false)
        end)
        if not glowSuccess then
            glowTex:Hide()
        else
            -- Apply blend mode for better visibility (like Blizzard does)
            glowTex:SetBlendMode("ADD")
            -- Ensure full alpha for glow
            glowTex:SetAlpha(1.0)
        end
        glowTex:SetSnapToPixelGrid(false)
        glowTex:SetTexelSnappingBias(0)
    end
    frame.glow = glowTex
    
    -- 2. Bag (ARTWORK layer - main icon)
    local bagTex = frame:CreateTexture(nil, "ARTWORK")
    bagTex:SetAllPoints()
    local bagSuccess = pcall(function()
        bagTex:SetAtlas("ParagonReputation_Bag", false)
    end)
    if not bagSuccess then
        -- Fallback to texture
        bagTex:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        bagTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    bagTex:SetSnapToPixelGrid(false)
    bagTex:SetTexelSnappingBias(0)
    frame.bag = bagTex
    
    -- 3. Checkmark (OVERLAY layer - on top, only if reward pending)
    -- Use same texture as standalone checkmark for consistency
    if hasRewardPending then
        local checkTex = frame:CreateTexture(nil, "OVERLAY")
        checkTex:SetAllPoints()
        -- Use same texture as the standalone checkmark (ReadyCheck-Ready)
        checkTex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        checkTex:SetSnapToPixelGrid(false)
        checkTex:SetTexelSnappingBias(0)
        frame.checkmark = checkTex
    end
    
    -- Gray out if no reward pending
    if not hasRewardPending then
        bagTex:SetVertexColor(0.5, 0.5, 0.5, 1)
    end
    
    return frame
end

--[[
    Create a pixel-perfect status bar (progress bar) with optional border.
    @param parent frame - Parent frame
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default black)
    @param noBorder boolean - If true, no border (for use inside a bordered wrapper)
    @return frame - StatusBar frame
]]
local function CreateStatusBar(parent, width, height, bgColor, borderColor, noBorder)
    if not parent then return nil end

    width = width or 200
    height = height or 14
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {0, 0, 0, 1}
    noBorder = (noBorder == true)

    -- Classic theme: FrameXML-style bar (UI-StatusBar fill + thin stroke track),
    -- never the 32px dialog-box border that ApplyVisuals would route to.
    if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
        bar:SetSize(width, height)
        if not noBorder and ns.UI_ApplyClassicThinBorderChrome then
            ns.UI_ApplyClassicThinBorderChrome(bar, { 0.03, 0.03, 0.04, 0.9 })
        elseif bar.SetBackdrop then
            bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            bar:SetBackdropColor(0.03, 0.03, 0.04, 0.9)
        end
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local fillTex = bar:GetStatusBarTexture()
        if fillTex then
            fillTex:SetDrawLayer("ARTWORK", 0)
            if fillTex.SetHorizTile then
                fillTex:SetHorizTile(false)
            end
        end
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar._wnBlizzardChrome = true
        return bar
    end

    local frame = CreateFrame("StatusBar", nil, parent, noBorder and "BackdropTemplate" or nil)
    frame:SetSize(width, height)

    if not noBorder then
        ApplyVisuals(frame, bgColor, borderColor)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.95)
    end

    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local barTexture = frame:GetStatusBarTexture()
    if barTexture then
        barTexture:SetDrawLayer("ARTWORK", 0)
        barTexture:SetSnapToPixelGrid(false)
        barTexture:SetTexelSnappingBias(0)
    end

    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)

    return frame
end

--[[
    Create a pixel-perfect button with border (for rows, cards, etc.)
    @param parent frame - Parent frame
    @param width number - Button width
    @param height number - Button height
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @param noBorder boolean - If true, skip border (default false)
    @return button - Button frame
]]
local function CreateButton(parent, width, height, bgColor, borderColor, noBorder)
    if not parent then return nil end

    if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        if noBorder then
            local button = CreateFrame("Button", nil, parent)
            if width and height then
                button:SetSize(width, height)
            end
            button:EnableMouse(true)
            button._wnSkipCustomChrome = true
            local w = tonumber(width) or 0
            local h = tonumber(height) or 0
            local compactIcon = (w <= 0 or w <= 36) and (h <= 0 or h <= 36)
            if compactIcon and ns.UI_ApplyClassicIconWellChrome then
                ns.UI_ApplyClassicIconWellChrome(button)
            elseif ns.UI_ApplyClassicTransparentInterior then
                ns.UI_ApplyClassicTransparentInterior(button)
            elseif button.SetBackdrop then
                pcall(button.SetBackdrop, button, nil)
            end
            return button
        end
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        if width and height then
            button:SetSize(width, height)
        end
        button:EnableMouse(true)
        button._wnBlizzardButton = true
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(button)
        end
        return button
    end

    if not bgColor then
        if ns.UI_GetControlChromeBackdrop then
            bgColor = ns.UI_GetControlChromeBackdrop()
        else
            bgColor = { 0.05, 0.05, 0.07, 0.95 }
        end
    end
    borderColor = borderColor or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
    noBorder = noBorder or false
    
    -- Button frame
    local button = CreateFrame("Button", nil, parent)
    if width and height then
        button:SetSize(width, height)
    end
    button:EnableMouse(true)
    
    if not noBorder then
        ApplyVisuals(button, bgColor, borderColor)
    else
        -- Icon-only hit target: no opaque panel (row delete / header assign / reorder arrows).
        if button.SetBackdrop then
            pcall(button.SetBackdrop, button, nil)
        end
    end

    return button
end

-- Export factory functions to namespace
ns.UI_CreateIcon = CreateIcon
-- In-place icon retexture for pooled/reused icon frames (virtual browse grid). Retextures the
-- ARTWORK texture created by CreateIcon (stored as frame.texture) without recreating the frame.
ns.UI_ApplyIconTexture = ApplyIconTexture
function ns.UI_RetextureIcon(iconFrame, texture, isAtlas)
    if iconFrame and iconFrame.texture then
        ApplyIconTexture(iconFrame.texture, texture, isAtlas)
    end
end
ns.UI_CreateStatusBar = CreateStatusBar
ns.UI_CreateButton = CreateButton
ns.UI_CreateParagonIcon = CreateParagonIcon
-- Get item type name from class ID
local function GetItemTypeName(classID)
    local typeName = GetItemClassInfo(classID)
    return typeName or "Other"
end

-- Get item class ID from item ID
local function GetItemClassID(itemID)
    if not itemID then return 15 end -- Miscellaneous
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID or 15
end

local KEYSTONE_CATEGORY_ICON = "Interface\\Icons\\INV_Misc_Key_03"

local function ItemLinkLooksKeystone(link)
    if not link or link == "" then return false end
    if issecretvalue and issecretvalue(link) then return false end
    return link:find("|Hkeystone:", 1, true) ~= nil
end

---True when a lean/hydrated storage row represents a Mythic+ keystone.
local function IsItemKeystoneEntry(item)
    if not item then return false end
    if item.isKeystone then return true end
    local link = item.itemLink or item.link
    if ItemLinkLooksKeystone(link) then return true end
    local id = item.itemID
    if id and C_Item and C_Item.IsItemKeystoneByID then
        local ok, isKs = pcall(C_Item.IsItemKeystoneByID, id)
        return ok and isKs == true
    end
    return false
end

---Stable display category for item lists (Bank virtual list + storage tree).
---Falls back from itemType -> classID -> Miscellaneous; keystones get KEYSTONE bucket.
local function ResolveItemCategoryName(item)
    local misc = (ns.L and ns.L["GROUP_MISC"]) or "Miscellaneous"
    local keystoneLbl = (ns.L and ns.L["KEYSTONE"]) or "Keystone"
    if IsItemKeystoneEntry(item) then
        return keystoneLbl
    end
    local itemType = item.itemType
    if itemType and itemType ~= "" then
        return itemType
    end
    local classID = item.classID
    if not classID and item.itemID then
        classID = GetItemClassID(item.itemID)
        item.classID = classID
    end
    if classID then
        local tn = GetItemTypeName(classID)
        if tn and tn ~= "" then return tn end
    end
    return misc
end

-- Get icon texture for item type
local function GetTypeIcon(classID)
    local icons = {
        [0] = "Interface\\Icons\\INV_Potion_51",          -- Consumable (Potion)
        [1] = "Interface\\Icons\\INV_Box_02",             -- Container
        [2] = "Interface\\Icons\\INV_Sword_27",           -- Weapon
        [3] = "Interface\\Icons\\INV_Misc_Gem_01",        -- Gem
        [4] = "Interface\\Icons\\INV_Chest_Cloth_07",     -- Armor
        [5] = "Interface\\Icons\\INV_Enchant_DustArcane", -- Reagent
        [6] = "Interface\\Icons\\INV_Ammo_Arrow_02",      -- Projectile
        [7] = "Interface\\Icons\\Trade_Engineering",      -- Trade Goods
        [8] = "Interface\\Icons\\INV_Misc_EnchantedScroll", -- Item Enhancement
        [9] = "Interface\\Icons\\INV_Scroll_04",          -- Recipe
        [12] = "Interface\\Icons\\INV_Misc_Key_03",       -- Quest (Key icon)
        [15] = "Interface\\Icons\\INV_Misc_Gear_01",      -- Miscellaneous
        [16] = "Interface\\Icons\\INV_Inscription_Tradeskill01", -- Glyph
        [17] = "Interface\\Icons\\PetJournalPortrait",    -- Battlepet
        [18] = "Interface\\Icons\\WoW_Token01",           -- WoW Token
    }
    return icons[classID] or "Interface\\Icons\\INV_Misc_Gear_01"
end

local function ResolveItemCategoryIcon(item, classID)
    if IsItemKeystoneEntry(item) then
        return KEYSTONE_CATEGORY_ICON
    end
    return GetTypeIcon(classID or (item and item.classID) or 15)
end

ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_IsItemKeystoneEntry = IsItemKeystoneEntry
ns.UI_ResolveItemCategoryName = ResolveItemCategoryName
ns.UI_ResolveItemCategoryIcon = ResolveItemCategoryIcon

-- CHARACTER ICON HELPERS (Faction, Race, Class)

--[[
    Get faction icon texture path
    @param faction string - "Alliance", "Horde", or "Neutral"
    @return string - Texture path
]]
local function GetFactionIcon(faction)
    if faction == "Alliance" then
        return "Interface\\FriendsFrame\\PlusManz-Alliance"
    elseif faction == "Horde" then
        return "Interface\\FriendsFrame\\PlusManz-Horde"
    else
        -- Neutral (Pandaren starting zone or unknown)
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    end
end

--[[
    Get race-gender icon atlas name
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female)
    @return string - Atlas name
]]
local function GetRaceGenderAtlas(raceFile, gender)
    if not raceFile then
        return "shop-icon-housing-characters-up"
    end

    local raceMap = Constants and Constants.RACE_FILE_TO_ATLAS_PREFIX
    local atlasRace = raceMap and raceMap[raceFile]
    if not atlasRace then
        return "shop-icon-housing-characters-up"  -- Fallback
    end
    
    local genderStr = (gender == 3) and "female" or "male"
    
    return string.format("raceicon128-%s-%s", atlasRace, genderStr)
end

--[[
    Get race icon - NOW RETURNS ATLAS (not texture path)
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @return string - Atlas name
]]
local function GetRaceIcon(raceFile, gender)
    -- Use atlas system with gender support
    return GetRaceGenderAtlas(raceFile, gender or 2)  -- Default to male if not provided
end

--[[
    Create faction icon on a frame
    @param parent frame - Parent frame
    @param faction string - "Alliance", "Horde", "Neutral"
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateFactionIcon(parent, faction, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetFactionIcon(faction))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

--[[
    Create race icon on a frame (NEW: Auto-uses race-gender atlases)
    @param parent frame - Parent frame
    @param raceFile string - English race name
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateRaceIcon(parent, raceFile, gender, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 28, size or 28)
    icon:SetPoint(point, x, y)
    
    -- Always use atlas system
    local atlasName = GetRaceIcon(raceFile, gender)  -- GetRaceIcon now returns atlas name
    icon:SetAtlas(atlasName, false)  -- false = don't use atlas size (we set it manually)
    
    -- Circular mask to hide grey corners on race atlas icons
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    icon._mask = mask  -- Store reference for cleanup
    
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return icon
end

-- Export to namespace
ns.UI_GetRaceIcon = GetRaceIcon
ns.UI_GetRaceGenderAtlas = GetRaceGenderAtlas
ns.UI_CreateFactionIcon = CreateFactionIcon
ns.UI_CreateRaceIcon = CreateRaceIcon
local function GetClassIcon(classFile)
    -- Use class crest icons (clean, no frame)
    local classIcons = {
        ["WARRIOR"] = "Interface\\Icons\\ClassIcon_Warrior",
        ["PALADIN"] = "Interface\\Icons\\ClassIcon_Paladin",
        ["HUNTER"] = "Interface\\Icons\\ClassIcon_Hunter",
        ["ROGUE"] = "Interface\\Icons\\ClassIcon_Rogue",
        ["PRIEST"] = "Interface\\Icons\\ClassIcon_Priest",
        ["DEATHKNIGHT"] = "Interface\\Icons\\ClassIcon_DeathKnight",
        ["SHAMAN"] = "Interface\\Icons\\ClassIcon_Shaman",
        ["MAGE"] = "Interface\\Icons\\ClassIcon_Mage",
        ["WARLOCK"] = "Interface\\Icons\\ClassIcon_Warlock",
        ["MONK"] = "Interface\\Icons\\ClassIcon_Monk",
        ["DRUID"] = "Interface\\Icons\\ClassIcon_Druid",
        ["DEMONHUNTER"] = "Interface\\Icons\\ClassIcon_DemonHunter",
        ["EVOKER"] = "Interface\\Icons\\ClassIcon_Evoker",
    }
    
    return classIcons[classFile] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--- Reset pooled/reused icon textures to full color (atlas + file icons).
local function EnsureTextureFullColor(tex)
    if not tex then return end
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    if tex.SetAlpha then tex:SetAlpha(1) end
    if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
end
ns.UI_EnsureTextureFullColor = EnsureTextureFullColor

--- Apply class icon (atlas with file fallback); safe for pooled textures.
local function ApplyClassIconTexture(tex, classFile)
    if not tex or not classFile or classFile == "" then return end
    local cf = classFile
    if type(cf) == "string" then
        cf = string.upper(cf)
    end
    if tex.SetTexture then
        tex:SetTexture(nil)
    end
    local atlasName = "classicon-" .. cf
    local applied = false
    if tex.SetAtlas then
        applied = pcall(tex.SetAtlas, tex, atlasName)
        if applied and tex.GetAtlas then
            local a = tex:GetAtlas()
            applied = a and a ~= ""
        end
    end
    if not applied then
        if tex.SetAtlas then
            pcall(tex.SetAtlas, tex, nil)
        end
        tex:SetTexture(GetClassIcon(cf))
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    EnsureTextureFullColor(tex)
end
ns.UI_ApplyClassIconTexture = ApplyClassIconTexture

--[[
    Create class icon on a frame
    @param parent frame - Parent frame
    @param classFile string - English class name (e.g., "WARRIOR")
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateClassIcon(parent, classFile, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    ApplyClassIconTexture(icon, classFile)
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

-- Exports
ns.UI_CreateClassIcon = CreateClassIcon

-- FAVORITE ICON HELPERS

-- Constants
local FAVORITE_ICON_ATLAS = "transmog-icon-favorite"
local FAVORITE_COLOR_ACTIVE = {1, 0.84, 0}  -- Gold
local FAVORITE_COLOR_INACTIVE = {0.5, 0.5, 0.5}  -- Gray

--[[
    Get favorite icon atlas name
    @return string - Atlas name
]]
local function GetFavoriteIconTexture()
    return FAVORITE_ICON_ATLAS
end

--[[
    Apply favorite icon styling
    @param texture texture - Texture object to style
    @param isFavorite boolean - Whether character is favorited
]]
local function StyleFavoriteIcon(texture, isFavorite)
    texture:SetAtlas(FAVORITE_ICON_ATLAS)
    if isFavorite then
        texture:SetDesaturated(false)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_ACTIVE))
    else
        texture:SetDesaturated(true)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_INACTIVE))
    end
end

--[[
    Create complete favorite button with click handler
    @param parent frame - Parent frame
    @param charKey string - Character key (name-realm)
    @param isFavorite boolean - Current favorite status
    @param size number - Button size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @param onToggle function - Callback(charKey) returns new status
    @return button - Created button
]]
local function CreateFavoriteButton(parent, charKey, isFavorite, size, point, x, y, onToggle)
    local iconSize = size * 0.65  -- 65% of button size
    local yOffset = y
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)  -- Keep button hitbox same size
    btn:SetPoint(point, x, yOffset)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER", 0, 0)
    StyleFavoriteIcon(icon, isFavorite)
    
    btn.icon = icon
    btn.charKey = charKey
    btn.isFavorite = isFavorite
    
    btn:SetScript("OnClick", function(self)
        local newStatus = onToggle(self.charKey)
        self.isFavorite = newStatus
        StyleFavoriteIcon(self.icon, newStatus)
    end)
    
    -- Add SetChecked method (mimic CheckButton) for compatibility
    function btn:SetChecked(checked)
        self.isFavorite = checked
        StyleFavoriteIcon(self.icon, checked)
    end
    
    return btn
end

-- Exports
ns.UI_StyleFavoriteIcon = StyleFavoriteIcon
ns.UI_CreateFavoriteButton = CreateFavoriteButton

-- ONLINE INDICATOR HELPERS

-- Constants
local ONLINE_ICON_TEXTURE = "Interface\\FriendsFrame\\StatusIcon-Online"
local ONLINE_ICON_SIZE = 16

--[[
    Get online indicator texture path
    @return string - Texture path
]]
local function GetOnlineIconTexture()
    return ONLINE_ICON_TEXTURE
end

--[[
    Create online indicator (simple texture, no interaction)
    @param parent frame - Parent frame
    @param size number - Icon size (optional, defaults to 16)
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateOnlineIndicator(parent, size, point, x, y)
    local indicator = parent:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(size or ONLINE_ICON_SIZE, size or ONLINE_ICON_SIZE)
    indicator:SetPoint(point, x, y)
    indicator:SetTexture(ONLINE_ICON_TEXTURE)
    return indicator
end

-- Exports
ns.UI_CreateOnlineIndicator = CreateOnlineIndicator

assert(ns.UI_CreateIcon and ns.UI_CreateCollapseExpandControl, "SharedWidgets_Icons: exports missing")
