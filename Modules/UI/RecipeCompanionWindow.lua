--[[
    Warband Nexus - Recipe Companion Window
    Floating, movable, resizable panel beside Blizzard's profession frame. It draws the same recipe
    detail pane as the saved-recipe window (ns.RecipeDetailUI, CharacterSystemsPopup) for the
    recipe selected in the profession frame: schematic, reagents with their per-character
    holdings and who knows the recipe -- one recipe view, two entry points.
    Position and size saved in db.global.recipeCompanion -- no anchor to ProfessionsFrame, so no
    overlap with the K window or the craft result.

    Data flow (read-only, saved data):
    WN_RECIPE_SELECTED            -> paint the selected recipe from the character's saved recipes
    WN_CHARACTER_SYSTEMS_UPDATED  -> repaint (the recipe scan that runs while the frame is open)
    BAG_UPDATE_DELAYED            -> repaint (have-counts changed)
    WN_PROFESSION_WINDOW_OPENED   -> RestorePosition + Show
    WN_PROFESSION_WINDOW_CLOSED   -> Hide (SavePosition in OnHide)
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end

local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 }, accentDark = { 0.25, 0.2, 0.35 } }
local ApplyVisuals = ns.UI_ApplyVisuals
local function ChromeBackdrop()
    return (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop())
        or COLORS.bgCard or COLORS.bgLight or COLORS.bg
end
local function ChromeBorder(alpha)
    alpha = alpha or 0.6
    return { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], alpha }
end
local function TextRoleHex(role)
    if ns.UI_GetTextRoleHexRaw then
        return ns.UI_GetTextRoleHexRaw(role)
    end
    if ns.UI_GetTextRoleRGB then
        local r, g, b = ns.UI_GetTextRoleRGB(role)
        return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    return "ffffff"
end

local function GetFactory()
    return ns.UI and ns.UI.Factory
end

-- Unique AceEvent handler identity for RecipeCompanionWindow
local RecipeCompanionEvents = {}

-- ── Layout constants ──
local PADDING = 8
local function RCGetFrameContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

local function RCGetCompanionHeaderHeight()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.RECIPE_COMPANION_HEADER_HEIGHT or 32
end
-- The detail pane needs room for reagent names plus the bags / bank columns.
local WINDOW_WIDTH = 380
local MAX_FRAME_WIDTH = 720
local MIN_FRAME_HEIGHT = 200
local MAX_FRAME_HEIGHT = 900
local DEFAULT_WIDTH = 440
local DEFAULT_HEIGHT = 560

-- ── State ──
local companionFrame = nil
local toggleTrackerBtn = nil       -- Button on ProfessionsFrame to toggle Recipe Companion
local currentRecipeID = nil
local currentRecipeName = nil
local companionRefreshTimer = nil
local COMPANION_REFRESH_DEBOUNCE = 0.12
local bagUpdateRegistered = false

-- FLOATING WINDOW POSITION (db.global.recipeCompanion)

-- Created / written through WindowManager (no View writes into db.global; 2026-10-22).
local COMPANION_DB_DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    width = DEFAULT_WIDTH,
    height = DEFAULT_HEIGHT,
}

local function GetDB()
    local WM = ns.WindowManager
    if not WM or not WM.GetFloatingWindowState then return nil end
    return WM:GetFloatingWindowState("recipeCompanion", COMPANION_DB_DEFAULTS)
end

local function SavePosition(frame)
    if not frame then return end
    local db = GetDB()
    if not db then return end
    if frame:GetNumPoints() < 1 then return end
    ns.WindowManager:SaveFloatingWindowGeometry("recipeCompanion", frame, true)
end

local function RestorePosition(frame)
    local db = GetDB()
    if not db then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    local w = db.width or DEFAULT_WIDTH
    local h = db.height or DEFAULT_HEIGHT
    if w < WINDOW_WIDTH then w = DEFAULT_WIDTH end
    if h < MIN_FRAME_HEIGHT then h = DEFAULT_HEIGHT end
    if h > MAX_FRAME_HEIGHT then h = MAX_FRAME_HEIGHT end
    frame:SetSize(w, h)
end

-- REFRESH

--[[
    Header: recipe name + crafts possible from materials (GetRecipeCraftCountFromMaterials — not quantityMax).
]]
local function FormatCompanionTitle(recipeID, recipeName)
    local name = recipeName or "Recipe"
    if recipeID and WarbandNexus and WarbandNexus.GetRecipeCraftCountFromMaterials then
        local n = WarbandNexus:GetRecipeCraftCountFromMaterials(recipeID)
        if n ~= nil and n >= 0 then
            return "|cff" .. TextRoleHex("Bright") .. name .. " (" .. n .. ")|r"
        end
    end
    return "|cff" .. TextRoleHex("Bright") .. name .. "|r"
