## v3.3.6 (2026-07-22)

### Added

- Added a "Guild (A-Z)" option to Sort By, on both the Characters list and the PvP overview. Characters without a guild are listed last.
- Selecting Turkish as the addon language now shows a note in Settings: if any Turkish letters do not render with your chosen font, try a different one such as Exo or Arial.

### Updated

- To-Do plan tooltips are now compact: they show the plan's name and description instead of listing every achievement criterion (the card already shows the overall progress).
- The floating To-Do List window header now mirrors the main window: a full-width title band with no dark gaps on the sides, and close/collapse/settings buttons in the same size and style as the main window's controls.
- The To-Do collection browser (Mounts, Pets, Toys, Illusions) now uses more columns on wider windows instead of stretching two cards across the whole width.
- The main window now stays aligned at every size: on narrow windows the Characters gold summary keeps the same width as the list below it and scrolls together, and the list keeps a clean margin instead of running under the vertical scrollbar. Characters columns still shrink toward a readable minimum before horizontal scrolling begins, and PvP section headers track the window width.
- The Mail Details window now frames its message list with a border that stays fixed in place while you scroll through your mail.

### Fixed

- Fixed the Great Vault badge showing the wrong count: it could disagree with the Vault Tracker list (badge showing 3 while two characters were listed), change depending on which character you were logged in on, and only catch up after you opened the Great Vault. A character whose vault you already looted now stays looted when you view it from your other characters, instead of going back to "reward waiting" as soon as you switched away. The badge, the tracker window and the tooltips share one up-to-date view, and claiming a vault, finishing a Mythic+ run, raid boss or delve, and the weekly reset each refresh it on their own; the badge hides itself when nothing is ready.
- Fixed a Great Vault left unclaimed for a week or more being treated as empty: rewards earned in an earlier week stay in the chest and are still claimable, but those characters were not counted by the badge and could even be recorded as already claimed, hiding the vault for good.
- Fixed a doubled colon appearing in the Mail Details window's From and Subject labels.
- Fixed Turkish letters showing as missing or blank glyphs in tooltips and the rest of the UI; the Turkish interface now uses a font with full Turkish coverage.
- Fixed To-Do plan tooltips running off the edge of the screen; long descriptions and values now wrap instead of stretching the tooltip wide.
- Fixed truncated text in the Vault Tracker: the Status column was cut off, and the "Ready" label in the Raid, Dungeon and World columns rendered as "Re...". Both now show in full.
- Fixed frame-rate drops while resizing the floating To-Do List window; it now reflows smoothly and only does the heavier layout work once you let go.
- Fixed content in the floating windows (Saved Instances, Great Vault, To-Do List) sitting flush against the window border; it now keeps a small margin.
- Fixed an error ("attempt to perform arithmetic on ... 'inset'") that could appear when opening the Great Vault quick view.
- Fixed a "stack overflow" error on the To-Do tab when achievement cards were expanded.
- Fixed lag and rare "script ran too long" errors on accounts with many untracked characters: the Great Vault badge and tracker now only process the characters you track, and untracked characters no longer collect Great Vault, PvP or mail data in the background.
- Fixed lag spikes when your gold changes rapidly, such as selling a full bag at a vendor or looting coin-heavy chests; gold updates are now batched.
- Fixed remaining cases where the Characters tab could snap back to the top during automatic refreshes, whether scrolling with the mouse wheel or dragging the scrollbar.
