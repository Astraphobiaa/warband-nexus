# UI Centralization Guide

## ⚠️ IMPORTANT: Current State (TEMPORARY SOLUTION)

### Problem
All UI files currently create **local copies** of SharedWidgets values:
```lua
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 40
```

This means changing `SharedWidgets.lua` **DOES NOT** automatically update all UI files!

### Current Workaround (Manual Update Required)
If you change a value in `SharedWidgets.lua`, you MUST also update the fallback value in **ALL** UI files:

**Files to Update:**
1. `CharactersUI.lua` (lines 36, 42)
2. `ItemsUI.lua` (line 35)
3. `StorageUI.lua` (line 38)
4. `PvEUI.lua` (lines 24, 30)
5. `ReputationUI.lua` (line 39)
6. `CurrencyUI.lua` (line 46)
7. `PlansUI.lua` (lines 24, 30)
8. `StatisticsUI.lua` (lines 21, 27)

**Example:**
```lua
-- SharedWidgets.lua
SECTION_SPACING = 50,  -- Changed from 40 to 50

-- Then update in ALL files above:
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 50  -- Update fallback!
```

---

## ✅ FUTURE SOLUTION (TODO)

### Goal: True Centralization
Remove all local variables and use `UI_LAYOUT` directly everywhere.

**Instead of:**
```lua
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 40
-- Later in code:
yOffset = yOffset + SECTION_SPACING
```

**Use:**
```lua
-- No local variable
yOffset = yOffset + UI_LAYOUT.SECTION_SPACING
```

### Benefits
- ✅ Change once in SharedWidgets, applies everywhere automatically
- ✅ No manual sync required
- ✅ Single source of truth

### Performance Impact
- **Negligible**: Lua table lookups are extremely fast
- **Minor**: One extra table access per usage (microseconds)

---

## 📋 Standardized Values (Current)

### Spacing
| Constant | Value | Usage |
|----------|-------|-------|
| `HEADER_SPACING` | 40px | Section → Expansion header |
| `SECTION_SPACING` | 40px | Expansion → Expansion spacing |
| `ROW_SPACING` | 26px | Row height + gap (26px + 0px) |
| `SUBHEADER_SPACING` | 40px | Sub-header spacing |

### Indentation
| Constant | Value | Usage |
|----------|-------|-------|
| `BASE_INDENT` | 15px | Level 1 indent |
| `SUBROW_EXTRA_INDENT` | 10px | Extra for Level 2 (total: 40px) |

### Margins
| Constant | Value | Usage |
|----------|-------|-------|
| `SIDE_MARGIN` | 10px | Left/right content margin |
| `TOP_MARGIN` | 8px | Top content margin |

### Layout Pattern (All UI Files)
```
[Section Header] (0px indent)
    ↓ 40px (HEADER_SPACING - major separator)
[Expansion/Type Header] (BASE_INDENT = 15px indent)
    ↓ 32px (HEADER_HEIGHT - no extra spacing)
[Row] (BASE_INDENT = 15px indent)
[Row]
    ↓ 8px (SECTION_SPACING - minor separator)
[Next Expansion Header] (BASE_INDENT = 15px indent)
    ↓ 32px
[Row]
```

---

## 🔨 Refactor Checklist (TODO)

- [ ] Remove all local `SECTION_SPACING` variables
- [ ] Remove all local `HEADER_SPACING` variables
- [ ] Remove all local `BASE_INDENT` variables
- [ ] Replace with direct `UI_LAYOUT.*` access
- [ ] Test all UI files for visual consistency
- [ ] Update this README when refactor is complete

---

## 📝 Notes

- **Last Updated:** 2026-01-21
- **Status:** Temporary solution in place, refactor pending
- **Maintainer:** Warband Nexus Team