end

--- The selected recipe from the logged-in character's saved recipes, and its profession entry.
local function FindLiveRecipe(recipeID)
    local U = ns.Utilities
    local charKey = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus)
    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    local row = charKey and chars and chars[charKey]
    local all = row and type(row.systems) == "table" and row.systems.recipes
    if not recipeID or type(all) ~= "table" or not WarbandNexus.GetProfessionRecipes then return nil, nil, charKey end
    for professionID in pairs(all) do
        local entry = WarbandNexus:GetProfessionRecipes(charKey, professionID)
        local list = entry and entry.recipes
        if list then
            for i = 1, #list do
                if list[i].id == recipeID then return list[i], entry, charKey end
            end
        end
    end
    return nil, nil, charKey
end

--- Paint the current recipe into the shared detail pane. Before the first recipe scan of this
--- profession has been saved the pane shows its select hint; the scan's message repaints it.
local function PaintCompanion()
    local frame = companionFrame
    if not frame or not frame.detail or not ns.RecipeDetailUI then return end
    local recipe, entry, charKey = FindLiveRecipe(currentRecipeID)
    ns.RecipeDetailUI.Paint(frame.detail, recipe, entry, charKey)
    -- Height follows the recipe (up to the cap and the screen), so a short recipe has no empty
    -- tail and a long one scrolls only past the cap; width stays the player's choice.
    if recipe and not InCombatLockdown() then
        local chrome = RCGetCompanionHeaderHeight() + RCGetFrameContentInset() * 2 + 2
        local screenH = (UIParent:GetHeight() or MAX_FRAME_HEIGHT) * 0.85
        local want = ns.RecipeDetailUI.ContentHeight(frame.detail) + chrome
        local h = math.max(MIN_FRAME_HEIGHT, math.min(want, MAX_FRAME_HEIGHT, screenH))
        if math.abs((frame:GetHeight() or 0) - h) > 1 then
            frame:SetHeight(h)
            ns.RecipeDetailUI.Relayout(frame.detail)
        end
    end
end

--[[
    Refresh companion window content (debounced).
]]
local function RefreshCompanion()
    if companionRefreshTimer and companionRefreshTimer.Cancel then
        companionRefreshTimer:Cancel()
    end
    companionRefreshTimer = C_Timer.NewTimer(COMPANION_REFRESH_DEBOUNCE, function()
        companionRefreshTimer = nil
        if not companionFrame or not companionFrame:IsShown() then return end
        if companionFrame.titleText and currentRecipeID and currentRecipeName then
            companionFrame.titleText:SetText(FormatCompanionTitle(currentRecipeID, currentRecipeName))
        end
        PaintCompanion()
    end)
end

-- EVENT HANDLERS

--[[
    Called when a recipe is selected in the profession UI.
    @param recipeInfo table - Contains recipeID, name, icon, etc.
]]
local function OnRecipeSelected(recipeInfo)
    if not recipeInfo or not recipeInfo.recipeID then return end
    if recipeInfo.recipeID == currentRecipeID then return end
    if WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false then return end

    currentRecipeID = recipeInfo.recipeID
    currentRecipeName = recipeInfo.name or "Recipe"

    if companionFrame and companionFrame.titleText then
        companionFrame.titleText:SetText(FormatCompanionTitle(recipeInfo.recipeID, currentRecipeName))
    end

    RefreshCompanion()
end

--[[
    Create the "Toggle Tracker" button on ProfessionsFrame (once).
    Toggles recipeCompanionEnabled and shows/hides the Recipe Companion.
]]
local function EnsureToggleTrackerButton()
    if toggleTrackerBtn then return end
    if not ProfessionsFrame then return end

    local Factory = GetFactory()
    if not Factory then return end

    local btn = Factory:CreateButton(ProfessionsFrame, 130, 24, false)
    btn:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMLEFT", 285, 5)
    if ApplyVisuals then
        ApplyVisuals(btn, ChromeBackdrop(), ChromeBorder(0.6))
    end
    local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    label:SetText((ns.L and ns.L["TOGGLE_TRACKER"]) or "Toggle Tracker")
    ns.UI_SetTextColorRole(label, "Bright")
    btn:SetScript("OnClick", function()
        if not WarbandNexus.db then return end
        WarbandNexus.db.profile.recipeCompanionEnabled = not (WarbandNexus.db.profile.recipeCompanionEnabled ~= false)
        if WarbandNexus.db.profile.recipeCompanionEnabled then
            if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.Show then
                ns.RecipeCompanionWindow.Show()
            end
        else
            if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.Hide then
                ns.RecipeCompanionWindow.Hide()
            end
        end
    end)
    toggleTrackerBtn = btn
end

