--[[
    Warband Nexus - Icon Registry
    Semantic icon keys -> the addon's own icon files under Media/ (no Blizzard UI art, so every
    client and port renders the same set). Source + rebuild: scripts/build_ui_icons.py (SVG -> 64 px TGA).

    Two families:
      mono    = white glyphs tinted at call time (theme vertex via UI_GetMonochromeIconVertex,
                or a caller color such as the accent for scroll arrows).
      colored = flat fills with a dark outline (status, favorite, money); drawn with a neutral vertex.

    Loads early (after Constants.lua, .toc) so load-time markup constants in services,
    FormatHelpers and VaultButton can use it. Theme helpers from SharedWidgets.lua
    (UI_GetMonochromeIconVertex) are resolved lazily at call time, never at load.

    entry = {
        atlases       = { "atlas-a", "atlas-b" },  -- optional legacy path, tried first (none ship today)
        atlasTexCoord = { l, r, t, b },            -- optional, atlas path only (flip)
        file          = "path" | fileID,           -- texture
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
local function Icon(name) return WN_MEDIA .. "Icon-" .. name .. ".tga" end

local SORT_UP_TC = { 0, 1, 1, 0 }
local SORT_DOWN_TC = { 0, 1, 0, 1 }

ns.UI_ICONS = {
    -- mono
    sort_up        = { file = Icon("TriangleDown"), texCoord = SORT_UP_TC, mono = true },
    sort_down      = { file = Icon("TriangleDown"), mono = true },
    marker_up      = { file = Icon("TriangleDown"), texCoord = SORT_UP_TC, mono = true },
    arrow_left     = { file = Icon("TriangleLeft"), mono = true },  -- scroll buttons rotate it
    arrow_right    = { file = Icon("TriangleRight"), mono = true },
    status_pending = { file = Icon("StatusPending"), mono = true },
    clock          = { file = Icon("Clock"), mono = true },
    lock           = { file = Icon("Lock"), mono = true },
    plus           = { file = Icon("Plus"), mono = true },
    minus          = { file = Icon("Minus"), mono = true },
    settings       = { file = Icon("Settings"), mono = true },
    filter         = { file = Icon("Filter"), mono = true },
    sound_play     = { file = Icon("Sound"), mono = true },
    spinner        = { file = Icon("Spinner"), mono = true },
    reset          = { file = Icon("Reset"), mono = true },
    upgrade        = { file = Icon("Upgrade"), mono = true },        -- callers tint it green
    crafting_order = { file = Icon("CraftingOrder"), mono = true },
    warband        = { file = Icon("Campfire") },  -- colored
    close          = { file = Constants.WN_ICON_CLOSE or Icon("Close"), mono = true },
    clear          = { file = Constants.WN_ICON_CLOSE or Icon("Close"), mono = true },
    chevron_up     = { file = Constants.WN_ICON_CHEVRON_UP or Icon("ChevronUp"), mono = true },
    chevron_down   = { file = Constants.WN_ICON_CHEVRON_DOWN or Icon("ChevronDown"), mono = true },
    -- mono: tab headers, source categories, storage markers (key = concept; file = WoW-flavoured glyph)
    character      = { file = Icon("FactionPortraits") },  -- colored
    faction_alliance = { file = Icon("FactionAlliance") },  -- colored
    faction_horde  = { file = Icon("FactionHorde") },  -- colored
    bag            = { file = Icon("WowBag34") },  -- colored
    crate          = { file = Icon("WowBox") },  -- colored
    checklist      = { file = Icon("Checklist") },  -- colored
    token          = { file = Icon("Currency") },  -- colored
    medal          = { file = Icon("Handshake") },  -- colored
    dungeon        = { file = Icon("BossSkull") },  -- colored
    pvp            = { file = Icon("CrossedSwords") },  -- colored
    bar_chart      = { file = Icon("BarChart") },  -- colored
    book           = { file = Icon("HorseHead") },  -- colored
    anvil          = { file = Icon("AnvilHammer") },  -- colored
    cuirass        = { file = Icon("PlateArmor") },  -- colored
    info           = { file = Icon("Info") },  -- colored
    wand           = { file = Icon("GearGold") },  -- colored
    vault          = { file = Icon("MoneySacks") },  -- colored
    guild          = { file = Icon("Tabard") },  -- colored
    chest          = { file = Icon("WowLootChest") },  -- colored
    scroll         = { file = Icon("RolledScroll") },  -- colored
    stall          = { file = Icon("DrawstringSack") },  -- colored
    paw            = { file = Icon("Paw") },  -- colored
    trophy         = { file = Icon("Trophy") },  -- colored
    calendar       = { file = Icon("Calendar") },  -- colored
    gift           = { file = Icon("Present") },  -- colored
    cards          = { file = Icon("TarotCards") },  -- colored
    shop_bag       = { file = Icon("Cart") },  -- colored
    compass        = { file = Icon("Spyglass") },  -- colored
    tag            = { file = Icon("Tent") },  -- colored
    question       = { file = Icon("RedQuestion") },  -- colored
    sparkle        = { file = Icon("Sparkle") },  -- colored
    pin            = { file = Icon("GoldPin") },  -- colored
    illusion       = { file = Icon("Illusion") },  -- colored
    title          = { file = Icon("TitleCrown") },  -- colored
    knowledge      = { file = Icon("Knowledge") },  -- colored
    quest_weekly   = { file = Icon("QuestWeekly") },  -- colored
    quest_daily    = { file = Icon("QuestDaily") },  -- colored
    quest_important = { file = Icon("QuestImportant") },  -- colored
    first_craft    = { file = Icon("FirstCraft") },  -- colored
    mail           = { file = Icon("Mail") },  -- colored
    link           = { file = Icon("ChatLink") },  -- colored
    reminder       = { file = Icon("Bell") },  -- colored
    search         = { file = Icon("Search") },  -- colored
    wowhead        = { file = Icon("Wowhead") },  -- colored
    gathering      = { file = Icon("Gathering") },  -- colored
    -- colored
    status_ok      = { file = Icon("StatusOk") },
    status_fail    = { file = Icon("StatusFail") },
    status_warn    = { file = Icon("StatusWarn") },
    check_minimal  = { file = Icon("CheckMinimal") },
    favorite_on    = { file = Icon("FavoriteOn") },
    favorite_off   = { file = Icon("FavoriteOff") },
    money_gold     = { file = Icon("CoinGold") },
    money_silver   = { file = Icon("CoinSilver") },
    money_copper   = { file = Icon("CoinCopper") },
    warning        = { file = Icon("Warning") },
    attention      = { file = Icon("Attention") },
    -- Mythic Keystone item icon (game item art, not UI chrome; fileID already used by CharactersUI).
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

--- Texture file of `key` (path or fileID), or nil. For APIs that take a file, e.g. Button:SetNormalTexture.
function ns.UI_GetIconFile(key)
    local entry = ICONS[key]
    return entry and entry.file or nil
end

--- True when `texture` is one of the addon's own Media files (drawn edge to edge: no icon-border crop).
function ns.UI_IsAddonMediaTexture(texture)
    return type(texture) == "string" and texture:find("\\WarbandNexus\\Media\\", 1, true) ~= nil
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
        -- trilinear: these 64 px files are mostly drawn at 12-20 px
        tex:SetTexture(entry.file, nil, nil, "TRILINEAR")
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
--- Same argument order as CreateAtlasMarkup(atlas, width, height, offsetX, offsetY), plus an optional
--- tint {r, g, b} (0-1). Mono keys default to the theme glyph color so they stay visible on light panels.
--- |T full form (path:h:w:ox:oy:texW:texH:l:r:t:b:R:G:B) per warcraft.wiki.gg UI_escape_sequences, 2026-11-03.
function ns.UI_GetIconMarkup(key, width, height, offsetX, offsetY, tint)
    width = width or 0
    height = height or width
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    local entry = ICONS[key]
    if not tint and entry and entry.mono and ns.UI_GetMonochromeIconVertex then
        tint = ns.UI_GetMonochromeIconVertex(1)
    end
    local r, g, b = 255, 255, 255
    if tint then
        r, g, b = math.floor((tint[1] or 1) * 255 + 0.5), math.floor((tint[2] or 1) * 255 + 0.5), math.floor((tint[3] or 1) * 255 + 0.5)
    end
    local cacheKey = key .. ":" .. width .. ":" .. height .. ":" .. offsetX .. ":" .. offsetY .. ":" .. r .. ":" .. g .. ":" .. b
    local cached = markupCache[cacheKey]
    if cached then return cached end
    local markup = ""
    local atlas = ns.UI_GetIconAtlas(key)
    if atlas and CreateAtlasMarkup then
        markup = CreateAtlasMarkup(atlas, width, height, offsetX, offsetY)
    elseif entry and entry.file then
        if ns.UI_IsAddonMediaTexture(entry.file) and not entry.texCoord then
            -- our icons are 64x64: full texel range, plus the tint
            markup = "|T" .. entry.file .. ":" .. height .. ":" .. width .. ":" .. offsetX .. ":" .. offsetY
                .. ":64:64:0:64:0:64:" .. r .. ":" .. g .. ":" .. b .. "|t"
        else
            markup = "|T" .. tostring(entry.file) .. ":" .. height .. ":" .. width .. ":" .. offsetX .. ":" .. offsetY .. "|t"
        end
    end
    markupCache[cacheKey] = markup
    return markup
end
