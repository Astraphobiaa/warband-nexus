--[[
    Warband Nexus - Icon Helpers
    
    Centralized icon system for character, faction, race, class, and header icons.
    
    Provides:
    - Faction icons (Alliance/Horde/Neutral)
    - Race-gender icons (Blizzard atlas system)
    - Class icons (frameless icons)
    - Tab header icons (standardized system)
    - Current character icons (customizable)
    - Character-specific icons (for headers)
    - Currency header icons (expansion-based)
    
    Extracted from SharedWidgets.lua (366 lines)
    Location: Lines 1443-1808
]]

local ADDON_NAME, ns = ...

-- Import dependencies
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local GetPixelScale = ns.GetPixelScale

--============================================================================
-- CHARACTER ICON HELPERS (Faction, Race, Class)
--============================================================================

---Get faction icon texture path
---@param faction string "Alliance", "Horde", or "Neutral"
---@return string Texture path
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

---Get race-gender icon atlas name
---@param raceFile string English race name (e.g., "BloodElf", "Human")
---@param gender number Gender (2=male, 3=female)
---@return string Atlas name
local function GetRaceGenderAtlas(raceFile, gender)
    if not raceFile then
        return "shop-icon-housing-characters-up"
    end
    
    -- Map race file names to atlas names
    local raceMap = {
        ["BloodElf"] = "bloodelf",
        ["DarkIronDwarf"] = "darkirondwarf",
        ["Dracthyr"] = "dracthyrvisage",  -- Dracthyr uses visage form
        ["Draenei"] = "draenei",
        ["Dwarf"] = "dwarf",
        ["Earthen"] = "earthen",
        ["Gnome"] = "gnome",
        ["Goblin"] = "goblin",
        ["HighmountainTauren"] = "highmountain",
        ["Human"] = "human",
        ["KulTiran"] = "kultiran",
        ["LightforgedDraenei"] = "lightforged",
        ["MagharOrc"] = "magharorc",
        ["Mechagnome"] = "mechagnome",
        ["Nightborne"] = "nightborne",
        ["NightElf"] = "nightelf",
        ["Orc"] = "orc",
        ["Pandaren"] = "pandaren",
        ["Tauren"] = "tauren",
        ["Troll"] = "troll",
        ["Scourge"] = "undead",  -- Undead is "Scourge" in API
        ["Worgen"] = "worgen",
        ["ZandalariTroll"] = "zandalari",
        ["VoidElf"] = "voidelf",
        ["Vulpera"] = "vulpera",
    }
    
    local atlasRace = raceMap[raceFile]
    if not atlasRace then
        return "shop-icon-housing-characters-up"  -- Fallback
    end
    
    local genderStr = (gender == 3) and "female" or "male"
    
    return string.format("raceicon128-%s-%s", atlasRace, genderStr)
end

---Get race icon - NOW RETURNS ATLAS (not texture path)
---@param raceFile string English race name (e.g., "BloodElf", "Human")
---@param gender number|nil Gender (2=male, 3=female) - Optional, defaults to male
---@return string Atlas name
local function GetRaceIcon(raceFile, gender)
    -- NEW: Use atlas system with gender support
    return GetRaceGenderAtlas(raceFile, gender or 2)  -- Default to male if not provided
end

---Create faction icon on a frame
---@param parent frame Parent frame
---@param faction string "Alliance", "Horde", "Neutral"
---@param size number Icon size
---@param point string Anchor point
---@param x number X offset
---@param y number Y offset
---@return texture Created texture
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

---Create race icon on a frame (NEW: Auto-uses race-gender atlases)
---@param parent frame Parent frame
---@param raceFile string English race name
---@param gender number|nil Gender (2=male, 3=female) - Optional, defaults to male
---@param size number Icon size
---@param point string Anchor point
---@param x number X offset
---@param y number Y offset
---@return texture Created texture
local function CreateRaceIcon(parent, raceFile, gender, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 28, size or 28)
    icon:SetPoint(point, x, y)
    
    -- Always use atlas system
    local atlasName = GetRaceIcon(raceFile, gender)  -- GetRaceIcon now returns atlas name
    icon:SetAtlas(atlasName, false)  -- false = don't use atlas size (we set it manually)
    
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return icon
end

