## v3.2.0 (2026-06-23)

### Added

- Characters: mail column shows pending mail per alt; tooltip lists sender, subject, gold, and attachments; shift-click opens Mail Details with full messages and item rows.
- To-Do: Weekly Progress planner lets you choose weekly categories (Spark, world quests, dailies, events, vault assignments) and specific Midnight objectives per character.
- Collections: achievement rows show completion date and which character earned the achievement, including on the Recent tab.
- PvE: Shard of Dundun currency column next to coffer shards in the vault grid.
- Notifications: achievement hierarchy routes criteria, sub-achievements, and meta chains into the right toast lane; Traveler's Log progress uses the progress lane.

### Updated

- Login: currencies, reputations, and bags skip full rescans when saved data is warm; only event-driven deltas refresh.
- To-Do: Collections browse subtabs (Mounts, Pets, Toys, Achievements) are separate from To-Do List and Weekly Progress; Show Planned applies only to browse views.
- Midnight weekly catalog expanded for 12.0.7 objectives (upcoming entries stay labeled until live on your client).
- Profiler: unified trace window with nested timing, tab paint traces, and optional verbose phase splits.
- Item tooltips: Item ID on the bottom line of every item hover (addon cards and GameTooltip).

### Fixed

- Try Counter: Mythic Sylvanas chest tries count after the post-kill cinematic when loot links are secret or missing at chest close.
- Tooltips: nil and secret API returns no longer break item hover cards.
- Notifications: improved stacking, spacing, and deduplication across earned, criteria, and collectible lanes.
- Professions: safer handling when profession spell names are nil or secret.
- Migrations: legacy transmog To-Do plans and stale currency buckets are cleaned on upgrade.

### Removed

- Transmog To-Do plans and the legacy transmog tracking / Clear Start system (other collection tracking is unchanged).
