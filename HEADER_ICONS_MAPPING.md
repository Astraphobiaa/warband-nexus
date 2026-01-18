# Header Icons Mapping

This document lists all tab header icons and their atlas names for easy customization.

## System Overview

All tab headers now use the **centralized icon system** from `SharedWidgets.lua`. Icons are defined in one place and automatically applied to all tabs.

### Centralized Configuration

**Icon mapping:** `TAB_HEADER_ICONS` table in `SharedWidgets.lua`
**Size configuration:** `HEADER_ICON_SIZE`, `HEADER_BORDER_SIZE` constants

```lua
-- From SharedWidgets.lua
local TAB_HEADER_ICONS = {
    characters = "poi-town",
    items = "Banker",
    storage = "VignetteLoot",
    plans = "poi-islands-table",
    currency = "Auctioneer",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    statistics = "racing",
}

local HEADER_ICON_SIZE = 41      -- Icon size
local HEADER_BORDER_SIZE = 51    -- Border size
local HEADER_ICON_XOFFSET = 18   -- X position
local HEADER_ICON_YOFFSET = 0    -- Y position
```

### Usage in UI Files

All UI modules now use the centralized system:

```lua
local GetTabIcon = ns.UI_GetTabIcon
local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("characters"))
```

**Benefits:**
- Change icon for all tabs from one place
- Consistent sizing and positioning
- Easy to maintain and update
- No hardcoded values scattered across files

---

## Current Icon Mapping

| Tab | Atlas Name | Description |
|-----|------------|-------------|
| **Characters** | `poi-town` | Town/settlement icon |
| **Items** | `Banker` | Banker/vault icon |
| **Storage** | `VignetteLoot` | Treasure chest/loot icon |
| **Plans** | `poi-islands-table` | Islands table/planning icon |
| **Currency** | `Auctioneer` | Auctioneer/gold icon |
| **Reputation** | `MajorFactions_MapIcons_Centaur64` | Centaur faction icon |
| **PvE** | `Tormentors-Boss` | Boss/raid icon |
| **Statistics** | `racing` | Racing/achievement icon |

---

## Current Size Configuration

| Property | Value | Description |
|----------|-------|-------------|
| **Icon Size** | 41x41 | Inner icon size |
| **Border Size** | 51x51 | Outer border/frame size |
| **Margin** | 10px | Space between icon and border (5px per side) |
| **Border Atlas** | `search-iconframe-large` | Search UI frame (best coloring support) |
| **X Offset** | 18px | Horizontal position from left |
| **Y Offset** | 0px | Vertical position (centered) |

---

## How to Change Icons

### Method 1: Change All Icons from One Place (Recommended)

Edit `Modules/UI/SharedWidgets.lua` → `TAB_HEADER_ICONS` table:

```lua
local TAB_HEADER_ICONS = {
    characters = "YOUR-NEW-ATLAS",  -- Change this line
    items = "Banker",
    -- ... etc
}
```

Then `/reload` in-game. **All tabs update automatically.**

### Method 2: Change Icon Size Globally

Edit `Modules/UI/SharedWidgets.lua` → Size constants:

```lua
local HEADER_ICON_SIZE = 50       -- Make icons bigger
local HEADER_BORDER_SIZE = 60     -- Make borders bigger
local HEADER_ICON_XOFFSET = 20    -- Move right
```

Then `/reload` in-game. **All tabs update automatically.**

### Method 3: Change Border Style

Edit `CreateHeaderIcon()` function in `SharedWidgets.lua`:

```lua
-- Find this line:
border:SetAtlas("search-iconframe-large", false)

-- Replace with:
border:SetAtlas("YOUR-BORDER-ATLAS", false)
```

---

## Special: Current Character Icon (Global Setting)

The "Current Character" icon is **GLOBAL** and managed from one place for easy customization.

**To change it:**

1. Open `Modules/UI/SharedWidgets.lua`
2. Find `GetCurrentCharacterIcon()` function
3. Change the return value:

```lua
local function GetCurrentCharacterIcon()
    -- Change this line to customize globally:
    return "YOUR-ATLAS-NAME"  -- e.g., "Banker", "shop-icon-housing-characters-up"
end
```

**Current:** `charactercreate-gendericon-female-selected` (female character icon, no border)

This icon appears in all "Current Character" displays across the addon. It does NOT have a border frame.

---

## Special: Character-Specific Icon (Used in Headers)

The **character-specific icon** is used across multiple tab headers and is **GLOBAL** - managed from one place.

### Usage Contexts

This icon appears in:

