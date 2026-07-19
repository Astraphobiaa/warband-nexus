## v3.3.4 (2026-07-19)

### Fixed

- Gear tab: your weapons no longer overlap the Character Stats and Upgrade Currencies panel beneath the paperdoll.
- The Characters tab no longer snaps back to the top when the list refreshes (for example when your gold or currencies change); your scroll position is kept.
- Fixed a Gear tab error that could stop the tab from loading for characters carrying older saved upgrade-track data.
- Collection views for Mounts, Pets, Toys, and Titles now redraw correctly when switching tabs, including the "Show completed" filter.
- Reminders that could silently never fire now trigger reliably, covering daily, weekly, and days-before-reset alerts as well as zone, instance, and world-event triggers.
- Zone, instance, and world-event reminders now update as soon as you change their settings, instead of waiting for a zone change.
- Weekly reset timing is now timezone-correct, so "days before reset" counts down accurately regardless of your game client's region.
- Saving a reminder now shows a confirmation, and clearing all of a reminder's triggers turns it off instead of leaving it enabled with nothing to fire.
