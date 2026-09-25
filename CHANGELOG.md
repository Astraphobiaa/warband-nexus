## v3.5.11 (2026-09-25)

Hotfix addressing a PvE cache subtable lookup error during window refresh.

### Fixed

- Resolved a Lua error in PvE cache retrieval when reading weekly Mythic+ run history during UI refresh.
- Improved character subtable lookup safety across weekly reset state checks.
- Prevented window population failures when opening or switching between main interface tabs.
- Ensured consistent fallback behavior when character weekly reset timestamps are queried.
