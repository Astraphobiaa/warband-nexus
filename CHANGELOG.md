## v3.4.3 (2026-08-07)

### Updated

- To-Do and Collections achievement browsing is now built one screenful at a time: opening the category tree, scrolling it and expanding or collapsing sections stay smooth instead of freezing the game for a second or two.
- Adding or removing a plan updates just that entry instead of redrawing the whole tab.
- Achievement categories with no matching results are no longer listed.

### Fixed

- Fixed collapsing an achievement category not being remembered: it reopened the next time the list was rebuilt.
- Fixed achievement rows drawing on top of category headers after expanding or collapsing a section, and nested categories being indented twice.
- Fixed the To-Do marker on mounts, pets, toys, illusions and titles only adding: clicking it again now removes the entry from your list.
- Fixed the Collections tab showing the game's "Warband Collections" label instead of its own name.
- Fixed the Gear tab keeping a bag item as a recommendation after you re-equipped it, and paired slots (two rings, trinkets or weapons) sharing a single recommendation row instead of getting one each.
- Fixed the Gear tab's Recommend and Location columns being clipped out of view at some window widths.
- Fixed the Tazavesh mount drop being tracked on Mythic only when it also drops on Heroic, and its attempt counter reading the wrong statistic.
- Fixed the What's New window failing to open on login.
- Fixed a batch of Lua errors caused by load-order problems across Gear, To-Do, collections, character migrations and the try counter.
