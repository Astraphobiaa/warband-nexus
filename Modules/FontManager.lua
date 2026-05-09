--[[
    Warband Nexus - Font Manager
    Centralized font management with resolution-aware scaling
    Font sizes follow WoW UI Scale via the frame hierarchy; optional normalization
    applies a DPI comfort factor: sqrt(physH / 1080) — no effectiveScale division.

    TYPOGRAPHY STANDARD (use only these roles via CreateFontString(parent, role, layer)):
    - header   : Section titles, tab labels, main card headings (largest)
    - title    : Card titles, dialog titles
    - subtitle : Secondary headings, section descriptions
    - body     : Default text, labels, list content
    - small    : Captions, hints, metadata, secondary info (smallest)
    Alias: "smalltext" -> "small"

    Semantic aliases (tek yerden tema): FontManager:GetFontRole("gearStatLabel") → one of the above.
    Tab/modül bazlı eşleme: FontManager.FONT_ROLE / ns.UI_FONT_ROLE.
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local E = ns.Constants.EVENTS

-- LibSharedMedia-3.0 (optional): shared font/media handling; silent fail if missing
local LSM = (LibStub and LibStub("LibSharedMedia-3.0", true)) or nil

-- Debug print helper
local DebugPrint = ns.DebugPrint
local FontManager = {}

--[[
    Semantic UI roles → size category (tek noktadan tema / Gear ve diğer sekmeler).
    CreateFontString: FontManager:CreateFontString(parent, FontManager:GetFontRole("gearStatLabel"), layer)
]]
FontManager.FONT_ROLE = {
    --------------------------------------------------------------------
    -- Paylaşılan sekme / başlık / diyalog (tüm UI tek yerden)
    --------------------------------------------------------------------
    tabTitlePrimary = "header",
    tabSubtitle = "subtitle",
    sectionCollapsibleTitle = "title",
    popupDialogTitle = "title",
    settingsSectionTitle = "header",
    noticeTitle = "body",
    noticeBody = "small",
    statsBarText = "small",
    emptyStateTitle = "title",
    emptyStateBody = "body",
    emptyCardTitle = "header",
    emptyCardBody = "body",
    moduleDisabledTitle = "header",
    moduleDisabledBody = "body",
    loadingCardTitle = "title",
    loadingCardProgress = "body",
    loadingCardHint = "small",
    loadingPanelTitle = "title",
    loadingPanelProgress = "body",
    errorCardBody = "body",
    resetTimerText = "body",
    searchPlaceholder = "body",
    searchButtonText = "body",
    versionBadge = "small",
    tryPopupHeader = "title",
    tryPopupBody = "body",
    dialogButtonLabel = "body",
    listRowLabel = "body",
    listRowValue = "body",
    listRowQty = "body",
    listRowLocation = "body",
    factorySectionHeaderTitle = "title",
    factorySectionHeaderRight = "body",
    factoryDataRowLabel = "body",
    factoryDataRowRight = "small",
    cardHeaderLabel = "subtitle",
    cardHeaderValue = "body",

    --------------------------------------------------------------------
    -- Ana pencere başlığı, nav sekmeleri, shell (UI.lua / WindowFactory)
    --------------------------------------------------------------------
    windowChromeTitle = "title",
    mainNavTabLabel = "body",
    mainNavTabCount = "small",
    mainShellTrackingStatus = "body",
    trackingRequiredBannerTitle = "title",
    trackingRequiredBannerBody = "body",
    collectionAchievementPopupName = "title",
    collectionAchievementPopupBody = "body",
    collectionAchievementPopupButton = "body",
    loadingBarPrimaryText = "body",
    loadingBarSecondaryText = "body",
    searchEditBoxBody = "body",

    --------------------------------------------------------------------
    -- PvE sekmesi — kart başlığı / vault tracker etiketi
    --------------------------------------------------------------------
    pveVaultCardCharName = "title",
    pveVaultCardRealm = "subtitle",
    pveVaultCardStatus = "subtitle",
    pveTitleCardCheckboxLabel = "body",

    --------------------------------------------------------------------
    -- Gear tab — panels & stats (3 sütun grid ile uyumlu body/small dengesi)
    --------------------------------------------------------------------
    gearPanelTitle = "title",
    gearSectionTitle = "title",
    gearStatLabel = "body",
    gearStatPct = "body",
    gearStatRating = "body",
    gearPrimaryMid = "small",
    gearCurrencyLabel = "body",
    gearCurrencyAmount = "body",
    gearGoldLabel = "body",
    gearGoldAmount = "body",
    gearStorageCardTitle = "title",
    gearStorageSubtitle = "subtitle",
    gearStorageEmpty = "small",
    gearStorageRow = "body",
    gearStorageSource = "small",
    gearCharacterName = "title",
    gearPortraitLine = "title",
    gearPortraitMeta = "small",
    gearIlvlBadge = "subtitle",
    gearSlotIlvl = "small",
    gearSlotName = "body",
    gearTrackLabel = "body",
    gearChromeHint = "small",
    gearEmptyStatsHint = "body",
    gearCharSelector = "body",
}

---@param roleKey string
---@return string category header|title|subtitle|body|small
function FontManager:GetFontRole(roleKey)
    if not roleKey or type(roleKey) ~= "string" then return "body" end
    local cat = self.FONT_ROLE and self.FONT_ROLE[roleKey]
    if type(cat) == "string" and cat ~= "" then return cat end
    return "body"
end

--============================================================================
-- CONFIGURATION
--============================================================================

-- Migration: map old DB path values to LSM keys (for profiles created before LSM integration)
local PATH_TO_LSM_KEY = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata TT",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\skurri.TTF"] = "Skurri",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf"] = "Action Man",
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf"] = "Continuum Medium",
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf"] = "Expressway",
}

