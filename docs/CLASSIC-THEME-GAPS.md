# Classic Theme — Known Gaps & Fix Log

Tracking parity work for `profile.themeMode == "classic"` (Blizzard chrome, transparent container hosts).

## Phase 9 — Container fill + stock scrollbar (2026-07-02)

**Symptom:** Characters tab showed a grey viewport slab behind list/title/gold cards; main scroll column showed a flat grey thumb with no up/down arrow buttons.

**Root causes**

1. `UI_ConfigureMainScrollViewportForTab` cleared classic viewport fill, then `PopulateContent` called `UI_EnsureScrollChildViewportFill` and re-painted the entire `scrollChild`.
2. `UI_RefreshColors` unconditionally re-applied scrollChild viewport fill and annex chrome.
3. `ApplyStandardCardElevatedChrome` / `ApplyStandardTitleCardChrome` / `UI_CreateCard` still painted elevated card surfaces in classic.
4. `PositionScrollBarInContainer` looked for WN custom `ScrollUpBtn` / `ScrollDownBtn` only; Blizzard template exposes `ScrollUpButton` / `ScrollDownButton`, so layout fell back to bar-only full height.

**Fixes**

| Area | Change |
|------|--------|
| `UI_EnsureScrollChildViewportFill` | Classic / Blizzard chrome: hide fill, skip create |
| `PopulateContent` (`UI.lua`) | Skip viewport fill, annex layout, and `_wnScrollBottomFill` in classic |
| `UI_RefreshColors` | Skip viewport fill + annex refresh in classic; hide existing fills |
| Card chrome helpers | Classic: `UI_ApplyClassicTransparentInterior` (borderless transparent hosts) |
| `PositionScrollBarInContainer` | Resolve `ScrollUpBtn` **or** `ScrollUpButton`; Button \| Bar \| Button layout; hide leaked custom track/borders in classic |
| `CreateScrollFrame` classic branch | Show/size Blizzard up/down buttons; tag `_wnBlizzardChrome` on bar |
| `UI_RefreshMainShellChrome` | Hide scrollChild fill bands on theme refresh; re-sync scrollbar columns |

**QA (Characters tab, classic mode)**

- [ ] No grey slab behind title row, gold summary cards, or character list
- [ ] Scrollbar column shows Blizzard up/down arrow buttons + track (not flat accent thumb only)
- [ ] Theme toggle dark/light/classic without `/reload` — container stays transparent; scrollbar layout intact

## Prior phases

See git history and `docs/THEME-TOKENS.md` for surface ladder and chrome policy in dark/light modes.