-- ============================================================================
-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)
-- ============================================================================

-- Centralized icon mapping for all tabs
local TAB_HEADER_ICONS = {
    characters = "poi-town",
    items = "Banker",
    storage = "VignetteLoot",
    plans = "poi-islands-table",
    currency = "Auctioneer",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    statistics = "racing",
    professions = "Vehicle-HammerGold",
}

-- Centralized size configuration
local HEADER_ICON_SIZE = 41      -- Icon size
local HEADER_BORDER_SIZE = 51    -- Border size
local HEADER_ICON_XOFFSET = 18   -- X position
local HEADER_ICON_YOFFSET = 0    -- Y position

---Get tab header icon atlas name
---@param tabName string Tab name (e.g., "characters", "items")
---@return string Atlas name
local function GetTabIcon(tabName)
    return TAB_HEADER_ICONS[tabName] or "shop-icon-housing-characters-up"
end

---Get header icon size configuration
---@return number iconSize Icon size
---@return number borderSize Border size
---@return number xOffset X offset
---@return number yOffset Y offset
local function GetHeaderIconSize()
    return HEADER_ICON_SIZE, HEADER_BORDER_SIZE, HEADER_ICON_XOFFSET, HEADER_ICON_YOFFSET
end

---Create a standardized header icon with character-style ring border
---This creates the same icon+border style used in "Your Characters" and "Current Character"
---Border color adapts to theme accent color
---@param parent frame Parent frame (typically a card/header)
---@param atlasName string Atlas name for the inner icon
---@param size number|nil Icon size (default: from HEADER_ICON_SIZE)
---@param borderSize number|nil Border size (default: from HEADER_BORDER_SIZE)
---@param point string|nil Anchor point (default: "LEFT")
---@param x number|nil X offset (default: from HEADER_ICON_XOFFSET)
---@param y number|nil Y offset (default: from HEADER_ICON_YOFFSET)
---@return table {icon=texture, border=texture} for further manipulation if needed
local function CreateHeaderIcon(parent, atlasName, size, borderSize, point, x, y)
    size = size or HEADER_ICON_SIZE
    borderSize = borderSize or HEADER_BORDER_SIZE
    point = point or "LEFT"
    x = x or HEADER_ICON_XOFFSET
    y = y or HEADER_ICON_YOFFSET
    
    -- Create container frame for border
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 4, size + 4)  -- Slightly larger for border
    container:SetPoint(point, x, y)
    
    -- Apply border with theme color
    if ApplyVisuals then
        ApplyVisuals(container, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Inner icon (inset by pixel scale for border)
    local pixelScale = GetPixelScale and GetPixelScale() or 1.0
    local iconInset = pixelScale * 2
    local icon = container:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetPoint("TOPLEFT", iconInset, -iconInset)
    icon:SetPoint("BOTTOMRIGHT", -iconInset, iconInset)
    icon:SetAtlas(atlasName, false)
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return {
        icon = icon,
        border = container  -- Return container as "border" for positioning compatibility
    }
end

-- ============================================================================
-- CURRENT CHARACTER ICON (Global, easily customizable)
-- ============================================================================

---Get the atlas name for "Current Character" icon
---This is a global setting that applies to all "Current Character" displays
---Change this function to customize the icon globally
---@return string Atlas name for the current character icon
local function GetCurrentCharacterIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all "Current Character" icons
    -- Default: "charactercreate-gendericon-female-selected" (generic character icon)
    -- Alternatives: 
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    --   "Banker" (banker icon)
    return "charactercreate-gendericon-female-selected"
end

-- ============================================================================
-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)
-- ============================================================================