-- Fallback when LSM is not loaded (LSM key -> display name for dropdowns)
local FALLBACK_FONT_OPTIONS = {
    ["Friz Quadrata TT"] = "Friz Quadrata TT",
    ["Arial Narrow"] = "Arial Narrow",
    ["Skurri"] = "Skurri",
    ["Morpheus"] = "Morpheus",
    ["Action Man"] = "Action Man",
    ["Continuum Medium"] = "Continuum Medium",
    ["Expressway"] = "Expressway",
}

-- Reverse lookup: LSM key -> font path (used when LSM is not loaded to resolve keys)
local LSM_KEY_TO_PATH = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\skurri.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Action Man"] = "Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf",
    ["Continuum Medium"] = "Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf",
    ["Expressway"] = "Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf",
}

-- Register addon custom fonts with LSM (Latin-only; LSM filters by locale on Register)
if LSM and LSM.MediaType and LSM.LOCALE_BIT_western then
    LSM:Register("font", "Action Man", "Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf", LSM.LOCALE_BIT_western)
    LSM:Register("font", "Continuum Medium", "Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf", LSM.LOCALE_BIT_western)
    LSM:Register("font", "Expressway", "Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf", LSM.LOCALE_BIT_western)
end

--============================================================================
-- FONT PRELOADING (forces WoW to load .ttf files during loading screen)
--============================================================================
-- CreateFont() objects tell WoW's engine to load font files BEFORE PLAYER_LOGIN.
-- Without this, custom .ttf files are loaded lazily on first SetFont() call,
-- causing blank text on early UI elements (e.g., notifications) because the GPU
-- hasn't rasterized the glyphs yet. SetFont() returns true (path valid) but
-- renders nothing -- the fallback never triggers.
-- This runs at FILE LOAD TIME (during loading screen), guaranteeing fonts are
-- ready before any UI code executes.

local PRELOADED_FONTS = {}
for key, path in pairs(LSM_KEY_TO_PATH) do
    local safeName = "WN_FontPreload_" .. key:gsub("[^%w]", "_")
    local fontObj = CreateFont(safeName)
    if fontObj and fontObj.SetFont then
        pcall(function()
            fontObj:SetFont(path, 12, "")
        end)
        PRELOADED_FONTS[path] = fontObj
    end
end

-- Build font options: LSM keys -> display label (key as label); or fallback path -> name
local function GetFilteredFontOptions()
    if LSM and LSM.List and LSM.MediaType then
        local list = LSM:List(LSM.MediaType.FONT)
        if list and #list > 0 then
            local out = {}
            for i = 1, #list do
                local key = list[i]
                out[key] = key
            end
            return out
        end
    end
    return FALLBACK_FONT_OPTIONS
end

-- Anti-aliasing options
local AA_OPTIONS = {
    none = "",
    OUTLINE = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
}

