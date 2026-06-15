# Warband Nexus — Release notes

Canonical source for CurseForge / Wago uploads (BigWigs packager `manual-changelog`).
Mirror the same bullets in `Locales/*/CHANGELOG_V*` for in-game What's New.

**Release ritual:** prepend a new `## vX.Y.Z (date)` section below; trim older locale keys when shipping.

## v3.1.10 (2026-06-16)

### Updated

- Performance: flight paths and taxi rides no longer cause large FPS drops from addon quest-log work (updates are batched).
- Reminders: zone reminder checks pause while you are flying or on a flight path, then catch up when you land or regain control.
- Character zone tracking skips redundant saves when your zone and subzone did not change.
- Daily quests: background weekly-reset polling runs every 5 minutes instead of every minute.