--[[
    Called when profession window opens. Show companion at saved position (floating).
]]
local function OnProfessionWindowOpened()
    if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
    EnsureToggleTrackerButton()

    if not companionFrame then return end
    if WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false then return end

    RestorePosition(companionFrame)
    companionFrame:Show()
end

--[[
    Called when profession window closes.
]]
local function OnProfessionWindowClosed()
    if companionFrame then
        companionFrame:Hide()
    end
    currentRecipeID = nil
end

-- WINDOW CREATION

--[[
    Create the companion window frame. Floating, movable, resizable (like Plans Tracker).
    Called once during initialization; frame is reused.
]]
local function CreateCompanionWindow()
    if companionFrame then return companionFrame end

    local Factory = GetFactory()
    if not Factory then return nil end

    -- ── Main frame ──
    local frame = CreateFrame("Frame", "WarbandNexus_RecipeCompanion", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)

    -- WindowManager: standardized strata/level + ESC + combat hide
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:Register(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:InstallESCHandler(frame)
    else
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(120)
    end
    frame:SetResizeBounds(WINDOW_WIDTH, MIN_FRAME_HEIGHT, MAX_FRAME_WIDTH, MAX_FRAME_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:Hide()

    if ns.UI_ApplyFloatingWindowShellChrome then
        ns.UI_ApplyFloatingWindowShellChrome(frame)
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    elseif ApplyVisuals then
        ApplyVisuals(frame, (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or ChromeBackdrop(), ChromeBorder(0.7))
    end

    local bandH = RCGetCompanionHeaderHeight()
    local frameInset = RCGetFrameContentInset()

    -- ── Header (draggable) ──
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(bandH)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", frameInset, -frameInset)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -frameInset, -frameInset)
    header:EnableMouse(true)
    frame._rcHeader = header
    if ns.WindowManager and ns.WindowManager.InstallDragHandler then
        ns.WindowManager:InstallDragHandler(header, frame, function()
            if SavePosition then SavePosition(frame) end
        end)
    else
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function()
            if not InCombatLockdown() then
                frame:StartMoving()
            end
        end)
        header:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            if SavePosition then SavePosition(frame) end
        end)
    end
    if ApplyVisuals then
        if ns.UI_ApplyFloatingWindowHeaderChrome then
            ns.UI_ApplyFloatingWindowHeaderChrome(header)
        else
            ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }, ChromeBorder(0.6))
        end
    end

    -- Header icon (profession/recipe icon)
    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(18, 18)
    hIcon:SetPoint("LEFT", PADDING + 2, 0)
    hIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    frame.headerIcon = hIcon

    -- Title
    local titleFontRole = (FontManager.GetFontRole and FontManager:GetFontRole("windowChromeTitle")) or "body"
    local titleText = FontManager:CreateFontString(header, titleFontRole, "OVERLAY")
    titleText:SetPoint("LEFT", hIcon, "RIGHT", 6, 0)
    titleText:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetMaxLines(1)
    titleText:SetText((ns.L and ns.L["RECIPE_COMPANION_TITLE"]) or "Recipe Companion")
    ns.UI_SetTextColorRole(titleText, "Bright")
    frame.titleText = titleText

    -- ── Content area ──
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", frameInset, -(frameInset + bandH))
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frameInset, frameInset)
    frame.contentArea = contentArea

    -- ── Recipe detail: the shared pane (it owns its scroll frame and scrollbar lane) ──
    if ns.RecipeDetailUI then
        frame.detail = ns.RecipeDetailUI.Create(contentArea, DEFAULT_WIDTH - frameInset * 2, frame)
    end

    -- ── Resize grip (bottom-right) ──
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frameInset, frameInset)
    resizer:SetNormalTexture(ns.UI_GetIconFile("resize_grip"))
    resizer:SetHighlightTexture(ns.UI_GetIconFile("resize_grip"))
    resizer:SetPushedTexture(ns.UI_GetIconFile("resize_grip"))
    resizer:SetScript("OnMouseDown", function()
        if not InCombatLockdown() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    local function CompanionSatelliteLiveLayout()
        if frame.detail and ns.RecipeDetailUI then ns.RecipeDetailUI.Relayout(frame.detail) end
    end

    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        CompanionSatelliteLiveLayout(frame)
        local LC = ns.UI_LayoutCoordinator
        if LC and LC.OnSatelliteMetricsChanged then
            LC:OnSatelliteMetricsChanged(frame, frame:GetWidth(), frame:GetHeight(), true)
        else
            CompanionSatelliteLiveLayout()
        end
    end)

    local LC = ns.UI_LayoutCoordinator
    if LC and LC.RegisterSatelliteFrame then
        LC:RegisterSatelliteFrame(frame, {
            onLive = CompanionSatelliteLiveLayout,
            onCommit = CompanionSatelliteLiveLayout,
        })
    else
        frame:SetScript("OnSizeChanged", function()
            CompanionSatelliteLiveLayout(frame)
        end)
    end

    -- ── Escape key: close companion and profession window together ──
    local function SetupKeyboard()
        if InCombatLockdown() then return false end
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
                -- Close profession window too so one ESC closes both
                if ProfessionsFrame and ProfessionsFrame:IsShown() then
                    if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then
                        C_TradeSkillUI.CloseTradeSkill()
                    else
                        ProfessionsFrame:Hide()
                    end
                end
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)
        return true
    end
    if not SetupKeyboard() then
        local kbDefer = CreateFrame("Frame")
        kbDefer:RegisterEvent("PLAYER_REGEN_ENABLED")
        kbDefer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            SetupKeyboard()
        end)
    end

    -- ── OnShow: paint (select hint or the recipe) so first open is not a blank panel ──
    frame:SetScript("OnShow", function()
        RefreshCompanion()
    end)

    frame:SetScript("OnHide", function()
        SavePosition(frame)
    end)

    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(frame)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(frame)
    end

    companionFrame = frame
    return frame