--============================================================================
-- PRIVATE HELPERS
--============================================================================

-- Get active scale multiplier from user settings
-- CRITICAL: Safe fallback if DB not initialized yet (prevents ghost window bug)
local function GetScaleMultiplier()
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        DebugPrint("|cffffff00[WN FontManager]|r WARNING: Database not ready, using default scale (1.0)")
        return 1.0
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then 
        return 1.0 
    end
    
    return db.scaleCustom or 1.0
end

--[[
    Resolution-aware scaling factor for FONT sizes.

    WoW's SetFont() uses logical points in the 768-unit coordinate space.
    UIParent scales these up via effectiveScale, so on a 4K monitor at
    UI Scale 1.0 a "12pt" font already renders at the correct physical size.
    No division by physH or effectiveScale is needed — that would shrink text.

    What we DO want: a small bump on very-high-DPI screens (≥ 1440p) where
    even correctly scaled 12pt feels physically tiny (small monitor, high PPI).
    We scale font sizes by  sqrt(physH / 1080):
      1080p → 1.00   (no change)
      1440p → 1.15
      2160p → 1.41   (4K: ~40 % larger base sizes, nicely readable)
    This is purely a DPI comfort factor, not a coordinate-space conversion.

    Cached per session; invalidated on DISPLAY_SIZE_CHANGED via ResetPixelScale.
]]
local cachedFontResNorm = nil
local function GetFontResolutionNormalization()
    if cachedFontResNorm then return cachedFontResNorm end
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    else
        local resolution = GetCVar("gxWindowedResolution") or "1920x1080"
        local _, h = string.match(resolution, "(%d+)x(%d+)")
        h = tonumber(h)
        if h and h > 0 then physH = h end
    end
    if physH <= 0 then physH = 1080 end
    cachedFontResNorm = math.sqrt(physH / 1080)
    return cachedFontResNorm
end

--============================================================================
-- FONT WARM-UP (forces GPU to rasterize custom fonts before use)
--============================================================================

-- Reusable off-screen frame for font preloading
local warmupFrame = nil
local warmupFontStrings = {}   -- pool of FontStrings on the warmup frame
local warmedUpPaths = {}       -- set of paths already warmed up this session

-- Create or return the off-screen warm-up frame (lazy init)
local function GetWarmupFrame()
    if not warmupFrame then
        warmupFrame = CreateFrame("Frame", "WarbandNexus_FontWarmup", UIParent)
        warmupFrame:SetSize(10, 10)
        warmupFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10000, -10000)  -- off-screen
        warmupFrame:SetAlpha(0.01)  -- visible to GPU (alpha > 0) but invisible to player
        warmupFrame:Hide()
    end
    return warmupFrame
end

-- Get or create a FontString from the warm-up pool
local function AcquireWarmupFontString(index)
    local frame = GetWarmupFrame()
    if not warmupFontStrings[index] then
        warmupFontStrings[index] = frame:CreateFontString(nil, "OVERLAY")
    end
    return warmupFontStrings[index]
end

--[[
    Warm up a single font path: force GPU rasterization by rendering text off-screen.
    @param fontPath string - Font file path
    @param slotIndex number - Pool slot (allows multiple concurrent warm-ups)
]]
local function WarmupFontPath(fontPath, slotIndex)
    if not fontPath or fontPath == "" then return end
    if warmedUpPaths[fontPath] then return end  -- already warm
    local fs = AcquireWarmupFontString(slotIndex or 1)
    local ok = false
    pcall(function()
        ok = fs:SetFont(fontPath, 14, "OUTLINE")
    end)
    if ok then
        fs:SetText("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        warmedUpPaths[fontPath] = true
    end
end

--[[
    Warm up all known fonts + the user's currently selected font.
    Called at PLAYER_LOGIN as secondary insurance after CreateFont() preloading.
    Also warms up fonts from other addons (via LSM) that weren't preloaded at file time.
]]
local function WarmupAllFonts()
    local frame = GetWarmupFrame()
    frame:Show()
    -- Warm up all fonts in the reverse lookup table (includes custom + built-in)
    local slot = 0
    for key, path in pairs(LSM_KEY_TO_PATH) do
        slot = slot + 1
        WarmupFontPath(path, slot)
    end
    -- Also warm up the user's currently selected font (may be from another addon via LSM)
    local selectedPath = FontManager:GetFontFace()
    if selectedPath and not warmedUpPaths[selectedPath] then
        slot = slot + 1
        WarmupFontPath(selectedPath, slot)
    end
    -- Keep frame visible for 2 seconds so GPU finishes rasterization, then hide
    C_Timer.After(2.0, function()
        if warmupFrame then
            warmupFrame:Hide()
        end
    end)
end

-- PLAYER_LOGIN handler: warm up fonts early, before any UI opens
local warmupLoader = CreateFrame("Frame")
warmupLoader:RegisterEvent("PLAYER_LOGIN")
warmupLoader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    WarmupAllFonts()
end)

