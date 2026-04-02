# Contributing to Warband Nexus

Thank you for your interest in contributing to **Warband Nexus**! We welcome bug reports, feature suggestions, and code contributions from the community.

## How to Contribute

### Reporting Bugs

1. Check existing [Issues](https://github.com/Astraphobiaa/warband-nexus/issues) to avoid duplicates.
2. Open a new issue with a clear title and detailed description.
3. Include steps to reproduce, expected behavior, and actual behavior.
4. If possible, include screenshots or error logs (from `/wn debug`).

### Suggesting Features

1. Open an issue with the **Feature Request** label.
2. Describe the feature, why it would be useful, and any implementation ideas.

### Submitting Code (Pull Requests)

1. **Fork** the repository and create a new branch from `main`.
2. Make your changes in your branch.
3. Test your changes in-game to ensure they work correctly.
4. Submit a **Pull Request** (PR) with a clear description of the changes.

### Code Guidelines

- Follow the existing code style and patterns in the project.
- Use the established factory patterns (`ns.UI.Factory`) for UI components.
- All user-facing strings must use the localization system (`ns.L`).
- Keep performance in mind — avoid unnecessary frame updates and iterations.
- Use the existing event-driven architecture (`WarbandNexus:RegisterMessage` / `SendMessage`).

### Collectible drop sources & try counts (mounts, pets, toys)

`Modules/CollectibleSourceDB.lua` is the source of truth for **which NPCs/objects/containers/zones** drive try counters and tooltips. We cannot scrape Wowhead reliably from all regions; use this workflow when adding or auditing drops:

1. **Baseline NPC lists (mounts):** cross-check a well-known open-source mount DB’s `DB/Mounts/*.lua` — entries often list `npcs = { ... }` or `itemId` / `statisticId` for bosses.
2. **Midnight zone rares:** that project’s `DB/Mounts/Midnight.lua` vs our `legacyZones` + `sources` (`zone_drop`, `raresOnly`) and per-NPC `legacyNpcs` rows — **map IDs** must match in-game `C_Map.GetMapInfo` (see comments in `CollectibleSourceDB.lua`).
3. **Containers / chests:** external `items = { ... }` or `USE` method vs our `legacyContainers` / `sourceType = "container"`.
4. **Do not** add `zone_drop` with `hostileOnly` for a whole zone unless every hostile there should share the same try counter (e.g. Isle of Dorn shard), not faction-specific zone drops (e.g. Nazmir blood trolls).
5. **Same mount, multiple source types is often correct:** e.g. holiday bosses use **`legacyContainers`** (Pumpkin, Heart-Shaped Box) — see comments above `legacyContainers` / `legacyObjects`. Raid mounts may appear on **both** the **boss NPC** (`legacyNpcs`, stats) and the **loot chest object** (`legacyObjects`, actual `GetLootSourceInfo` GUID). Do not delete one “duplicate” without confirming in-game loot flow.
6. **Scripts:** shallow-clone that mount DB repo to `.tmp-addon-db-audit/`, then `python scripts/extract_external_db_npcs.py` and `python scripts/audit_external_npcs_vs_wn.py` for itemId→NPC coverage vs our shared `_`-prefixed drop tables. (Full-file NPC assignment diff needs a richer parser than the alias-based audit.)
7. After edits, `/reload` and use **Settings → debug `debugTryCounterLoot`** while looting to confirm P1/P2 match lines in chat.

### Optional one-time mount attempt import

If a third-party mount collector (AceDB `profile.groups.mounts`) is enabled, WN can merge its stored attempt totals **once** into WN try counts (`legacyMountTrackerSeedComplete`). With **`/wn debug`**: `/wn legacymountpreview`, `/wn legacyseedreset`. See `TryCounterService.lua` (legacy mount tracker import).

### Localization

- Locale files are in the `Locales/` directory.
- If you add new user-facing strings, add them to **all** locale files.
- `enUS.lua` is the base — other locales can fall back to English.

## License & Contribution Agreement

This project is licensed under **All Rights Reserved** (see [LICENSE](LICENSE)).

By submitting a Pull Request, you agree that:

- Your contribution will be licensed under the same terms as the project.
- You grant the project maintainer (Mert Gedikli) full rights to use, modify, and distribute your contribution as part of this project.
- You confirm that your contribution is your own original work, or you have the right to submit it.

## Code of Conduct

- Be respectful and constructive in all interactions.
- Focus on the project and its improvement.
- No harassment, discrimination, or toxic behavior.

## Questions?

If you have any questions about contributing, feel free to open an issue or reach out to the maintainer.

---

Thank you for helping make Warband Nexus better!