---Get the atlas name for "Character-Specific" contexts
---This icon is used for headers and sections that represent character-specific data
---
---Used in:
---  - Characters tab → "Characters" header
---  - Storage tab → "Personal Banks" header
---  - Reputations tab → "Character-Based Reputations" header
---@return string Atlas name for character-specific icon
local function GetCharacterSpecificIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all character-specific headers
    -- Current: "honorsystem-icon-prestige-9" (honor prestige badge, character-specific indicator)
    -- Alternatives:
    --   "charactercreate-gendericon-female-selected" (generic character)
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    return "honorsystem-icon-prestige-9"
end

---Get currency header icon texture path
---Returns appropriate icon for currency category headers (Legacy, expansions, etc.)
---Note: Blizzard API does not provide icons for headers, so we use manual mapping
---@param headerName string Header name (e.g., "Legacy", "War Within", "Season 3")
---@return string|nil Texture path or nil if no icon
local function GetCurrencyHeaderIcon(headerName)
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Current content
    elseif headerName:find("Season 3") or headerName:find("Season3") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    -- Expansions
    elseif headerName:find("War Within") then
        return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
    elseif headerName:find("Dragonflight") then
        return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
    elseif headerName:find("Shadowlands") then
        return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
    elseif headerName:find("Battle for Azeroth") then
        return "Interface\\Icons\\INV_Sword_39"
    elseif headerName:find("Legion") then
        return "Interface\\Icons\\Spell_Shadow_Twilight"
    elseif headerName:find("Warlords of Draenor") or headerName:find("Draenor") then
        return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
    elseif headerName:find("Mists of Pandaria") or headerName:find("Pandaria") then
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    elseif headerName:find("Cataclysm") then
        return "Interface\\Icons\\Spell_Fire_Flameshock"
    elseif headerName:find("Wrath") or headerName:find("Lich King") then
        return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
    elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
        return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
    elseif headerName:find("PvP") or headerName:find("Player vs") then
        return "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG"
    elseif headerName:find("Dungeon") or headerName:find("Raid") then
        return "Interface\\Icons\\achievement_boss_archaedas"
    elseif headerName:find("Miscellaneous") then
        return "Interface\\Icons\\INV_Misc_Gear_01"
    end
    return nil
end

---Get class icon texture path (clean, frameless icons)
---@param classFile string English class name (e.g., "WARRIOR", "MAGE")
---@return string Texture path
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

---Create class icon on a frame
---@param parent frame Parent frame
---@param classFile string English class name (e.g., "WARRIOR")
---@param size number Icon size
---@param point string Anchor point
---@param x number X offset
---@param y number Y offset
---@return texture Created texture
local function CreateClassIcon(parent, classFile, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetClassIcon(classFile))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Faction icons
ns.UI_GetFactionIcon = GetFactionIcon
ns.UI_CreateFactionIcon = CreateFactionIcon

-- Race icons
ns.UI_GetRaceIcon = GetRaceIcon
ns.UI_GetRaceGenderAtlas = GetRaceGenderAtlas
ns.UI_CreateRaceIcon = CreateRaceIcon

-- Class icons
ns.UI_GetClassIcon = GetClassIcon
ns.UI_CreateClassIcon = CreateClassIcon

-- Header icon system
ns.UI_GetTabIcon = GetTabIcon
ns.UI_GetHeaderIconSize = GetHeaderIconSize
ns.UI_CreateHeaderIcon = CreateHeaderIcon

-- Character icons
ns.UI_GetCurrentCharacterIcon = GetCurrentCharacterIcon
ns.UI_GetCharacterSpecificIcon = GetCharacterSpecificIcon

-- Currency header icons
ns.UI_GetCurrencyHeaderIcon = GetCurrencyHeaderIcon

-- Module loaded - verbose logging removed
