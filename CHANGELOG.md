## v3.3.0 (2026-07-05)

### Added

- PvP tab: rated bracket progress, honor, conquest, and recent match history across your warband.
- Settings: Classic UI style option uses Blizzard default buttons, frames, and scrollbars.

### Updated

- Classic theme: transparent list hosts and Blizzard scroll arrows (no grey slab behind character lists).
- Gear tab: refreshed paperdoll and stash panel chrome, especially in Classic UI.
- PvP overview: warband column layout and bracket column order tuned for readability.
- Mini tracker windows (To-Do, Vault, Saved Instances): layout overhaul with symmetric scroll lanes.
- Professions tab: layout and equipment rows improved for Classic and Modern UI.
- Settings: UI Style (Modern vs Classic) separated from dark/light color mode.
- Guild bank: scan completion reports item count and refreshes WN Search tooltips.
- Gear stash recommendations: more reliable ilvl comparison when items move between bags and slots.

### Fixed

- To-Do tracker: layout and scrollbar no longer overlap plan rows.
- PvE tab: character grid redraws correctly after column or tab changes.
- Guild bank: opening the bank commits a full scan atomically (avoids stale empty snapshots).
- Collections: empty scans retry once collection APIs finish loading.
- Chat integrations: throttled when message volume would overload processing.
- Guild bank scanning: throttled to reduce repeated scan churn during open bank.
- Try Counter: improved Netherwarped Cursed Egg drop detection and tracking.

## v3.2.3 (2026-07-02)

### Added

- About: Patreon Supporters section (thank you, Melissa CD!).

### Updated

- Item tooltips: improved timing for storage count refresh while scanning bags.

### Fixed

- To-Do Illusions browse no longer stuck on "Scanning Illusions" while collection data loads.
- Professions tab refreshes correctly when the profession window opens or updates.
- Professions: fixed duplicate event registration causing extra refreshes.
- Main window: list redraw pool no longer leaves stale rows after fast tab switches.
- Zone reminders: world quest reminder handling improved.