1. **Characters tab** → "Characters" collapsible header
2. **Storage tab** → "Personal Banks" collapsible header
3. **Reputations tab** → "Character-Based Reputations" collapsible header

### How to Change

**To change it globally:**

1. Open `Modules/UI/SharedWidgets.lua`
2. Find `GetCharacterSpecificIcon()` function
3. Change the return value:

```lua
local function GetCharacterSpecificIcon()
    -- Change this line to customize globally:
    return "YOUR-ATLAS-NAME"  -- e.g., "shop-icon-housing-characters-up"
end
```

**Current:** `honorsystem-icon-prestige-9` (honor prestige badge, character-specific indicator)

**Alternatives:**
- `charactercreate-gendericon-female-selected` (generic character icon)
- `shop-icon-housing-characters-up` (house character icon)
- `charactercreate-icon-customize-body` (body customization icon)
- Any other atlas name you prefer

### API Access

```lua
-- Get character-specific icon atlas name
local icon = ns.UI_GetCharacterSpecificIcon()  -- Returns: "honorsystem-icon-prestige-9"
```

This centralized system ensures all character-related headers use the same icon, maintaining visual consistency across the addon.

---

## Border Testing History

| Border Atlas | Result | Notes |
|--------------|--------|-------|
| `charactercreate-ring-select` | ❌ No color | Golden ring, doesn't support SetVertexColor |
| `ConduitIconFrame-Corners` | ❌ No color | Modern frame, doesn't support SetVertexColor |
| `collections-itemborder-collected` | ✅ Good fit | Fits icon well but no color support |
| `MainPet-Frame` | ❌ No color | Pet frame, doesn't support SetVertexColor |
| `AzeriteIconFrame` (texture) | ✅ Color works | Texture path, supports coloring, but heavy |
| `perks-slot-glow` | ❓ Testing | Glow effect |
| `search-iconframe-large` | ✅ **CURRENT** | Search frame, best attempt at coloring |
| `plunderstorm-actionbar-slot-border-swappable` | ❌ No color | Plunderstorm border, doesn't support SetVertexColor |

**Current:** `search-iconframe-large` - Best compromise between fit and coloring support

**Note:** Most WoW atlas textures do NOT support `SetVertexColor()` for theme coloring. Only texture paths (e.g., `Interface\\...`) reliably support vertex coloring.

---

## Suggested Atlas Names

Here are some WoW atlas suggestions for each tab:

| Tab | Current | Alternatives |
|-----|---------|--------------|
| **Characters** | `poi-town` | `charactercreate-gendericon-female-selected`, `shop-icon-housing-characters-up` |
| **Items** | `Banker` | `bags-icon`, `bagslot` |
| **Storage** | `VignetteLoot` | `warbands-icon`, `poi-treasureislands` |
| **Plans** | `poi-islands-table` | `questlog-icon`, `poi-workorders` |
| **Currency** | `Auctioneer` | `coin-icon`, `banker` (texture: `Interface\\Icons\\INV_Misc_Coin_02`) |
| **Reputation** | `MajorFactions_MapIcons_Centaur64` | `reputation-icon` (texture: `Interface\\Icons\\Achievement_Reputation_01`) |
| **PvE** | `Tormentors-Boss` | `groupfinder-icon-raid`, `questlog-icon` |
| **Statistics** | `racing` | `charactercreate-icon-customize-face`, `poi-workorders` |

---

## Atlas Browser

To find atlas names in-game, use:
```lua
/run AtlasFrameSearch = CreateFrame("Frame", "AtlasSearch") AtlasSearch:SetScript("OnUpdate", function() for k,v in pairs(C_Texture.GetAtlasInfo("shop-icon-housing-characters-up")) do print(k,v) end end)
```

Or install the **"What's My Atlas?"** addon from CurseForge.

---

## Export Functions

**Get tab icon:**
```lua
local icon = ns.UI_GetTabIcon("characters")  -- Returns atlas name
```

**Get size configuration:**
```lua
local iconSize, borderSize, xOffset, yOffset = ns.UI_GetHeaderIconSize()
```

---

## Notes

- **Centralized system:** All icons and sizes are defined in `SharedWidgets.lua`
- **No hardcoding:** UI files fetch icons dynamically using `ns.UI_GetTabIcon()`
- **Easy updates:** Change icon/size once, applies to all tabs
- **Border coloring:** Most atlases don't support `SetVertexColor()` - only texture paths do
- **Current border:** `search-iconframe-large` (best attempt at theme coloring)
- Icon size: 41x41, border: 51x51, margin: 10px (5px/side)
