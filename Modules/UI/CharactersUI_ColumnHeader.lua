--[[
    Warband Nexus - Characters tab: column header strip (split satellite of CharactersUI.lua).
    One TableKit text strip (SharedWidgets_TableKit.lua) in the scroll body directly above the first
    character section. Display-only: roster sorting stays in the title-card Filter dropdown
    (profile.characterSort). Column defs + x positions come from ns.UI_ResolveCharRowHeaderColumns
    (SharedWidgets_CharRow.lua), the same column model DrawCharacterRow paints from.
    Optional: profile.ui.showCharactersColumnHeader == false hides it (nil = shown).
]]

local ADDON_NAME, ns = ...
local B = assert(ns.CharactersUI and ns.CharactersUI._bind, "CharactersUI_ColumnHeader: load Modules/UI/CharactersUI.lua first")
local TK = assert(ns.UI_TableKit, "SharedWidgets_TableKit.lua must load before CharactersUI_ColumnHeader.lua")
local WarbandNexus = B.WarbandNexus

local HEADER_STRIP_OPTS = {
    mode = "text",
    bottomRule = true,
}

-- Scratch reused every paint (TK.ResolveWidths trims stale tail entries).
local _hdrCols, _hdrWidths, _hdrOffsets = {}, {}, {}

local function PaintCharactersColumnHeader(strip, rowW)
    if not ns.UI_ResolveCharRowHeaderColumns then return end
    local guildW = WarbandNexus and WarbandNexus._charListMaxGuildWidth
    local n = ns.UI_ResolveCharRowHeaderColumns(rowW, guildW, _hdrCols, _hdrWidths, _hdrOffsets)
    if n > 0 then
        strip:SetColumns(_hdrCols, _hdrWidths, _hdrOffsets, n)
    end
end

---@param profile table|nil db.profile
---@return boolean
local function IsCharactersColumnHeaderEnabled(profile)
    local ui = profile and profile.ui
    return not (ui and ui.showCharactersColumnHeader == false)
end

--- Acquire (pooled on the scroll child, re-adopted after teardown like the gold card trio), anchor at
--- `yOffset` on the same [side .. side + stackW] band as section headers/rows, and paint.
---@return number yOffset advanced past the strip + gap
local function PlaceCharactersColumnHeader(parent, yOffset, contentSide, stackW, gap)
    local strip = parent._wnCharsColHeaderStrip
    if not strip then
        strip = TK.CreateHeaderStrip(parent, HEADER_STRIP_OPTS)
        parent._wnCharsColHeaderStrip = strip
    end
    local w = math.max(1, stackW or 1)
    strip:SetParent(parent)
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
    strip:SetWidth(w)
    PaintCharactersColumnHeader(strip, w)
    strip:Show()
    return yOffset + strip:GetStripHeight() + (gap or 0)
end

--- Live viewport relayout: follow the section stack width (rows re-chain flex columns at this width).
local function RelayoutCharactersColumnHeader(scrollChild, stackW)
    local strip = scrollChild and scrollChild._wnCharsColHeaderStrip
    if not strip or not strip:IsShown() or strip:GetParent() ~= scrollChild then return end
    local w = math.max(1, stackW or 1)
    strip:SetWidth(w)
    PaintCharactersColumnHeader(strip, w)
end

ns.CharactersUI.IsCharactersColumnHeaderEnabled = IsCharactersColumnHeaderEnabled
ns.CharactersUI.PlaceCharactersColumnHeader = PlaceCharactersColumnHeader
ns.CharactersUI.RelayoutCharactersColumnHeader = RelayoutCharactersColumnHeader