--============================================================================
-- FONT REGISTRY (for live updates)
--============================================================================

-- Registry of all FontStrings created via FontManager
local FONT_REGISTRY = {}

--============================================================================
-- PUBLIC API
--============================================================================

--[[
    Calculate final font size for a given category
    Applies: base size → user scale → pixel normalization
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @param category string - Font category ("header", "title", "subtitle", "body", "small")
    @return number - Final font size in pixels
]]
function FontManager:GetFontSize(category)
    -- Normalize aliases to canonical categories
    if category == "smalltext" or category == "tiny" then
        category = "small"
    else
        category = category or "body"
    end
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        DebugPrint("|cffffff00[WN FontManager]|r WARNING: Database not ready, using default font size")
        local defaults = {
            header = 16,
            title = 14,
            subtitle = 12,
            body = 12,
            small = 10,
        }
        return defaults[category] or 12
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db or not db.baseSizes then
        -- Fallback to defaults
        local defaults = {
            header = 16,
            title = 14,
            subtitle = 12,
            body = 12,
            small = 10,
        }
        return defaults[category] or 12
    end
    local baseSize = db.baseSizes[category] or 12
    local scaleMultiplier = GetScaleMultiplier()
    local resNorm = db.usePixelNormalization and GetFontResolutionNormalization() or 1.0

    -- Final: base × addon font slider × resolution normalization (not WoW UI Scale).
    -- WoW UI Scale still scales rendered text via UIParent / frame effective scale.
    local finalSize = baseSize * scaleMultiplier * resNorm
    
    -- Clamp to reasonable bounds (6px - 72px)
    -- Upper bound must accommodate 4K + resolution normalization + user scale slider
    return math.max(6, math.min(72, finalSize))
end

--[[
    Get anti-aliasing flags from user settings
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @return string - Font flags ("", "OUTLINE", or "THICKOUTLINE")
]]
function FontManager:GetAAFlags()
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        return "OUTLINE"  -- Safe default
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then return "OUTLINE" end
    
    return AA_OPTIONS[db.antiAliasing] or "OUTLINE"
end

-- Default font path when LSM unavailable or key invalid
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_LSM_KEY = "Friz Quadrata TT"

-- Resolve DB fontFace (LSM key or legacy path) to file path; migrate path -> key in DB when possible
local function ResolveFontFaceFromDB(db)
    if not db or type(db.fontFace) ~= "string" or db.fontFace == "" then
        return DEFAULT_FONT_PATH
    end
    local value = db.fontFace
    local key = value
    -- Migration: if value is a legacy path, convert to LSM key and write back
    if value:find("\\") and PATH_TO_LSM_KEY[value] then
        key = PATH_TO_LSM_KEY[value]
        db.fontFace = key
    end
    -- Primary: resolve via LSM
    if LSM and LSM.Fetch and LSM.MediaType then
        local path = LSM:Fetch(LSM.MediaType.FONT, key)
        if path and path ~= "" then
            return path
        end
    end
    -- Fallback: resolve key via built-in lookup (LSM not loaded)
    if LSM_KEY_TO_PATH[key] then
        return LSM_KEY_TO_PATH[key]
    end
    -- Last resort: if value looks like a path, use it directly
    if value:find("\\") then
        return value
    end
    return DEFAULT_FONT_PATH
end

--[[
    Get font face path from user settings
    Returns WoW font path (for SetFont). Uses LSM when available; migrates old path DB values to LSM keys.
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @return string - Font file path
]]
function FontManager:GetFontFace()
    if not ns or not ns.db then
        return DEFAULT_FONT_PATH
    end
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then return DEFAULT_FONT_PATH end
    local path = ResolveFontFaceFromDB(db)
    return path
