--[[
    Warband Nexus - Icon Registry
    Semantic icon keys -> the addon's own icon files under Media/ (no Blizzard UI art, so every
    client and port renders the same set). Source + rebuild: scripts/build_ui_icons.py (SVG -> 64 px TGA).

    Every shipped icon is colored art with a dark rim, readable on dark and light panels; it is drawn
    with a neutral vertex. Dim states use alpha, never a color tint (that would muddy the art).
    The mono flag stays supported for white glyphs (tinted by UI_GetMonochromeIconVertex), none ship today.

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

-- Loose TGAs get no mipmaps (TRILINEAR on them crashes the client), so a 64-256 px source drawn at
-- 12-24 px aliases. scripts/build_small_icons.py pre-shrinks every shipped icon into
-- Media/Small16|Small|Small64|Small128; pick the smallest copy that still covers the draw.
-- Upscaling from a copy that is too small reads blurry, downscaling more than 2x shimmers.
local TIER_PX = { 16, 32, 64, 128 }
local TIER_DIR = { [16] = "Small16\\", [32] = "Small\\", [64] = "Small64\\", [128] = "Small128\\" }

--- GetHeight()/markup height are UI units, not pixels: at 1440p a 24-unit icon already draws at ~29
--- physical px and at 4K at ~43, so the tier has to be chosen from the real pixel count.
--- Height 0 (font line height) resolves to the smallest tier.
local function PhysicalPixels(height, region)
    if not height or height <= 0 then return nil end
    local ps = ns.GetPixelScale and ns.GetPixelScale(region)
    if not ps or ps <= 0 then return height end
    return height / ps
end
ns.UI_PhysicalPixels = PhysicalPixels

--- Shipped source size per family. A tier only exists on disk when it is smaller than its source,
--- so picking one blindly would point at a missing file and draw nothing.
local function SourcePixels(file)
    if file:find("ClassCrest-", 1, true) then return 128 end
    if file == WN_MEDIA .. "icon.tga" or file == WN_MEDIA .. "patreon.tga" then
        return file:sub(-8) == "icon.tga" and 256 or 128
    end
    return 64  -- Media\Icon-*.tga, discord.tga
end

local tierCache = {}
--- Returns the file to draw and its pixel size. Non-addon textures pass through untouched.
local function PickIconFile(file, px)
    if type(file) ~= "string" or file:sub(1, #WN_MEDIA) ~= WN_MEDIA then return file, nil end
    if file:find("Small", #WN_MEDIA + 1, true) then return file, nil end  -- already a tier copy
    local src = SourcePixels(file)
    -- nil = caller has no size yet (texture not laid out): keep the source rather than guess small
    -- and upscale. 0 = font line height, which really is the smallest tier.
    if px == nil then return file, src end
    if px <= 0 then px = 0 end
    local want
    for i = 1, #TIER_PX do
        local tier = TIER_PX[i]
        if tier < src and px <= tier then
            want = tier
            break
        end
    end
    if not want then return file, src end
    local key = want .. file
    local out = tierCache[key]
    if not out then
        out = WN_MEDIA .. TIER_DIR[want] .. file:sub(#WN_MEDIA + 1)
        tierCache[key] = out
    end
    return out, want
end
ns.UI_PickIconFile = PickIconFile

--- The addon logo ships at 256 px but the chrome draws it from 16 units (vault header) to 80
--- (empty-state card). Straight off the source it aliases at every button size, so every
--- caller resolves it through a tier. `size` is the draw size in UI units.
local LOGO_FILE = WN_MEDIA .. "icon.tga"
function ns.UI_AddonLogoFile(size, region)
    return (PickIconFile(LOGO_FILE, PhysicalPixels(size, region)))
end

--- Back-compat shims for callers that only ask "is this a small draw?".
local function UseSmallIcon(height, region)
    if height == 0 then return true end
    local px = PhysicalPixels(height, region)
    return px ~= nil and px <= 32
end
ns.UI_UseSmallIcon = UseSmallIcon
local function SmallIconFile(file) return (PickIconFile(file, 32)) end
ns.UI_SmallIconFile = SmallIconFile

local SORT_UP_TC = { 0, 1, 1, 0 }
local SORT_DOWN_TC = { 0, 1, 0, 1 }

ns.UI_ICONS = {
    -- UI glyphs (colored line art, scripts/build_ui_icons.py GLYPH_COLOR)
    sort_up        = { file = Icon("TriangleDown"), texCoord = SORT_UP_TC },
    sort_down      = { file = Icon("TriangleDown") },
    marker_up      = { file = Icon("TriangleDown"), texCoord = SORT_UP_TC },
    arrow_left     = { file = Icon("TriangleLeft") },  -- scroll buttons rotate it
    arrow_right    = { file = Icon("TriangleRight") },
    status_pending = { file = Icon("StatusPending") },
    clock          = { file = Icon("Clock") },
    lock           = { file = Icon("Lock") },
    plus           = { file = Icon("Plus") },
    minus          = { file = Icon("Minus") },
    settings       = { file = Icon("Settings") },
    filter         = { file = Icon("Filter") },
    sound_play     = { file = Icon("Sound") },
    spinner        = { file = Icon("Spinner") },
    reset          = { file = Icon("Reset") },
    upgrade        = { file = Icon("Upgrade") },        -- green art; never tint it
    crafting_order = { file = Icon("CraftingOrder") },
    -- settings category rail
    modules        = { file = Icon("Modules") },
    keyboard       = { file = Icon("Keyboard") },
    notifications  = { file = Icon("BellLine") },
    palette        = { file = Icon("Palette") },
    sliders        = { file = Icon("Sliders") },
    credits        = { file = Icon("Credits") },  -- About tab
    warband        = { file = Icon("Campfire") },  -- colored
    close          = { file = Constants.WN_ICON_CLOSE or Icon("Close") },
    clear          = { file = Constants.WN_ICON_CLOSE or Icon("Close") },
    chevron_up     = { file = Constants.WN_ICON_CHEVRON_UP or Icon("ChevronUp") },
    chevron_down   = { file = Constants.WN_ICON_CHEVRON_DOWN or Icon("ChevronDown") },
    -- tab headers, source categories, storage markers (key = concept; file = WoW-flavoured glyph)
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
    try_counter    = { file = Icon("TryCounter") },  -- colored
    online         = { file = Icon("Online") },  -- colored
    great_vault    = { file = Icon("GreatVault") },  -- colored
    quest_dungeon  = { file = Icon("QuestDungeon") },  -- colored
    quest_raid     = { file = Icon("QuestRaid") },  -- colored
    quest_delve    = { file = Icon("QuestDelve") },  -- colored
    arrow_gold     = { file = Icon("ArrowGold") },  -- colored (points up; down = flipped texCoord)
    resize_grip    = { file = Icon("ResizeGrip") },  -- colored
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
--- Markup strings bake in the 32 px vs 64 px source choice, which depends on the pixel scale.
--- EventManager clears them when UI scale / resolution changes.
function ns.UI_ResetIconMarkupCache()
    for k in pairs(markupCache) do markupCache[k] = nil end
end

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
        local file = entry.file
        local h = tex.GetHeight and tex:GetHeight()
        file = (PickIconFile(file, PhysicalPixels(h, tex)))
        tex:SetTexture(file)
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
            -- full texel range off whichever pre-shrunk copy covers this draw, plus the tint
            -- height 0 = draw at font line height; size it like a default line so the tier still
            -- follows the UI scale instead of defaulting to the smallest copy.
            local drawH = (height and height > 0) and height or 12
            local file, px = PickIconFile(entry.file, PhysicalPixels(drawH))
            px = px or 64
            markup = "|T" .. file .. ":" .. height .. ":" .. width .. ":" .. offsetX .. ":" .. offsetY
                .. ":" .. px .. ":" .. px .. ":0:" .. px .. ":0:" .. px .. ":" .. r .. ":" .. g .. ":" .. b .. "|t"
        else
            markup = "|T" .. tostring(entry.file) .. ":" .. height .. ":" .. width .. ":" .. offsetX .. ":" .. offsetY .. "|t"
        end
    end
    markupCache[cacheKey] = markup
    return markup
end
