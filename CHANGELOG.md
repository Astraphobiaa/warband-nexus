# Warband Nexus — Release notes

Canonical source for CurseForge / Wago uploads (BigWigs packager `manual-changelog`).
Mirror the same bullets in `Locales/*/CHANGELOG_V*` for in-game What's New.

**Release ritual:** prepend a new `## vX.Y.Z (date)` section below; keep older sections for history.

## v3.1.9 (2026-06-15)

### Fixed

- Bags and loot: moving items, vendor buy/sell, and loot pickup no longer cause large FPS drops from re-compressing your entire bag on every change (v3.1.8 regression).
- Items cache: fixed error when the idle save timer ran in the background.
- Notifications: mount and collection toasts no longer crash when an icon table was missing.
- Currency tab: amounts no longer follow only the logged-in character; rows compare tracked characters correctly.
- Performance: dragonriding and other frequent spell casts no longer repeat spell API lookups on every button press (fewer FPS stutters while flying).
- Try Counter: spellcast detection no longer runs when the Try Counter module is disabled.
- Guild Bank: characters without bank tab view permission no longer clear the shared scan when they open the guild bank window (other alts in the same guild keep their cached items).
- Guild Bank: Items > Guild shows account-wide cached scans even when your current character is not in that guild.

### Updated

- Light mode: warmer panel surfaces, clearer row and button contrast, full-color navigation icons, and more readable tooltips (soft shadows).
- Light mode: Vault button, easy-access tracker, and Collections model preview follow the same theme polish.
- Bag cache: inventory stays in fast session memory while playing; uncompressed saves run ~15s after the last bag change (helps if you Alt+F4); full compression only on logout or /reload.
- Reordering slots in a bag no longer triggers a full gear storage rescan when item counts did not change.
- Tooltip item counts and collection scans reuse recent bag data to avoid extra container walks.
- Collections bag scan is skipped when the Collections module is off and runs on the next frame when enabled.
- Map quest reminders skip work when you have no active plans.
- Currency tab: Warband Transferable rows show your character with current / warband total amounts; Character-Specific rows show warband total with the highest-holder badge.
- Currency tooltips: per-character amounts on hover (top 10 by default, hold Shift for more, capped at 50 for large rosters).
- Reputation tab: rows show your character standing vs warband-best on the progress bar; tooltips list per-character progress with the same Shift limits.
