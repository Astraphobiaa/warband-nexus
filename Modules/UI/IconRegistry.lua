--[[
    Warband Nexus - Icon Registry
    Semantic icon keys -> verified Blizzard atlases, with a file-texture fallback.

    Every atlas listed here was confirmed against Blizzard FrameXML 12.1.5 (70391)
    (Gethe/wow-ui-source live) on 2026-10-14. Do NOT add an atlas name that has no
    reference in FrameXML; add a file fallback instead.

    Loads early (after Constants.lua, .toc) so load-time markup constants in services,
    FormatHelpers and VaultButton can use it. Theme helpers from SharedWidgets.lua
    (UI_GetMonochromeIconVertex) are resolved lazily at call time, never at load.

    entry = {
        atlases       = { "atlas-a", "atlas-b" },  -- tried in order (first existing wins)
        atlasTexCoord = { l, r, t, b },            -- optional, atlas path only (flip)
        file          = "path" | fileID,           -- fallback texture
        texCoord      = { l, r, t, b },            -- optional, file path only
        mono          = true,                      -- tint white (dark) / black (light)
    }
]]

local _, ns = ...
local Constants = ns.Constants
assert(Constants, "Modules/Constants.lua must load before Modules/UI/IconRegistry.lua")

local C_Texture = C_Texture
local pcall = pcall
local tostring = tostring

local WN_MEDIA = "Interface\\AddOns\\WarbandNexus\\Media\\"

-- Atlas evidence (12.1.5 FrameXML):
--   auctionhouse-ui-sortarrow       Blizzard_ProfessionsTemplates.xml:273; flip per
--                                   Blizzard_ProfessionsTemplates.lua:211-216 (0,1,1,0 = up arrow; 0,1,0,1 = down)
--   common-icon-checkmark           Blizzard_CharacterCreate.lua:2150
--   common-icon-redx                Blizzard_CharacterCreate.lua:2156
--   common-icon-yellowx             Blizzard_SharedXML/HelpTip.lua:358
--   checkmark-minimal               Blizzard_GroupFinder/Mainline/LFGList.xml:437
--   ui-questtracker-objective-nub   Blizzard_ObjectiveTracker/Blizzard_BonusObjectiveTracker.lua:327
--   auctionhouse-icon-favorite(-off) Blizzard_StableUI/Blizzard_StableUI.lua:436
--   coin-gold / coin-silver / coin-copper  Blizzard_MoneyFrame/Shared/MoneyFrame.lua:348-349, MoneyInputFrame.xml
--   auctionhouse-icon-clock         Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUtil.lua:8
--   activities-icon-lock            Blizzard_EncounterJournal/Mainline/Blizzard_MonthlyActivities.xml:314
--   transmog-icon-warning(-small)   Blizzard_Transmog/Blizzard_TransmogTemplates.xml:363 / .lua:533
--   importantavailablequesticon     Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua:136
--   common-search-clearbutton       Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:228
--   common-icon-plus / -minus       Blizzard_HouseList/Blizzard_HouseList.lua:179-181
--   questlog-icon-setting           Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:2235
--   ui-questtrackerbutton-filter    Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerContainer.xml:13
local SORT_UP_TC = { 0, 1, 1, 0 }
local SORT_DOWN_TC = { 0, 1, 0, 1 }

