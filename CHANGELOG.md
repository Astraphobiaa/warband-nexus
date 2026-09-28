## v3.5.14 (2026-09-28)

Fixes for profession weekly treatise tracking on alts and dungeon boss try counter attribution.

### Fixed

- Resolved an issue where using profession treatises or contracts failed to update weekly knowledge on alts.
- Fixed profession knowledge progress skipping characters that had not yet opened their crafting window.
- Added real-time tracking for profession knowledge gains from item consumption, bag updates, and quest log changes.
- Ensured weekly profession knowledge and treatise completions are saved immediately on character logout.
- Fixed an issue where trash mob pulls after killing a dungeon boss incorrectly incremented the boss attempt counter.
- Hardened encounter try counting against secret values and comparison errors in Midnight secure instances.
- Resolved missing Midnight profession column data when alt expansion details were not yet cached.