end

-- INITIALIZATION (called from EventManager after events are wired)

function WarbandNexus:InitializeRecipeCompanion()
    -- Create the frame (hidden)
    CreateCompanionWindow()

    -- NOTE: Uses RecipeCompanionEvents as 'self' key to avoid overwriting other modules' handlers.
    -- Listen for recipe selection (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.RECIPE_SELECTED, function(_, recipeInfo)
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        OnRecipeSelected(recipeInfo)
    end)

    -- Listen for profession window lifecycle (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.PROFESSION_WINDOW_OPENED, function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        OnProfessionWindowOpened()
    end)

    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.PROFESSION_WINDOW_CLOSED, function()
        OnProfessionWindowClosed()
    end)

    -- BAG_UPDATE_DELAYED: refresh counts when inventory changes (guard with module check)
    -- Uses RecipeCompanionEvents as 'self' key so we don't overwrite
    -- ItemsCacheService's BAG_UPDATE_DELAYED → OnInventoryBagsChanged handler.
    if not bagUpdateRegistered then
        bagUpdateRegistered = true
        WarbandNexus.RegisterEvent(RecipeCompanionEvents, "BAG_UPDATE_DELAYED", function()
            if not ns.Utilities:IsModuleEnabled("professions") then return end
            if companionFrame and companionFrame:IsShown() and currentRecipeID then
                RefreshCompanion()
            end
        end)
    end

    -- The recipe scan saved new rows for this character: repaint from them.
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.CHARACTER_SYSTEMS_UPDATED, function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        if companionFrame and companionFrame:IsShown() and currentRecipeID then
            RefreshCompanion()
        end
    end)

    -- WN_RECIPE_DATA_UPDATED: refresh when recipe scan completes (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.RECIPE_DATA_UPDATED, function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        if companionFrame and companionFrame:IsShown() and currentRecipeID then
            RefreshCompanion()
        end
    end)

    WarbandNexus.RegisterMessage(RecipeCompanionEvents, E.FONT_CHANGED, function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        if companionFrame and companionFrame:IsShown() then
            if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.RefreshTheme then
                ns.RecipeCompanionWindow.RefreshTheme()
            else
                RefreshCompanion()
            end
        end
    end)
end

-- EXPORT

ns.RecipeCompanionWindow = {
    Show = function()
        if companionFrame and not (WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false) then
            OnProfessionWindowOpened()
        end
    end,
    Hide = function()
        if companionFrame then
            OnProfessionWindowClosed()
        end
    end,
    Refresh = RefreshCompanion,
    RefreshTheme = function()
        if ns.FontManager and ns.FontManager.RefreshThemeTypography then
            ns.FontManager:RefreshThemeTypography()
        end
        local frame = companionFrame
        if not frame then return end
        if ns.UI_ApplyFloatingWindowShellChrome then
            ns.UI_ApplyFloatingWindowShellChrome(frame)
        elseif ns.UI_ApplyStandardCardElevatedChrome then
            ns.UI_ApplyStandardCardElevatedChrome(frame)
        end
        local hdr = frame._rcHeader
        if hdr then
            if ns.UI_ApplyFloatingWindowHeaderChrome then
                ns.UI_ApplyFloatingWindowHeaderChrome(hdr)
            elseif ApplyVisuals then
                ApplyVisuals(hdr, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }, ChromeBorder(0.6))
            end
        end
        if frame.titleText then
            ns.UI_SetTextColorRole(frame.titleText, "Bright")
        end
        if toggleTrackerBtn and ApplyVisuals then
            ApplyVisuals(toggleTrackerBtn, ChromeBackdrop(), ChromeBorder(0.6))
        end
        if frame:IsShown() then
            RefreshCompanion()
        end
    end,
}