ns.UI_ICONS = {
    sort_up        = { atlases = { "auctionhouse-ui-sortarrow" }, atlasTexCoord = SORT_UP_TC,
                       file = Constants.WN_ICON_CHEVRON_UP or (WN_MEDIA .. "Icon-ChevronUp.tga") },
    sort_down      = { atlases = { "auctionhouse-ui-sortarrow" }, atlasTexCoord = SORT_DOWN_TC,
                       file = Constants.WN_ICON_CHEVRON_DOWN or (WN_MEDIA .. "Icon-ChevronDown.tga") },
    status_ok      = { atlases = { "common-icon-checkmark" }, file = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    status_fail    = { atlases = { "common-icon-redx" }, file = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
    status_warn    = { atlases = { "common-icon-yellowx" }, file = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
    status_pending = { atlases = { "ui-questtracker-objective-nub" }, file = "Interface\\RaidFrame\\ReadyCheck-Waiting", mono = true },
    check_minimal  = { atlases = { "checkmark-minimal" }, file = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    favorite_on    = { atlases = { "auctionhouse-icon-favorite" } },
    favorite_off   = { atlases = { "auctionhouse-icon-favorite-off" } },
    money_gold     = { atlases = { "coin-gold" }, file = "Interface\\MoneyFrame\\UI-GoldIcon" },
    money_silver   = { atlases = { "coin-silver" }, file = "Interface\\MoneyFrame\\UI-SilverIcon" },
    money_copper   = { atlases = { "coin-copper" }, file = "Interface\\MoneyFrame\\UI-CopperIcon" },
    clock          = { atlases = { "auctionhouse-icon-clock" } },
    lock           = { atlases = { "activities-icon-lock" } },
    warning        = { atlases = { "transmog-icon-warning-small", "transmog-icon-warning" } },
    attention      = { atlases = { "importantavailablequesticon", "transmog-icon-warning-small" } },
    close          = { file = Constants.WN_ICON_CLOSE or (WN_MEDIA .. "Icon-Close.tga") },
    clear          = { atlases = { "common-search-clearbutton" }, file = Constants.WN_ICON_CLOSE or (WN_MEDIA .. "Icon-Close.tga") },
    plus           = { atlases = { "common-icon-plus" } },
    minus          = { atlases = { "common-icon-minus" } },
    settings       = { atlases = { "questlog-icon-setting" } },
    filter         = { atlases = { "ui-questtrackerbutton-filter" } },
    -- Monochrome WN stroke chevrons (expand/collapse); atlases cannot be lightened for dark mode.
    chevron_up     = { file = Constants.WN_ICON_CHEVRON_UP or (WN_MEDIA .. "Icon-ChevronUp.tga"), mono = true },
    chevron_down   = { file = Constants.WN_ICON_CHEVRON_DOWN or (WN_MEDIA .. "Icon-ChevronDown.tga"), mono = true },
    -- Mythic Keystone item icon (fileID already used by CharactersUI as its fallback).
    keystone       = { file = 525134, texCoord = { 0.08, 0.92, 0.08, 0.92 } },
}

local ICONS = ns.UI_ICONS
local atlasExists = {}
local markupCache = {}

local function AtlasExists(name)
    local v = atlasExists[name]
    if v == nil then
        v = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            v = (ok and info) and true or false
        end
        atlasExists[name] = v
    end
    return v
end

--- First atlas of `key` that exists in this client, or nil.
function ns.UI_GetIconAtlas(key)
    local entry = ICONS[key]
    local list = entry and entry.atlases
    if not list then return nil end
    for i = 1, #list do
        if AtlasExists(list[i]) then return list[i] end
    end
    return nil
end

local function ApplyIconVertex(tex, entry, opts)
    local vc = opts and opts.vertexColor
    if vc then
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
        return
    end
    local alpha = (opts and opts.alpha) or 1
    if entry.mono then
        local fn = ns.UI_GetMonochromeIconVertex
        if fn then
            local m = fn(alpha)
            tex:SetVertexColor(m[1], m[2], m[3], m[4] or alpha)
            return
        end
    end
    tex:SetVertexColor(1, 1, 1, alpha)
end

--- Apply a semantic icon to a texture: verified atlas first, then the file fallback.
--- opts: useAtlasSize bool, alpha number, vertexColor {r,g,b,a} (overrides mono/neutral tint).
--- Colored semantic atlases keep their own colors (neutral 1,1,1 vertex); mono entries follow the theme.
--- Returns true, "atlas"|"file" on success; false when nothing could be applied.
function ns.UI_SetIcon(tex, key, opts)
    if not tex or not key then return false end
    local entry = ICONS[key]
    if not entry then return false end
    local applied
    local atlas = ns.UI_GetIconAtlas(key)
    if atlas and tex.SetAtlas then
        local useSize = (opts and opts.useAtlasSize) and true or false
        if pcall(tex.SetAtlas, tex, atlas, useSize) then
            local tc = entry.atlasTexCoord or SORT_DOWN_TC
            tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            applied = "atlas"
        end
    end
    if not applied and entry.file then
        tex:SetTexture(entry.file)
        local tc = entry.texCoord or SORT_DOWN_TC
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        applied = "file"
    end
    if not applied then return false end
    tex:SetDesaturated(false)
    ApplyIconVertex(tex, entry, opts)
    return true, applied
end

--- Inline markup for FontStrings/tooltips: |A atlas markup, else |T file markup, else "".
--- Same argument order as CreateAtlasMarkup(atlas, width, height, offsetX, offsetY).
function ns.UI_GetIconMarkup(key, width, height, offsetX, offsetY)
    width = width or 0
    height = height or width
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    local cacheKey = key .. ":" .. width .. ":" .. height .. ":" .. offsetX .. ":" .. offsetY
    local cached = markupCache[cacheKey]
    if cached then return cached end
    local markup = ""
    local atlas = ns.UI_GetIconAtlas(key)
    if atlas and CreateAtlasMarkup then
        markup = CreateAtlasMarkup(atlas, width, height, offsetX, offsetY)
    else
        local entry = ICONS[key]
        if entry and entry.file then
            markup = "|T" .. tostring(entry.file) .. ":" .. height .. ":" .. width .. ":" .. offsetX .. ":" .. offsetY .. "|t"
        end
    end
    markupCache[cacheKey] = markup
    return markup
end
