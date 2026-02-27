--[[
    Warband Nexus - Collections Tab
    Placeholder for collection overview (mounts, pets, toys, etc.)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local COLORS = ns.UI_COLORS
local CreateHeaderIcon = ns.UI_CreateHeaderIcon
local GetTabIcon = ns.UI_GetTabIcon

--============================================================================
-- DRAW COLLECTIONS TAB
--============================================================================

function WarbandNexus:DrawCollectionsTab(parent)
    local yOffset = 8
    HideEmptyStateCard(parent, "collections")

    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)

    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("collections"))
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["COLLECTIONS_SUBTITLE"]) or "Mounts, pets, toys, and transmog overview"

    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetJustifyH("LEFT")
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)
    titleCard:Show()

    yOffset = yOffset + 75

    -- Placeholder empty state (content can be added later)
    local _, height = CreateEmptyStateCard(parent, "collections", yOffset)
    return yOffset + (height or 120)
end