end

--[[
    SAFE: Apply font to a FontString with error handling
    Prevents errors during early initialization when db might not be ready
    @param fontString FontString - The font string to apply font to
    @param sizeCategory string - Font size category ("header", "title", "subtitle", "body", "small")
    @return boolean - Success/failure
]]
function FontManager:SafeSetFont(fontString, sizeCategory)
    if not fontString or not fontString.SetFont then
        return false
    end
    
    local fontPath = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize(sizeCategory or "body")
    local flags = FontManager:GetAAFlags()
    
    if type(fontPath) ~= "string" or fontPath == "" then
        fontPath = DEFAULT_FONT_PATH
    end
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    if type(flags) ~= "string" then
        flags = "OUTLINE"
    end
    
    local ok = false
    local success = pcall(function()
        ok = fontString:SetFont(fontPath, fontSize, flags)
    end)
    
    if not success or not ok then
        -- Try preloaded FontObject
        local preloaded = PRELOADED_FONTS[fontPath]
        if preloaded then
            pcall(function()
                fontString:SetFontObject(preloaded)
                fontString:SetFont(fontPath, fontSize, flags)
            end)
        else
            pcall(function()
                fontString:SetFont(DEFAULT_FONT_PATH, fontSize, flags)
            end)
        end
        return false
    end
    return true
end

--[[
    Create a new FontString with managed font settings
    Factory method for creating font strings with automatic scaling
    @param parent Frame - Parent frame
    @param category string - Font category ("header", "title", "subtitle", "body", "small")
    @param layer string - Draw layer (default "OVERLAY")
    @param colorType string - Color type ("normal", "accent") for live theme updates (default "normal")
    @return FontString - Configured font string
]]
function FontManager:CreateFontString(parent, category, layer, colorType)
    if not parent then
        return nil
    end
    
    layer = layer or "OVERLAY"
    category = category or "body"
    colorType = colorType or "normal"
    
    local fs = parent:CreateFontString(nil, layer)
    if fs then
        self:ApplyFont(fs, category)
        
        -- Register for live updates (font AND color)
        fs._fontCategory = category
        fs._colorType = colorType
        table.insert(FONT_REGISTRY, fs)
    end
    
    return fs
end

--[[
    Apply font settings to an existing FontString
    Updates font face, size, and anti-aliasing flags
    @param fontString FontString - Target font string
    @param category string - Font category
]]
function FontManager:ApplyFont(fontString, category)
    if not fontString then
        return
    end
    
    -- Extra safety: check if the FontString is still valid (parent not garbage collected)
    if not fontString.SetFont or not fontString.GetText then
        return
    end
    
    if category == "smalltext" or category == "tiny" then
        category = "small"
    else
        category = category or "body"
    end
    
    local fontFace = self:GetFontFace()
    local fontSize = self:GetFontSize(category)
    local flags = self:GetAAFlags()
    
    if type(fontFace) ~= "string" or fontFace == "" then
        fontFace = DEFAULT_FONT_PATH
    end
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    
    if type(flags) ~= "string" then
        flags = "OUTLINE"
    end
    
    -- Save existing text before font change (for re-render)
    local existingText = fontString:GetText()
    
    -- Try SetFont with resolved path
    local ok = false
    local success = pcall(function()
        ok = fontString:SetFont(fontFace, fontSize, flags)
    end)
    
    if not success or not ok then
        DebugPrint("|cffff0000[WN FontManager]|r Font load failed for: " .. tostring(fontFace))
        -- Try preloaded FontObject (guaranteed loaded at file time)
        local preloaded = PRELOADED_FONTS[fontFace]
        if preloaded then
            pcall(function()
                fontString:SetFontObject(preloaded)
                -- Override size/flags from the prototype
                fontString:SetFont(fontFace, fontSize, flags)
            end)
        else
            -- Last resort: default WoW font
            local fallbackOk = false
            pcall(function()
                fallbackOk = fontString:SetFont(DEFAULT_FONT_PATH, fontSize, flags)
            end)
            if not fallbackOk then
                if fontString.SetFontObject then
                    fontString:SetFontObject("GameFontNormal")
                end
            end
        end
    end
    
    -- Force re-render by re-setting existing text (never pass secret values back into SetText)
    if existingText and not (issecretvalue and issecretvalue(existingText)) and existingText ~= "" then
        fontString:SetText(existingText)
    end
