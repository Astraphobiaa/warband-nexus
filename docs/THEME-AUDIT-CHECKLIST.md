# Theme Audit Checklist — Warband Nexus

Run after each epic wave and before merge. Use **light mode** for fixes; **dark mode** for regression spot-check only.

## Automated gate (2026-06-13 epic baseline)

```bash
python scripts/theme_audit.py
```

| Signal | Baseline | Target |
|--------|----------|--------|
| `cff_white` | 0 | 0 (allowlisted chat/debug only) |
| `hardcoded_rgb` | ~362 | Theme tokens / COLORS refs; bootstrap fallbacks documented |
| `set_text_color` | ~162 | Role helpers or semantic colors (class, quality, accent) |

Pass: `cff_white == 0` after allowlist. Remaining `set_text_color` / `hardcoded_rgb` must be documented exceptions or `COLORS.*` / `UI_Get*` usage.

## Per-tab manual QA (light)

| Tab | Surfaces | Text / markup | Borders / chrome | Tooltips | Theme toggle |
|-----|----------|---------------|------------------|----------|--------------|
| chars | | | | | |
| currency | | | | | |
| items (+ storage) | | | | | |
| gear | | | | | |
| collections | | | | | |
| plans | | | | | |
| pve | | | | | |
| reputations | | | | | |
| professions | | | | | |
| stats | | | | | |
| settings | | | | | |
| about | | | | | |

## Floating windows

- [ ] Plans Tracker
- [ ] Reminder Set Alert dialog
- [ ] Gold Management popup
- [ ] Character Bank Money Log
- [ ] Profession Info / Recipe Companion
- [ ] Notification / What's New changelog

## Satellite UI

- [ ] Minimap button
- [ ] VaultButton tracker + saved instances tooltip

## Cross-cutting scenarios

1. Nav rail idle + active — icons full color in light
2. One hovered row + one selected row
3. Items bank sub-tab active state
4. Item tooltip — title, stats, bind line readable
5. Plan card expanded — source/vendor/quest lines
6. Settings theme toggle without `/reload`
7. Tracking chip yes/no — no white on light green
8. 1080p @ 150% UI scale — pixel borders crisp

## Dark regression (spot-check)

Same 3 screens as light: nav, one list tab, one tooltip. Must match pre-epic baseline.
