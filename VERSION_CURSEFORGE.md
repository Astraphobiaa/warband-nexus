# CurseForge / Wago — **Warband Nexus v2.5.12** (2026-04-12)

## Summary for project description / changelog field

**v2.5.12** — Notifications **Try counter chat output** dropdown layout fixed (opens downward, reserved space, stable route order). **GameTooltip:SetText** alpha fix in Settings / Gold Management / Plans (Midnight). Try Counter instance-entry **[WN-Drops]** messaging; manual/Rarity handling for owned non-repeatable collectibles. Tooltip/collection/locale polish; shorter **[WN-TC]** probe chat format.

## Full notes

### UI

- Settings → Notifications: try-counter chat route dropdown opens **downward** with extra gap so the list does not cover the checkbox grid; `valueOrder` keeps Loot → Warband Nexus → all tabs.

### Bug fixes

- `GameTooltip:SetText(..., r, g, b, a)` — no invalid wrap argument; Settings / Gold popup / Plans UI.

### Try Counter

- Instance entry: drop list vs short hint aligned with trackable/mount logic.
- `ProcessManualDrop` / Rarity: non-repeatable + already collected → no try inflation.

### Tooltips & collections

- Midnight `issecretvalue` patterns where touched; DB/service alignment.

### Localization

- Key parity with enUS; `CHANGELOG_V2512` What's New.

---

Package: `WarbandNexus-2.5.12.zip` from `python build_addon.py` at repo root.