end

-- Internal: apply font to all registered FontStrings (called after warm-up)
local function ApplyToAllRegistered()
    local updated, removed = 0, 0
    for i = #FONT_REGISTRY, 1, -1 do
        local fs = FONT_REGISTRY[i]
        if not fs or not fs.SetFont or not fs.GetText then
            table.remove(FONT_REGISTRY, i)
            removed = removed + 1
        else
            local category = fs._fontCategory or "body"
            FontManager:ApplyFont(fs, category)
            updated = updated + 1
        end
    end
end

--[[
    Trigger global UI refresh to apply new font settings.
    Warms up the target font first (forces GPU rasterization), then applies after a short delay.
    Called when user changes font settings in Config / SettingsUI.
]]
function FontManager:RefreshAllFonts()
    -- Clear pixel scale cache (borders) and font resolution cache
    if ns.ResetPixelScale then
        ns.ResetPixelScale()
    end
    cachedFontResNorm = nil

    local fontPath = self:GetFontFace()
    local needsWarmup = fontPath and not warmedUpPaths[fontPath]

    if needsWarmup then
        -- Warm up the new font: show off-screen frame, render text, wait for GPU
        local frame = GetWarmupFrame()
        frame:Show()
        WarmupFontPath(fontPath, #warmupFontStrings + 1)
        -- Wait one frame for GPU to rasterize, then apply to all FontStrings
        C_Timer.After(0.05, function()
            ApplyToAllRegistered()
            -- Fire font changed event after apply completes
            C_Timer.After(0.15, function()
                if warmupFrame then warmupFrame:Hide() end
                if ns.WarbandNexus and ns.WarbandNexus.SendMessage then
                    ns.WarbandNexus:SendMessage(E.FONT_CHANGED)
                end
            end)
        end)
    else
        -- Font already warm: apply immediately
        ApplyToAllRegistered()
        C_Timer.After(0.2, function()
            if ns.WarbandNexus and ns.WarbandNexus.SendMessage then
                ns.WarbandNexus:SendMessage(E.FONT_CHANGED)
            end
        end)
    end
end

--[[
    Refresh all FontStrings using accent colors
    Called when user changes theme color
]]
function FontManager:RefreshAccentColors()
    if not ns.UI_COLORS then return end
    
    local accentColor = ns.UI_COLORS.accent
    local updated = 0
    
    -- Update ALL registered FontStrings with accent color
    for i = #FONT_REGISTRY, 1, -1 do
        local fs = FONT_REGISTRY[i]
        
        -- Check if FontString still exists
        if not fs or not fs.SetTextColor then
            table.remove(FONT_REGISTRY, i)
        elseif fs._colorType == "accent" then
            -- Update accent-colored text
            fs:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
            updated = updated + 1
        end
    end
end

--[[
    Get font preview text for settings panel
    Shows calculated sizes for all categories
    @return string - Formatted preview text
]]
function FontManager:GetPreviewText()
    local lines = {}
    local categories = {"header", "title", "subtitle", "body", "small"}
    
    for ci = 1, #categories do
        local cat = categories[ci]
        local size = self:GetFontSize(cat)
        table.insert(lines, string.format("%s: %dpx", cat:gsub("^%l", string.upper), math.floor(size)))
    end
    
    return table.concat(lines, " | ")
end

-- Export to namespace
ns.FontManager = FontManager
ns.GetFilteredFontOptions = GetFilteredFontOptions
--- Tek kaynak font rol tablosu (modüller doğrudan okuyabilir)
ns.UI_FONT_ROLE = FontManager.FONT_ROLE

--- Global helper for UI modules: semantic role → category string
function ns.GetFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- Notify UI when other addons register new fonts (LSM callback)
if LSM and LSM.RegisterCallback then
    LSM.RegisterCallback(FontManager, "LibSharedMedia_Registered", function(_, mediatype)
        if mediatype == "font" and ns.WarbandNexus and ns.WarbandNexus.SendMessage then
            ns.WarbandNexus:SendMessage(E.FONT_LIST_UPDATED)
        end
    end)
end